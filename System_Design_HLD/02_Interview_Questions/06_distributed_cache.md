# Design a Distributed Cache

## Problem Statement

"Design a distributed, in-memory caching system — think a simplified Redis or Memcached cluster — that a fleet of application servers can share to store and retrieve key-value data with sub-millisecond latency. The cache needs to scale horizontally across many nodes as the working set grows, survive individual node failures without losing significant cached data, and handle the reality that popularity across keys is wildly uneven." This is the infrastructure layer that sits between application servers and the database in almost every large-scale system, and it's usually the follow-up to "the database is the bottleneck" in a broader design interview.

## Step 1: Clarify Requirements

### Functional Requirements

- Basic key-value operations: `GET(key)`, `SET(key, value, ttl)`, `DELETE(key)`.
- Batch operations (`MGET`/`MSET`) to amortize network round trips for multi-key lookups.
- TTL-based expiry — every key can optionally expire automatically.
- The cluster grows and shrinks over time (nodes added for capacity, removed for maintenance/failure) without requiring a full cache flush.
- Clients (application servers) need a way to know which node owns a given key.
- Out of scope in depth, but should not be precluded by the design: richer data structures (lists, sets, sorted sets) beyond simple strings/blobs.

### Non-Functional Requirements

- **Latency**: sub-millisecond p50, low single-digit-millisecond p99 for `GET`/`SET` — this is the entire reason the cache exists instead of just querying the database.
- **Throughput**: sustain millions of operations/second across the cluster.
- **Availability over consistency**: the cache is not the system of record — the database is. A cache node briefly serving a stale or even momentarily unavailable value is acceptable; the cache going down and forcing 100% of traffic onto the database is not. This shapes nearly every trade-off in Step 6.
- **Horizontal scalability**: adding or removing nodes should remap only a small fraction of keys, not cause a mass cache miss across the whole dataset.
- **Fault tolerance**: losing a single node should not cause data loss for all keys it owned, nor should it cause a synchronized wave of cache misses (thundering herd) against the database.
- **Even load distribution**: no single node should become a hotspot under normal, evenly-distributed key access — and the design should have an explicit answer for when access is *not* evenly distributed (hot keys).

## Step 2: Back-of-Envelope Estimation

**Assumptions**:
- The cache fronts a service handling 200,000 requests/sec at peak.
- Each incoming request triggers, on average, 3 cache lookups (a typical page/API response assembled from several cached objects).
- Cache hit rate is high (~90%), which is the entire point of the cache — misses fall through to the database.
- 10% of read volume additionally produces a cache write (populate-on-miss, or explicit invalidation-driven update).
- Average cached value size: 2 KB (a serialized object — user profile, rendered fragment, query result).
- Target working set: 100 million hot keys resident in the cache at once.

**Operation QPS**

```
Reads:  200,000 req/sec × 3 lookups/req = 600,000 GET ops/sec at peak
Writes: 600,000 × 10% ≈ 60,000 SET ops/sec at peak
```

**Data size**

```
100,000,000 keys × 2 KB/value = 200,000,000 KB = 200,000 MB = 200 GB total working set
```

With a replication factor of 2 (Step 6) for availability:

```
200 GB × 2 = 400 GB total memory footprint across the cluster
```

**Node sizing**

Assume each cache node runs on a 64 GB RAM instance, with ~50 GB usable for cached data after reserving headroom for the OS, connection buffers, and internal data-structure overhead:

```
Nodes needed for data: 400 GB / 50 GB ≈ 8 nodes minimum
```

Add headroom for availability (so losing a node doesn't immediately overflow the rest) and for spreading load thinner per node:

```
~12-16 nodes in the cluster
```

**Per-node throughput check**

```
600,000 read ops/sec / 12 nodes = 50,000 ops/sec/node
```

A well-tuned in-memory KV node (Redis/Memcached-class) comfortably handles 50,000-100,000+ simple ops/sec on modern hardware, so this is a reasonable node count, not an under- or over-provisioned one.

**Bandwidth**

```
600,000 ops/sec × 2 KB avg value = 1,200,000 KB/sec ≈ 1.2 GB/s cluster-wide
Spread across 12 nodes: 1.2 GB/s / 12 ≈ 100 MB/s/node ≈ 800 Mbps/node
```

Well within a single 10 Gbps NIC per node, with plenty of headroom for replication traffic on top.

**Replication traffic overhead**

At replication factor 2, every write is shipped once more to a replica:

```
60,000 SET ops/sec × 2 KB = 120,000 KB/sec ≈ 117 MB/s additional cluster-wide traffic for replication
```

Spread across the nodes acting as replica targets, this adds roughly another 10 MB/s per node on top of the primary read/write traffic above — small relative to the 100 MB/s already computed, which is why replication factor 2-3 is affordable even at this scale; the real cost of replication is memory (Step 2's 400 GB footprint already includes it), not network.

**Connections**

Assume each of, say, 2,000 application server instances keeps a small persistent connection pool (e.g., 5 connections) open to the cache cluster:

```
2,000 app servers × 5 connections = 10,000 total connections
10,000 / 12 nodes ≈ 830 connections/node
```

A well-tuned cache node handles this comfortably (Redis/Memcached routinely handle tens of thousands of concurrent connections per instance), so connection count is not a limiting factor at this scale — it becomes relevant only at a much larger application fleet size.

## Step 3: High-Level Design

```text
                    +-------------------------+
                    |   Application Servers    |
                    +------------+-------------+
                                 |
                 +---------------+---------------+
                 |     Client Library / Proxy     |   <- runs consistent-hashing
                 |  (knows which node owns a key) |      logic (Step 6)
                 +----+----------+----------+-----+
                      |          |          |
            +---------+   +------+---+   +--+-------+
            | Cache    |   | Cache    |   | Cache    |   ... (hash ring, N nodes)
            | Node A   |   | Node B   |   | Node C   |
            | (primary |   | (primary |   | (primary |
            |  shard 1)|   |  shard 2)|   |  shard 3)|
            +----+-----+   +----+-----+   +----+-----+
                 |               |              |
            replicate       replicate      replicate
                 |               |              |
            +----v-----+   +----v-----+   +----v-----+
            | Replica  |   | Replica  |   | Replica  |
            | of C's   |   | of A's   |   | of B's   |
            | shard    |   | shard    |   | shard    |
            +----------+   +----------+   +----------+

            +-------------------------------------+
            |     Coordination Service (etcd/      |
            |     ZooKeeper or gossip) — tracks     |
            |     cluster membership + hash ring    |
            +-------------------------------------+

                         (on a cache miss)
                                 |
                                 v
                    +-------------------------+
                    |        Database          |
                    +-------------------------+
```

**Flow**: an application server asks the client library (or a proxy layer, Step 6) for a key. The library runs consistent hashing to determine which node currently owns that key and talks to it directly. On a hit, the value comes back in well under a millisecond. On a miss, the application server (in the common cache-aside pattern — see `05_caching.md`) queries the database and populates the cache itself. Each node's data is asynchronously or semi-synchronously replicated to at least one other node, so a single node's failure doesn't erase that slice of the keyspace. A small coordination layer (or gossip protocol — see `09_distributed_systems_core.md`) tracks which nodes are alive and what the current hash ring looks like, so clients and nodes agree on ownership.

**Key components**:
- **Client library / proxy**: the layer that decides "which node owns this key" — the central design fork covered in Step 6.
- **Cache nodes**: in-memory hash tables, each running its own local eviction policy (LRU/LFU) independently.
- **Replication**: each shard's primary has one or more replicas on different nodes.
- **Coordination service**: authoritative record of cluster membership and ring topology, so a node addition/removal is agreed upon consistently rather than each client guessing independently.

**Walking through one operation end to end**: (1) an application server calls `GET("user:42")` on the client library. (2) The library hashes `"user:42"` onto the ring and, using its locally cached copy of the topology, determines node B currently owns that key's hash range. (3) The library sends the request directly to node B. (4a) On a hit, node B returns the value from its in-memory hash table in well under a millisecond. (4b) On a miss, node B returns "not found," and the application server (using cache-aside, `05_caching.md`) queries the database, then issues a `SET` back through the same client library, which again hashes the key, again routes to node B, and node B stores it and asynchronously ships a copy to its replica. (5) If node B were to crash between steps 3 and 4, the client library detects the failed connection (via the coordination service's updated membership view) and retries against whichever node now owns that hash range — the promoted replica — rather than retrying against the dead node.

## Step 4: API Design

**Get a value**
```
GET /cache/{key}
→ 200 OK { "value": "...", "ttl_remaining_ms": 42000 }
→ 404 Not Found (cache miss)
```

**Set a value**
```
PUT /cache/{key}
{ "value": "...", "ttl_ms": 60000 }
→ 200 OK
```

**Delete / invalidate a value**
```
DELETE /cache/{key}
→ 204 No Content
```

**Batch get** (amortizes round trips for multi-key reads)
```
POST /cache/mget
{ "keys": ["user:42", "user:43", "post:9001"] }
→ 200 OK
{ "user:42": {...}, "user:43": null, "post:9001": {...} }
```

**Cluster topology** (internal, node-to-node and client-to-coordination-service)
```
GET /cluster/topology
→ 200 OK
{
  "nodes": [
    { "id": "node-a", "hash_range": [0, 1398101333], "status": "up" },
    { "id": "node-b", "hash_range": [1398101334, 2796202667], "status": "up" }
  ],
  "version": 1284
}
```
The `version` field lets clients cheaply detect "has the ring changed since I last cached this locally" without re-fetching the full topology on every operation.

## Step 5: Data Model

The cache itself is not backed by a database in the traditional sense — each node holds an **in-memory hash table**, keyed by the cache key, valued by an opaque byte blob plus a small metadata header:

| Field | Notes |
|---|---|
| `key` | string, the lookup key |
| `value` | opaque bytes (the application decides serialization — JSON, protobuf, etc.) |
| `expires_at` | absolute timestamp derived from TTL, checked lazily on read and/or proactively swept |
| `version` / `last_write_time` | used to resolve conflicts between a primary and a lagging replica on failover |

This maps to an **in-memory key-value store** class of system (Redis/Memcached), not SQL or a general document store — justified because every access pattern here is a point lookup or point write by exact key, there are no relational queries or secondary indexes needed, and the entire value proposition is raw speed, which rules out anything with disk-durability overhead on the hot path.

**Cluster metadata** (ring topology, node health) is a separate, much smaller data set — this is exactly the kind of small, strongly-consistent, infrequently-changing configuration data that belongs in a coordination service like etcd or ZooKeeper (see `09_distributed_systems_core.md`) rather than in the cache itself: it needs strong consistency (every client must agree on ring ownership) at low volume, which is the opposite profile of the cached data itself (high volume, availability over consistency).

**Local L1 cache** (Step 6): each application server may additionally keep a small, short-TTL in-process cache (a plain in-memory map, not a separate system) for the very hottest keys — this has no formal schema, it's just an LRU-capped map living in the application process.

**Storage choice justification, summarized**:

| Component | Storage type | Why |
|---|---|---|
| Cached key-value data | In-memory hash table per node (Redis/Memcached-class) | Point lookups/writes only, no relational queries, speed is the entire value proposition |
| Cluster topology / membership | Coordination service (etcd/ZooKeeper) | Small, low-volume, needs strong consistency across every client |
| Local hot-key cache | In-process map on each app server | Zero network hop, per-process, no durability needed |

## Step 6: Deep Dive

### Consistent Hashing for Key Distribution

The core question a distributed cache must answer on every operation is "which node owns this key?" A naive `hash(key) % N` mapping breaks catastrophically the moment `N` changes — adding or removing a single node changes the modulus, which reshuffles the ownership of *almost every key* in the cluster simultaneously. Concretely, going from 12 to 13 nodes would invalidate roughly 92% of existing key-to-node mappings at once (`(N-1)/N` keys move under naive modulo hashing) — every one of those "moved" keys is now looked up on a node that doesn't have it, producing a mass, synchronized wave of cache misses that all fall through to the database at once. That's precisely the thundering-herd failure this cache was built to prevent.

**Consistent hashing** (covered in general in `07_database_scaling.md`; applied here specifically) fixes this by hashing both nodes and keys onto the same fixed circular hash space (e.g., a 32-bit or 160-bit ring). A key is owned by the first node found walking clockwise from the key's hash position. Adding a node only takes ownership of the slice of the ring between it and its counter-clockwise neighbor — only the keys in that one slice need to move; removing a node only affects the slice it owned, which falls to its clockwise neighbor. With 12-16 nodes, adding a 13th node remaps roughly `1/13 ≈ 7.7%` of keys instead of ~92% — more than a 10x reduction in cache-miss blast radius for the exact scenario above.

**Virtual nodes**: mapping each physical node to a single point on the ring creates uneven load if nodes happen to land close together (some nodes own much larger arcs than others by chance). The standard fix is giving each physical node many virtual positions on the ring (commonly 100-200 per physical node) — ownership becomes the union of many small arcs per node, which averages out to near-even load distribution regardless of how the random hash positions happen to fall, and also means a node's failure spreads its lost capacity across many other nodes' virtual positions instead of dumping it all on one neighbor.

### Replication for High Availability

Each shard (the slice of the ring one node owns) is replicated to N-1 additional nodes (commonly N=2 or N=3 total copies), typically the next nodes clockwise on the ring so replica placement follows the same consistent-hashing logic as primary placement. Two concrete failure modes this addresses:

- **Data loss on node failure**: without replication, a node crash means every key it owned is now unrecoverable from the cache (it isn't gone from the database, but it's gone from the cache, meaning the *next* read for each of those keys is a guaranteed miss) — with a live replica, a promoted replica continues serving that slice with no data loss for reads.
- **Thundering herd on failover**: if a node dies with no replica, every key it owned starts missing simultaneously the moment traffic reroutes to the new owner (whichever node the ring now maps that slice to) — a synchronized spike of database load exactly like the naive-rehashing problem above, just triggered by failure instead of scaling. A warm replica avoids this because it already holds the data; failover promotes it in place rather than starting that key range from empty.

**Replication mode trade-off**: synchronous replication (acknowledge the write only after the replica confirms) guarantees the replica is never behind, at the cost of added write latency and reduced write availability if the replica is slow or unreachable. Asynchronous replication (acknowledge immediately, replicate in the background) keeps write latency low and availability high, at the cost of a small window where a just-failed primary's most recent writes may not have reached the replica yet. Given this system's stated priority (availability over consistency, Step 1), asynchronous replication is the standard choice — losing the last few milliseconds of writes on a rare node crash is an acceptable cost for keeping every write fast, especially because the cache is never the sole copy of the data (Step 1: the database remains the source of truth).

| | Synchronous replication | Asynchronous replication |
|---|---|---|
| Write latency | Higher — waits for replica ack | Lower — acks immediately after primary write |
| Write availability | Lower — degrades if replica is slow/unreachable | Higher — unaffected by replica health |
| Data loss window on primary crash | None (replica always caught up) | Small (in-flight, unacknowledged-to-replica writes) |
| Fit for this system | Poor — conflicts with the availability-first NFR | Good — matches "cache, not source of truth" |

**Read replicas for load-spreading, not just failover**: beyond pure availability, replicas can also serve reads directly (not just stand by for failover), which spreads read load for a shard across multiple nodes instead of concentrating it entirely on the primary — this is a natural complement to the hot-key mitigations discussed next, since a replicated hot key already has multiple nodes capable of answering reads for it.

### Eviction Policy at the Cluster Level

Each node enforces its own memory-pressure eviction policy locally (LRU or LFU — see `05_caching.md` for the full mechanics of each), but the interesting wrinkle at cluster scale is that **eviction decisions made independently, per node, can still produce cluster-wide effects**. Because consistent hashing assigns each key to exactly one owning node (ignoring replicas for a moment), that node's local memory pressure is the *only* thing that determines whether a given key survives — there's no cluster-wide "least recently used across the whole dataset" concept, and building one would require constant cross-node coordination that would destroy the latency budget this cache exists for.

This has a concrete consequence: **uneven key size or uneven per-node popularity causes uneven per-node memory pressure**, even when the *count* of keys is balanced by consistent hashing. A node that happens to own a disproportionate share of large values, or values from a heavily-read tenant, evicts more aggressively than its neighbors — from the outside this looks like "random" extra cache misses concentrated on one part of the keyspace, and the fix is usually operational (monitor per-node memory pressure and eviction rate, not just cluster-aggregate hit rate) rather than architectural. TTL is layered on top of whichever eviction policy is chosen exactly as in the single-node case — it bounds staleness independent of memory pressure, while LRU/LFU governs what gets evicted *when* the node is full.

**LRU vs. LFU choice at cluster scale mirrors the single-node trade-off** (see `05_caching.md` for the full mechanics): LRU is the default for this system because application access patterns typically shift over time (which objects are "hot" changes as product usage changes) and LRU adapts automatically without any tuning per node. LFU becomes attractive specifically when a subset of keys are known to be reliably, permanently popular (e.g., global configuration objects, top-N leaderboard entries) and the operator wants to guard against a brief unrelated traffic burst evicting them — but LFU's slower adaptation to newly-trending keys is a worse fit for a general-purpose cache fronting varied application traffic, which is why LRU remains the more common cluster-wide default even though the decision is technically made independently per node.

### The Hot Key Problem and Client Library Design

**The hot key problem**: consistent hashing guarantees an even *distribution* of keys across nodes, but it does nothing about *access frequency* — a single extremely popular key (a viral post's like-count, a trending product's price, a celebrity's profile) still maps to exactly one node under the hashing scheme, and if that key alone receives a disproportionate share of the cluster's total read traffic, that one node can be overwhelmed while every other node in the cluster sits well under capacity. This is fundamentally different from the "hot shard" problem in a sharded database, because a cache's whole purpose is absorbing very skewed access patterns — and consistent hashing, by design, sends all of a hot key's traffic to one place.

**Mitigations**:
- **Replicate hot keys beyond the normal replication factor**: detect keys receiving outsized traffic (via per-key access counters, sampled) and proactively copy them to several additional nodes beyond the standard N replicas, then have the client library round-robin reads for that specific key across all of its copies. This directly spreads a hot key's read load the way normal replication doesn't (normal replicas exist for failover, not routine load-spreading, in most configurations).
- **Local in-process cache (L1) in front of the distributed cache (L2)**: each application server keeps a small, short-TTL map for the very hottest keys, checked before ever reaching the distributed cache at all. A short TTL (seconds, not minutes) bounds staleness while still absorbing the overwhelming majority of a hot key's request volume locally, in-process, with zero network hop — this is the single most effective mitigation for extreme hot-key skew, because it removes the traffic from the distributed cache entirely rather than just spreading it across more of the cluster.

**Client library vs. proxy**: how does the calling application actually learn which node owns a key?

| | Smart client library | Proxy / router layer |
|---|---|---|
| Who runs the hashing logic | The application process itself, via an embedded library | A dedicated proxy tier (e.g., Twemproxy-style) between app servers and cache nodes |
| Network hops per operation | 1 (app talks directly to the owning node) | 2 (app → proxy → owning node) |
| Latency | Lower (no extra hop) | Slightly higher (extra hop), but often negligible if colocated |
| Topology-change propagation | Every application instance must learn about ring changes independently (via the coordination service) | Only the proxy tier needs to learn about ring changes — a much smaller set of processes |
| Operational simplicity | More moving parts spread across every app server/language | Centralizes cache-routing logic in one place — easier to upgrade, monitor, and reason about |
| Cross-language consistency | Needs a maintained client library per language in a polyglot environment | Proxy is language-agnostic — any client speaks a simple protocol to it |

Neither is strictly better: a smart client is the lower-latency choice and is what most large single-language deployments (a large Ruby or Java monolith fleet) use once they're willing to maintain the hashing logic in a shared library; a proxy layer is the better choice in a polyglot environment or when centralizing operational control (topology changes, monitoring, connection pooling) outweighs the cost of an extra network hop.

**Detecting a hot key in the first place**: neither mitigation is useful without first knowing which keys are hot. In practice this means sampling access counts per key (or per key-prefix, to avoid the overhead of tracking every individual key) at the client library or proxy layer, exporting the top-N most-accessed keys to a monitoring system, and setting an automatic threshold (e.g., a key exceeding some multiple of the average per-key request rate) that triggers the extra-replication mitigation without requiring a human to notice the problem first — by the time a human notices via a paged alert, the owning node may already be degraded.

## Step 7: Bottlenecks & Trade-offs

- **Hot keys are the first thing that breaks**, not aggregate cluster capacity — Step 2's math shows the cluster is comfortably sized for *even* load; a single popular key concentrating disproportionate traffic on one node is a failure mode that raw node count doesn't fix, only the mitigations in Step 6 do.
- **Memory is always the limiting resource**, not CPU — an in-memory cache node's ceiling is RAM capacity (Step 2: ~50 GB usable per 64 GB node), so the trade-off is between fewer, larger (more expensive, higher blast radius on failure) nodes versus more, smaller (more network overhead, more operational surface) nodes.
- **Availability over consistency has a real cost**: asynchronous replication (Step 6) means a small window of possible data loss on failover is an accepted trade-off — a system that instead required strict consistency on every cache write would pay for it in write latency, directly undermining the cache's entire reason for existing.
- **Cache warmth after a large-scale event** (a full cluster restart, a major rebalance from many nodes being added at once) means a wave of misses hits the database until the cache refills — this is the same thundering-herd risk as the naive-rehashing scenario, and it's mitigated operationally (staged rollouts, pre-warming from a snapshot, gradual traffic shifting) rather than architecturally solved.
- **TTL choice is a permanent staleness-vs-hit-rate dial** (see `05_caching.md`) layered on top of everything above — nothing in the distributed-cache architecture changes that fundamental trade-off, it just determines how many nodes are involved in absorbing the resulting traffic pattern.
- **Coordination service becomes a dependency**, even though it's small — if clients can't reach the coordination layer to learn ring topology, they fall back to stale topology information, which can misroute requests to a node that no longer owns a key range (usually handled by having the wrongly-hit node forward or reject with a redirect, similar to Redis Cluster's `MOVED` response).

**Bottleneck-to-mitigation summary**:

| Bottleneck | Mitigation | Cost accepted |
|---|---|---|
| Naive rehashing on scale change | Consistent hashing + virtual nodes | Slightly more complex client/proxy routing logic |
| Node failure loses a shard | Replication (async) to N-1 replicas | Small window of possible data loss on failover |
| One key overwhelms one node | Extra replication of detected hot keys + local L1 cache | Extra memory for duplicated hot data, brief staleness at L1 |
| Uneven per-node memory pressure | Per-node LRU/LFU + monitoring, not cluster-wide eviction | No global optimality — decisions are local per node |
| Cold cluster after mass restart/rebalance | Staged rollout, pre-warming, gradual traffic shift | Slower recovery in exchange for avoiding a DB-crushing thundering herd |

## Follow-up Questions an Interviewer Might Ask

**How would you support a multi-region deployment where users are served from their nearest region?**
Run an independent cache cluster per region rather than one global cluster (cross-region network latency would defeat the sub-millisecond goal), and either accept per-region cache divergence (acceptable given the cache is never the source of truth) or replicate specific hot, rarely-changing keys across regions asynchronously for global consistency where it matters most.

**How would you add optional persistence so the cache can be warmed quickly after a full restart instead of starting cold?**
Borrow Redis's approach: periodic point-in-time snapshots (RDB-style) or an append-only write log (AOF-style) written to disk asynchronously off the hot path, then replayed on startup to pre-populate memory — this trades a bit of disk I/O overhead and implementation complexity for dramatically reducing the cold-start thundering-herd window described in Step 7.

**How would you monitor and act on cache health in production?**
Track per-node and cluster-aggregate hit rate, eviction rate, memory pressure, and p99 latency, with per-key or per-key-prefix breakdowns to catch hot-key skew (Step 6) before it saturates a node; alert on eviction rate spikes (signals undersized cluster) and on hit-rate drops (signals a TTL, invalidation, or cold-start problem) separately, since they point at different root causes.

**How would you extend this beyond simple key-value gets/sets to support richer data structures like sorted sets or lists (Redis-style)?**
Keep the same node/replication/hashing architecture, but change what a node stores per key from an opaque blob to a typed structure with its own operations (`ZADD`/`ZRANGE` for a sorted set, `LPUSH`/`LRANGE` for a list) — the distribution and availability story doesn't change, only the per-node value representation and the operation surface exposed by the API layer.

**How do you handle a client that has stale ring topology information after a rebalance?**
Version the topology (as in Step 4's API) so a node can detect a request routed under an outdated view and either serve it anyway if it still happens to own the key, forward it to the correct current owner, or reject it with a redirect telling the client to refresh its topology — Redis Cluster's `MOVED`/`ASK` responses are the reference implementation of this pattern.

**Why not just use a single large cache node instead of a distributed cluster?**
A single node has a hard capacity ceiling (Step 2's 200 GB+ working set doesn't fit in one machine's RAM affordably) and is a single point of failure — losing it drops 100% of cache traffic onto the database at once, which is the exact thundering-herd scenario this whole design exists to prevent; distributing both spreads capacity and bounds the blast radius of any single node's failure to its slice of the keyspace.

**How would you decide the right replication factor and cluster size as traffic grows 5x?**
Recompute Step 2's arithmetic with the new QPS and working-set numbers — replication factor is primarily an availability decision (2 tolerates one node loss per shard, 3 tolerates two) independent of raw scale, while node count scales with total memory needed divided by per-node usable capacity; the exercise is to show the estimation process generalizes, not to memorize a fixed number.
