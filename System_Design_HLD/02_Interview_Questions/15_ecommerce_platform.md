# Design an E-commerce Platform

## Problem Statement

"Design an e-commerce platform like Amazon. Users should be able to browse and
search a product catalog, add items to a cart, check out, and pay. The system needs
to track inventory accurately so we never sell something we don't have, handle flash
sales where a single product suddenly gets hammered with orders, and stay fast for
millions of people just browsing. Walk me through how you'd architect this — I want
to see how you separate concerns, not just draw one big database."

## Step 1: Clarify Requirements

**Functional Requirements**
- Browse and search a product catalog (by category, keyword, filters like
  price/brand).
- View product detail pages (price, images, description, stock status).
- Add/remove items to a shopping cart, update quantities.
- Checkout: address, shipping method, payment, order confirmation.
- Inventory tracking per SKU, possibly per warehouse/fulfillment center.
- Order history and order status tracking (placed, paid, shipped, delivered,
  cancelled).
- Seller/admin side: add products, update stock, view sales (mention briefly, not
  the focus).

**Non-Functional Requirements**
- Scale: assume 50M monthly active users, 10M products (SKUs), a major retailer
  scale.
- Read-heavy overall: browsing/search traffic outweighs checkout traffic by roughly
  100:1.
- Browsing latency: product page and search results should render in under 200ms
  p99.
- Checkout latency: acceptable up to 1-2s given it involves payment gateway calls,
  but each step should feel responsive.
- **Never oversell**: inventory correctness is a hard consistency requirement — this
  is a business and legal constraint, not a "nice to have."
- Catalog data can be eventually consistent (a price update propagating in a few
  seconds is fine); inventory counts used at checkout cannot be stale.
- High availability for browsing (a search outage is bad but recoverable); checkout
  availability matters even more because it's revenue-generating, but correctness
  there trumps availability — better to fail a checkout than to oversell.
- Must survive flash-sale traffic spikes on a single hot product without falling
  over.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 50M MAU, of which ~5M are daily active users (DAU).
- Each DAU views ~20 product pages/search results per session → 100M page views/day.
- Browse:checkout ratio ≈ 100:1 → roughly 1M checkout-relevant actions/day (cart
  add, checkout start, order placed combined, order placement being the smallest of
  these).
- Assume 300K orders placed per day on a normal day.

**QPS**
- Browse/search QPS: 100M views / 86,400s ≈ **1,160 QPS average**, with a peak
  multiplier of 5-10x during evenings/sales → **~8,000-10,000 QPS peak** for read
  traffic.
- Order placement QPS: 300K / 86,400s ≈ **3.5 QPS average**, peaking at maybe 50-100
  QPS during a normal peak hour.
- Flash sale scenario: a single SKU drop can draw 200K concurrent users trying to
  buy in a 60-second window → **thousands of write attempts per second against a
  single row**, which is the crux of Step 6's hot-SKU discussion.

**Storage**
- Product catalog: 10M SKUs × ~5KB (title, description, attributes, metadata) ≈ 50GB
  of catalog text data — small enough to fit comfortably in a search index and a
  cache tier.
- Product images: 10M SKUs × ~5 images × 200KB ≈ 10TB, stored in blob storage
  (cross-reference `12_storage_systems.md`), served via CDN, not a database concern.
- Inventory table: 10M SKUs × maybe 3 warehouses each ≈ 30M rows, each a tiny row
  (SKU id, warehouse id, count, reserved count) — a few GB, fits easily in a
  relational database, and is small enough to be a source of truth without sharding
  at this scale.
- Orders: 300K orders/day × 365 days × 3 years retention ≈ 330M order rows. At ~2KB
  per order (with line items) that's ~660GB — this is where a relational database
  starts needing partitioning/sharding by order_id or user_id range as it grows
  (cross-reference `07_database_scaling.md`).

**Bandwidth**
- Peak read QPS 10,000 × ~50KB average page payload (JSON + a few images cached
  client-side) ≈ 500MB/s at the edge — this is why a CDN and aggressive caching are
  not optional, they're load-bearing.

## Step 3: High-Level Design

The core architectural decision is splitting the system into services with genuinely
different consistency and scaling profiles, rather than one monolithic "products"
table backing everything:

- **Catalog Service** — product metadata, descriptions, images, search. Backed by a
  search index (Elasticsearch/OpenSearch) and heavily cached. Eventually consistent
  is fine.
- **Inventory Service** — authoritative stock counts per SKU/warehouse. Backed by a
  strongly consistent relational store. This is the one place we cannot cut
  consistency corners.
- **Cart Service** — ephemeral per-user cart state in a fast key-value store.
- **Order Service** — durable order records, orchestrates the checkout saga across
  inventory, payment, and shipping.
- **Payment Service** — external gateway integration (cross-reference
  `14_payment_system.md`).
- **Shipping/Fulfillment Service** — hands off to warehouse/logistics systems once
  payment succeeds.

```text
                          ┌────────────┐
                          │    CDN     │  (static assets, images)
                          └─────┬──────┘
                                │
                          ┌─────▼──────┐
                          │ API Gateway │
                          └──┬───┬───┬──┘
              ┌──────────────┘   │   └───────────────┐
              │                  │                   │
      ┌───────▼───────┐  ┌───────▼───────┐   ┌────────▼────────┐
      │ Catalog Service│  │  Cart Service  │   │  Order Service   │
      │ (search+browse)│  │ (Redis, ephem.)│   │ (checkout saga)  │
      └───────┬────────┘  └────────────────┘   └───┬────┬────┬───┘
              │                                     │    │    │
      ┌───────▼────────┐                    ┌───────▼┐ ┌▼────▼──┐  ┌────────────┐
      │ Search Index    │                    │Inventory│ │Payment │  │ Shipping/   │
      │ (Elasticsearch) │                    │Service  │ │Service │  │ Fulfillment │
      │  + cache (CDN/  │                    │(strong  │ │(gateway│  │ Service     │
      │  Redis, TTL'd)  │                    │consist.)│ │+idempo)│  └────────────┘
      └───────┬─────────┘                    └────┬────┘ └────────┘
              │                                    │
      ┌───────▼─────────┐                   ┌──────▼──────┐
      │ Catalog DB       │                   │ Inventory DB │
      │ (source of truth,│                   │ (RDBMS, row- │
      │  async-indexed)  │                   │  or queue-   │
      └──────────────────┘                   │  serialized  │
                                              │  per SKU)    │
                                              └──────────────┘
```

Data flow for a purchase: browse (Catalog Service, cache-heavy) → add to cart (Cart
Service, Redis, no inventory touch) → begin checkout (Order Service starts a saga:
reserve inventory with TTL → charge payment → finalize inventory decrement → hand
off to shipping) → order confirmed.

## Step 4: API Design

```
GET /products/search?q=wireless+mouse&category=electronics&page=2
→ 200 { results: [{sku_id, title, price, thumbnail_url, in_stock: bool}], total, page }

GET /products/{sku_id}
→ 200 { sku_id, title, description, price, images[], attributes{}, stock_status: "in_stock"|"low_stock"|"out_of_stock" }
  # stock_status is a cached/approximate signal for display, NOT the authoritative count used at checkout

POST /cart/items
  { user_id, sku_id, quantity }
→ 200 { cart_id, items[], subtotal }
  # writes only to Cart Service (Redis); does NOT touch Inventory Service

POST /checkout/start
  { cart_id, shipping_address }
→ 201 { checkout_id, reserved_items: [{sku_id, quantity, hold_expires_at}], total }
  # this is the moment inventory is actually reserved (see Step 6)

POST /checkout/{checkout_id}/pay
  { payment_method_token, idempotency_key }
→ 200 { order_id, status: "confirmed" } | 402 { error: "payment_failed" } | 409 { error: "hold_expired" }

GET /orders/{order_id}
→ 200 { order_id, status, line_items[], tracking_info }
```

Note the deliberate asymmetry: `POST /cart/items` never talks to the Inventory
Service, but `POST /checkout/start` does — that boundary is the whole point of the
reservation pattern in Step 6.

## Step 5: Data Model

**Catalog DB (document store, e.g. MongoDB, or RDBMS + search index)** — product
attributes vary wildly by category (a book has an ISBN, a shirt has size/color), so
a flexible schema fits better than a rigid relational one. Justification:
read-heavy, tolerant of eventual consistency, benefits from denormalized documents
that map directly to what a product page needs.

```
Product {
  sku_id (PK), title, description, category, price,
  attributes: { ... category-specific fields ... },
  image_urls: [...],
  updated_at
}
```

**Search Index (Elasticsearch)** — denormalized copy of catalog data, updated
asynchronously via a change stream/CDC pipeline from the Catalog DB (cross-reference
`13_search_and_indexing.md`). Never the source of truth for price or stock.

**Inventory DB (relational, e.g. PostgreSQL)** — this needs ACID transactions and
row-level locking guarantees, so relational is the right choice despite the catalog
being document-oriented. Two different databases for two different consistency needs
is a deliberate, defensible split, not an inconsistency in the design.

```
inventory (
  sku_id, warehouse_id,
  available_count INT,
  reserved_count INT,
  PRIMARY KEY (sku_id, warehouse_id)
)

inventory_reservations (
  reservation_id PK, sku_id, warehouse_id, quantity,
  checkout_id, expires_at, status  -- pending|committed|released
)
```

**Cart Store (Redis)** — key `cart:{user_id}` → hash of `{sku_id: quantity}` with a
TTL of, say, 30 days of inactivity. No foreign key relationship to Inventory; a cart
is a wishlist-like scratchpad, not a commitment.

**Order DB (relational, sharded by user_id or order_id range at scale)** — orders
need durability and transactional integrity (an order and its line items must be
written together), and are queried by user and by order id, both of which shard
cleanly.

```
orders (order_id PK, user_id, status, total, created_at, shard_key)
order_items (order_id FK, sku_id, quantity, unit_price)
```

## Step 6: Deep Dive

### 6.1 Catalog vs. Inventory: Two Services, Two Consistency Models

This is the single most important modeling decision in the whole system, and
interviewers are specifically listening for whether a candidate treats "product
data" as one undifferentiated blob or splits it correctly.

The Catalog Service answers "what does this product look like and roughly is it
available" — title, description, images, price, and a coarse `stock_status` badge.
This can be cached aggressively at every layer: CDN edge, application cache, even
the search index itself (cross-reference `05_caching.md`). If the cached stock badge
says "in stock" but the item actually sold out 4 seconds ago, the cost of that
staleness is a mildly annoying UX moment on the product page — not a business
problem — because the *authoritative* check happens later, at checkout.

The Inventory Service answers a different question: "can I actually decrement one
unit of this SKU right now, atomically, without letting two concurrent requests both
succeed for the last unit." This cannot be served from a cache, because a cache miss
on staleness here means overselling — shipping a promise you can't keep, which means
refunds, angry customers, and in some jurisdictions regulatory exposure. So
Inventory reads on the checkout path always hit the strongly consistent store
directly, never a cache, even though this is a small fraction of total traffic
(checkout QPS is ~1/100th of browse QPS, so the strongly-consistent path being
slower/more expensive per-request is an acceptable trade because it's rare).

The practical consequence: these are separate services, likely separate databases,
updated at different cadences, and a candidate who tries to serve both from one
"products" table with one caching strategy will either make browsing too slow (by
never caching, to stay safe on stock) or make checkout unsafe (by trusting a cached
count).

### 6.2 Inventory Reservation: Why Add-to-Cart Must Never Touch Stock

A naive design decrements `inventory.available_count` the moment a user adds an item
to their cart. This is wrong, and explaining why is a strong signal in an interview:
a cart is a low-commitment, long-lived, often-abandoned object. Users add things to
carts and vanish for hours, days, or forever — cart abandonment rates in real
e-commerce are commonly 60-70%. If adding to cart decremented stock, a popular
item's entire inventory could be "sold" to people who never check out, while an
actually-motivated buyer sees "out of stock" and leaves. Stock would effectively be
locked up by browsing behavior, not purchasing behavior.

The correct pattern has three distinct states for a unit of stock:
1. **Available** — free to be reserved.
2. **Reserved (held)** — a checkout is in progress; the unit is set aside with a
   TTL, tracked in `inventory_reservations` with an `expires_at`.
3. **Committed (sold)** — payment succeeded, the reservation is finalized into a
   permanent decrement.

The reservation only happens at `POST /checkout/start`, not at cart add. It's
implemented as an atomic operation against the Inventory DB: `UPDATE inventory SET
available_count = available_count - qty, reserved_count = reserved_count + qty WHERE
sku_id = ? AND available_count >= qty`, inside a transaction that also inserts the
`inventory_reservations` row with a short TTL (typically 10-15 minutes, long enough
to enter payment details, short enough that abandoned checkouts don't lock stock for
long). A background job (or lazy check on next access) sweeps expired reservations,
moving `reserved_count` back to `available_count`. If payment succeeds, the
reservation transitions to `committed` and the units simply never return to
`available_count` — no additional decrement is needed because the decrement already
happened at reservation time; if payment fails or the hold expires, the reservation
is released, exactly mirroring the seat-hold pattern used in ticket booking systems
(cross-reference `16_ticket_booking_system.md` — the same hold-with-TTL shape recurs
anywhere a scarce resource needs a commitment window).

### 6.3 Order Fulfillment as a Saga

A single order touches at least three services that cannot participate in one ACID
transaction because they're different systems (and Payment is a third-party gateway
you don't control): Inventory (reserve/commit stock), Payment (charge the card), and
Shipping (create a fulfillment request). This is the textbook case for the **Saga
pattern** (cross-reference `09_distributed_systems_core.md` and
`14_payment_system.md`'s treatment of Sagas for payment flows): a sequence of local
transactions, each with a defined compensating action if a later step fails.

```
1. Reserve inventory (hold, TTL)        compensate: release hold
2. Charge payment (idempotent request)  compensate: refund
3. Commit inventory decrement            compensate: restore stock
4. Create shipping request                compensate: cancel shipment
```

If step 2 (payment) fails, the saga only needs to undo step 1 — release the
inventory hold — because nothing after step 1 ran. If step 4 fails (e.g., the
shipping service is down), the saga must compensate steps 3, 2, and 1 in reverse:
restore stock, refund the payment, and mark the order failed. The Order Service acts
as the saga orchestrator, persisting saga state (which step it's on) so that if the
orchestrator itself crashes mid-saga, it can resume from the last known step on
restart rather than leaving an order in limbo — this durability of saga state is as
important as the compensating logic itself.

### 6.4 The Flash-Sale Hot-SKU Problem

Everything above works fine when write load is spread across millions of SKUs. It
breaks down for a single wildly popular SKU during a flash sale, where the `UPDATE
inventory ... WHERE sku_id = X` row becomes a hotspot receiving thousands of
concurrent write attempts per second, all targeting the exact same row.

The naive fix — row-level locking, where each request takes a lock, decrements, and
releases — collapses under this load. Every request queues behind the lock; with
thousands of concurrent attempts, latency for each request balloons as the queue
grows, and many databases will start timing out or piling up connections waiting on
the same lock, which can degrade the whole database instance, not just that SKU. An
optimistic-concurrency alternative (read the count, compute the new value, `UPDATE
... WHERE available_count = <value I read>`, retry on conflict) is just as bad or
worse here: at this contention level, almost every optimistic write loses the race
and retries, producing a retry storm that multiplies effective load on the row
several times over.

The standard mitigation is to stop letting requests contend on the row directly at
all, and instead serialize all decrements for that specific hot SKU through a single
ordered path:
- **Queue-based serialization**: all "buy SKU X" requests for the hot SKU are pushed
  onto a queue (or a Kafka partition keyed by sku_id, cross-reference
  `10_message_queues_and_streaming.md`), and a single consumer processes them one at
  a time against the inventory row, so there's no lock contention because there's no
  concurrency at the point of decrement — the queue itself imposes ordering.
  Requests are enqueued fast (low latency for the user-facing "we got your request"
  response) and the actual decrement happens asynchronously, with the user polling
  or getting a websocket push for the result.
- **Atomic distributed counter**: alternatively, hold the hot SKU's available count
  as a single atomic counter in Redis (`DECR`), which handles very high throughput
  per key far better than a relational row under lock contention, and only sync back
  to the relational Inventory DB periodically or at sale end. This trades a small
  window of using an in-memory store as a temporary source of truth for that one SKU
  against surviving the spike at all.

Either way, the key insight the interviewer wants to hear: this is not a general
inventory-scaling problem (most SKUs are never contended), it's a single-hot-key
problem, and the fix is specific to that key — you don't redesign the whole
Inventory Service around it, you special-case the hot path (often even detecting
"this SKU is trending" ahead of a scheduled sale and pre-routing it through the
queue-serialized path).

### 6.5 Search/Browse Decoupled from the Transactional Path

The search index (Elasticsearch/OpenSearch, cross-reference
`13_search_and_indexing.md`) is populated by an asynchronous pipeline off the
Catalog DB — not queried live against Inventory or Orders. A "search for wireless
mice" action and a "buy this specific wireless mouse" action have fundamentally
different requirements: search needs to be fast, relevant, and can tolerate a few
seconds of staleness (a sold-out item showing up in results for a moment is a minor
UX issue, fixed by the checkout-time stock check); a buy action needs correctness
above all else. Sharing one data path between them would force search to either be
slow (if it always checked live inventory) or the buy path to be unsafe (if it
trusted the search index's cached stock field) — so they're deliberately kept on
separate infrastructure, connected only by an async indexing pipeline (CDC from the
Catalog DB, or an event stream on product updates).

## Step 7: Bottlenecks & Trade-offs

- **The Inventory DB is the system's true bottleneck at extreme scale**, not the
  catalog or search — because it's the one component that cannot be arbitrarily
  cached or horizontally read-replicated without risking correctness. The mitigation
  is sharding it by SKU (or SKU range) rather than by warehouse or category, since
  SKU is the natural access pattern for both reservation and commit operations, plus
  the hot-key queue-serialization strategy from 6.4 for outlier SKUs.
- **Cache staleness on the catalog side is an accepted trade-off, not a bug** — the
  design deliberately favors availability and latency for browsing (99% of traffic)
  at the cost of a small, bounded window of stale display data, because the
  authoritative check always happens at the narrow checkout chokepoint.
- **Reservation TTL is a tuning knob with real trade-offs**: too short, and
  legitimate slow shoppers lose their hold mid-checkout, hurting conversion; too
  long, and abandoned checkouts lock up stock during high-demand periods, hurting
  other buyers. In practice this value is often shortened dynamically during flash
  sales specifically because contention is high.
- **The Saga's eventual consistency window** means an order can briefly exist in a
  "processing" state visible to the user before all compensating logic would resolve
  a failure — acceptable for e-commerce (unlike, say, a bank transfer) because the
  customer-facing status just says "processing" and resolves within seconds.
- **Cart Service data loss** is an accepted risk: because carts live in Redis rather
  than a durable relational store, a Redis node failure could lose in-flight cart
  state for some users. This is deliberately tolerated because a lost cart is a UX
  annoyance (re-add a few items), not a correctness or financial problem — a trade
  only defensible because nothing financially binding has happened yet at the cart
  stage.

## Follow-up Questions an Interviewer Might Ask

- **"How would you handle international pricing/currency and tax calculation?"**
  Extend the Catalog Service with a pricing sub-component that resolves price by
  locale/currency at read time rather than storing one price per SKU, and push tax
  calculation into checkout as a dedicated step (often via a third-party tax
  service) since it depends on shipping address, not just the product.
- **"What happens if the payment gateway is slow or down during a flash sale?"**
  Discuss circuit breakers around the Payment Service call, and consider decoupling
  "payment initiated" from "payment confirmed" via async webhook callbacks
  (cross-reference `14_payment_system.md`) rather than holding the checkout request
  open waiting synchronously.
- **"How do you handle a return/refund after an order has shipped?"** Explain that
  this is effectively a new saga in reverse — restock inventory (with its own
  validation, since a warehouse needs to physically receive the item first), issue a
  payment refund, and update order status — not simply "undo" the original saga,
  since real-world time has passed and physical goods are involved.
- **"How would you recommend products (recommendations/'customers also bought')?"**
  Point to a separate, offline-computed recommendation service reading from an event
  stream of browse/purchase behavior, deliberately decoupled from the transactional
  path for the same reasons search is — it's a read-side enhancement that must never
  block or slow down checkout.
- **"How do you keep the search index and catalog DB in sync without lag causing
  visible bugs?"** Discuss CDC (change data capture) with a monotonic
  sequence/version per product so indexing consumers can detect and skip
  out-of-order updates, plus a periodic full reconciliation job as a safety net
  (cross-reference `13_search_and_indexing.md`).
- **"What if two warehouses each show stock but combined they oversell due to a
  routing bug?"** Discuss that `inventory` is keyed by `(sku_id, warehouse_id)`
  precisely so reservations are warehouse-scoped, and that the checkout flow must
  pick a specific warehouse (nearest/available) before reserving — a global "total
  stock" number is a display aggregate only, never used to authorize a reservation.

