# Design an LRU Cache (Object-Oriented Design)

## Problem Statement

"Design an LRU (Least Recently Used) cache with `get(key)` and
`put(key, value)`, both O(1). When the cache is at capacity and a new key
comes in, evict the least recently used entry first."

Stop here for a second, because this exact sentence is also a classic
**data-structures/algorithms** question — `dsa.rb` in this same repo already
covers the algorithmic core of this problem under its "13. DESIGN PROBLEMS"
section (hash map + doubly linked list, O(1) get/put). If you're asked this
in a DSA round, the goal is "get me a correct, O(1) implementation, fast."
That is NOT what this file is about. Asked in an **LLD/OOD round**, the bar
is different: the interviewer already assumes you can write the hash-map +
linked-list mechanics. What they're actually testing is whether your class
boundaries are clean — specifically, whether "LRU" is hard-wired into your
cache's core logic, or whether the eviction *policy* is a pluggable
component you could swap for LFU or FIFO without touching `get`/`put` at
all. That distinction — mechanics vs. policy — is the entire point of this
file.

## Step 1: Clarify Requirements

**Functional Requirements**
- `get(key)`: return the value for `key` if present, and mark it as most
  recently used; return a sentinel (e.g. `nil` or `-1`, clarify with the
  interviewer) if absent.
- `put(key, value)`: insert or update `key`. If the cache is at capacity and
  `key` is new, evict the least recently used entry first.
- Fixed capacity, set at construction time.
- Both operations must be O(1) time.

**Non-Functional Requirements**
- **O(1) time for both operations** — this is the constraint that forces
  the hash-map + doubly-linked-list combination; no single data structure
  alone gets you there (see Step 4).
- **Swappable eviction policy**: the interviewer's natural follow-up is
  "now make it LFU" or "now make it FIFO" — a design where that requires
  rewriting `get`/`put` has failed the *design* portion of this question
  even if the original LRU code was correct.
- **O(1) auxiliary space per entry** — no scanning structures whose size
  grows with history length.

## Step 2: Identify Core Objects / Entities

- **Node** — one doubly-linked-list node: `key`, `value`, `prev`, `next`.
  Storing `key` on the node (not just `value`) is the detail people forget —
  when you evict the tail node, you need its key to also delete it from the
  hash map, and without the key on the node you'd have no O(1) way to find
  it.
- **EvictionPolicy** (interface) — decides *which* key to evict next and
  *when* a key counts as "used." `LRUPolicy` is the default implementation;
  `LFUPolicy`/`FIFOPolicy` are alternate implementations behind the same
  interface.
- **Cache** — orchestrates: owns the hash map (`key -> Node`), owns the
  doubly linked list (via sentinel head/tail nodes), and delegates
  "what to evict" / "how to record usage" to its `EvictionPolicy`, rather
  than deciding that itself.

## Step 3: Identify Relationships (Class Diagram)

```text
  Node
  - key, value
  - prev ---> Node|nil
  - next ---> Node|nil

  EvictionPolicy (interface)              LRUPolicy
  + on_access(key)          [abstract]    (move node to front of order)
  + on_insert(key)          [abstract]        implements
  + key_to_evict() : key    [abstract]  <-------------------  EvictionPolicy
                                                                    ^
                                                          also implemented by
                                                        LFUPolicy, FIFOPolicy

  Cache
  - capacity: Integer
  - map: { key => Node }                  (composition: owns every Node)
  - head, tail: Node        (sentinels, doubly linked list ordering)
  - policy: EvictionPolicy  ---uses-a---> EvictionPolicy
  + get(key) : value|nil
  + put(key, value)
  - evict!()
  - move_to_front(node) / append(node) / remove(node)   [list primitives]
```

Relationship types:
- `Cache` **composes** `Node`s — nodes have no existence or identity outside
  their owning cache (composition).
- `Cache` **uses-a** `EvictionPolicy` via dependency injection — this is
  association, and specifically the **Strategy pattern**: `Cache` is
  coded against the `EvictionPolicy` interface, never against `LRUPolicy`
  concretely, so any object satisfying the interface can be swapped in at
  construction time.
- `LRUPolicy`/`LFUPolicy`/`FIFOPolicy` **implement** `EvictionPolicy`
  (interface implementation, not class inheritance — in Ruby this is a
  duck-typing contract, optionally documented with a module).

## Step 4: Design Decisions & Patterns Used

**Why hash map AND doubly linked list — neither alone is enough.** A hash
map alone gives O(1) lookup by key, but has no concept of "which entry was
used least recently" — finding that requires scanning, O(n). A doubly
linked list alone gives O(1) reordering (splice a node to the front) once
you already have a reference to it, but finding *that node* by key is
O(n) list traversal. Composing them fixes both: the hash map gives O(1)
"find the node for this key," and the linked list gives O(1) "move this
node to the most-recently-used end" and O(1) "evict the node at the
least-recently-used end." This is the mechanical half of the problem, and
it's identical to what `dsa.rb`'s Design Problems section covers — nothing
new here, it's table stakes to even start the LLD discussion.

**Why `EvictionPolicy` is pulled out as a Strategy instead of being
`Cache`'s own logic.** The naive design bakes "move accessed node to head
of list, evict from tail" directly into `Cache#get` and `Cache#put`. That
works for LRU specifically, but the moment the interviewer says "now make
it LFU" (evict least *frequently* used, which needs a frequency counter,
not recency order) or "now make it FIFO" (evict oldest *inserted*,
ignoring access pattern entirely), you're rewriting `Cache`'s core methods
— which is exactly the kind of rigidity an LLD interviewer is probing for.
Pulling eviction decisions behind an `EvictionPolicy` interface means
`Cache#get`/`#put` only ever say "policy, record this access" and "policy,
who should I evict" — they never encode what "least recently used" means.
Swapping `LRUPolicy.new` for `LFUPolicy.new` at construction time is then
a one-line change with zero edits to `Cache` itself. This is the central
teaching point of this file: **the DSA version of this question rewards
getting the O(1) mechanics right; the OOD version rewards not coupling
those mechanics to one specific eviction rule.**

**Why sentinel head/tail nodes instead of nil-checking every edge.**
Without dummy head/tail nodes, every insert/remove needs special-case
branches for "list is empty," "removing the only node," "inserting into an
empty list." Two permanent sentinel nodes (`head.next` starts as `tail`,
`tail.prev` starts as `head`) mean every real node always has a real `prev`
and `next` to relink against — the list is never truly "empty" from the
splice logic's point of view, which deletes an entire class of edge-case
bugs.

## Step 5: Code

```ruby
class Node
  attr_accessor :key, :value, :prev, :next

  def initialize(key = nil, value = nil)
    @key = key
    @value = value
    @prev = nil
    @next = nil
  end
end

class LRUCache
  def initialize(capacity)
    raise ArgumentError, "capacity must be positive" if capacity < 1

    @capacity = capacity
    @map = {}                # key => Node, O(1) lookup
    @head = Node.new         # sentinel: @head.next is the most-recently-used
    @tail = Node.new         # sentinel: @tail.prev is the least-recently-used
    @head.next = @tail
    @tail.prev = @head
  end

  def get(key)
    node = @map[key]
    return nil unless node

    move_to_front(node)
    node.value
  end

  def put(key, value)
    if (node = @map[key])
      node.value = value
      move_to_front(node)
      return
    end

    evict! if @map.size >= @capacity

    node = Node.new(key, value)
    @map[key] = node
    insert_at_front(node)
  end

  private

  # Detach `node` from wherever it sits in the list, then splice it in
  # right after @head — i.e., mark it most-recently-used.
  def move_to_front(node)
    detach(node)
    insert_at_front(node)
  end

  def insert_at_front(node)
    node.prev = @head
    node.next = @head.next
    @head.next.prev = node
    @head.next = node
  end

  def detach(node)
    node.prev.next = node.next
    node.next.prev = node.prev
  end

  # Least-recently-used is always @tail.prev — the node right before the
  # tail sentinel — because every access/insert moves its node to the front.
  def evict!
    lru = @tail.prev
    return if lru == @head # cache is empty

    detach(lru)
    @map.delete(lru.key)
  end
end
```

**Sketch of the `EvictionPolicy` extraction** (not a full second
implementation — just enough to show the seam where LFU/FIFO would plug in):

```ruby
# Cache delegates two questions to the policy: "record that `key` was just
# touched" and "which key should die next." Cache never knows *why*.
module EvictionPolicy
  def on_access(key); raise NotImplementedError; end
  def on_insert(key); raise NotImplementedError; end
  def key_to_evict;   raise NotImplementedError; end
end

# The LRUCache above, with policy pulled out, would inject one of these:
class LRUPolicy
  include EvictionPolicy
  # on_access/on_insert both mean "move to front of an internal order";
  # key_to_evict reads the tail — exactly the list logic already shown above.
end

class LFUPolicy
  include EvictionPolicy
  # tracks a frequency counter per key instead of recency order;
  # key_to_evict returns the key with the lowest count (ties broken by
  # insertion order, typically) — no linked-list splicing needed at all.
end

class FIFOPolicy
  include EvictionPolicy
  # on_access is a no-op (FIFO ignores access pattern entirely);
  # on_insert enqueues; key_to_evict dequeues — simplest of the three.
end
```

The interview-winning line to say out loud: "`Cache#get` and `Cache#put`
would only ever call `policy.on_access(key)` and `policy.key_to_evict`; the
data structure each policy uses internally to answer those — a linked list
for LRU, a frequency table for LFU, a plain queue for FIFO — is that
policy's private concern, not `Cache`'s."

## Step 6: Edge Cases & Extensibility

- **`get` on a key that doesn't exist**: return `nil` (or the agreed
  sentinel) without touching the list — a miss must not count as a "use."
- **`put` on a key that already exists**: update the value AND move it to
  most-recently-used — a common bug is updating the value but forgetting
  the reorder, which silently breaks eviction order over time.
- **`put` of a brand-new key when at capacity**: evict the LRU entry
  *before* inserting the new node, not after — inserting first would
  transiently exceed capacity and risk evicting the just-inserted node if
  the eviction check is off by one.
- **Capacity of 1**: every `put` of a new key evicts the sole existing
  entry; `get` immediately after a `put` of the same key must still hit.
  This is a good one to trace through by hand on the whiteboard — it
  exercises the sentinel-node splicing with the smallest possible list.
- **Capacity of 0**: arguably invalid input — reject it in the constructor
  (as the code above does) rather than silently making every `put` a no-op
  eviction; state this assumption out loud.
- **Adding a second cache instance with a different policy**: because
  `EvictionPolicy` is injected, not hard-coded, `LRUCache.new(2,
  policy: LFUPolicy.new)` (once the extraction is done) requires no change
  to `Cache` — this is the payoff of Step 4's design decision, made
  concrete.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you make this thread-safe for concurrent access?"** Wrap
   mutating operations in a `Mutex#synchronize` — but note that locking
   each of `get` and `put` individually isn't automatically sufficient for
   compound sequences: a caller doing "check if key exists, then decide
   whether to `put`" across two separate lock acquisitions still has a
   race window between them (another thread's `put` can land in between).
   The fix is exposing a single atomic method for compound operations
   (e.g. `get_or_put(key) { computed_value }`) that holds the lock for the
   whole sequence, rather than trusting callers to compose two atomic calls
   safely.
2. **"How would you add TTL-based expiry on top of LRU eviction?"** Store
   an `expires_at` timestamp on each `Node` and treat expiry as a second,
   independent eviction trigger: `get` checks `expires_at` first and treats
   an expired entry as a miss (and evicts it), while capacity-based LRU
   eviction keeps working unchanged. The two triggers don't need to know
   about each other — a node can die from either one, whichever fires
   first — which is only clean because eviction was already pulled out from
   `get`/`put`'s core logic in Step 4.
3. **"Now make it LFU instead."** This is answered directly by Step 4/5:
   swap the injected `EvictionPolicy` from `LRUPolicy.new` to
   `LFUPolicy.new`; zero changes to `Cache#get`/`#put`. If your original
   design didn't have this seam, this question is where it gets exposed.
4. **"What if two keys should never evict each other" (e.g., pinned
   entries)?** Add a `pinned?` flag the policy checks before choosing
   `key_to_evict` — the policy's job absorbs this rule cleanly since it
   already owns "which key dies next."
5. **"How would this look at scale, across multiple servers sharing one
   logical cache?"** That's a distinct HLD problem — see
   `System_Design/02_Interview_Questions/06_distributed_cache.md` for the
   deep dive on sharding, consistent hashing, and cache invalidation across
   nodes. Naming this boundary explicitly — "this file is single-process
   LRU; a distributed cache is a different set of trade-offs" — is itself a
   signal that you know where LLD ends and HLD begins.
6. **"Why not just use Ruby's `Hash`, which preserves insertion order?"**
   A plain `Hash` preserves *insertion* order, not *access* order — `h[k]`
   doesn't reorder `k` to the end, so it can't express "least recently
   used" without extra bookkeeping, and re-inserting a key to fake reorder
   is O(1) amortized but muddies the code's intent versus an explicit
   linked list. It's a reasonable optimization to mention, but the
   interviewer usually wants to see the explicit data structures, since
   that's what demonstrates you understand *why* O(1) is achievable at all.
