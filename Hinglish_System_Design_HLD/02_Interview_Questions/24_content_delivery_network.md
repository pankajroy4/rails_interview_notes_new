# Design a Content Delivery Network

## Problem Statement

"Design a simplified Content Delivery Network — a system that serves static content (images, videos, JS/CSS bundles, downloadable files) to end users worldwide with low latency, while keeping a manageable number of origin servers as the source of truth. How would you get content physically close to users, decide which edge location serves a given request, and handle cache invalidation when the origin content changes?"

Yeh question test karta hai ki kya candidate samajhta hai ki ek CDN ki core value proposition fundamentally physical distance aur network topology ke baare mein hai, sirf "ek aur caching layer" nahi — aur kya woh un genuinely hard distributed-systems problems ke baare mein reason kar sakta hai jo caching infrastructure ko potentially hundreds of geographically dispersed locations ke across replicate karne se aati hain instead of ek jagah.

## Step 1: Clarify Requirements

**Functional Requirements**
- Static content (images, video segments, JS/CSS, downloadable files) end users ko low latency ke saath serve karo, ek nearby edge location tak route kiya hua.
- Edge locations par content cache karo, cache miss par origin se fetch karo.
- Cache invalidation/purging support karo jab origin content change ho (e.g. ek new deployment, ek updated image).
- Dono "pull" content (edge lazily first request par fetch karta hai) aur "push" content (proactively distribute kiya hua known-hot assets ke liye demand se pehle, e.g. ek major game/OS update release) support karo.
- Har edge location ke liye cache-hit-ratio aur latency metrics/observability provide karo.
- Origin se standard HTTP caching semantics support karo (Cache-Control headers, ETags, conditional requests).

**Non-Functional Requirements**
- Scale: ek global user base serve karo — assume karo 500 million requests/day sab edge locations ke across, content jo origin par petabytes tak total hai (video libraries, image assets).
- Latency: edge-served cache hits single-digit se low tens of milliseconds mein return honi chahiye; poore system ka point hi physical proximity exploit karke round-trip latency minimize karna hai.
- Availability: ek edge PoP failure uske nearby users ke liye outage cause nahi karna chahiye — traffic next-nearest healthy PoP par reroute hona chahiye.
- High cache-hit ratio at the edge: origin ko bulk traffic se shield karna hoga — ek well-tuned CDN ko majority requests (often 90%+) bina origin touch kiye serve karna chahiye.
- Consistency/freshness: purges globally propagate hone chahiye, but NOT instantly — design ko explicit, honest expectations set karni chahiye (seconds se couple minutes) instead of perfect instant global consistency promise karne ke, jo hundreds of independent edge locations ke across unacceptable cost/complexity ke bina realistically achievable nahi hai.
- Cost efficiency: bandwidth aur storage edge locations par dominant cost driver hain; design ko cold/rarely-requested content ko har edge location par needlessly replicate karne se avoid karna chahiye.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 500M requests/day globally, 100 edge PoPs (ek reasonable count wide geographic coverage ke liye bina extreme cost ke), assume karo traffic unevenly distributed hai but roughly ek manageable per-PoP load par average out hota hai kuch hot regions ke saath.
- Average object size: mixed content, ek blended average of 200 KB assume karo (many small images/JS/CSS, kuch larger video segments, ek realistic mix ke across averaged).

**Request rate**
- 500M requests/day / 86,400 sec/day ≈ 5,800 requests/sec average globally; regional evening-peak clustering ke liye 4x peak multiplier assume karo ≈ 23,200 requests/sec peak globally, 100 PoPs ke across spread ≈ ~232 requests/sec peak per PoP on average (hot PoPs major metro areas mein meaningfully zyada dekhte hain).

**Bandwidth**
- 5,800 requests/sec x 200 KB ≈ 1.16 GB/sec ≈ 9.3 Gbps average egress sab edges combined ke across; 4x peak par, ≈ 37 Gbps peak. 100 PoPs ke across spread yeh per PoP kaafi manageable hai (roughly 370 Mbps peak average per PoP, again hot PoPs average se well above) — ek modest edge server cluster per PoP local cache se serve kar sakta hai isse comfortably.

**Cache-hit math and origin shielding**
- 92% cache-hit ratio edge par assume karo (mixed static content ke liye ek realistic, strong target). Iska matlab hai peak par 23,200 requests/sec mein se sirf 8% — about 1,856 requests/sec — actually origin tak pahunchte hain, ek small origin fleet ke liye manageable load, poore 23,200/sec ke bajaye jo edges absorb karte hain.
- Yeh ek CDN ka poora economic argument hai: iske bina, origin fleet ko full peak request rate ke liye provision karna padega AUR har request full cross-region latency pay karega; iske saath, origin ko sirf cache-miss trickle ke liye capacity chahiye, aur majority users ko edge-local latency milti hai.

**Storage per edge PoP**
- Har PoP ko poore origin dataset (jo petabytes ho sakta hai) hold karne ki zaroorat nahi — har PoP sirf uske region mein actually popular content ka working set hold karta hai, cold content evict karte hue (ek LRU-style policy, `05_caching.md` ke according).
- Agar ek PoP 50 TB cache storage ke saath provisioned hai aur average object size 200 KB hai, toh yeh roughly 250 million objects ke liye room hai — comfortably ek regional working set hold karne ke liye kaafi sab except most extreme long-tail catalogs ke liye, cold/rare content sirf rare occasions par ek origin fetch par fallback karta hai jab request kiya jaaye.

## Step 3: High-Level Design

**Core components**
- **Origin Servers**: content ke liye authoritative source — object storage ho sakta hai (e.g. S3-like) plus ek application server dynamic-but-cacheable content ke liye.
- **Edge PoPs (Points of Presence)**: many small clusters of caching servers geographically end users ke close distributed — yeh ek CDN ka architectural core hai.
- **DNS-based Routing / GSLB (Global Server Load Balancing)**: ek CDN hostname ko ek nearby/healthy edge PoP ke IP tak resolve karta hai requester ki location ke basis par (cross-reference `04_load_balancing.md`).
- **Anycast Network** (alternative/complementary routing mechanism): same IP address multiple physical PoPs se announce hota hai; normal internet BGP routing har user ke packets ko topologically nearest announcing location tak bhejta hai.
- **Purge/Invalidation Service**: cache-purge requests ko content owners se har edge PoP tak propagate karta hai.
- **Edge Cache Coordination (request coalescing)**: ek single PoP ke andar, ensure karta hai ki same object ke liye ek cache-miss stampede ek single origin fetch mein collapse ho jaaye.
- **Metrics/Observability Pipeline**: per-PoP hit ratio, latency, aur error rates ko ek central monitoring system tak aggregate karta hai.

**Data flow**
1. Content owner Origin par ek asset upload/update karta hai, `Cache-Control` headers set karta hai cacheability aur TTL indicate karte hue.
2. End user `https://cdn.example.com/assets/logo.png` request karta hai.
3. DNS resolution (ya Anycast routing) request ko nearest/healthiest edge PoP tak direct karta hai.
4. Woh PoP apna local cache check karta hai: hit par, directly edge se serve karta hai (fast path, common case 92% hit-ratio estimate ke according).
5. Miss par, PoP Origin se fetch karta hai (ya ek regional mid-tier cache, very large deployments ke liye — Step 6 dekho), response ko locally cache karta hai uski `Cache-Control` policy ke according, aur user ko serve karta hai.
6. Agar content owner asset update ya remove karta hai, ek purge request issue kiya jaata hai, jise Purge Service sab PoPs tak propagate karta hai, har ek apna local copy evict/stale-mark karta hai.

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

**`GET /assets/{path}`** (actual content-serving request, edge par handle kiya jaata hai)
```
Request headers: If-None-Match: "etag123"
Response: 200 OK (cache hit or fresh fetch) with body, or
          304 Not Modified (conditional request, content unchanged)
Response headers: Cache-Control: public, max-age=86400
                   X-Cache: HIT (or MISS)
                   X-Served-By: pop-us-east-1
```

**`POST /purge`** (content owner cached content invalidate karta hai)
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

**`POST /push-cache`** (demand se pehle proactively known-hot content edges par push karna)
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
- Ek simple key-value structure edge par appropriate hai kyunki access pattern purely "look up by exact URL/cache-key" hai — koi relational queries nahi chahiye, aur priority raw lookup speed aur eviction efficiency (LRU/LFU) hai storage pressure ke under, jo exactly wahi cheez hai jiske liye ek local key-value cache (often ek tiered combination — in-memory hottest objects ke liye aur local SSD broader working set ke liye) built hai.

**Purge request log — relational or document database, centrally located**
```
Table: purge_requests
  purge_id    (PK)
  target      (url or prefix)
  issued_at
  status      (propagating | complete | failed)
  pop_confirmations  (JSON map: pop_id -> confirmed_at)
```
- Centrally queryable aur durable hona chahiye (taaki ek content owner purge status check kar sake, aur system kisi bhi PoP tak propagation retry kar sake jisne confirm nahi kiya), but volume content-serving traffic ke relative low hai, toh ek standard relational/document store sufficient hai — yahan koi special scaling nahi chahiye.

**Origin content — object storage (e.g. S3-like blob store) actual assets ke liye, plus ek lightweight relational/document metadata store**
```
Table: asset_metadata
  asset_id / path (PK)
  content_type
  cache_control_policy
  current_etag
  last_modified
```
- Object storage bulk asset bytes khud ke liye natural fit hai (durable, cheap petabyte scale par, relationally query nahi hota); metadata jise quick structured lookup chahiye (current ETag conditional requests ke liye, cache policy) separately aur cheaply rakha jaata hai.

## Step 6: Deep Dive

### 6.1 Edge PoP Architecture and the Latency Argument

Poora CDN ka premise ek simple physical fact par tika hai "latency numbers every engineer should know" discussion se (`02_scalability_and_estimation.md`): global scale par round-trip network latency physical distance aur us distance ke across speed-of-light propagation delay se dominate hoti hai, na ki server khud request kitni fast process karta hai. Ek perfectly optimized origin server Virginia mein abhi bhi ek Singapore ke user ko roughly round-trip light-speed-in-fiber delay us distance ke liye allow karta hai usse fast serve nahi kar sakta — often 200ms+ round trip regardless of server-side optimization.

Ek CDN ka answer architectural hai, algorithmic nahi: many small caching servers (Edge PoPs) physically deploy karo jahan users actually hain uske close, taaki bulk requests (92% hit-ratio assumption Step 2 ke according) origin ke aas paas kahin bhi travel na karein. Isliye ek modest, even somewhat under-provisioned edge server ek highly-optimized, powerful origin server ko outperform kar sakta hai end-user-perceived latency ke liye — server ko physically closer move karna frequently ek bigger latency win hota hai kisi bhi amount ke server-side optimization se jo ek single, distant origin par apply kiya jaaye. Yeh framing sabse important cheez hai jo is question ka answer dete waqt early communicate karni chahiye, kyunki yeh explain karti hai ki baaki poora design (routing, cache population, invalidation) is ek physical constraint ki service mein kyun exist karta hai.

### 6.2 Routing Users to Their Nearest/Best Edge PoP

Do complementary mechanisms, dono explain karne worth hain aur note karna worth hai ki real CDNs commonly dono combine karte hain:

**DNS-based routing / GSLB**: CDN ka authoritative DNS server, `cdn.example.com` resolve karte waqt, ek single fixed IP return nahi karta — yeh inspect karta hai ki DNS query kahan se aa rahi hai (typically resolver ka IP, end user ki approximate location ke proxy ke roop mein use kiya jaata hai) aur us region ke liye nearest ya currently-healthiest PoP ka IP address return karta hai, `04_load_balancing.md` ke load-balancing/GSLB concepts ke according. Isse fine-grained control milta hai: CDN operator real-time PoP health, load, aur even business logic (e.g. ek PoP undergoing maintenance ke around route karna) ko har DNS answer mein factor kar sakta hai. Trade-off yeh hai ki DNS resolution multiple layers par caching involve karta hai (TTLs) (OS, ISP resolver), toh routing decisions instantaneously change nahi kiye ja sakte — ek PoP jo abhi unhealthy hua hai abhi bhi un users se traffic receive kar sakta hai jinka DNS answer moments pehle cache ho chuka tha.

**Anycast**: same IP address simultaneously har PoP ki network location se BGP ke through announce kiya jaata hai, aur standard internet routing infrastructure — bina kisi CDN-specific logic ke — naturally har user ke packets ko jo bhi announcing location topologically nearest hai (fewest BGP hops) route karta hai, kyunki yahi tarika hai jaise internet routing inherently kaam karta hai. Iska advantage yeh hai ki yeh network layer par kaam karta hai, DNS caching se completely neeche, toh yeh ek PoP ke down hone par faster react karta hai (routers simply un location ka announcement sunna band kar dete hain aur reroute kar dete hain) aur DNS TTL staleness se suffer nahi karta. Trade-off coarser control hai — CDN operator ke paas kam fine-grained say hai exactly kaunsa PoP ek given user par land hota hai, kyunki yeh internet routing topology se determine hota hai, ek explicit, business-logic-aware decision se nahi.

Real-world CDNs frequently dono combine karte hain: Anycast ek user ke connection ko quickly aur resiliently ek topologically-nearby PoP tak le jaata hai, jabki DNS-based/application-layer logic abhi bhi specific hostnames ko steer kar sakti hai ya finer load-balancing decisions handle kar sakti hai nearby PoPs ke andar ya across.

### 6.3 Cache Population: Pull vs Push

**Pull CDN (zyadatar content ke liye default)**: ek edge PoP proactively content hold nahi karta jab tak actually request na kiya jaaye — ek given PoP par ek given asset ka first request karne wala user ek cache miss cause karta hai, jo origin se ek fetch trigger karta hai, jiske baad woh PoP subsequent requests ke liye result cache kar leta hai. Yeh right default hai kyunki proactively har piece of content ko potentially hundreds of PoPs worldwide tak push karna scale nahi karta — zyadatar content ki demand geographically concentrated hoti hai (ek local news site ki images mostly geographically nearby users se request ki jaati hain), toh zyadatar PoPs storage aur bandwidth waste karenge aisa content hold karke jise unke nearby koi kabhi request nahi karega. Yeh `05_caching.md` ke pull vs push framing ko mirror karta hai, applied edge-network scale par instead of ek single application cache par.

**Push (proactive distribution)**: ek small, deliberately-identified set of known-hot ya business-critical content ke liye reserved — e.g. ek major OS update, ek big game patch release, ya ek high-profile live-event asset jo advance mein pata hai ki ek massive synchronized demand spike generate karega available hote hi. Is content ko release moment se pehle proactively sab (ya strategically likely-relevant) PoPs tak distribute karna har PoP ko independently ek cache-miss stampede (6.5) face karne se avoid karta hai exact same instant par jab demand hit karti hai. Yeh pull default ka ek deliberate, selective exception hai — sparingly use kiya jaata hai, un content ke liye jahan operator advance mein spike predict kar sakta hai aur jahan over-provisioning ka cost clearly justified hai otherwise-inevitable origin overload launch moment par avoid karke.

### 6.4 Cache Invalidation/Purging Across Distributed Edge Locations

Cache invalidation already caching mein do hard problems mein se ek hai generally (`05_caching.md` ki invalidation discussion) — yeh jaanna ki cached data kab stale hai aur usse correctly get rid karna. Ek CDN yehi same fundamental difficulty inherit karta hai aur usse edge locations ki number se multiply karta hai: ek asset ke liye ek purge ab potentially hundreds of PoPs worldwide tak reach aur apply hona chahiye, har ek independently chal raha hai, kuch temporarily unreachable ya heavily loaded ho sakte hain purge issue hote waqt.

Honest, production-realistic answer yeh hai ki purge propagation speed aur system complexity/cost ke beech ek genuine trade-off hai, aur ek well-designed CDN explicit expectations set karta hai instead of kuch unachievable promise karne ke:
- Ek purge request ek baar issue kiya jaata hai (e.g. `POST /purge` API ke through) aur har PoP tak fan out kiya jaata hai, typically CDN ke apne internal control-plane network par (user-facing traffic se separate rakha jaata hai).
- Har PoP purge apply hone par acknowledge karta hai; central Purge Service har PoP ke confirmations track karta hai (Step 5 ke `purge_requests` table mein modeled) aur kisi bhi PoP ke against retry kar sakta hai jisne expected window ke andar confirm nahi kiya.
- Real-world CDN purges commonly globally fully propagate hone mein kahin bhi kuch seconds se couple minutes tak lete hain — yeh explicitly honest target ke roop mein state kiya jaana chahiye instead of instant global consistency claim karne ke, kyunki hundreds of independently-operating, geographically-distant locations ke across true instant consistency achieve karne ke liye synchronous coordination chahiye hoga jo normal caching path ke liye prohibitively slow aur fragile hoga jo baaki 99.9%+ requests serve karta hai.
- Ek lower-latency alternative un content ke liye jo har update par identity change karta hai (in place purge hone ke bajaye) hai versioned URL ya filename ke through cache-busting (e.g. `logo.v2.png` ya ek content-hash-based filename) — kyunki ek new URL, CDN ki perspective se, simply ek naya cache key hai bina kisi stale entry ke invalidate karne ke, yeh propagation-delay problem ko entirely sidestep karta hai un content ke liye jinke naming ko origin control karta hai, aur build artifacts (JS/CSS bundles) ke liye preferred pattern hai instead of purge propagation timing par rely karne ke.

### 6.5 Handling a Cache-Miss Stampede at a Single Edge PoP (Thundering Herd)

Jab previously-uncached content suddenly ek specific PoP par popular ho jaata hai (e.g. ek piece of content ek region mein viral ho jaata hai, ya ek TTL expiry ek burst of simultaneous requests ke saath coincide kar jaata hai), many concurrent requests same object ke liye us PoP par milliseconds ke andar arrive ho sakti hain, sab first request ke origin se fetch khatam karne se pehle. Naively, in mein se har concurrent request independently ek cache miss detect karegi aur independently apna fetch origin ko issue karegi — same thundering-herd/dog-piling problem jo `05_caching.md` mein discuss ki gayi hai, but ek single edge location par ho raha hai jo shayad ek region ka ek meaningful fraction of traffic serve kar raha ho.

Fix, specifically edge layer par applied, request coalescing hai: pehli request jo PoP par cache miss detect karti hai ek short-lived local marker acquire karti hai (e.g. cache key se keyed ek in-memory lock) yeh indicate karte hue "is object ke liye ek fetch already in flight hai," single origin fetch issue karti hai, aur har doosri concurrent request same object ke liye jo us PoP par fetch outstanding hote hue arrive hoti hai, locally hold/queue ki jaati hai aur us single in-flight fetch ke result se serve ki jaati hai complete hone par, instead of har ek independently origin hit karne ke. Isse ek popular object ka stampede origin-side overload mein badalne se ruk jaata hai — origin ko at most ek request per PoP per stale/missing object dikhta hai, regardless of kitne thousands end users simultaneously usse us PoP ke through request kar rahe hain, jo precisely wahi cheez hai jo origin-shielding math (Step 2 mein — sirf 8% traffic origin tak pahunchta hai) actually true rakhti hai real bursty conditions ke under, sirf average par nahi.

## Step 7: Bottlenecks & Trade-offs

- **Long-tail cold content still hits origin**: content jo rarely request hota hai ek given PoP par (ya globally) ek useful cache-hit ratio locally build up nahi karega, matlab har aisi request full origin round-trip latency pay karti hai regardless of edge infrastructure. Mitigation: very large catalogs ke liye, ek regional "mid-tier" cache layer introduce karo edge PoPs aur origin ke beech (ek smaller number of larger regional caches, har ek many nearby edge PoPs serve karta hai) — ek edge PoP par miss regional tier check karta hai origin tak poori tarah jaane se pehle, cross-PoP-within-region locality capture karte hue bina har small PoP ko poora regional working set hold karne ki zaroorat ke.
- **Purge propagation delay is an inherent trade-off, not a solvable bug**: jaisa 6.4 mein discuss kiya, purges ke liye instant global consistency realistically achievable nahi hai bina normal-path caching performance ko unacceptable cost pay kiye; mitigation honest expectations set karna hai plus versioned/content-hashed URLs offer karna fast-path escape hatch ke roop mein un content ke liye jahan staleness truly tolerate nahi ki ja sakti even briefly.
- **PoP failure and failover**: ek individual PoP down hona (hardware failure, regional network issue) un users ke liye outage cause nahi karna chahiye jinhe woh serve karta hai. Mitigation: health-checked DNS/GSLB routing (6.2) new DNS resolutions ko ek unhealthy PoP se door redirect karta hai, aur Anycast ka BGP-level failover in-flight routing ko faster handle karta hai DNS TTLs se zyada — dono mechanisms ki complementary failure characteristics (DNS ki business-logic awareness vs Anycast ki network-layer speed) hi exactly wahi reason hain ki dono combine karna standard practice kyun hai.
- **Uneven traffic distribution across PoPs**: ek viral event ek region mein concentrated us region ke PoP capacity ko overload kar sakta hai jabki doosre PoPs idle baithe rahein. Mitigation: GSLB routing logic real-time PoP load factor kar sakta hai (sirf geographic proximity nahi) aur overflow traffic ko next-nearest healthy PoP tak spill kar sakta hai, un overflow users ke liye ek small latency increase trade karte hue ek outage avoid karne ke against.
- **Trade-off — storage cost vs hit ratio per PoP**: har PoP ko itna storage provision karna ki origin catalog ka ek very large fraction cache kar sake hit ratio improve karta hai but hundreds of PoPs par expensive hai; under-provisioning cost save karta hai but origin par zyada traffic push karta hai aur average latency increase karta hai. Yeh ek direct, ongoing cost/performance dial hai jo actual observed access patterns ke basis par per deployment tune kiya jaata hai (Step 2 ke storage estimation ke according), ek one-time architectural decision nahi.

## Follow-up Questions an Interviewer Might Ask

1. **"Aap dynamic, personalized content ko kaise handle karoge jo technically har user ke liye same tarike se cache nahi ho sakta?"** Cacheable-but-varying content (`Vary` headers ya cache keys use karo jo varying dimension include karte hain, e.g. device type ya locale, taaki CDN ek small number of variants cache kare instead of usse fully uncacheable treat karne ke) ko truly per-user dynamic content se distinguish karo, jise cache entirely bypass karke directly origin tak proxy kiya jaana chahiye — CDN yahan bhi value add karta hai ek fast, geographically-distributed proxy/TLS-termination layer ke roop mein even bina caching ke.

2. **"Aap content ko secure kaise karte ho taaki unauthorized users access na kar sakein, given ki yeh ab aise servers par cached hai jinka aap end-to-end fully trust nahi karte?"** Signed URLs/tokens with expiry (origin ya ek control-plane service ek time-limited signed URL issue karta hai, aur edge PoPs signature validate karte hain cache se serve karne se pehle) CDN ko cached content serve karne dete hain bina har request ko origin ke against re-authenticate kiye, jabki still access control enforce karte hue.

3. **"Agar origin khud down ho jaaye — kya poora CDN uske saath down ho jaata hai?"** Ek well-designed CDN already-cached content serve karte rehna chahiye (even normal TTL ke past bhi, ek "stale-while-revalidate" ya "serve-stale-on-origin-error" mode mein) origin outage ke dauran, strict freshness ko continued availability ke against trade karte hue — yeh explicitly ek resilience feature ke roop mein mention karne worth hai instead of origin availability ko har request ke liye ek hard dependency treat karne ke.

4. **"Aap isko video streaming specifically support karne ke liye kaise extend karoge, jahan content many small segments mein deliver hota hai?"** Video streaming (e.g. HLS/DASH) content ko many small time-based segments mein split karta hai, har ek independently cacheable — same edge-caching aur pull-population model per-segment apply hota hai, but request coalescing (6.5) aur next few segments prefetch karna jo ek viewer request karne wala hai zyada important ho jaate hain given sequential, predictable access pattern ke.

5. **"Aap kaise decide karoge kitne PoPs deploy karne hain aur kahan?"** Latency coverage (zyada PoPs zyada users ke close average round-trip distance reduce karte hain) ko operational cost ke against balance karo aur is fact ke against ki har additional PoP ka ek minimum viable traffic level hota hai cost-effective hone ke liye — typically actual user geographic distribution data se driven, dense population/traffic centers ko pehle prioritize karte hue aur initially less-served regions ki ek longer tail accept karte hue, similar to general estimation-driven trade-off reasoning jo is folder ke designs mein throughout use hoti hai.

6. **"Aap ek PoP ko silently stale ya corrupted content serve karte hue kaise monitor aur detect karoge?"** Periodic synthetic/canary requests known content ke against ek known-good checksum ke saath, ek central monitoring system se har PoP ke against issued, silent divergence catch kar sakti hain (ek purge jo apply karne mein fail hua, ek corrupted cache entry) jo normal traffic-based metrics jaise hit ratio aur latency necessarily apne aap surface nahi karte.
