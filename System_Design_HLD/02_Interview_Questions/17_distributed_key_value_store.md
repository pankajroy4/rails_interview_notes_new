# Design a Distributed Key-Value Store

## Problem Statement

"Design a distributed key-value store — essentially, build a simplified version of
DynamoDB or Cassandra. It should support simple `get(key)` and `put(key, value)`
operations, scale horizontally across many commodity nodes, tolerate node failures
without losing data or availability, and let me reason about the consistency
guarantees it offers. This is deliberately the 'build the database itself' question
— I want to see you apply the distributed-systems concepts directly, not invent new
ones."

This question is unusual among system design interviews in that it's less about
inventing a novel architecture and more about correctly assembling and reasoning
through a set of well-known distributed-systems primitives — partitioning,
replication, quorums, conflict resolution, and failure handling — each of which has
a right answer grounded in theory. A strong candidate treats it that way: name the
technique, explain why it's the right fit here, and connect it to the
CAP/consistency trade-offs it implies, rather than re-deriving everything from first
principles.

## Step 1: Clarify Requirements

**Functional Requirements**
- `PUT(key, value)` — write/update a value for a key.
- `GET(key)` — read the value(s) for a key.
- `DELETE(key)` — remove a key.
- Simple API only: no complex queries, joins, or secondary indexes — this is a pure
  key-value store, not a general database.
- Operate across a cluster of many nodes, transparently to the client (client
  doesn't need to know which physical node holds a key).

**Non-Functional Requirements**
- Horizontal scalability: adding nodes should linearly increase capacity and
  throughput without a redesign.
- High availability: the system should keep serving reads and writes even when some
  nodes are down or unreachable — no single point of failure anywhere, including in
  cluster membership/coordination.
- Tunable consistency: some use cases want strict correctness, others want speed —
  the system should let the caller choose, rather than hard-coding one point on the
  CAP spectrum (cross-reference `08_cap_theorem_and_consistency.md`).
- Partition tolerance is assumed mandatory (network partitions happen in any real
  multi-node deployment), which per CAP means the real design choice is between
  availability and consistency during a partition, not whether to have partition
  tolerance at all.
- Low, predictable latency: single-digit-millisecond p99 for both `GET` and `PUT`
  under normal operation.
- Durability: an acknowledged write should survive a single node failure.
- Scale target: assume 100 nodes, 1 billion keys, ~10KB average value size.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 1 billion keys, ~10KB average value size (a mix of small config blobs and medium
  serialized objects — the kind of workload DynamoDB/Cassandra actually serve).
- Replication factor N = 3 (standard for this class of system, balancing durability
  against storage cost).
- Assume 100,000 GET QPS and 20,000 PUT QPS platform-wide at peak (a 5:1 read:write
  ratio, typical for key-value workloads).

**Storage**
- Raw data: 1B keys × 10KB ≈ 10TB of logical data.
- With replication factor 3: 10TB × 3 ≈ **30TB of physical storage** across the
  cluster.
- Across 100 nodes: 30TB / 100 ≈ **300GB per node** — comfortably within a single
  commodity node's disk capacity (modern nodes easily handle multiple TB), leaving
  headroom for growth.

**Throughput per node**
- Total GET QPS 100,000, spread across N=3 replicas each of which can serve a read
  for a quorum read of R=2 (see Step 6.2) → each read touches 2 of 3 replicas, so
  effective read load ≈ 100,000 × 2 / 100,000 (100 nodes) — worked more precisely:
  100,000 GETs/s × R=2 replica-reads each = 200,000 replica-read-ops/s, spread
  across 100 nodes ≈ **2,000 reads/s per node**, well within what a single node
  backed by an SSD and an in-memory cache can serve.
- Similarly, 20,000 PUTs/s × W=2 replica-writes each = 40,000 replica-write-ops/s /
  100 nodes ≈ **400 writes/s per node** — comfortably low.

**Network**
- Each replicated write sends ~10KB to W=2 replicas ≈ 20KB per logical write ×
  20,000 writes/s = **400MB/s of internal replication traffic** cluster-wide, which
  is why replication typically happens over a dedicated internal network rather than
  sharing bandwidth with client-facing traffic.

## Step 3: High-Level Design

Every node in the cluster is a peer running the same software (this is a
**decentralized, peer-to-peer** architecture, not a primary/coordinator design) —
any node can receive a client request, act as the coordinator for that request, and
forward it to whichever nodes actually own the relevant key range, per consistent
hashing.

```text
                         ┌──────────┐
                         │  Client   │
                         └────┬─────┘
                              │ GET/PUT key
                              ▼
                  ┌───────────────────────┐
                  │  Any node (coordinator  │  <- no central router;
                  │  for this request)      │     any node can coordinate
                  └───────────┬─────────────┘
                              │ consistent hash ring lookup
                              ▼
        ┌─────────────────────────────────────────────┐
        │           Consistent Hash Ring                │
        │  node A ── node B ── node C ── node D ── ...   │
        │  key K hashes between B and C → owned by       │
        │  C, D, E (N=3 successive nodes on the ring)     │
        └───────────┬──────────────┬──────────────┬──────┘
                     ▼              ▼              ▼
              ┌───────────┐  ┌───────────┐  ┌───────────┐
              │  Node C    │  │  Node D    │  │  Node E    │
              │ (replica)  │  │ (replica)  │  │ (replica)  │
              │ local store│  │ local store│  │ local store│
              └───────────┘  └───────────┘  └───────────┘
                     ▲              ▲              ▲
                     └──────────────┴──────────────┘
                     Gossip protocol: all nodes continuously
                     exchange membership/health info peer-to-peer
                     (no central coordinator for cluster state)

        Background per-node processes:
          - Hinted handoff receiver (temp writes for down peers)
          - Anti-entropy / read-repair (Merkle-tree diffing)
```

Data flow for a write: client sends `PUT(key, value)` to any node → that node
computes the key's position on the hash ring and identifies the N=3 nodes
responsible → forwards the write to all 3 (or fewer, if some are temporarily
unreachable, triggering hinted handoff) → waits for W acknowledgments before
returning success to the client. A read follows the same coordinator pattern,
querying R replicas and reconciling their responses (Step 6.3) before returning.

## Step 4: API Design

Since this is infrastructure, not a user-facing web app, the "API" is the
client-facing protocol/SDK surface (analogous to DynamoDB's or Cassandra's client
API):

```
PUT key=<string>, value=<bytes>, [consistency=ONE|QUORUM|ALL]
→ 200 OK { version_vector: {...} }
→ 503 { error: "insufficient_replicas_acked" }   # fewer than W acks received

GET key=<string>, [consistency=ONE|QUORUM|ALL]
→ 200 { value: <bytes>, version_vector: {...} }
→ 200 { conflicting_versions: [{value, version_vector}, ...] }  # if unresolved concurrent writes exist
→ 404 { error: "not_found" }

DELETE key=<string>, [consistency=...]
→ 200 OK    # implemented internally as a "tombstone" write, not a physical delete (see 6.2 note)

# Administrative/internal RPCs, not client-facing:
INTERNAL_REPLICATE(key, value, version_vector)   # coordinator → replica
INTERNAL_MERKLE_SYNC(key_range, tree_hash)         # replica ↔ replica, anti-entropy
GOSSIP_PING(node_id, membership_view)               # peer ↔ peer, every ~1s
```

The `consistency` parameter is the tunable-consistency knob from the requirements:
`ONE` returns as soon as any single replica acks (fastest, weakest guarantee),
`QUORUM` waits for a majority (the balanced default, detailed in 6.2), `ALL` waits
for every replica (strongest, slowest, least available under failure).

## Step 5: Data Model

There is deliberately no schema beyond key and value — this is the entire point of a
key-value store versus a relational database (cross-reference
`06_databases_fundamentals.md` on when a KV model is the right fit: no joins, no
query flexibility needed, in exchange for extreme horizontal scalability and
simplicity).

```
Logical record:
  key: string (or bytes)
  value: opaque bytes (the store doesn't interpret structure)
  version_vector: { node_id: counter, ... }   -- for conflict detection (Step 6.3)
  tombstone: bool                              -- marks logical deletion
  timestamp: for LWW mode, or as a tiebreaker
```

Per-node local storage engine: typically a log-structured merge-tree (LSM-tree)
based store (the same family as underlies Cassandra's SSTables or RocksDB), because
the workload is write-heavy-friendly and LSM-trees turn random writes into
sequential disk writes with a memtable + periodic flush-to-disk + background
compaction — a good match for the high sustained write throughput this kind of store
targets, and a deliberate contrast with a B-tree-based engine that would incur more
random I/O per write (cross-reference `12_storage_systems.md` and
`06_databases_fundamentals.md` for the LSM vs. B-tree trade-off).

## Step 6: Deep Dive

This system is explicitly the synthesis point for nearly every distributed-systems
concept covered elsewhere in this notes set — the value in this section is in
applying those concepts concretely to a single coherent system, not re-deriving
them.

### 6.1 Partitioning via Consistent Hashing

With 1 billion keys across 100 nodes, some way to decide which node(s) own which
keys is needed, and it needs to survive nodes joining/leaving without reshuffling
most of the data. This is the exact problem consistent hashing solves
(cross-reference `07_database_scaling.md`'s consistent hashing section — this system
is the practical, worked application of that concept, not a new idea).

Each node is assigned one or more positions ("tokens") on a fixed hash ring
(typically many virtual nodes per physical node — e.g., 256 virtual tokens each — to
spread load evenly and avoid one physical node getting a disproportionate hash range
just from bad luck). A key is hashed with the same hash function and placed on the
same ring; it's owned by the first node encountered walking clockwise from the key's
position, plus, for replication, the next N-1 distinct physical nodes continuing
clockwise. When a node joins, it takes over a contiguous slice of the ring from its
neighbors and only needs to receive the keys in that slice — not a full cluster
reshuffle. When a node leaves (planned or via failure), its ring range is absorbed
by its neighbor, again only moving that node's data rather than the whole dataset.
This is precisely why consistent hashing (versus naive `hash(key) % N`) is the right
partitioning strategy for a system built around nodes joining and leaving as a
routine, expected occurrence rather than a rare event.

### 6.2 Replication Factor N and Quorum Reads/Writes (W + R > N)

Given N=3 (each key stored on 3 distinct nodes per the ring walk above), the system
needs a rule for how many replicas must participate in a read or write to guarantee
correctness, and this is where the CAP/consistency trade-off (cross-reference
`08_cap_theorem_and_consistency.md`) becomes a concrete, tunable parameter rather
than an abstract theorem.

The quorum condition is **W + R > N**: if the number of replicas a write must reach
(W) plus the number of replicas a read must query (R) exceeds the replication factor
(N), then every read is mathematically guaranteed to overlap with the most recent
successful write on at least one replica, so the read can always find the latest
value (possibly needing to reconcile a couple of differing versions, Step 6.3, but
never missing the latest one entirely).

**Worked example: N=3, W=2, R=2.**
- A client issues `PUT(key, "v2")`. The coordinator sends the write to all 3
  replicas (R1, R2, R3) but only waits for W=2 acknowledgments before returning
  success to the client. Say R1 and R2 ack quickly; R3 is momentarily slow or
  unreachable (network blip) and the coordinator doesn't wait for it — the write is
  already considered durable and successful once 2 acks arrive. R3 will eventually
  get the write too, either from the coordinator retrying in the background or via
  hinted handoff / anti-entropy (6.4).
- Now a client issues `GET(key)`. The coordinator queries R=2 replicas — say it
  happens to pick R2 and R3. R2 has "v2" (it got the write). R3 might still have the
  old value "v1" (it hadn't received the write yet when queried). The coordinator
  receives both responses, sees they disagree, and needs to reconcile — but
  critically, **it is guaranteed that at least one of the R=2 replicas queried has
  the latest write**, because W=2 and R=2 out of N=3 means any 2-of-3 write set and
  any 2-of-3 read set must overlap by pigeonhole (2+2=4 > 3). So even in the worst
  case (R3 is the "stale" one selected), R2 is guaranteed to be among the queried
  set with the fresh value. The coordinator picks the value with the higher version
  (via the version vector or timestamp, 6.3) and returns "v2" to the client — and
  can optionally trigger a read-repair write back to R3 to bring it up to date
  immediately rather than waiting for background anti-entropy.
- Contrast: if the caller instead chose `consistency=ONE` for both read and write
  (W=1, R=1), W+R=2 is not > N=3, so there's no overlap guarantee — a read could
  easily hit the one replica that never got a particular write and silently return
  stale data. That's the explicit trade a caller makes for lower latency/higher
  availability (only 1 node needs to be up and fast) at the cost of consistency —
  exactly the CAP trade-off made tunable per-request rather than fixed for the whole
  system.

### 6.3 Conflict Resolution: Vector Clocks vs. Last-Write-Wins

Because W < N (in the example, W=2 out of N=3), and because network partitions or
concurrent clients can cause two different coordinators to accept writes to the same
key without seeing each other's write, replicas can genuinely diverge — not just
"some are behind," but holding truly concurrent, conflicting updates with no
inherent ordering between them. The system needs a defined way to detect and resolve
this (cross-reference `08_cap_theorem_and_consistency.md` and
`09_distributed_systems_core.md`).

**Vector clocks** are the general, correctness-preserving solution. Each value is
stored with a version vector — a map of `{node_id: counter}` recording, roughly,
"this version descends from having seen counter N from node X, counter M from node
Y, ...". When a node handles a write, it increments its own counter in the vector.
Comparing two version vectors tells you one of two things: either one vector's
counters are all ≥ the other's (meaning one write causally descends from the other —
no real conflict, just take the newer one), or neither dominates the other (meaning
the two writes were truly concurrent — happened without either client having seen
the other's update). In the second case, the store cannot safely pick one and
silently discard the other, because that could mean discarding real,
causally-independent user intent (this is exactly DynamoDB's original approach,
famously surfaced in the shopping-cart example: two concurrent "add item to cart"
writes shouldn't let one clobber the other — both are returned to the application as
sibling versions for it to merge, e.g. by unioning the cart contents).

**Last-write-wins (LWW) by timestamp** is the simpler, cheaper alternative: attach a
wall-clock (or hybrid logical clock) timestamp to every write, and on conflict,
whichever timestamp is later simply wins, discarding the other silently. This is far
simpler to implement and reason about, and is what Cassandra uses by default. The
explicit trade-off: LWW is lossy — if two truly concurrent writes happen close
together, one is silently and permanently discarded, which is unacceptable for
something like a shopping cart (you'd lose an item) but perfectly fine for something
like a device's last-reported sensor status (only the latest state matters, older
concurrent updates are genuinely irrelevant). A strong answer states this trade-off
explicitly rather than picking one mechanism as universally "better": vector clocks
preserve more information at the cost of implementation complexity and requiring the
application to handle sibling resolution; LWW is simple and fast but requires the
application's semantics to tolerate silently dropping one of two concurrent writes.

### 6.4 Handling Node Failure Gracefully: Hinted Handoff and Anti-Entropy

Nodes fail, transiently or permanently, constantly at this scale (100 nodes, real
hardware) — the design must keep serving writes during a temporary outage rather
than blocking or failing them, and must heal replicas back to consistency once nodes
recover.

**Hinted handoff** addresses the transient case. If a write's coordinator determines
that one of the key's N designated replicas is currently unreachable, rather than
failing the write (bad for availability) or simply skipping that replica forever
(bad for durability/replication factor), the coordinator hands the write to a
different, healthy node instead, along with a "hint" recording that this data
actually belongs to the down node. That substitute node stores the write
temporarily. Once the original replica comes back online (detected via gossip, 6.5),
the substitute node notices and forwards ("hands off") the hinted write to it, then
discards its temporary copy. This lets writes succeed at full replication intent
even during a node outage, at the cost of the temporarily-down replica being briefly
behind until handoff completes — an availability-favoring trade.

**Anti-entropy / read-repair** addresses longer-term drift — replicas that have been
out of sync for a while (a node down for hours, or hinted handoff itself
failing/expiring). A background process periodically compares each replica's data
against its peers for the same key range and reconciles differences. Doing this by
comparing every key individually would be prohibitively expensive at billions of
keys, so replicas instead compare **Merkle trees** — a hash tree where each leaf
hashes a small range of keys' data and each parent hashes the concatenation of its
children, up to a single root hash per key range. Two replicas first compare root
hashes; if they match, that entire range is provably identical and no further
comparison is needed. If they differ, the replicas recursively compare child hashes
to narrow down to exactly which sub-ranges (and eventually which specific keys)
actually differ, transferring only those — turning an O(all keys) comparison into
something closer to O(log(keys) + actual differences), which is what makes
background reconciliation of billions of keys practically feasible rather than a
full data re-transfer.

### 6.5 Gossip Protocol for Cluster Membership and Failure Detection

A system explicitly designed to have no single point of failure cannot rely on a
central coordinator to track "which nodes are alive" — that coordinator would itself
become the single point of failure the whole architecture is trying to avoid
(cross-reference `09_distributed_systems_core.md`). Instead, membership and failure
detection use a **gossip protocol**: periodically (e.g., once per second), each node
picks a small number of random peers and exchanges its current view of cluster state
(which nodes it believes are alive, their ring positions, any recent joins/leaves) —
information that has propagated to it via earlier rounds of gossip from other nodes.
Over a small number of rounds, information injected anywhere in the cluster (a new
node joining, a node being marked suspect) spreads to the entire cluster with high
probability, without any node needing to talk to all others or any single node
acting as the authority.

Failure detection typically layers a **phi accrual failure detector** (or simpler
heartbeat-timeout schemes) on top of gossip: rather than a binary "did the last
heartbeat arrive," each node tracks the historical inter-arrival time distribution
of heartbeats from each peer and computes a continuously-valued suspicion level,
marking a peer as failed only once that suspicion crosses a threshold — this
tolerates normal network jitter far better than a fixed timeout would, reducing
false-positive failure detection under momentary slowness. This decentralized
approach fits the system's core design goal directly: since there's no single node
whose failure can take down membership tracking, cluster health information degrades
gracefully and continues propagating through whichever nodes remain reachable,
exactly mirroring the no-single-point-of-failure principle applied to data itself (N
replicas) but applied here to cluster metadata.

## Step 7: Bottlenecks & Trade-offs

- **Hot keys still break consistent hashing's even distribution**: a small number of
  extremely popular keys can overload the specific nodes that happen to own them,
  regardless of how evenly the ring is balanced overall — mitigated by virtual nodes
  (spreading a physical node's *aggregate* load across many ring positions helps
  with uneven key distribution generally, but a single genuinely hot key still
  concentrates on its N owning replicas) and, for read-heavy hot keys specifically,
  an additional caching layer in front of the store or client-side/coordinator-side
  hot-key caching.
- **The W+R>N quorum trade-off is fundamentally a latency-vs-consistency knob, and
  it's per-operation, not global**: higher W/R (e.g., R=ALL) gives stronger
  guarantees but makes every operation as slow as its slowest required replica and
  less available during any node's failure; lower values (W=1, R=1) are fast and
  available but sacrifice the overlap guarantee — a well-designed system exposes
  this as a tunable per-request rather than forcing one global answer, since
  different keys/use-cases in the same cluster often want different points on that
  trade-off.
- **Vector clocks grow unboundedly** if not pruned — a key edited by many different
  nodes over time accumulates ever more entries in its version vector. Real systems
  cap this (pruning the oldest/least-relevant node entries once a size threshold is
  hit), trading a small amount of causal-history precision for bounded metadata
  size.
- **Anti-entropy is inherently a background, eventually-converging process** — it
  does not provide any bound on how quickly two replicas reconcile after diverging,
  only on how efficiently they compare data via Merkle trees when they do run.
  During that window, a `consistency=ONE` read against the stale replica can
  legitimately return old data; this is an accepted trade of the whole design, not a
  bug, and is exactly why `QUORUM` reads exist for callers who need the overlap
  guarantee instead.
- **Gossip convergence time grows with cluster size** (more nodes means more rounds
  needed for information to fully propagate) — at very large scale (thousands of
  nodes) this can make membership changes visible cluster-wide only after several
  seconds, which is acceptable for this system's purposes but is worth naming as a
  scaling limit of gossip specifically, distinct from the data-plane's own scaling
  limits.

## Follow-up Questions an Interviewer Might Ask

- **"How would you support range queries or secondary indexes, given consistent
  hashing scatters keys randomly?"** Explain this is fundamentally in tension with
  the design — consistent hashing deliberately destroys key ordering for
  load-balancing purposes, so range scans would require either a separate
  ordered-partitioning scheme (like Cassandra's option to trade even load
  distribution for range-query support) or an entirely separate secondary index
  structure maintained asynchronously, accepting eventual consistency on the index.
- **"What happens during a genuine network partition where the cluster splits into
  two halves that can't talk to each other?"** Walk through the CAP trade-off
  concretely: with W+R>N quorums, a client on the minority side of the partition
  typically cannot achieve quorum and its writes/reads fail (favoring consistency
  over availability for that request), while `consistency=ONE` operations can still
  proceed on both sides independently, guaranteeing availability but allowing the
  two sides to diverge until the partition heals and anti-entropy reconciles them.
- **"How would you handle a permanent node loss (disk failure, not transient), not
  just a temporary outage?"** Distinguish this from hinted handoff: a permanently
  lost node needs to be formally removed from the ring (via gossip-propagated
  membership change) and its key range's replicas re-replicated to a new node by
  streaming data from the surviving N-1 replicas of each affected key, not merely
  handed off hints.
- **"How do you keep hot-node imbalance from virtual nodes being unevenly
  assigned?"** Discuss that virtual node count per physical node is usually
  proportional to that node's actual capacity (so a beefier node gets more ring
  positions), letting heterogeneous hardware share load proportionally rather than
  assuming uniform node capacity.
- **"Would you use this system for something that needs multi-key transactions?"**
  No — explicitly call out that key-value stores of this shape intentionally
  sacrifice cross-key transactional guarantees for horizontal scalability and
  availability; a workload needing multi-key ACID transactions belongs on a
  different class of system (a distributed SQL database with a consensus-based
  commit protocol), a deliberate scope boundary worth stating rather than trying to
  bolt on.
- **"How would consensus protocols like Raft or Paxos fit into this design, if at
  all?"** Clarify that this design intentionally avoids needing cluster-wide
  consensus for the data path (that's what makes it highly available and
  gossip-based), but a component like cluster configuration changes (formally
  adding/removing a node from the ring) sometimes does use a lightweight consensus
  mechanism or an external coordination service, which is a narrower, rarer use than
  what a fully consensus-based system (like a distributed SQL database) would need
  it for on every write.

