# Design Twitter / X

## Problem Statement

"Design Twitter (ya X). Users short text messages (tweets) post kar sakte hain, dusre
users ko follow kar sakte hain, aur unke timeline mein un logon ke tweets dikhte hain
jinko woh follow karte hain. Retweets, likes, hashtags, aur search support karo. Assume
karo ki hundreds of millions users hain aur ek highly asymmetric social graph hai — kuch
accounts ke paas hundreds of millions followers hain."

## Step 1: Clarify Requirements

### Functional Requirements

- Users ek tweet post kar sakte hain (short text, optional media, optional hashtags).
- Users kisi dusre user ko follow/unfollow kar sakte hain — yeh ek **directed,
  asymmetric** relationship hai (A, B ko follow karta hai iska matlab yeh nahi ki B bhi
  A ko follow karega), unlike mutual "friend" graph.
- Users apna reverse-chronological (ya ranked) home timeline dekh sakte hain jisme un
  accounts ke tweets hote hain jinko woh follow karte hain.
- Users kisi tweet ko like aur retweet kar sakte hain.
- Users keyword aur hashtag se tweets search kar sakte hain.
- System trending topics/hashtags surface karta hai.

### Non-Functional Requirements

- **Read-heavy, aur bahut zyada**: timeline reads, tweet writes se kaafi zyada hote hain
  — yeh ratio hi is poore design ko shape karne wala sabse important fact hai (Step 2
  dekho).
- **Timeline load ke liye low read latency**: app open karke ek populated timeline
  dikhna instant feel hona chahiye (low hundreds of milliseconds mein).
- **Write availability, write latency se zyada matter karti hai**: tweet post karna load
  ke neeche bhi kabhi fail nahi hona chahiye — yeh acceptable hai ki tweet ko sabke
  timeline mein propagate hone mein thoda time lage (fan-out par eventual consistency),
  lekin write khud (tweet ka durably exist karna) reliably succeed hona chahiye.
- **Extreme fan-out skew**: follower-count ka distribution ek power law hai — zyadatar
  accounts ke paas handful followers hain, thode se accounts ke paas tens ya hundreds of
  millions. Koi bhi design jo "tweet post karo" ko "har follower ke timeline mein
  synchronously write karo" maan kar chale, woh us doosre group ke liye catastrophically
  break ho jayega — yeh is system ka defining hard problem hai (Step 6.1).
- **Near-real-time search aur trending**, zaroori nahi ki millisecond-fresh ho — thoda
  sa indexing/aggregation lag acceptable hai.
- **Eventual consistency acceptable hai** timeline propagation aur like counts ke liye;
  "kya mere follower ka timeline update ho gaya" — is baat ke liye strong consistency
  zaroori nahi hai.

## Step 2: Back-of-Envelope Estimation

**Assumptions:**

- 300 million daily active users (DAU).
- 500 million tweets roz post hote hain, poore system mein.
- Har DAU apna timeline average 10 baar/din check karta hai.
- Read:write ratio, upar wale se derive karke, roughly 1000:1 hai — yeh ek number hi
  neeche ke zyadatar architectural choices ko drive karta hai.
- Har account ka average follower count, tweets actually posted ke hisaab se weighted,
  ~700 hai (yeh "effective average" already is baat ko account karta hai ki zyadatar
  tweets ordinary accounts se aate hain, celebrities se nahi — celebrities ko Step 6.1
  mein alag case ki tarah handle kiya gaya hai, is average mein fold nahi kiya gaya).
- Peak traffic average se ~3x chalta hai.

**Write QPS (tweets)**

```
Average write QPS = 500,000,000 / 86,400 ≈ 5,787 tweets/sec
Peak write QPS ≈ 5,787 x 3 ≈ 17,360 tweets/sec
```

**Read QPS (timeline loads)**

```
Timeline reads/day = 300,000,000 DAU x 10 checks/day = 3,000,000,000 reads/day
Average read QPS = 3,000,000,000 / 86,400 ≈ 34,722 reads/sec
Peak read QPS ≈ 34,722 x 3 ≈ 104,000 reads/sec

Read:write ratio ≈ 34,722 : 5,787 ≈ 6:1 raw request counts par —
lekin har timeline read typically ~20 tweets return karta hai jo potentially
sainkdon followed accounts se pull hote hain, isliye actual *fan-out read* work
(agar naively kiya jaye, Step 6.1 ke according) is ratio se kaafi zyada hai, aur
yahi wajah hai precomputed timelines exist karte hain.
```

**Storage**

```
Average tweet: ~280 bytes text + metadata (tweet_id, author_id, timestamp,
reply/retweet pointers, counters) ≈ 1 KB stored per tweet indexing overhead ke saath.

Daily storage = 500,000,000 x 1 KB = 500 GB/day
Yearly storage (raw) = 500 GB x 365 ≈ 182.5 TB/year
3x replication ke saath ≈ 547.5 TB/year

(Media attachments — images/video — alag se object storage mein store hote hain aur
yeh figure ko dwarf kar dete hain; yeh tweet-storage calculation se out of scope hai,
same pattern jaisa ../01_Concepts/12_storage_systems.md mein hai.)
```

**Fan-out write amplification (woh number jo Step 6.1 ko motivate karta hai)**

```
Naive fan-out-on-write: har tweet post time pe har follower ke precomputed
timeline mein likha jaata hai.

Average case: 5,787 tweets/sec x 700 followers/tweet ≈ 4,050,900
timeline-row writes/sec — already kaafi zyada hai, lekin roughly steady aur
shardable hai.

Celebrity case: EK tweet, 100-million-follower account se, agar isi tarah kiya
jaye toh 100,000,000 timeline-row writes chahiye honge — even generous
50,000 writes/sec per fan-out worker par bhi, yeh 2,000 seconds (33+ minutes)
lega ek single tweet ko fan-out karne mein. Yahi concrete number hai jo pure
fan-out-on-write ko untenable banata hai aur 6.1 ke hybrid approach ko motivate
karta hai.
```

## Step 3: High-Level Design

```text
                         ┌───────────────┐
                         │    Client      │
                         └───────┬───────┘
                                 │
                        ┌────────▼─────────┐
                        │   API Gateway /    │
                        │   Load Balancer    │
                        └───┬───────────┬────┘
                            │           │
                 write path │           │ read path
                            ▼           ▼
                ┌────────────────┐  ┌──────────────────┐
                │  Tweet Service   │  │ Timeline Service  │
                │ (assign ID, write│  │ (assemble/serve   │
                │  tweet, publish) │  │  home timeline)   │
                └───┬──────────┬──┘  └───┬───────────┬───┘
                    │          │         │           │
         ┌──────────▼──┐   ┌───▼─────────▼──┐   ┌────▼──────────┐
         │ Tweet Store   │   │  Fan-out Service │   │ Precomputed     │
         │ (tweet_id ->  │   │ (async worker,   │   │ Timeline Cache  │
         │  tweet data)  │   │  reads follower   │   │ (Redis, per-user│
         └──────────────┘   │  graph, pushes to │   │  sorted list of │
                             │  follower timelines)│  │  tweet_ids)    │
                             └───┬──────────────┘   └────────────────┘
                                 │
                        ┌────────▼─────────┐
                        │ Social Graph Store │
                        │ (user -> followers)│
                        └───────────────────┘

  parallel paths off the Tweet Service:
                    ┌───────────────────────┐
   tweet published → │ Message Queue / Stream  │ → Search Indexer → Inverted Index
                    │ (firehose of tweets)    │ → Trending Aggregator → Trending Store
                    └───────────────────────┘
```

**Write flow**: client ek tweet post karta hai -> Tweet Service ek time-sortable ID
assign karta hai (Step 6.2), use Tweet Store mein persist karta hai, aur usse ek
firehose stream par publish karta hai. Teen cheezein us stream ko independently aur
asynchronously consume karti hain: Fan-out Service (tweet ko followers ke precomputed
timelines mein push karta hai, non-celebrity accounts ke liye), Search Indexer (usse
inverted index mein add karta hai), aur Trending Aggregator (hashtag/term frequency ko
ek sliding window mein count karta hai).

**Read flow**: client apna home timeline request karta hai -> Timeline Service
per-user cache se recent tweet IDs ki precomputed, pre-merged list read karta hai,
celebrity accounts ke tweets ko on the fly merge karta hai (Step 6.1), aur Tweet Store
(ya tweet-content cache) se tweet content hydrate karta hai.

## Step 4: API Design

**1. Post a tweet**

```
POST /v1/tweets
Request:  { "author_id": "u123", "text": "shipping a new feature today #buildinpublic", "media_ids": [] }
Response: { "tweet_id": "1745829301923840001", "created_at": "2026-09-13T10:15:00Z" }
```
`tweet_id` ek Snowflake-style, time-sortable 64-bit ID hai — dekho
`01_distributed_id_generator.md` aur Step 6.2.

**2. Get home timeline**

```
GET /v1/timeline/home?user_id=u456&limit=20&before_id=1745829301923840001
Response: {
  "tweets": [
    { "tweet_id": "...", "author_id": "...", "text": "...", "like_count": 214, "retweet_count": 12, "created_at": "..." },
    ...
  ],
  "has_more": true
}
```

**3. Follow a user**

```
POST /v1/follow
Request:  { "follower_id": "u456", "followee_id": "u123" }
Response: { "status": "OK" }
```
Yeh Social Graph Store ko ek write hai aur, notably, apne aap koi timeline backfill
trigger **nahi** karta zyadatar real designs mein — newly-followed account ke *past*
tweets typically retroactively fan-out nahi hote; user ko aage se naye tweets dikhte
hain (ek deliberate, documented trade-off).

**4. Like / retweet**

```
POST /v1/tweets/{tweet_id}/like
Request:  { "user_id": "u456" }
Response: { "status": "OK", "like_count": 215 }

POST /v1/tweets/{tweet_id}/retweet
Request:  { "user_id": "u456" }
Response: { "status": "OK", "retweet_id": "1745829999812340002" }
```

**5. Search tweets**

```
GET /v1/search?q=%23buildinpublic&limit=20
Response: { "tweets": [ { "tweet_id": "...", "text": "...", "relevance_score": 8.4 }, ... ] }
```

**6. Trending topics**

```
GET /v1/trending?region=US&limit=10
Response: { "trends": [ { "tag": "#buildinpublic", "tweet_count_last_hour": 48210 }, ... ] }
```

## Step 5: Data Model

**1. Tweets — wide-column / partitioned NoSQL store, `author_id` ya `tweet_id` range se partitioned**

```
Table: tweets
Key: tweet_id (time-sortable, Step 6.2)
Fields: author_id, text, media_ids, created_at, like_count, retweet_count, reply_to_id (nullable)
```
Yeh choose kiya gaya isi wajah se jaise `09_chat_application.md` mein chat message
store: extremely high write volume (Step 2), simple key-based access pattern (ID se
fetch karo, ya author ke recent tweets scan karo), aur writes ko horizontally scale
karne ki need bina manual resharding ke.

**2. Social graph — graph-shaped store ya ek purpose-built adjacency table**

```
Table: follows
Partition key: follower_id      Clustering key: followee_id, followed_at
(aur ek doosri table opposite direction mein key ki gayi —
 followee_id -> follower_id list — kyunki "main kisko follow karta hoon" aur
 "mujhe kaun follow karta hai" dono hi common queries hain aur ek single
 adjacency direction dono ko efficiently answer nahi kar sakti)
```
Yeh conceptually ek graph hai, lekin Twitter ke scale par typically yeh do
denormalized adjacency-list tables (ek har query direction ke liye) ki tarah
implement hota hai ek wide-column ya key-value store mein, na ki ek dedicated graph
database mein, kyunki actual query patterns jo chahiye ("main jinko follow karta hoon
unki list," "mujhe follow karne walon ki list," "kya A, B ko follow karta hai") simple
lookups hain, multi-hop graph traversals nahi jo ek graph database ke liye bane hote
hain.

**3. Precomputed home timelines — in-memory store (Redis), per user**

```
Key: timeline:{user_id}   Value: sorted set of tweet_ids, scored by tweet_id
                                  (jo khud time-sortable hai, Step 6.2)
```
Yeh woh read-path optimization hai jo timeline loads ko fast banata hai — dekho
Step 6.1. Size mein bounded hai (e.g., sirf recent ~800 tweet IDs per user rakhe jaate
hain) taaki memory cost constant rahe har user ke liye, chahe unka account kitna bhi
purana ho.

**4. Likes / retweets — lightweight counters aur relation rows**

```
Table: likes (tweet_id, user_id, created_at)   -- existence = "liked"
Counter: like_count:{tweet_id}  (approximate, ek counting service ke through
                                  increment hota hai, na ki har like par
                                  synchronous DB update se — same rationale
                                  jaisa 11_video_streaming.md mein view-count
                                  batching ka hai)
```

**5. Search index aur trending data**

Ek inverted index (tweet text/hashtags -> tweet IDs), banaya aur query kiya jaata hai
jaise `../01_Concepts/13_search_and_indexing.md` describe karta hai, plus trending
topics ke liye ek separate time-windowed counting store (Step 6.3) — dono hi tweet
data ki derived, asynchronously updated copies hain, source of truth nahi.

## Step 6: Deep Dive

### 6.1 Timeline Generation and the Celebrity Problem

Twitter ke liye timeline generation general fan-out problem ka canonical, sabse zyada
cite kiya jaane wala real-world example hai jo already `08_news_feed.md` mein depth
mein cover ho chuka hai — us file mein **fan-out-on-write** (naya post turant har
follower ke precomputed timeline mein push karo), **fan-out-on-read** (jab user follow
karne walon sab se query karke read time par timeline assemble karo), aur **hybrid**
approach cover hua hai jo dono ko combine karta hai. Yeh section us framework ko
specifically Twitter ke follow graph par apply karta hai, use dubara derive nahi karta,
kyunki Twitter hi woh jagah hai jahan asymmetry sabse extreme hai jo hybrid approach ko
zaroori banati hai.

Pure fan-out-on-write yahan is wajah se break hoti hai — Step 2 mein quantify kiya gaya
power-law follower distribution: ek regular account jiske 700 followers hain, uske liye
fan-out on write cheap hai (700 timeline-row writes, asynchronously ek second se kaafi
kam mein ho jaate hain). Ek account jiske 100 million followers hain, usi tarah fan-out
karne ka matlab hai ek single tweet ke liye 100 million timeline-row writes — kisi bhi
realistic worker throughput par yeh kai minutes leta hai, ek post ke liye enormous
fan-out infrastructure capacity use karta hai, aur, aur bhi bura, agar woh celebrity
jaldi jaldi kai baar post karta hai, toh fan-out work queue up ho jaata hai aur zyada se
zyada peeche padta jaata hai, matlab followers ko stale timelines dikhte hain exactly
tab jab account sabse zyada active hota hai.

Pure fan-out-on-read (kabhi precompute mat karo, hamesha read time par assemble karo
user ke follow kiye hue sabse tweets merge karke) us write explosion ko avoid kar deta
hai lekin opposite problem create karta hai: ek ordinary user ka timeline load ab
require karta hai un (potentially sainkdon) accounts se recent tweets fetch karna jinko
woh follow karta hai aur unhe on the fly merge karna, har single timeline load par — aur
timeline loads ~35,000 QPS average par hote hain (Step 2), tweets post hone se kaafi
zyada often. Yeh *common* case (ek normal user apna timeline open kar raha hai) ko
expensive bana deta hai instead of *rare* case (ek celebrity post kar raha hai) ke.

Standard hybrid answer, yahan concretely apply kiya gaya:

- Follower threshold ke neeche wale accounts ke liye (jo vast majority accounts hain),
  fan-out-on-write use karo: unke tweets asynchronously Fan-out Service ke through
  followers ke precomputed timeline caches mein push kiye jaate hain. Isse normal
  timeline reads ek single cache lookup rehte hain (Step 5 ka Redis sorted set), jo
  dominant read path ko fast rakhta hai.
- Threshold se upar wale accounts (celebrities) ke liye, **write time par fan-out ko
  poori tarah skip karo**. Unke tweets sirf Tweet Store mein likhe jaate hain aur wahin
  chhod diye jaate hain.
- Read time par, Timeline Service har user ke liye do sources merge karta hai: precomputed
  timeline (fan-out-on-write accounts se) plus us user ke follow kiye hue thode se
  celebrity accounts se live, on-demand fetch of recent tweets (itne kam celebrities
  hote hain, aur koi bhi ek user itne kam celebrities follow karta hai, ki yeh live
  fetch-and-merge cheap hai — har timeline load par handful extra sources merge karna
  hai, sainkdon nahi).

Yeh ek unbounded, spiky write cost (follower count ke proportional, jo unbounded hai) ko
ek chhoti, bounded extra read cost mein convert kar deta hai (proportional us number of
celebrities ke jinhe ek user follow karta hai, jo chhota hi rehta hai chahe user kitne
bhi celebrities follow kare) — yehi core trade-off hai jo hybrid model ko kaam karta
hai, aur specifically yahi wajah hai ki yeh is question par interviewers jo answer
sunna chahte hain.

### 6.2 Tweet Storage and ID Generation

Har tweet ko ek globally unique identifier chahiye, aur natural choice ek
**time-sortable ID** hai na ki ek random UUID ya simple auto-increment — ID generation
ka poora problem (kyun ek single auto-increment shards ke across scale nahi karta,
kyun random UUIDs sort order aur index locality destroy kar dete hain, aur
Snowflake-style bit layout of timestamp + machine ID + sequence number)
`01_distributed_id_generator.md` mein poori tarah cover hai; yeh section sirf note
karta hai ki yeh specifically yahan kyun matter karta hai.

Twitter ka dominant access pattern chronological hai: ek timeline "recent tweets
pehle" hoti hai, ek user ka profile "unke recent tweets pehle" hota hai, search
results often recency se sorted ya filtered hote hain. Ek time-sortable ID ka matlab
hai `ORDER BY tweet_id DESC` chronological order *hi hai* bina alag timestamp index ya
column scan ke, aur iska matlab yeh bhi hai ki Step 5 ke precomputed timeline sorted
sets `tweet_id` se directly score kar sakte hain — ID se sort karna aur time se sort
karna same operation hai, jo read path aur fan-out write path dono ko simplify karta
hai. Isi wajah se Step 4 ka API design `before_id` use karta hai (`before_timestamp`
nahi) pagination ke liye — yeh ek cheaper, unambiguous cursor hai precisely kyunki ID
mein already time order encode hai.

### 6.3 Search, Hashtags, and Trending Topics

**Search aur hashtags** wahi inverted-index approach use karte hain jo
`../01_Concepts/13_search_and_indexing.md` mein poori tarah cover hai: tweet text
tokenize hota hai, hashtags ko first-class searchable terms treated kiya jaata hai, aur
har term ek postings list of tweet IDs se map hota hai. Tweets asynchronously search
indexer mein flow karte hain firehose stream se (Step 3), jiska matlab hai — kisi bhi
search system ki tarah — "tweet posted" aur "tweet search results mein show hua" ke
beech ek chhota near-real-time indexing lag hota hai; yeh ek acceptable, explicitly
stated trade-off hai, bug nahi.

**Trending topics** ek genuinely different problem hai search se: "query match karne
wale tweets dhundo" ki jagah, yeh hai "continuously compute karo ki kaunse
terms/hashtags recent sliding window mein frequency mein spike kar rahe hain (e.g.,
last hour), ek constant high-volume stream of ~5,800 tweets/sec average ke across."
Isko naive per-request database query se answer karna — e.g., `SELECT hashtag,
COUNT(*) FROM tweets WHERE created_at > NOW() - INTERVAL 1 HOUR GROUP BY hashtag
ORDER BY COUNT(*) DESC` — scale nahi karta: iska matlab hoga har request par jo
trending data chahta hai, ek huge, constantly growing volume of recent rows scan
karna, har baar scratch se dubara.

Sahi approach hai **stream processing**: jaise tweets firehose ke through flow karte
hain (wahi message queue/stream jo fan-out aur search ko feed karta hai, Step 3), ek
stream-processing job har term ke liye ek running, windowed count maintain karta hai —
counters ko increment karte hue jaise tweets aate hain aur counts ko expire karte hue
jab woh window se age out ho jaate hain, continuously, na ki demand par raw data se
recompute karke. Yeh general pattern hai jo
`../01_Concepts/10_message_queues_and_streaming.md` mein cover hai (ek event firehose
par stream processing), yahan ek concrete counting problem par apply kiya gaya. Trending
endpoint (Step 4) phir sirf is continuously maintained counter store se current top-N
read karta hai — ek O(1)-ish read against precomputed state, exactly wahi
"per request recompute karne ki jagah precompute karo" principle jo
`../01_Concepts/13_search_and_indexing.md` mein typeahead ranking ke liye aur 6.1 mein
timelines ke liye use hua hai.

### 6.4 Retweets and Likes as Lightweight Relations, Not Copies

"Retweet" ka ek naive implementation shayad original tweet ka poora content duplicate
kar de retweeting user ke account ke neeche ek nayi row mein. Yeh wasteful hai aur ek
data-integrity problem create karta hai: agar original tweet edit hota hai (agar
product woh support karta hai) ya delete hota hai, toh har duplicated copy ko dhundh
kar update ya remove bhi karna padega.

Iski jagah, ek retweet ek chhoti relation ki tarah store hoti hai — essentially ek
pointer: `(retweet_id, original_tweet_id, retweeting_user_id, created_at)` — bina
original tweet ke text ya media ki koi duplication ke. Timeline mein ek retweet render
karne ka matlab hai us pointer ko resolve karna aur original tweet ka content (Tweet
Store ya uske cache se) read time par fetch karna, exactly jaise ek foreign key
resolve hota hai. Isse storage distinct tweets ki number ke proportional rehta hai, na
ki unke kitni baar retweet hua uske proportional, aur iska matlab hai ki original
tweet ki deletion ka ek clear jagah effect hota hai.

Likes bhi identical pattern follow karte hain: ek `likes` relation row (Step 5) record
karti hai *ki* ek user ne tweet ko like kiya, tweet ki copy nahi. Tweet par visible
like count har read par us table mein rows synchronously count karke compute nahi hota
(jo har single tweet render par ek aggregation query hoga) — yeh ek approximate,
asynchronously-updated counter ki tarah maintain hota hai, wahi write-hotspot reason ke
liye jaise `11_video_streaming.md` mein view counts batch kiye jaate hain: ek viral
tweet ko har second thousands of likes mil sakte hain, aur ek shared counter row ko
har single like ke liye synchronously increment karna us saare traffic ko ek hot row
ke through serialize kar dega.

## Step 7: Bottlenecks & Trade-offs

- **Celebrity read-merge path hi long-term bottleneck hai**, regular fan-out path
  nahi. Jaise-jaise bahut bade accounts ki number badhti hai, ya koi bhi single user
  unme se zyada follow karta hai, 6.1 mein "read time par thode extra live sources
  merge karo" ka cost badhta jaata hai — "celebrity kaun count hota hai" ka threshold
  aur specifically celebrity tweets ke liye caching strategy (woh definition se bahut
  often read hote hain, isliye excellent cache candidates hain) active tuning maangte
  hain.
- **Precomputed timeline cache ek bada, constantly churning working set hai.** Har
  fan-out-on-write push ek cache write hai; sirf recent ~800 tweet IDs per user rakhna
  (Step 5) memory ko bound karta hai lekin iska matlab hai ki jo user weeks se app
  nahi khola, uska timeline cache "recent" ke liye bana hai, "aap jab last yahan the tab
  se" ke liye nahi — timeline service ko bahut stale users ke liye ek slower
  reconstruction path par fall back karna padta hai.
- **Trending topics manipulation ke liye vulnerable hain (coordinated
  spam/bot spikes)** — 6.3 mein streaming aggregation raw frequency count karta hai,
  isliye ek real system anomaly/bot detection layer karta hai upar se raw counts par
  trust karne ki jagah, jo core counting pipeline se beyond meaningful complexity add
  karta hai.
- **Eventual consistency ka matlab hai users kabhi kabhi stale counts ya missing
  tweets briefly dekhte hain** (ek like count jo catch up nahi hua, ek tweet jisko
  abhi follow kiya usse jo abhi tak appear nahi hua) — ek explicit, accepted trade-off
  jo overall design ki write availability aur throughput ki need ke exchange mein hai;
  yeh system har derived view mein read-your-writes consistency offer nahi karta.
- **Social graph store, tweet store se zyada, practice mein aksar harder scaling
  problem hota hai** — extremely popular accounts hot partitions create karte hain
  "yeh account ko kaun follow karta hai" wale side par (Step 5 ki doosri adjacency
  table), wahi hot-partition problem jo generally `../01_Concepts/07_database_scaling.md`
  mein describe kiya gaya hai.

## Follow-up Questions an Interviewer Might Ask

**Timeline ko strict reverse-chronological order dikhane ki jagah aap use kaise rank karenge?**
Yeh ek ranking/scoring problem ban jaata hai usi candidate-generation pipeline ke upar
layered (fan-out cache + 6.1 ka celebrity merge) — candidates same tarah gather hote
hain, lekin unhe ID order mein return karne ki jagah, ek ranking step display se pehle
har ek ko engagement-prediction signals se score karta hai; ranking model khud ek
separate ML subsystem hai, deliberately core delivery design se out of scope, jaise
feed ranking `08_news_feed.md` mein scope se bahar rakha gaya hai.

**Aap ek user ko handle kaise karenge jo kisi ko unfollow karta hai jiske tweets already
uske precomputed timeline cache mein hain?**
Simplest approach hai lazy cleanup: already-cached entries ko as-is rehne do (woh
naturally age out ho jayenge jaise naye tweets bounded cache size se puraane ko push
karenge) aur bas future fan-out us author se is user ke cache mein aage se stop kar do
— ek eager scan-and-remove ek potentially large cached timeline ke across rarely worth
the cost hota hai ek transient inconsistency ke liye jo apne aap jaldi correct ho jaati
hai.

**Aap tweet deletion kaise support karenge?**
Tweet Store row deleted mark ho jaati hai (ya remove ho jaati hai) aur isse search
index (re-index/remove), trending counters (koi retroactive correction nahi, generally
as-is accept kiya jaata hai), aur precomputed timeline caches (ya toh lazily filtered
read/hydration time par jab Timeline Service content fetch karta hai aur deleted paata
hai, ya eagerly removed agar design ke paas ek efficient reverse-lookup hai — lazy
filtering usually simpler aur sufficient hoti hai) mein propagate karna padta hai.

**Aap tweet posting ko rate-limit kaise karenge taaki spam floods fan-out ko overload na
karein?**
Tweet Service ke saamne ek per-user token-bucket limiter, similar to
`09_chat_application.md` mein chat rate-limiting follow-up — yeh downstream fan-out aur
stream-processing layers ko protect karta hai, kyunki ek single spammy account jo
thousands of times per second post karta hai, warna directly ek proportional fan-out
aur indexing load spike mein translate ho jaayega.

**Aap threads/replies kaise handle karenge?**
Har reply ek normal tweet row hoti hai `reply_to_id` pointer ke saath (Step 5); ek
thread view us pointer chain ko follow karke reconstruct hoti hai, aur "yeh thread
load karo" endpoint home timeline se ek separate read path hai — isse fan-out design
ka part hone ki zaroorat hi nahi hai, kyunki threads on demand fetch hote hain jab user
unhe open karta hai, proactively push nahi hote.

**Social graph ke liye graph database kyun use nahi karte, jab follows naturally ek
graph hain?**
Twitter ke actual query patterns — "main kisko follow karta hoon list karo," "mujhe
kaun follow karta hai list karo," "kya A, B ko follow karta hai" — simple adjacency
lookups hain, multi-hop graph traversals nahi (e.g., "friends of friends," jo Twitter
ko apne core follow model ke liye nahi chahiye). Ek purpose-built graph database apni
complexity tab earn karta hai jab multi-hop traversal ek core query hoti hai; yahan, do
denormalized key-value/wide-column adjacency tables har needed query ko zyada simply
aur higher throughput par answer kar dete hain.
