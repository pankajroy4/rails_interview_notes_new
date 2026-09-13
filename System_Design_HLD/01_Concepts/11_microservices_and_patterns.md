# Microservices and Patterns

## Monolith vs microservices

A **monolith** is a single deployable unit containing all of an application's functionality — one codebase, one build, one deploy, typically one database. A **microservices architecture** splits the application into many small, independently deployable services, each owning its own piece of functionality (and usually its own data store), communicating over the network (HTTP/gRPC/messaging).

| Dimension | Monolith | Microservices |
|---|---|---|
| Deployment | Single unit — one deploy ships everything | Independent — each service deploys on its own schedule |
| Team scaling | Coordination overhead grows as more teams touch the same codebase | Team autonomy — teams own and ship their service without blocking on others |
| Failure isolation | A bug/crash in one part can take the whole app down | Blast radius contained to the failing service (if calls are resilient — see below) |
| Operational complexity | Simple — one thing to deploy, monitor, log | High — requires service discovery, distributed tracing, container orchestration, per-service monitoring |
| Data consistency | Easy — local ACID transactions across tables in one DB | Hard — distributed transactions/sagas needed across service boundaries (see `09_distributed_systems_core.md`) |
| Local development | Simple — run one app | Harder — may need many services running (or mocked) to test one flow |
| Performance (in-process calls) | Fast — function calls, no network hop | Slower — every cross-service call is a network round trip |

**Microservices are not free, and are often adopted prematurely.** The real justification is not "it scales better" — a monolith can scale horizontally too (run N copies behind a load balancer, exactly like you'd scale a service). The actual justification is organizational: **Conway's Law** — the observation that a system's architecture ends up mirroring the communication structure of the organization that built it. If you have many independent teams that each need to ship on their own schedule without waiting on each other's code review, release train, or test suite, a monolith becomes the bottleneck regardless of its technical scalability — every team is coupled to the same deploy, the same on-call, the same risk of "someone else's change broke my part of the app." Microservices let teams become **independently deployable**, which is an organizational/velocity property, not a raw-throughput property. A 5-person startup with one team gets essentially none of this benefit and pays the full operational tax — that's the classic premature-microservices mistake.

### Database-per-service

The data-consistency row above deserves its own explanation, because it's the single biggest hidden cost of adopting microservices. In a monolith, every table typically lives in one database, so a single ACID transaction can atomically update rows across "order," "payment," and "inventory" concepts at once — the database engine guarantees all-or-nothing.

Microservices are expected to each own their **own** database (or at least their own schema/tables that no other service touches directly) — this is what actually makes them independently deployable: if service B could reach directly into service A's tables, B would break the moment A changes its schema, recreating the same tight coupling microservices were meant to remove. But this means the atomic-multi-table-transaction tool is gone the moment an operation spans more than one service's data — there is no single database to run one transaction against anymore. That's precisely the gap the Saga pattern (see `09_distributed_systems_core.md`) exists to fill. The **shared database anti-pattern** — multiple services reading/writing the same database directly to dodge this problem — is generally avoided because it silently re-couples services that are supposed to be independent, defeating the main point of splitting them up in the first place.

## Service discovery

**The problem**: in a system where service instances scale up and down dynamically (autoscaling, deploys, crashes), a caller cannot just hardcode "call the payment service at 10.0.0.5:8080" — that IP might not even exist five minutes from now. Something needs to track which instances of a service are currently alive and reachable, and callers need a way to find that list.

- **Client-side discovery**: the calling service queries a **service registry** (e.g., Consul, Eureka) directly to get the current list of healthy instances, and then does its own load balancing (e.g., round-robin) across them itself.
- **Server-side discovery**: the calling service just calls a fixed address — a **load balancer/router** — which itself queries the registry and forwards the request to a healthy instance. The caller never talks to the registry directly.

| | Client-side discovery | Server-side discovery |
|---|---|---|
| Who queries the registry | The calling service itself | A load balancer/router in front of the target service |
| Extra network hop | No — client calls the instance directly after lookup | Yes — client calls the LB, which forwards to the instance |
| Client complexity | Higher — every client needs registry-aware load-balancing logic | Lower — client just calls a stable address |
| Coupling to registry | Every client is coupled to the registry's API/client library | Only the load balancer is coupled to the registry |
| Common in | Netflix-style stacks (Eureka + Ribbon), some service meshes | Most cloud setups — DNS + a load balancer, Kubernetes Services |

```text
Client-side discovery                    Server-side discovery

Client --> Registry (get instance list)   Client --> Load Balancer --> Registry
Client --> Instance B  (picks one, calls)                          --> Instance B
                                                                     (LB forwards)
```

Most modern cloud-native setups default to server-side discovery (a Kubernetes `Service` + its internal load balancer is a server-side discovery mechanism) because it keeps client code simple — client-side discovery shows up more in older/legacy stacks or where a service mesh sidecar is doing the discovery work on the client's behalf.

## API Gateway recap and the Backend-for-Frontend pattern

An **API Gateway** sits in front of a system's services as a single entry point for external clients, handling cross-cutting concerns like authentication, rate limiting, request routing, and TLS termination in one place instead of duplicating them in every service (see `03_networking_and_apis.md` for the full treatment).

The **Backend-for-Frontend (BFF)** pattern takes this further: instead of one generic gateway trying to serve every kind of client (web, iOS, Android, third-party API consumers) with the same shape of responses, you run a **dedicated gateway per client type**, each tailored to what that specific client actually needs — e.g., a mobile BFF that aggregates and trims responses to minimize payload size and round trips over a mobile network, versus a web BFF that can afford richer, more detailed responses. This avoids the generic gateway becoming a bloated compromise that over-fetches for mobile and under-fetches for web, at the cost of maintaining multiple gateway codebases.

## Service mesh

**The problem it solves**: resilience and observability concerns — retries, timeouts, mutual TLS (mTLS) encryption between services, load balancing, and request tracing/metrics — end up duplicated in every single service's code if each team implements them independently, leading to inconsistent behavior (one service retries 3 times, another 0 times) and a lot of repeated boilerplate across languages/teams.

A **service mesh** moves these concerns out of application code and into an infrastructure layer: a lightweight **sidecar proxy** deployed alongside every service instance intercepts all its network traffic (both incoming and outgoing) and handles retries, timeouts, mTLS, load balancing, and telemetry uniformly — the application code just makes a plain local call to its own sidecar and stays unaware of the network-level machinery.

- **Istio**: a widely used service mesh built on the Envoy proxy, offering fine-grained traffic control (canary routing, fault injection) and strong mTLS/security policy support.
- **Linkerd**: a lighter-weight, simpler-to-operate service mesh focused on being easy to adopt with a smaller resource footprint than Istio.

Both are deep topics on their own — the interview-relevant takeaway is *why* a mesh exists (centralizing cross-cutting network concerns out of application code) rather than their internals.

## Resilience patterns

These patterns exist because in a microservices architecture, network calls between services fail constantly (timeouts, slow responses, crashes) — and without deliberate handling, one struggling service's failure spreads to every service that calls it.

### Circuit breaker

**What triggers it**: a downstream dependency starts failing or timing out beyond a configured threshold (e.g., more than 50% of calls fail in a rolling window).

**What it prevents**: continuing to send requests to a dependency that's already struggling only makes things worse — callers pile up waiting on timeouts, consuming threads/connections, and the failing service gets no chance to recover under the still-incoming load. A circuit breaker stops calling the dependency entirely once the threshold trips, **failing fast** instead (immediate error/fallback, no wasted wait), and periodically allows a trial request through to check if the dependency has recovered.

Three states:
- **Closed**: normal operation, requests flow through, failures are being counted.
- **Open**: threshold tripped — all requests fail immediately without even attempting the call.
- **Half-open**: after a cooldown period, a limited number of trial requests are allowed through; if they succeed, the breaker closes again (resume normal traffic); if they fail, it reopens.

```text
   failures exceed threshold
CLOSED ------------------------> OPEN
   ^                                |
   | trial requests succeed        | cooldown timer expires
   |                                v
   +---------------------------- HALF-OPEN
              trial requests fail --> back to OPEN
```

### Bulkhead

**What triggers it**: it's not a reaction to a failure — it's a proactive resource-isolation design. Named after ship bulkheads (compartments that keep one flooded section from sinking the whole ship).

**What it prevents**: without isolation, a shared pool of threads/connections used to call *every* downstream dependency means one slow dependency can exhaust the entire pool waiting on it — starving calls to completely unrelated, healthy dependencies of the resources they need. A bulkhead allocates **separate resource pools per dependency** (e.g., a fixed-size connection pool or thread pool dedicated to calls to service B, independent of the pool used for service C), so a slow/stuck service B can only ever exhaust its own small pool, never starve calls to service C.

### Retry with exponential backoff + jitter

**What triggers it**: a call fails or times out and is considered safe/worth retrying (ideally only for idempotent operations — see `09_distributed_systems_core.md`).

**What it prevents / why naive retries make things worse**: if every failed caller retries immediately, and the reason for the failure was the downstream service being overloaded, an immediate retry storm adds even more load to an already-struggling service — actively delaying its recovery. **Exponential backoff** waits progressively longer between retries (e.g., 100ms, 200ms, 400ms, 800ms) to give the dependency room to recover instead of hammering it continuously. **Jitter** (adding a small random amount to each backoff delay) prevents the thundering-herd effect where many clients that failed at the same moment (e.g., because the dependency just went down) all retry at exactly the same synchronized intervals, recreating the same spike of load repeatedly instead of spreading it out.

### Timeouts

**Why every network call needs one**: without an explicit timeout, a caller can wait indefinitely for a response from a slow or hung dependency, tying up its own resources (threads, connections) the entire time. **The danger of not having one**: a single slow dependency can, over time, exhaust the caller's own resource pools purely from requests piling up waiting on it — turning one slow downstream service into an outage of the calling service too, even though the calling service's own code has no bug. Every one of the other resilience patterns above assumes timeouts are already in place — a circuit breaker can't count "failures" that never resolve, and a bulkhead's pool fills up permanently without a timeout to eventually free its slots.

## Strangler fig pattern

The **strangler fig pattern** (named after the vine that grows around a tree, gradually replacing it, until the original tree is gone) is how teams incrementally migrate a monolith to microservices without a risky big-bang rewrite. Instead of stopping feature work to rebuild everything from scratch (a project that routinely takes far longer than estimated and freezes the old system's improvement in the meantime), you:

1. Put a routing layer (often the API gateway) in front of both the monolith and the new services.
2. Extract one piece of functionality at a time into a new service.
3. Route an increasing slice of traffic for that functionality to the new service, while everything else still goes to the monolith.
4. Repeat, piece by piece, until the monolith handles nothing (or only what's deliberately left there).

```text
Before:                          During migration:                   After:
Client --> Monolith              Client --> Gateway --+-> Monolith    Client --> Gateway --> New Service A
           (everything)                               +-> New Svc A              +-> New Service B
                                                                                   +-> Monolith (remainder)
```

The benefit is that each extracted piece is independently low-risk and reversible (you can route traffic back to the monolith if the new service has problems), and the system stays fully functional and shippable throughout the migration, rather than being frozen mid-rewrite.

## Trade-offs / When to use what

| Situation | Lean toward | Why |
|---|---|---|
| Small team, early-stage product | Monolith | No org-scaling problem yet; avoid the operational tax of microservices for no benefit |
| Multiple independent teams needing to ship on their own schedule | Microservices | Conway's Law — independent deployability matches independent teams |
| Need raw horizontal scalability only | Either — scale out monolith replicas, or split into services | Horizontal scaling doesn't by itself require microservices |
| Different client types with very different data needs | BFF per client type | Avoids a bloated one-size-fits-all gateway |
| Many services duplicating retry/mTLS/observability code | Service mesh | Centralizes cross-cutting concerns instead of duplicating per-service |
| Migrating an existing monolith | Strangler fig | Incremental, reversible, avoids a risky big-bang rewrite |

## Interview Tips

- If you propose microservices, the interviewer will often ask "why not just scale the monolith horizontally?" — have the Conway's Law / team-autonomy answer ready; "it scales better" alone is a weak answer since monoliths scale too.
- Circuit breaker, bulkhead, retry+backoff+jitter, and timeouts are frequently asked as a group ("how do you make this service resilient to a failing dependency?") — naming all four together, and what each specifically prevents, is a strong signal of practical production experience.
- If an interviewer says "assume this is a monolith today and needs to become microservices," strangler fig is the expected answer over "rewrite it" — proposing a full rewrite is read as a red flag for real-world judgment.
- Service discovery questions ("how does service A find service B's healthy instances?") are common in any design with dynamic scaling — know both client-side and server-side discovery and be able to say which is more common in a Kubernetes-based stack (server-side, via a Service/load balancer).
- Don't reach for a service mesh as a default answer to "how do you handle retries/mTLS" for a small number of services — it's justified once the duplication/inconsistency problem across many services is real, not from day one.

## Quick Recall — Self-Test

**Q1: What is the actual justification for choosing microservices over a monolith, and why isn't "better scalability" alone a sufficient answer?**
The real justification is organizational: Conway's Law says a system's architecture mirrors the org's communication structure, so independent teams need independently deployable services to ship without blocking on each other. "Better scalability" alone is insufficient because a monolith can also scale horizontally by running many replicas behind a load balancer.

**Q2: What's the difference between client-side and server-side service discovery?**
In client-side discovery, the calling service queries the registry itself and load-balances across instances on its own. In server-side discovery, the client calls a fixed load balancer/router address, which queries the registry and forwards the request — the client never talks to the registry directly.

**Q3: What specifically does a circuit breaker prevent, and what are its three states?**
It prevents continuing to hammer an already-failing dependency with requests that pile up waiting on timeouts, consuming caller resources while giving the dependency no room to recover. Its states are closed (normal traffic flows), open (fails fast, no calls attempted), and half-open (limited trial requests after a cooldown to check for recovery).

**Q4: How does a bulkhead differ from a circuit breaker in what it protects against?**
A circuit breaker reacts to a specific dependency already failing and stops calling it. A bulkhead is proactive resource isolation — separate pools (threads/connections) per dependency — so a slow dependency can only exhaust its own pool, never starve calls to unrelated healthy dependencies sharing the same caller.

**Q5: Why does naive immediate retrying make outages worse, and what two techniques fix this?**
If a failure is caused by an overloaded dependency, immediate retries from every failed caller add even more load right when the dependency needs less, delaying recovery. Exponential backoff spaces out retries with increasing delay to give the dependency room to recover, and jitter randomizes those delays so many clients that failed simultaneously don't retry in synchronized spikes.

**Q6: Why does every one of the other resilience patterns assume timeouts are already in place?**
A circuit breaker can't count failures that never resolve without a timeout defining when a call counts as failed, and a bulkhead's dedicated pool fills up permanently and stays exhausted without a timeout eventually freeing its slots — timeouts are the basic mechanism that bounds how long any call is allowed to hold resources.

**Q7: What problem does the strangler fig pattern solve, and how does it work at a high level?**
It avoids the risk of a big-bang monolith rewrite (long timelines, frozen improvements, high failure risk) by incrementally routing an increasing slice of traffic to new services extracted one piece at a time, while the monolith still handles everything not yet migrated — keeping the system fully functional throughout.

**Q8: What is the Backend-for-Frontend pattern, and what problem does it solve that a single generic API Gateway doesn't?**
BFF runs a dedicated gateway per client type (web, mobile, etc.), each tailored to that client's specific data and payload needs. It solves the problem of a single generic gateway becoming a bloated compromise — over-fetching for constrained clients like mobile, or under-serving richer clients like web.

**Q9: Why does "database-per-service" break the ability to run a single atomic transaction across an operation that spans multiple services, and what fills that gap?**
Each service owning its own database means there's no longer one shared database engine that can enforce an all-or-nothing transaction across, say, order and payment and inventory data — those now live in separate databases with separate services in front of them. The Saga pattern fills the gap by sequencing local transactions with compensating actions instead of relying on a single cross-service atomic transaction.

**Q10: Why is the "shared database" anti-pattern considered harmful in a microservices architecture?**
It lets multiple services read/write the same database directly, which silently re-couples them — a schema change by one service can break another service reaching into the same tables — defeating the independent-deployability benefit that was the actual reason to adopt microservices in the first place.
