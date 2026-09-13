# Networking and APIs

## Why it matters

Every distributed system is, underneath, a collection of processes talking over a network — and the network is unreliable, has latency, and can partition. Choices made at this layer (which protocol, which communication pattern, how clients discover servers) directly determine whether your system can fail over quickly, whether real-time features are even feasible, and whether internal services can evolve independently. Get DNS TTLs wrong and a failover that should take seconds takes an hour. Pick a chatty REST API for a latency-sensitive mobile client and you burn the user's battery and data plan on 15 round trips to render one screen. This layer is invisible when it works and is the first thing to blame when it doesn't.

## DNS (Domain Name System)

**DNS** translates human-readable domain names (`api.example.com`) into IP addresses that machines actually route traffic to. It's effectively the internet's phone book, and it's also a lever system designers use for load balancing and failover.

**Resolution chain** (simplified, for an uncached lookup):

```text
client
  -> recursive resolver (usually your ISP or 8.8.8.8/1.1.1.1)
       -> root nameserver          (says: "ask the .com TLD server")
            -> TLD nameserver      (.com — says: "ask example.com's authoritative server")
                 -> authoritative nameserver for example.com
                      (returns the actual IP address for api.example.com)
  <- recursive resolver caches and returns the IP to the client
```

In practice, most lookups are served from cache at the recursive resolver (or even the OS/browser) well before reaching the root — the full chain only runs on a cold cache.

**Why DNS matters in system design:**

- **DNS-based load balancing / GSLB (Global Server Load Balancing)**: a DNS query for the same hostname can return different IP addresses depending on the querying client's location, current server health, or load — routing users to the nearest or least-loaded regional deployment before a single packet reaches your infrastructure.
- **TTL (Time To Live) and failover speed**: every DNS record has a TTL telling resolvers how long to cache the answer. A long TTL (e.g., 24 hours) means stale IPs (e.g., a decommissioned server) keep getting used by clients with a cached answer, slowing failover. A short TTL (e.g., 30-60 seconds) lets you redirect traffic away from a failed region quickly, at the cost of more DNS query volume and slightly higher per-request DNS lookup overhead for clients with cold caches.
- **CDN edge selection**: CDNs (Content Delivery Networks) commonly use DNS to route a client to the geographically/network-nearest edge server, so the DNS answer itself is part of how content gets served from a nearby location instead of a single origin far away.

## TCP vs UDP

Both are transport-layer protocols — sitting on top of IP — but they make opposite trade-offs between reliability and speed.

| | TCP | UDP |
|---|---|---|
| Connection | Connection-oriented (handshake before data flows) | Connectionless (just send packets) |
| Reliability | Guaranteed delivery — lost packets are retransmitted | No delivery guarantee — lost packets are just gone |
| Ordering | Guaranteed in-order delivery | No ordering guarantee |
| Overhead | Higher (handshake, acks, retransmission, flow control) | Lower (minimal framing, no acks) |
| Speed | Slower due to reliability machinery | Faster — no waiting for acknowledgment/retransmission |
| Typical use | APIs, databases, file transfer, anything needing correctness | Video calls, gaming, DNS, live streaming |

**Why each is chosen:** TCP is the default for almost all application-layer traffic (HTTP APIs, database connections) because losing or reordering a byte of an API response or a SQL query result is unacceptable — correctness matters more than the extra milliseconds of overhead. UDP is chosen when an occasional dropped packet is preferable to the delay of retransmitting it: in a video call, a lost frame that gets retransmitted 200ms late is worse than just skipping it and moving on to the current frame; a stale video frame isn't useful once it's late. DNS itself typically runs over UDP for the same reason — a quick, single-round-trip lookup where a client can simply retry on timeout rather than pay TCP's connection setup cost for every query.

## HTTP/HTTPS and protocol versions

**HTTP** (HyperText Transfer Protocol) is the application-layer protocol most APIs and web traffic run over, built on top of TCP (or, in HTTP/3, UDP). **HTTPS** is HTTP over **TLS** (Transport Layer Security) — it encrypts the connection so data can't be read or tampered with in transit. HTTPS is the default today (not just for logins/payments) because: any traffic on an untrusted network (public wifi, an ISP, a compromised router) is otherwise readable and modifiable in transit; browsers and search engines actively penalize/warn on plain HTTP; and TLS also gives you server identity verification (preventing you from silently talking to an impersonator).

| | HTTP/1.1 | HTTP/2 | HTTP/3 |
|---|---|---|---|
| Transport | TCP | TCP | UDP (via QUIC) |
| Multiplexing | No — one request waits per connection (browsers open several connections to compensate) | Yes — many requests/responses interleaved on one connection | Yes, and at the transport level |
| Header compression | No (headers sent as plain text repeatedly) | Yes (HPACK) | Yes (QPACK) |
| Head-of-line blocking | Yes, badly | Reduced at the HTTP layer, but a single lost TCP packet still blocks *all* multiplexed streams (TCP-level HOL blocking) | Avoided — QUIC handles each stream independently, so one lost packet only blocks its own stream |
| When it matters | Legacy/simple cases | Default for most modern web/API traffic | High-latency or lossy networks (mobile), where TCP's HOL blocking hurts most |

The practical takeaway for system design: HTTP/2's multiplexing is why you no longer need tricks like domain sharding or spriting to work around per-connection request limits, and HTTP/3's move to QUIC-over-UDP is specifically to fix the case where one lost packet on a flaky mobile connection used to stall every in-flight request on that TCP connection.

## Real-Time Communication Options

When a server needs to push updates to a client without the client repeatedly asking "anything new?", there are several patterns with very different cost/complexity profiles.

| | Direction | Connection overhead | Support | Use when |
|---|---|---|---|---|
| Short polling | Client asks repeatedly on a fixed interval | New HTTP request every interval — high overhead, wasted requests when nothing changed | Universal (plain HTTP) | Simplicity matters more than freshness; updates are infrequent (e.g., poll every 30s for a status check) |
| Long polling | Client asks, server holds the request open until there's data (or a timeout), client immediately re-asks | Fewer wasted round trips than short polling, but still repeated connection setup | Universal (plain HTTP) | Need near-real-time updates but can't use WebSockets (e.g., restrictive proxies/firewalls) |
| Server-Sent Events (SSE) | Unidirectional: server to client only | One long-lived HTTP connection, low overhead, auto-reconnect built into the browser API | Native browser support (`EventSource`), plain HTTP/HTTPS, not supported the same way on all mobile/native clients | Server pushes a stream of updates and the client never needs to send data back (e.g., live news feed, stock ticker, notification stream) |
| WebSockets | Bidirectional, full-duplex | One persistent connection after an initial HTTP upgrade handshake; low per-message overhead after that | Broadly supported, but needs infra that keeps long-lived connections open (LBs/proxies must support upgrade) | Client and server both need to send data continuously with low latency (e.g., chat, multiplayer games, collaborative editing) |

Rule of thumb: reach for the simplest option that satisfies the freshness requirement. Short polling first if update frequency is low; SSE if it's server-to-client only; WebSockets only when the client genuinely needs to send data back in real time too, since it's the most operationally expensive of the four (persistent bidirectional connections at scale mean your infrastructure must hold open and route state for every connected client).

## API Paradigms: REST vs GraphQL vs gRPC

| | REST | GraphQL | gRPC |
|---|---|---|---|
| Data fetching model | Fixed endpoints, each returns a fixed shape | Client specifies exactly the fields it wants in one query | Defined RPC (Remote Procedure Call) methods with strict request/response schemas |
| Over/under-fetching | Common — an endpoint may return more fields than needed (over-fetching) or force multiple calls to assemble a full view (under-fetching) | Solves both — client asks for exactly what it needs, in one round trip | Not really applicable — each call is a precise, purpose-built method |
| Schema/typing | Usually loose (JSON, optionally OpenAPI spec on top) | Strongly typed schema is core to GraphQL itself | Strongly typed via Protocol Buffers (.proto files), code-generated clients/servers |
| Performance | Reasonable; JSON + HTTP/1.1 or HTTP/2 | Similar to REST on the wire, but fewer round trips can win overall | Fastest — binary Protobuf serialization + HTTP/2 multiplexing, much smaller payloads than JSON |
| Typical use case | Public-facing APIs; simple, cacheable, widely understood | Mobile/frontend clients needing flexible queries across many resources without over-fetching | Internal service-to-service (microservice) communication where performance and strict contracts matter |

**Why the use-case split**: REST's simplicity, cacheability (standard HTTP caching semantics work naturally), and universal tooling make it the safe default for a public API consumed by many unknown clients. GraphQL earns its complexity when a frontend/mobile client needs to assemble data from many underlying resources and the network round-trip cost of multiple REST calls (or the waste of over-fetched fields on a slow mobile connection) is a real problem. gRPC's binary format and HTTP/2 multiplexing make it the default choice for internal microservice-to-microservice calls, where both ends are code you control (so a generated, strongly-typed client/server pair is a benefit, not a constraint) and raw performance/low overhead matters more than human-readability of the wire format.

## API Gateway

An **API Gateway** is a single entry point that sits between external clients and your internal services, and handles cross-cutting concerns so individual services don't each have to reimplement them:

- **Authentication** — verifying who's calling before a request ever reaches internal services.
- **Rate limiting** — throttling clients to protect backend services from being overwhelmed (by one abusive client or an accidental retry storm).
- **Request routing** — directing a request to the right internal service based on path, header, or other rule.
- **Response aggregation** — calling multiple internal services and combining their responses into one response for the client (reducing client-side round trips).
- **Protocol translation** — e.g., exposing REST externally while internal services communicate over gRPC.

```text
                         +-------------------+
 client (web/mobile) --> |    API Gateway    |
                         | (auth, rate limit, |
                         |  routing, aggreg.) |
                         +---------+---------+
                                   |
                 +-----------------+------------------+
                 |                 |                   |
                 v                 v                   v
          +-------------+  +-------------+     +-------------+
          | User Service|  | Order Service|    | Payment Svc |
          +-------------+  +-------------+     +-------------+
```

The gateway centralizes concerns that would otherwise be duplicated (and inevitably implemented inconsistently) across every internal service, and it's also what lets internal services change their own protocols/implementations freely as long as the gateway's external contract stays stable.

## Trade-offs

| Decision | Trade-off |
|---|---|
| Short DNS TTL | Faster failover, but more DNS query load and slightly higher cold-lookup latency |
| TCP over UDP | Reliability/ordering guaranteed, at the cost of latency and overhead |
| WebSockets over SSE/polling | Full bidirectional real-time capability, at the cost of holding many persistent connections in infrastructure |
| GraphQL over REST | Flexible, efficient client queries, at the cost of losing simple HTTP caching and adding query-complexity/abuse risks server-side |
| gRPC over REST | Much better performance/type-safety, at the cost of human-readability and broad external client compatibility (browsers need a proxy layer like gRPC-Web) |

## Interview Tips

Networking/API questions usually surface as a sub-decision inside a larger design ("how would the client get live updates?" or "should this be REST or gRPC?") rather than as a standalone question. Interviewers are checking that you know these aren't interchangeable defaults — that you can justify *why* WebSockets over polling, or gRPC over REST, based on the actual requirement (bidirectional need, internal vs external consumer, latency sensitivity) rather than picking the trendiest option. Mentioning DNS TTLs when discussing failover time, or mentioning that an API Gateway is where you'd put rate limiting/auth rather than in every service, are the kind of specific details that signal real hands-on exposure rather than memorized buzzwords.

## Quick Recall — Self-Test

**Q1: What's the practical effect of a very long DNS TTL when a server fails and you need to redirect traffic away from it?**
Clients and resolvers that already cached the old IP keep using it until the TTL expires, so failover is slow — traffic keeps hitting the dead server for as long as the TTL specifies, even though DNS has already been updated.

**Q2: Why does DNS typically use UDP instead of TCP?**
DNS lookups are small, single-round-trip request/response exchanges where an occasional lost query can simply be retried by the client; paying TCP's connection-setup overhead for every lookup would add unnecessary latency for a use case that doesn't need TCP's ordering/reliability guarantees.

**Q3: What specific problem does HTTP/3 (QUIC) solve that HTTP/2 still has?**
HTTP/2 multiplexes multiple streams over one TCP connection, but a single lost TCP packet still blocks all of those streams (TCP-level head-of-line blocking) because TCP delivers bytes in strict order. HTTP/3 runs over QUIC/UDP, where each stream is handled independently, so a lost packet only stalls its own stream.

**Q4: A dashboard needs to show live stock prices to the client but the client never sends data back. Which real-time option fits best, and why not WebSockets?**
Server-Sent Events (SSE) fits best — it's unidirectional server-to-client, which matches the requirement exactly, has lower overhead than a full-duplex connection, and has built-in reconnect support in browsers. WebSockets would work but is unnecessary complexity/overhead since the client-to-server direction is never used.

**Q5: Why is gRPC generally preferred over REST for internal microservice-to-microservice calls, but not for a public API?**
gRPC's binary Protobuf payloads and HTTP/2 multiplexing give much better performance and strict, code-generated type safety, which is ideal when you control both ends of the call. For a public API, REST's human-readable JSON, broad tooling/client support, and native HTTP caching make it more accessible to arbitrary external consumers.

**Q6: What problem does GraphQL solve that plain REST commonly has, and what does it give up to solve it?**
It solves over-fetching (endpoint returns more fields than needed) and under-fetching (needing multiple REST calls to assemble one view) by letting the client specify exactly the fields it wants in a single query. It gives up REST's simple, standard HTTP caching semantics and adds server-side complexity around query cost/abuse protection.

**Q7: List three responsibilities of an API Gateway and explain why centralizing them there is better than each service handling them independently.**
Authentication, rate limiting, and request routing (also response aggregation and protocol translation) are typical responsibilities. Centralizing them avoids every internal service having to reimplement the same cross-cutting logic (inconsistently), and lets the gateway's external contract stay stable even as internal services and protocols change behind it.

**Q8: Why is TCP the default choice for database connections and API calls, while UDP is chosen for video calls?**
Database queries and API responses must arrive complete, uncorrupted, and in order — a dropped or reordered byte is a correctness bug, so TCP's reliability guarantees are required. In a video call, a dropped frame that's stale by the time it's retransmitted is worse than just skipping it, so UDP's lower latency (no retransmission wait) is preferred over guaranteed delivery.
