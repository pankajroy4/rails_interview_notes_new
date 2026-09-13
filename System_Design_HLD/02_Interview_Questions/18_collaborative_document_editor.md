# Design a Collaborative Document Editor

## Problem Statement

"Design a real-time collaborative document editor, like Google Docs. Multiple
users can open the same document at the same time, type into it simultaneously,
see each other's changes appear within a fraction of a second, and see live
cursors showing where their collaborators are working. The document must never end
up in a corrupted or inconsistent state, even when two people edit the exact same
word at the exact same instant."

This is one of the harder system design interview questions because the core
difficulty is not scale in the traditional sense (storage, QPS) but correctness
under concurrency: merging edits from many clients into one coherent document
without a central lock that would kill the "real-time" feel.

## Step 1: Clarify Requirements

**Functional Requirements**

- Multiple users can open and edit the same document concurrently.
- Edits from one user propagate to all other connected collaborators in near real
  time (sub-second).
- The system supports live presence: who is currently viewing the document, and
  where their cursor/selection currently is.
- Users can see a version history and revert to a prior version.
- Users can edit offline and have their changes reconciled when they reconnect.
- Basic document operations: insert text, delete text, formatting (bold/italic),
  and (stretch) embedded objects like images or comments.
- Access control: owner, editor, viewer permissions per document.

**Non-Functional Requirements**

- Low latency: a keystroke should appear on collaborators' screens in well under
  200ms under normal conditions.
- Strong eventual consistency: every replica (every open client, plus the server's
  stored copy) must converge to the identical document content once all operations
  have been delivered, regardless of the order edits arrived in.
- No lost updates: two simultaneous edits must both survive; the system must never
  silently drop one user's keystrokes in favor of another's.
- Availability over strict real-time ordering: a slow network for one user
  shouldn't block others from continuing to edit.
- Durability: once an edit is acknowledged, it must not be lost even if the server
  crashes immediately after.
- Scale target for estimation: a large collaborative editing product used inside
  enterprises and by consumers, e.g. hundreds of millions of documents, tens of
  millions of daily active editing sessions, with individual documents typically
  having a handful of concurrent editors (a small number of documents may spike to
  dozens).

## Step 2: Back-of-Envelope Estimation

**Assumptions**

- 50 million daily active users (DAU) who open at least one document per day.
- Of those, 10 million are actively *editing* (not just viewing) on a given day.
- An average editing session lasts 10 minutes and produces roughly 1
  keystroke/operation every 2 seconds during active typing (people pause to think,
  so not every second is a keystroke).
- Peak concurrency: assume 5% of daily editors are concurrently active at peak,
  i.e. 500,000 concurrent editing sessions.

**Operation throughput**

- Per concurrent session: 1 operation / 2 sec = 0.5 ops/sec.
- Peak aggregate operation rate: 500,000 sessions x 0.5 ops/sec = 250,000
  operations/sec system-wide.
- Each operation is tiny (an insert/delete of a few characters plus metadata: doc
  id, revision number, user id, timestamp) — roughly 100-200 bytes serialized. At
  250K ops/sec x 150 bytes = ~37.5 MB/sec of raw operation traffic at peak. This
  is easily handled by modern network and message-broker infrastructure, but it
  tells us the system must be built around many small, frequent messages, not a
  batch/request-response model.

**Fan-out (the real cost driver)**

- The expensive part isn't accepting operations, it's *broadcasting* them. If the
  average document has 3 concurrent editors, each operation must be pushed to 2
  other clients: 250,000 ops/sec x 2 = 500,000 outbound pushes/sec at peak.
- If a document has an outlier spike of 50 concurrent viewers (e.g. an all-hands
  doc), one operation fans out to 49 clients — this tells us we need per-document
  fan-out logic that scales independently of steady-state assumptions (see Step
  6).

**Storage**

- Storing the full operation log (not just snapshots) is central to this design
  (see Step 6). Assume the average document accumulates 5,000 operations over its
  lifetime (edits, formatting changes) at ~150 bytes each = 750 KB of
  operation-log data per actively-edited document.
- With, say, 500 million actively-edited documents in the system: 500M x 750 KB =
  375 PB if kept forever, uncompressed, at full granularity. In practice,
  operation logs are periodically compacted into snapshots (e.g. keep
  full-fidelity ops for the last 30 days for undo/version history, collapse older
  history into coarser snapshots), which cuts this by an order of magnitude or
  more. This estimation is what justifies compaction as a real design decision,
  not just a nice-to-have.

**Connections**

- 500,000 concurrent editing sessions, each holding a persistent WebSocket
  connection. A single well-tuned server can hold on the order of 50,000-100,000
  idle-ish WebSocket connections, so we need on the order of 5-10 dedicated
  WebSocket-gateway hosts at peak, before accounting for redundancy — a useful
  sanity check that this is a connection-management problem as much as a compute
  problem, same shape as the chat system in `09_chat_application.md`.

**Document Session Service sizing**

- Each actively-edited document needs its sequencing logic (OT transform or CRDT
  merge) resident somewhere. With 10 million daily editing sessions spread across,
  say, 4 million distinct actively-edited documents at any given moment (many
  sessions share a document), and a single moderately-provisioned host able to
  hold in-memory sequencing state and do transform work for roughly 5,000-10,000
  lightly-active documents concurrently, that implies on the order of 400-800
  Document Session Service hosts at steady state — again reinforcing that this
  tier scales primarily with *number of concurrently-edited documents*, not with
  total operation throughput, since the per-operation transform cost is tiny
  (microseconds) compared to the memory/bookkeeping cost of simply holding open
  state for many documents at once.
- This is a useful number to say out loud in an interview: it's a small-to-medium
  fleet, not a hyperscale one, because the working set that actually needs
  low-latency in-memory access (documents being edited *right now*) is a small
  fraction of the total document corpus (hundreds of millions) at any instant.

## Step 3: High-Level Design

Core components:

- **Client**: rich text editor (e.g. a browser-based editor) that applies local
  edits optimistically (the user sees their own keystroke instantly, before server
  confirmation) and maintains a queue of not-yet-acknowledged local operations.
- **WebSocket Gateway layer**: stateless-ish servers that hold the persistent
  connection per client, authenticate the session, and route operations to/from
  the correct document's session.
- **Document Session Service (the "room")**: for each actively-edited document,
  one logical owner process/shard responsible for receiving operations from all
  connected clients on that document, ordering them, running the transform/merge
  logic (OT or CRDT, see Step 6), and broadcasting the result back out. This is
  the sequencing point that makes concurrent edits converge to the same result
  everywhere.
- **Operation Log Store**: an append-only, durable log of every operation ever
  applied to a document — the source of truth, not the "current text" snapshot
  (see Step 6).
- **Snapshot/Materializer**: periodically folds the operation log into a
  materialized current-state snapshot so opening a document doesn't require
  replaying its entire history from operation #1.
- **Presence Service**: an ephemeral, in-memory pub/sub layer for cursor positions
  and "who's viewing" — deliberately separate from the durable operation log (see
  Step 6).
- **Metadata/Access-control store**: document ownership, sharing permissions,
  folder structure — a fairly standard relational store, separate from the editing
  hot path.

Data flow for a single keystroke:

1. User types a character. The client applies it locally immediately (optimistic
   UI) and sends an operation `{docId, baseRevision, op: insert("x", pos=42),
   clientOpId}` over its WebSocket connection.
2. The gateway routes the operation to the Document Session Service instance
   currently "owning" that document.
3. The session service assigns the operation the next server revision number,
   transforms it (if using OT) against any operations that were applied after the
   client's `baseRevision` but that the client hadn't seen yet, appends it to the
   durable operation log, and broadcasts the transformed operation to all other
   connected clients on that document.
4. Other clients receive and apply the operation to their local copy; the
   originating client receives an acknowledgment and reconciles its optimistic
   local state with the authoritative transformed version if they differ.

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

**Establish an editing session (WebSocket handshake)**
```
WS CONNECT /docs/{docId}/edit
  -> Auth token in connection headers
  <- { type: "init", revision: 4032, snapshot: "<current document content>", 
       activeUsers: [{userId, cursorPos, color}] }
```

**Submit an operation (client -> server, over the open socket)**
```
SEND { type: "op", docId, baseRevision: 4032, clientOpId: "uuid-abc",
       op: { type: "insert", pos: 128, text: "hello" } }
```

**Receive a broadcast operation (server -> all connected clients)**
```
PUSH { type: "op", docId, revision: 4033, appliedBy: "userA",
       op: { type: "insert", pos: 128, text: "hello" } }
```

**Presence update (client -> server, high frequency, no ack needed)**
```
SEND { type: "presence", docId, cursorPos: 130, selectionRange: [128,133] }
PUSH { type: "presence", docId, userId: "userB", cursorPos: 130, selectionRange: [128,133] }
```

**Fetch version history**
```
GET /docs/{docId}/history?limit=50&before=revision_4000
<- { versions: [{ revision, timestamp, author, summary }] }
```

**Revert to a prior version**
```
POST /docs/{docId}/revert { targetRevision: 3800 }
<- { newRevision: 4034 }   # implemented as a new forward operation, not a destructive rewrite
```

## Step 5: Data Model

**Operation log** (the source of truth — append-only, high write volume, needs
strict ordering per document): a wide-column or log-oriented store (e.g. Cassandra
keyed by docId with a clustering column of revision number, or a partitioned Kafka
topic per document-shard backed by a compacted log) is a good fit because writes
are append-only, reads are almost always "give me everything after revision N,"
and there's no need for cross-document joins.

```
operation_log (partition key: docId, clustering key: revision)
  docId          string
  revision       int64          -- monotonically increasing per document
  op_type        enum(insert, delete, format, ...)
  payload        json           -- position, text, formatting attrs
  author_id      string
  client_op_id   string         -- for idempotency / dedup on retry
  applied_at     timestamp
```

**Snapshot store** (materialized current content, for fast document load): a
document store (e.g. a blob store or a document-oriented DB) keyed by docId,
storing the latest folded content plus the revision number it represents.

```
snapshots
  docId              string (PK)
  revision           int64
  content            blob/text  -- current materialized document body
  last_compacted_at  timestamp
```

**Metadata / ACL** (standard relational needs: joins, permission checks, folder
hierarchies): a relational database (Postgres/MySQL) fits well here since this is
classic structured, transactional, low-volume-relative-to-edits data.

```
documents(id PK, title, owner_id, created_at, folder_id)
permissions(document_id FK, user_id FK, role enum(owner, editor, viewer))
```

**Presence** (ephemeral, never durably persisted the same way): an in-memory keyed
store (e.g. Redis with short TTLs, or a pure in-process pub/sub within the
Document Session Service) keyed by docId -> {userId: {cursorPos, color,
lastSeen}}, cleared on disconnect. No table in a durable database — see Step 6 for
why.

## Step 6: Deep Dive

### Merging concurrent edits: Operational Transformation vs CRDTs

This is the central problem of the whole system: two users, both starting from
revision 100 of a document, each submit an operation before either has seen the
other's. Naively applying both in whatever order they happen to arrive at the
server produces different results on different clients (or outright corrupts
positions — e.g. "insert at position 42" means something different after someone
else has already inserted 5 characters before position 42).

**Operational Transformation (OT)**: each operation carries the revision it was
based on. When the server (or a peer) receives an operation based on an older
revision than what's now current, it *transforms* that operation against every
operation that was applied in between, adjusting its parameters (e.g. shifting an
insert position forward by the length of an intervening insert that landed before
it) so that applying it now produces the same logical effect as if it had been
applied immediately, in order. This requires a central sequencing authority — in
our design, the Document Session Service — because the transform logic depends on
establishing one canonical order of operations to transform against. OT is
notoriously easy to get subtly wrong: the transform functions must satisfy strict
mathematical properties (commonly discussed as TP1/TP2 conditions) across every
pair of operation types (insert-insert, insert-delete, delete-delete,
formatting-vs-text-edit), and a single missed edge case can silently corrupt
documents in ways that only show up after many compounding edits. This is why
building OT correctly from scratch is a multi-year endeavor in practice, not
something to reimplement casually.

**CRDTs (Conflict-free Replicated Data Types)**: instead of transforming
operations against each other, the document itself is represented as a data
structure specifically designed so that concurrent updates commute — applying them
in any order, on any replica, converges to the same result with no central
transform step. A common approach for text is to give every character a unique,
stable identifier derived from causal history (e.g. a fractional position or a
tree of identifiers) rather than a raw numeric index, so an "insert after
character X" operation remains meaningful no matter what else has happened
concurrently, without needing to be rewritten. This makes CRDTs naturally
decentralized — any two replicas (including two offline clients) can merge
directly with each other, no server required for correctness — which is exactly
why they're popular for offline-first and peer-to-peer collaborative tools. The
cost is memory and metadata overhead: every character (or object) needs a durable
unique identifier and often tombstones for deleted content are kept around rather
than truly removed, so CRDT-backed documents can carry meaningfully more overhead
per character than the equivalent OT operation log, especially for long-lived,
heavily-edited documents.

**The real trade-off, stated plainly**: OT keeps per-operation overhead small and
is well suited to a design that already has a natural central server (which this
design does, for broadcast and durability anyway), but is very hard to implement
correctly. CRDTs are easier to reason about correctness-wise and shine when true
peer-to-peer or robust offline support is a first-class requirement, at the cost
of higher steady-state memory/storage overhead. Conceptually, Google Docs'
collaborative editing has historically been described as OT-based, consistent with
having a central authoritative server anyway; many newer collaborative editors
have adopted CRDT-based approaches (e.g. libraries built around CRDT text
structures) particularly where offline-first or local-first behavior is a
priority. Either choice is defensible in an interview as long as the trade-off is
articulated correctly.

**A worked OT example, to make the transform concrete.** Say the document is `"the
cat sat"` at revision 100. Two users act concurrently, both based on revision 100:

- Alice inserts `"black "` at position 4, intending `"the black cat sat"` —
  operation `insert(pos=4, "black ")`.
- Bob deletes the word `"cat"` (positions 4-7), intending `"the  sat"` — operation
  `delete(pos=4, len=3)`.

Both arrive at the server based on revision 100. The server picks an arrival order
— say Alice's operation is sequenced first, becoming revision 101, and is
broadcast as-is. Now Bob's operation must be transformed against Alice's before it
can be applied: Bob's original `delete(pos=4, len=3)` was written when position 4
meant "c" in "cat," but after Alice's insert, position 4 is now the start of
"black " — the "c" of "cat" has shifted to position 10. The transform function
shifts Bob's delete position forward by the length of Alice's insertion (6
characters) whenever the insertion occurred at or before the delete's position,
producing a transformed operation `delete(pos=10, len=3)`, which correctly deletes
"cat" from `"the black cat sat"` to produce `"the black  sat"` — the logically
correct merged result, matching what both users intended. If the transform had
naively applied Bob's untransformed `delete(pos=4, len=3)` after Alice's insert,
it would have deleted "blac" instead — a corrupted, unintended result. This single
example is also only one of the (insert, delete) transform cases; a real
implementation needs correct, symmetric transforms for every pairing of operation
types, which is the source of OT's implementation complexity.

### Testing correctness: convergence and fuzzing

Because a subtle OT transform bug (or a CRDT merge-function bug) can silently
corrupt a document without throwing any visible error — the document just slowly
diverges from what it "should" be — this system needs a different testing strategy
than typical CRUD correctness testing. The standard approach is **convergence
testing via randomized simulation**: generate large numbers of random concurrent
operation sequences against a simulated multi-client setup (varying network delay,
arrival order, and concurrency level), apply them through the transform/merge
logic in every possible delivery order, and assert that all replicas converge to
byte-identical final document state regardless of order — a property sometimes
checked directly against the formal transform properties (informally, that
transforming two concurrent operations against each other and applying them in
either order yields the same result). This kind of property-based fuzzing is run
continuously in CI for any serious OT or CRDT implementation, precisely because
hand-written unit tests for specific scenarios (like the Alice/Bob example above)
only cover the cases someone thought to write down, while random fuzzing surfaces
the edge cases nobody anticipated — three-way concurrent edits, edits interleaved
with formatting operations, operations arriving in unusual orders after a slow
reconnect. In an interview, naming this testing strategy specifically (not just
"we'd write tests") is a signal of having actually grappled with how hard OT/CRDT
correctness is to verify.

### Real-time propagation and connection routing

Every edit needs to reach every other currently-connected collaborator within a
fraction of a second. This is the identical "which gateway server is this user
connected to" problem discussed in `09_chat_application.md`: a client holds a
persistent WebSocket to one specific gateway instance, and an operation arriving
at the Document Session Service must be routed back out through *whichever*
gateway instances hold connections for the other collaborators on that document —
not just broadcast locally, since a horizontally scaled gateway layer means those
collaborators' sockets may be terminated on entirely different machines. The
standard solution is the same: the Document Session Service publishes the outbound
operation onto a pub/sub channel keyed by docId, and every gateway instance
subscribes to the channels for the documents it currently has connected clients
for, pushing to its local sockets on receipt. The additional wrinkle versus chat
is that document collaborators are a much smaller, tighter-knit group (typically
single digits) than a chat room can be, but the latency bar is stricter — a laggy
chat message is tolerable, a laggy keystroke breaks the illusion of "live" editing
— so this path is optimized hard for tail latency, often colocating the Document
Session Service and its hot documents' state in memory rather than round-tripping
to a database on every keystroke.

### Operation log as the source of truth, not just current-state snapshots

A naive design stores only "the current text" and overwrites it on every edit.
This design instead treats the append-only operation log as authoritative, with
the materialized snapshot as a derived, rebuildable cache — the same
event-sourcing pattern discussed in `10_message_queues_and_streaming.md`, applied
to document state instead of business events. This choice pays for itself in three
ways that a snapshot-only design can't easily provide:

- **Version history and undo/redo fall out for free.** "What did this document
  look like an hour ago" is just "replay the log up to the operation at that
  timestamp." Undo is "generate an inverse operation for the last operation this
  user applied," rather than needing separate undo-stack infrastructure.
- **Auditability**: who changed what, and when, is inherently preserved — useful
  both for user-facing "see edit history" features and for internal
  abuse/compliance investigation.
- **Reconciliation and recovery**: if a Document Session Service instance crashes
  mid-broadcast, the operation log is the durable checkpoint to recover from —
  replay from the last durably-written revision, nothing is lost, whereas a
  "current text" overwrite model has no way to recover an in-flight edit that was
  lost before it was durably written.

The trade-off is the storage growth discussed in Step 2, managed via periodic
compaction of old operations into coarser snapshots once fine-grained history is
no longer valuable (e.g. collapse anything older than 30 days into daily
snapshots, keep the raw log only for recent history).

### Presence is ephemeral by design

Live cursors and "who's currently viewing" information is broadcast the same way
document operations are, but deliberately is *not* written to the durable
operation log or any persistent database. The reasoning: presence information's
entire value is instantaneous — a cursor position from 5 seconds ago, let alone
from an hour ago, is meaningless once the user has moved their cursor again or
disconnected, and it changes far more frequently than actual content does
(mouse-move-driven cursor updates can be an order of magnitude more frequent than
keystrokes). Persisting it durably would mean paying storage and
write-amplification cost for data with a shelf life measured in seconds, and it
would need to be cleaned up constantly anyway. So presence lives purely in fast,
in-memory, TTL-based storage (Redis or in-process state in the Document Session
Service), gets broadcast over the same WebSocket transport as content operations
for a unified client protocol, and is simply dropped from that in-memory store on
disconnect (or after a short heartbeat timeout to handle ungraceful disconnects) —
no cleanup job, no durable record.

### Offline editing and reconciliation

A client that goes offline (network drop, closed laptop) keeps accepting local
edits and applying them optimistically, queuing the corresponding operations
locally instead of sending them. When it reconnects, it has a batch of local
operations based on some old `baseRevision`, and the server document has very
likely moved forward through many other operations from other collaborators in the
meantime. This is exactly the scenario that makes the OT-vs-CRDT choice matter
most in practice, not just in theory:

- Under **OT**, the reconnecting client's queued operations must each be
  transformed, in order, against the full sequence of operations that happened on
  the server since its `baseRevision` — the same transform logic used for
  real-time concurrent edits, just applied to a larger backlog at once. This is
  more operations to transform through, but it's the same code path, which is a
  point in favor of OT's simplicity of *mental model* even though implementing the
  transform functions themselves is hard.
- Under **CRDTs**, the reconnecting client simply merges its local CRDT state with
  the server's current CRDT state — the same merge operation used for any two
  divergent replicas, whether they diverged for 200 milliseconds (normal
  concurrent editing) or 2 hours (extended offline editing). There's no
  special-cased "catch-up" logic; offline reconciliation is not a distinct code
  path from ordinary real-time merging, which is precisely why CRDTs are often
  favored for products where offline support is a first-class, heavily-used
  requirement rather than an edge case.

Either way, the client's optimistic local view must be reconciled against the
authoritative merged result once the round-trip completes, and the UI needs to
handle the (hopefully rare, and ideally invisible) case where the
locally-displayed cursor position or selection shifts slightly as a result of the
merge.

## Step 7: Bottlenecks & Trade-offs

- **The Document Session Service is a natural single point of sequencing per
  document**, which is exactly what makes OT tractable, but it also means a single
  hot document (an all-hands doc being edited by 50 people at once) concentrates
  load on one logical shard. Mitigate by ensuring the sequencing service is
  lightweight (pure in-memory ordering and transform, not doing heavy I/O per
  operation) and that broadcast fan-out is handled by a separate pub/sub layer,
  not the sequencer itself.
- **Fan-out cost grows with concurrent viewers per document, not with total system
  scale**, which is a different scaling axis than most systems in this question
  bank — a system that comfortably handles 10 million total documents can still
  choke on one document with 500 simultaneous editors if fan-out isn't handled by
  an efficient pub/sub broadcast rather than looping over connections
  synchronously.
- **Operation log storage growth is unbounded without compaction** — the trade-off
  is between keeping full history forever (expensive, but enables arbitrarily
  fine-grained version history) versus compacting aggressively (cheaper, but
  coarsens old version history granularity). Most products compact based on age
  and document activity level.
- **OT correctness bugs are a long-tail risk**: a subtle transform bug might not
  manifest for months and then corrupt documents in a way that's hard to detect
  (the document "looks fine" but has silently diverged between clients) — this is
  a strong argument in interviews for either using a battle-tested OT/CRDT library
  rather than hand-rolling one, or leaning toward CRDTs specifically to sidestep
  this class of bug, trading it for the CRDT's own overhead trade-offs instead.
- **Consistency vs latency**: the design chooses to let clients apply edits
  optimistically before server acknowledgment, favoring perceived low latency over
  strict consistency at every instant — this is a deliberate trade-off (eventual
  consistency with reconciliation) rather than the alternative of waiting for a
  round-trip before showing the user their own keystroke, which would feel
  unacceptably laggy.

## Follow-up Questions an Interviewer Might Ask

**How would you handle rich formatting (bold, italic, embedded images), not just
plain text insert/delete?** Extend the operation types beyond text insert/delete
to include formatting-range operations and embedded-object operations, and extend
the transform functions (for OT) or the CRDT's data model (e.g. a tree structure
rather than a flat sequence) to cover interactions like "someone deletes text that
another user just bolded." This substantially increases the number of
operation-type pairs the transform logic must handle correctly, which is part of
why real editors' OT/CRDT implementations are large, mature codebases.

**How do you scale the Document Session Service itself if one document gets an
unusually large number of concurrent editors?** Since ordering must remain
centralized per document for correctness, true horizontal scaling of a single
document's sequencing isn't straightforward; the practical mitigation is making
that sequencing service extremely cheap per operation (pure in-memory, minimal
serialization) and pushing all the expensive work (durable log writes, broadcast
fan-out) to asynchronous paths downstream of the ordering decision, so the
sequencer's job stays small enough to handle very high per-document operation
rates.

**How would you implement comments/suggestions (Suggesting mode) on top of this
model?** Model a comment or suggested edit as its own operation type that
references a range of the document (via the same stable position/identifier scheme
used for text) without mutating the underlying content until accepted — this
reuses the existing operation log and real-time broadcast machinery rather than
requiring a parallel system.

**What happens if the Document Session Service crashes mid-session?** Since the
operation log is durably written before being broadcast (or the design otherwise
guarantees durability precedes acknowledgment), a new instance can take over the
document by reading the last durably-committed revision from the log and
rebuilding in-memory state from there; clients that had unacknowledged operations
in flight simply resend them, and the resend is safely idempotent because of the
`client_op_id` on each operation.

**How would you support very large documents (hundreds of pages) without the
client having to load and hold the entire operation log or content in memory?**
Lean on the snapshot/materializer: clients load the latest snapshot plus only the
operations since that snapshot's revision, and for extremely large documents,
consider viewport-based lazy loading of content sections, analogous to pagination,
while keeping the operation stream itself lightweight since individual operations
stay small regardless of total document size.

**How do you prevent malicious or buggy clients from corrupting the document for
everyone (e.g. sending malformed operations)?** Validate and sanitize every
incoming operation server-side before it's allowed into the authoritative log —
never trust client-supplied transformed state, only client-supplied intents
(insert this text at this position relative to this revision) that the server
itself sequences and applies, so a single bad client can at worst have its own
operations rejected, not corrupt the shared document state.
