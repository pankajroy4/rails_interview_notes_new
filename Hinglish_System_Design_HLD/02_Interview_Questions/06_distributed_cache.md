# Design a Distributed Cache

## Problem Statement

"Design karo ek distributed, in-memory caching system — think ek
simplified Redis ya Memcached cluster — jise application servers ka ek
fleet share kar sake key-value data store aur retrieve karne ke liye
sub-millisecond latency ke saath। Cache ko horizontally scale karna
chahiye many nodes ke across jaise-jaise working set badhta hai, individual
node failures survive karna chahiye bina significant cached data lose
kiye, aur handle karna chahiye us reality ko ki keys ke across popularity
wildly uneven hoti hai।" Yeh woh infrastructure layer hai jo application
servers aur database ke beech baithti hai almost har large-scale system
mein, aur yeh usually "database bottleneck hai" ka follow-up hota hai ek
broader design interview mein।

## Step 1: Requirements Clarify Karo

### Functional Requirements

- Basic key-value operations: `GET(key)`, `SET(key, value, ttl)`,
  `DELETE(key)`.
- Batch operations (`MGET`/`MSET`) multi-key lookups ke liye network
  round trips amortize karne ke liye।
- TTL-based expiry — har key optionally automatically expire ho sakti
  hai।
- Cluster time ke saath grow aur shrink hota hai (nodes capacity ke liye
  add hote hain, maintenance/failure ke liye remove hote hain) bina ek
  full cache flush chahiye।
- Clients (application servers) ko ek tareeka chahiye yeh jaanne ka ki
  konsa node ek given key own karta hai।
- Depth mein out of scope, lekin design se precluded nahi hona chahiye:
  richer data structures (lists, sets, sorted sets) simple strings/blobs
  se aage।

### Non-Functional Requirements

- **Latency**: sub-millisecond p50, low single-digit-millisecond p99
  `GET`/`SET` ke liye — yehi poori wajah hai ki cache exist karta hai
  directly database query karne ki jagah।
- **Throughput**: cluster ke across millions operations/second sustain
  karo।
- **Availability over consistency**: cache system of record nahi hai —
  database hai। Ek cache node ka briefly stale ya even momentarily
  unavailable value serve karna acceptable hai; cache ka down ho jaana
  aur 100% traffic ko database pe force karna acceptable nahi hai। Yeh
  Step 6 ke almost har trade-off ko shape karta hai।
- **Horizontal scalability**: nodes add ya remove karna sirf keys ka ek
  small fraction hi remap karna chahiye, poore dataset ke across ek mass
  cache miss cause nahi karna chahiye।
- **Fault tolerance**: ek single node lose karna saare keys ke liye data
  loss cause nahi karna chahiye jo woh own karta tha, na hi ek
  synchronized wave of cache misses (thundering herd) database ke against
  cause karni chahiye।
- **Even load distribution**: normal, evenly-distributed key access ke
  under koi single node hotspot nahi banana chahiye — aur design ke paas
  ek explicit answer hona chahiye jab access evenly distributed *na* ho
  (hot keys)।

## Step 2: Back-of-Envelope Estimation

**Assumptions**:
- Cache ek service ke aage hai jo peak pe 200,000 requests/sec handle
  karti hai।
- Har incoming request average 3 cache lookups trigger karti hai (ek
  typical page/API response jo several cached objects se assemble hoti
  hai)।
- Cache hit rate high hai (~90%), jo cache ka poora point hai — misses
  database tak fall through karte hain।
- Read volume ka 10% additionally ek cache write produce karta hai
  (populate-on-miss, ya explicit invalidation-driven update)।
- Average cached value size: 2 KB (ek serialized object — user profile,
  rendered fragment, query result)।
- Target working set: 100 million hot keys ek saath cache mein resident।

**Operation QPS**

```
Reads:  200,000 req/sec × 3 lookups/req = 600,000 GET ops/sec at peak
Writes: 600,000 × 10% ≈ 60,000 SET ops/sec at peak
```

**Data size**

```
100,000,000 keys × 2 KB/value = 200,000,000 KB = 200,000 MB = 200 GB total working set
```

Ek replication factor of 2 (Step 6) ke saath availability ke liye:

```
200 GB × 2 = 400 GB total memory footprint across the cluster
```

**Node sizing**

Assume karo har cache node ek 64 GB RAM instance pe chalta hai, ~50 GB
usable cached data ke liye OS, connection buffers, aur internal
data-structure overhead ke liye headroom reserve karne ke baad:

```
Nodes needed for data: 400 GB / 50 GB ≈ 8 nodes minimum
```

Availability ke liye headroom add karo (taaki ek node lose karna baaki
sabko immediately overflow na kare) aur load ko har node pe thinner
spread karne ke liye:

```
~12-16 nodes in the cluster
```

**Per-node throughput check**

```
600,000 read ops/sec / 12 nodes = 50,000 ops/sec/node
```

Ek well-tuned in-memory KV node (Redis/Memcached-class) comfortably
50,000-100,000+ simple ops/sec handle karta hai modern hardware pe,
isliye yeh ek reasonable node count hai, under- ya over-provisioned
nahi।

**Bandwidth**

```
600,000 ops/sec × 2 KB avg value = 1,200,000 KB/sec ≈ 1.2 GB/s cluster-wide
Spread across 12 nodes: 1.2 GB/s / 12 ≈ 100 MB/s/node ≈ 800 Mbps/node
```

Yeh ek single 10 Gbps NIC per node ke andar comfortably fit hota hai,
replication traffic ke upar bhi kaafi headroom ke saath।

**Replication traffic overhead**

Replication factor 2 pe, har write ek baar aur ship hoti hai replica ko:

```
60,000 SET ops/sec × 2 KB = 120,000 KB/sec ≈ 117 MB/s additional cluster-wide traffic for replication
```

Un nodes ke across spread jo replica targets ki tarah act karte hain, yeh
roughly ek aur 10 MB/s per node add karta hai primary read/write traffic
ke upar — jo already compute kiye gaye 100 MB/s ke muqable small hai,
yehi wajah hai ki replication factor 2-3 is scale pe bhi affordable hai;
replication ki real cost memory hai (Step 2 ka 400 GB footprint already
usse include karta hai), network nahi।

**Connections**

Assume karo, say, 2,000 application server instances har ek ek small
persistent connection pool (jaise, 5 connections) cache cluster ko khula
rakhta hai:

```
2,000 app servers × 5 connections = 10,000 total connections
10,000 / 12 nodes ≈ 830 connections/node
```

Ek well-tuned cache node isse comfortably handle karta hai (Redis/
Memcached routinely tens of thousands concurrent connections per
instance handle karte hain), isliye connection count is scale pe ek
limiting factor nahi hai — yeh sirf ek kaafi bade application fleet size
pe relevant ban jaata hai।

## Step 3: High-Level Design

```text
                    +-------------------------+
                    |   Application Servers    |
                    +------------+-------------+
                                 |
                 +---------------+---------------+
                 |     Client Library / Proxy     |   <- runs consistent-hashing
                 |  (knows which node owns a key) |      logic (Step 6)
                 +----+----------+----------+-----+
                      |          |          |
            +---------+   +------+---+   +--+-------+
            | Cache    |   | Cache    |   | Cache    |   ... (hash ring, N nodes)
            | Node A   |   | Node B   |   | Node C   |
            | (primary |   | (primary |   | (primary |
            |  shard 1)|   |  shard 2)|   |  shard 3)|
            +----+-----+   +----+-----+   +----+-----+
                 |               |              |
            replicate       replicate      replicate
                 |               |              |
            +----v-----+   +----v-----+   +----v-----+
            | Replica  |   | Replica  |   | Replica  |
            | of C's   |   | of A's   |   | of B's   |
            | shard    |   | shard    |   | shard    |
            +----------+   +----------+   +----------+

            +-------------------------------------+
            |     Coordination Service (etcd/      |
            |     ZooKeeper or gossip) — tracks     |
            |     cluster membership + hash ring    |
            +-------------------------------------+

                         (on a cache miss)
                                 |
                                 v
                    +-------------------------+
                    |        Database          |
                    +-------------------------+
```

**Flow**: ek application server client library (ya ek proxy layer,
Step 6) se ek key ke liye poochta hai। Library consistent hashing chalati
hai yeh determine karne ke liye ki abhi konsa node us key ko own karta
hai aur directly usse baat karti hai। Hit pe, value ek millisecond se
kaafi kam mein wapas aa jaati hai। Miss pe, application server (common
cache-aside pattern mein — dekho `05_caching.md`) database query karta
hai aur khud cache populate karta hai। Har node ka data asynchronously ya
semi-synchronously kisi doosre node pe replicate hota hai, taaki ek
single node ki failure us keyspace ke slice ko erase na kare। Ek small
coordination layer (ya gossip protocol — dekho
`09_distributed_systems_core.md`) track karta hai kaunse nodes alive hain
aur current hash ring kaisi dikhti hai, taaki clients aur nodes ownership
pe agree karein।

**Key components**:
- **Client library / proxy**: woh layer jo decide karta hai "kaunsa node
  yeh key own karta hai" — central design fork Step 6 mein covered।
- **Cache nodes**: in-memory hash tables, har ek apni khud ki local
  eviction policy (LRU/LFU) independently run karta hai।
- **Replication**: har shard ke primary ke ek ya zyada replicas different
  nodes pe hote hain।
- **Coordination service**: cluster membership aur ring topology ka
  authoritative record, taaki ek node addition/removal consistently agree
  ho, har client independently guess na kare।

**Ek operation ko end to end walk through karte hue**: (1) ek application
server client library pe `GET("user:42")` call karta hai। (2) Library
`"user:42"` ko ring pe hash karti hai aur, topology ki apni locally
cached copy use karke, determine karti hai ki abhi node B us key ke hash
range ko own karta hai। (3) Library request directly node B ko bhejti
hai। (4a) Hit pe, node B value apne in-memory hash table se ek
millisecond se kaafi kam mein return karta hai। (4b) Miss pe, node B
"not found" return karta hai, aur application server (cache-aside use
karke, `05_caching.md`) database query karta hai, phir ek `SET` wapas
same client library ke through issue karta hai, jo phir se key hash
karti hai, phir se node B ko route karti hai, aur node B usse store karta
hai aur asynchronously ek copy apne replica ko ship karta hai। (5) Agar
node B step 3 aur 4 ke beech crash ho jaaye, client library failed
connection detect karti hai (coordination service ke updated membership
view se) aur wapas jis bhi node ne ab woh hash range own kiya hai us
against retry karti hai — promoted replica — dead node ke against retry
karne ki jagah।

## Step 4: API Design

**Ek value get karo**
```
GET /cache/{key}
→ 200 OK { "value": "...", "ttl_remaining_ms": 42000 }
→ 404 Not Found (cache miss)
```

**Ek value set karo**
```
PUT /cache/{key}
{ "value": "...", "ttl_ms": 60000 }
→ 200 OK
```

**Ek value delete / invalidate karo**
```
DELETE /cache/{key}
→ 204 No Content
```

**Batch get** (multi-key reads ke round trips amortize karta hai)
```
POST /cache/mget
{ "keys": ["user:42", "user:43", "post:9001"] }
→ 200 OK
{ "user:42": {...}, "user:43": null, "post:9001": {...} }
```

**Cluster topology** (internal, node-to-node aur client-to-coordination-service)
```
GET /cluster/topology
→ 200 OK
{
  "nodes": [
    { "id": "node-a", "hash_range": [0, 1398101333], "status": "up" },
    { "id": "node-b", "hash_range": [1398101334, 2796202667], "status": "up" }
  ],
  "version": 1284
}
```
`version` field clients ko cheaply detect karne deta hai "kya ring change
hua hai jab se maine last isse locally cache kiya tha" bina har operation
pe poori topology re-fetch kiye।

## Step 5: Data Model

Cache khud traditional sense mein kisi database se backed nahi hai — har
node ek **in-memory hash table** hold karta hai, cache key se keyed,
value ek opaque byte blob plus ek small metadata header:

| Field | Notes |
|---|---|
| `key` | string, the lookup key |
| `value` | opaque bytes (the application decides serialization — JSON, protobuf, etc.) |
| `expires_at` | absolute timestamp derived from TTL, checked lazily on read and/or proactively swept |
| `version` / `last_write_time` | used to resolve conflicts between a primary and a lagging replica on failover |

Yeh ek **in-memory key-value store** class ke system (Redis/Memcached) se
map karta hai, SQL ya ek general document store se nahi — justified
kyunki yaha har access pattern ek point lookup ya point write hai exact
key se, koi relational queries ya secondary indexes ki zaroorat nahi, aur
poora value proposition raw speed hai, jo kisi bhi disk-durability
overhead ko hot path pe rule out kar deta hai।

**Cluster metadata** (ring topology, node health) ek separate, much
smaller data set hai — yeh exactly wahi kism ka small, strongly-consistent,
infrequently-changing configuration data hai jo ek coordination service
mein belong karta hai jaise etcd ya ZooKeeper (dekho
`09_distributed_systems_core.md`) khud cache mein nahi: isko strong
consistency chahiye (har client ko ring ownership pe agree karna chahiye)
low volume pe, jo cached data ke opposite profile hai (high volume,
consistency se zyada availability)।

**Local L1 cache** (Step 6): har application server additionally ek
small, short-TTL in-process cache rakh sakta hai (ek plain in-memory map,
koi separate system nahi) sabse hottest keys ke liye — iska koi formal
schema nahi hai, yeh sirf ek LRU-capped map hai jo application process
mein rehta hai।

**Storage choice justification, summarized**:

| Component | Storage type | Why |
|---|---|---|
| Cached key-value data | In-memory hash table per node (Redis/Memcached-class) | Point lookups/writes only, no relational queries, speed is the entire value proposition |
| Cluster topology / membership | Coordination service (etcd/ZooKeeper) | Small, low-volume, needs strong consistency across every client |
| Local hot-key cache | In-process map on each app server | Zero network hop, per-process, no durability needed |

## Step 6: Deep Dive

### Consistent Hashing key Distribution ke liye

Ek distributed cache ko har operation pe jo core question answer karna
padta hai woh hai "yeh key kaunsa node own karta hai?" Ek naive
`hash(key) % N` mapping catastrophically break ho jaati hai jaise hi `N`
change hota hai — ek single node add ya remove karna modulus change kar
deta hai, jo simultaneously *almost har key* ki ownership reshuffle kar
deta hai poore cluster mein। Concretely, 12 se 13 nodes pe jaana roughly
92% existing key-to-node mappings ko ek saath invalidate kar dega
(`(N-1)/N` keys naive modulo hashing ke under move hoti hain) — un
"moved" keys mein se har ek ab ek aise node pe lookup ki jaati hai jiske
paas woh hai nahi, jo ek mass, synchronized wave of cache misses produce
karta hai jo sab ek saath database tak fall through kar jaati hain। Yehi
exactly woh thundering-herd failure hai jise rokne ke liye yeh cache
banaya gaya tha।

**Consistent hashing** (`07_database_scaling.md` mein general mein
covered; yahan specifically applied) isko fix karti hai dono nodes aur
keys ko same fixed circular hash space pe hash karke (jaise, ek 32-bit ya
160-bit ring)। Ek key us pehle node se owned hoti hai jo key ke hash
position se clockwise walk karke mile। Ek node add karna sirf ring ke us
slice ki ownership leta hai jo uske aur uske counter-clockwise neighbor
ke beech hai — sirf us ek slice ki keys ko move hona padta hai; ek node
remove karna sirf us slice ko affect karta hai jo woh own karta tha, jo
uske clockwise neighbor ko fall karta hai। 12-16 nodes ke saath, ek 13th
node add karna roughly `1/13 ≈ 7.7%` keys remap karta hai ~92% ki jagah —
upar wale exact scenario ke liye cache-miss blast radius mein 10x se
zyada reduction।

**Virtual nodes**: har physical node ko ring pe ek single point pe map
karna uneven load create karti hai agar nodes chance se close together
land kar jaayein (kuch nodes doosron se kaafi larger arcs own kar lete
hain by chance)। Standard fix hai har physical node ko ring pe many
virtual positions dena (commonly 100-200 per physical node) — ownership
ab har node ke many small arcs ka union ban jaata hai, jo near-even load
distribution mein average out ho jaata hai chahe random hash positions
kaise bhi fall hon, aur yeh bhi matlab hai ki ek node ki failure uski lost
capacity ko many doosre nodes' virtual positions ke across spread kar
deti hai, sab kuch ek hi neighbor pe dump karne ki jagah।

### High Availability ke liye Replication

Har shard (ring ka slice jo ek node own karta hai) N-1 additional nodes
pe replicate hoti hai (commonly N=2 ya N=3 total copies), typically ring
pe next clockwise nodes taaki replica placement primary placement jaisi
hi consistent-hashing logic follow kare। Do concrete failure modes jo
yeh address karta hai:

- **Node failure pe data loss**: bina replication ke, ek node crash ka
  matlab hai ki woh jo bhi keys own karta tha ab cache se unrecoverable
  hain (yeh database se gone nahi hai, lekin cache se gone hai, matlab un
  keys mein se har ek ka *next* read ek guaranteed miss hai) — ek live
  replica ke saath, ek promoted replica bina reads ke liye kisi data
  loss ke us slice ko serve karta rehta hai।
- **Failover pe thundering herd**: agar ek node bina replica ke marta
  hai, woh jo bhi keys own karta tha woh sab simultaneously miss karna
  shuru kar deti hain jaise hi traffic reroute hota hai new owner ki
  taraf (jo bhi node ab ring us slice ko map karta hai) — ek synchronized
  spike of database load exactly naive-rehashing problem jaisi, bas
  scaling ki jagah failure se triggered। Ek warm replica isse avoid karta
  hai kyunki woh already data hold karta hai; failover usse in place
  promote karta hai, us key range ko empty se start karne ki jagah।

**Replication mode trade-off**: synchronous replication (write ko sirf
tab acknowledge karo jab replica confirm kare) guarantee karta hai ki
replica kabhi behind na ho, added write latency aur reduced write
availability ki cost pe agar replica slow ya unreachable ho। Asynchronous
replication (immediately acknowledge karo, background mein replicate
karo) write latency low aur availability high rakhta hai, ek small
window ki cost pe jahan ek just-failed primary ke sabse recent writes
abhi replica tak nahi pahunche ho। Is system ki stated priority ke
given (availability over consistency, Step 1), asynchronous replication
standard choice hai — ek rare node crash pe last few milliseconds ki
writes lose karna ek acceptable cost hai har write ko fast rakhne ke
liye, especially kyunki cache kabhi bhi data ki sole copy nahi hoti
(Step 1: database source of truth banni rehti hai)।

| | Synchronous replication | Asynchronous replication |
|---|---|---|
| Write latency | Higher — waits for replica ack | Lower — acks immediately after primary write |
| Write availability | Lower — degrades if replica is slow/unreachable | Higher — unaffected by replica health |
| Data loss window on primary crash | None (replica always caught up) | Small (in-flight, unacknowledged-to-replica writes) |
| Fit for this system | Poor — conflicts with the availability-first NFR | Good — matches "cache, not source of truth" |

**Load-spreading ke liye read replicas, sirf failover ke liye nahi**:
pure availability ke alawa, replicas directly reads bhi serve kar sakte
hain (sirf failover ke liye khade rehne ki jagah), jo ek shard ke liye
read load ko multiple nodes ke across spread karta hai, purely primary pe
concentrate karne ki jagah — yeh ek natural complement hai next discuss
hone wale hot-key mitigations ka, kyunki ek replicated hot key ke paas
already multiple nodes hain uske liye reads answer karne ke capable।

### Cluster Level pe Eviction Policy

Har node apni memory-pressure eviction policy locally enforce karta hai
(LRU ya LFU — pura mechanics ke liye `05_caching.md` dekho), lekin
cluster scale pe interesting wrinkle yeh hai ki **independently, per
node liye gaye eviction decisions phir bhi cluster-wide effects produce
kar sakte hain**। Kyunki consistent hashing har key ko exactly ek owning
node assign karti hai (replicas ko abhi ke liye ignore karke), us node
ka local memory pressure hi *sirf* woh cheez hai jo decide karti hai ki
ek given key survive karti hai ya nahi — koi cluster-wide "poore dataset
ke across least recently used" concept nahi hai, aur ek banane ke liye
constant cross-node coordination chahiye hoga jo us latency budget ko
destroy kar dega jiske liye yeh cache exist karta hai।

Iska ek concrete consequence hai: **uneven key size ya uneven per-node
popularity uneven per-node memory pressure cause karti hai**, chahe
consistent hashing se keys ki *count* balanced ho। Ek node jo by chance
large values ka disproportionate share own karta hai, ya ek heavily-read
tenant ke values, apne neighbors se zyada aggressively evict karta hai —
bahar se yeh "random" extra cache misses jaisa dikhta hai jo keyspace
ke ek part pe concentrated hain, aur fix usually operational hota hai
(per-node memory pressure aur eviction rate monitor karo, sirf
cluster-aggregate hit rate nahi) architectural nahi। TTL jo bhi eviction
policy choose ki gayi ho uske upar exactly single-node case ki tarah
layer kiya jaata hai — yeh staleness ko memory pressure se independent
bound karta hai, jabki LRU/LFU decide karta hai ki node full hone *pe*
kya evict hota hai।

**Cluster scale pe LRU vs. LFU choice single-node trade-off ko mirror
karti hai** (pura mechanics ke liye `05_caching.md` dekho): LRU is
system ke liye default hai kyunki application access patterns typically
time ke saath shift hote hain (kaunse objects "hot" hain yeh product
usage change hone ke saath change hota hai) aur LRU bina kisi per-node
tuning ke automatically adapt karta hai। LFU tab attractive banta hai
jab specifically keys ka ek subset reliably, permanently popular hone
ke liye known ho (jaise, global configuration objects, top-N leaderboard
entries) aur operator ek brief unrelated traffic burst ke unhe evict
karne se guard karna chahta ho — lekin LFU ka newly-trending keys ke
liye slower adaptation ek general-purpose cache ke liye worse fit hai jo
varied application traffic ke aage hai, yehi wajah hai ki LRU zyada
common cluster-wide default rehta hai chahe decision technically per
node independently li jaati ho।

### Hot Key Problem aur Client Library Design

**Hot key problem**: consistent hashing keys ki even *distribution*
cluster ke across guarantee karti hai, lekin *access frequency* ke bare
mein kuch nahi karti — ek single extremely popular key (ek viral post ka
like-count, ek trending product ki price, ek celebrity ka profile) phir
bhi hashing scheme ke under exactly ek node pe map hoti hai, aur agar
akeli woh key cluster ke total read traffic ka ek disproportionate share
receive karti hai, woh ek node overwhelmed ho sakta hai jabki cluster ke
baaki har node capacity se kaafi neeche baithe rehte hain। Yeh
fundamentally different hai ek sharded database ke "hot shard" problem
se, kyunki ek cache ka poora purpose bahut skewed access patterns
absorb karna hai — aur consistent hashing, by design, ek hot key ke saare
traffic ko ek jagah bhej deti hai।

**Mitigations**:
- **Hot keys ko normal replication factor se aage replicate karo**:
  outsized traffic receive karne wali keys detect karo (per-key access
  counters, sampled, se) aur unhe proactively standard N replicas se
  aage additional nodes pe copy karo, phir client library ko batao ki us
  specific key ke saare copies ke across reads round-robin kare। Yeh
  directly ek hot key ke read load ko spread karta hai jaisa normal
  replication nahi karti (normal replicas failover ke liye exist karte
  hain, most configurations mein routine load-spreading ke liye nahi)।
- **Distributed cache (L2) ke aage local in-process cache (L1)**: har
  application server sabse hottest keys ke liye ek small, short-TTL map
  rakhta hai, distributed cache tak pahunchne se pehle hi check ki jaati
  hai। Ek short TTL (seconds, minutes nahi) staleness ko bound karta hai
  jabki phir bhi ek hot key ke request volume ka overwhelming majority
  locally, in-process, zero network hop ke saath absorb karta hai — yeh
  extreme hot-key skew ke liye single most effective mitigation hai,
  kyunki yeh traffic ko distributed cache se entirely remove kar deta
  hai, sirf usse cluster ke aur hisso mein spread karne ki jagah।

**Client library vs. proxy**: calling application actually kaise seekhti
hai konsa node ek key own karta hai?

| | Smart client library | Proxy / router layer |
|---|---|---|
| Who runs the hashing logic | The application process itself, via an embedded library | A dedicated proxy tier (e.g., Twemproxy-style) between app servers and cache nodes |
| Network hops per operation | 1 (app talks directly to the owning node) | 2 (app → proxy → owning node) |
| Latency | Lower (no extra hop) | Slightly higher (extra hop), but often negligible if colocated |
| Topology-change propagation | Every application instance must learn about ring changes independently (via the coordination service) | Only the proxy tier needs to learn about ring changes — a much smaller set of processes |
| Operational simplicity | More moving parts spread across every app server/language | Centralizes cache-routing logic in one place — easier to upgrade, monitor, and reason about |
| Cross-language consistency | Needs a maintained client library per language in a polyglot environment | Proxy is language-agnostic — any client speaks a simple protocol to it |

Koi bhi strictly better nahi hai: ek smart client lower-latency choice hai
aur yehi zyada tar large single-language deployments (ek large Ruby ya
Java monolith fleet) use karte hain ek baar woh hashing logic ek shared
library mein maintain karne ke liye willing hon; ek proxy layer better
choice hai ek polyglot environment mein ya jab operational control
centralize karna (topology changes, monitoring, connection pooling) ek
extra network hop ki cost se zyada important ho।

**Sabse pehle ek hot key detect karna**: koi bhi mitigation useless hai
agar pehle yeh na pata ho ki kaunsi keys hot hain। Practice mein iska
matlab hai per-key (ya per-key-prefix, har individual key track karne ka
overhead avoid karne ke liye) access counts sample karna client library
ya proxy layer pe, top-N sabse zyada accessed keys ko monitoring system
mein export karna, aur ek automatic threshold set karna (jaise, ek key
jo average per-key request rate ke kisi multiple se exceed kare) jo
extra-replication mitigation ko trigger kare bina kisi human ko pehle
problem notice karne ki zaroorat pade — jab tak ek human ek paged alert
se notice karta hai, tab tak owning node already degraded ho sakta hai।

## Step 7: Bottlenecks & Trade-offs

- **Hot keys sabse pehle todte hain**, aggregate cluster capacity nahi —
  Step 2 ka math dikhata hai ki cluster *even* load ke liye comfortably
  sized hai; ek single popular key jo ek node pe disproportionate
  traffic concentrate kar de, ek failure mode hai jise raw node count fix
  nahi karta, sirf Step 6 ke mitigations karte hain।
- **Memory hamesha limiting resource hai**, CPU nahi — ek in-memory
  cache node ki ceiling RAM capacity hai (Step 2: ~50 GB usable per 64
  GB node), isliye trade-off hai fewer, larger (zyada expensive, higher
  blast radius on failure) nodes vs. more, smaller (zyada network
  overhead, zyada operational surface) nodes ke beech।
- **Availability over consistency ki ek real cost hai**: asynchronous
  replication (Step 6) ka matlab hai ki failover pe possible data loss
  ka ek small window ek accepted trade-off hai — ek system jo iski jagah
  har cache write pe strict consistency require karta, uske liye write
  latency mein pay karna padta, directly cache ke poore existence ke
  reason ko undermine karte hue।
- **Ek large-scale event ke baad cache warmth** (ek full cluster restart,
  ek major rebalance jab bahut saare nodes ek saath add kiye jaate hain)
  ka matlab hai ki misses ki ek wave database ko hit karti hai jab tak
  cache refill na ho — yeh same thundering-herd risk hai jitna
  naive-rehashing scenario, aur yeh operationally mitigate kiya jaata hai
  (staged rollouts, ek snapshot se pre-warming, gradual traffic shifting)
  architecturally solve nahi।
- **TTL choice ek permanent staleness-vs-hit-rate dial hai** (dekho
  `05_caching.md`) upar diye gaye sab ke upar layered — distributed-cache
  architecture mein kuch bhi us fundamental trade-off ko change nahi
  karta, yeh sirf determine karta hai ki resulting traffic pattern
  absorb karne mein kitne nodes involved hain।
- **Coordination service ek dependency ban jaati hai**, chahe woh small
  ho — agar clients ring topology seekhne ke liye coordination layer tak
  nahi pahunch paate, woh stale topology information pe fall back karte
  hain, jo requests ko ek aise node pe misroute kar sakta hai jo ab ek
  key range own nahi karta (usually handled karke wrongly-hit node ko
  forward ya reject-with-redirect karke, Redis Cluster ke `MOVED`
  response jaisa)।

**Bottleneck-to-mitigation summary**:

| Bottleneck | Mitigation | Cost accepted |
|---|---|---|
| Naive rehashing on scale change | Consistent hashing + virtual nodes | Slightly more complex client/proxy routing logic |
| Node failure loses a shard | Replication (async) to N-1 replicas | Small window of possible data loss on failover |
| One key overwhelms one node | Extra replication of detected hot keys + local L1 cache | Extra memory for duplicated hot data, brief staleness at L1 |
| Uneven per-node memory pressure | Per-node LRU/LFU + monitoring, not cluster-wide eviction | No global optimality — decisions are local per node |
| Cold cluster after mass restart/rebalance | Staged rollout, pre-warming, gradual traffic shift | Slower recovery in exchange for avoiding a DB-crushing thundering herd |

## Follow-up Questions jo Interviewer Puuch Sakta Hai

**Aap ek multi-region deployment kaise support karoge jahan users apne
nearest region se serve kiye jaate hain?**
Ek global cluster ki jagah har region ke liye ek independent cache
cluster chalao (cross-region network latency sub-millisecond goal ko
defeat kar degi), aur ya to per-region cache divergence accept karo
(acceptable hai kyunki cache kabhi source of truth nahi hai) ya specific
hot, rarely-changing keys ko regions ke across asynchronously replicate
karo global consistency ke liye jahan woh sabse zyada matter karti hai।

**Aap optional persistence kaise add karoge taaki cache ek full restart
ke baad cold start karne ki jagah jaldi warm ho sake?**
Redis ke approach se seekho: periodic point-in-time snapshots (RDB-style)
ya ek append-only write log (AOF-style) jo disk pe asynchronously hot
path se off likhi jaati hai, phir startup pe replay hokar memory
pre-populate karti hai — yeh thoda disk I/O overhead aur implementation
complexity trade karta hai Step 7 mein describe kiye gaye cold-start
thundering-herd window ko dramatically reduce karne ke liye।

**Production mein cache health kaise monitor aur uspe act karoge?**
Per-node aur cluster-aggregate hit rate, eviction rate, memory pressure,
aur p99 latency track karo, per-key ya per-key-prefix breakdowns ke
saath hot-key skew (Step 6) catch karne ke liye isse pehle ki woh ek node
saturate kar de; eviction rate spikes pe alert karo (undersized cluster
ka signal) aur hit-rate drops pe separately (ek TTL, invalidation, ya
cold-start problem ka signal), kyunki yeh different root causes ki taraf
point karte hain।

**Aap isko simple key-value gets/sets se aage richer data structures
jaise sorted sets ya lists (Redis-style) support karne ke liye kaise
extend karoge?**
Same node/replication/hashing architecture rakho, lekin change karo ki
ek node per key kya store karta hai ek opaque blob se ek typed structure
mein apne khud ke operations ke saath (`ZADD`/`ZRANGE` ek sorted set ke
liye, `LPUSH`/`LRANGE` ek list ke liye) — distribution aur availability
story change nahi hoti, sirf per-node value representation aur API layer
se expose ki gayi operation surface change hoti hai।

**Ek client jiske paas ek rebalance ke baad stale ring topology
information hai, usse kaise handle karoge?**
Topology ko version karo (jaise Step 4 ke API mein) taaki ek node detect
kar sake ki ek request outdated view ke under route hui hai aur ya to
usse phir bhi serve kare agar woh still us key ko own karta hai, use
correct current owner ko forward kare, ya usse ek redirect ke saath
reject kare client ko topology refresh karne ko bolte hue — Redis
Cluster ke `MOVED`/`ASK` responses is pattern ka reference
implementation hain।

**Ek single large cache node use karne ki jagah ek distributed cluster
kyun na use karein?**
Ek single node ki ek hard capacity ceiling hoti hai (Step 2 ka 200 GB+
working set ek machine ki RAM mein affordably fit nahi hota) aur yeh ek
single point of failure hai — usse lose karna cache traffic ka 100% ek
saath database pe daal deta hai, jo exact thundering-herd scenario hai
jise rokne ke liye yeh poora design exist karta hai; distribute karna
capacity spread karta hai aur kisi bhi single node ki failure ka blast
radius uske keyspace ke slice tak bound kar deta hai।

**Traffic 5x badhne pe aap right replication factor aur cluster size
kaise decide karoge?**
Step 2 ka arithmetic naye QPS aur working-set numbers ke saath recompute
karo — replication factor primarily ek availability decision hai
(2 ek node loss per shard tolerate karta hai, 3 do tolerate karta hai)
raw scale se independent, jabki node count total memory needed ko
per-node usable capacity se divide karke scale karta hai; exercise yeh
show karna hai ki estimation process generalize karta hai, ek fixed
number memorize karna nahi।
