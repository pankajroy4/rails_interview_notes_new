# Design a Video Streaming Platform

## Problem Statement

"Design a video streaming platform jaise YouTube ya Netflix. Users videos upload kar
sakte hain, aur dusre users unhe watch kar sakte hain. Playback viewer ke network
conditions ke hisaab se adapt hona chahiye, video jaldi start hona chahiye, aur
popular content ko massive concurrent viewership ke neeche bhi smoothly stream hona
chahiye. Assume karo ki worldwide hundreds of millions users hain."

## Step 1: Clarify Requirements

### Functional Requirements

- Users ek video file upload kar sakte hain; platform use streamable form mein
  process karta hai.
- Users ek video watch kar sakte hain, aur playback quality unke current network speed
  ke hisaab se adapt hoti hai, fixed nahi hoti.
- Basic metadata dikhaya aur browse kiya ja sakta hai: title, description, uploader,
  duration, view count, likes.
- Users videos search kar sakte hain (yahan deep dive se out of scope, sirf note karte
  hain ki yeh `../01_Concepts/13_search_and_indexing.md` ka pattern reuse karta hai).
- Recommendations/"up next" product level par exist karte hain lekin explicitly core
  design se scope out kiye gaye hain (Step 6.4) — yeh ek separate ML system hai.

### Non-Functional Requirements

- **Fast start time**: video ko play dabane ke roughly 1-2 seconds ke andar start ho
  jaana chahiye — yeh real video platforms mein sabse heavily optimized metrics mein se
  ek hai, kyunki start-up latency ka har additional second measurably abandonment
  badhata hai.
- **Varying/poor network conditions ke neeche smooth playback**: player ko gracefully
  degrade karna chahiye (lower resolution) buffer aur stall karne ki jagah, aur network
  improve hone par quality recover karni chahiye.
- **Massive read amplification**: ek single popular video millions baar watch hota hai;
  system ko "write once, read many millions of times" ke around architect kiya jaana
  chahiye, jo almost ideal CDN use case hai.
- **Asynchronous, non-blocking uploads**: upload response ko poori processing
  (transcoding) complete hone ka wait nahi karna chahiye — yeh ek long video ke liye
  minutes le sakta hai.
- **Global low-latency delivery**: viewers worldwide distributed hain, aur video
  bandwidth-heavy hai, jisse content tak physical distance dominant latency factor ban
  jaata hai agar address na kiya jaye.
- **Playback ke liye strict consistency se zyada high availability** — metadata ke
  liye — ek thoda stale view count theek hai; ek video jo play na ho, woh theek nahi
  hai.
- **Scale par storage cost efficiency**: video poore system mein sabse bada storage
  cost driver hai ek wide margin se (Step 2), isliye storage tiering aur popularity-aware
  caching yahan zyadatar systems se zyada matter karte hain.

## Step 2: Back-of-Envelope Estimation

**Assumptions:**

- 200 million daily active users (DAU).
- Har DAU average 5 videos/din watch karta hai (view events).
- Platform-wide har minute 500 hours ka naya video content upload hota hai (yeh real
  order of magnitude hai jo YouTube ne historically cite kiya hai, aur ek useful anchor
  figure hai).
- Original uploaded video average roughly 1 GB per hour footage ka hota hai reasonable
  source bitrate par (~2.2 Mbps average resolutions/content types ke across — ek
  simplification, lekin order-of-magnitude estimation ke liye kaafi accha hai).
- Har uploaded video 5 renditions mein transcode hota hai (e.g., 1080p, 720p, 480p,
  360p, 240p) jinka *combined* storage footprint roughly original source size ka 1.5x
  hai (lower renditions kaafi chhote hote hain, aur renditions ke liye use hone wale
  modern codecs typical source upload se zyada efficient hote hain, isliye sabhi 5 ka
  sum storage ko 5x multiply nahi karta).
- Peak traffic (viewing) daily average se ~3x chalta hai.

**Upload volume and storage**

```
Video uploaded/day = 500 hours/min x 60 min/hour x 24 hours/day
                    = 500 x 1,440 = 720,000 hours of video/day

Raw source storage/day = 720,000 hours x 1 GB/hour = 720,000 GB = 720 TB/day

Transcoded (all renditions) storage/day = 720 TB x 1.5 ≈ 1,080 TB ≈ 1.08 PB/day

Total storage added per day (source + renditions) ≈ 720 TB + 1,080 TB ≈ 1.8 PB/day

Yearly storage growth (raw) ≈ 1.8 PB x 365 ≈ 657 PB/year
Replication/durability overhead (~1.5x, kyunki S3 jaise object storage systems already
internally redundancy handle karte hain ek naive 3x replica count se lower overhead
par) ke saath ≈ ~985 PB/year — roughly 1 exabyte/year.
```

Yeh number intentionally bahut bada hai — yahi wajah hai video platforms planet ke
sabse bade storage consumers mein se hain, aur yahi wajah hai storage tiering (Step
6.3), na ki simply "aur disks kharido," is scale par kisi bhi credible design ka
required part hai.

**View / playback QPS**

```
Views/day = 200,000,000 DAU x 5 views/day = 1,000,000,000 (1B) views/day

Average view-start QPS = 1,000,000,000 / 86,400 ≈ 11,574 views/sec
Peak view-start QPS ≈ 11,574 x 3 ≈ 34,700 views/sec
```

Har "view" phir watch ki duration ke liye sustained streaming bandwidth generate karta
hai, sirf ek single request nahi — yahi ek typical request/response system se key
difference hai.

**Bandwidth**

```
Assume karo ek average viewing bitrate of 3 Mbps (resolutions ka mix, adaptive
streaming actually zyadatar viewers ko jahan settle karti hai uske weighted) aur ek
average concurrent-viewer count jo view rate x average watch duration se derive hota
hai (assume karo 8 minutes average watch time):

Concurrent viewers ≈ average view-start QPS x average watch duration (sec)
                   ≈ 11,574 x 480 ≈ 5,555,520 concurrent streams (average)

Total average bandwidth ≈ 5,555,520 streams x 3 Mbps ≈ 16.67 Tbps average

Peak bandwidth (3x) ≈ 50 Tbps
```

Yeh bandwidth figure strongest possible argument hai iske liye ki virtually saara
traffic origin servers ki jagah CDN edge nodes se serve hona chahiye (Step 6.3) — koi
bhi reasonably sized origin fleet directly end users ko tens of terabits per second
serve nahi kar sakta.

## Step 3: High-Level Design

Do largely independent pipelines: ek **asynchronous upload/processing pipeline**
(slow, write-path, latency-sensitive nahi) aur ek **playback/delivery path** (fast
hona zaroori hai, read-path, extremely high fan-out). Yeh sirf usi point par milte
hain jahan processed video chunks object storage mein land karte hain.

```text
   UPLOAD PATH
   ┌────────┐      ┌────────────────┐      ┌──────────────────────┐
   │ Client  │─────►│ Upload Service   │─────►│ Raw Video Object       │
   │(uploader)│     │ (accepts file,   │      │ Storage (source files) │
   └────────┘      │  returns quickly)│      └──────────┬─────────────┘
                    └───────┬──────────┘                 │
                            │ publish "video uploaded"     │ triggers
                            ▼                              ▼
                 ┌────────────────────┐          ┌──────────────────────┐
                 │ Message Queue        │─────────►│ Transcoding Workers    │
                 │ (async job trigger)  │          │ (produce N renditions, │
                 └────────────────────┘          │  chunk into segments)  │
                                                    └──────────┬─────────────┘
                                                                │
                                                                ▼
                                                    ┌──────────────────────┐
                                                    │ Processed Video Object │
                                                    │ Storage (chunked, per- │
                                                    │ rendition segments)    │
                                                    └──────────┬─────────────┘
                                                                │ replicated to
                                                                ▼
                                                    ┌──────────────────────┐
                                                    │         CDN             │
                                                    │  (edge caches, global)  │
                                                    └──────────────────────┘

   PLAYBACK PATH
   ┌────────┐   1. request manifest    ┌────────────────┐
   │ Viewer  │─────────────────────────►│ Metadata Service │
   │ Client  │◄─────────────────────────│ (video info, DB)  │
   └───┬────┘   2. manifest (.m3u8/     └────────────────┘
       │            .mpd) w/ CDN URLs
       │ 3. request segments, one quality level at a time,
       │    adapting based on measured throughput
       ▼
   ┌────────────────┐   cache MISS (rare, long-tail)   ┌───────────────────┐
   │      CDN Edge     │─────────────────────────────────►│ Processed Video     │
   │  (cache HIT, common)│                                │ Object Storage      │
   └────────────────┘                                    │ (origin)            │
                                                            └───────────────────┘
```

**Upload flow**: client apni raw file Upload Service ko upload karta hai, jo use
directly object storage mein stream kar deta hai aur turant success return karta hai
— response transcoding complete hone ka wait nahi karta. Ek message queue par publish
hota hai, aur transcoding workers use asynchronously pick up karte hain, multiple
resolution/bitrate renditions produce karte hain jo short segments mein chunk kiye
hote hain, processed-video object storage mein wapas likhe jaate hain, jo phir CDN ko
push (ya first request par pull) kiya jaata hai.

**Playback flow**: client pehle Metadata Service se video maangta hai aur ek
**manifest file** (HLS `.m3u8` ya DASH `.mpd`) receive karta hai jisme available
quality levels aur unke segments ke CDN URLs list hote hain. Player phir segments ko
ek ek karke request karta hai, har segment ke liye quality level currently measured
network throughput ke aadhar par choose karta hai — almost hamesha ek nearby CDN edge
cache se seedha serve hota hai, sirf occasionally origin object storage tak fall
through karta hai.

## Step 4: API Design

**1. Initiate upload**

```
POST /v1/videos/upload
Request:  { "uploader_id": "u123", "title": "How CDNs work", "file_size_bytes": 524288000 }
Response: { "video_id": "v-9f31...", "upload_url": "https://upload.example.com/put/v-9f31...", "status": "PENDING_UPLOAD" }
```
`upload_url` typically ek pre-signed direct-to-object-storage URL hota hai taaki raw
bytes ko ek application server ke through proxy hi na karna pade — same principle
jaisa `../01_Concepts/12_storage_systems.md` mein direct-to-object-storage upload
patterns ka hai.

**2. Check processing status**

```
GET /v1/videos/{video_id}/status
Response: { "video_id": "v-9f31...", "status": "TRANSCODING", "progress_pct": 62 }
```
Statuses progress karte hain: `PENDING_UPLOAD -> UPLOADED -> TRANSCODING -> READY ->
(FAILED, error par)`. Client isko poll karta hai (ya webhook/push se subscribe karta
hai) instead of original upload call ke block hone ke.

**3. Get playback manifest**

```
GET /v1/videos/{video_id}/manifest
Response: {
  "video_id": "v-9f31...",
  "manifest_url": "https://cdn.example.com/v-9f31/master.m3u8",
  "duration_sec": 734,
  "available_renditions": ["1080p", "720p", "480p", "360p", "240p"]
}
```
Actual adaptive-bitrate logic (kaunsa segment, kaunsi quality) client-side player ke
andar hota hai ek baar yeh manifest mil jaaye — dekho Step 6.2.

**4. Get video metadata**

```
GET /v1/videos/{video_id}
Response: {
  "video_id": "v-9f31...", "title": "How CDNs work", "uploader_id": "u123",
  "duration_sec": 734, "view_count": 184213, "like_count": 6420,
  "created_at": "2026-09-01T12:00:00Z"
}
```

**5. Record a view**

```
POST /v1/videos/{video_id}/view
Request:  { "user_id": "u456", "watched_sec": 12 }
Response: { "status": "ACCEPTED" }
```
Client ke perspective se deliberately fire-and-forget — yeh database row mein
synchronously counter increment nahi karta; dekho Step 6.4.

**6. Search videos**

```
GET /v1/search?q=cdn+architecture&limit=20
Response: { "videos": [ { "video_id": "...", "title": "...", "relevance_score": 9.1 }, ... ] }
```

## Step 5: Data Model

**1. Video bytes (source and transcoded renditions) — object storage**

Raw uploaded file aur har transcoded rendition ke segments dono opaque blobs hote hain,
key se accessed, kabhi content ke basis par query ya filter nahi hote — object storage
(S3-style) ka textbook case, na ki filesystem ya database, jaisa
`../01_Concepts/12_storage_systems.md` mein cover hai. Object storage ka durability
model (data multiple devices/zones ke across automatically replicated) yahi wajah hai
Step 2 ke yearly storage estimate ne naive 3x application-level replica count se lighter
overhead multiplier use kiya.

```
Bucket layout (conceptual):
  raw/{video_id}/source.mp4
  processed/{video_id}/1080p/segment_000.ts ... segment_NNN.ts
  processed/{video_id}/720p/segment_000.ts ... segment_NNN.ts
  processed/{video_id}/master.m3u8   (manifest referencing all renditions)
```

**2. Video metadata — relational database**

```
Table: videos
video_id | uploader_id | title | description | duration_sec | status | created_at

Table: view_counts (ya ek separate fast counting store, dekho 6.4)
video_id | approximate_view_count | last_aggregated_at
```
Yeh choose kiya gaya kyunki metadata exactly wahi structured, relatively
low-volume-per-row, query-by-multiple-fields data hai jisme relational databases
excel karte hain (uploader se lookup karo, status se filter karo, channel/user data se
join karo) — aur critically, yeh video bytes se ek **poori tarah separate database**
hai, isliye metadata queries kabhi bhi actual video content ke enormous read/write
volume se compete ya block nahi hote.

**3. Manifests — generated files, segments ke saath object storage mein stored (ya ek chhoti manifest-generation service se dynamically serve kiye jaate hain)**

Manifest khud chhota text hota hai (segment URLs aur bitrates ki ek list) aur ya toh
transcode time par ek baar pre-generated hota hai aur CDN par kisi bhi static asset ki
tarah cached hota hai, ya ek lightweight service se on the fly generate hota hai —
kisi bhi tarah yeh hot video-byte storage path ka part nahi hai.

**4. View/engagement events — append-only log, ek async aggregation pipeline ko feed karta hai**

```
Event: { video_id, user_id, watched_sec, event_time }
```
Ek stream par likha jaata hai (`../01_Concepts/10_message_queues_and_streaming.md`)
directly ek row increment karne ki jagah — jo aggregation pipeline isse consume karta
hai aur `approximate_view_count` produce karta hai, woh Step 6.4 mein cover hai.

## Step 6: Deep Dive

### 6.1 Upload and the Asynchronous Transcoding Pipeline

Upload response jaldi return hona chahiye — ek user ko un minutes ke liye spinner
ghoorte hue nahi baithna chahiye jo ek long video ko poori tarah process hone mein
lag sakte hain. Design isse achieve karta hai "bytes accept karo" ko "bytes process
karo" se strictly separate karke: Upload Service ka sirf ek kaam hai raw file ko jitni
jaldi ho sake safely object storage (Step 5) mein daalna, often ek pre-signed URL ke
through jo client ko directly storage mein upload karne deta hai bina application
server ke bytes proxy kiye, aur phir yeh turant `PENDING_UPLOAD`/`UPLOADED` status ke
saath success return karta hai.

Actual transcoding — source ko decode karna aur use multiple target
resolutions/bitrates/formats mein re-encode karna — CPU-intensive aur slow hai (ek long
video ke liye multi-minute job, capable hardware par bhi, kyunki video encoding server
workloads mein sabse zyada computationally expensive common workloads mein se ek hai)
aur yeh poori tarah out-of-band handle hoti hai: "video uploaded" event ek message
queue par publish hoti hai (`../01_Concepts/10_message_queues_and_streaming.md`), aur
transcoding worker processes ka ek fleet us queue se consume karta hai, har ek ek job
pick karta hai, configured set of renditions produce karta hai, aur results ko
processed-video storage mein wapas likhta hai. Yeh decoupling do cheezein deti hai jo
ek synchronous design nahi de sakta: upload path fast aur simple rehta hai chahe
transcoding load kuch bhi ho, aur transcoding worker fleet independently (aur
elastically, kyunki transcoding demand upload volume ke saath spike karti hai, viewing
volume ke saath nahi) scale ho sakta hai bina upload path ko touch kiye. Client status
updates poll karta hai (ya push kiye jaate hain) jaise job queue aur workers ke through
progress karta hai.

### 6.2 Adaptive Bitrate Streaming (HLS / DASH)

Har viewer ko same fixed video quality serve karna ek poor fit hai global audience ke
liye jinke paas wildly different network conditions hain — ek fast fiber wala viewer
aur ek congested mobile connection wala viewer ke bandwidth budgets fundamentally
different hote hain, aur ek fixed quality choose karna ya toh pehle viewer ke liye
bandwidth waste karta hai ya doosre ke liye constant buffering cause karta hai.

Adaptive bitrate streaming isse video ko khud restructure karke solve karta hai, sirf
player ko nahi: har rendition (1080p, 720p, etc., 6.1 mein transcoding ke dauraan
produce ki gayi) short segments mein split hoti hai — typically kuch seconds ka har
ek — aur ek **manifest file** (HLS `.m3u8` use karta hai, DASH `.mpd` use karta hai)
list karti hai, har quality level ke liye, uske segments ki sequence ke URLs. Player
manifest ek baar download karta hai, phir segments ko **ek ek karke** request karta
hai, continuously apna recent download throughput measure karte hue aur *next* segment
ke liye kaunsi quality level request karni hai woh current conditions ke aadhar par
choose karte hue — poore video ke liye ek quality par commit nahi karta. Agar network
mid-playback degrade hota hai, toh very next segment lower bitrate par request ho
sakta hai, aur playback bina stall ke continue hota hai; agar conditions improve
hoti hain, toh next segment upar step back kar sakta hai. Kyunki different quality
levels ke segments same time boundaries par aligned hote hain, quality switch karna
segments ke beech koi visible glitch ya restart produce nahi karta — player bas usi
timeline ke agle kuch seconds ke liye ek different source choose kar raha hota hai.

Yahi wajah hai 6.1 ka transcoding pipeline har rendition ke liye ek file nahi balki
ek **chunked** output produce karta hai: adaptive streaming ka poora mechanism
independently segments ko request aur switch karne ki ability par depend karta hai,
sirf poore files ke beech nahi.

### 6.3 CDN Distribution and the Long Tail

Video almost ideal CDN workload hai: ek baar transcode hone ke baad, ek video ke
segments poori tarah static hote hain (immutable — same bytes har viewer ko serve
hote hain, forever, jab tak video delete ya re-process na ho) aur overwhelmingly
read-heavy (Step 2 ka bandwidth math — same underlying bytes ke millions playbacks).
Yeh exactly wahi profile hai jo `../01_Concepts/05_caching.md` ka CDN section
strongest CDN use case ki tarah describe karta hai: content jo per-request change
nahi hota aur huge numbers of geographically distributed users se request hota hai.

Practice mein iska matlab hai overwhelming majority playback bandwidth (Step 2 ka
~17-50 Tbps) CDN edge caches se serve hota hai, origin object storage se nahi — ek
edge cache hit origin ko kuch bhi cost nahi karta aur viewer ko ek nearby location se
serve karta hai, load aur latency dono minimize karta hai. Lekin CDN edge storage
finite hai aur har video equally benefit nahi karta: **popular aur recent videos**
itne concurrent viewers se, itne different edge regions se watch hote hain, ki unke
segments almost everywhere hot cache mein rehte hain — ek classic power-law access
pattern. Ek **long tail of rarely-watched videos** (older uploads, niche content, ek
video jiske handful total views hain) itni kam requests per edge region dekh sakta hai
ki unke segments requests ke beech evicted ho jaate hain, ya extreme cases mein kabhi
kisi given edge par cache hi nahi hote — un requests "origin hit" (processed video
object storage) zyada karte hain, per-request higher latency par lekin aggregate mein
far lower absolute volume par, jo ek acceptable trade-off hai precisely kyunki us tail
ko serve karne mein itna kam total bandwidth spend hota hai. Yeh popularity-driven
caching behavior yahi wajah bhi hai ki release-day/trending content kabhi kabhi
proactively edge locations mein push (push-CDN style) kiya jaata hai expected demand
se pehle, organic pull-based caching ka wait karne ki jagah, push-vs-pull CDN
trade-off jo generally `../01_Concepts/05_caching.md` mein describe hai.

### 6.4 Metadata Storage and View-Count Aggregation

Video metadata (title, description, uploader, duration — Step 5) ek relational
database mein rehta hai jo video bytes se poori tarah separate hai, dono is wajah se ki
yeh ek structurally different access pattern hai (small structured records,
queried/filtered/joined) aur kyunki alag rakhne se metadata reads aur writes kabhi
video-byte traffic ke vastly higher-volume se contend ya bottleneck nahi hote.

View count specifically apni ek explanation deserve karta hai kyunki obvious
implementation — `UPDATE videos SET view_count = view_count + 1 WHERE video_id = ?`
har single playback par — popular content par ek severe write hotspot create karta
hai. Ek viral video jo har second thousands of concurrent views receive kar raha ho,
uska matlab hai *same row* ko thousands of concurrent `UPDATE`s, us row ke lock ke
through serializing, aur metadata database ko platform ke sabse successful content ke
liye bottleneck bana dena — exactly opposite of what you want.

Iski jagah, view counts **batched ya approximated** hote hain synchronously per view
increment karne ki jagah. `POST /view` call (Step 4) bas ek event stream par emit karta
hai (Step 5 ka append-only event log) aur turant return karta hai, koi synchronous
database write nahi karta. Ek separate counting/aggregation pipeline — ya toh ek
dedicated counting service jo har video ke liye approximate in-memory counters rakhti
hai aur periodically unhe metadata store mein flush karti hai, ya ek stream-processing
job jo view events ko window aur sum karta hai (wahi conceptual pattern jo
`10_twitter_x.md` mein trending-topic counting ke liye use hua) — `view_count` ko
batched, infrequent writes mein update karti hai (e.g., har video ke liye har kuch
seconds ya minutes mein ek baar, potentially thousands individual view events ko ek
write mein coalesce karke). Users ko dikhaya jaane wala number isliye hamesha ek close
approximation hota hai, true real-time count se ek chhoti, bounded window se lag karte
hue — ek explicitly accepted trade-off, kyunki exact real-time view counts woh cheez
nahi hai jispar users ya product meaningfully depend karte hain, lekin popular videos
par ek write-hotspot-induced outage bilkul depend hoti.

## Step 7: Bottlenecks & Trade-offs

- **Transcoding capacity upload side par throughput ceiling hai.** Encoding CPU-bound
  aur comparatively expensive hai; upload volume mein ek spike (ya large/long videos ka
  backlog) finite worker capacity ke peeche queue up ho jaata hai, naye uploads ke liye
  time-to-availability delay karta hai — isse mitigate kiya jaata hai renditions ko
  prioritize karke (e.g., pehle ek lower-resolution rendition produce karo taaki video
  jaldi watchable ho, phir higher resolutions ko backfill karo), initial quality ko
  faster availability ke liye trade karte hue.
- **Long-tail content par CDN cache misses cost aur latency ko origin storage par
  push karte hain**, aur origin object storage, durable aur per byte cheap hone ke
  bawajood, ek low-latency, high-QPS playback origin ki tarah design nahi hui hai edge
  cache jaise performance tier par — ek design jo ek bahut long tail wala catalog serve
  karta hai (jaisa zyadatar large platforms karte hain) ko apne miss rate ke hisaab se
  origin capacity size karni padti hai, sirf total catalog size se nahi.
- **Storage growth effectively unbounded hai aur transcoded renditions se dominated
  hai** (Step 2 ka ~1 exabyte/year). Isse mitigate kiya jaata hai storage tiering se:
  rarely-accessed old renditions (ya unpopular videos ke lower-priority resolutions) ko
  cheaper, higher-latency cold storage tiers mein move karo, aur consider karo ki
  content jise koi nahi dekhta uske liye har rendition forever store karne ki jagah
  on-demand re-transcode kiya jaye — ek direct storage-cost vs. on-demand-compute
  trade-off.
- **View-count approximation ka matlab hai product kabhi perfectly real-time number
  nahi dikhata**, jo view counts ke liye theek hai lekin iska matlab yeh nahi ki isi
  batching pattern ko kisi bhi cheez ke liye blindly reuse kiya ja sake jisme strong
  consistency chahiye (e.g., ad billing/impression counts, jinhe exact, auditable
  figures chahiye) — unhe ek alag, consistency-prioritized pipeline chahiye.
- **Recommendations explicitly out of scope hain yahan** (neeche Step 6.5 note) lekin
  ek real system mein woh ek major additional subsystem hai apni khud ki data pipeline
  ke saath, aur interviewers jo personalization par push karte hain woh effectively is
  design ke upar layered ek alag, ML-systems question puch rahe hote hain.

### 6.5 Recommendations: explicitly out of scope

"Up next" ya homepage videos recommend karna ek substantial, separate ML subsystem hai
— watch history, engagement signals, aur content features ke upar personalization/
ranking models train aur serve karna — aur deliberately is design se scope out kiya
gaya hai, jaise feed ranking `08_news_feed.md` mein scope out kiya gaya hai. Upar ka
core streaming design woh hai jo ek recommendation ko *servable* banata hai ek baar
compute ho jaaye (fast metadata lookups, fast manifest/CDN delivery jo bhi video
recommend ho uske liye); yeh kuch nahi kehta ki recommendation khud kaise choose kiya
jaata hai.

## Follow-up Questions an Interviewer Might Ask

**Aap pre-recorded video ki jagah live streaming kaise support karenge?**
Live streaming batch transcoding pipeline ko ek low-latency real-time pipeline se
replace karta hai: incoming stream near-real-time mein multiple bitrates mein transcode
hota hai (segments continuously produce hote hain, capture hone ke seconds baad, ek
poori upload ke baad ek saath produce hone ki jagah), aur manifest ek baar generate
hone ki jagah continuously append hota hai — Step 6.2 aur 6.3 ke CDN distribution aur
adaptive-bitrate playback mechanics largely same rehte hain, lekin acceptable
end-to-end latency budget (capture se viewer tak) ek first-class design constraint
ban jaata hai jaisa on-demand video ke liye nahi hota.

**Aap video start-up latency ko aur kaise kam karenge?**
Techniques mein shamil hai: first segment ko ek lower, fast-to-fetch resolution par
serve karna player ke real throughput measure karne se pehle (taaki playback almost
instantly start ho throughput estimate ka wait karne ki jagah), manifest aur first
segment ko prefetch karna jaise hi user thumbnail hover/tap karta hai explicit play
action ka wait karne ki jagah, aur ensure karna ki popular content ke first segments
aggressively edge-cached hon kyunki woh definition se har baar us video ke start hone
par request hote hain.

**Aap upload time par copyright/content moderation kaise handle karenge?**
Yeh typically transcoding ke saath ek additional asynchronous pipeline stage hai —
e.g., ek content-fingerprinting/matching service same "video uploaded" event consume
karti hai, aur ek video `READY` status (Step 4) se hold kiya ja sakta hai jab tak
moderation decision na ho, bina transcoding pipeline ko khud block ya slow kiye.

**Aap ek bahut bade video (multi-hour, high resolution) ko ek short clip se differently
kaise handle karenge?**
Large uploads chunked/resumable upload use karte hain (taaki ek network interruption
ek multi-gigabyte upload ko scratch se restart na kare) aur ek long video ke liye
transcoding job khud parallelize ho sakta hai source ko segments mein split karke aur
unhe multiple workers ke across concurrently transcode karke, phir manifest ko
reassemble karke — ek worker se hours ka footage serially process karne ki jagah.

**Aap offline downloads (bina network connection ke watch karna) kaise support karenge?**
Yeh adaptive streaming (6.2) ka same segment-and-rendition structure reuse karta hai:
player ko segments network se just-in-time fetch karne ki jagah, woh ek chosen
rendition ke segments ko locally device par pehle se pre-fetch aur store kar leta hai,
DRM/licensing constraints ke subject to jo core delivery architecture se ek separate
concern hain.

**Application servers par traditional file system ki jagah video ko object storage
mein kyun store karte hain?**
Object storage exactly is shape ke data ke liye purpose-built hai — huge immutable
blobs, key se accessed, exabytes tak scale hona aur failures ke across durable rehna
bina kisi application server ke koi physical disk own kiye — aur storage
capacity/durability ko compute fleet se poori tarah decouple karta hai jo requests
serve karta hai, unlike ek traditional filesystem jo ek specific machine ke disks se
tied hoti hai; dekho `../01_Concepts/12_storage_systems.md`.
