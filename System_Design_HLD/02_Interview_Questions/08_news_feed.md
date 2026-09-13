# Design a News Feed

## Problem Statement

"Design a news feed — the home feed a user sees when they open an app like Facebook or Instagram: a scrollable stream of posts from the people and pages they follow, roughly ordered by recency (or relevance), that loads fast, supports infinite scroll, and stays reasonably up to date as new posts are created — at the scale of hundreds of millions of users, including some accounts with tens of millions of followers." This is one of the most commonly asked system design questions precisely because the naive solution (query posts from everyone you follow at read time) looks fine until you compute what it costs at scale, and the interesting design lives entirely in that gap.

## Step 1: Clarify Requirements

### Functional Requirements

- Users can create posts (text, possibly with media references).
- Users can follow/unfollow other users.
- A user's home feed shows posts from everyone they follow, ordered by recency (chronological is the baseline; true relevance ranking is discussed briefly, Step 6).
- The feed supports infinite scroll — fetching further pages of older posts as the user scrolls.
- A newly created post should appear in followers' feeds within a few seconds, not minutes or hours.
- Basic engagement counts (likes, comments) are shown alongside each post — out of scope for deep design here, but the data model must not preclude it.

### Non-Functional Requirements

- **Scale**: hundreds of millions of daily active users; follower counts range from zero to tens of millions (the "celebrity" case is a first-class scale concern, not an edge case).
- **Read-heavy workload**: users check their feed far more often than they post — the read:write ratio is large (quantified in Step 2), and the design should optimize overwhelmingly for read latency.
- **Latency**: feed load p99 under roughly 200ms — a slow-loading home feed is the single most visible performance metric for a social app.
- **Eventual consistency is acceptable**: a new post appearing in a follower's feed a few seconds late is a non-issue; there is no need for strong consistency between "post created" and "post visible in every follower's feed."
- **High read availability**: the feed should essentially never be unavailable — even if some backend components degrade, showing a slightly stale feed is far preferable to showing an error.
- **Write path must not block on fan-out for high-follower accounts** — a celebrity's post cannot make the post-creation call synchronously wait on millions of downstream writes (this is the celebrity problem, the centerpiece of Step 6).

## Step 2: Back-of-Envelope Estimation

**Assumptions**:
- 500 million daily active users (DAU).
- Posting rate: on average, 1 post per 20 DAU per day (most users are far more likely to scroll than post) → 25 million posts/day.
- Feed-reading rate: each DAU opens the app 8 times/day, and each app open fetches roughly 2 feed pages (initial load + one scroll-triggered page) → 16 feed-read requests/user/day.
- Average follower count (mean, not median — heavily skewed by a small number of very-high-follower accounts): 300.
- Feed entry size: `post_id` + `author_id` + `timestamp` ≈ 24 bytes.
- Precomputed feed depth kept per user: last 800 entries.

**Write QPS (post creation)**

```
25,000,000 posts/day / 86,400 sec ≈ 289 posts/sec average
Peak (3x): 289 × 3 ≈ 870 posts/sec
```

**Read QPS (feed fetch)**

```
500,000,000 DAU × 16 reads/day = 8,000,000,000 reads/day
8,000,000,000 / 86,400 sec ≈ 92,600 reads/sec average
Peak (3x): 92,600 × 3 ≈ 278,000 reads/sec
```

**Read:write ratio**

```
92,600 / 289 ≈ 320:1
```

This 320:1 ratio is the single number that justifies the entire architecture in Step 6: it means every unit of extra work done at write time to make reads cheap and fast is paid for roughly 320 times over by every subsequent read — which is exactly the argument for precomputing feeds rather than assembling them fresh on every read.

**Fan-out-on-write cost**

If every post is eagerly pushed into every follower's precomputed feed at write time:

```
25,000,000 posts/day × 300 avg followers/post = 7,500,000,000 feed-entry writes/day
7,500,000,000 / 86,400 sec ≈ 86,800 fan-out writes/sec average
```

That's already ~300x the raw post-creation QPS — and this used the *mean* follower count, which is dragged upward by a small number of huge accounts; the median user has far fewer followers, meaning an enormous share of those 86,800 writes/sec are attributable to a small number of very-high-follower posts. A single celebrity account with 50 million followers posting once generates 50 million feed-entry writes from that one post alone — doing that synchronously, or even eagerly-but-asynchronously without special-casing it, would dominate the entire fan-out pipeline's capacity for those few seconds. This is the concrete arithmetic behind why a hybrid fan-out strategy (Step 6) is necessary, not just a nice-to-have optimization.

**Feed storage**

```
500,000,000 users × 800 entries × 24 bytes = 9,600,000,000,000 bytes ≈ 9.6 TB
```

Entirely feasible for a fast key-value/wide-column store holding just references, not full post content.

**Post content storage**

```
25,000,000 posts/day × ~1 KB metadata (text, author, timestamp — excluding media) = 25,000,000 KB ≈ 25 GB/day
Over a year: 25 GB × 365 ≈ 9.1 TB/year of post metadata
```

Media (images/video) is stored separately in object storage at a much larger scale and is out of scope for this design's depth — see `12_storage_systems.md` — but the key point is that the feed itself never stores media, only references.

**Fan-out savings from the hybrid approach**

Assume celebrity accounts (a small fraction of all accounts, say the top 0.01% by follower count) collectively account for roughly 40% of total *follower relationships* despite being a tiny fraction of posting accounts — a realistic skew for social platforms. Removing celebrity posts from eager fan-out removes roughly that same proportion of fan-out writes:

```
86,800 fan-out writes/sec (Step 2, naive) × 40% ≈ 34,700 writes/sec avoided by deferring celebrity accounts to read-time
Remaining eager fan-out load: 86,800 - 34,700 ≈ 52,100 writes/sec
```

That's still a substantial write load, but it's now driven by the long tail of ordinary accounts with roughly-bounded follower counts each, rather than being periodically spiked by a single celebrity post generating tens of millions of writes in a burst — the hybrid approach flattens the write-load variance, not just its average.

## Step 3: High-Level Design

```text
                         +------------------+
                         |   Post Service    |  (write path)
                         +--------+---------+
                                  |
                        +---------+---------+
                        |                   |
                        v                   v
              +------------------+   +------------------+
              |    Post Store    |   |  "Post Created"   |
              |  (author_id,     |   |  Event (pub/sub)  |
              |   content, ts)   |   +---------+--------+
              +------------------+             |
                        ^                       v
                        |            +------------------------+
                        |            |     Fan-Out Service      |
                        |            |  (async consumer)        |
                        |            +------------+-------------+
                        |                          |
                        |          normal accounts |   celebrity accounts
                        |          (push to every   |   (skip fan-out;
                        |           follower's feed) |    flagged specially)
                        |                          |
                        |                 v                     |
                        |     +----------------------+          |
                        |     |     Feed Store         |          |
                        |     | (per-user precomputed  |          |
                        |     |  sorted list of        |          |
                        |     |  post_id references)   |          |
                        |     +-----------+-----------+          |
                        |                 |                      |
                        |                 v                      |
                        |     +----------------------+           |
                        +---->|     Feed Service       |<----------+
                              |  (read path: merge      |
                              |   precomputed feed +     |
                              |   celebrity follows,     |
                              |   hydrate post content)  |
                              +-----------+-----------+
                                          |
                                          v
                              +----------------------+
                              |       Client (app)     |
                              +----------------------+
```

**Flow**: creating a post writes it once to the durable Post Store and publishes a `post.created` event. An async Fan-Out Service consumes that event: for an ordinary account, it pushes a reference (`post_id`, `timestamp`) into every follower's precomputed feed list in the Feed Store — this is the expensive step Step 2 quantified. For a high-follower ("celebrity") account, fan-out is deliberately skipped at write time (Step 6). At read time, the Feed Service fetches the requesting user's precomputed feed list (already merged and sorted for normal follows), separately fetches any recent posts from the small number of celebrities that user follows, merges the two by timestamp, and then hydrates each `post_id` reference into full post content from the Post Store (or a cache in front of it) before returning the page to the client.

**Key components**:
- **Post Service / Post Store**: durable, authoritative store of post content — written once per post, read many times during hydration.
- **Fan-Out Service**: the async worker that decides, per post, whether to push eagerly (normal accounts) or defer to read time (celebrity accounts) — the hybrid logic lives here.
- **Feed Store**: per-user precomputed list of post references, optimized purely for fast append and fast range-read by recency.
- **Feed Service**: the read path — merges precomputed entries with celebrity posts fetched live, hydrates content, and paginates the result (Step 6).

**Walking through one post end to end**: (1) a normal user with 300 followers creates a post; the Post Service writes it once to the Post Store and publishes `post.created`. (2) The Fan-Out Service consumes the event, checks the follow graph's `follower_count` for this author (well under the celebrity threshold), and appends a `(post_id, created_at)` reference into each of the 300 followers' Feed Store entries — a few hundred fast writes, done asynchronously so the post-creation API call itself already returned before this finishes. (3) A follower opens the app minutes later; the Feed Service reads that follower's precomputed feed list (which now includes the new post's reference near the top), separately checks whether the follower follows any celebrity accounts and fetches their few most recent posts directly from the Post Store, merges both lists by `created_at`, hydrates each `post_id` into full content (via the post-content cache), and returns the first page. (4) If instead the author had 50 million followers, step (2) would be skipped entirely — the Fan-Out Service marks the post as belonging to a flagged celebrity and does nothing further — and every follower's feed read in step (3) does the extra live lookup against that celebrity's recent posts as part of assembling their page.

## Step 4: API Design

**Create a post**
```
POST /posts
{ "user_id": "u_1", "content": "hello world", "media_refs": [] }
→ 201 Created { "post_id": "p_9001", "created_at": "2026-09-13T10:00:00Z" }
```

**Fetch home feed (cursor-paginated)**
```
GET /feed?cursor=eyJ0cyI6MTcyNjIzMDQwMH0&limit=20
→ 200 OK
{
  "posts": [
    { "post_id": "p_9001", "author_id": "u_1", "content": "hello world", "created_at": "..." },
    ...
  ],
  "next_cursor": "eyJ0cyI6MTcyNjIyOTk4MH0"
}
```

**Follow / unfollow**
```
POST /follow   { "follower_id": "u_2", "followee_id": "u_1" } → 204 No Content
DELETE /follow { "follower_id": "u_2", "followee_id": "u_1" } → 204 No Content
```

**Fetch a single post** (used by clients for deep links, and internally for hydration)
```
GET /posts/{id}
→ 200 OK { "post_id": "p_9001", "author_id": "u_1", "content": "...", "like_count": 42 }
```

**Internal fan-out trigger** (consumed off the event bus, not a public endpoint)
```
FanOutService.OnPostCreated(post_id, author_id, created_at)
  → for author_id's followers (if not flagged celebrity): append (post_id, created_at) to each follower's feed list
  → if flagged celebrity: no-op (post picked up at read time instead)
```

## Step 5: Data Model

**Post Store** — NoSQL wide-column/document store (e.g., Cassandra/DynamoDB), partition key = `post_id`:

| Field | Notes |
|---|---|
| `post_id` (PK) | |
| `author_id` | secondary index — used to fetch "all posts by author X" for celebrity read-time fan-out |
| `content` | text; media is referenced, not stored inline |
| `media_refs` | pointers into object storage |
| `created_at` | |
| `like_count` / `comment_count` | denormalized counters, updated by separate engagement services (out of scope) |

NoSQL fits because access is dominated by simple key-based lookups (`post_id`) and author-scoped scans, at very high write volume (25M posts/day) with no need for relational joins across posts.

**Feed Store** — a fast in-memory or wide-column store optimized for append and range-read by recency; Redis sorted sets are a natural fit: key = `user_id`, members = `post_id`, score = `created_at` (or a monotonic sequence derived from it). `ZADD` appends a new entry in O(log N); `ZREVRANGE` fetches the most recent N entries in O(log N + M). Capped to the last ~800 entries per user (Step 2) via periodic trimming (`ZREMRANGEBYRANK`), since no product surface needs a feed that scrolls back further than that.

Critically, **the feed store holds only references** (`post_id` + `created_at`), never full post content — storing full content per follower would multiply the 9.1 TB/year of post data by the average follower count, an enormous and entirely avoidable duplication. Content is always hydrated from the Post Store (typically through a cache) at read time, which is the standard reference-then-hydrate pattern for any fan-out-heavy system.

**Follow graph** — two wide-column tables for O(1) lookups in both directions, since "who do I follow" and "who follows me" are both hot paths (the former for read-time celebrity merging, the latter for fan-out):

| Table | Partition key | Columns |
|---|---|---|
| `following` | `user_id` | list/set of `followee_id`s the user follows |
| `followers` | `user_id` | list/set of `follower_id`s who follow the user, plus a `follower_count` used to flag celebrity status |

**User/profile store** — a conventional relational database (SQL) for account data, authentication, and settings — comparatively small, benefits from relational integrity constraints, and isn't on the extreme-scale hot path the feed itself is on.

**Storage choice justification, summarized**:

| Component | Storage type | Why |
|---|---|---|
| Post content | Wide-column/document NoSQL | Very high write volume, simple key-based/author-scoped access, no joins |
| Feed list (references only) | Redis sorted set (or wide-column, timestamp-clustered) | Needs fast append + fast recency range-read at massive scale |
| Follow graph | Wide-column NoSQL, two tables | O(1) lookups needed in both directions (following/followers) |
| User/profile data | Relational (SQL) | Small, structured, benefits from integrity constraints, not on the hot path |
| Post media | Object storage | Large, immutable blobs, referenced not embedded |

## Step 6: Deep Dive

### Fan-Out-on-Write vs. Fan-Out-on-Read vs. the Hybrid Approach

This is the single most important design decision in the whole system, and it's a direct consequence of the 320:1 read:write ratio computed in Step 2.

**Fan-out-on-write (push model)**: when a user creates a post, the system immediately writes a reference to that post into the precomputed feed of every one of their followers. Reading a feed then becomes a single cheap fetch of an already-assembled list.
- *Pros*: feed reads are extremely fast — just a range-read on one precomputed list, exactly matching this system's read-latency priority.
- *Cons*: a post from a high-follower account triggers an enormous burst of writes at post-creation time — Step 2 showed a single 50-million-follower account's post generates 50 million feed-entry writes. Even done asynchronously, that's a massive, disproportionate load spike from one single logical event, and it means most of the system's total write capacity is consumed by a tiny fraction of posts from a tiny fraction of accounts.

**Fan-out-on-read (pull model)**: nothing is precomputed. When a user requests their feed, the system queries the latest posts from every account they follow, merges the results by timestamp, and returns the page.
- *Pros*: post creation is cheap and constant-cost regardless of follower count — writing a post is just one row in the Post Store, full stop.
- *Cons*: every single feed read now has to fan out to N sources (one per followee) and merge them live — for a user following even a few hundred accounts, that's hundreds of queries (or a scatter-gather against a system built to make that efficient) on *every* feed load, and this system's read volume is 320x its write volume, meaning this cost is paid at the worst possible multiplier.

**The hybrid approach — what real systems (Twitter/X, Instagram, Facebook) actually do**: use fan-out-on-write for the overwhelming majority of accounts (normal follower counts, where eager fan-out is cheap and reads stay fast), but switch to fan-out-on-read specifically for celebrity/high-follower accounts (a threshold, e.g. accounts with more than some tens of thousands of followers, flagged in the follow graph's `follower_count`). When a celebrity posts, the Fan-Out Service does nothing at write time — no eager push to millions of feeds. Instead, at read time, the Feed Service additionally checks the small list of celebrities a given user follows (small because there are relatively few celebrity accounts and any one user follows only a handful of them, even if a celebrity individually has millions of followers) and merges their most recent posts directly into the response alongside the precomputed feed.

This is the key insight interviewers are looking for: **the expensive direction of the celebrity problem is inverted by inverting who pays for it**. A celebrity has millions of followers but that same celebrity is followed by a *bounded, small* number of celebrities themselves need not be fanned out to — the cost that would have been "one post × millions of follower writes" becomes "one post, and then each follower's occasional feed read does a tiny bit of extra work merging in a handful of celebrity accounts they follow." The total system-wide cost is dramatically lower because it's distributed thin across many cheap read-time merges instead of concentrated into one enormous write-time burst.

| | Fan-out-on-write | Fan-out-on-read | Hybrid |
|---|---|---|---|
| Write cost | High, proportional to follower count | Constant, independent of follower count | Constant for celebrities, proportional for everyone else |
| Read cost | Very low — single precomputed list fetch | High — merge live from every followee | Low — precomputed list + small celebrity merge |
| Worst case | A single celebrity post spikes write load enormously | A user following thousands strains every single read | Bounded on both sides by the celebrity threshold |
| Matches this system's 320:1 read:write ratio? | Only for non-celebrity accounts | No — pays the expensive side on the majority-traffic path | Yes — cheap reads for the common case, cheap writes for the rare extreme case |

The **celebrity threshold** itself (the follower count above which an account switches to read-time fan-out) is a tunable configuration value, not a fixed constant — set high enough that it only captures a small fraction of accounts (keeping the read-time merge cost bounded per user, since most users follow at most a handful of accounts above any reasonable threshold), but low enough that no single eager fan-out burst meaningfully dents write capacity.

### Feed Storage Model

The precomputed feed is deliberately a **list of references** (`post_id`, `created_at`), not a denormalized copy of full post content, stored in a store chosen for very fast append and very fast recency-ordered range reads (Redis sorted sets, or a wide-column store with clustering-key-by-timestamp semantics). At read time, the Feed Service takes the batch of `post_id`s from the feed list and **hydrates** them — looks up full content — from the Post Store, almost always through a cache layer in front of it (`05_caching.md`), since the same popular posts get hydrated repeatedly across many different users' feed reads and are an ideal caching target (high read-to-write ratio at the individual post level too, not just the feed level).

Storing references instead of full content is what keeps the 9.6 TB feed-store number in Step 2 small relative to what duplicating full post content per follower would cost — and it also means an edit or deletion to a post is instantly reflected everywhere it appears (there's only ever one copy of the content, in the Post Store), rather than needing to be propagated into every follower's feed copy.

### Feed Ranking

A pure chronological feed (newest first) is the simplest correct baseline and is what the design above assumes throughout — the precomputed feed list is sorted by `created_at`, full stop. Real large-scale products instead rank by a **relevance/engagement score** (a function of predicted likelihood the user will engage with a given post, incorporating signals like the poster's relationship strength to the viewer, post recency, historical engagement patterns, and content type) rather than raw recency, computed by a machine-learning model trained on engagement data.

This is worth mentioning explicitly in an interview as the natural evolution of the design, but it's intentionally kept brief here — the ranking model itself (feature engineering, training pipeline, online scoring infrastructure) is a large, separate ML-systems problem, out of scope for a systems design interview's depth. The one architecturally relevant point is that ranking, if added, happens as a **re-sort step at read time** on top of the candidate set already assembled by the fan-out/hydration pipeline above (whether from the precomputed feed, the celebrity merge, or both) — it changes the *ordering* of what's shown, not the underlying fan-out/storage architecture that produces the candidate set in the first place.

### Cursor-Based Pagination for Infinite Scroll

**Why offset-based pagination breaks here**: a naive "give me posts 20-40" (`OFFSET 20 LIMIT 20`) approach assumes the underlying list is stable between page requests. But a feed is being actively inserted into concurrently — new posts from people the user follows can land at the top of the list between the user's first page load and their next scroll-triggered fetch. If page 2 is requested as "skip the first 20, give me the next 20" and 3 new posts were inserted at the top since page 1 loaded, the offset shifts by 3, and the user either sees 3 posts repeated (they were pushed from position 18-20 into position 21-23, which the offset-based page 2 would now include again) or, depending on direction, silently skips 3 posts entirely. This is a real, frequently-hit bug class in any offset-paginated feed under concurrent writes, not a theoretical concern.

**The fix — cursor-based pagination**: instead of a position (an offset), the client sends back an opaque cursor derived from a **stable sort key** on the last item it received — here, the `created_at` timestamp (or an equivalent monotonic sequence number) of the last post in the previous page. The next page's query becomes "give me the next 20 posts with `created_at` strictly older than the cursor's timestamp," which is correct regardless of how many new posts have been inserted above that point in the meantime, because the query is anchored to a specific post's position in the timeline, not to a numeric offset that shifts as the list grows. This is why the API in Step 4 returns an opaque `next_cursor` rather than a page number, and why the Feed Store's underlying structure (Redis sorted set scored by timestamp, or a timestamp-clustered wide-column table) is specifically chosen to make "give me entries older than X" an efficient, native range query rather than something bolted on.

## Step 7: Bottlenecks & Trade-offs

- **The celebrity problem is the first thing that breaks without the hybrid design** — Step 2's 50-million-follower example shows a naive fan-out-on-write system spends the overwhelming majority of its write capacity on a tiny fraction of posts; the hybrid approach is not an optional optimization, it's close to load-bearing for the system to function at all at this scale.
- **Feed store hot partitions for very active followers** — a user who follows thousands of accounts (even without any single one being a celebrity) still receives a disproportionate volume of fan-out writes into their one feed-list key, which can make that specific key a write hotspot even under otherwise-even sharding; mitigated by capping how many accounts a single user can follow, or by sharding a single user's feed list across multiple keys if needed.
- **Consistency lag is a real, accepted user-visible effect**: the gap between "post created" and "post appears in a follower's feed" (Step 3's async fan-out) means a follower could refresh at the exact wrong moment and not yet see a just-published post — acceptable per the stated non-functional requirement (eventual consistency), but worth naming explicitly as a trade-off rather than glossing over.
- **A single post going viral creates a read-side hot-key problem, not a write-side one**, once the hybrid design is in place — many users simultaneously hydrating the same `post_id` from the Post Store is exactly the hot-key caching scenario described in `06_distributed_cache.md`, and is mitigated the same way (aggressive caching of hot posts, potentially a local L1 cache layer).
- **Storage grows without bound on two axes independently** — the Post Store grows with total posts created (9.1 TB/year, Step 2) and the Feed Store grows with total (user × follow-count) pairs; both need independent capacity planning and independent sharding strategies, since they're driven by different underlying growth rates (post volume vs. social-graph density).
- **Ranking (if added) trades read-path simplicity for engagement** — a chronological feed is trivially reasoned about and debugged; a ranked feed adds an entire ML scoring step to the read path's latency budget and makes "why did I see this post" much harder to explain, which is a real product and engineering cost, not just an infrastructure one.

**Bottleneck-to-mitigation summary**:

| Bottleneck | Mitigation | Cost accepted |
|---|---|---|
| Celebrity post fan-out burst | Hybrid: fan-out-on-read for high-follower accounts | Slightly more read-path work per request for followers of celebrities |
| Feed-store hot key (user following very many accounts) | Cap follow count, or shard/limit live-merge sources per read | Reader sees a bounded subset of very-broad follow graphs |
| Viral post read-side hot key | Aggressive caching of hot posts, optional local L1 cache | Brief staleness on rapidly-changing engagement counts |
| Offset pagination breaking under concurrent writes | Cursor-based pagination keyed on a stable sort field | Slightly more complex client-side cursor handling |
| Unbounded storage growth on two independent axes | Independent capacity planning/sharding for Post Store vs. Feed Store | Two scaling strategies to operate instead of one |

## Follow-up Questions an Interviewer Might Ask

**How would you support ephemeral content like Stories that disappear after 24 hours?**
Treat Stories as a structurally separate feed type with its own precomputed list (same fan-out mechanics, since Stories are typically followed by comparatively few viewers relative to celebrity-scale problems) but with a TTL on both the Post Store entry and the feed reference, so expiry is enforced automatically rather than requiring an explicit deletion sweep.

**A user unfollows someone — does the design need to retroactively remove that person's old posts from the already-fanned-out feed?**
Generally no in practice — the operational cost of scanning and pruning a specific author's post references out of a follower's feed list is high relative to the benefit, so most systems simply let previously fanned-out posts age out naturally (they scroll further down and eventually fall outside the retained ~800-entry window, Step 2) while ensuring no *new* posts from the unfollowed account are fanned out going forward.

**How would you handle a user who follows an unusually large number of accounts (say, 10,000), which strains the fan-out-on-read merge step for their reads?**
Apply the same threshold-based hybrid logic in reverse for the follow-side: for a user following an extreme number of accounts, bias toward doing more precomputation (or capping how many of those follows contribute live at read time, e.g., only merging the most recently active N followees) rather than merging thousands of live sources on every read — this is a symmetric version of the celebrity problem, driven by follow-graph density on the reader's side instead of the poster's side.

**How would you generate a reasonable feed for a brand-new user with no follow history yet?**
Fall back to a separate cold-start path (a curated or popularity-ranked set of posts, similar to fan-out-on-read against trending/popular content) rather than the normal precomputed-feed path, since a new user's feed list is genuinely empty and has nothing to hydrate from yet — this is a distinct code path, not an edge case the main pipeline needs to handle gracefully.

**How would engagement (likes/comments) update in near-real-time without re-fanning-out the whole post?**
Keep engagement counters as a separately-updated field on the Post Store record (denormalized `like_count`/`comment_count`, incremented by a dedicated engagement service) rather than something the feed-fan-out pipeline touches at all — since the feed store only holds a `post_id` reference, an updated like count is automatically reflected the next time that post is hydrated, with no need to touch any follower's feed list.

**How would you replicate this across multiple regions for global users with low latency?**
Keep the Post Store and Feed Store partitioned/replicated per region close to where users read from, accepting cross-region propagation lag for a post to reach a follower in a different region (layered on top of the async fan-out lag that already exists intra-region) as an extension of the same eventual-consistency trade-off already accepted in Step 1, rather than a fundamentally new consistency requirement.

**How would you decide the celebrity threshold in practice, and would you ever move an account between the two fan-out strategies?**
Set it empirically from observed follower-count distribution (e.g., the point past which eager fan-out cost per post materially affects fan-out pipeline capacity) and monitor it continuously rather than as a one-time constant, since accounts cross the threshold over time (a rapidly growing account) and the fan-out service needs a clean transition path — typically, once an account crosses the threshold, stop eager fan-out for its future posts and let previously-fanned-out entries simply age out of followers' feed windows naturally rather than attempting a disruptive backfill/removal.
