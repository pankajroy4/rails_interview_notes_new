# Design an E-commerce Platform

## Problem Statement

"Ek e-commerce platform design karo, Amazon jaisa. Users ko ek product catalog browse
aur search karne, cart mein items add karne, checkout karne, aur pay karne ke able
hona chahiye. System ko inventory accurately track karna hai taaki hum kabhi woh
cheez na bechein jo hamare paas nahi hai, flash sales handle karni hain jahan ek
single product ko achanak orders se hammer kiya jaata hai, aur millions of logon ke
liye fast rehna hai jo bas browse kar rahe hain. Mujhe walk through karo ki tum yeh
kaise architect karoge — mujhe dekhna hai ki tum concerns kaise separate karte ho,
sirf ek bada database mat banao."

## Step 1: Requirements Clarify Karna

**Functional Requirements**
- Product catalog browse aur search karo (category, keyword, filters jaise
  price/brand se).
- Product detail pages dekho (price, images, description, stock status).
- Shopping cart mein items add/remove karo, quantities update karo.
- Checkout: address, shipping method, payment, order confirmation.
- Per SKU inventory tracking, possibly per warehouse/fulfillment center.
- Order history aur order status tracking (placed, paid, shipped, delivered,
  cancelled).
- Seller/admin side: products add karna, stock update karna, sales dekhna (briefly
  mention karo, focus nahi).

**Non-Functional Requirements**
- Scale: assume karo 50M monthly active users, 10M products (SKUs), ek major
  retailer scale.
- Read-heavy overall: browsing/search traffic checkout traffic se roughly 100:1
  outweigh karta hai.
- Browsing latency: product page aur search results ko under 200ms p99 mein render
  hona chahiye.
- Checkout latency: payment gateway calls involve hone ki wajah se 1-2s tak
  acceptable hai, par har step responsive feel hona chahiye.
- **Kabhi oversell mat karo**: inventory correctness ek hard consistency requirement
  hai — yeh ek business aur legal constraint hai, "nice to have" nahi.
- Catalog data eventually consistent ho sakta hai (ek price update ka kuch seconds
  mein propagate hona theek hai); checkout pe use hone waale inventory counts stale
  nahi hone chahiye.
- Browsing ke liye high availability (ek search outage bura hai par recoverable hai);
  checkout availability aur bhi zyada matter karti hai kyunki yeh revenue-generating
  hai, par wahaan correctness availability se upar hai — ek checkout fail karna
  oversell karne se behtar hai.
- Ek single hot product pe flash-sale traffic spikes ko bina gire survive karna hai.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 50M MAU, jinme se ~5M daily active users (DAU) hain.
- Har DAU ~20 product pages/search results per session dekhta hai → 100M page
  views/day.
- Browse:checkout ratio ≈ 100:1 → roughly 1M checkout-relevant actions/day (cart
  add, checkout start, order placed combined, in mein order placement sabse chhota
  hai).
- Assume karo 300K orders ek normal din pe place hote hain.

**QPS**
- Browse/search QPS: 100M views / 86,400s ≈ **1,160 QPS average**, evenings/sales ke
  douran 5-10x ke peak multiplier ke saath → read traffic ke liye **~8,000-10,000 QPS
  peak**.
- Order placement QPS: 300K / 86,400s ≈ **3.5 QPS average**, ek normal peak hour ke
  douran shayad 50-100 QPS tak peak.
- Flash sale scenario: ek single SKU drop 60-second window mein 200K concurrent
  users ko buy karne ke liye kheench sakta hai → **ek single row ke against
  thousands of write attempts per second**, jo Step 6 ki hot-SKU discussion ka crux
  hai.

**Storage**
- Product catalog: 10M SKUs × ~5KB (title, description, attributes, metadata) ≈
  50GB ka catalog text data — itna chhota ki ek search index aur ek cache tier mein
  comfortably fit ho jaaye.
- Product images: 10M SKUs × ~5 images × 200KB ≈ 10TB, blob storage mein stored
  (cross-reference `12_storage_systems.md`), CDN ke through serve hoti hain, ek
  database concern nahi.
- Inventory table: 10M SKUs × maybe 3 warehouses each ≈ 30M rows, har ek ek chhota
  row (SKU id, warehouse id, count, reserved count) — kuch GB, easily ek relational
  database mein fit ho jaata hai, aur is scale pe sharding ke bina source of truth
  bane rehne jitna chhota hai.
- Orders: 300K orders/day × 365 days × 3 years retention ≈ 330M order rows. ~2KB
  per order pe (line items ke saath) yeh ~660GB hai — yahaan se relational database ko
  order_id ya user_id range se partitioning/sharding chahiye hone lagti hai jaise
  jaise yeh badhta hai (cross-reference `07_database_scaling.md`).

**Bandwidth**
- Peak read QPS 10,000 × ~50KB average page payload (JSON + kuch images client-side
  cached) ≈ 500MB/s edge pe — isi liye ek CDN aur aggressive caching optional nahi
  hain, yeh load-bearing hain.

## Step 3: High-Level Design

Core architectural decision hai system ko genuinely different consistency aur
scaling profiles waale services mein split karna, ek monolithic "products" table
jo sab kuch back kare uske bajaye:

- **Catalog Service** — product metadata, descriptions, images, search. Ek search
  index (Elasticsearch/OpenSearch) se backed aur heavily cached. Eventually
  consistent theek hai.
- **Inventory Service** — per SKU/warehouse authoritative stock counts. Ek strongly
  consistent relational store se backed. Yeh woh ek jagah hai jahan hum consistency
  corners cut nahi kar sakte.
- **Cart Service** — ek fast key-value store mein ephemeral per-user cart state.
- **Order Service** — durable order records, inventory, payment, aur shipping ke
  across checkout saga ko orchestrate karta hai.
- **Payment Service** — external gateway integration (cross-reference
  `14_payment_system.md`).
- **Shipping/Fulfillment Service** — payment succeed hone ke baad warehouse/logistics
  systems ko hand off karta hai.

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

Ek purchase ka data flow: browse (Catalog Service, cache-heavy) → cart mein add karo
(Cart Service, Redis, inventory ko touch nahi karta) → checkout shuru karo (Order
Service ek saga start karta hai: TTL ke saath inventory reserve karo → payment charge
karo → inventory decrement finalize karo → shipping ko hand off karo) → order
confirmed.

## Step 4: API Design

```
GET /products/search?q=wireless+mouse&category=electronics&page=2
→ 200 { results: [{sku_id, title, price, thumbnail_url, in_stock: bool}], total, page }

GET /products/{sku_id}
→ 200 { sku_id, title, description, price, images[], attributes{}, stock_status: "in_stock"|"low_stock"|"out_of_stock" }
  # stock_status display ke liye ek cached/approximate signal hai, checkout pe use hone waali authoritative count NAHI hai

POST /cart/items
  { user_id, sku_id, quantity }
→ 200 { cart_id, items[], subtotal }
  # sirf Cart Service (Redis) mein likhta hai; Inventory Service ko touch NAHI karta

POST /checkout/start
  { cart_id, shipping_address }
→ 201 { checkout_id, reserved_items: [{sku_id, quantity, hold_expires_at}], total }
  # yahi woh moment hai jab inventory actually reserve hoti hai (Step 6 dekho)

POST /checkout/{checkout_id}/pay
  { payment_method_token, idempotency_key }
→ 200 { order_id, status: "confirmed" } | 402 { error: "payment_failed" } | 409 { error: "hold_expired" }

GET /orders/{order_id}
→ 200 { order_id, status, line_items[], tracking_info }
```

Note karo yeh deliberate asymmetry: `POST /cart/items` kabhi Inventory Service se
baat nahi karta, par `POST /checkout/start` karta hai — yahi boundary Step 6 ke
reservation pattern ki poori baat hai.

## Step 5: Data Model

**Catalog DB (document store, e.g. MongoDB, ya RDBMS + search index)** — product
attributes category ke hisaab se wildly vary karte hain (ek book ka ISBN hota hai,
ek shirt ka size/color hota hai), toh ek flexible schema ek rigid relational se
zyada fit baithta hai. Justification: read-heavy, eventual consistency ko tolerate
karta hai, denormalized documents se faayda uthaata hai jo directly map karte hain
usse jo ek product page ko chahiye.

```
Product {
  sku_id (PK), title, description, category, price,
  attributes: { ... category-specific fields ... },
  image_urls: [...],
  updated_at
}
```

**Search Index (Elasticsearch)** — catalog data ki denormalized copy, Catalog DB se
ek change stream/CDC pipeline ke through asynchronously updated (cross-reference
`13_search_and_indexing.md`). Price ya stock ke liye kabhi source of truth nahi.

**Inventory DB (relational, e.g. PostgreSQL)** — isko ACID transactions aur
row-level locking guarantees chahiye, toh catalog document-oriented hone ke bawajood
yahaan relational sahi choice hai. Do alag databases do alag consistency needs ke
liye — yeh ek deliberate, defensible split hai, design mein ek inconsistency nahi.

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

**Cart Store (Redis)** — key `cart:{user_id}` → `{sku_id: quantity}` ka ek hash,
inactivity ke, maan lo, 30 days ke TTL ke saath. Inventory ke saath koi foreign key
relationship nahi; ek cart ek wishlist-jaisa scratchpad hai, ek commitment nahi.

**Order DB (relational, scale pe user_id ya order_id range se sharded)** — orders ko
durability aur transactional integrity chahiye (ek order aur uske line items saath
likhe jaane chahiye), aur user se aur order id se query hote hain, dono cleanly
shard hote hain.

```
orders (order_id PK, user_id, status, total, created_at, shard_key)
order_items (order_id FK, sku_id, quantity, unit_price)
```

## Step 6: Deep Dive

### 6.1 Catalog vs. Inventory: Do Services, Do Consistency Models

Yeh poore system mein sabse important modeling decision hai, aur interviewers
specifically yeh sunne ke liye listen karte hain ki kya ek candidate "product data"
ko ek undifferentiated blob ke roop mein treat karta hai ya use sahi se split karta
hai.

Catalog Service jawab deta hai "yeh product kaisa dikhta hai aur roughly available
hai kya" — title, description, images, price, aur ek coarse `stock_status` badge.
Yeh har layer pe aggressively cache ho sakta hai: CDN edge, application cache, yahaan
tak ki search index khud (cross-reference `05_caching.md`). Agar cached stock badge
kehta hai "in stock" par item actually 4 seconds pehle sold out ho gaya, us staleness
ki cost hai product page pe ek mildly annoying UX moment — ek business problem nahi —
kyunki *authoritative* check baad mein, checkout pe hoti hai.

Inventory Service ek different question ka jawab deta hai: "kya main abhi, atomically,
is SKU ki ek unit actually decrement kar sakta hoon, bina do concurrent requests ko
last unit ke liye dono succeed hone diye." Yeh cache se serve nahi ho sakta, kyunki
yahaan staleness pe cache miss ka matlab hai overselling — ek promise ship karna jo
aap keep nahi kar sakte, jiska matlab hai refunds, angry customers, aur kuch
jurisdictions mein regulatory exposure. Toh checkout path pe Inventory reads hamesha
directly strongly consistent store ko hit karte hain, kabhi cache ko nahi, chahe yeh
total traffic ka ek chhota fraction ho (checkout QPS browse QPS ka ~1/100th hai, toh
strongly-consistent path ka per-request slower/expensive hona ek acceptable trade hai
kyunki yeh rare hai).

Practical consequence: yeh separate services hain, likely separate databases, alag
cadences pe updated, aur ek candidate jo dono ko ek "products" table se ek caching
strategy ke saath serve karne ki koshish karta hai woh ya toh browsing ko bahut slow
bana dega (kabhi cache na karke, stock ke baare mein safe rehne ke liye) ya checkout
ko unsafe bana dega (ek cached count trust karke).

### 6.2 Inventory Reservation: Add-to-Cart Ko Stock Kabhi Touch Kyun Nahi Karna Chahiye

Ek naive design user ke cart mein ek item add karte hi `inventory.available_count`
decrement kar deta hai. Yeh galat hai, aur iska explanation dena ek interview mein
ek strong signal hai: ek cart ek low-commitment, long-lived, often-abandoned object
hai. Users cheezein carts mein add karte hain aur ghanton, dinon, ya hamesha ke liye
gayab ho jaate hain — real e-commerce mein cart abandonment rates commonly 60-70%
hoti hain. Agar cart mein add karne se stock decrement hoti, ek popular item ka
poora inventory un logon ko "bik" sakta tha jo kabhi checkout hi nahi karte, jabki
ek actually-motivated buyer "out of stock" dekh kar chala jaata. Stock effectively
browsing behaviour se lock ho jaati, purchasing behaviour se nahi.

Correct pattern mein stock ki ek unit ke teen distinct states hain:
1. **Available** — reserve hone ke liye free.
2. **Reserved (held)** — ek checkout in progress hai; unit ek TTL ke saath set aside
   hai, `inventory_reservations` mein ek `expires_at` ke saath track ki jaati hai.
3. **Committed (sold)** — payment succeed ho gaya, reservation ek permanent decrement
   mein finalize ho jaati hai.

Reservation sirf `POST /checkout/start` pe hoti hai, cart add pe nahi. Yeh Inventory
DB ke against ek atomic operation ke roop mein implement hoti hai: `UPDATE inventory
SET available_count = available_count - qty, reserved_count = reserved_count + qty
WHERE sku_id = ? AND available_count >= qty`, ek transaction ke andar jo
`inventory_reservations` row bhi insert karta hai ek short TTL ke saath (typically
10-15 minutes, itna lamba ki payment details enter kar sakein, itna chhota ki
abandoned checkouts lambe time tak stock lock na karein). Ek background job (ya next
access pe lazy check) expired reservations ko sweep karta hai, `reserved_count` ko
wapas `available_count` mein move karta hai. Agar payment succeed hoti hai, reservation
`committed` mein transition ho jaati hai aur units simply kabhi `available_count` mein
wapas nahi jaatin — koi additional decrement ki zaroorat nahi kyunki decrement pehle
hi reservation time pe ho chuka tha; agar payment fail ho ya hold expire ho jaaye,
reservation release ho jaati hai, exactly ticket booking systems mein use hone waale
seat-hold pattern ko mirror karte hue (cross-reference `16_ticket_booking_system.md`
— yahi hold-with-TTL shape kahin bhi recur karti hai jahan ek scarce resource ko ek
commitment window chahiye).

### 6.3 Order Fulfillment ek Saga ke Roop Mein

Ek single order kam se kam teen services ko touch karta hai jo ek ACID transaction
mein participate nahi kar sakte kyunki yeh different systems hain (aur Payment ek
third-party gateway hai jise aap control nahi karte): Inventory (stock
reserve/commit karna), Payment (card charge karna), aur Shipping (ek fulfillment
request banana). Yeh **Saga pattern** (cross-reference
`09_distributed_systems_core.md` aur `14_payment_system.md`'s Sagas ke payment
flows ke treatment) ka textbook case hai: local transactions ki ek sequence, har ek
ke paas ek defined compensating action agar baad ka step fail ho.

```
1. Reserve inventory (hold, TTL)        compensate: release hold
2. Charge payment (idempotent request)  compensate: refund
3. Commit inventory decrement            compensate: restore stock
4. Create shipping request                compensate: cancel shipment
```

Agar step 2 (payment) fail ho, saga ko sirf step 1 undo karna padta hai — inventory
hold release karna — kyunki step 1 ke baad kuch chala hi nahi. Agar step 4 fail ho
(e.g., shipping service down hai), saga ko steps 3, 2, aur 1 reverse order mein
compensate karna padta hai: stock restore karo, payment refund karo, aur order ko
failed mark karo. Order Service saga orchestrator ka kaam karta hai, saga state
persist karta hai (yeh kis step pe hai) taaki agar orchestrator khud mid-saga crash
ho jaaye, yeh restart pe last known step se resume kar sake instead of ek order ko
limbo mein chhodne ke — saga state ki yeh durability compensating logic jitni hi
important hai.

### 6.4 Flash-Sale Hot-SKU Problem

Upar likha sab kuch theek kaam karta hai jab write load millions of SKUs ke across
spread ho. Yeh break down ho jaata hai ek single wildly popular SKU ke liye flash
sale ke douran, jahan `UPDATE inventory ... WHERE sku_id = X` row ek hotspot ban
jaata hai jise thousands of concurrent write attempts per second receive hote hain,
sab exact same row ko target karte hue.

Naive fix — row-level locking, jahan har request ek lock leti hai, decrement karti
hai, aur release karti hai — is load ke neeche collapse ho jaata hai. Har request lock
ke peeche queue hoti hai; thousands of concurrent attempts ke saath, har request ki
latency queue badhne ke saath balloon karti hai, aur bahut si databases timeout karna
ya same lock pe wait kar rahe connections pile up karna shuru kar deti hain, jo poore
database instance ko degrade kar sakta hai, sirf us SKU ko nahi. Ek
optimistic-concurrency alternative (count read karo, naya value compute karo, `UPDATE
... WHERE available_count = <value maine read kiya>`, conflict pe retry karo) yahaan
utna hi bura ya usse bhi bura hai: is contention level pe, almost har optimistic
write race haar jaata hai aur retry karta hai, ek retry storm produce karta hai jo
row pe effective load ko kai guna multiply kar deta hai.

Standard mitigation hai requests ko row pe directly contend karne dena bilkul band
karna, aur iske bajaye us specific hot SKU ke saare decrements ko ek single ordered
path se serialize karna:
- **Queue-based serialization**: hot SKU ke liye "buy SKU X" ki saari requests ek
  queue pe push ki jaati hain (ya sku_id se keyed ek Kafka partition,
  cross-reference `10_message_queues_and_streaming.md`), aur ek single consumer
  unhe inventory row ke against ek-ek karke process karta hai, toh koi lock
  contention nahi hai kyunki decrement ke point pe koi concurrency hi nahi hai —
  queue khud ordering impose karti hai. Requests fast enqueue hoti hain (user-facing
  "humein aapki request mil gayi" response ke liye low latency) aur actual
  decrement asynchronously hota hai, user result ke liye poll karta hai ya
  websocket push paata hai.
- **Atomic distributed counter**: alternatively, hot SKU ki available count ko Redis
  mein ek single atomic counter ke roop mein hold karo (`DECR`), jo per key bahut
  high throughput ko ek relational row ke lock contention ke under se kahin behtar
  handle karta hai, aur sirf periodically ya sale end pe relational Inventory DB ke
  saath sync back karta hai. Yeh us ek SKU ke liye ek in-memory store ko ek
  temporary source of truth ke roop mein use karne ki ek chhoti window ko spike ko
  bilkul survive karne ke against trade karta hai.

Dono tareekon mein, interviewer jo key insight sunna chahta hai: yeh ek general
inventory-scaling problem nahi hai (zyadatar SKUs kabhi contended nahi hote), yeh ek
single-hot-key problem hai, aur fix us key ke liye specific hai — aap poori
Inventory Service ko iske around redesign nahi karte, aap hot path ko special-case
karte ho (often ek scheduled sale se pehle hi "yeh SKU trending hai" detect karke aur
use queue-serialized path se pre-route karke).

### 6.5 Search/Browse Ko Transactional Path Se Decoupled Rakhna

Search index (Elasticsearch/OpenSearch, cross-reference `13_search_and_indexing.md`)
Catalog DB se ek asynchronous pipeline se populate hoti hai — Inventory ya Orders ke
against live query nahi ki jaati. Ek "wireless mice search karo" action aur ek "yeh
specific wireless mouse khareedo" action ki fundamentally different requirements
hain: search fast, relevant hona chahiye, aur kuch seconds ki staleness tolerate kar
sakta hai (ek sold-out item ka results mein ek pal ke liye dikhna ek minor UX issue
hai, jo checkout-time stock check se fix ho jaata hai); ek buy action ko sabse zyada
correctness chahiye. Inke beech ek data path share karna search ko ya toh slow bana
deta (agar yeh hamesha live inventory check karta) ya buy path ko unsafe bana deta
(agar yeh search index ke cached stock field ko trust karta) — toh yeh deliberately
separate infrastructure pe rakhe jaate hain, sirf ek async indexing pipeline se
connected (Catalog DB se CDC, ya product updates pe ek event stream).

## Step 7: Bottlenecks & Trade-offs

- **Inventory DB extreme scale pe system ka true bottleneck hai**, catalog ya
  search nahi — kyunki yeh woh ek component hai jise correctness risk kiye bina
  arbitrarily cache ya horizontally read-replicate nahi kiya ja sakta. Mitigation
  hai ise SKU (ya SKU range) se shard karna instead of warehouse ya category se,
  kyunki SKU hi reservation aur commit dono operations ke liye natural access
  pattern hai, plus outlier SKUs ke liye 6.4 waali hot-key queue-serialization
  strategy.
- **Catalog side pe cache staleness ek accepted trade-off hai, ek bug nahi** — design
  deliberately browsing (99% traffic) ke liye availability aur latency favor karta
  hai ek chhoti, bounded window ki stale display data ki cost pe, kyunki
  authoritative check hamesha narrow checkout chokepoint pe hoti hai.
- **Reservation TTL ek tuning knob hai real trade-offs ke saath**: bahut chhota, aur
  legitimate slow shoppers mid-checkout apna hold kho dete hain, conversion ko hurt
  karte hue; bahut lamba, aur abandoned checkouts high-demand periods ke douran
  stock lock kar dete hain, doosre buyers ko hurt karte hue. Practically yeh value
  aksar flash sales ke douran dynamically shorten ki jaati hai specifically kyunki
  contention high hoti hai.
- **Saga ki eventual consistency window** ka matlab hai ek order briefly "processing"
  state mein exist kar sakta hai user ko visible, saare compensating logic ke ek
  failure resolve karne se pehle — e-commerce ke liye acceptable (unlike, say, ek
  bank transfer) kyunki customer-facing status bas "processing" kehta hai aur
  seconds mein resolve ho jaata hai.
- **Cart Service data loss** ek accepted risk hai: kyunki carts Redis mein rehte hain
  ek durable relational store ke bajaye, ek Redis node failure kuch users ke liye
  in-flight cart state kho sakta hai. Yeh deliberately tolerate kiya jaata hai
  kyunki ek lost cart ek UX annoyance hai (kuch items dobara add karo), ek
  correctness ya financial problem nahi — ek trade jo sirf isliye defensible hai
  kyunki cart stage pe abhi tak kuch financially binding hua hi nahi hota.

## Follow-up Questions jo ek Interviewer Puch Sakta Hai

- **"Aap international pricing/currency aur tax calculation kaise handle karoge?"**
  Catalog Service ko ek pricing sub-component se extend karo jo read time pe
  locale/currency se price resolve kare instead of per SKU ek price store karne ke,
  aur tax calculation ko checkout mein ek dedicated step ke roop mein push karo
  (aksar ek third-party tax service ke through) kyunki yeh shipping address pe
  depend karta hai, sirf product pe nahi.
- **"Flash sale ke douran agar payment gateway slow ya down ho toh kya hota hai?"**
  Payment Service call ke around circuit breakers discuss karo, aur "payment
  initiated" ko "payment confirmed" se async webhook callbacks ke through decouple
  karne pe vichaar karo (cross-reference `14_payment_system.md`) instead of
  checkout request ko synchronously wait karte hue open rakhne ke.
- **"Order ship hone ke baad ek return/refund kaise handle karte ho?"** Explain
  karo ki yeh effectively ek naya saga hai reverse mein — inventory restock karo
  (apni khud ki validation ke saath, kyunki ek warehouse ko pehle physically item
  receive karna padta hai), ek payment refund issue karo, aur order status update
  karo — sirf original saga "undo" karna nahi, kyunki real-world time guzar chuka hai
  aur physical goods involved hain.
- **"Aap products (recommendations/'customers also bought') kaise recommend
  karoge?"** Ek separate, offline-computed recommendation service ki taraf point
  karo jo browse/purchase behaviour ke ek event stream se read kare, transactional
  path se deliberately decoupled unhi reasons ki wajah se jinse search hai — yeh ek
  read-side enhancement hai jisse checkout kabhi block ya slow nahi hona chahiye.
- **"Aap search index aur catalog DB ko sync mein kaise rakhte ho bina lag ke
  visible bugs cause kiye?"** CDC (change data capture) discuss karo har product
  pe ek monotonic sequence/version ke saath taaki indexing consumers
  out-of-order updates detect aur skip kar sakein, plus ek periodic full
  reconciliation job ek safety net ke roop mein (cross-reference
  `13_search_and_indexing.md`).
- **"Agar do warehouses dono stock dikhaate hain par combined woh ek routing bug
  ki wajah se oversell kar dein toh kya?"** Discuss karo ki `inventory`
  `(sku_id, warehouse_id)` se keyed hai precisely isliye taaki reservations
  warehouse-scoped hon, aur checkout flow ko reserve karne se pehle ek specific
  warehouse (nearest/available) choose karna padta hai — ek global "total stock"
  number sirf ek display aggregate hai, kabhi reservation authorize karne ke liye
  use nahi hota.
