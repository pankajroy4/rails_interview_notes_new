# Design a News Feed

## Problem Statement

"Design a news feed — home feed jo ek user dekhta hai jab woh Facebook ya Instagram jaisa app khole: un logo aur pages ke posts ki ek scrollable stream jinhe woh follow karta hai, roughly recency (ya relevance) ke hisaab se ordered, jo fast load ho, infinite scroll support kare, aur reasonably up to date rahe jab naye posts create hote hain — hundreds of millions of users ke scale pe, including kuch accounts jinke tens of millions of followers hain." Yeh sabse commonly asked system design questions mein se ek hai exactly isliye kyunki naive solution (follow kiye hue har insaan se posts read time pe query karna) tab tak theek lagta hai jab tak aap scale pe uski cost compute nahi karte, aur interesting design entirely usi gap mein rehta hai.

## Step 1: Clarify Requirements

### Functional Requirements

- Users posts create kar sakte hain (text, possibly media references ke saath).
- Users doosre users ko follow/unfollow kar sakte hain.
- Ek user ka home feed un sab logo ke posts dikhaata hai jinhe woh follow karta hai, recency ke hisaab se ordered (chronological baseline hai; true relevance ranking briefly discuss hoga, Step 6).
- Feed infinite scroll support karta hai — jab user scroll karta hai toh older posts ke aur pages fetch hote hain.
- Ek newly created post followers ke feeds mein kuch seconds ke andar dikhna chahiye, minutes ya hours mein nahi.
- Basic engagement counts (likes, comments) har post ke saath dikhte hain — yahan deep design ka scope nahi hai, lekin data model isko preclude nahi karna chahiye.

### Non-Functional Requirements

- **Scale**: hundreds of millions of daily active users; follower counts zero se lekar tens of millions tak range karte hain ("celebrity" case ek first-class scale concern hai, edge case nahi).
- **Read-heavy workload**: users apna feed post karne se kaafi zyada check karte hain — read:write ratio bada hai (Step 2 mein quantify hua), aur design ko read latency ke liye overwhelmingly optimize karna chahiye.
- **Latency**: feed load p99 roughly 200ms ke neeche — ek slow-loading home feed social app ke liye single most visible performance metric hai.
- **Eventual consistency acceptable hai**: ek naya post follower ke feed mein kuch seconds late dikhna ek non-issue hai; "post created" aur "har follower ke feed mein visible" ke beech strong consistency ki zaroorat nahi.
- **High read availability**: feed essentially kabhi bhi unavailable nahi hona chahiye — even agar kuch backend components degrade ho jaayein, thoda stale feed dikhana ek error dikhane se kaafi behtar hai.
- **Write path ko high-follower accounts ke fan-out pe block nahi karna chahiye** — ek celebrity ka post creation call ko synchronously millions of downstream writes pe wait nahi karwaa sakta (yeh celebrity problem hai, Step 6 ka centerpiece).

## Step 2: Back-of-Envelope Estimation

**Assumptions**:
- 500 million daily active users (DAU).
- Posting rate: on average, 1 post per 20 DAU per day (zyadatar users scroll karne ki possibility zyada rakhte hain, post karne ki kam) → 25 million posts/day.
- Feed-reading rate: har DAU app 8 baar/day khoolta hai, aur har app open roughly 2 feed pages fetch karta hai (initial load + ek scroll-triggered page) → 16 feed-read requests/user/day.
- Average follower count (mean, median nahi — kaafi skew hai chhote se number of very-high-follower accounts ki wajah se): 300.
- Feed entry size: `post_id` + `author_id` + `timestamp` ≈ 24 bytes.
- Precomputed feed depth kept per user: last 800 entries.

**Write QPS (post creation)**

```
25,000,000 posts/day / 86,400 sec ≈ 289 posts/sec average
Peak (3x): 289 × 3 ≈ 870 posts/sec
```

**Read QPS (feed fetch)**

```
500,000,000 DAU × 16 reads/day = 8,000,000,000 reads/day
8,000,000,000 / 86,400 sec ≈ 92,600 reads/sec average
Peak (3x): 92,600 × 3 ≈ 278,000 reads/sec
```

**Read:write ratio**

```
92,600 / 289 ≈ 320:1
```

Yeh 320:1 ratio hi woh single number hai jo Step 6 ke poore architecture ko justify karta hai: iska matlab hai ki write time pe cheap aur fast reads banaane ke liye kiya gaya har extra unit of work roughly 320 baar pay off hota hai har subsequent read se — jo exactly yeh argument hai ki feeds ko har read pe fresh assemble karne ki jagah precompute karna chahiye.

**Fan-out-on-write cost**

Agar har post write time pe eagerly har follower ke precomputed feed mein push kiya jaaye:

```
25,000,000 posts/day × 300 avg followers/post = 7,500,000,000 feed-entry writes/day
7,500,000,000 / 86,400 sec ≈ 86,800 fan-out writes/sec average
```

Yeh already raw post-creation QPS ka ~300x hai — aur isne *mean* follower count use kiya hai, jo thodi si huge accounts ki wajah se upward khinchi gayi hai; median user ke followers kaafi kam hain, matlab un 86,800 writes/sec ka enormous share bahut kam number ke very-high-follower posts ki wajah se hai. Ek single celebrity account jiske 50 million followers hain, ek baar post karta hai toh usi ek post se 50 million feed-entry writes generate hote hain. Isko synchronously, ya even eagerly-but-asynchronously bina special-case kiye karna, un chand seconds ke liye poore fan-out pipeline ki capacity ko dominate kar dega. Yehi concrete arithmetic hai ki kyun ek hybrid fan-out strategy (Step 6) zaroori hai, sirf ek nice-to-have optimization nahi.

**Feed storage**

```
500,000,000 users × 800 entries × 24 bytes = 9,600,000,000,000 bytes ≈ 9.6 TB
```

Ek fast key-value/wide-column store ke liye entirely feasible hai jo sirf references hold karta hai, full post content nahi.

**Post content storage**

```
25,000,000 posts/day × ~1 KB metadata (text, author, timestamp — media excluding) = 25,000,000 KB ≈ 25 GB/day
Over a year: 25 GB × 365 ≈ 9.1 TB/year of post metadata
```

Media (images/video) alag se object storage mein bahut bade scale pe stored hota hai aur is design ki depth se bahar hai — dekho `12_storage_systems.md` — lekin key point yeh hai ki feed khud kabhi media store nahi karta, sirf references.

**Fan-out savings from the hybrid approach**

Assume karo ki celebrity accounts (sabhi accounts ka ek chhota fraction, kaho top 0.01% by follower count) collectively roughly 40% total *follower relationships* account karte hain bhale hi posting accounts ka ek tiny fraction ho — social platforms ke liye ek realistic skew. Celebrity posts ko eager fan-out se hataane se roughly utna hi proportion of fan-out writes hat jaata hai:

```
86,800 fan-out writes/sec (Step 2, naive) × 40% ≈ 34,700 writes/sec avoided by deferring celebrity accounts to read-time
Remaining eager fan-out load: 86,800 - 34,700 ≈ 52,100 writes/sec
```

Yeh abhi bhi ek substantial write load hai, lekin ab yeh ordinary accounts ke long tail se driven hai jinke roughly-bounded follower counts har ek ke pass hain, na ki periodically ek single celebrity post se spike ho jo tens of millions of writes ek burst mein generate karta ho — hybrid approach write-load variance ko flatten karta hai, sirf average ko nahi.

## Step 3: High-Level Design

```text
                         +------------------+
                         |   Post Service    |  (write path)
                         +--------+---------+
                                  |
                        +---------+---------+
                        |                   |
                        v                   v
              +------------------+   +------------------+
              |    Post Store    |   |  "Post Created"   |
              |  (author_id,     |   |  Event (pub/sub)  |
              |   content, ts)   |   +---------+--------+
              +------------------+             |
                        ^                       v
                        |            +------------------------+
                        |            |     Fan-Out Service      |
                        |            |  (async consumer)        |
                        |            +------------+-------------+
                        |                          |
                        |          normal accounts |   celebrity accounts
                        |          (push to every   |   (skip fan-out;
                        |           follower's feed) |    flagged specially)
                        |                          |
                        |                 v                     |
                        |     +----------------------+          |
                        |     |     Feed Store         |          |
                        |     | (per-user precomputed  |          |
                        |     |  sorted list of        |          |
                        |     |  post_id references)   |          |
                        |     +-----------+-----------+          |
                        |                 |                      |
                        |                 v                      |
                        |     +----------------------+           |
                        +---->|     Feed Service       |<----------+
                              |  (read path: merge      |
                              |   precomputed feed +     |
                              |   celebrity follows,     |
                              |   hydrate post content)  |
                              +-----------+-----------+
                                          |
                                          v
                              +----------------------+
                              |       Client (app)     |
                              +----------------------+
```

**Flow**: post create karne se woh ek baar durable Post Store mein likha jaata hai aur ek `post.created` event publish hota hai. Ek async Fan-Out Service us event ko consume karti hai: ek ordinary account ke liye, yeh us post ka reference (`post_id`, `timestamp`) har follower ke precomputed feed list mein Feed Store mein push kar deta hai — yeh woh expensive step hai jo Step 2 mein quantify hua. Ek high-follower ("celebrity") account ke liye, fan-out write time pe deliberately skip kar diya jaata hai (Step 6). Read time pe, Feed Service requesting user ki precomputed feed list fetch karti hai (normal follows ke liye already merged aur sorted), separately us user ke follow kiye hue chand celebrities ke recent posts fetch karti hai, dono ko timestamp se merge karti hai, aur phir har `post_id` reference ko full post content mein hydrate karti hai Post Store se (ya usके saamne ek cache se) client ko page return karne se pehle.

**Key components**:
- **Post Service / Post Store**: durable, authoritative store post content ka — ek post ke liye ek baar likha jaata hai, hydration ke dauran multiple baar read hota hai.
- **Fan-Out Service**: woh async worker jo per-post decide karta hai ki eagerly push karna hai (normal accounts) ya read time tak defer karna hai (celebrity accounts) — hybrid logic yahin rehti hai.
- **Feed Store**: per-user precomputed list of post references, purely fast append aur fast range-read by recency ke liye optimized.
- **Feed Service**: read path — precomputed entries ko celebrity posts ke saath merge karta hai jo live fetch hote hain, content hydrate karta hai, aur result paginate karta hai (Step 6).

**Ek post ko end to end walk through karte hain**: (1) 300 followers wala ek normal user ek post create karta hai; Post Service usse ek baar Post Store mein likhta hai aur `post.created` publish karta hai. (2) Fan-Out Service event consume karta hai, follow graph ke `follower_count` ko is author ke liye check karta hai (celebrity threshold se well under), aur ek `(post_id, created_at)` reference append karta hai har ek 300 followers ke Feed Store entries mein — kuch sau fast writes, asynchronously kiya gaya, taaki post-creation API call khud pehle hi return kar chuki ho isse pehle ki yeh finish ho. (3) Ek follower minutes baad app khoolta hai; Feed Service us follower ki precomputed feed list read karta hai (jisme ab new post ka reference top ke paas hai), separately check karta hai ki follower kisi celebrity account ko follow karta hai ya nahi aur unke kuch most recent posts directly Post Store se fetch karta hai, dono lists ko `created_at` se merge karta hai, har `post_id` ko full content mein hydrate karta hai (post-content cache ke through), aur first page return karta hai. (4) Agar iski jagah author ke 50 million followers hote, toh step (2) entirely skip ho jaata — Fan-Out Service post ko ek flagged celebrity ka belonging mark kar deta aur kuch aur nahi karta — aur step (3) mein har follower ka feed read us celebrity ke recent posts ke against extra live lookup karta apna page assemble karte time.

## Step 4: API Design

**Create a post**
```
POST /posts
{ "user_id": "u_1", "content": "hello world", "media_refs": [] }
→ 201 Created { "post_id": "p_9001", "created_at": "2026-09-13T10:00:00Z" }
```

**Fetch home feed (cursor-paginated)**
```
GET /feed?cursor=eyJ0cyI6MTcyNjIzMDQwMH0&limit=20
→ 200 OK
{
  "posts": [
    { "post_id": "p_9001", "author_id": "u_1", "content": "hello world", "created_at": "..." },
    ...
  ],
  "next_cursor": "eyJ0cyI6MTcyNjIyOTk4MH0"
}
```

**Follow / unfollow**
```
POST /follow   { "follower_id": "u_2", "followee_id": "u_1" } → 204 No Content
DELETE /follow { "follower_id": "u_2", "followee_id": "u_1" } → 204 No Content
```

**Fetch a single post** (clients dwara deep links ke liye use hota hai, aur internally hydration ke liye)
```
GET /posts/{id}
→ 200 OK { "post_id": "p_9001", "author_id": "u_1", "content": "...", "like_count": 42 }
```

**Internal fan-out trigger** (event bus se consume hota hai, ek public endpoint nahi)
```
FanOutService.OnPostCreated(post_id, author_id, created_at)
  → for author_id's followers (if not flagged celebrity): append (post_id, created_at) to each follower's feed list
  → if flagged celebrity: no-op (post picked up at read time instead)
```

## Step 5: Data Model

**Post Store** — NoSQL wide-column/document store (jaise, Cassandra/DynamoDB), partition key = `post_id`:

| Field | Notes |
|---|---|
| `post_id` (PK) | |
| `author_id` | secondary index — "author X ke saare posts" fetch karne ke liye use hota hai celebrity read-time fan-out ke liye |
| `content` | text; media reference hai, inline store nahi |
| `media_refs` | object storage mein pointers |
| `created_at` | |
| `like_count` / `comment_count` | denormalized counters, separate engagement services dwara updated (out of scope) |

NoSQL fit karta hai kyunki access simple key-based lookups (`post_id`) aur author-scoped scans se dominate hoti hai, bahut high write volume pe (25M posts/day) bina posts ke beech kisi relational joins ki zaroorat ke.

**Feed Store** — ek fast in-memory ya wide-column store jo append aur recency ke hisaab se range-read ke liye optimized hai; Redis sorted sets ek natural fit hain: key = `user_id`, members = `post_id`, score = `created_at` (ya usse derive ek monotonic sequence). `ZADD` O(log N) mein ek nayi entry append karta hai; `ZREVRANGE` O(log N + M) mein most recent N entries fetch karta hai. Last ~800 entries per user tak capped hai (Step 2) periodic trimming (`ZREMRANGEBYRANK`) se, kyunki koi product surface ko itni peeche scroll hone wali feed ki zaroorat nahi.

Critically, **feed store sirf references hold karta hai** (`post_id` + `created_at`), kabhi full post content nahi — full content per follower store karne se 9.1 TB/year ka post data average follower count se multiply ho jaayega, ek enormous aur entirely avoidable duplication. Content hamesha Post Store se hydrate hota hai (typically ek cache ke through) read time pe, jo kisi bhi fan-out-heavy system ke liye standard reference-then-hydrate pattern hai.

**Follow graph** — dono directions mein O(1) lookups ke liye do wide-column tables, kyunki "main kisko follow karta hoon" aur "mujhe kaun follow karta hai" dono hot paths hain (pehla read-time celebrity merging ke liye, dusra fan-out ke liye):

| Table | Partition key | Columns |
|---|---|---|
| `following` | `user_id` | un `followee_id`s ki list/set jinhe user follow karta hai |
| `followers` | `user_id` | un `follower_id`s ki list/set jo user ko follow karte hain, plus ek `follower_count` jo celebrity status flag karne ke liye use hota hai |

**User/profile store** — account data, authentication, aur settings ke liye ek conventional relational database (SQL) — comparatively small, relational integrity constraints se benefit karta hai, aur feed jitne extreme-scale hot path pe nahi hai.

**Storage choice justification, summarized**:

| Component | Storage type | Why |
|---|---|---|
| Post content | Wide-column/document NoSQL | Bahut high write volume, simple key-based/author-scoped access, joins nahi chahiye |
| Feed list (references only) | Redis sorted set (ya wide-column, timestamp-clustered) | Massive scale pe fast append + fast recency range-read chahiye |
| Follow graph | Wide-column NoSQL, do tables | Dono directions mein (following/followers) O(1) lookups chahiye |
| User/profile data | Relational (SQL) | Small, structured, integrity constraints se benefit, hot path pe nahi |
| Post media | Object storage | Bade, immutable blobs, referenced hote hain, embedded nahi |

## Step 6: Deep Dive

### Fan-Out-on-Write vs. Fan-Out-on-Read vs. the Hybrid Approach

Yeh poore system ka single most important design decision hai, aur yeh Step 2 mein compute hue 320:1 read:write ratio ka ek direct consequence hai.

**Fan-out-on-write (push model)**: jab ek user post create karta hai, system immediately us post ka ek reference likhta hai har follower ke precomputed feed mein. Feed read karna phir ek already-assembled list ka ek single cheap fetch ban jaata hai.
- *Pros*: feed reads extremely fast hain — sirf ek precomputed list pe ek range-read, jo bilkul is system ki read-latency priority se match karta hai.
- *Cons*: ek high-follower account ka post post-creation time pe writes ka ek enormous burst trigger karta hai — Step 2 ne dikhaya ki ek 50-million-follower account ka post 50 million feed-entry writes generate karta hai. Asynchronously kiya jaaye tab bhi, yeh ek single logical event se ek massive, disproportionate load spike hai, aur iska matlab hai ki system ki total write capacity ka zyadatar hissa accounts ke tiny fraction ke posts ke tiny fraction se consume ho jaata hai.

**Fan-out-on-read (pull model)**: kuch bhi precompute nahi hota. Jab ek user apna feed request karta hai, system har account ke latest posts query karta hai jinhe woh follow karta hai, results ko timestamp se merge karta hai, aur page return karta hai.
- *Pros*: post creation cheap aur constant-cost hai follower count se independent — ek post likhna sirf Post Store mein ek row hai, bas.
- *Cons*: ab har single feed read ko N sources (per followee ek) mein fan out karna padta hai aur unhe live merge karna padta hai — ek user jo kuch sau accounts follow karta hai, uske liye yeh sau queries (ya usse efficient banaya gaya ek scatter-gather system ke against) hain *har* feed load pe, aur is system ka read volume iske write volume ka 320x hai, matlab yeh cost worst possible multiplier pe pay hoti hai.

**Hybrid approach — jo real systems (Twitter/X, Instagram, Facebook) actually karte hain**: overwhelming majority of accounts ke liye fan-out-on-write use karo (normal follower counts, jahan eager fan-out cheap hai aur reads fast rehte hain), lekin specifically celebrity/high-follower accounts ke liye fan-out-on-read pe switch karo (ek threshold, e.g. kuch tens of thousands se zyada followers wale accounts, follow graph ke `follower_count` mein flagged). Jab ek celebrity post karta hai, Fan-Out Service write time pe kuch nahi karta — millions of feeds ko koi eager push nahi. Iski jagah, read time pe, Feed Service additionally check karti hai ki given user kaunse chand celebrities follow karta hai (chhota kyunki relatively kam celebrity accounts hain aur koi bhi ek user unme se sirf handful follow karta hai, bhale hi ek celebrity individually millions of followers rakhta ho) aur unke most recent posts directly response mein merge kar deta hai precomputed feed ke saath.

Yehi key insight hai jo interviewers dhoondh rahe hote hain: **celebrity problem ki expensive direction ko invert kiya jaata hai isse invert karke ki kaun ispay pay karta hai**. Ek celebrity ke millions followers hain lekin usi celebrity ko khud bahut kam celebrities follow karte hain, jinhe fan-out karne ki zaroorat nahi — jo cost "ek post × millions of follower writes" hoti, woh "ek post, aur phir har follower ka occasional feed read thoda extra kaam karta hai handful of celebrity accounts merge karne mein jinhe woh follow karta hai" ban jaati hai. Total system-wide cost dramatically kam hai kyunki yeh many cheap read-time merges mein thinly distributed hai, ek enormous write-time burst mein concentrated hone ki jagah.

| | Fan-out-on-write | Fan-out-on-read | Hybrid |
|---|---|---|---|
| Write cost | High, follower count ke proportional | Constant, follower count se independent | Celebrities ke liye constant, baaki sabke liye proportional |
| Read cost | Bahut low — single precomputed list fetch | High — har followee se live merge | Low — precomputed list + chhota celebrity merge |
| Worst case | Ek single celebrity post write load ko enormously spike karta hai | Thousands follow karne wala user har single read ko strain karta hai | Dono side bounded hain celebrity threshold se |
| Is system ke 320:1 read:write ratio se match karta hai? | Sirf non-celebrity accounts ke liye | Nahi — majority-traffic path pe expensive side pay karta hai | Haan — common case ke liye cheap reads, rare extreme case ke liye cheap writes |

**Celebrity threshold** khud (woh follower count jiske upar ek account read-time fan-out pe switch karta hai) ek tunable configuration value hai, koi fixed constant nahi — itna high set kiya jaata hai ki yeh sirf accounts ka ek chhota fraction capture kare (per user read-time merge cost ko bounded rakhte hue, kyunki zyadatar users kisi bhi reasonable threshold se upar handful accounts hi follow karte hain), lekin itna low ki koi single eager fan-out burst write capacity ko meaningfully na dent kare.

### Feed Storage Model

Precomputed feed deliberately **references ki ek list** hai (`post_id`, `created_at`), full post content ki denormalized copy nahi, ek aisi store mein stored jo bahut fast append aur bahut fast recency-ordered range reads ke liye chosen hai (Redis sorted sets, ya ek wide-column store clustering-key-by-timestamp semantics ke saath). Read time pe, Feed Service feed list se `post_id`s ka batch leta hai aur unhe **hydrate** karta hai — full content lookup karta hai — Post Store se, almost hamesha ek cache layer ke through (`05_caching.md`), kyunki same popular posts different users ke feed reads mein baar baar hydrate hote hain aur ek ideal caching target hain (individual post level pe bhi high read-to-write ratio hai, sirf feed level pe nahi).

Full content ki jagah references store karna hi hai jo Step 2 ke 9.6 TB feed-store number ko chhota rakhta hai us cost ke muqable jo har follower ke liye full post content duplicate karne se aati — aur iska matlab yeh bhi hai ki ek post ka edit ya deletion turant har jagah reflect hota hai (content ka sirf ek copy hai, Post Store mein), har follower ke feed copy mein propagate karne ki zaroorat nahi.

### Feed Ranking

Ek pure chronological feed (newest first) sabse simple correct baseline hai aur woh hai jo upar ka design throughout assume karta hai — precomputed feed list `created_at` se sorted hai, bas. Real large-scale products iski jagah ek **relevance/engagement score** se rank karte hain (ek function jo predict karta hai ki user kitni likelihood se given post pe engage karega, jisme signals shamil hote hain jaise poster ka viewer se relationship strength, post recency, historical engagement patterns, aur content type) raw recency ki jagah, jo ek machine-learning model se compute hota hai engagement data pe trained.

Yeh interview mein explicitly mention karne layak hai design ke natural evolution ki tarah, lekin yahan intentionally brief rakha gaya hai — ranking model khud (feature engineering, training pipeline, online scoring infrastructure) ek bada, separate ML-systems problem hai, ek systems design interview ki depth ke liye out of scope. Ek architecturally relevant point yeh hai ki ranking, agar add ho, toh read time pe ek **re-sort step** ki tarah hoti hai upar wale fan-out/hydration pipeline se assemble hue candidate set ke upar (chahe precomputed feed se ho, celebrity merge se, ya dono se) — yeh jo dikhaya jaa raha hai uska *ordering* change karta hai, underlying fan-out/storage architecture nahi jo pehli jagah candidate set produce karta hai.

### Cursor-Based Pagination for Infinite Scroll

**Offset-based pagination yahan kyun break hota hai**: ek naive "posts 20-40 de do" (`OFFSET 20 LIMIT 20`) approach assume karta hai ki underlying list page requests ke beech stable hai. Lekin ek feed active concurrently insert ho raha hota hai — jinhe user follow karta hai unke naye posts list ke top pe land ho sakte hain user ke first page load aur unke next scroll-triggered fetch ke beech. Agar page 2 ko "pehle 20 skip karo, next 20 do" ki tarah request kiya jaaye aur 3 naye posts top pe insert hue hain page 1 load hone ke baad se, offset 3 se shift ho jaata hai, aur user ya toh 3 posts repeated dekhta hai (unhe position 18-20 se position 21-23 mein push kiya gaya, jise offset-based page 2 ab dobara include kar dega) ya, direction pe depend karke, silently 3 posts entirely skip kar deta hai. Yeh ek real, frequently-hit bug class hai kisi bhi offset-paginated feed mein concurrent writes ke neeche, ek theoretical concern nahi.

**Fix — cursor-based pagination**: ek position (ek offset) ki jagah, client ek opaque cursor bhej deta hai jo apne last received item pe ek **stable sort key** se derive hua hai — yahan, previous page ke last post ka `created_at` timestamp (ya ek equivalent monotonic sequence number). Next page ka query "cursor ke timestamp se strictly older wale next 20 posts do" ban jaata hai, jo correct hota hai chahe beech mein kitne bhi naye posts insert hue hon, kyunki query ek specific post ki timeline mein position se anchored hai, ek numeric offset se nahi jo list badhne pe shift hota hai. Yehi reason hai ki Step 4 ka API ek page number ki jagah ek opaque `next_cursor` return karta hai, aur kyun Feed Store ki underlying structure (timestamp se score kiya Redis sorted set, ya ek timestamp-clustered wide-column table) specifically isliye choose ki gayi hai ki "X se older entries do" ek efficient, native range query ho, kuch bolt-on kiya hua nahi.

## Step 7: Bottlenecks & Trade-offs

- **Celebrity problem sabse pehli cheez hai jo hybrid design ke bina break ho jaata hai** — Step 2 ka 50-million-follower example dikhaata hai ki ek naive fan-out-on-write system apni write capacity ka overwhelming majority posts ke ek tiny fraction pe spend karta hai; hybrid approach ek optional optimization nahi hai, yeh system ke is scale pe function karne ke liye close to load-bearing hai.
- **Bahut active followers ke liye feed store hot partitions** — ek user jo thousands of accounts follow karta hai (bina kisi ek celebrity ke bhi) apni ek feed-list key mein bhi disproportionate volume of fan-out writes receive karta hai, jo us specific key ko ek write hotspot bana sakta hai otherwise-even sharding ke neeche bhi; mitigate hota hai capping karke ki ek single user kitne accounts follow kar sakta hai, ya agar zaroorat ho toh ek single user ki feed list ko multiple keys mein shard karke.
- **Consistency lag ek real, accepted user-visible effect hai**: "post created" aur "post follower ke feed mein appear hota hai" (Step 3 ka async fan-out) ke beech ka gap matlab hai ki ek follower exact wrong moment pe refresh kar sakta hai aur abhi just-published post na dekhe — stated non-functional requirement (eventual consistency) ke hisaab se acceptable hai, lekin explicitly ek trade-off ki tarah naam lena chahiye, glossing over nahi.
- **Ek post viral hone se ek read-side hot-key problem create hota hai, write-side nahi**, ek baar hybrid design in place ho jaaye toh — bahut saare users simultaneously same `post_id` ko Post Store se hydrate kar rahe hain exactly wahi hot-key caching scenario hai jo `06_distributed_cache.md` mein describe hua hai, aur usi tarah mitigate hota hai (hot posts ka aggressive caching, potentially ek local L1 cache layer).
- **Storage do axes pe independently unbounded badhta hai** — Post Store total posts created ke saath badhta hai (9.1 TB/year, Step 2) aur Feed Store total (user × follow-count) pairs ke saath badhta hai; dono ko independent capacity planning aur independent sharding strategies chahiye, kyunki inhe different underlying growth rates drive karte hain (post volume vs. social-graph density).
- **Ranking (agar add ho) read-path simplicity ko engagement ke liye trade karta hai** — ek chronological feed trivially reason aur debug kiya ja sakta hai; ek ranked feed read path ke latency budget mein poora ek ML scoring step add karta hai aur "mujhe yeh post kyun dikha" explain karna kaafi harder bana deta hai, jo ek real product aur engineering cost hai, sirf infrastructure ki nahi.

**Bottleneck-to-mitigation summary**:

| Bottleneck | Mitigation | Cost accepted |
|---|---|---|
| Celebrity post fan-out burst | Hybrid: high-follower accounts ke liye fan-out-on-read | Celebrities ke followers ke liye per request thoda extra read-path work |
| Feed-store hot key (user following very many accounts) | Follow count cap karo, ya per read live-merge sources shard/limit karo | Reader ko bahut-broad follow graphs ka ek bounded subset dikhta hai |
| Viral post read-side hot key | Hot posts ka aggressive caching, optional local L1 cache | Rapidly-changing engagement counts pe brief staleness |
| Offset pagination breaking under concurrent writes | Ek stable sort field pe keyed cursor-based pagination | Thoda zyada complex client-side cursor handling |
| Unbounded storage growth on two independent axes | Post Store vs. Feed Store ke liye independent capacity planning/sharding | Ek ki jagah do scaling strategies operate karni padti hain |

## Follow-up Questions an Interviewer Might Ask

**Ephemeral content jaise Stories ko kaise support karoge jo 24 hours baad disappear ho jaate hain?**
Stories ko ek structurally separate feed type ki tarah treat karo apni khud ki precomputed list ke saath (same fan-out mechanics, kyunki Stories typically celebrity-scale problems ke muqable comparatively kam viewers follow karte hain) lekin Post Store entry aur feed reference dono pe ek TTL ke saath, taaki expiry automatically enforce ho, ek explicit deletion sweep ki zaroorat na pade.

**Ek user kisi ko unfollow karta hai — kya design ko retroactively us person ke old posts ko already-fanned-out feed se remove karna chahiye?**
Generally nahi practically — kisi specific author ke post references ko ek follower ki feed list se scan aur prune karne ki operational cost benefit ke muqable high hai, isliye zyadatar systems simply previously fanned-out posts ko naturally age out hone dete hain (woh aur neeche scroll hote hain aur eventually retained ~800-entry window se bahar gir jaate hain, Step 2) yeh ensure karte hue ki unfollowed account se koi *new* posts aage fan out na ho.

**Ek user jo unusually large number of accounts follow karta hai (kaho, 10,000), jo unke reads ke liye fan-out-on-read merge step ko strain karta hai, kaise handle karoge?**
Same threshold-based hybrid logic follow-side pe reverse mein apply karo: ek user jo extreme number of accounts follow karta hai uske liye, zyada precomputation ki taraf bias karo (ya cap karo ki read time pe kitne follows live contribute karte hain, e.g., sirf most recently active N followees merge karo) instead of thousands of live sources har read pe merge karne ke — yeh celebrity problem ka ek symmetric version hai, poster-side ki jagah reader-side follow-graph density se driven.

**Ek naye user ke liye ek reasonable feed kaise generate karoge jiska koi follow history nahi hai?**
Ek separate cold-start path pe fall back karo (curated ya popularity-ranked set of posts, trending/popular content ke against fan-out-on-read jaisa) normal precomputed-feed path ki jagah, kyunki naye user ki feed list genuinely empty hai aur usme hydrate karne ke liye kuch nahi hai — yeh ek distinct code path hai, main pipeline ko gracefully handle karni padne wali edge case nahi.

**Engagement (likes/comments) near-real-time mein kaise update honge bina poore post ko re-fan-out kiye?**
Engagement counters ko Post Store record pe ek separately-updated field ki tarah rakho (denormalized `like_count`/`comment_count`, ek dedicated engagement service se increment hote hue) na ki kuch jise feed-fan-out pipeline touch kare at all — kyunki feed store sirf ek `post_id` reference hold karta hai, ek updated like count automatically agli baar us post ke hydrate hone pe reflect ho jaata hai, kisi bhi follower ki feed list ko touch kiye bina.

**Global users ke liye low latency ke saath isse multiple regions mein kaise replicate karoge?**
Post Store aur Feed Store ko per-region partition/replicate rakho jahan users read karte hain, ek post ko different region ke follower tak pahunchne ke liye cross-region propagation lag accept karte hue (intra-region already existing async fan-out lag ke upar layered) usi eventual-consistency trade-off ke extension ki tarah jo already Step 1 mein accept hua, ek fundamentally new consistency requirement ki tarah nahi.

**Celebrity threshold ko practically kaise decide karoge, aur kya kabhi ek account ko dono fan-out strategies ke beech move karoge?**
Isse empirically observed follower-count distribution se set karo (jaise, woh point jiske baad eager fan-out cost per post fan-out pipeline capacity ko materially affect karta hai) aur continuously monitor karo, ek one-time constant ki tarah nahi, kyunki accounts time ke saath threshold cross karte hain (ek rapidly growing account) aur fan-out service ko ek clean transition path chahiye — typically, ek baar account threshold cross kar le, uske future posts ke liye eager fan-out stop kar do aur previously-fanned-out entries ko naturally follower ke feed windows se age out hone do, ek disruptive backfill/removal try karne ki jagah.
