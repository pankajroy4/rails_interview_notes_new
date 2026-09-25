# Distributed Systems Core

## Distributed systems fundamentally hard kyun hain

Ek distributed system independent machines (nodes) ka ek set hai jo network
par communicate karte hain aur outside world ko ek coherent system ki tarah
kaam karte hue dikhne chahiye. Difficulty business logic nahi hai — yeh
underlying environment ki teen properties hain jinse single-machine
programming ko kabhi deal nahi karna padta:

- **Partial failure**: ek single process mein, agar kuch galat hota hai, to
  poora process crash ho jaata hai aur aapko pata chal jaata hai ki crash ho
  gaya. Distributed system mein, kuch nodes fail ho sakte hain jabki baaki
  theek chalte rehte hain, aur — yeh hard part hai — ek healthy node often
  **difference nahi bata sakta** "woh doosra node dead hai," "woh doosra
  node bas slow hai," aur "hamare beech ka network packets drop kar raha
  hai" mein se. Teeno identical dikhte hain: koi response time par nahi
  aaya.
- **Koi shared global clock nahi**: har machine ka apna local clock hota
  hai, aur clocks ek doosre ke relative drift karte hain (typically
  milliseconds se seconds per day bina correction ke). Aap simply do
  different machines ke timestamps compare nahi kar sakte aur trust nahi
  kar sakte ki earlier timestamp reality mein pehle hua tha.
- **Unreliable, asynchronous networks**: messages ek unpredictable amount
  se delay ho sakte hain, poori tarah drop ho sakte hain, duplicate ho
  sakte hain, ya out of order deliver ho sakte hain. Koi upper bound nahi
  jo aap assume kar sako ki ek message aane mein kitna time lagega (yahan
  "asynchronous network" ka yahi matlab hai — non-blocking I/O nahi, balki
  "koi timing guarantees nahi").

In teeno facts ko milaake, ek distributed system kabhi bhi 100% sure nahi ho
sakta current global state ke baare mein kisi bhi instant par — yeh sirf
probabilistically reason kar sakta hai aur aise protocols bana sakta hai jo
uncertainty ko tolerate karte hain, usse assume away karne ke bajaye.

## Yeh important kyun hai

In realities ko account kiye bina, distributed systems specific, recurring
tareekon se fail hote hain:

- **Split brain**: do nodes dono believe karte hain ki woh "leader" hain
  (jaise, ek network partition ke baad), aur dono writes accept karte hain
  — jisse conflicting, unreconcilable data ban jaata hai.
- **Lost ya duplicated work**: ek client ek request retry karta hai kyunki
  usse time par response nahi mila, yeh realize kiye bina ki original
  request actually succeed ho chuki thi — ab action (jaise, "card charge
  karo") do baar hota hai.
- **Stuck systems**: ek coordinator protocol ke beech mein crash ho jaata
  hai (classically, Two-Phase Commit mein) aur baaki nodes ko locks ke saath
  forever chhod deta hai, ek aise message ka wait karte hue jo kabhi nahi
  aayega.
- **Clock skew se silent data corruption**: do writes wall-clock timestamp se
  order kiye jaate hain, lekin jis machine ne *baad wala* write kiya usska
  clock actually kuch seconds *peeche* chal raha tha, isliye "baad wala"
  write pehle hua hua ki tarah store ho jaata hai, silently real latest
  value ko overwrite karte hue.

Neeche diye concepts ka poora point — consensus, replication protocols,
idempotency, distributed locks, logical clocks — hai un components se
reliable, coordinated behavior build karna jo individually unreliable aur
default se uncoordinated hain.

## Consensus problem

**Consensus** ek problem hai nodes ke ek set ko ek single value par agree
karwane ki, ek baar, chahe kuch nodes crash ho jaayein ya messages delay ho
jaayein — aur ek baar agree ho jaane par, woh value sab nodes ke liye final
hai.

Yeh kyun chahiye:
- **Leader election**: cluster mein exactly ek node "the leader" designate
  hona chahiye (jaise, woh jise writes accept karne diye jaate hain) — agar
  do nodes dono sochte hain ki woh leader hain, to aapko split brain milta
  hai.
- **Ek replicated log mein operations ke order par agree karna**: agar data
  ka ek piece multiple nodes mein replicate hota hai, to har replica ko
  writes *same order* mein apply karne chahiye, nahi to woh alag-alag states
  mein diverge ho jaayenge. Consensus hi cluster ko "operation #57 X hai"
  har jagah identically agree karne deta hai.

Consensus provably impossible hai solve karna ek fully asynchronous network
mein correctness aur termination dono ki guarantee ke saath ek bhi faulty
node ke saath (FLP impossibility result) — practice mein, real systems isse
sidestep karte hain timeouts use karke aur temporarily progress na kar paane
ka ek chota chance accept karke (safe lekin occasionally slow) instead of
kabhi bhi wrong hone ke.

### Paxos

**Paxos** original, foundational consensus algorithm hai. Interview mein
aapko yeh prove nahi karna hoga correct — aapko high-level shape chahiye:

- **Proposers** values suggest karte hain agree hone ke liye.
- **Acceptors** proposed values par vote karte hain.
- Ek value **chosen** hoti hai jab acceptors ka ek **majority** (quorum)
  usse accept kar leta hai.

Key insight jo isse failures tolerate karne deti hai: kyunki ek value ko
sirf ek *majority* chahiye, *sab* nodes nahi, system kaam karta rehta hai
jab tak nodes ka majority up aur reachable hai — ek minority crash ho sakti
hai, ya slow ho sakti hai, ya network-partitioned ho sakti hai, aur consensus
still proceed karta hai. Aur kyunki same set of nodes se do majorities
guaranteed hain kam se kam ek node par overlap karne ke liye, yeh impossible
hai ki do *alag* values dono separately ek majority pa jaayein — woh
overlapping node ko dono accept karna padta, jo protocol ke voting rules
prevent karte hain. Woh overlap property hi poori wajah hai ki majority-based
agreement safe hai.

Paxos apne full form mein samajhna aur correctly implement karna notoriously
hard hai (competing proposers handle karne ke liye multiple sub-protocols,
etc.) — yahi exactly wahi gap hai jise Raft close karne ke liye design kiya
gaya tha.

### Raft

**Raft** explicitly ek zyada understandable alternative ke taur par Paxos ke
liye design kiya gaya tha, consensus ko do separable sub-problems mein
decompose karte hue jinhe aap independently reason kar sako: leader election
aur log replication.

**Leader election:**
- Time **terms** mein divide hota hai (monotonically increasing numbers,
  jaise ek "epoch" ki tarah ki kaun charge mein hai).
- Nodes followers ki tarah start karte hain. Agar ek follower ek timeout ke
  andar leader se ek **heartbeat** nahi sunta, to woh ek candidate ban jaata
  hai, term increment karta hai, aur doosre nodes se votes request karta hai.
- Har node har term ke liye zyada se zyada ek candidate ko vote karta hai
  (pehla valid request uska vote jeetta hai). Ek candidate jise nodes ka
  ek **majority** vote milta hai woh us term ke liye leader ban jaata hai.
- Randomized election timeouts (har node ek random amount wait karta hai
  election shuru karne se pehle) is chance ko kam karte hain ki multiple
  nodes ek saath candidate ban jaayein aur vote split ho jaaye.

**Log replication:**
- Sab writes leader ke through jaate hain. Leader operation ko apne local
  log mein append karta hai, phir usse sab followers ko bhejta hai.
- Ek baar jab nodes ka ek **majority** (leader included) ne entry durably
  store kar li ho, to leader use **committed** consider karta hai aur apne
  state machine par apply karta hai, phir followers ko batata hai ki woh
  bhi same kar sakte hain.
- Agar leader mar jaaye, to ek nayi election hoti hai; newly elected leader
  guaranteed hai (election rules ke through) ki uske paas sabse up-to-date
  committed log ho, isliye koi committed data lost nahi hota.

```text
   Client write
        |
        v
   +----------+   replicate   +-----------+
   |  Leader  |--------------->| Follower A|
   +----------+                +-----------+
        |        replicate     +-----------+
        +---------------------->| Follower B|
                                +-----------+
   Committed once a MAJORITY (leader + 1 follower here) have the entry.
```

Raft woh hai jise aapko interview mein naam se reach karna chahiye jab
poocha jaaye "yeh cluster kaise agree karta hai ki kaun leader hai / writes
ka order kya hai" — yeh industry-common answer hai (etcd, Consul, aur kai
doosre real systems Raft specifically implement karte hain uski
understandability ki wajah se).

### Practice mein leader election: coordination services

Almost koi bhi company Paxos ya Raft ko application ke andar scratch se
reimplement nahi karti — yeh genuinely correctly implement karna hard hai
(subtle bugs data loss cause karte hain). Iske bajaye, systems leader
election aur shared configuration management ko ek **coordination service**
ko delegate karte hain — ek chota, separately-run cluster jiska poora kaam
hai consensus correctly run karna aur ise ek simple API ki tarah expose
karna (locks, leader-election primitives, ek chota consistent key-value
config store).

- **ZooKeeper**: ek Paxos-like protocol (ZAB) par built hai; widely use hota
  hai (historically Kafka, HBase, aur kai doosron ne) leader election aur
  distributed configuration ke liye.
- **etcd**: directly Raft par built hai; Kubernetes apne poore cluster state
  store ke liye use karta hai, aur commonly leader election aur service
  configuration ke liye kahin aur bhi use hota hai.

Interview mein pattern: "consensus khud build karne ke bajaye, main ek
etcd/ZooKeeper cluster run karunga aur har service instance ko wahan ek
leader lock acquire karne ki koshish karwaunga" ek strong, realistic answer
hai.

## Gossip protocol

Ek **gossip protocol** (epidemic protocol) hai jaise ek bade cluster mein
nodes bina ek central coordinator ke state share karte hain: periodically
(jaise, ek second mein ek baar), har node kuch random peers pick karta hai
aur unke saath abhi jo pata hai (cluster membership, node health, metadata)
exchange karta hai. Kai rounds mein, information cluster mein exponentially
propagate hoti hai — kisi tarah jaise ek rumor ek population mein failta hai
— jab tak har node eventually same view par converge nahi kar leta.

Yeh **cluster membership** aur **failure detection** ke liye scale par kyun
use hota hai (jaise, Cassandra mein, aur Dynamo-style systems mein generally):
- Membership info ke liye koi single node bottleneck ya single point of
  failure nahi hai — koi central "membership server" nahi jo overload ho
  jaaye ya lost ho jaaye.
- Yeh achhi tarah scale karta hai: har node par load roughly constant rehta
  hai chahe cluster ki size kitni bhi ho, kyunki har node sirf ek handful
  random peers se hi baat karta hai har round mein, poore cluster se nahi.
- Yeh inherently partial failures ke against resilient hai — kuch
  unreachable nodes baaki cluster ko converge hone se nahi rokte, woh bas
  failed mark ho jaate hain jab enough peers unse na sunne ki report karte
  hain.

Trade-off yeh hai ki gossip **eventually consistent** hai — kuch number of
rounds lagte hain (typically seconds) ek state change (jaise, "node X abhi
mara") ko har jagah propagate hone mein, isliye ek window hoti hai jahan
different nodes ke cluster membership ke different views hote hain.

## Distributed transactions

Ek distributed transaction multiple independent nodes/services mein span
karti hai, aur sab ko ya to sab commit karna hai ya sab rollback — koi
partial application nahi.

### Two-Phase Commit (2PC)

2PC ek single atomic decision multiple participants ke across banane ke
liye classic protocol hai, jise ek **coordinator** node coordinate karta hai:

1. **Prepare phase**: coordinator har participant se poochta hai "kya tum
   ise commit kar sakte ho?" Har participant woh sab kaam karta hai jo yeh
   guarantee karne ke liye chahiye ki woh *kar sakta hai* commit agar bataya
   jaaye (jaise, locks acquire karta hai, ek durable log mein likhta hai)
   aur yes/no reply karta hai.
2. **Commit phase**: agar *sab* participants ne yes bola, to coordinator
   sabko commit karne ko kehta hai. Agar *kisi ne bhi* no bola (ya timeout
   ho gaya), to coordinator sabko abort karne ko kehta hai.

```text
Coordinator          Participant A        Participant B
    |-- PREPARE ------->|                     |
    |-- PREPARE --------------------------->|
    |<-- YES ------------|                     |
    |<-- YES ---------------------------------|
    |-- COMMIT --------->|                     |
    |-- COMMIT ------------------------------>|
```

**Yeh fragile kyun hai**: participants jinhone "yes" vote kiya woh already
locks le chuke hain aur final decision ka wait kar rahe hain — woh unilaterally
commit ya abort decide nahi kar sakte, kyunki coordinator abhi bhi *doosre*
participant ko kuch alag bata sakta hai. Agar **coordinator prepare phase ke
baad lekin commit/abort decision bhejne se pehle crash ho jaata hai**, to har
participant apne locks ke saath indefinitely stuck ho jaata hai, apne aap
proceed nahi kar sakta (isse "blocked" hona kehte hain). Yeh 2PC ki core
weakness hai: yeh correctness ko coordinator failure ke dauran availability
ke against trade karta hai.

### Saga pattern

**Saga pattern** microservices-era ka alternative hai un operations ke liye
jo multiple services mein span karte hain, aur yeh deliberately distributed
locks hold karne se bachta hai. Ek saga local transactions ki ek sequence
hai, har ek ek service mein, jahan har step ke saath ek paired
**compensating action** hoti hai — ek step jo apna effect undo kar deta hai
agar sequence mein koi baad wala step fail ho jaaye.

Example — ek order-payment-inventory saga "order place karo" ke liye:
1. Order service order create karta hai (status: pending).
2. Payment service customer ko charge karta hai.
3. Inventory service stock reserve karta hai.

Agar step 3 fail ho (out of stock), to saga reverse order mein compensations
run karta hai: payment refund karo (step 2 ko compensate karta hai), order
cancel karo (step 1 ko compensate karta hai). Kabhi bhi teeno services ke
across ek distributed lock hold nahi hua tha — har step locally aur turant
commit hua, aur failure *undo karke* handle hota hai, na ki ek aisi
transaction ko *rollback karke* jo kabhi poori tarah commit hi nahi hui thi.

**Choreography vs orchestration** — sequence drive karne ke do tareeke:

| | Choreography | Orchestration |
|---|---|---|
| How it works | Each service publishes events; other services subscribe and react independently | A central orchestrator explicitly calls each service in sequence and tracks saga state |
| Example flow | Order service emits `OrderCreated` → Payment service listens, charges, emits `PaymentCompleted` → Inventory service listens, reserves stock | A saga orchestrator calls "create order," then calls "charge payment," then calls "reserve inventory," handling failures itself |
| Coupling | Loose — services don't know about each other directly, only events | Orchestrator knows about and depends on every participant |
| Visibility into overall flow | Hard — logic is smeared across services' event handlers | Easy — the whole sequence lives in one place |
| Best for | Simple sagas, few steps | Complex sagas, many steps, need for central error handling/monitoring |

Koi bhi strictly better nahi hai: choreography services ko decoupled rakhta
hai lekin end-to-end flow ko reason karna ya debug karna hard bana deta hai
("is event par kisko react karna hai?"); orchestration flow ko explicit aur
monitor karna easy banata hai lekin ek central component reintroduce karta
hai jis par har participant depend karta hai.

## Idempotency

Kyunki networks unreliable hain, **retries unavoidable hain**: agar ek
client ek request bhejta hai aur apne timeout se pehle koi response nahi
milta, to yeh genuinely tell nahi kar sakta ki request kabhi pahunchi hi
nahi, pahunchi lekin server finish karne se pehle crash ho gaya, ya server
ne successfully finish kar diya lekin *response* wapas aate hue lost ho
gaya. Sirf safe assumption hai "shayad kaam nahi hua," isliye client retry
karta hai — lekin iska matlab hai server ko same logical request ek se zyada
baar receive karne ke liye ready rehna hoga.

**Idempotency** woh property hai jisme same request ko multiple baar process
karna same result deta hai jitna ek baar process karne se — chahe woh kitni
bhi baar retry ho.

Standard mechanism: ek **idempotency key** — ek unique identifier jo
*client* har logical operation ke liye ek baar generate karta hai aur us
same request ke har retry par attach karta hai (jaise, ek UUID jo ek header
ki tarah "50 dollar charge karo" payment request par bheja jaata hai).
Server yeh store karta hai ki usne konse idempotency keys already process
kiye hain (result ke saath); agar ek request ek key ke saath aati hai jo
pehle dekhi ja chuki hai, to woh operation dobara execute karne ke bajaye
stored result return karta hai. Yeh "response milne tak retry karo" ko ek
dangerous operation (customer ko double-charge karna) se ek safe operation
mein badal deta hai.

`10_message_queues_and_streaming.md` mein delivery-semantics discussion se
distinction note karo: idempotency woh cheez hai jo "at-least-once delivery"
ko caller ke perspective se "exactly-once" ki tarah treat karna safe banati
hai.

## Distributed locks

Ek **distributed lock** alag processes ya machines ke across mutual
exclusion provide karta hai — ensure karta hai, jaise, ki ek fleet mein sirf
ek worker ek diye gaye job ko ek time par process kare, chahe unme se koi
bhi use pick kar sakta ho.

Common implementations:
- **Redis `SETNX` with a TTL**: `SET lock_key unique_value NX PX 30000` key
  ko atomically set karta hai sirf tab jab woh already exist nahi karti,
  ek time-to-live ke saath taaki lock apne aap expire ho jaaye agar holder
  bina release kiye crash ho jaaye. Simple aur fast, lekin ek single Redis
  instance lock ke liye single point of failure hai.
- **Redlock**: ek Redis-specific algorithm jo lock ko independent Redis
  instances ke majority ke across acquire karta hai, jiska intent hai ek
  single-instance lock se zyada safe hona node failure ke under (halaanki
  yeh genuinely debated hai distributed-systems community mein ki kya yeh
  correctness-critical use cases ke liye strong enough guarantees deta hai).
- **ZooKeeper ephemeral nodes**: ek client ek ephemeral znode create karta
  hai (jise ZooKeeper automatically delete kar deta hai agar client ka
  session mar jaaye) lock ownership represent karne ke liye — TTL-based
  expiry ke bajaye ZooKeeper ki apni consensus guarantees par lean karta
  hai.

**Classic pitfall**: TTL-based locks assume karte hain ki holder apna kaam
finish kar lega (ya fail hokar expire hone dega) TTL window ke andar. Lekin
agar lock holder unexpectedly pause ho jaaye — ek long GC pause, ek slow
disk I/O stall, ek suspended VM — TTL se *zyada* time ke liye, to lock
expire ho jaata hai aur doosra process "same" lock acquire kar leta hai
jabki pehla process abhi zinda hai aur kaam resume karne wala hai, believe
karte hue ki woh abhi bhi lock hold karta hai. Ab do processes sochte hain
ki woh resource ko exclusively own karte hain.

**Fix, briefly**: **fencing tokens** — lock service har baar jab lock grant
karti hai ek monotonically increasing number deti hai. Lock holder jo bhi
write protected resource ko karta hai usme apna fencing token include karna
hota hai, aur resource (jaise, ek storage service) kisi bhi write ko reject
kar deta hai jisme token sabse latest se *purana* ho jo usne already dekha
ho. Toh agar ek stale lock holder wake up ho kar act karne ki koshish bhi
kare, uska outdated token reject ho jaata hai.

## Clock synchronization

**NTP (Network Time Protocol)** har machine ke wall-clock time ko reference
time servers ke against synchronize karta hai, clocks ko roughly sync mein
rakhte hue (typically well-configured networks par tens of milliseconds ke
andar, halaanki yeh network issues ya VM scheduling ke under degrade hota
hai).

**Wall-clock time NTP ke saath bhi events ko order karne ke liye poori tarah
trust kyun nahi ki jaa sakti**: NTP ke saath bhi, clocks kabhi perfectly
synchronized nahi hote — hamesha kuch drift aur correction lag hota hai, aur
ek correction ek clock ko backward bhi jump kara sakta hai. Agar aap do
events ko different machines par purely unke wall-clock timestamps se order
karte ho, to aap order galat pa sakte ho — event B ka timestamp event A se
pehle ho sakta hai chahe A ne actually B ko cause kiya ho.

**Logical clocks — Lamport timestamps**: real time measure karne ki koshish
karne ke bajaye, ek logical clock directly **causality** ("happened-before"
relationships) capture karta hai. Har node ek counter rakhta hai; woh har
local event se pehle counter increment karta hai, aur jab bhi woh ek message
bhejta hai to apna current counter value include karta hai, aur receiver
apna counter `max(local counter, received counter) + 1` par set kar deta hai
receive hone par. Yeh guarantee karta hai ki agar event A ne causally event
B ko influence kiya (jaise, A ka message B hone se pehle receive hua), to A
ka Lamport timestamp strictly B se kam hoga — ek real time-based clock yeh
guarantee nahi de sakta, lekin ek logical clock de sakta hai, kyunki yeh
ordering purely message-passing relationships se derive karta hai, possibly-
untrustworthy wall clock se nahi.

## Trade-offs / When to use what

| Need | Reach for |
|---|---|
| Cluster-wide agreement on a single value, leader election | Consensus (Raft/Paxos) — usually via etcd/ZooKeeper, not reimplemented |
| Fast, low-overhead cluster membership / failure detection at scale | Gossip protocol |
| Atomic all-or-nothing commit across a few tightly-coupled resources you fully control | 2PC — but know it blocks on coordinator failure; rare in modern microservice designs |
| Atomic-feeling multi-service workflow in a microservices architecture | Saga (choreography for simple/few steps, orchestration for complex/many steps) |
| Safety under client retries | Idempotency keys |
| Exclusive access to a shared resource across processes | Distributed lock + TTL + fencing tokens |
| Ordering events without trusting wall-clock time | Logical clocks (Lamport timestamps) |

## Interview Tips

- "Aap kaise ensure karoge ki is cron job ka sirf ek instance poore fleet
  mein chale?" ek distributed-lock question hai — TTL mention karo, crash/
  expiry pitfall, aur fencing tokens; wo last detail depth signal karti hai.
- "Yeh replicas kaise agree karte hain ki primary kaun hai?" ek leader-
  election/consensus question hai — Raft ki leader election + log
  replication (terms, heartbeats, majority commit) naam se batana expected
  depth hai; aapse Paxos ki correctness proof derive karne ki expect nahi
  ki jaati.
- "Payment API call timeout ho gaya — aap kya karoge?" idempotency reasoning
  test kar raha hai: aapko turant kehna chahiye "same idempotency key ke
  saath retry karo" na ki "bas retry karo," aur explain karna chahiye ki
  naive retry kyun double charge ka risk leta hai.
- Agar cross-service checkout/order flow design karne ko kaha jaaye, to
  proactively Saga pattern mention karo, "sab kuch ek distributed
  transaction mein wrap karo" ke bajaye — interviewers 2PC-across-
  microservices ko production designs ke liye ek red flag ki tarah padhte
  hain.
- "Yeh events order karne ke liye timestamps kyun use nahi karte?" yeh probe
  kar raha hai ki aap clock skew samajhte ho ya nahi — NTP ki limits mention
  karo aur logical clocks/happened-before par pivot karo agar sawaal
  correctness-critical ordering ke baare mein hai.

## Quick Recall — Self-Test

**Q1: Distributed environments ki teen properties kya hain jo unhe single-machine programming se fundamentally harder banati hain?**
Partial failure (kuch nodes fail hote hain jabki baaki kaam karte hain, aur aap often bata nahi sakte kaun sa), koi shared global clock nahi (clocks independently drift karte hain), aur unreliable/asynchronous networks (messages delay ho sakte hain, drop ho sakte hain, duplicate ho sakte hain, ya reorder ho sakte hain bina kisi guaranteed bound ke).

**Q2: Majority-based agreement (Paxos/Raft mein) safely nodes ki ek minority ki failure kyun tolerate karta hai?**
Same set of nodes se li gayi koi bhi do majorities kam se kam ek common node share karti hain, isliye do alag values kabhi bhi independently ek majority nahi jeet sakti — us shared node ko dono accept karne padte, jo protocol prevent karta hai. Iska matlab hai system correct aur available dono rehta hai jab tak nodes ka majority reachable hai.

**Q3: Two-Phase Commit ki core weakness kya hai, aur Saga pattern isse kaise avoid karta hai?**
Agar coordinator prepare phase ke baad lekin final commit/abort decision bhejne se pehle crash ho jaata hai, to participants indefinitely locks hold kiye blocked reh jaate hain. Sagas isse avoid karte hain kabhi bhi cross-service lock hold hi na karke — har step locally aur turant commit hota hai, aur failures baad mein compensating actions ke through handle hote hain jo complete hue steps ko undo karte hain.

**Q4: Ek client simply retries avoid kyun nahi kar sakta idempotency concerns sidestep karne ke liye?**
Kyunki ek client jise timely response nahi milta woh "request kabhi pahunchi hi nahi," "pahunchi lekin server finish karne se pehle crash ho gaya," aur "succeed ho gaya lekin response lost ho gaya" mein distinguish nahi kar sakta — retry karna hi network unreliability ke under progress karne ka ek tareeka hai, isliye server ko duplicate requests safely handle karne ke liye build karna zaroori hai.

**Q5: Ek worker ke paas ek Redis-based distributed lock hai 30-second TTL ke saath, phir usse ek 45-second GC pause hota hai. Kya galat hota hai, aur kya fix karta hai?**
Lock 30 seconds par expire ho jaata hai jabki worker abhi bhi paused hai aur believe karta hai ki usne lock hold kar rakha hai; doosra worker phir same lock acquire kar sakta hai, aur dono believe karte hain ki unke paas exclusive access hai jab pehla resume karta hai. Fencing tokens isse fix karte hain: har lock grant ek monotonically increasing token carry karta hai, aur protected resource kisi bhi write ko reject kar deta hai jisme token usse latest se purana ho jo usne dekha ho.

**Q6: Raft ko Paxos se "zyada understandable" kyun describe kiya jaata hai, aur uske do main sub-problems kya hain?**
Raft consensus ko do separable, independently reason kiye ja sakne wale parts mein decompose karta hai — leader election (terms, votes, heartbeats, randomized timeouts) aur log replication (leader entries append aur replicate karta hai, ek majority acknowledge karne par commit karta hai) — instead of Paxos ke zyada tangled, correctly implement karna harder protocol competing proposers handle karne ke liye.

**Q7: Zyada tar companies Paxos/Raft khud implement karne ke bajaye ZooKeeper ya etcd kyun use karti hain?**
Kyunki consensus correctly implement karna genuinely difficult hai aur bugs data loss ya split-brain cause karte hain; coordination services internally ek well-tested consensus protocol run karti hain (ZooKeeper ke liye ZAB, etcd ke liye Raft) aur ek simple locking/leader-election/config API expose karti hain, isliye application teams ko guarantees milti hain hard distributed-systems code own kiye bina.

**Q8: Cassandra jaise systems mein cluster membership ke liye gossip ko ek central coordinator se better kyun maana jaata hai?**
Ek central coordinator scale par ek bottleneck aur single point of failure hota hai. Gossip mein aisa koi single point nahi hai: har node har round mein sirf kuch random peers se baat karta hai, isliye cluster badhne par bhi per-node load roughly constant rehta hai, aur cluster converge karta rehta hai chahe kuch nodes unreachable ho jaayein — iski cost hai membership view ki sirf eventual (immediate nahi) consistency.
