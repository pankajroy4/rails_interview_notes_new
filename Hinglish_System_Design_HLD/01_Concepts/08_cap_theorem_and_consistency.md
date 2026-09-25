# CAP Theorem and Consistency Models

Ek baar database multiple machines par replicate ho jaaye (`07_database_scaling.md`),
ek naya sawaal unavoidable ho jaata hai: jab woh machines ek doosre se baat
nahi kar paatin, to aapka system kya karta hai? **CAP theorem** us sawaal ke
liye formal framework hai, aur **consistency models** describe karte hain ki
ek distributed system apne diye hue data ki freshness ke baare mein kitni
range ke answers de sakta hai.

## Yeh important kyun hai

Networks fail hote hain. Hypothetically nahi — ek se zyada machine wale kisi
bhi system mein, kuch machines kabhi na kabhi doosron tak reach nahi kar
paayengi: ek switch fail ho jaata hai, ek data center link saturate ho jaata
hai, ek node overloaded hokar time par respond karna band kar deta hai. CAP
aur consistency models samjhe bina:

- Aap ek aisa system design karoge jo silently assume karta hai ki network
  partitions kabhi nahi hote, aur woh pehli baar partition hone par
  unpredictably (ya catastrophically) behave karega.
- Aap explain nahi kar paoge ki aapka NoSQL database kabhi kabhi stale data
  kyun return karta hai, ya aapka relational database failover ke dauran
  kabhi kabhi reads serve karna kyun refuse karta hai — dono ek deliberate
  CAP choice ke direct consequences hain, bugs nahi.
- Aap struggle karoge yeh size karne mein ki kitne replicas ko agree (quorum)
  karna chahiye woh consistency guarantee paane ke liye jo aapko actually
  chahiye, aur ya to consistency ke liye over-pay karoge jo chahiye nahi
  thi, ya under-pay karke silently correctness lose kar doge.

## CAP Theorem, Precisely

CAP theorem kehta hai: ek network **P**artition ki presence mein, ek
distributed system ko **C**onsistency (har read sabse recent write receive
karta hai, ya ek error) aur **A**vailability (har request ko non-error
response milta hai, chahe woh sabse recent data na ho) ke beech choose
karna padta hai.

- **Consistency** yahan matlab hai *linearizability* — har client ek hi
  time par same data dekhta hai, jaise ki sirf ek hi copy ho.
- **Availability** ka matlab hai har request jo ek working node tak pahunchti
  hai use *koi na koi* response milta hai — system kabhi bhi simply answer
  dena refuse nahi karta.
- **Partition tolerance** ka matlab hai system network partitions ke bawajood
  operate karta rehta hai (kuch nodes doosron se communicate nahi kar paate).

**Key insight**: Partition tolerance really ek "choice" nahi hai jaise C aur
A hain. Kisi bhi real distributed system mein jo ek se zyada machine (ya ek
se zyada rack, data center, ya region) tak span karta hai, network partitions
**hongi hi** — yeh ek physical inevitability hai, koi design decision nahi
jisse aap opt out kar sako. Toh CAP theorem practice mein "3 mein se 2 pick
karo" nahi hai — yeh hai: **ek partition eventually hone wala hai; jab woh
hota hai, to yeh system us moment ke liye C choose karta hai ya A?** Ek
system jo bilkul bhi partition-tolerant nahi hai woh real distributed system
nahi hai — woh ek single machine hai, jo sawaal ko sidestep kar deta hai
lekin woh system bhi nahi hai jise CAP describe karti hai.

```text
Normal operation (no partition):
[Node A] <---> [Node B]     both consistent AND available, no trade-off needed

Partition occurs:
[Node A]   X   [Node B]     A and B can't talk to each other
   |                |
   can respond       can respond
   (but might        (but might
   diverge from B)    diverge from A)

  Choose C: refuse to serve some requests until partition heals
            (protect consistency, sacrifice availability)
  Choose A: keep serving from both sides, values may diverge
            (protect availability, sacrifice consistency)
```

## Common Misconceptions

- **"CAP ka matlab hai aap hamesha teen mein se ek sacrifice karte ho."**
  Galat — CAP ek behavior ke baare mein statement hai *specifically ek
  partition ke dauran*. Jab koi partition nahi hai, ek well-designed system
  ek saath consistent aur available ho sakta hai; trade-off sirf tab force
  hota hai jab nodes ke beech network communication actually break ho jaaye.
- **"CAP aapko latency ke baare mein batati hai."** Yeh directly nahi karti
  — CAP correctness (consistency) versus responsiveness (availability) ke
  baare mein hai partition ke dauran, na ki normal, non-partitioned requests
  kitni fast hain iske baare mein. PACELC (neeche) woh extension hai jo
  latency ko explicitly le aata hai.
- **"Ek system CP YA AP HAI, globally, sab kuch ke liye."** Yeh bhi ek
  oversimplification hai — CAP per operation apply hoti hai, aur real
  systems often different operations ke liye different choices karte hain
  ya aapko per-request choose karne dete hain (neeche Cassandra/DynamoDB
  tunable consistency note dekho). Poore system ko "AP" bulaana uske
  *default* behavior ke liye useful shorthand hai, uske andar har code path
  ke baare mein koi absolute, universal guarantee nahi.

## PACELC — The More Complete Extension

CAP sirf ek partition *ke dauran* ka behavior describe karti hai. **PACELC**
isko extend karti hai normal operation ko bhi cover karne ke liye:
**agar ek Partition (P) hai, to Availability aur Consistency (A/C) trade off
karo; Else (E — no partition), Latency aur Consistency (L/C) trade off karo**.

"Else" branch matter karti hai kyunki ek perfectly healthy network ke saath
bhi, strong consistency ki ek cost hoti hai: har replica ko ek value par
agree karwane se pehle **coordination** chahiye — nodes ke beech round trips
yeh confirm karne ke liye ki unke paas same data hai (ya hoga) ek read ya
write acknowledge karne se pehle. Yeh coordination time leti hai. Toh koi
partition na hone par bhi, ek system ko choose karna padta hai: us
coordination ka wait karo (higher latency, strong consistency) ya turant
local/nearby data se respond karo jo thoda stale ho sakta hai (lower
latency, weaker consistency). Isi liye even single-region, well-connected
systems bhi deliberate consistency/latency trade-offs karte hain — yeh
purely ek failure-scenario concern nahi hai.

## Consistency Models

Different systems (aur ek hi system ke andar different operations bhi) yeh
promise karte hain ki ek read most recent write ke against kitni fresh hai.

- **Strong consistency**: har read most recent completed write ko reflect
  karta hai, chahe koi bhi replica use serve kare. Example: ek traditional
  single-leader relational database, jahan reads jo leader ko (ya ek
  synchronously-replicated follower ko) jaati hain hamesha latest committed
  data dekhti hain.
- **Eventual consistency**: ek write ke baad, reads kuch time ke liye stale
  data return *kar sakti* hain, lekin agar koi naya write na ho, to sab
  replicas eventually same value par converge ho jaayengi. Example: ek DNS
  update — domain ki IP address change karne ke baad, duniya bhar mein kuch
  resolvers minutes se hours tak purani IP serve kar sakte hain (caching aur
  propagation delay ki wajah se) is se pehle ki har resolver naye value par
  converge ho jaaye.
- **Causal consistency**: operations jo causally related hain (ek doosre ki
  wajah se hui, ya doosri ko dekh ke hui) sab observers ko same order mein
  dikhti hain; operations jinka koi causal relationship nahi hai different
  observers ko different orders mein dikh sakte hain. Example: agar user A
  ek comment post karta hai aur user B usko reply karta hai, to har viewer
  ko A ka comment B ke reply se pehle dikhna chahiye (woh causally linked
  hain) — lekin do unrelated comments jo different users ne same time par
  post kiye hain, different viewers ko different orders mein dikh sakte hain
  bina kuch break kiye.
- **Read-your-writes consistency**: ek specific guarantee ki ek user jisne
  abhi ek write kiya hai, apni subsequent reads mein woh write hamesha
  dekhega, chahe doosre users abhi use na dekh paayein (kyunki woh unhe
  serve karne wale replicas tak propagate nahi hua). Example: aap apni
  profile photo update karte ho aur turant apni screen par nayi photo dekh
  lete ho, chahe uss exact moment par aapki profile dekh raha ek friend
  briefly purani photo dekh sakta hai. Yeh exactly wahi fix hai
  `07_database_scaling.md` mein describe hui replication-lag symptom ke
  liye — read-your-writes typically implement hoti hai ek user ke apne
  post-write reads ko specifically leader (ya ek caught-up confirm hui
  replica) par route karke.

| Model | Guarantee | Real example |
|---|---|---|
| Strong | Every read sees the latest write | Single-leader RDBMS reading from the leader |
| Eventual | Reads may be stale, converge over time | DNS propagation after a record change |
| Causal | Causally related ops seen in order; unrelated ops can reorder | Comment/reply threads |
| Read-your-writes | You always see your own writes immediately | Your own profile update appearing instantly for you |

## Quorum Reads and Writes

Leaderless (Dynamo-style) replication mein, consistency ek **quorum** ke
through tune hoti hai — ek minimum number of replicas ka read ya write mein
participate karna required hota hai, na ki *sab* replicas (jo availability
kill kar degi) ya sirf *ek* (jo consistency kill kar degi).

Define karo:

- **N** = ek piece of data hold karne wale total replicas ki number.
- **W** = kitne replicas ko ek write acknowledge karna hai isse pehle woh
  successful consider ho.
- **R** = kitne replicas ko query (aur unke results reconcile) karna hai
  isse pehle ek read successful consider ho.

**Rule**: agar **W + R > N**, to har possible read set aur har possible
write set guaranteed overlap karta hai kam se kam ek node par — matlab koi
bhi read quorum guaranteed hai ki usme kam se kam ek aisa replica ho jisme
sabse recent write ho, isliye read hamesha latest value find (aur return)
kar sakta hai. Yeh hi leaderless replication ko ek strong consistency
guarantee deta hai *bina* ek single leader ke jo har operation coordinate
kare.

**Worked example**: N=3, W=2, R=2.
- Ek write ko kam se kam 2 replicas mein se 3 mein se acknowledge karna
  hoga isse pehle woh committed consider ho.
- Ek read ko kam se kam 2 replicas mein se 3 ko query karna hoga.
- W + R = 4 > N = 3, isliye koi bhi 2-out-of-3 write set aur koi bhi
  2-out-of-3 read set mathematically guaranteed hai ki ek common replica
  share karein — us shared replica mein latest write hai, isliye read
  guaranteed hai use dekhne ke liye (reconcile karne ke baad, jaise, query
  kiye gaye replicas mein sabse latest timestamp/version wali value pick
  karke).
- Agar iske bajaye W=1 aur R=1 ho (W+R=2, N=3 se zyada nahi), to ek write
  sirf replica A par land ho sakta hai, aur ek read sirf replica B ko query
  kar sakta hai — koi overlap nahi, isliye read stale data return kar sakti
  hai. Yeh ek valid, deliberate configuration hai jab aapko maximum
  speed/availability chahiye aur eventual (not strong) consistency tolerate
  kar sakte ho.

```text
N = 3 replicas: [R1] [R2] [R3]
W = 2: write acknowledged by any 2, e.g. {R1, R2}
R = 2: read queries any 2, e.g. {R2, R3}
Overlap: {R1,R2} ∩ {R2,R3} = {R2}  -> guaranteed to see the write
```

W aur R ko tune karna latency/consistency/availability trade-off par ek
direct lever hai: lower W aur R ka matlab hai faster, zyada available
operations (kam nodes ko respond karna padta hai) lekin weaker consistency
guarantees; higher W aur R (W=R=N tak) ka matlab hai stronger consistency
lekin higher latency aur lower availability (zyada nodes reachable aur
responsive hone chahiye kisi bhi operation ke succeed hone ke liye).

## Vector Clocks

**Simple timestamps kyun enough nahi hain**: ek distributed system mein, har
node ka apna physical clock hota hai, aur machines ke clocks kabhi bhi
perfectly synchronized nahi hote (clock skew) — koi single global "now"
nahi hota. Agar same key par do writes do different nodes par hote hain aur
aap wall-clock timestamps use karke yeh determine karne ki koshish karte ho
ki "kaun pehle aaya," clock skew aapko galat answer de sakta hai, aur isse
bhi zyada, yeh bata bhi nahi sakta ki do writes truly *concurrent* the
(neither ne dusre ko cause kiya, dono independently valid hain) versus ek
genuinely doosre ke baad hua.

**Ek vector clock jo capture karta hai iske bajaye**: ek vector clock
per-node counters ka ek vector hai — ek counter har us node ke liye jisne
data ko touch kiya hai, jo us node ke har write par increment hota hai, aur
merge hota hai (har position ka max lekar) jab bhi nodes information
exchange karte hain. Do vector clocks compare karke, system teen relationships
mein se ek determine kar sakta hai:

- Ek vector clock doosre ko strictly dominate karta hai (har counter ≥ hai,
  kam se kam ek > hai) — matlab woh write genuinely doosre ke *baad* hua aur
  usse *aware* hote hue hua; naya wala safely purane ko supersede karta hai.
- Clocks identical hain — same write, koi conflict nahi.
- **Koi bhi dominate nahi karta** (har ek ke paas kam se kam ek counter
  doosre se zyada hai) — matlab dono writes **concurrently** hue, koi ek
  doosre se aware nahi tha, aur yeh ek genuine conflict hai jo surface karna
  zaroori hai (application ko, ya user ko, jaise classic "apni shopping cart
  merge karo" resolution jo Amazon ke original Dynamo paper mein use hua tha)
  — silently ek pick karke data lose karne ke bajaye, jaise ek naive
  "latest timestamp wins" approach karega.

Vector clocks yahi hai jisse leaderless systems ek global clock par depend
kiye bina real write conflicts detect karte hain — yeh causality (kaun kisse
aware tha) encode karte hain, wall-clock time nahi.

## Real Systems, Grounded

| System | CAP leaning | Why |
|---|---|---|
| Traditional single-leader RDBMS (PostgreSQL, MySQL) | CP-leaning (or effectively unavailable during partition) | A partitioned follower either serves potentially stale data (breaking C) or the system routes all reads/writes to the leader only, becoming unavailable to clients that can't reach it — most configurations favor not serving incorrect data over serving *something* |
| Cassandra / DynamoDB | Tunable per-request (AP-leaning by default) | Leaderless with quorum-based W/R — you can dial toward strong consistency (W+R>N) or toward availability/low-latency (small W and R) per operation, but the systems are architected with availability as the default priority |
| ZooKeeper / etcd | CP by design | Purpose-built for consistent coordination (leader election, distributed locks, configuration) — for these use cases, serving stale or divergent data is actively dangerous (e.g., two nodes both believing they're the leader), so these systems deliberately sacrifice availability during a partition rather than risk incorrect coordination state |

## Trade-offs

| Decision | Favor Consistency (C) | Favor Availability (A) |
|---|---|---|
| During a partition | Reject/block requests that can't be guaranteed fresh | Keep serving all requests, reconcile divergence later |
| Quorum sizing | High W and R (up to W=R=N) | Low W and R (e.g., W=1, R=1) |
| Use case fit | Financial transactions, coordination/locking (leader election), inventory counts | Social feeds, shopping carts, "likes," presence indicators — situations where staleness is a minor UX issue, not a correctness issue |

Koi universal right answer nahi hai — yeh distributed systems ka sabse
fundamental trade-off hai, aur sahi choice poori tarah is baat par depend
karti hai ki us specific operation ke liye *briefly wrong data* zyada bura
hai ya *briefly no data*.

## Interview Tips

- CAP theorem constantly aata hai, aur candidates ki sabse common mistake
  hai yeh kehna ki ek system "CP hai" ya "AP hai" ek unqualified, global
  statement ki tarah. Iske bajaye per operation/data type state karo —
  jaise, "order/payment path ko CP hona chahiye kyunki inventory oversell
  hona ek brief unavailability se zyada bura hai; product-recommendation
  path AP ho sakta hai kyunki stale recommendations harmless hain."
- Interviewers often poochte hain "network partition ke dauran kya hota
  hai?" specifically yeh dekhne ke liye ki aap samajhte ho ki partition
  tolerance optional nahi hai — ek real distributed answer kabhi nahi kehta
  "network kabhi partition nahi hota," woh batata hai ki system tab kya
  karta hai jab woh hota hai.
- PACELC unprompted mention karna, aur specifically Latency/Consistency
  trade-off *normal* operation ke dauran (sirf failures ke dauran nahi), ek
  strong signal hai — yeh dikhata hai ki aap samajhte ho ki CAP apne aap
  mein ek incomplete picture hai.
- Agar coordination chahne wali cheez design karne ko kaha jaaye (leader
  election, ek distributed lock, unique ID generation) — CP systems jaise
  ZooKeeper/etcd ko explicitly reach karo aur explain karo ki availability
  wahan acceptable sacrifice kyun hai.
- Quorum math (W+R>N) ek common concrete follow-up hai — ready raho live ek
  chota numeric example ke through kaam karne ke liye, jaise upar N=3/W=2/
  R=2 case mein kiya, sirf formula cite karne ki jagah.

## Quick Recall — Self-Test

**1. CAP theorem mein "partition tolerance" really ek free choice kyun nahi hai?**
Network partitions kisi bhi ek se zyada machine wale system mein ek physical inevitability hain — aap unhe design se dur nahi kar sakte. Toh CAP practice mein reduce ho jaata hai: jab (agar nahi) ek partition hota hai, to system us moment ke liye Consistency choose karta hai ya Availability?

**2. Is statement ko correct karo: "Hamara system AP hai, isliye yeh kisi bhi cheez ke liye kabhi consistency guarantee nahi karta."**
CAP trade-offs per operation apply hote hain, poore system par globally nahi — kai systems jo "AP" describe hote hain (jaise Cassandra) aapko specific operations ko strong consistency ki taraf tune karne dete hain (jaise quorum settings ke through) jabki baaki jagah availability default rakhte hain. Aur CAP ka consistency/availability trade-off sirf ek actual partition ke dauran apply hota hai; uske bina, ek system ek saath consistent aur available ho sakta hai.

**3. PACELC kya add karta hai jo akela CAP cover nahi karta?**
CAP sirf ek network partition ke dauran wala trade-off describe karta hai. PACELC "Else" branch add karta hai: koi partition na hone par bhi, strong consistency achieve karne ke liye replicas ke beech coordination chahiye, jo latency cost karta hai — isliye completely normal operation ke dauran bhi ek Latency/Consistency trade-off hota hai.

**4. Ek concrete example do jo causal consistency ko eventual consistency se distinguish kare.**
Eventual consistency ke under, koi bhi do writes temporarily kisi bhi order mein dikh sakte hain, sirf eventual convergence ki guarantee ke saath. Causal consistency ke under, agar user B ka reply user A ke original comment par causally dependent hai, to har viewer guaranteed hai A ka comment B ke reply se pehle dekhne ke liye — lekin same time par post hue do independent, unrelated comments ki koi aisi ordering guarantee nahi hai aur different viewers ko different orders mein dikh sakte hain.

**5. N=3, W=2, R=2 use karke walk through karo ki W+R > N kyun guarantee karta hai ki ek read latest write dekhega.**
Kisi bhi write ko 3 replicas mein se 2 acknowledge karne chahiye, aur kisi bhi read ko 3 mein se 2 query karne chahiye. Kyunki total sirf 3 replicas hain, koi bhi do 2-out-of-3 subsets mathematically guaranteed hain ki kam se kam ek replica share karein — us shared replica mein latest write hota hai, isliye woh hamesha read ke results mein included hota hai, jo guarantee karta hai ki read use dekh sake.

**6. Aap sirf wall-clock timestamps use karke yeh kyun determine nahi kar sakte ki ek distributed system mein do concurrent writes mein se "kaun pehle aaya"?**
Different machines ke clocks kabhi bhi perfectly synchronized nahi hote (clock skew), isliye nodes ke across timestamp comparisons galat ho sakte hain. Iske alawa, timestamps yeh distinguish nahi kar sakte ki "yeh write genuinely doosre ke baad hua" versus "yeh do writes concurrently hue aur koi ek doosre ko cause nahi kiya" — jo exactly wahi distinction hai jo conflict detection ke liye matter karta hai.

**7. Do vector clocks ka "concurrent" hona (koi bhi dominate na karna) kya matlab rakhta hai, aur yeh kyun matter karta hai?**
Iska matlab hai har vector clock mein kam se kam ek per-node counter doosre se zyada hai — koi bhi write doosre se aware nahi tha jab woh hua, isliye woh ek genuine conflict hain, ek doosre ko supersede nahi karta. Yeh isliye matter karta hai kyunki ek system jo blindly ek pick kar leta (jaise, "latest timestamp wins") silently valid data discard kar sakta hai; true concurrency detect karna system ko proper resolution ke liye conflict surface karne deta hai.

**8. ZooKeeper/etcd deliberately CP kyun hain, AP nahi?**
Yeh specifically consistent coordination tasks ke liye bane hain jaise leader election aur distributed locking, jahan stale ya divergent data serve karna actively dangerous hai — jaise, agar coordination service ek partition ke dauran inconsistent state serve kare to do nodes har ek khud ko leader samajh sakte hain. Us use case ke liye, answer na dena (availability lose karna) galat answer dene se safer hai.
