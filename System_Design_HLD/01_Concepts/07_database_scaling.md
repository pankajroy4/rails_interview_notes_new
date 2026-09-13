# Database Scaling

A single database server, no matter how powerful, eventually hits a wall:
vertical scaling (bigger machine) runs into hard hardware ceilings and its
cost grows non-linearly as you approach the biggest machines available (see
`02_scalability_and_estimation.md`). This file covers the two techniques
that let a database scale past what one machine can hold or serve:
**replication** (copying data across multiple machines for read scale and
fault tolerance) and **sharding/partitioning** (splitting data across
multiple machines so no single machine holds all of it).

## Why it matters

Most systems eventually become bottlenecked on the database before anything
else, because unlike stateless application servers (which you can clone
endlessly behind a load balancer, see `04_load_balancing.md`), a database
holds state — you can't just spin up an identical copy and split traffic
randomly, because writes to one copy have to somehow reach the others.
Without replication and sharding:

- A single database server caps your entire system's write and read
  throughput at whatever one machine can do — no amount of application
  server scaling fixes this.
- A single point of failure means a database crash takes down the entire
  system, with no failover target.
- All your data must fit on one machine's disk, which becomes physically
  impossible past a certain dataset size.

## Replication

**Replication** means maintaining multiple copies of the same data on
different machines (**replicas**). There are three main topologies.

### Leader-Follower (Master-Slave)

One node (the **leader**/**master**) accepts all writes; one or more
**followers**/**replicas** receive a copy of every write (via a replication
log) and serve read traffic.

```text
        writes
Client ---------> [Leader]
                      |  replication stream
             ---------+---------
             |                 |
        [Follower A]     [Follower B]
             ^                 ^
             |  reads          |  reads
          Client            Client
```

- **Pros**: simple to reason about — only one node ever accepts writes, so
  there's no write-conflict resolution needed; read capacity scales by
  adding more followers.
- **Cons**: the leader is a single point of failure for writes (though
  failover to a promoted follower is possible); all writes are still
  bottlenecked through one machine.
- This is the default topology for most relational databases (PostgreSQL
  streaming replication, MySQL replication) and is the right starting point
  for the large majority of systems.

### Multi-Leader

More than one node accepts writes (often one leader per data center/region),
and each leader propagates its writes to the others.

- **Pros**: writes can be accepted close to the user in each region,
  reducing write latency for geographically distributed systems; no single
  write bottleneck.
- **Cons**: **conflicts** — if the same record is written on two leaders at
  nearly the same time, the system has to reconcile the two versions
  (last-write-wins, custom merge logic, or surfacing the conflict to the
  application). This is meaningfully harder to reason about and is only
  worth the complexity when write latency across regions genuinely matters.

### Leaderless (Dynamo-style)

No node is designated leader — a client (or a coordinator) writes to
multiple replicas directly, and reads also query multiple replicas,
reconciling any differences. Uses a **quorum** model (see
`08_cap_theorem_and_consistency.md` for the W+R>N formula in depth).

- **Pros**: no single point of failure for either reads or writes; highly
  available — as long as enough replicas are reachable, the system keeps
  serving requests even if some nodes are down.
- **Cons**: more complex client/coordinator logic; requires explicit
  conflict detection (e.g., vector clocks) since there's no single leader
  establishing write order.
- Used by Cassandra, DynamoDB, and Riak — systems built to prioritize
  availability under partition over immediate consistency.

| Topology | Writes accepted at | Conflict handling needed? | Best for |
|---|---|---|---|
| Leader-follower | One node | No (single write path) | Most systems — the default |
| Multi-leader | Multiple nodes | Yes | Multi-region systems needing low write latency everywhere |
| Leaderless | Any replica (quorum-based) | Yes | Very high availability requirements, tolerant of eventual consistency |

### Replication Lag

In leader-follower replication, writes reach followers **asynchronously**
(usually — synchronous replication exists but costs latency on every
write). This creates a window where a follower is behind the leader —
**replication lag**.

**Concrete symptom**: a user posts a comment. The write goes to the leader
and succeeds. The user's page immediately refreshes, and that refresh
request happens to get load-balanced to a follower that hasn't yet received
the new comment via replication. The user sees their own comment missing —
a confusing, "did my post fail?" experience, even though the write actually
succeeded. This is precisely the **read-your-writes consistency** problem
covered in `08_cap_theorem_and_consistency.md`, and it's a direct
consequence of using read replicas.

## Read Replicas

**Read replicas** are exactly the followers described above, used
specifically to **offload read traffic** from the primary/leader — the
leader handles writes (and optionally some reads), while the bulk of read
traffic is distributed across N followers. This is usually the very first
scaling step taken once a single database can't handle read volume, because
it requires no changes to how data is structured (unlike sharding) — just
routing read queries to a different connection.

The trade-off is exactly the replication lag problem above: reads from a
replica are not guaranteed to reflect the very latest write. Systems that
need read-your-writes guarantees typically route a user's own reads to the
leader immediately after their own write (or to a replica confirmed to be
caught up), while routing general read traffic to any replica.

## Sharding / Partitioning

**Sharding** (also called **partitioning**) splits a dataset across
multiple database instances (**shards**), where each shard holds a subset
of the rows — unlike replication, where every replica holds *all* the data.
Sharding is what you reach for when the dataset (or write volume) is too
large for any single machine, even after replication has maximized read
capacity.

### Range-Based Sharding

Rows are split by ranges of the shard key (e.g., user IDs 1-1M on shard 1,
1M-2M on shard 2; or by date).

- **Pros**: simple to implement; range queries (e.g., "all orders from
  March") stay on one shard, since sorted ranges map to contiguous shards.
- **Cons**: risk of **hot ranges** — if the shard key correlates with time
  (e.g., sharding by timestamp), all *new* writes land on the single
  most-recent shard, while older shards sit idle. A logging system sharded
  by date has 100% of write traffic hitting today's shard.

### Hash-Based Sharding

The shard key is passed through a hash function, and the hash determines
which shard a row lands on (`hash(key) % N`, or more robustly, via
consistent hashing — see below).

- **Pros**: distributes data (and write load) evenly across shards, since a
  good hash function scatters keys uniformly regardless of their natural
  distribution.
- **Cons**: loses range-query locality — "all orders from March" is now
  scattered across every shard, since hashing destroys the original
  ordering, so a range query must fan out to all shards and merge results.

### Directory-Based Sharding

A separate **lookup service** (a directory) maintains an explicit mapping
of key → shard, consulted before every query.

```text
Client -> [Directory Service: "key X is on shard 3"] -> Shard 3
```

- **Pros**: maximally flexible — rebalancing data just means updating
  directory entries, and shards can hold arbitrary, non-formulaic groupings
  of keys (useful for deliberately isolating specific hot keys).
- **Cons**: adds an extra network hop (and dependency) on every query;
  the directory service itself becomes a critical piece of infrastructure
  that needs its own availability and scaling story.

| Strategy | Even distribution? | Range queries efficient? | Rebalancing cost | Weakness |
|---|---|---|---|---|
| Range-based | No (can hotspot) | Yes | Moderate | Hot ranges (e.g., recent timestamps) |
| Hash-based | Yes | No (scattered) | High without consistent hashing | Loses locality |
| Directory-based | Depends on mapping | Depends on mapping | Low (just update mapping) | Extra hop, directory becomes critical infra |

### Hot Shard / Hotspot Problem

Regardless of strategy, a **hot shard** occurs when one shard receives
disproportionate traffic relative to the others — the sharding scheme
successfully split the *data* evenly, but not the *access pattern* evenly.
Concrete example: shard by `user_id` (a reasonable, generally-even scheme),
but one user is a celebrity with 50 million followers — every view of their
profile, every like on their post, every follow action hits the single
shard holding that one user's row, regardless of how evenly every other
user's data is spread. The fix is usually workload-specific: splitting a
single hot entity's data further (e.g., sharding *that user's* followers
list separately), adding a cache layer in front of the hot shard
specifically, or replicating just the hot shard's data more heavily.

## Consistent Hashing

The naive way to hash-shard is `shard = hash(key) % N` where N is the
number of shards. This works fine until N changes (a shard is added or
removed) — because `% N` changes, **almost every key** now maps to a
different shard than before, meaning nearly the entire dataset has to be
physically moved to rebalance. For a large dataset, that's an enormous,
often infeasible, migration to run just to add one machine.

**Consistent hashing** solves this. Conceptually:

1. Both shard identifiers and data keys are hashed onto the same circular
   space — a **hash ring** (imagine hash values from 0 to some max value,
   wrapping back to 0, laid out as a circle).
2. Each shard owns the arc of the ring from its position going clockwise
   to the next shard's position.
3. A key is assigned to whichever shard's position is the next one
   clockwise from the key's own hash position.

```text
                    0
                    |
         Shard A ---+--- Key "cat" (-> Shard B, next clockwise)
        /                              \
       |                                |
  Key "dog"                          Shard B
  (-> Shard A)                          |
       |                                |
        \                              /
         Shard C ---------------------+
              (owns arc from B to C)
```

**Why this minimizes data movement**: when a new shard is added, it takes
a position on the ring and only "steals" the portion of the ring (and
therefore the keys) between itself and the next node counter-clockwise —
every other shard's ownership is completely untouched. Removing a shard
similarly only affects the keys it owned, which now fall to the next node
clockwise. Compare to naive `% N`: adding one shard to a 4-shard cluster
(N=4 -> N=5) reshuffles roughly 80% of all keys, while consistent hashing
moves only the fraction of keys that happen to land in the new node's
slice of the ring — typically close to `1/N` of the data, not nearly all
of it.

**Virtual nodes**: with only a few real shards placed on the ring, their
positions might be uneven by chance, leaving one shard responsible for a
much larger arc (and thus much more data/traffic) than others. The fix is
to give each physical shard many **virtual node** positions scattered
around the ring (e.g., each physical shard gets 100-200 virtual points),
so ownership is composed of many small, scattered arcs per shard rather
than one large contiguous one — this averages out to a much more even
distribution, and also means that when a shard is added or removed, the
resulting extra/missing load is spread thinly across many other shards
instead of dumped entirely onto one neighbor.

## Federation (Functional Partitioning)

**Federation** splits a database not by *rows* (like sharding) but by
*function/domain* — separate databases for separate parts of the system's
functionality. For example: a `users` database, a `products` database, and
an `orders` database, each a fully independent database instance (possibly
with its own replication and even its own sharding within it).

- **Pros**: each database is smaller and can be scaled, tuned, and operated
  independently — the `products` database might need heavy read caching
  while `orders` needs strong transactional guarantees, and federation lets
  each be configured for its own workload rather than compromising on one
  shared configuration.
- **Cons**: you lose the ability to do cross-domain joins or transactions
  at the database level — "get a user and their orders in one query" now
  requires the application to query two databases and join in memory, and
  "place an order and decrement inventory atomically" can no longer rely on
  a single database transaction (this is exactly the kind of problem
  distributed transaction patterns like Saga, covered in
  `09_distributed_systems_core.md`, exist to solve).

## Resharding Challenges

Moving from N shards to N+1 shards is one of the more operationally
dangerous events in a database's life, even with consistent hashing,
because:

- Data has to be physically copied to the new shard while the system stays
  online and serving traffic — a live migration, not an offline one.
- Every layer that routes requests to shards (the directory service, the
  hashing logic in application code, connection pools) has to be updated
  consistently, ideally without a window where some requests use the old
  mapping and some use the new one.

Two mitigations are used in practice, often together:

1. **Consistent hashing** (above) limits the *fraction* of data that needs
   to move for any given resharding event, but doesn't eliminate the
   operational complexity of actually moving it.
2. **Pre-splitting into far more shards than nodes**: many systems create,
   say, 4096 logical shards up front, but initially map many logical shards
   onto each of just a handful of physical nodes. Scaling out from 4 nodes
   to 8 nodes then means *reassigning* which physical node owns which
   existing logical shards (moving whole, already-defined shards, which is
   a much simpler and cheaper operation) rather than *re-partitioning* data
   from scratch into new boundaries. This is a common pattern in systems
   like Vitess (for MySQL) and many managed sharded databases.

## Trade-offs

| Decision | Choose this... | ...when |
|---|---|---|
| Leader-follower vs multi-leader | Leader-follower | Single-region, or writes can tolerate going to one place |
| | Multi-leader | Multi-region with low write-latency requirements, and you can handle conflicts |
| Range vs hash sharding | Range-based | Range queries are common and the key doesn't correlate with a hot dimension (like time) |
| | Hash-based | Even write distribution matters more than range-query efficiency |
| Sharding vs federation | Sharding | One logical entity (e.g., users) is too large/hot for one database |
| | Federation | The system has naturally separable domains that don't need cross-domain transactions |
| Read replicas vs sharding | Read replicas | The bottleneck is read *traffic*, not total data *size* |
| | Sharding | The dataset itself no longer fits on one machine, or write volume exceeds one leader's capacity |

## Interview Tips

- "The database is the bottleneck" is one of the most common turning
  points in a system design interview — when you hit it, the expected next
  move is: read replicas first (cheapest, no schema change), then sharding
  if the dataset/write-volume itself is the problem, not just read
  traffic.
- Always name your **shard key** explicitly and justify it against the
  system's actual access patterns — an unjustified "we'll shard by user
  ID" is a common but weak answer if the interviewer then asks "what if
  one user is far more active than all others?" (the hot shard problem) and
  you have no answer ready.
- Consistent hashing is a strong signal topic — being able to explain *why*
  naive `% N` sharding is bad (not just that consistent hashing exists) is
  what separates a memorized answer from an understood one.
- Replication lag is frequently used to probe whether you understand that
  "add read replicas" isn't free — a good candidate proactively mentions
  the read-your-writes problem it introduces, rather than waiting to be
  asked.
- Federation vs sharding is a subtle distinction interviewers sometimes
  test directly: sharding splits *one* logical table/entity across
  machines; federation splits *different* logical entities across
  machines. Confusing the two is a common tell of shallow understanding.

## Quick Recall — Self-Test

**1. In one sentence, why does vertical scaling alone eventually fail as a database strategy?**
A single machine has a hard ceiling on CPU, memory, and disk I/O, and the cost of ever-bigger machines grows non-linearly as you approach the top of the available hardware tiers — see `02_scalability_and_estimation.md`.

**2. What's the key difference between leader-follower and leaderless replication in terms of conflict handling?**
Leader-follower has a single node accepting all writes, so there's an inherent, unambiguous write order and no conflicts to resolve. Leaderless replication accepts writes at multiple replicas concurrently, so it needs explicit conflict detection/resolution (e.g., vector clocks) since there's no single authority establishing order.

**3. Describe a concrete user-visible symptom of replication lag.**
A user posts a comment (write goes to the leader and succeeds), then immediately refreshes the page; the refresh request is routed to a follower replica that hasn't yet received the new comment, so the user's own comment appears to be missing even though the write succeeded.

**4. Why does hash-based sharding lose range-query efficiency compared to range-based sharding?**
Hashing scatters keys pseudo-randomly across shards specifically to achieve even distribution, which means keys that were originally adjacent (like consecutive dates) end up on entirely different shards — a range query then has to fan out to every shard and merge results instead of hitting one contiguous shard.

**5. Explain the hot shard problem with a concrete example.**
Sharding by `user_id` distributes data evenly across shards in general, but if one user is a celebrity with millions of followers, every interaction involving that user (profile views, likes, follows) hits the single shard holding their row — that shard receives disproportionate traffic even though the overall data distribution looks even.

**6. Why does naive `hash(key) % N` sharding cause a large data migration when N changes, and how does consistent hashing avoid this?**
Changing N changes the result of `% N` for nearly every key, so nearly the entire dataset must move to the new shard it now maps to. Consistent hashing places both shards and keys on a hash ring where each shard only owns the arc up to the next shard; adding or removing a shard only affects the keys in its own arc, leaving every other shard's ownership untouched.

**7. What problem do virtual nodes solve in consistent hashing?**
With only a few real shard positions placed on the ring, chance can give one shard a much larger arc (and thus more data/traffic) than others. Virtual nodes give each physical shard many scattered positions on the ring, spreading its ownership across many small arcs, which evens out the distribution and spreads rebalancing load across many nodes instead of dumping it onto one neighbor.

**8. How does federation differ from sharding, and what capability do you lose with federation?**
Sharding splits rows of the *same* logical entity/table across machines; federation splits *different* logical entities/domains (e.g., users, products, orders) into separate databases. With federation you lose the ability to do cross-domain joins or transactions at the database level — combining data across domains, or committing a multi-domain change atomically, now has to happen in application code.
