# Design a Proximity/Nearby Search Service

## Problem Statement

"Design a service like Yelp's 'restaurants near me' — given a user's location and a search radius (and maybe a category like 'coffee'), return nearby points of interest ranked by some mix of distance and relevance. Assume there are tens of millions of businesses/POIs worldwide and a large, geographically distributed user base issuing these searches constantly. How would you build the indexing and query path?"

Yeh question frequently pair kiya jaata hai, ya contrast kiya jaata hai, ek ride-sharing/driver-matching design ke saath (dekho `12_ride_sharing_uber.md`). Interviewers isko specifically isliye poochte hain yeh dekhne ke liye ki candidate reflexively ek live-geospatial-index solution ko ek different problem se reapply karta hai, ya recognize karta hai ki yahan read/write characteristics fundamentally different hain aur ek different — aur kuch tarikon se simpler — architecture lead karte hain.

## Step 1: Clarify Requirements

**Functional Requirements**
- Given (latitude, longitude, radius, category filter), radius ke andar matching POIs return karo, distance aur relevance/rating ke ek blend se ranked.
- Category/keyword filtering support karo (e.g. "coffee," "italian restaurant").
- List view ke liye har POI par kaafi detail return karo: name, address, distance, rating, open/closed status, thumbnail.
- POI detail lookup support karo (full profile: hours, menu, reviews) ek secondary read path ke roop mein.
- Business owners apne khud ke POI ki info update kar sakein (hours, address, category) — ek low-frequency write path.
- New POIs add ho sakein (ek business khulta hai) aur existing ones remove/deactivate ho sakein (ek business band hota hai) — yeh bhi low-frequency.

**Non-Functional Requirements**
- Scale: 50 million POIs worldwide, 20 million daily active users, har ek session mein handful of nearby-searches issue karta hai — assume karo 100 million nearby-search requests/day.
- Read:write ratio: overwhelmingly read-heavy. POI data shayad har kuch weeks mein ek baar change hota hai per business (hours, menu updates) versus potentially thousands of times per day read hone ke against agar popular ho — ek ratio easily 10,000:1 ya usse zyada range mein, ek live-location system se sharp contrast mein.
- Latency: search results ko 200ms p99 se well under return hona chahiye — yeh ek interactive, impatient UI hai (ek user jo map ya list scroll kar raha hai).
- Freshness: POI location/details real-time fresh hone ki zaroorat nahi hai — ek business ka data kuch ghante ya even ek din stale hona (new hours abhi tak reflect nahi hue) ek acceptable trade-off hai, jo ek live-position system jaise ride-hailing mein NOT acceptable hai.
- Consistency: eventual consistency search results ke liye entirely fine hai; strong consistency is system mein kahin bhi requirement nahi hai except perhaps business owner ka apna edit-confirmation flow.
- Availability: search available rehni chahiye even if write path (POI edits) degraded ho — reads write-path health se coupled nahi hone chahiye.
- Geographic distribution: users aur POIs global hain; results user jahan bhi search kar raha ho relevant hone chahiye, bina artificially ek region ke infrastructure ko favor kiye (yeh users ke globally close read replicas / caches ke liye argue karta hai).

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 50M POIs, 100M search requests/day.
- Average search radius: ek dense urban area mein kuch kilometers, rural area mein bada — assume karo ek search typically ranking se pehle ek candidate set of kuch sau se kuch hazaar POIs consider karta hai.

**Query rate**
- 100M requests/day / 86,400 sec/day ≈ 1,157 requests/sec average; daytime/meal-time clustering ke liye ek 5x peak multiplier assume karo ≈ 5,800 requests/sec peak.

**Storage**
- Har POI record: id, name, lat/long, category, address, rating, hours, metadata ≈ 1 KB (large media jaise photos exclude karke, jo object storage mein rehte hain URL se referenced, inline nahi).
- 50M POIs x 1 KB ≈ 50 GB core searchable dataset ke liye — comfortably ek modest cluster ke across memory mein fit ho jaata hai, matlab poora geo-index realistically memory-resident ya near-memory-resident ho sakta hai, unlike ek system jismein terabytes of core data ho.

**Geo-index size**
- Agar geohash cells ke through indexed kiya jaaye ek resolution par jahan har cell roughly ek city-block-to-neighborhood scale cover karta hai (e.g. geohash precision 6, ~1.2km x 0.6km per cell), aur POIs unevenly distributed hain (cities mein dense, elsewhere sparse) — ek reasonable estimate hai worldwide kuch million populated cells, har ek ek POI-ID list hold karta hai. Index overhead (cell key + POI ID list) POI records ke khud se choti hai relatively, 50 GB core dataset size se well under.

**Bandwidth**
- Har search response: ~20 results x ~0.5 KB (name, distance, rating, thumbnail URL) ≈ 10 KB.
- 5,800 requests/sec x 10 KB ≈ 58 MB/sec peak par — modest, aur yeh exactly wahi kism ka traffic hai jise caching (Step 6) dramatically further reduce karti hai, kyunki requests ka ek bada fraction popular (location, category) combinations ke liye hota hai jo many different users ke across repeat hote hain.

**Write rate**
- Even generously assume karo ki 50M POIs mein se 5% ek given month mein kuch update karte hain, toh yeh 2.5M updates/month ≈ 83,000/day ≈ ~1/sec average hai — read rate ke comparison mein utterly trivial, isse reinforce hota hai ki is system ki poori architecture read throughput ke liye optimized honi chahiye, write path ko simple rakhte hue instead of aggressively highly available banane ke jaisa ek write-heavy system ko chahiye hota.

## Step 3: High-Level Design

**Ride-sharing driver-location problem ke saath contrast upfront**: `12_ride_sharing_uber.md` ek HIGH-WRITE geospatial problem solve karta hai — driver positions har kuch seconds mein change hoti hain, har active driver ke liye, aur index ko near-real-time positions reflect karni hoti hai kyunki ek stale driver location directly ek bad match lead karta hai (rider ko ek driver ki taraf route karna jo already door move ho chuka hai). Yeh system iska mirror image hai: POI positions essentially static hain (ek restaurant move nahi hota), aur read volume write volume ko vastly dominate karta hai. Yeh difference right architecture ko ek concrete tarike se change karta hai: ek live-updating in-memory geospatial index ke bajaye jo constant position churn absorb kare, yeh system ek aisa index use kar sakta hai jo mostly offline/periodically build hota hai aur largely cache se serve hota hai, kyunki yahan aisa "live" kuch nahi hai jise moment to moment reflect karna ho.

**Core components**
- **POI Write Service**: business owner edits handle karta hai (hours, category, address) — low volume, straightforward CRUD service ban sakta hai primary database ke against.
- **Primary POI Database**: sab POI data ke liye durable system of record.
- **Geo-Index Builder**: ek batch/periodic process (e.g. har kuch minutes se hours mein chalta hai, continuously nahi) jo geospatial index (geohash-cell-to-POI-ID mappings) primary database se (re)build ya incrementally update karta hai.
- **Geo-Index (read-optimized, heavily cached)**: geo-cells ko unke andar wale POI IDs se map karta hai; yeh woh cheez hai jise ek search query sabse pehle consult karti hai.
- **Search/Ranking Service**: ek search request leta hai, usse relevant geo-cells resolve karta hai, candidate POI IDs retrieve karta hai, unke details fetch karta hai, aur blended distance + rating + relevance se candidate set rank karta hai.
- **Cache layer** (e.g. Redis, `05_caching.md` ke according): popular (location-bucket, category) query combinations ke liye full search results cache karta hai, aur individual POI detail lookups cache karta hai.
- **Read Replicas** primary database ke, geographically distributed, ek fallback/detail-lookup path serve karte hue jab cache miss ho.

**Data flow**
1. Business owner POI info update karta hai → Primary POI Database mein likha jaata hai (low volume, straightforward path, koi special scaling nahi chahiye).
2. Geo-Index Builder periodically (e.g. har 15 minutes, ya incrementally write par ek change-data-capture stream ke through near-immediate but still not "live" freshness ke liye) changed POIs read karta hai aur geo-index ke cell mappings update karta hai.
3. User ek nearby-search issue karta hai: `GET /search?lat=..&long=..&radius=..&category=coffee`.
4. Search Service compute karta hai kaunse geo-cells requested radius cover karte hain, pehle is (cell-bucket, category) combination ke liye result cache check karta hai.
5. Cache hit par: cached ranked results turant return karo (yeh common case hai, upar ki estimation ke according).
6. Cache miss par: Geo-Index se POI IDs relevant cells mein query karo, unke details fetch karo (ek POI-detail cache se, ek read replica par fallback karte hue), candidate set rank karo, response cache karo, aur return karo.

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

**`POST /poi`** (business owner ek new POI register karta hai)
```
Request: { "name": "New Cafe", "lat": 37.78, "long": -122.41, "category": "coffee", "address": "..." }
Response: { "poi_id": "poi_7788", "status": "pending_index" }
```

**`PUT /poi/{poi_id}`** (business owner apna POI edit karta hai)
```
Request: { "hours": { "mon": "8:00-17:00" } }
Response: { "poi_id": "poi_5521", "status": "updated", "reindex_eta_minutes": 15 }
```

**`GET /poi/{poi_id}/nearby-similar?radius_km=1`**
```
Response: { "results": [ { "poi_id": "poi_9012", "name": "Ritual Coffee", "distance_km": 0.9 } ] }
```

## Step 5: Data Model

**Primary POI store — relational or document database (e.g. Postgres ya ek document store)**
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
- Relational/document yahan appropriate hai specifically ISLIYE kyunki yeh low-volume write path hai bina kisi exotic throughput requirement ke — POI edits infrequent, moderate-complexity records hain jo business owners ek normal CRUD UI se edit karte hain; yahan koi aisa pressure nahi hai jo ek specialized write-optimized store ki taraf push kare, read path ke unlike.

**Geo-Index — key-value store optimized for the cell-lookup access pattern (e.g. Redis, ya ek dedicated geospatial index structure)**
```
Key: geohash_cell (e.g. "9q8yy" at precision 5)
Value: [poi_id_1, poi_id_2, poi_id_3, ...]
```
- Geohashing (lat, long) ko ek base-32 string mein encode karta hai jahan geographically nearby locations string prefixes share karte hain — matlab ek search radius cleanly ek small, enumerable set of geohash-prefix cells par map ho jaata hai (search cell plus uske 8 neighbors, typically, edge-boundary misses avoid karne ke liye jahan ek nearby POI ek cell boundary ke just across padta hai). Isse "mujhe is point ke aas paas sab kuch do" ek small number of exact key lookups ban jaata hai instead of ek geometric computation full dataset ke upar.
- Ek live-updating structure (jaisa driver-location system ko chahiye hoga) ke upar isliye choose kiya gaya kyunki low write rate ka matlab hai index ko constant churn absorb karne ki zaroorat nahi — yeh ek relaxed schedule par rebuild ya incrementally patch ho sakta hai (Step 6) aur almost entirely cache/memory se serve ho sakta hai.
- Ek quad-tree alternative indexing structure hai similar properties ke saath (recursively space ko density ke basis par subdivide karta hai, toh dense areas ko automatically finer cells milte hain) — dono is read-heavy, low-write access pattern ke liye reasonable choice hain; geohashing often implementation simplicity ke liye preferred hai (yeh string-prefix operations mein reduce ho jaata hai ek standard key-value store par) jabki ek quad-tree wildly uneven density ke saath better adapt karta hai bina multiple precision levels ki zaroorat ke.

**Result cache — key-value store (e.g. Redis)**
```
Key: search:{geohash_cell_bucket}:{category}:{radius_bucket}
Value: serialized ranked result list, TTL ~15-60 minutes
```

## Step 6: Deep Dive

### 6.1 Why This Is a Fundamentally Different Problem Than Ride-Sharing's Geospatial Index

`12_ride_sharing_uber.md` ko ek geospatial index chahiye jo driver positions reflect kare jo har kuch seconds mein update hoti hain potentially hundreds of thousands of concurrently active drivers ke liye — ek genuinely high-write workload jahan even handful of seconds ka staleness visibly wrong results produce karta hai (ek rider ko ek driver se match karna jo ab wahan nahi hai jahan index kehta hai). Yeh ek design force karta hai jo constant position updates ko efficiently ek live index structure mein absorb karne ke around centered ho.

Is system ke POIs, sab practical purposes ke liye, static hain: ek restaurant ki location change nahi hoti, aur even uska metadata (hours, menu) weeks ke order mein change hota hai, seconds mein nahi. Step 2 mein computed read:write ratio (roughly 10,000:1 ya usse zyada) quantitative signal hai jo architecture ko ride-sharing case ke opposite direction mein drive karna chahiye: index ko writes cheaply absorb karne ke liye optimize karne ke bajaye, reads ko as cheaply as possible serve karne ke liye optimize karo, aur "index ko current rakhna" problem ko ek background, relaxed-schedule concern treat karo, real-time concern nahi. Concretely, iska matlab hai: geo-index ko batch mein ya lazy incremental updates ke through build karo instead of har write par synchronously, aur full query results cache karne par heavily lean karo — dono mein se koi bhi ride-sharing system mein safe ya effective nahi hota, jahan ek cached driver-position result seconds ke andar actively wrong ho sakta hai.

### 6.2 Geospatial Indexing for the Read-Heavy, Low-Write Case

Kyunki POIs rarely move karte hain, geohash-cell-to-POI-ID index ko efficient constant re-insertion support karne ki zaroorat nahi jaisi ek live index ko hoti. Isse simpler build strategies possible hote hain:
- **Batch rebuild**: periodically (e.g. har 15-60 minutes) primary POI database se poora index recompute karo. Simple, hamesha internally consistent, but new POIs ya edits appear hone mein batch interval tak lagta hai — Step 1 ki freshness requirement ke according acceptable.
- **Incremental update via change-data-capture**: jab ek POI likha jaata hai, ek CDC stream (ya simple write-through) sirf affected geohash cell(s) ko patch karta hai instead of sab kuch rebuild karne ke — new/edited POIs ke liye near-immediate visibility deta hai (e.g. ek ya do minutes ke andar) jabki ek aise system se kaafi simpler hai jise thousands of position updates per second handle karne padein, kyunki yahan maybe ek update per second handle karna padta hai (Step 2).
- Ek hybrid — periodic full rebuild correctness/self-healing ke liye (koi drift ya missed CDC events catch karta hai) plus freshness ke liye incremental patching — ek reasonable production answer hai aur explicitly mention karne worth hai, kyunki yeh CDC pipeline bugs ke against hedge karta hai bina har edit par full-rebuild latency pay kiye.
- Geohashing ya ek quad-tree dono yahan indexing structure ke liye fine choice hain; interview ke liye key point yeh nahi hai ki kaunsa, balki WHY low write rate ek high-write system ki zyada complex live-update machinery ki zaroorat ke bina dono ko comfortably sufficient banata hai.

### 6.3 Caching Popular (Location, Category) Query Combinations

Nearby-search traffic ka ek huge fraction poori duniya mein uniformly random nahi hai — yeh dense urban areas aur popular categories ke around heavily cluster hota hai ("coffee near downtown Chicago" ek din mein thousands of distinct users se poocha jaata hai, jo sab, practical purposes ke liye, same answer chahte hain). Yeh exactly wahi scenario hai jiske liye caching (`05_caching.md`) build ki gayi hai: ek given (geo-cell-bucket, category, radius-bucket) combination ke liye ranked result precompute karo ya first-request par cache karo, aur subsequent identical ya near-identical requests directly cache se serve karo bina geo-index ya ranking logic ko touch kiye.

Yeh explicitly ek aisi cheez NAHI hai jo ek live driver-matching query ke liye kaam karegi — "nearby available drivers" ko even 30 seconds ke liye cache karna aise drivers return kar sakta hai jo kisi aur se already match ho chuke hain ya range se bahar move ho chuke hain, ek actively wrong result produce karte hue. Yeh fact ki is system ka underlying data slowly change hota hai precisely wahi cheez hai jo aggressive result-caching ko sirf possible nahi, balki primary scalability lever banati hai: Step 2 ke bandwidth estimate ke according, yahan ek high cache-hit rate "5,800 requests/sec har ek index lookups + ranking kar raha hai" ko "5,800 requests/sec mostly cache se serve ho rahe hain, sirf cache-miss traffic (ek small fraction) actually geo-index aur ranking service touch kar raha hai" mein badal deta hai.

Practically, cache key ko location itna coarsely bucket karna chahiye ki many nearby users ke requests same key par collapse ho jaayein (e.g. lat/long ko ek geohash prefix tak round karo instead of exact coordinates par key karne ke, jo users ke beech almost kabhi repeat nahi hoga) jabki still results ko locally relevant rakhne jitna fine-grained bhi ho — ek direct trade-off cache hit rate aur result precision ke beech, tuned by choosing geohash precision cache key ke liye versus underlying index ke liye.

### 6.4 Two-Stage Retrieve-Then-Rank

Poore 50M-POI dataset ko ek blended distance+rating+relevance score se har search request ke liye rank karne ki koshish wasteful aur unnecessary hai — overwhelming majority POIs search location ke aas paas kahin nahi hain aur instantly geography se hi eliminate kiye ja sakte hain. Yeh system same two-stage retrieve-candidates-then-rank pattern use karta hai jo is folder ke designs mein baar baar recur karta hai (cross-shard search, cross-shard leaderboard merging):
1. **Retrieve**: geo-index use karo cheaply search radius cover karne wale geo-cells ke andar POI IDs ka small set pull karne ke liye — typically kuch sau se couple thousand candidates, millions nahi, kyunki geo-index ne already expensive part (spatial filtering) simple key lookups se kar diya hai.
2. **Rank**: sirf yeh much smaller candidate set expensive treatment paata hai — full details fetch karo, ek blended score compute karo actual distance (ek proper haversine/great-circle calculation, sirf cell membership nahi), rating, category-match relevance, aur possibly personalization signals combine karke, phir sort karo aur top results return karo.
- Yeh separation matter karti hai kyunki ranking step zyada computationally expensive hai (multiple weighted factors, possibly har candidate ke liye ek lookup jaise "open now" status ki freshness ke liye) — isko sirf hundreds of pre-filtered candidates ke upar run karna instead of full dataset ke upar, wahi cheez hai jo p99 latency ko Step 1 ke 200ms target se well under rakhti hai even bina ranking logic ko blazingly optimize kiye.

## Step 7: Bottlenecks & Trade-offs

- **Hot geo-cells in extremely dense areas**: ek single geohash cell jo ek dense downtown core cover karta hai bahut zyada POIs contain kar sakta hai ek sparse suburb ki cell se, uneven load aur candidate-set sizes cause karte hue cells ke across. Mitigation: variable-precision cells use karo (dense areas mein finer-grained subdivision, similar to how a quad-tree naturally adapts) ya simply ek larger candidate set accept karo dense areas mein aur ranking stage par rely karo usse trim karne ke liye, kyunki absolute POI counts even sabse dense single cell mein bhi full dataset ke relative small hain.
- **Cache staleness vs freshness trade-off**: aggressive result caching (Step 6.3) ka matlab hai ek POI ke newly-updated hours ya ek newly-opened business ko search results mein appear hone mein cache TTL tak lag sakta hai. Yeh non-functional requirements ke given ek explicitly accepted trade-off hai, but TTL choice (e.g. 15-60 minutes) ko ek deliberate freshness-vs-load dial ke roop mein state karna worth hai, ek oversight nahi.
- **Geo-cell boundary effects**: ek POI jo search point se ek cell boundary ke just across hai geographically ek POI se zyada close ho sakta hai jo nominally "inside" queried cell hai but miss ho sakta hai agar sirf exact containing cell query ki jaaye. Mitigation: hamesha containing cell plus uske immediate neighbors query karo (ek standard geohash technique), boundaries par correctness ke exchange mein ek slightly larger candidate set accept karte hue.
- **Global distribution and cross-region latency**: users aur POIs worldwide ke saath, har search ko ek single regional deployment tak route karna distant users ke liye unacceptable latency add karega. Mitigation: Search Service, cache layer, aur read replicas ko regionally deploy karo (POI data naturally geography se partitionable hai, unlike ek system jise single global consistent view chahiye), Primary POI Database ko ek smaller, less latency-sensitive write path rehne do jo centralized ya lightly multi-region hone ko tolerate kar sakta hai kyunki write volume itna low hai.
- **Trade-off — index freshness vs system simplicity**: batch-rebuild-only choose karna (simplest) new/edited POIs ke liye freshness sacrifice karta hai; full CDC-driven real-time indexing choose karna (most complex) freshness gain karta hai jo business requirement actually demand nahi karti. Hybrid approach (6.2) ek deliberate middle-ground trade-off hai, aur yeh articulate karna ki requirements sabse complex option justify nahi karti khud ek good judgment ka signal hai is interview mein.

## Follow-up Questions an Interviewer Might Ask

1. **"Aap ek very rural area ke liye search kaise handle karoge jahan nearest coffee shop 50km door ho — kya fixed-radius cell approach abhi bhi work karta hai?"** Progressively search expand karo — pehle immediate cells query karo, aur agar kaafi results na milein, ek larger ring of cells tak widen karo (ya ek coarser geohash precision par jump karo) instead of client ko upfront ek appropriately large radius guess karne ke liye require karne ke; yeh dense-area queries ko cheap rakhta hai jabki sparse-area queries bhi correctly answer karta hai.

2. **"Aap results ko kaise personalize karte ho — e.g. ek user ki previously-liked cuisine ko higher rank karna?"** Ek personalization signal ko sirf ranking stage mein layer karo (kabhi retrieval/candidate-selection stage mein nahi, jo purely geographic rehna chahiye cacheability ke liye) — e.g. ek lightweight per-user preference vector jo parallel mein candidate details ke saath fetch ho, final score mein blend kiya jaaye; note karo ki isse personalized results shared result-cache buckets mein cache karna harder ho jaata hai, toh yeh 6.3 ki aggressive caching strategy ke against ek direct trade-off hai, aur ek common resolution hai geographically-ranked base result cache karna aur personalization ko ek final client-side ya thin re-rank layer ke roop mein cached list ke upar apply karna.

3. **"Aap ek POI ko kaise handle karoge jo legitimately move karta hai, jaise ek food truck?"** Food trucks/mobile vendors is poori design ke "static POI" assumption ko break karte hain jispar poori design tiki hai; unhe ek distinct category treat karo jo ek separate, zyada frequently-refreshed index path se route ho (shorter TTLs, more frequent incremental updates) instead of poore system ki freshness guarantees ko POIs ke ek small subset accommodate karne ke liye neeche push karne ke.

4. **"Jab ek business band ho jaata hai kya hota hai — yeh search results se kitni jaldi disappear hoti hai, aur agar koi wahan navigate kare bhi toh?"** `status` field `closed` mein transition ho jaati hai, same incremental/batch indexing pipeline ke through propagate hote hue jaise koi bhi doosra edit (same freshness trade-off apply hota hai); POI detail page abhi bhi serve ki ja sakti hai (informational purposes ke liye, e.g. "permanently closed") even after yeh active search results se drop ho jaaye, jo ek product decision hai interviewer ko surface karne worth hai.

5. **"Aap keyword se search karne par results kaise rank karoge instead of category, e.g. 'best tacos'?"** Yeh ranking problem ka ek hissa text relevance/search-engine territory ki taraf shift karta hai (potentially ek dedicated search index jaise Elasticsearch keyword-matching component ke liye), geo-index abhi bhi geographic pre-filtering handle karta hai — two-stage retrieve-then-rank pattern abhi bhi apply hota hai, sirf ek richer, text-relevance-aware ranking stage ke saath.

6. **"Aap result cache ko time-sensitive info jaise 'open now' ke liye stale 'closed' status serve karne se kaise prevent karte ho?"** Cacheable aur non-cacheable fields split karo: matching POIs ki ranked list (name, distance, rating) itni stable hai ki longer TTL ke saath cache ho sake, but "open now" time-of-day-dependent hai aur usko request time par POI ke (cached, but presumably accurate) hours data se compute kiya jaana chahiye instead of cached response mein bake kiye jaane ke — otherwise ek cached result jo 2pm par generate hua tha incorrectly abhi bhi "open" bolega jab 11pm ko dobara serve kiya jaaye.
