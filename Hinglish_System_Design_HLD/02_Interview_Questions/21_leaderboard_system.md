# Design a Real-Time Leaderboard System

## Problem Statement

"Design a real-time leaderboard for a mobile game with millions of players — think a battle royale or a casual puzzle game. Players earn scores, and we need to show each player their global rank, a top-100 list, and 'nearby' players (a few ranks above and below them). Scores update constantly — every match that finishes changes at least two players' standings. How would you build this so it stays fast and correct as the player base and update rate grow?"

Yeh ek classic system design question hai kyunki naive relational approach — `SELECT ... ORDER BY score DESC` — demo mein toh fine chalta hai lekin production mein almost immediately gir jaata hai. Interviewer actually yeh test kar raha hota hai ki aapko pata hai ki kab ek specialized data structure (sorted set) use karna chahiye instead of ek general-purpose database, aur kya aap ek inherently "global" ranking problem ko shard karne ke baare mein reason kar sakte ho.

## Step 1: Clarify Requirements

**Functional Requirements**
- Har game/match ke baad player ka score update karna (increment ya absolute set).
- Player ka current global rank aur score retrieve karna.
- Top-N players (e.g. top 100) globally retrieve karna.
- Kisi given player ke "around" players retrieve karna (e.g. 5 ranks upar, 5 neeche) — yeh "nearby leaderboard" view hai.
- Multiple leaderboards support karna: global, per-region, per-game-mode, weekly/seasonal (resets), friends-only.
- Ties deterministically aur consistently break honi chahiye (page loads ke beech koi flicker nahi hona chahiye).

**Non-Functional Requirements**
- Scale: 50 million monthly active players, 5 million daily active, peak concurrency 500K players jo active matches mein hain.
- Write rate: har finished match 2+ player scores update karta hai. Assume karo 200K matches/minute peak par → ~400K score updates/minute (~6,700 writes/sec) peak par, popular event times ke aas paas bursty.
- Read rate: leaderboard views (top-100, own-rank, nearby) writes se bahut zyada request kiye jaate hain — assume karo 20:1 read:write ratio, toh peak par ~130K reads/sec.
- Latency: rank/score lookups aur top-N ko 50ms p99 se kam mein return hona chahiye — leaderboards usually match ke baad player jo UI ko actively ghoor raha hota hai usi par render hote hain.
- Consistency: eventual consistency acceptable hai — rank ka score-update ke kuch seconds baad tak stale rehna theek hai. Jo NOT acceptable hai woh ek rank computation hai jo internally inconsistent ho (e.g. do players ko incorrectly same rank dikhna, ya ranks jo sorted order se match na karein).
- Availability: leaderboard reads available rehni chahiye chahe score-write ingestion temporarily degraded ho (players ko apna ek match ka score turant dikhne se zyada leaderboard dekhna matter karta hai).
- Durability: score history silently lose nahi honi chahiye — even though live ranking structure ek in-memory cache ho sakta hai, uske peeche ek durable system of record hona chahiye.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 50M total registered players, 5M DAU.
- Peak: 6,700 score writes/sec, 130K leaderboard reads/sec (upar se).
- Har leaderboard entry: player_id (8 bytes), score (8 bytes as a double/long), plus sorted-set structure mein overhead.

**Storage for the live ranking structure (in-memory sorted set)**
- 5M active players "live" global leaderboard mein kisi bhi time track kiye jaate hain (inactive players exclude/archive kiye ja sakte hain).
- Ek sorted-set implementation (skip list) roughly 80-100 bytes per element cost karta hai including pointers, level array, aur member string/ID — safe rehne ke liye 100 bytes/entry maan lo.
- 5M entries x 100 bytes ≈ 500 MB ek global leaderboard ke liye.
- Agar hum, say, 50 regional leaderboards + 10 game-mode leaderboards + ek weekly-seasonal leaderboard maintain karte hain (62 total structures, though har ek 5M ka subset hai, har baar full duplicate nahi) — total working set comfortably low single-digit GB range mein hai. Yeh ek modestly sized Redis cluster mein fit ho jaata hai (e.g. 3-6 nodes of 8-16GB each, growth ke liye room aur headroom ke saath).

**Durable storage (system of record, e.g. player match/score history)**
- 400K score-changing events/minute x 60 x 24 ≈ 576M events/day.
- Har event record (player_id, match_id, score_delta, timestamp, game_mode) ≈ 64 bytes.
- 576M x 64 bytes ≈ 37 GB/day raw event data ka. Ek saal mein (compression aur eventual archival/cold storage of old seasons ke saath) yeh manageable hai standard object storage / wide-column store par, petabyte scale se kaafi kam.

**Bandwidth**
- Har leaderboard read response (top-100 payload) ≈ 100 entries x ~40 bytes (rank, player_id, name, score) ≈ 4 KB.
- 130K reads/sec x 4 KB ≈ 520 MB/sec agar har read top-100 fresh fetch kare — isi wajah se top-N response cache karna (Step 6) itna important hai; un 130K reads mein se zyadatar ko cache hit karna chahiye, sorted set ke against recompute nahi.

**Conclusion of the estimation**: live ranking structure poori tarah memory mein fit ho jaata hai handful of nodes ke across, toh core design decision hai "ek in-memory sorted-set structure ko rankings ke liye source of truth use karo, backed by ek durable event log/database score history aur disaster recovery ke liye," na ki "hum ek multi-terabyte table ko kaise shard karein."

## Step 3: High-Level Design

**Core components**
- **Game/Match Service**: jab bhi match end hota hai, ek score-update event emit karta hai.
- **Score Ingestion Service**: score-update events consume karta hai, unko validate karta hai (anti-cheat sanity checks), aur update ko leaderboard store par apply karta hai.
- **Leaderboard Store (Redis Sorted Set cluster)**: hot, in-memory, incrementally-maintained ranking structure. Ek sorted set per leaderboard (global, per-region, per-mode, per-season).
- **Durable Score Store (e.g. Cassandra/DynamoDB)**: score events ki append-only history, source of truth agar sorted set rebuild karna ho jab Redis data lose ho jaaye, aur analytics/anti-cheat auditing ke liye.
- **Leaderboard Read API**: top-N, player-rank, aur nearby-rank queries serve karta hai, backed by ek read-through cache Redis ke aage hottest queries (top-100 global) ke liye.
- **Real-Time Notification Service**: connected clients ko rank-change events push karta hai (Step 6).
- **Message Queue** (e.g. Kafka): match completion ko leaderboard update se decouple karta hai, write bursts absorb karta hai, aur event ko dono Score Ingestion Service aur durable store writer tak fan out karta hai.

**Data flow**
1. Match end hota hai → Game Service `ScoreUpdated{player_id, leaderboard_ids[], delta}` Kafka par publish karta hai.
2. Score Ingestion Service event consume karta hai, Redis mein relevant sorted set(s) ke against ek atomic increment issue karta hai (e.g. `ZINCRBY`).
3. Same Kafka topic ka ek separate consumer raw event ko durable store mein likhta hai history/audit/rebuild purposes ke liye — yeh parallel mein hota hai, hot path ko block nahi karta.
4. Client `GET /leaderboard/global/top?n=100` request karta hai → cache hit hota hai; miss par, Redis `ZREVRANGE` query karta hai aur cache ko short TTL ke saath repopulate karta hai.
5. Client `GET /leaderboard/global/rank/{player_id}` request karta hai → Redis `ZREVRANK` + `ZSCORE`, typically cache nahi hota (per-user, low cache hit value) but O(log n) ki wajah se directly serve karne ke liye kaafi cheap hai.
6. Rank-change events optionally subscribed clients ko ek persistent connection ke through push kiye jaate hain.

```text
                                +----------------------+
  Match Service  ---publish--->|   Kafka: score-events |
                                +----------+-----------+
                                           |
                     +---------------------+----------------------+
                     |                                            |
                     v                                            v
        +------------------------+                  +---------------------------+
        | Score Ingestion Service|                  | Durable Store Writer       |
        | (ZINCRBY / ZADD)       |                  | (append to Cassandra/S3)   |
        +-----------+------------+                  +---------------------------+
                     |
                     v
     +-------------------------------+
     | Redis Sorted Set Cluster       |
     |  - leaderboard:global          |
     |  - leaderboard:region:<r>      |
     |  - leaderboard:mode:<m>        |
     |  - leaderboard:season:<s>      |
     +---------------+----------------+
                      |
        +-------------+--------------+
        |                            |
        v                            v
+----------------+          +--------------------+
| Response Cache  |         | Leaderboard Read API|
| (top-N, hot     |<--------+ (rank, nearby, top) |
| queries)        |         +----------+----------+
+----------------+                     |
                                        v
                              +--------------------+
                              | Client (poll or     |
                              | WebSocket push)      |
                              +--------------------+
```

## Step 4: API Design

**`POST /internal/scores/update`** (Score Ingestion Service ke dwara call kiya jaata hai, public nahi hai)
```
Request:  { "player_id": "p123", "leaderboard_id": "global", "delta": 150, "match_id": "m987" }
Response: { "new_score": 48250, "new_rank": 1204 }
```

**`GET /leaderboard/{leaderboard_id}/top?n=100`**
```
Response: {
  "leaderboard_id": "global",
  "generated_at": "2026-09-13T10:00:00Z",
  "entries": [
    { "rank": 1, "player_id": "p001", "display_name": "Nova", "score": 982340 },
    { "rank": 2, "player_id": "p045", "display_name": "Kite", "score": 981900 }
  ]
}
```

**`GET /leaderboard/{leaderboard_id}/rank/{player_id}`**
```
Response: { "player_id": "p123", "rank": 1204, "score": 48250, "percentile": 97.6 }
```

**`GET /leaderboard/{leaderboard_id}/nearby/{player_id}?radius=5`**
```
Response: {
  "player_id": "p123",
  "entries": [
    { "rank": 1199, "player_id": "p771", "score": 48400 },
    { "rank": 1200, "player_id": "p552", "score": 48380 },
    { "rank": 1204, "player_id": "p123", "score": 48250 },
    { "rank": 1205, "player_id": "p900", "score": 48200 }
  ]
}
```

**`WS /leaderboard/{leaderboard_id}/subscribe/{player_id}`**
```
Server push on rank change:
{ "type": "rank_change", "old_rank": 1210, "new_rank": 1204, "score": 48250 }
```

## Step 5: Data Model

**Live ranking structure — Redis Sorted Set**
- Key: `leaderboard:global` (ya `leaderboard:region:eu-west`, etc.)
- Member: `player_id`
- Score: player ka numeric score (natively sort key ke roop mein use hota hai).
- Directly Redis ke ZSET commands par map hota hai: writes ke liye `ZADD`/`ZINCRBY`, top-N ke liye `ZREVRANGE`, player ka rank ke liye `ZREVRANK`, "nearby" ke liye `ZRANGEBYSCORE`/`ZRANGE ... REV ... LIMIT` ek rank ke around.
- Yeh ek key-value / in-memory data structure store hai, specifically isliye choose kiya gaya kyunki yeh sort order ko incrementally maintain karta hai — right tool jab access pattern ho "always sorted, constantly updated," jo ek relational B-tree index technically support toh karta hai lekin is update rate aur rank-position queries ke liye bahut higher constant-factor cost pay karta hai.

**Durable score history — wide-column store (e.g. Cassandra) ya ek append-only log**
```
Table: score_events
  player_id       (partition key)
  event_timestamp (clustering key, descending)
  match_id
  leaderboard_id
  delta
  resulting_score
```
- Isliye choose kiya kyunki writes append-only hain aur extremely high volume, reads typically "all events for a player" hote hain (partition-aligned), aur yeh rebuild source bhi doubles hota hai agar ek Redis node lose ho jaaye — events ko score order mein replay karke ek sorted set reconstruct karo.

**Player profile metadata — relational (e.g. Postgres)**
```
Table: players
  player_id (PK)
  display_name
  region
  created_at
```
- Denormalized display name aur avatar API layer par leaderboard read responses mein join kiye jaate hain (ya rank data ke saath cache kiye jaate hain) instead of sorted set mein hi redundantly store karne ke, kyunki profile data independently change hota hai aur score events ke relative low-cardinality hai.

## Step 6: Deep Dive

### 6.1 Why `ORDER BY score DESC LIMIT N` Collapses at Scale

Ek relational table `score` par ek B-tree index ke saath technically "top 100" ko reasonably fast answer kar sakta hai — index already sorted hai, toh `LIMIT 100` isolation mein cheap hai. Problem yeh hai ki is system mein iske around kya surround karta hai:
- **Update volume**: ~6,700 writes/sec mein se har ek `UPDATE players SET score = score + ? WHERE player_id = ?` hai, jisme B-tree index ko us position par rebalance/re-insert karna padta hai — ek `O(log n)` operation, complexity mein ek sorted-set update jaisa, EXCEPT yeh MVCC/transaction overhead, WAL writes, aur ek general-purpose OLTP engine par lock contention ke saath compete kar raha hai jo is single access pattern ke liye optimize nahi hai.
- **Rank computation is the real killer**: "is player ka rank kya hai" SQL ke through pana ya toh `SELECT COUNT(*) FROM players WHERE score > ?` chahiye (ek full scan ya index range-scan potentially millions of rows ke across, har single request par recompute hota hai) ya ek separate rank column maintain karna jo har player ke liye recalculate hona chahiye jiska score change hone se neeche hai — ek operation jo worst case mein O(n) rows touch karta hai per single score update (imagine karo last-place player suddenly sabse zyada points score kar de; sabka rank shift ho jaayega).
- Ek sorted-set/skip-list structure dono problems ko sidestep karta hai: yeh purpose-built hai elements ko incrementally ordered rakhne ke liye jab insert/update ho (`O(log n)` per update, other elements ki koi cascading re-numbering nahi) aur "rank of X" ko directly (`O(log n)`) answer karne ke liye by skip-list levels walk karke, rows count karne ke bajaye.
- Practical rule of thumb: ek relational table ke liye reach karo jab flexible queries aur strong transactional guarantees relatively slow-changing data ke upar chahiye ho; ek sorted-set-style structure ke liye reach karo jab access pattern ho "constantly changing values, always need them ordered, always need positional rank" — leaderboards baad ke case ka canonical example hain.

### 6.2 Getting a Single Player's Rank Efficiently

"Mera rank kya hai" ka naive relational approach hai `SELECT COUNT(*) FROM leaderboard WHERE score > my_score` — ek full scan/aggregate jo table badhne ke saath slower hota jaata hai aur har request par scratch se re-run hona padta hai, chahe overall distribution mein pichli baar se kuch bhi change na hua ho.

Ek sorted-set structure ise natively solve karta hai: `ZREVRANK leaderboard:global player_id` skip list ke level pointers ko walk karta hai, jo subtree/span sizes store karte hain, aur `O(log n)` mein 0-indexed rank return karta hai — koi scanning nahi, ek-ek row count karne ki zaroorat nahi. Yeh sabse bada reason hai ek leaderboard ke liye is data structure ko ek plain sorted list ya ek relational index ke upar prefer karne ka: rank lookup aur top-N retrieval dono cheap hain, aur incremental update bhi, same structure par.

### 6.3 Sharding and Computing a Global Top-N Across Shards

Jab ek single leaderboard structure ek node ke liye bahut bada ho jaata hai (ya, yahan zyada commonly, jab itni saari distinct leaderboards ho jaayein — per-region, per-mode, per-season — ki ek single Redis node ki memory ya throughput bottleneck ban jaaye), data ko shard karna padta hai.

Zyadatar sub-leaderboards ke liye natural partitions exist karte hain: per-region leaderboards region se trivially shard ho jaate hain, per-mode leaderboards mode se. Har ek entirely ek Redis node/shard par live karne ke liye kaafi chhota hai, toh zyadatar leaderboard queries kabhi shard boundary cross hi nahi karte.

Genuinely hard case ek single GLOBAL top-N hai ek player base ke across jo itna bada hai ki khud global leaderboard bhi shard karna pade (e.g. hash-partitioned by player_id N Redis shards ke across, kyunki koi single "region" poora answer nahi hai). Ab "top 100 globally" ek `ZREVRANGE` call se answer nahi ho sakta. Fix same retrieve-then-merge pattern hai jo cross-shard search aur cross-shard driver matching mein bhi use hota hai is system design series mein elsewhere:
1. `ZREVRANGE shard_i 0 99` sab N shards ko parallel mein fan out karo — har ek apna local top-100 candidates return karta hai.
2. N x 100 candidate lists ko merge karo (ek simple k-way merge score par, kyunki har shard ki sublist already sorted hai) aur merged, much smaller candidate set se global top 100 lo.
3. Yeh isliye work karta hai kyunki true global top-100 must be a subset of the union of every shard's local top-100 — ek player jo apne shard ke top 100 mein nahi hai woh global top 100 mein kabhi nahi ho sakta (unke apne shard mein already at least 100 players hain higher score ke saath).
- Yeh merge step cheap hai (kuch sau elements) ek naive global sort ke comparison mein, aur yeh expensive part (per-shard sorted retrieval) ko nodes ke across parallelize karta hai.
- Same technique "nearby rank" queries ke liye bhi generalize hota hai once sharded, though yeh messier hai — ek globally-correct rank compute karne ke liye sab shards ke across counts-above-score sum karna padta hai (`ZCOUNT` per shard, summed), sirf candidate lists merge karna kaafi nahi.

### 6.4 Handling Ties with a Stable Secondary Sort Key

Agar do players ka literally identical score hai, naive tie handling visible, confusing flicker cause karta hai — ek player ka rank page loads ke beech change hota hua dikhta hai even though unka score change nahi hua, sirf equal-score entries ke underlying structure mein nondeterministic ordering ki wajah se.

Fix ek deterministic composite sort key hai: purely `score` par sort karne ke bajaye, `(score, tiebreak_value)` par sort karo jahan `tiebreak_value` kuch stable aur meaningful ho — commonly "timestamp jab yeh score reach hua" (earlier achiever higher rank karta hai), encoded aisi ki yeh primary score ke saath ek single numeric sort key mein correctly compose ho jaaye. Ek common trick specifically Redis ZSETs ke saath: kyunki ZSET scores floating point hote hain, composite key ko `score * 10^13 - timestamp` (ya similar) encode karo, taaki ek single numeric comparison capture kar le "higher score wins; among equal scores, earlier timestamp wins" bina secondary query ki zaroorat ke. Yeh strict total order guarantee karta hai, toh ranks kabhi flicker nahi karte same underlying state ke against do requests ke liye.

### 6.5 Real-Time Rank-Change Push vs Polling

Ek player ke liye jo actively ek live leaderboard dekh raha hai (e.g. ek tournament ke closing minutes ke dauran), instant rank-change feedback matter karta hai. Do approaches, explicit trade-off ke saath:

**Persistent connection (WebSocket/SSE, `03_networking_and_apis.md` ke according)**: server ek `rank_change` event push karta hai ek subscribed client ko jaise hi unka rank shift hota hai. Pros: true real-time feel, jab kuch change nahi hua toh koi wasted requests nahi. Cons: har actively-watching client ke liye ek open connection hold karna scale par expensive hai — sau-hazaaron concurrent connections ko ek connection-management layer chahiye (e.g. WebSocket gateway servers ka ek fleet, sticky routing, aur score-update path se lekar jo bhi gateway instance ek given player ka connection hold karta hai wahan tak fan-out mechanism) — stateless HTTP se meaningfully zyada infrastructure aur operational complexity.

**Polling**: client `GET /leaderboard/.../rank/{player_id}` har kuch seconds mein re-request karta hai. Pros: stateless, trivially horizontally scalable, wahi cached/cheap read path reuse karta hai jo baaki sab kuch use karta hai, aur operationally kaafi simpler hai. Cons: staleness poll interval tak bounded hai (e.g. up to 3-5 seconds ka lag), aur jab kuch change nahi hua toh wasted requests (zyadatar polls unchanged rank hi return karte hain).

Right choice depend karta hai stakes par: ek competitive esports tournament ki live standings screen push ke connection overhead ko justify karti hai. Ek casual mobile game ka "check your rank" screen, jo match ke baad briefly view hota hai aur continuously stare nahi kiya jaata, poll every few seconds se ya even ek single on-demand fetch se well served hai — persistent connections ka cost millions-of-players scale par marginal UX gain se justify nahi hota. Ek middle ground jo many production systems use karte hain: idle rehte hue poll karo, push connection sirf un players ke liye upgrade karo jo actively ek live/contested leaderboard screen dekh rahe hain (e.g. tournament ka final match), expensive infrastructure ko sirf un moments tak scoped rakhte hue jahan yeh actually matter karta hai.

## Step 7: Bottlenecks & Trade-offs

- **Redis as a single point of contention per shard**: even sharded, ek single hot leaderboard (e.g. ek viral event ka global leaderboard) write load ko ek shard par concentrate kar sakta hai agar partitioning naive ho. Mitigation: player_id ke ek well-distributed hash se partition karo instead of kuch bhi jo activity level se correlated ho, aur per-shard QPS monitor karo hot shards ko rebalance karne ke liye.
- **Memory pressure from too many leaderboard variants**: per-region x per-mode x per-season combinations quickly multiply karte hain. Mitigation: old seasonal leaderboards ko TTL/archive karo hot Redis tier se durable store mein once season end ho jaaye aur actively query na ho raha ho; sirf currently-active leaderboards ko hot memory mein rakho.
- **Cache staleness vs load trade-off on top-N reads**: top-100 response cache karna Redis load ko dramatically reduce karta hai (upar ke bandwidth estimate ke according) but iska matlab hai displayed top-100 actual state se cache TTL (e.g. 1-5 seconds) tak lag kar sakta hai. Yeh ek accepted trade-off hai given non-functional requirement ki eventual consistency is use case ke liye fine hai.
- **Anti-cheat and score validation**: ek client-reported score directly trust nahi kiya ja sakta; Score Ingestion Service ko deltas ko plausible bounds ke against validate karna hoga (e.g. per-match maximum possible score) apply karne se pehle, kyunki ek compromised client otherwise trivially leaderboard top kar sakta hai. Yeh validation write path mein latency add karta hai but ek competitive leaderboard ke liye non-negotiable hai.
- **Disaster recovery**: agar ek Redis node/shard lose ho jaaye, live ranking structure durable event log se rebuild honi chahiye — isliye durable store parallel mein exist karta hai even though yeh hot read path par nahi hai. Ek large shard ke liye rebuild time (millions of events replay karna) ek real operational concern hai aur periodic snapshotting (Redis ka apna RDB/AOF persistence) ke liye argue karta hai external durable log ke saath saath, instead of full event replay ko hi recovery path maanne ke.

## Follow-up Questions an Interviewer Might Ask

1. **"Aap 'friends leaderboard' — sirf player ki friend list ke andar ranking — kaise support karoge?"** Yeh ek static sorted set as precomputed per player nahi kiya ja sakta (too many friend-lists, too much duplication). Instead, friend list fetch karo, phir ek sorted-set intersection-like approach use karo: har friend ka score `ZSCORE`/`ZMSCORE` se global leaderboard ke against query karo aur resulting small set (typically kuch sau friends se kam) ko application layer mein sort karo instead of ek separate structure per player maintain karne ke.

2. **"Ek seasonal reset ke dauran kya hota hai — aap midnight par ek jarring discontinuity ya load ka burst kaise avoid karte ho?"** New season ka sorted set pehle se (empty) create karo, reset boundary par writes cut over karo usmein, aur old season ka final state historical display ke liye ("last season's rank") durable store mein archive karo. Regions/timezones ke across reset ko stagger karo agar game global hai, ek single synchronized write spike avoid karne ke liye.

3. **"Aap ek single player ko score updates spam karke system ko overwhelm karne se (accidentally ya maliciously) kaise prevent karte ho?"** Ingestion layer par per player score-update events rate-limit karo, aur kyunki matches ki ek natural minimum duration hoti hai, per player plausible update frequency ko kuch aisa cap karo jo ek compromised client otherwise attempt kar sakta hai usse kaafi kam ho.

4. **"Aapka merge-based global top-N assume karta hai ki har shard ka local top-100 sufficient hai — kya yeh assumption kabhi break hota hai?"** Yeh hold karta hai jab tak aap local top-K retrieve karte ho jahan K >= global N chahiye (top-100 global ke liye har shard ke top-100 candidates chahiye, kam nahi) — agar ek shard unusually score-dense hai (e.g. ek region ke players systematically stronger hain), sirf top-100 per shard retrieve karna abhi bhi mathematically sufficient hai pigeonhole argument ki wajah se 6.3 mein, but yeh explicitly confirm karna worth hai interviewer ko.

5. **"Aap ek leaderboard ko billions of entries ke saath kaise handle karoge, jahan even sharded, yeh comfortably memory mein fit nahi hota?"** Us scale par, ek hybrid consider karo: sirf "interesting" tail ko hot in-memory structure mein rakho (e.g. top 1M globally, kyunki koi usse aage scroll nahi karta) aur deep-rank/percentile queries ko long tail ke liye ek approximate structure ya durable store se serve karo ek background-computed rank index ke saath, precision ko low-value long tail ke against cost se trade karte hue.

6. **"Aap leaderboard response mein display names/avatars ko fresh kaise rakhte ho agar ek player apna naam change kare?"** Denormalized profile data sorted set mein hi store mat karo (isko har leaderboard mein ek write chahiye hoga jismein player appear karta hai har profile edit par); instead, sorted set sirf player_id aur score hold karta hai, aur read API ek batch lookup karta hai ek cached profile store ke against (player_id se keyed) response ko hydrate karne ke liye, hot ranking structure ko lean rakhte hue aur profile edits ko cheap rakhte hue.
