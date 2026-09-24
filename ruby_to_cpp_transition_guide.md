# Ruby → C++ Transition Guide (for LeetCode Contests)

You already know C++ well — this isn't a C++ tutorial. It's a focused plan to get your
**STL muscle memory** back so you can move from Ruby to C++ on LeetCode without
losing time to syntax recall. Detailed STL syntax reference lives in
[cpp_stl_cheatsheet.cpp](cpp_stl_cheatsheet.cpp) — this file is the *study plan* and
the *Ruby → C++ mental map*.

Goal: **within 1–2 days, write LeetCode solutions in C++ as fluently as you do in Ruby.**

---

## 1. Priority order — what to revise first

| Priority | STL / Concept | Why |
|---|---|---|
| 🔥 Must know | `vector` | declaration, access, push_back, pop_back, size, sort |
| 🔥 Must know | `string` | indexing, substr, find, conversions |
| 🔥 Must know | `unordered_map` | frequency / hash-map problems |
| 🔥 Must know | `map` | ordered key-value |
| 🔥 Must know | `unordered_set` / `set` | membership + uniqueness |
| 🔥 Must know | `pair` | common with maps, priority queues, intervals |
| 🔥 Must know | `sort()` + custom comparator | almost every problem |
| 🔥 Must know | `stack` | monotonic stack problems |
| 🔥 Must know | `queue` | BFS |
| 🔥 Must know | `deque` | sliding window |
| 🔥 Must know | `priority_queue` | heap / Kth largest / top-K |
| 🔥 Must know | `lower_bound` / `upper_bound` | binary search |
| 2 — good to have | `min`, `max`, `reverse`, `swap`, `accumulate` | general algorithm helpers |
| 2 — good to have | lambdas | custom sorting / comparators |
| 2 — good to have | iterators | reading/writing STL code |
| 2 — good to have | `long long` | avoid integer overflow |
| 2 — good to have | `INT_MAX`, `LLONG_MAX` | initialization sentinels |
| 3 — occasional | `multiset`, `multimap` | less frequent |
| 3 — occasional | `tuple` | occasionally useful |

---

## 2. Ruby → C++ mental mapping

| Ruby | C++ |
|---|---|
| `Hash` | `unordered_map` / `map` |
| `Set` | `unordered_set` / `set` |
| `Array` | `vector` |
| Stack via `Array` (`push`/`pop`) | `stack` |
| Queue via `Array` (`push`/`shift`) | `queue` |
| `PriorityQueue` (gem) | `priority_queue` |
| `[a, b]` | `pair<int, int>` |
| `.sort` | `sort()` |
| `.bsearch` | `lower_bound()` / `upper_bound()` |

Example — Ruby frequency count:

```ruby
freq = Hash.new(0)
s.each_char { |ch| freq[ch] += 1 }
```

Equivalent C++:

```cpp
unordered_map<char, int> freq;
for (char ch : s) freq[ch]++;
```

That substitution — "which container replaces this Ruby idiom" — is the whole mental
shift. The algorithm you already know doesn't change; only the container syntax does.

---

## 3. Contest boilerplate

Use this on every LeetCode C++ submission so you never hunt for headers mid-contest:

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:

};
```

---

## 4. map vs unordered_map

| | `unordered_map` | `map` |
|---|---|---|
| Structure | hash table | balanced BST |
| Lookup | avg O(1) | O(log n) |
| Key order | not sorted | sorted automatically |
| Speed | usually faster | slower but ordered |

**Rule of thumb:**
- Need fast lookup only → `unordered_map`
- Need keys sorted / ordered iteration or range queries → `map`

Same logic applies to `set` vs `unordered_set`.

---

## 5. Things worth double-checking (common trip-ups coming from Ruby)

- `pq.pop()` / `st.pop()` / `q.pop()` do **not** return the popped element —
  read `top()`/`front()` first, then `pop()`.
- `priority_queue<int>` defaults to a **max-heap**. Min-heap needs
  `priority_queue<int, vector<int>, greater<int>>`.
- `lower_bound` → first element `>= x`. `upper_bound` → first element `> x`.
- `nums.size()` returns an unsigned type; using `int i = 0; i < nums.size()` is fine
  for contests, just be aware if you ever compare against a negative int.
- Sorting a `vector<pair<int,int>>` sorts by `first` ascending, then `second`
  ascending, automatically — no comparator needed unless you want different behavior.

---

## 6. Fast-track study plan

### Phase 1 (30 min) — core containers
`vector`, `string`, `pair`, `sort`, `reverse`, `min`/`max`

### Phase 2 (30 min) — maps & sets
`unordered_map`, `map`, `unordered_set`, `set`

### Phase 3 (30 min) — LIFO/FIFO/heap
`stack`, `queue`, `deque`, `priority_queue`

### Phase 4 (30 min) — search & syntax
`lower_bound`, `upper_bound`, `binary_search`, lambdas, iterators

### Phase 5 — practice by porting, not solving new problems
Take problems you've already solved in Ruby and rewrite them in C++. This isolates
the STL syntax as the only new variable — the algorithm is already proven correct in
your head, so all your attention goes to the C++/STL side.

Good candidates to port first:
- Two Sum
- Valid Anagram
- Palindrome
- Move Zeroes
- Merge Intervals
- Insert Interval
- Next Permutation
- Longest Substring Without Repeating Characters
- KMP / strStr

---

## 7. Reference

For full STL syntax (vector/map/set/stack/queue/priority_queue/algorithm functions,
bit tricks, complexity table, gotchas), see
[cpp_stl_cheatsheet.cpp](cpp_stl_cheatsheet.cpp).
