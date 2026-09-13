# Design a Chat Application

## Problem Statement

"Design a chat application like WhatsApp or Facebook Messenger. Users should be
able to send 1:1 messages and group messages to each other in near real time.
Messages should not get lost if the recipient is offline, and users should be
able to see when a message was delivered and read. Assume hundreds of millions
of users, most of them on mobile devices with unreliable networks."

## Step 1: Clarify Requirements

### Functional Requirements

- Users can send and receive 1:1 text messages in near real time.
- Users can create groups (bounded size, e.g. up to a few hundred members) and
  send messages to the whole group.
- Messages are persisted so a user can fetch full conversation history,
  including messages sent while they were offline.
- A sender can see delivery state per message: **sent** (left the client),
  **delivered** (reached the recipient's device), **read** (recipient opened
  it).
- Support for media attachments (images, short video, voice notes) — out of
  scope for the deep dive here beyond "store the blob in object storage and
  send a pointer/URL in the message," which is the same pattern as
  `../01_Concepts/12_storage_systems.md`.
- Users can see basic presence (online / last seen), though this is explicitly
  a soft, best-effort feature, not a strict guarantee.

### Non-Functional Requirements

- **Low latency**: a message sent by one online user should reach another
  online user in well under a second — this is the feature users notice most.
- **Durability**: a message must never be silently dropped once the client
  has been told "sent." Losing messages is the single least acceptable
  failure mode for a chat product.
- **At-least-once delivery** with client-side deduplication is acceptable —
  exactly-once delivery across an unreliable network is not achievable
  without an idempotency mechanism on top of at-least-once (see
  `../01_Concepts/09_distributed_systems_core.md` on idempotency).
- **Ordering**: messages within a single 1:1 or group conversation should be
  displayed in a consistent order to all participants — global ordering
  across unrelated conversations is not required.
- **High availability** over strict consistency: it's better for a user to
  briefly see a slightly stale delivery status than for the whole send path
  to become unavailable — this pushes the design toward an AP-leaning system
  for message delivery infrastructure (see `../01_Concepts/08_cap_theorem_and_consistency.md`),
  while the message content itself, once written, must be durable.
- **Massive concurrency**: hundreds of millions of users with tens of millions
  online simultaneously, each holding a long-lived connection.
- **Read/write pattern**: writes (sends) and near-immediate reads (the
  recipient receiving it) are roughly 1:1 per message — this is unlike a feed
  or search system; the dominant cost here is connection fan-out and routing,
  not a skewed read amplification.

## Step 2: Back-of-Envelope Estimation

**Assumptions** (stated explicitly, WhatsApp-scale order of magnitude):

- 500 million daily active users (DAU).
- Average of 40 messages sent per user per day (mix of 1:1 and group).
- 10% of DAU is connected concurrently at peak — 50 million concurrent
  WebSocket connections.
- Average message payload (text + metadata: sender ID, conversation ID,
  timestamp, message ID) is ~200 bytes on the wire and on disk.
- Peak traffic runs at roughly 3x the daily average (evening peak).

**Message volume and QPS**

```
Total messages/day = 500,000,000 users x 40 messages/user = 20,000,000,000 (20B) messages/day

Average QPS = 20,000,000,000 / 86,400 seconds ≈ 231,500 messages/sec

Peak QPS ≈ 231,500 x 3 ≈ 695,000 messages/sec
```

This is the number of *messages sent*. Actual *deliveries* are higher because
of group fan-out (a group message to 50 members is 1 send but 50 deliveries)
— see the fan-out discussion in Step 6.

**Storage**

```
Per-message storage (payload + indexing overhead) ≈ 200 bytes

Daily storage = 20,000,000,000 x 200 bytes = 4,000,000,000,000 bytes = 4 TB/day

Yearly storage (raw) = 4 TB x 365 ≈ 1.46 PB/year

With 3x replication for durability ≈ 4.4 PB/year
```

That is a large but very manageable number for a horizontally partitioned
store (see partitioning in Step 6) — text messaging is cheap to store per
message; the real cost driver in a real product is media attachments (images,
video, voice notes), which run orders of magnitude larger per item and belong
in object storage, not the message database.

**Connection infrastructure**

```
50,000,000 concurrent connections

If one connection-server process can hold ~50,000 open WebSocket connections
(realistic for a tuned server with enough file descriptors and memory —
each idle WebSocket costs roughly tens of KB of kernel + application memory):

Connection servers needed = 50,000,000 / 50,000 = 1,000 servers
```

**Bandwidth**

```
Average: 231,500 msgs/sec x 200 bytes x 2 (one write in, one push out per
1:1 message) ≈ 92.6 MB/sec ≈ 741 Mbps average

Peak: roughly 3x ≈ 2.2 Gbps

This excludes media traffic, which in a real product dwarfs text traffic by
orders of magnitude and is served via CDN, not through the messaging
pipeline itself.
```

## Step 3: High-Level Design

The core split is between **stateful connection infrastructure** (who is
online, and which server they're attached to) and **stateless message
processing** (validate, persist, route). This separation is what makes the
whole system horizontally scalable — connection servers can be added or
removed independently of message-processing capacity.

```text
                          ┌────────────────────┐
                          │   Mobile / Web      │
                          │   Client            │
                          └─────────┬───────────┘
                                    │ persistent WebSocket
                                    ▼
                     ┌───────────────────────────────┐
                     │   Connection Gateway Cluster    │
                     │  (thousands of stateful nodes,  │
                     │   each holds ~50k connections)  │
                     └───────┬───────────────┬─────────┘
                             │               │
              register/lookup│               │ publish incoming message
                             ▼               ▼
                  ┌─────────────────┐   ┌────────────────────┐
                  │ Presence /       │   │  Message Service    │
                  │ Session Registry │   │ (stateless workers) │
                  │ (user_id ->      │   └─────────┬────────────┘
                  │  gateway node)   │             │
                  └─────────────────┘              │ persist + assign seq #
                                                     ▼
                                          ┌─────────────────────┐
                                          │  Message Store        │
                                          │  (partitioned by       │
                                          │   conversation_id)     │
                                          └───────────┬─────────┘
                                                       │ publish for fan-out
                                                       ▼
                                          ┌─────────────────────┐
                                          │  Message Queue /       │
                                          │  Delivery Router       │
                                          └───────┬─────────┬─────┘
                                                   │         │
                                    recipient online│         │recipient offline
                                                   ▼         ▼
                                  ┌────────────────────┐ ┌──────────────────┐
                                  │ Lookup recipient's   │ │ Push Notification │
                                  │ gateway node, push   │ │ Service (APNs/FCM)│
                                  │ over open connection │ └──────────────────┘
                                  └────────────────────┘
```

**Flow for a 1:1 message:**

1. Sender's client pushes the message over its already-open WebSocket to its
   connection gateway node.
2. The gateway forwards it to the stateless message service, which assigns
   a message ID and a per-conversation sequence number, then writes it
   durably to the message store.
3. The message service looks up the recipient's current gateway (via the
   presence/session registry). If the recipient is online, the message is
   routed to that specific gateway node and pushed down their open
   connection. If offline, it's queued for store-and-forward and a mobile
   push notification is triggered.
4. The sender receives an ack once the message is durably persisted (this is
   what flips the UI to "sent" — a single checkmark).

## Step 4: API Design

Most of the "API" here is WebSocket message frames rather than REST, because
the core interaction is bidirectional and low-latency. A thin REST layer
still exists for connection setup, history fetch, and anything that doesn't
need to be pushed.

**1. Establish a session (REST, once per app start / reconnect)**

```
POST /v1/connect
Request:  { "user_id": "u123", "device_id": "d456", "auth_token": "..." }
Response: { "gateway_url": "wss://gw-17.chat.example.com/socket", "session_token": "..." }
```
The client is handed a specific gateway node to connect to (often chosen by
the load balancer for locality/load, see Step 6) and opens a WebSocket to it.

**2. Send a message (WebSocket frame, client -> server)**

```json
{
  "type": "MESSAGE_SEND",
  "client_msg_id": "c-9f2e...",
  "conversation_id": "conv_789",
  "recipient_ids": ["u456"],
  "body": { "text": "Hey, running 10 mins late" },
  "sent_at_client": 1757740000123
}
```
`client_msg_id` is generated client-side and is the deduplication key (see
Step 6) — the server never trusts client timestamps for ordering.

**3. Server ack (WebSocket frame, server -> sender)**

```json
{
  "type": "MESSAGE_ACK",
  "client_msg_id": "c-9f2e...",
  "server_msg_id": "m-01H8X...",
  "conversation_id": "conv_789",
  "seq_no": 4821,
  "status": "SENT"
}
```

**4. Incoming message push (WebSocket frame, server -> recipient)**

```json
{
  "type": "MESSAGE_PUSH",
  "server_msg_id": "m-01H8X...",
  "conversation_id": "conv_789",
  "sender_id": "u123",
  "seq_no": 4821,
  "body": { "text": "Hey, running 10 mins late" },
  "server_sent_at": 1757740000456
}
```

**5. Delivery / read receipt (WebSocket frame, recipient -> server)**

```json
{
  "type": "RECEIPT",
  "server_msg_id": "m-01H8X...",
  "conversation_id": "conv_789",
  "status": "READ",
  "at": 1757740012000
}
```

**6. Fetch conversation history (REST, for initial load / pagination / catch-up after reconnect)**

```
GET /v1/conversations/{conversation_id}/messages?before_seq=4821&limit=50
Response: {
  "messages": [ { "server_msg_id": "...", "seq_no": 4820, "sender_id": "...", "body": {...}, "sent_at": ... }, ... ],
  "has_more": true
}
```
This is also exactly the endpoint used for offline catch-up: on reconnect,
the client sends the last `seq_no` it has for each conversation and the
server backfills anything newer.

## Step 5: Data Model

Three distinct storage needs, each best served by a different database type
— a good interview signal is naming this explicitly rather than putting
everything in one store.

**1. Messages — wide-column / partitioned NoSQL store (e.g. Cassandra-style),
partitioned by `conversation_id`**

```
Table: messages
Partition key: conversation_id
Clustering key: seq_no (or a time-sortable message ID, ascending)

conversation_id | seq_no | message_id | sender_id | body            | sent_at
conv_789        | 4821   | m-01H8X... | u123      | {text: "..."}   | 1757740000456
conv_789        | 4820   | m-01H7Y... | u456      | {text: "..."}   | 1757739988112
```
Chosen because the dominant query is "give me messages in this conversation,
in order, recent-first" — a partition-per-conversation with a sorted
clustering key answers that with a single-partition range scan, which is the
cheapest possible query shape in a wide-column store. A relational DB could
work at moderate scale too (with an index on `(conversation_id, seq_no)`),
but a wide-column store's native partitioning matches this access pattern
directly and scales writes horizontally without manual sharding logic.

**2. Presence / session registry — in-memory key-value store (Redis)**

```
Key: presence:{user_id}          Value: { gateway_node: "gw-17", device_id: "d456", connected_at: ... }
Key: gateway:{gateway_node}:load  Value: current connection count (for load-balancer decisions)
```
Chosen because this data is small, accessed on the hot path of every message
route, and inherently ephemeral (it's meaningless the instant a connection
drops) — a perfect fit for an in-memory KV store rather than a durable
database. See `../01_Concepts/05_caching.md` for why Redis specifically fits
this (TTL support, atomic ops, pub/sub for invalidation).

**3. Conversation & delivery metadata — relational store (Postgres/MySQL)**

```
Table: conversations (conversation_id PK, type [1:1|group], created_at)
Table: conversation_members (conversation_id, user_id, joined_at, role)
Table: message_status (message_id, user_id, status [SENT|DELIVERED|READ], updated_at)
```
Chosen because group membership and per-recipient status are relational,
low-volume-per-row, and benefit from transactional guarantees (e.g. adding a
member to a group shouldn't race with a message being fanned out to a
half-updated member list).

**4. Media attachments — object storage**

Actual image/video/audio bytes live in object storage (S3-style), with the
message body carrying only a URL/object key — same pattern as
`../01_Concepts/12_storage_systems.md`.

## Step 6: Deep Dive

### 6.1 Connection Management and Message Routing at Scale

Every online user holds one persistent WebSocket connection to exactly one
connection-gateway server. At 50 million concurrent connections and ~50,000
connections per gateway node (Step 2), that's roughly 1,000 gateway
instances — no single server can hold all connections, so the fleet is
horizontally partitioned by *which users happen to be connected to it*, not
by any property of the data.

This creates the routing problem that defines this system: when user A sends
a message to user B, the message-processing layer has no inherent way to
know which of the 1,000 gateway nodes B is currently attached to. The fix is
a **presence/session registry** (Redis, Step 5) that maps `user_id ->
gateway_node_id`, written by the gateway the instant a user connects and
deleted (or TTL-expired) the instant they disconnect. Routing a message then
becomes: look up B's current gateway in the registry, forward the message to
that specific gateway instance over an internal RPC/queue, and that gateway
pushes it down B's open socket. If B is connected to multiple devices
(phone + web), the registry stores multiple entries per user and the message
is pushed to all of them.

Two operational details matter here: (1) the registry entry must be cleaned
up reliably on disconnect — a stale entry means messages get routed to a
gateway that no longer holds that connection, so gateways use a heartbeat +
TTL (e.g., refresh every 30s, expire after 60s) rather than relying purely on
an explicit disconnect event, since networks drop connections without a
clean close. (2) load balancing new connections across the 1,000 gateway
nodes should be aware of current load per node (from the same registry),
not purely round-robin, to avoid hot gateways.

### 6.2 Delivery Guarantees and Ordering

The network between a mobile client and the server is inherently unreliable
— packets get lost, connections drop mid-send, clients retry. The practical
guarantee this system offers is **at-least-once delivery**: if there's any
doubt whether a send succeeded, the client retries, which means the same
message can legitimately reach the server (or the recipient) more than once.
Exactly-once delivery is not achievable end-to-end without extra machinery,
so instead of trying to prevent duplicates, the design makes duplicates
harmless: every message carries a client-generated `client_msg_id`, and the
server (and the recipient's client) deduplicate on that ID — a retried send
that already succeeded is recognized and simply re-acknowledged rather than
stored/delivered twice. This is the same idempotency-key pattern covered
generally in `../01_Concepts/09_distributed_systems_core.md`.

Ordering is a related but distinct problem. It is tempting to order messages
by wall-clock timestamp, but clocks on different application servers (and
especially different mobile devices) are not perfectly synchronized — clock
skew of tens to hundreds of milliseconds is normal, and two messages sent
milliseconds apart could be timestamped out of order across machines. The
fix is a **monotonically increasing sequence number scoped to each
conversation**, assigned by the server (not the client) at write time — the
message store's per-conversation partition (Step 5) makes this cheap, since
sequence-number assignment can be a single atomic increment scoped to that
partition. Clients then order and display messages by `seq_no`, never by
timestamp; timestamps are kept only for display ("2 minutes ago") and are
not load-bearing for ordering.

### 6.3 Offline Delivery: Store-and-Forward

Not every recipient is online when a message arrives — the presence
registry lookup in 6.1 may simply come back empty. This is the normal case,
not an edge case, given that only ~10% of DAU is online at any moment (Step
2). The design handles it with a **store-and-forward** model: the message is
always durably persisted to the message store first (this is what the
sender's "sent" ack depends on — persistence, not delivery), completely
independent of whether the recipient is currently reachable. Delivery to a
connected recipient is best described as an *optimization* on top of
persistence, not a requirement for the write to succeed.

If the recipient is offline, the system additionally triggers a **mobile
push notification** (via APNs/FCM) to wake the device or surface a banner,
but the push notification itself carries no guarantee — pushes can be
dropped, delayed, or rate-limited by the OS. The actual, reliable delivery
mechanism is that when the recipient's client next connects, it performs the
catch-up flow from Step 4 (`GET /messages?before_seq=<last_known_seq>`),
which the per-conversation sequence number makes trivial and correct: the
client simply asks for everything newer than the last `seq_no` it has per
conversation, and the store answers with a straightforward range scan. This
is why persistence-first, push-as-optimization is the right mental model:
correctness never depends on the push notification arriving.

### 6.4 Group Chat Fan-out and Read Receipts

A message sent to a group of N members must be delivered to N recipients —
structurally the same fan-out problem as the "celebrity problem" discussed
for feeds and Twitter (see `10_twitter_x.md` and `08_news_feed.md`), just at
a much smaller, bounded scale, since chat groups are typically capped
(hundreds, not millions, of members). The message-processing layer writes
the message once to the conversation's partition in the message store, then
fans out N delivery attempts — one presence-registry lookup and one push per
online member, one push-notification trigger per offline member. Because N
is bounded and small relative to a viral social-feed fan-out, this can be
done synchronously as part of message processing rather than needing an
asynchronous background fan-out job; it only becomes a real problem at
group sizes the product intentionally caps (this is part of *why* chat
products cap group size, unlike a social graph's unbounded follower count).

Delivery status (sent/delivered/read) is naturally **per-recipient, per-
message** state — in a group of 50, a message has 50 independent
delivered/read states, not one. Modeling this as a mutation of the message
row itself would mean a single message row needs 50 mutable sub-fields and
every receipt update would contend on that same row. Instead, receipts are
modeled as a **separate, lightweight, append-style update** (`message_status`
table in Step 5, or an equivalent write into a fast KV/queue-backed store) —
one row per (message, recipient), written independently and cheaply, with no
contention with the original message write or with other recipients'
receipts. The sender's UI aggregates these (e.g., "delivered" once all
recipients report delivered, or per-recipient detail in a group's "read by"
list) by reading this side table, not by touching the message itself.

## Step 7: Bottlenecks & Trade-offs

- **The presence registry is a single hot dependency.** Every message send
  requires a lookup against it, at up to ~700k QPS peak (Step 2) just for
  1:1 sends, more with group fan-out. It must be horizontally sharded (by
  `user_id` hash) and highly available; if it becomes unavailable, the
  system can still *persist* messages (durability is preserved) but loses
  the ability to route live pushes, degrading gracefully to "everyone looks
  offline" rather than losing data — a deliberate trade-off of graceful
  degradation over an all-or-nothing failure.
- **Gateway nodes are stateful, which complicates deployment.** Restarting a
  gateway for a deploy drops every connection it holds (tens of thousands at
  once), forcing simultaneous reconnects that spike load on the connection
  layer and the registry. Rolling deploys with connection draining (stop
  accepting new connections, wait for existing ones to naturally cycle, or
  actively migrate them) are necessary rather than a naive rolling restart.
- **Group fan-out cost grows with group size**, and while product-level caps
  keep this bounded, a very active large group (hundreds of members, high
  message frequency) can still create a local hot spot of fan-out work
  concentrated on one conversation's partition — this is the same
  hot-partition problem covered generally in
  `../01_Concepts/07_database_scaling.md`.
- **At-least-once delivery pushes deduplication work to every client.**
  This is a deliberate trade-off: building a genuinely exactly-once pipeline
  end-to-end (distributed transactions across gateway, store, and push
  service) would add substantial latency and complexity for a guarantee that
  a simple client-side `client_msg_id` dedup achieves almost as well with
  far less cost.
- **Storage grows unboundedly with message history.** Text is cheap (Step
  2), but a real product also carries years of history per user; older,
  rarely-accessed conversations are natural candidates for tiering to
  cheaper, colder storage, trading a small amount of read latency on old
  history for a large reduction in storage cost.

## Follow-up Questions an Interviewer Might Ask

**How would you support end-to-end encryption?**
Keys are generated and held only on client devices (e.g., via the Signal
Protocol's double ratchet); the server stores and routes only ciphertext it
cannot read. This changes very little about the architecture above — routing,
presence, and fan-out all operate on opaque payloads — but it does mean
server-side features that require reading message content (search across
message history, spam detection) either can't work server-side at all or
must be reimplemented as client-side computation.

**How do you handle a user with many devices (phone, tablet, web) staying in sync?**
The presence registry stores multiple `(user_id, device_id) -> gateway`
entries instead of one, and both the fan-out on send and the catch-up-on-
reconnect flow operate per-device rather than per-user — each device tracks
its own last-seen `seq_no` per conversation, since one device might be
offline while another stays connected.

**What happens if a gateway node crashes with connections still open?**
Every client attached to it gets a dropped socket and reconnects (with
backoff) through the load balancer to a healthy gateway; the presence
registry entries for that node should be actively invalidated (or expire via
TTL quickly) so routing doesn't keep sending messages to a dead node in the
meantime. No messages are lost because persistence (Step 6.3) never
depended on that gateway staying up.

**How would you add "typing..." indicators without overloading the system?**
Typing indicators are treated as fundamentally different from messages: they
are ephemeral, lossy-tolerant, and never persisted — sent as a lightweight,
unacknowledged WebSocket frame, often debounced/throttled client-side (e.g.,
at most one "typing" event per few seconds), and simply dropped if the
recipient is offline rather than queued for later delivery the way a real
message would be.

**How would you scale search across a user's message history?**
This is a separate derived system, not part of the hot send/receive path —
messages are asynchronously indexed into a search system as they're written
(e.g., via a queue, see `../01_Concepts/10_message_queues_and_streaming.md`),
using an inverted index as described in
`../01_Concepts/13_search_and_indexing.md`, accepting the same near-real-time
indexing lag that any search system has.

**How would you rate-limit abusive senders (spam) without slowing down normal users?**
A per-user token-bucket rate limiter sits in the message-processing path
before persistence, tracked in the same kind of fast in-memory store used for
presence (Redis counters with TTL) — this keeps the check cheap (a single
atomic increment) and off the critical path for the vast majority of users
who never come close to the limit.
