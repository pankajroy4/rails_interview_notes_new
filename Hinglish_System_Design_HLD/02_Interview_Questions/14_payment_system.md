# Design a Payment / Transaction Processing System

## Problem Statement

"Ek payment processing system design karo — socho ek checkout button ke peeche ka
backend jo user ke card se charge karta hai, account balances update karta hai, aur
transaction record karta hai. Isko ek external payment processor (jaise Stripe ya ek
card network) ke saath baat karni hai, aur yeh bilkul bhi ek customer ko double-charge
nahi kar sakta ya money ka track nahi kho sakta, chahe networks fail ho jaayein aur
requests retry ho jaayein. Mujhe walk through karo ki tum yeh kaise design karoge."

Yeh iss set ka woh ek system-design question hai jahan primary constraint throughput ya
latency nahi hai — yeh hai **failure ke under correctness**. Ek ride-sharing app ka
GPS ping miss hona ek shrug hai; ek payment system ka customer ko double-charge karna ya
silently ek transaction kho dena ek serious, possibly legal, failure hai. Yahaan har
design decision usi ki service mein hai.

## Step 1: Requirements Clarify Karna

**Functional Requirements**
- Users ek payment initiate kar sakte hain (card charge karna, stored balance debit
  karna, accounts ke beech transfer karna).
- System ek external payment processor/card network ke saath integrate hota hai actual
  mein platform ke andar/bahar money move karne ke liye.
- Users aur merchants transaction history aur current balance dekh sakte hain.
- Refunds aur partial refunds support hote hain.
- System multiple currencies support karta hai (kam se kam: correctly store aur
  display karna; poori FX conversion scope se bahar rakhi ja sakti hai jab tak na
  poocha jaaye).
- Failed payments safely retry hote hain, duplicate charges ke risk ke bina.
- System financial reconciliation aur dispute handling (chargebacks) ke liye suitable
  auditable records produce karta hai.

**Non-Functional Requirements**
- **Correctness over latency**: agar ek payment confirmation ek extra second le le
  correctness guarantee karne ke liye, toh acceptable hai; money-moving operations pe
  correctness ko speed ke liye trade karna kabhi acceptable nahi hai.
- **Consistency**: balance-affecting writes strongly consistent honi chahiye
  (`cap_theorem_and_consistency.md` ke according) — yeh iss poore question bank ke
  rare subsystems mein se ek hai jahan "kya aap yahaan eventual consistency accept
  karoge?" ka jawab ek unambiguous no hai, ledger ke liye. Peripheral concerns (ek
  "payment received" notification email bhejna) eventually consistent ho sakte hain.
- **Idempotency**: koi bhi payment request pehle successful attempt ke outcome se aage
  kuch bhi change kiye bina, arbitrary number of times safely retryable honi chahiye.
- **Durability**: ek committed transaction record kabhi lost nahi hona chahiye — yeh
  ek regulatory aur trust requirement hai, sirf ek engineering niceties nahi.
- **Auditability**: har balance change ek immutable history se reconstructable hona
  chahiye, sirf ek final number mein reflect hona kaafi nahi hai.
- **Scale**: assume karo ek mid-to-large payments platform — 10 million
  transactions/day, sales events ke around sharp peaks ke saath (e.g., ek flash sale
  ke douran 10-20x normal peak).
- **Availability**: read paths (balance/history dekhna) ke liye availability favor karo
  par write path ke liye correctness-first, availability-second — ek payment system
  jo briefly unavailable hai recoverable hai; ek jo available hai par wrong hai woh
  nahi.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- Ek average din 10,000,000 transactions/day.
- Ek flash-sale/holiday event ke douran 10x peak multiplier, kuch hours tak sustained.
- Har transaction touch karta hai: 1 idempotency-key check, 1 external processor call,
  kam se kam 2 ledger entries (ek debit aur ek credit — Step 6.2 dekho), 1 transaction
  summary record.

**Transaction QPS**
```
10,000,000 / 86,400 sec ≈ 116 transactions/sec average
Peak event: 10x → ~1,160 transactions/sec sustained during the event window
```
Yeh raw QPS terms mein modest hai (kisi social feed ya location-tracking system ke
comparison mein) — yahaan mushkil volume nahi hai, mushkil yeh hai ki peak pe har ek
in ~1,200 operations/sec ko exactly-once aur durably correct hona chahiye, uss
"eventually consistent, mostly right" approach ke liye zero tolerance ke saath jo
kahin aur acceptable hai.

**Ledger row growth**
```
Double-entry bookkeeping (Step 6.2): each transaction writes at least 2 ledger rows (one debit, one credit)
10,000,000 transactions/day x 2 rows x ~200 bytes/row ≈ 4 GB/day ≈ 1.5 TB/year
```
Absolute terms mein chhota — yeh table kabhi storage bottleneck nahi banega — par yeh
append-only hai aur design se hamesha ke liye badhta hai (Step 6.2 explain karta hai
ki rows kabhi mutate ya delete kyun nahi hoti), toh long-term query performance ke
liye ek partitioning strategy chahiye (e.g., month se) chahe total volume unremarkable
ho.

**Idempotency key storage**
```
10,000,000 keys/day x ~150 bytes (key, request hash, result, status, timestamp) ≈ 1.5 GB/day
Retained for a bounded window (e.g., 7-30 days, matching realistic client retry windows) rather than forever
= well within reach of a fast key-value store with a TTL, not a growing-forever table
```

**External processor call latency**
Ek card-network/processor round trip typically 200ms-2s leti hai. 1,160 tx/sec peak
pe, agar calls fully serialized hoti toh yeh ek severe bottleneck hota; system ko
inhe high concurrency ke saath issue karna chahiye (ek saath bahut saari in-flight
requests, har ek ek independent async operation) instead of queue ko ek-ek karke
process karna — external call per-transaction latency ka long pole hai, toh
architecture ko iske upar serialization add nahi karni chahiye.

**Reconciliation batch volume**
```
A nightly reconciliation job compares ~10,000,000 internal records against the processor's
equivalent daily settlement report — a bulk diff job, not a request-latency-sensitive
path, so it can run as an offline batch process rather than needing real-time infrastructure.
```

## Step 3: High-Level Design

**Core components**
- **Payment API / Gateway** — payment requests receive karta hai, auth enforce karta
  hai, idempotency-key handling ka entry point hai.
- **Idempotency Service** — ek fast key-value store (idempotency key → status/result)
  jo kisi bhi processing shuru hone se pehle check hota hai, retries detect aur
  short-circuit karne ke liye.
- **Payment Orchestration Service** — multi-step payment flow (external processor
  charge karna, ledger update karna, user notify karna) ko ek Saga ke roop mein
  coordinate karta hai (Step 6.4), partial failure pe compensating actions samet.
- **Ledger Service** — account balances ka source of truth, ek append-only
  double-entry ledger ke roop mein implement kiya gaya (Step 6.2) ek strongly
  consistent relational database se backed.
- **External Payment Processor** — ek third party (card network/PSP) jo actually
  money move karta hai; ek external dependency ke roop mein treat kiya jata hai jise
  system control nahi karta, apne database ke saath transactional nahi bana sakta, aur
  assume karna padta hai ki yeh fail ya ambiguously timeout kar sakta hai.
- **Notification Service** — user ko payment success/failure ke baare mein inform
  karta hai; flow ka explicitly woh ek eventually-consistent, best-effort piece hai.
- **Reconciliation Service** — ek offline batch job jo internal ledger state ko
  processor ke settlement reports (Step 6.5) ke saath compare karta hai.

**Ek payment ka data flow**
1. Client ek client-generated idempotency key ke saath ek payment request submit karta
   hai.
2. Payment API Idempotency Service check karta hai: agar yeh key already process ho
   chuki hai, previously stored result immediately return karo — koi reprocessing
   nahi, duplicate charge ka koi risk nahi.
3. Agar naya hai, Payment Orchestration Service Saga start karta hai: external
   processor ko call karke card charge karo.
4. Processor success pe, double-entry ledger rows likho (user ke payment method ko
   debit karo / platform ke receivable ko credit karo, actual accounting flow ke
   according) ek single local ACID transaction ke andar.
5. Idempotency key ka result complete mark karo aur outcome cache karo.
6. User ko asynchronously notify karo (best-effort, eventually consistent).
7. Agar processor charge ke baad koi bhi step fail ho (e.g., ledger write fail ho
   jaaye), Saga ka compensating action fire hota hai — e.g., processor ko ek
   refund/void call issue karo — instead of system ko aisi state mein chhodna jahan
   money externally move ho gaya par internal ledger disagree kare.
8. Raat ko, Reconciliation Service processor ki settlement report pull karta hai aur
   use internal ledger ke saath diff karta hai, kisi bhi discrepancy ko manual/automated
   resolution ke liye flag karta hai.

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

**`POST /v1/payments`** — ek payment initiate karo; idempotency key caller ki
responsibility hai ki har logical attempt ke liye ek baar generate ho aur retry pe
reuse ho.
```json
Request:  { "idempotency_key": "ik_a1b2c3", "amount_cents": 4999, "currency": "USD", "payment_method_id": "pm_123", "user_id": "u_789" }
Response: { "payment_id": "pay_555", "status": "succeeded", "amount_cents": 4999 }
```

**`GET /v1/payments/{payment_id}`** — ek specific payment ka status check karo.
```json
Response: { "payment_id": "pay_555", "status": "succeeded", "created_at": 1699999999 }
```

**`POST /v1/refunds`** — ek full ya partial refund issue karo, yeh khud bhi idempotent
hai.
```json
Request:  { "idempotency_key": "ik_r9x8", "payment_id": "pay_555", "amount_cents": 2000 }
Response: { "refund_id": "ref_222", "status": "succeeded" }
```

**`GET /v1/accounts/{account_id}/balance`** — current balance, ledger se computed
(Step 6.2).
```json
Response: { "account_id": "acc_1", "balance_cents": 152340, "currency": "USD", "as_of": 1699999999 }
```

**`GET /v1/accounts/{account_id}/ledger?from=...&to=...`** — paginated transaction
history / audit trail.
```json
Response: { "entries": [ {"entry_id":"le_1","type":"debit","amount_cents":4999,"related_payment":"pay_555","ts":1699999999} ] }
```

**`POST /internal/reconciliation/run`** — nightly reconciliation batch trigger karo
(ya uska report do); internal/ops-facing, customer-facing nahi.
```json
Response: { "run_id": "recon_2026_09_13", "discrepancies_found": 3, "status": "completed" }
```

## Step 5: Data Model

**Ledger — relational (SQL) database, strongly consistent, `databases_fundamentals.md`
ke according**
Yeh iss poore question bank mein sabse kam negotiable database choice hai: ledger ko
multi-row ACID transactions chahiye (ek debit aur credit ko saath commit hona chahiye
ya bilkul nahi), strict consistency chahiye (`cap_theorem_and_consistency.md` ke
according, yeh write path pe C ko A ke upar choose karne ka case hai), aur relational
integrity constraints chahiye (foreign keys jo entries ko accounts aur transactions se
tie karti hain). Ek NoSQL store jo availability/eventual consistency ke liye optimized
hai, us ek property ko directly undermine karega jise yeh subsystem compromise nahi
kar sakta.
```sql
CREATE TABLE accounts (
  id            BIGINT PRIMARY KEY,
  owner_id      BIGINT NOT NULL,
  account_type  VARCHAR(20),      -- 'user_wallet', 'platform_receivable', 'platform_payable', ...
  currency      VARCHAR(3)
);

CREATE TABLE ledger_entries (
  id            BIGINT PRIMARY KEY,
  transaction_id BIGINT NOT NULL,   -- ek logical transaction ki debit+credit pair (aur kisi bhi related entries) ko group karta hai
  account_id    BIGINT NOT NULL,
  entry_type    VARCHAR(6) NOT NULL,  -- 'debit' ya 'credit'
  amount_cents  BIGINT NOT NULL,      -- integer, smallest currency unit -- kabhi ek float nahi
  currency      VARCHAR(3) NOT NULL,
  created_at    TIMESTAMP NOT NULL,
  INDEX idx_account (account_id, created_at),
  INDEX idx_txn (transaction_id)
);
-- ledger_entries rows insert ke baad KABHI update ya delete nahi hoti -- Step 6.2 dekho
```
Ek account ka current balance us account ke liye `SUM(credits) - SUM(debits)` ke roop
mein derive hota hai (ya read performance ke liye ek periodically-checkpointed running
total ke roop mein maintain hota hai, summed entries ke against reconciled — kabhi bhi
sirf stored truth ke roop mein nahi).

**Idempotency records — fast key-value store (Redis ya isi tarah ka koi low-latency
store), `databases_fundamentals.md` ke NoSQL section ke according**
Yeh isliye chosen hai kyunki yeh ek pure key-lookup access pattern hai
(idempotency_key → status/result), har single payment request ke hot path pe check
hona zaroori hai toh lookup latency relational query flexibility se zyada matter
karti hai, aur iski ek natural bounded retention window (TTL) hoti hai, ledger ke
unlike jise indefinitely retain karna padta hai.
```
Key:   idempotency:{key}
Value: { "status": "in_progress" | "completed" | "failed", "payment_id": "pay_555", "result_snapshot": {...}, "locked_at": ts }
TTL:   e.g., 30 days
```

**Transaction summary records — relational database** — ek denormalized,
query-friendly table (per payment ek row, current status, underlying ledger entries
ke references) jo customer-facing "aapki payment history" view serve karne ke liye
use hoti hai bina har aise read ko raw ledger entries se state reconstruct karne pe
force kiye.

## Step 6: Deep Dive

### 6.1 Idempotency: is system ki sabse critical property

Core failure mode jiske against yeh defend karta hai: ek client ek payment submit
karta hai, request server tak pahunchti hai aur fully process ho jaati hai (card
charge, ledger update), par response wapas jaate waqt kho jaata hai (network blip,
client timeout). Client, jiske paas "meri request kabhi pahunchi hi nahi" aur "yeh
pahunchi aur succeed hui par response kho gaya" mein distinguish karne ka koi tareeka
nahi hai, retry karta hai. Bina protection ke, woh retry same purchase ke liye ek
doosra real charge result karta hai — ek unambiguous, user-visible bug real financial
aur trust consequences ke saath.

Fix: client ek unique idempotency key generate karta hai per logical payment attempt
ek baar (typically ek UUID client-side generate hota hai jab user "pay" click karta
hai, us same attempt ke har retry pe verbatim reuse hota hai) aur use har request ke
saath bhejta hai us attempt ke liye. Server-side flow:
1. Ek request receive karte hi, koi bhi processing karne *se pehle* idempotency key
   ko Idempotency Service mein lookup karo.
2. Agar key exist karti hai aur uska status `completed` hai, stored result immediately
   return karo — koi re-charging nahi, koi reprocessing nahi, yeh purely ek
   cache-style read hai.
3. Agar key exist karti hai aur uska status `in_progress` hai (ek concurrent retry
   aayi jabki pehla attempt abhi bhi process ho raha hai — ek real scenario jab client
   timeout hokar retry karta hai original request actually finish hone se pehle),
   duplicate ko reject ya hold karo instead of same logical payment ki do copies ko
   processor call ke through ek doosre ke against race karne dena.
4. Agar key exist nahi karti, atomically use claim karo (ek conditional/compare-and-swap
   write ke saath `status: in_progress` likho, wahi atomic-claim pattern jo
   `distributed_systems_core.md` ke idempotency aur distributed-locks sections mein use
   hota hai), phir processing proceed karo, aur finally processing finish hone pe
   record ko `completed` result ke saath update karo.

Yeh ek system-wide idempotency guarantee hai, sirf ek database-level nahi — isko
external processor call ko bhi cover karna chahiye: payment processor ko actual
banaya gaya charge call khud ek processor-level idempotency key pass karni chahiye
(zyadatar real processors, e.g., Stripe, exactly isi ko support karte hain) taaki
chahe Payment Orchestration Service khud crash ho aur mid-flow retry kare, processor
bhi apni taraf se double-charge karne se mana kar de. Idempotency har uss hop pe
enforce karni padti hai jo retry ho sakta hai, sirf outermost API boundary pe nahi.

### 6.2 Money ko sahi represent karna: double-entry ledger model

Do related par distinct correctness rules govern karte hain ki money kaise
represent hoti hai:

**Smallest currency unit mein integer amounts.** `amount_cents = 4999` store karo,
kabhi `amount_dollars = 49.99` ek float ke roop mein nahi. Floating-point arithmetic
zyadatar decimal fractions ko exactly represent nahi kar sakta, isliye float dollar
amounts ka repeated addition/subtraction rounding error accumulate karta hai —
unacceptable jab numbers real money represent karte hain aur cent tak balance hone
chahiye. Smallest unit (cents, ya doosri currencies ke equivalent) mein integers isse
entirely sidestep kar dete hain; currency-aware display formatting (100 se divide
karna aur ek decimal point add karna) sirf presentation layer pe hoti hai, kabhi bhi
stored ya computed values mein nahi.

**Ek single mutable balance field ke bajaye double-entry bookkeeping.** Naive design —
ek `accounts.balance` column jo har transaction pe directly increment/decrement hota
hai — ke do serious problems hain: concurrent writes ke under ek lost update (do
simultaneous transactions dono old balance read karte hain, dono ek naya balance
compute karte hain, ek doosre ko overwrite kar deta hai — classic read-modify-write
race) silently money lose kar sakta hai, aur kyu balance jo hai woh hai iska koi
historical record nahi hota, sirf yeh ki abhi kya hai, jo auditing, dispute
resolution, aur bug investigation ko baad mein essentially impossible bana deta hai.
Double-entry bookkeeping iske bajaye har transaction ko involved accounts ke across
**debit aur credit entries ke ek balanced pair** ke roop mein record karti hai — money
kabhi "bas increase" nahi hoti, yeh hamesha ek account ke credit *se* doosre account
ke debit *tak* move hoti hai (ya account type convention ke according vice versa), aur
ek pair ki dono entries hamesha zero tak sum hoti hain. User ka current balance ek
stored field nahi hai jo mutate hoti hai; yeh us account ki *ledger entries ka sum*
hai, computed (ya checkpointed aur periodically reconciled) instead of sole truth ke
roop mein stored. Yeh do properties free mein deta hai: full auditability (har
balance entries replay karke reconstructable hai, aur koi bhi discrepancy ek specific
transaction_id tak traceable hai) aur concurrent lost-updates ke against safety
(naye, immutable entries ka ek INSERT wahi read-modify-write race nahi rakhta jo ek
mutable UPDATE rakhti hai — concurrent transactions apni-apni entries append karte
hain instead of same field overwrite karne ke liye contend karna). Ledger entries,
ek baar likhi jaane ke baad, kabhi update ya delete nahi hoti; ek error correct karne
ka matlab hai ek naya, reversing entry insert karna, history edit karna nahi — ledger
table design se append-only hai, isi liye iski expected growth (Step 2) ko ek
ever-growing, partitioned table ke roop mein estimate karna pada, ek fixed-size table
ke roop mein nahi.

### 6.3 Multiple systems ke across partial failures: Saga pattern

Ek single payment logically kam se kam teen systems ke across span karta hai jo ek
local ACID transaction share nahi kar sakte kyunki yeh different systems hain (aur
Payment ek third-party gateway hai jise aap control nahi karte): external payment
processor (ek alag company ka system, network ke over reach hua, hamare database ke
saath two-phase commit mein enlist karne ka koi tareeka nahi), internal ledger
(hamara apna strongly consistent database), aur user notification. Kyunki processor
external hai, "card charge karo" aur "ledger update karo" ko ek single atomic
transaction mein wrap karne ka koi tareeka nahi hai jaisa ek single-database operation
allow karta — yeh exactly wahi scenario hai jo `distributed_systems_core.md` ka Saga
pattern section describe karta hai: local transactions ki ek sequence, har ek ke paas
ek defined compensating action agar sequence mein baad ka step fail ho.

Concretely: step 1 external processor charge karta hai. Agar step 1 outright fail ho
(processor decline karta hai, definitive failure response ke saath timeout hota hai),
kuch bhi aage nahi hota — koi compensation ki zaroorat nahi, kyunki koi money move
nahi hui aur koi ledger entry nahi likhi gayi. Agar step 1 *succeed* hota hai par
step 2 (ledger entries likhna) fail ho jaata hai (e.g., exact wrong moment pe ek
database outage), system ab ek aisi state mein hai jahan money externally move ho
chuki hai par internal ledger use reflect nahi karta — exactly waisi inconsistency
jise fix karne ke liye Saga ka compensating action exist karta hai: orchestrator
processor ko ek compensating call issue karta hai (charge void karo, ya agar voiding
available nahi hai toh immediate refund issue karo) taaki external side effect
unwind ho jaaye, world ko "koi charge hua hi nahi" state mein wapas laaye instead of
ek charged-but-unrecorded transaction ko floating chhodna. Compensating action khud
bhi idempotent aur retry hone tak retried hona chahiye (retry state track ki jaani
chahiye, fire-and-forget nahi), kyunki compensation step mein ek failure utni hi
dangerous hai jitni forward step mein ek failure. Ledger write ke baad ke steps (jaise
ek notification bhejna) explicitly Saga ki correctness-critical chain ka part *nahi*
hain — ek failed notification ko compensating action ki zaroorat nahi hai kyunki
usne money affect nahi ki, sirf communication, toh use best-effort/
eventually-consistent chhod dena aur bina upstream kuch block ya unwind kiye ek queue
pe simply retry karna theek hai.

### 6.4 Reconciliation: idempotency aur sagas ke neeche ka safety net

Ek correct idempotency implementation aur ek correctly-compensating Saga ke saath bhi,
ek external third party ke saath truly exact real-time consistency guarantee karna
fully achievable nahi hai — aise edge cases exist karte hain jo koi bhi mechanism
fully cover nahi karta: orchestrator processor ka success response receive karne aur
durably record karne ke beech crash ho jaata hai ki usne woh response dekha (toh uski
apni retry logic ko pata hi nahi ki charge already succeed ho chuka hai), compensating
void/refund call khud baar-baar fail hota hai aur retries exhaust kar deta hai, ya
processor ka asynchronous webhook jo final settlement confirm karta hai us se
disagree karta hai jo synchronous charge call ne initially report kiya tha (holds,
disputes, aur delayed settlement real card processing mein common hain). Yeh koi
exotic cheezein nahi hain — yeh ek distributed system ka normal long tail hai jo ek
third party ke saath integrate karta hai jise platform control nahi karta.

Isi liye har real payment system **reconciliation** ko ek standing, permanent safety
net ke roop mein chalata hai, ek one-time migration step nahi: ek periodic (typically
nightly) batch job processor ki settlement report pull karta hai — uska apna
authoritative record ki usne actually kya charge aur settle kiya — aur use, transaction
by transaction, internal ledger ke saath diff karta hai. Teen outcomes: entries match
karti hain (overwhelming majority, confirm karta hai ki real-time mechanisms sahi se
kaam kiye); processor ek charge dikhata hai jiska koi matching internal ledger entry
nahi hai (implies ek ledger write kho gaya — automatic backfill chahiye, alerting ke
saath); ya internal ledger ek completed transaction dikhata hai jiska processor ke
paas koi record nahi hai (implies ek phantom success internally record hua — ek more
serious class ka bug jise manual investigation chahiye, kyunki iska matlab ho sakta
hai ki ek user ka balance credit hua bina actually money move hue). Reconciliation
deliberately ek offline, non-latency-critical batch process ke roop mein design ki
gayi hai — isko fast ya real-time hone ki zaroorat nahi, kyunki iska poora kaam hai un
rare cases ko pakadna jo real-time path ki cracks se nikal jaate hain, ek aisi time
horizon pe (hours, milliseconds nahi) jo us purpose ke liye appropriate hai.

## Step 7: Bottlenecks & Trade-offs

- **Ledger ki strong consistency requirement ek deliberate throughput ceiling hai.**
  Iss question bank ke zyadatar systems ke unlike jahan aur scale karne ka jawab hai
  "consistency relax karo, aur replicas add karo, eventually consistent ban jaao,"
  ledger explicitly aisa nahi kar sakta — har balance-affecting write ko strict
  consistency chahiye, jo bound karta hai ki ek single logical ledger sirf read
  replicas add karke kitna scale kar sakti hai. Very large scale pe iska address
  accounts ko multiple strongly-consistent ledger shards ke across sharding karke
  hota hai (e.g., account_id range se), yeh accept karke ki cross-shard transactions
  (rare, kyunki zyadatar payments ek user account aur ek platform account ke beech
  hote hain jo co-locate ho sakte hain) apna careful handling maangte hain — na ki
  ek shard ke andar consistency ko weaken karke.
- **External processor call latency mein long pole aur system ka sabse kam
  controllable part hai.** Ek slow ya degraded processor directly har payment ko slow
  kar deta hai; iska mitigation hai aggressive timeouts idempotent retries ke saath
  (kabhi bhi blind unlimited waiting nahi) aur, architecture level pe, us external
  call ke across koi bhi internal locks ya long-lived transactions open na rakhkar —
  local ledger transaction sirf tabhi shuru hota hai jab processor already respond kar
  chuka ho.
- **Idempotency key storage ke paas ek retention trade-off hai.** Keys ko hamesha ke
  liye rakhna wasteful aur unnecessary hai (koi bhi legitimate client chhe mahine
  purani request retry nahi karta); bahut chhota TTL risk karta hai ki ek legitimate
  slow retry apni original key na paaye aur accidentally reprocess ho jaaye. TTL
  window (Step 5) realistic client retry/backoff ceilings ke basis pe chosen hai,
  arbitrarily nahi.
- **Reconciliation discrepancies ek fundamental limit represent karti hain, ek bug
  nahi jise fully eliminate karna hai.** Kyunki system ek third party ke saath
  integrate hota hai jiska internal behaviour real time mein fully observable nahi
  hai, discrepancy ki kuch rate expected hai aur reconciliation exactly isi liye
  exist karta hai kyunki zero discrepancies structurally guarantee nahi ki ja sakti —
  goal hai unhe jaldi catch aur resolve karna, unhe kabhi occur hi na hone dena nahi.
- **Ledger write path pe availability ke upar consistency favor karna outages ko
  silently absorb hone ke bajaye visible bana deta hai.** Agar ledger database
  unreachable ho, system correctly naye payments accept karne se mana kar deta hai
  instead of unhe accept karke baad mein reconcile karna — availability ko
  correctness ke liye trade karne ka ek deliberate decision jo, kahin aur jaise ek
  social feed mein, wrong choice hoti, par yahaan sahi hai.

## Follow-up Questions jo ek Interviewer Puch Sakta Hai

**"Aap cross-currency transactions ke liye currency conversion kaise handle karoge?"**
Ek explicit FX conversion step introduce karo jo transaction time pe ek rate lock kar
le aur use transaction ke part ke roop mein record kare (kabhi bhi baad mein, ek
different rate pe ek historical transaction ki value recompute mat karo), ek
cross-currency transaction ke dono sides ki ledger entries unki respective native
currencies mein record hoti hain instead of ek shared currency force karne ke —
double-entry model ki ek extension, uski replacement nahi.

**"Aap fraudulent transactions kaise detect aur prevent karoge?"** Processor charge
se pehle ek fraud-scoring step layer karo (velocity checks, device/IP reputation, ML
risk scoring) jo ek transaction ko pre-emptively hold ya decline kar sake — yeh
correctness/idempotency se ek entirely separate concern hai, ek distinct subsystem
ke roop mein naam lene layak (hot path pe synchronous scoring, plus asynchronous
post-hoc review) instead of ise ledger design ke saath conflate karne ke.

**"Agar same idempotency key ek different payment amount ke saath bheji jaaye toh
kya hoga?"** Yeh explicitly ek client error ke roop mein reject hona chahiye
(idempotency key ek specific logical request identify karti hai; ek mismatched
payload ya toh ek client bug hai ya ek suspicious retry) — Idempotency Service ko
key ke saath original request parameters ka ek hash store karna chahiye aur har
lookup pe use compare karna chahiye, agar payload us key ke saath pehli baar
associated cheez se match na kare toh request refuse karna chahiye.

**"Aap disputes aur chargebacks kaise support karoge?"** Ek chargeback ko apna khud ka
transaction type model karo jo apni khud ki balanced ledger entries generate kare
(original transaction ke effect ko reverse karte hue, plus koi bhi chargeback fee
ek separate entry ke roop mein), original transaction ke din ya hafton baad processor
se ek asynchronous webhook se trigger hua — kabhi bhi original transaction ki
historical entries mutate karke nahi, 6.2 ki append-only guarantee preserve karte
hue.

**"Aap ek flash-sale ke 10-20x traffic spike ko handle karne ke liye isse kaise scale
karoge?"** Kyunki bottleneck external processor call plus strongly consistent ledger
write hai (raw request parsing nahi), in-flight processor calls ki concurrency
badhakar scale karo (async processing, ek-ek karke nahi), ek known event se pehle
ledger database ki capacity pre-warm/scale karo, aur backpressure apply karo
(incoming requests ko drop karne ke bajaye, ya unhe accept karke silently fail hone
dene ke bajaye, queue karo) agar correctness-critical path keep up na kar paaye —
explicitly "user ko thoda zyada wait karwao" ko "correctness guarantees ke bina
process karo" ke upar choose karte hue.

**"Aap ek aise system ko test kaise karoge jahan correctness bugs itne costly hon?"**
Normal unit/integration tests ke alawa, yeh specific system ledger ke property-based
testing se bahut faayda uthaata hai (e.g., "kisi bhi transaction_id ki saari entries
ka sum hamesha zero hota hai," "operations ki kisi bhi sequence ke across total
platform balance conserved rehta hai") aur multi-step Saga ko specifically target
karne waale chaos-style fault injection se (orchestrator ko steps ke beech kill karo,
processor timeouts aur duplicate webhooks simulate karo) yeh verify karne ke liye ki
compensating actions aur reconciliation actually wahi catch karte hain jiske liye
unhe design kiya gaya, sirf happy path test karne ke bajaye.
