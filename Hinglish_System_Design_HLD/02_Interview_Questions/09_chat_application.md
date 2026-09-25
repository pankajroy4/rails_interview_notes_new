# Design a Chat Application

## Problem Statement

"Design a chat application like WhatsApp ya Facebook Messenger. Users ko
ek dusre ko near real time mein 1:1 messages aur group messages send kar
paana chahiye. Agar recipient offline hai toh messages lose nahi hone chahiye,
aur users ko dekhna chahiye ki ek message kab delivered hua aur kab read hua.
Assume karo hundreds of millions of users, jinme se zyadatar mobile devices
pe hain unreliable networks ke saath."

## Step 1: Clarify Requirements

### Functional Requirements

- Users near real time mein 1:1 text messages send aur receive kar sakte hain.
- Users groups create kar sakte hain (bounded size, e.g. up to a few hundred members) aur
  poore group ko message send kar sakte hain.
- Messages persist hote hain taaki ek user full conversation history fetch kar sake,
  including woh messages jo unke offline hote hue send hue.
- Sender har message ka delivery state dekh sakta hai: **sent** (client se nikal gaya),
  **delivered** (recipient ke device tak pahuncha), **read** (recipient ne
  open kiya).
- Media attachments ke liye support (images, short video, voice notes) — deep dive ke
  scope se bahar hai yahan "blob ko object storage mein store karo aur
  message mein ek pointer/URL bhejo" se zyada, jo same pattern hai
  `../01_Concepts/12_storage_systems.md` ka.
- Users basic presence dekh sakte hain (online / last seen), bhale hi yeh explicitly
  ek soft, best-effort feature hai, ek strict guarantee nahi.

### Non-Functional Requirements

- **Low latency**: ek online user dwara send kiya gaya message doosre online user tak
  well under a second mein pahunchna chahiye — yeh woh feature hai jo users sabse zyada notice karte hain.
- **Durability**: ek message kabhi silently drop nahi hona chahiye ek baar client ko "sent"
  bata diya gaya toh. Messages lose karna chat product ke liye single least acceptable
  failure mode hai.
- **At-least-once delivery** client-side deduplication ke saath acceptable hai —
  ek unreliable network ke across exactly-once delivery achievable nahi hai
  bina at-least-once ke upar ek idempotency mechanism ke (dekho
  `../01_Concepts/09_distributed_systems_core.md` idempotency pe).
- **Ordering**: ek single 1:1 ya group conversation ke andar messages sabhi
  participants ko consistent order mein dikhne chahiye — unrelated conversations ke across
  global ordering ki zaroorat nahi.
- **High availability strict consistency ke upar**: user ke liye behtar hai ki thoda stale
  delivery status dikhe uske muqable poora send path unavailable ho jaaye — yeh design ko
  message delivery infrastructure ke liye ek AP-leaning system ki taraf le jaata hai
  (dekho `../01_Concepts/08_cap_theorem_and_consistency.md`),
  jabki message content khud, ek baar likha jaane ke baad, durable hona chahiye.
- **Massive concurrency**: hundreds of millions of users, jinme se tens of millions
  simultaneously online hote hain, har ek ka ek long-lived connection hold kiya hua.
- **Read/write pattern**: writes (sends) aur near-immediate reads (recipient ka message
  receive karna) roughly 1:1 per message hain — yeh ek feed ya search system
  se different hai; yahan dominant cost connection fan-out aur routing hai,
  skewed read amplification nahi.

## Step 2: Back-of-Envelope Estimation

**Assumptions** (explicitly stated, WhatsApp-scale order of magnitude):

- 500 million daily active users (DAU).
- Average of 40 messages sent per user per day (1:1 aur group ka mix).
- 10% of DAU peak pe concurrently connected hai — 50 million concurrent
  WebSocket connections.
- Average message payload (text + metadata: sender ID, conversation ID,
  timestamp, message ID) wire pe aur disk pe ~200 bytes hai.
- Peak traffic roughly daily average ka 3x chalta hai (evening peak).

**Message volume and QPS**

```
Total messages/day = 500,000,000 users x 40 messages/user = 20,000,000,000 (20B) messages/day

Average QPS = 20,000,000,000 / 86,400 seconds ≈ 231,500 messages/sec

Peak QPS ≈ 231,500 x 3 ≈ 695,000 messages/sec
```

Yeh *messages sent* ka number hai. Actual *deliveries* isse zyada hain group
fan-out ki wajah se (50 members wale group ko ek message 1 send hai lekin 50 deliveries
hain) — dekho Step 6 mein fan-out discussion.

**Storage**

```
Per-message storage (payload + indexing overhead) ≈ 200 bytes

Daily storage = 20,000,000,000 x 200 bytes = 4,000,000,000,000 bytes = 4 TB/day

Yearly storage (raw) = 4 TB x 365 ≈ 1.46 PB/year

3x replication for durability ke saath ≈ 4.4 PB/year
```

Yeh ek horizontally partitioned store (dekho Step 6 mein partitioning) ke liye
large lekin bahut manageable number hai — text messaging store karna per message
cheap hai; real product mein real cost driver media attachments hain (images,
video, voice notes), jo per item orders of magnitude bade hote hain aur
object storage mein rehte hain, message database mein nahi.

**Connection infrastructure**

```
50,000,000 concurrent connections

Agar ek connection-server process ~50,000 open WebSocket connections hold kar sake
(ek tuned server ke liye realistic jiske paas enough file descriptors aur memory ho —
har idle WebSocket roughly tens of KB kernel + application memory cost karta hai):

Connection servers needed = 50,000,000 / 50,000 = 1,000 servers
```

**Bandwidth**

```
Average: 231,500 msgs/sec x 200 bytes x 2 (ek write in, ek push out per
1:1 message) ≈ 92.6 MB/sec ≈ 741 Mbps average

Peak: roughly 3x ≈ 2.2 Gbps

Yeh media traffic exclude karta hai, jo real product mein text traffic ko
orders of magnitude se dwarf karta hai aur CDN ke through serve hota hai, messaging
pipeline se nahi.
```

## Step 3: High-Level Design

Core split **stateful connection infrastructure** (kaun online hai, aur woh kaunse
server se attached hai) aur **stateless message processing** (validate, persist, route)
ke beech hai. Yehi separation hai jo poore system ko horizontally scalable
banaata hai — connection servers ko message-processing capacity se independently
add ya remove kiya ja sakta hai.

```text
                          ┌────────────────────┐
                          │   Mobile / Web      │
                          │   Client            │
                          └─────────┬───────────┘
                                    │ persistent WebSocket
                                    ▼
                     ┌───────────────────────────────┐
                     │   Connection Gateway Cluster    │
                     │  (thousands of stateful nodes,  │
                     │   each holds ~50k connections)  │
                     └───────┬───────────────┬─────────┘
                             │               │
              register/lookup│               │ publish incoming message
                             ▼               ▼
                  ┌─────────────────┐   ┌────────────────────┐
                  │ Presence /       │   │  Message Service    │
                  │ Session Registry │   │ (stateless workers) │
                  │ (user_id ->      │   └─────────┬────────────┘
                  │  gateway node)   │             │
                  └─────────────────┘              │ persist + assign seq #
                                                     ▼
                                          ┌─────────────────────┐
                                          │  Message Store        │
                                          │  (partitioned by       │
                                          │   conversation_id)     │
                                          └───────────┬─────────┘
                                                       │ publish for fan-out
                                                       ▼
                                          ┌─────────────────────┐
                                          │  Message Queue /       │
                                          │  Delivery Router       │
                                          └───────┬─────────┬─────┘
                                                   │         │
                                    recipient online│         │recipient offline
                                                   ▼         ▼
                                  ┌────────────────────┐ ┌──────────────────┐
                                  │ Lookup recipient's   │ │ Push Notification │
                                  │ gateway node, push   │ │ Service (APNs/FCM)│
                                  │ over open connection │ └──────────────────┘
                                  └────────────────────┘
```

**Ek 1:1 message ke liye flow:**

1. Sender ka client message ko apni already-open WebSocket pe apne
   connection gateway node ko push karta hai.
2. Gateway isse stateless message service ko forward karta hai, jo ek
   message ID aur ek per-conversation sequence number assign karta hai, phir usko
   durably message store mein likhta hai.
3. Message service recipient ke current gateway ko lookup karta hai (presence/session
   registry ke through). Agar recipient online hai, message us specific gateway node
   ko route hota hai aur unke open connection pe push hota hai. Agar offline hai, yeh
   store-and-forward ke liye queue hota hai aur ek mobile push notification trigger hoti hai.
4. Sender ko ek ack milta hai jab message durably persist ho jaata hai (yehi
   UI ko "sent" mein flip karta hai — ek single checkmark).

## Step 4: API Design

Yahan zyadatar "API" REST ki jagah WebSocket message frames hain, kyunki
core interaction bidirectional aur low-latency hai. Ek thin REST layer
phir bhi exist karti hai connection setup, history fetch, aur kuch bhi jo push
karne ki zaroorat nahi hoti uske liye.

**1. Ek session establish karo (REST, per app start / reconnect ek baar)**

```
POST /v1/connect
Request:  { "user_id": "u123", "device_id": "d456", "auth_token": "..." }
Response: { "gateway_url": "wss://gw-17.chat.example.com/socket", "session_token": "..." }
```
Client ko ek specific gateway node handover ki jaati hai connect karne ke liye (often
locality/load ke liye load balancer se chosen hota hai, dekho Step 6) aur woh
usse ek WebSocket khoolta hai.

**2. Ek message send karo (WebSocket frame, client -> server)**

```json
{
  "type": "MESSAGE_SEND",
  "client_msg_id": "c-9f2e...",
  "conversation_id": "conv_789",
  "recipient_ids": ["u456"],
  "body": { "text": "Hey, running 10 mins late" },
  "sent_at_client": 1757740000123
}
```
`client_msg_id` client-side pe generate hota hai aur yeh deduplication key hai (dekho
Step 6) — server ordering ke liye client timestamps kabhi trust nahi karta.

**3. Server ack (WebSocket frame, server -> sender)**

```json
{
  "type": "MESSAGE_ACK",
  "client_msg_id": "c-9f2e...",
  "server_msg_id": "m-01H8X...",
  "conversation_id": "conv_789",
  "seq_no": 4821,
  "status": "SENT"
}
```

**4. Incoming message push (WebSocket frame, server -> recipient)**

```json
{
  "type": "MESSAGE_PUSH",
  "server_msg_id": "m-01H8X...",
  "conversation_id": "conv_789",
  "sender_id": "u123",
  "seq_no": 4821,
  "body": { "text": "Hey, running 10 mins late" },
  "server_sent_at": 1757740000456
}
```

**5. Delivery / read receipt (WebSocket frame, recipient -> server)**

```json
{
  "type": "RECEIPT",
  "server_msg_id": "m-01H8X...",
  "conversation_id": "conv_789",
  "status": "READ",
  "at": 1757740012000
}
```

**6. Conversation history fetch karo (REST, initial load / pagination / reconnect ke baad catch-up ke liye)**

```
GET /v1/conversations/{conversation_id}/messages?before_seq=4821&limit=50
Response: {
  "messages": [ { "server_msg_id": "...", "seq_no": 4820, "sender_id": "...", "body": {...}, "sent_at": ... }, ... ],
  "has_more": true
}
```
Yeh exactly wahi endpoint hai jo offline catch-up ke liye use hota hai: reconnect pe,
client har conversation ke liye apna last `seq_no` bhejta hai aur server
kuch bhi naya backfill kar deta hai.

## Step 5: Data Model

Teen distinct storage needs, har ek ko alag database type sabse achhe se
serve karta hai — ek acha interview signal yeh explicitly naam lena hai, na ki
sab kuch ek hi store mein daal dena.

**1. Messages — wide-column / partitioned NoSQL store (e.g. Cassandra-style),
`conversation_id` se partitioned**

```
Table: messages
Partition key: conversation_id
Clustering key: seq_no (or a time-sortable message ID, ascending)

conversation_id | seq_no | message_id | sender_id | body            | sent_at
conv_789        | 4821   | m-01H8X... | u123      | {text: "..."}   | 1757740000456
conv_789        | 4820   | m-01H7Y... | u456      | {text: "..."}   | 1757739988112
```
Chosen kyunki dominant query hai "is conversation mein messages do,
order mein, recent-first" — ek partition-per-conversation ek sorted
clustering key ke saath isko ek single-partition range scan se answer karta hai, jo
wide-column store mein cheapest possible query shape hai. Ek relational DB
moderate scale pe bhi kaam kar sakti thi (ek index ke saath `(conversation_id, seq_no)` pe),
lekin ek wide-column store ka native partitioning is access pattern se directly
match karta hai aur writes ko horizontally scale karta hai bina manual sharding logic ke.

**2. Presence / session registry — in-memory key-value store (Redis)**

```
Key: presence:{user_id}          Value: { gateway_node: "gw-17", device_id: "d456", connected_at: ... }
Key: gateway:{gateway_node}:load  Value: current connection count (for load-balancer decisions)
```
Chosen kyunki yeh data chhota hai, har message route ke hot path pe access hota hai,
aur inherently ephemeral hai (ek connection drop hote hi yeh meaningless ho jaata hai) —
ek perfect fit ek in-memory KV store ke liye, ek durable database ki jagah. Dekho
`../01_Concepts/05_caching.md` yeh dekhne ke liye ki Redis specifically isse kyun fit
karta hai (TTL support, atomic ops, pub/sub for invalidation).

**3. Conversation & delivery metadata — relational store (Postgres/MySQL)**

```
Table: conversations (conversation_id PK, type [1:1|group], created_at)
Table: conversation_members (conversation_id, user_id, joined_at, role)
Table: message_status (message_id, user_id, status [SENT|DELIVERED|READ], updated_at)
```
Chosen kyunki group membership aur per-recipient status relational hain,
low-volume-per-row hain, aur transactional guarantees se benefit karte hain (jaise, ek
group mein member add karna ek message ke half-updated member list ko
fan out hone ke saath race nahi karna chahiye).

**4. Media attachments — object storage**

Actual image/video/audio bytes object storage (S3-style) mein rehte hain, jisme
message body sirf ek URL/object key carry karta hai — same pattern jo
`../01_Concepts/12_storage_systems.md` mein hai.

## Step 6: Deep Dive

### 6.1 Connection Management and Message Routing at Scale

Har online user ek persistent WebSocket connection exactly ek connection-gateway
server ko hold karta hai. 50 million concurrent connections aur ~50,000
connections per gateway node (Step 2) pe, yeh roughly 1,000 gateway
instances hain — koi single server saare connections hold nahi kar sakta, isliye fleet
horizontally partition hota hai *is basis pe ki kaunse users happen se usse
connected hain*, data ki kisi property se nahi.

Yeh woh routing problem create karta hai jo is system ko define karta hai: jab user A user B ko
ek message bhejta hai, message-processing layer ke paas yeh jaanne ka koi inherent tareeka
nahi hai ki 1,000 gateway nodes mein se konsi B abhi attached hai. Fix hai ek
**presence/session registry** (Redis, Step 5) jo `user_id ->
gateway_node_id` map karta hai, gateway dwara likha jaata hai jaise hi user connect hota hai
aur delete (ya TTL-expire) hota hai jaise hi woh disconnect hota hai. Ek message route
karna phir yeh ban jaata hai: registry mein B ka current gateway lookup karo, message ko
us specific gateway instance ko internal RPC/queue se forward karo, aur woh
gateway usse B ke open socket pe push kar deta hai. Agar B multiple devices
se connected hai (phone + web), registry per user multiple entries store karta hai aur message
sabko push hota hai.

Yahan do operational details matter karti hain: (1) registry entry ko disconnect pe reliably
clean up karna hoga — ek stale entry ka matlab hai messages ek aise gateway ko route hote hain
jo ab woh connection hold nahi karta, isliye gateways ek heartbeat + TTL use karte hain
(e.g., har 30s refresh karo, 60s baad expire) sirf ek explicit disconnect event
pe rely karne ki jagah, kyunki networks bina clean close ke bhi connections drop kar dete hain.
(2) 1,000 gateway nodes ke across naye connections ko load balance karna
(same registry se) current load ke hisaab se hona chahiye, purely round-robin nahi,
taaki hot gateways avoid ho.

### 6.2 Delivery Guarantees and Ordering

Mobile client aur server ke beech ka network inherently unreliable hai
— packets lose ho jaate hain, connections mid-send drop ho jaate hain, clients retry karte hain. Yeh
system jo practical guarantee deta hai woh hai **at-least-once delivery**: agar koi
doubt ho ki ek send succeed hua ya nahi, client retry karta hai, jiska matlab hai ki
same message legitimately server (ya recipient) tak ek se zyada baar pahunch sakta hai.
Exactly-once delivery end-to-end achievable nahi hai extra machinery ke bina,
isliye duplicates prevent karne ki koshish karne ki jagah, design duplicates ko
harmless bana deta hai: har message ek client-generated `client_msg_id` carry karta hai, aur
server (aur recipient ka client) us ID pe deduplicate karte hain — ek retried send jo
already succeed ho chuka tha recognize ho jaata hai aur simply re-acknowledge ho jaata hai, twice
store/deliver hone ki jagah. Yeh wahi idempotency-key pattern hai jo
`../01_Concepts/09_distributed_systems_core.md` mein generally cover hua hai.

Ordering ek related lekin distinct problem hai. Messages ko wall-clock timestamp se
order karna tempting hai, lekin different application servers (aur especially
different mobile devices) ke clocks perfectly synchronized nahi hote — clock
skew of tens to hundreds of milliseconds normal hai, aur milliseconds apart send hue
do messages different machines ke across out of order timestamp ho sakte hain. Fix
hai ek **monotonically increasing sequence number har conversation ke scope
mein**, server (client nahi) dwara write time pe assign hota hai — message store ka
per-conversation partition (Step 5) isse cheap banaata hai, kyunki
sequence-number assignment us partition ke scope mein ek single atomic increment ho sakta hai.
Clients phir messages ko `seq_no` se order aur display karte hain, timestamp se kabhi nahi;
timestamps sirf display ke liye rakhe jaate hain ("2 minutes ago") aur
ordering ke liye load-bearing nahi hain.

### 6.3 Offline Delivery: Store-and-Forward

Har recipient online nahi hota jab message aata hai — 6.1 ka presence
registry lookup simply empty aa sakta hai. Yeh normal case hai, edge case
nahi, given ki sirf ~10% of DAU kisi bhi moment online hota hai (Step
2). Design isse ek **store-and-forward** model se handle karta hai: message
hamesha durably persist hota hai message store mein pehle (yehi hai jispe sender
ka "sent" ack depend karta hai — persistence pe, delivery pe nahi), recipient
abhi reachable hai ya nahi usse completely independent. Ek connected recipient ko delivery
best described hai ek *optimization* ki tarah persistence ke upar, write
succeed hone ke liye ek requirement ki tarah nahi.

Agar recipient offline hai, system additionally ek **mobile push notification**
trigger karta hai (APNs/FCM ke through) device ko wake karne ya ek banner surface karne ke liye,
lekin push notification khud koi guarantee carry nahi karta — pushes drop, delay,
ya OS dwara rate-limit ho sakte hain. Actual, reliable delivery mechanism yeh hai ki
jab recipient ka client next connect hota hai, woh Step 4 ka catch-up flow perform karta hai
(`GET /messages?before_seq=<last_known_seq>`),
jise per-conversation sequence number trivial aur correct bana deta hai: client
simply har conversation ke liye apne paas jo last `seq_no` hai usse newer sab kuch
maangta hai, aur store ek straightforward range scan se answer karta hai. Isiliye
persistence-first, push-as-optimization right mental model hai:
correctness kabhi push notification ke pahunchne pe depend nahi karta.

### 6.4 Group Chat Fan-out and Read Receipts

N members ke group ko bheja gaya ek message N recipients ko deliver hona chahiye —
structurally same fan-out problem jo feeds aur Twitter ke liye "celebrity problem"
discuss hua tha (dekho `10_twitter_x.md` aur `08_news_feed.md`), bas
kaafi chhote, bounded scale pe, kyunki chat groups typically capped
hote hain (hundreds, na ki millions, of members). Message-processing layer message
ko ek baar conversation ke partition mein message store mein likhta hai, phir
N delivery attempts fan out karta hai — ek presence-registry lookup aur ek push
per online member, ek push-notification trigger per offline member. Kyunki N
bounded aur chhota hai ek viral social-feed fan-out ke relative, yeh
synchronously kiya ja sakta hai message processing ke part ki tarah bina ek
asynchronous background fan-out job ki zaroorat ke; yeh sirf tab ek real problem
banta hai jab group sizes product intentionally cap karta hai (yeh part hai *kyun*
chat products group size cap karte hain, ek social graph ke unbounded follower count ke unlike).

Delivery status (sent/delivered/read) naturally **per-recipient, per-
message** state hai — 50 ke group mein, ek message ke 50 independent
delivered/read states hote hain, ek nahi. Isko message row khud ke mutation ki tarah
model karne ka matlab hoga ki ek single message row ko 50 mutable sub-fields chahiye hon aur
har receipt update usi same row pe contend karega. Iski jagah, receipts
ek **separate, lightweight, append-style update** ki tarah model hote hain (`message_status`
table Step 5 mein, ya ek equivalent write ek fast KV/queue-backed store mein) —
ek row per (message, recipient), independently aur cheaply written, koi
contention nahi original message write ke saath ya doosre recipients ki
receipts ke saath. Sender ka UI inhe aggregate karta hai (jaise, "delivered" ek baar sab
recipients delivered report kar dein, ya group ki "read by" list mein per-recipient
detail) is side table ko read karke, message ko khud touch karke nahi.

## Step 7: Bottlenecks & Trade-offs

- **Presence registry ek single hot dependency hai.** Har message send ko
  iske against ek lookup chahiye, up to ~700k QPS peak (Step 2) pe sirf
  1:1 sends ke liye, group fan-out ke saath aur zyada. Yeh horizontally sharded
  (`user_id` hash se) aur highly available hona chahiye; agar yeh unavailable ho jaata hai,
  system phir bhi messages *persist* kar sakta hai (durability preserve rehti hai) lekin live
  pushes route karne ki ability lose kar deta hai, gracefully degrade hota hai "sab
  offline lag rahe hain" ki taraf, data lose karne ki jagah — ek deliberate
  trade-off graceful degradation ka ek all-or-nothing failure ke upar.
- **Gateway nodes stateful hain, jo deployment complicate karta hai.** Ek
  gateway ko deploy ke liye restart karna uske hold kiye hue har connection ko (ek saath
  tens of thousands) drop kar deta hai, simultaneous reconnects force karte hue jo
  connection layer aur registry pe load spike karte hain. Connection draining
  ke saath rolling deploys (naye connections accept karna band karo, existing
  ke naturally cycle hone ka wait karo, ya actively unhe migrate karo) naive rolling
  restart ki jagah zaroori hain.
- **Group fan-out cost group size ke saath badhta hai**, aur bhale hi product-level caps
  isko bounded rakhein, ek bahut active large group (hundreds of members, high
  message frequency) phir bhi ek local hot spot of fan-out work create kar sakta hai
  ek conversation ke partition pe concentrated — yeh wahi
  hot-partition problem hai jo generally cover hua
  `../01_Concepts/07_database_scaling.md` mein.
- **At-least-once delivery deduplication work ko har client tak push karta hai.**
  Yeh ek deliberate trade-off hai: ek genuinely exactly-once pipeline
  end-to-end banaana (gateway, store, aur push service ke across distributed
  transactions) ek guarantee ke liye substantial latency aur complexity add karega jo
  ek simple client-side `client_msg_id` dedup almost utna hi achieve kar leta hai
  kaafi kam cost mein.
- **Storage message history ke saath unboundedly badhta hai.** Text cheap hai (Step
  2), lekin ek real product per user years of history bhi carry karta hai; older,
  rarely-accessed conversations cheaper, colder storage mein tiering ke liye natural
  candidates hain, old history pe thoda read latency trade karke storage cost mein
  bada reduction paane ke liye.

## Follow-up Questions an Interviewer Might Ask

**End-to-end encryption kaise support karoge?**
Keys sirf client devices pe generate aur hold hoti hain (jaise, Signal
Protocol ke double ratchet ke through); server sirf ciphertext store aur route karta hai
jo woh read nahi kar sakta. Isse upar wale architecture mein bahut kam change hota hai — routing,
presence, aur fan-out sab opaque payloads pe operate karte hain — lekin iska matlab hai ki
server-side features jinhe message content read karna padta hai (message history ke across
search, spam detection) ya toh server-side kaam nahi kar sakte at all
ya client-side computation ki tarah reimplement karne padenge.

**Ek user ke bahut saare devices (phone, tablet, web) sync kaise rakhoge?**
Presence registry ek ki jagah multiple `(user_id, device_id) -> gateway`
entries store karta hai, aur send pe fan-out aur reconnect-pe-catch-up
dono flows per-user ki jagah per-device operate karte hain — har device apna
khud ka last-seen `seq_no` per conversation track karta hai, kyunki ek device offline ho
sakta hai jabki doosra connected rehta hai.

**Agar ek gateway node crash ho jaaye connections open rehte hue kya hoga?**
Usse attached har client ka socket drop hota hai aur woh reconnect karta hai
(backoff ke saath) load balancer ke through ek healthy gateway pe; us node ke liye
presence registry entries actively invalidate honi chahiye (ya jaldi TTL se expire) taaki
routing meanwhile ek dead node pe messages bhejta na rahe. Koi
messages lose nahi hote kyunki persistence (Step 6.3) kabhi us gateway ke up rehne pe
depend nahi karti thi.

**System ko overload kiye bina "typing..." indicators kaise add karoge?**
Typing indicators ko messages se fundamentally different treat kiya jaata hai: yeh
ephemeral hain, lossy-tolerant hain, aur kabhi persist nahi hote — ek lightweight,
unacknowledged WebSocket frame ki tarah send hote hain, often client-side debounce/throttle
hote hain (e.g., at most ek "typing" event har kuch seconds mein), aur agar
recipient offline hai toh simply drop ho jaate hain, ek real message ki tarah later
delivery ke liye queue hone ki jagah.

**User ki message history ke across search kaise scale karoge?**
Yeh ek separate derived system hai, hot send/receive path ka part nahi —
messages asynchronously ek search system mein index hote hain jaise likhe jaate hain
(jaise, ek queue ke through, dekho `../01_Concepts/10_message_queues_and_streaming.md`),
ek inverted index use karke jaisa describe hua hai
`../01_Concepts/13_search_and_indexing.md` mein, wahi near-real-time
indexing lag accept karte hue jo kisi bhi search system ka hota hai.

**Abusive senders (spam) ko normal users ko slow kiye bina kaise rate-limit karoge?**
Ek per-user token-bucket rate limiter message-processing path mein
persistence se pehle baithta hai, tracked usi tarah ke fast in-memory store mein jo
presence ke liye use hota hai (Redis counters TTL ke saath) — yeh check ko cheap rakhta hai
(ek single atomic increment) aur critical path se off rakhta hai un zyadatar users ke liye jo
limit ke kabhi kareeb nahi aate.
