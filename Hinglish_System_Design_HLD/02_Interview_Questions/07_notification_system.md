# Design a Notification System

## Problem Statement

"Design a notification system jo users ko multiple channels — push notifications, SMS, aur email — ke through notifications bhejta hai, jo backend events se trigger hote hain jaise 'your order has shipped' ya 'someone commented on your post'." System ko large scale pe kaam karna hai, sudden bursts handle karne hain (ek flash sale jo millions of users ko ek saath notify karta hai), har user ki channel preferences aur quiet hours respect karni hain, aur gracefully handle karna hai ki actual push/SMS/email deliver karne wale third-party providers apni khud ki rate limits impose karte hain aur independently fail bhi ho sakte hain." Yeh woh shared notification infrastructure hai jo almost har consumer product ko eventually chahiye hoti hai, kisi bhi single feature se decoupled jo notification trigger karta hai.

## Step 1: Clarify Requirements

### Functional Requirements

- Internal services ek event publish karke notification trigger kar sakte hain (jaise, `order.shipped`, `comment.created`) ya ek direct "send notification" API call karke one-off/scheduled sends ke liye.
- Kam se kam teen channels support karo: push (iOS/Android), SMS, aur email — ek single logical notification same user ke liye multiple channels pe fan-out ho sakta hai.
- Har channel ke liye templated, personalized content support karo (push notification short hota hai; email mein subject, body, aur layout hote hain).
- Per-user, per-channel, per-category preferences respect karo (jaise, ek user marketing emails se opt-out karta hai lekin order-status push notifications rakhta hai) aur quiet hours (user ke local timezone mein raat 3 baje push mat karo).
- Guarantee karo ki transient failure ke baad ek retry, user ko same notification twice dikhane ka result nahi banega (idempotency).
- Delivery status expose karo (queued, sent, delivered, failed, opened jahan channel support karta hai) observability aur debugging ke liye.
- Scheduled/delayed sends support karo, sirf immediate sends nahi.

### Non-Functional Requirements

- **Scale**: tens of millions of notifications per day, highly bursty traffic ke saath — ek single triggering event (flash sale, major outage notice) minutes ke andar volume ko 10x spike kar sakta hai.
- **Latency**: push near-real-time feel hona chahiye (triggering event ke seconds ke andar deliver ho jaana chahiye); email aur SMS thoda zyada delay tolerate kar sakte hain (seconds se low minutes) bina broken consider hue.
- **Delivery guarantee**: at-least-once, exactly-once nahi — system ko kabhi bhi transient failure ki wajah se silently ek notification drop nahi karna chahiye, lekin ek rare duplicate (idempotency se mitigate) exactly-once guarantee karne ki cost ke muqable acceptable trade-off hai (Step 6).
- **Ingestion path ki availability**: internal service se notification request accept karna highly available aur fast hona chahiye — actual channel delivery decouple aur queue ki ja sakti hai, lekin "kya mera event accept hua" ka answer calling service ke liye bottleneck nahi ban sakta.
- **Third-party constraints ka respect**: har provider (APNs/FCM, ek SMS gateway jaisa Twilio, ek email service provider) apni khud ki rate limits enforce karta hai — system ko unhe kabhi exceed nahi karna chahiye, kyunki aisa karne se provider account ko throttle ya ban kar sakta hai.
- **Compliance**: email (CAN-SPAM) aur SMS (TCPA) ke liye unsubscribe/opt-out reliably honor hona chahiye — yeh ek legal requirement hai, sirf ek UX niceties nahi.

## Step 2: Back-of-Envelope Estimation

**Assumptions**:
- 50 million users, averaging 4 notifications/user/day across all channels combined.
- Channel split: 60% push, 25% email, 15% SMS (push sabse cheapest hai aur transactional updates ke liye sabse zyada use hota hai; SMS higher-priority/lower-volume cases ke liye reserve hai kyunki cost zyada hai).
- Average notification record size: ~1 KB (recipient, channel, template ID, rendered payload, status, timestamps).
- Retention: 90 days of notification history support/debugging/analytics ke liye.

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

Yeh split concretely matter karta hai: SMS providers commonly ek single sender account/number ko roughly 100-200 messages/sec pe rate-limit karte hain. SMS ke liye 3,500/sec ka peak matlab system ko provider limits ke neeche rehne ke liye **~20-35 parallel sender identities/number pools** chahiye — yeh ek hard external constraint hai jise design ko plan karna padega (Step 6), sirf zyada application-server capacity se yeh fix nahi hoga.

**Storage**

```
200,000,000 notifications/day × 1 KB = 200,000,000 KB = 200,000 MB ≈ 200 GB/day
Over 90 days retention: 200 GB × 90 ≈ 18 TB
```

18 TB squarely ek horizontally-partitioned NoSQL store ke range mein hai, single relational instance ke nahi.

**Queue throughput check**

Peak ingestion ka 23,150 events/sec pub/sub/queueing layer (Step 3) ko absorb karna hoga. Ek modern distributed log (Kafka-class) modest hardware pe per cluster hundreds of thousands of messages/sec handle kar leta hai, toh yeh peak ek single reasonably-sized cluster ki capacity ke well within hai — is system mein bottleneck queue nahi hai, yeh downstream third-party providers ki rate limits hain, jaisa SMS math ne dikhaya.

**Preference-check load**

Har send dispatch karne se pehle user ki preferences check karta hai — 23,150 notifications/sec peak pe, matlab 23,150 preference lookups/sec. Agar har lookup ek cold database read hoti, toh yeh akela ek relational store ko meaningfully load karta; yehi concrete reason hai ki preference data ko hot path (Step 5/6) pe cache-backed hona chahiye, na ki har send pe relational database se fresh query karni chahiye.

**Idempotency table load and sizing**

Har ingested request ek Redis check-and-set bhi karti hai idempotency dedup table (Step 6) ke against. 23,150/sec peak pe, aur dedup keys pe 24-hour TTL assume karke (itna lamba ki realistic upstream retry windows cover ho jaayein):

```
Resident dedup keys ≈ average ingestion rate × TTL window
                     ≈ 2,315/sec × 86,400 sec ≈ 200,000,000 keys resident at once
```

Roughly 80 bytes per key pe (ek UUID-length string key plus ek short `notification_id` value aur Redis ka apna per-key overhead):

```
200,000,000 × 80 bytes = 16,000,000,000 bytes = 16 GB
```

Ek modest, single-digit-node Redis deployment isse easily hold kar leta hai — cache-heavy systems mein dekhe jaane wale 400 GB working sets ke muqable chhota hai, kyunki dedup table ko sirf recent activity yaad rakhni hai, full notification history nahi (woh 18 TB notification store ke liye hai, jo next compute hua).

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

**Flow**: koi internal service ya toh ek domain event publish karta hai (`order.shipped`) jise notification system subscribe karta hai, ya seedha Notification API call karta hai one-off send ke liye. API request validate karti hai, ek idempotency key check karti hai (Step 6) upstream retries se duplicates reject karne ke liye, aur kuch bhi karne se pehle preference service check karti hai. Agar user kam se kam ek channel pe notification allow karta hai, toh event ek pub/sub bus pe publish hota hai, jo per-channel separate topics mein fan-out hota hai. Har channel ke paas apna dedicated worker pool hai jo apne topic se pull karta hai, us channel ka specific rate limiting aur retry logic apply karta hai, relevant third-party provider ko call karta hai, aur outcome record karta hai. Provider ke delivery-status webhooks (jaise, Twilio ke delivery receipts, SendGrid ka event webhook) asynchronously status store mein feed back hote hain.

**Key components**:
- **Notification API**: ingestion, validation, idempotency check — fast, highly-available front door.
- **Preference Service**: hot-path gate jo decide karta hai ki given user ko whether/how notify karna hai; speed ke liye cache-backed (Step 6).
- **Event Bus**: ingestion ko delivery se decouple karta hai — yehi hai jo 10x burst ko absorb hone deta hai bina ingestion path khud fall over kiye (dekho `10_message_queues_and_streaming.md`).
- **Per-channel worker pools**: har channel ke bahut different failure modes, rate limits, aur retry semantics ko ek dusre se isolate karte hain — ek SMS provider outage ki wajah se push delivery back up nahi hona chahiye.
- **Delivery Status Store**: durable record ki kya bheja gaya, kisko bheja gaya, aur kya hua.

**Ek notification ko end to end walk through karte hain**: (1) order service `order.shipped` publish karti hai order `o_789` ke liye, jisme ek `idempotency_key` order ID se derive hoti hai. (2) Notification API idempotency table check karti hai — pehli baar dekha gaya, toh aage badhti hai — request validate karti hai, aur Preference Service se poochti hai ki user `u_123` `order_updates` ko push aur email pe allow karta hai (dono ke liye yes assume karo, aur yeh bhi ki abhi unke quiet hours nahi chal rahe). (3) Event internal event bus pe publish hota hai, `push-notifications` aur `email-notifications` topics mein fan out hota hai. (4) Push worker pool message pick karta hai, apna rate limiter check karta hai (is volume ke liye APNs limits se well under), templated payload render karta hai, aur FCM/APNs ko call karta hai; email worker pool ESP ke against parallel mein, independently wahi karta hai. (5) Har worker outcome (`sent`, ek provider message ID ke saath) Delivery Status Store mein likhta hai. (6) Minutes baad, push provider ka delivery webhook fire hota hai, record ko `sent` se `delivered` mein update karta hai. Agar order service ki original call time out ho jaati aur *same* `idempotency_key` ke saath retry hoti, toh step (2) immediately short-circuit ho jaata, already-assigned `notification_id` return karta bina kuch bhi re-publish kiye — koi duplicate push ya email nahi bheja jaata.

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

**Internal preference check RPC** (workers dwara har send se pehle call hota hai, preference cache ko hit karta hai, is HTTP path ko nahi)
```
PreferenceService.IsAllowed(user_id, channel, category) → { allowed: bool, quiet_hours_active: bool }
```

## Step 5: Data Model

**Notification record** — NoSQL document/wide-column store (jaise, DynamoDB/Cassandra), partition key = `notification_id` (ya `user_id` + time bucket efficient per-user history queries ke liye):

| Field | Notes |
|---|---|
| `notification_id` (PK) | ingestion pe generate hota hai |
| `user_id` | secondary index "user X ke saare notifications" ke liye |
| `event_type` | e.g. `order.shipped` |
| `channels` | channel → {status, attempts, sent_at, provider_message_id} ka map |
| `idempotency_key` | unique index — dedup mechanism (Step 6) |
| `created_at` | |
| `payload` | rendered/template-resolved content, ya usko reference |

NoSQL fit karta hai kyunki writes extremely high-volume hain (Step 2: 200M+/day) aur access almost hamesha exact `notification_id` ya `user_id` se hota hai, koi relational joins ki zaroorat nahi — ek wide-column/document store is write volume ke liye horizontally scale karta hai ek relational database se kaafi zyada cheaply.

**User preferences** — ek chhota, read-heavy dataset jo *har* send ke hot path pe access hota hai (Step 2: 23,150 lookups/sec peak pe). Durably ek simple relational table mein stored hai (yeh small, structured hai, aur straightforward schema/constraints se benefit karta hai) lekin hamesha ek cache (Redis) ke through read hota hai, kyunki har single notification send pe ek cold read se preference check hi system ka actual bottleneck ban jaayega:

| Field | Notes |
|---|---|
| `user_id` | |
| `channel` | push / sms / email |
| `category` | order_updates / promotions / security / ... |
| `enabled` | bool |
| `quiet_hours_start` / `quiet_hours_end` / `timezone` | |

**Idempotency dedup table** — Redis, key = `idempotency_key`, value = `notification_id`, short TTL (itna lamba ki realistic retry windows cover ho jaayein, e.g. 24 hours) — har ingestion request pe ek O(1) check-and-set (Step 6), deliberately primary notification store se bahar rakha gaya kyunki yeh fast aur short-lived hona chahiye, durable long-term history nahi.

**Device token store** — `user_id → [device tokens]` push delivery ke liye, ek simple KV/relational table, jab bhi client app ek token register/re-register karta hai tab refresh hota hai (tokens OS side pe periodically rotate hote hain).

**Dead-letter queue** — ek database table nahi balki ek queue construct hai (ek dedicated Kafka topic ya SQS DLQ) jo un notifications ko hold karta hai jinka retry budget khatam ho gaya, Step 6 mein cover hua hai.

**Storage choice justification, summarized**:

| Component | Storage type | Why |
|---|---|---|
| Notification records | Wide-column/document NoSQL | Bahut high write volume (200M+/day), simple key-based access, joins ki zaroorat nahi |
| User preferences | SQL, Redis cache ke through read | Small, structured, schema/constraints se benefit; cache hot-path read volume absorb karta hai |
| Idempotency dedup | Redis (KV with TTL) | Ingestion rate pe O(1) check-and-set chahiye, design se hi short-lived |
| Device tokens | KV/relational | Simple `user_id → tokens` lookup, token rotation pe moderate write rate |
| Dead-letter queue | Message queue (Kafka topic/SQS DLQ) | Ek lookup structure nahi — reprocessing ya inspection ke liye ek durable backlog |

## Step 6: Deep Dive

### Fan-Out via Pub/Sub and Multi-Channel Worker Pools

Core architectural decision yeh hai ki har notification-worthy event ko **ek baar** publish karo, ek pub/sub bus pe, na ki triggering service (jaise, order service) khud har channel ki delivery logic ko directly call kare. Yeh wahi pub/sub fan-out pattern hai jo `10_message_queues_and_streaming.md` mein generally describe kiya gaya hai, yahan specifically apply hota hai "kuch hua" ko "kitne tareekon se hum user ko batayenge" se decouple karne ke liye.

Concretely: order service ek single `order.shipped` event publish karti hai aur aage badh jaati hai — usse koi idea nahi hai, aur na hi hona chahiye, ki yeh ek push notification, ek email, dono, ya kuch bhi nahi mein translate hoga (yeh preference service ka kaam hai, jo downstream check hota hai). Notification system ka apna internal fan-out phir us ek event ko per-channel messages mein split karta hai separate topics pe (`push-notifications`, `sms-notifications`, `email-notifications`), har ek apne dedicated worker pool se consume hota hai.

**Kyun har channel ke liye alag worker pools, na ki ek generic "send notification" worker**: har channel ka genuinely alag failure aur rate-limit profile hai —
- **Push workers** APNs/FCM ko call karte hain, jinka apna token-based delivery model hai, koi meaningful per-message cost nahi, aur failures mostly invalid/expired device tokens ke baare mein hote hain (jinhe device token store se clean up hona chahiye, endlessly retry nahi).
- **SMS workers** ek gateway jaisa Twilio ko call karte hain, jiska real per-message cost hai aur sabse tightest sender-account rate limits (Step 2 ka ~100-200/sec/number constraint) — SMS worker pools ko apna khud ka token-bucket rate limiter chahiye jo provider ke actual limits ke hisaab se tuned ho, push ya email throughput se independent.
- **Email workers** ek ESP (SendGrid, SES) ko call karte hain, jiske alag failure modes hain (bounces, spam-complaint feedback loops jo suppression lists mein feed back hone chahiye).

Inhe separate pools mein isolate karne ka matlab hai ki SMS provider outage ya rate-limit exhaustion sirf SMS topic ko back up karta hai — push aur email normally flow karte rehte hain. Ek single shared worker pool jo teeno channels handle kare, unke failure domains ko bina kisi benefit ke couple kar dega.

**Channel comparison, summarized**:

| Channel | Provider example | Typical rate-limit pressure | Dominant failure mode | Retry/cleanup action |
|---|---|---|---|---|
| Push | APNs / FCM | Low (token-based, near-free per send) | Expired/invalid device token | Stale token device store se remove karo, retry mat karo |
| SMS | Twilio / similar gateway | High (~100-200/sec per sender number) | Provider throttling, invalid number | Back off aur queue karo; invalid numbers flag karo, retry mat karo |
| Email | SendGrid / SES | Moderate (provider-defined sending reputation limits) | Hard bounce, spam complaint | Us address pe future sends suppress karo, suppression list mein feed karo |

### Idempotency and Deduplication

Kyunki ingestion path aur har worker pool retries ke around banaye gaye hain (Step 6, next section), same logical notification genuinely ek se zyada baar process ho sakta hai — ek calling service timeout ke baad retry karti hai bina yeh jaane ki pehli call succeed hui ya nahi, ya ek worker provider ko call karne ke baad crash ho jaata hai lekin success record karne se pehle, aur restart pe message ko re-process karta hai. Bina ek dedup mechanism ke, iska matlab hai ki ek user ko "your order shipped" push twice mil sakta hai, jo ek real, visible product bug hai bhale hi underlying infrastructure ne "correctly" behave kiya ho retrying karke.

Mechanism (`09_distributed_systems_core.md` mein diye gaye idempotency-key pattern ke consistent) yeh hai: **caller** (triggering internal service) ek `idempotency_key` supply karta hai jo same logical event ke retries mein stable rehta hai — typically event se hi derive hota hai (jaise, `"order-shipped-" + order_id`, jo naturally same value hota hai chahe order service call ko kitni bhi baar retry kare). Notification API kuch bhi karne se pehle is key ko Redis dedup table (Step 5) ke against check karti hai: agar key already dekha gaya hai, toh yeh existing `notification_id` aur status return kar deta hai bina event ko re-publish kiye at all — yeh duplicate ko bilkul first hop pe hi rok deta hai, kisi worker ya third-party provider tak pahunchne se pehle, jo pipeline mein baad mein deduplicate karne ki koshish se cheaper aur simpler dono hai. Workers additionally `provider_message_id`s bhi track karte hain jahan provider khud idempotent send support karta hai (kuch SMS/email APIs client-supplied idempotency token accept karte hain), jo specifically worker-level retry ke against defense in depth deta hai.

### User Preferences, Opt-Outs, and Quiet Hours

Har send preference check se guzarta hai **pehle** kisi channel topic pe publish hone se — baad mein nahi, aur worker level pe bhi nahi — kyunki ek disallowed notification ko jitni jaldi ho sake reject karna wasted downstream work avoid karta hai aur, zyada important, kabhi bhi ek opted-out user ke liye third-party provider ko call karne se bachata hai (jo actual compliance requirement hai, sirf efficiency concern nahi).

Check order mein evaluate karta hai: **channel-level opt-out** (kya is user ne push entirely disable kiya hai?), **category-level opt-out** (kya is user ne "promotions" specifically disable kiya hai, jabki same channel pe "order updates" allow rakha hai?), aur **quiet hours** (kya abhi user ke configured do-not-disturb window mein hain, *unke* local timezone mein, unke stored timezone se compute hokar, server ke timezone se nahi)? Quiet hours se block hua ek notification simply drop nahi hota — non-time-sensitive categories ke liye yeh typically defer hota hai aur quiet-hours window khatam hone ke baad re-evaluate hota hai, jabki genuinely time-sensitive categories (security alerts, fraud warnings) ke liye quiet hours deliberately apply hi nahi hote, jo khud ek product/policy decision hai jise preference schema ko support karna chahiye (per-category ek "quiet-hours-exempt" flag).

**Unsubscribe/opt-out compliance** email aur SMS ke liye specifically optional nahi hai — har email mein ek functioning unsubscribe link hona chahiye, aur har SMS mein "reply STOP to opt out" mechanism, dono ko usi preference store mein wapas likhna chahiye jise system ka baaki hissa padhta hai, taaki channel ke through directly liya gaya opt-out (email mein unsubscribe click karna) immediately respect ho next send pe kisi bhi channel se, sirf email se nahi.

Kyunki yeh check peak volume pe har single send pe chalta hai (Step 2: 23,150 lookups/sec), preference data hamesha relational preference table (Step 5) ke saamne Redis cache ke through read hota hai — ek cache-aside pattern (`05_caching.md`) jahan cache invalidate hota hai jaise hi user preference update karta hai, taaki opt-outs immediately effect mein aa jaayein, ek TTL ka wait kiye bina.

### Handling Third-Party Failures: Rate Limits, Retries, DLQ, and At-Least-Once Delivery

Har worker pool ka apna **rate limiter hai jo specific provider ke documented limits ke hisaab se tuned hai** (jaise, ek token-bucket limiter jo SMS sends ko provider ke per-account ceiling se just neeche cap karta hai) — yeh proactively enforce hota hai, reactively nahi, kyunki provider ki rate limit *exceed* karne se poora risk hai ki provider entire account ko throttle ya suspend kar de, jo poore channel ko sab users ke liye down kar dega, sirf offending burst ko slow nahi karega. Jab kisi channel ke pending sends ka queue rate limiter ke immediately allow karne se zyada ho jaata hai, messages simply topic mein wait karte hain drop hone ki jagah — yeh exactly wahi reason hai ki event bus (Step 3) ingestion aur delivery ke beech baithta hai: yeh bursts (Step 2 ka 10x flash-sale scenario) ko backlog ki tarah absorb karta hai, ingestion API pe synchronous, immediately-rate-limited delivery force karne ki jagah, jo warna *caller* (order service, kaho) ko downstream provider ki limits ki wajah se wait ya fail karwaata.

**Retries**: ek failed provider call (timeout, 5xx, transient network error) exponential backoff aur jitter ke saath retry hoti hai, ek bounded number of attempts tak. **Retryable** failures (timeouts, 5xx, provider-side rate-limit responses) ko **non-retryable** wale se (invalid phone number, permanently expired device token, hard email bounce) distinguish karna matter karta hai — ek non-retryable failure ko retry karna sirf budget waste karta hai aur inevitable ko delay karta hai, aur kuch non-retryable push/SMS failures ke liye correct action actually stale token/number ko device store se clean up karna hai taaki future sends same failure repeat na karein.

**Dead-letter queue**: ek notification jo apna retry budget khatam kar deta hai (maximum backoff attempts ke baad bhi fail ho raha hai) ko silently discard karne ki jagah per-channel DLQ mein move kiya jaata hai — yeh isse manual inspection, alerting (DLQ volume mein spike ek provider outage ya systemic problem signal karta hai jo page karne layak hai), aur underlying issue (provider outage, ek bad template) fix hone ke baad potential reprocessing ke liye preserve karta hai.

**At-least-once realistic, deliberately chosen target hai, koi accidentally settled compromise nahi**: ek unreliable network, ek queue, ek worker process, aur ek third-party provider (jo khud succeed ho sakta hai lekin acknowledge karne mein fail ho sakta hai) shamil chain mein genuine exactly-once delivery guarantee karna ya toh impossible hai ya har provider ke saath distributed-transaction-style coordination chahiye — jo koi bhi third-party SMS/push/email provider support nahi karta. At-least-once, upar wale idempotency mechanism ke saath, practically achievable equivalent deta hai: duplicates *rare* bana diye jaate hain (sirf genuine failure-and-retry edge cases pe hote hain) aur, zyada important, *safe* (ek duplicate jo idempotency key se slip through ho jaaye, phir bhi sirf already-approved content ka duplicate send hai, kabhi double-charge ya double-shipped order nahi) — correctness ka burden "kabhi twice mat bhejo" (unachievable) se "twice bhejna harmless hai" (achievable aur sufficient) pe shift ho jaata hai.

## Step 7: Bottlenecks & Trade-offs

- **Third-party provider rate limits hi real ceiling hain, internal infrastructure nahi.** Step 2 ka SMS math (peak throughput hit karne ke liye 20-35 parallel number pools chahiye ek single provider ke per-account limits ke andar) dikhata hai ki bottleneck external aur commercial hai (provider ke saath kitni sender identities/accounts provision ki gayi hain) na ki kuch jo zyada application servers fix kar sakein.
- **Preference check har single send ke liye ek mandatory hot-path dependency hai** — agar preference cache cold ho jaaye ya cache layer khud degrade ho jaaye, toh system ko choose karna padta hai: fail open (opted-out users ko bhejne ka risk — ek compliance violation) ya fail closed (preferences available hone tak sab sends block karo — ek availability hit). Most real systems compliance-sensitive categories (marketing) ke liye fail closed karte hain aur sirf critical/safety notifications ke liye fail open karte hain, jo khud ek explicit, reviewed policy decision hona chahiye, default nahi.
- **Ek single triggering event jo ek saath millions of users tak fan out hota hai (Step 2 ka flash-sale scenario) ko kabhi synchronously process nahi karna chahiye** — event bus ka poora kaam hi hai us spike ko queue backlog mein badalna jise worker pools sustainable, provider-limit-respecting rate pe drain karte hain, immediate delivery ko sustained, non-throttled delivery ke liye trade karke.
- **SMS cost** ek real constraint hai jo baaki channels share nahi karte — meaningful scale pe, indiscriminate SMS usage ek significant recurring cost hai, isliye product policy typically SMS ko high-value, lower-volume categories (security codes, critical alerts) ke liye reserve karti hai, general-purpose notifications ke liye nahi.
- **Idempotency window bounded hai, infinite nahi** — Redis dedup table ka TTL (Step 5) matlab hai ki ek retry jo us window ke expire hone *ke baad* aata hai duplicate ki tarah recognize nahi hoga; TTL ko realistic caller retry behavior ke against generously set karna hoga, aur yeh ek deliberate, tunable trade-off hai dedup-table memory cost aur duplicate-prevention coverage ke beech.
- **DLQ volume ek operational signal hai, lekin sirf tab jab koi usse dekh raha ho** — ek DLQ jo silently accumulate hota hai bina alerting ke apna hi purpose defeat karta hai; failed messages ko drop karne ki jagah hold karne ka trade-off tabhi pay off karta hai jab usko drain karne aur act karne ka ek real operational process ho.

**Bottleneck-to-mitigation summary**:

| Bottleneck | Mitigation | Cost accepted |
|---|---|---|
| Provider rate limits (esp. SMS) | Per-channel token-bucket limiter, multiple sender identities/number pools | Providers ke saath provisioning/commercial overhead |
| Preference check on every send | Cache-aside preference lookups (SQL ke saamne Redis) | Ek preference update aur cache invalidation ke beech chhota staleness window |
| Traffic burst (flash sale, 10x spike) | Ingestion aur delivery ke beech pub/sub buffering | Burst ke dauran delivery delay, dropped/failed sends ki jagah |
| Retry-induced duplicates | Ingestion pe idempotency key check | Chhota dedup-table memory cost, bounded TTL window |
| Repeatedly failing sends | Infinite retry ya silent drop ki jagah Dead-letter queue | DLQ monitor aur drain karne ke liye ek operational process chahiye |

## Follow-up Questions an Interviewer Might Ask

**Notification fatigue kaise prevent karoge — jahan ek user bombard ho jaata hai kyunki short window mein multiple triggering events fire hote hain?**
Ek per-user, per-category rate cap add karo (jaise, "someone liked your post" push har 30 minutes mein max ek baar, subsequent likes ko ek single digest notification mein batch karke) jo preference/fan-out stage pe enforce ho channel topic pe publish hone se pehle — yeh Step 6 ki provider-level rate limiting ke upar ek product-level throttle hai, replacement nahi.

**Push/SMS/email ke saath ek in-app notification center (unread count wala bell icon) kaise banaoge?**
"In-app" ko ek fourth channel ki tarah treat karo jiska apna worker pool hai jo ek external provider call karne ki jagah ek per-user notification-history store mein likhta hai, aur ek unread counter maintain karo (likely ek fast KV store jaisa Redis mein, write pe increment aur read pe decrement/reset) — fan-out aur preference-check architecture otherwise unchanged rehta hai, kyunki yeh sirf same upstream events ke liye ek aur delivery target hai.

**Product analytics ke liye delivery/open/click rates kaise measure aur improve karoge?**
Workers ko har status transition (sent, delivered, opened, clicked) pe ek delivery event ek analytics pipeline mein log karwao (primary notification store mein nahi, taaki transactional path analytics load se couple na ho), jo delivered/opened ke liye jahan support ho provider webhooks se feed ho, phir ek separate analytics/warehouse system mein aggregate karo, operational notification store ko reporting ke liye directly query karne ki jagah.

**Multi-region users aur data residency requirements (jaise, GDPR) kaise support karoge?**
Preference store aur notification history ko user ke home region ke hisaab se partition karo, user ki notification requests ko unke region ke pipeline pe route karo, aur cross-region replication ko strictly necessary tak limit rakho (jaise, notification content ke liye kuch bhi nahi, jo regional rehna chahiye) — yeh general data-residency patterns mirror karta hai, kuch notification-specific nahi.

**Backpressure event ke dauran ek critical security alert ko ek promotional notification se kaise prioritize karoge?**
Separate queue partitions ya topics use karo per priority tier (critical vs. standard) taaki worker pools ko hamesha critical tier pehle drain karne ke liye configure kiya ja sake, aur quiet-hours/rate-limit exemptions specifically critical tier pe apply karo (Step 6) — isme priority ko notification request pe ek first-class field hona chahiye, baad mein infer nahi karna chahiye.

**Notification copy ya send-time optimization ko A/B test kaise karoge?**
Notification request creation time pe ek experiment/variant ID attach karo, template resolution step ko assigned variant ke hisaab se copy pick karne do, aur variant ko analytics pipeline (previous question) mein delivery/open/click events ke saath log karo taaki downstream experimentation tooling per-variant engagement lift compute kar sake — yeh existing template aur analytics mechanisms ke upar entirely layered hai, koi nayi delivery infrastructure ki zaroorat nahi.

**Ek scheduled/delayed notification (jaise, "remind me in 2 hours") ko constantly database poll kiye bina right time pe kaise guarantee karoge ki fire ho?**
Ek delay-capable queue mechanism use karo — ya toh ek message queue ka native delayed-delivery feature, ya ek scheduled-jobs table jise ek lightweight poller short interval pe scan kare aur due hone pe hi main event bus pe re-publish kare — scheduled notifications ko application memory mein hold karne ki jagah, kyunki ingestion path aur worker pools dono stateless aur horizontally scalable rehne chahiye.
