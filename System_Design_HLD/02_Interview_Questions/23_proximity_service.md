# Design a Proximity/Nearby Search Service

## Problem Statement

"Design a service like Yelp's 'restaurants near me' — given a user's location and a search radius (and maybe a category like 'coffee'), return nearby points of interest ranked by some mix of distance and relevance. Assume there are tens of millions of businesses/POIs worldwide and a large, geographically distributed user base issuing these searches constantly. How would you build the indexing and query path?"

This question is frequently paired with, or contrasted against, a ride-sharing/driver-matching design (see `12_ride_sharing_uber.md`). Interviewers ask it specifically to see whether a candidate reflexively reapplies a live-geospatial-index solution from a different problem, or recognizes that the read/write characteristics here are fundamentally different and lead to a different — and in some ways simpler — architecture.

## Step 1: Clarify Requirements

**Functional Requirements**
- Given (latitude, longitude, radius, category filter), return matching POIs within the radius, ranked by a blend of distance and relevance/rating.
- Support category/keyword filtering (e.g. "coffee," "italian restaurant").
- Return enough detail per result for a list view: name, address, distance, rating, open/closed status, thumbnail.
- Support POI detail lookup (full profile: hours, menu, reviews) as a secondary read path.
- Business owners can update their own POI's info (hours, address, category) — a low-frequency write path.
- New POIs can be added (a business opens) and existing ones removed/deactivated (a business closes) — also low-frequency.

**Non-Functional Requirements**
- Scale: 50 million POIs worldwide, 20 million daily active users, each issuing a handful of nearby-searches per session — assume 100 million nearby-search requests/day.
- Read:write ratio: overwhelmingly read-heavy. POI data changes maybe once every few weeks per business (hours, menu updates) versus being read potentially thousands of times per day if popular — a ratio easily in the range of 10,000:1 or higher, in sharp contrast to a live-location system.
- Latency: search results should return in well under 200ms p99 — this is an interactive, impatient UI (a user scrolling a map or list).
- Freshness: POI location/details do not need to be real-time fresh — a business's data being a few hours or even a day stale (new hours not yet reflected) is an acceptable trade-off, NOT acceptable in a live-position system like ride-hailing.
- Consistency: eventual consistency is entirely fine for search results; strong consistency is not a requirement anywhere in this system except perhaps the business owner's own edit-confirmation flow.
- Availability: search should stay available even if the write path (POI edits) is degraded — reads must not be coupled to write-path health.
- Geographic distribution: users and POIs are global; results must be relevant to wherever the user is searching, without artificially favoring one region's infrastructure over another (argues for read replicas / caches close to users globally).

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 50M POIs, 100M search requests/day.
- Average search radius: a few kilometers in a dense urban area, larger in rural areas — assume a search typically needs to consider a candidate set of a few hundred to a few thousand POIs before ranking.

**Query rate**
- 100M requests/day / 86,400 sec/day ≈ 1,157 requests/sec average; assume a 5x peak multiplier for daytime/meal-time clustering ≈ 5,800 requests/sec peak.

**Storage**
- Each POI record: id, name, lat/long, category, address, rating, hours, metadata ≈ 1 KB (excluding large media like photos, which live in object storage referenced by URL, not inline).
- 50M POIs x 1 KB ≈ 50 GB for the core searchable dataset — comfortably fits in memory across a modest cluster, meaning the entire geo-index can realistically be memory-resident or nearly so, unlike a system with terabytes of core data.

**Geo-index size**
- If indexed via geohash cells at a resolution where each cell covers roughly a city-block-to-neighborhood scale (e.g. geohash precision 6, ~1.2km x 0.6km per cell), and POIs are unevenly distributed (dense in cities, sparse elsewhere) — a reasonable estimate is a few million populated cells worldwide, each holding a POI-ID list. Index overhead (cell key + POI ID list) is small relative to the POI records themselves, well under the 50 GB core dataset size.

**Bandwidth**
- Each search response: ~20 results x ~0.5 KB (name, distance, rating, thumbnail URL) ≈ 10 KB.
- 5,800 requests/sec x 10 KB ≈ 58 MB/sec at peak — modest, and this is exactly the kind of traffic that caching (Step 6) reduces dramatically further, since a large fraction of requests are for popular (location, category) combinations that repeat across many different users.

**Write rate**
- Even generously assuming 5% of 50M POIs update something in a given month, that's 2.5M updates/month ≈ 83,000/day ≈ ~1/sec average — utterly trivial compared to the read rate, reinforcing that this system's entire architecture should be optimized for read throughput, with the write path kept simple rather than highly available in the aggressive sense a write-heavy system would need.

## Step 3: High-Level Design

**Contrast with the ride-sharing driver-location problem up front**: `12_ride_sharing_uber.md` solves a HIGH-WRITE geospatial problem — driver positions change every few seconds, for every active driver, and the index must reflect near-real-time positions because a stale driver location leads directly to a bad match (routing a rider to a driver who has already moved away). This system is the mirror image: POI positions are essentially static (a restaurant doesn't move), and the read volume vastly dominates the write volume. That difference changes the right architecture in a concrete way: instead of a live-updating in-memory geospatial index that must absorb constant position churn, this system can use an index that's built mostly offline/periodically and served largely from cache, because there's nothing "live" that needs reflecting moment to moment.

**Core components**
- **POI Write Service**: handles business owner edits (hours, category, address) — low volume, can afford to be a straightforward CRUD service against the primary database.
- **Primary POI Database**: the durable system of record for all POI data.
- **Geo-Index Builder**: a batch/periodic process (e.g. runs every few minutes to hours, not continuously) that (re)builds or incrementally updates the geospatial index — geohash-cell-to-POI-ID mappings — from the primary database.
- **Geo-Index (read-optimized, heavily cached)**: maps geo-cells to the POI IDs within them; this is what a search query actually consults first.
- **Search/Ranking Service**: takes a search request, resolves it to the relevant geo-cells, retrieves candidate POI IDs, fetches their details, and ranks the candidate set by blended distance + rating + relevance.
- **Cache layer** (e.g. Redis, per `05_caching.md`): caches full search results for popular (location-bucket, category) query combinations, and caches individual POI detail lookups.
- **Read Replicas** of the primary database, geographically distributed, serving as a fallback/detail-lookup path when cache misses.

**Data flow**
1. Business owner updates POI info → written to the Primary POI Database (low volume, straightforward path, no special scaling needed).
2. Geo-Index Builder periodically (e.g. every 15 minutes, or incrementally on write via a change-data-capture stream for near-immediate but still not "live" freshness) reads changed POIs and updates the geo-index's cell mappings.
3. User issues a nearby-search: `GET /search?lat=..&long=..&radius=..&category=coffee`.
4. Search Service computes which geo-cells cover the requested radius, checks the result cache for this (cell-bucket, category) combination first.
5. On cache hit: return cached ranked results immediately (this is the common case, given the estimation above).
6. On cache miss: query the Geo-Index for POI IDs in the relevant cells, fetch their details (from a POI-detail cache, falling back to a read replica), rank the candidate set, cache the response, and return it.

```text
    Business Owner                         End User
         |                                     |
         v                                     v
+------------------+                +-------------------------+
| POI Write Service |                |  Search/Ranking Service  |
+---------+----------+               +------------+-------------+
          |                                       |
          v                                       | 1. check cache
+----------------------+                          |    (loc-bucket, category)
| Primary POI Database  |<----read (on miss)-------+
| (system of record)    |                          |
+-----------+------------+                         |
            |                                      |
            | periodic / CDC                       |
            v                                      v
+---------------------------+          +--------------------------+
|  Geo-Index Builder          |-------->|   Geo-Index                |
|  (batch/incremental job)    |         |   geohash_cell -> [POI IDs]|
+---------------------------+          +--------------------------+
                                                    |
                                                    v
                                       +--------------------------+
                                       |  Candidate POI details     |
                                       |  (cache + read replicas)   |
                                       +--------------------------+
                                                    |
                                                    v
                                       +--------------------------+
                                       |  Rank: distance + rating   |
                                       |  + relevance                |
                                       +--------------------------+
                                                    |
                                                    v
                                            Response to user
```

## Step 4: API Design

**`GET /search`**
```
Query: ?lat=37.7749&long=-122.4194&radius_km=2&category=coffee&limit=20
Response: {
  "results": [
    { "poi_id": "poi_5521", "name": "Blue Bottle Coffee", "distance_km": 0.3,
      "rating": 4.6, "category": "coffee", "open_now": true, "thumbnail_url": "..." },
    { "poi_id": "poi_9012", "name": "Ritual Coffee", "distance_km": 0.7,
      "rating": 4.4, "category": "coffee", "open_now": true, "thumbnail_url": "..." }
  ],
  "next_page_token": "..."
}
```

**`GET /poi/{poi_id}`**
```
Response: {
  "poi_id": "poi_5521", "name": "Blue Bottle Coffee",
  "address": "66 Mint St, San Francisco, CA", "lat": 37.7822, "long": -122.4058,
  "category": "coffee", "rating": 4.6, "review_count": 1204,
  "hours": { "mon": "7:00-18:00", "...": "..." }
}
```

**`POST /poi`** (business owner registers a new POI)
```
Request: { "name": "New Cafe", "lat": 37.78, "long": -122.41, "category": "coffee", "address": "..." }
Response: { "poi_id": "poi_7788", "status": "pending_index" }
```

**`PUT /poi/{poi_id}`** (business owner edits their POI)
```
Request: { "hours": { "mon": "8:00-17:00" } }
Response: { "poi_id": "poi_5521", "status": "updated", "reindex_eta_minutes": 15 }
```

**`GET /poi/{poi_id}/nearby-similar?radius_km=1`**
```
Response: { "results": [ { "poi_id": "poi_9012", "name": "Ritual Coffee", "distance_km": 0.9 } ] }
```

## Step 5: Data Model

**Primary POI store — relational or document database (e.g. Postgres or a document store)**
```
Table: pois
  poi_id      (PK)
  name
  lat, long
  category
  address
  rating
  hours       (JSON)
  status      (active | closed | pending)
  updated_at
```
- Relational/document is appropriate here specifically BECAUSE this is the low-volume write path with no exotic throughput requirements — POI edits are infrequent, moderate-complexity records with fields business owners edit through a normal CRUD UI; there's no pressure here that would push toward a specialized write-optimized store, unlike the read path.

**Geo-Index — key-value store optimized for the cell-lookup access pattern (e.g. Redis, or a dedicated geospatial index structure)**
```
Key: geohash_cell (e.g. "9q8yy" at precision 5)
Value: [poi_id_1, poi_id_2, poi_id_3, ...]
```
- Geohashing encodes (lat, long) into a base-32 string where geographically nearby locations share string prefixes — meaning a search radius maps cleanly onto a small, enumerable set of geohash-prefix cells to query (the search cell plus its 8 neighbors, typically, to avoid edge-boundary misses where a nearby POI falls just across a cell boundary). This makes "give me everything near this point" a small number of exact key lookups rather than a geometric computation over the full dataset.
- Chosen over a live-updating structure (like the driver-location system would need) precisely because the low write rate means the index doesn't need to absorb constant churn — it can be rebuilt or incrementally patched on a relaxed schedule (Step 6) and served almost entirely from cache/memory.
- A quad-tree is the alternative indexing structure with similar properties (recursively subdivides space based on density, so dense areas get finer cells automatically) — either is a reasonable choice for this read-heavy, low-write access pattern; geohashing is often preferred for implementation simplicity (it reduces to string-prefix operations on a standard key-value store) while a quad-tree adapts better to wildly uneven density without needing multiple precision levels.

**Result cache — key-value store (e.g. Redis)**
```
Key: search:{geohash_cell_bucket}:{category}:{radius_bucket}
Value: serialized ranked result list, TTL ~15-60 minutes
```

## Step 6: Deep Dive

### 6.1 Why This Is a Fundamentally Different Problem Than Ride-Sharing's Geospatial Index

`12_ride_sharing_uber.md` needs a geospatial index that reflects driver positions updated every few seconds for potentially hundreds of thousands of concurrently active drivers — a genuinely high-write workload where staleness of even a handful of seconds produces visibly wrong results (matching a rider to a driver who is no longer where the index says they are). That forces a design centered on efficiently absorbing constant position updates into a live index structure.

This system's POIs are, for all practical purposes, static: a restaurant's location doesn't change, and even its metadata (hours, menu) changes on the order of weeks, not seconds. The read:write ratio computed in Step 2 (roughly 10,000:1 or higher) is the quantitative signal that should drive the architecture in the opposite direction from the ride-sharing case: instead of optimizing the index for absorbing writes cheaply, optimize it for serving reads as cheaply as possible, and treat the "keep the index current" problem as a background, relaxed-schedule concern rather than a real-time one. Concretely, this means: build the geo-index in batch or via lazy incremental updates rather than synchronously on every write, and lean heavily on caching full query results — neither of which would be safe or effective in the ride-sharing system, where a cached driver-position result could be actively wrong within seconds.

### 6.2 Geospatial Indexing for the Read-Heavy, Low-Write Case

Since POIs rarely move, the geohash-cell-to-POI-ID index does not need to support efficient constant re-insertion the way a live index would. This opens up simpler build strategies:
- **Batch rebuild**: periodically (e.g. every 15-60 minutes) recompute the entire index from the primary POI database. Simple, always internally consistent, but new POIs or edits take up to the batch interval to appear — acceptable per the freshness requirement in Step 1.
- **Incremental update via change-data-capture**: when a POI is written, a CDC stream (or simple write-through) patches just the affected geohash cell(s) rather than rebuilding everything — gives near-immediate visibility for new/edited POIs (e.g. within a minute or two) while still being far simpler than a system that has to handle thousands of position updates per second, since here it's handling maybe one update per second (Step 2).
- A hybrid — periodic full rebuild for correctness/self-healing (catches any drift or missed CDC events) plus incremental patching for freshness — is a reasonable production answer and worth mentioning explicitly, since it hedges against CDC pipeline bugs without paying full-rebuild latency on every edit.
- Either geohashing or a quad-tree is a fine choice of indexing structure here; the key point for the interview is not which one, but WHY the low write rate makes either one comfortably sufficient without needing the more complex live-update machinery a high-write system would require.

### 6.3 Caching Popular (Location, Category) Query Combinations

A huge fraction of nearby-search traffic is not uniformly random across the whole world — it clusters heavily around dense urban areas and popular categories ("coffee near downtown Chicago" is asked by thousands of distinct users across a day, all of whom, for practical purposes, want the same answer). This is exactly the scenario caching (`05_caching.md`) is built for: precompute or cache-on-first-request the ranked result for a given (geo-cell-bucket, category, radius-bucket) combination, and serve subsequent identical or near-identical requests directly from cache without touching the geo-index or ranking logic at all.

This is explicitly NOT something that would work for a live driver-matching query — caching "nearby available drivers" for even 30 seconds could return drivers who have since been matched to someone else or moved out of range, producing an actively wrong result. The fact that this system's underlying data changes slowly is precisely what makes aggressive result-caching not just possible but the primary scalability lever: per the bandwidth estimate in Step 2, a high cache-hit rate here turns "5,800 requests/sec each doing index lookups + ranking" into "5,800 requests/sec mostly served from cache, with only cache-miss traffic (a small fraction) actually touching the geo-index and ranking service."

Practically, the cache key needs to bucket location coarsely enough that many nearby users' requests collapse onto the same key (e.g. round lat/long to a geohash prefix rather than keying on exact coordinates, which would almost never repeat between users) while still being fine-grained enough that results remain locally relevant — a direct trade-off between cache hit rate and result precision, tuned by choosing the geohash precision used for the cache key versus the one used for the underlying index.

### 6.4 Two-Stage Retrieve-Then-Rank

Attempting to rank the entire 50M-POI dataset by a blended distance+rating+relevance score for every search request is wasteful and unnecessary — the overwhelming majority of POIs are nowhere near the search location and can be eliminated instantly by geography alone. This system uses the same two-stage retrieve-candidates-then-rank pattern that recurs across this folder's designs (cross-shard search, cross-shard leaderboard merging):
1. **Retrieve**: use the geo-index to cheaply pull the small set of POI IDs within the geo-cells covering the search radius — typically a few hundred to a couple thousand candidates, not millions, because the geo-index has already done the expensive part (spatial filtering) via simple key lookups.
2. **Rank**: only this much smaller candidate set gets the more expensive treatment — fetch full details, compute a blended score combining actual distance (a proper haversine/great-circle calculation, not just cell membership), rating, category-match relevance, and possibly personalization signals, then sort and return the top results.
- This separation matters because the ranking step is the more computationally expensive one (multiple weighted factors, possibly involving a lookup per candidate for freshness like "open now" status) — running it only over hundreds of pre-filtered candidates rather than the full dataset is what keeps p99 latency well under the 200ms target from Step 1 even without needing that ranking logic itself to be blazingly optimized.

## Step 7: Bottlenecks & Trade-offs

- **Hot geo-cells in extremely dense areas**: a single geohash cell covering a dense downtown core can contain far more POIs than a cell in a sparse suburb, causing uneven load and candidate-set sizes across cells. Mitigation: use variable-precision cells (finer-grained subdivision in dense areas, similar to how a quad-tree naturally adapts) or simply accept a larger candidate set in dense areas and rely on the ranking stage to trim it, since the absolute POI counts even in the densest single cell are still small relative to the full dataset.
- **Cache staleness vs freshness trade-off**: aggressive result caching (Step 6.3) means a POI's newly-updated hours or a newly-opened business can take up to the cache TTL to appear in search results. This is an explicitly accepted trade-off given the non-functional requirements, but it's worth being able to state the TTL choice (e.g. 15-60 minutes) as a deliberate freshness-vs-load dial, not an oversight.
- **Geo-cell boundary effects**: a POI just across a cell boundary from the search point can be geographically closer than one nominally "inside" the queried cell but be missed if only the exact containing cell is queried. Mitigation: always query the containing cell plus its immediate neighbors (a standard geohash technique), accepting a slightly larger candidate set in exchange for correctness at boundaries.
- **Global distribution and cross-region latency**: with users and POIs worldwide, routing every search to a single regional deployment would add unacceptable latency for distant users. Mitigation: deploy the Search Service, cache layer, and read replicas regionally (POI data is naturally partitionable by geography, unlike a system requiring a single global consistent view), with the Primary POI Database remaining a smaller, less latency-sensitive write path that can tolerate being centralized or lightly multi-region since write volume is so low.
- **Trade-off — index freshness vs system simplicity**: choosing batch-rebuild-only (simplest) sacrifices freshness for new/edited POIs; choosing full CDC-driven real-time indexing (most complex) gains freshness the business requirement doesn't actually demand. The hybrid approach (6.2) is a deliberate middle-ground trade-off, and articulating why the requirements don't justify the most complex option is itself a signal of good judgment in this interview.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you handle a search for a very rural area where the nearest coffee shop might be 50km away — does the fixed-radius cell approach still work?"** Expand the search progressively — query the immediate cells first, and if too few results are found, widen to a larger ring of cells (or jump to a coarser geohash precision) rather than requiring the client to guess an appropriately large radius upfront; this keeps dense-area queries cheap while still answering sparse-area queries correctly.

2. **"How do you personalize results — e.g. ranking a user's previously-liked cuisine higher?"** Layer a personalization signal into the ranking stage only (never the retrieval/candidate-selection stage, which should stay purely geographic for cacheability) — e.g. a lightweight per-user preference vector fetched in parallel with candidate details, blended into the final score; note this also means personalized results are harder to cache in shared result-cache buckets, so it's a direct trade-off against the aggressive caching strategy in 6.3, and a common resolution is to cache the geographically-ranked base result and apply personalization as a final client-side or thin re-rank layer on top of the cached list.

3. **"How would you handle a POI that legitimately moves, like a food truck?"** Food trucks/mobile vendors break the "static POI" assumption this whole design leans on; treat them as a distinct category routed through a separate, more frequently-refreshed index path (shorter TTLs, more frequent incremental updates) rather than forcing the entire system's freshness guarantees down to accommodate a small subset of POIs.

4. **"What happens when a business closes down — how quickly does it disappear from search results, and what if someone navigates there anyway?"** The `status` field transitions to `closed`, propagating through the same incremental/batch indexing pipeline as any other edit (same freshness trade-off applies); the POI detail page can still be served (for informational purposes, e.g. "permanently closed") even after it drops out of active search results, which is a product decision worth surfacing to the interviewer.

5. **"How would you rank results when a user searches by keyword rather than category, e.g. 'best tacos'?"** This shifts part of the ranking problem toward text relevance/search-engine territory (potentially a dedicated search index like Elasticsearch for the keyword-matching component), with the geo-index still handling the geographic pre-filtering — the two-stage retrieve-then-rank pattern still applies, just with a richer, text-relevance-aware ranking stage.

6. **"How do you prevent the result cache from serving stale 'closed' status for time-sensitive info like 'open now'?"** Split cacheable and non-cacheable fields: the ranked list of matching POIs (name, distance, rating) is stable enough to cache with a longer TTL, but "open now" is time-of-day-dependent and should be computed at request time from the POI's (cached, but presumably accurate) hours data rather than baked into the cached response itself — otherwise a cached result generated at 2pm would incorrectly still say "open" when served again at 11pm.
