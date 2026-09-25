# Design a Movie/Event Ticket Booking System

## Problem Statement

"Design karo ek ticket booking system jaise BookMyShow ya Ticketmaster. Users
browse kar paayein events/movies, ek specific showtime ke liye seat map dekh
paayein, seats select karein, aur payment karke booking confirm karein. Hard part
browsing nahi hai — hard part yeh hai ki jab ek popular event on-sale hota hai, to
thousands of log same handful of achhi seats grab karne ki koshish karte hain
seconds ke andar, aur do logon ko kabhi bhi same seat ke liye pay nahi karna chahiye.
Mujhe walk through karo ki tum yeh design kaise banaoge taaki woh exact moment of
contention mein bhi tik sake."

## Step 1: Requirements Clarify Karo

**Functional Requirements**
- Events/movies/showtimes browse karna, venue aur showtime details dekhna.
- Ek given showtime ke liye seat map dekhna, jisme available/held/booked seats
  dikhein.
- Ek ya multiple seats select karna aur unhe temporarily hold karna jab tak payment
  complete na ho.
- Pay karke booking confirm karna; ek ticket/confirmation receive karna.
- Agar payment time pe complete na ho to seats automatically release ho jayein.
- Existing bookings view/cancel kar paana.

**Non-Functional Requirements**
- Scale target: ek large ticketing platform, maan lo platform par kisi bhi time 500
  concurrent high-demand on-sales chal rahe hain, aur sabse bada single on-sale
  ek event pe up to 200,000 concurrent users la sakta hai jinke target mein, kaho,
  20,000 seats hon.
- **Sabse zyada important: correctness**: do users ne kabhi bhi same seat ke liye
  successfully pay nahi karna chahiye. Yeh ek non-negotiable requirement hai.
- Seat-map viewing fast honi chahiye (200ms se kam) heavy read load ke neeche bhi —
  zyadatar log jo seat map dekh rahe hain wo sirf browse kar rahe hain, buy karne
  wale nahi hain.
- Seat selection/hold near-instant hona chahiye (sub-500ms) taaki live on-sale ke
  dauraan UI responsive feel ho.
- System ko ek traffic stampede survive karna chahiye exactly usi moment jab
  tickets on-sale jaate hain, bina seat-selection requests ke backend ko overwhelm
  kiye.
- Availability trade-off: extreme contention ke dauraan, yeh acceptable hai ki kuch
  users ko wait karwaya jaaye (ek queue mein) instead of sabko andar aane dena aur
  risk lena ki seat-selection path collapse ho jaaye ya, aur bura, ek seat double-book
  ho jaaye.
- Payment idempotent hona chahiye — network issues ki wajah se retried requests
  double-charge ya double-booking nahi karni chahiye.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- Platform-wide: 10,000 events/venues kisi bhi time active hain, average 2,000
  seats per venue → 20M total seats track ho rahi hain platform pe kisi bhi given
  moment mein (ek bounded, modest number overall).
- Normal traffic: 1M seat-map views/day platform-wide, saare events mein spread
  hue → low tens ka QPS average, kuch bhi remarkable nahi.
- Flash on-sale scenario (jo case actually matter karta hai): ek single event
  jisme 20,000 seats hain on-sale jaata hai, aur 200,000 users seat-selection page
  ko first 60 seconds ke andar hit karte hain.

**QPS during an on-sale spike**
- 200,000 requests / 60s ≈ **3,300 QPS** "view/select seat" endpoint pe hit kar
  rahe hain ek single event ke liye, ek aise system mein jiska steady-state QPS
  usi event ke liye normally near-zero ho sakta hai.
- In 200,000 users mein se, sirf 20,000 seats exist karti hain — to best case
  mein sirf 10% arriving users succeed kar sakte hain; 90% ko "sold out" ya "still
  waiting" bataya jaana chahiye bina unhe kabhi seat state corrupt karne diye.
- Agar naively seat-hold write path pe direct hit hone diya jaaye, to yeh ban jaata
  hai **3,300+ concurrent attempts per second ek 20,000-row seat table ke against,
  ek event ke liye** — absolute row count mein chhota, lekin write contention ke
  hisaab se massive kyunki yeh ek tiny keyspace pe concentrated hai, aur yehi wajah
  hai ki ek waiting-room admission mechanism (Step 6) zaroori hai, na ki ek bigger
  database.

**Storage**
- Seat state: 20M seats platform-wide × ~200 bytes (seat_id, event_id, status,
  held_by, hold_expires_at) ≈ 4GB — trivially chhota; yeh storage problem nahi
  hai, yeh ek concurrency/contention problem hai.
- Bookings: maan lo 5M bookings/month × 500 bytes ≈ 2.5GB/month, ~90GB 3 saalon
  mein — ek standard relational database time-based partitioning ke saath easily
  handle kar sakta hai.

**Bandwidth**
- Seat-map view payload ~20KB (SVG/JSON seat layout). 3,300 QPS peak par yeh ~66MB/s
  ban jaata hai ek hot event ke liye — comfortably ek cache/CDN layer se serve ho
  sakta hai instead of har request pe fresh compute karne ke.

## Step 3: High-Level Design

Ek generic e-commerce system ke against distinguishing components: ek **Waiting
Room service** jo high-demand on-sales ke dauraan entry gate karti hai, aur ek
**Seat Locking service** jo individual seats pe short-lived holds manage karti
hai, jo booking/payment flow ke saamne baithi hoti hai.

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

Flow ek live on-sale ke dauraan: user event page hit karta hai → **Waiting Room**
ke through route hota hai jo users ko ek aisi rate pe admit karti hai jo backend
sustain kar sake → admitted user seat map dekhta hai (cache se read hota hai, thoda
stale ho sakta hai) → user ek seat select karta hai → **Seat Locking Service** ek
atomic hold attempt karti hai, real seat state ke against re-validate karte hue
(cached view ko kabhi trust nahi karte) → success pe, user ke paas N minutes hote
hain pay karne ke → payment succeed hoti hai → hold ek permanent booking mein
convert ho jaati hai; payment fail ho ya time out ho jaaye → hold release ho
jaati hai, seat phir se available ho jaati hai.

## Step 4: API Design

```
GET /events/{event_id}/showtimes
→ 200 { showtimes: [{showtime_id, venue, start_time, price_tiers}] }

GET /showtimes/{showtime_id}/seatmap
→ 200 { seats: [{seat_id, section, row, number, status: "available"|"held"|"booked", price}] }
  # cache se serve hota hai; yahan status ek display hint hai, hold attempt pe re-validate hota hai

POST /waitingroom/{event_id}/join     (sirf tabhi invoke hota hai jab event high-demand flag ho)
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

Waiting room ka `queue_token` `POST /seats/hold` pe required hai flagged
high-demand events ke liye specifically taaki hold-write path sirf admission-
controlled rate pe hi reach ho, raw stampede rate pe nahi.

## Step 5: Data Model

**Seat DB (relational, jaise PostgreSQL)** — seat state ko atomic compare-and-swap
semantics aur strong consistency chahiye; ek relational database row-level
constraints ke saath yahan natural fit hai, aur per-event row count (thousands,
millions nahi) ka matlab hai ki yeh kabhi bhi single event ke andar sharding nahi
maangta — yeh point 6.3 mein aur develop kiya gaya hai.

```
seats (
  seat_id PK, showtime_id, section, row, number, price_tier,
  status ENUM('available','held','booked'),
  held_by_user_id NULLABLE,
  hold_expires_at TIMESTAMP NULLABLE,
  version INT   -- optimistic-lock / CAS updates ke liye
)

bookings (booking_id PK, user_id, showtime_id, seat_ids[], status, created_at)
```

**Seat Hold Cache (Redis)** — ek fast-path lock coordinator ke roop mein use hota
hai: key `hold:{seat_id}` value `{user_id, hold_id}` ke saath aur ek native TTL
(`SET ... NX EX 600`). Yeh ek atomic, self-expiring lock primitive deta hai bina
common case ke liye background sweep job ki zaroorat ke — Redis khud key expire
kar deta hai. Relational DB row abhi bhi durable source of truth hai jiske against
yeh reconcile hoti hai, lekin Redis hi wo cheez hai jo concurrent hold attempts ke
burst ko cheaply absorb karta hai.

**Waiting Room Queue (Redis ya ek dedicated queue)** — ek ordered structure (jaise
ek Redis sorted set arrival time se scored, ya ek Kafka partition) per high-demand
event_id ke liye, jo seat-selection flow mein bounded number of users per
second/interval admit karta hai.

**Booking DB** — standard relational table durable, paid bookings ke liye;
partitioned by showtime date scale pe kyunki purani showtimes rarely query hoti
hain jab event khatam ho chuka ho.

Kyun relational specifically seats ke liye, ek general e-commerce system ke
catalog ke document-store choice ke unlike: seat state chhota hai, shape mein
uniform hai (koi category-specific variability nahi), aur usme har operation ko
ek atomic conditional update chahiye — exactly wahi jiske liye relational
row-locking/CAS aur ACID transactions bane hain.

## Step 6: Deep Dive

### 6.1 Seat Locking: Hold-with-TTL, Not Checkout Ke Across Pessimistic Locking

Yeh poore design ka centerpiece hai. Naive approach — jaise hi user seat select
kare, seat pe ek row-level database lock lena aur usko tab tak hold rakhna jab tak
wo payment details enter na kar le — ek disaster hai: payment entry ek slow,
user-paced, unreliable step hoti hai (log apna card fumble karte hain, distract ho
jaate hain, connectivity lose kar dete hain) jo 10 seconds se lekar several
minutes tak le sakti hai. Ek lock jo poore is window mein hold rehta hai iska
matlab hai ki us lock ko backing karne wala database connection/transaction poora
time open rehna chahiye, jo handful concurrent checkouts ke aage scale hi nahi
karta, thousands during an on-sale to door ki baat hai, aur ek single slow/
abandoning user indefinitely ek seat block kar sakta hai agar unka connection
cleanly release kiye bina hi mar jaaye.

Correct pattern "seat claim karna" ko "database lock hold karna" se decouple
karta hai ek **hold with a TTL** use karke instead of ek unbounded duration wale
lock ke:

1. Jab ek user seat select karta hai, system ek atomic conditional write perform
   karta hai: `SET hold:{seat_id} = {user_id} NX EX 600` Redis mein (NX = sirf
   set karo agar already held na ho; EX = 600 seconds mein expire karo), ya
   equivalently SQL mein, `UPDATE seats SET status='held', held_by_user_id=?,
   hold_expires_at=NOW()+interval '10 min', version=version+1 WHERE seat_id=? AND
   status='available' AND version=?` — ek compare-and-swap jo `version` column
   use karta hai taaki same seat pe ek concurrent attempt WHERE clause fail kar de
   aur zero rows update ho, jise application "seat unavailable" ke roop mein
   padhti hai.
2. Yeh write instantaneous hoti hai — koi lock user ka wait karte hue open nahi
   rehta. Ab user ke paas 10 minutes hote hain payment complete karne ke liye;
   agar wo kar lete hain to hold permanently `status='booked'` mein convert ho
   jaata hai. Agar nahi karte, to TTL simply expire ho jaata hai (Redis yeh
   natively karta hai; DB-only version ko ek lazy check-on-read ya ek periodic
   sweep job chahiye jo expired holds ko wapas `available` mein flip kare).
3. Crucially, hold attempt hamesha write time pe live seat state ke against
   re-validate hota hai — yeh kabhi bhi user ke browser mein cached kya tha, us
   par trust nahi karta jo seat-map view se aaya ho. Do users dono ek seat-map
   dekh sakte hain jisme seat 12B "available" dikh rahi ho (kyunki jab wo cached
   view render hui thi tab woh available thi hi); unme se sirf ek user ka `POST
   /seats/hold` call atomic CAS jeetega, aur doosre ko ek 409 milega jo client ko
   seat map refresh karne ko kahega.

Yeh wahi hold-with-TTL shape hai jo ek general e-commerce checkout mein inventory
reservation ke liye use hoti hai (cross-reference `15_ecommerce_platform.md`'s
Step 6.2) — underlying problem (ek scarce resource ko ek slow user-paced step ke
across lock mat karo) wahin recur hoti hai jahan bhi ek system kuch finite bechta
hai.

### 6.2 On-Sale Stampede Ko Survive Karna: Ek Virtual Waiting Room

Hold-with-TTL correctness solve karta hai ek baar jab request seat-locking path
tak pahunch jaaye, lekin yeh arrival-rate problem solve nahi karta: agar 200,000
users sab ke sab `POST /seats/hold` (ya sirf seat-map page bhi) same few seconds
ke andar hit kar dein, to backend request volume se hi overwhelm ho sakta hai —
connection pools exhaust ho jaate hain, cache tier hammered ho jaata hai, aur
legitimate requests time out hone lagti hain — chahe locking logic khud correct
ho ya na ho, usse independent.

Mitigation ek **virtual waiting room** hai, conceptually ek admission-controlled
queue jo seat-selection flow ke saamne baithti hai, jo `02_rate_limiter.md` ke
same token-bucket/leaky-bucket rate-limiting ideas apply karti hai lekin *user
admission* pe, na ki raw API request throttling pe. Jab ek event high-demand flag
ho jaata hai (chahe ek known bade on-sale ke liye pre-configured ho, ya
dynamically detect ho ek incoming traffic ke spike se), arriving users ko ek
`queue_token` issue kiya jaata hai aur ek ordered queue mein place kiya jaata hai
(ek Redis sorted set arrival timestamp se scored is scale pe achha kaam karta
hai, ya ek Kafka partition jo fixed rate pe consume ho). Ek background admitter
queue se users pull karta hai aur unhe "admitted" mark karta hai ek aisi rate pe
jo seat-locking backend sustain kar sake — for example, har few seconds mein 500
users admit karna instead of sabke 200,000 ko ek saath andar aane dena. Admitted
users ko live seat map aur hold endpoint ka access mil jaata hai; queued users ko
ek "aap number 4,213 ho, estimated wait 2 minutes" screen dikhti hai jo `GET
/waitingroom/{event_id}/status` poll karti rehti hai.

Yeh deliberately strict fairness/speed trade karta hai system stability ke liye:
kuch users wait karte hain even though seats bachi hui hain, kyunki alternative —
ek hot, tiny keyspace pe unbounded concurrent access — poore seat-locking path ke
sabke liye degrade hone ka risk leta hai, un users ke liye bhi jo succeed kar
sakte the.

### 6.3 Ek Bounded Resource Right Answer Change Kar Deta Hai

Yeh explicitly state karna zaroori hai ki is system ka core hard problem ek zyada
centralized approach se solvable kyun hai, unlike, kaho, ek distributed key-value
store ke writes ka approach (cross-reference
`17_distributed_key_value_store.md`): kisi bhi single event ke liye seat map ek
chhota, **bounded** resource hai — kuch hazaar seats, jo event schedule hote hi
known aur fixed ho jaati hain. Yeh most large-scale systems ke unlike hai jahan
keyspace (users, products, messages) unbounded hoti hai aur storage aur load dono
reasons ke liye many nodes/shards mein partition karni padti hai.

Kyunki kisi bhi ek event ke liye contended resource comfortably ek single database
instance pe fit ho jaati hai (ya ek single Redis instance ki memory mein bhi),
design ek zyada centralized, strongly consistent locking strategy per event
afford kar sakta hai jo ek globally sharded system ke liye viable na hoti.
Cross-shard transactions, seats ki consistent hashing nodes ke across, ya seat
state ke liye quorum reads ke baare mein reason karne ki zaroorat nahi — ek
event ke saare seats ek authoritative lock coordinator ke peeche reh sakte hain.
Trade-off yeh hai ki yeh centralization ek different scale pe wrong choice hoti
(agar ek single "resource" billions of keys hota, to sabkuch ek coordinator ke
through force karna ek bottleneck ban jaata) — lekin yeh recognize karna ki seat
maps small-N-per-event hain aur large-N-only-in-aggregate-across-events hain, yehi
per-event centralization ko justify karta hai: shard by event_id (har event ka
seat map independently hosted/cached/locked hai), seat_id globally se nahi,
kyunki different events ki seats kabhi ek doosre se contend nahi karti.

### 6.4 Payment Integration Aur Failure Pe Compensating Action

Booking confirmation e-commerce checkout ke same Saga shape follow karta hai
(cross-reference `14_payment_system.md`'s idempotency aur Saga discussion): seat
hold karo (already 6.1 mein ho chuka) → payment charge karo → booking confirm
karo. `POST /bookings/confirm` ko ek `idempotency_key` chahiye precisely kyunki
payment gateway calls client dwara timeout ke baad retry ho sakti hain bina gateway
ka original response pata hue — Payment Service ko ek repeated idempotency key
recognize karna hoga aur original result return karna hoga instead of dobara
charge karne ke.

Agar payment fail ho jaaye (declined card, gateway timeout, gateway error) to
compensating action simply hai **seat hold ko jaldi release karna** instead of
uske TTL ka wait karne ke — `status` ko turant wapas `available` flip karo (ya
Redis `hold:{seat_id}` key delete karo) taaki seat jaldi se jaldi doosre
waiting-room-admitted users ke liye available ho jaaye, kyunki live on-sale ke
dauraan har second jo ek seat needlessly held rehti hai wo lost throughput hai.
Agar payment gateway call khud ambiguously time out ho jaaye (unclear ki charge
succeed hua ki nahi), to safe move hai hold ko turant release *na* karna — usko
held rakho jab tak ek reconciliation check gateway ke against ambiguity resolve
na kar de, taaki seat kisi doosre insaan ko na bik jaaye jab first person ka
payment abhi bhi land kar sakta ho.

### 6.5 Read-Heavy Viewing vs. Write-Critical Selection

Seat map actually seats select hone se kahin zyada bar view hoti hai — event page
ke zyadatar visitors prices ya availability check kar rahe hote hain bina buy
kiye. Yeh read path aggressively cache hoti hai: seat-map response Redis se ya
CDN-edge par bhi cache ho sakta hai ek short TTL ke saath (kuch seconds), jo ek
background process dwara refresh ho ya booking events pe invalidate ho, kyunki
ek thoda stale "available" badge ek aisi seat pe jo already book ho chuki hai,
sirf ek momentary UX hiccup cost karta hai us moment jab user actually usse
select karne ki koshish karta hai.

Seat-*selection* path iske bilkul opposite hai: yeh kabhi bhi usi cache se serve
nahi honi chahiye. `POST /seats/hold` hamesha apna atomic CAS live source of truth
ke against perform karta hai (Redis hold-key ya version check wali DB row),
cached seat-map snapshot ke against kabhi nahi, precisely kyunki yeh wo ek
operation hai jahan staleness directly correctness violation mein translate hoti
hai jise rokne ke liye poora system exist karta hai (double-booking). Yeh
read/write asymmetry — display ke liye aggressively cache karo, actual write ke
liye hamesha transactionally re-validate karo — wahi principle hai jo e-commerce
design mein inventory `stock_status` display versus authoritative decrement ke
liye use hota hai (cross-reference `15_ecommerce_platform.md` Step 6.1), yahan
SKUs ki jagah seats pe applied.

## Step 7: Bottlenecks & Trade-offs

- **Ek single hot event ke liye seat-locking coordinator sabse sharp bottleneck
  hai**, precisely kyunki 6.3 isko centralize karne ka argument deta hai —
  mitigation waiting room (6.2) hai jo us coordinator mein arrival rate control
  karti hai, coordinator ko khud distribute karna nahi, kyunki ek few-thousand-row
  keyspace ko distribute karna cross-node coordination overhead add karta bina
  kisi real capacity benefit ke.
- **Waiting room fairness vs. throughput**: ek strict FIFO queue fair hai lekin
  capacity ko under-utilize kar sakta hai agar early-admitted users stall ho
  jaayein (e.g., ek hold complete karne se pehle abandon kar dein); many real
  systems strictly available seats se thoda zyada users admit karte hain, hold
  attempts pe higher 409-rate accept karke, pipeline ko full rakhne ke exchange
  mein — better throughput ke liye kuch wasted client-side attempts ka ek
  deliberate trade.
- **TTL tuning ek direct conversion lever hai**: shorter holds contested seats ko
  jaldi free karti hain (achha on-sale ke dauraan) lekin legitimate slow payers
  apni seat lose kar sakte hain (bura conversion/trust ke liye); many platforms
  hold TTL ko specifically shorten karte hain flagged high-demand events ke
  dauraan aur ek longer, zyada forgiving TTL use karte hain ordinary
  low-contention bookings ke liye.
- **Seat map pe cache staleness window** short rakhna hi hoga (seconds, minutes
  nahi) precisely kyunki, general product catalog ke unlike, yahan users actively
  ek real-time decision le rahe hote hain ek chhote se set ke individually
  distinguishable items mein se (yeh exact seat, na ki "a" unit of a SKU) — stale
  seat maps zyada visibly aur immediately frustrating hoti hain ek stale product
  page se.
- **Ambiguous payment gateway failures ke baad reconciliation** (6.4) kisi bhi
  real system mein genuinely ek unsolved-feeling edge case hai: manual/automated
  reconciliation pending ek seat ko indefinitely hold rakhna usse premature
  release karne se safer hai, lekin exactly highest-demand moments pe inventory
  tie up kar deta hai — zyadatar platforms isko ek secondary, longer timeout aur
  ek operational alert ke saath bound karte hain, isko truly indefinite chhodne ke
  bajaye.

## Follow-up Questions Jo Ek Interviewer Puuch Sakta Hai

- **"Group bookings kaise handle karoge jahan ek user adjacent seats chahta hai,
  aur desired seats mein se ek mid-selection le li jaati hai?"** Discuss karo ki
  saari requested seats ko ek atomic multi-key operation mein hold karna (Redis
  mein ek Lua script, ya ek single DB transaction jo saari seat rows cover kare)
  taaki hold either poore group ke liye succeed ho ya poori tarah fail ho, instead
  of partially seats hold karke user ko ek broken selection ke saath chhod dena.
- **"Agar waiting room khud hi ek bottleneck ban jaaye 200,000 concurrent joins ke
  neeche?"** Point out karo ki waiting room ka apna write path (tokens issue
  karna, position track karna) seat-locking path se kahin zyada cheap hai — yeh
  ek simple counter/queue insert hai, ek conditional multi-row update nahi — aur
  horizontally scale ho sakta hai ya edge/CDN-adjacent layer se bhi serve ho sakta
  hai kyunki token issuance ko strong global ordering nahi chahiye, sirf
  monotonic-enough fairness chahiye.
- **"Bots/scalpers ko automated requests ke through mass-holding seats se kaise
  rokoge?"** Discuss karo rate limiting per user/IP waiting-room admission step
  pe (cross-reference `02_rate_limiter.md`), CAPTCHA ya proof-of-work challenges
  admission se pehle, aur ek user account ke liye concurrent holds ki number
  capping.
- **"Ek venue-wide event cancellation kaise handle karoge, jisme ek saath
  thousands of bookings refund aur release karni ho?"** Isko ek bulk
  compensating-action job ki tarah treat karo: event ke bookings ko iterate karo,
  Payment Service ke through refunds trigger karo (idempotent, isliye partial
  failure pe retry karna safe hai), aur bookings ko cancelled mark karo — yeh
  explicitly ek batch/async job hai, ek synchronous user-facing flow nahi.
- **"Tickets already sold hone ke baad accessibility ya partial venue closures ke
  liye seat-map layout changes ka kya?"** Isko ek manual reconciliation flow
  chahiye normal hold/book path se bahar — affected bookings ko explicit
  reassignment ya refund chahiye, kyunki automated seat-locking system ek fixed
  seat map assume karta hai aur already-sold seats ko silently remap karne ke
  liye designed nahi hai.
- **"Isse dynamic pricing (demand ke basis pe price changes) support karne ke liye
  kaise extend karoge?"** Note karo ki price hold time pe capture aur lock hona
  chahiye (`seats` row pe ya hold record pe khud stored), payment confirmation pe
  re-evaluate nahi hona chahiye, taaki hold aur payment ke beech ek demand-driven
  price increase silently yeh na badal de ki user se kitna charge hua.
