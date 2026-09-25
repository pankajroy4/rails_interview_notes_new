# Design a Distributed Key-Value Store

## Problem Statement

"Design karo ek distributed key-value store — essentially, DynamoDB ya Cassandra
ka ek simplified version banao. Isme simple `get(key)` aur `put(key, value)`
operations support hone chahiye, many commodity nodes ke across horizontally
scale karna chahiye, node failures tolerate karna chahiye bina data ya
availability lose kiye, aur mujhe iske diye jaane wale consistency guarantees pe
reason karne do. Yeh deliberately 'database ko khud build karo' wala question
hai — mujhe dekhna hai tum distributed-systems concepts ko directly apply kar
rahe ho, naye invent nahi kar rahe."

Yeh question system design interviews mein unusual hai is baat mein ki yeh ek
novel architecture invent karne ke baare mein kam hai aur zyada correctly
assemble karne aur ek set of well-known distributed-systems primitives ke through
reason karne ke baare mein hai — partitioning, replication, quorums, conflict
resolution, aur failure handling — jinme se har ek ka ek right answer hota hai
theory mein grounded. Ek strong candidate isko waise hi treat karta hai:
technique ka naam lo, explain karo ki yahan wo right fit kyun hai, aur usko
CAP/consistency trade-offs se connect karo jo wo imply karti hai, first
principles se sab kuch re-derive karne ke bajaye.

## Step 1: Requirements Clarify Karo

**Functional Requirements**
- `PUT(key, value)` — ek key ke liye value write/update karo.
- `GET(key)` — ek key ke liye value(s) read karo.
- `DELETE(key)` — ek key remove karo.
- Simple API only: koi complex queries, joins, ya secondary indexes nahi — yeh
  ek pure key-value store hai, ek general database nahi.
- Ek cluster of many nodes ke across operate karo, client ke liye transparently
  (client ko yeh jaanne ki zaroorat nahi ki kaunsa physical node ek key hold
  karta hai).

**Non-Functional Requirements**
- Horizontal scalability: nodes add karna capacity aur throughput ko linearly
  increase karna chahiye bina kisi redesign ke.
- High availability: system ko reads aur writes serve karte rehna chahiye jab
  kuch nodes down ya unreachable hon — kahin bhi koi single point of failure
  nahi hona chahiye, cluster membership/coordination mein bhi nahi.
- Tunable consistency: kuch use cases ko strict correctness chahiye, doosron ko
  speed — system ko caller ko choose karne dena chahiye, CAP spectrum pe ek
  point ko hard-code karne ke bajaye (cross-reference
  `08_cap_theorem_and_consistency.md`).
- Partition tolerance mandatory assume ki jaati hai (network partitions kisi bhi
  real multi-node deployment mein hote hain), jiska matlab CAP ke hisaab se yeh
  hai ki real design choice availability aur consistency ke beech hai ek
  partition ke dauraan, na ki partition tolerance rakhna hai ya nahi.
- Low, predictable latency: single-digit-millisecond p99 dono `GET` aur `PUT`
  ke liye normal operation ke neeche.
- Durability: ek acknowledged write ko ek single node failure survive karna
  chahiye.
- Scale target: maan lo 100 nodes, 1 billion keys, ~10KB average value size.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 1 billion keys, ~10KB average value size (small config blobs aur medium
  serialized objects ka ek mix — usi tarah ka workload jo DynamoDB/Cassandra
  actually serve karte hain).
- Replication factor N = 3 (is class of system ke liye standard, durability ko
  storage cost ke against balance karta hai).
- Assume karo 100,000 GET QPS aur 20,000 PUT QPS platform-wide peak pe (ek 5:1
  read:write ratio, key-value workloads ke liye typical).

**Storage**
- Raw data: 1B keys × 10KB ≈ 10TB logical data.
- Replication factor 3 ke saath: 10TB × 3 ≈ **30TB physical storage** cluster ke
  across.
- 100 nodes ke across: 30TB / 100 ≈ **300GB per node** — ek single commodity
  node ki disk capacity ke andar comfortably (modern nodes easily multiple TB
  handle karte hain), growth ke liye headroom chhodte hue.

**Throughput per node**
- Total GET QPS 100,000, N=3 replicas ke across spread, jinme se har ek quorum
  read of R=2 ke liye ek read serve kar sakta hai (dekho Step 6.2) → har read 2
  of 3 replicas ko touch karta hai, to effective read load ≈ 100,000 × 2 /
  100,000 (100 nodes) — zyada precisely work kiya to: 100,000 GETs/s × R=2
  replica-reads each = 200,000 replica-read-ops/s, 100 nodes ke across spread ≈
  **2,000 reads/s per node**, jo achhe se ek single node backed by ek SSD aur ek
  in-memory cache serve kar sakta hai.
- Similarly, 20,000 PUTs/s × W=2 replica-writes each = 40,000 replica-write-ops/s
  / 100 nodes ≈ **400 writes/s per node** — comfortably low.

**Network**
- Har replicated write ~10KB W=2 replicas ko bhejta hai ≈ 20KB per logical write
  × 20,000 writes/s = **400MB/s internal replication traffic** cluster-wide,
  jiski wajah se replication typically ek dedicated internal network par hoti
  hai instead of client-facing traffic ke saath bandwidth share karne ke.

## Step 3: High-Level Design

Cluster ka har node ek peer hai jo same software run karta hai (yeh ek
**decentralized, peer-to-peer** architecture hai, ek primary/coordinator design
nahi) — koi bhi node ek client request receive kar sakta hai, us request ke liye
coordinator ki tarah act kar sakta hai, aur usko un nodes ko forward kar sakta
hai jo actually relevant key range own karte hain, consistent hashing ke hisaab
se.

```text
                         ┌──────────┐
                         │  Client   │
                         └────┬─────┘
                              │ GET/PUT key
                              ▼
                  ┌───────────────────────┐
                  │  Any node (coordinator  │  <- no central router;
                  │  for this request)      │     any node can coordinate
                  └───────────┬─────────────┘
                              │ consistent hash ring lookup
                              ▼
        ┌─────────────────────────────────────────────┐
        │           Consistent Hash Ring                │
        │  node A ── node B ── node C ── node D ── ...   │
        │  key K hashes between B and C → owned by       │
        │  C, D, E (N=3 successive nodes on the ring)     │
        └───────────┬──────────────┬──────────────┬──────┘
                     ▼              ▼              ▼
              ┌───────────┐  ┌───────────┐  ┌───────────┐
              │  Node C    │  │  Node D    │  │  Node E    │
              │ (replica)  │  │ (replica)  │  │ (replica)  │
              │ local store│  │ local store│  │ local store│
              └───────────┘  └───────────┘  └───────────┘
                     ▲              ▲              ▲
                     └──────────────┴──────────────┘
                     Gossip protocol: all nodes continuously
                     exchange membership/health info peer-to-peer
                     (no central coordinator for cluster state)

        Background per-node processes:
          - Hinted handoff receiver (temp writes for down peers)
          - Anti-entropy / read-repair (Merkle-tree diffing)
```

Ek write ke liye data flow: client `PUT(key, value)` kisi bhi node ko bhejta hai
→ wo node key ki hash ring pe position compute karta hai aur responsible N=3
nodes identify karta hai → write ko sabhi 3 (ya kam, agar kuch temporarily
unreachable hon, jo hinted handoff trigger kare) ko forward karta hai → client
ko success return karne se pehle W acknowledgments ka wait karta hai. Ek read
same coordinator pattern follow karta hai, R replicas ko query karke aur unke
responses reconcile karke (Step 6.3) return karne se pehle.

## Step 4: API Design

Kyunki yeh infrastructure hai, ek user-facing web app nahi, "API" client-facing
protocol/SDK surface hai (DynamoDB ya Cassandra ke client API ke analogous):

```
PUT key=<string>, value=<bytes>, [consistency=ONE|QUORUM|ALL]
→ 200 OK { version_vector: {...} }
→ 503 { error: "insufficient_replicas_acked" }   # W se kam acks receive hue

GET key=<string>, [consistency=ONE|QUORUM|ALL]
→ 200 { value: <bytes>, version_vector: {...} }
→ 200 { conflicting_versions: [{value, version_vector}, ...] }  # agar unresolved concurrent writes exist karte hain
→ 404 { error: "not_found" }

DELETE key=<string>, [consistency=...]
→ 200 OK    # internally ek "tombstone" write ki tarah implement hota hai, physical delete nahi (dekho 6.2 note)

# Administrative/internal RPCs, client-facing nahi:
INTERNAL_REPLICATE(key, value, version_vector)   # coordinator → replica
INTERNAL_MERKLE_SYNC(key_range, tree_hash)         # replica ↔ replica, anti-entropy
GOSSIP_PING(node_id, membership_view)               # peer ↔ peer, har ~1s
```

`consistency` parameter requirements ka tunable-consistency knob hai:
`ONE` jaise hi koi bhi single replica ack kare wapas aa jaata hai (fastest,
weakest guarantee), `QUORUM` ek majority ka wait karta hai (balanced default,
6.2 mein detail mein), `ALL` har replica ka wait karta hai (strongest, slowest,
failure ke neeche least available).

## Step 5: Data Model

Deliberately koi schema nahi hai key aur value ke ilawa — yeh ek key-value
store ka poora point hai ek relational database ke against (cross-reference
`06_databases_fundamentals.md` iske liye ki kab ek KV model right fit hai: no
joins, no query flexibility chahiye, exchange mein extreme horizontal
scalability aur simplicity milti hai).

```
Logical record:
  key: string (ya bytes)
  value: opaque bytes (store structure interpret nahi karta)
  version_vector: { node_id: counter, ... }   -- conflict detection ke liye (Step 6.3)
  tombstone: bool                              -- logical deletion mark karta hai
  timestamp: LWW mode ke liye, ya ek tiebreaker ki tarah
```

Per-node local storage engine: typically ek log-structured merge-tree
(LSM-tree) based store (wahi family jo Cassandra ke SSTables ya RocksDB ke
neeche hai), kyunki workload write-heavy-friendly hai aur LSM-trees random
writes ko sequential disk writes mein badal dete hain ek memtable + periodic
flush-to-disk + background compaction ke saath — ek achha match high sustained
write throughput ke liye jo is tarah ka store target karta hai, aur ek
deliberate contrast ek B-tree-based engine se jo har write pe zyada random I/O
incur karta (cross-reference `12_storage_systems.md` aur
`06_databases_fundamentals.md` LSM vs. B-tree trade-off ke liye).

## Step 6: Deep Dive

Yeh system explicitly is notes set mein cover kiye gaye lagbhag har
distributed-systems concept ke liye synthesis point hai — is section ki value
un concepts ko concretely ek single coherent system pe apply karne mein hai,
unko re-derive karne mein nahi.

### 6.1 Consistent Hashing Ke Through Partitioning

100 nodes ke across 1 billion keys ke saath, kuch tarika chahiye yeh decide
karne ka ki kaunsa node(s) kaunsi keys own karte hain, aur usko nodes ke
join/leave hone se survive karna chahiye bina zyadatar data reshuffle kiye. Yeh
exactly wahi problem hai jo consistent hashing solve karta hai (cross-reference
`07_database_scaling.md`'s consistent hashing section — yeh system us concept
ka practical, worked application hai, koi nayi idea nahi).

Har node ko ek ya zyada positions ("tokens") assign hote hain ek fixed hash ring
pe (typically har physical node ke liye many virtual nodes — e.g., 256 virtual
tokens each — taaki load evenly spread ho aur ek physical node ko sirf bad luck
se disproportionate hash range na mil jaaye). Ek key same hash function se hash
hoti hai aur usi ring pe place hoti hai; yeh usi first node ki ownership mein
hoti hai jo key ki position se clockwise walk karte hue milta hai, plus,
replication ke liye, next N-1 distinct physical nodes continuing clockwise. Jab
ek node join karta hai, wo ring ka ek contiguous slice apne neighbors se le
leta hai aur sirf usi slice ki keys receive karne ki zaroorat hoti hai — ek full
cluster reshuffle nahi. Jab ek node leave karta hai (planned ho ya failure ke
through), uski ring range uske neighbor dwara absorb ho jaati hai, phir se sirf
us node ka data move hota hai, poora dataset nahi. Yehi exact wajah hai ki
consistent hashing (naive `hash(key) % N` ke against) right partitioning
strategy hai ek aise system ke liye jo nodes ke routine, expected occurrence
ki tarah join aur leave hone ke around bana hai, ek rare event ki tarah nahi.

### 6.2 Replication Factor N Aur Quorum Reads/Writes (W + R > N)

N=3 diya gaya hai (har key 3 distinct nodes pe stored hai ring walk ke hisaab
se, upar wale), system ko ek rule chahiye ki correctness guarantee karne ke
liye ek read ya write mein kitne replicas participate karne chahiye, aur yahin
pe CAP/consistency trade-off (cross-reference
`08_cap_theorem_and_consistency.md`) ek concrete, tunable parameter ban jaata
hai instead of ek abstract theorem ke.

Quorum condition hai **W + R > N**: agar replicas ki number jinse ek write
reach karni chahiye (W) plus replicas ki number jinse ek read query karni
chahiye (R) replication factor (N) se exceed kare, to har read mathematically
guarantee ho jaati hai ki wo most recent successful write se kam se kam ek
replica pe overlap kare, to read hamesha latest value find kar sakta hai
(possibly ek couple differing versions reconcile karna pad sakta hai, Step
6.3, lekin kabhi bhi latest ko poori tarah miss nahi karega).

**Worked example: N=3, W=2, R=2.**
- Ek client `PUT(key, "v2")` issue karta hai. Coordinator write ko sabhi 3
  replicas (R1, R2, R3) ko bhejta hai lekin sirf W=2 acknowledgments ka wait
  karta hai client ko success return karne se pehle. Maan lo R1 aur R2 jaldi
  ack karte hain; R3 momentarily slow ya unreachable hai (network blip) aur
  coordinator uska wait nahi karta — write already durable aur successful maani
  jaati hai jaise hi 2 acks aa jaate hain. R3 ko eventually wo write mil jaayegi,
  chahe coordinator ke background mein retry karne se ya hinted handoff /
  anti-entropy (6.4) ke through.
- Ab ek client `GET(key)` issue karta hai. Coordinator R=2 replicas query
  karta hai — maan lo wo R2 aur R3 pick karta hai. R2 ke paas "v2" hai (usko
  write mil gayi thi). R3 ke paas abhi bhi purani value "v1" ho sakti hai (jab
  usko query kiya gaya tab tak write nahi mili thi). Coordinator dono responses
  receive karta hai, dekhta hai ki wo disagree kar rahe hain, aur reconcile
  karna padta hai — lekin critically, **yeh guaranteed hai ki query kiye gaye
  R=2 replicas mein se kam se kam ek ke paas latest write hai**, kyunki W=2 aur
  R=2 out of N=3 ka matlab hai ki koi bhi 2-of-3 write set aur koi bhi 2-of-3
  read set pigeonhole se overlap karna hi hai (2+2=4 > 3). To worst case mein
  bhi (R3 hi "stale" wala select ho jaaye), R2 guaranteed hai queried set mein
  fresh value ke saath. Coordinator higher version wali value pick karta hai
  (version vector ya timestamp ke through, 6.3) aur "v2" client ko return karta
  hai — aur optionally ek read-repair write R3 ko wapas trigger kar sakta hai
  usko turant up to date karne ke liye instead of background anti-entropy ka
  wait karne ke.
- Contrast: agar caller ne instead `consistency=ONE` choose kiya hota dono read
  aur write ke liye (W=1, R=1), to W+R=2 N=3 se > nahi hai, to koi overlap
  guarantee nahi hai — ek read easily usi ek replica ko hit kar sakti hai jisko
  woh particular write kabhi mili hi nahi, aur silently stale data return kar
  sakti hai. Yeh explicit trade hai jo caller lower latency/higher availability
  ke liye karta hai (sirf 1 node ka up aur fast hona chahiye) consistency ke
  cost pe — exactly wahi CAP trade-off jo per-request tunable banaya gaya hai
  instead of poore system ke liye fixed hone ke.

### 6.3 Conflict Resolution: Vector Clocks vs. Last-Write-Wins

Kyunki W < N hai (example mein, W=2 out of N=3), aur kyunki network partitions
ya concurrent clients do different coordinators se same key pe writes accept
karwa sakte hain bina ek doosre ki write dekhe, replicas genuinely diverge kar
sakte hain — sirf "kuch peeche hain" nahi, balki truly concurrent, conflicting
updates hold karte hue bina kisi inherent ordering ke. System ko isko detect
aur resolve karne ka ek defined tarika chahiye (cross-reference
`08_cap_theorem_and_consistency.md` aur `09_distributed_systems_core.md`).

**Vector clocks** general, correctness-preserving solution hain. Har value ek
version vector ke saath stored hoti hai — ek map of `{node_id: counter}` jo
roughly record karta hai, "yeh version descend karta hai node X se counter N
dekh kar, node Y se counter M dekh kar, ...". Jab ek node ek write handle karta
hai, wo apna khud ka counter vector mein increment karta hai. Do version
vectors compare karne se do cheezein pata chalti hain: ya to ek vector ke
counters doosre ke ≥ sabhi hain (matlab ek write dusre se causally descend
karti hai — koi real conflict nahi, bas newer wali le lo), ya koi bhi ek doosre
pe dominate nahi karta (matlab dono writes truly concurrent thi — ek client ne
doosre ka update dekhe bina hi hui). Doosre case mein, store safely ek pick
nahi kar sakta aur doosri ko silently discard nahi kar sakta, kyunki isse real,
causally-independent user intent discard ho sakta hai (yeh exactly DynamoDB ka
original approach hai, famously shopping-cart example mein surface hua: do
concurrent "cart mein item add karo" writes mein se ek ko doosri clobber nahi
karni chahiye — dono application ko sibling versions ki tarah return ki jaati
hain merge karne ke liye, e.g. cart contents ko union karke).

**Last-write-wins (LWW) by timestamp** simpler, cheaper alternative hai: har
write pe ek wall-clock (ya hybrid logical clock) timestamp attach karo, aur
conflict pe, jiska bhi timestamp later ho wo simply jeet jaata hai, doosri ko
silently discard karte hue. Yeh implement aur reason karne mein kahin zyada
simple hai, aur yehi hai jo Cassandra by default use karta hai. Explicit
trade-off: LWW lossy hai — agar do truly concurrent writes close together hoti
hain, ek permanently aur silently discard ho jaati hai, jo ek shopping cart
jaisi cheez ke liye unacceptable hai (ek item lose ho jaayega) lekin ek device
ke last-reported sensor status jaisi cheez ke liye perfectly fine hai (sirf
latest state matter karta hai, older concurrent updates genuinely irrelevant
hain). Ek strong answer yeh trade-off explicitly state karta hai instead of ek
mechanism ko universally "better" pick karne ke: vector clocks zyada
information preserve karte hain implementation complexity ke cost pe aur
application ko sibling resolution handle karwane ki zaroorat pe; LWW simple
aur fast hai lekin application ki semantics ko silently do concurrent writes
mein se ek drop karna tolerate karna padta hai.

### 6.4 Node Failure Ko Gracefully Handle Karna: Hinted Handoff Aur Anti-Entropy

Nodes fail hote hain, transiently ya permanently, constantly is scale pe (100
nodes, real hardware) — design ko ek temporary outage ke dauraan writes serve
karte rehna chahiye instead of unko block ya fail karne ke, aur ek baar nodes
recover hone pe replicas ko wapas consistency mein heal karna chahiye.

**Hinted handoff** transient case address karta hai. Agar ek write ka
coordinator determine karta hai ki key ke N designated replicas mein se ek
currently unreachable hai, to write fail karne (availability ke liye bura) ya
simply us replica ko forever skip karne (durability/replication factor ke liye
bura) ke bajaye, coordinator write ko ek different, healthy node ko handover
karta hai, saath mein ek "hint" record karke ki yeh data actually us down node
ka hai. Wo substitute node write ko temporarily store karta hai. Ek baar
original replica wapas online aa jaaye (gossip ke through detect hota hai,
6.5), substitute node notice karta hai aur hinted write ko usko forward
("handoff") karta hai, phir apni temporary copy discard kar deta hai. Isse
writes full replication intent pe succeed ho paate hain ek node outage ke
dauraan bhi, cost yeh hai ki temporarily-down replica handoff complete hone tak
briefly behind rehti hai — ek availability-favoring trade.

**Anti-entropy / read-repair** longer-term drift address karta hai — replicas
jo kaafi time se out of sync hain (ek node hours tak down raha ho, ya hinted
handoff khud fail/expire ho gaya ho). Ek background process periodically har
replica ke data ko uske peers ke against usi key range ke liye compare karta
hai aur differences reconcile karta hai. Har key ko individually compare karke
yeh karna billions of keys pe prohibitively expensive hoga, to replicas iske
bajaye **Merkle trees** compare karte hain — ek hash tree jahan har leaf keys ke
ek small range ke data ko hash karta hai aur har parent apne children ka
concatenation hash karta hai, ek single root hash per key range tak. Do
replicas pehle root hashes compare karte hain; agar match kar jaayein, to poora
range provably identical hai aur further comparison ki zaroorat nahi. Agar
differ karein, replicas recursively child hashes compare karte hain yeh narrow
down karne ke liye ki exactly kaunse sub-ranges (aur eventually kaunsi specific
keys) actually differ karti hain, sirf unhi ko transfer karte hue — isse ek
O(all keys) comparison ban jaata hai kuch closer to O(log(keys) +
actual differences) ke, jisse billions of keys ka background reconciliation
practically feasible ban jaata hai instead of ek full data re-transfer ke.

### 6.5 Cluster Membership Aur Failure Detection Ke Liye Gossip Protocol

Ek system jo explicitly no single point of failure hone ke liye design kiya
gaya hai, ek central coordinator pe rely nahi kar sakta yeh track karne ke liye
ki "kaunse nodes alive hain" — wo coordinator khud us single point of failure
ban jaata jise poora architecture avoid karne ki koshish kar raha hai
(cross-reference `09_distributed_systems_core.md`). Iske bajaye, membership aur
failure detection ek **gossip protocol** use karte hain: periodically (e.g.,
har second ek baar), har node kuch random peers pick karta hai aur apna current
view of cluster state exchange karta hai (kaunse nodes wo believe karta hai
alive hain, unki ring positions, koi recent joins/leaves) — information jo usko
earlier rounds of gossip se doosre nodes se propagate hui hai. Kuch rounds mein,
information jo cluster mein kahin bhi inject hui ho (ek naya node join kar raha
ho, ek node suspect mark ho raha ho) high probability ke saath poore cluster
mein spread ho jaati hai, bina kisi node ko sabse baat karne ki zaroorat ke ya
kisi single node ke authority ki tarah act kiye.

Failure detection typically gossip ke upar ek **phi accrual failure detector**
(ya simpler heartbeat-timeout schemes) layer karta hai: ek binary "kya last
heartbeat aayi" ke bajaye, har node har peer se heartbeats ka historical
inter-arrival time distribution track karta hai aur ek continuously-valued
suspicion level compute karta hai, ek peer ko sirf tabhi failed mark karte hue
jab wo suspicion ek threshold cross kar jaaye — yeh normal network jitter ko
ek fixed timeout se kahin zyada achhe se tolerate karta hai, momentary slowness
ke neeche false-positive failure detection reduce karte hue. Yeh decentralized
approach system ke core design goal ko directly fit karta hai: kyunki koi
single node nahi hai jiska failure membership tracking ko down kar sake,
cluster health information gracefully degrade hoti hai aur propagate hoti
rehti hai jitne bhi nodes reachable rahein, exactly usi no-single-point-of-
failure principle ko mirror karte hue jo data pe (N replicas) apply hoti hai
lekin yahan cluster metadata pe applied.

## Step 7: Bottlenecks & Trade-offs

- **Hot keys abhi bhi consistent hashing ki even distribution ko break karte
  hain**: chhoti number of extremely popular keys un specific nodes ko overload
  kar sakti hain jo unhe own karte hain, chahe ring overall kitna bhi evenly
  balanced ho — mitigate hota hai virtual nodes se (ek physical node ka
  *aggregate* load ko many ring positions mein spread karna uneven key
  distribution mein generally help karta hai, lekin ek genuinely hot key phir
  bhi apne N owning replicas pe concentrate karti hai) aur, read-heavy hot keys
  ke liye specifically, ek additional caching layer store ke saamne ya
  client-side/coordinator-side hot-key caching se.
- **W+R>N quorum trade-off fundamentally ek latency-vs-consistency knob hai, aur
  yeh per-operation hai, global nahi**: higher W/R (e.g., R=ALL) stronger
  guarantees deta hai lekin har operation ko uske sabse slow required replica
  jitna slow bana deta hai aur kisi bhi node ki failure ke dauraan less
  available bana deta hai; lower values (W=1, R=1) fast aur available hain
  lekin overlap guarantee sacrifice karte hain — ek well-designed system isko
  ek tunable per-request ki tarah expose karta hai ek global answer force karne
  ke bajaye, kyunki same cluster mein different keys/use-cases often us
  trade-off ke different points chahte hain.
- **Vector clocks unboundedly grow hote hain** agar prune na kiye jaayein — ek
  key jo many different nodes dwara time ke saath edit hui ho apni version
  vector mein aur zyada entries accumulate karti hai. Real systems isko cap
  karte hain (oldest/least-relevant node entries ko prune karte hain ek size
  threshold hit hone pe), thoda causal-history precision trade karke bounded
  metadata size ke liye.
- **Anti-entropy inherently ek background, eventually-converging process hai**
  — yeh koi bound nahi deta ki do replicas diverge hone ke baad kitni jaldi
  reconcile hongi, sirf yeh bound deta hai ki jab wo run karti hain to data
  kitni efficiently Merkle trees se compare hota hai. Us window ke dauraan, ek
  `consistency=ONE` read stale replica ke against legitimately old data return
  kar sakti hai; yeh poore design ka ek accepted trade hai, bug nahi hai, aur
  yehi exact wajah hai ki `QUORUM` reads exist karti hain un callers ke liye
  jinhe overlap guarantee chahiye.
- **Gossip convergence time cluster size ke saath grow hoti hai** (jitne zyada
  nodes utne zyada rounds chahiye information poori tarah propagate hone ke
  liye) — bahut large scale pe (thousands of nodes) yeh membership changes ko
  cluster-wide visible hone mein several seconds tak laga sakta hai, jo is
  system ke purposes ke liye acceptable hai lekin gossip specifically ki ek
  scaling limit ki tarah naam lena chahiye, data-plane ki khud ki scaling
  limits se distinct.

## Follow-up Questions Jo Ek Interviewer Puuch Sakta Hai

- **"Range queries ya secondary indexes kaise support karoge, jab consistent
  hashing keys ko randomly scatter kar deta hai?"** Explain karo ki yeh
  fundamentally design ke saath tension mein hai — consistent hashing
  deliberately key ordering destroy karta hai load-balancing purposes ke liye,
  to range scans ke liye ya to ek separate ordered-partitioning scheme chahiye
  (jaise Cassandra ka option even load distribution ko range-query support ke
  liye trade karne ka) ya ek poori tarah separate secondary index structure
  chahiye jo asynchronously maintain ho, index pe eventual consistency accept
  karte hue.
- **"Ek genuine network partition ke dauraan kya hota hai jahan cluster do
  halves mein split ho jaaye jo ek doosre se baat nahi kar sakte?"** CAP
  trade-off ko concretely walk through karo: W+R>N quorums ke saath, partition
  ke minority side pe ek client typically quorum achieve nahi kar paata aur
  uski writes/reads fail ho jaati hain (us request ke liye availability ke upar
  consistency favor karte hue), jabki `consistency=ONE` operations dono sides
  pe independently proceed kar sakte hain, availability guarantee karte hue
  lekin dono sides ko diverge hone dete hue jab tak partition heal na ho aur
  anti-entropy unhe reconcile na kar de.
- **"Ek permanent node loss (disk failure, transient outage nahi) kaise handle
  karoge?"** Isko hinted handoff se distinguish karo: ek permanently lost node
  ko formally ring se remove karna padta hai (gossip-propagated membership
  change ke through) aur uski key range ke replicas ko ek naye node pe
  re-replicate karna padta hai, surviving N-1 replicas se har affected key ka
  data stream karke, sirf hints handoff nahi karke.
- **"Virtual nodes ke unevenly assign hone se hot-node imbalance kaise rokoge?"**
  Discuss karo ki har physical node ke liye virtual node count usually us node
  ki actual capacity ke proportional hota hai (to ek beefier node ko zyada ring
  positions milti hain), heterogeneous hardware ko load proportionally share
  karne dete hue instead of uniform node capacity assume karne ke.
- **"Kya tum is system ko kisi aise cheez ke liye use karoge jise multi-key
  transactions chahiye?"** Nahi — explicitly call out karo ki is shape ke
  key-value stores intentionally cross-key transactional guarantees sacrifice
  karte hain horizontal scalability aur availability ke liye; ek workload jise
  multi-key ACID transactions chahiye wo system ki ek alag class pe belong
  karta hai (ek distributed SQL database ek consensus-based commit protocol ke
  saath), ek deliberate scope boundary jo state karna worth hai bolt on karne
  ki koshish karne ke bajaye.
- **"Consensus protocols jaise Raft ya Paxos is design mein kahan fit hote
  hain, agar hote hain?"** Clarify karo ki yeh design intentionally data path
  ke liye cluster-wide consensus ki zaroorat avoid karta hai (yehi wajah hai ki
  yeh highly available aur gossip-based hai), lekin ek component jaise cluster
  configuration changes (ring mein formally node add/remove karna) kabhi kabhi
  ek lightweight consensus mechanism ya ek external coordination service use
  karta hai, jo ek narrower, rarer use hai us se jitna ek fully
  consensus-based system (jaise ek distributed SQL database) ko har write pe
  chahiye hota.
