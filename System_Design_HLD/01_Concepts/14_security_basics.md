# Security Basics

## Why it matters

Every system design interview eventually touches "how do you know who's calling this API, and how do you stop it from being abused." You don't need to be a security engineer to do well here — you need a correct mental model of a small set of recurring concepts (authentication vs authorization, session vs token auth, rate limiting, encryption) so that when an interviewer asks "how would you prevent someone from hammering this endpoint" or "how does the client prove who it is," you have a precise, confident answer instead of a vague gesture at "add some security." These same concepts also matter directly in production Rails apps you already operate — this file gives the vocabulary layer on top of instincts you likely already have (e.g., you've used `devise` or JWTs, you've rate-limited an API, you already serve everything over HTTPS).

## Authentication vs Authorization

**Authentication (AuthN)** answers "who are you?" — proving identity. Logging in with a username and password (or a passkey, or an OAuth flow) is authentication: at the end of it, the system knows *which* user is making requests.

**Authorization (AuthZ)** answers "what are you allowed to do?" — permission, given a known identity. Being logged in as a regular user and getting a `403 Forbidden` when hitting `/admin/users` is authorization: the system knows exactly who you are, it's just decided you don't have the rights for that action.

They're separate concerns and separate failure modes: a system can have flawless authentication (rock-solid login) and still leak data if authorization checks are missing (any logged-in user can hit another user's private endpoint by guessing an ID) — that class of bug is called **broken access control**, and it's one of the most common real-world security failures. Always model them as two distinct checks in a design, not one blended "is this request OK" step.

| | Authentication | Authorization |
|---|---|---|
| Question | Who are you? | What are you allowed to do? |
| Example | Logging in with a password | Being blocked from `/admin` while logged in |
| Failure mode | Someone impersonates another user | A legitimate user accesses data/actions they shouldn't |
| Typically happens | Once per session/token issuance | On every request, per resource/action |

## Session-based auth vs Token-based auth (JWT)

Both answer "once a user has logged in, how does each subsequent request prove who they are without re-sending a password every time?" — they differ in where the state of "this user is logged in" lives.

**Session-based auth**: after login, the server creates a session record (server-side state — typically in a DB or a fast store like Redis) keyed by a random session ID, and sends that ID to the client as a cookie. On each request, the client sends the cookie back, and the server looks up the session ID to find out who's logged in.

- Revocation is trivial: delete the session record server-side, and the user is instantly logged out everywhere.
- Requires either **sticky sessions** (the load balancer always routes a given user to the same server that holds their session in memory — see `04_load_balancing.md`) or a **shared session store** (Redis/DB reachable by every server) so any server can validate any session. Sticky sessions reintroduce a form of server-affinity that complicates horizontal scaling and failover; a shared store avoids that but is another piece of infrastructure to run and adds a lookup on every request.

**Token-based auth (JWT — JSON Web Token)**: after login, the server issues a signed token containing the user's identity and claims (e.g., user ID, roles, expiry) directly inside the token itself. The client sends the token on each request (commonly in an `Authorization` header), and any server can verify it using the signing key/secret — no database lookup, no shared session store, because the token is **self-contained and stateless**.

JWT structure, at the level you need for an interview: `header.payload.signature`, three base64url-encoded segments separated by dots.
- **Header**: metadata, e.g. which signing algorithm was used.
- **Payload**: the claims — arbitrary data like user ID, roles, expiry time. Readable by anyone who has the token (it's encoded, not encrypted), so never put secrets in it.
- **Signature**: cryptographically signed by the server using a secret (or private key), so any server holding the corresponding secret/public key can verify the token hasn't been tampered with, without needing to store anything about the session.

The core trade-off: JWTs remove the shared-state requirement (great for stateless, horizontally scaled services, and for cross-service/cross-domain auth), but a token **can't be revoked before it expires** — since verification doesn't consult a central store, there's no single place to "delete" a live token. Mitigations, worth naming explicitly in an interview:
- Keep expiry short (minutes) and issue a longer-lived **refresh token** to silently obtain new short-lived tokens — limits the damage window of a leaked token.
- Maintain a server-side **blocklist** of revoked token IDs for the rare "must revoke immediately" case (e.g., a compromised account) — this reintroduces a shared store for that one check, trading back some of JWT's statelessness for the ability to revoke.

| | Session-based | Token-based (JWT) |
|---|---|---|
| Where's the state? | Server-side (session store) | Client-side (inside the token) |
| Revocation | Instant — delete the record | Hard — must wait for expiry, or maintain a blocklist |
| Scaling across servers | Needs sticky sessions or shared store | Any server can verify independently (stateless) |
| Per-request cost | A lookup against the session store | Signature verification only (no I/O) |
| Good fit | Single service/app, need instant revocation | Multiple services/APIs, cross-domain, mobile clients |

### What a JWT looks like, structurally

```text
  header              payload                       signature
 (algorithm)      (claims: user id, role, exp)   (proves it wasn't tampered with)
┌──────────┐    ┌──────────────────────────┐    ┌─────────────────────┐
│eyJhbGciOi│ .  │eyJ1c2VyX2lkIjo0ODIxLCJyb│ .  │SflKxwRJSMeKKF2QT4fwp│
│Mi5In0    │    │xlIjoiYWRtaW4ifQ         │    │MeJf36POk6yJV_adQssw5c│
└──────────┘    └──────────────────────────┘    └─────────────────────┘
     base64url            base64url                  HMAC/RSA signature
   (not encrypted — decodable by anyone; never put secrets in the payload)
```

Any server holding the shared secret (HMAC-style signing) or the public key (RSA/ECDSA-style signing) can independently recompute/verify the signature over the header+payload, confirming the token was issued by a trusted authority and hasn't been altered — without ever contacting the server that originally issued it.

### A note on passwords specifically

Authentication via password requires storing something to check the password against — and that something must never be the plaintext password itself. Passwords are stored **hashed** (run through a one-way function like bcrypt or Argon2, with a per-user random **salt** mixed in so two users with the same password don't produce the same stored hash, and so precomputed "rainbow table" lookups don't work). Login then re-hashes the submitted password with the stored salt and compares hashes, never comparing plaintext. This is a detail worth having ready if an interviewer asks "how do you store credentials," even though it's rarely the focus of a system design interview (it's more of a security-review-level detail than an architecture-level one).

## OAuth2, at the mental-model level

**OAuth2** is a protocol for **delegated authorization**: it lets a user grant a third-party application limited access to their data on another service, *without* handing that third-party app their password for the other service.

The canonical example is "Login with Google" or "Allow this app to access your Google Calendar": you're redirected to Google, you log in to Google directly (the third-party app never sees your Google password), you approve a specific scope of access ("read your calendar events"), and Google's **authorization server** issues an **access token** back to the third-party app. The app then uses that access token to call Google's APIs on your behalf, limited to whatever scope you approved, and typically for a limited time.

Key actors, conceptually:
- **Resource owner**: you, the user who owns the data.
- **Client**: the third-party app requesting access.
- **Authorization server**: issues tokens after you approve access (e.g., Google's login/consent screen).
- **Resource server**: the API that actually holds the data and accepts the access token (e.g., Google Calendar's API).

You don't need to enumerate every OAuth2 grant type for a system design interview — the mental model that matters is: **authentication proves identity to the authorization server (you log in to Google), and OAuth2's job is authorization — letting an app act on your behalf with a scoped, revocable token, without ever seeing your credentials for the underlying service.**

### The OAuth2 flow, shaped as a diagram

```text
   user            third-party app          Google (auth server)      Google API (resource server)
    │                     │                         │                          │
    │  "log in with       │                         │                          │
    │   Google" click     │                         │                          │
    │────────────────────►│                         │                          │
    │                     │  redirect to Google      │                          │
    │◄──────────────────────────────────────────────│                          │
    │  logs in + approves scope, directly on Google's page (app never sees the password)
    │────────────────────────────────────────────────►                          │
    │                     │   authorization code / access token issued         │
    │                     │◄────────────────────────│                          │
    │                     │   calls API using the access token                 │
    │                     │─────────────────────────────────────────────────────►
    │                     │◄─────────────────────────────────────────────────────
    │                     │   scoped data returned                              │
```

The critical detail worth stating explicitly in an interview: the password is entered only on Google's own page, never on the third-party app — the app only ever receives a scoped, revocable token, not credentials.

## Rate limiting algorithms

Rate limiting caps how many requests a client can make in a given time window, protecting a system from abuse, runaway clients, and traffic spikes. The full worked design (where to enforce it — client, edge, or per-service; what to key it on — IP, user, API key; what to return to a throttled client) lives in **`02_Interview_Questions/02_rate_limiter.md`**. Here's the algorithm-level vocabulary you need going in.

**Fixed window counter**: divide time into fixed windows (e.g., 1-minute buckets), keep a counter per window, reject requests once the counter hits the limit, reset to zero at the window boundary. Simple, cheap (one counter per client per window), but has a real **boundary-burst problem**: a client can send the full limit of requests in the last instant of one window, then immediately send the full limit again in the first instant of the next window — e.g., a 100 req/min limit lets 100 requests at 0:59 and another 100 at 1:00, i.e. 200 requests in under 2 seconds, well beyond the intended rate.

```text
window 1 [0:00 - 1:00]         window 2 [1:00 - 2:00]
...............|████████|      |████████|...............
            100 reqs at 0:59    100 reqs at 1:00
            = 200 reqs in ~1 second, limit "respected" per window
```

**Sliding window log**: store the exact timestamp of every request per client; to check a new request, count how many stored timestamps fall within the last window (e.g., the last 60 seconds), discarding older ones. Perfectly accurate — no boundary artifact — but memory-heavy, since it stores every individual request timestamp per client rather than a single counter.

**Sliding window counter**: a practical approximation that avoids storing every timestamp. Keep fixed-window counters (like the naive approach) but, when checking a request, weight the *previous* window's count by how much of it still overlaps the trailing window — e.g., if you're 25% into the current window, count 75% of the previous window's requests plus 100% of the current window's. This smooths out the boundary-burst problem with far less memory than a full log — a good default for real systems.

**Token bucket**: a bucket holds up to `N` tokens and refills at a steady rate (e.g., 10 tokens/second); each request consumes one token, and requests are rejected when the bucket is empty. Because the bucket can hold up to `N` tokens, a client that's been idle can burst up to `N` requests instantly, then is throttled back to the steady refill rate — allows controlled burstiness rather than a perfectly flat rate, which fits real traffic patterns better than a hard cap.

```text
   refill: +1 token/100ms
        ┌─────────────┐
        │ ● ● ● ● ●   │  bucket (capacity 5)
        └─────────────┘
  request arrives → consume 1 token → allowed
  bucket empty → request rejected until next refill
```

**Leaky bucket**: incoming requests are queued and processed (leak out) at a constant, fixed rate, regardless of how bursty the incoming traffic is — like a bucket with a small hole in the bottom: water (requests) can pour in fast, but it only drains at a fixed rate, and if it pours in faster than it drains, the bucket overflows (requests get dropped). This smooths bursty traffic into a steady outflow, prioritizing a constant processing rate over allowing any burst at all — the opposite emphasis from token bucket, which explicitly allows bursts up to bucket size.

| Algorithm | Accuracy | Memory cost | Allows bursts? |
|---|---|---|---|
| Fixed window counter | Low (boundary burst) | Very low (1 counter) | Yes, unintentionally, at boundaries |
| Sliding window log | Exact | High (every timestamp) | No |
| Sliding window counter | Good approximation | Low | Slightly, smoothed |
| Token bucket | Approximate by design | Low | Yes, intentionally, up to bucket size |
| Leaky bucket | Approximate by design | Low | No — enforces constant outflow |

## Encryption basics

**Encryption at rest** protects data stored on disk (a database, a backup, an object storage bucket) — if someone gains physical or filesystem access to the storage medium, the data is unreadable without the decryption key. **Encryption in transit** protects data while it's moving over the network (client to server, service to service) — primarily via **TLS** (Transport Layer Security, the protocol behind HTTPS). These protect against different threats and you need both: at-rest encryption doesn't help if an attacker sniffs unencrypted network traffic, and in-transit encryption doesn't help if someone steals an unencrypted database backup.

**Symmetric encryption**: the same key both encrypts and decrypts. Fast, so it's used for bulk data (the actual payload of a request, an encrypted database column). The hard problem is key distribution — both parties need the same secret key, and safely getting that key to both sides over an insecure channel is non-trivial.

**Asymmetric encryption**: a key *pair* — a public key (shareable with anyone) and a private key (kept secret). Data encrypted with the public key can only be decrypted with the matching private key. Slower than symmetric encryption (more computationally expensive), so it's not used to encrypt bulk data directly — it's used to securely establish/exchange a symmetric key, which then does the actual bulk encryption.

**TLS handshake, at a high level**: the client and server use asymmetric cryptography to agree on a shared symmetric session key (this solves symmetric encryption's key-distribution problem — the symmetric key itself is exchanged over a channel secured by asymmetric crypto), and the server proves its identity via a certificate signed by a trusted certificate authority. Once that session key is established, the rest of the actual traffic is encrypted symmetrically, for speed. You don't need the full multi-step protocol for an interview — just: **asymmetric crypto bootstraps a shared secret; symmetric crypto does the heavy lifting after that**, giving you both the security of asymmetric key exchange and the speed of symmetric bulk encryption.

| | Symmetric | Asymmetric |
|---|---|---|
| Keys | One shared key | Public/private key pair |
| Speed | Fast | Slow (much more compute per byte) |
| Used for | Bulk data encryption | Key exchange, digital signatures, identity verification |
| Hard problem | Distributing the key safely | Nothing to distribute secretly (public key is public), but slower at scale |

## DDoS mitigation basics

A **DDoS (Distributed Denial of Service) attack** floods a system with traffic from many sources at once, aiming to exhaust its capacity so legitimate users can't get through. This is a brief overview — not a deep dive — of the standard layers of defense:

- **Rate limiting at the edge**: apply rate limits (see above) as early as possible in the request path — ideally before traffic even reaches your application servers — so abusive volume is dropped at the perimeter rather than consuming backend capacity.
- **CDN absorbing/caching traffic**: a CDN (Content Delivery Network) sits in front of your origin servers, geographically distributed, and can absorb and cache a large volume of traffic (especially for static/cacheable content) so it never reaches your origin at all — origin servers only see the residual traffic the CDN can't serve from cache.
- **Web Application Firewall (WAF)**: a layer that inspects incoming requests for known malicious patterns (SQL injection attempts, known bad IP ranges, suspicious request shapes) and blocks them before they reach the application — a pattern-matching filter sitting in front of your app, distinct from rate limiting (which is volume-based, not pattern-based).

## Trade-offs

| Decision | Choose this when... | Watch out for |
|---|---|---|
| Session-based auth | Single app/service, need instant revocation (e.g., banking, admin tools) | Sticky sessions or shared store needed to scale horizontally |
| JWT | Multiple services/APIs, mobile clients, cross-domain auth | Revocation before expiry is hard — mitigate with short expiry + refresh tokens |
| Token bucket rate limiting | Want to allow legitimate bursty usage (e.g., a user loading a page that fires several API calls at once) | Must size bucket capacity carefully — too large defeats the limiting purpose |
| Leaky bucket rate limiting | Want a strictly smoothed, constant outbound rate regardless of input burstiness (e.g., protecting a downstream system with a hard throughput ceiling) | Bursty-but-legitimate traffic gets queued/dropped just like abuse would |

## Interview Tips

- When asked "how do you secure this API," don't just say "add authentication" — explicitly separate authentication (who's calling) from authorization (what they can do), since interviewers listen for that distinction.
- If the design involves multiple services, default toward JWT/stateless tokens and explicitly name the revocation trade-off and its mitigation (short expiry + refresh tokens) — this shows you understand the real cost, not just the buzzword.
- For rate limiting questions, don't just name an algorithm — explain the boundary-burst problem with fixed windows concretely, since it's the detail that shows genuine understanding rather than memorized vocabulary.
- Mention both at-rest and in-transit encryption when asked "how is data protected" — candidates often mention only TLS (in-transit) and forget at-rest, or vice versa.
- Keep OAuth2 and DDoS mitigation answers conceptual and move on quickly unless the interviewer explicitly asks to go deeper — these are rarely the deep-dive focus of a system design interview.

## Quick Recall — Self-Test

**Q1: What's the one-sentence distinction between authentication and authorization?**
Authentication proves who you are (identity); authorization determines what you're allowed to do once your identity is known (permissions). Logging in is authentication; being denied access to an admin endpoint while logged in is authorization.

**Q2: Why is JWT-based auth harder to revoke than session-based auth?**
Session-based auth stores session state server-side, so revoking access is just deleting that record. A JWT is self-contained and verified via signature alone, with no central lookup — so there's no single record to delete, and the token stays valid until it naturally expires unless you add extra infrastructure like a blocklist.

**Q3: What problem does OAuth2 solve, described without naming a specific grant type?**
It lets a user grant a third-party app limited, scoped access to their data on another service, without ever sharing their password for that service with the third-party app — the authorization server authenticates the user directly and issues a scoped access token to the app.

**Q4: Explain the fixed window counter's boundary-burst problem concretely.**
Because the counter resets at fixed time boundaries, a client can send the full allowed limit right at the end of one window and the full limit again right at the start of the next window — two back-to-back bursts landing in different windows pass the per-window check even though they occurred almost simultaneously, far exceeding the intended rate.

**Q5: How does token bucket differ from leaky bucket in what it optimizes for?**
Token bucket allows controlled bursts up to the bucket's capacity, since unused tokens accumulate while idle. Leaky bucket enforces a constant outflow rate regardless of how bursty the input is, smoothing everything to a fixed processing rate rather than allowing bursts through.

**Q6: Why do you need both at-rest and in-transit encryption — isn't one enough?**
They protect against different threats: in-transit (TLS) protects data while it moves over the network from interception; at-rest protects stored data if the storage medium itself is compromised (stolen backup, unauthorized filesystem access). Having only one leaves the other attack surface open.

**Q7: In a TLS handshake, why use both asymmetric and symmetric encryption instead of just one?**
Asymmetric encryption solves the key-distribution problem (safely agreeing on a secret without a prior shared secret) but is too slow for bulk data. So it's used only to establish a shared symmetric session key, after which the actual traffic is encrypted symmetrically for speed — combining asymmetric's secure key exchange with symmetric's performance.

**Q8: Name the three standard layers of DDoS mitigation mentioned here and what each does.**
Rate limiting at the edge (drop excess volume before it reaches the app), a CDN (absorbs/caches traffic geographically distributed so it never hits origin servers), and a WAF (inspects and blocks requests matching known malicious patterns).
