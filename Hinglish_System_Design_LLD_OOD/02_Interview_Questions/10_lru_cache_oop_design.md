# Design an LRU Cache (Object-Oriented Design)

## Problem Statement

"Design an LRU (Least Recently Used) cache with `get(key)` and
`put(key, value)`, both O(1). Jab cache capacity par ho aur naya key aaye,
toh least recently used entry ko sabse pehle evict karo."

Ek second yahan ruk jao, kyunki yahi exact sentence ek classic
**data-structures/algorithms** question bhi hai — `dsa.rb` isi repo mein is
problem ka algorithmic core already cover karta hai apne "13. DESIGN
PROBLEMS" section mein (hash map + doubly linked list, O(1) get/put). Agar
yeh aapko DSA round mein poocha jaaye, toh goal hai "mujhe ek correct, O(1)
implementation chahiye, fast." Yeh file us baare mein NAHI hai. **LLD/OOD
round** mein poochne par, bar different hota hai — interviewer already yeh
assume karta hai ki aap hash-map + linked-list mechanics likh sakte ho. Woh
actually yeh test kar rahe hain ki aapki class boundaries clean hain ya
nahi — specifically, "LRU" aapke cache ki core logic mein hard-wired hai ya
eviction *policy* ek pluggable component hai jise aap LFU ya FIFO ke liye
`get`/`put` ko touch kiye bina swap kar sakte ho. Yeh distinction — mechanics
vs. policy — hi is file ka poora point hai.

## Step 1: Clarify Requirements

**Functional Requirements**
- `get(key)`: agar `key` present hai toh uska value return karo, aur usko
  most recently used mark karo; agar absent hai toh ek sentinel return karo
  (jaise `nil` ya `-1`, interviewer se clarify karo).
- `put(key, value)`: `key` ko insert ya update karo. Agar cache capacity par
  hai aur `key` naya hai, toh sabse pehle least recently used entry ko
  evict karo.
- Fixed capacity, construction time par set hoti hai.
- Dono operations O(1) time mein hone chahiye.

**Non-Functional Requirements**
- **Dono operations ke liye O(1) time** — yeh constraint hi hash-map +
  doubly-linked-list combination force karta hai; akeli koi bhi data
  structure yeh guarantee nahi de sakti (Step 4 dekho).
- **Swappable eviction policy**: interviewer ka natural follow-up hoga "ab
  ise LFU bana do" ya "ab ise FIFO bana do" — agar design mein yeh
  `get`/`put` rewrite karne ki demand kare, toh us design ne is question ke
  *design* portion mein fail kar diya hai, chahe original LRU code correct
  hi kyun na ho.
- **Har entry ke liye O(1) auxiliary space** — koi bhi scanning structure
  nahi jiska size history length ke saath badhta jaaye.

## Step 2: Identify Core Objects / Entities

- **Node** — ek doubly-linked-list node: `key`, `value`, `prev`, `next`.
  `key` ko node par store karna (sirf `value` nahi) woh detail hai jo log
  bhool jaate hain — jab aap tail node evict karte ho, toh usse hash map se
  bhi delete karne ke liye uska key chahiye hota hai, aur agar node par key
  na ho toh usse O(1) mein dhoondhne ka koi tareeka nahi hoga.
- **EvictionPolicy** (interface) — decide karta hai ki agla *kaunsa* key
  evict hoga aur *kab* ek key "used" count hoti hai. `LRUPolicy` default
  implementation hai; `LFUPolicy`/`FIFOPolicy` isi interface ke peeche
  alternate implementations hain.
- **Cache** — orchestrate karta hai: hash map ka owner hai (`key -> Node`),
  doubly linked list ka owner hai (sentinel head/tail nodes ke through),
  aur "kya evict karna hai" / "usage kaise record karna hai" yeh decide
  karna apni `EvictionPolicy` ko delegate karta hai, khud decide nahi
  karta.

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
- `Cache` **composes** `Node`s — nodes ka koi existence ya identity apni
  owning cache ke bahar nahi hota (composition).
- `Cache` **uses-a** `EvictionPolicy` dependency injection ke through — yeh
  association hai, aur specifically **Strategy pattern** hai: `Cache`
  `EvictionPolicy` interface ke against code hota hai, kabhi bhi `LRUPolicy`
  ke against concretely nahi, isliye construction time par interface
  satisfy karne wala koi bhi object swap kiya ja sakta hai.
- `LRUPolicy`/`LFUPolicy`/`FIFOPolicy` `EvictionPolicy` ko **implement**
  karte hain (interface implementation, class inheritance nahi — Ruby mein
  yeh ek duck-typing contract hai, optionally ek module ke saath documented).

## Step 4: Design Decisions & Patterns Used

**Hash map AUR doubly linked list kyun — akela koi bhi kaafi nahi.** Ek hash
map akela O(1) lookup by key deta hai, lekin usme "kaunsi entry least
recently use hui" jaisa koi concept nahi hota — woh dhoondhna scanning
maangega, O(n). Ek doubly linked list akela O(1) reordering deta hai (ek
node ko front mein splice karna) agar aapke paas uska reference already ho,
lekin key se *woh node* dhoondhna O(n) list traversal hai. In dono ko
compose karna dono problems fix karta hai: hash map O(1) "is key ke liye
node dhoondho" deta hai, aur linked list O(1) "is node ko most-recently-used
end par le jao" aur O(1) "least-recently-used end par jo node hai usse
evict karo" deta hai. Yeh problem ka mechanical half hai, aur yeh bilkul
wahi hai jo `dsa.rb` ka Design Problems section cover karta hai — yahan
kuch naya nahi, LLD discussion start karne ke liye yeh table stakes hai.

**`EvictionPolicy` ko `Cache` ki apni logic banane ke bajaye ek Strategy
ke roop mein kyun pull out kiya.** Naive design "accessed node ko list ke
head par move karo, tail se evict karo" seedha `Cache#get` aur `Cache#put`
mein bake kar deta hai. Yeh specifically LRU ke liye kaam karta hai, lekin
jaise hi interviewer bolta hai "ab isse LFU bana do" (least *frequently*
used evict karo, jisko recency order nahi ek frequency counter chahiye) ya
"ab isse FIFO bana do" (sabse purana *inserted* evict karo, access pattern
ko poora ignore karke), toh aap `Cache` ke core methods rewrite kar rahe ho
— jo exactly wahi rigidity hai jo ek LLD interviewer probe kar raha hota
hai. Eviction decisions ko `EvictionPolicy` interface ke peeche pull karne
ka matlab hai ki `Cache#get`/`#put` sirf itna hi kehte hain "policy, is
access ko record karo" aur "policy, mujhe kisko evict karna chahiye" — woh
kabhi encode nahi karte ki "least recently used" ka matlab kya hai.
Construction time par `LRUPolicy.new` ko `LFUPolicy.new` se swap karna phir
ek one-line change ban jaata hai, `Cache` mein zero edits ke saath. Yahi is
file ka central teaching point hai: **is question ka DSA version O(1)
mechanics sahi karne ko reward karta hai; OOD version un mechanics ko ek
specific eviction rule se couple na karne ko reward karta hai.**

**Sentinel head/tail nodes kyun, har edge case ke liye nil-check karne ke
bajaye.** Dummy head/tail nodes ke bina, har insert/remove ko "list empty
hai," "sirf ek node remove ho raha hai," "empty list mein insert ho raha
hai" jaise special-case branches chahiye hote hain. Do permanent sentinel
nodes (`head.next` start hota hai `tail` se, `tail.prev` start hota hai
`head` se) ka matlab hai ki har real node ke paas hamesha ek real `prev`
aur `next` hote hain jinke against woh relink kar sake — list splice
logic ke perspective se kabhi truly "empty" nahi hoti, jo edge-case bugs
ki ek poori class delete kar deta hai.

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

**`EvictionPolicy` extraction ka sketch** (poora doosra implementation
nahi — bas itna dikhane ke liye ki LFU/FIFO kahan plug in hongi):

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

Interview jeetne wali line jo zubaan se bolni chahiye: "`Cache#get` aur
`Cache#put` sirf `policy.on_access(key)` aur `policy.key_to_evict` call
karenge; har policy internally in sawaalon ka jawab dene ke liye jo data
structure use karti hai — LRU ke liye ek linked list, LFU ke liye ek
frequency table, FIFO ke liye ek plain queue — woh us policy ka private
concern hai, `Cache` ka nahi."

## Step 6: Edge Cases & Extensibility

- **`get` ek aise key par jo exist nahi karta**: `nil` (ya agreed sentinel)
  return karo bina list ko touch kiye — ek miss ko "use" count nahi karna
  chahiye.
- **`put` ek aise key par jo already exist karta hai**: value update karo
  AUR usse most-recently-used move karo — ek common bug value update karna
  hai lekin reorder bhool jaana, jo silently eviction order ko time ke
  saath break kar deta hai.
- **`put` ek bilkul naye key ka jab capacity par ho**: LRU entry ko naye
  node insert karne *se pehle* evict karo, baad mein nahi — pehle insert
  karne se transiently capacity exceed ho jaayegi aur risk hoga ki abhi
  insert kiya gaya node hi evict ho jaaye agar eviction check off-by-one
  ho.
- **Capacity 1**: naye key ka har `put` sole existing entry ko evict kar
  deta hai; usi key ka `put` karne ke turant baad `get` phir bhi hit hona
  chahiye. Yeh whiteboard par haath se trace karne ke liye achha case hai —
  yeh sentinel-node splicing ko smallest possible list ke saath exercise
  karta hai.
- **Capacity 0**: arguably invalid input hai — constructor mein isse
  reject karo (jaise upar ke code mein hua hai) na ki silently har `put` ko
  ek no-op eviction bana do; yeh assumption zubaan se bolo.
- **Ek doosra cache instance different policy ke saath add karna**: kyunki
  `EvictionPolicy` inject hoti hai, hard-code nahi, `LRUCache.new(2,
  policy: LFUPolicy.new)` (jab extraction ho chuki ho) ke liye `Cache` mein
  koi change nahi chahiye — yahi Step 4 ke design decision ka payoff hai,
  concrete form mein.

## Follow-up Questions an Interviewer Might Ask

1. **"Isse concurrent access ke liye thread-safe kaise banaoge?"** Mutating
   operations ko `Mutex#synchronize` mein wrap karo — lekin note karo ki
   `get` aur `put` ko individually lock karna compound sequences ke liye
   automatically sufficient nahi hai: ek caller jo "check karo key exist
   karta hai ya nahi, phir decide karo `put` karna hai ya nahi" do alag lock
   acquisitions ke through kar raha hai, unke beech mein ek race window
   reh jaata hai (doosre thread ka `put` beech mein aa sakta hai). Fix hai
   compound operations ke liye ek single atomic method expose karna (jaise
   `get_or_put(key) { computed_value }`) jo poori sequence ke liye lock
   hold kare, callers par bharosa karne ke bajaye ki woh do atomic calls
   ko safely compose kar lenge.
2. **"LRU eviction ke upar TTL-based expiry kaise add karoge?"** Har `Node`
   par ek `expires_at` timestamp store karo aur expiry ko ek second,
   independent eviction trigger ki tarah treat karo: `get` pehle
   `expires_at` check karta hai aur expired entry ko miss treat karta hai
   (aur usse evict karta hai), jabki capacity-based LRU eviction unchanged
   kaam karta rehta hai. In dono triggers ko ek doosre ke baare mein jaanne
   ki zaroorat nahi — ek node kisi bhi ek se mar sakta hai, jo bhi pehle
   fire ho — aur yeh sirf isliye clean hai kyunki eviction Step 4 mein
   already `get`/`put` ki core logic se pull out ho chuka tha.
3. **"Ab isse LFU bana do."** Yeh directly Step 4/5 se answer hota hai:
   injected `EvictionPolicy` ko `LRUPolicy.new` se `LFUPolicy.new` mein
   swap karo; `Cache#get`/`#put` mein zero changes. Agar aapke original
   design mein yeh seam nahi thi, toh yahi wahan hai jahan woh expose ho
   jaati hai.
4. **"Agar do keys ek doosre ko kabhi evict nahi karna chahiye" (jaise,
   pinned entries)?** Ek `pinned?` flag add karo jo policy `key_to_evict`
   choose karne se pehle check kare — policy ka job yeh rule cleanly
   absorb kar leta hai kyunki woh already "agla kaunsa key marega" own
   karta hai.
5. **"Yeh scale par kaisa dikhega, multiple servers ke across ek logical
   cache share karte hue?"** Yeh ek alag HLD problem hai — sharding,
   consistent hashing, aur nodes ke across cache invalidation par deep dive
   ke liye `System_Design/02_Interview_Questions/06_distributed_cache.md`
   dekho. Is boundary ko explicitly naam dena — "yeh file single-process
   LRU hai; distributed cache ek alag set of trade-offs hai" — khud ek
   signal hai ki aapko pata hai LLD kahan khatam hoti hai aur HLD kahan
   shuru hoti hai.
6. **"Ruby ke `Hash` ka use kyun nahi karte, jo insertion order preserve
   karta hai?"** Ek plain `Hash` *insertion* order preserve karta hai,
   *access* order nahi — `h[k]` `k` ko end mein reorder nahi karta, isliye
   extra bookkeeping ke bina "least recently used" express nahi kar sakta,
   aur reorder fake karne ke liye ek key ko re-insert karna O(1) amortized
   hai lekin explicit linked list ke against code ke intent ko muddy karta
   hai. Yeh mention karne layak ek reasonable optimization hai, lekin
   interviewer usually explicit data structures dekhna chahta hai, kyunki
   yahi demonstrate karta hai ki aap samajhte ho O(1) *kyun* achievable hai.
