# What Is System Design

## Definition

System design is the practice of defining the **architecture** (how components are split up and deployed), the **components** (services, databases, caches, queues, load balancers), the **data model** (how information is structured and where it lives), and the **APIs/contracts** between pieces of a software system — all in service of meeting a set of **functional requirements** (what the system must do) and **non-functional requirements** (how well it must do it) under real-world constraints: limited budget, limited engineering headcount, deadlines, and a codebase that has to keep evolving after launch.

It is fundamentally a **decision-making discipline**. You are rarely inventing a new algorithm; you are choosing between known building blocks (relational DB vs NoSQL, synchronous vs async, monolith vs microservices, cache-aside vs write-through) and justifying each choice against the specific constraints you were given. Two engineers given the same problem and different constraints (say, "10 users" vs "10 million users") should produce different, both-correct designs.

## Why it matters

Without deliberate system design, systems degrade in predictable ways:

- **A single database melts under load** because nobody planned for read replicas, caching, or sharding — the schema and access patterns were designed for correctness only, not for the write/read volume the product would actually see.
- **A "quick fix" becomes a permanent bottleneck**: e.g., a synchronous call to a slow third-party API sits directly in the request path of a checkout flow, so when that API is slow, your entire checkout goes down with it — no queue, no timeout, no circuit breaker.
- **Outages cascade**: one overloaded service takes down every service that calls it synchronously, because no one thought about backpressure, retries with jitter, or bulkheading.
- **The team can't move fast after month 3**: a design with no clear service boundaries or API contracts means every change requires coordinating five teams, because nothing is decoupled.

System design is what stands between "works in the demo" and "works at 2am during a traffic spike, three years in, maintained by engineers who didn't write it."

## System Design vs DSA: a different kind of problem

You already know how to solve DSA (Data Structures & Algorithms) problems: given a precise, unambiguous problem statement, find the algorithm with optimal time/space complexity, and there is generally **one correct/optimal answer** that can be verified against test cases.

System design inverts almost every one of those properties:

| Dimension | DSA | System Design |
|---|---|---|
| Problem statement | Fully specified upfront | Ambiguous, incomplete — you must ask questions to pin it down |
| "Correct" answer | Usually one optimal solution | Many valid designs; correctness = fit for the given constraints |
| Evaluation | Pass/fail against test cases | Judged on trade-off reasoning, not a single right answer |
| Time horizon | Solve once | Must evolve as scale/requirements change over months/years |
| Scope | Self-contained function/algorithm | Spans components, teams, failure modes, operational cost |
| Skills tested | Algorithmic reasoning | Architecture, communication, prioritization under ambiguity |
| Changing requirements | Not part of the problem | Core part of the problem — interviewer adds constraints mid-discussion |

Because requirements are ambiguous and evolving, system design also has a heavy **organizational** dimension that DSA has none of: who owns which service, how do two teams agree on an API contract without blocking each other, what's cheap to change later vs what locks you in (a chosen database engine is hard to swap after millions of rows are written; an internal API's parameter list is easy to change before other teams depend on it).

## Functional vs Non-Functional Requirements

**Functional requirements (FRs)** describe *what* the system does — the features, the user-visible behavior. They're usually easy to state and everyone agrees on them quickly.

Examples:
- Users can post a tweet (text + optional image).
- A user can follow another user and see their posts in a feed.
- A rider can request a trip and get matched to a nearby driver.

**Non-functional requirements (NFRs)** describe *how well* the system must perform — the qualities and constraints that don't show up as a single feature but shape every architectural decision. These are where the real design work happens, because FRs alone are satisfiable by a single Rails app and a Postgres instance; NFRs are what force you into caching, replication, queues, sharding, etc.

Examples:
- 99.9% availability (the system must be reachable and functioning that fraction of the time).
- p99 read latency under 200ms (99% of read requests must complete faster than 200ms).
- Support 10,000 writes/second at peak.
- Durability: once a write is acknowledged, it must never be lost, even if a node dies immediately after.
- Data must be eventually consistent within 5 seconds across regions (or: must be strongly consistent for financial balances).

A huge part of doing well in system design — in interviews and in real work — is **surfacing the NFRs explicitly** before designing, because the interviewer (or your PM) usually only states the FRs and expects you to ask about scale, latency, and consistency needs yourself.

## Why companies test this in interviews

A system design interview is a proxy for the actual job of a senior/staff engineer: given a vague ask ("build a URL shortener," "we need a notification system"), can you

1. **ask clarifying questions** to convert ambiguity into concrete requirements (functional and non-functional),
2. **make and justify trade-offs** out loud, so a team can follow and challenge your reasoning,
3. **estimate scale** so the design isn't wildly over- or under-engineered,
4. **identify failure modes** and design for them rather than assuming the happy path,
5. **communicate architecture** clearly enough that another engineer could implement it from your description.

None of this is about memorizing "the" design for a chat app. Interviewers actively want to see you adapt the design when they change a constraint mid-interview ("now assume 100x the users but reads must be real-time") — that adaptability is the actual signal, more than the initial diagram.

## The core mindset: there is no perfect design, only the right trade-offs for the given constraints

Every design decision trades one property for another: consistency for availability, latency for throughput, cost for redundancy, simplicity for flexibility. "Best" only makes sense relative to a stated set of constraints. Below are the same requirement solved differently as constraints change.

**Example 1 — "store and serve a user's profile photo"**
- *Small scale (thousands of users, internal tool)*: store the image as a BLOB in the same Postgres row as the user. Simple, one system to operate, fully consistent, totally fine at this scale.
- *Large scale (hundreds of millions of users)*: store the image in object storage (e.g., S3), store only the URL/key in Postgres, and serve the image through a CDN. Reason: DB storage and I/O are expensive and not built for large binary blobs; a CDN pushes bytes close to the user and offloads your origin entirely.

**Example 2 — "let users see their notification count"**
- *Read-heavy, small scale*: query `COUNT(*) WHERE read = false` directly against the notifications table on every page load. Simple, always accurate, fine if traffic is low.
- *Read-heavy, huge scale*: maintain a denormalized counter (in Redis, incremented/decremented on write) rather than a `COUNT` query on every read, because a live aggregate query per page load doesn't scale to millions of concurrent reads. Trade-off: the counter can drift slightly out of sync and needs periodic reconciliation — you've traded perfect accuracy for speed and DB load reduction.

**Example 3 — "handle order writes for an e-commerce checkout"**
- *Write-light (a boutique store)*: write directly to a single relational database inside the request; synchronous, simple, strongly consistent, and the user sees success/failure immediately.
- *Write-heavy (flash sale, huge spike)*: accept the order request, push it onto a queue, return "order received" immediately, and process/persist it asynchronously with workers that can be scaled independently and retried on failure. Trade-off: you gain the ability to absorb bursts and survive downstream slowness, but you give up the immediate strong guarantee that the order is fully processed by the time you respond to the user — you now need to communicate "pending" state back to them.

In every example, the "less scalable" option isn't wrong — it's the correct answer for its constraints, and reaching for the more complex option prematurely is itself a design mistake (unnecessary operational cost and complexity for no real benefit).

## You already have the intuition — this gives it vocabulary

If you've scaled a database (read replicas, indexes, connection pooling, sharding) or debugged a production incident caused by load, you have already made real system design trade-offs — you just made them under a different name, in the moment, without a formal framework to communicate them. This material isn't teaching you a new way of thinking from zero. It's giving your existing instincts:

- **Vocabulary** — so "the thing where you route to the nearest server" becomes "GSLB" or "L7 load balancing," and you can communicate precisely with other engineers and interviewers.
- **A repeatable framework** — clarify requirements → estimate scale → define API/data model → design high-level architecture → go deep on 1-2 hard parts → discuss trade-offs and failure modes — so you don't improvise the structure of a discussion from scratch every time.
- **The missing pieces** — patterns you may not have needed yet in your own work (e.g., consistent hashing, CDNs, message queues at scale) but that come up constantly in system design contexts.

## Roadmap for this folder

The rest of `01_Concepts` builds the shared vocabulary and mental models used throughout every system design discussion:

- **02_scalability_and_estimation.md** — vertical vs horizontal scaling, latency vs throughput, availability and "the nines," SLA/SLO/SLI, and how to do back-of-envelope capacity estimation.
- **03_networking_and_apis.md** — DNS, TCP vs UDP, HTTP evolution, real-time communication options (WebSockets/SSE/polling), REST vs GraphQL vs gRPC, and API gateways.
- **04_load_balancing.md** — what load balancers do, L4 vs L7, load balancing algorithms, health checks, and session affinity.

Later folders (outside `01_Concepts`) build on this foundation to cover caching, database scaling, message queues, and full worked system designs — all of which lean on the terms and trade-off framing introduced here.

## Quick Recall — Self-Test

**Q1: What are the two categories of requirements you must gather before designing a system, and what's the difference between them?**
Functional requirements describe *what* the system does (features/behaviors, e.g., "users can post a tweet"). Non-functional requirements describe *how well* it must do it (e.g., 99.9% availability, p99 latency under 200ms). NFRs are usually what drive the hard architectural decisions.

**Q2: Why is there no single "correct" system design for a given problem?**
Because the right design depends on constraints — scale, read/write ratio, consistency needs, budget, team size — that vary per situation. A design optimal for one set of constraints (e.g., low traffic, strong consistency needed) can be the wrong choice under different constraints (e.g., massive scale, eventual consistency acceptable).

**Q3: Name one concrete way a system without deliberate design tends to fail in production.**
A synchronous call to a slow downstream dependency (e.g., a third-party API) sitting directly in a user-facing request path — when that dependency slows down, the calling service slows or fails too, with no timeout, queue, or circuit breaker to contain the damage.

**Q4: Why do companies use system design interviews instead of just more DSA questions?**
Because the job of a senior engineer is largely about handling ambiguous requirements, making and communicating trade-offs, estimating scale, and anticipating failure modes — skills DSA problems (which are fully specified with one right answer) don't test at all.

**Q5: A requirement says "the app must feel fast." What's wrong with that statement, and what should you do with it in an interview?**
It's not measurable — it's a vague NFR. You should convert it into a concrete, testable target by asking clarifying questions, e.g., "p99 latency under 200ms for the read path," so the design can actually be evaluated against it.

**Q6: Give an example of the same functional requirement leading to two different, both-valid designs.**
"Show a user's notification count": at small scale, a direct `COUNT(*)` query per page load is fine; at huge scale, a denormalized counter maintained in a fast store (e.g., Redis) avoids hammering the database with aggregate queries on every read, at the cost of possible small drift that requires reconciliation.

**Q7: What does it mean that system design has an "organizational" dimension that DSA doesn't?**
Real systems are built and operated by teams, not solved in isolation. Decisions like service boundaries and API contracts determine how much teams must coordinate to ship changes, and some choices (e.g., a database engine) are expensive to reverse later — so design must account for who owns what and what's cheap vs costly to change.
