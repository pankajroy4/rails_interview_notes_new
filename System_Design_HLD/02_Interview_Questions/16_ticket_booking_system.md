# Design a Movie/Event Ticket Booking System

## Problem Statement

"Design a ticket booking system like BookMyShow or Ticketmaster. Users should be
able to browse events/movies, view a seat map for a specific showtime, select seats,
and pay to confirm the booking. The hard part isn't the browsing — it's that when a
popular event goes on sale, thousands of people try to grab the same handful of good
seats within seconds of each other, and two people must never end up paying for the
same seat. Walk me through how you'd design this so it holds up under that exact
moment of contention."

## Step 1: Clarify Requirements

**Functional Requirements**
- Browse events/movies/showtimes, view venue and showtime details.
- View a seat map for a given showtime, showing available/held/booked seats.
- Select one or more seats and hold them temporarily while completing payment.
- Pay and confirm the booking; receive a ticket/confirmation.
- Release seats automatically if payment isn't completed in time.
- View/cancel existing bookings.

**Non-Functional Requirements**
- Scale target: a large ticketing platform, assume 500 concurrent high-demand
  on-sales at any time across the platform, with the single largest on-sale drawing
  up to 200,000 concurrent users targeting one event with, say, 20,000 seats.
- **Correctness above all**: two users must never both successfully pay for the same
  seat. This is the one non-negotiable requirement.
- Seat-map viewing should be fast (under 200ms) even under heavy read load — most
  people looking at a seat map are just browsing, not about to buy.
- Seat selection/hold must be near-instant (sub-500ms) so the UI feels responsive
  during a live on-sale.
- The system must survive a traffic stampede at the exact moment tickets go on sale
  without seat-selection requests overwhelming the backend.
- Availability trade-off: during extreme contention, it's acceptable to make some
  users wait (a queue) rather than let everyone in and risk the seat-selection path
  collapsing or, worse, double-booking a seat.
- Payment must be idempotent — retried requests due to network issues must not
  double-charge or double-book.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- Platform-wide: 10,000 events/venues active at a time, average 2,000 seats per
  venue → 20M total seats tracked across the platform at any given moment (a
  bounded, modest number overall).
- Normal traffic: 1M seat-map views/day platform-wide, spread across all events →
  low tens of QPS average, nothing remarkable.
- Flash on-sale scenario (the case that matters): a single event with 20,000 seats
  goes on sale, and 200,000 users hit the seat-selection page within the first 60
  seconds.

**QPS during an on-sale spike**
- 200,000 requests / 60s ≈ **3,300 QPS** hitting the "view/select seat" endpoint for
  a single event, in a system whose steady-state QPS for that same event might
  normally be near zero.
- Of those 200,000 users, only 20,000 seats exist — so at best 10% of arriving users
  can succeed; 90% must be told "sold out" or "still waiting" without ever being
  allowed to corrupt seat state.
- If naively allowed to hit the seat-hold write path directly, this is **3,300+
  concurrent attempts per second against a 20,000-row seat table for one event** —
  small in absolute row count, but massive in write contention concentrated on a
  tiny keyspace, which is exactly why a waiting-room admission mechanism (Step 6) is
  needed rather than a bigger database.

**Storage**
- Seat state: 20M seats platform-wide × ~200 bytes (seat_id, event_id, status,
  held_by, hold_expires_at) ≈ 4GB — trivially small; this is not a storage problem,
  it's a concurrency/contention problem.
- Bookings: assume 5M bookings/month × 500 bytes ≈ 2.5GB/month, ~90GB over 3 years —
  easily handled by a standard relational database with time-based partitioning.

**Bandwidth**
- Seat-map view payload ~20KB (SVG/JSON seat layout). At 3,300 QPS peak that's
  ~66MB/s for one hot event — comfortably served from a cache/CDN layer rather than
  computed fresh per request.

## Step 3: High-Level Design

The distinguishing components versus a generic e-commerce system: a **Waiting Room
service** that gates entry during high-demand on-sales, and a **Seat Locking
service** that manages short-lived holds on individual seats, sitting in front of
the booking/payment flow.

```text
                     ┌─────────────┐
                     │     CDN      │ (static seat-map layout, venue images)
                     └──────┬───────┘
                             │
                     ┌───────▼────────┐
                     │  API Gateway    │
                     └───┬────────┬───┘
                          │        │
            ┌─────────────▼─┐   ┌──▼────────────────┐
            │ Waiting Room    │   │ Seat-Map Read Path │
            │ Service         │   │ (cached view,      │
            │ (admission      │   │  Redis/CDN, TTL'd) │
            │  control queue) │   └────────────────────┘
            └────────┬────────┘
                      │ admits users at controlled rate
            ┌─────────▼────────┐
            │ Seat Locking       │
            │ Service             │────────┐
            │ (hold w/ TTL,       │        │
            │  atomic CAS)        │        │
            └─────────┬───────────┘        │
                      │                    │
            ┌─────────▼─────────┐  ┌───────▼────────┐
            │ Seat/Inventory DB   │  │ Redis (seat     │
            │ (source of truth,   │  │ hold cache, TTL │
            │  strongly consist.) │  │ per seat key)   │
            └─────────┬────────────┘  └─────────────────┘
                      │
            ┌─────────▼─────────┐
            │ Booking/Payment     │
            │ Saga Orchestrator   │───► Payment Gateway (cross-ref 14)
            └─────────────────────┘
```

Flow during a live on-sale: user hits the event page → routed through the **Waiting
Room** which admits users at a rate the backend can sustain → admitted user sees the
seat map (read from cache, may already be slightly stale) → user selects a seat →
**Seat Locking Service** attempts an atomic hold, re-validating against the real
seat state (never trusting the cached view) → on success, user has N minutes to pay
→ payment succeeds → hold converts to a permanent booking; payment fails or times
out → hold releases, seat becomes available again.

## Step 4: API Design

```
GET /events/{event_id}/showtimes
→ 200 { showtimes: [{showtime_id, venue, start_time, price_tiers}] }

GET /showtimes/{showtime_id}/seatmap
→ 200 { seats: [{seat_id, section, row, number, status: "available"|"held"|"booked", price}] }
  # served from cache; status here is a display hint, re-validated on hold attempt

POST /waitingroom/{event_id}/join     (only invoked when an event is flagged high-demand)
  { user_id }
→ 200 { queue_token, estimated_wait_seconds }

GET /waitingroom/{event_id}/status?token=...
→ 200 { admitted: bool, position: int }

POST /seats/hold
  { showtime_id, seat_ids[], user_id, queue_token }
→ 200 { hold_id, seat_ids[], hold_expires_at }   # ~10 min TTL
→ 409 { error: "seat_unavailable", unavailable_seat_ids[] }

POST /bookings/confirm
  { hold_id, payment_method_token, idempotency_key }
→ 200 { booking_id, status: "confirmed", tickets[] }
→ 409 { error: "hold_expired" }
→ 402 { error: "payment_failed" }
```

The `queue_token` from the waiting room is required on `POST /seats/hold` for
flagged high-demand events specifically so the hold-write path is only ever reached
at the admission-controlled rate, not at the raw stampede rate.

## Step 5: Data Model

**Seat DB (relational, e.g. PostgreSQL)** — seat state needs atomic compare-and-swap
semantics and strong consistency; a relational database with row-level constraints
is the natural fit, and the row count per event (thousands, not millions) means this
never needs sharding within a single event — the whole point developed further in
6.3.

```
seats (
  seat_id PK, showtime_id, section, row, number, price_tier,
  status ENUM('available','held','booked'),
  held_by_user_id NULLABLE,
  hold_expires_at TIMESTAMP NULLABLE,
  version INT   -- for optimistic-lock / CAS updates
)

bookings (booking_id PK, user_id, showtime_id, seat_ids[], status, created_at)
```

**Seat Hold Cache (Redis)** — used as a fast-path lock coordinator: key
`hold:{seat_id}` with value `{user_id, hold_id}` and a native TTL (`SET ... NX EX
600`). This gives an atomic, self-expiring lock primitive without needing a
background sweep job for the common case — Redis expires the key itself. The
relational DB row is still the durable source of truth reconciled against this, but
Redis is what absorbs the burst of concurrent hold attempts cheaply.

**Waiting Room Queue (Redis or a dedicated queue)** — an ordered structure (e.g. a
Redis sorted set scored by arrival time, or a Kafka partition) per high-demand
event_id, admitting a bounded number of users per second/interval into the
seat-selection flow.

**Booking DB** — standard relational table for durable, paid bookings; partitioned
by showtime date at scale since old showtimes are rarely queried once the event has
passed.

Why relational for seats specifically, unlike the document-store choice for a
catalog in a general e-commerce system: seat state is small, uniform in shape (no
category-specific variability), and every operation on it needs an atomic
conditional update — exactly what relational row-locking/CAS and ACID transactions
are built for.

## Step 6: Deep Dive

### 6.1 Seat Locking: Hold-with-TTL, Not Pessimistic Locking Across Checkout

This is the centerpiece of the whole design. The naive approach — take a row-level
database lock on a seat the moment a user selects it, and hold that lock until they
finish entering payment details — is a disaster: payment entry is a slow,
user-paced, unreliable step (people fumble with their card, get distracted, lose
connectivity) that can take anywhere from 10 seconds to several minutes. A lock held
across that entire window means the database connection/transaction backing that
lock must stay open the whole time, which doesn't scale past a handful of concurrent
checkouts, let alone thousands during an on-sale, and a single slow/abandoning user
could block a seat indefinitely if their connection just dies without releasing the
lock cleanly.

The correct pattern decouples "claiming a seat" from "holding a database lock" by
using a **hold with a TTL** instead of a lock with unbounded duration:

1. When a user selects a seat, the system performs an atomic conditional write: `SET
   hold:{seat_id} = {user_id} NX EX 600` in Redis (NX = only set if not already
   held; EX = expire in 600 seconds), or equivalently in SQL, `UPDATE seats SET
   status='held', held_by_user_id=?, hold_expires_at=NOW()+interval '10 min',
   version=version+1 WHERE seat_id=? AND status='available' AND version=?` — a
   compare-and-swap using the `version` column so a concurrent attempt on the same
   seat fails the WHERE clause and gets zero rows updated, which the application
   reads as "seat unavailable."
2. This write is instantaneous — no lock is held open waiting on the user. The user
   now has 10 minutes to complete payment; if they do, the hold converts to
   `status='booked'` permanently. If they don't, the TTL simply expires (Redis does
   this natively; the DB-only version needs a lazy check-on-read or a periodic sweep
   job that flips expired holds back to `available`).
3. Crucially, the hold attempt always re-validates against live seat state at write
   time — it never trusts whatever the user's browser had cached from the seat-map
   view. Two users can both be looking at a seat-map that shows seat 12B as
   "available" (because it was, when that cached view was rendered); only one of
   their `POST /seats/hold` calls will win the atomic CAS, and the other gets a 409
   telling the client to refresh the seat map.

This is the same hold-with-TTL shape used for inventory reservation in a general
e-commerce checkout (cross-reference `15_ecommerce_platform.md`'s Step 6.2) — the
underlying problem (don't lock a scarce resource across a slow user-paced step)
recurs anywhere a system sells something finite.

### 6.2 Surviving the On-Sale Stampede: A Virtual Waiting Room

Hold-with-TTL solves correctness once a request reaches the seat-locking path, but
it doesn't solve the arrival-rate problem: if 200,000 users all hit `POST
/seats/hold` (or even just the seat-map page) within the same few seconds, the
backend can be overwhelmed by request volume alone — connection pools exhaust, the
cache tier gets hammered, and legitimate requests start timing out — independent of
whether the locking logic itself is correct.

The mitigation is a **virtual waiting room**, conceptually an admission-controlled
queue in front of the seat-selection flow, applying the same
token-bucket/leaky-bucket rate-limiting ideas from `02_rate_limiter.md` but applied
to *user admission* rather than raw API request throttling. When an event is flagged
high-demand (either pre-configured for a known big on-sale, or dynamically detected
from a spike in incoming traffic), arriving users are issued a `queue_token` and
placed in an ordered queue (a Redis sorted set scored by arrival timestamp works
well at this scale, or a Kafka partition consumed at a fixed rate). A background
admitter pulls users off the queue and marks them "admitted" at a rate calibrated to
what the seat-locking backend can sustain — for example, admitting 500 users every
few seconds rather than letting all 200,000 through at once. Admitted users get
access to the live seat map and the hold endpoint; queued users see a "you're number
4,213, estimated wait 2 minutes" screen polling `GET
/waitingroom/{event_id}/status`.

This deliberately trades strict fairness/speed for system stability: some users wait
even though seats remain, because the alternative — unbounded concurrent access to a
hot, tiny keyspace — risks the entire seat-locking path degrading for everyone,
including the users who would have succeeded.

### 6.3 A Bounded Resource Changes the Right Answer

It's worth stating explicitly why this system's core hard problem is solvable with a
more centralized approach than, say, a distributed key-value store's approach to
writes (cross-reference `17_distributed_key_value_store.md`): the seat map for any
single event is a small, **bounded** resource — a few thousand seats, known and
fixed the moment the event is scheduled. This is unlike most large-scale systems
where the keyspace (users, products, messages) is unbounded and must be partitioned
across many nodes/shards for both storage and load reasons.

Because the contended resource for any one event fits comfortably on a single
database instance (or even in a single Redis instance's memory), the design can
afford a much more centralized, strongly consistent locking strategy per event than
would be viable for a globally sharded system. There's no need to reason about
cross-shard transactions, consistent hashing of seats across nodes, or quorum reads
for seat state — one event's seats can live behind one authoritative lock
coordinator. The trade-off is that this centralization would be the wrong choice at
a different scale (if a single "resource" were billions of keys, forcing everything
through one coordinator would be a bottleneck) — but recognizing that seat maps are
small-N-per-event and large-N-only-in-aggregate-across-events is what justifies
per-event centralization: shard by event_id (each event's seat map is independently
hosted/cached/locked), not by seat_id globally, since seats from different events
never contend with each other.

### 6.4 Payment Integration and Compensating Action on Failure

Booking confirmation follows the same Saga shape as e-commerce checkout
(cross-reference `14_payment_system.md`'s idempotency and Saga discussion): hold
seat (already done in 6.1) → charge payment → confirm booking. `POST
/bookings/confirm` requires an `idempotency_key` precisely because payment gateway
calls can be retried by the client after a timeout without the gateway's original
response being known — the Payment Service must recognize a repeated idempotency key
and return the original result rather than charging twice.

The compensating action if payment fails (declined card, gateway timeout, gateway
error) is simply **releasing the seat hold early** rather than waiting for its TTL —
flip `status` back to `available` immediately (or delete the Redis `hold:{seat_id}`
key) so the seat re-enters availability for other waiting-room-admitted users as
fast as possible, since during a live on-sale every second a seat sits needlessly
held is lost throughput. If the payment gateway call itself times out ambiguously
(unclear whether the charge succeeded), the safe move is to *not* release the hold
immediately — keep it held until a reconciliation check against the gateway resolves
the ambiguity, to avoid the seat being sold to a second person while the first
person's payment might still land.

### 6.5 Read-Heavy Viewing vs. Write-Critical Selection

The seat map is viewed far more often than seats are actually selected — most
visitors to an event page are checking prices or availability without buying. This
read path is cached aggressively: the seat-map response can be served from Redis or
even CDN-edge-cached with a short TTL (a few seconds), refreshed by a background
process or invalidated on booking events, because a slightly stale "available" badge
on a seat that's since been booked costs nothing beyond a momentary UX hiccup at the
moment the user actually tries to select it.

The seat-*selection* path is the opposite: it must never be served from that same
cache. `POST /seats/hold` always performs its atomic CAS against the live source of
truth (Redis hold-key or the DB row with version check), never against the cached
seat-map snapshot, precisely because this is the one operation where staleness
translates directly into the correctness violation the whole system exists to
prevent (double-booking). This read/write asymmetry — cache aggressively for
display, always re-validate transactionally for the actual write — is the same
principle used for inventory `stock_status` display versus authoritative decrement
in the e-commerce design (cross-reference `15_ecommerce_platform.md` Step 6.1),
applied here to seats instead of SKUs.

## Step 7: Bottlenecks & Trade-offs

- **The seat-locking coordinator for a single hot event is the sharpest
  bottleneck**, precisely because 6.3 argues for centralizing it — the mitigation is
  the waiting room (6.2) controlling arrival rate into that coordinator, not
  distributing the coordinator itself, since distributing a few-thousand-row
  keyspace would add cross-node coordination overhead for no real capacity benefit.
- **Waiting room fairness vs. throughput**: a strict FIFO queue is fair but can
  under-utilize capacity if early-admitted users stall (e.g., abandon before
  completing a hold); many real systems admit slightly more users than strictly
  available seats, accepting a higher 409-rate on hold attempts in exchange for
  keeping the pipeline full — a deliberate trade of some wasted client-side attempts
  for better throughput.
- **TTL tuning is a direct conversion lever**: shorter holds free up contested seats
  faster (good during an on-sale) but risk legitimate slow payers losing their seat
  (bad for conversion/trust); many platforms shorten the hold TTL specifically
  during flagged high-demand events and use a longer, more forgiving TTL for
  ordinary low-contention bookings.
- **Cache staleness window on the seat map** must be kept short (seconds, not
  minutes) precisely because unlike a general product catalog, users here are
  actively trying to make a real-time decision among a small set of specific,
  individually distinguishable items (this exact seat, not "a" unit of a SKU) —
  stale seat maps are more visibly and immediately frustrating than a stale product
  page.
- **Reconciliation after ambiguous payment gateway failures** (6.4) is a genuine
  unsolved-feeling edge case in any real system: holding a seat indefinitely pending
  manual/automated reconciliation is safer than releasing it prematurely, but ties
  up inventory during exactly the highest-demand moments — most platforms bound this
  with a secondary, longer timeout plus an operational alert rather than leaving it
  truly indefinite.

## Follow-up Questions an Interviewer Might Ask

- **"How do you handle group bookings where a user wants adjacent seats, and one of
  the desired seats gets taken mid-selection?"** Discuss holding all requested seats
  in one atomic multi-key operation (a Lua script in Redis, or a single DB
  transaction covering all seat rows) so the hold either succeeds for the whole
  group or fails entirely, rather than partially holding seats and leaving the user
  with a broken selection.
- **"What if the waiting room itself becomes a bottleneck under 200,000 concurrent
  joins?"** Point out the waiting room's own write path (issuing tokens, tracking
  position) is much cheaper than the seat-locking path — it's a simple counter/queue
  insert, not a conditional multi-row update — and can be horizontally scaled or
  even served from an edge/CDN-adjacent layer since token issuance doesn't need
  strong global ordering, just monotonic-enough fairness.
- **"How would you prevent bots/scalpers from mass-holding seats via automated
  requests?"** Discuss rate limiting per user/IP at the waiting-room admission step
  (cross-reference `02_rate_limiter.md`), CAPTCHA or proof-of-work challenges before
  admission, and capping the number of concurrent holds per user account.
- **"How do you handle a venue-wide event cancellation, needing to refund and
  release thousands of bookings at once?"** Treat this as a bulk compensating-action
  job: iterate bookings for the event, trigger refunds via the Payment Service
  (idempotent, so safe to retry on partial failure), and mark bookings cancelled —
  explicitly a batch/async job, not a synchronous user-facing flow.
- **"What about seat-map layout changes for accessibility or partial venue closures
  after tickets have already been sold?"** This requires a manual reconciliation
  flow outside the normal hold/book path — affected bookings need explicit
  reassignment or refund, since the automated seat-locking system assumes a fixed
  seat map and isn't designed to silently remap already-sold seats.
- **"How would you extend this to support dynamic pricing (price changes based on
  demand)?"** Note that price should be captured and locked in at hold time (stored
  on the `seats` row or the hold record itself), not re-evaluated at payment
  confirmation, so a demand-driven price increase between hold and payment doesn't
  silently change what the user is charged.

