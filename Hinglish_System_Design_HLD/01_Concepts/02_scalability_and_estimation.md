# Scalability and Estimation

## Yeh important kyun hai

"Ise scalable banao" bina numbers ke meaningless hai. Estimation ke bina, teams ya toh over-engineer kar deti hain (multi-region, sharded, queue-everything systems bana dete hain ek product ke liye jiske 500 users hain — engineering time aur ongoing operational cost mahino tak burn karte hain us headroom ke liye jo kisi ko chahiye hi nahi) ya under-engineer kar deti hain (ek single unindexed Postgres instance launch kar dete hain us product ke peeche jo viral ho jaata hai aur kisi ke bhi test kiye load se 10x load par gir jaata hai). Estimation woh tool hai jo aapko, code ki ek line likhne se pehle, roughly bataata hai ki aap kaunse regime mein ho — "yeh ek beefy box par fit ho jaayega" vs "isko day one se hi horizontally distribute karna padega" — taaki architecture actual problem ke saath match kare, kisi ke gut feeling ke saath nahi.

## Vertical vs Horizontal Scaling

**Vertical scaling (scaling up)**: ek single machine ki capacity badhana — zyada CPU, RAM, faster disk (jaise, ek database ko 4-core/16GB instance se 64-core/512GB instance par move karna).

**Horizontal scaling (scaling out)**: zyada machines add karna aur unke beech load distribute karna (jaise, app ko 1 huge server ke bajaye load balancer ke peeche 20 chhote servers par run karna).

| | Vertical Scaling | Horizontal Scaling |
|---|---|---|
| Kaise | Bigger machine | More machines |
| Cost curve | Linearly se zyada fast badhta hai — top-tier hardware ka steep price premium hota hai, aur ek hard ceiling hoti hai (biggest machine jo paison se khareedi ja sake) | Roughly linear — commodity machines cheap hoti hain aur bas aap zyada add karte jaate ho |
| Single point of failure | Haan — ek machine, ek failure domain | Nahi, agar sahi se kiya jaaye — ek node ke marne se system down nahi hota |
| Operational complexity | Kam — ek machine patch karni, monitor karni, backup leni hai | Zyada — service discovery, load balancing, distributed monitoring, deployment orchestration |
| Statefulness | Problem nahi hai — saara data/state ek hi machine par rehta hai | Ek real problem hai — in-memory state, sessions, aur data ko externalize ya partition karna padta hai kyunki koi bhi request kisi bhi node par land kar sakti hai |
| Upgrade ke liye downtime | Often restart/resize chahiye hota hai (brief downtime) | Typically zero downtime ke saath nodes roll in/out ho sakte hain |
| Ceiling | Hard physical/hardware ceiling | Practically unbounded (aur nodes add karo) |

System design mein baar-baar aane wala theme: horizontal scaling default target hota hai kisi bhi cheez ke liye jo ek machine se zyada grow karne wali expect ho, lekin yeh free nahi hai — yeh aapko statelessness, coordination, aur distributed failure modes ka saamna karne par force karta hai jinke baare mein vertical scaling aapko kabhi sochne hi nahi deta. Kayi real systems pehle vertically scale karte hain (yeh simpler hai aur real time buy karta hai) aur sirf tab horizontal scaling par move karte hain jab woh ceiling hit kar lein ya redundancy chahiye ho.

## Latency vs Throughput

**Latency**: ek single operation complete karne ka time (jaise, "yeh API call 120ms leti hai").

**Throughput**: unit time mein complete hui operations ki number (jaise, "yeh service 5,000 requests/second handle karti hai").

Yeh sunne mein similar lagte hain lekin same axis nahi hain, aur ek ko improve karna doosre ko hurt kar sakta hai. Example: **batching**. Agar ek service 100 write requests ko buffer karti hai aur har 50ms mein unhe ek batch mein database ko flush karti hai, toh throughput badh jaata hai (kam, bade DB round-trips 100 chhote round-trips se kaafi zyada efficient hote hain), lekin kisi individual request ki latency bhi badh jaati hai (ek request jo flush ke turant baad aaya, ab woh next batch mein include hone se pehle 50ms tak wait karta hai). Conversely, har request ko immediately, ek-ek karke process karna per-request latency ko minimize karta hai lekin throughput ko lower cap kar deta hai kyunki aap per-operation overhead (connection setup, lock contention, network round-trips) har single request par pay kar rahe ho, usse amortize karne ke bajaye.

Yeh trade-off constantly dikhta hai: bade batches, bade buffers, aur queuing sab throughput ko raise karte hain saath hi tail latency ko bhi raise karte hain.

## Availability aur "the Nines"

**Availability**: woh fraction of time jitne mein ek system requests ko correctly serve karne ke capable hota hai, usually ek year ke over percentage mein express kiya jaata hai. Commonly describe kiya jaata hai ki usme kitne "9" hain.

Arithmetic: ek non-leap year mein 365 × 24 = 8,760 hours hote hain. Per year allowed downtime = (1 − availability) × 8,760 hours.

| Availability | Downtime / year (hours) | Downtime / year (human terms) |
|---|---|---|
| 90% ("one nine") | 0.10 × 8,760 = 876 hours | ~36.5 days |
| 99% ("two nines") | 0.01 × 8,760 = 87.6 hours | ~3.65 days |
| 99.9% ("three nines") | 0.001 × 8,760 = 8.76 hours | ~8 hours 46 minutes |
| 99.99% ("four nines") | 0.0001 × 8,760 = 0.876 hours | 0.876 × 60 = 52.6 minutes |
| 99.999% ("five nines") | 0.00001 × 8,760 = 0.0876 hours | 0.0876 × 60 = 5.26 minutes |

Har additional nine allowed downtime ko roughly 10x kaat deta hai — aur agla nine buy karne ki engineering cost non-linearly badhti hai (99% se 99.9% jaane ka matlab "ek second server add karo" ho sakta hai; 99.99% se 99.999% jaane ka matlab multi-region active-active failover, chaos testing, aur ek dedicated on-call reliability team ho sakta hai). Isliye right availability target pick karna — sirf maximum ke peeche na bhagna — khud ek design decision hai jiske real cost trade-offs hain.

## SLA vs SLO vs SLI

Yeh teen terms often confuse ho jaate hain; yeh teeno same underlying metric ko teen different angles se describe karte hain.

- **SLI (Service Level Indicator)**: kisi metric ki actual, measured value. Jaise, "hamara measured p99 read latency last 30 days mein 260ms hai." Yeh ek fact hai, real traffic se observe kiya gaya.
- **SLO (Service Level Objective)**: us metric ke liye ek internal target jo team commit karti hai. Jaise, "hum p99 latency 300ms se kam rakhne ka aim rakhte hain." Yeh ek goal hai jo engineering priorities aur alerting thresholds drive karta hai.
- **SLA (Service Level Agreement)**: ek external, often contractual, promise customers ko, usually consequences ke saath (service credits, financial penalties) agar miss ho jaaye. Jaise, "hum guarantee karte hain p99 latency 500ms se kam, warna aapko us month ke liye service credit milega."

Practice mein relationship: SLAs deliberately SLOs se looser set kiye jaate hain, jo ki SLI actually achieve kar raha hai usse looser set kiye jaate hain — isse aapko ek buffer milta hai taaki normal variance kisi customer-facing contract ko breach na kare. Concrete chain: SLI = 260ms measured → SLO = 300ms internal target (isse pehle aapko page kiya jaayega jab yeh risk mein ho) → SLA = 500ms external promise (isko cross karna company ka paisa lena hai). SLO aur SLA ke beech ka gap aapka safety margin hai.

## Back-of-Envelope Estimation

Method, step by step:

**1. DAU (Daily Active Users) aur actions/user/day se QPS (queries per second) estimate karo**
```
total actions/day = DAU × actions per user per day
average QPS       = total actions/day ÷ seconds/day (86,400)
peak QPS          = average QPS × peak factor (commonly ~2-3x average,
                     yeh account karne ke liye ki traffic din bhar uniform nahi rehta)
```

**2. Record size, count, retention, aur replication se storage estimate karo**
```
total records         = records created per day × retention period (days)
raw storage           = total records × size per record
total storage (stored) = raw storage × replication factor
```

**3. QPS aur payload size se bandwidth estimate karo**
```
bandwidth ≈ QPS × average payload size
```

### Worked example

Scenario: ek social app jiske **100M DAU** hain, har user average **2 baar/din** post karta hai, har post (metadata ke saath) **~1KB** ki hai, data **3x replication** ke saath rakha jaata hai, aur **5 years** ke liye retain kiya jaata hai.

**QPS (writes):**
```
total posts/day = 100,000,000 users × 2 posts/user = 200,000,000 posts/day
average QPS     = 200,000,000 ÷ 86,400 sec ≈ 2,315 writes/sec
peak QPS (3x)   = 2,315 × 3 ≈ 6,944 writes/sec  (~7,000 QPS at peak)
```

**5 years ke over total storage:**
```
total posts over 5 years = 200,000,000 posts/day × 365 days × 5 years
                          = 200,000,000 × 1,825
                          = 365,000,000,000 posts (365 billion)

raw storage = 365,000,000,000 posts × 1 KB = 365,000,000,000 KB
            = 365,000,000 MB = 365,000 GB = 365 TB

3x replication ke saath = 365 TB × 3 ≈ 1,095 TB ≈ 1.1 PB (petabytes)
```

**Daily write bandwidth:**
```
daily bandwidth = posts/day × size/post
                = 200,000,000 × 1 KB = 200,000,000 KB
                = 200,000 MB = 200 GB/day ingested (write path, pre-replication)

average bandwidth ≈ 2,315 QPS × 1 KB/post ≈ 2.26 MB/sec sustained
peak bandwidth    ≈ 6,944 QPS × 1 KB/post ≈ 6.8 MB/sec at peak
```

In numbers se conclusion: peak par ~7,000 writes/sec aur 5 saal mein ~1.1 PB squarely "horizontal scaling aur ek proper distributed storage/sharding strategy chahiye" wale territory mein aata hai — ek single relational database instance directly yeh sab handle kare toh woh write throughput aur raw disk capacity dono par struggle karega, isse aapko immediately pata chal jaata hai ki design mein sharding, media ke liye ek distributed object store, ya ek append-friendly storage engine jaisi cheezein include honi chahiye, ek single API endpoint ke baare mein sochne se bhi pehle.

## Latency Numbers Jo Har Programmer Ko Pata Hone Chahiye

Common operations ke approximate, order-of-magnitude figures (exact numbers hardware/network ke hisaab se vary karte hain, lekin *relative* gaps hi matter karte hain):

| Operation | Approximate latency |
|---|---|
| L1 cache reference | ~1 nanosecond |
| Main memory (RAM) reference | ~100 nanoseconds |
| SSD random read | ~100-150 microseconds |
| Round trip within same datacenter | ~0.5 millisecond |
| Disk seek (spinning HDD) | ~10 milliseconds |
| Round trip cross-region / cross-continent | ~100-150 milliseconds |

Exact nanosecond values memorize karna point nahi hai — **relative magnitudes** memorize karna point hai: memory SSD se ~100x faster hai, ek in-datacenter round trip ek memory access se ~1,000x slow hota hai, aur ek cross-region round trip memory se ~100,000x+ slow hota hai. Isi liye aap hot data ko memory mein cache karte ho instead of use har request par disk se re-read karne ke, aur isi liye cross-region calls ko hot path se door rakha jaata hai (jaise, aap data ko us region mein replicate kar dete ho instead of har user request par synchronously kisi doosre continent ko query karne ke) — gap itna bada hai ki ek single unnecessary cross-region call aapke poore request ke latency budget par dominate kar sakta hai.

## Kab kya use karein

| Situation | Kaunsa lena chahiye |
|---|---|
| Chhota/predictable load, fast move karna hai | Vertical scaling — simplicity jeetegi, time buy karo |
| Load ek machine ki ceiling se aage badhega, ya redundancy chahiye | Horizontal scaling — added complexity accept karo |
| User-facing interactive request | Latency ke liye optimize karo (individual request feel) |
| Bulk/background data processing | Throughput ke liye optimize karo (batch karo, per-item delay accept karo) |
| Consumer product at scale | Higher nines (99.9-99.99%) revenue/reputation impact se justified hain |
| Internal tool, low usage | 99% ya usse bhi kam often perfectly fine hai — over-invest mat karo |

## Interviewers estimation kyun important maante hain

Koi bhi keh sakta hai "yeh fast aur scalable hona chahiye" — yeh ek slogan hai, analysis nahi. Back-of-envelope calculation karna aapko concrete numbers (QPS, storage, bandwidth) par commit karne ke liye force karta hai jo phir real architectural decisions ko *drive* karte hain: thousands ke range ki QPS numbers ek well-indexed single database ke aage cache lagakar fine ho sakti hain; hundreds of thousands ki QPS numbers ko clearly horizontal partitioning chahiye. Interviewers is step ka use karke check karte hain ki aap ek vague requirement ko ek quantified constraint mein translate kar sakte ho, aur ki aapki architecture actually us number ka response hai, na ki ek generic "microservices + Kafka + Redis" template jo scale ki parwaah kiye bina apply kar diya gaya ho.

## Quick Recall — Self-Test

**Q1: Horizontal scaling kaunsa key operational trade-off introduce karta hai jo vertical scaling avoid kar leta hai?**
Statefulness. Vertical scaling mein, saara data/state ek machine par rehta hai isliye coordinate karne ko kuch nahi hota. Horizontal scaling mein, koi bhi request kisi bhi node par land kar sakti hai, isliye in-memory state aur sessions ko externalize karna padta hai (jaise, Redis mein) ya data ko partition karna padta hai — isse real coordination aur consistency complexity add hoti hai.

**Q2: Throughput improve karne se kabhi-kabhi latency kyun worsen ho sakti hai? Ek concrete mechanism batao.**
Batching classic mechanism hai: kayi operations ko ek batch mein group karna (jaise, har 50ms mein 100 writes flush karna) throughput badhata hai per-operation overhead amortize karke, lekin ab kisi individual request ko batch window close hone ka wait karna padta hai, jisse uski apni latency badh jaati hai.

**Q3: 99.95% availability ke liye annual downtime compute karo.**
Downtime = (1 − 0.9995) × 8,760 hours = 0.0005 × 8,760 = 4.38 hours/year (lagbhag 4 hours 23 minutes).

**Q4: SLI/SLO/SLA chain mein, kaunsa financial/contractual consequences carry karta hai, aur woh typically internal target se looser kyun set kiya jaata hai?**
SLA financial/contractual consequences carry karta hai (jaise, breaches ke liye service credits). Yeh SLO se looser set kiya jaata hai taaki measured SLI ka normal variance accidentally kisi customer contract ko breach na kar de — SLO ek internal early-warning buffer ki tarah SLA line ke upar act karta hai.

**Q5: Kisi feature ke liye storage requirements estimate karne ke liye aapko kaunse teen inputs chahiye?**
Record size (bytes per record), retention window ke over record count (creation rate × retention period), aur replication factor — total storage = record size × count × retention-driven count × replication factor.

**Q6: Exact numbers ke bajaye relative latency gaps (memory vs disk vs cross-region) kyun memorize karein?**
Kyunki system design jis reasoning par depend karta hai woh comparative hoti hai: yeh jaanna ki memory access SSD se ~100x faster hai aur ek same-datacenter round trip ek memory access se roughly ~1,000x slow hota hai — yehi cheez hot data cache karne aur hot path par synchronous cross-region calls avoid karne ko justify karti hai — exact nanosecond figures woh nahi hain jo architectural decision drive karte hain, order-of-magnitude gap karta hai.

**Q7: Ek system 500 average QPS karta hai. 3x peak factor use karke, estimated peak QPS kya hai, aur hum peak factor apply hi kyun karte hain?**
Peak QPS ≈ 500 × 3 = 1,500 QPS. Peak factor isliye apply kiya jaata hai kyunki traffic din bhar uniform nahi hota (yeh usage peaks jaise evenings ya lunch hours ke around cluster hota hai), isliye sirf daily average ke liye design karna system ko exactly tab under-provisioned chhod dega jab sabse zyada matter karta hai.

**Q8: Aap deliberately higher availability pursue na karne ka decision kab lenge (jaise, 99.99% push karne ke bajaye 99% par stick karna)?**
Jab agle nine ki cost/complexity (multi-region failover, dedicated on-call, redundant infra) system ke actual business impact se justify na ho — jaise, ek internal admin tool jo handful employees business hours mein use karte hain usse five-nines engineering investment ki zaroorat nahi.
