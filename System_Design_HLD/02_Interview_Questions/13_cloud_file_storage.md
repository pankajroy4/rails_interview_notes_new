# Design a Cloud File Storage & Sync Service (Dropbox/Google Drive)

## Problem Statement

"Design a cloud file storage and sync service like Dropbox. A user installs a desktop
client, drops files into a special folder, and those files get uploaded to the cloud
and automatically synced to all of their other devices — and to anyone they've shared
the folder with. If they edit a large file, we don't want to re-upload the whole thing
on every keystroke's worth of change. Let's design the system, focusing especially on
how sync actually works efficiently."

The defining challenge here is **not** "store a file" (that's what object storage is
for) — it's **efficient synchronization of changing files across multiple devices**,
which requires rethinking "a file" as a set of smaller, independently-updatable pieces.

## Step 1: Clarify Requirements

**Functional Requirements**
- Users can upload, download, delete, and organize files into folders.
- Files uploaded/edited on one device automatically sync to the user's other devices.
- Users can share files/folders with other users (read-only or edit access).
- The system supports offline edits that sync once connectivity returns.
- Users can view file version history and restore a previous version.
- Large-file edits should only re-transmit the changed portion of the file, not the
  whole file, to keep sync fast and bandwidth-cheap.

**Non-Functional Requirements**
- **Scale**: assume 500 million registered users, 100 million daily active, averaging
  a few GB of stored data each.
- **Durability**: file data must essentially never be lost — this is the single
  strongest guarantee the product sells (users trust it with irreplaceable data), so
  durability trumps almost every other trade-off for stored bytes.
- **Latency**: metadata operations (listing a folder, renaming a file) should feel
  instant (sub-200ms); actual file transfer latency is bounded by network bandwidth and
  file size, not something the backend design controls directly — but the backend
  should minimize *how much* has to transfer.
- **Consistency**: metadata (folder structure, sharing permissions) should be strongly
  consistent per-account — a rename should be immediately visible to that user's other
  active sessions. Cross-device propagation of *content* changes can be eventually
  consistent (a few seconds of lag between "I saved on laptop" and "phone sees the
  update" is acceptable).
- **Storage efficiency**: avoid redundant storage of unchanged data — both across
  versions of the same file and, ideally, across different users' identical files
  (deduplication).
- **Bandwidth efficiency**: this is the headline non-functional requirement for this
  system specifically — editing one paragraph in a 500-page document should not
  re-upload 500 pages' worth of bytes.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 100 million daily active users.
- Average user stores 5 GB total, syncs across 3 devices.
- Average user performs ~20 file operations/day (create, edit-save, delete, move) —
  most are small edits to a few actively-worked-on files, not new uploads.
- Chunk size: 4 MB fixed chunks (a common real-world choice — big enough to keep
  chunk-count and metadata overhead low, small enough that a typical edit only touches
  a handful of chunks).

**Total stored data**
```
100,000,000 users x 5 GB = 500,000,000 GB = 500 PB of logical data
```
With deduplication (see Step 6) and the fact that many users store overlapping common
files (shared documents, common app data, OS-generated files), effective physical
storage is materially lower than the logical figure — but we design assuming the
logical upper bound and treat dedup as a bonus, not a load-bearing assumption.

**Write QPS (sync operations)**
```
100,000,000 users x 20 ops/day = 2,000,000,000 ops/day
2,000,000,000 / 86,400 sec ≈ 23,150 ops/sec average
Assume 3x business-hours peak multiplier → ~70,000 ops/sec peak
```
Each "op" here is a metadata operation; the associated chunk upload only happens for
the chunks that actually changed, which is the entire point of chunking.

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
This comfortably fits a well-indexed, horizontally-sharded relational/NoSQL metadata
tier — three orders of magnitude smaller than the raw content, confirming metadata and
content genuinely belong in separate, differently-optimized storage systems.

**Bandwidth**
```
70,000 ops/sec peak, assume avg 4 MB actually transferred per op (mix of small edits and larger new uploads)
= 280,000 MB/sec = 280 GB/sec aggregate peak transfer across the whole service
```
This is why chunking matters at the estimation level, not just the UX level — without
it, "average op transfers a whole average-sized file" would multiply this bandwidth
figure by an order of magnitude or more.

## Step 3: High-Level Design

**Core components**
- **Client (desktop/mobile app)** — watches a local sync folder, chunks changed files,
  computes chunk hashes, and talks to the backend.
- **API Gateway** — auth, request routing.
- **Metadata Service** — owns the file/folder hierarchy, ownership, sharing/permission
  data, and each file version's list of chunk hashes. Backed by a database (SQL or a
  strongly consistent NoSQL store — see Step 5).
- **Block/Chunk Service** — handles chunk upload/download, talks to object storage,
  and does chunk-level deduplication (if this hash already exists, skip the upload).
- **Object Storage** — durable, cheap, massively scalable storage for raw chunk bytes
  (the actual file content), addressed by content hash.
- **Sync/Notification Service** — maintains a live channel to each of a user's online
  devices and pushes "something changed" events so other devices know to pull deltas,
  instead of every device polling on an interval.
- **Sharing Service** — manages permissions on shared files/folders, layered on top of
  Metadata Service records.

**Data flow for editing an existing file**
1. Client detects a local file change (filesystem watcher), re-chunks the file, and
   hashes each chunk.
2. Client compares the new chunk-hash list to the last-known-synced list (cached
   locally) and identifies which chunks actually changed.
3. Client uploads only the changed chunks to the Block/Chunk Service, which stores them
   in Object Storage keyed by content hash (and skips storage entirely if that hash
   already exists — global dedup).
4. Client then calls the Metadata Service to commit a new file version: the new
   ordered list of chunk hashes, replacing the old version's list.
5. Metadata Service persists the new version and publishes a change event.
6. Sync/Notification Service pushes "file X changed" to the user's other online
   devices over their live connection.
7. Each notified device fetches the new chunk-hash list from Metadata Service, diffs
   it against its own local copy's list, and downloads only the chunks it's missing —
   the same delta principle in reverse.

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

**`POST /v1/files/{file_id}/versions`** — commit a new file version after uploading
changed chunks.
```json
Request:  { "chunk_hashes": ["h1","h2","h9","h4"], "size_bytes": 52428800, "parent_version": 41 }
Response: { "version": 42, "status": "committed" }
```

**`POST /v1/chunks/check`** — ask which chunks (by hash) the server already has, before
uploading, to avoid redundant transfer.
```json
Request:  { "hashes": ["h1","h2","h9","h4"] }
Response: { "missing": ["h9"] }
```

**`PUT /v1/chunks/{hash}`** — upload a single missing chunk's bytes.
```json
Request:  <raw 4MB chunk bytes>, header X-Chunk-Hash: h9
Response: { "stored": true, "hash": "h9" }
```

**`GET /v1/files/{file_id}?version=latest`** — fetch current metadata/chunk list for a
file (client then downloads only chunks it doesn't already have locally).
```json
Response: { "file_id":"f_1", "version":42, "chunk_hashes":["h1","h2","h9","h4"], "size_bytes":52428800 }
```

**`GET /v1/folders/{folder_id}/listing`** — list folder contents (metadata only,
independent of file sizes).
```json
Response: { "entries": [ {"id":"f_1","name":"report.docx","type":"file","modified_at":1699999999}, {"id":"fd_2","name":"Photos","type":"folder"} ] }
```

**`POST /v1/shares`** — share a file/folder with another user.
```json
Request:  { "resource_id": "fd_2", "grantee_email": "user@example.com", "permission": "edit" }
Response: { "share_id": "sh_1", "status": "active" }
```

**`GET /v1/sync/subscribe`** — long-lived connection (WebSocket or SSE) a device opens
to receive push notifications of changes made elsewhere.
```json
Pushed event: { "type": "file_changed", "file_id": "f_1", "new_version": 42, "changed_by_device": "dev_A" }
```

## Step 5: Data Model

**Metadata — relational (SQL) database, per `databases_fundamentals.md`**
Chosen because the file/folder hierarchy, ownership, and sharing permissions are
relational by nature (a folder contains files and folders; a share grants a user
access to a resource), require strong consistency (two devices must never see
diverging views of "what's the current version of this file"), and the write volume
here (metadata-only, chunk bytes excluded) is modest enough — tens of thousands of
ops/sec, not millions — that a well-sharded SQL tier handles it comfortably.
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
  chunk_hashes  JSON,          -- ordered array of chunk content-hashes
  size_bytes    BIGINT,
  created_at    TIMESTAMP,
  created_by_device VARCHAR(64),
  PRIMARY KEY (file_id, version)
);

CREATE TABLE shares (
  id            BIGINT PRIMARY KEY,
  resource_id   BIGINT,
  resource_type VARCHAR(10),   -- 'file' or 'folder'
  grantee_id    BIGINT,
  permission    VARCHAR(10)    -- 'read' or 'edit'
);
```
Sharded by `owner_id` (most access patterns — "list my files," "sync my changes" — are
scoped to one account), with shared-resource lookups resolved through the `shares`
table by a secondary index on `grantee_id`.

**Chunk content — object storage, per `storage_systems.md`**
Chosen because chunk bytes are large, immutable once written (a chunk is
content-addressed by its own hash, so it never needs an in-place update — a changed
chunk is just a new object with a new hash), accessed relatively infrequently compared
to metadata, and object storage is purpose-built for exactly this: cheap, durable,
massively horizontally scalable storage of opaque blobs, with no need for relational
query capability over the content itself.
```
Key:   chunks/{sha256_hash}
Value: raw chunk bytes (up to 4 MB), stored once regardless of how many files/users reference it
```
The content-addressing (key = hash of the value) is what makes both delta sync and
deduplication fall out almost for free: identical content, anywhere in the system,
always maps to the same key.

**Local client-side index — embedded key-value store (e.g., SQLite) on each device** —
tracks the last-synced chunk-hash list per local file, so the client can diff its own
state against the server without re-hashing files it hasn't touched.

## Step 6: Deep Dive

### 6.1 File chunking: the foundation of efficient sync

Splitting each file into fixed-size blocks (e.g., 4 MB) before upload is the single
idea that makes everything else in this system work. Consider editing one paragraph in
the middle of a 200 MB document: without chunking, any "file changed" detection forces
a re-upload of the entire 200 MB, because from the storage layer's point of view, "the
file" is one opaque blob and any byte changing invalidates the whole thing. With
chunking, the file is represented as an ordered list of chunk hashes — say, fifty 4 MB
chunks — and editing one paragraph only touches the byte ranges inside one or two of
those chunks. The client re-hashes all chunks (cheap — hashing is CPU-bound and fast
compared to network transfer), compares the new hash list to the previous one
positionally, finds that 48 of 50 hashes are unchanged, and only needs to upload the 1-2
chunks whose hash changed. The "file" itself, as tracked by the Metadata Service, is
never really "the file" at all — it's a versioned list of chunk-hash references,
similar in spirit to how a Git commit is a tree of content-addressed blobs rather than
a full copy of the repository.

A practical wrinkle: fixed-size chunking has an edge case where *inserting* a few bytes
near the start of a file shifts every subsequent byte offset, which can cascade a
change across every chunk boundary after the insertion point even though most of the
content didn't semantically change (this is the classic problem content-defined
chunking / rolling-hash chunk boundaries, as used by tools like rsync, are designed to
solve — worth mentioning as a refinement, but fixed-size chunking is the simpler
baseline design and is what's assumed elsewhere in this write-up).

### 6.2 Delta sync: chunking plus hashing equals "sync only what changed"

Delta sync is the direct application of 6.1 to the multi-device propagation problem.
When Device A commits a new file version (new chunk-hash list), Device B — notified via
the push channel (6.4) — doesn't blindly re-download the whole file. It fetches only
the new chunk-hash list from the Metadata Service (a small, cheap metadata read), diffs
it against its own last-known-synced list for that file, and downloads only the chunks
whose hash it doesn't already have locally (using the `POST /v1/chunks/check`-style
flow, or simply comparing lists directly since both sides already have them). This is
symmetric with the upload path in 6.1 — the same mechanism (content hash comparison)
drives both "what do I need to upload" and "what do I need to download," which is why
designing chunking correctly at the outset pays off on both sides of sync
simultaneously.

### 6.3 Separating metadata storage from block/content storage

This separation is what keeps common operations fast regardless of file size. Listing
a folder, renaming a file, or checking "has anything changed since I last synced" are
all pure metadata operations — they touch the Metadata Service's relational rows
(hundreds of bytes) and never need to look at, move, or even know the size of, the
actual chunk bytes sitting in object storage. If metadata and content were stored
together (e.g., a single "file blob" table holding both the file's attributes and its
raw bytes), listing a folder of a thousand large video files would mean the database
is at least indirectly entangled with gigabytes of content, and a rename would risk
touching large-object storage paths for no reason. By contrast, with the separation:
a rename is a single small UPDATE to `files.name`; a folder listing is an indexed query
over `files` rows, bounded by folder size, not file size; and the actual chunk data
in object storage is only ever touched when content — not metadata — needs to move.
This mirrors the same reasoning `databases_fundamentals.md` and `storage_systems.md`
give independently: use the database for what needs relational structure, indexing,
and transactional consistency, and use object storage for what needs to durably hold
large opaque bytes cheaply — combining them into one system optimizes neither well.

### 6.4 Conflict resolution: same file edited on two offline devices

If a user edits the same file on their laptop and phone while both are offline, then
both come back online, the two devices will each try to commit a new version built on
top of the *same* parent version — a genuine conflict, since neither device's edit
built on the other's. Two standard strategies:

- **Last-write-wins**: the server accepts whichever version commits first (by
  server-received timestamp), and the second device's commit is rejected or
  auto-merged if possible; the user on the losing device gets a warning that their
  version was overwritten. Simple to implement, but silently loses data from the
  user's perspective — acceptable for low-stakes files, risky for anything the user
  would consider important.
- **Conflicted copy**: the server detects the version conflict (the incoming commit's
  `parent_version` doesn't match the file's actual current version) and, instead of
  overwriting, saves the second device's version as a new file — e.g.,
  `report (conflicted copy, Device B, 2026-09-13).docx` — leaving both versions intact
  for the user to manually reconcile. This never loses data, at the cost of a
  sometimes-annoying UX (the user has to notice and merge the duplicate themselves).

The conflicted-copy approach is the one real systems like Dropbox actually ship,
because for a product whose core promise is "we will not lose your data," silently
discarding one device's edits (last-write-wins) directly contradicts that promise —
the trade-off of "the user has to manually clean up a conflicted copy sometimes" is
strictly preferable to "the system silently destroyed work with no warning."

### 6.5 Real-time change notification across a user's devices

Once a version is committed, the other devices need to find out *without* constantly
polling the Metadata Service ("has anything changed?" every few seconds, multiplied
across hundreds of millions of idle devices, would itself become a significant load
source for near-zero signal, most of the time nothing has changed). Instead, each
online device holds a long-lived connection to the Sync/Notification Service — a
lightweight push channel (WebSocket, or long-polling as a fallback for constrained
clients/networks, per the trade-offs in `networking_and_apis.md`'s real-time
communication comparison) — and the Metadata Service publishes a small "file X now has
version N" event on every commit. The Notification Service fans that event out only to
the affected user's other currently-connected devices (looked up by user_id — a small,
targeted fan-out, not a broadcast). A device that's offline when the event fires simply
misses the push and instead does a reconciliation sync (compare local state to server
state) the next time it reconnects — so the push channel is a latency optimization for
the common case (multiple devices online simultaneously), not a correctness
requirement, since the client always has a fallback poll/reconcile path for the
offline-then-reconnect case.

## Step 7: Bottlenecks & Trade-offs

- **Metadata Service is the first bottleneck under heavy small-edit workloads.** Users
  who keep files open and auto-saving frequently (e.g., every few seconds) generate a
  disproportionate share of version-commit traffic relative to their storage footprint.
  Mitigation: batch/debounce commits client-side (don't commit a new version on every
  keystroke, coalesce edits over a short window before syncing) rather than trying to
  scale the Metadata Service to absorb unbounded commit frequency.
- **Chunk-check round-trips add latency for many-small-file workloads.** A folder with
  thousands of tiny files (e.g., a code repository) means thousands of small
  metadata/chunk-check operations instead of one big transfer — the per-operation
  overhead dominates. Mitigation: batch chunk-existence checks and metadata commits
  across many small files into fewer, larger requests instead of one round-trip per
  file.
- **Global deduplication is a durability and privacy trade-off, not a free win.**
  Storing one copy of a chunk regardless of how many users reference it saves
  enormous storage cost, but it means a single corrupted/deleted chunk can affect many
  users' files at once (mitigated by very high replication durability in object
  storage) and requires careful reference counting so a chunk is only actually deleted
  from storage once no file version anywhere still references it.
- **Fixed-size chunking's boundary-shift problem** (6.1) means certain edit patterns
  (inserting bytes near the start of a large file) get worse delta-sync efficiency than
  the common case (appending, or editing near the end) — an accepted limitation of the
  simpler fixed-size scheme, addressable later with content-defined chunking if it
  becomes a measured problem.
- **Sharing introduces cross-shard metadata queries.** Metadata sharded by owner_id
  means a shared folder's access-control check for a non-owner grantee has to reach
  across shards; mitigated by the separate `shares` table with its own index on
  `grantee_id`, kept small relative to the main file tree, rather than trying to
  co-locate every possible grantee's data with every resource they've been granted
  access to.

## Follow-up Questions an Interviewer Might Ask

**"How would you support very large files, like 50 GB video files?"** The chunking
model already handles this naturally — a 50 GB file is just ~12,500 chunks at 4 MB
each; the interesting addition is parallel multi-chunk upload/download (fan out chunk
transfers across multiple concurrent connections) and resumability (if a transfer is
interrupted, only the not-yet-confirmed chunks need retrying, not the whole file).

**"How do you handle version history and storage growth from keeping every version?"**
Because versions are just ordered lists of chunk hashes, and unchanged chunks between
versions are literally the same stored object, keeping N versions of a file costs only
the chunks that actually changed across those versions, not N full copies — version
history is nearly free in storage terms thanks to the same content-addressing that
powers delta sync. Retention policy (e.g., keep all versions for 30 days, then thin
out to daily/weekly snapshots) trims the metadata list without touching shared chunks
still referenced elsewhere.

**"How would you prevent a malicious user from uploading a chunk that doesn't match
its claimed hash?"** The Block/Chunk Service recomputes the hash server-side on
receipt and rejects the upload if it doesn't match the claimed hash — never trust a
client-supplied hash as ground truth for what's about to be stored under that key,
since another user's download of that same hash later would silently receive corrupted
data otherwise.

**"How do you scale search (finding files by name/content) across this system?"** File
name search is a metadata-tier query (indexed by name/owner, per `databases_fundamentals.md`);
full-text content search requires a separate inverted-index pipeline (per
`search_and_indexing.md`) that asynchronously extracts and indexes text content from
supported file types after upload — explicitly decoupled from the sync path so
indexing latency never blocks a file being considered "synced."

**"What happens if two users are simultaneously editing a shared document?"** At the
file-storage layer described here, this degenerates to the same conflict scenario as
6.4 (two commits racing against the same parent version) unless the product also
offers real-time co-editing (Google-Docs-style), which is a fundamentally different
system — operational-transform or CRDT-based merging of concurrent edits at the
character level — worth naming as an explicit extension beyond this design's scope.

**"How would you estimate and control infrastructure cost as storage grows unbounded?"**
Tier storage by access recency — chunks belonging to files not accessed in a long
time move to cheaper, higher-latency cold storage classes, transparent to the user
except for a slower first-access after a long idle period — a standard object-storage
lifecycle policy layered on top of the same content-addressed chunk store.
