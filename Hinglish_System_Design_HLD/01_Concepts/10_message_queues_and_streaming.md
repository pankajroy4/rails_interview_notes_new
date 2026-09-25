# Message Queues and Streaming

## Asynchronous messaging kyun exist karti hai

Ek purely synchronous system mein, service A directly service B ko call
karti hai aur continue karne se pehle response ka wait karti hai. Yeh
simple hai, lekin isse A ki availability aur latency directly B se wire ho
jaati hai: agar B slow hai, to A slow hai; agar B down hai, to A bhi fail ho
jaati hai. Ek **message queue** us coupling ko break karta hai producer aur
consumer of work ke beech ek durable buffer daal ke.

Teen concrete problems jo yeh solve karta hai:

- **Producers ko consumers se decouple karna**: producer ko yeh janne ki
  zaroorat nahi ki message kaun consume karta hai, kitne consumers hain, ya
  woh currently healthy hain ya nahi — woh bas message likhta hai aur aage
  badh jaata hai. Consumers add, remove, ya rewrite ho sakte hain bina
  producer ko bilkul bhi change kiye.
- **Traffic spikes ko smooth karna**: agar 10,000 requests ek second mein
  aa jaayein lekin aapka system comfortably sirf 1,000/second process kar
  sakta hai, to ek queue aapko sab 10,000 turant accept karne deti hai (queue
  mein ek cheap, fast write) aur agle 10 seconds mein unhe drain karne deti
  hai, instead of 9,000 ko reject karne ke ya unhe sabko synchronously
  process karne ki koshish karte hue fall over hone ke.
- **Fault isolation**: agar ek downstream service slow hai ya temporarily
  down hai, to messages queue mein pile up ho jaate hain instead of upstream
  service mein failed requests ya timed-out threads ki tarah pile up hone
  ke — upstream service healthy rehti hai aur naya kaam accept karti rehti
  hai.

## Yeh important kyun hai

Asynchronous messaging ke bina, systems in specific tareekon se fail hote
hain:

- **Ek request path ke andar ek slow email/SMS/webhook provider** har us
  request ko slow bana deta hai jo ek notification trigger karti hai, ya
  poori request fail kar deta hai jab provider mein blip ho — chahe "ek
  notification bhejo" kabhi bhi aisi cheez nahi thi jiska user ko wait karna
  padta.
- **Ek traffic spike (flash sale, viral post) poore system ko down kar deta
  hai** kyunki har request apna sara kaam synchronously karne ki koshish
  karta hai, aur database/downstream services overwhelmed ho jaate hain
  bina kisi buffer ke jo burst ko absorb kare.
- **Ek service ka outage unrelated services tak cascade karta hai** jo usse
  synchronously call karte hain, ek single component failure ko ek
  system-wide outage bana dete hue.

## Pub/sub vs point-to-point queue

Yeh do fundamental messaging shapes hain, aur interviewers expect karte hain
ki aap scenario ke liye sahi wala pick karo.

- **Point-to-point queue**: har message exactly **ek** consumer ko deliver
  aur process kiya jaata hai, chahe kitne bhi consumers sun rahe hon. Yeh
  **work distribution** ke liye hai — aapko workers ka ek pool chahiye jo
  jobs ka ek backlog split up kare.
  - Example: order-processing jobs ek queue par push kiye jaate hain, worker
    processes ke ek pool se consume hote hain — har order ek baar process
    hona chahiye, ek worker se, sabse nahi.
- **Publish/subscribe (pub/sub)**: har message **har** subscriber ko
  independently broadcast hota hai. Yeh **fan-out** ke liye hai — aap
  chahte ho ki multiple, independent parties har ek same event par apne
  tareeke se react karein.
  - Example: ek `UserUpdated` event publish hota hai jab user apna email
    change karta hai; email service, analytics service, aur fraud-detection
    service teeno independently subscribe aur react karte hain — teeno ko
    har event dekhna chahiye, sirf jo pehle grab kare woh nahi.

```text
Point-to-point queue (work distribution)     Pub/Sub (fan-out)
                                               
 Producer --> [ Queue ] --> Worker 1           Publisher --> [ Topic ] --> Subscriber A
                        \-> Worker 2                                  \-> Subscriber B
                        \-> Worker 3                                  \-> Subscriber C
 (each message goes to ONE worker)            (each message goes to EVERY subscriber)
```

## Delivery semantics

Delivery semantics describe karte hain ki ek messaging system kya guarantee
karta hai kitni baar ek message actually deliver/process hoga.

| Semantic | Guarantee | Failure mode | Mechanism |
|---|---|---|---|
| At-most-once | Message delivered zero or one times | Can silently lose messages | Fire-and-forget — send and don't wait for/retry on failure |
| At-least-once | Message delivered one or more times | Can deliver duplicates | Producer/broker retries until it gets an acknowledgment (ack) from the consumer |
| Exactly-once | Message delivered and processed exactly one time | Very hard to actually guarantee end-to-end | Usually simulated, not truly native |

**Exactly-once practice mein almost hamesha "effectively-once" hi hota
hai**: real systems exactly-once ka *effect* achieve karte hain
**at-least-once delivery** (safe default — kabhi bhi silently ek message
drop na karo, duplicates aane ko tolerate karo) ko **idempotent consumers**
(consumer safely same message do baar process kar sakta hai aur same result
pa sakta hai) ke saath combine karke. Yeh wahi idempotency-key mechanism hai
jo `09_distributed_systems_core.md` mein describe hui — messaging layer ka
kaam bas kuch bhi lose na karna hai, aur consumer ka kaam re-processing ko
harmless banana hai. Transport level par true exactly-once delivery ke liye
har single message par distributed consensus solve karna padega, jo high-
throughput systems ke liye too costly hai, isliye nearly sab log effectively-
once hi build karte hain.

## Kafka basics

**Apache Kafka** ek distributed streaming platform hai jo durable, ordered,
replayable logs ke around built hai, ek traditional "delete on ack" queue
nahi. Interview ke liye chahiye wali vocabulary:

- **Topic**: messages ki ek named stream (jaise, `orders`, `page_views`) —
  logical channel jispe producers likhte hain aur consumers padhte hain.
- **Partition**: ek topic multiple partitions mein split hota hai, har ek
  ek ordered, append-only log. Partitions mein split karna hi parallelism
  enable karta hai — different partitions independently likhe aur padhe ja
  sakte hain, load ko machines ke across spread karte hue. Order sirf ek
  single partition ke **andar** guaranteed hai, poore topic mein nahi.
- **Consumer group**: consumer instances ka ek named set jo ek topic padhne
  ka kaam split karte hain. Ek group ke andar, **har partition ek time par
  exactly ek consumer se consume hota hai** — yahi cheez consumption ko
  horizontally scalable banati hai: ek group mein zyada consumer instances
  add karo (partitions ki number tak) aur Kafka automatically unme partitions
  rebalance kar deta hai.
- **Offset**: ek partition ke andar ek consumer ki position (ek integer
  index), yeh mark karta hai woh kitna aage tak padh chuka hai. Kyunki yeh
  bas ek position hai — ek deletion pointer nahi — ek consumer apna offset
  rewind karke purane messages **replay** kar sakta hai, ya ek bilkul naya
  consumer group run kar sakta hai jo poori history offset 0 se padhe.
- **Retention**: Kafka messages ko ek configured time window ya size limit
  ke liye retain karta hai (jaise, 7 days) **chahe woh consume hue ho ya
  nahi** — ek traditional queue ke unlike, ek message padhna use delete
  nahi karta. Yahi cheez replay possible banati hai: ek naya consumer (ya
  ek buggy wala jise reprocess karna hai) un messages ko padh sakta hai jo
  kisi aur ne pehle hi din pehle consume kar liye the.

```text
Topic: orders
  Partition 0: [msg0][msg1][msg2][msg3] --> Consumer group "billing": Consumer A
  Partition 1: [msg0][msg1][msg2]       --> Consumer group "billing": Consumer B
  Partition 2: [msg0][msg1][msg2][msg3][msg4] --> Consumer group "billing": Consumer C

  Same topic, independently read by a second, unrelated group:
  Consumer group "analytics": reads all partitions from its own offsets, unaffected by "billing"
```

Kyunki retention time/size-based hai ack-based nahi, **multiple independent
consumer groups har ek poora topic apni apni speed par padh sakte hain** —
yeh ek traditional queue se fundamentally alag model hai, jahan ek message
gayab ho jaata hai jab koi use ack kar de.

## RabbitMQ / SQS vs Kafka

**RabbitMQ** aur **AWS SQS** traditional message queues hain: ek message ek
consumer ko deliver hota hai, consumer use process karta hai aur ek **ack**
bhejta hai, aur broker phir message delete kar deta hai. Koi replay nahi —
ek baar ack hone aur chale jaane ke baad, woh chala gaya (jab tak aapne apna
khud ka archival na banaya ho).

| | RabbitMQ / SQS | Kafka |
|---|---|---|
| Mental model | Queue — message deleted after ack | Log — message retained regardless of consumption |
| Per-message tracking | Per-message ack/nack, easy to retry a single failed message | Offset-based — tracks position, not per-message state |
| Replay | Not supported natively | Native — rewind offset, or spin up a new consumer group |
| Throughput ceiling | Good for moderate throughput task queues | Built for very high throughput (millions of messages/sec) |
| Multiple independent readers of the same stream | Awkward — typically needs fan-out exchanges/topics per consumer | Natural — every consumer group reads independently |
| Best fit | Task queues, job processing, request/reply patterns, simpler ops | Event streaming, analytics pipelines, event sourcing, systems needing replay or many independent consumers |

Interview ke liye practical rule of thumb: **RabbitMQ/SQS** reach karo jab
aapko bas simple per-message semantics ke saath reliable task distribution
chahiye (jaise, "yeh uploaded image process karo," "yeh email bhejo"). Reach
karo **Kafka** jab aapko replay chahiye, bahut high sustained throughput
chahiye, ya kai unrelated services ko independently same event stream apni
apni speed par consume karna hai.

## Event-driven architecture patterns

Yeh describe karte hain *event khud kya contain karta hai*, transport
mechanism nahi — aap in mein se kisi ko bhi Kafka, RabbitMQ, ya SQS par
implement kar sakte ho.

- **Event notification**: ek chota, minimal event ("kuch hua," jaise,
  `{"orderId": 123, "event": "OrderCreated"}`) — consumer, agar use zyada
  detail chahiye, to source service ke API ko call back karke poora data
  fetch karta hai. Events ko chota aur simple rakhta hai, lekin ek extra
  network call aur source service ke available hone par ek runtime
  dependency add karta hai.
- **Event-carried state transfer**: event khud change ka **poora relevant
  data** carry karta hai (jaise, `{"orderId": 123, "event": "OrderCreated",
  "items": [...], "total": 49.99, "customerId": 456}`). Consumer ko kabhi
  call back karne ki zaroorat nahi — usme sab kuch already hai jo use
  chahiye. Trade-off: events bade ho jaate hain, aur har consumer ab event
  schema par depend karta hai woh sab kuch include karne ke liye jo unhe
  kabhi bhi chahiye ho sakta hai.
- **Event sourcing**: current state directly store karne ke bajaye, aap
  events ki poori **sequence** store karte ho jo us state tak le gayi, aur
  current state un events ko shuru se (ya last snapshot se) replay karke
  **derive** hota hai. Jaise, ek account ka balance ek stored column nahi
  hai — yeh us account par apply hue har `Deposited`/`Withdrawn` event ka
  sum hai. Yeh aapko ek poora audit trail deta hai aur kisi bhi point in
  time ke as-of state reconstruct karne ki ability, lekin yeh real added
  complexity hai (replaying logic, performance ke liye snapshotting, purane
  events ki schema evolution) aur default se reach nahi karna chahiye —
  sirf tab jab audit trail / time-travel / replay capability ek actual
  requirement ho, sirf isliye nahi ki "yeh robust lagta hai."

## Push vs pull consumption

Yeh ek second axis hai jo queue vs pub/sub ke saath jaanna worth hai,
kyunki yeh explain karta hai *kyun* Kafka aur RabbitMQ load ke under itne
alag behave karte hain:

- **Push-based** (RabbitMQ, SQS-with-long-polling-pushed-to-workers): broker
  actively messages ko consumers ko bhejta hai jaise woh arrive/available
  hote hain. Lower latency (koi polling delay nahi), lekin broker ko
  actively consumer speed manage karni padti hai — agar woh ek consumer se
  fast push karta hai jitna woh handle kar sakta hai, to consumer overwhelmed
  ho jaata hai unless protocol mein ek explicit flow-control mechanism ho
  (jaise, RabbitMQ ka "prefetch count," jo cap karta hai ki ek consumer ek
  time par kitne unacked messages hold kar sakta hai).
- **Pull-based** (Kafka): consumers actively agla batch of messages apni
  apni speed par request karte hain, apna khud ka offset track karte hue.
  Yeh naturally self-regulate karta hai — ek slow consumer bas kam often
  pull karta hai aur apne khud ke offset mein peeche reh jaata hai, bina
  broker ko kuch special karne ki zaroorat ke — aur yahi cheez replay ko
  trivial banati hai (bas ek purana offset maango).

Pull-based hona ek bada reason hai kyun Kafka very high throughput aur kai
independent consumer groups ko achhi tarah handle karta hai: broker ko
per-consumer delivery state track karne ki zaroorat nahi hai "yeh consumer
ka offset kahan hai" ke alawa, jabki ek push broker jo delivery aur acks
actively manage karta hai kai different consumers ke liye uske paas per
message zyada bookkeeping hai.

## Dead-letter queues and poison messages

Ek **poison message** ek aisa message hai jise ek consumer kabhi successfully
process nahi kar sakta — jaise, yeh malformed hai, ya yeh ek bug trigger
karta hai jo har retry par consumer ko crash kar deta hai. Bina ek safety
valve ke, ek consumer jo at-least-once delivery use karta hai, wahi message
forever retry karta rahega, use queue/partition mein uske peeche wale sab
kuch se progress karne se block karte hue (yeh especially damaging hai
point-to-point queues mein jahan ordering matter karti hai, ya Kafka mein
jahan ek stuck partition har message ko block karta hai uske peeche jab tak
offset advance na ho).

Ek **dead-letter queue (DLQ)** standard fix hai: ek message ke kuch configured
number of times fail hone ke baad (jaise, 5 retries), yeh automatically main
queue se nikal ke ek separate DLQ mein move ho jaata hai indefinitely retry
hone ke bajaye. Main queue flow karta rehta hai; DLQ un messages ko accumulate
karta hai jinhe manual investigation ya ek code fix chahiye reprocess hone
se pehle. RabbitMQ aur SQS dono DLQs ko natively support karte hain; Kafka
ka equivalent typically application banati hai (processing error catch
karo, failed message ko ek separate `*-dlq` topic par publish karo, phir
offset advance karo taaki partition stuck na rahe).

## Backpressure

**Backpressure** woh hai jo hota hai jab producers consumers se faster
messages generate karte hain jitna woh process kar sakte hain — gap badhta
jaata hai, aur system ko ek deliberate strategy chahiye nahi to yeh
uncontrolled degrade ho jaata hai (unbounded memory growth, cascading
timeouts, eventual crash).

Strategies:
- **Bounded queues jo upstream push back karti hain**: queue size cap karo,
  aur full hone ke baad, producer ko wait karwao ya naye writes reject
  karo — yeh slowdown ko source tak wapas propagate karta hai use hide
  karne ke bajaye, producer (ya jo bhi uske upstream hai) ko overload ko
  explicitly deal karne ke liye force karte hue instead of silently
  unbounded backlog accumulate karne ke.
- **Load shedding**: deliberately lower-priority messages/requests drop
  karo jab overloaded ho, higher-priority ones ke liye capacity protect
  karne ke liye — ek explicit, controlled trade-off instead of ek
  uncontrolled failure ke.
- **Consumer autoscaling**: zyada consumer instances add karo (jaise, ek
  consumer group mein zyada workers) queue depth/lag badhne ke response
  mein, taaki processing capacity load ke saath badhe.
- **Buffering with retention**: Kafka ka approach — kyunki messages padhe
  jaane par delete nahi hote, ek burst bas log mein baitha rehta hai jab
  tak consumers catch up na kar lein; jab tak retention window/size exceed
  nahi hota, koi data lose nahi hota, bas delay hota hai.

## Trade-offs / When to use what

| Scenario | Choice | Why |
|---|---|---|
| Distribute jobs across a worker pool, each job done once | Point-to-point queue (SQS/RabbitMQ) | Built-in work distribution, simple ack model |
| Notify multiple independent services of an event | Pub/sub (SNS, Kafka topic, RabbitMQ fan-out exchange) | Every subscriber needs its own copy |
| Need to replay history or support new consumers reading old data | Kafka | Retention-based, replayable log |
| Very high sustained throughput, ordered per key | Kafka (partitioned by key) | Partitions parallelize while preserving per-key order |
| Simple task queue, minimal ops overhead | SQS/RabbitMQ | Simpler mental model, less to operate than a Kafka cluster |
| Guaranteeing no double-processing on retries | At-least-once delivery + idempotent consumer | True exactly-once is impractical at scale; this achieves the same effect |

## Interview Tips

- Jab kisi design mein koi "doosri services ko notify karo" ya "isse
  asynchronously process karo" requirement ho, proactively ek synchronous
  call ki jagah ek queue/event bus suggest karo — interviewers check karte
  hain ki aap exactly in cases ke liye default se decoupling karte ho ya
  nahi (slow downstream, traffic spikes, fault isolation).
- Agar aap "exactly-once" bolte ho, to interviewer likely push karega ki
  kaise — strong answer hai "at-least-once delivery plus ek idempotent
  consumer jo ek dedup key use kare," "message broker guarantee karta hai"
  nahi.
- Ek direct "yahan Kafka use karoge ya SQS?" question expect karo —
  ek specific property se justify karo (replay chahiye → Kafka; simple job
  queue, minimal ops → SQS), "Kafka zyada scalable hai" jaisi ek blanket
  statement se nahi.
- Agar ek design mein ordering requirements mention hon ("ek diye gaye
  user ke events ko order mein process karo"), to Kafka partitioning by key
  mention karo — same key wale messages same partition par jaate hain aur
  uske andar order mein process hote hain, lekin poore topic mein koi
  global ordering nahi hoti.
- Event sourcing reach mat karo jab tak sawaal explicitly ek audit trail ya
  point-in-time reconstruction na maange — ise default ki tarah propose
  karna ek common over-engineering tell hai.

## Quick Recall — Self-Test

**Q1: Asynchronous messaging kaunse teen problems solve karti hai jo synchronous calls nahi karte?**
Decoupling (producer ko consumers ke baare mein janne ya unpar depend karne ki zaroorat nahi), traffic spikes ko smooth karna (bursts ko buffer karna instead of unke under reject ya collapse hone ke), aur fault isolation (ek slow/down downstream failure/latency wapas producer tak propagate nahi karta).

**Q2: Ek point-to-point queue aur pub/sub mein fundamental difference kya hai?**
Ek queue har message ko exactly ek consumer ko deliver karti hai (ek pool ke across kaam distribute karne ke liye), jabki pub/sub har message ko har subscriber ko broadcast karta hai (ek event ko multiple independent, unrelated consumers ko fan out karne ke liye).

**Q3: "Exactly-once" delivery usually literally implement kyun nahi hoti, aur iski jagah kya use hota hai?**
Transport level par true exactly-once effectively har message par distributed consensus require karta hai, jo scale par too expensive hai. Practice mein systems at-least-once delivery (kabhi silently drop na karo, duplicates tolerate karo) ko idempotent consumers ke saath combine karte hain, same practical effect ("effectively-once") achieve karte hue.

**Q4: Kafka mein, ek group ke andar kitne consumers parallel mein ek topic process kar sakte hain yeh kya determine karta hai, aur agar aap partitions se zyada consumers add karo to kya hota hai?**
Partitions ki number ek consumer group ke andar parallelism ki ceiling hai, kyunki har partition ek time par group ke exactly ek consumer se consume hota hai. Partition count se zyada extra consumers idle baithe rehte hain unhe kuch assign hue bina.

**Q5: Kafka ka retention model RabbitMQ/SQS se kaise alag hai, aur yeh kyun matter karta hai?**
Kafka messages ko ek configured time/size ke liye retain karta hai chahe woh consume hue ho ya nahi, isliye messages replay ho sakte hain aur multiple independent consumer groups poori stream apni apni speed par padh sakte hain. RabbitMQ/SQS ek message delete kar dete hain jaise hi woh ack ho jaaye, isliye koi native replay nahi hai aur ek doosre, baad wale consumer ke history dekhne ka koi clean tareeka nahi.

**Q6: Event notification aur event-carried state transfer mein kya difference hai, aur har ek kya trade off karta hai?**
Event notification ek minimal "kuch hua" ping bhejta hai aur consumer ko details ke liye call back karne ki zaroorat padti hai (chote events, extra network dependency); event-carried state transfer poora changed data event ke andar hi embed kar deta hai (koi callback nahi chahiye, lekin bade events aur har consumer event schema par depend karta hai).

**Q7: Event sourcing specifically kab choose karoge, aur yeh default choice kyun nahi honi chahiye?**
Ise choose karo jab aapko genuinely ek poora audit trail ya kisi past point in time tak state reconstruct karne ki ability chahiye. Yeh default isliye nahi hai kyunki events replay karna, performance ke liye snapshotting, aur time ke saath event schemas evolve karna real, ongoing complexity add karte hain jo zyada tar applications ko nahi chahiye.

**Q8: Backpressure handle karne ke do concrete strategies naam batao jab consumers producers ke saath keep up nahi kar paate.**
Bounded queues jo full hone par producers par push back karti hain (slowdown ko hide karne ke bajaye upstream surface karti hain), aur consumer autoscaling (badhte queue depth/lag ke response mein zyada consumer instances add karna). Load shedding aur retention-based buffering (Kafka ka approach) baaki do cover hue hain.

**Q9: Push-based aur pull-based message consumption mein practical difference kya hai, aur yeh scaling ke liye kyun matter karta hai?**
Push-based brokers (RabbitMQ) actively consumers ko messages bhejte hain aur ek slow consumer ko overwhelm hone se bachane ke liye explicit flow control chahiye hoti hai (jaise ek prefetch limit). Pull-based brokers (Kafka) consumers ko apni apni speed par messages request karne dete hain, jo naturally self-regulate karta hai aur broker se kam per-consumer bookkeeping chahiye hoti hai — yeh ek badi wajah hai Kafka high throughput aur kai independent consumer groups tak achhi tarah scale karta hai.

**Q10: Ek dead-letter queue kya hai, aur yeh kya problem solve karta hai?**
Yeh ek separate queue hai jispar ek poison message (jo repeatedly process karna fail karta hai, jaise malformed data ya ek triggered bug ki wajah se) ek configured number of failed attempts ke baad automatically move ho jaata hai, forever retry hone ke bajaye. Yeh ek single unprocessable message ko main queue/partition mein uske peeche wale sab kuch block karne se rokta hai jabki manual investigation ke liye message preserve karta hai.
