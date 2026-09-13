# Scalability and Estimation

## Why it matters

"Make it scalable" is meaningless without numbers. Without estimation, teams either over-engineer (building multi-region, sharded, queue-everything systems for a product with 500 users — burning months of engineering time and ongoing operational cost for headroom nobody needs) or under-engineer (launching a single unindexed Postgres instance behind a product that goes viral and falls over at 10x the load anyone tested). Estimation is the tool that tells you, before you write a line of code, roughly which regime you're in — "this fits on one beefy box" vs "this needs to be horizontally distributed from day one" — so the architecture matches the actual problem instead of someone's gut feeling.

## Vertical vs Horizontal Scaling

**Vertical scaling (scaling up)**: increase the capacity of a single machine — more CPU, RAM, faster disk (e.g., moving a database from a 4-core/16GB instance to a 64-core/512GB instance).

**Horizontal scaling (scaling out)**: add more machines and distribute load across them (e.g., running the app on 20 small servers behind a load balancer instead of 1 huge one).

| | Vertical Scaling | Horizontal Scaling |
|---|---|---|
| How | Bigger machine | More machines |
| Cost curve | Increases faster than linearly — top-tier hardware carries a steep price premium, and there's a hard ceiling (the biggest machine money can buy) | Roughly linear — commodity machines are cheap and you just add more |
| Single point of failure | Yes — one machine, one failure domain | No, if done right — one node dying doesn't take the system down |
| Operational complexity | Low — one machine to patch, monitor, back up | Higher — service discovery, load balancing, distributed monitoring, deployment orchestration |
| Statefulness | Not a problem — all data/state lives on the one machine | A real problem — in-memory state, sessions, and data need to be externalized or partitioned since any request can land on any node |
| Downtime for upgrade | Often requires a restart/resize (brief downtime) | Can typically roll nodes in/out with zero downtime |
| Ceiling | Hard physical/hardware ceiling | Practically unbounded (add more nodes) |

The recurring theme in system design: horizontal scaling is the default target for anything expected to grow past what one machine can handle, but it's not free — it forces you to confront statelessness, coordination, and distributed failure modes that vertical scaling never makes you think about. Many real systems scale vertically first (it's simpler and buys real time) and only move to horizontal scaling once they hit the ceiling or need redundancy.

## Latency vs Throughput

**Latency**: the time to complete a single operation (e.g., "this API call takes 120ms").

**Throughput**: the number of operations completed per unit time (e.g., "this service handles 5,000 requests/second").

These sound similar but are not the same axis, and improving one can hurt the other. Example: **batching**. If a service buffers 100 write requests and flushes them to the database in one batch every 50ms, throughput goes up (fewer, larger DB round-trips are far more efficient than 100 tiny ones), but the latency of any individual request goes up too (a request that arrived right after a flush now waits up to 50ms before it's even included in the next batch). Conversely, processing every request immediately, one at a time, minimizes latency per-request but caps throughput lower because you're paying per-operation overhead (connection setup, lock contention, network round-trips) on every single one instead of amortizing it.

This trade-off shows up constantly: bigger batches, larger buffers, and queuing all tend to raise throughput while raising tail latency.

## Availability and "the Nines"

**Availability**: the fraction of time a system is capable of serving requests correctly, usually expressed as a percentage over a year. Commonly described by how many "9"s it has.

The arithmetic: a non-leap year has 365 × 24 = 8,760 hours. Downtime allowed per year = (1 − availability) × 8,760 hours.

| Availability | Downtime / year (hours) | Downtime / year (human terms) |
|---|---|---|
| 90% ("one nine") | 0.10 × 8,760 = 876 hours | ~36.5 days |
| 99% ("two nines") | 0.01 × 8,760 = 87.6 hours | ~3.65 days |
| 99.9% ("three nines") | 0.001 × 8,760 = 8.76 hours | ~8 hours 46 minutes |
| 99.99% ("four nines") | 0.0001 × 8,760 = 0.876 hours | 0.876 × 60 = 52.6 minutes |
| 99.999% ("five nines") | 0.00001 × 8,760 = 0.0876 hours | 0.0876 × 60 = 5.26 minutes |

Each additional nine cuts allowed downtime by roughly 10x — and the engineering cost to buy that next nine grows non-linearly (99% to 99.9% might mean "add a second server"; 99.99% to 99.999% might mean multi-region active-active failover, chaos testing, and a dedicated on-call reliability team). This is why picking the right availability target — not just chasing the maximum — is itself a design decision with real cost trade-offs.

## SLA vs SLO vs SLI

These three terms are often confused; they describe the same underlying metric from three different angles.

- **SLI (Service Level Indicator)**: the actual, measured value of a metric. E.g., "our measured p99 read latency over the last 30 days is 260ms." It's a fact, observed from real traffic.
- **SLO (Service Level Objective)**: an internal target for that metric that the team commits to. E.g., "we aim for p99 latency under 300ms." It's a goal used to drive engineering priorities and alerting thresholds.
- **SLA (Service Level Agreement)**: an external, often contractual, promise to customers, usually with consequences (service credits, financial penalties) if missed. E.g., "we guarantee p99 latency under 500ms, or you get a service credit for that month."

Relationship in practice: SLAs are deliberately set looser than SLOs, which are set looser than what the SLI is actually achieving — this gives you a buffer so that normal variance doesn't breach a customer-facing contract. Concrete chain: SLI = 260ms measured → SLO = 300ms internal target (you get paged before this is at risk) → SLA = 500ms external promise (crossing this costs the company money). The gap between SLO and SLA is your safety margin.

## Back-of-Envelope Estimation

The method, step by step:

**1. Estimate QPS (queries per second) from DAU (Daily Active Users) and actions/user/day**
```
total actions/day = DAU × actions per user per day
average QPS       = total actions/day ÷ seconds/day (86,400)
peak QPS          = average QPS × peak factor (commonly ~2-3x average,
                     to account for traffic not being uniform across the day)
```

**2. Estimate storage from record size, count, retention, and replication**
```
total records         = records created per day × retention period (days)
raw storage           = total records × size per record
total storage (stored) = raw storage × replication factor
```

**3. Estimate bandwidth from QPS and payload size**
```
bandwidth ≈ QPS × average payload size
```

### Worked example

Scenario: a social app with **100M DAU**, each user posts on average **2 times/day**, each post (with metadata) is **~1KB**, data is kept with **3x replication**, and retained for **5 years**.

**QPS (writes):**
```
total posts/day = 100,000,000 users × 2 posts/user = 200,000,000 posts/day
average QPS     = 200,000,000 ÷ 86,400 sec ≈ 2,315 writes/sec
peak QPS (3x)   = 2,315 × 3 ≈ 6,944 writes/sec  (~7,000 QPS at peak)
```

**Total storage over 5 years:**
```
total posts over 5 years = 200,000,000 posts/day × 365 days × 5 years
                          = 200,000,000 × 1,825
                          = 365,000,000,000 posts (365 billion)

raw storage = 365,000,000,000 posts × 1 KB = 365,000,000,000 KB
            = 365,000,000 MB = 365,000 GB = 365 TB

with 3x replication = 365 TB × 3 ≈ 1,095 TB ≈ 1.1 PB (petabytes)
```

**Daily write bandwidth:**
```
daily bandwidth = posts/day × size/post
                = 200,000,000 × 1 KB = 200,000,000 KB
                = 200,000 MB = 200 GB/day ingested (write path, pre-replication)

average bandwidth ≈ 2,315 QPS × 1 KB/post ≈ 2.26 MB/sec sustained
peak bandwidth    ≈ 6,944 QPS × 1 KB/post ≈ 6.8 MB/sec at peak
```

Conclusion from these numbers: ~7,000 writes/sec at peak and ~1.1 PB over 5 years is squarely in "needs horizontal scaling and a proper distributed storage/sharding strategy" territory — a single relational database instance handling all of that directly would struggle both on write throughput and on raw disk capacity, telling you immediately that the design needs to include things like sharding, a distributed object store for media, or an append-friendly storage engine, well before you've thought about a single API endpoint.

## Latency Numbers Every Programmer Should Know

Approximate, order-of-magnitude figures for common operations (exact numbers vary by hardware/network, but the *relative* gaps are what matter):

| Operation | Approximate latency |
|---|---|
| L1 cache reference | ~1 nanosecond |
| Main memory (RAM) reference | ~100 nanoseconds |
| SSD random read | ~100-150 microseconds |
| Round trip within same datacenter | ~0.5 millisecond |
| Disk seek (spinning HDD) | ~10 milliseconds |
| Round trip cross-region / cross-continent | ~100-150 milliseconds |

Memorizing exact nanosecond values isn't the point — memorizing the **relative magnitudes** is: memory is ~100x faster than SSD, an in-datacenter round trip is ~1,000x slower than a memory access, and a cross-region round trip is ~100,000x+ slower than memory. That's *why* you cache hot data in memory instead of re-reading it from disk on every request, and *why* cross-region calls are kept off the hot path (e.g., you replicate data to the region instead of querying another continent synchronously on every user request) — the gap is large enough that a single unnecessary cross-region call can dominate your entire request's latency budget.

## When to use what

| Situation | Lean toward |
|---|---|
| Small/predictable load, need to move fast | Vertical scaling — simplicity wins, buy time |
| Load will grow past one machine's ceiling, or need redundancy | Horizontal scaling — accept the added complexity |
| User-facing interactive request | Optimize for latency (individual request feel) |
| Bulk/background data processing | Optimize for throughput (batch, accept per-item delay) |
| Consumer product at scale | Higher nines (99.9-99.99%) justified by revenue/reputation impact |
| Internal tool, low usage | 99% or even lower is often perfectly fine — don't over-invest |

## Why interviewers care about estimation

Anyone can say "it needs to be fast and scalable" — that's a slogan, not an analysis. Doing a back-of-envelope calculation forces you to commit to concrete numbers (QPS, storage, bandwidth) that then *drive* real architectural decisions: numbers in the thousands of QPS might be fine on a well-indexed single database with a cache in front; numbers in the hundreds of thousands of QPS clearly require horizontal partitioning. Interviewers use this step to check that you can translate a vague requirement into a quantified constraint, and that your architecture is actually a response to that number rather than a generic "microservices + Kafka + Redis" template applied regardless of scale.

## Quick Recall — Self-Test

**Q1: What's the key operational trade-off horizontal scaling introduces that vertical scaling avoids?**
Statefulness. With vertical scaling, all data/state lives on one machine so there's nothing to coordinate. With horizontal scaling, any request can land on any node, so in-memory state and sessions must be externalized (e.g., to Redis) or the data must be partitioned — this adds real coordination and consistency complexity.

**Q2: Why can improving throughput sometimes worsen latency? Give a concrete mechanism.**
Batching is the classic mechanism: grouping many operations into one batch (e.g., flushing 100 writes every 50ms) increases throughput by amortizing per-operation overhead, but any individual request now has to wait for the batch window to close, increasing its own latency.

**Q3: Compute the annual downtime for 99.95% availability.**
Downtime = (1 − 0.9995) × 8,760 hours = 0.0005 × 8,760 = 4.38 hours/year (about 4 hours 23 minutes).

**Q4: In the SLI/SLO/SLA chain, which one carries financial/contractual consequences, and why is it typically set looser than the internal target?**
The SLA carries financial/contractual consequences (e.g., service credits for breaches). It's set looser than the SLO so normal variance in the measured SLI doesn't accidentally breach a customer contract — the SLO acts as an internal early-warning buffer above the SLA line.

**Q5: What three inputs do you need to estimate storage requirements for a feature?**
Record size (bytes per record), record count over the retention window (creation rate × retention period), and replication factor — total storage = record size × count × retention-driven count × replication factor.

**Q6: Why memorize the relative latency gaps (memory vs disk vs cross-region) instead of exact numbers?**
Because the reasoning system design relies on is comparative: knowing memory access is ~100x faster than SSD and a same-datacenter round trip is roughly 1,000x slower than a memory access is what justifies caching hot data and avoiding synchronous cross-region calls on the hot path — the exact nanosecond figures aren't what drives the architectural decision, the order-of-magnitude gap is.

**Q7: A system does 500 average QPS. Using a 3x peak factor, what's the estimated peak QPS, and why do we apply a peak factor at all?**
Peak QPS ≈ 500 × 3 = 1,500 QPS. A peak factor is applied because traffic isn't uniform across the day (it clusters around usage peaks like evenings or lunch hours), so designing only for the daily average would leave the system under-provisioned exactly when it matters most.

**Q8: When would you deliberately choose NOT to pursue higher availability (e.g., stick with 99% instead of pushing to 99.99%)?**
When the cost/complexity of the next nine (multi-region failover, dedicated on-call, redundant infra) isn't justified by the system's actual business impact — e.g., an internal admin tool used by a handful of employees during business hours doesn't need five-nines engineering investment.
