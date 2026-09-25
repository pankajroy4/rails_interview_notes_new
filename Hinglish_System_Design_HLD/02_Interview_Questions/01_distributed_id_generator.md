# Design a Unique ID Generator (Twitter Snowflake)

## Problem Statement

"Humare paas ek distributed system hai — hundreds of application servers,
dozens of database shards — aur jo bhi row hum likhte hain (tweets, orders,
events) usko ek unique identifier chahiye. Aisi service design karo jo is
poore fleet ke across unique IDs generate kare, high throughput ke saath,
bina kisi coordination bottleneck ke. Ideally IDs roughly creation time ke
hisaab se sortable bhi hone chahiye, kyunki humein 'recent tweets' ko
efficiently fetch karna hai bina kisi secondary index ke."

Yeh canonical framing hai (Twitter ke original Snowflake blog post se), lekin
yahi problem tab bhi aati hai jab bhi ek single auto-increment column
handle nahi kar paata: sharded e-commerce DB mein order IDs, chat system mein
message IDs, analytics pipeline mein event IDs.

## Step 1: Clarify Requirements

**Functional Requirements**
- Har request pe ek unique ID generate karna, jisme kabhi bhi do callers ko
  same ID na mile (globally, saare machines ke across, hamesha ke liye).
- IDs roughly time-sortable hone chahiye — jo ID baad mein generate hui ho
  woh (almost hamesha) numerically pehle wali se badi honi chahiye, taaki
  `ORDER BY id` approximately `ORDER BY created_at` jaisa result de bina
  ek separate index ke.
- IDs ko directly primary key / shard key ki tarah use kiya ja sake (ek
  standard 64-bit integer column mein fit ho, uniqueness validate karne ke
  liye koi external lookup na chahiye).
- Service ko multiple independent generator instances (machines/processes)
  ke across kaam karna chahiye bina un instances ko hot path pe ek doosre se
  baat karne ki zaroorat ke.

**Non-Functional Requirements**
- **Throughput**: bahut high ID-issuance rates support karni hain — Twitter
  ke original numbers tens of thousands of IDs/sec sustained the, aur burst
  mein aur zyada. Hum 100,000 IDs/sec system-wide ke liye size karenge.
- **Latency**: ID generation near-instant hona chahiye — sub-millisecond,
  in-process. Isme hot path pe koi network round trip ya database write
  involve nahi hona chahiye (warna ID generator khud hi wahi bottleneck ban
  jayega jise hataana tha).
- **Availability**: ID generator ka single point of failure nahi hona
  chahiye. Agar ek generator instance mar jaaye, baaki instances IDs issue
  karte rahenge; koi global lock ya single sequencer nahi hoga.
- **Hot path pe koi central coordination nahi**: jo bhi coordination
  chahiye (machine ID assign karna), woh rarely hota hai (sirf startup pe),
  per-ID nahi.
- **Compactness**: IDs ko 64 bits (ek native `bigint`) mein fit hona chahiye,
  na ki UUID jitne 128 bits, kyunki yeh har row, har index, aur system ke
  har foreign key mein store hote hain.
- Consistency model: humein strict global ordering ki zaroorat nahi (ID N+1
  guaranteed nahi hai ki ID N ke baad system-wide create hui ho, sirf yeh ki
  IDs time ke saath upward trend karein aur unique hon) — yeh ek deliberately
  relaxed requirement hai jo poore design ko tractable banata hai.

## Step 2: Back-of-Envelope Estimation

**Assumptions**: ek product jisme 500 million monthly active users hain,
jo roz 1 billion naye "posts" (ya orders, ya events) generate karta hai,
peak-to-average ratio 3x ke saath (traffic flat nahi hota — peak hours ke
aas paas spike karta hai).

**Throughput**
- Average: 1,000,000,000 / 86,400 sec ≈ 11,574 IDs/sec average.
- Peak (3x average): ≈ 34,722 IDs/sec.
- Headroom aur multi-year growth ke liye round up karke: 100,000 IDs/sec
  sustained system-wide ko target ceiling maankar design karenge.

**Per-machine capacity (yeh number bit layout drive karta hai)**
- Agar ID ke 12 bits ek per-millisecond sequence counter ke liye allocate
  karein, toh ek machine ek single millisecond ke andar 2^12 = 4,096 unique
  IDs issue kar sakti hai next millisecond tick ka wait kiye bina.
- 4,096 IDs/ms = 4,096,000 IDs/sec **per machine**.
- Humara 100,000 IDs/sec system-wide target hit karne ke liye ek machine ki
  capacity se bhi kaafi kam chahiye — practically hum availability ke liye
  (single point of failure na ho) aur generator ko un services ke saath
  co-locate karne ke liye (aksar ek library ki tarah embedded, standalone
  service ki jagah) multiple generator instances chalate hi hain.

**Storage / bandwidth**
- Har ID ek 64-bit integer hai = 8 bytes.
- 1 billion IDs/day x 8 bytes = 8 GB/day pure ID data ka, lekin IDs standalone
  store nahi hote — yeh us row ki primary key hote hain jisko woh identify
  karte hain, toh yeh cost row storage mein hi fold ho jaati hai, ek
  separate concern nahi.
- ID generator ka khud ka network cost effectively zero hai agar yeh
  in-process library call hai; agar yeh ek network service hai, toh 100,000
  req/sec x ~20 bytes (request + response) ≈ 2 MB/sec, ek single link ke
  liye trivial.

**Machine ID space**
- 10 bits ka machine ID 2^10 = 1,024 distinct generator instances deta hai
  jo bina ID collisions ke concurrently chal sakte hain. Kuch sau se lekar
  ~1,000 app servers tak ke fleet ke liye jinme generator embedded ho, yeh
  comfortably sufficient hai.

## Step 3: High-Level Design

Generator typically **har application server ke andar ek library ki tarah
embedded** hota hai (na ki koi centralized network service jise HTTP pe call
karo, halaanki isko waise bhi deploy kiya ja sakta hai) — yehi key design
choice hai jo hot-path bottleneck ko poori tarah se hata deti hai. Har
instance:

1. Apna khud ka unique machine ID jaanta hai (ek baar assign hota hai,
   startup pe).
2. System clock read karta hai current timestamp lene ke liye.
3. Ek in-memory, per-millisecond sequence counter maintain karta hai.
4. (timestamp, machine ID, sequence) ko ek single 64-bit integer mein pack
   karke return karta hai — koi network call nahi, koi database write nahi,
   doosre machines ke saath koi lock contention nahi.

```text
                    +--------------------------------------+
                    |         Coordination Service          |
                    |   (ZooKeeper / etcd / config store)    |
                    |  - assigns each app server a unique    |
                    |    machine_id (0-1023) at startup      |
                    +--------------------+-------------------+
                                         | (once, at boot)
                                         v
   +----------------+    +----------------+    +----------------+
   |  App Server 1   |    |  App Server 2   |    |  App Server N   |
   |  machine_id=1   |    |  machine_id=2   |    |  machine_id=N   |
   |                 |    |                 |    |                 |
   |  +-----------+  |    |  +-----------+  |    |  +-----------+  |
   |  | Snowflake |  |    |  | Snowflake |  |    |  | Snowflake |  |
   |  | Generator |  |    |  | Generator |  |    |  | Generator |  |
   |  | (in-proc) |  |    |  | (in-proc) |  |    |  | (in-proc) |  |
   |  +-----+-----+  |    |  +-----+-----+  |    |  +-----+-----+  |
   +--------|--------+    +--------|--------+    +--------|--------+
            v                      v                      v
      new_id -> DB row       new_id -> DB row       new_id -> DB row
      (no cross-machine communication needed to generate an ID)
```

Agar standalone network service ki tarah deploy kiya jaaye (kabhi kabhi yeh
isliye kiya jaata hai taaki application code ko har language mein jo
polyglot fleet use karti hai, generator logic embed na karna pade), tab bhi
har generator instance independently, ek load balancer ke peeche kaam karta
hai — load balancer ko sticky sessions ki zaroorat nahi hoti kyunki koi bhi
instance kisi bhi request ko serve kar sakta hai, bas usko ek unique
`machine_id` chahiye.

## Step 4: API Design

Chahe library ki tarah embedded ho, phir bhi "interface" describe karna
useful hai — ya toh ek in-process method call, ya standalone deployment ke
liye ek thin RPC.

**`generate_id()` (library call, in-process)**
```
Input:  none
Output: 719283740981248001   (int64)
```

**`POST /v1/ids` (standalone service variant)**
```json
Request: {}
Response: {
  "id": 719283740981248001,
  "generated_at_ms": 1757740800123,
  "machine_id": 42
}
```

**`POST /v1/ids/batch` (batch variant, bulk-insert workloads ke liye round trips kam karta hai)**
```json
Request:  { "count": 100 }
Response: { "ids": [719283740981248001, 719283740981248002, "..."] }
```

**`GET /v1/machine-id/lease` (internal, coordination-service-backed, sirf startup pe ek baar call hota hai, per-ID nahi)**
```json
Request:  { "hostname": "app-server-17" }
Response: { "machine_id": 42, "lease_expires_at": 1757744400 }
```

## Step 5: Data Model

Generator ke liye ek traditional "data model" nahi hai — yeh stateless
per-request hai — lekin do cheezein store hoti hain:

1. **Machine ID assignments** — `hostname -> machine_id` ka ek chhota
   mapping, coordination service (ZooKeeper/etcd) mein hold hota hai, na ki
   ek relational database mein. Yeh coordination service ke liye ek natural
   fit hai relational database ki jagah, kyunki jo chahiye woh exactly wahi
   hai jo yeh services provide karti hain: ephemeral nodes jo ek session se
   tied hote hain (taaki ek crash hue server ka machine ID automatically
   release ho jaaye), involved thoda-sa writes ke liye strong consistency,
   aur ek watch/notify mechanism. Dekho `01_Concepts/09_distributed_systems_core.md`
   yeh samajhne ke liye ki ZooKeeper-style coordination services kaise kaam
   karti hain.

   ```text
   /snowflake/machine-ids/42  ->  { hostname: "app-server-17", leased_at: ... }
   ```

2. **Generated IDs khud** generator dwara kahin store nahi kiye jaate —
   yeh jis bhi row se attach hote hain uski primary key ban jaate hain, us
   row ke apne database mein (SQL ya NoSQL, ID ki value se shard ho ya kisi
   aur key se — ID generator ko farak nahi padta).

## Step 6: Deep Dive

### 6.1 Naive approaches kyun fail hoti hain

- **Database auto-increment (`AUTO_INCREMENT` / `SERIAL`)**: single
  database pe trivial hai, lekin sharding ke saath hi break ho jaata hai.
  Agar tumhare paas 8 shards hain jinke apne apne auto-increment counters
  hain, toh shard 1 ki row 500 aur shard 2 ki row 500 collide kar jaayengi.
  Tum har shard ke liye ID ranges pre-allocate kar sakte ho (shard 1 ko
  1-1M milte hain, shard 2 ko 1M-2M, waise hi) lekin isme upfront manual
  coordination chahiye hoti hai aur jab tum shard 9 add karte ho toh yeh
  elastically scale nahi karta. Ek single global auto-increment table bhi
  ek write bottleneck aur single point of failure ban jaata hai — system
  mein kahin bhi koi insert pehle isse round-trip karta hai.
- **UUIDs (v4, random)**: uniqueness ko khoobsurti se solve karti hain —
  122 bits ki randomness ka matlab hai ki collisions astronomically
  unlikely hain bina kisi coordination ke. Lekin yeh do aur requirements
  mein fail hoti hain: (1) yeh **time ke hisaab se sortable nahi hain** —
  ek UUID jo abhi generate hui aur ek jo ek ghante pehle hui, dono equally
  random dikhti hain, toh "recent rows ek doosre ke paas sort hote hain"
  wali property kho jaati hai jo range scans aur B-tree index inserts ko
  efficient banati hai (random UUID primary keys high insert volume ke
  neeche severe B-tree page splits aur index fragmentation cause karte
  hain); (2) 128 bits pe (ek string ke roop mein 36 characters), yeh ek
  64-bit int ke storage se 2-4x zyada hain, jo har index aur us ID ko
  reference karne wale har foreign key ke across compound ho jaata hai.
  UUIDv7 (time-ordered UUIDs) sortability problem ko fix karta hai lekin
  ek newer standard hai aur phir bhi Snowflake ke 64 bits se zyada bytes
  costs karta hai.

### 6.2 Snowflake ka 64-bit structure

```text
 0                   1                   1
 (sign)  <-- 41 bits timestamp -->  <10 bits-> <-12 bits->
 +---+------------------------------------------+----------+------------+
 | 0 |        timestamp (ms since epoch)          | machine  |  sequence  |
 +---+------------------------------------------+----------+------------+
   1 bit              41 bits                      10 bits      12 bits
                                                                 = 64 bits total
```

- **1 unused/sign bit**: 0 rakha jaata hai taaki value hamesha ek positive
  signed 64-bit integer rahe — yeh matter karta hai kyunki bahut si
  languages aur DB columns (jaise Java `long`, SQL `BIGINT`) signed hote
  hain, aur ek negative ID bugs ka constant source ban jaayega.
- **41 bits timestamp ke liye** (milliseconds since a custom epoch, na ki
  Unix epoch — tum ek recent "epoch" choose karte ho jaise apni company ki
  founding date, taaki useful range maximize ho): 2^41 milliseconds ≈
  2.199 x 10^12 ms ≈ 69.7 years. Custom epoch (jaise 2020-01-01) use karna
  1970-01-01 ki jagah, iska matlab hai ki 69.7-year window 2020 se roughly
  2089 tak chalti hai, na ki Unix epoch ke ~50 already-elapsed years range
  mein waste karna.
- **10 bits machine/worker ID ke liye**: 2^10 = 1,024 concurrently-safe
  generator instances. Kuch implementations isko aur split karte hain
  datacenter ID (5 bits = 32 datacenters) + worker ID (5 bits = 32 workers
  per datacenter) mein, multi-region deployments mein operational clarity
  ke liye.
- **12 bits sequence number ke liye**: 2^12 = 4,096 IDs per machine per
  millisecond. Agar ek single machine same millisecond ke andar 4,097th ID
  generate karne ki koshish karti hai, toh usko ya toh next millisecond
  tick ka wait karna padega ya error return karna padega — practically,
  generators spin-wait (busy-loop) karte hain jab tak clock tick forward
  nahi karta, kyunki 1ms ka wait request latency budgets ke relative
  imperceptible hai.
- **Sortability property**: kyunki timestamp highest-order bits (sign bit
  ke baad) occupy karta hai, baad mein generate hui IDs almost hamesha
  numerically badi values rakhti hain — "almost" isliye kyunki same
  millisecond ke andar, ordering machine ID aur sequence pe depend karti
  hai, machines ke across true arrival order pe nahi. Yeh wahi relaxed
  ordering guarantee hai jo Step 1 mein call out ki gayi thi.

### 6.3 Unique machine IDs assign karna

Machine ID har running instance ke liye unique hona chahiye, warna poori
scheme ki uniqueness guarantee collapse ho jaati hai (agar do machines ka
same ID ho toh same millisecond mein colliding IDs generate ho sakti hain).
Approaches:

- **Coordination service (ZooKeeper/etcd), standard approach**: startup pe,
  har instance ek shared path ke neeche (jaise `/snowflake/workers/`) ek
  **ephemeral sequential znode** create karta hai. ZooKeeper usko agla
  available sequence number uske machine ID ki tarah assign karta hai aur
  znode ki lifetime ko instance ke session se tie kar deta hai — agar
  instance crash ho jaaye ya connection lose kar de, znode automatically
  remove ho jaata hai aur woh machine ID reassignment ke liye available ho
  jaata hai. Yeh exactly wahi leader-election aur ephemeral-node pattern
  hai jo `01_Concepts/09_distributed_systems_core.md` mein describe hua
  hai. Coordination service sirf startup pe (ya network partition ke baad
  reconnect pe) touch hoti hai, per-ID hot path pe kabhi nahi, jo ID
  generation ko request time pe kisi bhi external dependency se free
  rakhta hai.
- **Static config / manual assignment**: chhote, stable fleets ke liye
  sabse simple option — har instance ko deploy time pe environment
  variable ya config file ke through machine ID diya jaata hai (jaise, ek
  Kubernetes StatefulSet ke stable pod ordinal se derive kiya hua,
  `app-server-3` ko machine ID 3 milta hai). Larger scale pe fragile hai
  kyunki isme ek human ya deployment script ko guarantee karni padti hai
  ki kabhi bhi do instances same static ID na paayein, aur yeh
  decommissioned instances se IDs automatically reclaim nahi karta.
- **IP-address ya hostname hashing**: machine ke IP/hostname ko 10-bit
  space mein hash kar do. Fast hai aur koi coordination service nahi
  chahiye, lekin collisions possible hain (do machines same value pe hash
  ho jaayein) aur inko detect aur handle karna padta hai (jaise, collision
  pe coordination service pe fall back karo), isliye yeh usually primary
  mechanism ki jagah ek fallback hota hai.

### 6.4 Clock drift aur clock ka backwards jaana

Yeh poore design ka sabse sharp edge case hai, aur woh jise interviewers
sabse zyada probe karte hain, kyunki poori uniqueness guarantee isi pe
depend karti hai ki timestamp component ek particular machine ke liye
sirf forward hi move kare.

- **Failure mode**: NTP (Network Time Protocol) periodically ek machine ke
  clock ko resynchronize karta hai. Agar machine ka clock fast chal raha
  tha, ek NTP correction clock ko *backwards* jump kara sakta hai. Agar ek
  generator naively `current_time_ms()` read karta hai aur woh value uske
  last use kiye gaye timestamp se kam hai, toh usme risk hai ki ek aisi ID
  generate ho jaaye jiska timestamp already issue hui ID se chhota ho —
  yeh uniqueness (agar sequence counter bhi reset ho jaaye) aur
  sortability guarantee, dono ko break kar deta hai.
- **Mitigation 1 — clock catch up hone tak generate karne se mana karna**:
  generator `last_timestamp` track karta hai, jo uske sabse recently
  generate hui ID ke liye use hua timestamp hai. Har request pe, agar
  `current_time_ms() < last_timestamp`, generator ID generate nahi karta —
  ya toh block/retry karta hai jab tak `current_time_ms() >= last_timestamp`
  na ho jaaye, ya turant caller ko ek error raise kar deta hai ("clock
  moved backwards, refusing to generate ID") taaki caller/operator uspe
  alert kar sake. Twitter ka original Snowflake implementation yehi karta
  hai. Trade-off yeh hai ki us ek machine pe backward jump ke dauran ek
  chhota-sa availability gap hota hai (typically milliseconds, kyunki NTP
  corrections usually chhote hote hain), badle mein ek hard uniqueness
  guarantee milti hai.
- **Mitigation 2 — hybrid logical clocks (HLC)**: sirf wall-clock time pe
  rely karne ki jagah, ek HLC physical clock ko ek logical counter ke
  saath combine karta hai jo guaranteed monotonic hota hai — logical
  component increment hota hai jab bhi physical clock advance nahi hua
  (ya backwards gaya) hai, isse ensure hota hai ki combined (physical,
  logical) pair har machine ke liye hamesha strictly increasing rahe chahe
  clock corrections ho jayein. Yeh "refuse to generate" wale availability
  gap ko poori tarah avoid karta hai, lekin cost pe ek zyada complex ID
  structure aur thodi weaker wall-clock interpretability ke (timestamp
  component ab exactly "yeh ID kab create hui" nahi rehta, bas "isse
  pehle ka nahi").
- **Operational mitigation**: generator hosts pe NTP ko "slew" mode mein
  chalao (clock ko time ke saath gradually adjust karna) na ki "step" mode
  mein (instantaneous jump), aur clock skew monitor karo taaki large
  backward jumps practically rare hon, na ki kuch aisa jo hot path ko
  routinely handle karna pade.
- **Ek millisecond ke andar sequence overflow** iska sibling edge case
  hai: agar ek machine 1ms ke andar 4,096 IDs generate kar deti hai (12-bit
  sequence ceiling hit kar leti hai), toh usko ID #4,097 issue karne se
  pehle millisecond roll over hone ka wait karna padta hai — yeh ek tight
  spin-loop ki tarah implement hota hai jo `current_time_ms() > last_timestamp`
  check karta hai, ek sleep nahi, kyunki wait sub-millisecond hota hai.

## Step 7: Bottlenecks & Trade-offs

- **Sabse pehle kya break hota hai**: agar generator ko ek centralized
  network service ki tarah deploy kiya jaaye (per-app-server embed karne ki
  jagah), toh woh service system ke har write path ke liye ek shared
  dependency ban jaati hai — 100,000+ req/sec pe usko ek load balancer ke
  peeche horizontally scale karna padta hai, aur ek slow ya down ID service
  ab system-wide saare writes ko block kar deti hai. Isi wajah se generator
  ko in-process library ki tarah embed karna preferred hai jab bhi
  deployment language allow kare.
- **Coordination service ek soft dependency ki tarah**: chahe machine-ID
  assignment sirf startup pe hoti ho, agar coordination service (etcd/
  ZooKeeper) down ho jab koi *naya* instance boot ho raha ho (jaise, ek
  autoscaling event ke dauran), toh woh instance machine ID nahi le
  paayega aur IDs issue karna start nahi kar paayega. Isko mitigate karo
  generous machine-ID lease TTLs se aur new instances ko backoff ke saath
  retry karwa ke, turant hard fail karne ki jagah.
- **Clock reliance**: poori scheme yeh assume karti hai ki fleet ke across
  clocks reasonably synchronized hain. Large, uncorrected clock skew
  machines ke beech uniqueness break nahi karta (machine ID phir bhi
  disambiguate kar deta hai), lekin yeh "IDs poore system mein time ke
  saath upward trend karte hain" wali property zaroor break kar deta hai
  jispe downstream consumers approximate global ordering ke liye
  implicitly rely kar sakte hain.
- **Accepted trade-off**: humne strict global ordering chhod di (ID N+1
  guaranteed nahi hai ki saare machines ke across ID N ke strictly baad
  create hui ho) badle mein zero-coordination, sub-millisecond, horizontally
  unlimited ID generation ke. Yeh almost hamesha sahi trade hai — bahut
  kam systems ko actually strict global ordering chahiye hoti hai, aur jinko
  chahiye (financial ledgers) unko usually us specific data ke liye ek
  alag mechanism chahiye (ek single ordered log, jaise consensus ke
  through), ek general ID generator nahi.
- **Fixed-size bit budget**: 41/10/12 split ek design decision hai, physics
  ka law nahi — ek system jisme 1,024 se kaafi zyada machines hon lekin
  fewer IDs/ms/machine chahiye ho, woh bits ko realloc kar sakta hai
  (jaise, 13 bits machine ID, 9 bits sequence) cost pe lower per-machine
  throughput ke. Yeh trade-off explicitly kiya jaana chahiye aur apne
  traffic numbers se justify kiya jaana chahiye, Twitter ke original split
  se blindly copy nahi karna chahiye.

## Follow-up Questions an Interviewer Might Ask

- **"Agar coordination service outage ki wajah se do data centers mein
  same worker ID wala machine ho jaaye toh kya hoga?"** Machine-ID bits se
  ek datacenter ID segment carve out karo (jaise, 10 bits worker ki jagah
  5 bits datacenter + 5 bits worker), taaki coordination service ko sirf
  ek datacenter *ke andar* uniqueness guarantee karni pade, aur
  cross-datacenter collisions structurally impossible ho jaayein chahe
  dono DCs ki coordination services ek doosre se partitioned kyun na hon.
- **"Kaise migrate karoge ek existing system ko auto-increment IDs se
  Snowflake IDs pe bina downtime ke?"** Ek transition window ke dauran
  dual-write karo: naye rows ko purane-style ID aur ek naye column mein
  Snowflake ID dono mile, historical rows pe Snowflake IDs ko ek batch job
  se backfill karo, backfill complete aur verify hone ke baad reads ko
  naye column pe switch karo, phir purana column drop karo — classic
  expand-contract schema migration.
- **"Kya tum Snowflake ki jagah Redis `INCR` use kar sakte ho?"** Haan,
  pure uniqueness + monotonicity ke liye (Redis `INCR` atomic hai aur
  strictly increasing hai), lekin isse hot path pe ek centralized network
  hop wapas aa jaata hai aur ek single point of failure/bottleneck (jab
  tak counter ko shard na karo, jaise range ke hisaab se different Redis
  keys), jo basically machine-ID partitioning ka ek weaker version reinvent
  kar deta hai jo Snowflake pehle se free mein deta hai, bina
  sub-millisecond in-process latency ke.
- **"Isko production mein kaise monitor karoge?"** Clock-skew alerts track
  karo (kitni baar "clock moved backwards" events aaye), sequence-overflow
  rate (kitni baar ek machine 4,096/ms ceiling hit karti hai — ek signal ki
  shayad tumhe zyada machines ya zyada sequence bits chahiye), aur
  machine-ID lease churn (ek spike batata hai ki instances crash-loop kar
  rahe hain aur baar-baar re-register ho rahe hain).
- **"Agar IDs ko non-guessable hona chahiye (sirf unique nahi), jaise
  public-facing resource URLs ke liye?"** Snowflake IDs design se hi
  sequential aur predictable hain (yehi toh point hai, sortability ke
  liye) — public IDs ke liye jahan enumeration ek security concern hai, ya
  toh Snowflake ID ko externally expose karne se pehle ek reversible
  obfuscation (Hashids-style) se encode karo, ya ek separate random
  public-facing token maintain karo jo internally Snowflake ID pe map
  karta ho.
- **"12 bits sequence hi kyun, kyun na 8 ya 16?"** Yeh ek capacity vs.
  bit-budget trade hai: 8 bits sirf 256 IDs/ms/machine deta hai
  (256,000/sec), jo ek single hot machine ke liye burst ke dauran bahut
  tight ho sakta hai; 16 bits 65,536/ms/machine deta hai lekin timestamp
  ya machine ID ke liye available bits khaa jaata hai. 12 bits
  (4,096/ms/machine = 4.096M/sec/machine) Twitter ka apne traffic profile
  ke liye empirically chosen middle ground tha — sahi answer tumhare apne
  Step 2 ke peak per-machine write rate pe depend karta hai.
