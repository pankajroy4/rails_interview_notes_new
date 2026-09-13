# Load Balancing

## What a load balancer does and why it's needed

A **load balancer (LB)** sits in front of a pool of servers and distributes incoming requests across them. It gives clients a single, stable entry point (one IP/domain) while the actual work is spread across many machines behind it.

Without one: clients would need to know about every server individually (fragile — what happens when a server is added, removed, or dies?), and any single server could be overwhelmed by more traffic than it can handle while others sit idle. A load balancer solves both problems: it hides the pool's internal topology from clients, and it actively spreads load so no single server becomes the bottleneck (or falls over) while capacity exists elsewhere in the pool.

**The important nuance**: introducing a load balancer to remove a single point of failure from your server pool just moves the single point of failure to the load balancer itself — if the LB dies, every server behind it becomes unreachable even though they're all healthy. So the LB itself must be made highly available, typically via:

- **Active-passive LB pairs**: a standby LB monitors the primary and takes over (via a floating/virtual IP) if the primary fails.
- **DNS round-robin across multiple LBs**: multiple independent load balancer instances are all published under the same DNS name, so a client is handed one of several LBs, and losing one doesn't take down the entry point entirely.

## Why it matters

Real systems fail without proper load balancing in specific, visible ways:

- **Hot-spotting**: without balancing, requests might all land on one server (e.g., due to naive round-robin over a DNS cache, or a sticky client) while others sit idle — that one server times out or crashes under load that the pool as a whole could easily have absorbed.
- **No graceful handling of server failure**: if one app server crashes and there's no health-check-aware LB in front, a fraction of all incoming requests keep getting routed to the dead server and fail, instead of being automatically routed only to healthy servers.
- **The LB becomes an unplanned single point of failure**: teams add a load balancer to fix availability, then forget the LB itself needs redundancy — and a single LB outage takes down a perfectly healthy fleet behind it.

## L4 vs L7 Load Balancing

Load balancers operate at different layers of the network stack, and the layer determines what information they can use to route.

| | L4 (Transport Layer) | L7 (Application Layer) |
|---|---|---|
| Operates on | IP address and port | Full HTTP request content — path, headers, cookies, method, body |
| Awareness | Protocol-agnostic — doesn't parse the payload, just forwards packets/connections | Protocol-aware — understands HTTP (or gRPC, WebSocket, etc.) |
| Speed / CPU cost | Faster, lower CPU overhead (no payload inspection) | Slower, higher CPU cost (has to terminate/parse the request) |
| Routing intelligence | Basic — routes by IP/port only | Smart — can route `/api/orders` to one service and `/api/users` to another, route based on a cookie, do A/B testing by header, etc. |
| Typical use | High-throughput, protocol-agnostic traffic (e.g., raw TCP services, database traffic) | Web/API traffic where routing decisions depend on request content |

Concrete implication: an L4 LB can't route based on URL path (it never looks at the HTTP request, only at IP/port), so if you need `/checkout` and `/search` to go to different backend services from the same public endpoint, you need an L7 LB (or an L7 layer, like an API Gateway, downstream of an L4 LB).

## Load Balancing Algorithms

| Algorithm | How it works | When it's appropriate |
|---|---|---|
| Round robin | Requests distributed to servers in fixed rotating order | Servers are roughly equal in capacity and requests are roughly equal in cost |
| Weighted round robin | Like round robin, but servers with more capacity get proportionally more requests | Server pool is heterogeneous (some bigger/faster machines than others) |
| Least connections | New request goes to the server with the fewest active connections | Request durations vary a lot — avoids piling more work onto an already-busy server |
| Least response time | New request goes to the server with the lowest recent response time (and/or fewest active connections) | You want to actively favor servers that are currently performing best, not just least loaded |
| IP hash | Client's IP is hashed to consistently map to the same server | Need a simple way to keep a given client on the same server without external session storage |
| Consistent hashing | Requests/keys are mapped onto a hash ring so that when a server is added/removed, only a small fraction of mappings change (instead of nearly all of them, as with plain modulo hashing) | Distributing requests or data across a changing set of nodes with minimal reshuffling — this is covered in depth in `database_scaling.md` and `caching.md`, since it's the backbone of consistent-hash-based sharding and cache node distribution; introduced here only as a routing option |

## Health Checks

A load balancer can only route around failure if it knows which servers are actually healthy.

- **Active health checks**: the LB proactively sends periodic requests (e.g., `GET /health`) to each server and marks it unhealthy if it stops responding correctly or times out. Catches failures even when no real traffic is currently hitting that server.
- **Passive health checks**: the LB observes real production traffic and marks a server unhealthy if actual requests to it start failing or timing out. Reflects real-world behavior directly, but by definition only detects failure after real requests have already suffered.

Both matter together: active checks catch a dead server before it's discovered via failed customer requests; passive checks catch subtler failures (e.g., a server that responds to a trivial `/health` endpoint fine but is actually failing real, heavier requests) that a shallow active check would miss.

## Sticky Sessions (Session Affinity)

**Sticky sessions**: the load balancer routes all requests from a given client to the same backend server for the duration of their session (commonly via a cookie or IP hash).

**Why it's sometimes needed**: if a server keeps session state in its own local memory (e.g., a shopping cart held in-process rather than in a shared store), that client *must* keep hitting the same server, or their session data appears to vanish when a different server handles their next request.

**Why it's generally avoided in modern design**: sticky sessions undermine the core benefit of horizontal scaling and load balancing — if a server holding many "stuck" clients gets overloaded or dies, you can't freely redistribute its load (or its users lose their session state entirely). The preferred alternative is to design services **stateless**: externalize session state to a shared, fast store like Redis that any server instance can read, so any request can go to any server and get identical behavior. This keeps the LB free to balance purely on load/health, without being constrained by "which server already has this user's state."

## Where Load Balancers Sit

```text
        clients
           |
           v
          DNS  (resolves to one of several LB IPs / a GSLB decision)
           |
           v
   +----------------+
   |  Load Balancer  |  (active-passive pair, or multiple behind DNS round-robin)
   +--------+--------+
            |
   +--------+---------+---------+
   |        |         |         |
   v        v         v         v
 +-----+  +-----+   +-----+   +-----+
 | App |  | App |   | App |   | App |
 | Srv |  | Srv |   | Srv |   | Srv |
 +-----+  +-----+   +-----+   +-----+
```

Load balancers aren't only at the public edge. They also commonly sit:

- **In front of database read replicas** — spreading read queries across multiple replicas so no single replica takes all the read traffic.
- **Between internal microservices** — service A calling service B often goes through a load balancer (or service-mesh sidecar doing the same job) so B can be scaled to multiple instances transparently to A.

## Trade-offs / When to use what

| Choice | Trade-off |
|---|---|
| L4 LB | Fast, protocol-agnostic, cheap — but can't make content-aware routing decisions |
| L7 LB | Smart, content-aware routing — but costs more CPU per request and adds a bit of latency |
| Round robin | Simple, no state to track — but ignores actual server load, so uneven request costs cause imbalance |
| Least connections | Adapts to real load — but requires the LB to track connection state per server, slightly more overhead |
| Sticky sessions | Simple way to keep in-memory state working — but reintroduces the "server as single point of failure for its users" problem that load balancing was meant to remove |
| Externalized session state (e.g., Redis) | Keeps servers stateless and freely interchangeable — but adds an extra network hop and a dependency on the shared store's own availability |

## Interview Tips

Load balancing questions test whether you understand that an LB is not a magic box you draw once and never mention again — interviewers want to hear you reason about *what* it's routing on (L4 vs L7) and *how* (which algorithm, and why that one fits the traffic pattern you described). A common trap is proposing sticky sessions without acknowledging the trade-off — a strong answer either justifies it explicitly (e.g., "we're keeping session state in-memory for now, so we need affinity") or proactively avoids it by externalizing state. Also expect to be asked "what if the load balancer itself goes down?" — having the active-passive / multiple-LBs-behind-DNS answer ready shows you're not treating the LB as inherently infallible. Finally, mentioning that load balancers also appear in front of DB replicas and between internal services (not just at the public edge) signals you're thinking about the whole architecture, not just the entry point.

## Quick Recall — Self-Test

**Q1: Why does adding a single load balancer in front of your server pool not fully solve your availability problem?**
It removes the server pool as a single point of failure but introduces the load balancer itself as a new single point of failure — if that one LB goes down, every healthy server behind it becomes unreachable. The LB needs its own redundancy (active-passive pair, or multiple LBs behind DNS) to actually close the gap.

**Q2: What can an L7 load balancer do that an L4 load balancer fundamentally cannot, and why?**
An L7 LB can route based on the actual HTTP request content — path, headers, cookies (e.g., send `/api/orders` to one service and `/api/search` to another). An L4 LB operates only on IP/port and never inspects the payload, so it has no visibility into HTTP-level information to route on.

**Q3: When would "least connections" be a better choice than plain round robin?**
When request costs vary significantly — round robin blindly rotates regardless of how "expensive" a request is, so a server can end up with several long-running requests while another sits idle. Least connections actively routes new requests to whichever server currently has the fewest in-flight connections, adapting to real load.

**Q4: What's the difference between active and passive health checks, and why do production systems typically use both?**
Active checks are proactive pings/polls the LB sends on a schedule to test server health, even without real traffic. Passive checks observe actual production traffic and flag a server unhealthy when real requests to it fail. Both matter because active checks catch a fully dead server fast, while passive checks catch failures that only show up under real request patterns a shallow health endpoint wouldn't reveal.

**Q5: Why are sticky sessions generally discouraged in modern service design, and what's the standard alternative?**
They tie a client to one specific server, which undermines load balancing's ability to freely redistribute load and means that server dying can lose or strand that client's session. The standard alternative is making services stateless by externalizing session state to a shared store like Redis, so any server can serve any client's request.

**Q6: Besides the public-facing edge, name two other places in an architecture where load balancers commonly appear.**
In front of a database's read replicas (spreading read queries across them), and between internal microservices (so a calling service can transparently talk to a scaled-out pool of instances of the service it depends on).

**Q7: What problem does consistent hashing solve that plain round robin or simple modulo hashing does not, at a high level?**
When the set of backend nodes changes (a node is added or removed), consistent hashing only remaps a small fraction of the keys/requests to different nodes, whereas simple modulo-based hashing remaps nearly everything — consistent hashing minimizes the disruption caused by scaling the pool up or down.

**Q8: Two LBs are deployed for redundancy, using DNS round-robin between them. What's the failover trade-off compared to an active-passive pair with a floating IP?**
DNS round-robin failover is bounded by DNS TTL — clients with a cached record for the now-dead LB keep trying it until the TTL expires, so failover isn't instant. An active-passive pair with a floating IP can fail over faster since the IP itself moves to the standby without waiting on DNS cache expiry, though it requires the active-passive mechanism to be reliable and fast to detect failure itself.
