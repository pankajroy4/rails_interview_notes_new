/*
===============================================================================================
                       SYSTEM DESIGN BASICS + SCHEMA DESIGN (Node lens)
===============================================================================================
(Mirrors my ECommerce_schema_design.rb and the system-design gaps. Schema design + system design
are language-agnostic, but the interviewer will expect Node-flavored answers — where the queue,
cache, search, and ORM fit. Combines with files 14, 17, 25, 33.)
*/

/*
-----------------------------------------------------------------------------------------------
Q1: Design the schema for an e-commerce system (same answer as my Rails notes)
-----------------------------------------------------------------------------------------------
Answer -> A minimal relational model (Postgres), which I'd express via Prisma/Sequelize migrations:

  customers(   customer_id PK, name, email UNIQUE, phone, created_at )
  products(    product_id PK, name, sku UNIQUE, price DECIMAL(10,2), stock_quantity, created_at )
  orders(      order_id PK, customer_id FK, status, total_amount DECIMAL(12,2), placed_at )
  order_items( order_item_id PK, order_id FK, product_id FK, quantity, unit_price DECIMAL(10,2) )
  inventory(   warehouse_id, product_id FK, available_qty, PRIMARY KEY(warehouse_id, product_id) )

  Design notes to say out loud:
   - Money as DECIMAL/NUMERIC, never float (rounding bugs). In Node, handle money carefully (a
     money lib or integer cents) — JS numbers are floats.
   - order_items captures unit_price AT PURCHASE TIME (price can change later) — a snapshot, not a
     live FK to product price.
   - Indexes: orders(customer_id), order_items(order_id), order_items(product_id), products(sku).
   - UUIDs vs auto-increment: UUIDs avoid enumeration + ease sharding/merging; bigint is smaller/faster.

  // total sales per product last month (same SQL, runs anywhere)
  SELECT p.product_id, p.name, SUM(oi.quantity * oi.unit_price) AS total_sales
  FROM order_items oi
  JOIN orders o   ON o.order_id   = oi.order_id
  JOIN products p ON p.product_id = oi.product_id
  WHERE o.placed_at >= now() - INTERVAL '1 month'
  GROUP BY p.product_id, p.name;
*/

/*
-----------------------------------------------------------------------------------------------
Q2: Domain concepts (OMS / WMS / integrations — my Anchanto-flavored notes)
-----------------------------------------------------------------------------------------------
Answer ->
  ORDER MANAGEMENT SYSTEM (OMS): tracks an order's full lifecycle (placement -> delivery), manages
  inventory allotment, routes to the nearest/best warehouse, handles returns and fulfillment, can
  split an order across warehouses by stock.
  WAREHOUSE MANAGEMENT SYSTEM (WMS): tracks real inventory LOCATIONS, the pick/pack/dispatch flow,
  real-time stock across facilities, and prevents overselling.
  INTEGRATIONS: connect marketplaces (Amazon, eBay), web stores, POS, carriers, ERPs — syncing
  orders, inventory, pricing, tracking in real time via APIs/webhooks. KEY CONCERNS: scalability,
  RETRIES, and IDEMPOTENCY (because external systems redeliver/duplicate). SKU = unique product id
  for tracking inventory/sales.

  Node framing: integrations are I/O-bound webhook + API work — exactly Node's strength. I'd ingest
  webhooks on thin Express endpoints, push to BullMQ, process idempotently with retries/backoff —
  the same pipeline as my WhatsApp project (file 27).
*/

/*
-----------------------------------------------------------------------------------------------
Q3: Handling inventory / stockouts / overselling (ties to the race-condition answer)
-----------------------------------------------------------------------------------------------
Answer ->
  - RESERVE stock at order placement (don't wait until fulfillment).
  - Prevent OVERSELLING with an ATOMIC conditional update:
      UPDATE inventory SET available_qty = available_qty - :q
      WHERE product_id = :id AND available_qty >= :q;     -- rows-affected 0 => out of stock
    (or SELECT ... FOR UPDATE in a transaction; or a Redis atomic counter for flash sales — file 28 Q9).
  - Support BACKORDERS where appropriate; low-stock threshold ALERTS; real-time stock sync to
    marketplaces via webhooks/jobs.
  "Reserve early, decrement atomically, sync stock asynchronously, and alert on thresholds."
*/

/*
-----------------------------------------------------------------------------------------------
Q4: How I approach ANY system-design question (a repeatable framework)
-----------------------------------------------------------------------------------------------
Answer -> I drive it in steps so I don't ramble:
  1. CLARIFY requirements + scale: functional (what it must do) and non-functional (QPS, data size,
     read/write ratio, latency, consistency needs). Always ask numbers.
  2. Define the API/contract (endpoints or events).
  3. Data model + storage choice: SQL vs NoSQL vs search (Postgres for relational integrity, Mongo
     for document/flexible, Elasticsearch for search, Redis for hot/ephemeral). Justify it.
  4. High-level components: clients -> load balancer -> stateless Node app tier -> DB(+replicas) +
     cache + queue + search + object storage.
  5. Handle scale + bottlenecks: caching (file 17), read replicas/partitioning/sharding (file 33),
     background jobs for heavy/async work (file 16), CDN for static, horizontal scaling (file 18).
  6. Reliability: idempotency, retries, circuit breakers, graceful degradation, monitoring (file 25/8).
  7. Trade-offs + bottleneck call-out: name what breaks first and how I'd evolve it.

  "Start from requirements and numbers, pick storage to match the access patterns, keep the app
   tier stateless, and push heavy/async work to queues — then talk explicitly about the trade-offs."
*/

/*
-----------------------------------------------------------------------------------------------
Q5: A reference Node architecture I can sketch for most web systems
-----------------------------------------------------------------------------------------------
Answer ->
                          ┌─────────────┐
   Clients ── CDN ──►  Load Balancer (ALB)
                          └──────┬──────┘
                     ┌──────────┼──────────┐
              Node API      Node API     Node API     (stateless, cluster/PM2/k8s replicas)
                     └──────────┼──────────┘
        ┌───────────────┬───────┼────────┬─────────────┬───────────────┐
   Postgres(primary) Read replicas    Redis (cache +   Elasticsearch   S3 (files)
        │                            BullMQ queue +     (search)
        └─ writes                    rate limit + sessions)
                                          │
                                  BullMQ Worker tier  (separate deployment: emails, imports,
                                                       webhooks, notifications — file 16/27)

  Every box maps to a file in these notes. Being able to draw this and explain WHY each piece
  exists (and where it'd bottleneck) is what a 3.5-yr system-design round is testing.
*/

module.exports = {};
