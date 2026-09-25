# Design a Web Crawler

## Problem Statement

"Design karo ek web crawler. Ek set of seed URLs diye gaye, system ko
systematically discover aur download karna chahiye pages web se — seeds
se start karke, har downloaded page se hyperlinks extract karke, aur un
links ko follow karke aur pages discover karte hue — billions of pages
ke scale pe, bina kisi single website ko hammer kiye, bina infinite loops
mein stuck hue, aur already-crawled content ko time ke saath reasonably
fresh rakhte hue।" Yeh woh system hai jo search engine ke indexing
pipeline ke front pe baithta hai (think ek early Googlebot), ya jo kisi
bhi large-scale web data collection product ko power karta hai।

## Step 1: Requirements Clarify Karo

### Functional Requirements

- Ek set of seed URLs diye gaye, outward crawl karo har page pe discover
  hue hyperlinks follow karke।
- Har crawled page ka raw content (kam se kam HTML) download aur persist
  karo ek downstream indexing/processing pipeline ke liye।
- Har page ke HTML se links extract aur normalize karo naye candidate
  URLs discover karne ke liye।
- Same URL ko freshness policy dictate karne se zyada baar recrawl mat
  karo — yeh ek one-shot crawl nahi hai, yeh continuously chalta hai।
- Crawling prioritize karo: kuch pages (high-authority news sites,
  frequently-updated pages) ko jaldi aur zyada baar crawl hona chahiye
  ek obscure, static personal blog ke muqable।
- `robots.txt` aur kisi bhi per-site `Crawl-delay` directive ko respect
  karo।
- Baad mein naye content types ke liye extensible ho (images, PDFs, video
  metadata) — core pipeline ko HTML-only assume nahi karna chahiye, bhale
  hi abhi sirf HTML parsing hi built ho।

### Non-Functional Requirements

- **Scale**: roughly 1 billion pages per month crawl sustain karo
  (mid-size search engine scale, planet-scale nahi, lekin ek toy script
  se kaafi zyada)।
- **Throughput**: average aur peak fetch rate jo us monthly target ke
  saath keep up kare, bursty re-indexing campaigns ke liye headroom ke
  saath।
- **Politeness**: kabhi bhi same domain ko ek minimum interval ke andar
  ek se zyada request mat bhejo (kuch sau ms se lekar multiple seconds
  tak, site pe depend karta hai) — yeh ek hard constraint hai, nice-to-
  have nahi।
- **Scalability**: har axis pe horizontally scalable — more crawler
  workers, more frontier capacity, more storage — kyunki URL space aur
  content volume dono bina bound ke badhte hain।
- **Fault tolerance**: ek crawler worker ka mid-fetch crash hona
  significant progress lose nahi karna chahiye ya restart pe large-scale
  duplicate work cause nahi karna chahiye।
- **Extensibility**: freshness/priority policy per-domain ya per-content
  category tunable honi chahiye bina system redeploy kiye।
- **Consistency**: strong sense mein kuch bhi zaroori nahi — crawl
  frontier aur crawled-page index inherently eventually consistent hain;
  "page thoda hours stale hai" ek acceptable, expected state hai, bug
  nahi।
- **Safety**: per-domain bounded resource usage — design ko actively
  unbounded URL spaces (crawler traps) ko poora crawl budget consume
  karne se rokna chahiye।

## Step 2: Back-of-Envelope Estimation

**Assumptions** (explicitly stated, jaisa ek candidate karega):
- Target: 1 billion pages crawled per month.
- Average fetched page size: 500 KB raw HTML (text-light API-driven
  pages aur image-heavy inline markup ke beech ek reasonable middle
  ground — yeh download khud hai, embedded assets nahi, jinhe most
  crawlers skip karte hain ya separately fetch karte hain)।
- Average out-degree: ~30 links discovered per page।
- Known URL space (seen, chahe crawled ho ya na ho) roughly 10x hai
  actually crawled pages ka ek month mein, kyunki ek crawl policy
  frontier ka sirf ek fraction hi revisit karti hai har month, continuously
  naye links discover karte hue — isse call karo 10 billion known URLs।

**Fetch QPS**

```
1,000,000,000 pages / month
  ÷ (30 days × 24 hours × 3600 sec) = 2,592,000 sec/month
  ≈ 386 pages/sec average
```

Ek 3x peak multiplier assume karo re-indexing pushes ya downtime ke baad
catch up karne ke liye:

```
386 × 3 ≈ 1,160 pages/sec peak
```

**Bandwidth**

```
Average: 386 pages/sec × 500 KB = 193,000 KB/sec ≈ 188 MB/s ≈ 1.5 Gbps sustained
Peak:    1,160 pages/sec × 500 KB ≈ 566 MB/s ≈ 4.5 Gbps
```

Yeh outbound+inbound bandwidth ka ek meaningful, lekin exotic nahi, amount
hai — comfortably usme jo ek handful well-connected data-center links ya
ek cloud provider ka network tier sustain kar sakta hai।

**Storage (raw content)**

```
1e9 pages/month × 500 KB = 5e11 KB = 5e8 MB = 500,000 GB = 500 TB/month raw
```

HTML pe ~4:1 gzip compression apply karke (text bahut achhi compress hota
hai):

```
500 TB / 4 ≈ 125 TB/month compressed
→ ~1.5 PB/year compressed
```

Yeh object-storage territory hai (dekho `12_storage_systems.md`), koi
filesystem ya relational database nahi।

**URL frontier / dedup structure**

Known URL space: 10 billion URLs. "Kya humne pehle yeh URL dekha hai"
track karne ke do tareeke:

- **Naive hash set of full URLs**: average URL length ~60 bytes.
  `10e9 × 60 bytes = 600 GB` sirf set hold karne ke liye, bina kisi
  indexing overhead ke — aur yeh assume kar raha hai ki koi hash-table
  load-factor waste nahi, jo practice mein 30-50% aur add karta hai।
- **Bloom filter at a 1% false-positive rate**: roughly 9.6 bits per
  element chahiye (standard Bloom filter sizing formula ~1% FPR ke
  liye)। `10e9 × 9.6 bits = 9.6e10 bits ≈ 12 GB`.

Yeh ek **50x** memory reduction hai (600 GB → 12 GB) ek small, bounded
false-positive rate accept karne ke badle — yehi concrete number hai jo
Bloom filter ko is scale pe obvious choice banata hai (detailed Step 6
mein)।

**URL metadata storage** (frontier state — status, priority, last-crawled
time, per known URL):

```
10e9 URLs × ~100 bytes/record (url, hash, domain, status, priority, last_crawled_at, next_crawl_at)
≈ 1,000,000,000,000 bytes = 1 TB
```

Comfortably ek distributed wide-column store mein fit hota hai, URL hash
se sharded।

**Concurrent connections aur DNS load**

Peak pe (1,160 pages/sec) ek average fetch roughly 2 seconds end-to-end
leta hai (DNS + connect + TLS handshake + download), Little's Law un
connections ki count deta hai jo simultaneously in flight honi chahiye:

```
Concurrent in-flight fetches ≈ throughput × latency = 1,160 pages/sec × 2 sec ≈ 2,320 concurrent connections
```

In connections mein se har ek typically ek DNS lookup se start hota hai
jab tak target domain ka IP already cached na ho, isliye worker fleet ke
front mein ek caching DNS resolver layer is volume pe close to mandatory
hai — har fetch ke liye directly public DNS ko hit karna tens to hundreds
of milliseconds ka avoidable latency add karega har new-domain request
pe aur risk hai ki crawler khud upstream resolvers se rate-limited ho
jaaye।

**Content dedup checksum storage**

URL-level dedup (Step 6 ka Bloom filter) ke alawa, system har crawled
page (Step 5) ke liye ek `content_hash` bhi store karta hai byte-identical
ya near-identical recrawls detect karne ke liye। Ek hash per crawled page
per month pe:

```
1e9 pages/month × 20 bytes/hash (SHA-1 truncated) = 2e10 bytes = 20 GB/month of pure hash data
```

125 TB/month raw content ke muqable negligible hai — same metadata store
mein resident rakhna cheap hai jo already crawl status track kar rahi
hai।

**Crawler worker count**

Assume karo har worker ~50 concurrent in-flight connections hold karta
hai, aur har fetch (DNS, connect, TLS, download, aur politeness wait
amortized queue time ke tor pe fold kiya hua) average 2 seconds wall time
leta hai per connection slot:

```
Throughput per worker ≈ 50 connections / 2 sec ≈ 25 pages/sec
```

```
Workers needed at average load: 386 / 25 ≈ 16
Workers needed at peak load:    1,160 / 25 ≈ 47, round up to ~60 for headroom
```

Toh fleet size "tens of machines" hai, thousands nahi — ek real crawler
mein bottleneck almost kabhi raw worker count nahi hota, yeh politeness
constraints aur frontier management hota hai (Step 6)।

## Step 3: High-Level Design

```text
                         +------------------+
                         |   Seed URL List   |
                         +---------+--------+
                                   |
                                   v
   +---------------+     +------------------+     +-------------------+
   |  URL Filter /  |<----|   URL Frontier   |---->|  Politeness Layer |
   |  Bloom Filter  |     | (per-domain      |     | (per-domain rate  |
   |  dedup         |     |  priority queues)|     |  limiter + robots |
   +-------+--------+     +--------+---------+     |  .txt cache)      |
           ^                       |                +---------+---------+
           |                       v                          |
           |              +------------------+                v
           |              |  Crawler Workers |<----------------+
           |              | (fetch, follow   |
           |              |  redirects, DNS) |
           |              +--------+---------+
           |                       |
           |                       v
           |              +------------------+       +------------------+
           |              |  HTML Parser &   |------>|   Content Store  |
           |              |  Link Extractor  |       |  (object storage,|
           |              +--------+---------+       |   compressed)    |
           |                       |                 +------------------+
           |                       v
           |              +------------------+
           +--------------|  New URLs found  |
                           +------------------+
                                   |
                                   v (loop back into Frontier)
                         +------------------+
                         |  URL Metadata DB |  (status, priority, next_crawl_at)
                         +------------------+
                                   |
                                   v
                         +------------------+
                         | Downstream Index |  (out of scope: search index build)
                         +------------------+
```

**Flow**: ek worker frontier se ek batch of URLs pull karta hai (already
politeness ke liye filtered — frontier sirf un URLs deta hai jinke domain
abhi rate-limited nahi hain), page fetch karta hai, raw bytes content
store ko hand kar deta hai, aur HTML parser ko de deta hai। Parser links
extract karta hai, unhe normalize karta hai (relative URLs resolve karo,
fragments strip karo, host lowercase karo), aur har ek ko Bloom filter
dedup check se guzarta hai isse pehle ki woh frontier mein ek new
candidate ke tor pe wapas allow ho। URL metadata DB durable source of
truth hai "yeh URL kis state mein hai" ke liye (queued, in-progress,
done, failed) — frontier khud ek fast, partially-volatile work queue
jaisi hai jo us state se built hai।

**Key components**:
- **URL Frontier**: prioritized, per-domain-partitioned work queue —
  poore system ka actual bottleneck (Step 6)।
- **Politeness Layer**: per-domain crawl-delay enforce karta hai aur har
  domain ka parsed `robots.txt` cache karta hai taaki har request pe
  re-fetch na ho।
- **URL Filter / Bloom Filter**: fast, memory-cheap "kya maine yeh URL
  dekha hai" check isse pehle ki uspe ek fetch spend ho।
- **Crawler Workers**: stateless fetch-and-parse processes; horizontally
  scalable, disposable, koi local state nahi jo frontier + metadata DB se
  rebuild na ho sake।
- **Content Store**: object storage (S3-like) jo raw/compressed page
  bytes hold karta hai, URL ke hash se keyed।
- **URL Metadata DB**: har known URL ka durable record uske crawl status
  aur scheduling info ka।

**Ek URL ko end to end walk through karte hue**: (1) frontier ka
per-domain scheduler check karta hai ki `example.com` currently apne
`next_allowed_fetch_time` se past hai ya nahi; agar nahi, URL queued
rehta hai aur scheduler next eligible domain pe move karta hai। (2) Ek
baar eligible hone pe, ek worker ek batch dequeue karta hai jisme yeh URL
included hai, `example.com` ke cached `robots.txt` rules check karta hai
confirm karne ke liye ki path disallowed nahi hai, aur fetch issue karta
hai। (3) Ek successful response pe, raw bytes content store mein likhe
jaate hain aur ek `content_hash` compute hoti hai। (4) HTML parse hoti
hai, links extract aur normalize hote hain। (5) Har extracted link Bloom
filter ke against check hoti hai; new-looking links URL metadata DB mein
`discovered` ke tor pe likhi jaati hain aur appropriate domain ke
frontier queue mein push ki jaati hain (jo page discover karne wale se
alag partition ho sakta hai, kyunki link kisi bhi domain ki taraf point
kar sakta hai)। (6) Abhi-crawled URL ka metadata DB record update hota
hai: `status = crawled`, `last_crawled_at = now`, `next_crawl_at`
freshness policy se recomputed (Step 6), aur domain ka
`next_allowed_fetch_time` politeness layer mein advance ho jaata hai। Yeh
loop — dequeue, politeness check, fetch, parse, dedup-and-requeue,
update metadata — poore system ka steady-state behavior hai, jo saare
domain partitions ke across parallel mein continuously chalta rehta hai।

## Step 4: API Design

Ek crawler ka zyada tar "API" internal hota hai (frontier ↔ worker RPCs),
lekin system ko ek operator-facing surface bhi chahiye:

**Seed URLs add karo**
```
POST /seeds
{ "urls": ["https://example.com", "https://news.example.org"] }
→ 202 Accepted { "accepted": 2 }
```

**Ek URL ka crawl status query karo**
```
GET /crawl/status?url=https://example.com/page
→ 200 OK
{
  "url": "https://example.com/page",
  "status": "crawled",
  "last_crawled_at": "2026-09-10T04:12:00Z",
  "next_crawl_at": "2026-09-17T04:12:00Z",
  "content_hash": "a1b2c3..."
}
```

**Ek domain ke liye crawl policy adjust karo** (operator/admin control)
```
POST /policy/domain
{ "domain": "news.example.org", "priority": "high", "recrawl_interval_hours": 6 }
→ 200 OK
```

**Fleet stats** (monitoring/ops ke liye)
```
GET /stats
→ 200 OK
{ "pages_crawled_last_hour": 1390000, "frontier_size": 842000000, "active_workers": 58 }
```

**Internal frontier RPC** (worker ↔ frontier, public nahi)
```
Frontier.Dequeue(worker_id, batch_size=50) → [ {url, domain, priority}, ... ]
Frontier.ReportResult(url, status, discovered_links=[...], content_hash) → ack
```

## Step 5: Data Model

**URL Metadata table** — wide-column NoSQL (Cassandra/DynamoDB-style),
`url_hash` se partitioned even distribution ke liye:

| Field | Type | Notes |
|---|---|---|
| `url_hash` (PK) | string | SHA-1/MD5 of normalized URL |
| `url` | string | full normalized URL |
| `domain` | string | secondary index — used for per-domain queries |
| `status` | enum | `discovered`, `queued`, `in_progress`, `crawled`, `failed` |
| `priority` | int | derived from domain authority + change frequency |
| `last_crawled_at` | timestamp | |
| `next_crawl_at` | timestamp | drives recrawl scheduling |
| `content_hash` | string | detects unchanged content across recrawls |
| `discovered_at` | timestamp | |

NoSQL/wide-column sahi fit hai: access almost hamesha ek point lookup ya
ek scan hota hai `next_crawl_at`/`domain` se, write volume enormous hai
(billions of rows churned per month), aur koi cross-record relational
joins nahi hain jo SQL ke overhead ko justify karein।

**URL Frontier** — ek table bilkul nahi, balki ek distributed
priority-queue structure, commonly per-domain queues ke tor pe
implemented ek system mein jaise Redis (sorted sets scored by
`next_allowed_fetch_time`) ya ek dedicated queueing layer। Yeh
intentionally metadata DB se separate rakha jaata hai kyunki frontier ko
*fast* hona chahiye (millions of dequeue/enqueue ops) jabki metadata DB
ko *durable* hona chahiye — frontier ko metadata DB se partially rebuild
kiya ja sakta hai agar woh lost ho jaaye।

**Content Store** — object storage (S3-class), key = `url_hash`, value =
compressed raw HTML bytes + ek small header (content-type, fetch
timestamp, HTTP status)। Object storage sahi fit hai kyunki content
large hai, immutable hai ek baar likhe jaane ke baad (ek recrawl ek new
object likhta hai in place update karne ki jagah), aur simple key se
access hota hai — koi database query capabilities ki zaroorat nahi।

**robots.txt cache** — small key-value cache (Redis), key = domain,
value = parsed rule set + `fetched_at`, TTL'd (jaise, 24 hours) taaki yeh
periodically refresh ho bina har single page fetch pe har domain ka
`robots.txt` hit kiye।

**Bloom filter** — koi database bilkul nahi; ek in-memory (ya
sharded-in-memory-across-nodes) probabilistic structure, next detail
mein।

**Storage choice justification, summarized**:

| Component | Storage type | Why |
|---|---|---|
| URL metadata | Wide-column NoSQL | Massive write volume, point/scan access by hash or domain, no joins |
| Frontier queue | In-memory sorted structure (Redis-like) | Needs fast enqueue/dequeue at millions of ops/sec, rebuildable from metadata DB |
| Content store | Object storage | Large, immutable blobs, simple key-based access, cheapest at this volume |
| robots.txt cache | Key-value cache with TTL | Small, hot, read on every fetch, tolerates brief staleness |
| Bloom filter | In-memory probabilistic set | Needs to answer membership at fetch-time speed for 10B+ URLs within realistic memory |

## Step 6: Deep Dive

### URL Frontier: Prioritization aur Freshness

Frontier hi system ka real bottleneck hai aur sabse interesting design
surface — yeh ek plain FIFO queue nahi hai, kyunki do competing goals ko
simultaneously balance karna padta hai: **breadth** (new pages discover
karo) aur **freshness** (important pages ko stale hone se pehle revisit
karo)।

**Structure**: frontier ek global queue ki jagah bahut saari small
per-domain queues ke tor pe organized hai। Har domain ki queue priority
score se ordered hai, aur ek separate scheduler decide karta hai kaunse
domain queues abhi "dequeue karne ke liye eligible" hain, politeness rule
ke basis pe (Step 6, next section) — ek domain jiska last fetch bahut
recent tha, offer hi nahi kiya jaata, chahe uska next URL kitna bhi
high-priority kyun na ho।

**Prioritization signals**, jo ek single priority score per URL mein
combine hote hain:
- **Domain authority / importance**: high-traffic, high-inbound-link
  domains (major news sites, popular reference sites) pe pages zyada
  eagerly crawl hoti hain — approximated inbound link count ya ek
  PageRank-style score se jo offline compute kiya jaata hai link graph
  se jo crawl khud already bana raha hai।
- **Historical change frequency**: ek page jiska content last several
  recrawls pe change hua hai (different `content_hash`), uska
  `next_crawl_at` interval shorter ho jaata hai; ek page jo ek saal se
  byte-identical hai, uska interval much longer push kiya jaata hai। Yehi
  hai jo freshness policy ko per-page banata hai poore web ke liye ek
  single fixed interval ki jagah — ek static "About Us" page aur ek live
  sports score page ki ideal recrawl rates wildly different hoti hain,
  aur system ko yeh observed history se seekhna chahiye, hand se
  configure karne ki jagah।
- **Depth from seed / discovery recency**: newly discovered URLs ko ek
  modest priority boost milta hai taaki crawl entirely old pages
  recrawl karne pe stall na ho jaaye aur naye pages discover karna kabhi
  na rok de — yeh breadth-vs-freshness knob hai, typically ek weighted
  mix ke tor pe tune kiya jaata hai, ek doosre pe strictly dominate karne
  ki jagah।

**Yeh concretely kyun matter karta hai**: bina differentiated freshness
ke, sirf do options hain "sab kuch ek fixed schedule pe recrawl karo"
(enormous fetch budget waste hota hai un pages ko re-download karne mein
jo kabhi change nahi hote) ya "kabhi recrawl mat karo" (index stale ho
jaata hai)। Ek frequency-aware frontier apna ~386 pages/sec budget wahan
spend karta hai jahan woh actually freshness khareedta hai।

**Implementation shape**: isko realize karne ka ek common tareeka hai har
URL ka priority score ek numeric field ke tor pe metadata DB (Step 5)
mein store karna, jo har crawl ke baad ek simple formula se recompute
hota hai jaise `priority = domain_authority_weight ×
change_frequency_weight`, aur frontier ki per-domain queue ko actually
ek min-heap (ya ek sorted-set) banana `next_crawl_at` se ordered, insertion
order se nahi — dequeuing hamesha jo bhi eligible URL apne own target
interval ke relative sabse zyada overdue hai usse pull karta hai, sirf
sabse oldest-enqueued wala nahi। Jab ek URL ka `content_hash` do ya teen
consecutive recrawls mein unchanged aata hai, uska `next_crawl_at`
interval multiplicatively back off ho jaata hai (retries ke exponential
backoff jaisa spirit mein); jab yeh change hota hai, interval tighten ho
jaata hai। Yeh freshness policy ko self-correcting banata hai bina kisi
operator ke manually per-domain schedules tune kiye।

### Politeness: Rate Limiting aur robots.txt

**Per-domain rate limiting** ek hard constraint hai, ek performance
optimization nahi — ek single web server ko hundreds of concurrent
requests se hit karna usse gira sakta hai ya target ke apne DDoS
protections trigger kar sakta hai, jispe crawler IP-banned ho jaata hai
aur us domain tak access permanently lose kar deta hai। Politeness layer
same domain ko consecutive requests ke beech ek minimum delay enforce
karta hai (commonly default se kuch seconds, ya jo bhi site ka apna
`Crawl-delay` directive specify kare), ek `next_allowed_fetch_time` per
domain ke tor pe track kiya jaata hai, jo frontier ke us domain ke liye
URL dene se pehle check hota hai।

**`robots.txt`** ek plain-text file hai (`https://domain.com/robots.txt`)
jo ek site publish karti hai automated crawlers ko yeh batane ke liye ki
woh kaunse paths access kar sakte hain aur kaunse nahi, aur kis rate pe।
Ek typical file kuch aisi dikhti hai:

```
User-agent: *
Disallow: /admin/
Disallow: /search
Crawl-delay: 5

User-agent: GoodBot
Disallow:
```

Compliance do concrete reasons se matter karti hai: **ethically**, yeh
file site owner ka explicit statement hai kis chiz pe woh crawl hone ke
liye consent de rahe hain (kuch paths disallowed hote hain kyunki woh
render karna expensive hai, private hai, ya simply indexing ke liye
intended nahi hai), aur usse ignore karna is consent ka ek real breach
hai; **practically**, `robots.txt` (ya uske `Crawl-delay`) ko ignore
karna hi hai jaisa crawlers apne IP ranges permanently blocked karwate
hain, jo file ko pehle se respect karne se kaafi zyada expensive failure
hai — ek banned IP range silently ek poore major domain ko future crawls
se remove kar sakta hai। Crawler har domain ka `robots.txt` ek baar fetch
aur cache karta hai (Step 5 ka robots cache) har single page se pehle
re-fetch karne ki jagah, aur isse periodically re-validate karta hai
kyunki site owners apne rules change karte rehte hain।

### Scale pe Deduplication: Bloom Filters

10 billion+ known URLs pe, question "kya humne already yeh URL discover/
queue kiya hai" essentially har link pe answer karna padta hai jo parser
extract karta hai — yeh ek check hai jo fetch throughput times average
out-degree ke proportional rate pe hota hai (386 pages/sec × 30 links ≈
11,600 checks/sec average load pe, peak pe usse several times zyada)। Ek
plain hash set isko exactly answer karta hai, lekin real cost pe
(Step 2: ~600 GB+ poore URL set ke liye) — ek single node ki memory mein
comfortably rakhne ke liye bahut bada, aur consistently replicated/sharded
rakhna expensive।

Ek **Bloom filter** ek probabilistic set-membership structure hai: ek
fixed-size bit array plus several independent hash functions। Ek element
add karne ke liye, aap usse k baar hash karte ho aur un k bit positions
ko 1 set karte ho। Membership check karne ke liye, aap candidate ko same
k tareekon se hash karte ho aur check karte ho ki *saare* woh bits set
hain ya nahi — agar koi bhi 0 hai, element **definitely not** set mein
hai (kabhi false negatives nahi); agar sab 1 hain, element **probably**
set mein hai, lekin yeh ek **false positive** ho sakta hai (elements ka
ek different combination same bits set kar gaya ho)।

Yeh asymmetry exactly wahi trade-off hai jo URL dedup ke liye sahi hai:
ek **false negative** ka matlab hoga silently ek URL ko kabhi crawl na
karna jise system pehle se dekha hua sochta hai — ek real, permanent gap
coverage mein। Ek **false positive** ka matlab bas itna hai ki occasionally
ek URL skip ho jaaye jo actually naya tha — ek small, bounded, aur
statistically tunable amount of missed coverage (1% Step 2 ke sizing pe),
badle mein ek 50x memory reduction ke। Ek system mein 1% newly discovered
URLs miss karna jo waise bhi continuously most URLs ko multiple inbound
links se rediscover kar raha hai, ek cost hai jo pay karne layak hai
poora "seen" set fast memory mein resident rakhne ke liye ek much larger,
slower structure ke across spread karne ki jagah।

Practice mein, Bloom filter same domain-hash partitioning ke across
sharded hota hai jitni frontier (next section), taaki har partition apne
URL space ke slice ke liye frontier queue aur dedup filter dono own kare,
"kya yeh naya hai" check ko local aur fast rakhte hue, ek cross-cluster
round trip ki jagah।

**Do dedup layers, ek nahi**: URL-level dedup (Bloom filter, ek fetch
schedule hone se pehle hi check hota hai) answer karta hai "kya humne
yeh URL pehle discover kiya hai" — lekin yeh content ke bare mein kuch
nahi kehta। Ek different URL identical ya near-identical content serve
kar sakta hai (mirrors, URL parameters jo page change nahi karte,
syndicated articles jo verbatim republish hote hain)। Isliye
`content_hash` jo har fetch ke baad compute hoti hai (Step 2, Step 5)
ek second, independent dedup signal ke tor pe exist karti hai — fetch ke
*baad* check hoti hai, kyunki aap ek page ka content download kiye bina
jaan nahi sakte। Ek URL jo Bloom filter pass kar jaata hai (naya lagta
hai) lekin ek `content_hash` produce karta hai jo already metadata DB
mein exist karta hai, ek content duplicate ke tor pe flag ho jaata hai,
jo downstream indexer ke liye useful hai (same content ko do baar index
mat karo) chahe crawl khud ne uspe ek fetch spend kiya ho।

**Bloom filter ka time ke saath growth**: ek fixed-size Bloom filter ka
false-positive rate uske designed capacity se zyada elements add hone pe
badhta hai (zyada bits 1 set hote hain, collision odds badhte hain)।
Kyunki known URL space continuously badhta hai, filter ko projected
growth ke liye size karna padta hai (jaise, current 10 billion URLs ke
2-3x ke liye built) ya periodically ek larger size pe rebuild kiya jaata
hai — ek operational detail jo follow-up ke tor pe mention karne layak
hai yeh show karne ke liye ki Step 2 ka "12 GB" ek one-time, static
number nahi hai।

### Distributed Coordination aur Crawler Traps

**Frontier ko workers ke across partition karna**: dozens se hundreds
crawler workers ke saath, naively kisi bhi worker ko koi bhi URL fetch
karne dena politeness todta hai — do different workers dono decide kar
sakte hain ki `example.com` ko abhi fetch karna safe hai, ek doosre se
unaware। Standard fix hai URL space ko **domain ke hash se partition**
karna, taaki ek specific domain ki queue, uska politeness state
(`next_allowed_fetch_time`), aur uska `robots.txt` cache entry sab ek
specific frontier partition/owner pe live karein। Workers specific
partitions assign kiye jaate hain (ya dynamically pull karte hain), jo
matlab hai ki ek given domain ke saare URLs ek single point of
politeness enforcement se flow karte hain — koi cross-partition
coordination nahi chahiye "kya abhi is domain ko fetch karna safe hai"
answer karne ke liye। Yeh same domain-hash partitioning idea hai jo Bloom
filter shard ke liye upar use hui thi, jisse dono structures ek given
domain ke liye colocate ho sakein।

**Crawler traps**: kuch URL spaces construction se hi effectively
infinite hain — ek calendar page jiska "next month" link forever ek new,
technically-distinct URL generate karta hai; ek site jisme session IDs
har URL mein embedded hain (`?sessionid=...`) infinite unique-looking
URLs same content ke liye generate karta hai; ek e-commerce site pe
auto-generated faceted search/filter combinations billions of URL
permutations mein combine ho sakte hain। Agar unchecked chhod diya
jaaye, ek single aisa domain poora crawl budget indefinitely consume kar
sakta hai aur har doosre domain ko starve kar sakta hai। Mitigations,
politeness/frontier layer pe per domain apply kiye jaate hain:
- **Max crawl depth**: cap karo ki crawler ek seed se kitne link-hops
  deep follow karega ek domain ke andar further descent ko deprioritize
  karne se pehle।
- **Max URLs per domain per time window**: ek hard budget cap — ek baar
  ek domain apna allotted fetch budget period ke liye consume kar chuka
  ho, uski queue deprioritize ho jaati hai chahe uski queue mein aur
  kitne bhi URLs baaki ho।
- **URL pattern heuristics**: un URLs ko detect aur downrank karo jo ek
  already-crawled URL se sirf ek known-junk query parameter mein differ
  karte hain (session IDs, sort/filter permutations jo substantive
  content change nahi karte) — aksar content-hash comparison ke saath
  paired (Step 6, frontier section) taaki agar aisa URL ek baar fetch bhi
  ho jaaye, ek identical `content_hash` ek recently-crawled page se usse
  aage ke deeper traversal ko short-circuit kar de।

**Frontier prioritization signals ka summary**:

| Signal | What it captures | Effect on priority score |
|---|---|---|
| Domain authority | Inbound link count / PageRank-style score | Higher authority → crawled sooner, more often |
| Historical change frequency | How often `content_hash` differs across recrawls | Frequently-changing → shorter `next_crawl_at` interval |
| Discovery recency | How recently the URL was first found | Newly discovered → modest boost, to keep breadth moving |
| Per-domain budget remaining | Fetches already spent on this domain this period | Budget exhausted → deprioritized regardless of other signals |

## Step 7: Bottlenecks & Trade-offs

- **Frontier, raw fetch throughput nahi, real bottleneck hai।** Step 2 ne
  dikhaya ki target throughput ke liye sirf ~16-60 worker machines
  chahiye — actual scaling challenge hai 10 billion+ URLs ke frontier ko,
  correctly partitioned aur politeness-aware, itna fast rakhna ki har
  worker feed rahe bina per-domain limits violate kiye। Ek poorly
  partitioned frontier (jaise, full URL se hash karna domain se karne ki
  jagah) ek domain ka politeness state kaafi partitions ke across scatter
  kar dega aur rate-limit enforcement ko cross-partition coordination
  chahiye bana dega — exactly wahi jo domain hash se partitioning avoid
  karta hai।
- **Hot domains dominate karte hain।** Ek domain jiska millions pages hain
  (Wikipedia, ek major e-commerce catalog) ek single frontier partition
  banata hai jiska backlog kisi typical domain se enormously zyada hota
  hai, aur politeness cap karta hai ki us backlog ko kitni jaldi drain
  kiya ja sakta hai chahe kahin aur kitne bhi idle workers ho — yeh
  politeness ka ek inherent trade-off hai, engineer karke hataane wala
  bug nahi।
- **Storage bina bound ke badhta hai।** 125 TB/month compressed (Step 2)
  ka matlab hai storage cost, compute nahi, dominant long-run cost ban
  jaata hai; trade-off hai retention policy — older, unchanged crawls ko
  zyada aggressively compress kiya ja sakta hai ya colder/cheaper storage
  tiers pe move kiya ja sakta hai, agar zaroorat pade to slower re-access
  ki cost pe।
- **Bloom filter false positives ek permanent, accepted gap hain**, fix
  karne wala bug nahi — Bloom filter ko ek exact set ke upar choose karne
  ka poora point tha ek small, bounded miss rate ko ek 50x memory win ke
  liye trade karna; false-positive rate ko zero ki taraf drive karna
  matlab hoga woh memory savings wapas dena।
- **DNS resolution aur connection setup latency** per-fetch time pe
  actual download se kaafi zyada dominate karte hain small-to-medium
  pages ke liye — ek production crawler typically apna khud ka caching
  DNS resolver layer workers ke aage run karta hai har request pe public
  DNS hit karne ki jagah, jo upar core diagram mein nahi hai lekin is
  scale pe near-mandatory addition hai।
- **Freshness vs. coverage ek permanent dial hai, solved problem nahi** —
  fetch budget ki har unit jo ek already-known page recrawl karne mein
  spend hoti hai woh ek unit hai jo ek naya page discover karne mein
  spend nahi hoti, aur "right" balance shift hota hai is baat pe depend
  karke ki product goal maximum coverage hai (ek new search engine jo
  web ko pehli baar index karne ki koshish kar raha hai) ya maximum
  freshness (ek mature system jiska already broad coverage hai aur woh
  optimize kar raha hai kitna current uska index hai)।
- **Worker fleet size scale karna cheap hai, frontier correctness nahi।**
  Zyada crawler workers add karna (Step 2: 60 se 120 machines tak jaana)
  ek trivial horizontal scale-out hai; yeh ek poorly partitioned frontier
  ya ek under-provisioned dedup structure ko fix karne mein kuch nahi
  karta, yehi wajah hai ki interviewers jab "isko 10x kaise scale karoge"
  pooch rahe hote hain, woh really yeh puuch rahe hote hain ki candidate
  samajhta hai ki bottleneck move ho gaya hai, yeh nahi ki usse pata hai
  aur boxes add karne hain।
- **Ek single slow ya unresponsive domain ko poori fleet ko stall nahi
  karna chahiye** — kyunki workers specific domain partitions assign
  kiye jaate hain ya unse pull karte hain, ek domain jo respond karne
  mein slow hai (down nahi, bas latent), sirf un workers ko throttle
  karta hai jo abhi us partition ko serve kar rahe hain; politeness
  layer ka per-domain budget naturally bound karta hai ki koi ek slow
  domain fleet-wide capacity kitni consume kar sakta hai, lekin isko
  phir bhi per-fetch timeouts chahiye taaki ek single hung connection ek
  worker slot ko indefinitely tie up na kare।

**Bottleneck-to-mitigation summary**:

| Bottleneck | Mitigation | Cost accepted |
|---|---|---|
| Frontier partitioning/politeness coordination | Partition by domain hash, colocate politeness state | Uneven partition sizes for domains with very different page counts |
| Hot/huge domains dominate a partition | Per-domain fetch budget cap per time window | Slower full coverage of very large single domains |
| Unbounded storage growth | Compression + tiered/cold storage for old, unchanged crawls | Slower re-access of archived content |
| Bloom filter false positives | Accept ~1% miss rate | Small permanent gap in URL coverage |
| DNS/connect latency per fetch | Caching DNS resolver layer, connection pooling | Extra infrastructure component to operate |
| Crawler traps (infinite URL spaces) | Max depth, max URLs/domain, pattern heuristics | Occasionally deprioritizing legitimate deep content |

## Follow-up Questions jo Interviewer Puuch Sakta Hai

**Aap crawled pages ko importance se kaise rank karoge, sirf yeh decide
karne ki jagah ki aage kya crawl karna hai?**
Ek offline importance score compute karo (PageRank-style, ya ek simpler
inbound-link-count heuristic) link graph se jo crawl khud bana raha hai,
periodically ek batch job ke tor pe accumulated graph pe run karo, aur
resulting score ko frontier ki priority calculation mein wapas feed karo
(Step 6) — yeh loop close karta hai "crawl ne web ki structure ke bare
mein kya seekha hai" aur "aage kya crawl karna prioritize karna chahiye"
ke beech।

**Aap different URLs ke across near-duplicate content (mirrors,
syndicated articles) ka recrawl kaise detect aur avoid karoge?**
Ek content similarity signature compare karo (jaise, MinHash/SimHash of
the page body, exact hashing se cheaper jab near-identical-but-not-
byte-identical content common ho) previously seen signatures ke against;
agar ek strong match milta hai, new URL ko ek duplicate ke tor pe record
karo jo canonical crawled copy ki taraf point kare, content ko phir se
store aur re-index karne ki jagah, storage aur downstream indexing work
dono bacha kar।

**Aap isko JavaScript-heavy single-page applications crawl karne ke liye
kaise extend karoge jahan content client-side render hota hai?**
URLs ka ek subset (low extracted-content-to-HTML-size ratio se detect
kiya gaya, ya domain allowlisting se) ek headless-browser rendering tier
se route karo jo parser ko handoff karne se pehle JavaScript execute
karta hai — yeh per page kaafi zyada expensive hai (real CPU/memory
rendering ke liye, sirf ek network fetch nahi), isliye yeh selectively
apply kiya jaata hai, poore crawl pe nahi।

**Aap ek aisi site kaise handle karoge jo aapke crawler ke IP addresses
block karna shuru kar de ya CAPTCHAs serve kare?**
Ek domain se elevated 403/429 response rates ko us domain ka crawl rate
automatically back off karne ka signal maano (uske stated `Crawl-delay`
se aage), legitimate large-scale crawling ke liye IP ranges ke ek pool
ke across rotate karo (blocking ko maliciously evade karne ke liye nahi,
balki kyunki ek single IP is volume pe naturally abuse jaisa dikhta hai
chahe woh compliant hi kyun na ho), aur ek clear, identifiable
`User-Agent` string maintain karo contact info ke saath taaki site owners
sirf outright block karne ki jagah reach out kar sakein।

**Aap isko 10x current throughput tak kaise scale karoge?**
Frontier partitions aur worker capacity ko proportionally add karo (dono
near-linearly scale karte hain kyunki partitioning domain hash se hai),
lekin recognize karo ki ceiling infrastructure nahi hai — yeh distinct
domains ki number hai jo politeness constraints ke under parallelize
karne ke liye available hain; extreme throughput pe bottleneck shift ho
jaata hai enough breadth frontier mein hone ki taraf (enough distinct,
currently-eligible domains) taaki itne workers ko busy rakha ja sake bina
per-domain rate limits violate kiye।

**Iss design ko robots.txt se aage kaunse legal/ethical constraints shape
karne chahiye?**
Individual pages pe `noindex`/`nofollow` meta tags aur `X-Robots-Tag`
headers respect karo (domain-level `robots.txt` se finer-grained), bina
permission ke authentication ya explicitly paywalled content crawl
karne se bacho, aur crawl rate limits ko itna conservative rakho ki
crawler kabhi bhi kisi site ke total traffic ka meaningful fraction na
bane — yehi practical lines hain ek good-citizen crawler aur ek aise
crawler ke beech jo abuse complaints aur IP blocks generate karta hai।
