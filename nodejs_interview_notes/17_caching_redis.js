/*
===============================================================================================
                              CACHING & REDIS
===============================================================================================
My Rails caching notes (cache strategies, Redis, invalidation) apply almost unchanged — Redis
is Redis. This file focuses on the Node specifics (ioredis client, patterns in Express).
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: Why cache, and what to cache
-----------------------------------------------------------------------------------------------
Answer -> Caching stores the result of an expensive operation so future requests are served
fast from memory instead of recomputing/refetching. Cache when data is READ far more than
written and is expensive to produce:
  - DB query results (hot rows, expensive aggregations)
  - Computed/derived data
  - Third-party API responses (with respect to their freshness)
  - Sessions, rate-limit counters, feature flags

  Don't cache: highly volatile data, per-request unique data, or anything where staleness is
  unacceptable without a solid invalidation plan.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: Where caches live (in-process vs Redis)
-----------------------------------------------------------------------------------------------
Answer ->
  IN-PROCESS (node-cache, an in-memory Map/LRU):
    - Fastest (no network hop), simplest.
    - BUT: not shared across instances, lost on restart, duplicated per process. With cluster/
      multiple pods each has its OWN cache -> inconsistency. Memory counts against the process.
    - Good for tiny, stable, per-instance data (config, compiled templates).

  REDIS (shared, out-of-process):
    - Shared across ALL app instances -> consistent. Survives app restarts. Huge capacity.
    - Tiny network latency, but worth it for correctness at scale. THE default for real apps.
    - Same Redis you use for BullMQ and sessions.

  Many systems do BOTH (multi-layer): a small in-process L1 cache in front of a Redis L2.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: Redis client in Node (ioredis)
-----------------------------------------------------------------------------------------------
Answer ->
  const Redis = require('ioredis');
  const redis = new Redis(process.env.REDIS_URL);   // reuse this ONE client app-wide

  await redis.set('user:42', JSON.stringify(user), 'EX', 3600);  // value + TTL of 3600s
  const cached = await redis.get('user:42');                      // string or null
  const user = cached ? JSON.parse(cached) : null;
  await redis.del('user:42');                                     // invalidate
  await redis.incr('rate:ip:1.2.3.4');                            // atomic counter (rate limit)
  await redis.expire('rate:ip:1.2.3.4', 60);

  ioredis vs node-redis: both are fine; ioredis is popular for cluster support + a nice API and
  is what BullMQ uses. Reuse a single client; don't open one per request.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: The cache-aside (lazy) pattern — the one you'll write most
-----------------------------------------------------------------------------------------------
Answer -> The app checks the cache first; on a MISS it loads from the DB and populates the
cache. (Same as Rails.fetch with a block.)

  async function getUser(id) {
    const key = `user:${id}`;
    const cached = await redis.get(key);
    if (cached) return JSON.parse(cached);          // HIT

    const user = await db.users.findById(id);        // MISS -> load source of truth
    if (user) await redis.set(key, JSON.stringify(user), 'EX', 3600);  // populate with TTL
    return user;
  }

  // reusable helper (the Rails.cache.fetch equivalent)
  async function cacheFetch(key, ttl, loader) {
    const hit = await redis.get(key);
    if (hit) return JSON.parse(hit);
    const value = await loader();
    await redis.set(key, JSON.stringify(value), 'EX', ttl);
    return value;
  }
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Other caching strategies (name them)
-----------------------------------------------------------------------------------------------
Answer ->
  - Cache-aside (lazy loading): app manages cache; load on miss. Most common. (above)
  - Write-through: write to cache AND DB on every write -> cache always fresh, slower writes.
  - Write-behind (write-back): write to cache now, async flush to DB later -> fast, risk of loss.
  - Read-through: the cache layer itself loads from DB on miss (library/proxy does it).
  - HTTP caching: ETag / Last-Modified / Cache-Control for GET responses (browser/CDN caches).

  For most APIs: cache-aside in Redis + HTTP caching headers on cacheable GETs.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Cache invalidation — "one of the two hard problems"
-----------------------------------------------------------------------------------------------
Answer -> Stale data is the danger. Strategies:
  - TTL (expiry): simplest — let entries expire (EX seconds). Accept brief staleness.
  - Explicit invalidation: on write, delete/refresh the affected keys.
      await db.users.update(...); await redis.del(`user:${id}`);
  - Versioned/namespaced keys: bump a version to invalidate a whole group without scanning
      (e.g. key `user:${id}:v${userListVersion}`).
  - Event-driven: publish a change event; subscribers evict. (Redis pub/sub.)

  Hard cases: invalidating LIST/aggregate caches when one item changes (use short TTLs or
  version namespaces). Always ask "what's my staleness tolerance?" — it drives the strategy.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Cache pitfalls (interview-worthy depth)
-----------------------------------------------------------------------------------------------
Answer ->
  - CACHE STAMPEDE / dogpile: a hot key expires and 1000 concurrent requests all MISS and hit
    the DB at once. Fixes: a lock/mutex so only one request rebuilds it (others wait), "stale-
    while-revalidate" (serve stale while one refreshes), or randomized/jittered TTLs.
  - THUNDERING HERD at startup: warm critical caches on deploy.
  - CACHE PENETRATION: requests for keys that don't exist always miss and hit the DB. Cache the
    "not found" (a short-TTL null) or use a bloom filter.
  - Stale data after writes: pair every write with an invalidation.
  - Memory/eviction: set maxmemory + an eviction policy (allkeys-lru) so Redis doesn't OOM.
  - Serialization cost: JSON.stringify/parse on huge objects is CPU on the event loop — keep
    cached values reasonably sized.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: Redis is more than a cache (mention this breadth)
-----------------------------------------------------------------------------------------------
Answer -> In a Node stack, the same Redis often powers:
  - Caching (this file)
  - Background job queue (BullMQ, file 16)
  - Session store (express-session + connect-redis)
  - Rate limiting (atomic INCR + EXPIRE, or express-rate-limit's Redis store)
  - Pub/Sub (real-time fan-out; scaling Socket.io across instances — file 24)
  - Distributed locks, leaderboards (sorted sets), feature flags

  "One Redis, many roles" is exactly how I used it in Rails (cache + Sidekiq) — same here.
*/

module.exports = {};
