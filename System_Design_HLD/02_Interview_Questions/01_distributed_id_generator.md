# Design a Unique ID Generator (Twitter Snowflake)

## Problem Statement

"We have a distributed system — hundreds of application servers, dozens of
database shards — and every row we write (tweets, orders, events) needs a
unique identifier. Design a service that generates unique IDs across this
fleet, at high throughput, with no coordination bottleneck. Ideally the IDs
should also be roughly sortable by creation time, since we'll want to fetch
'recent tweets' efficiently without a secondary index."

This is the canonical framing (Twitter's original Snowflake blog post), but
the same problem shows up any time a single auto-increment column can't keep
up: order IDs in a sharded e-commerce DB, message IDs in a chat system,
event IDs in an analytics pipeline.

## Step 1: Clarify Requirements

**Functional Requirements**
- Generate a unique ID on every request, with no two callers ever receiving
  the same ID (globally, across all machines, forever).
- IDs should be roughly time-sortable — an ID generated later should
  (almost always) be numerically larger than one generated earlier, so
  `ORDER BY id` approximates `ORDER BY created_at` without a separate index.
- IDs should be usable as a primary key / shard key directly (fit in a
  standard 64-bit integer column, no external lookup needed to validate
  uniqueness).
- The service must work across multiple independent generator instances
  (machines/processes) without those instances talking to each other on the
  hot path.

**Non-Functional Requirements**
- **Throughput**: must support very high ID-issuance rates — Twitter's
  original numbers were in the tens of thousands of IDs/sec sustained,
  bursting higher. We'll size for 100,000 IDs/sec system-wide.
- **Latency**: ID generation must be near-instant — sub-millisecond,
  in-process. It cannot involve a network round trip or a database write on
  the hot path (that would make the ID generator itself the bottleneck it's
  meant to remove).
- **Availability**: the ID generator must not have a single point of
  failure. If one generator instance dies, others keep issuing IDs; no
  global lock or single sequencer.
- **No central coordination on the hot path**: whatever coordination is
  needed (assigning a machine ID) happens rarely (at startup), not per-ID.
- **Compactness**: IDs should fit in 64 bits (a native `bigint`), not the
  128 bits a UUID needs, because they get stored in every row, every index,
  and every foreign key across the system.
- Consistency model: we don't need strict global ordering (ID N+1 isn't
  guaranteed to have been created after ID N system-wide, only that IDs
  trend upward over time and are unique) — this is a deliberately relaxed
  requirement that makes the whole design tractable.

## Step 2: Back-of-Envelope Estimation

**Assumptions**: a product with 500 million monthly active users, generating
1 billion new "posts" (or orders, or events) per day, with a peak-to-average
ratio of 3x (traffic isn't flat — it spikes around peak hours).

**Throughput**
- Average: 1,000,000,000 / 86,400 sec ≈ 11,574 IDs/sec average.
- Peak (3x average): ≈ 34,722 IDs/sec.
- Round up for headroom and multi-year growth: design for 100,000 IDs/sec
  sustained system-wide as a target ceiling.

**Per-machine capacity (this is the number that drives the bit layout)**
- If we allocate 12 bits of the ID to a per-millisecond sequence counter,
  one machine can issue 2^12 = 4,096 unique IDs within a single millisecond
  before it has to wait for the next millisecond tick.
- 4,096 IDs/ms = 4,096,000 IDs/sec **per machine**.
- To hit our 100,000 IDs/sec system-wide target we need far fewer than one
  machine's worth of capacity — in practice you run multiple generator
  instances anyway for availability (no single point of failure) and to
  co-locate the generator with the services that need IDs (often embedded
  as a library inside each app server rather than a standalone service).

**Storage / bandwidth**
- Each ID is a 64-bit integer = 8 bytes.
- 1 billion IDs/day x 8 bytes = 8 GB/day of pure ID data, but IDs aren't
  stored standalone — they're the primary key of the row they identify, so
  this cost is folded into the row storage, not a separate concern.
- Network cost of the ID generator itself is effectively zero if it's an
  in-process library call; if it's a network service, at 100,000 req/sec x
  ~20 bytes (request + response) ≈ 2 MB/sec, trivial for a single link.

**Machine ID space**
- 10 bits of machine ID gives 2^10 = 1,024 distinct generator instances
  that can run concurrently without ID collisions. For a fleet of a few
  hundred to ~1,000 app servers each embedding the generator, this is
  comfortably sufficient.

## Step 3: High-Level Design

The generator is typically embedded as a **library inside each application
server** (not a centralized network service you call over HTTP, though it
can be deployed that way too) — this is the key design choice that removes
the hot-path bottleneck entirely. Each instance:

1. Knows its own unique machine ID (assigned once, at startup).
2. Reads the system clock to get the current timestamp.
3. Maintains an in-memory, per-millisecond sequence counter.
4. Packs (timestamp, machine ID, sequence) into a single 64-bit integer and
   returns it — no network call, no database write, no lock contention with
   other machines.

```text
                    +--------------------------------------+
                    |         Coordination Service          |
                    |   (ZooKeeper / etcd / config store)    |
                    |  - assigns each app server a unique    |
                    |    machine_id (0-1023) at startup      |
                    +--------------------+-------------------+
                                         | (once, at boot)
                                         v
   +----------------+    +----------------+    +----------------+
   |  App Server 1   |    |  App Server 2   |    |  App Server N   |
   |  machine_id=1   |    |  machine_id=2   |    |  machine_id=N   |
   |                 |    |                 |    |                 |
   |  +-----------+  |    |  +-----------+  |    |  +-----------+  |
   |  | Snowflake |  |    |  | Snowflake |  |    |  | Snowflake |  |
   |  | Generator |  |    |  | Generator |  |    |  | Generator |  |
   |  | (in-proc) |  |    |  | (in-proc) |  |    |  | (in-proc) |  |
   |  +-----+-----+  |    |  +-----+-----+  |    |  +-----+-----+  |
   +--------|--------+    +--------|--------+    +--------|--------+
            v                      v                      v
      new_id -> DB row       new_id -> DB row       new_id -> DB row
      (no cross-machine communication needed to generate an ID)
```

If deployed as a standalone network service instead (sometimes done so
application code doesn't need to embed generator logic in every language a
polyglot fleet uses), each generator instance still operates independently
behind a load balancer — the load balancer doesn't need sticky sessions
because any instance can serve any request, it just needs a unique
`machine_id`.

## Step 4: API Design

Even when embedded as a library, it's useful to describe the "interface" —
either an in-process method call or, for a standalone deployment, a thin
RPC.

**`generate_id()` (library call, in-process)**
```
Input:  none
Output: 719283740981248001   (int64)
```

**`POST /v1/ids` (standalone service variant)**
```json
Request: {}
Response: {
  "id": 719283740981248001,
  "generated_at_ms": 1757740800123,
  "machine_id": 42
}
```

**`POST /v1/ids/batch` (batch variant, reduces round trips for bulk-insert workloads)**
```json
Request:  { "count": 100 }
Response: { "ids": [719283740981248001, 719283740981248002, "..."] }
```

**`GET /v1/machine-id/lease` (internal, coordination-service-backed, called once at startup, not per-ID)**
```json
Request:  { "hostname": "app-server-17" }
Response: { "machine_id": 42, "lease_expires_at": 1757744400 }
```

## Step 5: Data Model

There isn't a traditional "data model" for the generator itself — it's
stateless per-request — but two things are stored:

1. **Machine ID assignments** — a small mapping of `hostname -> machine_id`,
   held in the coordination service (ZooKeeper/etcd), not a relational
   database. This is a natural fit for a coordination service rather than
   SQL/NoSQL because what's needed is exactly what those services provide:
   ephemeral nodes tied to a session (so a crashed server's machine ID is
   automatically released), strong consistency for the handful of writes
   involved, and a watch/notify mechanism. See
   `01_Concepts/09_distributed_systems_core.md` for how ZooKeeper-style
   coordination services work.

   ```text
   /snowflake/machine-ids/42  ->  { hostname: "app-server-17", leased_at: ... }
   ```

2. **The generated IDs themselves** are not stored anywhere by the
   generator — they become the primary key of whatever row they're attached
   to, in that row's own database (SQL or NoSQL, sharded by the ID's value
   or by another key entirely — the ID generator doesn't care).

## Step 6: Deep Dive

### 6.1 Why naive approaches fail

- **Database auto-increment (`AUTO_INCREMENT` / `SERIAL`)**: trivial on a
  single database, but breaks the moment you shard. If you have 8 shards
  each with their own auto-increment counter, shard 1's row 500 and shard
  2's row 500 collide. You could pre-allocate ID ranges per shard (shard 1
  gets IDs 1-1M, shard 2 gets 1M-2M, etc.) but that requires manual
  coordination up front and doesn't scale elastically when you add shard 9.
  A single global auto-increment table also becomes a write bottleneck and
  a single point of failure — every insert anywhere in the system has to
  round-trip to it first.
- **UUIDs (v4, random)**: solve uniqueness beautifully — 122 bits of
  randomness means collisions are astronomically unlikely without any
  coordination at all. But they fail two other requirements: (1) they are
  **not sortable by time** — a UUID generated now and one generated an hour
  ago look equally random, so you lose the "recent rows sort near each
  other" property that makes range scans and B-tree index inserts
  efficient (random UUID primary keys cause severe B-tree page splits and
  index fragmentation under high insert volume); (2) at 128 bits (36
  characters as a string), they're 2-4x the storage of a 64-bit int, which
  compounds across every index and foreign key referencing that ID.
  UUIDv7 (time-ordered UUIDs) fixes the sortability problem but is a newer
  standard and still costs more bytes than Snowflake's 64 bits.

### 6.2 The Snowflake 64-bit structure

```text
 0                   1                   1
 (sign)  <-- 41 bits timestamp -->  <10 bits-> <-12 bits->
 +---+------------------------------------------+----------+------------+
 | 0 |        timestamp (ms since epoch)          | machine  |  sequence  |
 +---+------------------------------------------+----------+------------+
   1 bit              41 bits                      10 bits      12 bits
                                                                 = 64 bits total
```

- **1 unused/sign bit**: kept 0 so the value is always a positive signed
  64-bit integer — this matters because many languages and DB columns
  (e.g., Java `long`, SQL `BIGINT`) are signed, and a negative ID would be
  a constant source of bugs.
- **41 bits for timestamp** (milliseconds since a custom epoch, not the
  Unix epoch — you pick a recent "epoch" like your company's founding date
  to maximize the useful range): 2^41 milliseconds ≈ 2.199 x 10^12 ms ≈
  69.7 years. Using a custom epoch (e.g., 2020-01-01) instead of
  1970-01-01 means the 69.7-year window runs from 2020 to roughly 2089,
  rather than wasting ~50 already-elapsed years of the range on the Unix
  epoch.
- **10 bits for machine/worker ID**: 2^10 = 1,024 concurrently-safe
  generator instances. Some implementations split this further into
  datacenter ID (5 bits = 32 datacenters) + worker ID (5 bits = 32 workers
  per datacenter) for operational clarity in multi-region deployments.
- **12 bits for sequence number**: 2^12 = 4,096 IDs per machine per
  millisecond. If a single machine tries to generate a 4,097th ID within
  the same millisecond, it must either wait for the next millisecond tick
  or return an error — in practice, generators spin-wait (busy-loop) until
  the clock ticks forward, since a 1ms wait is imperceptible relative to
  request latency budgets.
- **Sortability property**: because the timestamp occupies the highest-order
  bits (after the sign bit), IDs generated later have numerically larger
  values almost all the time — "almost" because within the same
  millisecond, ordering depends on machine ID and sequence, not true
  arrival order across machines. This is the relaxed ordering guarantee
  called out in Step 1.

### 6.3 Assigning unique machine IDs

The machine ID must be unique per running instance, or the whole scheme's
uniqueness guarantee collapses (two machines with the same ID could
generate colliding IDs in the same millisecond). Approaches:

- **Coordination service (ZooKeeper/etcd), the standard approach**: on
  startup, each instance creates an **ephemeral sequential znode** under a
  shared path (e.g., `/snowflake/workers/`). ZooKeeper assigns it the next
  available sequence number as its machine ID and ties the znode's
  lifetime to the instance's session — if the instance crashes or loses
  its connection, the znode is automatically removed and that machine ID
  becomes available for reassignment. This is exactly the leader-election
  and ephemeral-node pattern described in
  `01_Concepts/09_distributed_systems_core.md`. The coordination service is
  only touched once at startup (or on reconnect after a network partition),
  never on the per-ID hot path, which is what keeps ID generation itself
  free of any external dependency at request time.
- **Static config / manual assignment**: simplest option for small,
  stable fleets — each instance is given its machine ID via an environment
  variable or config file at deploy time (e.g., derived from a Kubernetes
  StatefulSet's stable pod ordinal, `app-server-3` gets machine ID 3).
  Fragile at larger scale because it requires a human or a deployment
  script to guarantee no two instances ever get the same static ID, and it
  doesn't reclaim IDs from decommissioned instances automatically.
- **IP-address or hostname hashing**: hash the machine's IP/hostname into
  the 10-bit space. Fast and requires no coordination service, but
  collisions are possible (two machines hashing to the same value) and
  must be detected and handled (e.g., fall back to a coordination service
  on collision), so this is usually a fallback rather than the primary
  mechanism.

### 6.4 Clock drift and clock going backwards

This is the sharpest edge case in the whole design, and the one interviewers
probe hardest, because the entire uniqueness guarantee depends on the
timestamp component only ever moving forward for a given machine.

- **The failure mode**: NTP (Network Time Protocol) periodically
  resynchronizes a machine's clock. If the machine's clock was running
  fast, an NTP correction can make the clock jump *backwards*. If a
  generator naively reads `current_time_ms()` and that value is less than
  the last timestamp it used, it risks generating an ID with a smaller
  timestamp than an ID it already issued — breaking both uniqueness (if the
  sequence counter also resets) and the sortability guarantee.
- **Mitigation 1 — refuse to generate until the clock catches up**: the
  generator keeps track of `last_timestamp`, the timestamp used for its
  most recently generated ID. On each request, if `current_time_ms() <
  last_timestamp`, the generator does not generate an ID — it either
  blocks/retries until `current_time_ms() >= last_timestamp` again, or
  immediately raises an error to the caller ("clock moved backwards,
  refusing to generate ID") so the caller/operator can alert on it. This is
  what Twitter's original Snowflake implementation does. The trade-off is
  a brief availability gap on that one machine during the backward jump
  (typically milliseconds, since NTP corrections are usually small), in
  exchange for a hard uniqueness guarantee.
- **Mitigation 2 — hybrid logical clocks (HLC)**: instead of relying purely
  on wall-clock time, an HLC combines the physical clock with a logical
  counter that's guaranteed monotonic — the logical component increments
  whenever the physical clock hasn't advanced (or has gone backwards),
  ensuring the combined (physical, logical) pair is always strictly
  increasing per machine even through clock corrections. This avoids the
  "refuse to generate" availability gap entirely at the cost of a more
  complex ID structure and slightly weaker wall-clock interpretability
  (the timestamp component is no longer exactly "when this ID was
  created," just "not earlier than").
- **Operational mitigation**: run NTP in "slew" mode (gradually adjusting
  the clock over time) rather than "step" mode (instantaneous jump) on
  generator hosts, and monitor clock skew so large backward jumps are rare
  in practice rather than something the hot path has to handle routinely.
- **Sequence overflow within a millisecond** is the sibling edge case:
  if a machine generates 4,096 IDs within 1ms (hits the 12-bit sequence
  ceiling), it must wait for the millisecond to roll over before issuing
  ID #4,097 — implemented as a tight spin-loop checking
  `current_time_ms() > last_timestamp`, not a sleep, since the wait is
  sub-millisecond.

## Step 7: Bottlenecks & Trade-offs

- **What breaks first**: if the generator is deployed as a centralized
  network service (rather than embedded per-app-server), that service
  becomes a shared dependency for every write path in the system — at
  100,000+ req/sec it needs to be horizontally scaled behind a load
  balancer, and a slow or down ID service now blocks all writes system-wide.
  This is exactly why embedding the generator as an in-process library is
  preferred whenever the deployment language allows it.
- **Coordination service as a soft dependency**: even though machine-ID
  assignment only happens at startup, if the coordination service (etcd/
  ZooKeeper) is down when a *new* instance boots (e.g., during an
  autoscaling event), that instance can't get a machine ID and can't start
  issuing IDs. Mitigate with generous machine-ID lease TTLs and by having
  new instances retry with backoff rather than failing hard immediately.
- **Clock reliance**: the whole scheme assumes reasonably synchronized
  clocks across the fleet. Large, uncorrected clock skew between machines
  doesn't break uniqueness (machine ID still disambiguates), but it does
  break the "IDs trend upward over time across the whole system" property
  that downstream consumers may implicitly rely on for approximate global
  ordering.
- **Trade-off accepted**: we gave up strict global ordering (ID N+1 is not
  guaranteed to have been created strictly after ID N across all machines)
  in exchange for zero-coordination, sub-millisecond, horizontally
  unlimited ID generation. This is almost always the right trade — very
  few systems actually need strict global ordering, and the ones that do
  (financial ledgers) usually need a different mechanism (a single
  ordered log, e.g., via consensus) for that specific data, not a general
  ID generator.
- **Fixed-size bit budget**: the 41/10/12 split is a design decision, not a
  law of physics — a system with far more than 1,024 machines but fewer
  IDs/ms/machine needed could reallocate bits (e.g., 13 bits machine ID,
  9 bits sequence) at the cost of lower per-machine throughput. This
  trade-off should be made explicit and justified with your own traffic
  numbers, not copied blindly from Twitter's original split.

## Follow-up Questions an Interviewer Might Ask

- **"What happens if two data centers each have a machine with the same
  worker ID due to a coordination service outage?"** Add a datacenter ID
  segment carved out of the machine-ID bits (e.g., 5 bits datacenter + 5
  bits worker instead of 10 bits worker), so the coordination service only
  needs to guarantee uniqueness *within* a datacenter, and cross-datacenter
  collisions become structurally impossible even if both DCs' coordination
  services are partitioned from each other.
- **"How would you migrate an existing system off auto-increment IDs onto
  Snowflake IDs without downtime?"** Dual-write during a transition window:
  new rows get both an old-style ID and a Snowflake ID in a new column,
  backfill Snowflake IDs onto historical rows via a batch job, switch reads
  to the new column once backfill completes and is verified, then drop the
  old column — classic expand-contract schema migration.
- **"Could you use Redis `INCR` instead of Snowflake?"** Yes for pure
  uniqueness + monotonicity (Redis `INCR` is atomic and strictly
  increasing), but it reintroduces a centralized network hop on the hot
  path and a single point of failure/bottleneck unless you shard the
  counter (e.g., different Redis keys per range), which just reinvents a
  weaker version of the machine-ID partitioning Snowflake already gives
  you for free, without the sub-millisecond in-process latency.
- **"How do you monitor this in production?"** Track clock-skew alerts
  (frequency of "clock moved backwards" events), sequence-overflow rate
  (how often a machine hits the 4,096/ms ceiling — a signal you may need
  more machines or more sequence bits), and machine-ID lease churn (a spike
  suggests instances are crash-looping and repeatedly re-registering).
- **"What if you need IDs to be non-guessable (not just unique), e.g., for
  public-facing resource URLs?"** Snowflake IDs are sequential and
  predictable by design (that's the point, for sortability) — for public
  IDs where enumeration is a security concern, either encode the Snowflake
  ID through a reversible obfuscation (Hashids-style) before exposing it
  externally, or maintain a separate random public-facing token that maps
  internally to the Snowflake ID.
- **"Why 12 bits of sequence and not, say, 8 or 16?"** It's a capacity vs.
  bit-budget trade: 8 bits gives only 256 IDs/ms/machine (256,000/sec),
  which could be too tight for a single hot machine during a burst; 16
  bits gives 65,536/ms/machine but eats into the bits available for
  timestamp or machine ID. 12 bits (4,096/ms/machine = 4.096M/sec/machine)
  was Twitter's empirically chosen middle ground for their traffic profile
  — the right answer depends on your own peak per-machine write rate from
  Step 2.
