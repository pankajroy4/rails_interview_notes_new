# Design a Ride-Sharing Service (Uber/Lyft)

## Problem Statement

"Design a ride-sharing platform like Uber. A rider opens the app, sees nearby available
drivers on a map, requests a ride, and gets matched with a driver within a few seconds.
The driver navigates to the pickup, the trip happens, and payment is settled at the end.
Focus on how you'd find and match nearby drivers efficiently at scale, and how you'd
handle the real-time location updates that make the whole system work."

This is fundamentally a **geospatial matching problem under a tight latency budget** —
the interesting parts are not CRUD (create a trip, look up a user) but the mechanics of
"who is near whom, right now, out of millions of constantly-moving points."

## Step 1: Clarify Requirements

**Functional Requirements**
- Riders can see nearby available drivers on a map in near-real-time.
- Riders can request a ride from their current location to a destination.
- The system matches the rider with a nearby available driver within a few seconds.
- Drivers can accept or reject a ride request.
- Both parties can track the other's live location during the pickup and the trip.
- The system computes ETA (time to pickup, time to destination) and fare estimate.
- Trip lifecycle is tracked: requested → matched → driver en route → in progress →
  completed → paid.
- Riders and drivers can rate each other after a trip.

**Non-Functional Requirements**
- **Scale**: assume a large global player — 20 million daily active riders, 1 million
  daily active drivers, concentrated in ~50 major metro areas at any given moment.
- **Latency**: matching a rider to a driver should complete in under 3-5 seconds end to
  end (nearby-driver lookup + ranking + dispatch). Location map updates should feel
  live — sub-second to a couple of seconds of staleness is acceptable.
- **Availability**: this is a "money-moving, safety-adjacent" consumer app — favor high
  availability for search/matching (a few seconds of degraded ranking is better than a
  rider seeing no drivers at all), but trip state transitions (a driver is "claimed")
  must be strongly consistent — double-booking a driver is a hard failure, not a
  degraded experience.
- **Consistency**: driver location data can be eventually consistent (a driver's dot on
  the map can lag by a second or two). Driver *availability status* (free vs.
  on-a-trip) must be strongly consistent at the moment of matching — this is the classic
  tension in this system and drives most of the deep-dive design below.
- **Write-heavy on location**: every active driver's app pushes a GPS ping every 3-5
  seconds regardless of whether a trip is happening. This is the dominant write
  workload in the whole system, far exceeding trip-related writes.
- **Read-heavy on matching**: every ride request triggers a geospatial read across
  potentially thousands of nearby driver locations.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 1,000,000 daily active drivers, and at peak roughly 40% (400,000) are online and
  broadcasting location simultaneously (some driving passengers, some idle/available).
- Each online driver's app sends a location ping every 4 seconds.
- 20,000,000 daily active riders, each requesting on average 0.15 rides/day at peak
  usage patterns (most riders don't ride daily) → ~3,000,000 ride requests/day, but
  concentrated in AM/PM peaks.

**Location ping write QPS**
```
400,000 online drivers / 4 seconds per ping = 100,000 writes/sec (location updates)
```
This is the single largest sustained write load in the system — 100K writes/sec just
for "where is this driver right now," and it's *overwrite* traffic (the previous
location is discarded), not append-only history for most use cases.

**Ride request QPS**
```
3,000,000 requests/day, ~50% within a 4-hour combined peak window
= 1,500,000 requests / 14,400 sec ≈ 104 requests/sec average during peak
Assume 5x burst multiplier for rush-hour spikes in a single metro → ~500 requests/sec peak in one region
```

**Nearby-driver lookup fan-out**
Each ride request triggers one geospatial query that might scan/return ~50-200
candidate drivers within a few km radius in a dense city. At 500 req/sec peak, that's
25,000-100,000 candidate-driver evaluations/sec during a regional rush hour — cheap
individually (an in-memory geospatial index lookup), but it means the location store
must serve both the 100K writes/sec *and* these read bursts from the same hot dataset.

**Storage**
- **Live location state** (current position only, one row per online driver): 400,000
  drivers x ~150 bytes (driver_id, lat, lng, heading, speed, timestamp, status) ≈ 60 MB.
  Trivially fits in memory — this confirms live location belongs in an in-memory store,
  not a disk-backed table scanned per request.
- **Trip records**: 3,000,000 trips/day x ~2 KB per trip record (rider, driver, route
  summary, fare, timestamps, ratings) ≈ 6 GB/day, ≈ 2.2 TB/year. This is small and
  fits comfortably in a conventional relational database with time-based partitioning.
- **Location history for auditing/ML** (if retained): 100,000 writes/sec x 86,400 sec/day
  x ~100 bytes (compact form) ≈ 864 GB/day if every ping were durably logged. This is
  why raw location pings are NOT written to a durable log for every ping in the hot
  path — only sampled/aggregated trajectories are persisted (e.g., one point every
  15-30 seconds, or only during active trips), which cuts this by 5-10x.

**Bandwidth**
- Driver ping: ~200 bytes (payload + headers) x 100,000/sec ≈ 20 MB/sec inbound.
- Map location push to nearby riders (if riders watch driver dots live): comparable
  order of magnitude on the fan-out side, mitigated by only pushing to riders who have
  an active screen/trip watching a specific driver, not broadcasting globally.

These numbers justify the core architectural decision: **location is a high-volume,
ephemeral, in-memory problem; trips/payments are a low-volume, durable, relational
problem.** They should not share a database.

## Step 3: High-Level Design

**Core components**
- **Rider App / Driver App** — mobile clients; driver app streams location, rider app
  requests rides and renders the map.
- **API Gateway** — auth, rate limiting, routes requests to the right backend service.
- **Location Service** — ingests driver GPS pings at high write volume, writes into a
  geospatial in-memory store (Redis with geospatial commands, or a purpose-built
  location index), and serves "find drivers near (lat, lng)" queries.
- **Matching Service** — given a ride request, queries the Location Service for nearby
  *available* drivers, ranks candidates (ETA, rating, acceptance likelihood), and
  attempts to atomically claim one driver.
- **Trip Service** — owns trip lifecycle state (requested/matched/in_progress/completed)
  backed by a relational database; the source of truth for "what happened."
- **ETA/Routing Service** — wraps an external mapping/routing provider (e.g., a
  Google-Maps-like API) for route and ETA computation; not built in-house.
- **Notification Service** — pushes trip status updates to rider and driver devices
  (WebSocket/push notification) — reuses the same "push, don't poll" pattern used in
  chat and notification-system designs.
- **Payment Service** — settles fare at trip completion (delegates to the dedicated
  payment-system design for the ledger/idempotency mechanics).
- **Driver Status Store** — the strongly-consistent piece: tracks whether a driver is
  `available`, `pending_match`, or `on_trip`, and is the thing the atomic "claim"
  operation locks against.

**Data flow for a ride request**
1. Driver apps continuously push location → Location Service → in-memory geospatial
   index, keyed by metro region (sharded by city/geohash prefix, see Step 6).
2. Rider requests a ride → Matching Service asks Location Service for the N closest
   `available` drivers around the rider's coordinates.
3. Matching Service ranks candidates (ETA from Routing Service, rating, driver
   idle-time-fairness), and attempts to claim the top candidate via a conditional write
   against the Driver Status Store.
4. If the claim succeeds, Trip Service creates a trip record and Notification Service
   pushes the match to both rider and driver. If it fails (driver was claimed by a
   concurrent request or went offline), the Matching Service retries with the next
   candidate.
5. During the trip, the driver's location continues streaming; the rider's app
   subscribes to a live feed of that specific driver's position via the Notification
   Service (push channel), not by polling.
6. On completion, Trip Service finalizes the trip, hands off to Payment Service, and
   both apps show a summary/rating screen.

```text
                          +--------------------+
                          |     API Gateway     |
                          +----------+---------+
                                     |
          +--------------------------+--------------------------+
          |                          |                          |
+---------v---------+    +-----------v-----------+    +---------v---------+
|  Location Service  |    |    Matching Service    |    |    Trip Service    |
|  (ingest + query)  |<---|  (rank + claim driver)  |--->|  (lifecycle, SQL)  |
+---------+---------+    +-----------+-----------+    +---------+---------+
          |                          |                          |
   writes/reads              claim / lock                 create / update
          |                          |                          |
+---------v---------+    +-----------v-----------+    +---------v---------+
|  In-memory Geo     |    |   Driver Status Store   |    |   Trip Database    |
|  Index (Redis      |    |  (strongly consistent,  |    |   (SQL, sharded    |
|  GEO / quad-tree,  |    |  conditional writes)    |    |   by region)        |
|  sharded by city)  |    +------------------------+    +---------+---------+
+---------------------+                                          |
          ^                                                      v
          | GPS pings, ~every 3-5s                     +--------v---------+
          |                                             | Payment Service   |
+---------+---------+     +----------------------+      | (see payment      |
|    Driver App       |    |    ETA/Routing        |      |  system design)   |
+---------------------+    |  Service (external)   |      +-------------------+
                            +----------------------+
          +---------------------+       ^
          |    Rider App         |------+ (fare estimate)
          +---------------------+
                     ^
                     | live trip/driver updates (push, not poll)
                     |
          +----------+-----------+
          |  Notification Service |
          +-----------------------+
```

## Step 4: API Design

**`POST /v1/drivers/{driver_id}/location`** — high-frequency ping from the driver app.
```json
Request:  { "lat": 37.7749, "lng": -122.4194, "heading": 84, "speed_kmh": 22, "ts": 1699999999 }
Response: { "ack": true }
```
Fire-and-forget from the client's perspective; the server never blocks this path on
anything but the in-memory index write.

**`POST /v1/rides/request`** — rider requests a ride.
```json
Request:  { "rider_id": "r_123", "pickup": {"lat":37.77,"lng":-122.42}, "dropoff": {"lat":37.80,"lng":-122.41} }
Response: { "request_id": "req_789", "status": "searching" }
```

**`GET /v1/rides/{request_id}/status`** (or pushed via WebSocket instead of polled) —
poll/subscribe for match result.
```json
Response: { "status": "matched", "driver": { "id":"d_456","name":"Alex","eta_sec":180,"lat":37.771,"lng":-122.421 }, "fare_estimate": 14.50 }
```

**`POST /v1/drivers/{driver_id}/respond`** — driver accepts/rejects a dispatched match.
```json
Request:  { "request_id": "req_789", "response": "accept" }
Response: { "trip_id": "trip_555", "status": "confirmed" }
```

**`POST /v1/trips/{trip_id}/status`** — trip lifecycle transitions (arrived, started,
completed), driven by the driver app or geofence triggers.
```json
Request:  { "event": "trip_started", "ts": 1699999999 }
Response: { "trip_id": "trip_555", "status": "in_progress" }
```

**`GET /v1/trips/{trip_id}/track`** — live position stream for an in-progress trip,
implemented as a push subscription rather than repeated polling.
```json
Response (pushed): { "driver_lat": 37.775, "driver_lng": -122.419, "eta_to_dropoff_sec": 420 }
```

## Step 5: Data Model

**Live driver location — in-memory key-value / geospatial store (Redis-like)**
Chosen because this data is ephemeral (overwritten every few seconds, no need for
durability or transaction history), read/write latency must be sub-millisecond, and
Redis's `GEOADD`/`GEOSEARCH` commands give geospatial radius queries natively without
building custom indexing infrastructure.
```
Key:    geo:city:sf              (a Redis geo set, one per metro/region shard)
Member: driver_id
Value:  (lat, lng) encoded internally as a geohash-based sorted-set score

Key:    driver:status:{driver_id}   (a plain KV entry)
Value:  { "status": "available" | "pending_match" | "on_trip", "version": N }
```
The `version`/conditional-update field is what makes the "claim a driver" operation
safe under concurrency (Step 6).

**Trip records — relational (SQL) database**
Chosen because trips are low-volume relative to location pings, need multi-row
transactional guarantees (a trip creation must atomically reserve the driver and write
the trip row), require relational joins (rider history, driver history, fare
breakdown), and benefit from strong ACID guarantees for anything touching money.
```sql
CREATE TABLE trips (
  id            BIGINT PRIMARY KEY,
  rider_id      BIGINT NOT NULL,
  driver_id     BIGINT NOT NULL,
  status        VARCHAR(20) NOT NULL,  -- requested, matched, in_progress, completed, cancelled
  pickup_lat    DECIMAL(9,6), pickup_lng DECIMAL(9,6),
  dropoff_lat   DECIMAL(9,6), dropoff_lng DECIMAL(9,6),
  requested_at  TIMESTAMP,
  matched_at    TIMESTAMP,
  started_at    TIMESTAMP,
  completed_at  TIMESTAMP,
  fare_cents    INT,
  INDEX idx_rider (rider_id, requested_at),
  INDEX idx_driver (driver_id, requested_at)
);
```
Sharded by region/city (most queries are region-scoped) with a separate global lookup
by `trip_id` for cross-region support tooling.

**Driver profile / rider profile** — a standard relational table (rarely-updated
attributes: name, vehicle, rating aggregate) — read-heavy, cacheable, not on the
matching hot path directly.

## Step 6: Deep Dive

### 6.1 Geospatial indexing: finding nearby drivers efficiently

The naive approach — scan every online driver's location and compute distance to the
rider — is O(n) per request. With 400,000 online drivers and 500+ requests/sec, that's
untenable. The system needs an index that turns "give me drivers within 2 km" into a
narrow range query instead of a full scan.

**Geohashing** encodes a (lat, lng) pair into a base-32 string by recursively
subdividing the world into a grid: each additional character narrows the cell size
(roughly halving each dimension). The key property that makes it useful is that
**nearby locations tend to share a common string prefix** — two points a few hundred
meters apart will usually agree on the first 6-7 characters of their geohash. This
turns "find nearby drivers" into: compute the geohash of the rider's location, then
query for driver location-keys sharing the same prefix (or the prefix plus its 8
neighboring cells, to catch drivers just across a cell boundary — a well-known geohash
edge case, since two points can be meters apart but fall in different top-level cells
if they straddle a boundary). Because geohash strings sort lexicographically, this is
implementable as a range scan over a sorted structure — exactly what Redis's
sorted-set-backed `GEOADD`/`GEOSEARCH` commands do internally (they store a geohash-
derived score and do a range query under the hood).

**Quad-trees** are the alternative: a tree that recursively subdivides 2D space into
four quadrants, splitting a quadrant further only when it holds more than some
threshold of points. This gives a naturally *adaptive* resolution — dense areas
(downtown) get finely subdivided, sparse areas (suburbs) stay coarse — versus
geohashing's fixed-resolution grid at any given prefix length. The trade-off:
geohashing is simpler to shard (the prefix directly tells you which shard/machine owns
a region, and it works well with an off-the-shelf store like Redis with zero custom
tree-maintenance code), while a quad-tree gives better query efficiency in
highly non-uniform density (a fixed-resolution geohash grid either over-subdivides
sparse rural areas or under-subdivides dense downtown cores) at the cost of building
and maintaining custom tree infrastructure, including rebalancing as driver density
shifts through the day. For a ride-sharing system, geohashing via Redis is the
pragmatic default (matches the "use Redis geo commands" convention in the industry);
a quad-tree is worth the extra complexity mainly if driver density varies by orders of
magnitude across a single metro and query latency at the tails matters more than
operational simplicity.

### 6.2 Real-time driver location updates at scale

400,000 drivers pinging every 3-5 seconds is 100,000 writes/sec, and this is
*sustained*, not bursty — it never stops as long as drivers are online. Two design
decisions follow directly from this:

1. **Never write every raw ping to the primary relational database.** A relational
   store doing 100,000 row upserts/sec, every one immediately superseding the last, is
   both wasteful (paying for durability and transaction-log overhead on data that's
   obsolete in 4 seconds) and would saturate a SQL database's write path long before
   the rest of the system needs to scale. Instead, pings go to an in-memory geospatial
   store (Redis, sharded by city) that overwrites the previous position for that
   driver_id on every ping — there's no history to preserve for the live-tracking use
   case, only current state.
2. **Shard the location store by geography, not by driver_id hash.** Because every
   query is inherently geographic ("drivers near this point"), sharding by city/region
   means a single query hits a single shard instead of fanning out across all shards
   and merging results. A driver_id-hash shard (common for generic KV workloads) would
   scatter geographically-close drivers across random shards and turn every nearby-
   driver query into a scatter-gather across the whole cluster — exactly the wrong
   trade-off here.

If durable location history is needed later (for ML-based ETA models, fraud detection,
or trip replay), it's handled as a *separate* asynchronous pipeline: pings are also
published to a message queue/stream, and a downstream consumer samples/batches them
into a data warehouse — decoupled from the latency-critical write path so analytics
volume never threatens live-tracking latency.

### 6.3 The matching algorithm

Given a ride request, matching is a two-phase process: **retrieval**, then **ranking**.
Retrieval is the geospatial query described in 6.1 — pull the K nearest drivers whose
status is `available` (a radius search, expanding the search radius if too few
candidates are found nearby, e.g., start at 1 km and widen to 3 km, 5 km if needed).
Ranking then orders those candidates by a composite score — predicted ETA to pickup
(from the Routing Service, not straight-line distance, since straight-line distance is
a poor proxy in a city with rivers, highways, and one-way streets), driver rating, and
sometimes a fairness factor (how long since this driver's last trip, to avoid always
favoring the closest driver and starving others). The system deliberately keeps this
ranking function pluggable and secondary to the retrieval mechanism — the interview-
relevant engineering challenge is making the *candidate retrieval* sub-second at scale;
the ranking weights are a product/business decision layered on top of a small,
already-cheap candidate set (tens of drivers, not thousands).

### 6.4 ETA calculation

Road-network ETA (accounting for real streets, turns, current traffic) is a hard
problem in its own right — it depends on live traffic data and a routing graph of the
entire road network, which is squarely outside the scope of a ride-sharing system
design and is treated as an **external dependency**: a call to a maps/routing provider,
the same way a payment system treats a card network as external. What *is* worth
designing here is caching: ETA between two points changes slowly relative to how often
it's requested (traffic patterns shift over minutes, not seconds), so common route
segments — especially "driver's current geohash cell → rider's pickup geohash cell,"
recomputed periodically per traffic-condition bucket (e.g., every 60-120 seconds, or
on a significant traffic-state change) — can be cached and reused across the many
concurrent ride requests happening in the same neighborhood, rather than hitting the
external routing API on every single match attempt. This cache is naturally keyed by
(origin geohash prefix, destination geohash prefix, time-of-day bucket) and invalidated
on a short TTL.

### 6.5 Request lifecycle and race conditions: the atomic driver claim

This is the part of the system that must be strongly consistent even though almost
everything else can be eventually consistent. The failure mode to prevent: two
concurrent ride requests both see driver D as the best nearby candidate (both read
`status: available` from the Driver Status Store before either has written back), and
both try to dispatch to D — resulting in a double-booked driver.

The fix is the same pattern as `distributed_systems_core.md`'s distributed locks
section: the claim must be an **atomic conditional write**, not a read-then-write. In
practice: `SET driver:status:{id} = "pending_match" IF current value == "available"`
(a compare-and-swap, e.g., Redis `WATCH`/`MULTI` or a Lua script for atomicity, or an
optimistic-concurrency `UPDATE ... WHERE status = 'available' AND version = N` against a
strongly consistent store). Only one of the two concurrent requests' conditional write
succeeds; the loser immediately falls back to its next-ranked candidate from the
retrieval step, with no user-visible delay in the common case since retrieval already
returned multiple candidates. The claimed status is held as `pending_match` (not yet
`on_trip`) with a short timeout — if the driver doesn't respond (accept/reject) within
that window, the claim is released back to `available` automatically, so a
non-responsive driver app doesn't permanently strand the driver in a locked state.
This whole claim operation is intentionally scoped to a single key in a single store —
it does not need distributed consensus across multiple services, which keeps it fast
(sub-10ms) even though it must be strictly serialized per driver.

## Step 7: Bottlenecks & Trade-offs

- **The location store is the first thing to fall over.** 100,000 writes/sec sustained,
  concentrated on hot cells during rush hour in dense downtown geohash prefixes, means
  a single Redis shard covering "downtown SF" can become a hot spot even though the
  city-level shard count looks balanced overall. Mitigation: sub-shard the busiest
  cities by finer geohash prefix rather than one shard per city, and accept that this
  adds operational complexity (rebalancing shard boundaries as density patterns shift
  through the day).
- **Consistency vs. availability is split deliberately, not uniformly.** Location data
  favors availability (a stale dot on the map for a second is harmless); the driver
  claim favors consistency (a double-booked driver is a real-world failure — a driver
  physically can't serve two trips). Applying strong consistency everywhere would tank
  location-update throughput for no benefit; applying eventual consistency to the claim
  would cause double-bookings. This is a textbook case of choosing consistency
  per-operation rather than per-system.
- **Driver-side network unreliability.** A driver's phone can lose signal mid-ping-
  stream; the system must treat "haven't heard from this driver in N seconds" as
  "assume offline, evict from the geo index" via a TTL on the location entry (rather
  than an explicit offline signal, which the client can't reliably send if its
  connection just dropped).
- **The matching service scales horizontally but the driver claim is a serialization
  point per driver.** This is fine because contention is naturally partitioned — two
  riders competing for the exact same driver at the exact same second is rare relative
  to overall throughput — but it means the claim path can't be blindly sharded away
  from the location store the way stateless services can.
- **External ETA/routing dependency is a single point of latency risk.** If the routing
  provider is slow or down, matching can degrade to straight-line-distance ranking as a
  fallback rather than blocking ride requests entirely — an explicit trade-off of
  ranking accuracy for availability.

## Follow-up Questions an Interviewer Might Ask

**"How would you handle surge pricing?"** Track supply (available drivers) vs. demand
(ride requests) per geohash region over a short rolling window in the same in-memory
store already used for location; when the demand/supply ratio crosses thresholds, apply
a regional price multiplier that's fetched at fare-estimate time. This is a read-mostly
side computation layered on data the system already has, not a new data pipeline.

**"What if the driver cancels after accepting?"** Revert the trip to `searching`,
release the driver's status back to `available`, and immediately re-run the matching
retrieval (the rider ideally never sees a hard failure, just a brief "finding a new
driver" state). Log the cancellation against the driver for fraud/quality scoring.

**"How do you handle a rider requesting a ride at a location with very few nearby
drivers, e.g., a rural area?"** Progressive radius expansion (as in 6.3) with a
maximum radius and a user-visible "no drivers nearby, expanding search" or ultimately
"no drivers available" response rather than an unbounded search that blocks the
request indefinitely.

**"How would you support ride-pooling (multiple riders sharing a car)?"** This changes
matching from "nearest single driver" to a constrained optimization problem (route
overlap, detour tolerance, seat capacity) — worth mentioning as a fundamentally
harder variant, solved with batched matching windows (accumulate requests for a few
seconds, then jointly optimize) rather than the immediate per-request matching used for
solo rides.

**"How do you make the driver claim work if driver status is sharded across multiple
machines/regions?"** As long as a given driver's status always lives on the same
shard (hash-partitioned by driver_id, separate from the geo-sharded location index),
the conditional write stays a single-shard operation and needs no cross-shard
coordination — worth being explicit that location sharding (by geography) and status
sharding (by driver_id) can use different partitioning schemes for different reasons.

**"How would you test/validate the matching algorithm before shipping changes to
ranking weights?"** Replay historical ride-request logs against the new ranking logic
in a shadow/offline mode, comparing match quality (predicted vs. actual pickup ETA,
driver idle-time fairness) before rolling out live — an A/B test on live traffic only
after offline validation looks reasonable, since a bad live ranking change directly
costs real trips and real driver earnings.
