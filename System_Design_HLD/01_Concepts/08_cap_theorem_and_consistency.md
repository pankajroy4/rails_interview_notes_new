# CAP Theorem and Consistency Models

Once a database is replicated across multiple machines (`07_database_scaling.md`),
a new question becomes unavoidable: when those machines can't talk to each
other, what does your system do? **CAP theorem** is the formal framework for
that question, and **consistency models** describe the range of answers a
distributed system can give about how fresh the data it returns actually is.

## Why it matters

Networks fail. Not hypothetically — in any system with more than one
machine, some machines will, at some point, be unable to reach others: a
switch fails, a data center link is saturated, a node is overloaded and
stops responding in time. Without understanding CAP and consistency models:

- You'll design a system that silently assumes network partitions never
  happen, and it will behave unpredictably (or catastrophically) the first
  time one does.
- You won't be able to explain *why* your NoSQL database sometimes returns
  stale data, or *why* your relational database sometimes refuses to serve
  reads during a failover — both are direct, deliberate consequences of a
  CAP choice, not bugs.
- You'll struggle to size how many replicas need to agree (quorum) to get
  the consistency guarantee you actually need, and either over-pay for
  consistency you didn't need or under-pay and silently lose correctness.

## CAP Theorem, Precisely

CAP theorem states: in the presence of a network **P**artition, a
distributed system must choose between **C**onsistency (every read
receives the most recent write, or an error) and **A**vailability (every
request receives a non-error response, even if it isn't the most recent
data).

- **Consistency** here means *linearizability* — every client sees the same
  data at the same time, as if there were only one copy.
- **Availability** means every request that reaches a working node gets
  *some* response — the system never simply refuses to answer.
- **Partition tolerance** means the system continues operating despite
  network partitions (some nodes unable to communicate with others).

**The key insight**: Partition tolerance isn't really a "choice" the way C
and A are. In any real distributed system spanning more than one machine (or
more than one rack, data center, or region), network partitions **will**
happen — it's a physical inevitability, not a design decision you can opt
out of. So CAP theorem in practice isn't "pick 2 of 3" — it's: **a
partition is going to happen eventually; when it does, does this system
choose C or A for that moment?** A system that isn't partition-tolerant at
all isn't a real distributed system — it's a single machine, which sidesteps
the question but also isn't the system CAP is describing.

```text
Normal operation (no partition):
[Node A] <---> [Node B]     both consistent AND available, no trade-off needed

Partition occurs:
[Node A]   X   [Node B]     A and B can't talk to each other
   |                |
   can respond       can respond
   (but might        (but might
   diverge from B)    diverge from A)

  Choose C: refuse to serve some requests until partition heals
            (protect consistency, sacrifice availability)
  Choose A: keep serving from both sides, values may diverge
            (protect availability, sacrifice consistency)
```

## Common Misconceptions

- **"CAP means you always sacrifice one of the three."** False — CAP is a
  statement about behavior *during a partition specifically*. When there's
  no partition, a well-designed system can be both consistent and
  available simultaneously; the trade-off is only forced at the moment
  network communication between nodes actually breaks.
- **"CAP tells you about latency."** It doesn't, directly — CAP is about
  correctness (consistency) versus responsiveness (availability) under
  partition, not about how fast normal, non-partitioned requests are.
  PACELC (below) is the extension that brings latency in explicitly.
- **"A system IS CP or AP, globally, for everything."** Also an
  oversimplification — CAP applies per operation, and real systems often
  make different choices for different operations or even let you choose
  per-request (see the Cassandra/DynamoDB tunable consistency note below).
  Calling an entire system "AP" is a useful shorthand for its *default*
  behavior, not an absolute, universal guarantee about every code path in
  it.

## PACELC — The More Complete Extension

CAP only describes behavior *during* a partition. **PACELC** extends it to
cover normal operation too: **if there is a Partition (P), trade off
Availability and Consistency (A/C); Else (E — no partition), trade off
Latency and Consistency (L/C)**.

The "Else" branch matters because even with a perfectly healthy network,
there's still a cost to strong consistency: getting every replica to agree
on a value before responding requires **coordination** — round trips
between nodes to confirm they all have (or will have) the same data before
acknowledging a read or write. That coordination takes time. So even absent
any partition, a system has to choose: wait for that coordination (higher
latency, strong consistency) or respond immediately from local/nearby data
that might be slightly stale (lower latency, weaker consistency). This is
why even single-region, well-connected systems still make deliberate
consistency/latency trade-offs — it's not purely a failure-scenario
concern.

## Consistency Models

Different systems (and even different operations within the same system)
promise different things about how fresh a read is relative to the most
recent write.

- **Strong consistency**: every read reflects the most recent completed
  write, no matter which replica serves it. Example: a traditional
  single-leader relational database, where reads that go to the leader (or
  a synchronously-replicated follower) always see the latest committed
  data.
- **Eventual consistency**: after a write, reads *may* return stale data
  for some period, but if no new writes occur, all replicas will
  eventually converge to the same value. Example: a DNS update — after you
  change a domain's IP address, some resolvers around the world may serve
  the old IP for minutes to hours (due to caching and propagation delay)
  before every resolver converges on the new value.
- **Causal consistency**: operations that are causally related (one
  happened because of, or after seeing, another) are observed in that same
  order by everyone; operations with no causal relationship may be seen in
  different orders by different observers. Example: if user A posts a
  comment and user B replies to it, every viewer must see A's comment
  before B's reply (they're causally linked) — but two unrelated comments
  posted by different users at the same time can appear in either order to
  different viewers without breaking anything.
- **Read-your-writes consistency**: a specific guarantee that a user who
  just performed a write will always see that write on their own
  subsequent reads, even if other users don't see it yet (because it
  hasn't propagated to the replicas serving them). Example: you update your
  own profile photo and immediately see the new photo on your own screen,
  even though a friend viewing your profile at that exact moment might
  briefly still see the old one. This is exactly the fix for the
  replication-lag symptom described in `07_database_scaling.md` — read-
  your-writes is typically implemented by routing a user's own
  post-write reads to the leader (or a replica confirmed caught up)
  specifically.

| Model | Guarantee | Real example |
|---|---|---|
| Strong | Every read sees the latest write | Single-leader RDBMS reading from the leader |
| Eventual | Reads may be stale, converge over time | DNS propagation after a record change |
| Causal | Causally related ops seen in order; unrelated ops can reorder | Comment/reply threads |
| Read-your-writes | You always see your own writes immediately | Your own profile update appearing instantly for you |

## Quorum Reads and Writes

In leaderless (Dynamo-style) replication, consistency is tuned via a
**quorum** — requiring a minimum number of replicas to participate in a
read or write, rather than requiring *all* of them (which would kill
availability) or just *one* (which would kill consistency).

Define:

- **N** = total number of replicas holding a piece of data.
- **W** = number of replicas that must acknowledge a write before it's
  considered successful.
- **R** = number of replicas that must be queried (and their results
  reconciled) for a read to be considered successful.

**The rule**: if **W + R > N**, every possible read set and every possible
write set is guaranteed to overlap by at least one node — meaning any read
quorum is guaranteed to include at least one replica that has the most
recent write, so the read can always find (and return) the latest value.
This is what gives leaderless replication a strong consistency guarantee
*without* a single leader coordinating every operation.

**Worked example**: N=3, W=2, R=2.
- A write must be acknowledged by at least 2 of the 3 replicas before
  it's considered committed.
- A read must query at least 2 of the 3 replicas.
- W + R = 4 > N = 3, so any 2-out-of-3 write set and any 2-out-of-3 read
  set are mathematically guaranteed to share at least one common replica
  — that shared replica has the latest write, so the read is guaranteed to
  see it (after reconciling, e.g., picking the value with the latest
  timestamp/version among the replicas queried).
- If instead W=1 and R=1 (W+R=2, not > N=3), a write could land on replica
  A only, and a read could query replica B only — no overlap, so the read
  could return stale data. This is a valid, deliberate configuration when
  you want maximum speed/availability and can tolerate eventual (not
  strong) consistency.

```text
N = 3 replicas: [R1] [R2] [R3]
W = 2: write acknowledged by any 2, e.g. {R1, R2}
R = 2: read queries any 2, e.g. {R2, R3}
Overlap: {R1,R2} ∩ {R2,R3} = {R2}  -> guaranteed to see the write
```

Tuning W and R is a direct lever on the latency/consistency/availability
trade-off: lower W and R means faster, more available operations (fewer
nodes need to respond) but weaker consistency guarantees; higher W and R
(up to W=R=N) means stronger consistency but higher latency and lower
availability (more nodes must be reachable and responsive for any
operation to succeed).

## Vector Clocks

**Why simple timestamps aren't enough**: in a distributed system, each node
has its own physical clock, and clocks across machines are never perfectly
synchronized (clock skew) — there is no single global "now." If two writes
to the same key happen on two different nodes and you try to determine
which "came first" using wall-clock timestamps, clock skew can give you the
wrong answer, and worse, it can't even tell you whether the two writes were
truly *concurrent* (neither caused the other, both are independently
valid) versus one genuinely happening after the other.

**What a vector clock captures instead**: a vector clock is a vector of
per-node counters — one counter per node that has touched the data,
incremented by that node on each write, and merged (taking the max of each
position) whenever nodes exchange information. By comparing two vector
clocks, the system can determine one of three relationships:

- One vector clock strictly dominates the other (every counter is ≥, at
  least one is >) — meaning that write genuinely happened *after* and
  *aware of* the other; the newer one safely supersedes it.
- The clocks are identical — same write, no conflict.
- **Neither dominates the other** (each has at least one counter higher
  than the other) — meaning the two writes happened **concurrently**,
  neither aware of the other, and this is a genuine conflict that must be
  surfaced (to the application, or to the user, as in the classic "merge
  your shopping cart" resolution Amazon's original Dynamo paper used) —
  rather than silently picking one and losing data, the way a naive
  "latest timestamp wins" approach would.

Vector clocks are how leaderless systems detect real write conflicts
without relying on a global clock — they encode causality (who knew about
whom) instead of wall-clock time.

## Real Systems, Grounded

| System | CAP leaning | Why |
|---|---|---|
| Traditional single-leader RDBMS (PostgreSQL, MySQL) | CP-leaning (or effectively unavailable during partition) | A partitioned follower either serves potentially stale data (breaking C) or the system routes all reads/writes to the leader only, becoming unavailable to clients that can't reach it — most configurations favor not serving incorrect data over serving *something* |
| Cassandra / DynamoDB | Tunable per-request (AP-leaning by default) | Leaderless with quorum-based W/R — you can dial toward strong consistency (W+R>N) or toward availability/low-latency (small W and R) per operation, but the systems are architected with availability as the default priority |
| ZooKeeper / etcd | CP by design | Purpose-built for consistent coordination (leader election, distributed locks, configuration) — for these use cases, serving stale or divergent data is actively dangerous (e.g., two nodes both believing they're the leader), so these systems deliberately sacrifice availability during a partition rather than risk incorrect coordination state |

## Trade-offs

| Decision | Favor Consistency (C) | Favor Availability (A) |
|---|---|---|
| During a partition | Reject/block requests that can't be guaranteed fresh | Keep serving all requests, reconcile divergence later |
| Quorum sizing | High W and R (up to W=R=N) | Low W and R (e.g., W=1, R=1) |
| Use case fit | Financial transactions, coordination/locking (leader election), inventory counts | Social feeds, shopping carts, "likes," presence indicators — situations where staleness is a minor UX issue, not a correctness issue |

There's no universal right answer — this is the single most fundamental
trade-off in distributed systems, and the right choice depends entirely on
whether *briefly wrong data* or *briefly no data* is worse for the specific
operation in question.

## Interview Tips

- CAP theorem comes up constantly, and the single most common mistake
  candidates make is saying a system "is CP" or "is AP" as an unqualified,
  global statement. State it per operation/data type instead — e.g., "the
  order/payment path should be CP because overselling inventory is
  worse than a brief unavailability; the product-recommendation path can
  be AP because stale recommendations are harmless."
- Interviewers often ask "what happens during a network partition?"
  specifically to see if you understand that partition tolerance isn't
  optional — a real distributed answer never says "the network never
  partitions," it says what the system does when it does.
- Mentioning PACELC unprompted, and specifically the Latency/Consistency
  trade-off during *normal* operation (not just during failures), is a
  strong signal — it shows you understand CAP is an incomplete picture on
  its own.
- If asked to design something requiring coordination (leader election, a
  distributed lock, unique ID generation) — reach for CP systems like
  ZooKeeper/etcd explicitly and explain why availability is the acceptable
  sacrifice there.
- Quorum math (W+R>N) is a common concrete follow-up — be ready to work
  through a small numeric example live, the way the N=3/W=2/R=2 case above
  does, not just cite the formula.

## Quick Recall — Self-Test

**1. Why is "partition tolerance" not really a free choice in CAP theorem?**
Network partitions are a physical inevitability in any system spanning more than one machine — you can't design them away. So CAP in practice reduces to: when a partition happens (not if), does the system choose Consistency or Availability for that moment?

**2. Correct this statement: "Our system is AP, so it never guarantees consistency for anything."**
CAP trade-offs apply per operation, not globally to an entire system — many systems described as "AP" (like Cassandra) let you tune specific operations toward strong consistency (e.g., via quorum settings) while defaulting to availability elsewhere. And CAP's consistency/availability trade-off only applies during an actual partition; outside of one, a system can be both consistent and available.

**3. What does PACELC add that CAP alone doesn't cover?**
CAP only describes the trade-off during a network partition. PACELC adds the "Else" branch: even with no partition, achieving strong consistency requires coordination between replicas, which costs latency — so there's a Latency/Consistency trade-off during completely normal operation too.

**4. Give a concrete example that distinguishes causal consistency from eventual consistency.**
Under eventual consistency, any two writes might be seen in any order temporarily, with only an eventual guarantee of convergence. Under causal consistency, if user B's reply is causally dependent on user A's original comment, every viewer is guaranteed to see A's comment before B's reply — but two independent, unrelated comments posted at the same time have no such ordering guarantee and can appear in different orders to different viewers.

**5. Walk through why W+R > N guarantees a read sees the latest write, using N=3, W=2, R=2.**
Any write must be acknowledged by 2 of the 3 replicas, and any read must query 2 of the 3 replicas. Since there are only 3 replicas total, any two 2-out-of-3 subsets are mathematically guaranteed to share at least one replica — that shared replica holds the latest write, so it's always included in the read's results, guaranteeing the read can see it.

**6. Why can't you just use wall-clock timestamps to determine which of two concurrent writes "came first" in a distributed system?**
Clocks on different machines are never perfectly synchronized (clock skew), so timestamp comparisons across nodes can be wrong. Worse, timestamps can't distinguish "this write genuinely happened after that one" from "these two writes happened concurrently and neither caused the other" — which is exactly the distinction that matters for conflict detection.

**7. What does it mean for two vector clocks to be "concurrent" (neither dominates the other), and why does that matter?**
It means each vector clock has at least one per-node counter higher than the other's — neither write was aware of the other when it happened, so they're a genuine conflict, not one superseding the other. This matters because a system that blindly picked one (e.g., "latest timestamp wins") could silently discard valid data; detecting true concurrency lets the system surface the conflict for proper resolution instead.

**8. Why is ZooKeeper/etcd deliberately CP rather than AP?**
They're built specifically for consistent coordination tasks like leader election and distributed locking, where serving stale or divergent data is actively dangerous — for example, two nodes could each believe they're the leader if the coordination service served inconsistent state during a partition. For that use case, refusing to answer (losing availability) is safer than answering incorrectly.
