# Design a Collaborative Document Editor

## Problem Statement

"Design karo ek real-time collaborative document editor, jaise Google Docs.
Multiple users same document ko same time pe open kar sakein, simultaneously
type kar sakein, ek doosre ke changes ek second ke fraction ke andar appear hote
dekh sakein, aur live cursors dekh sakein jo dikhaein ki unke collaborators
kahan kaam kar rahe hain. Document kabhi bhi corrupted ya inconsistent state
mein nahi jaana chahiye, chahe do log exact same word ko exact same instant pe
edit kar rahe hon."

Yeh ek harder system design interview questions mein se ek hai kyunki core
difficulty traditional sense mein scale nahi hai (storage, QPS) balki
concurrency ke neeche correctness hai: many clients se edits ko ek coherent
document mein merge karna bina ek central lock ke jo "real-time" feel ko kill
kar de.

## Step 1: Requirements Clarify Karo

**Functional Requirements**

- Multiple users same document ko concurrently open aur edit kar sakte hain.
- Ek user ke edits sabhi doosre connected collaborators tak near real time mein
  propagate hote hain (sub-second).
- System live presence support karta hai: kaun currently document dekh raha
  hai, aur unka cursor/selection currently kahan hai.
- Users version history dekh sakte hain aur ek prior version pe revert kar
  sakte hain.
- Users offline edit kar sakte hain aur reconnect hone pe unke changes
  reconcile ho jaate hain.
- Basic document operations: text insert, text delete, formatting (bold/
  italic), aur (stretch) embedded objects jaise images ya comments.
- Access control: owner, editor, viewer permissions per document.

**Non-Functional Requirements**

- Low latency: ek keystroke collaborators ki screens pe well under 200ms mein
  appear honi chahiye normal conditions ke neeche.
- Strong eventual consistency: har replica (har open client, plus server ki
  stored copy) ko identical document content mein converge hona chahiye ek
  baar sabhi operations deliver ho jaayein, chahe edits kisi bhi order mein
  aayi hon.
- No lost updates: do simultaneous edits dono survive karne chahiye; system ko
  kabhi bhi ek user ke keystrokes ko doosre ke favor mein silently drop nahi
  karna chahiye.
- Availability over strict real-time ordering: ek user ke liye slow network
  doosron ko edit karte rehne se block nahi karna chahiye.
- Durability: ek baar edit acknowledge ho jaaye, wo lost nahi honi chahiye
  chahe server turant crash ho jaaye.
- Estimation ke liye scale target: ek large collaborative editing product jo
  enterprises ke andar aur consumers dwara use hota hai, e.g. hundreds of
  millions of documents, tens of millions of daily active editing sessions,
  jahan individual documents typically ek handful concurrent editors rakhte
  hain (kuch documents dozens tak spike kar sakte hain).

## Step 2: Back-of-Envelope Estimation

**Assumptions**

- 50 million daily active users (DAU) jo din mein kam se kam ek document open
  karte hain.
- Inme se, 10 million actually *edit* kar rahe hote hain (sirf view nahi) kisi
  given din pe.
- Ek average editing session 10 minutes chalta hai aur roughly 1
  keystroke/operation har 2 seconds mein produce karta hai active typing ke
  dauraan (log sochne ke liye pause karte hain, to har second ek keystroke
  nahi hota).
- Peak concurrency: maan lo daily editors ka 5% concurrently active hai peak
  pe, i.e. 500,000 concurrent editing sessions.

**Operation throughput**

- Per concurrent session: 1 operation / 2 sec = 0.5 ops/sec.
- Peak aggregate operation rate: 500,000 sessions x 0.5 ops/sec = 250,000
  operations/sec system-wide.
- Har operation tiny hoti hai (ek insert/delete of a few characters plus
  metadata: doc id, revision number, user id, timestamp) — roughly 100-200
  bytes serialized. 250K ops/sec x 150 bytes = ~37.5 MB/sec raw operation
  traffic peak pe. Yeh modern network aur message-broker infrastructure se
  easily handle ho jaata hai, lekin yeh batata hai ki system ko many small,
  frequent messages ke around banana hai, ek batch/request-response model ke
  around nahi.

**Fan-out (asli cost driver)**

- Expensive part operations accept karna nahi hai, yeh unhe *broadcast* karna
  hai. Agar average document ke 3 concurrent editors hain, to har operation ko
  2 doosre clients tak push karna padta hai: 250,000 ops/sec x 2 = 500,000
  outbound pushes/sec peak pe.
- Agar ek document mein outlier spike ho 50 concurrent viewers ka (e.g. ek
  all-hands doc), ek operation 49 clients tak fan out hota hai — yeh batata
  hai ki hume per-document fan-out logic chahiye jo steady-state assumptions
  se independently scale kare (dekho Step 6).

**Storage**

- Poora operation log store karna (sirf snapshots nahi) is design ka central
  hissa hai (dekho Step 6). Maan lo average document apni lifetime mein 5,000
  operations accumulate karta hai (edits, formatting changes) ~150 bytes each
  pe = 750 KB operation-log data per actively-edited document.
- Agar system mein, kaho, 500 million actively-edited documents hain: 500M x
  750 KB = 375 PB agar hamesha rakha jaaye, uncompressed, full granularity pe.
  Practice mein, operation logs periodically snapshots mein compact ho jaate
  hain (e.g. undo/version history ke liye last 30 days ki full-fidelity ops
  rakho, purani history ko coarser snapshots mein collapse kar do), jo isko
  ek order of magnitude ya usse zyada kam kar deta hai. Yeh estimation hi
  compaction ko ek real design decision banata hai, sirf ek nice-to-have nahi.

**Connections**

- 500,000 concurrent editing sessions, har ek ek persistent WebSocket
  connection hold karti hai. Ek single well-tuned server order of 50,000-
  100,000 idle-ish WebSocket connections hold kar sakta hai, to hume peak pe
  order of 5-10 dedicated WebSocket-gateway hosts chahiye, redundancy account
  karne se pehle — ek useful sanity check ki yeh utna hi ek connection-
  management problem hai jitna ek compute problem, wahi shape jo
  `09_chat_application.md` ke chat system mein hai.

**Document Session Service sizing**

- Har actively-edited document ko apna sequencing logic (OT transform ya CRDT
  merge) kahin resident chahiye. 10 million daily editing sessions ke saath
  jo, kaho, 4 million distinct actively-edited documents ke across spread hain
  kisi bhi given moment pe (many sessions ek document share karte hain), aur
  ek moderately-provisioned host jo in-memory sequencing state hold kar sake
  aur transform work kar sake roughly 5,000-10,000 lightly-active documents ke
  liye concurrently, iska matlab hai order of 400-800 Document Session Service
  hosts steady state pe — jo phir se yeh reinforce karta hai ki yeh tier
  primarily *concurrently-edited documents ki number* se scale karta hai, na
  ki total operation throughput se, kyunki per-operation transform cost tiny
  hai (microseconds) us memory/bookkeeping cost ke against jo bahut sare
  documents ka state ek saath khula rakhne mein lagti hai.
- Yeh ek useful number hai interview mein bolne ke liye: yeh ek small-to-medium
  fleet hai, ek hyperscale wali nahi, kyunki working set jise actually
  low-latency in-memory access chahiye (documents jo *abhi* edit ho rahe hain)
  total document corpus (hundreds of millions) ka ek chhota fraction hota hai
  kisi bhi instant pe.

## Step 3: High-Level Design

Core components:

- **Client**: rich text editor (e.g. ek browser-based editor) jo local edits
  optimistically apply karta hai (user apna khud ka keystroke turant dekhta
  hai, server confirmation se pehle) aur not-yet-acknowledged local operations
  ki ek queue maintain karta hai.
- **WebSocket Gateway layer**: stateless-ish servers jo per-client persistent
  connection hold karte hain, session authenticate karte hain, aur operations
  ko correct document ke session tak/se route karte hain.
- **Document Session Service (the "room")**: har actively-edited document ke
  liye, ek logical owner process/shard jo us document pe sabhi connected
  clients se operations receive karne, unhe order karne, transform/merge logic
  (OT ya CRDT, dekho Step 6) run karne, aur result ko wapas broadcast karne ke
  liye responsible hai. Yeh sequencing point hai jo concurrent edits ko
  everywhere same result mein converge karwata hai.
- **Operation Log Store**: ek append-only, durable log un sabhi operations ka
  jo kabhi bhi ek document pe apply hue — source of truth, "current text"
  snapshot nahi (dekho Step 6).
- **Snapshot/Materializer**: periodically operation log ko fold karta hai ek
  materialized current-state snapshot mein taaki ek document open karne ke
  liye uski poori history operation #1 se replay karne ki zaroorat na pade.
- **Presence Service**: ek ephemeral, in-memory pub/sub layer cursor
  positions aur "kaun view kar raha hai" ke liye — deliberately durable
  operation log se separate (dekho Step 6).
- **Metadata/Access-control store**: document ownership, sharing permissions,
  folder structure — ek fairly standard relational store, editing hot path se
  separate.

Ek single keystroke ke liye data flow:

1. User ek character type karta hai. Client usko locally turant apply kar deta
   hai (optimistic UI) aur ek operation `{docId, baseRevision, op: insert("x",
   pos=42), clientOpId}` apni WebSocket connection pe bhejta hai.
2. Gateway operation ko us Document Session Service instance tak route karta
   hai jo currently us document ko "own" kar rahi hai.
3. Session service operation ko next server revision number assign karta hai,
   usko transform karta hai (agar OT use ho raha ho) un operations ke against
   jo client ke `baseRevision` ke baad apply hui thi lekin jo client ne dekhi
   nahi thi, usko durable operation log mein append karta hai, aur transformed
   operation ko document ke sabhi doosre connected clients tak broadcast karta
   hai.
4. Doosre clients operation receive karke apni local copy pe apply karte hain;
   originating client ko ek acknowledgment milta hai aur wo apna optimistic
   local state authoritative transformed version ke saath reconcile karta hai
   agar wo differ karte hain.

```text
                        +--------------------+
                        |   Metadata / ACL    |
                        |  (Postgres/MySQL)   |
                        +---------+-----------+
                                  |
   Client A                      |                     Client B
 (WebSocket)                     |                    (WebSocket)
     |                            |                          |
     v                            v                          v
+---------+                +--------------+            +---------+
| Gateway |<-------------->| Load Balancer|<---------->| Gateway |
+----+----+                +--------------+            +----+----+
     |                                                       |
     |           routes by docId --> owning shard            |
     v                                                       v
        +-----------------------------------------------+
        |          Document Session Service              |
        |   (per-doc sequencing, OT/CRDT merge logic)     |
        +----------------+---------------+----------------+
                          |               |
                          v               v
              +----------------+   +----------------+
              | Operation Log   |   | Presence Pub/Sub|
              | (append-only,   |   | (in-memory,      |
              |  durable, e.g.  |   |  ephemeral)       |
              |  Kafka/DB log)  |   +----------------+
              +--------+--------+
                       |
                       v
              +----------------+
              | Snapshot Store  |
              | (materialized    |
              |  current text)   |
              +----------------+
```

## Step 4: API Design

**Ek editing session establish karna (WebSocket handshake)**
```
WS CONNECT /docs/{docId}/edit
  -> Auth token in connection headers
  <- { type: "init", revision: 4032, snapshot: "<current document content>", 
       activeUsers: [{userId, cursorPos, color}] }
```

**Ek operation submit karna (client -> server, open socket ke upar)**
```
SEND { type: "op", docId, baseRevision: 4032, clientOpId: "uuid-abc",
       op: { type: "insert", pos: 128, text: "hello" } }
```

**Ek broadcast operation receive karna (server -> sabhi connected clients)**
```
PUSH { type: "op", docId, revision: 4033, appliedBy: "userA",
       op: { type: "insert", pos: 128, text: "hello" } }
```

**Presence update (client -> server, high frequency, ack ki zaroorat nahi)**
```
SEND { type: "presence", docId, cursorPos: 130, selectionRange: [128,133] }
PUSH { type: "presence", docId, userId: "userB", cursorPos: 130, selectionRange: [128,133] }
```

**Version history fetch karna**
```
GET /docs/{docId}/history?limit=50&before=revision_4000
<- { versions: [{ revision, timestamp, author, summary }] }
```

**Ek prior version pe revert karna**
```
POST /docs/{docId}/revert { targetRevision: 3800 }
<- { newRevision: 4034 }   # ek naye forward operation ki tarah implement hota hai, ek destructive rewrite nahi
```

## Step 5: Data Model

**Operation log** (source of truth — append-only, high write volume, per
document strict ordering chahiye): ek wide-column ya log-oriented store (e.g.
Cassandra keyed by docId ek clustering column of revision number ke saath, ya
ek partitioned Kafka topic per document-shard backed by ek compacted log) ek
good fit hai kyunki writes append-only hain, reads almost hamesha "revision N
ke baad ka sabkuch do," hoti hain, aur cross-document joins ki zaroorat nahi
hai.

```
operation_log (partition key: docId, clustering key: revision)
  docId          string
  revision       int64          -- per document monotonically increasing
  op_type        enum(insert, delete, format, ...)
  payload        json           -- position, text, formatting attrs
  author_id      string
  client_op_id   string         -- idempotency / retry pe dedup ke liye
  applied_at     timestamp
```

**Snapshot store** (materialized current content, fast document load ke liye):
ek document store (e.g. ek blob store ya ek document-oriented DB) keyed by
docId, latest folded content aur wo revision number jise woh represent karta
hai store karta hai.

```
snapshots
  docId              string (PK)
  revision           int64
  content            blob/text  -- current materialized document body
  last_compacted_at  timestamp
```

**Metadata / ACL** (standard relational needs: joins, permission checks,
folder hierarchies): ek relational database (Postgres/MySQL) yahan achhe se
fit hota hai kyunki yeh classic structured, transactional, edits ke against
low-volume data hai.

```
documents(id PK, title, owner_id, created_at, folder_id)
permissions(document_id FK, user_id FK, role enum(owner, editor, viewer))
```

**Presence** (ephemeral, kabhi bhi usi tarah durably persist nahi hoti): ek
in-memory keyed store (e.g. Redis short TTLs ke saath, ya ek pure in-process
pub/sub Document Session Service ke andar) keyed by docId -> {userId:
{cursorPos, color, lastSeen}}, disconnect pe clear ho jaata hai. Kisi durable
database mein koi table nahi — dekho Step 6 ki iske kyun.

## Step 6: Deep Dive

### Concurrent edits ko merge karna: Operational Transformation vs CRDTs

Yeh poore system ka central problem hai: do users, dono document ki revision
100 se start karte hue, dono ek operation submit karte hain ek doosre ko
dekhne se pehle. Naively dono ko jis bhi order mein wo server pe arrive karein
apply karne se different results milte hain different clients pe (ya outright
positions corrupt ho jaati hain — e.g. "position 42 pe insert karo" ka matlab
kuch aur ho jaata hai jab koi aur pehle hi position 42 se pehle 5 characters
insert kar chuka ho).

**Operational Transformation (OT)**: har operation apni revision carry karti
hai jispe wo based thi. Jab server (ya ek peer) ek aisi operation receive
karta hai jo current revision se ek purani revision pe based hai, wo us
operation ko *transform* karta hai un sabhi operations ke against jo beech
mein apply hui thi, uske parameters adjust karte hue (e.g. ek insert position
ko forward shift karte hue kisi intervening insert ki length se jo uske pehle
land hui thi) taaki abhi usko apply karna wahi logical effect produce kare
jaisa hota agar wo turant, order mein apply hui hoti. Isko ek central
sequencing authority chahiye — hamare design mein, Document Session Service —
kyunki transform logic ek canonical order of operations establish karne pe
depend karta hai jiske against transform kiya jaaye. OT ko notoriously subtly
galat karna aasan hai: transform functions ko strict mathematical properties
(commonly TP1/TP2 conditions ki tarah discuss hoti hain) satisfy karna hota hai
har pair of operation types ke across (insert-insert, insert-delete,
delete-delete, formatting-vs-text-edit), aur ek single missed edge case
silently documents ko corrupt kar sakta hai un tareeqon se jo sirf many
compounding edits ke baad dikhte hain. Yehi wajah hai ki OT ko scratch se
correctly banana practice mein ek multi-year endeavor hai, kuch casually
reimplement karne wali cheez nahi.

**CRDTs (Conflict-free Replicated Data Types)**: operations ko ek doosre ke
against transform karne ke bajaye, document khud ek data structure ki tarah
represent hota hai jo specifically isliye design hui hai ki concurrent updates
commute karein — unhe kisi bhi order mein, kisi bhi replica pe apply karna,
same result mein converge hota hai bina kisi central transform step ke. Text
ke liye ek common approach yeh hai ki har character ko ek unique, stable
identifier diya jaaye causal history se derived (e.g. ek fractional position
ya identifiers ka ek tree) instead of ek raw numeric index ke, taaki ek
"character X ke baad insert karo" operation meaningful rahe chahe concurrently
kuch bhi ho chuka ho, bina rewrite hue. Yeh CRDTs ko naturally decentralized
banata hai — koi bhi do replicas (do offline clients bhi shaamil) directly
merge kar sakte hain ek doosre ke saath, correctness ke liye koi server nahi
chahiye — yehi exact wajah hai ki wo offline-first aur peer-to-peer
collaborative tools ke liye popular hain. Cost memory aur metadata overhead
hai: har character (ya object) ko ek durable unique identifier chahiye aur
often deleted content ke tombstones rakhe jaate hain truly remove karne ke
bajaye, to CRDT-backed documents equivalent OT operation log se meaningfully
zyada overhead per character carry kar sakte hain, especially long-lived,
heavily-edited documents ke liye.

**Real trade-off, plainly stated**: OT per-operation overhead ko chhota
rakhta hai aur ek design ke liye well suited hai jo already ek natural central
server rakhta hai (jo yeh design broadcast aur durability ke liye rakhta hi
hai), lekin correctly implement karna bahut hard hai. CRDTs correctness-wise
reason karne mein easier hain aur shine karte hain jab true peer-to-peer ya
robust offline support ek first-class requirement ho, higher steady-state
memory/storage overhead ke cost pe. Conceptually, Google Docs ki collaborative
editing historically OT-based describe ki gayi hai, consistent hai ek central
authoritative server rakhne ke saath already; many newer collaborative editors
ne CRDT-based approaches adopt kiye hain (e.g. CRDT text structures ke around
built libraries) particularly jahan offline-first ya local-first behavior ek
priority hai. Interview mein dono choices defensible hain jab tak trade-off
correctly articulate ho.

**Ek worked OT example, transform ko concrete banane ke liye.** Maan lo
document `"the cat sat"` hai revision 100 pe. Do users concurrently act karte
hain, dono revision 100 pe based:

- Alice `"black "` insert karti hai position 4 pe, intending `"the black cat
  sat"` — operation `insert(pos=4, "black ")`.
- Bob word `"cat"` delete karta hai (positions 4-7), intending `"the  sat"` —
  operation `delete(pos=4, len=3)`.

Dono server pe revision 100 pe based aate hain. Server ek arrival order pick
karta hai — maan lo Alice ki operation pehle sequence hoti hai, revision 101
ban jaati hai, aur as-is broadcast ho jaati hai. Ab Bob ki operation ko Alice
ki operation ke against transform karna padega usse apply hone se pehle: Bob
ka original `delete(pos=4, len=3)` tab likha gaya tha jab position 4 ka matlab
"cat" mein "c" hota tha, lekin Alice ke insert ke baad, position 4 ab "black "
ka start hai — "cat" ka "c" position 10 pe shift ho chuka hai. Transform
function Bob ki delete position ko Alice ki insertion ki length (6 characters)
se forward shift karta hai jab bhi insertion delete ki position pe ya usse
pehle hui ho, ek transformed operation `delete(pos=10, len=3)` produce karte
hue, jo correctly "cat" ko `"the black cat sat"` se delete karta hai `"the
black  sat"` produce karne ke liye — logically correct merged result, jo dono
users ki intention ke match karta hai. Agar transform ne naively Bob ki
untransformed `delete(pos=4, len=3)` ko Alice ke insert ke baad apply kiya
hota, to yeh "blac" delete kar deta — ek corrupted, unintended result. Yeh
single example bhi (insert, delete) transform cases mein se sirf ek hai; ek
real implementation ko har operation type ke pairing ke liye correct,
symmetric transforms chahiye, jo OT ki implementation complexity ka source
hai.

### Correctness test karna: convergence aur fuzzing

Kyunki ek subtle OT transform bug (ya ek CRDT merge-function bug) ek document
ko silently corrupt kar sakta hai bina koi visible error throw kiye — document
bas slowly diverge karta hai us se jo usko "hona chahiye" tha — is system ko
typical CRUD correctness testing se ek different testing strategy chahiye.
Standard approach hai **randomized simulation ke through convergence
testing**: bade number mein random concurrent operation sequences generate
karo ek simulated multi-client setup ke against (network delay, arrival order,
aur concurrency level vary karte hue), unhe transform/merge logic ke through
apply karo har possible delivery order mein, aur assert karo ki sabhi replicas
byte-identical final document state mein converge hoti hain chahe order kuch
bhi ho — ek property jo kabhi kabhi directly formal transform properties ke
against check ki jaati hai (informally, ki do concurrent operations ko ek
doosre ke against transform karna aur unhe either order mein apply karna same
result deta hai). Is tarah ka property-based fuzzing continuously CI mein run
hota hai kisi bhi serious OT ya CRDT implementation ke liye, precisely kyunki
hand-written unit tests specific scenarios ke liye (jaise upar wale Alice/Bob
example) sirf un cases ko cover karte hain jo kisi ne likhne ki socha, jabki
random fuzzing un edge cases ko surface karta hai jinke baare mein kisi ne
socha hi nahi — three-way concurrent edits, formatting operations ke saath
interleaved edits, ek slow reconnect ke baad unusual orders mein aane wali
operations. Interview mein, is testing strategy ko specifically naam lena
(sirf "hum tests likhenge" nahi) ek signal hai ki tumne actually is baat se
grapple kiya hai ki OT/CRDT correctness verify karna kitna hard hai.

### Real-time propagation aur connection routing

Har edit ko ek second ke fraction ke andar har doosre currently-connected
collaborator tak pahunchna chahiye. Yeh wahi identical "yeh user kis gateway
server se connected hai" problem hai jo `09_chat_application.md` mein discuss
hui hai: ek client ek specific gateway instance se ek persistent WebSocket
hold karta hai, aur Document Session Service pe aayi ek operation ko wapas un
*saare* gateway instances ke through route karna padta hai jo us document ke
doosre collaborators ke connections hold karte hain — sirf locally broadcast
nahi karna, kyunki ek horizontally scaled gateway layer ka matlab hai ki un
collaborators ke sockets poori tarah alag machines pe terminate ho sakte hain.
Standard solution wahi hai: Document Session Service outbound operation ko ek
pub/sub channel pe publish karti hai docId se keyed, aur har gateway instance
un documents ke channels ko subscribe karta hai jinke liye uske paas currently
connected clients hain, receipt pe apne local sockets pe push karte hue. Chat
ke against additional wrinkle yeh hai ki document collaborators ek much
smaller, tighter-knit group hote hain (typically single digits) ek chat room
ke against, lekin latency bar zyada strict hai — ek laggy chat message
tolerable hai, ek laggy keystroke "live" editing ka illusion tod deta hai — to
yeh path tail latency ke liye hard optimize hota hai, often Document Session
Service aur uske hot documents ka state memory mein colocate karte hue instead
of har keystroke pe database round-trip karne ke.

### Operation log source of truth ki tarah, sirf current-state snapshots nahi

Ek naive design sirf "current text" store karta hai aur har edit pe usko
overwrite kar deta hai. Yeh design iske bajaye append-only operation log ko
authoritative treat karta hai, materialized snapshot ko ek derived,
rebuildable cache ki tarah — wahi event-sourcing pattern jo
`10_message_queues_and_streaming.md` mein discuss hua hai, business events ki
jagah document state pe applied. Yeh choice teen tareeqon se apna cost recover
karta hai jo ek snapshot-only design easily nahi de sakta:

- **Version history aur undo/redo free mein mil jaate hain.** "Yeh document ek
  ghante pehle kaisa dikhta tha" bas "us timestamp pe wali operation tak log
  replay karo" hota hai. Undo hai "is user ki last applied operation ke liye
  ek inverse operation generate karo," ek separate undo-stack infrastructure
  ki zaroorat ke bina.
- **Auditability**: kisne kya change kiya, aur kab, inherently preserve ho
  jaata hai — useful hai dono user-facing "edit history dekho" features ke
  liye aur internal abuse/compliance investigation ke liye.
- **Reconciliation aur recovery**: agar ek Document Session Service instance
  mid-broadcast crash ho jaaye, operation log durable checkpoint hai recover
  karne ke liye — last durably-written revision se replay karo, kuch bhi lost
  nahi hota, jabki ek "current text" overwrite model ke paas ek in-flight edit
  recover karne ka koi tarika nahi hota jo durably write hone se pehle lost ho
  gayi thi.

Trade-off Step 2 mein discuss hui storage growth hai, managed via periodic
compaction of old operations coarser snapshots mein ek baar fine-grained
history valuable na rahe (e.g. 30 days se purani kisi bhi cheez ko daily
snapshots mein collapse kar do, raw log sirf recent history ke liye rakho).

### Presence design se ephemeral hai

Live cursors aur "kaun currently view kar raha hai" information usi tarah
broadcast hoti hai jaise document operations, lekin deliberately durable
operation log ya kisi bhi persistent database mein *nahi* likhi jaati.
Reasoning: presence information ki poori value instantaneous hai — 5 seconds
purana cursor position, ek ghante purana to door ki baat, meaningless ho
jaata hai ek baar user ne apna cursor phir move kar diya ho ya disconnect ho
gaya ho, aur yeh actual content se kahin zyada frequently change hoti hai
(mouse-move-driven cursor updates keystrokes se ek order of magnitude zyada
frequent ho sakte hain). Isko durably persist karne ka matlab hoga storage aur
write-amplification cost pay karna ek aisi data ke liye jiski shelf life
seconds mein measure hoti hai, aur usko constantly clean up bhi karna padta.
To presence purely fast, in-memory, TTL-based storage mein rehti hai (Redis
ya Document Session Service ke andar in-process state), same WebSocket
transport pe broadcast hoti hai jaise content operations ek unified client
protocol ke liye, aur simply us in-memory store se drop ho jaati hai
disconnect pe (ya ek short heartbeat timeout ke baad ungraceful disconnects
handle karne ke liye) — koi cleanup job nahi, koi durable record nahi.

### Offline editing aur reconciliation

Ek client jo offline ho jaata hai (network drop, laptop close) local edits
accept karte rehta hai aur optimistically apply karte hue, corresponding
operations ko locally queue karte hue bhejne ke bajaye. Jab wo reconnect
karta hai, uske paas ek batch of local operations hoti hai ek purane
`baseRevision` pe based, aur server document bahut likely already many
doosre operations se aage badh chuka hota hai doosre collaborators se us
duraan mein. Yeh exactly wahi scenario hai jo OT-vs-CRDT choice ko practice
mein sabse zyada matter karta hai, sirf theory mein nahi:

- **OT** ke neeche, reconnecting client ki queued operations mein se har ek
  ko, order mein, us poori sequence of operations ke against transform karna
  padta hai jo server pe uske `baseRevision` ke baad se hui hain — wahi
  transform logic jo real-time concurrent edits ke liye use hoti hai, bas ek
  bade backlog pe ek saath applied. Yeh transform karne ke liye zyada
  operations hai, lekin yeh same code path hai, jo OT ke *mental model* ki
  simplicity ke favor mein ek point hai chahe transform functions khud
  implement karna hard ho.
- **CRDTs** ke neeche, reconnecting client simply apna local CRDT state
  server ke current CRDT state ke saath merge kar deta hai — wahi merge
  operation jo kisi bhi do divergent replicas ke liye use hoti hai, chahe wo
  200 milliseconds ke liye diverge hue ho (normal concurrent editing) ya 2
  ghante ke liye (extended offline editing). Koi special-cased "catch-up"
  logic nahi hai; offline reconciliation ordinary real-time merging se ek
  distinct code path nahi hai, jo precisely wajah hai ki CRDTs often un
  products ke liye favor kiye jaate hain jahan offline support ek first-class,
  heavily-used requirement ho, ek edge case nahi.

Kisi bhi tarah, client ka optimistic local view authoritative merged result
ke against reconcile hona hi chahiye ek baar round-trip complete ho jaaye, aur
UI ko us (hopefully rare, aur ideally invisible) case ko handle karna padta
hai jahan locally-displayed cursor position ya selection thoda shift ho jaaye
merge ke result mein.

## Step 7: Bottlenecks & Trade-offs

- **Document Session Service ek natural single point of sequencing hai per
  document**, jo exactly wo cheez hai jo OT ko tractable banati hai, lekin
  iska matlab yeh bhi hai ki ek single hot document (ek all-hands doc jo 50
  logon dwara ek saath edit ho raha ho) load ko ek logical shard pe
  concentrate kar deta hai. Mitigate karo yeh ensure karke ki sequencing
  service lightweight ho (pure in-memory ordering aur transform, per operation
  heavy I/O nahi), aur broadcast fan-out ek separate pub/sub layer se handle
  ho, sequencer khud se nahi.
- **Fan-out cost concurrent viewers per document ke saath grow karta hai, na
  ki total system scale ke saath**, jo is question bank ke zyadatar systems se
  ek different scaling axis hai — ek system jo comfortably 10 million total
  documents handle kar leta hai, phir bhi ek document pe 500 simultaneous
  editors pe choke kar sakta hai agar fan-out ek efficient pub/sub broadcast
  se handle na ho, connections pe synchronously loop karne se.
- **Operation log storage growth compaction ke bina unbounded hai** —
  trade-off full history hamesha ke liye rakhne (expensive, lekin arbitrarily
  fine-grained version history enable karta hai) versus aggressively
  compacting karne (cheaper, lekin old version history granularity coarsen
  karta hai) ke beech hai. Zyadatar products age aur document activity level
  ke basis pe compact karte hain.
- **OT correctness bugs ek long-tail risk hain**: ek subtle transform bug
  mahino tak manifest nahi ho sakta aur phir documents ko aise corrupt kar
  sakta hai jo detect karna hard ho (document "theek dikhta hai" lekin
  silently clients ke beech diverge ho chuka hota hai) — yeh interviews mein
  ek strong argument hai ya to ek battle-tested OT/CRDT library use karne ke
  liye instead of ek hand-roll karne ke, ya specifically CRDTs ki taraf lean
  karne ke liye is class of bug ko sidestep karne ke liye, isko CRDT ke apne
  overhead trade-offs se trade karte hue.
- **Consistency vs latency**: design clients ko edits optimistically apply
  karne deta hai server acknowledgment se pehle, perceived low latency ko
  strict consistency ke upar favor karte hue har instant pe — yeh ek
  deliberate trade-off hai (eventual consistency reconciliation ke saath)
  instead of alternative ke, jo hai user ko unka apna keystroke dikhane se
  pehle ek round-trip ka wait karna, jo unacceptably laggy feel karta.

## Follow-up Questions Jo Ek Interviewer Puuch Sakta Hai

**Rich formatting (bold, italic, embedded images) kaise handle karoge, sirf
plain text insert/delete nahi?** Operation types ko text insert/delete se
aage extend karo formatting-range operations aur embedded-object operations
include karne ke liye, aur transform functions (OT ke liye) ya CRDT ka data
model (e.g. ek flat sequence ke bajaye ek tree structure) extend karo aise
interactions cover karne ke liye jaise "koi aisa text delete kar de jo doosra
user abhi bhi bold kar chuka ho." Yeh operation-type pairs ki number
substantially badha deta hai jise transform logic ko correctly handle karna
padta hai, jo part hai kyun real editors ke OT/CRDT implementations bade,
mature codebases hain.

**Document Session Service ko khud kaise scale karoge agar ek document ko
unusually large number of concurrent editors mil jaayein?** Kyunki ordering
correctness ke liye per document centralized rehni chahiye, ek single
document ki sequencing ko true horizontally scale karna straightforward nahi
hai; practical mitigation hai us sequencing service ko extremely cheap banana
per operation (pure in-memory, minimal serialization) aur saara expensive
kaam (durable log writes, broadcast fan-out) ko ordering decision ke
downstream asynchronous paths mein push karna, taaki sequencer ka kaam itna
small rahe ki wo bahut high per-document operation rates handle kar sake.

**Is model ke upar comments/suggestions (Suggesting mode) kaise implement
karoge?** Ek comment ya suggested edit ko apni khud ki operation type ki
tarah model karo jo document ke ek range ko reference kare (usi stable
position/identifier scheme se jo text ke liye use hota hai) bina underlying
content ko mutate kiye jab tak accept na ho jaaye — yeh existing operation
log aur real-time broadcast machinery ko reuse karta hai instead of ek
parallel system chahiye ke.

**Agar Document Session Service mid-session crash ho jaaye to kya hota hai?**
Kyunki operation log durably likha jaata hai broadcast hone se pehle (ya
design otherwise guarantee karta hai ki durability acknowledgment se pehle
aati hai), ek naya instance document ko takeover kar sakta hai log se last
durably-committed revision read karke aur in-memory state ko wahan se rebuild
karke; clients jinke paas unacknowledged operations in flight thi wo simply
unhe resend karte hain, aur resend safely idempotent hai `client_op_id` ki
wajah se jo har operation pe hota hai.

**Bahut large documents (hundreds of pages) support kaise karoge bina client
ko poora operation log ya content memory mein load/hold karwaye?**
Snapshot/materializer pe lean karo: clients latest snapshot plus sirf us
snapshot ki revision ke baad ki operations load karte hain, aur extremely
large documents ke liye, content sections ke viewport-based lazy loading pe
consider karo, pagination ke analogous, operation stream ko khud lightweight
rakhte hue kyunki individual operations chhoti rehti hain chahe total document
size kuch bhi ho.

**Malicious ya buggy clients ko document ko sabke liye corrupt karne se kaise
rokoge (e.g. malformed operations bhejna)?** Har incoming operation ko
server-side validate aur sanitize karo authoritative log mein allow hone se
pehle — kabhi bhi client-supplied transformed state pe trust mat karo, sirf
client-supplied intents pe (is text ko is position pe insert karo is revision
ke relative) jise server khud sequence aur apply karta hai, taaki ek bura
client worst case mein sirf apni khud ki operations reject karwa sake, shared
document state corrupt nahi kar sake.
