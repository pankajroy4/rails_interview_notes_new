# Design a Cloud File Storage & Sync Service (Dropbox/Google Drive)

## Problem Statement

"Ek cloud file storage aur sync service design karo, Dropbox jaisi. User apna desktop
client install karta hai, ek special folder mein files daalta hai, aur woh files cloud
mein upload ho jaati hain aur automatically uske baaki sab devices pe sync ho jaati
hain — aur un logon ke saath bhi jinke saath usne woh folder share kiya hai. Agar woh
ek badi file edit kare, toh hum har keystroke ke change pe poori file re-upload nahi
karna chahte. Chalo system design karte hain, especially focus karte hue ki sync
efficiently kaise kaam karta hai."

Yahaan defining challenge hai **nahi** "ek file store karna" (uske liye toh object
storage hai hi) — balki **changing files ka multiple devices ke across efficient
synchronization**, jiske liye "ek file" ko chhote, independently-updatable pieces ke
set ke roop mein rethink karna padta hai.

## Step 1: Requirements Clarify Karna

**Functional Requirements**
- Users files upload, download, delete, aur folders mein organize kar sakte hain.
- Ek device pe upload/edit ki hui files automatically user ke baaki devices pe sync ho
  jaati hain.
- Users doosre users ke saath files/folders share kar sakte hain (read-only ya edit
  access).
- System offline edits ko support karta hai jo connectivity wapas aane pe sync ho
  jaate hain.
- Users file ki version history dekh sakte hain aur ek previous version restore kar
  sakte hain.
- Large-file edits mein sirf file ka changed portion re-transmit hona chahiye, poori
  file nahi, taaki sync fast rahe aur bandwidth-cheap rahe.

**Non-Functional Requirements**
- **Scale**: assume karo 500 million registered users, 100 million daily active,
  average har ek ke paas kuch GB stored data hai.
- **Durability**: file data essentially kabhi lost nahi hona chahiye — yeh product ki
  sabse strongest guarantee hai jo bikti hai (users apna irreplaceable data isi pe
  trust karte hain), isliye durability stored bytes ke liye almost har trade-off se
  upar hai.
- **Latency**: metadata operations (folder list karna, file rename karna) instant feel
  hone chahiye (sub-200ms); actual file transfer latency network bandwidth aur file
  size se bound hoti hai, kuch aisa nahi jo backend design directly control kare — par
  backend ko minimize karna chahiye ki *kitna* transfer karna padta hai.
- **Consistency**: metadata (folder structure, sharing permissions) per-account
  strongly consistent honi chahiye — ek rename us user ke doosre active sessions mein
  immediately visible hona chahiye. *Content* changes ka cross-device propagation
  eventually consistent ho sakta hai (kuch seconds ka lag "maine laptop pe save kiya"
  aur "phone ko update dikha" ke beech acceptable hai).
- **Storage efficiency**: unchanged data ka redundant storage avoid karo — same file ke
  versions ke across bhi, aur ideally, alag-alag users ki identical files ke across bhi
  (deduplication).
- **Bandwidth efficiency**: yeh is system ke liye specifically headline non-functional
  requirement hai — ek 500-page document mein ek paragraph edit karne se 500 pages
  jitne bytes re-upload nahi hone chahiye.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 100 million daily active users.
- Average user total 5 GB store karta hai, 3 devices ke across sync karta hai.
- Average user ~20 file operations/day karta hai (create, edit-save, delete, move) —
  zyadatar kuch actively-worked-on files ke small edits hote hain, naye uploads nahi.
- Chunk size: 4 MB fixed chunks (ek common real-world choice — itna bada ki
  chunk-count aur metadata overhead kam rahe, itna chhota ki ek typical edit sirf kuch
  chunks ko hi touch kare).

**Total stored data**
```
100,000,000 users x 5 GB = 500,000,000 GB = 500 PB of logical data
```
Deduplication ke saath (Step 6 dekho) aur is fact ke saath ki bahut se users overlapping
common files store karte hain (shared documents, common app data, OS-generated files),
effective physical storage logical figure se materially kam hoti hai — par hum logical
upper bound assume karke design karte hain aur dedup ko ek bonus treat karte hain, ek
load-bearing assumption nahi.

**Write QPS (sync operations)**
```
100,000,000 users x 20 ops/day = 2,000,000,000 ops/day
2,000,000,000 / 86,400 sec ≈ 23,150 ops/sec average
Assume 3x business-hours peak multiplier → ~70,000 ops/sec peak
```
Yahaan har "op" ek metadata operation hai; associated chunk upload sirf un chunks ke
liye hota hai jo actually change hue hain, jo iss chunking ki poori baat hai.

**Chunk-level traffic from a single edit**
```
Editing one paragraph in a 50 MB document with 4 MB chunks
= ~13 total chunks, of which typically 1-2 chunks actually change
= re-upload ~4-8 MB instead of the full 50 MB
= roughly 85-90% bandwidth savings on this single edit, and this ratio improves further for larger files
```

**Metadata storage**
```
Average user: ~2,000 files, each file has current metadata + chunk-hash list
Per file: ~500 bytes base metadata + (avg 3 chunks/file x 32 bytes/hash) ≈ 600 bytes
100,000,000 users x 2,000 files x 600 bytes ≈ 120 TB of metadata
```
Yeh comfortably ek well-indexed, horizontally-sharded relational/NoSQL metadata tier
mein fit ho jaata hai — raw content se teen orders of magnitude chhota, jo confirm karta
hai ki metadata aur content genuinely alag, differently-optimized storage systems mein
belong karte hain.

**Bandwidth**
```
70,000 ops/sec peak, assume avg 4 MB actually transferred per op (mix of small edits and larger new uploads)
= 280,000 MB/sec = 280 GB/sec aggregate peak transfer across the whole service
```
Isi liye chunking estimation level pe bhi matter karta hai, sirf UX level pe nahi —
iske bina, "average op poori average-sized file transfer karta hai" is bandwidth figure
ko ek order of magnitude ya usse zyada se multiply kar deta.

## Step 3: High-Level Design

**Core components**
- **Client (desktop/mobile app)** — ek local sync folder watch karta hai, changed
  files ko chunk karta hai, chunk hashes compute karta hai, aur backend se baat karta
  hai.
- **API Gateway** — auth, request routing.
- **Metadata Service** — file/folder hierarchy, ownership, sharing/permission data, aur
  har file version ki chunk hashes ki list ka owner hai. Ek database (SQL ya ek
  strongly consistent NoSQL store — Step 5 dekho) se backed hai.
- **Block/Chunk Service** — chunk upload/download handle karta hai, object storage se
  baat karta hai, aur chunk-level deduplication karta hai (agar yeh hash pehle se
  exist karta hai, toh upload skip karo).
- **Object Storage** — raw chunk bytes (actual file content) ke liye durable, cheap,
  massively scalable storage, content hash se addressed.
- **Sync/Notification Service** — user ke har online device ke saath ek live channel
  maintain karta hai aur "kuch change hua" events push karta hai taaki doosre devices
  ko pata chale ki deltas pull karein, instead of har device ko interval pe poll karna
  padhe.
- **Sharing Service** — shared files/folders pe permissions manage karta hai, Metadata
  Service ke records ke upar layered.

**Ek existing file edit karne ka data flow**
1. Client ek local file change detect karta hai (filesystem watcher), file ko
   re-chunk karta hai, aur har chunk ko hash karta hai.
2. Client naye chunk-hash list ko last-known-synced list (locally cached) ke saath
   compare karta hai aur identify karta hai ki actually kaunse chunks change hue.
3. Client sirf changed chunks Block/Chunk Service ko upload karta hai, jo unhe content
   hash se keyed karke Object Storage mein store karta hai (aur agar woh hash pehle se
   exist karta hai toh storage entirely skip kar deta hai — global dedup).
4. Phir Client Metadata Service ko call karta hai ek naya file version commit karne ke
   liye: chunk hashes ki nayi ordered list, purane version ki list ko replace karte
   hue.
5. Metadata Service naya version persist karta hai aur ek change event publish karta
   hai.
6. Sync/Notification Service user ke doosre online devices ko "file X change hui" push
   karta hai unke live connection ke upar.
7. Har notified device Metadata Service se naya chunk-hash list fetch karta hai, use
   apni local copy ki list ke saath diff karta hai, aur sirf woh chunks download karta
   hai jo uske paas missing hain — same delta principle reverse mein.

```text
+------------------+        +------------------+
|  Desktop Client    |        |   Mobile Client    |
|  (chunk + hash)    |        |  (chunk + hash)    |
+---------+--------+        +---------+--------+
          |                            ^
          | upload changed chunks       | push: "file changed"
          | commit new version          | pull delta chunks
          v                            |
+---------+----------------------------+--------+
|                    API Gateway                  |
+---------+--------------------------+-----------+
          |                          |
+---------v---------+      +---------v-----------+
|  Metadata Service   |      |  Sync/Notification   |
|  (file tree,        |<---->|  Service (long-lived  |
|  chunk-hash lists,   | events|  push channel per    |
|  versions, SQL)      |      |  online device)       |
+---------+---------+      +-----------------------+
          |
          | validates chunk hashes exist
          v
+---------+---------+
|  Block/Chunk Service |
|  (dedup check,        |
|  upload/download)      |
+---------+---------+
          |
          v
+---------+---------+
|   Object Storage     |
|  (chunks keyed by     |
|   content hash)        |
+---------------------+
```

## Step 4: API Design

**`POST /v1/files/{file_id}/versions`** — changed chunks upload karne ke baad ek naya
file version commit karo.
```json
Request:  { "chunk_hashes": ["h1","h2","h9","h4"], "size_bytes": 52428800, "parent_version": 41 }
Response: { "version": 42, "status": "committed" }
```

**`POST /v1/chunks/check`** — upload se pehle poocho ki kaunse chunks (hash se) server
ke paas already hain, redundant transfer avoid karne ke liye.
```json
Request:  { "hashes": ["h1","h2","h9","h4"] }
Response: { "missing": ["h9"] }
```

**`PUT /v1/chunks/{hash}`** — ek single missing chunk ke bytes upload karo.
```json
Request:  <raw 4MB chunk bytes>, header X-Chunk-Hash: h9
Response: { "stored": true, "hash": "h9" }
```

**`GET /v1/files/{file_id}?version=latest`** — file ke current metadata/chunk list
fetch karo (client phir sirf woh chunks download karta hai jo already locally nahi
hain).
```json
Response: { "file_id":"f_1", "version":42, "chunk_hashes":["h1","h2","h9","h4"], "size_bytes":52428800 }
```

**`GET /v1/folders/{folder_id}/listing`** — folder contents list karo (metadata only,
file sizes se independent).
```json
Response: { "entries": [ {"id":"f_1","name":"report.docx","type":"file","modified_at":1699999999}, {"id":"fd_2","name":"Photos","type":"folder"} ] }
```

**`POST /v1/shares`** — ek file/folder doosre user ke saath share karo.
```json
Request:  { "resource_id": "fd_2", "grantee_email": "user@example.com", "permission": "edit" }
Response: { "share_id": "sh_1", "status": "active" }
```

**`GET /v1/sync/subscribe`** — ek long-lived connection (WebSocket ya SSE) jo ek
device kahin aur ki hui changes ke push notifications receive karne ke liye open
karta hai.
```json
Pushed event: { "type": "file_changed", "file_id": "f_1", "new_version": 42, "changed_by_device": "dev_A" }
```

## Step 5: Data Model

**Metadata — relational (SQL) database, `databases_fundamentals.md` ke according**
Yeh isliye chosen hai kyunki file/folder hierarchy, ownership, aur sharing permissions
naturally relational hain (ek folder mein files aur folders hote hain; ek share ek
user ko ek resource ka access deta hai), strong consistency ki requirement hai (do
devices ko kabhi "is file ka current version kya hai" ke diverging views nahi dikhne
chahiye), aur yahaan write volume (sirf metadata, chunk bytes exclude karke) itna
modest hai — tens of thousands ops/sec, millions nahi — ki ek well-sharded SQL tier ise
comfortably handle kar sakti hai.
```sql
CREATE TABLE files (
  id            BIGINT PRIMARY KEY,
  owner_id      BIGINT NOT NULL,
  parent_folder_id BIGINT,
  name          VARCHAR(255),
  current_version INT,
  size_bytes    BIGINT,
  created_at    TIMESTAMP,
  updated_at    TIMESTAMP,
  INDEX idx_parent (parent_folder_id)
);

CREATE TABLE file_versions (
  file_id       BIGINT,
  version       INT,
  chunk_hashes  JSON,          -- chunk content-hashes ka ordered array
  size_bytes    BIGINT,
  created_at    TIMESTAMP,
  created_by_device VARCHAR(64),
  PRIMARY KEY (file_id, version)
);

CREATE TABLE shares (
  id            BIGINT PRIMARY KEY,
  resource_id   BIGINT,
  resource_type VARCHAR(10),   -- 'file' ya 'folder'
  grantee_id    BIGINT,
  permission    VARCHAR(10)    -- 'read' ya 'edit'
);
```
`owner_id` se sharded (zyadatar access patterns — "meri files list karo," "meri
changes sync karo" — ek account ke scope tak simit hain), shared-resource lookups
`shares` table se `grantee_id` pe ek secondary index se resolve hote hain.

**Chunk content — object storage, `storage_systems.md` ke according**
Yeh isliye chosen hai kyunki chunk bytes bade hote hain, ek baar likhe jaane ke baad
immutable hote hain (ek chunk apne hi hash se content-addressed hai, isliye usse kabhi
in-place update ki zaroorat nahi — ek changed chunk bas ek naya object hai naye hash ke
saath), metadata ke comparison mein relatively kam frequently access hota hai, aur
object storage exactly isi ke liye purpose-built hai: opaque blobs ka cheap, durable,
massively horizontally scalable storage, jisme content ke upar relational query
capability ki koi zaroorat nahi.
```
Key:   chunks/{sha256_hash}
Value: raw chunk bytes (up to 4 MB), ek baar hi store hota hai chahe kitni bhi files/users use reference karein
```
Content-addressing (key = value ka hash) hi wo cheez hai jo delta sync aur
deduplication dono ko almost free mein possible banati hai: identical content, system
mein kahin bhi ho, hamesha same key pe map karta hai.

**Local client-side index — har device pe ek embedded key-value store (e.g., SQLite)** —
har local file ka last-synced chunk-hash list track karta hai, taaki client server ke
saath apni state diff kar sake bina un files ko re-hash kiye jinhe usne touch nahi
kiya.

## Step 6: Deep Dive

### 6.1 File chunking: efficient sync ki foundation

Har file ko upload se pehle fixed-size blocks (e.g., 4 MB) mein split karna woh ek
single idea hai jo iss poore system ko kaam karwati hai. Socho ek 200 MB document ke
beech mein ek paragraph edit karna: chunking ke bina, koi bhi "file change hui" detection
poori 200 MB re-upload karwaega, kyunki storage layer ki nazar mein, "file" ek opaque
blob hai aur koi bhi byte change hone se poori cheez invalidate ho jaati hai. Chunking
ke saath, file chunk hashes ki ek ordered list ke roop mein represent hoti hai — maan
lo, pachaas 4 MB chunks — aur ek paragraph edit karne se sirf ek ya do chunks ke andar
ke byte ranges touch hote hain. Client saare chunks re-hash karta hai (cheap — hashing
CPU-bound hai aur network transfer ke comparison mein fast hai), naye hash list ko
purane list ke saath positionally compare karta hai, pata chalta hai ki 50 mein se 48
hashes unchanged hain, aur sirf un 1-2 chunks ko upload karna padta hai jinka hash change
hua. "File" khud, jaisa ki Metadata Service track karta hai, actually kabhi "file" hai
hi nahi — yeh chunk-hash references ki ek versioned list hai, kuch waisa hi jaisa ek
Git commit poori repository ki full copy na hoke content-addressed blobs ka ek tree
hota hai.

Ek practical wrinkle: fixed-size chunking mein ek edge case hai jahan file ke start ke
paas kuch bytes *insert* karne se har subsequent byte offset shift ho jaata hai, jo
insertion point ke baad har chunk boundary ke across ek change cascade kar sakta hai
chahe zyadatar content semantically change na hua ho (yeh classic problem hai jise
content-defined chunking / rolling-hash chunk boundaries — jaise rsync jaise tools use
karte hain — solve karne ke liye design kiye gaye hain — ek refinement ke roop mein
mention karne layak, par fixed-size chunking simpler baseline design hai aur yahi is
write-up mein baaki jagah assume kiya gaya hai).

### 6.2 Delta sync: chunking plus hashing barabar hai "sirf woh sync karo jo change hua"

Delta sync 6.1 ka multi-device propagation problem pe direct application hai. Jab
Device A ek naya file version commit karta hai (naya chunk-hash list), Device B — jo
push channel (6.4) se notify hua — poori file blindly re-download nahi karta. Yeh
Metadata Service se sirf naya chunk-hash list fetch karta hai (ek chhota, cheap
metadata read), use us file ke apne last-known-synced list ke saath diff karta hai,
aur sirf woh chunks download karta hai jinka hash uske paas locally already nahi hai
(`POST /v1/chunks/check`-style flow use karke, ya simply lists direct compare karke
kyunki dono sides ke paas already hain). Yeh 6.1 ke upload path ke symmetric hai — same
mechanism (content hash comparison) dono ko drive karta hai "mujhe kya upload karna
hai" aur "mujhe kya download karna hai," isi liye chunking ko shuru mein sahi design
karna sync ke dono sides pe simultaneously pay off karta hai.

### 6.3 Metadata storage ko block/content storage se separate karna

Yeh separation hi wo cheez hai jo common operations ko file size se independent fast
rakhti hai. Folder list karna, file rename karna, ya "kya kuch change hua hai jab se
maine last sync kiya" check karna — yeh sab pure metadata operations hain — yeh sirf
Metadata Service ki relational rows (sirf sau bytes) ko touch karte hain aur kabhi
object storage mein baithe actual chunk bytes ko dekhne, move karne, ya unka size
janne ki bhi zaroorat nahi padti. Agar metadata aur content saath store hote (e.g., ek
single "file blob" table jisme file ke attributes aur raw bytes dono hote), toh ek
hazaar badi video files ke folder ki listing ka matlab hota ki database indirectly
gigabytes ke content se entangled hai, aur rename karne se bina wajah large-object
storage paths touch hone ka risk hota. Iske contrast mein, separation ke saath: rename
`files.name` pe ek single chhoti UPDATE hai; folder listing `files` rows ke upar ek
indexed query hai, jo file size se nahi balki folder size se bound hai; aur object
storage mein actual chunk data sirf tabhi touch hota hai jab content — metadata nahi —
move karna ho. Yeh wahi reasoning mirror karta hai jo `databases_fundamentals.md` aur
`storage_systems.md` independently deti hain: database use karo jisko relational
structure, indexing, aur transactional consistency chahiye, aur object storage use
karo jisko large opaque bytes cheaply durably hold karna hai — inhe ek system mein
combine karna kisi ko bhi achhi tarah optimize nahi karta.

### 6.4 Conflict resolution: same file do offline devices pe edit ho

Agar ek user apni same file laptop aur phone pe edit kare jab dono offline hain, aur
phir dono online wapas aayein, toh dono devices apne-apne naye version commit karne ki
koshish karenge jo *same* parent version ke upar built hoga — ek genuine conflict,
kyunki koi bhi device ka edit doosre ke upar built nahi hua. Do standard strategies:

- **Last-write-wins**: server jo bhi version pehle commit hota hai use accept kar leta
  hai (server-received timestamp se), aur doosre device ka commit reject ho jaata hai
  ya possible ho toh auto-merge ho jaata hai; losing device wale user ko warning milti
  hai ki uska version overwrite ho gaya. Implement karna simple hai, par user ke
  perspective se silently data lose kar deta hai — low-stakes files ke liye acceptable,
  par kisi bhi cheez ke liye risky jisse user important samajhta hai.
- **Conflicted copy**: server version conflict detect karta hai (incoming commit ka
  `parent_version` file ke actual current version se match nahi karta) aur, overwrite
  karne ke bajaye, doosre device ke version ko ek nayi file ke roop mein save kar deta
  hai — e.g., `report (conflicted copy, Device B, 2026-09-13).docx` — dono versions
  user ke manually reconcile karne ke liye intact chhod deta hai. Yeh kabhi data lose
  nahi karta, iski cost hai kabhi-kabhi annoying UX (user ko khud duplicate notice
  karke merge karna padta hai).

Conflicted-copy approach hi wo hai jo real systems jaise Dropbox actually ship karte
hain, kyunki ek product ke liye jiska core promise hai "hum aapka data lose nahi
karenge," silently ek device ke edits discard karna (last-write-wins) directly us
promise ko contradict karta hai — "user ko kabhi-kabhi manually ek conflicted copy
clean up karni padti hai" ka trade-off "system ne bina warning ke silently work
destroy kar diya" se strictly behtar hai.

### 6.5 User ke devices ke across real-time change notification

Ek baar version commit ho jaaye, toh baaki devices ko bina constantly poll kiye pata
chalna chahiye ("kuch change hua kya?" har kuch seconds mein, hundreds of millions of
idle devices ke across multiply karke, khud hi ek significant load source ban jaata
near-zero signal ke liye, zyadatar time kuch change hua hi nahi hota). Iske bajaye, har
online device Sync/Notification Service ke saath ek long-lived connection hold karta
hai — ek lightweight push channel (WebSocket, ya fallback ke roop mein long-polling
constrained clients/networks ke liye, `networking_and_apis.md` ke real-time
communication comparison ke trade-offs ke according) — aur Metadata Service har commit
pe ek chhota "file X ab version N pe hai" event publish karta hai. Notification
Service us event ko sirf affected user ke baaki currently-connected devices tak fan
out karta hai (user_id se lookup — ek chhota, targeted fan-out, broadcast nahi). Ek
device jo event fire hone ke waqt offline tha, push simply miss kar deta hai aur uske
bajaye agli baar reconnect karne pe ek reconciliation sync karta hai (local state ko
server state ke saath compare karta hai) — toh push channel common case (multiple
devices ek saath online) ke liye ek latency optimization hai, ek correctness
requirement nahi, kyunki client ke paas offline-then-reconnect case ke liye hamesha ek
fallback poll/reconcile path hota hai.

## Step 7: Bottlenecks & Trade-offs

- **Metadata Service heavy small-edit workloads ke neeche pehla bottleneck hai.** Woh
  users jo files open rakhte hain aur frequently auto-save karte hain (e.g., har kuch
  seconds mein), unke storage footprint ke comparison mein disproportionate share
  version-commit traffic generate karte hain. Mitigation: client-side commits ko
  batch/debounce karo (har keystroke pe naya version commit mat karo, ek chhoti window
  ke andar edits ko coalesce karo sync karne se pehle) instead of Metadata Service ko
  unbounded commit frequency absorb karne ke liye scale karne ki koshish karna.
- **Chunk-check round-trips many-small-file workloads ke liye latency add karte hain.**
  Hazaaron chhoti files wala ek folder (e.g., ek code repository) ka matlab hai
  hazaaron chhote metadata/chunk-check operations instead of ek badi transfer —
  per-operation overhead dominate karta hai. Mitigation: bahut si chhoti files ke
  across chunk-existence checks aur metadata commits ko kam, badi requests mein batch
  karo instead of ek round-trip per file.
- **Global deduplication ek durability aur privacy trade-off hai, ek free win nahi.**
  Ek chunk ki ek copy store karna chahe kitne bhi users use reference karein, huge
  storage cost save karta hai, par iska matlab hai ki ek corrupted/deleted chunk ek
  saath bahut se users ki files affect kar sakta hai (object storage mein very high
  replication durability se mitigate hota hai) aur careful reference counting chahiye
  hoti hai taaki ek chunk storage se sirf tabhi actually delete ho jab koi bhi file
  version kahin bhi use reference na kar raha ho.
- **Fixed-size chunking ka boundary-shift problem** (6.1) ka matlab hai ki kuch edit
  patterns (bade file ke start ke paas bytes insert karna) common case (append karna,
  ya end ke paas edit karna) se worse delta-sync efficiency paate hain — simpler
  fixed-size scheme ki ek accepted limitation, jise baad mein content-defined chunking
  se address kiya ja sakta hai agar yeh ek measured problem ban jaaye.
- **Sharing cross-shard metadata queries introduce karti hai.** owner_id se sharded
  metadata ka matlab hai ki ek shared folder ka ek non-owner grantee ke liye
  access-control check ko shards ke across pahunchna padta hai; separate `shares`
  table se mitigate hota hai jiska apna index `grantee_id` pe hai, main file tree ke
  comparison mein chhota rakha gaya, instead of har possible grantee ka data har
  resource ke saath co-locate karne ki koshish karna jiska use access diya gaya ho.

## Follow-up Questions jo ek Interviewer Puch Sakta Hai

**"Aap bahut badi files, jaise 50 GB video files, kaise support karoge?"** Chunking
model yeh naturally handle kar leta hai — ek 50 GB file bas ~12,500 chunks hai 4 MB
each pe; interesting addition hai parallel multi-chunk upload/download (multiple
concurrent connections ke across chunk transfers fan out karna) aur resumability
(agar transfer interrupt ho jaaye, toh sirf not-yet-confirmed chunks retry karne
padte hain, poori file nahi).

**"Aap version history aur har version rakhne se hone waali storage growth kaise
handle karoge?"** Kyunki versions bas chunk hashes ki ordered lists hain, aur versions
ke beech unchanged chunks literally same stored object hain, ek file ke N versions
rakhna sirf un chunks ki cost aati hai jo un versions ke across actually change hue,
N full copies ki nahi — version history storage terms mein near-free hai, thanks to
usi content-addressing ki jo delta sync ko power karti hai. Retention policy (e.g., 30
din tak saare versions rakho, phir daily/weekly snapshots tak thin out karo) metadata
list ko trim karti hai bina un shared chunks ko touch kiye jo kahin aur abhi bhi
reference kiye ja rahe hain.

**"Aap ek malicious user ko ek aisa chunk upload karne se kaise rokoge jo uske claimed
hash se match nahi karta?"** Block/Chunk Service receipt pe server-side hash
recompute karta hai aur agar claimed hash se match na kare toh upload reject kar deta
hai — kabhi bhi client-supplied hash ko us key ke neeche store hone wali cheez ke
ground truth ke roop mein trust mat karo, kyunki baad mein kisi doosre user ka usi
hash ka download otherwise silently corrupted data receive kar lega.

**"Aap is system ke across search (name/content se files dhoondhna) kaise scale
karoge?"** File name search ek metadata-tier query hai (name/owner se indexed,
`databases_fundamentals.md` ke according); full-text content search ke liye ek
separate inverted-index pipeline chahiye (`search_and_indexing.md` ke according) jo
supported file types se text content asynchronously extract aur index karta hai
upload ke baad — explicitly sync path se decoupled taaki indexing latency kabhi ek
file ko "synced" consider hone se block na kare.

**"Agar do users ek shared document ko simultaneously edit kar rahe hon toh kya
hota hai?"** Yahaan describe kiye gaye file-storage layer pe, yeh 6.4 wale same
conflict scenario mein degenerate ho jaata hai (same parent version ke against race
karti do commits) jab tak product real-time co-editing (Google-Docs-style) bhi offer
na kare, jo ek fundamentally different system hai — operational-transform ya
CRDT-based merging of concurrent edits character level pe — explicit extension ke
roop mein naam lene layak, is design ke scope se aage.

**"Storage unbounded badhne pe aap infrastructure cost kaise estimate aur control
karoge?"** Storage ko access recency se tier karo — un files ke chunks jinhe lambe
time se access nahi kiya gaya woh cheaper, higher-latency cold storage classes mein
move ho jaate hain, user ke liye transparent, sirf ek lambe idle period ke baad first
access thoda slow hota hai — usi content-addressed chunk store ke upar layered ek
standard object-storage lifecycle policy.
