# Design a Payment / Transaction Processing System

## Problem Statement

"Design a payment processing system — think of the backend behind a checkout button
that charges a user's card, updates account balances, and records the transaction. It
needs to talk to an external payment processor (like Stripe or a card network), and it
absolutely cannot double-charge a customer or lose track of money, even when networks
fail and requests get retried. Walk me through how you'd design this."

This is the one system-design question in this set where the primary constraint is not
throughput or latency — it's **correctness under failure**. A ride-sharing app losing a
GPS ping is a shrug; a payment system double-charging a customer or silently losing a
transaction is a serious, possibly legal, failure. Every design decision here is in
service of that.

## Step 1: Clarify Requirements

**Functional Requirements**
- Users can initiate a payment (charge a card, debit a stored balance, transfer between
  accounts).
- The system integrates with an external payment processor/card network to actually
  move money in/out of the platform.
- Users and merchants can view transaction history and current balance.
- Refunds and partial refunds are supported.
- The system supports multiple currencies (at least: store and display correctly; full
  FX conversion can be scoped out unless asked).
- Failed payments are retried safely, without risk of duplicate charges.
- The system produces auditable records suitable for financial reconciliation and
  dispute handling (chargebacks).

**Non-Functional Requirements**
- **Correctness over latency**: it is acceptable for a payment confirmation to take an
  extra second if that guarantees correctness; it is never acceptable to trade
  correctness for speed on money-moving operations.
- **Consistency**: balance-affecting writes must be strongly consistent (per
  `cap_theorem_and_consistency.md`) — this is one of the rare subsystems in this whole
  question bank where the answer to "would you accept eventual consistency here?" is an
  unambiguous no, for the ledger itself. Peripheral concerns (sending a "payment
  received" notification email) can be eventually consistent.
- **Idempotency**: any payment request must be safely retryable an arbitrary number of
  times without changing the outcome beyond the first successful attempt.
- **Durability**: a committed transaction record must never be lost — this is a
  regulatory and trust requirement, not just an engineering nicety.
- **Auditability**: every balance change must be reconstructable from an immutable
  history, not just reflected in a final number.
- **Scale**: assume a mid-to-large payments platform — 10 million transactions/day,
  with sharp peaks around sales events (e.g., 10-20x normal peak during a flash sale).
- **Availability**: favor availability for read paths (viewing balance/history) but
  correctness-first, availability-second for the write path — a payment system that is
  briefly unavailable is recoverable; one that is available but wrong is not.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 10,000,000 transactions/day on an average day.
- Peak multiplier of 10x during a flash-sale/holiday event, sustained for a few hours.
- Each transaction touches: 1 idempotency-key check, 1 external processor call, at
  least 2 ledger entries (a debit and a credit — see Step 6.2), 1 transaction summary
  record.

**Transaction QPS**
```
10,000,000 / 86,400 sec ≈ 116 transactions/sec average
Peak event: 10x → ~1,160 transactions/sec sustained during the event window
```
This is modest in raw QPS terms compared to, say, a social feed or a location-tracking
system — the difficulty here isn't volume, it's that every single one of these ~1,200
operations/sec at peak must be exactly-once and durably correct, with zero tolerance
for the kind of "eventually consistent, mostly right" approach acceptable elsewhere.

**Ledger row growth**
```
Double-entry bookkeeping (Step 6.2): each transaction writes at least 2 ledger rows (one debit, one credit)
10,000,000 transactions/day x 2 rows x ~200 bytes/row ≈ 4 GB/day ≈ 1.5 TB/year
```
Small in absolute terms — this table will never be the storage bottleneck — but it is
append-only and grows forever by design (Step 6.2 explains why rows are never mutated
or deleted), so it needs a partitioning strategy (e.g., by month) for long-term query
performance even though total volume is unremarkable.

**Idempotency key storage**
```
10,000,000 keys/day x ~150 bytes (key, request hash, result, status, timestamp) ≈ 1.5 GB/day
Retained for a bounded window (e.g., 7-30 days, matching realistic client retry windows) rather than forever
= well within reach of a fast key-value store with a TTL, not a growing-forever table
```

**External processor call latency**
A card-network/processor round trip typically takes 200ms-2s. At 1,160 tx/sec peak,
if calls were fully serialized this would be a severe bottleneck; the system must
issue these calls with high concurrency (many in-flight requests at once, each an
independent async operation) rather than processing the queue one at a time — the
external call is the long pole in per-transaction latency, so the architecture must
not add serialization on top of it.

**Reconciliation batch volume**
```
A nightly reconciliation job compares ~10,000,000 internal records against the processor's
equivalent daily settlement report — a bulk diff job, not a request-latency-sensitive
path, so it can run as an offline batch process rather than needing real-time infrastructure.
```

## Step 3: High-Level Design

**Core components**
- **Payment API / Gateway** — receives payment requests, enforces auth, is the entry
  point for idempotency-key handling.
- **Idempotency Service** — a fast key-value store (idempotency key → status/result)
  checked before any processing begins, to detect and short-circuit retries.
- **Payment Orchestration Service** — coordinates the multi-step payment flow (charge
  external processor, update ledger, notify user) as a Saga (Step 6.4), including
  compensating actions on partial failure.
- **Ledger Service** — the source of truth for account balances, implemented as an
  append-only double-entry ledger (Step 6.2) backed by a strongly consistent relational
  database.
- **External Payment Processor** — a third party (card network/PSP) that actually
  moves money; treated as an external dependency the system doesn't control, can't make
  transactional with its own database, and must assume can fail or time out
  ambiguously.
- **Notification Service** — informs the user of payment success/failure; explicitly
  the one eventually-consistent, best-effort piece of the flow.
- **Reconciliation Service** — an offline batch job comparing internal ledger state
  against the processor's settlement reports (Step 6.5).

**Data flow for a payment**
1. Client submits a payment request with a client-generated idempotency key.
2. Payment API checks the Idempotency Service: if this key was already processed,
   return the previously stored result immediately — no reprocessing, no risk of a
   duplicate charge.
3. If new, Payment Orchestration Service begins the Saga: call the external processor
   to charge the card.
4. On processor success, write the double-entry ledger rows (debit the user's payment
   method / credit the platform's receivable, per the actual accounting flow) inside a
   single local ACID transaction.
5. Mark the idempotency key's result as complete and cache the outcome.
6. Asynchronously notify the user (best-effort, eventually consistent).
7. If any step after the processor charge fails (e.g., the ledger write fails), the
   Saga's compensating action fires — e.g., issue a refund/void call to the processor —
   rather than leaving the system in a state where money moved externally but the
   internal ledger disagrees.
8. Overnight, Reconciliation Service pulls the processor's settlement report and diffs
   it against the internal ledger, flagging any discrepancy for manual/automated
   resolution.

```text
+-------------+
|   Client     |
+------+------+
       | payment request + idempotency_key
       v
+------+----------------------+
|      Payment API / Gateway    |
+------+----------------------+
       |
       v
+------+----------------------+     already processed?
|   Idempotency Service          |----------------------> return cached result
|  (KV store, key -> result)     |
+------+----------------------+
       | new request
       v
+------+----------------------+          +----------------------------+
|  Payment Orchestration        |-------->|  External Payment Processor |
|  Service (Saga coordinator)   |<--------|   (card network / PSP)      |
+------+----------------------+  charge  +----------------------------+
       | on success: write ledger           result
       v
+------+----------------------+
|      Ledger Service            |
|  (double-entry, SQL, ACID,     |
|   strongly consistent)         |
+------+----------------------+
       | on failure: compensating action (void/refund) back to processor
       |
       v
+------+----------------------+     +------------------------+
|   Notification Service        |     |  Reconciliation Service |
|  (best-effort, async)         |     |  (nightly batch diff     |
+-------------------------------+     |  vs. processor report)   |
                                       +------------------------+
```

## Step 4: API Design

**`POST /v1/payments`** — initiate a payment; the idempotency key is the caller's
responsibility to generate once per logical attempt and reuse on retry.
```json
Request:  { "idempotency_key": "ik_a1b2c3", "amount_cents": 4999, "currency": "USD", "payment_method_id": "pm_123", "user_id": "u_789" }
Response: { "payment_id": "pay_555", "status": "succeeded", "amount_cents": 4999 }
```

**`GET /v1/payments/{payment_id}`** — check status of a specific payment.
```json
Response: { "payment_id": "pay_555", "status": "succeeded", "created_at": 1699999999 }
```

**`POST /v1/refunds`** — issue a full or partial refund, itself idempotent.
```json
Request:  { "idempotency_key": "ik_r9x8", "payment_id": "pay_555", "amount_cents": 2000 }
Response: { "refund_id": "ref_222", "status": "succeeded" }
```

**`GET /v1/accounts/{account_id}/balance`** — current balance, computed from the
ledger (Step 6.2).
```json
Response: { "account_id": "acc_1", "balance_cents": 152340, "currency": "USD", "as_of": 1699999999 }
```

**`GET /v1/accounts/{account_id}/ledger?from=...&to=...`** — paginated transaction
history / audit trail.
```json
Response: { "entries": [ {"entry_id":"le_1","type":"debit","amount_cents":4999,"related_payment":"pay_555","ts":1699999999} ] }
```

**`POST /internal/reconciliation/run`** — trigger (or report on) the nightly
reconciliation batch; internal/ops-facing, not customer-facing.
```json
Response: { "run_id": "recon_2026_09_13", "discrepancies_found": 3, "status": "completed" }
```

## Step 5: Data Model

**Ledger — relational (SQL) database, strongly consistent, per `databases_fundamentals.md`**
This is the least negotiable database choice in this entire question bank: the ledger
needs multi-row ACID transactions (a debit and credit must commit together or not at
all), strict consistency (per `cap_theorem_and_consistency.md`, this is a case for
choosing C over A on the write path), and relational integrity constraints (foreign
keys tying entries to accounts and transactions). A NoSQL store optimized for
availability/eventual consistency would directly undermine the one property this
subsystem cannot compromise on.
```sql
CREATE TABLE accounts (
  id            BIGINT PRIMARY KEY,
  owner_id      BIGINT NOT NULL,
  account_type  VARCHAR(20),      -- 'user_wallet', 'platform_receivable', 'platform_payable', ...
  currency      VARCHAR(3)
);

CREATE TABLE ledger_entries (
  id            BIGINT PRIMARY KEY,
  transaction_id BIGINT NOT NULL,   -- groups the debit+credit pair (and any related entries) of one logical transaction
  account_id    BIGINT NOT NULL,
  entry_type    VARCHAR(6) NOT NULL,  -- 'debit' or 'credit'
  amount_cents  BIGINT NOT NULL,      -- integer, smallest currency unit -- never a float
  currency      VARCHAR(3) NOT NULL,
  created_at    TIMESTAMP NOT NULL,
  INDEX idx_account (account_id, created_at),
  INDEX idx_txn (transaction_id)
);
-- ledger_entries rows are NEVER updated or deleted after insert -- see Step 6.2
```
An account's current balance is derived as `SUM(credits) - SUM(debits)` for that
account (or maintained as a periodically-checkpointed running total for read
performance, reconciled against the summed entries — never as the sole stored truth).

**Idempotency records — fast key-value store (Redis or a similarly low-latency store),
per `databases_fundamentals.md`'s NoSQL section**
Chosen because this is a pure key-lookup access pattern (idempotency_key → status/
result), needs to be checked on the hot path of every single payment request so
lookup latency matters more than relational query flexibility, and has a natural
bounded retention window (TTL), unlike the ledger which must be retained
indefinitely.
```
Key:   idempotency:{key}
Value: { "status": "in_progress" | "completed" | "failed", "payment_id": "pay_555", "result_snapshot": {...}, "locked_at": ts }
TTL:   e.g., 30 days
```

**Transaction summary records — relational database** — a denormalized, query-friendly
table (one row per payment, current status, references the underlying ledger entries)
used to serve the customer-facing "your payment history" view without forcing every
such read to reconstruct state from raw ledger entries.

## Step 6: Deep Dive

### 6.1 Idempotency: the single most critical property in this system

The core failure mode this defends against: a client submits a payment, the request
reaches the server and is fully processed (card charged, ledger updated), but the
response is lost on the way back (network blip, client timeout). The client, having no
way to distinguish "my request never arrived" from "it arrived and succeeded but the
response was lost," retries. Without protection, that retry results in a second real
charge for the same purchase — an unambiguous, user-visible bug with real financial
and trust consequences.

The fix: the client generates a unique idempotency key once per logical payment
attempt (typically a UUID generated client-side at the moment the user clicks "pay,"
reused verbatim on every retry of that same attempt) and sends it with every request
for that attempt. Server-side flow:
1. On receiving a request, look up the idempotency key in the Idempotency Service
   *before* doing any processing.
2. If the key exists and its status is `completed`, return the stored result
   immediately — no re-charging, no reprocessing, this is purely a cache-style read.
3. If the key exists and its status is `in_progress` (a concurrent retry arrived while
   the first attempt is still being processed — a real scenario when a client times
   out and retries before the original request actually finished), reject or hold the
   duplicate rather than let two copies of the same logical payment race each other
   through the processor call.
4. If the key doesn't exist, atomically claim it (write `status: in_progress` with a
   conditional/compare-and-swap write, the same atomic-claim pattern used in
   `distributed_systems_core.md`'s idempotency and distributed-locks sections), then
   proceed with processing, and finally update the record to `completed` with the
   result once processing finishes.

This is a system-wide idempotency guarantee, not just a database-level one — it must
cover the external processor call too: the actual charge call made to the payment
processor should itself pass a processor-level idempotency key (most real processors,
e.g., Stripe, support exactly this) so that even if the Payment Orchestration Service
itself crashes and retries mid-flow, the processor also refuses to double-charge on
its end. Idempotency has to be enforced at every hop that could be retried, not just
at the outermost API boundary.

### 6.2 Representing money correctly: the double-entry ledger model

Two related but distinct correctness rules govern how money is represented:

**Integer amounts in the smallest currency unit.** Store `amount_cents = 4999`, never
`amount_dollars = 49.99` as a float. Floating-point arithmetic cannot represent most
decimal fractions exactly, so repeated addition/subtraction of float dollar amounts
accumulates rounding error — unacceptable when the numbers represent real money and
must balance to the cent. Integers in the smallest unit (cents, or the equivalent for
other currencies) sidestep this entirely; currency-aware display formatting (dividing
by 100 and adding a decimal point) happens only at the presentation layer, never in
stored or computed values.

**Double-entry bookkeeping instead of a single mutable balance field.** The naive
design — an `accounts.balance` column that gets incremented/decremented directly on
every transaction — has two serious problems: a lost update under concurrent writes
(two simultaneous transactions both read the old balance, both compute a new balance,
one overwrites the other — the classic read-modify-write race) can silently lose
money, and there is no historical record of *why* the balance is what it is, only what
it currently is, which makes auditing, dispute resolution, and bug investigation
essentially impossible after the fact. Double-entry bookkeeping instead records every
transaction as a **balanced pair of debit and credit entries** across the accounts
involved — money is never "just increased," it always moves *from* one account's
credit *to* another account's debit (or vice versa depending on account type
convention), and the two entries in a pair always sum to zero. A user's current
balance is not a stored field that gets mutated; it's the *sum of that account's
ledger entries*, computed (or checkpointed and periodically reconciled) rather than
stored as the sole truth. This gives two properties for free: full auditability (every
balance is reconstructable by replaying entries, and any discrepancy is traceable to a
specific transaction_id) and safety against concurrent lost-updates (an INSERT of new,
immutable entries doesn't have the same read-modify-write race a mutable UPDATE does —
concurrent transactions each append their own entries rather than contending over
overwriting the same field). Ledger entries, once written, are never updated or
deleted; correcting an error means inserting a new, reversing entry, not editing
history — the ledger table is append-only by design, which is also why its expected
growth (Step 2) had to be estimated as an ever-growing, partitioned table rather than a
fixed-size one.

### 6.3 Partial failures across multiple systems: the Saga pattern

A single payment logically spans at least three systems that cannot share one local
ACID transaction: the external payment processor (a separate company's system, reached
over the network, with no way to enlist it in a two-phase commit with our database),
the internal ledger (our own strongly consistent database), and user notification.
Because the processor is external, there is no way to wrap "charge the card" and
"update the ledger" in a single atomic transaction the way a single-database operation
would allow — this is exactly the scenario `distributed_systems_core.md`'s Saga
pattern section describes: a sequence of local transactions, each with a defined
compensating action if a later step in the sequence fails.

Concretely: step 1 charges the external processor. If step 1 fails outright (processor
declines, times out with a definitive failure response), nothing further happens — no
compensation needed, since no money moved and no ledger entry was written. If step 1
*succeeds* but step 2 (writing the ledger entries) then fails (e.g., a database outage
at the exact wrong moment), the system is now in a state where money has moved
externally but the internal ledger doesn't reflect it — exactly the kind of
inconsistency a Saga's compensating action exists to fix: the orchestrator issues a
compensating call to the processor (void the charge, or issue an immediate refund if
voiding isn't available) to unwind the external side effect, bringing the world back
to "no charge happened" rather than leaving a charged-but-unrecorded transaction
floating. The compensating action itself must also be idempotent and retried until it
succeeds (with the retry state tracked, not fire-and-forget), since a failure in the
compensation step is exactly as dangerous as a failure in the forward step. Steps after
the ledger write (like sending a notification) are explicitly *not* part of the Saga's
correctness-critical chain — a failed notification doesn't need a compensating action
because it never affected money, only communication, so it's fine to leave it as
best-effort/eventually-consistent and simply retry it on a queue without blocking or
unwinding anything upstream.

### 6.4 Reconciliation: the safety net beneath idempotency and sagas

Even with a correct idempotency implementation and a correctly-compensating Saga,
truly guaranteeing exact real-time consistency with an external third party is not
fully achievable — there exist edge cases neither mechanism fully covers: the
orchestrator crashes between receiving the processor's success response and durably
recording that it saw that response (so its own retry logic doesn't know the charge
already succeeded), the compensating void/refund call itself fails repeatedly and
exhausts retries, or the processor's asynchronous webhook confirming final settlement
disagrees with what the synchronous charge call initially reported (holds, disputes,
and delayed settlement are common in real card processing). None of these are
exotic — they're the normal long tail of a distributed system integrating with a
third party the platform doesn't control.

This is why every real payment system runs **reconciliation** as a standing, permanent
safety net, not a one-time migration step: a periodic (typically nightly) batch job
pulls the processor's settlement report — its own authoritative record of what it
actually charged and settled — and diffs it, transaction by transaction, against the
internal ledger. Three outcomes: entries match (the overwhelming majority, confirming
the real-time mechanisms worked correctly); the processor shows a charge with no
matching internal ledger entry (implies a ledger write was lost — needs an automatic
backfill, with alerting); or the internal ledger shows a completed transaction the
processor has no record of (implies a phantom success was recorded internally — a more
serious class of bug needing manual investigation, since it could mean a user's
balance was credited without money actually moving). Reconciliation is deliberately
designed as an offline, non-latency-critical batch process — it doesn't need to be
fast or real-time, because its entire job is to catch the rare cases that fall through
the cracks of the real-time path, on a time horizon (hours, not milliseconds) that's
appropriate for that purpose.

## Step 7: Bottlenecks & Trade-offs

- **The ledger's strong consistency requirement is a deliberate throughput ceiling.**
  Unlike most systems in this question bank where the answer to scaling further is
  "relax consistency, add more replicas, go eventually consistent," the ledger
  explicitly cannot do that — every balance-affecting write needs strict consistency,
  which bounds how far a single logical ledger can scale by simply adding read
  replicas. At very large scale this is addressed by sharding accounts across multiple
  strongly-consistent ledger shards (e.g., by account_id range), accepting that
  cross-shard transactions (rare, since most payments are between a user account and a
  platform account that can be co-located) need their own careful handling — not by
  weakening consistency within a shard.
- **The external processor call is the long pole in latency and the least controllable
  part of the system.** A slow or degraded processor directly slows every payment;
  mitigated by aggressive timeouts paired with idempotent retries (never blind
  unlimited waiting) and, at the architecture level, by not holding any internal locks
  or long-lived transactions open across that external call — the local ledger
  transaction only begins after the processor has already responded.
- **Idempotency key storage has a retention trade-off.** Keeping keys forever is
  wasteful and unnecessary (no legitimate client retries a request from six months
  ago); too short a TTL risks a legitimate slow retry no longer finding its
  original key and accidentally reprocessing. The TTL window (Step 5) is chosen based
  on realistic client retry/backoff ceilings, not arbitrarily.
- **Reconciliation discrepancies represent a fundamental limit, not a bug to be fully
  eliminated.** Because the system integrates with a third party whose internal
  behavior isn't fully observable in real time, some rate of discrepancy is expected
  and reconciliation exists precisely because zero discrepancies can't be structurally
  guaranteed — the goal is catching and resolving them quickly, not preventing them
  from ever occurring.
- **Favoring consistency over availability on the ledger write path means outages are
  visible rather than silently absorbed.** If the ledger database is unreachable, the
  system correctly refuses to accept new payments rather than accepting them and
  reconciling later — a deliberate trade-off of availability for correctness that
  would be the wrong choice in, say, a social feed, and is the right one here.

## Follow-up Questions an Interviewer Might Ask

**"How do you handle currency conversion for cross-currency transactions?"** Introduce
an explicit FX conversion step that locks in a rate at transaction time and records it
as part of the transaction (never recompute a historical transaction's value at a
later, different rate), with the ledger entries for the two sides of a cross-currency
transaction recorded in their respective native currencies rather than forcing a
single shared currency — an extension to the double-entry model, not a replacement of
it.

**"How would you detect and prevent fraudulent transactions?"** Layer a fraud-scoring
step before the processor charge (velocity checks, device/IP reputation, ML risk
scoring) that can hold or decline a transaction pre-emptively — an entirely separate
concern from correctness/idempotency, worth naming as a distinct subsystem
(synchronous scoring on the hot path, plus asynchronous post-hoc review) rather than
conflating it with the ledger design.

**"What if the same idempotency key is sent with a different payment amount?"** This
should be explicitly rejected as a client error (the idempotency key identifies one
specific logical request; a mismatched payload is either a client bug or a suspicious
retry) — the Idempotency Service should store a hash of the original request
parameters alongside the key and compare it on every lookup, refusing the request if
the payload doesn't match what that key was first associated with.

**"How do you support disputes and chargebacks?"** Model a chargeback as its own
transaction type generating its own balanced ledger entries (reversing the original
transaction's effect, plus any chargeback fee as a separate entry), triggered by an
asynchronous webhook from the processor days or weeks after the original transaction —
never by mutating the original transaction's historical entries, preserving the
append-only guarantee from 6.2.

**"How would you scale this to handle a flash-sale 10-20x traffic spike?"** Because the
bottleneck is the external processor call plus the strongly consistent ledger write
(not raw request parsing), scale by increasing concurrency of in-flight processor
calls (async processing, not one-at-a-time), pre-warming/scaling the ledger database's
capacity ahead of a known event, and applying backpressure (queue incoming requests
rather than dropping them, or rather than accepting them and letting them silently
fail) if the correctness-critical path can't keep up — explicitly choosing "make the
user wait a bit longer" over "process without the correctness guarantees."

**"How do you test a system where correctness bugs are this costly?"** Beyond normal
unit/integration tests, this specific system benefits heavily from property-based
testing of the ledger (e.g., "the sum of all entries for any transaction_id is always
zero," "total platform balance is conserved across any sequence of operations") and
chaos-style fault injection specifically targeting the multi-step Saga (kill the
orchestrator between steps, simulate processor timeouts and duplicate webhooks) to
verify compensating actions and reconciliation actually catch what they're designed to
catch, rather than only testing the happy path.
