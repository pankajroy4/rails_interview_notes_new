# Design a Notification System

## Problem Statement

"Design a notification system that sends notifications to users across multiple channels — push notifications, SMS, and email — triggered by backend events like 'your order has shipped' or 'someone commented on your post.' The system needs to work at large scale, handle sudden bursts (a flash sale notifying millions of users at once), respect each user's channel preferences and quiet hours, and gracefully handle the fact that the third-party providers actually delivering push/SMS/email each impose their own rate limits and can fail independently." This is the shared notification infrastructure that almost every consumer product eventually needs, decoupled from any single feature that triggers a notification.

## Step 1: Clarify Requirements

### Functional Requirements

- Internal services can trigger a notification by publishing an event (e.g., `order.shipped`, `comment.created`) or calling a direct "send notification" API for one-off/scheduled sends.
- Support at least three channels: push (iOS/Android), SMS, and email — a single logical notification may fan out to multiple channels for the same user.
- Support templated, personalized content per channel (a push notification is short; an email has a subject, body, and layout).
- Respect per-user, per-channel, per-category preferences (e.g., a user opts out of marketing emails but keeps order-status push notifications) and quiet hours (don't push at 3 AM in the user's local timezone).
- Guarantee a retry after a transient failure doesn't result in the user seeing the same notification twice (idempotency).
- Expose delivery status (queued, sent, delivered, failed, opened where the channel supports it) for observability and debugging.
- Support scheduled/delayed sends, not just immediate ones.

### Non-Functional Requirements

- **Scale**: tens of millions of notifications per day, with highly bursty traffic — a single triggering event (flash sale, major outage notice) can spike volume by 10x within minutes.
- **Latency**: push should feel near-real-time (delivered within seconds of the triggering event); email and SMS can tolerate slightly more delay (seconds to low minutes) without being considered broken.
- **Delivery guarantee**: at-least-once, not exactly-once — the system must never silently drop a notification due to a transient failure, but a rare duplicate (mitigated by idempotency) is an acceptable trade-off over the cost of guaranteeing exactly-once (Step 6).
- **Availability of the ingestion path**: accepting a notification request from an internal service must be highly available and fast — the actual channel delivery can be decoupled and queued, but the "did my event get accepted" answer can't be a bottleneck for the calling service.
- **Respect for third-party constraints**: each provider (APNs/FCM, an SMS gateway like Twilio, an email service provider) enforces its own rate limits — the system must never exceed them, since doing so risks the provider throttling or banning the account entirely.
- **Compliance**: unsubscribe/opt-out for email (CAN-SPAM) and SMS (TCPA) must be honored reliably — this is a legal requirement, not just a UX nicety.

## Step 2: Back-of-Envelope Estimation

**Assumptions**:
- 50 million users, averaging 4 notifications/user/day across all channels combined.
- Channel split: 60% push, 25% email, 15% SMS (push is cheapest and most used for transactional updates; SMS is reserved for higher-priority/lower-volume cases due to cost).
- Average notification record size: ~1 KB (recipient, channel, template ID, rendered payload, status, timestamps).
- Retention: 90 days of notification history for support/debugging/analytics.

**Total volume**

```
50,000,000 users × 4 notifications/day = 200,000,000 notifications/day
```

**QPS**

```
Average: 200,000,000 / 86,400 sec ≈ 2,315 notifications/sec
Peak (10x burst, e.g. a major product event): 2,315 × 10 ≈ 23,150/sec
```

**Per-channel breakdown (average / peak)**

```
Push:  200M × 60% = 120M/day → 1,389/sec avg → ~13,900/sec peak
Email: 200M × 25% =  50M/day →   579/sec avg →  ~5,800/sec peak
SMS:   200M × 15% =  30M/day →   347/sec avg →  ~3,500/sec peak
```

This split matters concretely: SMS providers commonly rate-limit a single sender account/number to on the order of 100-200 messages/sec. A peak of 3,500/sec for SMS means the system needs **~20-35 parallel sender identities/number pools** just to stay under provider limits — this is a hard external constraint the design must plan around (Step 6), not something more application-server capacity can fix.

**Storage**

```
200,000,000 notifications/day × 1 KB = 200,000,000 KB = 200,000 MB ≈ 200 GB/day
Over 90 days retention: 200 GB × 90 ≈ 18 TB
```

18 TB is squarely in the range of a horizontally-partitioned NoSQL store, not a single relational instance.

**Queue throughput check**

Peak ingestion of 23,150 events/sec needs to be absorbed by the pub/sub/queueing layer (Step 3). A modern distributed log (Kafka-class) handles hundreds of thousands of messages/sec per cluster on modest hardware, so this peak is well within a single reasonably-sized cluster's capacity — the bottleneck in this system is not the queue, it's the downstream third-party providers' rate limits, as the SMS math above shows.

**Preference-check load**

Every send checks the user's preferences before dispatching — at 23,150 notifications/sec peak, that's 23,150 preference lookups/sec. If each lookup were a cold database read, this alone would meaningfully load a relational store; this is the concrete reason preference data needs to be cache-backed on the hot path (Step 5/6), not queried fresh from a relational database on every send.

**Idempotency table load and sizing**

Every ingested request also does one Redis check-and-set against the idempotency dedup table (Step 6). At 23,150/sec peak, and assuming a 24-hour TTL on dedup keys (long enough to cover realistic upstream retry windows):

```
Resident dedup keys ≈ average ingestion rate × TTL window
                     ≈ 2,315/sec × 86,400 sec ≈ 200,000,000 keys resident at once
```

At roughly 80 bytes per key (a UUID-length string key plus a short `notification_id` value and Redis's own per-key overhead):

```
200,000,000 × 80 bytes = 16,000,000,000 bytes = 16 GB
```

A modest, single-digit-node Redis deployment easily holds this — small relative to the 400 GB working sets seen in cache-heavy systems, because the dedup table only needs to remember recent activity, not the full notification history (that's what the 18 TB notification store, computed next, is for).

## Step 3: High-Level Design

```text
+------------------+       +---------------------+
| Internal Services |------>|  Notification API    |
| (order, social,   |       |  (ingest + validate + |
|  billing, etc.)    |       |   idempotency check) |
+------------------+       +----------+-----------+
                                       |
                                       v
                           +-----------------------+
                           |  Preference Service    |  (cached, hot-path check)
                           |  (opt-outs, quiet hrs) |
                           +-----------+-----------+
                                       |
                                       v
                           +-----------------------+
                           |  Event Bus / Pub-Sub    |  (Kafka-style, one topic
                           |  (fan-out trigger)      |   per event type)
                           +-----------+-----------+
                     +-----------------+-----------------+
                     |                 |                 |
                     v                 v                 v
           +------------------+ +------------------+ +------------------+
           |  Push Worker Pool | |  SMS Worker Pool  | |  Email Worker    |
           |  (rate-limited,   | |  (rate-limited,   | |  Pool (rate-     |
           |   retries, DLQ)   | |   retries, DLQ)   | |  limited, DLQ)   |
           +--------+---------+ +--------+---------+ +--------+---------+
                    |                    |                    |
                    v                    v                    v
              +----------+         +----------+         +----------+
              | APNs/FCM |         |  Twilio  |         |   ESP    |
              |          |         | (SMS gw) |         | (email)  |
              +----------+         +----------+         +----------+
                    |                    |                    |
                    +--------------------+--------------------+
                                         |
                                         v
                           +-----------------------+
                           |  Delivery Status Store  |
                           |  (status, retries,      |
                           |   provider callbacks)   |
                           +-----------------------+
```

**Flow**: an internal service either publishes a domain event (`order.shipped`) that the notification system subscribes to, or calls the Notification API directly for a one-off send. The API validates the request, checks an idempotency key (Step 6) to reject duplicates from upstream retries, and checks the preference service before doing anything else. If the user allows the notification on at least one channel, the event is published onto a pub/sub bus, fanned out per-channel into separate topics. Each channel has its own dedicated worker pool that pulls from its topic, applies that channel's specific rate limiting and retry logic, calls the relevant third-party provider, and records the outcome. Provider delivery-status webhooks (e.g., Twilio's delivery receipts, SendGrid's event webhook) feed back into the status store asynchronously.

**Key components**:
- **Notification API**: ingestion, validation, idempotency check — the fast, highly-available front door.
- **Preference Service**: the hot-path gate that decides whether/how to notify a given user; backed by a cache for speed (Step 6).
- **Event Bus**: decouples ingestion from delivery — this is what lets a 10x burst be absorbed without the ingestion path itself falling over (see `10_message_queues_and_streaming.md`).
- **Per-channel worker pools**: isolate each channel's very different failure modes, rate limits, and retry semantics from each other — an SMS provider outage shouldn't back up push delivery.
- **Delivery Status Store**: durable record of what was sent, to whom, and what happened.

**Walking through one notification end to end**: (1) the order service publishes `order.shipped` for order `o_789`, including an `idempotency_key` derived from the order ID. (2) The Notification API checks the idempotency table — first time seen, so it proceeds — validates the request, and asks the Preference Service whether user `u_123` allows `order_updates` on push and email (assume yes to both, and that it isn't currently within their quiet hours). (3) The event is published to the internal event bus, fanned into the `push-notifications` and `email-notifications` topics. (4) The push worker pool picks up the message, checks its rate limiter (well under APNs limits for this volume), renders the templated payload, and calls FCM/APNs; the email worker pool does the same against the ESP in parallel, independently. (5) Each worker writes the outcome (`sent`, with a provider message ID) to the Delivery Status Store. (6) Minutes later, the push provider's delivery webhook fires, updating the record from `sent` to `delivered`. If the order service's original call had timed out and been retried with the *same* `idempotency_key`, step (2) would have short-circuited immediately, returning the already-assigned `notification_id` without re-publishing anything — no duplicate push or email would be sent.

## Step 4: API Design

**Send a notification**
```
POST /notifications
{
  "user_id": "u_123",
  "event_type": "order.shipped",
  "template_id": "order_shipped_v2",
  "data": { "order_id": "o_789", "tracking_url": "https://..." },
  "idempotency_key": "order-shipped-o_789"
}
→ 202 Accepted
{ "notification_id": "n_abc123", "status": "queued" }
```

**Check delivery status**
```
GET /notifications/{id}/status
→ 200 OK
{
  "notification_id": "n_abc123",
  "channels": {
    "push": { "status": "delivered", "sent_at": "2026-09-13T10:00:01Z" },
    "email": { "status": "sent", "sent_at": "2026-09-13T10:00:02Z" }
  }
}
```

**Update user preferences**
```
PUT /users/{id}/preferences
{
  "channel": "email",
  "category": "promotions",
  "enabled": false
}
→ 200 OK
```

**Read user preferences**
```
GET /users/{id}/preferences
→ 200 OK
{
  "push": { "order_updates": true, "promotions": true },
  "email": { "order_updates": true, "promotions": false },
  "sms": { "order_updates": true, "promotions": false },
  "quiet_hours": { "start": "22:00", "end": "08:00", "timezone": "America/New_York" }
}
```

**Inbound provider delivery-status webhook**
```
POST /webhooks/delivery-status/{provider}
{ "provider_message_id": "SM123...", "status": "delivered", "timestamp": "..." }
→ 200 OK
```

**Internal preference check RPC** (called by workers before every send, hits the preference cache, not this HTTP path)
```
PreferenceService.IsAllowed(user_id, channel, category) → { allowed: bool, quiet_hours_active: bool }
```

## Step 5: Data Model

**Notification record** — NoSQL document/wide-column store (e.g., DynamoDB/Cassandra), partition key = `notification_id` (or `user_id` + time bucket for efficient per-user history queries):

| Field | Notes |
|---|---|
| `notification_id` (PK) | generated at ingestion |
| `user_id` | secondary index for "all notifications for user X" |
| `event_type` | e.g. `order.shipped` |
| `channels` | map of channel → {status, attempts, sent_at, provider_message_id} |
| `idempotency_key` | unique index — the dedup mechanism (Step 6) |
| `created_at` | |
| `payload` | rendered/template-resolved content, or a reference to it |

NoSQL fits because writes are extremely high-volume (Step 2: 200M+/day) and access is almost always by exact `notification_id` or `user_id`, with no need for relational joins — a wide-column/document store scales horizontally for this write volume far more cheaply than a relational database would.

**User preferences** — a smaller, read-heavy dataset accessed on the hot path of *every* send (Step 2: 23,150 lookups/sec at peak). Stored durably in a simple relational table (it's small, structured, and benefits from straightforward schema/constraints) but always read through a cache (Redis) in front of it, since a cold read on every single notification send would make the preference check the system's actual bottleneck:

| Field | Notes |
|---|---|
| `user_id` | |
| `channel` | push / sms / email |
| `category` | order_updates / promotions / security / ... |
| `enabled` | bool |
| `quiet_hours_start` / `quiet_hours_end` / `timezone` | |

**Idempotency dedup table** — Redis, key = `idempotency_key`, value = `notification_id`, short TTL (long enough to cover realistic retry windows, e.g. 24 hours) — an O(1) check-and-set on every ingestion request (Step 6), deliberately kept out of the primary notification store because this needs to be fast and short-lived, not durable long-term history.

**Device token store** — `user_id → [device tokens]` for push delivery, a simple KV/relational table, refreshed whenever a client app registers/re-registers a token (tokens rotate periodically on the OS side).

**Dead-letter queue** — not a database table but a queue construct (a dedicated Kafka topic or SQS DLQ) holding notifications that exhausted their retry budget, covered in Step 6.

**Storage choice justification, summarized**:

| Component | Storage type | Why |
|---|---|---|
| Notification records | Wide-column/document NoSQL | Very high write volume (200M+/day), simple key-based access, no joins needed |
| User preferences | SQL, read through a Redis cache | Small, structured, benefits from schema/constraints; cache absorbs hot-path read volume |
| Idempotency dedup | Redis (KV with TTL) | Needs O(1) check-and-set at ingestion rate, short-lived by design |
| Device tokens | KV/relational | Simple `user_id → tokens` lookup, moderate write rate on token rotation |
| Dead-letter queue | Message queue (Kafka topic/SQS DLQ) | Not a lookup structure — a durable backlog awaiting reprocessing or inspection |

## Step 6: Deep Dive

### Fan-Out via Pub/Sub and Multi-Channel Worker Pools

The core architectural decision is publishing each notification-worthy event **once**, onto a pub/sub bus, rather than having the triggering service (e.g., the order service) call each channel's delivery logic directly. This is the same pub/sub fan-out pattern described generally in `10_message_queues_and_streaming.md`, applied here specifically to decouple "something happened" from "how many ways do we tell the user about it."

Concretely: the order service publishes a single `order.shipped` event and moves on — it has no idea, and shouldn't need to know, whether that translates into a push notification, an email, both, or neither (that's the preference service's job, checked downstream). The notification system's own internal fan-out then splits that one event into per-channel messages on separate topics (`push-notifications`, `sms-notifications`, `email-notifications`), each consumed by its own dedicated worker pool.

**Why separate worker pools per channel, not one generic "send notification" worker**: each channel has a genuinely different failure and rate-limit profile —
- **Push workers** call APNs/FCM, which have their own token-based delivery model, no meaningful per-message cost, and failures that are mostly about invalid/expired device tokens (which should be cleaned up from the device token store, not endlessly retried).
- **SMS workers** call a gateway like Twilio, which has a real per-message cost and the tightest sender-account rate limits (Step 2's ~100-200/sec/number constraint) — SMS worker pools need their own token-bucket rate limiter tuned to the provider's actual limits, independent of push or email throughput.
- **Email workers** call an ESP (SendGrid, SES), with different failure modes again (bounces, spam-complaint feedback loops that must feed back into suppression lists).

Isolating these into separate pools means an SMS provider outage or rate-limit exhaustion backs up only the SMS topic — push and email keep flowing normally. A single shared worker pool handling all three channels would couple their failure domains together for no benefit.

**Channel comparison, summarized**:

| Channel | Provider example | Typical rate-limit pressure | Dominant failure mode | Retry/cleanup action |
|---|---|---|---|---|
| Push | APNs / FCM | Low (token-based, near-free per send) | Expired/invalid device token | Remove stale token from device store, don't retry |
| SMS | Twilio / similar gateway | High (~100-200/sec per sender number) | Provider throttling, invalid number | Back off and queue; flag invalid numbers, don't retry |
| Email | SendGrid / SES | Moderate (provider-defined sending reputation limits) | Hard bounce, spam complaint | Suppress future sends to that address, feed into suppression list |

### Idempotency and Deduplication

Because the ingestion path and every worker pool are built around retries (Step 6, next section), the same logical notification can genuinely be processed more than once — a calling service retries after a timeout without knowing whether the first call succeeded, or a worker crashes after calling the provider but before recording success and re-processes the message on restart. Without a dedup mechanism, this means a user could receive the same "your order shipped" push twice, which is a real, visible product bug even though the underlying infrastructure behaved "correctly" by retrying.

The mechanism (consistent with the idempotency-key pattern in `09_distributed_systems_core.md`) is: the **caller** (the triggering internal service) supplies an `idempotency_key` that's stable across retries of the same logical event — typically derived from the event itself (e.g., `"order-shipped-" + order_id`, which is naturally the same value no matter how many times the order service retries the call). The Notification API checks this key against the Redis dedup table (Step 5) before doing anything else: if the key has been seen, it returns the existing `notification_id` and status without re-publishing the event at all — this stops the duplicate at the very first hop, before it ever reaches a worker or a third-party provider, which is both cheaper and simpler than trying to deduplicate later in the pipeline. Workers additionally track `provider_message_id`s where the provider itself supports idempotent send (some SMS/email APIs accept a client-supplied idempotency token), giving defense in depth against a worker-level retry specifically.

### User Preferences, Opt-Outs, and Quiet Hours

Every send passes through the preference check **before** anything is published to a channel topic — not after, and not at the worker level — because rejecting a disallowed notification as early as possible avoids wasted downstream work and, more importantly, avoids ever calling a third-party provider for a user who opted out (which is the actual compliance requirement, not just an efficiency concern).

The check evaluates, in order: **channel-level opt-out** (has this user disabled push entirely?), **category-level opt-out** (has this user disabled "promotions" specifically, while still allowing "order updates" on the same channel?), and **quiet hours** (is it currently within the user's configured do-not-disturb window, in *their* local timezone, computed from their stored timezone rather than the server's)? A notification blocked by quiet hours isn't simply dropped — for non-time-sensitive categories it's typically deferred and re-evaluated after the quiet-hours window ends, while for genuinely time-sensitive categories (security alerts, fraud warnings) quiet hours are deliberately not applied at all, which is itself a product/policy decision the preference schema needs to support (a "quiet-hours-exempt" flag per category).

**Unsubscribe/opt-out compliance** is not optional for email and SMS specifically — every email must include a functioning unsubscribe link, and every SMS a "reply STOP to opt out" mechanism, both of which must write back into the same preference store the rest of the system reads, so an opt-out taken directly through the channel (clicking unsubscribe in an email) is immediately respected on the very next send through any channel, not just email.

Because this check runs on every single send at peak volume (Step 2: 23,150 lookups/sec), the preference data is always read through the Redis cache in front of the relational preference table (Step 5) — a cache-aside pattern (`05_caching.md`) where the cache is invalidated the moment a user updates a preference, so opt-outs take effect immediately rather than waiting out a TTL.

### Handling Third-Party Failures: Rate Limits, Retries, DLQ, and At-Least-Once Delivery

Each worker pool owns a **rate limiter tuned to its specific provider's documented limits** (e.g., a token-bucket limiter capping SMS sends to just under the provider's per-account ceiling) — this is enforced proactively, not reactively, because *exceeding* a provider's rate limit risks the provider throttling or suspending the account entirely, which would take down the entire channel for all users, not just slow down the offending burst. When the queue of pending sends for a channel exceeds what the rate limiter allows to go out immediately, messages simply wait in the topic rather than being dropped — this is exactly why the event bus (Step 3) sits between ingestion and delivery: it absorbs bursts (Step 2's 10x flash-sale scenario) as backlog instead of forcing synchronous, immediately-rate-limited delivery at the ingestion API, which would otherwise make the *caller* (the order service, say) wait on or fail due to a downstream provider's limits.

**Retries**: a failed provider call (timeout, 5xx, transient network error) is retried with exponential backoff and jitter, up to a bounded number of attempts. Distinguishing **retryable** failures (timeouts, 5xx, provider-side rate-limit responses) from **non-retryable** ones (invalid phone number, permanently expired device token, hard email bounce) matters — retrying a non-retryable failure just wastes budget and delays the inevitable, and for some non-retryable push/SMS failures the correct action is actually cleaning up the stale token/number from the device store so future sends don't repeat the same failure.

**Dead-letter queue**: a notification that exhausts its retry budget (still failing after the maximum backoff attempts) is moved to a per-channel DLQ rather than being silently discarded — this preserves it for manual inspection, alerting (a spike in DLQ volume signals a provider outage or a systemic problem worth paging on), and potential reprocessing once the underlying issue (a provider outage, a bad template) is fixed.

**At-least-once is the realistic, deliberately chosen target, not a compromise settled for by accident**: guaranteeing true exactly-once delivery across a chain that includes an unreliable network, a queue, a worker process, and a third-party provider that itself might succeed but fail to acknowledge, is either impossible or requires distributed-transaction-style coordination with every provider in the loop — which no third-party SMS/push/email provider supports. At-least-once, paired with the idempotency mechanism above, gets the practically achievable equivalent: duplicates are made *rare* (only occurring on genuine failure-and-retry edge cases) and, more importantly, *safe* (a duplicate that does slip through the idempotency key is still just a duplicate send of already-approved content, never a double-charge or a double-shipped order) — the burden of correctness is shifted from "never send twice" (unachievable) to "sending twice is harmless" (achievable and sufficient).

## Step 7: Bottlenecks & Trade-offs

- **Third-party provider rate limits are the real ceiling, not internal infrastructure.** Step 2's SMS math (needing 20-35 parallel number pools to hit peak throughput within a single provider's per-account limits) shows the bottleneck is external and commercial (how many sender identities/accounts are provisioned with the provider) rather than something more application servers can fix.
- **The preference check is a mandatory hot-path dependency for every single send** — if the preference cache goes cold or the cache layer itself degrades, the system faces a choice between failing open (risk sending to opted-out users — a compliance violation) or failing closed (block all sends until preferences are available again — an availability hit). Most real systems fail closed for compliance-sensitive categories (marketing) and fail open only for critical/safety notifications, which itself has to be an explicit, reviewed policy decision, not a default.
- **A single triggering event fanning out to millions of users at once (Step 2's flash-sale scenario) must never be processed synchronously** — the event bus's whole job is turning that spike into queue backlog that worker pools drain at a sustainable, provider-limit-respecting rate, trading immediate delivery for sustained, non-throttled delivery.
- **SMS cost** is a real constraint most other channels don't share — at meaningful scale, indiscriminate SMS usage is a significant recurring cost, which is why product policy typically reserves SMS for high-value, lower-volume categories (security codes, critical alerts) rather than general-purpose notifications.
- **Idempotency window is bounded, not infinite** — the Redis dedup table's TTL (Step 5) means a retry arriving *after* that window has expired won't be recognized as a duplicate; the TTL has to be set generously relative to realistic caller retry behavior, and this is a deliberate, tunable trade-off between dedup-table memory cost and duplicate-prevention coverage.
- **DLQ volume is an operational signal, but only if someone's watching it** — a DLQ that silently accumulates without alerting defeats its own purpose; the trade-off of choosing to hold failed messages instead of dropping them only pays off if there's a real operational process to drain and act on it.

**Bottleneck-to-mitigation summary**:

| Bottleneck | Mitigation | Cost accepted |
|---|---|---|
| Provider rate limits (esp. SMS) | Per-channel token-bucket limiter, multiple sender identities/number pools | Provisioning/commercial overhead with providers |
| Preference check on every send | Cache-aside preference lookups (Redis in front of SQL) | Small staleness window between a preference update and cache invalidation |
| Traffic burst (flash sale, 10x spike) | Pub/sub buffering between ingestion and delivery | Delivery delay during the burst instead of dropped/failed sends |
| Retry-induced duplicates | Idempotency key checked at ingestion | Small dedup-table memory cost, bounded TTL window |
| Repeatedly failing sends | Dead-letter queue instead of infinite retry or silent drop | Requires an operational process to monitor and drain the DLQ |

## Follow-up Questions an Interviewer Might Ask

**How would you prevent notification fatigue — a user getting bombarded because multiple triggering events fire in a short window?**
Add a per-user, per-category rate cap (e.g., at most one "someone liked your post" push per 30 minutes, batching subsequent likes into a single digest notification) enforced at the preference/fan-out stage before publishing to a channel topic — this is a product-level throttle layered on top of, not a replacement for, the provider-level rate limiting in Step 6.

**How would you build an in-app notification center (a bell icon with unread count) alongside push/SMS/email?**
Treat "in-app" as a fourth channel with its own worker pool that writes into a per-user notification-history store instead of calling an external provider, and maintain an unread counter (likely in a fast KV store like Redis, incremented on write and decremented/reset on read) — the fan-out and preference-check architecture is otherwise unchanged, since this is just another delivery target for the same upstream events.

**How would you measure and improve delivery/open/click rates for product analytics?**
Have workers log a delivery event to an analytics pipeline (not the primary notification store, to avoid coupling the transactional path to analytics load) on every status transition (sent, delivered, opened, clicked), fed by provider webhooks for delivered/opened where supported, then aggregate in a separate analytics/warehouse system rather than querying the operational notification store directly for reporting.

**How would you support multi-region users and data residency requirements (e.g., GDPR)?**
Partition the preference store and notification history by user's home region, route a user's notification requests to their region's pipeline, and keep cross-region replication limited to what's strictly necessary (e.g., none for notification content, which should stay regional) — this mirrors general data-residency patterns rather than anything notification-specific.

**How would you prioritize a critical security alert over a promotional notification during a backpressure event?**
Use separate queue partitions or topics per priority tier (critical vs. standard) so worker pools can be configured to always drain the critical tier first, and apply quiet-hours/rate-limit exemptions specifically to the critical tier (Step 6) — this requires priority to be a first-class field on the notification request, not inferred after the fact.

**How would you A/B test notification copy or send-time optimization?**
Attach an experiment/variant ID to the notification request at creation time, let the template resolution step pick copy based on the assigned variant, and log the variant alongside delivery/open/click events in the analytics pipeline (previous question) so downstream experimentation tooling can compute engagement lift per variant — this is layered entirely on top of the existing template and analytics mechanisms rather than requiring new delivery infrastructure.

**How would you guarantee a scheduled/delayed notification (e.g., "remind me in 2 hours") fires at the right time without polling a database constantly?**
Use a delay-capable queue mechanism — either a message queue's native delayed-delivery feature, or a scheduled-jobs table scanned by a lightweight poller on a short interval and only re-published to the main event bus once due — rather than holding scheduled notifications in application memory, since the ingestion path and the worker pools must both remain stateless and horizontally scalable.
