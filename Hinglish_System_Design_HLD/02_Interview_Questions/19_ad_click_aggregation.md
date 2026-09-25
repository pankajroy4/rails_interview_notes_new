# Design an Ad Click Aggregation System

## Problem Statement

"Design a system that ingests ad impression and click events from web and mobile
clients at massive scale, and aggregates them into per-ad, per-campaign counters —
both for near-real-time dashboards that advertisers watch, and for exact,
authoritative numbers that feed billing. Advertisers pay based on these numbers,
so undercounting loses revenue and overcounting is effectively charging someone
for clicks that didn't happen."

Ye question basically do cheezon ke baare mein hai: ek huge, bursty firehose of
small events ko handle karna, aur "fast and approximate" vs "slow but exact" ke
beech ki tension ko reconcile karna jab money on the line ho.

## Step 1: Clarify Requirements

**Functional Requirements**

- Bahut saare client sources se (web pixels, mobile SDKs, ad exchanges se
  server-to-server callbacks) ad click aur impression events ingest karna hai.
- Per ad, per campaign, per advertiser basis pe, configurable time windows
  (per-minute, per-hour, per-day) ke over counts aggregate karna hai.
- Advertisers ko near-real-time dashboards provide karne hain (e.g. "clicks in the
  last hour," jo ek-do minute ke andar update ho jaaye).
- Exact, authoritative daily (ya usse finer) totals produce karne hain jo
  advertiser billing drive karte hain.
- Raw click/impression counts ke saath-saath, per ad/campaign distinct-user counts
  (unique reach) bhi support karna hai.
- Obviously fraudulent ya duplicate clicks (bot traffic, double-fires) detect aur
  filter karna hai — kam se kam basic level pe.

**Non-Functional Requirements**

- Bursty peaks ke saath extremely high write throughput (e.g. ek popular
  livestream ya major sporting event se impression volume short window mein 10x
  spike ho sakta hai).
- Ingestion se at-least-once delivery acceptable/expected hai, lekin aggregation
  idempotent hona chahiye — redelivery pe koi double-counting nahi honi chahiye.
- Billing numbers exact hone chahiye — systematic over- ya under-counting ke liye
  zero tolerance hai, chahe dashboards thoda approximation error tolerate kar
  sakte hon.
- Near-real-time dashboard latency: results event occur hone ke roughly 1-2
  minute ke andar visible hone chahiye.
- Durability: raw events kabhi silently drop nahi hone chahiye durably record hone
  se pehle, kyunki wo baad mein exact reconciliation ke liye ek-matra source hain.
- Ingestion ke liye specifically high availability chahiye — thodi si aggregation
  outage tolerable hai, lekin ingestion down hone ki wajah se raw events lose ho
  jaana tolerable nahi hai.

## Step 2: Back-of-Envelope Estimation

**Assumptions**

- Ek large ad network jo per day 5 billion ad impressions serve karta hai, typical
  click-through rate 0.5% ke saath, jisse 25 million clicks/day banta hai.
- Traffic uniform nahi hai: maan lete hain peak hour mein average hourly rate ka
  3x traffic hota hai (evening/prime-time concentration), aur peak hour ke andar
  bhi, short bursts (e.g. koi viral moment) briefly 2-3x aur spike kar sakte hain.

**Impression event throughput**

- Average: 5,000,000,000 / 86,400 sec ≈ 58,000 impressions/sec average.
- Peak hour average: 58,000 x 3 ≈ 174,000 impressions/sec.
- Short-burst peak: 174,000 x 2.5 ≈ 435,000 impressions/sec — ye wo number hai
  jiske liye ingestion layer ko provision karna hoga taaki wo bina fail hue is
  load ko absorb kar sake, chahe ye sustained rate na ho.

**Click event throughput**

- 25,000,000 / 86,400 ≈ 290 clicks/sec average, jo peak pe roughly 290 x 3 x 2.5
  ≈ 2,175 clicks/sec ho jaata hai. Clicks, impressions se do orders of magnitude
  kam volume mein hote hain, jo matter karta hai: iska matlab hai ki click-specific
  processing (e.g. zyada careful fraud checks) per-event impression processing se
  zyada expensive afford kar sakti hai.

**Event size and bandwidth**

- Har event (ad_id, campaign_id, user_id/device_id, timestamp, event_type, geo/
  device jaisa metadata) roughly 200-300 bytes mein serialize hota hai; isko 250
  bytes maan lete hain.
- Peak impression bandwidth: 435,000 events/sec x 250 bytes ≈ 109 MB/sec ≈ 872
  Mbps sustained during burst — ye meaningful hai lekin properly partitioned
  Kafka cluster aur modern networking ke andar aaram se handle ho jaata hai.

**Storage**

- Daily raw event volume: 5.025 billion events/day x 250 bytes ≈ 1.26 TB/day of
  raw event data.
- Raw events ke liye 1-year retention window ke over (jo exact
  reprocessing/audits ke liye zaroori hai): 1.26 TB x 365 ≈ 460 TB. Ye tiering ka
  justification hai: raw events ko cheap, compressed, append-only storage (e.g.
  object storage / data lake) mein rakho, hot aggregation database mein nahi.
- Aggregated counters bahut chhote hote hain: maan lete hain per day 10 million
  distinct (ad, hour) buckets x ~100 bytes per counter row ≈ 1 GB/day of aggregate
  data — ise years tak fast-access store mein rakhna trivial hai.

**Aggregation processing throughput**

- Stream processing layer ko peak pe ~435,000 events/sec sustain karna hoga. Agar
  single stream-processing task roughly 20,000-50,000 simple counter-increment
  events/sec handle kar sakta hai, to iska matlab hai peak pe 10-20 parallel
  partitions/consumer tasks chahiye honge, jo ki Kafka-consumer-group-based stream
  processor ke liye ek achievable scale-out factor hai.

**Kafka cluster sizing**

- ~250 bytes each ke saath 435,000 events/sec sustain karne ke liye (≈109 MB/sec)
  headroom ke saath, aur assume karte hue ki single Kafka broker comfortably
  20-30 MB/sec ka sustained produce+replicate traffic handle kar leta hai before
  becoming a bottleneck, iska matlab hai sirf raw ingest throughput ke liye
  roughly 5-8 brokers chahiye; practically, teams isse meaningfully zyada
  provision karte hain (kuch dozen brokers) taaki parallelism ke liye
  partition-count headroom mile, durability ke liye replication factor 3 (jo
  roughly effective write bandwidth ko triple kar deta hai), aur periodic burst
  multiplier ke liye room ho. Ye ek useful sanity check hai ki "durable log in
  front of aggregation" free abstraction nahi hai — iska apna real infrastructure
  footprint hai, bas ye ek stateful aggregation database ke comparison mein
  horizontally scale karna kahin zyada aasan hai.
- Partition count sirf current peak ke liye nahi, future growth ke liye bhi
  provision karna chahiye — Kafka topic ko under-partition karna baad mein fix
  karna expensive hota hai (existing topics ko repartition karna disruptive hota
  hai), isliye current peak partition-consumer parallelism ke 3-5x ke liye sized
  topic ek reasonable starting point hai.

## Step 3: High-Level Design

Core components:

- **Ad servers / SDKs**: raw click/impression events emit karte hain,
  fire-and-forget tareeke se (local retry/buffering ke saath) ingestion endpoint
  ki taraf.
- **Ingestion API (thin, stateless)**: events ko validate aur minimally enrich
  karta hai (e.g. server-side timestamp attach karta hai, basic bot-signature
  filtering karta hai), phir unhe ek durable log mein likhta hai.
- **Durable event log (Kafka)**: shock absorber — bursty firehose ko buffer karta
  hai taaki downstream ko instantaneous peak ke liye provision na karna pade;
  exact reprocessing ke liye replayable source of truth bhi hai.
- **Stream aggregation layer**: log consume karta hai, windowed counters
  maintain karta hai (per ad/campaign tumbling windows), idempotency ke liye
  deduplication apply karta hai, aur rolling aggregates ko dashboards ke liye fast-
  access store mein likhta hai. Jahan exactness required nahi hai wahan
  approximate structures (HyperLogLog, Count-Min Sketch) use karta hai.
- **Fast aggregate store**: near-real-time dashboard queries serve karta hai (e.g.
  ek key-value ya time-series store, incrementally updated).
- **Raw event data lake**: wahi events, cheap columnar/object store mein durably
  archived, time ke basis pe partitioned.
- **Batch reconciliation job**: data lake mein raw event log ke over ek nightly
  (ya kisi aur periodic cadence) exact batch computation, jo billing ke liye use
  hone waale authoritative counts produce karta hai.
- **Billing store**: har advertiser ke har billing period ke exact, immutable,
  audit-friendly ledger of billable events.

```text
 Ad Servers / SDKs (web pixels, mobile, exchange callbacks)
        |
        v
 +-------------------+
 |  Ingestion API      |  (stateless, validate + light enrich)
 +---------+-----------+
           |
           v
 +----------------------------+
 |   Kafka (durable event log)  |   <-- shock absorber for bursty firehose
 |   partitioned by ad_id hash  |
 +------+----------------+------+
        |                |
        v                v
+---------------+   +--------------------------+
| Stream         |   |  Raw Event Data Lake      |
| Aggregation    |   |  (S3-like, partitioned     |
| (windowed,      |   |   by day/hour, cheap,      |
|  dedup, HLL/CMS) |   |   long retention)          |
+-------+--------+   +-------------+--------------+
        |                            |
        v                            v
 +-----------------+       +--------------------------+
 |  Fast Aggregate  |       |  Nightly Batch            |
 |  Store           |       |  Reconciliation Job        |
 |  (dashboards,    |       |  (exact counts, dedup       |
 |   near-real-time)|       |   against raw log)          |
 +-----------------+       +-------------+--------------+
                                          |
                                          v
                                +--------------------+
                                |  Billing Store       |
                                |  (authoritative,      |
                                |   immutable ledger)   |
                                +--------------------+
```

## Step 4: API Design

**Record an ad event (called from SDK/pixel, extremely high volume — must be
cheap)**
```
POST /events/track
{
  "eventId": "uuid-generated-client-side",   // used for idempotency/dedup downstream
  "adId": "ad_88213",
  "campaignId": "camp_4471",
  "eventType": "click" | "impression",
  "userId": "device_hash_or_user_id",
  "clientTimestamp": 1732000000123,
  "metadata": { "geo": "US-CA", "device": "mobile", "placement": "feed" }
}
-> 202 Accepted   // fire-and-forget; do not block the ad-serving critical path on this
```

**Query near-real-time aggregate (dashboard-facing)**
```
GET /stats/realtime?adId=ad_88213&window=1h
<- { adId: "ad_88213", windowStart: "...", clicks: 4820, impressions: 962000,
     estimatedUniqueUsers: 391000 }   // note: "estimated" — approximate structures
```

**Query exact billing totals**
```
GET /stats/billing?campaignId=camp_4471&date=2026-09-01
<- { campaignId: "camp_4471", date: "2026-09-01",
     exactClicks: 118422, exactImpressions: 23684000, status: "finalized" }
```

**Trigger/inspect reconciliation job status (internal/ops)**
```
GET /internal/reconciliation/status?date=2026-09-01
<- { date: "2026-09-01", status: "completed", discrepancyVsRealtime: "+0.3%" }
```

## Step 5: Data Model

**Raw event log (Kafka topic, then archived to data lake)**: ye traditional
database nahi hai — ek append-only, partitioned log hai. Partition key typically
`ad_id` ya `campaign_id` hash hota hai, taaki kisi bhi ad ke saare events same
partition pe land karein, jo windowed aggregation ke dauran per-ad ordering
maintain karne ke liye matter karta hai.

```
ad_events (Kafka topic, partitioned by hash(ad_id))
  eventId          string   -- client-generated, used for dedup
  adId             string
  campaignId       string
  eventType        enum(click, impression)
  userId           string
  clientTimestamp  int64
  serverTimestamp  int64    -- set at ingestion, used for watermarking
  metadata         json
```

**Fast aggregate store (dashboards)**: ek key-value ya wide-column store jo fast
incrementing counters aur time window ke over range reads ke liye optimized hai —
e.g. sabse recent, hottest windows ke liye Redis (jise older windows ke liye
Cassandra jaisi wide-column store ke saath backed/rolled kiya jaata hai jo abhi
bhi dashboards pe chahiye hote hain). Ye achhi tarah map hota hai kyunki access
almost hamesha "iss counter ko increment karo" ya "iss key ke counters ko iss time
range ke over read karo" hota hai, relational joins nahi.

```
realtime_counters  (key: adId + windowStart, e.g. "ad_88213:2026-09-01T14:32")
  clicks            int
  impressions       int
  hll_sketch        bytes   -- HyperLogLog register set for unique-user estimate
  cms_sketch        bytes   -- Count-Min Sketch for frequency estimation (optional, per use case)
```

**Billing store (authoritative)**: ek relational database, kyunki billing ke liye
strong consistency, transactional guarantees, exact numeric correctness, aur
auditability (row-level history, no silent overwrite) chahiye hoti hai —
properties jinke liye relational engines banaye gaye hain, aur yahan volume
(campaign per day ke hisaab se aggregated) raw events se orders of magnitude kam
hai, isliye usual "relational is scale ko handle nahi kar sakta" objection apply
nahi hota.

```
billing_ledger
  campaign_id    string
  billing_date   date
  exact_clicks   bigint
  exact_impressions bigint
  computed_at    timestamp
  status         enum(pending, finalized, disputed)
  PRIMARY KEY (campaign_id, billing_date)
```

## Step 6: Deep Dive

### Kyun ek durable message log aggregation ke aage baitha hota hai

Agar ad servers directly click/impression events aggregation database mein
likhte (counters ko synchronously increment karte), to aggregation database ka
write throughput hamesha absolute peak burst rate (hamare estimate mein 435,000
events/sec) ke liye provision karna padta, aur us database mein koi bhi transient
slowdown (compaction, failover, hot partition) turant back-pressure banake poore
system se hote hue ad-serving path tak pahunch jaata — jo poore system mein wo
ek path hai jise kabhi slow nahi hona chahiye, kyunki ad serving hi actual
revenue-generating user-facing product hai. Beech mein Kafka rakhne se in
concerns ko completely decouple kar diya jaata hai: ingestion API ka sirf ek kaam
hota hai — event ko jitni fast ho sake log mein durably append karna (ek
operation jise Kafka partitioning ke through extremely cheap aur horizontally
scalable banane ke liye banaya gaya hai), aur wo success return kar deta hai jaise
hi write durable ho jaaye, chahe downstream aggregation kitni bhi fast ya slow
chal rahi ho. Agar burst ke dauran aggregation layer peeche reh jaata hai, to
events simply Kafka mein queue ho jaate hain (jo disk pe cheaply large backlogs
buffer karne ke liye design kiya gaya hai) aur burst subside hone ke baad
aggregation catch up kar leta hai — kuch bhi lose nahi hota, aur burst kabhi
wapas propagate hoke ad serving ya ingestion latency ko affect nahi karta. Ye
bilkul wahi shock-absorber role hai jo bursty firehoses ke liye
`10_message_queues_and_streaming.md` mein generally describe kiya gaya hai, yahan
specifically click/impression events pe apply kiya gaya hai.

### Tumbling windows ke saath stream aggregation aur late-arriving-data problem

Stream aggregation layer events ko fixed, non-overlapping tumbling windows mein
group karta hai — e.g. "ad X ke saare clicks count karo jinka timestamp 14:32:00
aur 14:33:00 ke beech hai." Ek naive implementation ek window ko aggregate karega
aur usi instant "final" consider kar lega jab wall-clock time window ke end ko
paar kar jaaye (e.g. 14:32-14:33 window ko 14:33:00 pe done treat kar lega).
Problem ye hai ki events hamesha usi order mein aggregator ke paas nahi pahunchte
jis order mein wo logically hue: ek mobile client several clicks locally batch
kar sakta hai aur slow network pe unhe minutes baad flush kar sakta hai, ya ek
network hiccup impression events ke ek batch ko delay kar sakta hai; *event ka
apna timestamp* 14:32 window ke andar aa sakta hai chahe wo physically
aggregator tak 14:36 pe hi pahunche. Agar window already 14:33 pe finalize aur
flush ho chuki hai, to ye late event ya to drop ho jaata hai ya galat tareeke se
jo bhi window currently open hai usme count ho jaata hai — dono cases mein,
14:32 window ka count galat ho jaata hai, aur chunki ye numbers eventually
billing mein roll up ho jaate hain, "galat" hone ka yahan seedha dollar cost hai.

Standard mitigation ek **watermark** hai (equivalently, ek grace period): window
ke wall-clock end paar hote hi usse finalize karne ke bajaye, aggregator window
ke nominal end ke baad ek additional buffer wait karta hai — e.g. 5 minutes —
usse closed treat karke downstream flush karne se pehle. Us grace period ke andar
aane waala koi bhi event, chahe wo "late" ho, phir bhi finalization se pehle uske
proper window mein correctly fold ho jaata hai. Ye explicitly thodi si dashboard
latency (results 5 minutes baad available hote hain jitna otherwise hote) ko
trade karta hai materially better correctness ke liye. Jo events watermark allow
karne se bhi zyada late aate hain, wo ya to real-time path se drop kar diye
jaate hain (acceptable hai, kyunki real-time path explicitly approximate hai) ya
specially handle kiye jaate hain, lekin critically, wo raw event log se lost
NAHI hote — wo wahan durably record hote hain aur exact batch reconciliation job
dwara correctly include kiye jaayenge, jisko watermark problem bilkul nahi hota
kyunki wo complete historical log ke over well after the fact operate karta hai.

**Ek worked timeline, isse concrete banane ke liye.** Ad X ke 14:32:00-14:33:00
tumbling window ko consider karein, 5-minute watermark ke saath:

- 14:32:07 — `clientTimestamp` 14:32:07 waala ek click event aggregator ke paas
  14:32:07 pe hi pahunch jaata hai (normal case, koi delay nahi). Turant open
  window mein count ho jaata hai.
- 14:32:51 — ek mobile client click generate karne ke turant baad ek network
  dead zone mein chala jaata hai jiska `clientTimestamp` 14:32:51 hai; SDK usse
  locally buffer kar leta hai.
- 14:33:00 — wall clock window ke nominal end ko paar kar jaata hai. Naive
  (no-watermark) design ke under, window yahan close ho jaata. Is design ke
  under, wo open rehta hai, aur aage kisi bhi arrival ko accumulate karta rehta
  hai, kyunki watermark abhi elapse nahi hua hai.
- 14:34:40 — mobile client ko connectivity wapas milti hai aur wo apna buffered
  click flush karta hai. Ye ab aggregator ke paas pahunchta hai, window ke
  nominal end ke 1 minute 49 seconds baad, lekin 5-minute watermark ke andar hi —
  aggregator recognize karta hai ki iska `clientTimestamp` 14:32-14:33 window ke
  andar aata hai aur ise correctly fold kar deta hai.
- 14:38:00 — 14:32-14:33 window ka watermark elapse ho jaata hai (14:33:00 ke 5
  minute baad). Window ab finalize hoke fast aggregate store mein flush ho jaata
  hai, jisme 14:34:40 waala delayed click correctly include hai. Is window ke
  liye jo bhi event 14:38:00 ke baad `clientTimestamp` ke saath aata hai, wo ya to
  real-time counter se drop kar diya jaata hai (acceptable — fast path explicitly
  approximate hai) ya monitoring purposes ke liye "very late" metric ki tarah
  logged kar diya jaata hai; raw event log mein ye untouched rehta hai aur next
  batch reconciliation run dwara exactly count ho jaayega.

Ye walkthrough ye bhi batata hai ki har event pe `serverTimestamp` (ingestion pe
set hota hai) aur `clientTimestamp` (jab event actually hua tab set hota hai) dono
kyun store kiye jaate hain: windowing aur correctness logic `clientTimestamp` pe
operate karti hai (jab click genuinely occur hua), jabki `serverTimestamp` se
system measure aur monitor kar paata hai ki practically kitni lateness ho rahi
hai, jo aage jaake operator ko watermark duration khud tune karne mein help
karta hai.

### At-least-once delivery ke under idempotency aur deduplication

Kafka (jaise most durable messaging systems) default se at-least-once delivery
guarantee karta hai: certain failure/retry scenarios ke under (ek consumer
process karne ke baad lekin apna offset commit karne se pehle crash ho jaaye, ek
producer ek write retry karta hai jiske success hone ka usse yakeen nahi tha),
same event ek se zyada baar deliver aur process ho sakta hai. Agar aggregation
counters simply har received event pe increment kiye jaate hain, to ek
redelivered click event do baar count ho jaayega — jo directly click count ko
inflate kar dega jispe ad billing based hai. Chunki iss system ke numbers seedha
paise mein translate hote hain jo advertisers se charge kiye jaate hain,
double-counting sirf ek cosmetic bug nahi hai, ye effectively customer ko
overbill karna hai, jiske real business aur trust consequences hote hain.

Fix ye hai ki aggregation ko ek unique event ID pe deduplication ke through
idempotent banaya jaaye: har event ek client-generated `eventId` carry karta hai
(ek UUID jo event create hote hi ek baar generate hota hai, kisi bhi retry se
pehle), aur aggregation layer track karta hai ki kaunse event IDs kisi relevant
time window ke andar already count ho chuke hain (e.g. eventId ke basis pe keyed
ek set ya bloom-filter-backed dedup cache, jiska TTL isse match karta hai ki
redelivery plausibly kitni der tak ho sakti hai — typically minutes, consumer
retry/rebalance behavior se bounded). Jab koi redelivered event ek already-seen
eventId ke saath aata hai, to usse recognize karke skip kar diya jaata hai
double-count karne ke bajaye. Exact batch reconciliation job bhi same
deduplication perform karta hai, lekin zyada rigorously aur exhaustively, kyunki
wo complete raw log ko leisure mein process karta hai, real-time pressure ke
under nahi — isi wajah se ise billing ke liye authoritative source ki tarah
trust kiya jaata hai chahe real-time path ka dedup cache theoretically kisi edge
case ko miss kar sake (e.g. dedup cache ka TTL expire hone ke baad ek redelivery
aana).

### Approximate counting structures: HyperLogLog aur Count-Min Sketch

Ye system jitne bhi numbers produce karta hai, unme se har ek exact hona zaroori
nahi hai, aur ye pehchaanna ki kaunse nahi hain, wahi cheez hai jo real-time
path ko iss scale pe affordable banati hai.

**HyperLogLog (HLL)** cardinality estimation solve karta hai — "kitne *distinct*
users ne ye ad dekhi" (unique reach), raw impression count ke bajaye. Ise exactly
compute karne ke liye har ad ke liye dekhe gaye har unique user ID ka ek set
track karna padega, jo billions events/day pe naively karne se popular ad ke liye
gigabytes memory le sakta hai (ek hash set distinct elements ki number ke saath
linearly scale karta hai). HLL iske bajaye registers ka ek chhota, fixed-size
array maintain karta hai (typically kuch KB, chahe true cardinality thousand ho
ya billion) jo hashed inputs pe bit-pattern statistics ke through distinct
elements ki count probabilistically estimate karta hai, ek well-understood,
bounded standard error ke saath (typically common configurations mein 2% se
kam). Memory savings — fixed KB-scale structures jo memory ke saath grow nahi
hote jaisa true cardinality ke saath hota — yahi hai jo millions ads ke liye
simultaneously, per time window, ek live unique-reach estimate maintain karna
feasible banata hai.

**Count-Min Sketch (CMS)** frequency estimation solve karta hai — e.g. "roughly
kitni baar ek specific user ne ek specific ad click ki hai" (ek fraud/abuse
signal ki tarah useful — koi user ek minute mein same ad ko sau baar click kare
to suspicious hai) — ek small fixed-size grid of counters use karke jo per event
multiple hash functions ke through update hota hai, ek baar phir se over-counting
ke ek small, bounded amount of error ko exact per-(user, ad) frequency pairs
track karne ke against large space savings ke liye trade karta hai, jinki number
enormous combinatorially ho sakti hai.

**Explicit line**: dono structures *real-time dashboard aur internal
fraud-signal* path ke liye appropriate hain, jahan couple percent ka estimation
error, constant, tiny memory footprint aur speed ke liye ek acceptable trade
hai. Advertiser billing mein actually use hone waale numbers ke liye dono
acceptable nahi hain — ek advertiser ko probabilistically-estimated count ke
basis pe charge karna, chahe expected error chhota ho, defensible nahi hai, dono
practically (advertisers apne bills audit karte hain) aur often contractually.
Billing exact counts se compute honi chahiye, jo exactly wahi hai jiske liye
batch reconciliation path hai (complete raw log ke over operate karta hai, koi
space constraint na hote hue rigorous exact deduplicated counting karta hai
kyunki wo real-time streaming job ki tarah nahi chal raha).

### Two-speed Lambda architecture

Upar diye gaye pieces ko jodne se ek deliberate two-path design banta hai jise
commonly Lambda architecture kaha jaata hai: ek **fast/approximate path** —
tumbling windows, watermarks, aur approximate structures ke saath stream
aggregation — jo un dashboards ko power karta hai jinhe advertisers pure din
check karte hain, jahan low latency ko perfect precision se zyada value diya
jaata hai; aur ek **slow/exact path** — ek batch job (e.g. nightly) jo data lake
se complete, immutable raw event log ko reprocess karta hai, bina kisi time
pressure ke rigorous exact deduplication aur counting perform karta hai, aur
wo numbers produce karta hai jo actually invoices pe appear karte hain. Ye split
isliye exist karta hai, na ki real-time path ko khud perfectly exact banane ki
koshish ki jaaye, kyunki exactness aur real-time speed yahan genuinely tension
mein hain: exact counting ke liye itna wait karna padega taaki confirm ho sake
koi late/duplicate events outstanding nahi hain (jo low latency ke against
conflict karta hai) aur/ya exact distinct-count tracking ke liye unbounded
memory chahiye (jo constant-time, constant-memory processing ke against
conflict karta hai jo iss event rate pe real-time streaming ke liye required
hai). Dono goals ko simultaneously compromise karne ke bajaye, design unhe
cleanly separate kar deta hai: fast path purely latency ke liye optimize karta
hai aur small, bounded error accept karta hai; slow path purely correctness ke
liye optimize karta hai aur hours mein measured latency accept karta hai. Dono
ke beech reconciliation (upar diye status API mein `discrepancyVsRealtime`
figure) khud ek useful operational signal hai — real-time estimate aur exact
batch number ke beech ek persistently large gap batata hai ki upstream kahin
kuch galat hai (e.g. ek dedup TTL misconfigured, ya watermark bahut chhota set
hua), chahe batch number hi actually bill kiya jaata hai, real-time waala nahi.

### Window granularity apne aap mein ek trade-off hai

Tumbling window size (ek minute vs ek hour vs ek din) choose karna watermark se
alag ek separate dial hai, aur explicitly mention karne layak hai kyunki ye
alag direction mein trade-off karta hai. Ek fine-grained window (per-minute)
advertisers ko zyada responsive-feeling dashboard deta hai (wo ek spike ko hone
ke couple minutes ke andar dekh sakte hain) lekin fast aggregate store ko
maintain karne waale distinct counter keys ki number ko multiply kar deta hai —
Step 2 ke estimate ke hisaab se, hourly se per-minute buckets pe move karne se
live (ad, window) counter rows ki number roughly 60x badh jaati hai, jo fast
aggregate store pe write load aur storage churn ko directly badha deta hai. Ek
coarser window (hourly) maintain karna cheap hai aur campaign performance ki
reasonably useful picture bhi deta hai, lekin click volume mein sudden change
kitni jaldi visible hota hai usme delay karta hai. Kai real systems ise multiple
granularities simultaneously maintain karke resolve karte hain — short recent
retention period ke liye fine-grained windows (e.g. pichhle kuch hours ke liye
per-minute counters, live monitoring aur budget pacing ke liye useful), longer
retention ke liye coarser windows mein roll up karna (last month ke liye hourly,
usse aage daily) — jo responsiveness aur long-term storage efficiency donon ka
best pane ke liye thodi extra rollup/compaction complexity trade karta hai.

## Step 7: Bottlenecks & Trade-offs

- **Ek single hot ad ya campaign ek skewed Kafka partition create kar sakta
  hai**: agar partitioning `ad_id` hash se ho rahi hai, ek viral ad events ka ek
  disproportionate share ek partition pe concentrate kar sakta hai, jisse ek hot
  spot ban jaata hai jo us ad ki aggregation throughput ko limit karta hai chahe
  cluster overall ke paas capacity ho. Mitigation: bahut hot keys ko
  sub-partition karo (e.g. highest-volume ads ke liye ek random shard suffix
  append karo aur unke sub-aggregates ko downstream merge karo), added
  aggregation complexity ki cost pe.
- **Watermark/grace-period length ek direct latency-vs-completeness dial
  hai**: ek longer grace period zyada late events ko correctly catch karta hai
  lekin ye delay kar deta hai ki dashboards kab ek window ke "final-ish" numbers
  dikhaate hain; ek shorter grace period numbers jaldi dikhata hai lekin fast
  path mein late arrivals ko undercount karne ke higher risk ke saath (jo fine
  hai, kyunki fast path explicitly approximate hai — lekin bahut aggressive
  setting dashboard ko eventual billed number ke relative noticeably aur
  confusingly inaccurate bana deti hai).
- **Dedup cache size/TTL fast path mein ek memory-vs-correctness trade-off
  hai**: bahut short TTL genuinely delayed redeliveries ko double-count karne ka
  risk badhata hai; bahut long TTL event IDs ke very high-cardinality stream ke
  across zyada memory le leta hai. Poore log ke over batch path ka exhaustive
  dedup hi ultimately guard karta hai ki koi bhi fast-path dedup miss billing
  tak na pahunche.
- **Batch reconciliation job ka runtime raw event volume ke saath grow karta
  hai**, aur ek point pe purely nightly cadence un advertisers ke liye kaafi
  frequent nahi ho sakta jo same-day finalized billing visibility chahte hain —
  trade-off batch job frequency/cost (more frequent runs data lake ke against
  zyada compute aur I/O cost karte hain) aur "final" numbers kitni jaldi
  available hote hain, iske beech hai.
- **Raw events ke pure saal ke liye data lake storage cost (Step 2 ke hisaab se
  hundreds of terabytes) nontrivial hai** — ise compression se aur iss fact se
  mitigate kiya jaata hai ki ye cold, rarely-accessed-in-bulk storage hai (sirf
  batch job aur occasional audits/disputes ise touch karte hain), jo hot
  database storage ke bajaye cheap object storage tiers ke liye ek achha fit
  hai.

## Follow-up Questions an Interviewer Might Ask

**Aap click fraud (bots, click farms) kaise detect karoge?** Ingestion/stream-
aggregation path ko fraud-signal features se extend karo — velocity checks
(short windows ke over per user/IP Count-Min-Sketch-estimated click frequency),
device/browser fingerprint anomalies, known bot IP-range filtering — aur
suspicious events ko billing counts se exclude karne ke liye flag karo ya to
automatically (high-confidence fraud signals ke liye) ya ek review queue ke
through, jabki audit purposes ke liye raw events ko data lake mein unfiltered
retain karte hue.

**Aap ek late correction kaise handle karoge — e.g. billing finalize hone ke
baad ye discover karna ki kuch clicks fraudulent thay?** Billing ledger ko har
period ke liye append-only/immutable treat karo mutable ke bajaye: history
rewrite karne ke bajaye original finalized period ko reference karte hue ek
correcting adjustment entry (ek credit) issue karo, jo ek clean audit trail
preserve karta hai — wahi principle jo event-sourced systems generally use karte
hain.

**Aap isse real-time budget pacing support karne ke liye kaise extend karoge
(daily budget spend hone ke baad automatically ek ad campaign pause karna)?**
Isko dashboards se kahin zyada lower end-to-end latency guarantee chahiye
(seconds, couple minutes nahi) kyunki overspend continuously accrue hota hai;
typically ek separate, tighter-loop spend-tracking path se handle kiya jaata hai
jo same event stream use karta hai lekin wider error tolerance ke saath speed ko
prioritize karta hai (thoda early/conservatively pause karna overspend se behtar
hai), jo billing-accuracy path se distinct hai.

**Ad volume 10x badhne pe aap stream aggregation layer ko kaise scale
karoge?** Kafka topic partition count aur aggregation consumer-group
parallelism ko proportionally badhao (design already ad_id se horizontally
partitioned hai, isliye ye mostly matlab hai zyada partitions aur consumer
instances add karna), jabki above bottleneck ke hisaab se higher scale pe hot-
key skew ke zyada pronounced hone ko dekhte rehna.

**Real-time path ko itna wait karke aur exact data structures use karke exact
kyun nahi bana dete?** Tension ko directly push karo: exact unique-count
tracking ke liye memory true cardinality ke proportional chahiye (HLL ke fixed
footprint ke unlike), aur itna wait karna ki fully sure ho jaao ki koi late/
duplicate events nahi aayenge, ye directly "near-real-time" latency requirement
ke against conflict karta hai — effectively tum batch path hi rebuild kar rahe
hoge, bas usse poorly, tighter latency constraints ke saath jinhe wo meet nahi
kar sakta.

**Ek advertiser apne bill pe jo discrepancy dispute kare use aap kaise
reconcile karoge?** Chunki raw event log retained aur immutable hai, ek dispute
ko specific disputed date/campaign ke raw events ke over exact batch
computation ko ek audit ki tarah re-run karke resolve kiya ja sakta hai, aur
chunki har event ek durable `eventId` aur full metadata carry karta hai,
individual events ko sirf ek aggregate number pe trust karne ke bajaye directly
inspect kiya ja sakta hai.
