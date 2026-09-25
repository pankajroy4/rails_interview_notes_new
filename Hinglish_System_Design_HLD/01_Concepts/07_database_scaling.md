# Database Scaling

Ek single database server, chahe kitna bhi powerful kyun na ho, eventually ek
wall se takra jaata hai: vertical scaling (bigger machine) hard hardware
ceilings mein fasti hai aur uski cost non-linearly badhti hai jaise-jaise aap
sabse bade available machines ke kareeb pahunchte ho (dekho
`02_scalability_and_estimation.md`). Yeh file un do techniques ko cover karti
hai jo ek database ko ek machine ki capacity se aage scale karne dete hain:
**replication** (data ko multiple machines par copy karna read scale aur
fault tolerance ke liye) aur **sharding/partitioning** (data ko multiple
machines mein split karna taaki koi single machine sab kuch na hold kare).

## Yeh important kyun hai

Zyada tar systems eventually database par bottleneck ho jaate hain kisi aur
cheez se pehle, kyunki stateless application servers ke unlike (jinhe aap
endlessly clone kar sakte ho ek load balancer ke peeche, dekho
`04_load_balancing.md`), ek database state hold karta hai — aap bas ek
identical copy spin up karke traffic randomly split nahi kar sakte, kyunki
ek copy ke writes ko kisi na kisi tarah doosri copies tak pahunchna hota hai.
Replication aur sharding ke bina:

- Ek single database server aapke poore system ka write aur read throughput
  cap kar deta hai jo bhi ek machine kar sakti hai — application server ki
  kitni bhi scaling isse fix nahi karti.
- Ek single point of failure ka matlab hai ki database crash poore system ko
  down kar deta hai, koi failover target nahi hota.
- Aapka sara data ek machine ke disk par fit hona chahiye, jo ek certain
  dataset size ke baad physically impossible ho jaata hai.

## Replication

**Replication** ka matlab hai same data ki multiple copies ko alag-alag
machines (**replicas**) par maintain karna. Iski teen main topologies hain.

### Leader-Follower (Master-Slave)

Ek node (**leader**/**master**) sab writes accept karta hai; ek ya zyada
**followers**/**replicas** har write ki copy receive karte hain (replication
log ke through) aur read traffic serve karte hain.

```text
        writes
Client ---------> [Leader]
                      |  replication stream
             ---------+---------
             |                 |
        [Follower A]     [Follower B]
             ^                 ^
             |  reads          |  reads
          Client            Client
```

- **Pros**: reason karna simple hai — sirf ek node kabhi bhi writes accept
  karta hai, isliye koi write-conflict resolution ki zaroorat nahi; read
  capacity zyada followers add karke scale hoti hai.
- **Cons**: leader writes ke liye single point of failure hai (halaanki
  ek promoted follower par failover possible hai); sab writes still ek
  machine ke through bottleneck hoti hain.
- Yeh zyada tar relational databases ke liye default topology hai
  (PostgreSQL streaming replication, MySQL replication) aur bahut saare
  systems ke liye sahi starting point hai.

### Multi-Leader

Ek se zyada nodes writes accept karte hain (often ek leader per data
center/region), aur har leader apne writes doosron ko propagate karta hai.

- **Pros**: writes user ke kareeb har region mein accept ho sakte hain,
  jisse geographically distributed systems ke liye write latency kam hoti
  hai; koi single write bottleneck nahi.
- **Cons**: **conflicts** — agar same record do leaders par almost same
  time par likha jaaye, to system ko do versions ko reconcile karna padta
  hai (last-write-wins, custom merge logic, ya conflict ko application tak
  surface karna). Yeh reason karne mein meaningfully harder hai aur sirf
  tab worth hoti hai jab regions ke beech write latency genuinely matter
  karti hai.

### Leaderless (Dynamo-style)

Koi node leader designate nahi hota — ek client (ya coordinator) directly
multiple replicas par likhta hai, aur reads bhi multiple replicas ko query
karti hain, kisi bhi difference ko reconcile karte hue. Yeh ek **quorum**
model use karta hai (dekho `08_cap_theorem_and_consistency.md` W+R>N formula
ke depth ke liye).

- **Pros**: reads ya writes dono ke liye koi single point of failure nahi;
  highly available — jab tak enough replicas reachable hain, system
  requests serve karta rehta hai chahe kuch nodes down ho jaayein.
- **Cons**: zyada complex client/coordinator logic; explicit conflict
  detection chahiye (jaise vector clocks) kyunki koi single leader write
  order establish nahi karta.
- Cassandra, DynamoDB, aur Riak use karte hain — systems jo partition ke
  dauran availability ko immediate consistency se zyada priority dete hain.

| Topology | Writes accepted at | Conflict handling needed? | Best for |
|---|---|---|---|
| Leader-follower | One node | No (single write path) | Most systems — the default |
| Multi-leader | Multiple nodes | Yes | Multi-region systems needing low write latency everywhere |
| Leaderless | Any replica (quorum-based) | Yes | Very high availability requirements, tolerant of eventual consistency |

### Replication Lag

Leader-follower replication mein, writes followers tak **asynchronously**
pahunchte hain (usually — synchronous replication bhi exist karti hai lekin
har write par latency cost karti hai). Isse ek window banti hai jahan follower
leader se peeche hota hai — **replication lag**.

**Concrete symptom**: ek user comment post karta hai. Write leader ko jaata
hai aur succeed hota hai. User ka page turant refresh hota hai, aur woh
refresh request load-balanced hokar ek aise follower ke paas chali jaati hai
jisne abhi tak naya comment replication ke through receive nahi kiya. User ko
apna hi comment missing dikhta hai — ek confusing "kya mera post fail ho
gaya?" wala experience, jabki write actually succeed ho chuka tha. Yeh exactly
wahi **read-your-writes consistency** problem hai jo
`08_cap_theorem_and_consistency.md` mein cover hui hai, aur yeh read replicas
use karne ka ek direct consequence hai.

## Read Replicas

**Read replicas** exactly wahi followers hain jo upar describe kiye gaye, jo
specifically **read traffic offload** karne ke liye use hote hain
primary/leader se — leader writes handle karta hai (aur optionally kuch
reads), jabki bulk read traffic N followers ke beech distribute hota hai. Yeh
usually pehla scaling step hota hai jab ek single database read volume handle
nahi kar pata, kyunki isme data ki structure change nahi karni padti
(sharding ke unlike) — bas read queries ko different connection par route
karna hota hai.

Trade-off exactly wahi upar wali replication lag problem hai: replica se
reads guaranteed nahi karte ki woh sabse latest write reflect karengi.
Systems jinhe read-your-writes guarantees chahiye, typically ek user ke apne
reads ko unke apne write ke turant baad leader par route karte hain (ya ek
aise replica par jo caught up confirm ho), jabki general read traffic kisi
bhi replica par route hota hai.

## Sharding / Partitioning

**Sharding** (jise **partitioning** bhi kehte hain) ek dataset ko multiple
database instances (**shards**) mein split karta hai, jahan har shard rows ka
ek subset hold karta hai — replication ke unlike, jahan har replica *saara*
data hold karta hai. Sharding tab use hoti hai jab dataset (ya write volume)
kisi single machine ke liye bahut zyada bada ho jaaye, replication ke read
capacity maximize karne ke baad bhi.

### Range-Based Sharding

Rows shard key ki ranges ke hisaab se split hoti hain (jaise, user IDs 1-1M
shard 1 par, 1M-2M shard 2 par; ya date ke hisaab se).

- **Pros**: implement karna simple hai; range queries (jaise "March ke sab
  orders") ek hi shard par rehti hain, kyunki sorted ranges contiguous
  shards mein map hoti hain.
- **Cons**: **hot ranges** ka risk — agar shard key time se correlate karti
  hai (jaise timestamp se sharding), to sab *naye* writes ek hi most-recent
  shard par land hote hain, jabki purane shards idle baithe rehte hain. Ek
  logging system jo date se sharded hai, uska 100% write traffic aaj wale
  shard par hit karta hai.

### Hash-Based Sharding

Shard key ek hash function se guzarti hai, aur hash decide karta hai ki row
konse shard par jaayega (`hash(key) % N`, ya zyada robustly, consistent
hashing ke through — neeche dekho).

- **Pros**: data (aur write load) ko evenly saare shards mein distribute
  karta hai, kyunki ek achha hash function keys ko unke natural distribution
  ke bina uniformly scatter karta hai.
- **Cons**: range-query locality lose ho jaati hai — "March ke sab orders"
  ab har shard mein scattered ho jaate hain, kyunki hashing original
  ordering destroy kar deti hai, isliye ek range query ko har shard mein
  fan out karke results merge karne padte hain.

### Directory-Based Sharding

Ek alag **lookup service** (ek directory) key → shard ka explicit mapping
maintain karti hai, jo har query se pehle consult hoti hai.

```text
Client -> [Directory Service: "key X is on shard 3"] -> Shard 3
```

- **Pros**: maximally flexible — rebalancing data ka matlab bas directory
  entries update karna hai, aur shards keys ke arbitrary, non-formulaic
  groupings hold kar sakte hain (jo specific hot keys ko deliberately
  isolate karne ke liye useful hai).
- **Cons**: har query par ek extra network hop (aur dependency) add hoti
  hai; directory service khud ek critical piece of infrastructure ban jaati
  hai jisko apni khud ki availability aur scaling story chahiye.

| Strategy | Even distribution? | Range queries efficient? | Rebalancing cost | Weakness |
|---|---|---|---|---|
| Range-based | No (can hotspot) | Yes | Moderate | Hot ranges (e.g., recent timestamps) |
| Hash-based | Yes | No (scattered) | High without consistent hashing | Loses locality |
| Directory-based | Depends on mapping | Depends on mapping | Low (just update mapping) | Extra hop, directory becomes critical infra |

### Hot Shard / Hotspot Problem

Chahe strategy koi bhi ho, ek **hot shard** tab hota hai jab ek shard doosron
ki tulna mein disproportionate traffic receive karta hai — sharding scheme ne
*data* ko to evenly split kar diya, lekin *access pattern* ko evenly nahi
kiya. Concrete example: `user_id` se shard karna (ek reasonable, generally-
even scheme), lekin ek user celebrity hai jiske 50 million followers hain —
uske profile ka har view, uske post par har like, har follow action us ek
single shard ko hit karta hai jisme uss ek user ki row hai, chahe baaki har
user ka data kitna bhi evenly spread ho. Fix usually workload-specific hota
hai: ek single hot entity ka data aur split karna (jaise, *us user ke*
followers list ko alag se shard karna), hot shard ke saamne specifically ek
cache layer add karna, ya sirf hot shard ke data ko zyada heavily replicate
karna.

## Consistent Hashing

Hash-shard karne ka naive tareeka hai `shard = hash(key) % N` jahan N shards
ki number hai. Yeh tab tak theek chalta hai jab tak N change na ho (ek shard
add ya remove hota hai) — kyunki `% N` change ho jaata hai, **almost har
key** ab ek alag shard par map hoti hai pehle se, matlab nearly poora dataset
physically move karna padta hai rebalance karne ke liye. Ek bade dataset ke
liye, yeh ek enormous, often infeasible, migration hai jo bas ek machine add
karne ke liye run karni padti hai.

**Consistent hashing** isko solve karti hai. Conceptually:

1. Shard identifiers aur data keys dono same circular space par hash hote
   hain — ek **hash ring** (imagine karo hash values 0 se kisi max value
   tak, wapas 0 par wrap hoti hui, ek circle ki tarah laid out).
2. Har shard ring ke arc ko own karta hai apni position se clockwise agle
   shard ki position tak.
3. Ek key us shard ko assign hoti hai jiski position key ke apne hash
   position se agli clockwise position hai.

```text
                    0
                    |
         Shard A ---+--- Key "cat" (-> Shard B, next clockwise)
        /                              \
       |                                |
  Key "dog"                          Shard B
  (-> Shard A)                          |
       |                                |
        \                              /
         Shard C ---------------------+
              (owns arc from B to C)
```

**Yeh data movement ko kyun minimize karta hai**: jab ek naya shard add hota
hai, to woh ring par ek position leta hai aur sirf ring ka woh portion
(aur isliye keys) "chura" leta hai jo uske aur agle counter-clockwise node
ke beech mein hai — har doosre shard ka ownership completely untouched
rehta hai. Ek shard remove karna similarly sirf uski own ki hui keys ko
affect karta hai, jo ab agle clockwise node ko fall karti hain. Naive `% N`
se compare karo: 4-shard cluster mein ek shard add karna (N=4 -> N=5)
roughly 80% saari keys reshuffle kar deta hai, jabki consistent hashing sirf
un keys ka fraction move karti hai jo naye node ke ring slice mein land
karti hain — typically close to `1/N` data ka, na ki nearly sara.

**Virtual nodes**: sirf kuch real shards ring par place hone se, unki
positions chance se uneven ho sakti hain, jisse ek shard ke paas doosron ki
tulna mein bahut bada arc (aur isliye bahut zyada data/traffic) reh jaata
hai. Fix yeh hai ki har physical shard ko ring par bikhre hue kai **virtual
node** positions di jaayein (jaise, har physical shard ko 100-200 virtual
points milte hain), taaki ownership har shard ke liye ek badi contiguous arc
ki jagah kai chote, scattered arcs se compose ho — yeh average out hokar ek
zyada even distribution deta hai, aur iska matlab yeh bhi hai ki jab koi
shard add ya remove hota hai, to resulting extra/missing load kai doosre
nodes mein thinly spread ho jaati hai ek hi neighbor par dump hone ke bajaye.

## Federation (Functional Partitioning)

**Federation** ek database ko *rows* se nahi (sharding ki tarah) balki
*function/domain* se split karta hai — system ki alag-alag functionality ke
liye alag databases. Jaise: ek `users` database, ek `products` database, aur
ek `orders` database, har ek fully independent database instance (possibly
apni khud ki replication aur apne andar khud ki sharding ke saath bhi).

- **Pros**: har database chota hai aur independently scale, tune, aur
  operate ho sakta hai — `products` database ko heavy read caching chahiye
  ho sakti hai jabki `orders` ko strong transactional guarantees chahiye,
  aur federation har ek ko apne khud ke workload ke liye configure hone deta
  hai instead of ek shared configuration par compromise karne ke.
- **Cons**: aap cross-domain joins ya transactions database level par nahi
  kar sakte — "ek query mein ek user aur uske orders lao" ab application ko
  do databases query karke memory mein join karne ki zaroorat padti hai, aur
  "ek order place karo aur inventory atomically decrement karo" ab ek single
  database transaction par rely nahi kar sakta (yeh exactly wahi tarah ki
  problem hai jise distributed transaction patterns jaise Saga, jo
  `09_distributed_systems_core.md` mein cover hai, solve karne ke liye
  exist karte hain).

## Resharding Challenges

N shards se N+1 shards par move karna ek database ki life ke sabse
operationally dangerous events mein se ek hai, consistent hashing ke saath
bhi, kyunki:

- Data ko physically naye shard par copy karna padta hai jabki system online
  rehta hai aur traffic serve karta rehta hai — ek live migration, offline
  nahi.
- Har layer jo requests ko shards par route karti hai (directory service,
  application code mein hashing logic, connection pools) ko consistently
  update karna padta hai, ideally bina us window ke jahan kuch requests
  purani mapping use karein aur kuch nayi.

Practice mein do mitigations use hoti hain, often saath mein:

1. **Consistent hashing** (upar) kisi bhi resharding event ke liye move hone
   wale data ke *fraction* ko limit karti hai, lekin usko actually move karne
   ki operational complexity ko eliminate nahi karti.
2. **Nodes se kaafi zyada shards mein pre-splitting**: kai systems shuru mein
   hi, kahiye, 4096 logical shards create karte hain, lekin initially kai
   logical shards ko sirf mutthi bhar physical nodes par map karte hain. 4
   nodes se 8 nodes tak scale out karna phir matlab hota hai *reassign*
   karna ki konsa physical node konse existing logical shards ko own karta
   hai (poore, already-defined shards ko move karna, jo ek bahut simpler
   aur cheaper operation hai) instead of data ko scratch se new boundaries
   mein *re-partition* karna. Yeh Vitess (MySQL ke liye) aur kai managed
   sharded databases jaise systems mein ek common pattern hai.

## Trade-offs

| Decision | Choose this... | ...when |
|---|---|---|
| Leader-follower vs multi-leader | Leader-follower | Single-region, or writes can tolerate going to one place |
| | Multi-leader | Multi-region with low write-latency requirements, and you can handle conflicts |
| Range vs hash sharding | Range-based | Range queries are common and the key doesn't correlate with a hot dimension (like time) |
| | Hash-based | Even write distribution matters more than range-query efficiency |
| Sharding vs federation | Sharding | One logical entity (e.g., users) is too large/hot for one database |
| | Federation | The system has naturally separable domains that don't need cross-domain transactions |
| Read replicas vs sharding | Read replicas | The bottleneck is read *traffic*, not total data *size* |
| | Sharding | The dataset itself no longer fits on one machine, or write volume exceeds one leader's capacity |

## Interview Tips

- "Database bottleneck hai" system design interview ka ek sabse common
  turning point hai — jab aap yahan pahunchte ho, expected next move hoti
  hai: pehle read replicas (cheapest, no schema change), phir sharding agar
  dataset/write-volume khud problem hai, sirf read traffic nahi.
- Hamesha apni **shard key** explicitly naam lo aur usko system ke actual
  access patterns ke against justify karo — ek unjustified "hum user ID se
  shard karenge" ek common lekin weak answer hai agar interviewer phir
  pooche "agar ek user baaki sabse zyada active ho to?" (hot shard problem)
  aur aapke paas koi ready answer na ho.
- Consistent hashing ek strong signal topic hai — yeh explain kar paana ki
  naive `% N` sharding *kyun* bad hai (sirf yeh bataana nahi ki consistent
  hashing exist karti hai) hi ek memorized answer aur ek understood answer
  mein farak karta hai.
- Replication lag frequently use hoti hai yeh probe karne ke liye ki aap
  samajhte ho ki "read replicas add karna" free nahi hai — ek good candidate
  proactively read-your-writes problem mention karta hai jo yeh introduce
  karta hai, poochhe jaane ka wait kiye bina.
- Federation vs sharding ek subtle distinction hai jo interviewers kabhi
  kabhi directly test karte hain: sharding *ek* logical table/entity ko
  machines mein split karti hai; federation *alag* logical entities ko
  machines mein split karti hai. In dono ko confuse karna shallow
  understanding ka ek common tell hai.

## Quick Recall — Self-Test

**1. Ek sentence mein, vertical scaling akele database strategy ke taur par eventually kyun fail hoti hai?**
Ek single machine par CPU, memory, aur disk I/O ki ek hard ceiling hoti hai, aur ever-bigger machines ki cost non-linearly badhti hai jaise-jaise aap available hardware tiers ke top ke kareeb jaate ho — dekho `02_scalability_and_estimation.md`.

**2. Leader-follower aur leaderless replication mein conflict handling ke terms mein key difference kya hai?**
Leader-follower mein ek single node sab writes accept karta hai, isliye ek inherent, unambiguous write order hoti hai aur koi conflicts resolve nahi karne padte. Leaderless replication multiple replicas par concurrently writes accept karti hai, isliye explicit conflict detection/resolution chahiye (jaise vector clocks) kyunki koi single authority order establish nahi karti.

**3. Replication lag ka ek concrete user-visible symptom describe karo.**
Ek user comment post karta hai (write leader ko jaata hai aur succeed hota hai), phir turant page refresh karta hai; refresh request ek follower replica par route hoti hai jisne abhi tak naya comment receive nahi kiya, isliye user ka apna comment missing dikhta hai chahe write succeed ho chuka ho.

**4. Hash-based sharding range-query efficiency kyun lose karti hai range-based sharding ke comparison mein?**
Hashing keys ko pseudo-randomly saare shards mein scatter karti hai specifically even distribution achieve karne ke liye, jiska matlab hai ki keys jo originally adjacent thi (jaise consecutive dates) ab poori tarah alag shards par end up hoti hain — ek range query ko phir har shard mein fan out karke results merge karne padte hain ek contiguous shard hit karne ke bajaye.

**5. Hot shard problem ko ek concrete example ke saath explain karo.**
`user_id` se sharding generally data ko evenly saare shards mein distribute karti hai, lekin agar ek user celebrity hai jiske millions followers hain, to us user involve karne wala har interaction (profile views, likes, follows) us single shard ko hit karta hai jisme unki row hai — woh shard disproportionate traffic receive karta hai chahe overall data distribution even dikhe.

**6. Naive `hash(key) % N` sharding N change hone par ek badi data migration kyun cause karti hai, aur consistent hashing isse kaise avoid karti hai?**
N change hona `% N` ka result nearly har key ke liye change kar deta hai, isliye nearly poora dataset naye shard par move hona padta hai jispe woh ab map hota hai. Consistent hashing shards aur keys dono ko ek hash ring par place karti hai jahan har shard sirf agle shard tak ka arc own karta hai; ek shard add ya remove karna sirf uske apne arc ki keys ko affect karta hai, baaki har shard ka ownership untouched rehta hai.

**7. Consistent hashing mein virtual nodes kya problem solve karte hain?**
Ring par sirf kuch real shard positions hone se, chance se ek shard ko doosron ki tulna mein bahut bada arc (aur isliye zyada data/traffic) mil sakta hai. Virtual nodes har physical shard ko ring par kai scattered positions dete hain, jisse uska ownership kai chote arcs mein spread ho jaata hai, jo distribution ko even karta hai aur rebalancing load ko kai nodes mein spread karta hai ek hi neighbor par dump karne ke bajaye.

**8. Federation sharding se kaise different hai, aur federation ke saath aap konsi capability lose karte ho?**
Sharding ek *same* logical entity/table ki rows ko machines mein split karti hai; federation *alag* logical entities/domains (jaise, users, products, orders) ko alag databases mein split karti hai. Federation ke saath aap cross-domain joins ya transactions database level par karne ki ability lose kar dete ho — domains ke across data combine karna, ya ek multi-domain change atomically commit karna, ab application code mein hona padta hai.
