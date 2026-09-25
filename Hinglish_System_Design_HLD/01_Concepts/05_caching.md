# Caching

Ek **cache** ek chhoti, faster storage layer hoti hai jo ek slower source of truth (ek database, ek API, ek disk) ke saamne baithti hai aur frequently ya recently accessed data ki ek copy hold karti hai. Ek cache jo bet lagata hai woh simple hai: zyaadatar systems mein **skewed access patterns** hote hain — data ka ek small fraction (hot keys) zyaadatar reads account karta hai — isliye us fraction ko kahin fast rakhna disproportionately pay off karta hai.

## Yeh important kyun hai

Caching ke bina, har single read directly aapke database ya origin server ko hit karta hai. Concretely, iska matlab hai:

- **Latency**: ek disk-backed relational query 5-50ms le sakti hai; ek in-memory cache lookup 1ms se kaafi kam leta hai. Ek page ke liye jo 20 queries fire karta hai, yeh difference hi ek 100ms page load aur ek 2-second page load ke beech ka gap hai.
- **Database load**: databases system ka sabse hard part hote hain horizontally scale karne ke liye (dekho `07_database_scaling.md`). Cache se serve ki gayi har read aapke database ko kabhi process nahi karni padti, jiska matlab hai aap same database hardware par kaafi zyada traffic serve kar sakte ho.
- **Traffic spikes**: read-heavy spikes (ek post viral ho jaana, ek product homepage par aa jaana) exactly wahi failure mode hai jiske liye caching bani hai — cache ke bina, reads mein ek spike directly database connections mein ek spike mein translate ho jaata hai, jo ki databases ke gir jaane ka tareeka hai.
- **Cost**: ek expensive result ko (ek complex aggregation, ek machine learning inference, ek third-party API call) har request par re-compute karna often system mein sabse bada avoidable cost hota hai.

Jo trade-off aap hamesha bana rahe ho woh hai **speed ke liye freshness**— ek cache aisa data serve kar sakta hai jo milliseconds se minutes tak out of date ho. Har caching design decision actually ek decision hai ki aap kitni staleness tolerate kar sakte ho.

## Core Caching Strategies

Yeh strategies describe karti hain ki *caching logic kahan rehta hai* aur *cache aur database ko sync mein rakhne ki responsibility kiski hai*. Per data type pick karo, poore system ke liye ek baar nahi — zyaadatar real systems inhe mix karte hain.

### 1. Cache-Aside (Lazy Loading)

Application code responsible hota hai cache check karne ke liye, aur miss hone par, database se load karke khud cache populate karne ke liye.

```text
Read:
  App -> Cache: get(key)
  Cache -> App: MISS
  App -> DB: query
  DB -> App: data
  App -> Cache: set(key, data)   (agli baar ke liye populate karo)

Write:
  App -> DB: write
  App -> Cache: delete(key)      (invalidate karo, update mat karo)
```

- **Miss par**: application DB query karta hai, phir result ko cache mein likh deta hai.
- **Write par**: application DB mein likhta hai aur cache entry ko *invalidate* karta hai (delete karta hai, update nahi) — agli read use repopulate kar degi.
- **Pros**: sirf requested data hi cache hota hai (cold data par memory waste nahi hoti); cache failure fatal nahi hai — app bas DB par fall back kar jaata hai.
- **Cons**: har cache miss ek round trip add karta hai (DB query karo, phir cache populate karo) return karne se pehle; app cache logic own karta hai, jo galat hona aasan hai (kahin invalidate karna bhool jaana).
- Yeh practice mein sabse common pattern hai — yeh wahi hai jo aap Rails ke `Rails.cache.fetch(key) { expensive_query }` use karte waqt kar rahe hote ho.

### 2. Read-Through

Functionally cache-aside jaisa hi, lekin cache khud (application nahi) responsible hota hai miss hone par database se load karne ke liye. Application sirf cache se hi baat karta hai.

```text
Read:
  App -> Cache: get(key)
  Cache -> DB: query (cache yeh internally karta hai, app ko pata nahi hota)
  DB -> Cache: data
  Cache -> App: data
```

- **Pros**: application code simpler hota hai (har jagah manually "cache check karo, phir DB query karo, phir populate karo" logic scatter nahi hota); loading logic cache layer mein centralized hota hai.
- **Cons**: iske liye ek aisi caching library/provider chahiye jo yeh pattern support kare (jaise, kuch ORMs, kuch managed caches); kisi bhi key ki pehli request abhi bhi slow hoti hai (miss ki penalty avoidable nahi hai chahe fetch koi bhi own kare).

### 3. Write-Through

Har write cache se guzarta hai, jo synchronously cache aur database dono mein likhta hai write ko acknowledge karne se pehle.

```text
Write:
  App -> Cache: set(key, value)
  Cache -> DB: write value           (synchronous)
  DB -> Cache: ack
  Cache -> App: ack
```

- **Pros**: cache hamesha DB ke saath consistent rehta hai — write ke baad koi stale-cache window nahi hota; reads hamesha fast hoti hain kyunki data write time par hi cache ho chuka hota hai.
- **Cons**: ab har write do writes ki latency pay karta hai (cache + DB) — write path slower ho jaata hai; aap aisa data cache kar sakte ho jo likha gaya hai lekin kabhi read nahi hoga (wasted memory) jab tak isse ek eviction policy ke saath combine na kiya jaaye.
- Yeh tab achha fit hota hai jab read-after-write consistency matter kare aur write volume moderate ho (jaise, user profile updates).

### 4. Write-Back (Write-Behind)

Writes sirf cache mein jaate hain, aur turant acknowledge ho jaate hain. Cache asynchronously baad mein database ko write flush karta hai (batched, ek timer par, ya eviction par).

```text
Write:
  App -> Cache: set(key, value)
  Cache -> App: ack (immediate)
  ... baad mein, async ...
  Cache -> DB: flush batched writes
```

- **Pros**: write latency utni hi fast hoti hai jitni cache khud — DB write critical path se poori tarah hat jaata hai; writes batch/coalesce ho sakte hain (ek second mein same key ke 10 updates 1 hi DB write ban jaate hain), jo DB load ko significantly kam kar deta hai.
- **Cons**: **data loss risk** — agar cache node flush hone se pehle crash ho jaaye, toh unflushed writes gaye; DB kuch time ke liye cache ke relative stale ho sakta hai, jo dangerous hai agar kuch aur directly DB se read karta ho.
- Wahan use hota hai jahan write throughput durability guarantees se zyada matter kare (view counters, analytics events, metrics) — kisi transactional cheez ke liye jaise payments rarely use hota hai.

### 5. Write-Around

Writes directly database mein jaate hain, cache ko completely bypass karke. Cache sirf baad mein populate hota hai, ek subsequent read par (cache-aside ya read-through ke through).

```text
Write:
  App -> DB: write   (cache untouched)

Read (write ke baad pehli baar):
  App -> Cache: get(key) -> MISS
  App -> DB: query -> populate cache
```

- **Pros**: cache ko aise data se flood hone se bachata hai jo ek baar likha jaata hai aur rarely read hota hai (jaise, bulk imports, logs) — cache ke working set ko actually-hot data par focused rakhta hai.
- **Cons**: write ke baad pehli read hamesha miss hoti hai (slower); agar writes ke turant baad hi reads hoti hain (read-your-writes pattern), toh yeh poor fit hai.

### Strategy Comparison

| Strategy | Write latency | Read latency (post-write) | Data loss risk | Best for |
|---|---|---|---|---|
| Cache-aside | Fast (DB only) | First read par slow | Low | General-purpose, sabse common default |
| Read-through | Fast (DB only) | First read par slow | Low | Cache-aside jaisa hi, centralized loader |
| Write-through | Slow (cache+DB) | Fast (hamesha warm) | Low | Read-heavy, consistency-sensitive data |
| Write-back | Very fast (cache only) | Fast (hamesha warm) | High | Write-heavy, loss tolerant (counters, metrics) |
| Write-around | Fast (DB only) | First read par slow | Low | Write-once/read-rarely data (logs, bulk data) |

## Eviction Policies

Ek cache ke paas finite memory hoti hai, isliye jab woh full ho aur ek naya item store karna ho, toh kuch evict karna padta hai. Aap kaunsi policy pick karte ho isse yeh change hota hai ki kya "hot" rehta hai.

- **LRU (Least Recently Used)**: us item ko evict karta hai jise sabse zyada time se *access* nahi kiya gaya. Assume karta hai ki recently-used data phir se jald use hoga (temporal locality). Yeh zyaadatar general-purpose caches ke liye default choice hai (Redis ka `allkeys-lru`, zyaadatar CDN edge caches) kyunki yeh bina kisi tuning ke changing access patterns ke saath automatically adapt ho jaata hai.
- **LFU (Least Frequently Used)**: us item ko evict karta hai jiske total accesses sabse kam hain, recency ki parwaah kiye bina. LRU se better hota hai jab popularity time ke saath stable ho (ek perennially popular product page) aur aap nahi chahte ki ek rarely-used item ka ek recent traffic burst kisi aisi cheez ko evict kar de jo reliably hot hai. Downside: adapt hone mein slow — ek newly-popular item ek low count se start hota hai aur hits accumulate karne se pehle hi evict ho sakta hai.
- **FIFO (First In, First Out)**: access pattern ki parwaah kiye bina sabse oldest-inserted item evict karta hai. Implement karna cheap hai (access-tracking ki zaroorat nahi) lekin usage ko poori tarah ignore karta hai, isliye yeh aisi cheez evict kar sakta hai jise constantly access kiya jaata hai sirf isliye kyunki woh pehle add hui thi. Wahan use hota hai jahan simplicity/overhead hit-rate optimality se zyada matter kare, ya jab items naturally insertion order mein hi expire hote hon (jaise, recent events ka ek queue-like cache).
- **TTL-based expiry (Time To Live)**: har entry ko ek expiration time diya jaata hai; jab woh time guzar jaata hai toh woh evict ho jaata hai (ya miss treat kiya jaata hai), memory pressure se independent. Yeh really "pressure ke under kaunsa item evict karein" wali policy nahi hai — yeh ek **staleness bound** hai: aap TTL tab use karte ho jab aapko pata ho ki data ek fixed window ke baad stale ho jaata hai (session tokens, ek stock price quote, ek OAuth token) aur aap guarantee karna chahte ho ki cache kabhi us window se purana data serve na kare. TTL usually LRU/LFU ke saath combine kiya jaata hai — TTL correctness (staleness) control karta hai, LRU/LFU capacity control karta hai.

| Policy | Kis basis par evict karta hai | Kab achha hai | Kab weak hai |
|---|---|---|---|
| LRU | Access ki recency | General-purpose, evolving hot set | Sudden one-off scans cache ko pollute kar dete hain |
| LFU | Access ki frequency | Stable, long-term popularity | Newly-trending items adopt karne mein slow |
| FIFO | Insertion order | Simplicity, low overhead | Actual usage ko poori tarah ignore karta hai |
| TTL | Fixed expiry time | Known staleness bound wala data | Khud memory pressure manage nahi karta |

## Caching Kahan Rehti Hai — Layered View

Caching ek layer nahi hai — ek single request database tak pahunchne se pehle kayi caches se guzar sakta hai, har ek kisi different job ke liye optimized.

```text
Client (browser/mobile)
   |  [1] Client-side cache (HTTP cache headers, local storage)
   v
CDN (edge, geographically distributed)
   |  [2] CDN cache — static assets, kabhi-kabhi API responses
   v
Reverse proxy / API gateway
   |  [3] Gateway cache — hot API endpoints ke liye response caching
   v
Application server
   |  [4] Distributed cache (Redis / Memcached) — query results, sessions, computed objects
   v
Database
   |  [5] DB query cache / buffer pool — data ke pages jo already memory mein hain
   v
Disk
```

1. **Client-side cache**: `Cache-Control` / `ETag` headers se govern hone wala browser cache, ya mobile par app-local storage. Agar hit ho jaaye toh zero network round trip — sabse fast possible cache, lekin ek baar client par aane ke baad invalidation par aapka lagbhag koi control nahi hota.
2. **CDN**: static assets (images, JS, CSS, video) ko user ke close edge locations par cache karta hai. Latency (origin ki physical distance) aur load (origin server ko request kabhi dikhta hi nahi) dono hata deta hai.
3. **Reverse proxy / API gateway cache**: aapke app servers ke saamne baithta hai (jaise, Nginx, Varnish, ya ek API gateway ki caching layer) aur ek short TTL ke liye poore HTTP responses cache karta hai — un endpoints ke liye useful hai jo kayi users ke liye identical hain (ek public leaderboard, ek product listing).
4. **Application-level distributed cache**: Redis/Memcached — sabhi app server instances mein shared, query results, rendered fragments, session data, rate-limit counters hold karta hai. Zyaadatar "caching" design questions actually isi layer ke baare mein hote hain.
5. **Database-level cache**: DB ka apna buffer pool / query cache recently-accessed pages of data (aur kabhi-kabhi query results) ko memory mein rakhta hai taaki disk hit na karna pade. Yeh automatically hota hai aur application code directly manage nahi karta, lekin isi wajah se restart ke baad ek "cold" database ek "warm" database se slower hota hai.

Har downstream layer un traffic ko absorb karti hai jo usse pehle wali layers miss kar chuki hoti hain — cache hit jitna left (client ki taraf) hota hai, utna hi cheaper aur faster hota hai.

## CDN (Content Delivery Network)

Ek **CDN** proxy servers ("edge servers" ya points of presence) ka ek globally distributed network hai jo content ko requesting user ke physically close ek location se cache aur serve karta hai, instead of har request ke aapke origin server tak poora safar karne ke.

Yeh important kyun hai: network latency speed of light se bound hai — Singapore mein ek user jo Virginia mein baithe server se ek asset request kar raha hai woh ~200ms+ pure round-trip travel time pay karta hai jise koi bhi caching *origin par* fix nahi kar sakti. Singapore mein ek CDN edge node cached content ke liye us distance ko poori tarah hata deta hai.

| | Push CDN | Pull CDN |
|---|---|---|
| Content kaun upload karta hai | Aap proactively files CDN par push karte ho | CDN pehli request (cache miss) par aapke origin se pull karta hai, phir use cache kar leta hai |
| Best for | Bade, infrequently-changing files (release bundles, video libraries) | Frequently-changing ya bahut bade content catalogs (zyaadatar websites) |
| Storage cost | Aap CDN par full storage ke liye pay karte ho | Sirf accessed content hi cache hota hai — long tail ke liye cheaper |
| Freshness control | Aap exactly control karte ho ki kya live hai | Expiry ke baad pehla requester cache-miss penalty jhelta hai |

CDNs sirf static files tak limited nahi hain. **Dynamic content caching at the edge** increasingly common hai: ek API response jo short window ke liye sabhi users ke liye same ho (jaise, ek product catalog page, ek public feed) use CDN edge nodes par ek short TTL ke saath cache kiya ja sakta hai, jo read traffic ka ek bada fraction poori tarah aapke origin se hata deta hai. Yeh personalized responses se alag hai (ek user ka apna dashboard), jinhe generally per-user cache keys ke bina edge-cache nahi kiya ja sakta.

## Cache Invalidation

Ek well-known quip hai: *"Computer science mein sirf do hard problems hain: cache invalidation aur naming things."* Invalidation genuinely hard hone ki wajah yeh hai ki ek cache, definition se, **truth ki ek second copy** hoti hai — aur ek baar aapke paas kisi bhi cheez ki do copies ho gayin, aapko unhe actively sync mein rakhna padta hai, ya accept karna padta hai ki woh diverge ho jaayengi. Ek system mein jahan kayi cache layers hon (upar dekho) aur kayi app servers mein se har ek apna khud ka local cache hold kar raha ho, "data change ho gaya" ko har copy tak propagate karna padta hai, aur koi single moment nahi hota jahan yeh atomically ho jaaye. Ek miss karo, aur users ka koi fraction stale data dekhta hai — kabhi-kabhi indefinitely.

Teen main strategies, usually combined:

- **TTL expiry**: har cache entry ko ek lifespan do; expire hone ke baad usse miss treat kiya jaata hai aur refetch kiya jaata hai. Simple aur self-healing (koi explicit invalidation code nahi chahiye), lekin iska matlab hai TTL window tak staleness *hamesha* possible hai — aap correctness ko simplicity ke liye trade kar rahe ho.
- **Write-through invalidation**: write path khud write ke part ki tarah cache entry ko update ya delete karta hai (upar Write-Through aur Cache-Aside strategies dekho). Precise — cache write hote hi turant correct ho jaata hai — lekin sirf un writes ke liye kaam karta hai jo aapke control kiye hue code paths se guzarte hain; ek direct DB update (ek migration, ek background job, ek admin console) silently cache ko stale chhod sakta hai.
- **Event-based invalidation**: write ek event publish karta hai (jaise, ek message queue par — dekho `10_message_queues_and_streaming.md`) jise sabhi interested caches subscribe karte hain aur khud ko invalidate kar lete hain. Yeh kayi cache layers/services tak scale hota hai bina har writer ko har cache ke baare mein pata hone ke, lekin infrastructure aur ek chhota propagation delay add karta hai (caches write ke saath *atomically* invalidate nahi hote, bas bahut jald baad mein).

Teenon mein underlying tension same hai: **staleness vs. consistency cost**. Perfect consistency (kabhi stale data serve na karna) ke liye ya toh extremely short TTLs chahiye (jo caching ka point hi defeat kar dete hain) ya har jagah synchronous invalidation chahiye (jo har write mein latency aur coupling add kar deti hai). Har real system per data type ek tolerable staleness window pick karta hai, isse globally solve karne ke bajaye.

## Cache Stampede (Thundering Herd)

**Problem**: ek hot key (maan lo, ek trending post ka data) expire hota hai. Expiry ke turant baad, agar us key ke liye 10,000 concurrent requests hain, toh *sabhi 10,000* ek saath ek cache miss dekhte hain aur sab ek saath same value recompute karne ke liye database ko hammer karte hain — ek load spike jiske liye database kabhi sized hi nahi tha, jo potentially ek outage mein cascade ho sakta hai.

```text
Expiry se pehle:  10,000 req/s -> Cache HIT -> fast, DB untouched
Expiry par:       10,000 req/s -> Cache MISS -> SAB ek saath DB hit karte hain
                                 DB ko ek saath 10,000 identical queries milti hain
```

Mitigations:

- **Request coalescing / single-flight**: jab miss hota hai, sirf *pehla* request actually DB query karta hai; same key ke liye concurrent requests us in-flight request par wait karte hain aur apna khud ka query issue karne ke bajaye uska result share karte hain. (Kayi caching libraries is pattern ko "single-flight" bulaati hain.)
- **Locking**: similar idea — pehla request recompute karne se pehle key par ek short-lived lock acquire karta hai; doosre requests ya toh lock release hone ka wait karte hain (phir ab-fresh cache read karte hain) ya sab ek saath DB query karne ke bajaye briefly stale data serve karte hain.
- **Jittered / staggered TTLs**: sabhi related keys ko exactly same time par expire set karne ke bajaye (jaise, entries ke ek pure batch ke liye "midnight par expire karo"), random jitter add karo (jaise, TTL = 60s ± 10s) taaki expiries ek spike mein bunch hone ke bajaye time ke saath spread ho jaayein.
- **Background refresh before expiry**: ek hot key ko uske expire hone se *thoda pehle* proactively recompute aur repopulate karo (jaise, TTL ke 90% par refresh karo) taaki incoming requests ke perspective se woh kabhi actually cold ho hi na.

## Redis vs Memcached

Do dominant distributed caching systems, often simple key-value caching ke liye interchangeably use kiye jaate hain lekin jab zyaadatar kuch chahiye ho toh unme real differences hote hain.

| | Redis | Memcached |
|---|---|---|
| Data structures | Strings, hashes, lists, sets, sorted sets, streams, bitmaps | Sirf strings (values opaque blobs hoti hain) |
| Persistence | Optional (RDB snapshots, AOF log) — restart survive kar sakta hai | Kuch nahi — purely in-memory, restart hone par sab kuch gaya |
| Clustering | Native (Redis Cluster) automatic sharding ke saath | Sirf client-side sharding (koi built-in cluster mode nahi) |
| Pub/Sub | Built-in | Support nahi karta |
| Multithreading | Historically per instance single-threaded (baad mein I/O threading add hui) | Natively multithreaded — per instance zyada cores use kar sakta hai |
| Typical use case | Simple caching se aage kuch bhi: leaderboards (sorted sets), rate limiting (counters + TTL), session store, pub/sub, queues | Pure, simple, maximally fast key-value caching minimal overhead ke saath |

Rule of thumb: **Memcached** tab lo jab aapko simplest possible cache chahiye aur kuch aur nahi — plain key-value gets ke liye raw throughput. **Redis** ke liye reach karo jaise hi aapko usse aage kuch chahiye ho: strings se aage data structures, persistence, pub/sub, atomic increments, ya built-in clustering. Zyaadatar new systems Redis ko default rakhte hain kyunki extra capability thodi hi cost karti hai aur baad mein frequently chahiye hoti hai.

## Trade-offs

| Decision | Yeh choose karo... | ...jab |
|---|---|---|
| Cache-aside vs write-through | Cache-aside | Reads dominate karte hain, write ke baad occasional stale acceptable hai |
| | Write-through | Write ke turant baad reads hamesha fresh honi chahiye |
| Write-back vs write-through | Write-back | Write throughput durability se zyada matter karta hai (counters, metrics) |
| | Write-through | Ek write lose hona unacceptable hai |
| LRU vs LFU | LRU | Access patterns time ke saath shift hote hain, tuning nahi chahiye |
| | LFU | Popularity stable aur long-lived hai |
| TTL length | Short TTL | Data often change hota hai / staleness costly hai |
| | Long TTL | Data nearly static hai / cache hit-rate sabse zyada matter karta hai |
| Push vs Pull CDN | Push | Bade static libraries jo advance mein pata hain |
| | Pull | Bade, evolving catalogs jahan sab kuch pre-upload karna wasteful hai |

Yahan koi universally "correct" cache configuration nahi hai — har choice **freshness, latency, throughput, aur durability** ke beech ek dial hai, aur right setting poori tarah is baat par depend karta hai ki ek particular data ka kuch seconds (ya minutes) purana hona kitna bura hai.

## Interview Tips

- Caching lagbhag hamesha ek **follow-up** ki tarah aata hai, opening question ki tarah nahi — aap ek design propose karte ho, interviewer kehta hai "reads dominate kar rahi hain aur DB bottleneck hai, aap kya karoge?" aur woh dekhna chahta hai ki aap specifically caching ke liye reach karo, ek stated strategy ke saath, sirf "cache add kar do" nahi.
- Hamesha state karo **kya** cache kar rahe ho (ek full object? ek rendered page fragment? ek query result?), **kahan** (kaunsi layer), aur **kitni der ke liye** (TTL) — "hum ise cache kar denge" jaise vague answers in specifics ke bina surface-level lagte hain.
- Interviewers frequently invalidation ko purposely probe karte hain, kyunki yahin candidates jinhone caches superficially hi use kiya hai fall apart ho jaate hain. Ready raho precisely batane ke liye ki ek write cache tak kaise propagate/invalidate hota hai, aur us gap mein user ko kya dikhta hai jab tak woh hota hai.
- Thundering herd ek strong signal question hai — ek "hot key" scenario (celebrity profile, viral post) discuss karte waqt ise unprompted mention karna dikhata hai ki aapne actually real load ke under ek cache operate ki hai, sirf caching ke baare mein padha nahi hai.
- **Latency** ke liye caching (client/CDN layers) aur **database offload** ke liye caching (distributed cache layer) mein difference pata hona chahiye — yeh different problems solve karte hain aur interviewers poochhenge ki aap kaunsa target kar rahe ho.

## Quick Recall — Self-Test

**1. Cache-aside aur write-through mein core difference kya hai is baat mein ki write par kya hota hai?**
Cache-aside DB mein likhta hai aur cache entry ko *delete* karta hai (invalidate karta hai), agli read ko use repopulate karne deta hai. Write-through same write operation ke part ki tarah cache aur DB dono mein synchronously likhta hai, isliye write ke baad cache kabhi stale nahi hota.

**2. Write-back risky kyun hai, aur yeh risk kab acceptable hai?**
Write-back write ko cache mein aate hi acknowledge kar deta hai, DB mein flush hone se pehle — agar cache node flush hone se pehle crash ho jaaye, toh woh data lose ho jaata hai. Yeh us data ke liye acceptable hai jahan kuch loss tolerable ho aur write speed zyada matter kare, jaise view counters ya metrics, lekin kisi transactional cheez ke liye nahi.

**3. LFU ko LRU se kab prefer karoge eviction ke liye?**
Jab popularity ek lambe time tak stable ho aur aap nahi chahte ki ek rarely-used item ka ek recent traffic burst kisi reliably popular cheez ko evict kar de. LRU better default hai jab access patterns time ke saath shift hote hain, kyunki yeh frequency track kiye bina automatically adapt ho jaata hai.

**4. Cache invalidation ko sirf `.delete(key)` call karne se aage "hard" kyun maana jaata hai?**
Kyunki ek cache truth ki ek second copy hai, aur real systems mein often kayi cache layers aur kayi servers hote hain jinme se har ek ek copy hold karta hai — invalidation ko har copy tak pahunchna padta hai, koi single atomic moment nahi hota jahan "data change ho gaya" har jagah propagate ho jaaye, aur koi bhi path jo aapke write code ko bypass kare (ek direct DB update, ek migration) stale copies ko indefinitely peeche chhod sakta hai.

**5. Cache stampede kis wajah se hota hai, aur do mitigations batao.**
Ek hot key expire ho jaata hai aur concurrent requests ka ek bada volume ek saath miss karta hai, ek saath identical queries ka burst DB ko bhejta hai. Mitigations mein hain request coalescing/single-flight (sirf ek request recompute karta hai, doosre usi par wait karte hain) aur jittered TTLs (expiry times ko spread karna taaki sab ek saath na girein) ya expiry se pehle background refresh.

**6. CDN akele personalized/dynamic content ke liye latency kyun fix nahi kar sakta?**
Ek CDN aisa content cache karta hai jo kayi users ke liye ek shared cache key par same ho; personalized content (ek user ka apna dashboard, account data) per user different hota hai, isliye serve karne ke liye koi single cached copy nahi hoti — iske liye per-user cache keys chahiye hongi, jo shared-caching ke zyaadatar benefit ko defeat kar deta hai aur yeh CDNs typically kaise use hote hain uske against hai.

**7. Redis persistence support karta hai aur Memcached nahi — yeh "cache" ke liye actually kab matter karta hai?**
Yeh tab matter karta hai jab cached data regenerate karna expensive enough ho, ya store pure caching se aage bhi use ho raha ho (jaise, session data ya counters ke liye ek lightweight primary store ki tarah) — persistence ka matlab hai restart poora dataset wipe nahi karega aur poore dataset ke across ek stampede of cache misses force nahi karega.

**8. TTL aur ek eviction policy jaise LRU mein kya difference hai?**
TTL ek correctness/staleness bound hai — ek entry uska time khatam hote hi invalid treat ki jaati hai, memory pressure ki parwaah kiye bina. LRU ek capacity management policy hai — yeh decide karta hai ki *jab cache full ho* toh kya remove karna hai, chahe entries expire hui hon ya nahi. Yeh usually saath mein use hote hain: TTL freshness control karta hai, LRU control karta hai ki kya fit hota hai.
