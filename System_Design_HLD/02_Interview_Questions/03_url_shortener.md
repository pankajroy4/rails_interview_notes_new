# Design a URL Shortener (bit.ly / TinyURL)

## Problem Statement

"Design a service like bit.ly: a user submits a long URL and gets back a
short one (e.g., `short.ly/aZ9kLp`); visiting the short URL redirects the
browser to the original long URL. Support custom aliases, and assume the
system will be read-heavy — far more people click short links than create
them. Design it end to end: the short-code generation strategy, the
redirect path, and how you'd keep redirects fast at scale."

This is one of the most commonly asked system design questions precisely
because it looks simple but has several genuinely non-obvious decisions
hiding in it (code generation strategy, 301 vs 302, read-heavy caching).

## Step 1: Clarify Requirements

**Functional Requirements**
- Given a long URL, generate a unique short URL (short code) and store the
  mapping.
- Given a short URL, redirect the client to the original long URL.
- Support user-specified **custom aliases** (e.g.,
  `short.ly/my-conference-talk`) in addition to system-generated codes.
- Support link **expiration** (a link stops resolving after a configured
  date, or after N uses, depending on the plan/feature).
- Track basic click analytics (click count, referrer, timestamp) per short
  link — commonly a paid/pro feature, and it directly affects whether we
  can use HTTP 301 redirects (see Step 6.2).

**Non-Functional Requirements**
- **Read:write ratio is heavily skewed toward reads.** Link creation is
  rare relative to link clicks — a link created once might be clicked
  thousands of times. We'll quantify this in Step 2, and it's the single
  biggest driver of the caching and redirect-status-code decisions in
  Step 6.
- **Redirect latency**: clicking a short link should feel instantaneous —
  target well under 100ms server-side processing time, since the redirect
  is on the critical path of the user's actual destination.
- **Availability over strict consistency for redirects**: if the system is
  briefly inconsistent (a very recently created link takes a few seconds to
  propagate to all caches), that's acceptable; a redirect service being
  *down* is not — broken links erode trust immediately and are highly
  visible (shared on social media, printed on physical materials).
  Availability is prioritized over strong consistency here (an AP choice).
- **Uniqueness**: two different long URLs must never accidentally map to
  the same short code, and code generation must not require heavy
  coordination that slows down link creation at scale.
- **Short code length**: should be as short as practical (fewer characters
  = more shareable, prints better, fits in SMS/social character limits)
  while providing enough keyspace to avoid running out for years.

## Step 2: Back-of-Envelope Estimation

**Assumptions**: 100 million new short URLs created per month; a
conservative 100:1 read:write ratio (each link is clicked 100 times on
average over its life, and clicks are naturally spread out, but concentrate
early).

**Write (creation) QPS**
- 100,000,000 / (30 days x 86,400 sec) ≈ 38.6 creations/sec average.
- Even with a generous 5x peak multiplier for launch-day traffic spikes,
  that's under 200 creations/sec — a trivially low write load for any
  reasonable single write path.

**Read (redirect) QPS**
- 100:1 ratio -> 100,000,000 x 100 = 10,000,000,000 redirects/month.
- 10,000,000,000 / (30 x 86,400) ≈ 3,858 redirects/sec average.
- At a 3x peak multiplier (redirect traffic spikes align with real-world
  events — a viral link, a marketing campaign): ≈ 11,574 redirects/sec
  peak. This read load, not the write load, is what the architecture must
  be built to absorb — confirming the read-heavy skew called out in Step 1.

**Storage**
- Each URL mapping record: short_code (7 bytes) + long_url (avg ~100
  bytes, URLs can be much longer but this is a reasonable average) + user_id
  (8 bytes) + created_at/expires_at (16 bytes) + metadata ≈ 200 bytes/row.
- 100M new rows/month x 200 bytes ≈ 20 GB/month.
- Over 5 years: 20 GB x 60 months = 1.2 TB. Entirely manageable for a
  sharded relational or key-value store, and small enough that most of the
  *hot* subset can live in cache (see Step 6.4).

**Keyspace sizing (drives short code length — see Step 6.1)**
- Base62 alphabet (a-z, A-Z, 0-9) = 62 symbols.
- 7 characters: 62^7 ≈ 3.52 trillion unique codes — at 100M new codes/month
  (1.2B/year), this keyspace lasts roughly 2,900+ years before exhaustion,
  comfortable headroom. 6 characters (62^6 ≈ 56.8 billion) would still last
  ~47 years at this rate, so 6-7 characters is the right ballpark; most real
  systems land here for exactly this reason.

**Bandwidth**
- Redirect response is tiny (an HTTP 301/302 with a `Location` header, no
  body needed) — maybe 300-500 bytes including headers.
- 11,574 redirects/sec x ~400 bytes ≈ 4.6 MB/sec at peak — negligible
  network load; the bottleneck is request *rate* (connection handling,
  lookup latency), not payload bandwidth.

## Step 3: High-Level Design

```text
                         +----------------------+
      Create flow        |     API Gateway /      |
   User -> POST /shorten ->    Load Balancer       |
                         +-----------+------------+
                                     |
                                     v
                         +----------------------+
                         |   URL Shortening       |
                         |   Service               |
                         |  - validate long URL     |
                         |  - generate/reserve       |
                         |    short code (Step 6.1)  |
                         |  - write mapping           |
                         +-----+---------------+----+
                               |                |
                               v                v
                  +--------------------+   +------------------+
                  |  Primary Datastore  |   |  Key-Generation   |
                  |  (short_code ->     |   |  Service (KGS) /   |
                  |   long_url mapping) |   |  pre-generated code|
                  |  sharded by         |   |  range pool         |
                  |  short_code hash    |   +------------------+
                  +--------------------+

                         Redirect flow (the hot path)
      User clicks short.ly/aZ9kLp
              |
              v
     +------------------+     cache hit (>90% of traffic)
     |   CDN / Edge       | ------------------------------+
     |   Cache (optional)  |                                |
     +--------+-----------+                                |
              | cache miss                                  |
              v                                              v
     +------------------+        +------------------+   +----------+
     |  Redirect Service  |  -->  |  Redis Cache      |   |  Browser  |
     |  (stateless,        |      |  (short_code ->    |-->  gets     |
     |   horizontally      |<-----|   long_url, hot     |   302/301  |
     |   scaled)            |      |   keys)             |   response |
     +--------+-----------+        +------------------+   +----------+
              | cache miss (rare)
              v
     +------------------+
     |  Primary Datastore |
     +------------------+
     (async: click event -> analytics pipeline / message queue)
```

The creation and redirect paths are deliberately drawn as separate
services that can be scaled independently — creation is low-QPS and can
tolerate more latency (it's a one-time user action); redirects are
high-QPS and latency-critical, so the redirect service is kept minimal
(cache lookup, then a 3xx response) with everything non-essential (click
analytics) pushed off the critical path onto an async queue.

## Step 4: API Design

**`POST /api/v1/shorten` — create a short URL**
```json
Request: {
  "long_url": "https://example.com/some/very/long/path?with=params",
  "custom_alias": "my-conference-talk",   // optional
  "expires_at": "2027-01-01T00:00:00Z"     // optional
}
Response: {
  "short_url": "https://short.ly/my-conference-talk",
  "short_code": "my-conference-talk",
  "long_url": "https://example.com/some/very/long/path?with=params",
  "created_at": "2026-09-13T10:00:00Z",
  "expires_at": "2027-01-01T00:00:00Z"
}
Errors: 409 Conflict if custom_alias is already taken.
```

**`GET /{short_code}` — redirect (the hot path)**
```
Request:  GET /aZ9kLp
Response: HTTP/1.1 301 Moved Permanently   (or 302, see Step 6.2)
          Location: https://example.com/some/very/long/path?with=params
```

**`GET /api/v1/urls/{short_code}` — fetch metadata (dashboard use, not the redirect path)**
```json
Response: {
  "short_code": "aZ9kLp",
  "long_url": "https://example.com/...",
  "click_count": 1523,
  "created_at": "2026-09-13T10:00:00Z",
  "is_expired": false
}
```

**`DELETE /api/v1/urls/{short_code}` — disable a short link**
```json
Response: { "short_code": "aZ9kLp", "status": "deactivated" }
```

**`GET /api/v1/urls/{short_code}/analytics` — click analytics**
```json
Response: {
  "short_code": "aZ9kLp",
  "total_clicks": 1523,
  "clicks_by_day": [{ "date": "2026-09-12", "count": 210 }, "..."],
  "top_referrers": [{ "referrer": "twitter.com", "count": 480 }]
}
```

## Step 5: Data Model

The core mapping is a simple key-value lookup by short_code — this maps
naturally to a **NoSQL key-value store or a sharded relational table**
keyed on `short_code` (the access pattern is always "look up by exact
short_code," never a range scan or complex join), fronted by a **cache**
(Redis) for the hot redirect path, since redirects need sub-millisecond
lookups at high QPS that a database alone, even a fast one, adds
unnecessary latency and load to.

**Primary mapping table (SQL, sharded by hash of short_code, or a NoSQL
KV store like DynamoDB/Cassandra — either works; SQL is shown for clarity
and gives easy custom-alias uniqueness constraints):**
```sql
CREATE TABLE url_mappings (
  short_code   VARCHAR(10) PRIMARY KEY,
  long_url     TEXT NOT NULL,
  user_id      BIGINT,
  created_at   TIMESTAMP,
  expires_at   TIMESTAMP NULL,
  is_custom_alias BOOLEAN DEFAULT FALSE,
  is_active    BOOLEAN DEFAULT TRUE
);
-- shard key: hash(short_code) -> shard N
```

**Cache layer (Redis), the actual lookup path for 90%+ of redirects:**
```
Key:   redirect:{short_code}
Value: long_url string (plus is_active/expires_at flags, or a "gone" tombstone)
TTL:   long (e.g., 24h), refreshed on access; short-lived negative-cache
       entries for deleted/expired codes to avoid repeatedly hitting the
       DB for dead links
```

**Click analytics (write-heavy, append-only, time-series shaped)** — a
separate store from the mapping table, since analytics writes (potentially
one per click, at the full 11,574/sec peak redirect rate) would otherwise
contend with the mapping table's read traffic. A **wide-column / time-series
store** (or a message queue feeding into a data warehouse — see
`01_Concepts/12_storage_systems.md` for the warehouse-vs-operational-store
distinction) fits better than piling this onto the relational mapping
table:
```
click_events: { short_code, timestamp, referrer, user_agent, ip_country }
```
Click counts shown to users are usually pre-aggregated periodically (e.g.,
hourly rollups) rather than computed live from raw events on every
analytics page load.

## Step 6: Deep Dive

### 6.1 Short code generation strategies, compared

**Strategy A — Base62 encoding of an auto-incrementing counter**
- A single global counter (or a distributed counter service) hands out
  sequential integers: 1, 2, 3, .... Each integer is encoded into base62
  (0-9, a-z, A-Z) to produce a compact string — e.g., integer 125 encodes
  to a short handful of characters.
- **Pros**: trivially collision-free (the counter never repeats a value);
  codes can be made shorter over time as the counter starts small.
- **Cons**: the counter itself is a centralized, coordinated resource —
  every code-generation request needs to obtain the next value, which
  either means a single database sequence (a bottleneck and single point
  of contention at scale) or a distributed counter service (adds
  complexity, and now you need something like Snowflake-style
  partitioning, see `01_distributed_id_generator.md`, to avoid
  recentralizing the bottleneck). Sequential codes are also
  **predictable/guessable** (code `N+1` is obviously "the next link
  someone created"), which can leak information (e.g., competitor guessing
  how many links a company has created) unless deliberately obfuscated.

**Strategy B — Hash the long URL (e.g., MD5) and take the first N base62 characters**
- Compute `MD5(long_url)`, base62-encode the hash, and take the first 6-7
  characters as the short code.
- **Pros**: no centralized counter needed — any server can compute a code
  independently and deterministically from the input URL, with no
  coordination at all.
- **Cons**: truncating a hash to a handful of characters makes
  **collisions likely** (birthday-paradox math: with a 7-character base62
  truncation, the effective space is ~3.5 trillion, but at 100M+ codes/
  month the collision probability climbs meaningfully over years — and
  more importantly, two different users shortening the *same* long URL
  deterministically get the *same* short code, which may or may not be
  desired behavior). Requires a collision-handling path: on collision,
  append a salt/counter and rehash, retry, and check-then-insert again —
  extra round trips exactly on the write path, and added implementation
  complexity for a case that must be gotten right or you silently
  overwrite someone else's link.

**Strategy C — Pre-generate a keyspace of random codes, hand out ranges to
each server (often the best real-world answer)**
- A background job generates a large batch of random, unique 7-character
  base62 strings ahead of time and stores them in a "available codes" pool
  (a table or queue). Each application server, on startup or when it runs
  low, claims a **contiguous range or batch** of unused codes from this
  pool (e.g., "server A, here are 10,000 codes reserved just for you").
- When a user creates a short URL, the server simply pops the next
  available code from its **locally held batch** — no network round trip,
  no coordination, no risk of collision with another server, because each
  server's batch is disjoint from every other server's batch by
  construction.
- **Pros**: this is the sweet spot — codes are genuinely random
  (non-guessable, unlike Strategy A), there's zero per-request coordination
  (unlike Strategy A's shared counter), and there's zero collision risk or
  retry logic needed (unlike Strategy B's hash truncation), because
  uniqueness was already guaranteed when the pool was generated (checked
  once, centrally, at generation time, not on every request).
- **Cons**: requires a background process to keep the pool replenished
  before servers exhaust their batches (monitor pool depletion rate and
  regenerate proactively); a server that crashes with an unused batch
  "wastes" those codes unless there's a mechanism to reclaim unused ranges
  (usually just accepted as an acceptable loss given the enormous total
  keyspace from Step 2).
- This range-handout approach is directly analogous to how distributed
  primary-key allocation works in some sharded database setups, and is
  generally the answer that demonstrates the deepest understanding in an
  interview, because it explicitly trades a small amount of operational
  complexity (managing the pool) for eliminating coordination from the hot
  path entirely.

**Custom aliases**: bypass code generation entirely — the user supplies
the code directly, and the system just needs to check-and-reserve it
atomically (`INSERT ... ON CONFLICT DO NOTHING` or an equivalent atomic
"insert if absent," to avoid a race where two users grab the same alias
simultaneously) against the primary mapping table.

### 6.2 HTTP 301 vs. 302 — a genuine product trade-off

This is frequently glossed over, but it's one of the most concrete,
decision-worthy details in the whole system.

- **301 Moved Permanently**: tells the browser (and any intermediate
  caches/CDNs) that this redirect is permanent. Browsers **cache the
  redirect locally** — on a repeat visit to the same short link, the
  browser may skip contacting your server entirely and navigate straight
  to the long URL from its own cache.
  - *Benefit*: dramatically reduces load on your redirect service for
    repeat visits to the same link — exactly the kind of savings that
    matters given the 100:1+ read skew from Step 2.
  - *Cost*: you **lose visibility** into those cached repeat visits — if
    the browser never hits your server, you can't log that click, which
    directly undermines the click-analytics functional requirement from
    Step 1. You also lose the ability to ever change where that short code
    points (if you needed to update the destination later, browsers with a
    cached 301 won't re-check).
- **302 Found (temporary redirect)**: tells the browser this redirect might
  change, so **every single click hits your server** — no browser-side
  caching of the redirect target.
  - *Benefit*: complete click visibility (every click is logged), and the
    destination can be changed at any time and takes effect immediately
    for all future clicks.
  - *Cost*: significantly higher load on the redirect service, since the
    301's "free" caching benefit is gone — every one of the ~11,574
    redirects/sec at peak actually reaches your infrastructure.
- **The trade-off in practice**: most production URL shorteners (including
  bit.ly) use **302**, explicitly prioritizing click analytics — the whole
  business value of a link shortener product is often the analytics, not
  just the redirect — and instead handle the resulting load with
  aggressive server-side caching (Step 6.4) rather than relying on the
  browser to cache. A system with no analytics requirement at all, or one
  explicitly optimizing to minimize its own infrastructure load above all
  else, would reasonably choose 301 instead. This should be surfaced
  explicitly as a deliberate choice, not defaulted silently.

### 6.3 Custom alias support

- Custom aliases share the same underlying `short_code` column and lookup
  path as generated codes — the distinction (`is_custom_alias`) is
  metadata, not a structurally different code path.
- **Availability check** must be atomic to prevent a race between two users
  requesting the same alias simultaneously — implemented as a conditional
  insert (`INSERT ... ON CONFLICT DO NOTHING`, then checking whether the
  row you intended to insert is the one that's actually present) rather
  than a separate "check if exists" read followed by an "insert" write,
  which would reintroduce a check-then-act race.
- **Namespace collision with generated codes**: since generated codes come
  from Strategy C's pre-generated random pool, a custom alias could
  coincidentally match a code already reserved in that pool (unlikely, but
  possible) — the reservation pool should mark a code as "consumed" the
  moment a custom alias claims it, so the pool distribution job never hands
  that code out to a server later.
- **Validation**: custom aliases need character-set and length validation
  (avoid reserved paths like `/api`, `/admin`; avoid characters that need
  URL-encoding) that generated codes, drawn from a known-safe base62
  alphabet, don't need.

### 6.4 Caching strategy for the heavy read:write skew

Given the ~100:1+ (often far higher in real products, since popular links
get clicked disproportionately) read:write ratio quantified in Step 2, the
entire redirect path is designed around **caching hot short codes
aggressively**, following the cache-aside pattern described in
`01_Concepts/05_caching.md`:
- On a redirect request, the redirect service checks Redis first
  (`redirect:{short_code}`). A cache hit resolves the redirect without ever
  touching the primary datastore — this is the path that must handle the
  bulk of the ~11,574 redirects/sec peak.
- On a cache miss, the service reads from the primary datastore, returns
  the redirect, and populates the cache for subsequent requests (standard
  cache-aside).
- **Popularity skew (a small fraction of links account for most clicks)**
  means a relatively small, hot working set — even if there are hundreds
  of millions of total links, the links receiving traffic *right now* at
  any given moment are a much smaller set, which fits comfortably in a
  Redis cluster's memory (recall Step 2's storage estimate: even the full
  mapping table is only ~1.2 TB after 5 years; the actively-hot subset at
  any moment is a small fraction of that).
- **Negative caching**: cache "this code doesn't exist / is expired /
  is deactivated" results too (with a shorter TTL), not just successful
  lookups — otherwise a burst of requests for a dead or mistyped link
  (which happens constantly in practice — typos, expired campaign links
  still being clicked) repeatedly falls through to the primary datastore.
- **CDN/edge caching** can be layered in front of the redirect service
  itself for further offload, though it interacts with the 301/302 choice:
  if using 302, a CDN can still cache the redirect response server-side
  (distinct from the browser caching a 301 client-side) using a short TTL,
  giving *some* of 301's server-load benefits while still logging clicks
  at the CDN edge before forwarding to origin, and can be periodically
  invalidated for a shorter, more analytics-friendly effective cache
  window than a browser's indefinite 301 cache.

## Step 7: Bottlenecks & Trade-offs

- **What breaks first**: the redirect service's cache layer, if it's
  under-provisioned relative to the actively-hot key set — a cache-miss
  storm (e.g., after a cache cluster restart with a cold cache, or during
  a sudden viral spike on a previously-cold link) sends a burst of traffic
  straight to the primary datastore, which is sized for steady-state cache
  offload, not for absorbing the full redirect QPS directly. Mitigate with
  cache warming on deploy and request coalescing (a single in-flight DB
  read for a given short_code services all concurrent requests for that
  same code, rather than each one independently hitting the DB — the
  thundering herd problem, covered in `01_Concepts/05_caching.md`).
- **Hot-link concentration**: a single link going viral can direct
  effectively unbounded QPS at one cache key — mitigated by the cache
  layer's own horizontal scaling and, for truly extreme cases, a
  short-lived local (in-process) cache on each redirect service instance
  for the single hottest keys, accepting slightly staler data for those in
  exchange for not round-tripping to Redis on every request for the
  single most popular link in the system.
- **Trade-off — 301 vs 302**: already covered in depth in Step 6.2;
  restated as the headline trade-off of this whole design — analytics
  completeness vs. infrastructure load, resolved in most production
  systems by choosing 302 + aggressive server-side caching over 301 +
  browser caching.
- **Trade-off — short code generation strategy**: Strategy C (pre-generated
  range handout) trades a small amount of background-job complexity for
  eliminating both the coordination bottleneck of Strategy A and the
  collision-handling complexity of Strategy B — the right choice for most
  systems at this scale, though Strategy A remains simpler to reason about
  for a much smaller-scale system where a single counter's throughput is
  genuinely sufficient.
- **Write path is comparatively unconstrained**: at ~200 creations/sec
  average (Step 2), the write path has enormous headroom — this is why the
  design correctly invests almost all its complexity budget in the read
  path, not the write path; a design that spent equal effort optimizing
  link creation would be solving the wrong problem.

## Follow-up Questions an Interviewer Might Ask

- **"How would you handle a link that suddenly goes viral — 100x its
  normal traffic in minutes?"** Rely on the cache layer's horizontal
  scalability and request coalescing to absorb the spike without it ever
  reaching the primary datastore; if using 302, consider dynamically
  shortening that specific key's effective staleness tolerance is
  unnecessary since the mapping itself doesn't change — the concern is
  purely read throughput, which caching already addresses.
- **"How do you prevent someone from shortening a URL to a phishing or
  malware site?"** Add a URL-safety check (e.g., against Google Safe
  Browsing or a similar reputation API) synchronously or near-synchronously
  at creation time, plus asynchronous periodic re-scanning of existing
  links, since a destination site can turn malicious after the short link
  was already created and shared.
- **"How would you support link expiration efficiently, without a
  background job scanning the whole table for expired rows?"** Check
  `expires_at` lazily at read time (the redirect service treats an expired
  link as a 404/410 the moment it's accessed past its expiry, regardless of
  whether a cleanup job has run yet) and use a background job only for
  eventual physical deletion/archival, not for enforcing the expiry
  behavior itself.
- **"How would you migrate to longer short codes if you're approaching
  keyspace exhaustion?"** Because codes are opaque strings, not fixed-width
  integers, you can simply start generating 8-character codes once the
  7-character pool runs low, while all existing 7-character codes continue
  resolving normally — no migration of existing data needed, since lookup
  is by exact string match regardless of length.
- **"What happens if two servers claim overlapping code ranges from the
  pool due to a bug?"** The atomic "insert if absent" write at creation
  time (Step 6.3) is the actual safety net — even if range allocation had
  a bug, the final uniqueness guarantee comes from the database's
  conditional-insert constraint, not from trusting that ranges never
  overlap; defense in depth rather than relying on a single mechanism.
- **"How would you shard the primary datastore as it grows?"** Shard by a
  hash of `short_code` (already noted in Step 5) rather than by
  `user_id` or `created_at`, because the redirect access pattern is always
  a point lookup by short_code — hashing on it distributes both storage
  and redirect read load evenly across shards, whereas sharding by
  creation time would concentrate all current click traffic on whichever
  shard holds recently-created (typically more actively clicked) links.
