# Design a Ride-Sharing Service (Uber/Lyft)

## Problem Statement

"Design a ride-sharing platform jaise Uber. Ek rider app open karta hai, map par nearby
available drivers dekhta hai, ek ride request karta hai, aur kuch seconds mein ek
driver se match ho jaata hai. Driver pickup tak navigate karta hai, trip hoti hai, aur
end mein payment settle hota hai. Focus karo ki aap nearby drivers ko efficiently scale
par kaise dhundhoge aur match karoge, aur real-time location updates ko kaise handle
karoge jo poore system ko chalate hain."

Yeh fundamentally ek **geospatial matching problem hai ek tight latency budget ke
under** — interesting parts CRUD nahi hain (ek trip create karo, ek user lookup karo)
balki mechanics hain "kaun kiske paas hai, right now, out of millions of
constantly-moving points."

## Step 1: Clarify Requirements

**Functional Requirements**
- Riders map par near-real-time mein nearby available drivers dekh sakte hain.
- Riders apni current location se destination tak ek ride request kar sakte hain.
- System rider ko ek nearby available driver se kuch seconds mein match karta hai.
- Drivers ek ride request accept ya reject kar sakte hain.
- Dono parties dusre ki live location track kar sakte hain pickup aur trip ke dauraan.
- System ETA (time to pickup, time to destination) aur fare estimate compute karta hai.
- Trip lifecycle track hoti hai: requested → matched → driver en route → in progress →
  completed → paid.
- Riders aur drivers trip ke baad ek doosre ko rate kar sakte hain.

**Non-Functional Requirements**
- **Scale**: assume karo ek large global player — 20 million daily active riders,
  1 million daily active drivers, concentrated in ~50 major metro areas kisi bhi given
  moment par.
- **Latency**: rider ko driver se match karna 3-5 seconds end to end mein complete hona
  chahiye (nearby-driver lookup + ranking + dispatch). Location map updates live feel
  hone chahiye — sub-second se lekar couple of seconds ki staleness acceptable hai.
- **Availability**: yeh ek "money-moving, safety-adjacent" consumer app hai — favor
  karo high availability search/matching ke liye (rider ko kuch seconds ka degraded
  ranking milna better hai us se ki rider ko koi drivers hi na dikhein), lekin trip
  state transitions (ek driver "claimed" hai) strongly consistent hone chahiye —
  ek driver ko double-book karna ek hard failure hai, degraded experience nahi.
- **Consistency**: driver location data eventually consistent ho sakta hai (map par
  ek driver ka dot ek ya do second lag kar sakta hai). Driver *availability status*
  (free vs. on-a-trip) matching ke moment par strongly consistent hona chahiye — yeh
  is system mein classic tension hai aur neeche ka zyadatar deep-dive design isi se
  drive hota hai.
- **Write-heavy on location**: har active driver ka app har 3-5 seconds mein ek GPS
  ping push karta hai, chahe trip ho raha ho ya nahi. Yeh poore system ka dominant
  write workload hai, trip-related writes se kaafi zyada.
- **Read-heavy on matching**: har ride request ek geospatial read trigger karta hai
  potentially thousands nearby driver locations ke across.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 1,000,000 daily active drivers, aur peak par roughly 40% (400,000) online hote hain
  aur simultaneously location broadcast kar rahe hote hain (kuch passengers drive kar
  rahe, kuch idle/available).
- Har online driver ka app har 4 seconds mein ek location ping bhejta hai.
- 20,000,000 daily active riders, har ek average 0.15 rides/din request karta hai peak
  usage patterns par (zyadatar riders daily ride nahi karte) → ~3,000,000 ride
  requests/din, lekin AM/PM peaks mein concentrated.

**Location ping write QPS**
```
400,000 online drivers / 4 seconds per ping = 100,000 writes/sec (location updates)
```
Yeh system ka single largest sustained write load hai — 100K writes/sec sirf "yeh
driver abhi kahan hai" ke liye, aur yeh *overwrite* traffic hai (previous location
discard ho jaata hai), zyadatar use cases ke liye append-only history nahi.

**Ride request QPS**
```
3,000,000 requests/day, ~50% ek 4-hour combined peak window ke andar
= 1,500,000 requests / 14,400 sec ≈ 104 requests/sec average peak ke dauraan
Assume karo 5x burst multiplier rush-hour spikes ke liye ek single metro mein → ~500 requests/sec peak ek region mein
```

**Nearby-driver lookup fan-out**
Har ride request ek geospatial query trigger karta hai jo ek dense city mein ~50-200
candidate drivers scan/return kar sakta hai kuch km radius ke andar. 500 req/sec peak
par, yeh 25,000-100,000 candidate-driver evaluations/sec hain ek regional rush hour ke
dauraan — individually cheap (ek in-memory geospatial index lookup), lekin iska matlab
hai location store ko dono 100K writes/sec *aur* yeh read bursts same hot dataset se
serve karne padte hain.

**Storage**
- **Live location state** (current position only, ek row per online driver): 400,000
  drivers x ~150 bytes (driver_id, lat, lng, heading, speed, timestamp, status) ≈ 60 MB.
  Trivially memory mein fit ho jaata hai — yeh confirm karta hai ki live location
  in-memory store mein belong karta hai, na ki per-request scan ki jaane wali disk-backed
  table mein.
- **Trip records**: 3,000,000 trips/din x ~2 KB per trip record (rider, driver, route
  summary, fare, timestamps, ratings) ≈ 6 GB/day, ≈ 2.2 TB/year. Yeh chhota hai aur
  comfortably ek conventional relational database mein time-based partitioning ke saath
  fit ho jaata hai.
- **Location history for auditing/ML** (agar retain kiya jaaye): 100,000 writes/sec x
  86,400 sec/day x ~100 bytes (compact form) ≈ 864 GB/day agar har ping durably log kiya
  jaaye. Yahi wajah hai raw location pings hot path mein durable log mein har ping ke
  liye NAHI likhe jaate — sirf sampled/aggregated trajectories persist ki jaati hain
  (e.g., har 15-30 seconds mein ek point, ya sirf active trips ke dauraan), jo isse
  5-10x cut kar deta hai.

**Bandwidth**
- Driver ping: ~200 bytes (payload + headers) x 100,000/sec ≈ 20 MB/sec inbound.
- Map location push to nearby riders (agar riders driver dots live watch karte hain):
  fan-out side par comparable order of magnitude, mitigated iske through ki sirf un
  riders ko push kiya jaata hai jinki ek active screen/trip ek specific driver watch
  kar rahi hai, globally broadcast nahi kiya jaata.

Yeh numbers core architectural decision ko justify karte hain: **location ek
high-volume, ephemeral, in-memory problem hai; trips/payments ek low-volume, durable,
relational problem hain.** Inhe ek database share nahi karni chahiye.

## Step 3: High-Level Design

**Core components**
- **Rider App / Driver App** — mobile clients; driver app location stream karta hai,
  rider app rides request karta hai aur map render karta hai.
- **API Gateway** — auth, rate limiting, requests ko sahi backend service tak route
  karta hai.
- **Location Service** — driver GPS pings ko high write volume par ingest karta hai,
  ek geospatial in-memory store mein likhta hai (Redis geospatial commands ke saath, ya
  ek purpose-built location index), aur "find drivers near (lat, lng)" queries serve
  karta hai.
- **Matching Service** — ek ride request diye jaane par, Location Service se nearby
  *available* drivers query karta hai, candidates ko rank karta hai (ETA, rating,
  acceptance likelihood), aur ek driver ko atomically claim karne ki koshish karta hai.
- **Trip Service** — trip lifecycle state (requested/matched/in_progress/completed) own
  karta hai ek relational database ke backed; "kya hua" ke liye source of truth.
- **ETA/Routing Service** — ek external mapping/routing provider (e.g., ek
  Google-Maps-jaisi API) ko route aur ETA computation ke liye wrap karta hai; in-house
  build nahi kiya gaya.
- **Notification Service** — trip status updates rider aur driver devices ko push
  karta hai (WebSocket/push notification) — wahi "push, poll mat karo" pattern reuse
  karta hai jo chat aur notification-system designs mein use hua hai.
- **Payment Service** — trip completion par fare settle karta hai (ledger/idempotency
  mechanics ke liye dedicated payment-system design ko delegate karta hai).
- **Driver Status Store** — strongly-consistent piece: track karta hai ki driver
  `available`, `pending_match`, ya `on_trip` hai, aur yehi cheez hai jispar atomic
  "claim" operation lock karta hai.

**Data flow for a ride request**
1. Driver apps continuously location push karte hain → Location Service → in-memory
   geospatial index, metro region se keyed (city/geohash prefix se sharded, dekho
   Step 6).
2. Rider ek ride request karta hai → Matching Service, Location Service se rider ke
   coordinates ke around N closest `available` drivers maangta hai.
3. Matching Service candidates ko rank karta hai (Routing Service se ETA, rating,
   driver idle-time-fairness), aur top candidate ko claim karne ki koshish karta hai ek
   conditional write ke through Driver Status Store ke against.
4. Agar claim succeed karta hai, Trip Service ek trip record create karta hai aur
   Notification Service match ko rider aur driver dono ko push karta hai. Agar yeh fail
   hota hai (driver concurrent request se claim ho gaya ya offline chala gaya), Matching
   Service next candidate ke saath retry karta hai.
5. Trip ke dauraan, driver ki location stream hoti rehti hai; rider ka app us specific
   driver ki position ke live feed ko Notification Service (push channel) ke through
   subscribe karta hai, poll karke nahi.
6. Completion par, Trip Service trip finalize karta hai, Payment Service ko hand off
   karta hai, aur dono apps ek summary/rating screen dikhate hain.

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

**`POST /v1/drivers/{driver_id}/location`** — driver app se high-frequency ping.
```json
Request:  { "lat": 37.7749, "lng": -122.4194, "heading": 84, "speed_kmh": 22, "ts": 1699999999 }
Response: { "ack": true }
```
Client ke perspective se fire-and-forget; server iss path ko kabhi block nahi karta
sirf in-memory index write ke alawa kisi cheez par.

**`POST /v1/rides/request`** — rider ek ride request karta hai.
```json
Request:  { "rider_id": "r_123", "pickup": {"lat":37.77,"lng":-122.42}, "dropoff": {"lat":37.80,"lng":-122.41} }
Response: { "request_id": "req_789", "status": "searching" }
```

**`GET /v1/rides/{request_id}/status`** (ya WebSocket ke through push kiya jaata hai
poll karne ki jagah) — match result ke liye poll/subscribe karo.
```json
Response: { "status": "matched", "driver": { "id":"d_456","name":"Alex","eta_sec":180,"lat":37.771,"lng":-122.421 }, "fare_estimate": 14.50 }
```

**`POST /v1/drivers/{driver_id}/respond`** — driver ek dispatched match ko
accept/reject karta hai.
```json
Request:  { "request_id": "req_789", "response": "accept" }
Response: { "trip_id": "trip_555", "status": "confirmed" }
```

**`POST /v1/trips/{trip_id}/status`** — trip lifecycle transitions (arrived, started,
completed), driver app ya geofence triggers se driven.
```json
Request:  { "event": "trip_started", "ts": 1699999999 }
Response: { "trip_id": "trip_555", "status": "in_progress" }
```

**`GET /v1/trips/{trip_id}/track`** — ek in-progress trip ke liye live position
stream, repeated polling ki jagah ek push subscription ki tarah implemented.
```json
Response (pushed): { "driver_lat": 37.775, "driver_lng": -122.419, "eta_to_dropoff_sec": 420 }
```

## Step 5: Data Model

**Live driver location — in-memory key-value / geospatial store (Redis-like)**
Yeh choose kiya gaya kyunki yeh data ephemeral hai (har kuch seconds mein overwrite
hota hai, koi durability ya transaction history ki need nahi), read/write latency
sub-millisecond honi chahiye, aur Redis ke `GEOADD`/`GEOSEARCH` commands geospatial
radius queries natively de dete hain bina custom indexing infrastructure banaye.
```
Key:    geo:city:sf              (ek Redis geo set, ek per metro/region shard)
Member: driver_id
Value:  (lat, lng) internally ek geohash-based sorted-set score ki tarah encoded

Key:    driver:status:{driver_id}   (ek plain KV entry)
Value:  { "status": "available" | "pending_match" | "on_trip", "version": N }
```
`version`/conditional-update field hi wahi cheez hai jo "driver claim karo" operation
ko concurrency ke under safe banata hai (Step 6).

**Trip records — relational (SQL) database**
Yeh choose kiya gaya kyunki trips location pings ke relative low-volume hote hain,
inhe multi-row transactional guarantees chahiye (ek trip creation ko atomically driver
reserve aur trip row write karna chahiye), inhe relational joins chahiye (rider
history, driver history, fare breakdown), aur money touch karne wali kisi bhi cheez ke
liye strong ACID guarantees se benefit hota hai.
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
Region/city se sharded (zyadatar queries region-scoped hote hain) ek separate global
lookup ke saath `trip_id` se, cross-region support tooling ke liye.

**Driver profile / rider profile** — ek standard relational table (rarely-updated
attributes: name, vehicle, rating aggregate) — read-heavy, cacheable, directly matching
hot path par nahi.

## Step 6: Deep Dive

### 6.1 Geospatial indexing: finding nearby drivers efficiently

Naive approach — har online driver ki location scan karo aur rider tak distance
compute karo — O(n) per request hai. 400,000 online drivers aur 500+ requests/sec ke
saath, yeh untenable hai. System ko ek index chahiye jo "2 km ke andar drivers do" ko
ek full scan ki jagah ek narrow range query mein badal de.

**Geohashing** ek (lat, lng) pair ko ek base-32 string mein encode karta hai world ko
recursively ek grid mein subdivide karke: har additional character cell size ko narrow
karta hai (roughly har dimension ko half karke). Key property jo isse useful banati hai
yeh hai ki **nearby locations usually ek common string prefix share karte hain**: do
points jo kuch sau meters apart hain, usually apne geohash ke pehle 6-7 characters par
agree karte hain. Yeh "nearby drivers dhundo" ko is mein badal deta hai: rider ki
location ka geohash compute karo, phir driver location-keys ke liye query karo jo same
prefix share karte hain (ya prefix plus uske 8 neighboring cells, un drivers ko catch
karne ke liye jo cell boundary ke bilkul across hain — ek well-known geohash edge case,
kyunki do points meters apart ho sakte hain lekin different top-level cells mein aa
sakte hain agar woh ek boundary straddle karte hain). Kyunki geohash strings
lexicographically sort hoti hain, yeh implementable hai ek range scan ki tarah ek
sorted structure ke upar — exactly wahi jo Redis ke sorted-set-backed
`GEOADD`/`GEOSEARCH` commands internally karte hain (woh ek geohash-derived score store
karte hain aur under the hood ek range query karte hain).

**Quad-trees** alternative hain: ek tree jo 2D space ko recursively char quadrants mein
subdivide karta hai, ek quadrant ko sirf tab further split karta hai jab woh kisi
threshold se zyada points hold karta hai. Yeh naturally ek *adaptive* resolution deta
hai — dense areas (downtown) finely subdivided ho jaate hain, sparse areas (suburbs)
coarse rehte hain — versus geohashing ka fixed-resolution grid kisi bhi given prefix
length par. Trade-off: geohashing shard karne mein simpler hai (prefix directly bata
deta hai kaunsa shard/machine ek region owns karta hai, aur yeh ek off-the-shelf store
jaise Redis ke saath zero custom tree-maintenance code se accha kaam karta hai), jabki
ek quad-tree highly non-uniform density mein better query efficiency deta hai (ek
fixed-resolution geohash grid ya toh sparse rural areas ko over-subdivide karta hai ya
dense downtown cores ko under-subdivide karta hai) custom tree infrastructure build aur
maintain karne ki cost par, including rebalancing jaise driver density din bhar shift
hoti hai. Ek ride-sharing system ke liye, Redis ke through geohashing pragmatic default
hai (industry mein "Redis geo commands use karo" convention se match karta hai); ek
quad-tree extra complexity ke liye worth hai mainly agar driver density ek single metro
ke across orders of magnitude se vary karti hai aur tails par query latency operational
simplicity se zyada matter karti hai.

### 6.2 Real-time driver location updates at scale

400,000 drivers har 3-5 seconds mein ping karte hain, matlab 100,000 writes/sec, aur
yeh *sustained* hai, bursty nahi — jab tak drivers online hain, yeh kabhi nahi rukta.
Do design decisions isse directly follow karte hain:

1. **Har raw ping ko kabhi primary relational database mein mat likho.** Ek
   relational store 100,000 row upserts/sec kar raha ho, har ek turant last ko supersede
   kar raha ho, dono wasteful hai (aisi data par durability aur transaction-log
   overhead pay karna jo 4 seconds mein obsolete ho jaata hai) aur ek SQL database ke
   write path ko bahut pehle hi saturate kar dega us se pehle ki system ke baaki hisse
   ko scale karne ki zaroorat pade. Iski jagah, pings ek in-memory geospatial store
   (Redis, city se sharded) mein jaate hain jo har ping par us driver_id ke liye
   previous position overwrite kar deta hai — live-tracking use case ke liye koi
   history preserve karne ki zaroorat nahi, sirf current state.
2. **Location store ko geography se shard karo, driver_id hash se nahi.** Kyunki har
   query inherently geographic hai ("iss point ke paas drivers"), city/region se
   sharding ka matlab hai ek single query ek single shard ko hit karti hai, na ki sabhi
   shards ke across fan out karke results merge karna. Ek driver_id-hash shard (generic
   KV workloads ke liye common) geographically-close drivers ko random shards mein
   scatter kar dega aur har nearby-driver query ko poore cluster ke across ek
   scatter-gather bana dega — exactly wrong trade-off yahan.

Agar durable location history baad mein chahiye (ML-based ETA models, fraud detection,
ya trip replay ke liye), toh yeh ek *separate* asynchronous pipeline ki tarah handle
kiya jaata hai: pings ek message queue/stream par bhi publish kiye jaate hain, aur ek
downstream consumer unhe sample/batch karke ek data warehouse mein daal deta hai —
latency-critical write path se decoupled taaki analytics volume kabhi live-tracking
latency ko threaten na kare.

### 6.3 The matching algorithm

Ek ride request diye jaane par, matching ek two-phase process hai: **retrieval**, phir
**ranking**. Retrieval woh geospatial query hai jo 6.1 mein describe hui — K nearest
drivers pull karo jinka status `available` hai (ek radius search, search radius ko
expand karte hue agar bahut kam candidates nearby milein, e.g., 1 km se shuru karke 3
km, 5 km tak widen karo agar zaroorat pade). Ranking phir un candidates ko ek composite
score se order karta hai — pickup tak predicted ETA (Routing Service se, straight-line
distance se nahi, kyunki straight-line distance ek poor proxy hai ek city mein jahan
rivers, highways, aur one-way streets hain), driver rating, aur kabhi kabhi ek fairness
factor (kitni der ho gayi is driver ki last trip se, taaki hamesha closest driver ko
favor karke doosron ko starve na kiya jaaye). System deliberately is ranking function
ko pluggable aur secondary rakhta hai retrieval mechanism ke, retrieval hi hai
interview-relevant engineering challenge — *candidate retrieval* ko scale par
sub-second banana; ranking weights ek product/business decision hain jo already ek
chhote, already-cheap candidate set (tens of drivers, thousands nahi) ke upar layered
hain.

### 6.4 ETA calculation

Road-network ETA (real streets, turns, current traffic ko account karte hue) apne aap
mein ek hard problem hai — yeh live traffic data aur poore road network ke ek routing
graph par depend karta hai, jo ek ride-sharing system design ke scope se squarely bahar
hai aur ek **external dependency** ki tarah treat kiya jaata hai: ek maps/routing
provider ko ek call, wahi tarike se jaise ek payment system ek card network ko external
treat karta hai. Yahan jo design karna worth hai woh hai caching: do points ke beech
ETA relatively slowly change hota hai us hisaab se ki yeh kitni baar request hota hai
(traffic patterns minutes mein shift hote hain, seconds mein nahi), isliye common route
segments — especially "driver ka current geohash cell → rider ka pickup geohash cell,"
periodically per traffic-condition bucket recompute kiya jaata hai (e.g., har 60-120
seconds, ya ek significant traffic-state change par) — cache aur reuse kiya ja sakta
hai us same neighborhood mein ho rahe many concurrent ride requests ke across, har
single match attempt par external routing API hit karne ki jagah. Yeh cache naturally
(origin geohash prefix, destination geohash prefix, time-of-day bucket) se keyed hota
hai aur ek short TTL par invalidated hota hai.

### 6.5 Request lifecycle and race conditions: the atomic driver claim

Yeh system ka woh hissa hai jo strongly consistent hona chahiye chahe baaki sab kuch
eventually consistent ho sakta ho. Failure mode jise prevent karna hai: do concurrent
ride requests dono driver D ko best nearby candidate ki tarah dekhte hain (dono
`status: available` read karte hain Driver Status Store se pehle koi bhi wapas likhe),
aur dono D ko dispatch karne ki koshish karte hain — resulting ek double-booked driver
mein.

Fix wahi pattern hai jo `distributed_systems_core.md` ke distributed locks section
mein hai: claim ek **atomic conditional write** hona chahiye, read-then-write nahi.
Practice mein: `SET driver:status:{id} = "pending_match" IF current value ==
"available"` (ek compare-and-swap, e.g., Redis `WATCH`/`MULTI` ya atomicity ke liye ek
Lua script, ya ek optimistic-concurrency `UPDATE ... WHERE status = 'available' AND
version = N` ek strongly consistent store ke against). Do concurrent requests mein se
sirf ek ka conditional write succeed karta hai; loser turant apne next-ranked candidate
par fall back karta hai retrieval step se, common case mein koi user-visible delay nahi
hoti kyunki retrieval already multiple candidates return kar chuka tha. Claimed status
`pending_match` (abhi `on_trip` nahi) ki tarah hold kiya jaata hai ek short timeout ke
saath — agar driver us window ke andar respond (accept/reject) nahi karta, claim
automatically wapas `available` ho jaata hai release, taaki ek non-responsive driver
app driver ko permanently ek locked state mein strand na kar de. Yeh poora claim
operation intentionally ek single key ek single store mein scoped hai — isse multiple
services ke across distributed consensus ki zaroorat nahi hoti, jo isse fast (sub-10ms)
rakhta hai chahe isse per driver strictly serialized hona chahiye.

## Step 7: Bottlenecks & Trade-offs

- **Location store sabse pehli cheez hai jo fall over hoti hai.** 100,000 writes/sec
  sustained, rush hour ke dauraan dense downtown geohash prefixes mein hot cells par
  concentrated, matlab ek single Redis shard jo "downtown SF" cover karta hai ek hot
  spot ban sakta hai chahe city-level shard count overall balanced dikhta ho. Mitigation:
  busiest cities ko finer geohash prefix se sub-shard karo ek city ke liye ek shard ki
  jagah, aur accept karo ki isse operational complexity add hoti hai (shard boundaries
  ko rebalance karna jaise density patterns din bhar shift hote hain).
- **Consistency vs. availability deliberately split hai, uniformly nahi.** Location
  data availability favor karta hai (map par ek stale dot ek second ke liye harmless
  hai); driver claim consistency favor karta hai (ek double-booked driver ek real-world
  failure hai — ek driver physically do trips serve nahi kar sakta). Everywhere strong
  consistency apply karna location-update throughput ko bina kisi benefit ke tank kar
  dega; claim par eventual consistency apply karna double-bookings cause karega. Yeh ek
  textbook case hai per-system ki jagah per-operation consistency choose karne ka.
- **Driver-side network unreliability.** Ek driver ka phone mid-ping-stream signal lose
  kar sakta hai; system ko "is driver se N seconds se kuch nahi suna" ko "assume karo
  offline, geo index se evict karo" ki tarah treat karna padega ek TTL ke through
  location entry par (ek explicit offline signal ki jagah, jo client reliably send
  nahi kar sakta agar uska connection abhi drop hua ho).
- **Matching service horizontally scale karti hai lekin driver claim per driver ek
  serialization point hai.** Yeh theek hai kyunki contention naturally partitioned hai
  (do riders exact same driver ke liye exact same second par compete karein, yeh
  overall throughput ke relative rare hai) — lekin iska matlab hai claim path ko
  blindly location store se alag shard nahi kiya ja sakta jaise stateless services
  se kiya ja sakta hai.
- **External ETA/routing dependency ek single point of latency risk hai.** Agar
  routing provider slow ya down hai, matching straight-line-distance ranking par
  degrade ho sakta hai ek fallback ki tarah, ride requests ko poori tarah block karne
  ki jagah — ranking accuracy ka availability ke liye ek explicit trade-off.

## Follow-up Questions an Interviewer Might Ask

**"Aap surge pricing kaise handle karenge?"** Supply (available drivers) vs. demand
(ride requests) ko per geohash region ek short rolling window mein track karo usi
in-memory store mein jo already location ke liye use ho raha hai; jab demand/supply
ratio thresholds cross kare, ek regional price multiplier apply karo jo fare-estimate
time par fetch kiya jaata hai. Yeh ek read-mostly side computation hai jo data ke upar
layered hai jo system ke paas already hai, ek naya data pipeline nahi.

**"Agar driver accept karne ke baad cancel kar de toh?"** Trip ko `searching` mein
revert karo, driver ka status wapas `available` par release karo, aur turant matching
retrieval dubara run karo (rider ideally kabhi ek hard failure nahi dekhta, bas ek
brief "naya driver dhoonda ja raha hai" state). Cancellation ko driver ke against log
karo fraud/quality scoring ke liye.

**"Aap ek rider ko handle kaise karenge jo ek aisi location par ride request karta hai
jahan bahut kam nearby drivers hain, e.g., ek rural area?"** Progressive radius
expansion (6.3 ki tarah) ek maximum radius ke saath aur ek user-visible "koi drivers
nearby nahi, search expand ki jaa rahi hai" ya ultimately "koi drivers available nahi"
response ke saath, ek unbounded search ki jagah jo request ko indefinitely block kar de.

**"Aap ride-pooling (multiple riders ek car share karte hue) kaise support karenge?"**
Yeh matching ko "nearest single driver" se ek constrained optimization problem mein
badal deta hai (route overlap, detour tolerance, seat capacity) — mention karne
worth hai ki yeh ek fundamentally harder variant hai, batched matching windows se solve
kiya jaata hai (kuch seconds ke liye requests accumulate karo, phir jointly optimize
karo) instead of immediate per-request matching jo solo rides ke liye use hoti hai.

**"Aap driver claim ko kaise kaam karayenge agar driver status multiple
machines/regions ke across sharded ho?"** Jab tak ek given driver ka status hamesha
same shard par rehta hai (driver_id se hash-partitioned, geo-sharded location index se
separate), conditional write ek single-shard operation rehta hai aur koi cross-shard
coordination ki zaroorat nahi hoti — yeh explicit hona worth hai ki location sharding
(geography se) aur status sharding (driver_id se) different partitioning schemes use
kar sakte hain different reasons ke liye.

**"Aap matching algorithm ko test/validate kaise karenge ranking weights mein changes
ship karne se pehle?"** Historical ride-request logs ko naye ranking logic ke against
replay karo ek shadow/offline mode mein, match quality compare karte hue (predicted vs.
actual pickup ETA, driver idle-time fairness) live rollout se pehle — live traffic par
A/B test sirf offline validation reasonable lagne ke baad karo, kyunki ek bad live
ranking change directly real trips aur real driver earnings cost karta hai.
