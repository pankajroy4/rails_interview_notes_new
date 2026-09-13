# Design a Content Delivery Network

## Problem Statement

"Design a simplified Content Delivery Network — a system that serves static content (images, videos, JS/CSS bundles, downloadable files) to end users worldwide with low latency, while keeping a manageable number of origin servers as the source of truth. How would you get content physically close to users, decide which edge location serves a given request, and handle cache invalidation when the origin content changes?"

This question tests whether a candidate understands that a CDN's core value proposition is fundamentally about physical distance and network topology, not just "another caching layer" — and whether they can reason about the genuinely hard distributed-systems problems that come from having caching infrastructure replicated across potentially hundreds of geographically dispersed locations instead of one.

## Step 1: Clarify Requirements

**Functional Requirements**
- Serve static content (images, video segments, JS/CSS, downloadable files) to end users with low latency, routed to a nearby edge location.
- Cache content at edge locations, fetching from origin on a cache miss.
- Support cache invalidation/purging when origin content changes (e.g. a new deployment, an updated image).
- Support both "pull" content (edge fetches lazily on first request) and "push" content (proactively distributed ahead of demand for known-hot assets, e.g. a major game/OS update release).
- Provide cache-hit-ratio and latency metrics/observability per edge location.
- Support standard HTTP caching semantics (Cache-Control headers, ETags, conditional requests) from origin.

**Non-Functional Requirements**
- Scale: serve a global user base — assume 500 million requests/day across all edge locations, for content totaling petabytes at origin (video libraries, image assets).
- Latency: edge-served cache hits should return in single-digit to low tens of milliseconds; the entire point of the system is minimizing round-trip latency by exploiting physical proximity.
- Availability: an edge PoP failure should not cause an outage for users near it — traffic should reroute to the next-nearest healthy PoP.
- High cache-hit ratio at the edge: the origin must be shielded from the bulk of traffic — a well-tuned CDN should serve the vast majority of requests (often 90%+) without touching origin at all.
- Consistency/freshness: purges should propagate globally, but NOT instantly — the design should set explicit, honest expectations (seconds to a couple of minutes) rather than promise perfect instant global consistency, which is not realistically achievable across hundreds of independent edge locations without unacceptable cost/complexity.
- Cost efficiency: bandwidth and storage at edge locations are the dominant cost driver; the design should avoid needlessly replicating cold/rarely-requested content to every edge location.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 500M requests/day globally, 100 edge PoPs (a reasonable count for wide geographic coverage without extreme cost), assume traffic is unevenly distributed but roughly averages to manageable per-PoP load with some hot regions.
- Average object size: mixed content, assume a blended average of 200 KB (many small images/JS/CSS, some larger video segments, averaged across a realistic mix).

**Request rate**
- 500M requests/day / 86,400 sec/day ≈ 5,800 requests/sec average globally; assume 4x peak multiplier for regional evening-peak clustering ≈ 23,200 requests/sec peak globally, spread across 100 PoPs ≈ ~232 requests/sec peak per PoP on average (with hot PoPs in major metro areas seeing meaningfully more).

**Bandwidth**
- 5,800 requests/sec x 200 KB ≈ 1.16 GB/sec ≈ 9.3 Gbps average egress across all edges combined; at 4x peak, ≈ 37 Gbps peak. Spread across 100 PoPs this is very manageable per PoP (roughly 370 Mbps peak average per PoP, again with hot PoPs well above average) — well within what a modest edge server cluster per PoP can serve from local cache.

**Cache-hit math and origin shielding**
- Assume a 92% cache-hit ratio at the edge (a realistic, strong target for mixed static content). That means only 8% of the 23,200 requests/sec peak — about 1,856 requests/sec — actually reach origin, a manageable load for a small origin fleet rather than the full 23,200/sec the edges absorb.
- This is the entire economic argument for a CDN: without it, the origin fleet would need to be provisioned for the full peak request rate AND every request would pay full cross-region latency; with it, origin only needs capacity for the cache-miss trickle, and the vast majority of users get edge-local latency.

**Storage per edge PoP**
- Not every PoP needs to hold the entire origin dataset (which may be petabytes) — each PoP holds only the working set of content actually popular in its region, evicting cold content (an LRU-style policy, per `05_caching.md`).
- If a PoP is provisioned with, say, 50 TB of cache storage and average object size is 200 KB, that's room for roughly 250 million objects — comfortably enough to hold a regional working set for all but the most extreme long-tail catalogs, with cold/rare content simply falling back to an origin fetch on the rare occasions it's requested.

## Step 3: High-Level Design

**Core components**
- **Origin Servers**: the authoritative source of content — could be object storage (e.g. S3-like) plus an application server for dynamic-but-cacheable content.
- **Edge PoPs (Points of Presence)**: many small clusters of caching servers distributed geographically close to end users — this is the architectural core of a CDN.
- **DNS-based Routing / GSLB (Global Server Load Balancing)**: resolves a CDN hostname to the IP of a nearby/healthy edge PoP based on the requester's location (cross-reference `04_load_balancing.md`).
- **Anycast Network** (alternative/complementary routing mechanism): the same IP address announced from multiple physical PoPs; normal internet BGP routing sends each user's packets to the topologically nearest announcing location.
- **Purge/Invalidation Service**: propagates cache-purge requests from content owners to every edge PoP.
- **Edge Cache Coordination (request coalescing)**: within a single PoP, ensures a cache-miss stampede for the same object collapses into a single origin fetch.
- **Metrics/Observability Pipeline**: aggregates per-PoP hit ratio, latency, and error rates back to a central monitoring system.

**Data flow**
1. Content owner uploads/updates an asset at Origin, sets `Cache-Control` headers indicating cacheability and TTL.
2. End user requests `https://cdn.example.com/assets/logo.png`.
3. DNS resolution (or Anycast routing) directs the request to the nearest/healthiest edge PoP.
4. That PoP checks its local cache: on hit, serves directly from edge (fast path, the common case per the 92% hit-ratio estimate).
5. On miss, the PoP fetches from Origin (or a regional mid-tier cache, for very large deployments — see Step 6), caches the response locally per its `Cache-Control` policy, and serves it to the user.
6. If the content owner updates or removes the asset, a purge request is issued, which the Purge Service propagates to all PoPs, each of which evicts/marks-stale its local copy.

```text
                                    +----------------------+
                                    |    Origin Servers      |
                                    |  (object storage +     |
                                    |   app servers)          |
                                    +-----------+------------+
                                                |
                     +---------------------------+---------------------------+
                     |                           |                           |
                     v                           v                           v
             +---------------+           +---------------+           +---------------+
             |  Edge PoP: US   |          |  Edge PoP: EU   |         |  Edge PoP: APAC|
             |  (cache + coa-  |          |  (cache + coa-  |         |  (cache + coa- |
             |   lescing)      |          |   lescing)      |         |   lescing)     |
             +--------+--------+          +--------+--------+         +--------+--------+
                      ^                            ^                           ^
                      |  DNS/GSLB or Anycast        |                           |
                      |  routes by location          |                           |
             +--------+--------+          +--------+--------+         +--------+--------+
             |  Users (US)      |          |  Users (EU)      |        |  Users (APAC)   |
             +-----------------+           +-----------------+        +-----------------+

           +----------------------------+
           |   Purge/Invalidation Service |----> fans out purge to every PoP above
           +----------------------------+
```

## Step 4: API Design

**`GET /assets/{path}`** (the actual content-serving request, handled at the edge)
```
Request headers: If-None-Match: "etag123"
Response: 200 OK (cache hit or fresh fetch) with body, or
          304 Not Modified (conditional request, content unchanged)
Response headers: Cache-Control: public, max-age=86400
                   X-Cache: HIT (or MISS)
                   X-Served-By: pop-us-east-1
```

**`POST /purge`** (content owner invalidates cached content)
```
Request: { "urls": ["https://cdn.example.com/assets/logo.png"], "mode": "url" }
   or:   { "prefix": "https://cdn.example.com/assets/campaign-2026/", "mode": "prefix" }
Response: { "purge_id": "purge_881", "status": "propagating", "eta_seconds": 60 }
```

**`GET /purge/{purge_id}/status`**
```
Response: { "purge_id": "purge_881", "status": "complete",
            "pops_confirmed": 100, "pops_total": 100 }
```

**`POST /push-cache`** (proactively push known-hot content to edges ahead of demand)
```
Request: { "urls": ["https://cdn.example.com/releases/app-v9.pkg"], "target_pops": "all" }
Response: { "push_id": "push_331", "status": "distributing" }
```

**`GET /analytics/pop/{pop_id}`**
```
Response: { "pop_id": "pop-us-east-1", "hit_ratio": 0.93,
            "requests_per_sec": 410, "p99_latency_ms": 8 }
```

## Step 5: Data Model

**Edge cache — in-memory + local disk key-value store per PoP**
```
Key: request URL (or a normalized cache key derived from URL + relevant headers, e.g. Vary: Accept-Encoding)
Value: { body, headers (including Cache-Control, ETag), cached_at, expires_at }
```
- A simple key-value structure is appropriate at the edge because the access pattern is purely "look up by exact URL/cache-key" — no relational queries needed, and the priority is raw lookup speed and eviction efficiency (LRU/LFU) under storage pressure, which is exactly what a local key-value cache (often a tiered combination of in-memory for the hottest objects and local SSD for the broader working set) is built for.

**Purge request log — relational or document database, centrally located**
```
Table: purge_requests
  purge_id    (PK)
  target      (url or prefix)
  issued_at
  status      (propagating | complete | failed)
  pop_confirmations  (JSON map: pop_id -> confirmed_at)
```
- Needs to be centrally queryable and durable (so a content owner can check purge status, and so the system can retry propagation to any PoP that didn't confirm), but volume is low relative to content-serving traffic, so a standard relational/document store suffices — no special scaling needed here.

**Origin content — object storage (e.g. S3-like blob store) for the actual assets, plus a lightweight relational/document metadata store**
```
Table: asset_metadata
  asset_id / path (PK)
  content_type
  cache_control_policy
  current_etag
  last_modified
```
- Object storage is the natural fit for the bulk asset bytes themselves (durable, cheap at petabyte scale, not queried relationally); metadata needing quick structured lookup (current ETag for conditional requests, cache policy) is kept separately and cheaply.

## Step 6: Deep Dive

### 6.1 Edge PoP Architecture and the Latency Argument

The entire premise of a CDN rests on a simple physical fact from the "latency numbers every engineer should know" discussion (`02_scalability_and_estimation.md`): round-trip network latency at global scale is dominated by physical distance and the speed-of-light propagation delay across that distance, not by how fast the server itself processes the request. A perfectly optimized origin server in Virginia still cannot serve a user in Singapore faster than roughly the round-trip light-speed-in-fiber delay for that distance allows — often 200ms+ round trip regardless of server-side optimization.

A CDN's answer is architectural, not algorithmic: deploy many small caching servers (Edge PoPs) physically close to where users actually are, so that the bulk of requests (per the 92% hit-ratio assumption in Step 2) never have to travel anywhere near the origin at all. This is why a modest, even somewhat under-provisioned edge server can outperform a highly-optimized, powerful origin server for end-user-perceived latency — moving the server physically closer is frequently a bigger latency win than any amount of server-side optimization applied to a single, distant origin. This framing is the single most important thing to communicate early when answering this question, because it explains why the rest of the design (routing, cache population, invalidation) exists in service of this one physical constraint.

### 6.2 Routing Users to Their Nearest/Best Edge PoP

Two complementary mechanisms, worth explaining both and noting real CDNs commonly combine them:

**DNS-based routing / GSLB**: the CDN's authoritative DNS server, when resolving `cdn.example.com`, doesn't return a single fixed IP — it inspects where the DNS query is coming from (typically the resolver's IP, used as a proxy for the end user's approximate location) and returns the IP address of the nearest or currently-healthiest PoP for that region, per the load-balancing/GSLB concepts in `04_load_balancing.md`. This gives fine-grained control: the CDN operator can factor in real-time PoP health, load, and even business logic (e.g. route around a PoP undergoing maintenance) into each DNS answer. The trade-off is that DNS resolution involves caching (TTLs) at multiple layers (the OS, the ISP resolver), so routing decisions can't be changed instantaneously — a PoP that just went unhealthy may still receive traffic from users whose DNS answer was cached moments before.

**Anycast**: the same IP address is announced simultaneously from every PoP's network location via BGP, and standard internet routing infrastructure — without any CDN-specific logic — naturally routes each user's packets to whichever announcing location is topologically nearest (fewest BGP hops), because that's how internet routing inherently works. This has the advantage of working at the network layer, beneath DNS caching entirely, so it reacts faster to a PoP going down (routers simply stop hearing that location's announcement and reroute) and doesn't suffer from DNS TTL staleness. The trade-off is coarser control — the CDN operator has less fine-grained say over exactly which PoP a given user lands at, since it's determined by internet routing topology rather than an explicit, business-logic-aware decision.

Real-world CDNs frequently combine both: Anycast gets a user's connection to a topologically-nearby PoP quickly and resiliently, while DNS-based/application-layer logic can still steer specific hostnames or handle finer load-balancing decisions within or across nearby PoPs.

### 6.3 Cache Population: Pull vs Push

**Pull CDN (the default for most content)**: an edge PoP does not proactively hold content until it's actually requested — the first user to request a given asset at a given PoP causes a cache miss, which triggers a fetch from origin, after which that PoP caches the result for subsequent requests. This is the right default because proactively pushing every piece of content to every one of potentially hundreds of PoPs worldwide does not scale — most content has geographically concentrated demand (a local news site's images are mostly requested by geographically nearby users), so most PoPs would be wasting storage and bandwidth holding content nobody near them will ever request. This mirrors the pull vs push framing in `05_caching.md`, applied at the edge-network scale rather than a single application cache.

**Push (proactive distribution)**: reserved for a small, deliberately-identified set of known-hot or business-critical content — e.g. a major OS update, a big game patch release, or a high-profile live-event asset known in advance to generate a massive synchronized demand spike the instant it's available. Proactively distributing this content to all (or strategically likely-relevant) PoPs ahead of the release moment avoids every PoP independently experiencing a cache-miss stampede (6.5) at the exact same instant when demand hits. This is a deliberate, selective exception to the pull default — used sparingly, for content where the operator can predict the spike in advance and where the cost of over-provisioning is clearly justified by avoiding an otherwise-inevitable origin overload at launch moment.

### 6.4 Cache Invalidation/Purging Across Distributed Edge Locations

Cache invalidation is already one of the two hard problems in caching generally (`05_caching.md`'s invalidation discussion) — knowing when cached data is stale and getting rid of it correctly. A CDN inherits that same fundamental difficulty and multiplies it by the number of independent edge locations: a purge for one asset must now reach and be applied at every one of potentially hundreds of PoPs worldwide, each running independently, some of which may be temporarily unreachable or under heavy load when the purge is issued.

The honest, production-realistic answer is that there's a genuine trade-off between purge propagation speed and system complexity/cost, and a well-designed CDN sets explicit expectations rather than promising something unachievable:
- A purge request is issued once (e.g. via the `POST /purge` API) and fanned out to every PoP, typically over the CDN's own internal control-plane network (kept separate from user-facing traffic).
- Each PoP acknowledges the purge once applied; the central Purge Service tracks confirmations per PoP (as modeled in the `purge_requests` table in Step 5) and can retry against any PoP that hasn't confirmed within an expected window.
- Real-world CDN purges commonly take anywhere from a few seconds to a couple of minutes to fully propagate globally — this should be stated explicitly as the honest target rather than claiming instant global consistency, because achieving true instant consistency across hundreds of independently-operating, geographically-distant locations would require synchronous coordination that would be prohibitively slow and fragile for the normal caching path that serves the other 99.9%+ of requests.
- A lower-latency alternative for content that changes identity on every update (rather than being purged in place) is cache-busting via a versioned URL or filename (e.g. `logo.v2.png` or a content-hash-based filename) — since a new URL is, from the CDN's perspective, simply a new cache key with no stale entry to invalidate at all, this sidesteps the propagation-delay problem entirely for content the origin controls the naming of, and is the preferred pattern for build artifacts (JS/CSS bundles) over relying on purge propagation timing.

### 6.5 Handling a Cache-Miss Stampede at a Single Edge PoP (Thundering Herd)

When previously-uncached content suddenly becomes popular at a specific PoP (e.g. a piece of content goes viral in one region, or a TTL expiry happens to coincide with a burst of simultaneous requests), many concurrent requests can arrive at that PoP for the same object within milliseconds of each other, all before the first one has finished fetching from origin. Naively, each of those concurrent requests would independently detect a cache miss and independently issue its own fetch to origin — the same thundering-herd/dog-piling problem discussed in `05_caching.md`, but happening at a single edge location that may be serving a meaningful fraction of a region's traffic.

The fix, applied specifically at the edge layer, is request coalescing: the first request that misses the cache at a given PoP acquires a short-lived local marker (e.g. an in-memory lock keyed by the cache key) indicating "a fetch for this object is already in flight," issues the single origin fetch, and every other concurrent request for the same object arriving at that PoP while the fetch is outstanding is held/queued locally and served from the result of that single in-flight fetch once it completes, rather than each one independently hitting origin. This keeps a single popular object's stampede from turning into origin-side overload — origin sees at most one request per PoP per stale/missing object, regardless of how many thousands of end users are simultaneously requesting it through that PoP, which is precisely what keeps the origin-shielding math in Step 2 (only 8% of traffic reaching origin) actually true under real bursty conditions rather than just on average.

## Step 7: Bottlenecks & Trade-offs

- **Long-tail cold content still hits origin**: content that's rarely requested at a given PoP (or globally) won't build up a useful cache-hit ratio locally, meaning every such request pays full origin round-trip latency regardless of edge infrastructure. Mitigation: for very large catalogs, introduce a regional "mid-tier" cache layer between edge PoPs and origin (a smaller number of larger regional caches, each serving many nearby edge PoPs) — a miss at an edge PoP checks the regional tier before going all the way to origin, capturing cross-PoP-within-region locality without needing every small PoP to hold the full regional working set itself.
- **Purge propagation delay is an inherent trade-off, not a solvable bug**: as discussed in 6.4, instant global consistency for purges isn't realistically achievable without unacceptable cost to the normal-path caching performance; the mitigation is setting honest expectations plus offering versioned/content-hashed URLs as the fast-path escape hatch for content where staleness truly cannot be tolerated even briefly.
- **PoP failure and failover**: an individual PoP going down (hardware failure, regional network issue) must not cause an outage for the users it serves. Mitigation: health-checked DNS/GSLB routing (6.2) redirects new DNS resolutions away from an unhealthy PoP, and Anycast's BGP-level failover handles in-flight routing more quickly than DNS TTLs would allow — the two mechanisms' complementary failure characteristics (DNS's business-logic awareness vs Anycast's network-layer speed) are exactly why combining them is standard practice.
- **Uneven traffic distribution across PoPs**: a viral event concentrated in one region can overload that region's PoP capacity even while other PoPs sit idle. Mitigation: GSLB routing logic can factor in real-time PoP load (not just geographic proximity) and spill overflow traffic to the next-nearest healthy PoP, trading a small latency increase for those overflow users against avoiding an outage.
- **Trade-off — storage cost vs hit ratio per PoP**: provisioning every PoP with enough storage to cache a very large fraction of the origin catalog improves hit ratio but is expensive at hundreds of PoPs; under-provisioning saves cost but pushes more traffic to origin and increases average latency. This is a direct, ongoing cost/performance dial tuned per deployment based on actual observed access patterns (per Step 2's storage estimation) rather than a one-time architectural decision.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you handle dynamic, personalized content that technically can't be cached the same way for every user?"** Distinguish cacheable-but-varying content (use `Vary` headers or cache keys that include the varying dimension, e.g. device type or locale, so the CDN caches a small number of variants rather than treating it as fully uncacheable) from truly per-user dynamic content, which should bypass the cache entirely and be proxied straight to origin — the CDN still adds value here as a fast, geographically-distributed proxy/TLS-termination layer even without caching.

2. **"How do you secure content so it can't be accessed by unauthorized users, given it's now cached on servers you don't fully control end-to-end trust for?"** Signed URLs/tokens with expiry (the origin or a control-plane service issues a time-limited signed URL, and edge PoPs validate the signature before serving from cache) let the CDN serve cached content without needing to re-authenticate every request against origin, while still enforcing access control.

3. **"What if origin itself goes down — does the whole CDN go down with it?"** A well-designed CDN should be able to continue serving already-cached content (even past its normal TTL, in a "stale-while-revalidate" or "serve-stale-on-origin-error" mode) during an origin outage, trading strict freshness for continued availability — worth calling out explicitly as a resilience feature rather than treating origin availability as a hard dependency for every request.

4. **"How would you extend this to support video streaming specifically, where content is delivered in many small segments?"** Video streaming (e.g. HLS/DASH) splits content into many small time-based segments, each independently cacheable — the same edge-caching and pull-population model applies per-segment, but request coalescing (6.5) and prefetching the next few segments a viewer is likely to request become more important given the sequential, predictable access pattern.

5. **"How do you decide how many PoPs to deploy and where?"** Balance latency coverage (more PoPs closer to more users reduces average round-trip distance) against operational cost and the fact that each additional PoP has a minimum viable traffic level to be cost-effective — typically driven by actual user geographic distribution data, prioritizing dense population/traffic centers first and accepting a longer tail of less-served regions initially, similar to the general estimation-driven trade-off reasoning used throughout this folder's designs.

6. **"How would you monitor and detect a PoP silently serving stale or corrupted content?"** Periodic synthetic/canary requests against known content with a known-good checksum, issued from a central monitoring system against each PoP, can catch silent divergence (a purge that failed to apply, a corrupted cache entry) that normal traffic-based metrics like hit ratio and latency wouldn't necessarily surface on their own.
