/*
===============================================================================================
                       DSA in JAVASCRIPT  (patterns + REAL solutions)
===============================================================================================
(Mirrors my dsa.rb + DSA_problem_solving.rb — but in JavaScript, because live-coding rounds use
the language of the role. Same patterns, same problems I solved in Ruby, re-solved in JS with the
JS idioms. Re-solve each after 1 day / 3 days / 7 days for retention.)
*/

/*
-----------------------------------------------------------------------------------------------
JAVASCRIPT DSA TOOLKIT (the Ruby->JS translation that trips people up live)
-----------------------------------------------------------------------------------------------
  RUBY                          JAVASCRIPT
  ---------------------------   --------------------------------------------------
  hash = {}                     const map = new Map();  // for algos use Map, not {}
  hash[k] = v / hash[k]         map.set(k, v) / map.get(k)
  hash.key?(k)                  map.has(k)
  arr.each_with_index           arr.forEach((x, i) => ...) / for (const [i,x] of arr.entries())
  arr.length / arr.size         arr.length
  arr.sort                      arr.sort((a,b) => a-b)   // DEFAULT sort is LEXICOGRAPHIC! must pass comparator
  arr.max / arr.min             Math.max(...arr) / Math.min(...arr)
  arr.push / arr.pop            arr.push / arr.pop        // pop = stack top (end)
  arr.shift / arr.unshift       same                       // shift = queue front (slow O(n))
  Set.new                       new Set()                  // .add/.has/.delete, .size
  (0...k).each                  for (let i = 0; i < k; i++)
  string.chars                  [...str] or str.split('')

  GOTCHAS:
   - Default Array.sort is STRING sort: [10,2,1].sort() -> [1,10,2]. ALWAYS pass (a,b)=>a-b.
   - Use Map (not plain object) for frequency maps: preserves key types, has .size, faster for
     frequent inserts, no prototype-key pitfalls.
   - Integer division: Math.floor(a/b). Avoid floats for indices.
   - A real queue with .shift() is O(n); for big BFS use an index pointer or a deque.
*/

/*
-----------------------------------------------------------------------------------------------
PATTERN MAP (which pattern when — same as my Ruby notes)
-----------------------------------------------------------------------------------------------
  contiguous subarray ............ sliding window
  sorted array / "find position" . binary search / two pointers
  "top K" ........................ heap (or sort)
  pair/triplet summing to target . hash map / two pointers
  repeated overlapping subproblems  dynamic programming
  parent-child / levels .......... tree DFS/BFS
  grid / connected regions ....... graph BFS/DFS (flood fill)
*/

// ===============================================================================================
// 1) TWO SUM  — hash map, O(n) time / O(n) space   (my exact Ruby Q, in JS)
//    Return indices of the two numbers that add to target.
// ===============================================================================================
function twoSum(nums, target) {
  const seen = new Map();                 // value -> index
  for (let i = 0; i < nums.length; i++) {
    const need = target - nums[i];
    if (seen.has(need)) return [seen.get(need), i];   // found the complement we saw earlier
    seen.set(nums[i], i);
  }
  return [];
}
// twoSum([2,7,11,15], 9) -> [0,1]
// Why O(n): one pass, O(1) map lookups. Sorting would lose original indices, so hashing is right.

// ===============================================================================================
// 2) GROUP ANAGRAMS — hash map keyed by sorted letters, O(n*k log k)   (my exact Ruby Q)
// ===============================================================================================
function groupAnagrams(strs) {
  const groups = new Map();
  for (const s of strs) {
    const key = [...s].sort().join('');   // anagrams share the same sorted key
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(s);
  }
  return [...groups.values()];
}
// groupAnagrams(["eat","tea","tan","ate","nat","bat"]) -> [["eat","tea","ate"],["tan","nat"],["bat"]]

// ===============================================================================================
// 3) MAX SUM SUBARRAY OF SIZE K — sliding window, O(n)   (literally my dsa.rb solved problem)
//    arr = [1,34,6,9,0,12,4,6], k=3 -> 49
// ===============================================================================================
function maxSubarraySum(arr, k) {
  let windowSum = 0;
  for (let i = 0; i < k; i++) windowSum += arr[i];   // first window
  let maxSum = windowSum;
  for (let j = k; j < arr.length; j++) {
    windowSum += arr[j] - arr[j - k];                 // slide: add new, drop leftmost
    maxSum = Math.max(maxSum, windowSum);
  }
  return maxSum;
}
// maxSubarraySum([1,34,6,9,0,12,4,6], 3) -> 49
// Sliding window turns an O(n*k) brute force into O(n) by reusing the previous window's sum.

// ===============================================================================================
// 4) BINARY SEARCH — first & last occurrence + frequency, O(log n)  (my exact dsa.rb solution)
// ===============================================================================================
function firstOccurrence(arr, k) {
  let lo = 0, hi = arr.length - 1, ans = -1;
  while (lo <= hi) {
    const mid = lo + ((hi - lo) >> 1);                // avoids overflow; >>1 == Math.floor(/2)
    if (arr[mid] === k) { ans = mid; hi = mid - 1; }  // record, keep searching LEFT
    else if (arr[mid] < k) lo = mid + 1;
    else hi = mid - 1;
  }
  return ans;
}
function lastOccurrence(arr, k) {
  let lo = 0, hi = arr.length - 1, ans = -1;
  while (lo <= hi) {
    const mid = lo + ((hi - lo) >> 1);
    if (arr[mid] === k) { ans = mid; lo = mid + 1; }  // record, keep searching RIGHT
    else if (arr[mid] < k) lo = mid + 1;
    else hi = mid - 1;
  }
  return ans;
}
function frequency(arr, k) {
  const first = firstOccurrence(arr, k);
  if (first === -1) return 0;
  return lastOccurrence(arr, k) - first + 1;
}
// frequency([12,19,21,21,21,21,56,78], 21) -> 4

// ===============================================================================================
// 5) LONGEST SUBSTRING WITHOUT REPEATING CHARS — sliding window + Set, O(n)
// ===============================================================================================
function lengthOfLongestSubstring(s) {
  const set = new Set();
  let left = 0, best = 0;
  for (let right = 0; right < s.length; right++) {
    while (set.has(s[right])) set.delete(s[left++]);  // shrink from left until no dup
    set.add(s[right]);
    best = Math.max(best, right - left + 1);
  }
  return best;
}
// lengthOfLongestSubstring("abcabcbb") -> 3 ("abc")

// ===============================================================================================
// 6) VALID PARENTHESES — stack, O(n)
// ===============================================================================================
function isValidParentheses(s) {
  const pairs = { ')': '(', ']': '[', '}': '{' };
  const stack = [];
  for (const ch of s) {
    if (ch === '(' || ch === '[' || ch === '{') stack.push(ch);
    else if (stack.pop() !== pairs[ch]) return false;  // mismatch or empty
  }
  return stack.length === 0;
}
// isValidParentheses("()[]{}") -> true ; isValidParentheses("(]") -> false

// ===============================================================================================
// 7) REVERSE A LINKED LIST — iterative pointer swap, O(n) time / O(1) space
// ===============================================================================================
function reverseList(head) {
  let prev = null, curr = head;
  while (curr) {
    const next = curr.next;   // save
    curr.next = prev;          // reverse the pointer
    prev = curr;               // advance
    curr = next;
  }
  return prev;                 // new head
}

// ===============================================================================================
// 8) DETECT CYCLE — Floyd's tortoise & hare, O(n) time / O(1) space
// ===============================================================================================
function hasCycle(head) {
  let slow = head, fast = head;
  while (fast && fast.next) {
    slow = slow.next;          // +1
    fast = fast.next.next;     // +2
    if (slow === fast) return true;  // they meet => cycle
  }
  return false;
}

// ===============================================================================================
// 9) NUMBER OF ISLANDS — grid DFS / flood fill, O(rows*cols)   (graph-on-a-grid)
// ===============================================================================================
function numIslands(grid) {
  if (!grid.length) return 0;
  const rows = grid.length, cols = grid[0].length;
  let count = 0;
  const sink = (r, c) => {
    if (r < 0 || c < 0 || r >= rows || c >= cols || grid[r][c] === '0') return;
    grid[r][c] = '0';                          // mark visited
    sink(r + 1, c); sink(r - 1, c); sink(r, c + 1); sink(r, c - 1);  // 4 neighbors
  };
  for (let r = 0; r < rows; r++)
    for (let c = 0; c < cols; c++)
      if (grid[r][c] === '1') { count++; sink(r, c); }   // each new land cell = a new island
  return count;
}

// ===============================================================================================
// 10) GRAPH BFS + DFS (adjacency list) — they often ask you to code the traversal
// ===============================================================================================
function bfs(adj, start) {                     // adj: Map<node, node[]>
  const visited = new Set([start]);
  const queue = [start];                        // (for huge graphs use an index pointer, not shift)
  const order = [];
  for (let i = 0; i < queue.length; i++) {      // index pointer => O(1) dequeue
    const node = queue[i];
    order.push(node);
    for (const nb of adj.get(node) || [])
      if (!visited.has(nb)) { visited.add(nb); queue.push(nb); }
  }
  return order;
}
function dfs(adj, start, visited = new Set(), order = []) {
  visited.add(start); order.push(start);
  for (const nb of adj.get(start) || [])
    if (!visited.has(nb)) dfs(adj, nb, visited, order);
  return order;
}

// ===============================================================================================
// 11) DP BASICS — Climbing Stairs / Fibonacci, O(n) time / O(1) space
// ===============================================================================================
function climbStairs(n) {                       // ways to reach step n taking 1 or 2 steps
  let a = 1, b = 1;                              // a = ways(i-2), b = ways(i-1)
  for (let i = 2; i <= n; i++) { [a, b] = [b, a + b]; }   // bottom-up, no recursion stack
  return b;
}
// climbStairs(5) -> 8.  Same recurrence as Fibonacci. Top-down recursion + memo also works:
function fibMemo(n, memo = new Map()) {
  if (n < 2) return n;
  if (memo.has(n)) return memo.get(n);
  const v = fibMemo(n - 1, memo) + fibMemo(n - 2, memo);
  memo.set(n, v);
  return v;
}

/*
-----------------------------------------------------------------------------------------------
COMPLEXITY THEORY Q&A (they ask these — from my dsa.rb)
-----------------------------------------------------------------------------------------------
  - Why is HashMap/Map O(1) average? -> a hash function maps the key to a bucket directly, so
    lookups don't scan; average O(1).
  - Worst case of HashMap? -> O(n) if many keys collide into one bucket (everything in one chain).
    Good hashing + resizing keeps it O(1) amortized.
  - Amortized time? -> average cost per operation over a sequence. e.g. a dynamic array push is
    O(1) amortized even though an occasional resize copies all elements (O(n) that one time).
  - O(n log n) vs O(n^2) practically? -> for n=1e6, n log n ≈ 2e7 ops vs n^2 = 1e12 — the
    difference between instant and "never finishes." Always prefer n log n sorts.
  - Space complexity of recursion? -> O(depth) for the call stack; deep recursion can blow the
    stack (in Node, "Maximum call stack size exceeded") — convert to iteration for deep cases.
  - Why quicksort worst case O(n^2)? -> bad pivot choices (already-sorted input + first-element
    pivot) give unbalanced partitions; randomized/median pivots keep it O(n log n) expected.
*/

/*
-----------------------------------------------------------------------------------------------
INTERVIEW APPROACH (say this while solving)
-----------------------------------------------------------------------------------------------
  1. Restate the problem + clarify constraints (input size, sorted?, duplicates?, edge cases).
  2. State a brute force + its complexity, THEN the optimal pattern and why.
  3. Talk through the approach BEFORE coding; name the data structure (Map/Set/stack/heap).
  4. Code cleanly, narrate as you go.
  5. Walk a small example by hand; check edge cases (empty, single element, all same, negatives).
  6. State final time + space complexity.
  Practicing OUT LOUD in JS (not Ruby) is the point — the syntax must be automatic under pressure.
*/

module.exports = {
  twoSum, groupAnagrams, maxSubarraySum, firstOccurrence, lastOccurrence, frequency,
  lengthOfLongestSubstring, isValidParentheses, reverseList, hasCycle, numIslands, bfs, dfs,
  climbStairs, fibMemo,
};
