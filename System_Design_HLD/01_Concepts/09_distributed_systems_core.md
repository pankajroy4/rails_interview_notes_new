# Distributed Systems Core

## Why distributed systems are fundamentally hard

A distributed system is a set of independent machines (nodes) that communicate over a network and must appear, to the outside world, to work together as one coherent system. The difficulty isn't the business logic — it's three properties of the underlying environment that single-machine programming never has to deal with:

- **Partial failure**: in a single process, if something goes wrong, the whole thing crashes and you know it crashed. In a distributed system, some nodes can fail while others keep running fine, and — this is the hard part — a healthy node often **cannot tell the difference** between "that other node is dead," "that other node is just slow," and "the network between us is dropping packets." All three look identical: no response arrived in time.
- **No shared global clock**: each machine has its own local clock, and clocks drift relative to each other (typically milliseconds to seconds per day without correction). You cannot simply compare timestamps from two different machines and trust that the earlier timestamp happened first in reality.
- **Unreliable, asynchronous networks**: messages can be delayed by an unpredictable amount, dropped entirely, duplicated, or delivered out of order. There is no upper bound you can assume on how long a message might take to arrive (this is what "asynchronous network" means here — not non-blocking I/O, but "no timing guarantees").

Put together, these three facts mean a distributed system can never be 100% sure of the current global state at any instant — it can only reason probabilistically and build protocols that tolerate the uncertainty instead of assuming it away.

## Why it matters

Without accounting for these realities, distributed systems fail in specific, recurring ways:

- **Split brain**: two nodes both believe they are "the leader" (e.g., after a network partition), and both accept writes — leading to conflicting, unreconcilable data.
- **Lost or duplicated work**: a client retries a request because it didn't get a response in time, not realizing the original request actually succeeded — now the action (e.g., "charge the card") happens twice.
- **Stuck systems**: a coordinator crashes mid-protocol (classically, in Two-Phase Commit) and leaves other nodes holding locks forever, waiting for a message that will never come.
- **Silent data corruption from clock skew**: two writes are ordered by wall-clock timestamp, but the machine that made the *later* write actually had a clock running a few seconds *behind*, so the "later" write is stored as if it happened first, silently overwriting the real latest value.

The entire point of the concepts below — consensus, replication protocols, idempotency, distributed locks, logical clocks — is to build reliable, coordinated behavior out of components that are individually unreliable and uncoordinated by default.

## The consensus problem

**Consensus** is the problem of getting a set of nodes to agree on a single value, once, even though some nodes might crash or messages might be delayed — and once agreed, that value is final for all nodes.

Why you need it:
- **Leader election**: exactly one node in a cluster must be designated "the leader" (e.g., the one allowed to accept writes) — if two nodes both think they're the leader, you get split brain.
- **Agreeing on the order of operations in a replicated log**: if a piece of data is replicated across multiple nodes, every replica must apply writes in the *same order*, or they'll diverge into different states. Consensus is what lets a cluster agree on "operation #57 is X" identically everywhere.

Consensus is provably impossible to solve with a guarantee of both correctness and termination in a fully asynchronous network with even one faulty node (the FLP impossibility result) — in practice, real systems sidestep this by using timeouts and accepting a small chance of temporarily not making progress (safe but occasionally slow) rather than ever being wrong.

### Paxos

**Paxos** is the original, foundational consensus algorithm. You will not need to prove it correct in an interview — you need the high-level shape:

- **Proposers** suggest values to be agreed upon.
- **Acceptors** vote on proposed values.
- A value is **chosen** once a **majority** (quorum) of acceptors have accepted it.

The key insight that makes this tolerate failures: because a value only needs a *majority*, not *all* nodes, the system keeps working as long as a majority of nodes are up and reachable — a minority can crash, or be slow, or be network-partitioned away, and consensus still proceeds. And because any two majorities out of the same set of nodes must overlap by at least one node, it's impossible for two *different* values to each separately get a majority — that overlapping node would have had to accept both, which the protocol's voting rules prevent. That overlap property is the whole reason majority-based agreement is safe.

Paxos is notoriously hard to understand and implement correctly in its full form (multiple sub-protocols to handle competing proposers, etc.) — which is precisely the gap Raft was designed to close.

### Raft

**Raft** was explicitly designed as a more understandable alternative to Paxos, decomposing consensus into two separable sub-problems you can reason about independently: leader election and log replication.

**Leader election:**
- Time is divided into **terms** (monotonically increasing numbers, like an "epoch" for who's in charge).
- Nodes start as followers. If a follower doesn't hear a **heartbeat** from a leader within a timeout, it becomes a candidate, increments the term, and requests votes from other nodes.
- Each node votes for at most one candidate per term (first valid request wins its vote). A candidate that gets votes from a **majority** of nodes becomes leader for that term.
- Randomized election timeouts (each node waits a random amount before starting an election) reduce the chance of multiple nodes becoming candidates simultaneously and splitting the vote.

**Log replication:**
- All writes go through the leader. The leader appends the operation to its own local log, then sends it to all followers.
- Once a **majority** of nodes (leader included) have durably stored the entry, the leader considers it **committed** and applies it to its state machine, then informs followers they can do the same.
- If the leader dies, a new election happens; the newly elected leader is guaranteed (by the election rules) to have the most up-to-date committed log, so no committed data is lost.

```text
   Client write
        |
        v
   +----------+   replicate   +-----------+
   |  Leader  |--------------->| Follower A|
   +----------+                +-----------+
        |        replicate     +-----------+
        +---------------------->| Follower B|
                                +-----------+
   Committed once a MAJORITY (leader + 1 follower here) have the entry.
```

Raft is what you should reach for by name in an interview when asked "how does this cluster agree on who's the leader / on the order of writes" — it's the industry-common answer (etcd, Consul, and many other real systems implement Raft specifically because of its understandability).

### Leader election in practice: coordination services

Almost no company reimplements Paxos or Raft from scratch inside their application — that's genuinely hard to get right (subtle bugs cause data loss). Instead, systems delegate leader election and shared configuration management to a **coordination service** — a small, separately-run cluster whose entire job is to run consensus correctly and expose it as a simple API (locks, leader-election primitives, a small consistent key-value config store).

- **ZooKeeper**: built on a Paxos-like protocol (ZAB); widely used (historically by Kafka, HBase, and many others) for leader election and distributed configuration.
- **etcd**: built directly on Raft; used by Kubernetes as its entire cluster state store, and commonly used elsewhere for leader election and service configuration.

The pattern in an interview: "instead of building consensus myself, I'd run an etcd/ZooKeeper cluster and have each service instance try to acquire a leader lock there" is a strong, realistic answer.

## Gossip protocol

A **gossip protocol** (epidemic protocol) is how nodes in a large cluster share state without a central coordinator: periodically (e.g., once a second), each node picks a few random peers and exchanges what it currently knows (cluster membership, node health, metadata) with them. Over several rounds, information propagates exponentially through the cluster — similar to how a rumor spreads through a population — until every node eventually converges on the same view.

Why it's used for **cluster membership** and **failure detection** at scale (e.g., in Cassandra, and Dynamo-style systems generally):
- No single node is a bottleneck or single point of failure for membership info — there's no central "membership server" to overload or lose.
- It scales well: the load per node stays roughly constant regardless of cluster size, because each node only ever talks to a handful of random peers per round, not the whole cluster.
- It's inherently resilient to partial failures — a few unreachable nodes don't stop the rest of the cluster from converging, they just get marked as failed once enough peers report not hearing from them.

The trade-off is that gossip is **eventually consistent** — it takes some number of rounds (typically seconds) for a state change (e.g., "node X just died") to propagate everywhere, so there's a window where different nodes have different views of cluster membership.

## Distributed transactions

A distributed transaction spans multiple independent nodes/services, and all of them must either all commit or all roll back — no partial application.

### Two-Phase Commit (2PC)

2PC is the classic protocol for making a single atomic decision across multiple participants, coordinated by one **coordinator** node:

1. **Prepare phase**: the coordinator asks every participant "can you commit this?" Each participant does whatever work is needed to guarantee it *can* commit if told to (e.g., acquires locks, writes to a durable log) and replies yes/no.
2. **Commit phase**: if *all* participants said yes, the coordinator tells everyone to commit. If *any* said no (or timed out), the coordinator tells everyone to abort.

```text
Coordinator          Participant A        Participant B
    |-- PREPARE ------->|                     |
    |-- PREPARE --------------------------->|
    |<-- YES ------------|                     |
    |<-- YES ---------------------------------|
    |-- COMMIT --------->|                     |
    |-- COMMIT ------------------------------>|
```

**Why it's fragile**: participants that voted "yes" have already taken locks and are waiting for the final decision — they cannot unilaterally decide to commit or abort, because the coordinator might still tell the *other* participant something different. If the **coordinator crashes after the prepare phase but before sending the commit/abort decision**, every participant is stuck holding its locks indefinitely, unable to proceed on their own (this is called being "blocked"). This is 2PC's core weakness: it trades correctness for availability during coordinator failure.

### Saga pattern

The **Saga pattern** is the microservices-era alternative for operations that span multiple services, and it deliberately avoids holding distributed locks. A saga is a sequence of local transactions, each in one service, where every step has a paired **compensating action** — a step that undoes its effect if a later step in the sequence fails.

Example — an order-payment-inventory saga for "place an order":
1. Order service creates the order (status: pending).
2. Payment service charges the customer.
3. Inventory service reserves stock.

If step 3 fails (out of stock), the saga runs compensations in reverse: refund the payment (compensates step 2), cancel the order (compensates step 1). There was never a distributed lock held across all three services — each step committed locally and immediately, and failure is handled by *undoing*, not by *rolling back a transaction that never fully committed*.

**Choreography vs orchestration** — two ways to drive the sequence:

| | Choreography | Orchestration |
|---|---|---|
| How it works | Each service publishes events; other services subscribe and react independently | A central orchestrator explicitly calls each service in sequence and tracks saga state |
| Example flow | Order service emits `OrderCreated` → Payment service listens, charges, emits `PaymentCompleted` → Inventory service listens, reserves stock | A saga orchestrator calls "create order," then calls "charge payment," then calls "reserve inventory," handling failures itself |
| Coupling | Loose — services don't know about each other directly, only events | Orchestrator knows about and depends on every participant |
| Visibility into overall flow | Hard — logic is smeared across services' event handlers | Easy — the whole sequence lives in one place |
| Best for | Simple sagas, few steps | Complex sagas, many steps, need for central error handling/monitoring |

Neither is strictly better: choreography keeps services decoupled but makes the end-to-end flow hard to reason about or debug ("who's supposed to react to this event?"); orchestration makes the flow explicit and easy to monitor but re-introduces a central component that every participant depends on.

## Idempotency

Because networks are unreliable, **retries are unavoidable**: if a client sends a request and gets no response before its timeout, it genuinely cannot tell whether the request never arrived, arrived but the server crashed before finishing, or the server finished successfully but the *response* was lost on the way back. The only safe assumption is "it might not have worked," so the client retries — but that means the server must be prepared to receive the *same* logical request more than once.

**Idempotency** is the property that processing the same request multiple times produces the same result as processing it once — no matter how many times it's retried.

The standard mechanism: an **idempotency key** — a unique identifier the *client* generates once per logical operation and attaches to every retry of that same request (e.g., a UUID sent as a header on a "charge $50" payment request). The server stores which idempotency keys it has already processed (with the result); if a request arrives with a key it's seen before, it returns the stored result instead of re-executing the operation. This turns "retry until you get a response" from a dangerous operation (double-charging a customer) into a safe one.

Note the distinction from the delivery-semantics discussion in `10_message_queues_and_streaming.md`: idempotency is what makes "at-least-once delivery" safe to treat as if it were "exactly-once" from the caller's perspective.

## Distributed locks

A **distributed lock** provides mutual exclusion across separate processes or machines — ensuring, for example, that only one worker in a fleet processes a given job at a time, even though any of them could pick it up.

Common implementations:
- **Redis `SETNX` with a TTL**: `SET lock_key unique_value NX PX 30000` atomically sets the key only if it doesn't already exist, with a time-to-live so the lock auto-expires if the holder crashes without releasing it. Simple and fast, but a single Redis instance is a single point of failure for the lock.
- **Redlock**: a Redis-specific algorithm that acquires the lock across a majority of independent Redis instances, intended to be safer under node failure than a single-instance lock (though it's genuinely debated in the distributed-systems community whether it provides strong enough guarantees for correctness-critical use cases).
- **ZooKeeper ephemeral nodes**: a client creates an ephemeral znode (which ZooKeeper automatically deletes if the client's session dies) to represent lock ownership — leans on ZooKeeper's own consensus guarantees rather than TTL-based expiry.

**The classic pitfall**: TTL-based locks assume the holder will finish its work and release the lock (or fail and let it expire) within the TTL window. But if the lock holder pauses unexpectedly — a long GC pause, a slow disk I/O stall, a suspended VM — for *longer* than the TTL, the lock expires and another process acquires "the same" lock while the first process is still alive and about to resume work, believing it still holds it. Now two processes think they exclusively own the resource.

**The fix, briefly**: **fencing tokens** — the lock service hands out a monotonically increasing number every time the lock is granted. Every write the lock holder makes to the protected resource must include its fencing token, and the resource (e.g., a storage service) rejects any write carrying a token *older* than the latest one it has already seen. So even if a stale lock holder wakes up and tries to act, its outdated token gets rejected.

## Clock synchronization

**NTP (Network Time Protocol)** synchronizes each machine's wall-clock time against reference time servers, keeping clocks roughly in sync (typically within tens of milliseconds on well-configured networks, though this degrades under network issues or VM scheduling).

**Why wall-clock time still can't be fully trusted for ordering events across machines**: even with NTP, clocks are never perfectly synchronized — there's always some drift and correction lag, and a correction can even make a clock jump backward. If you order two events on different machines purely by their wall-clock timestamps, you can get the order wrong — event B might be timestamped earlier than event A even though A actually caused B.

**Logical clocks — Lamport timestamps**: instead of trying to measure real time, a logical clock captures **causality** ("happened-before" relationships) directly. Each node keeps a counter; it increments the counter before each local event, and whenever it sends a message it includes its current counter value, and the receiver sets its own counter to `max(local counter, received counter) + 1` on receipt. This guarantees that if event A causally influenced event B (e.g., A's message was received before B happened), then A's Lamport timestamp is strictly less than B's — a real time-based clock cannot make that guarantee, but a logical clock can, because it derives ordering purely from the message-passing relationships, not from the possibly-untrustworthy wall clock.

## Trade-offs / When to use what

| Need | Reach for |
|---|---|
| Cluster-wide agreement on a single value, leader election | Consensus (Raft/Paxos) — usually via etcd/ZooKeeper, not reimplemented |
| Fast, low-overhead cluster membership / failure detection at scale | Gossip protocol |
| Atomic all-or-nothing commit across a few tightly-coupled resources you fully control | 2PC — but know it blocks on coordinator failure; rare in modern microservice designs |
| Atomic-feeling multi-service workflow in a microservices architecture | Saga (choreography for simple/few steps, orchestration for complex/many steps) |
| Safety under client retries | Idempotency keys |
| Exclusive access to a shared resource across processes | Distributed lock + TTL + fencing tokens |
| Ordering events without trusting wall-clock time | Logical clocks (Lamport timestamps) |

## Interview Tips

- "How would you ensure only one instance of this cron job runs across your fleet?" is a distributed-lock question — mention TTL, the crash/expiry pitfall, and fencing tokens; that last detail signals depth.
- "How do these replicas agree on who's primary?" is a leader-election/consensus question — naming Raft's leader election + log replication (terms, heartbeats, majority commit) is the expected depth; you are not expected to derive Paxos's correctness proof.
- "The payment API call timed out — what do you do?" is testing idempotency reasoning: you should immediately say "retry with the same idempotency key" rather than "just retry," and explain why a naive retry risks a double charge.
- If asked to design a cross-service checkout/order flow, proactively bring up the Saga pattern instead of "wrap it all in a distributed transaction" — interviewers read 2PC-across-microservices as a red flag for production designs.
- "Why not just use timestamps to order these events?" is probing whether you understand clock skew — mention NTP's limits and pivot to logical clocks/happened-before if the question is about correctness-critical ordering.

## Quick Recall — Self-Test

**Q1: What are the three properties of distributed environments that make them fundamentally harder than single-machine programming?**
Partial failure (some nodes fail while others work, and you often can't tell which), no shared global clock (clocks drift independently), and unreliable/asynchronous networks (messages can be delayed, dropped, duplicated, or reordered with no guaranteed bound).

**Q2: Why does majority-based agreement (as in Paxos/Raft) tolerate a minority of node failures safely?**
Any two majorities drawn from the same set of nodes must share at least one common node, so two different values can never each independently win a majority — that shared node would have had to accept both, which the protocol prevents. This means the system stays both correct and available as long as a majority of nodes are reachable.

**Q3: What is the core weakness of Two-Phase Commit, and how does the Saga pattern avoid it?**
If the coordinator crashes after the prepare phase but before sending the final commit/abort decision, participants are left blocked holding locks indefinitely. Sagas avoid this by never holding a cross-service lock at all — each step commits locally and immediately, and failures are handled afterward via compensating actions that undo completed steps.

**Q4: Why can't a client simply avoid retries to sidestep idempotency concerns?**
Because a client that doesn't get a timely response cannot distinguish "the request never arrived," "it arrived but the server crashed before finishing," and "it succeeded but the response was lost" — retrying is the only way to make progress under network unreliability, so the server must be built to handle duplicate requests safely.

**Q5: A worker holds a Redis-based distributed lock with a 30-second TTL, then experiences a 45-second GC pause. What goes wrong, and what fixes it?**
The lock expires at 30 seconds while the worker is still paused and believes it holds it; another worker can then acquire the same lock, and both end up believing they have exclusive access once the first resumes. Fencing tokens fix this: each lock grant carries a monotonically increasing token, and the protected resource rejects any write carrying an older token than the latest it has seen.

**Q6: Why is Raft described as "more understandable" than Paxos, and what are its two main sub-problems?**
Raft decomposes consensus into two separable, independently reasoned-about parts — leader election (terms, votes, heartbeats, randomized timeouts) and log replication (leader appends and replicates entries, commits once a majority acknowledge) — instead of Paxos's more tangled, harder-to-implement-correctly protocol for handling competing proposers.

**Q7: Why do most companies use ZooKeeper or etcd instead of implementing Paxos/Raft themselves?**
Because implementing consensus correctly is genuinely difficult and bugs cause data loss or split-brain; coordination services run a well-tested consensus protocol internally (ZAB for ZooKeeper, Raft for etcd) and expose a simple locking/leader-election/config API, so application teams get the guarantees without owning the hard distributed-systems code.

**Q8: Why is gossip preferred over a central coordinator for cluster membership in systems like Cassandra?**
A central coordinator is a bottleneck and single point of failure at scale. Gossip has no such single point: each node only talks to a few random peers per round, so per-node load stays roughly constant as the cluster grows, and the cluster still converges even when some nodes are unreachable — at the cost of only eventual (not immediate) consistency of the membership view.
