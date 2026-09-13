# Design a Real-Time Leaderboard System

## Problem Statement

"Design a real-time leaderboard for a mobile game with millions of players — think a battle royale or a casual puzzle game. Players earn scores, and we need to show each player their global rank, a top-100 list, and 'nearby' players (a few ranks above and below them). Scores update constantly — every match that finishes changes at least two players' standings. How would you build this so it stays fast and correct as the player base and update rate grow?"

This is a classic system design question because the naive relational approach — `SELECT ... ORDER BY score DESC` — works fine in a demo and falls over almost immediately in production. The interviewer is really testing whether you know when to reach for a specialized data structure (a sorted set) instead of a general-purpose database, and whether you can reason about sharding an inherently "global" ranking problem.

## Step 1: Clarify Requirements

**Functional Requirements**
- Update a player's score (increment or absolute set) after each game/match.
- Retrieve a player's current global rank and score.
- Retrieve the top-N players (e.g. top 100) globally.
- Retrieve players "around" a given player (e.g. 5 ranks above, 5 below) — the "nearby leaderboard" view.
- Support multiple leaderboards: global, per-region, per-game-mode, weekly/seasonal (resets), friends-only.
- Ties must be broken deterministically and consistently (no flicker between page loads).

**Non-Functional Requirements**
- Scale: 50 million monthly active players, 5 million daily active, peak concurrency of 500K players in active matches.
- Write rate: every finished match updates 2+ player scores. Assume 200K matches/minute at peak → ~400K score updates/minute (~6,700 writes/sec) at peak, bursty around popular event times.
- Read rate: leaderboard views (top-100, own-rank, nearby) are requested far more often than writes — assume a 20:1 read:write ratio, so ~130K reads/sec at peak.
- Latency: rank/score lookups and top-N should return in under 50ms p99 — leaderboards are usually rendered on a UI the player is actively staring at after a match.
- Consistency: eventual consistency is acceptable — a rank being a few seconds stale after a score update is fine. What's NOT acceptable is a rank computation that's internally inconsistent (e.g. two players shown with the same rank incorrectly, or ranks that don't match sorted order).
- Availability: leaderboard reads should stay available even if score-write ingestion is temporarily degraded (players care more about seeing a leaderboard than about their one match's score appearing instantly).
- Durability: score history should not be silently lost — even though the live ranking structure can be an in-memory cache, there should be a durable system of record behind it.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 50M total registered players, 5M DAU.
- Peak: 6,700 score writes/sec, 130K leaderboard reads/sec (from above).
- Each leaderboard entry: player_id (8 bytes), score (8 bytes as a double/long), plus overhead in the sorted-set structure.

**Storage for the live ranking structure (in-memory sorted set)**
- 5M active players tracked in the "live" global leaderboard at any time (inactive players can be excluded/archived).
- A sorted-set implementation (skip list) costs roughly 80-100 bytes per element including pointers, level array, and the member string/ID — call it 100 bytes/entry to be safe.
- 5M entries x 100 bytes ≈ 500 MB for one global leaderboard.
- If we maintain, say, 50 regional leaderboards + 10 game-mode leaderboards + a weekly-seasonal leaderboard (62 total structures, though each is a subset of the 5M, not a full duplicate each time) — total working set is comfortably in the low single-digit GB range. This fits in memory on a modestly sized Redis cluster (e.g. 3-6 nodes of 8-16GB each, with room to spare and headroom for growth).

**Durable storage (system of record, e.g. player match/score history)**
- 400K score-changing events/minute x 60 x 24 ≈ 576M events/day.
- Each event record (player_id, match_id, score_delta, timestamp, game_mode) ≈ 64 bytes.
- 576M x 64 bytes ≈ 37 GB/day of raw event data. Over a year (with compression and eventual archival/cold storage of old seasons) this is manageable on standard object storage / a wide-column store, well under petabyte scale.

**Bandwidth**
- Each leaderboard read response (top-100 payload) ≈ 100 entries x ~40 bytes (rank, player_id, name, score) ≈ 4 KB.
- 130K reads/sec x 4 KB ≈ 520 MB/sec if every read fetched top-100 fresh — this is why caching the top-N response (Step 6) matters enormously; most of those 130K reads should hit a cache, not recompute against the sorted set.

**Conclusion of the estimation**: the live ranking structure fits entirely in memory across a handful of nodes, so the core design decision is "use an in-memory sorted-set structure as the source of truth for rankings, backed by a durable event log/database for score history and disaster recovery," not "how do we shard a multi-terabyte table."

## Step 3: High-Level Design

**Core components**
- **Game/Match Service**: emits a score-update event whenever a match ends.
- **Score Ingestion Service**: consumes score-update events, validates them (anti-cheat sanity checks), and applies the update to the leaderboard store.
- **Leaderboard Store (Redis Sorted Set cluster)**: the hot, in-memory, incrementally-maintained ranking structure. One sorted set per leaderboard (global, per-region, per-mode, per-season).
- **Durable Score Store (e.g. Cassandra/DynamoDB)**: append-only history of score events, source of truth for rebuilding a sorted set if Redis data is lost, and for analytics/anti-cheat auditing.
- **Leaderboard Read API**: serves top-N, player-rank, and nearby-rank queries, backed by a read-through cache in front of Redis for the hottest queries (top-100 global).
- **Real-Time Notification Service**: pushes rank-change events to connected clients (Step 6).
- **Message Queue** (e.g. Kafka): decouples match completion from leaderboard update, absorbs write bursts, and fans the event out to both the Score Ingestion Service and the durable store writer.

**Data flow**
1. Match ends → Game Service publishes `ScoreUpdated{player_id, leaderboard_ids[], delta}` to Kafka.
2. Score Ingestion Service consumes the event, issues an atomic increment against the relevant sorted set(s) in Redis (e.g. `ZINCRBY`).
3. A separate consumer of the same Kafka topic writes the raw event to the durable store for history/audit/rebuild purposes — this happens in parallel, not blocking the hot path.
4. Client requests `GET /leaderboard/global/top?n=100` → hits cache; on miss, queries Redis `ZREVRANGE` and repopulates the cache with a short TTL.
5. Client requests `GET /leaderboard/global/rank/{player_id}` → Redis `ZREVRANK` + `ZSCORE`, typically not cached (per-user, low cache hit value) but cheap enough (O(log n)) to serve directly.
6. Rank-change events optionally pushed to subscribed clients over a persistent connection.

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

**`POST /internal/scores/update`** (called by Score Ingestion Service, not public)
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
- Key: `leaderboard:global` (or `leaderboard:region:eu-west`, etc.)
- Member: `player_id`
- Score: the player's numeric score (used natively as the sort key).
- Maps directly onto Redis's ZSET commands: `ZADD`/`ZINCRBY` for writes, `ZREVRANGE` for top-N, `ZREVRANK` for a player's rank, `ZRANGEBYSCORE`/`ZRANGE ... REV ... LIMIT` around a rank for "nearby."
- This is a key-value / in-memory data structure store, chosen specifically because it maintains sort order incrementally — the right tool when the access pattern is "always sorted, constantly updated," which a relational B-tree index technically supports but pays a much higher constant-factor cost for at this update rate and for rank-position queries.

**Durable score history — wide-column store (e.g. Cassandra) or an append-only log**
```
Table: score_events
  player_id       (partition key)
  event_timestamp (clustering key, descending)
  match_id
  leaderboard_id
  delta
  resulting_score
```
- Chosen because writes are append-only and extremely high volume, reads are typically "all events for a player" (partition-aligned), and it doubles as the rebuild source if a Redis node is lost — replay events in score order to reconstruct a sorted set.

**Player profile metadata — relational (e.g. Postgres)**
```
Table: players
  player_id (PK)
  display_name
  region
  created_at
```
- Denormalized display name and avatar are joined into leaderboard read responses at the API layer (or cached alongside rank data) rather than stored redundantly in the sorted set itself, since profile data changes independently and is low-cardinality relative to score events.

## Step 6: Deep Dive

### 6.1 Why `ORDER BY score DESC LIMIT N` Collapses at Scale

A relational table with a B-tree index on `score` can technically answer "top 100" reasonably fast — the index is already sorted, so `LIMIT 100` is cheap in isolation. The problem is what surrounds that query in this system:
- **Update volume**: every one of the ~6,700 writes/sec is an `UPDATE players SET score = score + ? WHERE player_id = ?`, which requires the B-tree index to be rebalanced/re-inserted at that position — a `O(log n)` operation, similar in complexity to a sorted-set update, EXCEPT it's competing with MVCC/transaction overhead, WAL writes, and lock contention on a general-purpose OLTP engine not optimized for this single access pattern.
- **Rank computation is the real killer**: getting "what is this player's rank" via SQL requires either `SELECT COUNT(*) FROM players WHERE score > ?` (a full scan or index range-scan across potentially millions of rows, recomputed on every single request) or maintaining a separate rank column that must be recalculated for every player below the one whose score just changed — an operation that touches O(n) rows per single score update in the worst case (imagine the last-place player suddenly scores the most points; everyone's rank shifts).
- A sorted-set/skip-list structure sidesteps both problems: it's purpose-built to keep elements ordered incrementally as they're inserted/updated (`O(log n)` per update, no cascading re-numbering of other elements) and to answer "rank of X" directly (`O(log n)`) by walking skip-list levels rather than counting rows.
- The practical rule of thumb: reach for a relational table when you need flexible queries and strong transactional guarantees over relatively slow-changing data; reach for a sorted-set-style structure when the access pattern is "constantly changing values, always need them ordered, always need positional rank" — leaderboards are the canonical case for the latter.

### 6.2 Getting a Single Player's Rank Efficiently

The naive relational approach to "what's my rank" is `SELECT COUNT(*) FROM leaderboard WHERE score > my_score` — a full scan/aggregate that gets slower as the table grows and has to be re-run from scratch on every request, even though nothing about the overall distribution changed since the last time someone asked.

A sorted-set structure solves this natively: `ZREVRANK leaderboard:global player_id` walks the skip list's level pointers, which store subtree/span sizes, and returns the 0-indexed rank in `O(log n)` — no scanning, no counting rows one at a time. This is the single biggest reason to prefer this data structure over a plain sorted list or a relational index for a leaderboard: rank lookup and top-N retrieval are both cheap, and so is the incremental update, on the very same structure.

### 6.3 Sharding and Computing a Global Top-N Across Shards

Once a single leaderboard structure grows too large for one node (or, more commonly here, once there are so many distinct leaderboards — per-region, per-mode, per-season — that a single Redis node's memory or throughput is the bottleneck), the data must be sharded.

Natural partitions exist for most sub-leaderboards: per-region leaderboards shard trivially by region, per-mode leaderboards by mode. Each of those is small enough to live entirely on one Redis node/shard, so most leaderboard queries never cross a shard boundary at all.

The genuinely hard case is a single GLOBAL top-N across a player base large enough that even the global leaderboard itself must be sharded (e.g. hash-partitioned by player_id across N Redis shards, since no single "region" is the whole answer). Now "top 100 globally" cannot be answered by one `ZREVRANGE` call. The fix is the same retrieve-then-merge pattern used for cross-shard search and cross-shard driver matching elsewhere in this system design series:
1. Fan out `ZREVRANGE shard_i 0 99` to all N shards in parallel — each returns its own local top-100 candidates.
2. Merge the N x 100 candidate lists (a simple k-way merge on score, since each shard's sublist is already sorted) and take the global top 100 from the merged, much smaller candidate set.
3. This works because the true global top-100 must be a subset of the union of every shard's local top-100 — a player who isn't in their own shard's top 100 cannot possibly be in the global top 100 (there are already at least 100 players in their own shard alone with a higher score).
- This merge step is cheap (a few hundred elements) compared to a naive global sort, and it parallelizes the expensive part (the per-shard sorted retrieval) across nodes.
- The same technique generalizes to "nearby rank" queries once sharded, though it's messier — computing a globally-correct rank requires summing counts-above-score across all shards (`ZCOUNT` per shard, summed), not just merging candidate lists.

### 6.4 Handling Ties with a Stable Secondary Sort Key

If two players have literally identical scores, naive tie handling causes visible, confusing flicker — a player's rank appears to change between page loads even though their score didn't, simply because of nondeterministic ordering of equal-score entries in the underlying structure.

The fix is a deterministic composite sort key: instead of sorting purely on `score`, sort on `(score, tiebreak_value)` where `tiebreak_value` is something stable and meaningful — commonly "timestamp at which this score was reached" (earlier achiever ranks higher), encoded so it composes correctly with the primary score in a single numeric sort key. A common trick with Redis ZSETs specifically: since ZSET scores are floating point, encode the composite key as `score * 10^13 - timestamp` (or similar), so a single numeric comparison captures "higher score wins; among equal scores, earlier timestamp wins" without needing a secondary query. This guarantees a strict total order, so ranks never flicker for two requests against the same underlying state.

### 6.5 Real-Time Rank-Change Push vs Polling

For a player actively watching a live leaderboard (e.g. during a tournament's closing minutes), instant rank-change feedback matters. Two approaches, explicit trade-off:

**Persistent connection (WebSocket/SSE, per `03_networking_and_apis.md`)**: the server pushes a `rank_change` event to a subscribed client the moment their rank shifts. Pros: true real-time feel, no wasted requests when nothing changed. Cons: holding an open connection per actively-watching client is expensive at scale — hundreds of thousands of concurrent connections require a connection-management layer (e.g. a fleet of WebSocket gateway servers, sticky routing, and a fan-out mechanism from the score-update path to whichever gateway instance holds a given player's connection) — meaningfully more infrastructure and operational complexity than stateless HTTP.

**Polling**: client re-requests `GET /leaderboard/.../rank/{player_id}` every few seconds. Pros: stateless, trivially horizontally scalable, reuses the same cached/cheap read path as everything else, and is far simpler operationally. Cons: staleness bounded by the poll interval (e.g. up to 3-5 seconds of lag), and wasted requests when nothing has changed (most polls return an unchanged rank).

The right choice depends on the stakes: a competitive esports tournament's live standings screen justifies the connection overhead of push. A casual mobile game's "check your rank" screen, viewed briefly after a match and not stared at continuously, is well served by polling every few seconds or even just a single on-demand fetch — the cost of persistent connections at millions-of-players scale is not justified by the marginal UX gain. A middle ground many production systems use: poll while idle, upgrade to a push connection only for players actively viewing a live/contested leaderboard screen (e.g. final match of a tournament), keeping the expensive infrastructure scoped to the moments it actually matters.

## Step 7: Bottlenecks & Trade-offs

- **Redis as a single point of contention per shard**: even sharded, a single hot leaderboard (e.g. a viral event's global leaderboard) can concentrate write load on one shard if partitioning is naive. Mitigation: partition by a well-distributed hash of player_id rather than anything correlated with activity level, and monitor per-shard QPS to rebalance hot shards.
- **Memory pressure from too many leaderboard variants**: per-region x per-mode x per-season combinations multiply quickly. Mitigation: TTL/archive old seasonal leaderboards out of the hot Redis tier into the durable store once a season ends and is no longer actively queried; only keep currently-active leaderboards hot in memory.
- **Cache staleness vs load trade-off on top-N reads**: caching the top-100 response reduces Redis load dramatically (per the bandwidth estimate above) but means the displayed top-100 can lag actual state by the cache TTL (e.g. 1-5 seconds). This is an accepted trade-off given the non-functional requirement that eventual consistency is fine for this use case.
- **Anti-cheat and score validation**: a client-reported score cannot be trusted directly; the Score Ingestion Service must validate deltas against plausible bounds (e.g. a per-match maximum possible score) before applying them, since a compromised client could otherwise trivially top the leaderboard. This validation adds latency to the write path but is non-negotiable for a competitive leaderboard.
- **Disaster recovery**: if a Redis node/shard is lost, the live ranking structure must be rebuilt from the durable event log — this is why the durable store exists in parallel even though it's not on the hot read path. Rebuild time for a large shard (replaying millions of events) is a real operational concern and argues for periodic snapshotting (Redis's own RDB/AOF persistence) in addition to the external durable log, rather than relying on full event replay as the only recovery path.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you support a 'friends leaderboard' — ranking only within a player's friend list?"** This can't be precomputed as a static sorted set per player (too many friend-lists, too much duplication). Instead, fetch the friend list, then use a sorted-set intersection-like approach: query each friend's score via `ZSCORE`/`ZMSCORE` against the global leaderboard and sort the small resulting set (typically under a few hundred friends) in the application layer rather than maintaining a separate structure per player.

2. **"What happens during a seasonal reset — how do you avoid a jarring discontinuity or a burst of load at midnight?"** Create the new season's sorted set ahead of time (empty), cut writes over to it at the reset boundary, and archive the old season's final state to the durable store for historical display ("last season's rank"). Stagger the reset across regions/timezones if the game is global, to avoid a single synchronized write spike.

3. **"How do you prevent a single player from spamming score updates and overwhelming the system (accidentally or maliciously)?"** Rate-limit score-update events per player at the ingestion layer, and since matches have a natural minimum duration, cap the plausible update frequency per player to something far below what a compromised client could otherwise attempt.

4. **"Your merge-based global top-N assumes each shard's local top-100 is sufficient — does that assumption ever break?"** It holds as long as you retrieve local top-K where K >= the global N you need (top-100 global needs each shard's top-100 candidates, not fewer) — if a shard is unusually score-dense (e.g. one region's players are systematically stronger), retrieving only top-100 per shard is still mathematically sufficient because of the pigeonhole argument in 6.3, but it's worth explicitly confirming that reasoning to the interviewer.

5. **"How would you handle a leaderboard with billions of entries, where even sharded, this doesn't comfortably fit in memory?"** At that scale, consider a hybrid: keep only the "interesting" tail in the hot in-memory structure (e.g. top 1M globally, since nobody scrolls past that) and serve deep-rank/percentile queries for the long tail from an approximate structure or the durable store with a background-computed rank index, trading precision for the low-value long tail against cost.

6. **"How do you keep display names/avatars in the leaderboard response fresh if a player changes their name?"** Don't store denormalized profile data in the sorted set itself (it would require a write to every leaderboard the player appears in on every profile edit); instead, the sorted set holds only player_id and score, and the read API does a batch lookup against a cached profile store (keyed by player_id) to hydrate the response, keeping the hot ranking structure lean and profile edits cheap.
