# Caching

A **cache** is a smaller, faster storage layer that sits in front of a slower
source of truth (a database, an API, a disk) and holds a copy of frequently or
recently accessed data. The bet a cache makes is simple: most systems have
**skewed access patterns** — a small fraction of data (hot keys) accounts for
most of the reads — so keeping that fraction somewhere fast pays off
disproportionately.

## Why it matters

Without caching, every single read hits your database or origin server
directly. Concretely, that means:

- **Latency**: a disk-backed relational query might take 5-50ms; an in-memory
  cache lookup takes well under 1ms. For a page that fires 20 queries, that
  difference is the gap between a 100ms page load and a 2-second one.
- **Database load**: databases are the hardest part of a system to scale
  horizontally (see `07_database_scaling.md`). Every read you serve from a
  cache is a read your database never has to process, which means you can
  serve far more traffic on the same database hardware.
- **Traffic spikes**: read-heavy spikes (a post goes viral, a product hits the
  homepage) are exactly the failure mode caching is built for — without a
  cache, a spike in reads translates directly into a spike in database
  connections, which is how databases fall over.
- **Cost**: re-computing an expensive result (a complex aggregation, a machine
  learning inference, a third-party API call) on every request is often the
  single largest avoidable cost in a system.

The trade-off you're always making is **freshness for speed** — a cache can
serve data that is milliseconds to minutes out of date. Every caching design
decision is really a decision about how much staleness you can tolerate.

## Core Caching Strategies

These strategies describe *where the caching logic lives* and *who is
responsible for keeping the cache and the database in sync*. Pick per data
type, not once for the whole system — most real systems mix these.

### 1. Cache-Aside (Lazy Loading)

The application code is responsible for checking the cache, and on a miss,
loading from the database and populating the cache itself.

```text
Read:
  App -> Cache: get(key)
  Cache -> App: MISS
  App -> DB: query
  DB -> App: data
  App -> Cache: set(key, data)   (populate for next time)

Write:
  App -> DB: write
  App -> Cache: delete(key)      (invalidate, don't update)
```

- **On a miss**: application queries the DB, then writes the result into the
  cache.
- **On a write**: application writes to the DB and *invalidates* (deletes,
  doesn't update) the cache entry — the next read will repopulate it.
- **Pros**: only requested data gets cached (no wasted memory on cold data);
  cache failure is non-fatal — the app just falls back to the DB.
- **Cons**: every cache miss adds a round trip (query DB, then populate
  cache) before returning; the app owns cache logic, which is easy to get
  wrong (forgetting to invalidate somewhere).
- This is the most common pattern in practice — it's what you're doing when
  you use Rails' `Rails.cache.fetch(key) { expensive_query }`.

### 2. Read-Through

Functionally similar to cache-aside, but the cache itself (not the
application) is responsible for loading from the database on a miss. The
application only ever talks to the cache.

```text
Read:
  App -> Cache: get(key)
  Cache -> DB: query (cache does this internally, app is unaware)
  DB -> Cache: data
  Cache -> App: data
```

- **Pros**: application code is simpler (no manual "check cache, then query
  DB, then populate" logic scattered everywhere); loading logic is
  centralized in the cache layer.
- **Cons**: requires a caching library/provider that supports this pattern
  (e.g., some ORMs, some managed caches); first request for any key is still
  slow (the "miss" penalty is unavoidable no matter who owns the fetch).

### 3. Write-Through

Every write goes through the cache, which synchronously writes to both the
cache and the database before acknowledging the write.

```text
Write:
  App -> Cache: set(key, value)
  Cache -> DB: write value           (synchronous)
  DB -> Cache: ack
  Cache -> App: ack
```

- **Pros**: cache is always consistent with the DB — no stale-cache window
  after a write; reads are always fast because data was cached at write time.
- **Cons**: every write now pays the latency of *two* writes (cache + DB) —
  write path gets slower; you can end up caching data that's written but
  never read (wasted memory) unless combined with an eviction policy.
- Good fit when read-after-write consistency matters and write volume is
  moderate (e.g., user profile updates).

### 4. Write-Back (Write-Behind)

Writes go to the cache only, and are acknowledged immediately. The cache
asynchronously flushes the write to the database later (batched, on a timer,
or on eviction).

```text
Write:
  App -> Cache: set(key, value)
  Cache -> App: ack (immediate)
  ... later, async ...
  Cache -> DB: flush batched writes
```

- **Pros**: write latency is as fast as the cache itself — the DB write is
  completely off the critical path; writes can be batched/coalesced (10
  updates to the same key in a second become 1 DB write), which reduces DB
  load significantly.
- **Cons**: **data loss risk** — if the cache node crashes before flushing,
  unflushed writes are gone; the DB can be stale relative to the cache for a
  window, which is dangerous if anything else reads directly from the DB.
- Used where write throughput matters more than durability guarantees (view
  counters, analytics events, metrics) — rarely used for anything
  transactional like payments.

### 5. Write-Around

Writes go directly to the database, completely bypassing the cache. The
cache is only populated later, on a subsequent read (via cache-aside or
read-through).

```text
Write:
  App -> DB: write   (cache untouched)

Read (first time after write):
  App -> Cache: get(key) -> MISS
  App -> DB: query -> populate cache
```

- **Pros**: avoids flooding the cache with data that's written once and
  rarely read (e.g., bulk imports, logs) — keeps the cache's working set
  focused on actually-hot data.
- **Cons**: the first read after a write is always a miss (slower); if reads
  happen immediately after writes (read-your-writes pattern), this is a poor
  fit.

### Strategy Comparison

| Strategy | Write latency | Read latency (post-write) | Data loss risk | Best for |
|---|---|---|---|---|
| Cache-aside | Fast (DB only) | Slow on first read | Low | General-purpose, most common default |
| Read-through | Fast (DB only) | Slow on first read | Low | Same as cache-aside, centralized loader |
| Write-through | Slow (cache+DB) | Fast (always warm) | Low | Read-heavy, consistency-sensitive data |
| Write-back | Very fast (cache only) | Fast (always warm) | High | Write-heavy, tolerant of loss (counters, metrics) |
| Write-around | Fast (DB only) | Slow on first read | Low | Write-once/read-rarely data (logs, bulk data) |

## Eviction Policies

A cache has finite memory, so when it's full and a new item needs to be
stored, something has to be evicted. Which policy you pick changes what stays
"hot."

- **LRU (Least Recently Used)**: evicts the item that hasn't been *accessed*
  for the longest time. Assumes recently-used data is likely to be used
  again soon (temporal locality). This is the default choice for most
  general-purpose caches (Redis's `allkeys-lru`, most CDN edge caches)
  because it adapts automatically to changing access patterns without any
  tuning.
- **LFU (Least Frequently Used)**: evicts the item with the fewest total
  accesses, regardless of recency. Better than LRU when popularity is stable
  over time (a perennially popular product page) and you don't want one
  recent burst of traffic to a rarely-used item to evict something that's
  reliably hot. Downside: slow to adapt — a newly-popular item starts with a
  low count and can get evicted before it accumulates hits.
- **FIFO (First In, First Out)**: evicts the oldest-inserted item regardless
  of access pattern. Cheap to implement (no access-tracking needed) but
  ignores usage entirely, so it can evict something that's accessed
  constantly just because it was added first. Used when simplicity/overhead
  matters more than hit-rate optimality, or when items naturally expire in
  insertion order anyway (e.g., a queue-like cache of recent events).
- **TTL-based expiry (Time To Live)**: every entry is given an expiration
  time; it's evicted (or treated as a miss) once that time passes,
  independent of memory pressure. This isn't really a "which item to evict
  under pressure" policy — it's a **staleness bound**: you use TTL when you
  know data becomes stale after some fixed window (session tokens, a stock
  price quote, an OAuth token) and want to guarantee the cache never serves
  data older than that window. TTL is usually combined with LRU/LFU —
  TTL controls correctness (staleness), LRU/LFU controls capacity.

| Policy | Evicts based on | Good when | Weak when |
|---|---|---|---|
| LRU | Recency of access | General-purpose, evolving hot set | Sudden one-off scans pollute the cache |
| LFU | Frequency of access | Stable, long-term popularity | Slow to adopt newly-trending items |
| FIFO | Insertion order | Simplicity, low overhead | Ignores actual usage entirely |
| TTL | Fixed expiry time | Data with a known staleness bound | Doesn't manage memory pressure by itself |

## Where Caching Lives — The Layered View

Caching isn't one layer — a single request can pass through several caches
before it ever reaches your database, each optimized for a different job.

```text
Client (browser/mobile)
   |  [1] Client-side cache (HTTP cache headers, local storage)
   v
CDN (edge, geographically distributed)
   |  [2] CDN cache — static assets, sometimes API responses
   v
Reverse proxy / API gateway
   |  [3] Gateway cache — response caching for hot API endpoints
   v
Application server
   |  [4] Distributed cache (Redis / Memcached) — query results, sessions, computed objects
   v
Database
   |  [5] DB query cache / buffer pool — pages of data already in memory
   v
Disk
```

1. **Client-side cache**: browser cache governed by `Cache-Control` /
   `ETag` headers, or app-local storage on mobile. Zero network round trip if
   it hits — the fastest possible cache, but you have almost no control over
   invalidation once it's on the client.
2. **CDN**: caches static assets (images, JS, CSS, video) at edge locations
   close to the user. Removes both latency (physical distance to origin) and
   load (origin server never sees the request at all).
3. **Reverse proxy / API gateway cache**: sits in front of your app servers
   (e.g., Nginx, Varnish, or the caching layer of an API gateway) and caches
   whole HTTP responses for a short TTL — useful for endpoints that are
   identical for many users (a public leaderboard, a product listing).
4. **Application-level distributed cache**: Redis/Memcached — shared across
   all app server instances, holds query results, rendered fragments,
   session data, rate-limit counters. This is the layer most "caching"
   design questions are actually about.
5. **Database-level cache**: the DB's own buffer pool / query cache keeps
   recently-accessed pages of data (and sometimes query results) in memory
   so it doesn't hit disk. This happens automatically and isn't something
   application code manages directly, but it's why a "cold" database is
   slower than a "warm" one after a restart.

Each layer downstream absorbs traffic the layers before it missed — the
further left (toward the client) a cache hit happens, the cheaper and faster
it is.

## CDN (Content Delivery Network)

A **CDN** is a globally distributed network of proxy servers ("edge
servers" or "points of presence") that cache and serve content from a
location physically close to the requesting user, instead of every request
traveling all the way to your origin server.

Why it matters: network latency is bounded by the speed of light — a user in
Singapore requesting an asset from a server in Virginia pays ~200ms+ of pure
round-trip travel time no caching *at the origin* can fix. A CDN edge node in
Singapore removes that distance entirely for cached content.

| | Push CDN | Pull CDN |
|---|---|---|
| Who uploads content | You proactively push files to the CDN | CDN pulls from your origin on first request (cache miss), then caches it |
| Best for | Large, infrequently-changing files (release bundles, video libraries) | Frequently-changing or very large content catalogs (most websites) |
| Storage cost | You pay for full storage on the CDN | Only accessed content is cached — cheaper for a long tail |
| Freshness control | You control exactly what's live | First requester after expiry eats a cache-miss penalty |

CDNs aren't limited to static files. **Dynamic content caching at the edge**
is increasingly common: an API response that's the same for all users for a
short window (e.g., a product catalog page, a public feed) can be cached at
CDN edge nodes with a short TTL, which offloads a large fraction of read
traffic away from your origin entirely. This is distinct from personalized
responses (a user's own dashboard), which generally can't be edge-cached
without per-user cache keys.

## Cache Invalidation

There's a well-known quip: *"There are only two hard problems in computer
science: cache invalidation and naming things."* The reason invalidation is
genuinely hard is that a cache is, by definition, a **second copy of the
truth** — and once you have two copies of anything, you must actively keep
them in sync, or accept that they'll diverge. In a system with multiple
cache layers (see above) and multiple app servers each possibly holding
their own local cache, "the data changed" has to propagate to every copy,
and there's no single moment where that happens atomically. Miss one, and
some fraction of users see stale data — sometimes indefinitely.

Three main strategies, usually combined:

- **TTL expiry**: give every cache entry a lifespan; after it expires it's
  treated as a miss and refetched. Simple and self-healing (no explicit
  invalidation code needed), but it means staleness up to the TTL window is
  *always* possible — you're trading correctness for simplicity.
- **Write-through invalidation**: the write path itself updates or deletes
  the cache entry as part of the write (see the Write-Through and
  Cache-Aside strategies above). Precise — the cache is corrected the
  instant the write happens — but only works for writes that go through code
  paths you control; a direct DB update (a migration, a background job, an
  admin console) can silently leave the cache stale.
- **Event-based invalidation**: the write publishes an event (e.g., to a
  message queue — see `10_message_queues_and_streaming.md`) that all
  interested caches subscribe to and invalidate themselves on. This scales
  to multiple cache layers/services without every writer needing to know
  about every cache, but adds infrastructure and a small propagation delay
  (the caches aren't invalidated *atomically* with the write, just very
  soon after).

The underlying tension in all three is the same: **staleness vs.
consistency cost**. Perfect consistency (never serve stale data) requires
either extremely short TTLs (defeats the point of caching) or synchronous
invalidation everywhere (adds latency and coupling to every write). Every
real system picks a tolerable staleness window per data type rather than
solving this globally.

## Cache Stampede (Thundering Herd)

**The problem**: a single hot key (say, a trending post's data) expires.
In the instant after expiry, if there are 10,000 concurrent requests for
that key, *all 10,000* see a cache miss simultaneously and all hammer the
database at once to recompute the same value — a load spike the database
was never sized for, potentially cascading into an outage.

```text
Before expiry:  10,000 req/s -> Cache HIT -> fast, DB untouched
At expiry:      10,000 req/s -> Cache MISS -> ALL hit DB simultaneously
                                 DB gets 10,000 identical queries at once
```

Mitigations:

- **Request coalescing / single-flight**: when a miss occurs, only the
  *first* request actually queries the DB; concurrent requests for the same
  key wait on that in-flight request and share its result instead of each
  issuing their own query. (Many caching libraries call this pattern
  "single-flight.")
- **Locking**: similar idea — the first request acquires a short-lived lock
  on the key before recomputing; other requests either wait for the lock to
  release (then read the now-fresh cache) or serve stale data briefly rather
  than all querying the DB.
- **Jittered / staggered TTLs**: instead of setting every related key to
  expire at exactly the same time (e.g., "expire at midnight" for a whole
  batch of entries), add random jitter (e.g., TTL = 60s ± 10s) so expiries
  spread out over time instead of bunching into one spike.
- **Background refresh before expiry**: proactively recompute and
  repopulate a hot key shortly *before* it expires (e.g., refresh at 90% of
  TTL) so it never actually goes cold from the perspective of incoming
  requests.

## Redis vs Memcached

The two dominant distributed caching systems, often used interchangeably for
simple key-value caching but with real differences once you need more.

| | Redis | Memcached |
|---|---|---|
| Data structures | Strings, hashes, lists, sets, sorted sets, streams, bitmaps | Strings only (values are opaque blobs) |
| Persistence | Optional (RDB snapshots, AOF log) — can survive a restart | None — purely in-memory, restart loses everything |
| Clustering | Native (Redis Cluster) with automatic sharding | Client-side sharding only (no built-in cluster mode) |
| Pub/Sub | Built-in | Not supported |
| Multithreading | Historically single-threaded per instance (I/O threading added later) | Multithreaded natively — can use more cores per instance |
| Typical use case | Anything beyond simple caching: leaderboards (sorted sets), rate limiting (counters + TTL), session store, pub/sub, queues | Pure, simple, maximally fast key-value caching with minimal overhead |

Rule of thumb: reach for **Memcached** when you want the simplest possible
cache and nothing else — raw throughput for plain key-value gets. Reach for
**Redis** the moment you need anything beyond that: data structures beyond
strings, persistence, pub/sub, atomic increments, or built-in clustering.
Most new systems default to Redis because the extra capability costs little
and is frequently needed later.

## Trade-offs

| Decision | Choose this... | ...when |
|---|---|---|
| Cache-aside vs write-through | Cache-aside | Reads dominate, occasional stale-on-write is acceptable |
| | Write-through | Reads must always be fresh right after a write |
| Write-back vs write-through | Write-back | Write throughput matters more than durability (counters, metrics) |
| | Write-through | Losing a write is unacceptable |
| LRU vs LFU | LRU | Access patterns shift over time, no tuning wanted |
| | LFU | Popularity is stable and long-lived |
| TTL length | Short TTL | Data changes often / staleness is costly |
| | Long TTL | Data is nearly static / cache hit-rate matters most |
| Push vs Pull CDN | Push | Large static libraries known in advance |
| | Pull | Large, evolving catalogs where pre-uploading everything is wasteful |

There is no universally "correct" cache configuration — every choice here
is a dial between **freshness, latency, throughput, and durability**, and
the right setting depends entirely on how bad it is for a given piece of
data to be a few seconds (or minutes) out of date.

## Interview Tips

- Caching almost always comes up as a **follow-up**, not the opening
  question — you propose a design, the interviewer says "reads are
  dominating and the DB is the bottleneck, what do you do?" and wants to see
  you reach for caching specifically, with a stated strategy, not just "add
  a cache."
- Always state **what** you're caching (a full object? a rendered page
  fragment? a query result?), **where** (which layer), and **for how long**
  (TTL) — vague answers like "we'll cache it" without these specifics read
  as surface-level.
- Interviewers frequently probe invalidation on purpose, because it's where
  candidates who've only used caches superficially fall apart. Be ready to
  say precisely how a write propagates to (or invalidates) the cache, and
  what a user sees in the gap before it does.
- Thundering herd is a strong signal question — bringing it up
  unprompted when discussing a "hot key" scenario (celebrity profile, viral
  post) shows you've actually operated a cache under real load, not just
  read about caching.
- Know the difference between caching for **latency** (client/CDN layers) and
  caching for **database offload** (distributed cache layer) — they solve
  different problems and interviewers will ask which one you're targeting.

## Quick Recall — Self-Test

**1. What's the core difference between cache-aside and write-through in terms of what happens on a write?**
Cache-aside writes to the DB and *deletes* the cache entry (invalidates), letting the next read repopulate it. Write-through writes to both the cache and DB synchronously as part of the same write operation, so the cache is never stale after a write.

**2. Why is write-back risky, and when is that risk acceptable?**
Write-back acknowledges the write once it's in the cache, before it's flushed to the DB — if the cache node crashes before flushing, that data is lost. It's acceptable for data where some loss is tolerable and write speed matters more, like view counters or metrics, but not for anything transactional.

**3. When would you pick LFU over LRU for eviction?**
When popularity is stable over a long period and you don't want a single recent burst of traffic to a rarely-used item to evict something reliably popular. LRU is the better default when access patterns shift over time, since it adapts automatically without tracking frequency.

**4. Why is cache invalidation considered "hard" beyond just calling `.delete(key)`?**
Because a cache is a second copy of the truth, and in real systems there are often multiple cache layers and multiple servers each holding a copy — invalidation has to reach every copy, there's no single atomic moment where "the data changed" propagates everywhere, and any path that bypasses your write code (a direct DB update, a migration) can leave stale copies behind indefinitely.

**5. What causes a cache stampede, and name two mitigations.**
A hot key expires and a large volume of concurrent requests all miss at once, sending a burst of identical queries to the DB simultaneously. Mitigations include request coalescing/single-flight (only one request recomputes, others wait on it) and jittered TTLs (spreading expiry times so they don't all fall at once) or background refresh before expiry.

**6. Why can't a CDN alone fix latency for personalized/dynamic content?**
A CDN caches content that's the same for many users at a shared cache key; personalized content (a user's own dashboard, account data) differs per user, so there's no single cached copy to serve — it would require per-user cache keys, which defeats most of the shared-caching benefit and isn't how CDNs are typically used.

**7. Redis supports persistence and Memcached doesn't — when does that actually matter for a "cache"?**
It matters when the cached data is expensive enough to regenerate, or the store is being used for more than pure caching (e.g., as a lightweight primary store for session data or counters) — persistence means a restart doesn't wipe everything and force a stampede of cache misses across the whole dataset at once.

**8. What's the difference between a TTL and an eviction policy like LRU?**
TTL is a correctness/staleness bound — an entry is treated as invalid once its time is up, regardless of memory pressure. LRU is a capacity management policy — it decides what to remove *when the cache is full*, regardless of whether entries have expired. They're usually used together: TTL controls freshness, LRU controls what fits.
