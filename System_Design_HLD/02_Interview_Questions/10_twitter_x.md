# Design Twitter / X

## Problem Statement

"Design Twitter (or X). Users can post short text messages (tweets), follow
other users, and see a timeline of tweets from people they follow. Support
retweets, likes, hashtags, and search. Assume hundreds of millions of users
and a highly asymmetric social graph — some accounts have hundreds of
millions of followers."

## Step 1: Clarify Requirements

### Functional Requirements

- Users can post a tweet (short text, optional media, optional hashtags).
- Users can follow/unfollow other users — this is a **directed, asymmetric**
  relationship (A follows B does not imply B follows A), unlike a mutual
  "friend" graph.
- Users can view a reverse-chronological (or ranked) home timeline of tweets
  from accounts they follow.
- Users can like and retweet a tweet.
- Users can search tweets by keyword and by hashtag.
- The system surfaces trending topics/hashtags.

### Non-Functional Requirements

- **Read-heavy, and extremely so**: timeline reads vastly outnumber tweet
  writes — this ratio is the single most important fact shaping the whole
  design (see Step 2).
- **Low read latency for timeline load**: opening the app and seeing a
  populated timeline should feel instant (low hundreds of milliseconds).
- **Write availability matters more than write latency**: posting a tweet
  should never fail even under load — it's acceptable if the tweet takes a
  little while to propagate into everyone's timeline (eventual consistency
  on fan-out), but the write itself (the tweet existing, durably) must
  succeed reliably.
- **Extreme fan-out skew**: the follower-count distribution is a power law
  — most accounts have a handful of followers, a small number have tens or
  hundreds of millions. Any design that treats "post a tweet" as "write to
  every follower's timeline synchronously" breaks catastrophically for the
  latter group — this is the defining hard problem of this system (Step
  6.1).
- **Near-real-time search and trending**, not necessarily millisecond-fresh
  — a short indexing/aggregation lag is acceptable.
- **Eventual consistency is acceptable** for timeline propagation and like
  counts; strong consistency is not required for "did my follower's timeline
  update yet."

## Step 2: Back-of-Envelope Estimation

**Assumptions:**

- 300 million daily active users (DAU).
- 500 million tweets posted per day, system-wide.
- Each DAU checks their timeline an average of 10 times/day.
- Read:write ratio, derived from the above, is roughly 1000:1 — this single
  number is what drives most of the architectural choices below.
- Average follower count per account, weighted by tweets actually posted, is
  ~700 (this "effective average" already accounts for the fact that most
  tweets come from ordinary accounts, not celebrities — celebrities are
  handled as a separate case in Step 6.1, not folded into this average).
- Peak traffic runs ~3x average.

**Write QPS (tweets)**

```
Average write QPS = 500,000,000 / 86,400 ≈ 5,787 tweets/sec
Peak write QPS ≈ 5,787 x 3 ≈ 17,360 tweets/sec
```

**Read QPS (timeline loads)**

```
Timeline reads/day = 300,000,000 DAU x 10 checks/day = 3,000,000,000 reads/day
Average read QPS = 3,000,000,000 / 86,400 ≈ 34,722 reads/sec
Peak read QPS ≈ 34,722 x 3 ≈ 104,000 reads/sec

Read:write ratio ≈ 34,722 : 5,787 ≈ 6:1 on raw request counts —
but each timeline read typically returns ~20 tweets pulled from potentially
hundreds of followed accounts, so the actual *fan-out read* work (if done
naively, per Step 6.1) is far higher than this ratio suggests, which is
exactly why precomputed timelines exist.
```

**Storage**

```
Average tweet: ~280 bytes of text + metadata (tweet_id, author_id, timestamp,
reply/retweet pointers, counters) ≈ 1 KB stored per tweet including indexing
overhead.

Daily storage = 500,000,000 x 1 KB = 500 GB/day
Yearly storage (raw) = 500 GB x 365 ≈ 182.5 TB/year
With 3x replication ≈ 547.5 TB/year

(Media attachments — images/video — are stored separately in object storage
and dwarf this figure; out of scope for the tweet-storage calculation itself,
same pattern as ../01_Concepts/12_storage_systems.md.)
```

**Fan-out write amplification (the number that motivates Step 6.1)**

```
Naive fan-out-on-write: every tweet is written into every follower's
precomputed timeline at post time.

Average case: 5,787 tweets/sec x 700 followers/tweet ≈ 4,050,900
timeline-row writes/sec — already a lot, but roughly steady and shardable.

Celebrity case: ONE tweet from a 100-million-follower account requires
100,000,000 timeline-row writes if done the same way — at even a generous
50,000 writes/sec per fan-out worker, that's 2,000 seconds (33+ minutes) to
finish fanning out a single tweet. This is the concrete number that makes
pure fan-out-on-write untenable and motivates the hybrid approach in 6.1.
```

## Step 3: High-Level Design

```text
                         ┌───────────────┐
                         │    Client      │
                         └───────┬───────┘
                                 │
                        ┌────────▼─────────┐
                        │   API Gateway /    │
                        │   Load Balancer    │
                        └───┬───────────┬────┘
                            │           │
                 write path │           │ read path
                            ▼           ▼
                ┌────────────────┐  ┌──────────────────┐
                │  Tweet Service   │  │ Timeline Service  │
                │ (assign ID, write│  │ (assemble/serve   │
                │  tweet, publish) │  │  home timeline)   │
                └───┬──────────┬──┘  └───┬───────────┬───┘
                    │          │         │           │
         ┌──────────▼──┐   ┌───▼─────────▼──┐   ┌────▼──────────┐
         │ Tweet Store   │   │  Fan-out Service │   │ Precomputed     │
         │ (tweet_id ->  │   │ (async worker,   │   │ Timeline Cache  │
         │  tweet data)  │   │  reads follower   │   │ (Redis, per-user│
         └──────────────┘   │  graph, pushes to │   │  sorted list of │
                             │  follower timelines)│  │  tweet_ids)    │
                             └───┬──────────────┘   └────────────────┘
                                 │
                        ┌────────▼─────────┐
                        │ Social Graph Store │
                        │ (user -> followers)│
                        └───────────────────┘

  parallel paths off the Tweet Service:
                    ┌───────────────────────┐
   tweet published → │ Message Queue / Stream  │ → Search Indexer → Inverted Index
                    │ (firehose of tweets)    │ → Trending Aggregator → Trending Store
                    └───────────────────────┘
```

**Write flow**: client posts a tweet -> Tweet Service assigns a time-sortable
ID (Step 6.2), persists it to the Tweet Store, and publishes it onto a
firehose stream. Three things consume that stream independently and
asynchronously: the Fan-out Service (pushes the tweet into followers'
precomputed timelines, for non-celebrity accounts), the Search Indexer
(adds it to the inverted index), and the Trending Aggregator (counts
hashtag/term frequency in a sliding window).

**Read flow**: client requests their home timeline -> Timeline Service reads
the precomputed, pre-merged list of recent tweet IDs from the per-user cache,
merges in any celebrity accounts' tweets on the fly (Step 6.1), and hydrates
tweet content from the Tweet Store (or a tweet-content cache).

## Step 4: API Design

**1. Post a tweet**

```
POST /v1/tweets
Request:  { "author_id": "u123", "text": "shipping a new feature today #buildinpublic", "media_ids": [] }
Response: { "tweet_id": "1745829301923840001", "created_at": "2026-09-13T10:15:00Z" }
```
`tweet_id` is a Snowflake-style, time-sortable 64-bit ID — see
`01_distributed_id_generator.md` and Step 6.2.

**2. Get home timeline**

```
GET /v1/timeline/home?user_id=u456&limit=20&before_id=1745829301923840001
Response: {
  "tweets": [
    { "tweet_id": "...", "author_id": "...", "text": "...", "like_count": 214, "retweet_count": 12, "created_at": "..." },
    ...
  ],
  "has_more": true
}
```

**3. Follow a user**

```
POST /v1/follow
Request:  { "follower_id": "u456", "followee_id": "u123" }
Response: { "status": "OK" }
```
This is a write to the Social Graph Store and, notably, does **not** trigger
any timeline backfill by itself in most real designs — a newly-followed
account's *past* tweets typically aren't retroactively fanned out; the user
sees new tweets going forward (a deliberate, documented trade-off).

**4. Like / retweet**

```
POST /v1/tweets/{tweet_id}/like
Request:  { "user_id": "u456" }
Response: { "status": "OK", "like_count": 215 }

POST /v1/tweets/{tweet_id}/retweet
Request:  { "user_id": "u456" }
Response: { "status": "OK", "retweet_id": "1745829999812340002" }
```

**5. Search tweets**

```
GET /v1/search?q=%23buildinpublic&limit=20
Response: { "tweets": [ { "tweet_id": "...", "text": "...", "relevance_score": 8.4 }, ... ] }
```

**6. Trending topics**

```
GET /v1/trending?region=US&limit=10
Response: { "trends": [ { "tag": "#buildinpublic", "tweet_count_last_hour": 48210 }, ... ] }
```

## Step 5: Data Model

**1. Tweets — wide-column / partitioned NoSQL store, partitioned by `author_id` or `tweet_id` range**

```
Table: tweets
Key: tweet_id (time-sortable, Step 6.2)
Fields: author_id, text, media_ids, created_at, like_count, retweet_count, reply_to_id (nullable)
```
Chosen for the same reason as the chat message store in
`09_chat_application.md`: extremely high write volume (Step 2), simple
key-based access pattern (fetch by ID, or scan an author's recent tweets),
and a need to scale writes horizontally without manual resharding.

**2. Social graph — graph-shaped store or a purpose-built adjacency table**

```
Table: follows
Partition key: follower_id      Clustering key: followee_id, followed_at
(and a second table keyed the other way — followee_id -> follower_id list —
 since both "who do I follow" and "who follows me" are common queries and
 a single adjacency direction can't answer both efficiently)
```
This is conceptually a graph, but at Twitter's scale it is typically
implemented as two denormalized adjacency-list tables (one per query
direction) in a wide-column or key-value store rather than a dedicated graph
database, because the actual query patterns needed ("list of IDs I follow,"
"list of IDs that follow me," "does A follow B") are simple lookups, not the
multi-hop graph traversals a graph database is built for.

**3. Precomputed home timelines — in-memory store (Redis), per user**

```
Key: timeline:{user_id}   Value: sorted set of tweet_ids, scored by tweet_id
                                  (which is itself time-sortable, Step 6.2)
```
This is the read-path optimization that makes timeline loads fast — see
Step 6.1. Bounded in size (e.g., only the most recent ~800 tweet IDs are
kept per user) so memory cost stays constant per user regardless of how long
they've had an account.

**4. Likes / retweets — lightweight counters and relation rows**

```
Table: likes (tweet_id, user_id, created_at)   -- existence = "liked"
Counter: like_count:{tweet_id}  (approximate, incremented via a counting
                                  service rather than a synchronous DB update
                                  on every like — same rationale as view-count
                                  batching in 11_video_streaming.md)
```

**5. Search index and trending data**

An inverted index (tweet text/hashtags -> tweet IDs), built and queried the
way `../01_Concepts/13_search_and_indexing.md` describes, plus a separate
time-windowed counting store for trending topics (Step 6.3) — both are
derived, asynchronously updated copies of the tweet data, not the source of
truth.

## Step 6: Deep Dive

### 6.1 Timeline Generation and the Celebrity Problem

Timeline generation for Twitter is the canonical, most-cited real-world
example of the general fan-out problem already worked through in depth in
`08_news_feed.md` — that file covers **fan-out-on-write** (push a new post
into every follower's precomputed timeline immediately), **fan-out-on-read**
(assemble a timeline on demand at read time by querying everyone the user
follows), and the **hybrid** approach that combines both. This section
applies that framework specifically to Twitter's follow graph rather than
re-deriving it, because Twitter is where the asymmetry that makes the hybrid
approach necessary is most extreme.

The reason pure fan-out-on-write breaks here is the power-law follower
distribution quantified in Step 2: a regular account with 700 followers
fanning out on write is cheap (700 timeline-row writes, done asynchronously
in well under a second). An account with 100 million followers fanning out
the same way means 100 million timeline-row writes for a single tweet — at
any realistic worker throughput this takes many minutes, uses enormous fan-
out infrastructure capacity for one post, and, worse, if that celebrity posts
several times in quick succession, fan-out work queues up and falls further
and further behind, meaning followers see stale timelines exactly when the
account is most active.

Pure fan-out-on-read (never precompute, always assemble at read time by
merging tweets from everyone a user follows) avoids that write explosion but
creates the opposite problem: an ordinary user's timeline load now requires
fetching recent tweets from every one of the (potentially hundreds of)
accounts they follow and merging them on the fly, on every single timeline
load — and timeline loads happen at ~35,000 QPS average (Step 2), far more
often than tweets are posted. This makes the *common* case (a normal user
opening their timeline) expensive instead of the *rare* case (a celebrity
posting).

The standard hybrid answer, applied concretely here:

- For accounts under a follower threshold (the vast majority of accounts),
  use fan-out-on-write: their tweets are pushed into followers'
  precomputed timeline caches asynchronously via the Fan-out Service. This
  keeps normal timeline reads a single cache lookup (Step 5's Redis sorted
  set), which is what keeps the dominant read path fast.
- For accounts over the threshold (celebrities), **skip fan-out entirely at
  write time**. Their tweets are simply written to the Tweet Store and left
  there.
- At read time, the Timeline Service merges two sources for every user: the
  precomputed timeline (from fan-out-on-write accounts) plus a live,
  on-demand fetch of recent tweets from the small number of celebrity
  accounts that user follows (there are few enough celebrities, and few
  enough celebrities any one user follows, that this live fetch-and-merge is
  cheap — merging in a handful of extra sources per timeline load, not
  hundreds).

This converts an unbounded, spiky write cost (proportional to follower
count, which is unbounded) into a small, bounded extra read cost
(proportional to the number of celebrities a given user follows, which stays
small even for a user who follows many celebrities) — the core trade-off
that makes the hybrid model work, and specifically why it's the answer
interviewers are listening for on this question.

### 6.2 Tweet Storage and ID Generation

Every tweet needs a globally unique identifier, and the natural choice is a
**time-sortable ID** rather than a random UUID or a simple auto-increment —
the full ID generation problem (why a single auto-increment doesn't scale
across shards, why random UUIDs destroy sort order and index locality, and
the Snowflake-style bit layout of timestamp + machine ID + sequence number)
is covered in full in `01_distributed_id_generator.md`; this section only
notes why it matters specifically here.

Twitter's dominant access pattern is chronological: a timeline is "recent
tweets first," a user's profile is "their recent tweets first," search
results are often sorted or filtered by recency. A time-sortable ID means
`ORDER BY tweet_id DESC` *is* chronological order without needing a separate
timestamp index or column scan, and it means the precomputed timeline sorted
sets in Step 5 can score entries directly by `tweet_id` — sorting by ID and
sorting by time are the same operation, which simplifies both the read path
and the fan-out write path. This is also why the API design in Step 4 uses
`before_id` (not `before_timestamp`) for pagination — it's a cheaper,
unambiguous cursor precisely because the ID already encodes time order.

### 6.3 Search, Hashtags, and Trending Topics

**Search and hashtags** use the same inverted-index approach covered fully
in `../01_Concepts/13_search_and_indexing.md`: tweet text is tokenized,
hashtags are treated as first-class searchable terms, and each term maps to
a postings list of tweet IDs. Tweets flow into the search indexer
asynchronously off the firehose stream (Step 3), which means — as with any
search system — there's a small near-real-time indexing lag between "tweet
posted" and "tweet shows up in search results"; this is an acceptable,
explicitly stated trade-off, not a bug.

**Trending topics** are a genuinely different problem from search: instead
of "find tweets matching a query," it's "continuously compute which
terms/hashtags are spiking in frequency over a recent sliding window (e.g.,
the last hour), across a constant high-volume stream of ~5,800 tweets/sec
average." Answering this with a naive per-request database query — e.g.,
`SELECT hashtag, COUNT(*) FROM tweets WHERE created_at > NOW() - INTERVAL 1
HOUR GROUP BY hashtag ORDER BY COUNT(*) DESC` — does not scale: it would
mean scanning a huge, constantly growing volume of recent rows on every
request that wants trending data, redone from scratch each time.

The right approach is **stream processing**: as tweets flow through the
firehose (the same message queue/stream used to feed fan-out and search,
Step 3), a stream-processing job maintains a running, windowed count per
term — incrementing counters as tweets arrive and expiring counts that age
out of the window, continuously, rather than recomputing from raw data on
demand. This is the general pattern covered in
`../01_Concepts/10_message_queues_and_streaming.md` (stream processing over
an event firehose) applied to a concrete counting problem. The trending
endpoint (Step 4) then just reads the current top-N from this continuously
maintained counter store — an O(1)-ish read against precomputed state,
exactly the same "precompute instead of recomputing per request" principle
used for typeahead ranking in `../01_Concepts/13_search_and_indexing.md` and
for timelines in 6.1 above.

### 6.4 Retweets and Likes as Lightweight Relations, Not Copies

A naive implementation of "retweet" might duplicate the entire original
tweet's content into a new row under the retweeting user's account. This is
wasteful and creates a data-integrity problem: if the original tweet is
edited (if the product supports that) or deleted, every duplicated copy
would need to be found and updated or removed too.

Instead, a retweet is stored as a small relation — essentially a pointer:
`(retweet_id, original_tweet_id, retweeting_user_id, created_at)` — with no
duplication of the original tweet's text or media. Rendering a retweet in a
timeline means resolving that pointer and fetching the original tweet's
content (from the Tweet Store or its cache) at read time, the same way a
foreign key is resolved. This keeps storage proportional to the number of
*distinct* tweets, not the number of times they're retweeted, and it means a
deletion of the original tweet has one clear place to take effect.

Likes follow the identical pattern: a `likes` relation row (Step 5) records
*that* a user liked a tweet, not a copy of the tweet. The visible like count
on a tweet is not computed by counting rows in that table synchronously on
every read (which would mean an aggregation query on every single tweet
render) — it's maintained as an approximate, asynchronously-updated counter,
for the same write-hotspot reason view counts are batched in
`11_video_streaming.md`: a viral tweet can receive thousands of likes per
second, and synchronously incrementing one shared counter row for every
single like would serialize all of that traffic through one hot row.

## Step 7: Bottlenecks & Trade-offs

- **The celebrity read-merge path is the long-term bottleneck**, not the
  regular fan-out path. As the number of very-large accounts grows, or as
  any single user follows more of them, the "merge a few extra live sources
  at read time" cost in 6.1 grows — the threshold for "who counts as a
  celebrity" and the caching strategy for celebrity tweets specifically
  (they're read very often, by definition, so they're excellent cache
  candidates) need active tuning.
- **The precomputed timeline cache is a large, constantly-churning working
  set.** Every fan-out-on-write push is a cache write; keeping only the
  most recent ~800 tweet IDs per user (Step 5) bounds memory but means a
  user who hasn't opened the app in weeks has a timeline cache built for
  "recent," not "since you were last here" — the timeline service has to
  fall back to a slower reconstruction path for very stale users.
- **Trending topics are vulnerable to manipulation (coordinated
  spam/bot spikes)** — the streaming aggregation in 6.3 counts raw
  frequency, so a real system layers anomaly/bot detection on top rather
  than trusting raw counts, which adds meaningful complexity beyond the
  core counting pipeline described here.
- **Eventual consistency means users occasionally see stale counts or
  missing tweets briefly** (a like count that hasn't caught up, a tweet from
  someone just followed that hasn't appeared yet) — an explicit, accepted
  trade-off in exchange for the write availability and throughput the
  overall design needs; this is not a system that offers read-your-writes
  consistency across every derived view.
- **The social graph store, not the tweet store, is often the harder
  scaling problem in practice** — extremely popular accounts create hot
  partitions on the "who follows this account" side (Step 5's second
  adjacency table), the same hot-partition problem described generally in
  `../01_Concepts/07_database_scaling.md`.

## Follow-up Questions an Interviewer Might Ask

**How would you rank the timeline instead of showing strict reverse-chronological order?**
This becomes a ranking/scoring problem layered on top of the same
candidate-generation pipeline (fan-out cache + celebrity merge from 6.1) —
candidates are gathered the same way, but instead of returning them in ID
order, a ranking step scores each by engagement-prediction signals before
display; the ranking model itself is a separate ML subsystem, deliberately
out of scope for the core delivery design, the same way feed ranking is
scoped out in `08_news_feed.md`.

**How do you handle a user unfollowing someone whose tweets are already in their precomputed timeline cache?**
The simplest approach is lazy cleanup: leave already-cached entries in place
(they'll naturally age out as new tweets push old ones past the bounded
cache size) and simply stop future fan-out from that author into this
user's cache going forward — an eager scan-and-remove across a potentially
large cached timeline is rarely worth the cost for a transient
inconsistency that self-corrects quickly.

**How would you support tweet deletion?**
The Tweet Store row is marked deleted (or removed) and this needs to
propagate to the search index (re-index/remove), the trending counters
(no retroactive correction, generally accepted as-is), and the precomputed
timeline caches (either lazily filtered at read/hydration time when the
Timeline Service fetches content and finds it deleted, or eagerly removed if
the design has an efficient reverse-lookup — lazy filtering is usually
simpler and sufficient).

**How would you rate-limit tweet posting to prevent spam floods that would overload fan-out?**
A per-user token-bucket limiter in front of the Tweet Service, similar to
the chat rate-limiting follow-up in `09_chat_application.md` — this protects
the fan-out and stream-processing layers downstream, since a single spammy
account posting thousands of times per second would otherwise directly
translate into a proportional fan-out and indexing load spike.

**How would you handle threads/replies?**
Each reply is a normal tweet row with a `reply_to_id` pointer (Step 5); a
thread view is reconstructed by following that pointer chain, and a "load
this thread" endpoint is a separate read path from the home timeline — it
doesn't need to be part of the fan-out design at all, since threads are
fetched on demand when a user opens them, not pushed proactively.

**Why not use a graph database for the social graph, given follows are naturally a graph?**
Twitter's actual query patterns — "list who I follow," "list who follows
me," "does A follow B" — are simple adjacency lookups, not multi-hop graph
traversals (e.g., "friends of friends," which Twitter doesn't need for its
core follow model). A purpose-built graph database earns its complexity when
multi-hop traversal is a core query; here, two denormalized key-value/wide-
column adjacency tables answer every needed query more simply and at higher
throughput.
