# Design an API Rate Limiter

## Problem Statement

"Our public API is getting hammered — a handful of misbehaving clients (and
occasionally a bot attack) are sending far more requests than any reasonable
client should, and it's degrading service for everyone else. Design a rate
limiter that sits in front of our API and throttles clients that exceed a
configured request quota, without becoming a bottleneck itself and without
letting one gateway instance's local counter be trivially bypassed by
spreading requests across instances."

This is asked both as a standalone system ("design a rate limiter like the
one AWS API Gateway or Stripe offers") and as a component embedded inside
bigger designs (any high-traffic API you're asked to design will eventually
need one).

## Step 1: Clarify Requirements

**Functional Requirements**
- Limit the number of requests a client can make within a defined time
  window (e.g., 100 requests/minute).
- Support multiple, independently configurable limiting rules — per user,
  per IP address, per API key, and per endpoint (a `/login` endpoint needs a
  much stricter limit than a `/search` endpoint).
- When a client exceeds its limit, reject the request with a clear signal
  (HTTP 429) and tell the client when it can retry.
- Limits must be configurable without a full redeploy (product/ops teams
  change quotas frequently — new pricing tiers, abuse response, etc.).

**Non-Functional Requirements**
- **Accuracy vs. performance trade-off**: the limiter doesn't need to be
  perfectly precise (allowing a client to sneak through a few extra requests
  at a boundary is acceptable) but it must never be wildly wrong in a way
  that lets an attacker bypass it entirely.
- **Latency**: the rate-limiting check itself must add negligible overhead
  to every single API request — sub-millisecond to a few milliseconds,
  since it sits on the hot path of 100% of traffic, not just a fraction.
- **Availability**: the limiter must not become a single point of failure
  for the entire API — if the limiter's own storage is unreachable, the API
  should have a defined, deliberate fallback behavior (see fail-open/closed
  in Step 6.4), not just crash.
- **Distributed correctness**: the limit must hold correctly across a fleet
  of many gateway/service instances handling the same client's traffic
  concurrently — a per-instance in-memory counter is not acceptable because
  it lets a client's effective limit scale with however many instances
  happen to receive its requests.
- **Scale**: must handle very high aggregate request volume (we'll size for
  500,000 requests/sec across the whole fleet in Step 2) while keeping
  per-request overhead low.

## Step 2: Back-of-Envelope Estimation

**Assumptions**: an API platform serving 50,000 active API keys, with a
typical client capped at 100 requests/minute and average utilization at
about 30% of the cap, plus overall platform traffic (including higher-tier
clients) totaling 500,000 requests/sec at peak.

**Rate-limit check throughput**
- Every one of the 500,000 requests/sec must pass through the rate-limit
  check, since the check gates the request before it's processed — so the
  limiter's own storage layer must sustain at least 500,000 reads +
  500,000 writes/sec (checking and incrementing a counter), i.e. roughly
  1,000,000 ops/sec.
- A single Redis instance comfortably handles 100,000-200,000 simple
  ops/sec; to hit 1,000,000 ops/sec we need a **sharded Redis cluster**,
  roughly 6-10 shards assuming even key distribution (Redis Cluster or
  client-side sharding by hashing the rate-limit key).

**Storage size**
- Each active rate-limit counter entry: a key (e.g.,
  `ratelimit:user:12345:endpoint:/search`, ~40 bytes) plus a small value
  (an integer counter or a short list of timestamps, 8-64 bytes depending
  on algorithm) plus Redis's per-key overhead (~50-100 bytes) ≈ roughly
  150-250 bytes per active limiter key.
- With 50,000 API keys x an average of ~5 distinct endpoints each tracked
  separately = 250,000 active keys, at ~200 bytes each ≈ 50 MB. Even at 10x
  that scale (2.5M active keys for a much larger platform), storage stays
  under 1 GB — rate-limit counter state is small; the bottleneck is always
  **ops/sec**, not storage volume.
- Counters expire (TTL'd) shortly after their window closes, so this
  storage footprint doesn't grow unbounded — it reflects only the
  currently-active window, not historical data.

**Bandwidth**
- Each check is a tiny Redis command (a Lua script call or `INCR` +
  `EXPIRE`), request+response on the order of 100-200 bytes.
- 1,000,000 ops/sec x ~150 bytes ≈ 150 MB/sec of internal traffic between
  gateway instances and the Redis cluster — trivial for a datacenter-local
  network, but it does mean the Redis cluster needs to sit close
  (low-latency) to the gateways, not across a WAN link.

## Step 3: High-Level Design

The rate limiter is best implemented as **middleware at the API
gateway layer**, checked before a request is routed to any backend service,
backed by a **shared, distributed counter store** (Redis) so every gateway
instance sees the same up-to-date count for a given client.

```text
                                +------------------------+
                                |   Rate Limit Rules      |
                                |   Config Store          |
                                |  (per-user/IP/key/      |
                                |   endpoint limits)       |
                                +-----------+--------------+
                                            | (read/watch)
                                            v
Client --> [ Load Balancer ] --> +----------------------+
                                  |   API Gateway (N      |
                                  |   instances)           |
                                  |                        |
                                  |  1. extract client key  |
                                  |     (user/IP/API key)   |
                                  |  2. check + incr count  |----+
                                  |     against shared store|    |
                                  |  3. allow -> forward     |    |
                                  |     deny  -> 429          |    |
                                  +-----------+--------------+    |
                                              | (allowed)          |
                                              v                    v
                                    +------------------+   +----------------+
                                    |  Backend Services |   |  Redis Cluster  |
                                    |  (business logic)  |   |  (shared counter|
                                    +------------------+   |   state, sharded)|
                                                            +----------------+
```

Key architectural decision: the counter state lives in a **shared store
external to every gateway instance**, not in each instance's local memory —
this is what makes the limit correct regardless of which instance(s) handle
a given client's requests, and regardless of how many gateway instances are
running.

## Step 4: API Design

The rate limiter is usually not a client-facing API in itself — it's
middleware — but it exposes a few operational interfaces.

**Effective interface for every API request (via response headers), e.g. `GET /v1/search?q=...`**
```
Response headers on success:
  X-RateLimit-Limit: 100
  X-RateLimit-Remaining: 37
  X-RateLimit-Reset: 1757740860   (unix timestamp when the window resets)

Response on limit exceeded:
  HTTP/1.1 429 Too Many Requests
  Retry-After: 23                 (seconds until the client should retry)
  { "error": "rate_limit_exceeded", "retry_after_seconds": 23 }
```

**Internal check, called by gateway middleware on every request**
```
check_and_increment(key: "user:12345:endpoint:/search", limit: 100, window_sec: 60)
  -> { allowed: true, remaining: 37, reset_at: 1757740860 }
```

**`PUT /admin/v1/rate-limit-rules/{rule_id}` (config management, low volume)**
```json
Request: {
  "match": { "endpoint": "/login", "tier": "free" },
  "limit": 5,
  "window_seconds": 60
}
Response: { "rule_id": "r-882", "status": "active" }
```

**`GET /admin/v1/rate-limit-status/{client_key}` (ops/debugging, low volume)**
```json
Response: {
  "client_key": "user:12345",
  "endpoints": [
    { "endpoint": "/search", "current_count": 63, "limit": 100, "resets_in_sec": 41 }
  ]
}
```

## Step 5: Data Model

The core state is a **cache/key-value store (Redis)**, not a SQL or
document database, because rate-limit counters are exactly the shape
Redis is built for: high-frequency atomic increments, native per-key TTLs
(so old windows expire automatically without a cleanup job), and sub-
millisecond in-memory access. A relational database would add unacceptable
per-request latency and would need a manual expiry/cleanup process; a
general document store lacks the atomic increment + TTL primitives that
make the check race-free (see Step 6.3).

**Token bucket, stored as a Redis hash:**
```
Key:   ratelimit:bucket:{client_key}:{endpoint}
Value: { tokens: 42, last_refill_ts: 1757740800123 }
TTL:   refreshed on each access, expires after a period of inactivity
```

**Sliding window counter, stored as a Redis string with TTL, or a sorted set:**
```
# Fixed-window-with-smoothing variant (single counter + previous window read):
Key:   ratelimit:window:{client_key}:{endpoint}:{current_minute_bucket}
Value: 63                              (INCR'd atomically)
TTL:   120 seconds (2x window, so the previous window's value is still
                     readable for the sliding calculation)

# Sliding-log variant (sorted set of individual request timestamps):
Key:    ratelimit:log:{client_key}:{endpoint}
Value:  ZSET of { score: request_timestamp_ms, member: unique_request_id }
TTL:    window_seconds
```

**Rule configuration** (low write volume, read-heavy, cached aggressively in
each gateway instance's local memory and refreshed periodically) fits a
regular **SQL table** (or a config service) since it's small, relational
("this rule applies to this tier + this endpoint"), and doesn't need
Redis's raw throughput:
```sql
CREATE TABLE rate_limit_rules (
  id            BIGINT PRIMARY KEY,
  match_tier    VARCHAR(50),
  match_endpoint VARCHAR(255),
  limit_count   INT,
  window_seconds INT,
  updated_at    TIMESTAMP
);
```

## Step 6: Deep Dive

### 6.1 Where to enforce the limit

- **Client SDK**: the client library self-throttles before even sending a
  request. Reduces wasted network round trips for well-behaved clients, but
  provides **zero actual protection** — a malicious or buggy client simply
  doesn't use the SDK, or patches around it. Useful only as a courtesy
  layer on top of real enforcement, never as the enforcement itself.
- **API Gateway (the standard answer)**: enforced centrally, before a
  request reaches any backend service. Every request from every client
  passes through it, so it's the one place a limit is guaranteed to be
  checked regardless of client behavior. This is also the natural place to
  put it operationally — gateways already terminate auth and TLS, so
  extracting the client identity (user ID, API key, IP) needed to key the
  limiter is already happening there.
- **Individual service**: enforcing at each backend service gives the most
  fine-grained control (a service can protect itself specifically, e.g., a
  "search" service limiting expensive queries independent of general API
  traffic) but means every service reimplements limiting logic and talks
  to the shared counter store separately, multiplying the number of
  network hops to Redis and the operational surface area. In practice,
  most systems do **both**: coarse-grained limiting at the gateway (cheap,
  catches most abuse early) plus a stricter, resource-aware limit inside
  specific expensive services (e.g., a search or ML-inference endpoint that
  needs a much lower ceiling than generic CRUD endpoints).

### 6.2 Algorithm choice: token bucket vs. sliding window counter

**Token bucket**
- Each client has a "bucket" that holds up to `capacity` tokens (e.g., 100).
  Tokens refill at a steady `refill_rate` (e.g., 100 tokens/60 sec ≈ 1.67
  tokens/sec). Every request consumes one token; if the bucket is empty,
  the request is rejected.
- **Redis implementation**: store `{tokens, last_refill_timestamp}` per
  client key. On each request: compute `elapsed = now - last_refill_timestamp`,
  add `elapsed * refill_rate` tokens (capped at `capacity`), then check if
  `tokens >= 1` — if so, decrement and allow; if not, reject. This "lazy
  refill" approach (compute the refill amount on read rather than running a
  background timer) avoids needing a scheduled job per client.
- **Why it's popular**: naturally allows short bursts up to the bucket
  capacity (a client that's been idle can suddenly send `capacity` requests
  at once, which matches real client behavior — e.g., a page load firing
  several API calls simultaneously) while still enforcing a steady average
  rate over time. This burst tolerance is usually a feature, not a bug.

**Sliding window counter**
- Two flavors:
  - **Sliding log**: store the timestamp of every individual request in a
    Redis sorted set (`ZADD`), and on each check, `ZREMRANGEBYSCORE` to
    drop entries older than the window, then `ZCARD` to count what's left.
    Perfectly precise (exact count of requests in the trailing window) but
    the most memory- and CPU-expensive — storage grows with request volume
    within the window, not just with client count.
  - **Sliding window with weighted counts (the common production
    approach)**: keep two fixed-window counters — the current window's
    count and the previous window's count — and estimate the sliding count
    as `previous_window_count * (overlap_fraction) + current_window_count`,
    where `overlap_fraction` is how much of the previous window still
    falls within the trailing N seconds from now. This is an approximation
    (assumes uniform distribution of requests within the previous window)
    but is far cheaper than the sliding log: just two `INCR`-able integers
    per client instead of a growing set.
- **Why it matters over naive fixed windows**: a naive fixed window (reset
  the counter every 60 seconds on the clock) allows a client to send
  `limit` requests right before a window boundary and another `limit`
  requests right after — effectively `2x limit` within a short span
  straddling the boundary. The sliding approaches close this gap.
- **Practical choice**: token bucket is generally preferred when
  burst-tolerance is desirable (most public APIs); the weighted sliding
  window counter is preferred when precise, smooth rate enforcement matters
  more than burst allowance (e.g., protecting a fragile downstream
  resource that truly cannot handle any burst). Both are far more common in
  production than the sliding log, because of the memory cost difference.

### 6.3 Correctness across distributed gateway instances

A single in-memory counter per gateway instance is fundamentally broken in
a distributed deployment: if a client's requests get load-balanced across
10 gateway instances, and each instance independently enforces "100
requests/minute" using its own local counter, the client can actually
achieve 10 x 100 = 1,000 requests/minute by spreading requests evenly —
the limit is bypassed by simply not concentrating traffic on one instance.

- **The fix**: all gateway instances share a single external counter store
  (Redis), so "check and increment" happens against one shared value
  regardless of which instance handles the request.
- **The race condition this introduces**: if "check the current count" and
  "increment the count" are two separate Redis calls, two concurrent
  requests from the same client, handled by two different gateway
  instances at the same instant, can both read `count = 99` (limit 100),
  both conclude "allowed," and both increment — letting 101 requests
  through instead of 100. This is a classic check-then-act race condition.
- **Fix 1 — atomic `INCR` with `EXPIRE`**: for the fixed/sliding-window-
  counter approach, use Redis's `INCR` (which is atomic by itself) to bump
  the counter and compare the *returned* value against the limit, rather
  than reading first and incrementing second:
  ```
  count = INCR(key)
  if count == 1: EXPIRE(key, window_seconds)   # set TTL only on first increment
  if count > limit: reject
  else: allow
  ```
  This works because `INCR` atomically returns the post-increment value —
  there's no separate read step to race on. The `EXPIRE` on first increment
  needs its own care (a crash between `INCR` and `EXPIRE` could leave a key
  with no TTL); the standard fix is to wrap both in a single Lua script.
- **Fix 2 — Lua script for compound operations (needed for token bucket)**:
  the token bucket algorithm requires reading the current token count,
  computing the refill, checking against `capacity`, and conditionally
  decrementing — multiple steps that must happen atomically or the same
  race reappears. Redis executes a Lua script as a single atomic operation
  (no other client's commands can interleave mid-script), so the entire
  "read tokens, compute refill, check, decrement" sequence is sent as one
  `EVAL` call and Redis guarantees it runs start-to-finish without
  interruption. This is the standard production pattern for token bucket
  in Redis.
- **Why not a distributed lock instead?** A lock (e.g., via Redlock) around
  the check-then-act sequence would also fix the race, but it's strictly
  worse here: it adds lock-acquire/release round trips to every single
  request on the hot path, whereas a Lua script achieves the same
  atomicity in one round trip with no lock contention or lock-timeout
  failure modes to reason about.

### 6.4 Rate-limiting keys and differentiated limits

- **Per-user**: the most common key for authenticated APIs — ties the
  limit to a logged-in identity regardless of which device or IP they use.
  Requires the request to already be authenticated before the rate check
  (or the check happens after auth in the middleware chain).
- **Per-IP address**: necessary for unauthenticated endpoints (login,
  signup, password reset) where there's no user identity yet to key on.
  Weaker signal — many real users can share an IP (corporate NAT, mobile
  carrier NAT), so IP-based limits must be more generous than user-based
  ones to avoid collateral throttling of innocent users behind a shared IP.
- **Per-API-key**: standard for B2B/developer-platform APIs, where the key
  also encodes the client's pricing tier (free tier: 100 req/min, paid
  tier: 10,000 req/min) — the rule lookup joins the API key to its tier to
  pick the applicable limit.
- **Per-endpoint**: limits should differ sharply by cost/sensitivity — a
  cheap, cacheable `GET /products/{id}` might allow 1,000 req/min, while an
  expensive `POST /search` or a security-sensitive `POST /login` (target
  for credential-stuffing attacks) might be capped at 5-20 req/min.
- **Composite keys in practice**: real systems combine dimensions, e.g. the
  key is literally `{api_key}:{endpoint}:{window}`, so a client's `/search`
  quota and `/login` quota are tracked and enforced completely
  independently, per the rule table in Step 5.

### 6.5 Response contract and fail-open vs. fail-closed

- **HTTP 429 Too Many Requests** is the correct status code (not 403, which
  implies a permissions problem, or 503, which implies the server itself is
  down) — it specifically communicates "you, this client, have sent too
  many requests," which lets client-side logic distinguish "back off and
  retry" from "something is broken, don't retry."
- **`Retry-After` header**: tells the client exactly how many seconds (or
  an HTTP-date) to wait before retrying, computed from the window's reset
  time. Well-behaved clients (and most HTTP libraries) respect this
  automatically, which reduces the retry storm that would otherwise happen
  if every throttled client immediately retried in a tight loop.
- **Fail-open vs. fail-closed when Redis is unreachable**: this is a
  genuine, deliberate trade-off, not an oversight to fix.
  - **Fail open** (let all requests through when the limiter's storage is
    down): protects overall API availability — a Redis outage doesn't take
    down the entire API — at the cost of losing abuse protection exactly
    when you might need it (e.g., if the Redis outage was itself triggered
    by an attack). Most general-purpose consumer APIs choose this, because
    total API unavailability is worse than temporarily unlimited access.
  - **Fail closed** (reject all requests when the limiter's storage is
    down): protects backend systems from being overwhelmed at all costs,
    at the cost of the rate limiter becoming a new single point of failure
    for the entire API — a Redis blip now means a full outage. Chosen for
    endpoints protecting a fragile or expensive downstream resource where
    unlimited traffic would cause worse damage than temporary unavailability
    (e.g., an endpoint that triggers an expensive ML inference or a
    third-party paid API call).
  - Many production systems fail open for general traffic but fail closed
    for a short list of specifically fragile/expensive endpoints —
    configured per-rule, not system-wide.

## Step 7: Bottlenecks & Trade-offs

- **Redis as a shared dependency**: every request now has an extra network
  hop to Redis on the hot path. At high scale this hop's latency (typically
  sub-millisecond to a few ms within a datacenter) is added to every single
  API call, and Redis itself must be sharded (Step 2) to keep up with
  aggregate ops/sec — a single Redis instance will become the first thing
  to break under this design as traffic grows past what one instance can
  handle.
- **Hot-key contention**: a single very-high-traffic client (or a coarse
  key like "per-IP" behind a large NAT) concentrates enormous request
  volume onto one Redis key, which can become a hot shard within the Redis
  cluster even though the cluster's aggregate capacity is fine — mitigated
  by choosing keys with enough cardinality (e.g., combining IP with a
  secondary dimension) or, for genuinely extreme cases, approximating the
  count locally per-gateway-instance with periodic reconciliation instead
  of a fully synchronous shared counter.
- **Accuracy vs. cost trade-off, revisited**: the weighted sliding-window
  approximation (Step 6.2) can be off by a bounded margin near window
  boundaries under non-uniform traffic — accepted because true precision
  (sliding log) costs far more in memory and Redis CPU at scale, and
  perfect precision isn't actually a functional requirement (Step 1).
- **Fail-open/fail-closed trade-off, revisited**: whichever is chosen sets
  a ceiling — fail-open caps the guarantee of abuse protection at "as long
  as Redis is up," fail-closed caps the guarantee of API availability at
  the same thing. There's no configuration that avoids this trade-off
  entirely; only which failure mode is more acceptable per endpoint.
- **Clock skew between gateway instances**: token-bucket refill math and
  fixed-window boundaries both depend on `now()` — meaningful clock drift
  across gateway instances can cause small inconsistencies in effective
  limits, though this is a much softer problem than the Snowflake ID
  generator's clock-backwards issue, since a rate limiter being briefly a
  few requests too generous or strict is not a correctness catastrophe.

## Follow-up Questions an Interviewer Might Ask

- **"How would you rate-limit at a CDN/edge layer, before traffic even
  reaches your datacenter?"** Push a coarser, cheaper first-pass limit to
  edge nodes (e.g., Cloudflare Workers or a similar edge runtime) using
  local, eventually-consistent counters synced periodically — accept looser
  accuracy at the edge in exchange for blocking obvious abuse (e.g., a
  volumetric attack) before it consumes any origin bandwidth, then apply
  the precise, Redis-backed limit once traffic reaches the gateway.
- **"What if an attacker rotates through thousands of IPs or API keys to
  dodge the limit?"** Layer in a secondary, coarser limit keyed on a more
  attacker-resistant signal (device fingerprint, TLS fingerprint, behavioral
  anomaly score) in addition to the primary per-key limit, and feed
  suspicious patterns into a separate abuse-detection pipeline rather than
  trying to solve it purely with per-key rate limiting.
- **"How do you let a legitimate client burst above their limit
  temporarily (e.g., a batch import job)?"** Expose an explicit, time-boxed
  quota-increase mechanism (an admin API or self-service "request a burst
  window" feature) that temporarily rewrites that client's rule in the
  config store rather than trying to infer legitimate bursts automatically
  from traffic shape.
- **"How would this design change for a globally distributed, multi-region
  deployment?"** A single global Redis cluster across regions adds
  cross-region latency to every check; the common approach is per-region
  Redis clusters with a slightly higher regional limit (total limit split
  or slightly overallocated across regions) rather than a strongly
  consistent global counter, trading perfect global accuracy for regional
  low latency — consistent with the CAP-theorem trade-offs.
- **"How would you test that the limiter is actually correct under
  concurrency?"** Load-test with concurrent requests from a single client
  identity issued simultaneously from many gateway instances/threads and
  verify the accepted count never exceeds the configured limit by more than
  the algorithm's known bounded error margin — this specifically exercises
  the race condition described in Step 6.3.
- **"Should rate limit rule changes require a redeploy?"** No — rules
  should live in a config store or database the gateway polls or
  subscribes to (e.g., watching a key in etcd/Redis, or polling a rules
  table every few seconds), with each gateway instance caching the current
  rules locally to avoid a config lookup on every single request.
