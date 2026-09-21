===========================================================================================
                    DSA INTERVIEW QUESTION BANK (Top-Company Prep)
===========================================================================================
Format per question:
  Title — (Pattern)
  Problem: full statement
  Input / Output: worked example
  Explanation: why thats the output
  Constraints: typical bounds (guides brute-force vs optimal choice)
  Approach: expected technique — time / space complexity

Progression per topic: Easy -> Medium -> Advanced
Purely conceptual questions (no code) are marked "Discussion" instead of Input/Output.

===========================================================================================
                                  PATTERN RECOGNITION
===========================================================================================
The single highest-leverage skill in a DSA interview is not knowing 205 solutions — it is
recognizing, within the first 30 seconds of reading a NEW problem, which of ~30 known
patterns it is an instance of. This table is that lookup: scan the "Problem Signal" column
for phrasing that resembles what you are reading, jump to the "Likely Pattern," then to the
cited question number(s) for a worked example. Use this to drill recognition speed during
revision — cover the right two columns, read only the signal, and try to name the pattern
and technique before revealing them.

+--------------------------------------------------+---------------------------------------+--------------+
|                                          ARRAYS & TWO POINTERS                                          |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| two numbers sum to target, unsorted array        | Hashing (value -> index)              | Q1           |
| find/compare from both ends of an array          | Two Pointers                          | Q4, Q10, Q15 |
| sorted array, remove/dedupe in place             | Two Pointers (slow/fast)              | Q5           |
| merge two sorted arrays in place                 | Three Pointers (fill from back)       | Q6           |
| find triplets/quadruplets summing to target      | Sort + Two Pointers                   | Q7           |
| partition array into 3 fixed values in place     | Dutch National Flag                   | Q8           |
| running best value while scanning once           | Kadane / One-pass Greedy              | Q2, Q3       |
| product of all elements except self, no division | Prefix/Suffix Product                 | Q9           |
| merge/overlap a list of ranges                   | Sort + Sweep                          | Q11, Q12     |
| rotate array in place by k                       | Reversal Trick                        | Q13          |
| next lexicographic arrangement                   | Find pivot + swap + reverse suffix    | Q14          |
| median of two sorted arrays, O(log(m+n))         | Binary Search on partition            | Q16          |
| element appears more than n/2 times              | Boyer-Moore Voting                    | Q17          |
| count subarrays with sum == k                    | Prefix Sum + Hashing                  | Q18          |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                             SLIDING WINDOW                                              |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| contiguous subarray of FIXED size k, best sum    | Fixed Sliding Window                  | Q80          |
| contiguous subarray, condition on sum/product    | Variable Sliding Window               | Q82          |
| smallest subarray with sum >= target             | Shrinking Window                      | Q172         |
| longest substring without repeating chars        | Sliding Window + Hash Set             | Q24          |
| smallest window containing all chars of T        | Sliding Window + Need/Have Map        | Q29          |
| substring is a permutation of another string     | Fixed Window + Frequency Compare      | Q81          |
| longest substring after replacing <= k chars     | Window shrinks when invalid           | Q83          |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                                 STRINGS                                                 |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| reverse or palindrome-check a string in place    | Two Pointers                          | Q19, Q21     |
| check if two strings are anagrams                | Frequency Count                       | Q20          |
| group strings by anagram signature               | Hashing (sorted-string key)           | Q23          |
| longest palindromic substring                    | Expand Around Center / DP             | Q25          |
| longest palindromic substring, n up to 10^5      | Manacher Algorithm (true O(n))        | Q184         |
| compress repeated runs of characters             | Two Pointers (write on run end)       | Q26          |
| parse a string into a number (atoi)              | State-machine Parsing                 | Q27          |
| is s2 a rotation of s1?                          | Concatenation Trick (s+s)             | Q28          |
| find first occurrence of pattern in text         | KMP (LPS array)                       | Q182         |
| find pattern occurrences via hashing             | Rabin-Karp (rolling hash)             | Q183         |
| match string against pattern with . and *        | 2D DP                                 | Q30          |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                         HASHING / FREQUENCY MAP                                         |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| has this value been seen before?                 | Hash Set                              | Q31          |
| first character that never repeats               | Frequency Map                         | Q32          |
| consistent one-to-one char mapping               | Two Hash Maps (forward/back)          | Q33          |
| repeated transform leads to a cycle?             | Hashing / Cycle Detection             | Q34          |
| duplicate value within a distance k              | Hash Map of last-seen index           | Q35          |
| k most frequent elements                         | Hashing + Heap / Bucket Sort          | Q36          |
| longest run of consecutive integers, O(n)        | Hash Set (start only if n-1 absent)   | Q37          |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                                  STACK                                                  |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| matching / balanced nested brackets              | Stack                                 | Q38          |
| O(1) min or max alongside push/pop               | Auxiliary Stack                       | Q39          |
| next greater/smaller element to the side         | Monotonic Stack                       | Q40, Q41     |
| evaluate postfix (RPN) expression                | Stack                                 | Q42          |
| decode a nested encoded string                   | Stack (string, repeat-count pairs)    | Q43          |
| largest rectangle area under a histogram         | Monotonic Increasing Stack            | Q44          |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                              QUEUE / DEQUE                                              |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| build FIFO behavior from two stacks              | Stack/Queue Design                    | Q45          |
| first negative number in every window            | Deque of indices                      | Q46          |
| state spreads outward one step per minute        | Multi-source BFS                      | Q47          |
| max or min of every sliding window               | Monotonic Deque                       | Q48          |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                               LINKED LIST                                               |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| reverse a list or a sublist of it                | Pointer Manipulation                  | Q49, Q55     |
| find the middle node in one pass                 | Fast / Slow Pointers                  | Q50          |
| detect a cycle, or find where it starts          | Floyd Tortoise and Hare               | Q52, Q53     |
| remove the nth node from the end, one pass       | Two Pointers with a gap               | Q54          |
| do two lists intersect at a node?                | Two Pointers (switch heads)           | Q56          |
| add numbers stored as reversed-digit lists       | Simulation with carry                 | Q57          |
| deep-copy a list with random pointers            | Hashing / Interweaving clones         | Q58          |
| merge k sorted linked lists                      | Min-Heap / Divide & Conquer           | Q59          |
| O(1) get/put with recency-based eviction         | HashMap + Doubly Linked List          | Q60          |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                        RECURSION / BACKTRACKING                                         |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| all subsets / combinations / permutations        | Backtracking (include/exclude)        | Q64-Q69      |
| place items so none conflict (N-Queens)          | Backtracking + Pruning                | Q70          |
| does a word exist as a path in a grid?           | Backtracking + DFS                    | Q71          |
| compute x^n fast                                 | Divide & Conquer (fast exponent.)     | Q63          |
| partition a string so every piece is valid       | Backtracking over prefixes            | Q201         |
| fill a board so every constraint holds           | Backtracking + constraint sets        | Q202         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                              BINARY SEARCH                                              |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| sorted array, find index / insert position       | Classic Binary Search                 | Q72          |
| find first AND last occurrence of a value        | Binary Search x2 (L/R bound)          | Q74          |
| search in a rotated sorted array                 | Modified Binary Search                | Q75, Q76     |
| find a peak (local max) in an array              | Binary Search on the slope            | Q77          |
| minimize the max, or find smallest feasible X    | Binary Search on the Answer           | Q78, Q79     |
| flatten a row/col-sorted matrix and search       | Binary Search (index mapping)         | Q204         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                            BIT MANIPULATION                                             |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| every element appears twice except one           | XOR all elements                      | Q85          |
| count the number of set bits                     | n & (n-1) clears lowest set bit       | Q86          |
| check if a number is a power of two              | n & (n-1) == 0                        | Q87          |
| set-bit counts for every i in 0..n               | DP + Bit Trick                        | Q88          |
| find the missing number in 0..n                  | XOR / Sum Formula                     | Q89          |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                          HEAP / PRIORITY QUEUE                                          |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| kth largest or smallest element                  | Min/Max Heap or Quickselect           | Q90          |
| running median of a live data stream             | Two Heaps (max-half, min-half)        | Q91          |
| k closest points / elements to a target          | Max-Heap of size k                    | Q173         |
| repeatedly combine cheapest two values           | Min-Heap (Huffman-style)              | Q174         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                                  TRIE                                                   |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| prefix search / autocomplete over words          | Trie                                  | Q92          |
| search a word set where '.' = any char           | Trie + DFS over children              | Q93          |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                                 MATRIX                                                  |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| rotate an NxN matrix in place                    | Transpose then Reverse Rows           | Q95          |
| traverse a matrix boundary inward                | Boundary Simulation                   | Q96          |
| a 0 must zero its whole row and column           | Use first row/col as markers          | Q97          |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                       DYNAMIC PROGRAMMING - CORE                                        |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| count ways to reach n (steps of 1 or 2)          | 1D DP (Fibonacci-shaped)              | Q98          |
| max sum picking non-adjacent elements            | 1D DP                                 | Q99          |
| fewest coins / ways to make an amount            | Unbounded Knapsack                    | Q100, Q101   |
| longest increasing subsequence                   | 1D DP or O(n log n) w/ tails array    | Q102         |
| max value under a weight cap, item used once     | 0/1 Knapsack                          | Q103         |
| count paths through a grid                       | Grid DP                               | Q104         |
| assign +/- signs to hit a target sum             | DP as Subset Sum                      | Q105         |
| can a string be split into dictionary words?     | 1D DP                                 | Q106         |
| split array into two equal-sum halves?           | Subset Sum DP                         | Q107         |
| longest common subsequence of two strings        | 2D DP                                 | Q108         |
| min edits to turn one string into another        | 2D DP                                 | Q109         |
| optimal order to multiply / merge / burst        | Interval DP                           | Q110, Q112   |
| max profit picking non-overlapping jobs          | DP + Binary Search                    | Q111         |
| rob a tree without robbing parent+child          | Tree DP (post-order pair)             | Q113         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                 DYNAMIC PROGRAMMING - ADVANCED FAMILIES                                 |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| max PRODUCT subarray (sign flips matter)         | DP tracking running max AND min       | Q190         |
| unlimited buy/sell stock transactions            | Greedy (sum positive diffs)           | Q191         |
| at most k buy/sell transactions                  | 2D DP                                 | Q192         |
| stock trading with cooldown or fee               | State-machine DP                      | Q193         |
| longest palindromic SUBSEQUENCE (not substr)     | 2D DP (or LCS with reverse)           | Q194         |
| min cuts so every piece is a palindrome          | Interval DP                           | Q195         |
| worst-case trials to find a critical floor       | DP inverted: dp[eggs][moves]          | Q196         |
| visit every city once, min cost, return home     | Bitmask DP (TSP)                      | Q197         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                                 GREEDY                                                  |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| can you reach the end / min jumps to do so       | Greedy (farthest reachable)           | Q166, Q167   |
| circular route, can you complete the loop?       | Greedy (running tank total)           | Q168         |
| can one person attend all meetings?              | Sort by start + check overlap         | Q169         |
| minimum conference rooms needed                  | Sort + Min-Heap of end times          | Q170         |
| schedule tasks with a cooldown, min time         | Greedy + Max-Heap / formula           | Q171         |
| min removals so intervals stop overlapping       | Sort by end + Greedy keep             | Q203         |
| make correct change with only 3 bill values      | Greedy (track small-bill counts)      | Q205         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                BINARY TREES - TRAVERSAL, PROPERTIES, BST                                |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| visit nodes in left/root/right order variants    | DFS (recursive or stack)              | Q114, Q115   |
| visit nodes level by level                       | BFS with a queue                      | Q116, Q117   |
| deepest or shallowest root-to-leaf path          | DFS or BFS                            | Q118, Q119   |
| are two trees structurally identical?            | DFS                                   | Q120         |
| mirror a tree / check tree is symmetric          | DFS / BFS swap or mirror-compare      | Q121, Q122   |
| is this a valid BST?                             | DFS with min/max bounds               | Q123         |
| search, insert, or delete in a BST               | BST property descent                  | Q124-Q126    |
| lowest common ancestor IN a BST                  | BST property descent                  | Q127         |
| kth smallest element in a BST                    | Inorder Traversal                     | Q128         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                         ADVANCED TREE PROBLEMS                                          |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| lowest common ancestor, general binary tree      | DFS (bubble node up)                  | Q129         |
| longest path between any two nodes               | DFS post-order (return height)        | Q130         |
| is the tree height-balanced?                     | DFS post-order, short-circuit -1      | Q131         |
| root-to-leaf path sums to a target               | DFS subtracting remaining sum         | Q132         |
| values visible from the right side               | BFS last-per-level / DFS right-first  | Q133         |
| count nodes with nothing greater on their path   | DFS carrying running max              | Q134         |
| max path sum between any two nodes               | DFS post-order, track global max      | Q135         |
| rebuild a tree from two traversal orders         | Recursion + Hashing (find root)       | Q136, Q137   |
| serialize a tree to a string and back            | DFS/BFS + explicit null markers       | Q138         |
| flatten a tree into a right-skewed list          | DFS (Morris-style splice)             | Q139         |
| group tree nodes into vertical columns           | DFS/BFS tracking (row,col) + sort     | Q140         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                    GRAPHS - TRAVERSAL & CONNECTIVITY                                    |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| visit reachable nodes level by level             | BFS                                   | Q141         |
| go as deep as possible before backtracking       | DFS                                   | Q142         |
| represent a graph from a list of edges           | Adjacency List / Matrix               | Q143, Q144   |
| count separate groups of connected nodes         | DFS/BFS or Union-Find                 | Q145, Q146   |
| count islands / connected land in a grid         | DFS/BFS Flood Fill                    | Q147, Q157   |
| does an undirected graph contain a cycle?        | DFS w/ parent, or Union-Find          | Q148         |
| does a directed graph contain a cycle?           | DFS + recursion-stack marker          | Q149         |
| recolor a connected region in an image           | DFS/BFS Flood Fill                    | Q158         |
| deep-copy a graph that may contain cycles        | DFS/BFS + Hashing (node->clone)       | Q160         |
| group elements, then answer 'same group?'        | Union-Find / Disjoint Set             | Q162         |
| find the one edge that creates a cycle           | Union-Find                            | Q163         |
| 2-color a graph with no same-color edge          | BFS/DFS Coloring                      | Q165         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                               GRAPHS - ORDERING, SHORTEST PATH & ADVANCED                               |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| valid order respecting dependencies              | Topological Sort (DFS+stack / Kahn)   | Q150, Q151   |
| can all courses/tasks finish given prereqs?      | Topological Sort / Cycle Check        | Q152, Q153   |
| shortest #edges from source, unweighted          | BFS                                   | Q154         |
| shortest path, all weights positive              | Dijkstra (min-heap)                   | Q155         |
| shortest path, negative weights allowed          | Bellman-Ford                          | Q156         |
| shortest path in a grid, 8 directions            | BFS                                   | Q159         |
| shortest word-to-word transformation chain       | BFS over an implicit word graph       | Q161         |
| min total edge weight connecting all nodes       | Kruskal (sort edges + Union-Find)     | Q164         |
| shortest path between EVERY pair of nodes        | Floyd-Warshall                        | Q198         |
| node/edge whose removal disconnects graph        | DFS + Low-Link (Tarjan-style)         | Q199         |
| maximal mutually-reachable groups, directed      | Kosaraju's / Tarjan's SCC             | Q200         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                              SORTING, PREFIX SUM & RANGE QUERY STRUCTURES                               |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| sort from scratch, need stability guaranteed     | Merge Sort                            | Q176         |
| sort in place, fastest average case              | Quick Sort                            | Q177         |
| sort in place, O(n log n) worst case             | Heap Sort                             | Q178         |
| many range-sum queries, array never changes      | Prefix Sum                            | Q179, Q180   |
| many range-increment updates, read once at end   | Difference Array                      | Q181         |
| range-sum queries AND the array is mutable       | Fenwick Tree (BIT)                    | Q185         |
| range min/max queries AND the array is mutable   | Segment Tree                          | Q186         |
+--------------------------------------------------+---------------------------------------+--------------+

+--------------------------------------------------+---------------------------------------+--------------+
|                                          MATH / NUMBER THEORY                                           |
+--------------------------------------------------+---------------------------------------+--------------+
| Problem Signal                                   | Likely Pattern                        | Example (Q#) |
+--------------------------------------------------+---------------------------------------+--------------+
| gcd or lcm of two numbers                        | Euclidean Algorithm                   | Q187         |
| find all primes below n                          | Sieve of Eratosthenes                 | Q188         |
| base^exponent mod m, huge exponent               | Modular / Fast Exponentiation         | Q189         |
+--------------------------------------------------+---------------------------------------+--------------+

Note: many problems carry MULTIPLE valid signals at once (e.g. Q18 "count subarrays with
sum == k" is both an Arrays problem and a Hashing problem — the table lists it under the
signal that is most diagnostic). When a problem seems to match two rows, that is normal —
try the cheaper/simpler pattern first, and fall back to the other if it does not fit.

===========================================================================================
1. ARRAYS
===========================================================================================

--- Easy ---

1.Two Sum — (Pattern: Hashing)
Problem: Given an array of integers nums and an integer target, return the indices of the
two numbers that add up to target. Exactly one solution exists; do not reuse an element.
Input:  nums = [2, 7, 11, 15], target = 9
Output: [0, 1]
Explanation: nums[0] + nums[1] = 2 + 7 = 9
Constraints: 2 <= nums.length <= 10^4, -10^9 <= nums[i], target <= 10^9
Approach: single pass, store value -> index in a hash map, check for (target - num) — O(n) time, O(n) space

2.Best Time to Buy and Sell Stock — (Pattern: One-pass Greedy)
Problem: Given an array prices where prices[i] is the stock price on day i, return the
maximum profit from one buy followed by one sell. Return 0 if no profit is possible.
Input:  prices = [7, 1, 5, 3, 6, 4]
Output: 5
Explanation: Buy on day 2 (price 1), sell on day 5 (price 6), profit = 6 - 1 = 5
Constraints: 1 <= prices.length <= 10^5, 0 <= prices[i] <= 10^4
Approach: track min-price-so-far and max-profit-so-far in one pass — O(n) time, O(1) space

3.Maximum Subarray — (Pattern: Kadanes Algorithm)
NOTE: "Kadane's Algorithm finds the maximum sum of a contiguous subarray by maintaining the best sum ending at each position and choosing between extending the previous subarray or starting a new one."

Problem: Given an integer array nums, find the contiguous subarray with the largest sum
and return its sum.
Input:  nums = [-2, 1, -3, 4, -1, 2, 1, -5, 4]
Output: 6
Explanation: The subarray [4, -1, 2, 1] has the maximum sum: 4 + (-1) + 2 + 1 = 6
Constraints: 1 <= nums.length <= 10^5, -10^4 <= nums[i] <= 10^4
Approach: Kadanes Algorithm (running sum, reset to 0 when it goes negative) — O(n) time, O(1) space

4.Move Zeroes — (Pattern: Two Pointers)
Problem: Given an array nums, move all 0s to the end while maintaining the relative
order of the non-zero elements, in-place.
Input:  nums = [0, 1, 0, 3, 12]
Output: [1, 3, 12, 0, 0]
Explanation: All non-zero elements keep their order; zeroes are pushed to the end.
Constraints: 1 <= nums.length <= 10^4
Approach: two pointers — one tracks the next position to fill with a non-zero — O(n) time, O(1) space

5.Remove Duplicates from Sorted Array — (Pattern: Two Pointers)
Problem: Given a sorted array nums, remove duplicates in-place so each element appears
once, and return the new length.
Input:  nums = [1, 1, 2, 2, 3]
Output: 3  (nums becomes [1, 2, 3, _, _])
Explanation: Unique elements 1, 2, 3 occupy the first 3 positions.
Constraints: 1 <= nums.length <= 3*10^4, sorted in non-decreasing order
Approach: slow/fast pointer, overwrite when a new value is seen — O(n) time, O(1) space

6.Merge Sorted Array — (Pattern: Three Pointers)
Problem: Given two sorted arrays nums1 (with extra trailing space) and nums2, merge
nums2 into nums1 in-place as one sorted array.
Input:  nums1 = [1,2,3,0,0,0], m = 3, nums2 = [2,5,6], n = 3
Output: [1,2,2,3,5,6]
Explanation: Merging both sorted arrays keeps overall sorted order.
Constraints: nums1.length == m + n, 0 <= m, n <= 200
Approach: fill from the back with three pointers to avoid overwriting — O(m+n) time, O(1) space

--- Medium ---

7.3Sum — (Pattern: Sorting + Two Pointers)
Problem: Given an integer array nums, return all UNIQUE triplets [nums[i], nums[j], nums[k]]
such that i != j != k and they sum to 0.
Input:  nums = [-1, 0, 1, 2, -1, -4]
Output: [[-1, -1, 2], [-1, 0, 1]]
Explanation: Both triplets sum to zero; duplicates TRIPLETS are excluded.
Constraints: 3 <= nums.length <= 3000, -10^5 <= nums[i] <= 10^5
Approach: sort array, fix one element, two-pointer scan for the rest, skip duplicates — O(n^2) time, O(1) extra space

[-4, -1, -1, 0, 1, 2 ]

8.Sort Colors — (Pattern: Dutch National Flag)
Problem: Given an array with only 0s, 1s, and 2s, sort it in-place in one pass without
using a library sort.
Input:  nums = [2, 0, 2, 1, 1, 0]
Output: [0, 0, 1, 1, 2, 2]
Explanation: All 0s first, then 1s, then 2s.
Constraints: 1 <= nums.length <= 300
Approach: three pointers (low, mid, high), swap to partition — O(n) time, O(1) space

9.Product of Array Except Self — (Pattern: Prefix/Suffix Product)
Problem: Given an array nums, return an array where each element is the product of all
other elements, without using division.
Input:  nums = [1, 2, 3, 4]
Output: [24, 12, 8, 6]
Explanation: answer[0] = 2*3*4 = 24, answer[1] = 1*3*4 = 12, etc.
Constraints: 2 <= nums.length <= 10^5
Approach: prefix-product pass then suffix-product pass, combined — O(n) time, O(1) extra space (excluding output)

10.Container With Most Water — (Pattern: Two Pointers)
Problem: Given heights array, find two lines that together with the x-axis form a
container holding the most water. Return the max area.
Input:  height = [1, 8, 6, 2, 5, 4, 8, 3, 7]
Output: 49
Explanation: Lines at index 1 (height 8) and index 8 (height 7): area = 7 * min(8,7) = 49
Constraints: 2 <= height.length <= 10^5, 0 <= height[i] <= 10^4
Approach: two pointers from both ends, move the shorter side inward — O(n) time, O(1) space

11.Merge Intervals — (Pattern: Sort + Sweep) / Greedy
Problem: Given an array of intervals, merge all overlapping intervals and return
the non-overlapping intervals covering all input ranges.
Input:  intervals = [[1,3],[2,6],[8,10],[15,18]]
Output: [[1,6],[8,10],[15,18]]
Explanation: [1,3] and [2,6] overlap, merged into [1,6].
Constraints: 1 <= intervals.length <= 10^4
Approach: sort by start, sweep and merge when current.start <= previous.end — O(n log n) time, O(n) space

12.Insert Interval — (Pattern: Intervals)
Problem: Given a sorted, non-overlapping list of intervals and a new interval, insert it
and merge if necessary. Return the resulting list.
Input:  intervals = [[1,3],[6,9]], newInterval = [2,5]
Output: [[1,5],[6,9]]
Explanation: [2,5] overlaps [1,3], merges into [1,5]; [6,9] stays separate.
Constraints: 0 <= intervals.length <= 10^4
Approach: single pass — add intervals before, merge overlapping ones, add intervals after — O(n) time, O(n) space

13.Rotate Array — (Pattern: Reversal Trick)
Problem: Given an array nums, rotate it to the right by k steps, in-place.
Input:  nums = [1,2,3,4,5,6,7], k = 3
Output: [5,6,7,1,2,3,4]
Explanation: Rotating right by 3 moves the last 3 elements to the front.
Constraints: 1 <= nums.length <= 10^5, 0 <= k <= 10^5
Approach: reverse whole array, then reverse first k and remaining n-k parts — O(n) time, O(1) space

14.Next Permutation — (Pattern: Array Manipulation)
Problem: Rearrange numbers into the lexicographically next greater permutation. If none
exists, rearrange to the lowest possible order (sorted ascending).
Input:  nums = [1, 2, 3]
Output: [1, 3, 2]
Explanation: The next permutation after [1,2,3] is [1,3,2].
Constraints: 1 <= nums.length <= 100
Approach: find rightmost ascent, swap with next-larger suffix element, reverse suffix — O(n) time, O(1) space.

Next permutation (agla dictionary order) nikalne ka seedha sa funda ye hai: Array ko peeche se (right to left) check karke pehla aisa number (Breakpoint) dhundo jo apne right wale se chhota ho. Phir dubara peeche se hi ek aisa number dhundo jo is Breakpoint se "just bada" ho, aur dono ko aapas mein Swap kar do. Swap ke baad, Breakpoint ke aage ka bacha hua hissa (suffix) hamesha apne sabse bade (descending) order mein hi rehta hai, isliye minimum possible agla sequence banane ke liye us bache hue hisse ko seedha Reverse kar do. (Bonus point: Agar shuru mein koi breakpoint na mile, matlab number already maximum hai, toh bina kuch soche poore array ko reverse kar do).

--- Advanced ---

15.Trapping Rain Water — (Pattern: Two Pointers / Prefix Max)
Problem: Given elevation heights, compute how much water is trapped after raining.
Input:  height = [0,1,0,2,1,0,1,3,2,1,2,1]
Output: 6
Explanation: Water accumulates in the dips between taller bars, totaling 6 units.
Constraints: 1 <= height.length <= 2*10^4, 0 <= height[i] <= 10^5
Approach: two pointers tracking left-max and right-max, move the smaller side — O(n) time, O(1) space

16.Median of Two Sorted Arrays — (Pattern: Binary Search)
Problem: Given two sorted arrays nums1 and nums2, return the median of the combined
sorted array in O(log(min(m,n))) time.
Input:  nums1 = [1, 3], nums2 = [2]
Output: 2.0
Explanation: Combined sorted array is [1,2,3]; median is 2.
Constraints: 0 <= m, n <= 1000, 1 <= m+n <= 2000
Approach: binary search on the partition point of the smaller array — O(log(min(m,n))) time, O(1) space

17.Majority Element — (Pattern: Boyer-Moore Voting)
Problem: Given an array nums, return the element that appears more than n/2 times
(guaranteed to exist).
Input:  nums = [2, 2, 1, 1, 1, 2, 2]
Output: 2
Explanation: 2 appears 4 times out of 7 elements, more than n/2.
Constraints: 1 <= nums.length <= 5*10^4
Approach: Boyer-Moore majority vote (candidate + counter) — O(n) time, O(1) space

18.Subarray Sum Equals K — (Pattern: Prefix Sum + Hashing)
Problem: Given an array nums and an integer k, return the number of contiguous
subarrays whose sum equals k.
Input:  nums = [1, 1, 1], k = 2
Output: 2
Explanation: Subarrays [1,1] (indices 0-1) and [1,1] (indices 1-2) sum to 2.
Constraints: 1 <= nums.length <= 2*10^4, -1000 <= nums[i] <= 1000
Approach: running prefix sum + hash map of prefix-sum frequencies, check for (sum - k) — O(n) time, O(n) space

===========================================================================================
2. STRINGS
===========================================================================================

--- Easy ---

19.Reverse String — (Pattern: Two Pointers)
Problem: Reverse a character array in-place without using extra space or built-ins.
Input:  s = ['h','e','l','l','o']
Output: ['o','l','l','e','h']
Explanation: Characters are reversed end to end.
Constraints: 1 <= s.length <= 10^5
Approach: two pointers from both ends, swap and move inward — O(n) time, O(1) space

20.Valid Anagram — (Pattern: Frequency Count)
Problem: Given two strings s and t, return true if t is an anagram of s.
Input:  s = "anagram", t = "nagaram"
Output: true
Explanation: Both strings contain exactly the same characters with the same frequency.
Constraints: 1 <= s.length, t.length <= 5*10^4
Approach: frequency count array/map, compare — O(n) time, O(1) space (fixed alphabet)

21.Valid Palindrome — (Pattern: Two Pointers)
Problem: Given a string s, check if it is a palindrome after converting to lowercase and
removing non-alphanumeric characters.
Input:  s = "A man, a plan, a canal: Panama"
Output: true
Explanation: Cleaned string "amanaplanacanalpanama" reads the same forwards and backwards.
Constraints: 1 <= s.length <= 2*10^5
Approach: two pointers from both ends, skip non-alphanumeric, compare case-insensitively — O(n) time, O(1) space

22.Implement strStr() — (Pattern: String Matching)
Problem: Given haystack and needle strings, return the index of the first occurrence of
needle in haystack, or -1 if not found.
Input:  haystack = "sadbutsad", needle = "sad"
Output: 0
Explanation: "sad" first occurs at index 0.
Constraints: 1 <= haystack.length, needle.length <= 10^4
Approach: Brute-force substring matching using a fixed-size window / Brute-force or KMP for optimal — O(n+m) time with KMP, O(m) space

--- Medium ---

23.Group Anagrams — (Pattern: Hashing)
Problem: Given an array of strings, group the anagrams together.
Input:  strs = ["eat","tea","tan","ate","nat","bat"]
Output: [["eat","tea","ate"],["tan","nat"],["bat"]]
Explanation: Strings with identical sorted-character keys are grouped.
Constraints: 1 <= strs.length <= 10^4, 0 <= strs[i].length <= 100
Approach: hash map keyed by sorted string (or char-count signature) — O(n * k log k) time, O(n*k) space

24.Longest Substring Without Repeating Characters — (Pattern: Sliding Window)
Problem: Given a string s, find the length of the longest substring without repeating
characters.
Input:  s = "abcabcbb"
Output: 3
Explanation: The answer is "abc", with length 3.
Constraints: 0 <= s.length <= 5*10^4
Approach: sliding window with a hash set/map of last-seen index — O(n) time, O(min(n, alphabet)) space

25.Longest Palindromic Substring — (Pattern: Expand Around Center / DP)
Problem: Given a string s, return the longest palindromic substring.
Input:  s = "babad"
Output: "bab"  (or "aba", both valid)
Explanation: "bab" and "aba" are both palindromes of length 3; either is accepted.
Constraints: 1 <= s.length <= 1000
Approach: expand around each center (odd & even) — O(n^2) time, O(1) space

26.String Compression — (Pattern: Two Pointers)
Problem: Compress a character array in-place using counts of repeated characters,
return the new length.
Input:  chars = ['a','a','b','b','c','c','c']
Output: 6, chars = ['a','2','b','2','c','3']
Explanation: 'a' repeats twice, 'b' twice, 'c' three times.
Constraints: 1 <= chars.length <= 2000
Approach: two pointers, write char + count when a run ends — O(n) time, O(1) space

27.String to Integer (atoi) — (Pattern: String Parsing)
Problem: Implement atoi: convert a string to a 32-bit signed integer, handling
leading whitespace, optional sign, digits, and overflow clamping.
Input:  s = "   -42"
Output: -42
Explanation: Leading spaces are skipped, sign is captured, digits parsed until non-digit.
Constraints: 0 <= s.length <= 200, result clamped to [-2^31, 2^31 - 1]
Approach: careful state-machine parsing — O(n) time, O(1) space

28.Check if One String is a Rotation of Another — (Pattern: Concatenation Trick)
Problem: Given strings s1 and s2 of equal length, check if s2 is a rotation of s1.
Input:  s1 = "waterbottle", s2 = "erbottlewat"
Output: true
Explanation: s2 appears as a substring of s1 + s1.
Constraints: 0 <= s1.length == s2.length <= 10^4
Approach: check if s2 is a substring of (s1 + s1) — O(n) time (with efficient substring search), O(n) space

--- Advanced ---

29.Minimum Window Substring — (Pattern: Sliding Window + Hashing)
Problem: Given strings s and t, return the smallest substring of s containing all
characters of t (with multiplicity). Return "" if none exists.
Input:  s = "ADOBECODEBANC", t = "ABC"
Output: "BANC"
Explanation: "BANC" is the smallest window in s containing 'A', 'B', and 'C'.
Constraints: 1 <= s.length, t.length <= 10^5
Approach: sliding window with need/have frequency maps — O(n + m) time, O(k) space

30.Regular Expression Matching — (Pattern: DP)
Problem: Implement regex matching supporting '.' (any single char) and '*' (zero or
more of the preceding element), matching the entire input string.
Input:  s = "aa", p = "a*"
Output: true
Explanation: '*' means zero or more of the preceding 'a', so "aa" matches "a*".
Constraints: 1 <= s.length <= 20, 1 <= p.length <= 30
Approach: 2D DP, dp[i][j] = does s[0..i) match p[0..j) — O(n*m) time, O(n*m) space

===========================================================================================
3. HASHING / FREQUENCY MAP
===========================================================================================

--- Easy ---

31.Contains Duplicate — (Pattern: Hashing)
Problem: Given an array nums, return true if any value appears at least twice.
Input:  nums = [1, 2, 3, 1]
Output: true
Explanation: 1 appears twice.
Constraints: 1 <= nums.length <= 10^5
Approach: hash set, return true on first repeat — O(n) time, O(n) space

32.First Non-Repeating Character in a String — (Pattern: Frequency Map)
Problem: Given a string s, return the index of the first character that does not
repeat; return -1 if none exists.
Input:  s = "leetcode"
Output: 0
Explanation: 'l' is the first character that appears only once.
Constraints: 1 <= s.length <= 10^5, lowercase English letters
Approach: frequency count pass, then scan for first count == 1 — O(n) time, O(1) space (fixed alphabet)

33.Isomorphic Strings — (Pattern: Hashing)
Problem: Given strings s and t, return true if the characters in s can be replaced to
get t, with a consistent one-to-one mapping.
Input:  s = "egg", t = "add"
Output: true
Explanation: 'e'->'a', 'g'->'d' is a consistent bijective mapping.
Constraints: 1 <= s.length == t.length <= 5*10^4
Approach: two hash maps for forward/backward character mapping — O(n) time, O(1) space (fixed alphabet)

34.Happy Number — (Pattern: Hashing / Cycle Detection)
Problem: A number is "happy" if repeatedly replacing it with the sum of squares of its
digits eventually reaches 1. Determine if n is happy.
Input:  n = 19
Output: true
Explanation: 19 -> 82 -> 68 -> 100 -> 1
Constraints: 1 <= n <= 2^31 - 1
Approach: hash set to detect cycles, or Floyd cycle detection for O(1) space — O(log n) time per step

--- Medium ---

35.Contains Duplicate II — (Pattern: Hashing + Sliding Window)
Problem: Given an array nums and integer k, return true if there are two distinct
indices i, j such that nums[i] == nums[j] and |i - j| <= k.
Input:  nums = [1,2,3,1], k = 3
Output: true
Explanation: nums[0] == nums[3] and |0-3| = 3 <= k.
Constraints: 1 <= nums.length <= 10^5, 0 <= k <= 10^5
Approach: hash map of value -> last seen index, check distance on each match — O(n) time, O(min(n,k)) space

36.Top K Frequent Elements — (Pattern: Hashing + Heap/Bucket Sort)
Problem: Given an array nums and integer k, return the k most frequent elements.
Input:  nums = [1,1,1,2,2,3], k = 2
Output: [1, 2]
Explanation: 1 occurs 3 times, 2 occurs 2 times — the top 2 most frequent.
Constraints: 1 <= nums.length <= 10^5, k <= number of distinct elements
Approach: frequency map + min-heap of size k, or bucket sort by frequency for O(n) — O(n log k) time (heap) or O(n) (bucket), O(n) space

37.Longest Consecutive Sequence — (Pattern: Hashing)
Problem: Given an unsorted array nums, return the length of the longest run of
consecutive integers, in O(n) time.
Input:  nums = [100, 4, 200, 1, 3, 2]
Output: 4
Explanation: The consecutive sequence [1, 2, 3, 4] has length 4.
Constraints: 0 <= nums.length <= 10^5
Approach: hash set, only start counting from numbers whose (num-1) is not present — O(n) time, O(n) space

(See also: Two Sum, Subarray Sum Equals K, Group Anagrams — under Arrays/Strings, same Hashing pattern)

===========================================================================================
4. STACK
===========================================================================================

--- Easy ---

38.Valid Parentheses — (Pattern: Stack)
Problem: Given a string containing only '(', ')', '{', '}', '[', ']', determine if
brackets are balanced and correctly nested.
Input:  s = "()[]{}"
Output: true
Explanation: Every opening bracket is closed in the correct order.
Constraints: 1 <= s.length <= 10^4
Approach: push opening brackets, pop and match on closing brackets — O(n) time, O(n) space

--- Medium ---

39.Min Stack — (Pattern: Stack + Auxiliary Stack)
Problem: Design a stack supporting push, pop, top, and getMin(), all in O(1) time.
Input:  push(-2), push(0), push(-3), getMin(), pop(), top(), getMin()
Output: -3, 0, -2
Explanation: getMin() reflects the current minimum after each operation.
Constraints: up to 3*10^4 calls total
Approach: auxiliary stack tracking running minimum alongside the main stack — O(1) time per op, O(n) space

40.Next Greater Element — (Pattern: Monotonic Stack)
Problem: Given an array nums, for each element find the next greater element to its
right; use -1 if none exists.
Input:  nums = [2, 1, 2, 4, 3]
Output: [4, 2, 4, -1, -1]
Explanation: For 2 (index 0), next greater is 4; for 1, next greater is 2; etc.
Constraints: 1 <= nums.length <= 10^4
Approach: monotonic decreasing stack of indices, pop when a bigger value is found — O(n) time, O(n) space

41.Daily Temperatures — (Pattern: Monotonic Stack)
Problem: Given daily temperatures, return an array where answer[i] is the number of
days to wait for a warmer temperature (0 if none).
Input:  temperatures = [73,74,75,71,69,72,76,73]
Output: [1,1,4,2,1,1,0,0]
Explanation: Day 0 (73) waits 1 day for 74; day 3 (71) waits 2 days for 72; etc.
Constraints: 1 <= temperatures.length <= 10^5
Approach: monotonic decreasing stack of indices — O(n) time, O(n) space

42.Evaluate Reverse Polish Notation — (Pattern: Stack)
Problem: Evaluate an arithmetic expression given in postfix (Reverse Polish) notation.
Input:  tokens = ["2","1","+","3","*"]
Output: 9
Explanation: (2 + 1) * 3 = 9
Constraints: 1 <= tokens.length <= 10^4
Approach: push operands, pop two and apply operator when an operator token appears — O(n) time, O(n) space

43.Decode String — (Pattern: Stack)
Problem: Given an encoded string like "3[a2[c]]", return its decoded form.
Input:  s = "3[a2[c]]"
Output: "accaccacc"
Explanation: "2[c]" decodes to "cc", so "a2[c]" is "acc", repeated 3 times.
Constraints: 1 <= s.length <= 30
Approach: stack of (previous string, repeat count), build on encountering ']' — O(n) time, O(n) space

--- Advanced ---

44.Largest Rectangle in Histogram — (Pattern: Monotonic Stack)
Problem: Given heights of histogram bars (width 1 each), find the area of the largest
rectangle in the histogram.
Input:  heights = [2,1,5,6,2,3]
Output: 10
Explanation: The rectangle formed by bars of height 5 and 6 (width 2) gives area 10.
Constraints: 1 <= heights.length <= 10^5
Approach: monotonic increasing stack of indices, compute area when popping — O(n) time, O(n) space

===========================================================================================
5. QUEUE / DEQUE
===========================================================================================

--- Easy ---

45.Implement Queue using Stacks — (Pattern: Stack/Queue Design)
Problem: Implement a FIFO queue using only two stacks, supporting push, pop, peek, empty.
Input:  push(1), push(2), peek(), pop(), empty()
Output: 1, 1, false
Explanation: Elements come out in the order they were pushed despite stacks being LIFO.
Constraints: up to 100 calls
Approach: an "in" stack for pushes, transfer to an "out" stack for pops when it is empty — amortized O(1) time, O(n) space

--- Medium ---

46.First Negative Number in Every Window of Size K — (Pattern: Deque)
Problem: Given an array and window size k, find the first negative number in every
contiguous window of size k.
Input:  arr = [12, -1, -7, 8, -15, 30, 16, 28], k = 3
Output: [-1, -1, -7, -15, -15, 0]
Explanation: Each windows first negative is reported; 0 if none exists in that window.
Constraints: 1 <= arr.length <= 10^5
Approach: deque storing indices of negative numbers, drop indices outside the window — O(n) time, O(k) space

47.Rotten Oranges — (Pattern: BFS)
Problem: Given a grid where 2 = rotten, 1 = fresh, 0 = empty, return the minimum
minutes until no fresh orange remains, or -1 if impossible.
Input:  grid = [[2,1,1],[1,1,0],[0,1,1]]
Output: 4
Explanation: Rot spreads one cell per minute in all 4 directions from each rotten orange.
Constraints: 1 <= rows, cols <= 10
Approach: multi-source BFS starting from all initially rotten cells — O(rows*cols) time, O(rows*cols) space

--- Advanced ---

48.Sliding Window Maximum — (Pattern: Monotonic Deque)
Problem: Given an array and window size k, return the max of every contiguous window.
Input:  nums = [1,3,-1,-3,5,3,6,7], k = 3
Output: [3,3,5,5,6,7]
Explanation: Max of [1,3,-1] is 3, max of [3,-1,-3] is 3, and so on as the window slides.
Constraints: 1 <= nums.length <= 10^5, 1 <= k <= nums.length
Approach: monotonic decreasing deque of indices — O(n) time, O(k) space

===========================================================================================
6. LINKED LIST
===========================================================================================

--- Easy ---

49.Reverse Linked List — (Pattern: Pointer Manipulation)
Problem: Given the head of a singly linked list, reverse it and return the new head.
Input:  head = 1 -> 2 -> 3 -> 4 -> 5
Output: 5 -> 4 -> 3 -> 2 -> 1
Explanation: Each nodes next pointer is flipped to point to its predecessor.
Constraints: 0 <= number of nodes <= 5000
Approach: iterative pointer reversal (prev, curr, next) — O(n) time, O(1) space

50.Middle of the Linked List — (Pattern: Fast/Slow Pointers)
Problem: Given the head of a singly linked list, return the middle node (second middle
if two exist).
Input:  head = 1 -> 2 -> 3 -> 4 -> 5
Output: 3
Explanation: 3 is the middle of 5 nodes.
Constraints: 1 <= number of nodes <= 100
Approach: slow pointer moves 1 step, fast pointer moves 2 steps — O(n) time, O(1) space

51.Merge Two Sorted Lists — (Pattern: Two Pointers)
Problem: Merge two sorted linked lists and return it as one sorted list.
Input:  l1 = 1->2->4, l2 = 1->3->4
Output: 1->1->2->3->4->4
Explanation: Nodes are spliced together in sorted order.
Constraints: 0 <= nodes in each list <= 50
Approach: dummy head, compare heads of both lists, attach the smaller each time — O(n+m) time, O(1) space

--- Medium ---

52.Linked List Cycle — (Pattern: Floyd Algorithm)
Problem: Given the head of a linked list, determine if it has a cycle.
Input:  head = 3 -> 2 -> 0 -> -4 -> (back to node with value 2)
Output: true
Explanation: The tail connects back into the list, forming a cycle.
Constraints: 0 <= number of nodes <= 10^4
Approach: fast/slow pointers (Floyd Tortoise and Hare) — if they meet, a cycle exists — O(n) time, O(1) space

53.Linked List Cycle II — (Pattern: Floyd Algorithm)
Problem: Given a linked list, return the node where the cycle begins, or null if there
is no cycle.
Input:  head = 3 -> 2 -> 0 -> -4 -> (back to node with value 2)
Output: node with value 2
Explanation: After detecting the cycle, resetting one pointer to head and advancing
both one step at a time meets exactly at the cycle's start.
Constraints: 0 <= number of nodes <= 10^4
Approach: Floyd's algorithm — detect meeting point, then find cycle start — O(n) time, O(1) space

54.Remove Nth Node From End of List — (Pattern: Two Pointers)
Problem: Given the head of a list, remove the nth node from the end, in one pass.
Input:  head = 1->2->3->4->5, n = 2
Output: 1->2->3->5
Explanation: The 2nd node from the end (value 4) is removed.
Constraints: 1 <= number of nodes <= 30
Approach: two pointers with a gap of n, advance both until the fast one hits the end — O(n) time, O(1) space

55.Reverse Linked List II — (Pattern: Pointer Manipulation)
Problem: Given the head of a list and positions m and n (1-indexed), reverse the nodes
from position m to n and return the head.
Input:  head = 1->2->3->4->5, m = 2, n = 4
Output: 1->4->3->2->5
Explanation: Only the sublist [2,3,4] is reversed in place.
Constraints: 1 <= number of nodes <= 500
Approach: locate node before m, reverse the sublist in place, reconnect — O(n) time, O(1) space

56.Intersection of Two Linked Lists — (Pattern: Two Pointers)
Problem: Given the heads of two singly linked lists, return the node at which they
intersect, or null if they don't.
Input:  listA = 4->1->8->4->5, listB = 5->6->1->8->4->5 (sharing tail 8->4->5)
Output: node with value 8
Explanation: Both lists share the same tail starting at node 8.
Constraints: total nodes across both lists <= 3*10^4
Approach: two pointers, each switches to the other list's head after reaching its own
end — they meet at the intersection (or both reach null) — O(n+m) time, O(1) space

57.Add Two Numbers — (Pattern: Simulation)
Problem: Given two non-empty linked lists representing non-negative integers in
reverse digit order, add them and return the sum as a linked list.
Input:  l1 = 2->4->3, l2 = 5->6->4
Output: 7->0->8
Explanation: 342 + 465 = 807, represented in reverse as 7->0->8.
Constraints: 1 <= number of nodes in each list <= 100
Approach: simulate digit-by-digit addition with a carry — O(max(n,m)) time, O(max(n,m)) space

58.Copy List with Random Pointer — (Pattern: Hashing / Interweaving)
Problem: Given a linked list where each node has a next and a random pointer, return
a deep copy of the list.
Input:  head = [[7,null],[13,0],[11,4],[10,2],[1,0]]  (value, random-index pairs)
Output: a fully independent deep copy with matching next/random structure
Explanation: Every new nodes random pointer must point into the new list, not the old one.
Constraints: 0 <= number of nodes <= 1000
Approach: hash map from original node -> cloned node, two passes (or O(1) space via
interweaving clones into the original list) — O(n) time, O(n) space (O(1) with interweaving)

--- Advanced ---

59.Merge K Sorted Lists — (Pattern: Heap / Divide & Conquer)
Problem: Given an array of k sorted linked lists, merge them into one sorted list.
Input:  lists = [[1,4,5],[1,3,4],[2,6]]
Output: [1,1,2,3,4,4,5,6]
Explanation: All nodes merged in ascending order.
Constraints: 0 <= k <= 10^4, 0 <= total nodes <= 10^4
Approach: min-heap of size k holding current head of each list, pop-min & push-next —
O(N log k) time, O(k) space

60.LRU Cache — (Pattern: HashMap + Doubly Linked List) — see Design section
Problem: Design a cache with get(key) and put(key, value) in O(1), evicting the least
recently used entry when capacity is exceeded.
Input:  LRUCache(2); put(1,1); put(2,2); get(1); put(3,3) [evicts key 2]; get(2)
Output: 1, then -1 (not found, key 2 was evicted)
Explanation: Accessing key 1 marks it as recently used, so key 2 is evicted instead.
Constraints: 1 <= capacity <= 3000, up to 2*10^5 calls
Approach: hash map (key -> node) + doubly linked list ordered by recency — O(1) time per op, O(capacity) space

===========================================================================================
7. RECURSION / BACKTRACKING
===========================================================================================

--- Easy ---

61.Fibonacci Number (optimized) — (Pattern: Recursion + DP)
Problem: Compute the nth Fibonacci number, where F(0)=0, F(1)=1, F(n)=F(n-1)+F(n-2).
Input:  n = 10
Output: 55
Explanation: 0,1,1,2,3,5,8,13,21,34,55 — the 10th term (0-indexed) is 55.
Constraints: 0 <= n <= 45
Approach: memoized recursion or bottom-up DP (avoid naive exponential recursion) — O(n) time, O(1) space (iterative)

62.Factorial of a Number — (Pattern: Recursion)
Problem: Compute n! (product of all positive integers up to n).
Input:  n = 5
Output: 120
Explanation: 5*4*3*2*1 = 120
Constraints: 0 <= n <= 20
Approach: simple recursion or iterative loop — O(n) time, O(n) space (recursive) / O(1) (iterative)

63.Pow(x, n) — (Pattern: Divide & Conquer)
Problem: Implement pow(x, n), calculating x raised to the power n.
Input:  x = 2.0, n = 10
Output: 1024.0
Explanation: 2^10 = 1024
Constraints: -100 < x < 100, -2^31 <= n <= 2^31 - 1
Approach: fast exponentiation (square and halve the exponent), handle negative n — O(log n) time, O(log n) space (recursive) or O(1) (iterative)

--- Medium ---

64.Subsets — (Pattern: Backtracking)
Problem: Given an array of unique integers, return all possible subsets (the power set).
Input:  nums = [1, 2, 3]
Output: [[],[1],[2],[1,2],[3],[1,3],[2,3],[1,2,3]]
Explanation: All 2^3 = 8 subsets are generated.
Constraints: 1 <= nums.length <= 10
Approach: backtracking, at each element choose include/exclude — O(2^n) time, O(n) space (recursion depth)

65.Subsets II — (Pattern: Backtracking)
Problem: Given an array that may contain duplicates, return all unique subsets.
Input:  nums = [1, 2, 2]
Output: [[],[1],[1,2],[1,2,2],[2],[2,2]]
Explanation: Sorting first and skipping duplicate siblings avoids repeated subsets.
Constraints: 1 <= nums.length <= 10
Approach: sort array, backtrack, skip duplicate values at the same recursion depth — O(2^n) time, O(n) space

66.Permutations — (Pattern: Backtracking)
Problem: Given an array of distinct integers, return all possible permutations.
Input:  nums = [1, 2, 3]
Output: [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]
Explanation: All 3! = 6 orderings are generated.
Constraints: 1 <= nums.length <= 6
Approach: backtracking with a "used" marker, swap-based or visited-set based — O(n!) time, O(n) space

67.Letter Combinations of a Phone Number — (Pattern: Backtracking)
Problem: Given a string of digits 2-9, return all possible letter combinations the
number could represent (as on a phone keypad).
Input:  digits = "23"
Output: ["ad","ae","af","bd","be","bf","cd","ce","cf"]
Explanation: '2' maps to a/b/c, '3' maps to d/e/f; all combinations are generated.
Constraints: 0 <= digits.length <= 4
Approach: backtracking, build one character per digit at a time — O(4^n) time, O(n) space

68.Combination Sum — (Pattern: Backtracking)
Problem: Given distinct candidates and a target, return all unique combinations that
sum to target; the same number may be reused unlimited times.
Input:  candidates = [2,3,6,7], target = 7
Output: [[2,2,3],[7]]
Explanation: 2+2+3=7 and 7=7 are the only valid combinations.
Constraints: 1 <= candidates.length <= 30, 1 <= target <= 40
Approach: backtracking, allow reusing the same index, prune when sum exceeds target — O(2^target) worst case, O(target) space

69.Combination Sum II — (Pattern: Backtracking)
Problem: Given candidates (may contain duplicates) and a target, return all unique
combinations that sum to target; each number used at most once.
Input:  candidates = [10,1,2,7,6,1,5], target = 8
Output: [[1,1,6],[1,2,5],[1,7],[2,6]]
Explanation: Sorting first and skipping duplicate values at the same depth avoids
repeated combinations.
Constraints: 1 <= candidates.length <= 100
Approach: sort, backtrack advancing index by 1, skip duplicate siblings — O(2^n) time, O(n) space

--- Advanced ---

70.N-Queens — (Pattern: Backtracking)
Problem: Place N queens on an N x N chessboard so that no two queens attack each other;
return all distinct solutions.
Input:  n = 4
Output: 2 solutions: [".Q..","...Q","Q...","..Q."] and ["..Q.","Q...","...Q",".Q.."]
Explanation: Only two arrangements avoid all row/column/diagonal attacks for n=4.
Constraints: 1 <= n <= 9
Approach: backtracking column by column, track attacked columns/diagonals — O(n!) time, O(n) space

71.Word Search — (Pattern: Backtracking + DFS)
Problem: Given a 2D grid of characters and a word, return true if the word exists as a
path of adjacent (horizontally/vertically) cells, each used at most once.
Input:  board = [["A","B","C","E"],["S","F","C","S"],["A","D","E","E"]], word = "ABCCED"
Output: true
Explanation: The path A->B->C->C->E->D traces through adjacent cells.
Constraints: rows, cols <= 6, word.length <= 15
Approach: DFS + backtracking from each cell, mark visited during the path — O(rows*cols*4^L) time, O(L) space

===========================================================================================
8. BINARY SEARCH
===========================================================================================

--- Easy ---

72.Binary Search — (Pattern: Binary Search)
Problem: Given a sorted array nums and a target, return its index, or -1 if not found.
Input:  nums = [-1,0,3,5,9,12], target = 9
Output: 4
Explanation: nums[4] == 9
Constraints: 1 <= nums.length <= 10^4, sorted ascending
Approach: classic binary search, halve the range each step — O(log n) time, O(1) space

73.Sqrt(x) — (Pattern: Binary Search)
Problem: Given a non-negative integer x, return the integer square root (floor of sqrt(x)).
Input:  x = 8
Output: 2
Explanation: sqrt(8) ~= 2.83, floor is 2.
Constraints: 0 <= x <= 2^31 - 1
Approach: binary search on the answer range [0, x] — O(log x) time, O(1) space

--- Medium ---

74.First and Last Position of Element in Sorted Array — (Pattern: Binary Search)
Problem: Given a sorted array and target, find the starting and ending index of targets
occurrences, or [-1,-1] if not found.
Input:  nums = [5,7,7,8,8,10], target = 8
Output: [3, 4]
Explanation: 8 first appears at index 3 and last appears at index 4.
Constraints: 0 <= nums.length <= 10^5
Approach: two binary searches — one for the leftmost, one for the rightmost bound — O(log n) time, O(1) space

75.Search in Rotated Sorted Array — (Pattern: Modified Binary Search)
Problem: Given a rotated sorted array (unique elements) and a target, return its index,
or -1 if not found, in O(log n).
Input:  nums = [4,5,6,7,0,1,2], target = 0
Output: 4
Explanation: nums[4] == 0.
Constraints: 1 <= nums.length <= 5000
Approach: modified binary search — determine which half is sorted, decide which side to search — O(log n) time, O(1) space

76.Find Minimum in Rotated Sorted Array — (Pattern: Binary Search)
Problem: Given a rotated sorted array of unique elements, find the minimum element in
O(log n).
Input:  nums = [4,5,6,7,0,1,2]
Output: 0
Explanation: The array was rotated at the point where 0 appears.
Constraints: 1 <= nums.length <= 5000
Approach: binary search comparing mid to the rightmost element to decide which half
contains the rotation point — O(log n) time, O(1) space

77.Find Peak Element — (Pattern: Binary Search)
Problem: Given an array nums, find a peak element (strictly greater than its neighbors)
and return its index. Assume nums[-1] = nums[n] = -infinity.
Input:  nums = [1,2,3,1]
Output: 2
Explanation: nums[2] = 3 is greater than both neighbors.
Constraints: 1 <= nums.length <= 1000
Approach: binary search, move toward the side with the larger neighbor — O(log n) time, O(1) space

--- Advanced ---

Median of Two Sorted Arrays — see Arrays section

78.Capacity To Ship Packages Within D Days — (Pattern: Binary Search on Answer)
Problem: Given package weights and D days, find the minimum ship capacity so all
packages can be shipped (in order) within D days.
Input:  weights = [1,2,3,4,5,6,7,8,9,10], days = 5
Output: 15
Explanation: With capacity 15, packages can be split into 5 day-groups without exceeding it.
Constraints: 1 <= weights.length <= 5*10^4, 1 <= days <= weights.length
Approach: binary search on capacity range [max(weights), sum(weights)], simulate day
count for each candidate capacity — O(n log(sum)) time, O(1) space

79.Koko Eating Bananas — (Pattern: Binary Search on Answer)
Problem: Given piles of bananas and h hours, find the minimum eating speed k (bananas
per hour) so Koko can eat all bananas within h hours.
Input:  piles = [3,6,7,11], h = 8
Output: 4
Explanation: At speed 4, total hours needed = ceil(3/4)+ceil(6/4)+ceil(7/4)+ceil(11/4) = 8.
Constraints: 1 <= piles.length <= 10^4, piles.length <= h <= 10^9
Approach: binary search on speed range [1, max(piles)], compute hours needed for each
candidate speed — O(n log(max(piles))) time, O(1) space

===========================================================================================
9. SLIDING WINDOW
===========================================================================================

--- Easy ---

80.Maximum Sum Subarray of Size K — (Pattern: Fixed Sliding Window)
Problem: Given an array and integer k, find the maximum sum of any contiguous
subarray of size k.
Input:  arr = [2, 1, 5, 1, 3, 2], k = 3
Output: 9
Explanation: Subarray [5, 1, 3] has the maximum sum of 9.
Constraints: 1 <= arr.length <= 10^5, 1 <= k <= arr.length
Approach: fixed-size sliding window, add new element and remove the one leaving — O(n) time, O(1) space

--- Medium ---

Longest Substring Without Repeating Characters — see Strings section

81.Permutation in String — (Pattern: Sliding Window)
Problem: Given strings s1 and s2, return true if s2 contains a permutation of s1 as a
contiguous substring.
Input:  s1 = "ab", s2 = "eidbaooo"
Output: true
Explanation: s2 contains "ba", which is a permutation of "ab".
Constraints: 1 <= s1.length, s2.length <= 10^4
Approach: fixed-size sliding window of length s1.length, compare frequency counts — O(n) time, O(1) space (fixed alphabet)

82.Subarray Product Less Than K — (Pattern: Variable Sliding Window)
Problem: Given an array of positive integers and an integer k, count the number of
contiguous subarrays where the product of all elements is less than k.
Input:  nums = [10, 5, 2, 6], k = 100
Output: 8
Explanation: Subarrays [10],[5],[2],[6],[10,5],[5,2],[2,6],[5,2,6] all have product < 100.
Constraints: 1 <= nums.length <= 3*10^4, 1 <= nums[i] <= 1000
Approach: variable sliding window, shrink from left while product >= k, add (right-left+1) each step — O(n) time, O(1) space

83.Longest Repeating Character Replacement — (Pattern: Sliding Window)
Problem: Given a string s and integer k, find the length of the longest substring
achievable by replacing at most k characters with any other character, such that all
characters become the same.
Input:  s = "AABABBA", k = 1
Output: 4
Explanation: Replace one 'B' with 'A' in "AABA" to get "AAAA", length 4.
Constraints: 1 <= s.length <= 10^5
Approach: sliding window, shrink when (window size - max char frequency) > k — O(n) time, O(1) space (fixed alphabet)

--- Advanced ---

84.Minimum Window Substring — see Strings section

===========================================================================================
10. BIT MANIPULATION (was missing — high frequency in screening rounds)
===========================================================================================

--- Easy ---

85.Single Number — (Pattern: XOR)
Problem: Given an array where every element appears twice except one, find that
single element in linear time and O(1) space.
Input:  nums = [4, 1, 2, 1, 2]
Output: 4
Explanation: XOR-ing all elements cancels out pairs, leaving the unique one.
Constraints: 1 <= nums.length <= 3*10^4
Approach: XOR all elements together — O(n) time, O(1) space

86.Number of 1 Bits — (Pattern: Bit Manipulation)
Problem: Given an unsigned integer, return the number of '1' bits it has (Hamming weight).
Input:  n = 11 (binary 1011)
Output: 3
Explanation: Binary 1011 has three set bits.
Constraints: n is a 32-bit unsigned integer
Approach: repeatedly clear the lowest set bit with n & (n-1), count iterations — O(number of set bits) time, O(1) space

87.Power of Two — (Pattern: Bit Manipulation)
Problem: Given an integer n, return true if it is a power of two.
Input:  n = 16
Output: true
Explanation: 16 = 2^4, and in binary it has exactly one set bit.
Constraints: -2^31 <= n <= 2^31 - 1
Approach: check n > 0 and (n & (n-1)) == 0 — O(1) time, O(1) space

--- Medium ---

88.Counting Bits — (Pattern: DP + Bit Manipulation)
Problem: Given n, return an array ans where ans[i] is the number of set bits in i, for
every i from 0 to n.
Input:  n = 5
Output: [0,1,1,2,1,2]
Explanation: 0=0,1=1,2=10,3=11,4=100,5=101 — set bit counts are 0,1,1,2,1,2.
Constraints: 0 <= n <= 10^5
Approach: DP using ans[i] = ans[i >> 1] + (i & 1) — O(n) time, O(n) space

89.Missing Number — (Pattern: XOR / Sum)
Problem: Given an array containing n distinct numbers from 0 to n, find the missing one.
Input:  nums = [3, 0, 1]
Output: 2
Explanation: Numbers 0..3 minus the present ones [3,0,1] leaves 2 missing.
Constraints: 1 <= nums.length <= 10^4
Approach: XOR all indices and values together, or use sum formula n*(n+1)/2 minus
actual sum — O(n) time, O(1) space

===========================================================================================
11. HEAP / PRIORITY QUEUE (was missing as an explicit pattern)
===========================================================================================

--- Medium ---

90.Kth Largest Element in an Array — (Pattern: Min-Heap / Quickselect)
Problem: Given an integer array nums and integer k, return the kth largest element
(kth largest in sorted order, not the kth distinct one).
Input:  nums = [3,2,1,5,6,4], k = 2
Output: 5
Explanation: Sorted descending: [6,5,4,3,2,1]; the 2nd largest is 5.
Constraints: 1 <= k <= nums.length <= 10^5
Approach: min-heap of size k (push, pop when size exceeds k) — O(n log k) time, O(k) space;
or Quickselect for average O(n) time, O(1) space

Top K Frequent Elements — see Hashing section

--- Advanced ---

Merge K Sorted Lists — see Linked List section

91.Find Median from Data Stream — (Pattern: Two Heaps)
Problem: Design a structure that supports adding a number and finding the median of
all numbers added so far, with addNum in O(log n).
Input:  addNum(1), addNum(2), findMedian(), addNum(3), findMedian()
Output: 1.5, then 2
Explanation: After [1,2], median is (1+2)/2 = 1.5; after [1,2,3], median is 2.
Constraints: up to 5*10^4 calls
Approach: a max-heap for the smaller half, a min-heap for the larger half, rebalance
after each insert — O(log n) time per insert, O(1) time for median, O(n) space

===========================================================================================
12. TRIE (was missing entirely)
===========================================================================================

--- Medium ---

92.Implement Trie (Prefix Tree) — (Pattern: Trie)
Problem: Implement a trie with insert(word), search(word) (exact match), and
startsWith(prefix) (any word has this prefix).
Input:  insert("apple"); search("apple"); search("app"); startsWith("app")
Output: true, false, true
Explanation: "apple" was inserted exactly; "app" was never inserted as a full word,
but it is a valid prefix.
Constraints: 1 <= word.length <= 2000, up to 3*10^4 calls total
Approach: tree of child-node maps (26 children per node typically), mark word-end flags — O(L) time per operation (L = word length), O(total characters) space

93.Design Add and Search Words Data Structure — (Pattern: Trie + DFS)
Problem: Design a structure supporting addWord(word) and search(word), where search
may contain '.' to match any single character.
Input:  addWord("bad"); addWord("dad"); addWord("mad"); search("pad"); search(".ad"); search("b..")
Output: false, true, true
Explanation: ".ad" matches "bad"/"dad"/"mad"; "b.." matches "bad".
Constraints: 1 <= word.length <= 25, up to 10^4 calls
Approach: trie insert as usual; search does DFS, branching over all children when a
'.' is encountered — O(26^m) worst case for search with wildcards, O(total characters) space

===========================================================================================
13. DESIGN PROBLEMS (was missing — LRU Cache is asked constantly)
===========================================================================================

Min Stack — see Stack section

--- Advanced ---

LRU Cache — see Linked List section (Advanced)

94.LFU Cache — (Pattern: HashMap + Frequency Buckets)
Problem: Design a cache with get(key) and put(key, value) in O(1), evicting the
Least Frequently Used entry on eviction (break ties by least recently used).
Input:  LFUCache(2); put(1,1); put(2,2); get(1); put(3,3) [evicts key 2, freq 1 vs key 1 freq 2]; get(2); get(3)
Output: 1, then -1, then 3
Explanation: Key 2 has the lowest usage frequency at eviction time, so it is removed.
Constraints: 0 <= capacity <= 10^4, up to 2*10^5 calls
Approach: hash map (key -> value/freq) + hash map (freq -> ordered set/list of keys),
track min frequency — O(1) time per op, O(capacity) space

===========================================================================================
14. MATRIX (was missing entirely)
===========================================================================================

--- Medium ---

95.Rotate Image — (Pattern: Layer-by-Layer Swap)
Problem: Given an n x n 2D matrix, rotate it 90 degrees clockwise, in-place.
Input:  matrix = [[1,2,3],[4,5,6],[7,8,9]]
Output: [[7,4,1],[8,5,2],[9,6,3]]
Explanation: Each element moves to its rotated position; row 1 becomes column (n-1).
Constraints: 1 <= n <= 20
Approach: transpose the matrix, then reverse each row (or rotate in groups of 4 cells) — O(n^2) time, O(1) space

96.Spiral Matrix — (Pattern: Boundary Simulation)
Problem: Given an m x n matrix, return all elements in spiral order.
Input:  matrix = [[1,2,3],[4,5,6],[7,8,9]]
Output: [1,2,3,6,9,8,7,4,5]
Explanation: Traverse right across the top row, down the right column, left across
the bottom row, up the left column, and shrink boundaries inward.
Constraints: 1 <= m, n <= 10
Approach: maintain top/bottom/left/right boundaries, walk and shrink after each side — O(m*n) time, O(1) extra space

97.Set Matrix Zeroes — (Pattern: Matrix Marking)
Problem: Given an m x n matrix, if an element is 0, set its entire row and column to
0, in-place.
Input:  matrix = [[1,1,1],[1,0,1],[1,1,1]]
Output: [[1,0,1],[0,0,0],[1,0,1]]
Explanation: The single 0 at (1,1) zeroes out row 1 and column 1 entirely.
Constraints: 1 <= m, n <= 200
Approach: use the first row/column as markers for which rows/cols to zero, with a
separate flag for the first row/column itself — O(m*n) time, O(1) extra space

===========================================================================================
15. DYNAMIC PROGRAMMING
===========================================================================================

--- Basic ---

98.Climbing Stairs — (Pattern: 1D DP)
Problem: You can climb 1 or 2 steps at a time. Given n steps, count the distinct ways
to reach the top.
Input:  n = 3
Output: 3
Explanation: Ways: (1,1,1), (1,2), (2,1).
Constraints: 1 <= n <= 45
Approach: dp[i] = dp[i-1] + dp[i-2] (Fibonacci-like) — O(n) time, O(1) space

99.House Robber — (Pattern: 1D DP)
Problem: Given houses with money amounts, find the max amount you can rob without
robbing two adjacent houses.
Input:  nums = [1, 2, 3, 1]
Output: 4
Explanation: Rob house 1 (1) and house 3 (3): 1 + 3 = 4.
Constraints: 1 <= nums.length <= 100
Approach: dp[i] = max(dp[i-1], dp[i-2] + nums[i]) — O(n) time, O(1) space

100.Coin Change (minimum coins) — (Pattern: Unbounded Knapsack)
Problem: Given coin denominations and an amount, return the fewest coins needed to
make that amount, or -1 if impossible.
Input:  coins = [1, 2, 5], amount = 11
Output: 3
Explanation: 11 = 5 + 5 + 1, using 3 coins.
Constraints: 1 <= coins.length <= 12, 0 <= amount <= 10^4
Approach: bottom-up DP, dp[a] = min(dp[a - coin] + 1) over all coins — O(amount * coins) time, O(amount) space

101.Coin Change II (number of ways) — (Pattern: Unbounded Knapsack)
Problem: Given coin denominations and an amount, return the number of distinct
combinations that make up that amount.
Input:  amount = 5, coins = [1, 2, 5]
Output: 4
Explanation: Combinations: [5], [1,2,2], [1,1,1,2], [1,1,1,1,1].
Constraints: 1 <= coins.length <= 300, 0 <= amount <= 5000
Approach: DP iterating coins in the outer loop, amounts in the inner loop (avoids
counting permutations as distinct) — O(amount * coins) time, O(amount) space

102.Longest Increasing Subsequence — (Pattern: 1D DP / Binary Search)
Problem: Given an array, return the length of the longest strictly increasing
subsequence.
Input:  nums = [10,9,2,5,3,7,101,18]
Output: 4
Explanation: The LIS is [2,3,7,101] (or [2,3,7,18]), length 4.
Constraints: 1 <= nums.length <= 2500
Approach: O(n^2) DP (dp[i] = longest ending at i), or O(n log n) with binary search
over a "tails" array — O(n log n) time (optimal), O(n) space

103. 0/1 Knapsack — (Pattern: 2D DP)
Problem: Given item weights/values and a capacity W, maximize value without exceeding
W, each item usable at most once.
Input:  weights = [1,3,4,5], values = [1,4,5,7], W = 7
Output: 9
Explanation: Choosing items with weight 3 and 4 (values 4 + 5 = 9) fits within capacity 7.
Constraints: 1 <= n <= 1000, 1 <= W <= 1000
Approach: 2D DP, dp[i][w] = max value using first i items with capacity w — O(n*W) time, O(n*W) space (or O(W) with rolling array)

104.Unique Paths — (Pattern: Grid DP)
Problem: Given an m x n grid, count paths from top-left to bottom-right moving only
right or down.
Input:  m = 3, n = 7
Output: 28
Explanation: Combinatorially, C(m+n-2, m-1) = C(8,2) = 28.
Constraints: 1 <= m, n <= 100
Approach: dp[i][j] = dp[i-1][j] + dp[i][j-1] — O(m*n) time, O(n) space (rolling row)

105.Target Sum — (Pattern: DP as Subset Sum)
Problem: Given nums and a target, assign each number a '+' or '-' sign so the
expression sums to target; count the number of ways.
Input:  nums = [1,1,1,1,1], target = 3
Output: 5
Explanation: 5 distinct sign assignments sum to 3, e.g. +1+1+1+1-1.
Constraints: 1 <= nums.length <= 20
Approach: transform into subset-sum DP: find subset summing to (total+target)/2 — O(n * sum) time, O(sum) space

--- Medium / Classic ---

106.Word Break — (Pattern: 1D DP)
Problem: Given a string s and a dictionary of words, return true if s can be
segmented into a space-separated sequence of dictionary words.
Input:  s = "leetcode", wordDict = ["leet","code"]
Output: true
Explanation: "leetcode" splits into "leet" + "code", both in the dictionary.
Constraints: 1 <= s.length <= 300, 1 <= wordDict.length <= 1000
Approach: dp[i] = true if some j < i has dp[j] true and s[j:i] in dictionary — O(n^2) time, O(n) space

107.Partition Equal Subset Sum — (Pattern: Subset Sum DP)
Problem: Given an array, determine if it can be partitioned into two subsets with
equal sum.
Input:  nums = [1, 5, 11, 5]
Output: true
Explanation: [11] and [1,5,5] both sum to 11.
Constraints: 1 <= nums.length <= 200
Approach: subset-sum DP for target = total/2 — O(n * sum) time, O(sum) space

108.Longest Common Subsequence — (Pattern: 2D DP)
Problem: Given two strings, return the length of their longest common subsequence.
Input:  text1 = "abcde", text2 = "ace"
Output: 3
Explanation: "ace" is a common subsequence of both, length 3.
Constraints: 1 <= text1.length, text2.length <= 1000
Approach: 2D DP, dp[i][j] = dp[i-1][j-1]+1 if chars match, else max(dp[i-1][j], dp[i][j-1]) — O(n*m) time, O(n*m) space (O(min(n,m)) with rolling array)

109.Edit Distance — (Pattern: 2D DP)
Problem: Given two strings word1 and word2, return the minimum number of
insert/delete/replace operations to convert word1 into word2.
Input:  word1 = "horse", word2 = "ros"
Output: 3
Explanation: horse -> rorse (replace h->r) -> rose (delete r) -> ros (delete e)
Constraints: 0 <= word1.length, word2.length <= 500
Approach: 2D DP, dp[i][j] = min of insert/delete/replace costs from smaller subproblems — O(n*m) time, O(n*m) space

110.Matrix Chain Multiplication — (Pattern: Interval DP)
Problem: Given dimensions of matrices to multiply in sequence, find the minimum
number of scalar multiplications needed to compute the product.
Input:  dims = [10, 20, 30, 40, 30]  (4 matrices)
Output: 30000
Explanation: Optimal parenthesization ((A1 A2) A3) A4 minimizes total multiplication cost.
Constraints: 2 <= dims.length <= 100
Approach: interval DP over (i, j) subchains, trying every split point k — O(n^3) time, O(n^2) space

--- Advanced ---

111.Weighted Job Scheduling — (Pattern: DP + Binary Search)
Problem: Given jobs with start time, end time, and profit, find the maximum profit
achievable by scheduling non-overlapping jobs.
Input:  jobs = [(1,3,50),(3,5,20),(6,19,100),(2,100,200)]
Output: 250
Explanation: Picking jobs (1,3,50) and (2,100,200) is invalid (overlap); the optimal
non-overlapping subset yields 250 (200 + 50).
Constraints: 1 <= jobs.length <= 5*10^4
Approach: sort by end time, DP with binary search to find the latest non-conflicting
job before each one — O(n log n) time, O(n) space

112.DP on Intervals (e.g. Burst Balloons) — (Pattern: Interval DP)
Problem: Given balloons with numbers, bursting a balloon gives coins = left * current
* right (of remaining balloons); maximize total coins from bursting all balloons.
Input:  nums = [3,1,5,8]
Output: 167
Explanation: Bursting in the order 1, 5, 3, 8 yields the maximum total of 167.
Constraints: 1 <= nums.length <= 300
Approach: interval DP, dp[i][j] = max coins bursting all balloons strictly between i
and j, trying every last-balloon-to-burst k — O(n^3) time, O(n^2) space

113.DP on Trees, basic idea (e.g. House Robber III) — (Pattern: Tree DP)
Problem: Given a binary tree representing houses, rob houses such that no two
directly-connected (parent-child) houses are robbed; maximize total money.
Input:  tree = [3,2,3,null,3,null,1]
Output: 7
Explanation: Rob the root's grandchildren (2's child 3, and node 3, and node 1): 3+3+1=7.
Constraints: 1 <= number of nodes <= 10^4
Approach: post-order DFS returning a pair (max if this node robbed, max if not) — O(n) time, O(h) space (h = tree height)

===========================================================================================
16. TIME & SPACE COMPLEXITY / CONCEPTUAL (Discussion — no code)
===========================================================================================
  - Why does HashMap give O(1) average lookup?
  - What is the worst case of HashMap, and why?
  - What is amortized time complexity?
  - Practical difference between O(n log n) and O(n^2)?
  - Space complexity of a recursive call stack?
  - Why is quicksort worst case O(n^2)?

===========================================================================================
17. BINARY TREE TRAVERSALS (MUST)
===========================================================================================

114.Binary Tree Inorder Traversal — (Pattern: DFS)
Problem: Given the root of a binary tree, return its inorder traversal (left, root, right).
Input:  root = [1,null,2,3]
Output: [1,3,2]
Explanation: Inorder visits left subtree, then root, then right subtree.
Constraints: 0 <= number of nodes <= 100
Approach: recursive DFS, or iterative with an explicit stack — O(n) time, O(n) space

115.Binary Tree Preorder / Postorder Traversal — (Pattern: DFS)
Problem: Return the preorder (root, left, right) or postorder (left, right, root)
traversal of a binary tree.
Input:  root = [1,null,2,3]
Output: Preorder: [1,2,3], Postorder: [3,2,1]
Explanation: Order of visiting root relative to children differs per traversal type.
Constraints: 0 <= number of nodes <= 100
Approach: recursive DFS, or iterative with a stack (postorder needs a second stack or
reversed preorder trick) — O(n) time, O(n) space

116.Binary Tree Level Order Traversal — (Pattern: BFS)
Problem: Given the root of a binary tree, return the level-order traversal (values
grouped by depth level).
Input:  root = [3,9,20,null,null,15,7]
Output: [[3],[9,20],[15,7]]
Explanation: Level 0 has [3], level 1 has [9,20], level 2 has [15,7].
Constraints: 0 <= number of nodes <= 2000
Approach: BFS with a queue, process one full level at a time — O(n) time, O(n) space

117.Binary Tree Zigzag Level Order Traversal — (Pattern: BFS + direction flag)
Problem: Return level-order traversal, but alternate direction per level (left-to-right,
then right-to-left, etc).
Input:  root = [3,9,20,null,null,15,7]
Output: [[3],[20,9],[15,7]]
Explanation: Level 0 left-to-right, level 1 reversed to right-to-left.
Constraints: 0 <= number of nodes <= 2000
Approach: BFS with a queue, reverse the collected level values on alternating levels — O(n) time, O(n) space

===========================================================================================
18. BASIC TREE PROPERTIES
===========================================================================================

118.Maximum Depth of Binary Tree — (Pattern: DFS)
Problem: Given a binary tree, return its maximum depth (longest root-to-leaf path node count).
Input:  root = [3,9,20,null,null,15,7]
Output: 3
Explanation: The path 3 -> 20 -> 15 (or 7) has 3 nodes.
Constraints: 0 <= number of nodes <= 10^4
Approach: recursive DFS, 1 + max(depth(left), depth(right)) — O(n) time, O(h) space

119.Minimum Depth of Binary Tree — (Pattern: BFS/DFS)
Problem: Given a binary tree, return its minimum depth (shortest root-to-leaf path).
Input:  root = [3,9,20,null,null,15,7]
Output: 2
Explanation: Path 3 -> 9 reaches a leaf in 2 nodes.
Constraints: 0 <= number of nodes <= 10^5
Approach: BFS (stop at first leaf found) is more efficient than DFS here — O(n) time, O(n) space

120.Check if Two Trees are Identical — (Pattern: DFS)
Problem: Given two binary trees, check if they are structurally identical with the
same node values.
Input:  p = [1,2,3], q = [1,2,3]
Output: true
Explanation: Both trees have identical structure and values at every node.
Constraints: 0 <= number of nodes in each tree <= 100
Approach: recursive DFS comparing values and recursing on left/right pairs — O(n) time, O(h) space

121.Invert Binary Tree — (Pattern: DFS/BFS)
Problem: Given the root of a binary tree, invert it (mirror left and right children
at every node) and return the root.
Input:  root = [4,2,7,1,3,6,9]
Output: [4,7,2,9,6,3,1]
Explanation: Left and right children are swapped at every level.
Constraints: 0 <= number of nodes <= 100
Approach: recursively swap left/right children — O(n) time, O(h) space

122.Check if a Tree is Symmetric — (Pattern: DFS)
Problem: Given the root of a binary tree, check if it is a mirror of itself around its
center.
Input:  root = [1,2,2,3,4,4,3]
Output: true
Explanation: The left and right subtrees are mirror images of each other.
Constraints: 1 <= number of nodes <= 1000
Approach: recursive comparison of left.left vs right.right and left.right vs right.left — O(n) time, O(h) space

===========================================================================================
19. BINARY SEARCH TREE (BST)
===========================================================================================

123.Validate BST — (Pattern: DFS with range bounds)
Problem: Given the root of a binary tree, determine if it is a valid BST.
Input:  root = [5,1,4,null,null,3,6]
Output: false
Explanation: Node 4's right child is 6, but node 4's right subtree also contains 3,
which is less than 4 — violates BST property relative to node 5.
Constraints: 1 <= number of nodes <= 10^4
Approach: recursive DFS passing down (min, max) valid bounds at each node — O(n) time, O(h) space

124.Search in a BST — (Pattern: BST property)
Problem: Given the root of a BST and a value, return the subtree rooted at the node
with that value, or null if not found.
Input:  root = [4,2,7,1,3], val = 2
Output: subtree rooted at [2,1,3]
Explanation: BST property lets us go left/right based on comparison at each node.
Constraints: 1 <= number of nodes <= 5000
Approach: iterative descent, go left if val < node.val, right if greater — O(h) time, O(1) space

125.Insert into a BST — (Pattern: BST property)
Problem: Given a BST root and a value, insert it into the BST and return the root.
Input:  root = [4,2,7,1,3], val = 5
Output: [4,2,7,1,3,5]
Explanation: 5 is inserted as the left child of 7 (since 5 < 7 and 5 > 4).
Constraints: 0 <= number of nodes <= 10^4
Approach: descend left/right based on comparison until a null spot is found, attach
new node — O(h) time, O(h) space (recursive) or O(1) (iterative)

126.Delete a Node in a BST — (Pattern: BST property)
Problem: Given a BST root and a key, delete the node with that key and return the
updated root, maintaining BST properties.
Input:  root = [5,3,6,2,4,null,7], key = 3
Output: [5,4,6,2,null,null,7]  (or an equivalent valid BST)
Explanation: Node 3 is replaced by its inorder successor (4).
Constraints: 0 <= number of nodes <= 10^4
Approach: find the node; if it has two children, replace its value with the inorder
successor (or predecessor) and delete that successor recursively — O(h) time, O(h) space

127.Lowest Common Ancestor of a BST — (Pattern: BST property)
Problem: Given a BST and two nodes p, q, find their lowest common ancestor.
Input:  root = [6,2,8,0,4,7,9,null,null,3,5], p = 2, q = 8
Output: 6
Explanation: 2 and 8 diverge at the root, so 6 is the LCA.
Constraints: 2 <= number of nodes <= 10^5
Approach: descend from root — if both p,q are smaller go left, both larger go right,
otherwise current node is the LCA — O(h) time, O(1) space

128.Kth Smallest Element in a BST — (Pattern: Inorder Traversal)
Problem: Given a BST and integer k, return the kth smallest value in the tree.
Input:  root = [3,1,4,null,2], k = 1
Output: 1
Explanation: Inorder traversal of a BST yields sorted order: [1,2,3,4]; the 1st is 1.
Constraints: 1 <= number of nodes <= 10^4
Approach: inorder traversal (iterative with a stack), stop at the kth visited node — O(h + k) time, O(h) space

===========================================================================================
20. IMPORTANT BINARY TREE PROBLEMS
===========================================================================================

129.Lowest Common Ancestor of a Binary Tree — (Pattern: DFS)
Problem: Given a general binary tree (not necessarily BST) and two nodes p, q, find
their lowest common ancestor.
Input:  root = [3,5,1,6,2,0,8,null,null,7,4], p = 5, q = 1
Output: 3
Explanation: 5 and 1 are on different sides of the root, so 3 is the LCA.
Constraints: 2 <= number of nodes <= 10^5
Approach: recursive DFS — if current node is p or q, return it; if both children
return non-null, current node is the LCA — O(n) time, O(h) space

130.Diameter of Binary Tree — (Pattern: DFS)
Problem: Given a binary tree, return the length (in edges) of the longest path
between any two nodes (may or may not pass through the root).
Input:  root = [1,2,3,4,5]
Output: 3
Explanation: The longest path is 4 -> 2 -> 1 -> 3 (or 5 -> 2 -> 1 -> 3), 3 edges.
Constraints: 1 <= number of nodes <= 10^4
Approach: post-order DFS returning height, update a global max using left height +
right height at each node — O(n) time, O(h) space

131.Balanced Binary Tree — (Pattern: DFS)
Problem: Given a binary tree, determine if it is height-balanced (heights of the two
subtrees of every node differ by no more than 1).
Input:  root = [3,9,20,null,null,15,7]
Output: true
Explanation: Every subtree's  left/right height difference is' at most 1.
Constraints: 0 <= number of nodes <= 5000
Approach: post-order DFS returning height, short-circuit and return -1/false as soon
as imbalance is found — O(n) time, O(h) space

132.Path Sum — (Pattern: DFS)
Problem: Given a binary tree and a target sum, determine if there is a root-to-leaf
path such that the sum of node values equals the target.
Input:  root = [5,4,8,11,null,13,4,7,2,null,null,null,1], targetSum = 22
Output: true
Explanation: Path 5 -> 4 -> 11 -> 2 sums to 22.
Constraints: 0 <= number of nodes <= 5000
Approach: recursive DFS subtracting node value from remaining target, check at leaves — O(n) time, O(h) space

133.Binary Tree Right Side View — (Pattern: BFS or DFS)
Problem: Given a binary tree, return the values visible from the right side, ordered
top to bottom.
Input:  root = [1,2,3,null,5,null,4]
Output: [1, 3, 4]
Explanation: Looking from the right, at each level the rightmost node is visible.
Constraints: 0 <= number of nodes <= 100
Approach: BFS, take the last node of each level (or DFS right-first, track first
node seen per depth) — O(n) time, O(n) space

134.Count Good Nodes — (Pattern: DFS)
Problem: A node is "good" if no node on the path from root to it has a value greater
than it. Count the good nodes in a binary tree.
Input:  root = [3,1,4,3,null,1,5]
Output: 4
Explanation: Nodes 3(root), 3, 4, 5 are all good (nothing greater appears before them).
Constraints: 1 <= number of nodes <= 10^5
Approach: DFS carrying the max value seen so far on the path — O(n) time, O(h) space

135.Binary Tree Maximum Path Sum — (Pattern: DFS)
Problem: Given a binary tree, return the maximum path sum between any two nodes
(path need not pass through the root, and may not branch).
Input:  root = [-10,9,20,null,null,15,7]
Output: 42
Explanation: Path 15 -> 20 -> 7 sums to 42.
Constraints: 1 <= number of nodes <= 3*10^4
Approach: post-order DFS returning the best downward-extendable sum from each node,
update a global max using left + node + right at each node — O(n) time, O(h) space

===========================================================================================
21. TREE CONSTRUCTION
===========================================================================================

136.Construct Binary Tree from Preorder and Inorder Traversal — (Pattern: Recursion + Hashing)
Problem: Given preorder and inorder traversal arrays of a binary tree with unique
values, reconstruct and return the tree.
Input:  preorder = [3,9,20,15,7], inorder = [9,3,15,20,7]
Output: [3,9,20,null,null,15,7]
Explanation: The first preorder element (3) is the root; its position in inorder
splits the tree into left/right subtrees.
Constraints: 1 <= number of nodes <= 3000
Approach: recursively pick the root from preorder, locate it in inorder (via a hash
map for O(1) lookup) to split subtrees — O(n) time, O(n) space

137.Construct Binary Tree from Inorder and Postorder Traversal — (Pattern: Recursion + Hashing)
Problem: Given inorder and postorder traversal arrays, reconstruct and return the tree.
Input:  inorder = [9,3,15,20,7], postorder = [9,15,7,20,3]
Output: [3,9,20,null,null,15,7]
Explanation: The last postorder element (3) is the root; its inorder position splits
left/right subtrees.
Constraints: 1 <= number of nodes <= 3000
Approach: recursively pick the root from the end of postorder, locate it in inorder
via a hash map — O(n) time, O(n) space

===========================================================================================
22. ADVANCED TREE PROBLEMS
===========================================================================================

138.Serialize and Deserialize Binary Tree — (Pattern: DFS/BFS + Encoding)
Problem: Design an algorithm to serialize a binary tree to a string and deserialize
that string back to the original tree structure.
Input:  root = [1,2,3,null,null,4,5]
Output: serialized string like "1,2,#,#,3,4,#,#,5,#,#", then deserialized back to the same tree
Explanation: Null markers preserve exact tree shape for reconstruction.
Constraints: 0 <= number of nodes <= 10^4
Approach: preorder DFS with explicit null markers for serialization; reconstruct
recursively consuming tokens in the same order for deserialization — O(n) time, O(n) space

139.Flatten Binary Tree to Linked List — (Pattern: DFS / Morris-style)
Problem: Given a binary tree, flatten it in-place into a "linked list" following
preorder traversal, using only the right child pointers.
Input:  root = [1,2,5,3,4,null,6]
Output: [1,null,2,null,3,null,4,null,5,null,6]
Explanation: Nodes are rearranged into a single right-skewed chain in preorder sequence.
Constraints: 0 <= number of nodes <= 2000
Approach: recursively flatten left and right subtrees, then splice flattened left
between node and flattened right — O(n) time, O(h) space

140.Vertical Order Traversal of a Binary Tree — (Pattern: DFS/BFS + Sorting)
Problem: Given a binary tree, return its vertical order traversal: group nodes by
column, top to bottom, left to right, sorted by value on ties.
Input:  root = [3,9,20,null,null,15,7]
Output: [[9],[3,15],[20],[7]]
Explanation: Column -1 has [9], column 0 has [3,15], column 1 has [20], column 2 has [7].
Constraints: 0 <= number of nodes <= 1000
Approach: BFS/DFS tracking (row, col) per node, group by col, sort by (row, then
value) within each column — O(n log n) time, O(n) space

===========================================================================================
23. TREE CONCEPTUAL QUESTIONS (Discussion — no code)
===========================================================================================
  - Difference between Binary Tree and BST?
  - Why is average BST time O(log n)? When does it degrade?
  - What makes a tree "balanced"?
  - Height vs Depth — what is the difference?
  - Full vs Complete vs Perfect Binary Tree — differences?

===========================================================================================
24. GRAPH TRAVERSALS & REPRESENTATION (MUST)
===========================================================================================

141..BFS Traversal of a Graph — (Pattern: BFS)
Problem: Given a graph (as adjacency list) and a start node, return nodes in
breadth-first traversal order.
Input:  graph = {0:[1,2], 1:[2], 2:[0,3], 3:[3]}, start = 2
Output: [2, 0, 3, 1]
Explanation: BFS visits all neighbors of the current node before going deeper.
Constraints: 1 <= nodes <= 100
Approach: queue-based traversal with a visited set — O(V+E) time, O(V) space

142.DFS Traversal, recursive and iterative — (Pattern: DFS)
Problem: Given a graph and a start node, return nodes in depth-first traversal order.
Input:  graph = {0:[1,2], 1:[2], 2:[0,3], 3:[3]}, start = 2
Output: [2, 0, 1, 3]
Explanation: DFS goes as deep as possible before backtracking.
Constraints: 1 <= nodes <= 100
Approach: recursion (or explicit stack for iterative), track a visited set — O(V+E) time, O(V) space

143.Implement Graph Representation using an Adjacency List — (Pattern: Graph Representation)
Problem: Given a list of edges, build an adjacency list representation of the graph
(directed or undirected).
Input:  edges = [[0,1],[1,2],[2,0]], undirected
Output: {0:[1,2], 1:[0,2], 2:[1,0]}
Explanation: Each node maps to the list of its directly connected neighbors.
Constraints: 1 <= edges.length <= 10^5
Approach: hash map (or array) of lists, append both directions for undirected edges — O(V+E) time, O(V+E) space

144.Implement Graph Representation using an Adjacency Matrix — (Pattern: Graph Representation)
Problem: Given a list of edges and number of nodes n, build an n x n adjacency
matrix representation.
Input:  n = 3, edges = [[0,1],[1,2]], undirected
Output: [[0,1,0],[1,0,1],[0,1,0]]
Explanation: matrix[i][j] = 1 if an edge exists between i and j.
Constraints: 1 <= n <= 500
Approach: initialize an n x n matrix of zeroes, set matrix[u][v] (and matrix[v][u]
for undirected) = 1 per edge — O(n^2) space, O(E) time to populate

===========================================================================================
25. CONNECTED COMPONENTS
===========================================================================================

145.Number of Connected Components in an Undirected Graph — (Pattern: DFS/BFS or Union-Find)
Problem: Given n nodes and a list of undirected edges, return the number of connected
components.
Input:  n = 5, edges = [[0,1],[1,2],[3,4]]
Output: 2
Explanation: {0,1,2} form one component, {3,4} form another.
Constraints: 1 <= n <= 2000
Approach: DFS/BFS from each unvisited node (count launches), or Union-Find counting
distinct roots — O(V+E) time, O(V) space

146.Number of Provinces — (Pattern: DFS/Union-Find)
Problem: Given an n x n matrix isConnected where isConnected[i][j]=1 means cities i
and j are directly connected, return the number of provinces (connected groups).
Input:  isConnected = [[1,1,0],[1,1,0],[0,0,1]]
Output: 2
Explanation: Cities 0 and 1 are connected (one province); city 2 is separate.
Constraints: 1 <= n <= 200
Approach: DFS/BFS over the matrix treating it as an adjacency matrix, or Union-Find — O(n^2) time, O(n) space

147.Number of Islands — (Pattern: DFS/BFS on Grid)
Problem: Given a 2D grid of '1' (land) and '0' (water), return the number of islands
(connected groups of land, 4-directionally).
Input:  grid = [["1","1","0","0"],["1","1","0","0"],["0","0","1","0"],["0","0","0","1"]]
Output: 3
Explanation: Two separate land blocks plus one isolated land cell = 3 islands.
Constraints: 1 <= rows, cols <= 300
Approach: DFS/BFS flood-fill from each unvisited land cell, marking visited cells — O(rows*cols) time, O(rows*cols) space

===========================================================================================
26. CYCLE DETECTION
===========================================================================================

148.Detect Cycle in an Undirected Graph — (Pattern: DFS/Union-Find)
Problem: Given an undirected graph, determine if it contains a cycle.
Input:  n = 4, edges = [[0,1],[1,2],[2,3],[3,0]]
Output: true
Explanation: 0-1-2-3-0 forms a cycle.
Constraints: 1 <= n <= 2000
Approach: DFS tracking parent (a visited neighbor that is not the parent means a
cycle), or Union-Find (edge connecting two already-unioned nodes means a cycle) — O(V+E) time, O(V) space

149.Detect Cycle in a Directed Graph — (Pattern: DFS + Recursion Stack)
Problem: Given a directed graph, determine if it contains a cycle.
Input:  n = 4, edges = [[0,1],[1,2],[2,3],[3,1]]
Output: true
Explanation: 1 -> 2 -> 3 -> 1 forms a cycle.
Constraints: 1 <= n <= 2000
Approach: DFS with a recursion-stack marker; a back-edge to a node currently in the
recursion stack means a cycle — O(V+E) time, O(V) space

===========================================================================================
27. TOPOLOGICAL SORT
===========================================================================================

150.Topological Sort (DFS based) — (Pattern: DFS + Stack)
Problem: Given a DAG, return a valid topological ordering of its nodes.
Input:  n = 6, edges = [[5,2],[5,0],[4,0],[4,1],[2,3],[3,1]]
Output: [5,4,2,3,1,0]  (one valid ordering; multiple may be valid)
Explanation: Every edge u->v has u appearing before v in the output.
Constraints: 1 <= n <= 2000, graph is acyclic
Approach: DFS, push node to a stack after visiting all its descendants, reverse the
stack at the end — O(V+E) time, O(V) space

151.Kahns Algorithm (BFS based) — (Pattern: BFS + In-degree)
Problem: Given a DAG, return a valid topological ordering using in-degree counting.
Input:  n = 4, edges = [[0,1],[0,2],[1,3],[2,3]]
Output: [0,1,2,3]  (one valid ordering)
Explanation: Nodes with in-degree 0 are output first, then their edges are removed,
repeating until all nodes are ordered.
Constraints: 1 <= n <= 2000
Approach: compute in-degrees, queue all in-degree-0 nodes, repeatedly pop, output,
decrement neighbors in-degree, enqueue new zeros — O(V+E) time, O(V) space

152.Course Schedule — (Pattern: Topological Sort)
Problem: Given numCourses and prerequisite pairs [a,b] (b must be taken before a),
determine if it is possible to finish all courses.
Input:  numCourses = 2, prerequisites = [[1,0]]
Output: true
Explanation: Take course 0, then course 1 — no cycle exists.
Constraints: 1 <= numCourses <= 2000
Approach: build graph, detect a cycle via DFS or Kahns algorithm (if all nodes get
processed, no cycle exists) — O(V+E) time, O(V+E) space

153.Course Schedule II — (Pattern: Topological Sort)
Problem: Same setup as Course Schedule, but return a valid course order to finish
all courses, or an empty array if impossible.
Input:  numCourses = 4, prerequisites = [[1,0],[2,0],[3,1],[3,2]]
Output: [0,1,2,3] (one valid ordering)
Explanation: Course 0 has no prerequisites; 1 and 2 depend on 0; 3 depends on both.
Constraints: 1 <= numCourses <= 2000
Approach: Kahns algorithm, collect the BFS output order; if fewer than numCourses
nodes are output, a cycle exists (return []) — O(V+E) time, O(V+E) space

===========================================================================================
28. SHORTEST PATH
===========================================================================================

154.Shortest Path in an Unweighted Graph — (Pattern: BFS)
Problem: Given an unweighted graph and a source node, find the shortest distance
(number of edges) from source to every other node.
Input:  graph = {0:[1,2], 1:[3], 2:[3], 3:[]}, source = 0
Output: {0:0, 1:1, 2:1, 3:2}
Explanation: BFS layers correspond exactly to shortest distances in unweighted graphs.
Constraints: 1 <= nodes <= 10^4
Approach: BFS from source, distance = current BFS layer depth — O(V+E) time, O(V) space

155.Dijkstra Algorithm: Network Delay Time — (Pattern: Dijkstra / Min-Heap)
Problem: Given a network of n nodes, travel times as directed weighted edges, and a
source node k, return the time for all nodes to receive a signal from k, or -1 if
impossible.
Input:  times = [[2,1,1],[2,3,1],[3,4,1]], n = 4, k = 2
Output: 2
Explanation: Node 2 reaches 1 and 3 at time 1, then 4 at time 2 — the max over all
shortest distances is 2.
Constraints: 1 <= n <= 100, 1 <= times.length <= 6000, edge weights are positive
Approach: Dijkstra algorithm with a min-heap of (distance, node) — O((V+E) log V) time, O(V+E) space

156.Bellman-Ford (Discussion + when applicable)
Problem: Given a graph with possibly negative edge weights (but no negative cycle)
and a source, find shortest distances to all nodes.
Input:  edges = [[0,1,4],[0,2,5],[1,2,-3]], source = 0
Output: dist = {0:0, 1:4, 2:1}
Explanation: Path 0->1->2 (4 + -3 = 1) is shorter than the direct 0->2 edge (5).
Constraints: works correctly only if there is no negative-weight cycle
Approach: relax all edges V-1 times; an extra relaxation round finding an
improvement indicates a negative cycle — O(V*E) time, O(V) space

===========================================================================================
29. GRID BASED GRAPH PROBLEMS
===========================================================================================

Number of Islands — see Connected Components

157.Max Area of Island — (Pattern: DFS/BFS on Grid)
Problem: Given a grid of 0s and 1s, return the area of the largest island
(4-directionally connected group of 1s).
Input:  grid = [[0,0,1,0],[0,1,1,0],[0,0,0,1]]
Output: 3
Explanation: The largest connected group of 1s has 3 cells.
Constraints: 1 <= rows, cols <= 50
Approach: DFS/BFS flood-fill from each unvisited land cell, track max area seen — O(rows*cols) time, O(rows*cols) space

Rotten Oranges — see Queue section

158.Flood Fill — (Pattern: DFS/BFS)
Problem: Given an image (2D grid of colors), a starting pixel, and a new color,
recolor the connected region (4-directional, same original color) starting from
that pixel.
Input:  image = [[1,1,1],[1,1,0],[1,0,1]], sr=1, sc=1, color=2
Output: [[2,2,2],[2,2,0],[2,0,1]]
Explanation: All cells connected to (1,1) with the original color 1 are repainted to 2.
Constraints: 1 <= rows, cols <= 50
Approach: DFS/BFS flood-fill, recolor and recurse to same-colored neighbors — O(rows*cols) time, O(rows*cols) space

159.Shortest Path in a Binary Matrix — (Pattern: BFS)
Problem: Given an n x n binary grid (0 = passable, 1 = blocked), find the length of
the shortest clear path from top-left to bottom-right, moving in 8 directions.
Input:  grid = [[0,1],[1,0]]
Output: 2
Explanation: The path (0,0) -> (1,1) is a direct diagonal move, length 2 (cell count).
Constraints: 1 <= n <= 100
Approach: BFS from (0,0), exploring all 8 directions, track path length by layer — O(n^2) time, O(n^2) space

===========================================================================================
30. ADVANCED GRAPH PROBLEMS
===========================================================================================

160.Clone Graph — (Pattern: DFS/BFS + Hashing)
Problem: Given a reference node in a connected undirected graph, return a deep copy
(clone) of the entire graph.
Input:  adjList = [[2,4],[1,3],[2,4],[1,3]]  (node 1 connects to 2 and 4, etc.)
Output: a structurally identical graph made entirely of new node objects
Explanation: Every node and edge must be duplicated, not shared with the original.
Constraints: 0 <= number of nodes <= 100
Approach: DFS/BFS with a hash map from original node -> cloned node to avoid
re-cloning and to handle cycles — O(V+E) time, O(V) space

161.Word Ladder — (Pattern: BFS)
Problem: Given a beginWord, endWord, and a word list, return the length of the
shortest transformation sequence changing one letter at a time, each intermediate
word must exist in the word list.
Input:  beginWord = "hit", endWord = "cog", wordList = ["hot","dot","dog","lot","log","cog"]
Output: 5
Explanation: hit -> hot -> dot -> dog -> cog is one shortest sequence, length 5.
Constraints: 1 <= wordList.length <= 5000
Approach: BFS where each state is a word, generate neighbors by changing one letter
at a time and checking against the word set — O(N * L^2) time (N words, L length), O(N*L) space

162.Union-Find / Disjoint Set — (Pattern: Union-Find)
Problem: Implement a Union-Find structure supporting find(x) and union(x, y) with
path compression and union by rank.
Input:  union(1,2); union(2,3); find(1) == find(3)?
Output: true
Explanation: 1, 2, 3 all end up in the same component after the unions.
Constraints: up to 10^5 elements/operations
Approach: parent array with path compression on find, union by rank/size — nearly O(1) amortized time per op (inverse Ackermann), O(n) space

163.Redundant Connection — (Pattern: Union-Find)
Problem: Given a graph that was a tree with one extra edge added (creating exactly
one cycle), return the extra edge that can be removed to make it a tree again.
Input:  edges = [[1,2],[1,3],[2,3]]
Output: [2, 3]
Explanation: [2,3] is the edge that, when added, creates the cycle 1-2-3-1.
Constraints: 3 <= edges.length <= 1000
Approach: Union-Find; the first edge connecting two already-unioned nodes is the
redundant one — O(n α(n)) time, O(n) space

164.Minimum Spanning Tree, basic idea — (Pattern: Kruskal Algorithm)
Problem: Given a weighted undirected graph, find the subset of edges connecting all
nodes with minimum total edge weight and no cycles.
Input:  n = 4, edges = [[0,1,10],[0,2,6],[0,3,5],[1,3,15],[2,3,4]]
Output: total MST weight = 19  (edges [2,3,4], [0,3,5], [0,1,10])
Explanation: Picking the smallest-weight edges that do not form a cycle, via Union-Find.
Constraints: 1 <= n <= 1000
Approach: Kruskal algorithm — sort edges by weight, add if it does not create a
cycle (checked via Union-Find) — O(E log E) time, O(V) space

165.Bipartite Graph Check — (Pattern: BFS/DFS coloring)
Problem: Given an undirected graph, determine if it can be colored with 2 colors
such that no two adjacent nodes share a color.
Input:  graph = [[1,3],[0,2],[1,3],[0,2]]
Output: true
Explanation: Nodes {0,2} can be one color and {1,3} the other, with no same-color
edges.
Constraints: 1 <= nodes <= 100
Approach: BFS/DFS coloring, assign alternating colors, fail if a neighbor already
has the same color — O(V+E) time, O(V) space

===========================================================================================
31. GREEDY ALGORITHMS (was missing entirely — high frequency, esp. interval scheduling)
===========================================================================================

--- Easy ---

166.Jump Game — (Pattern: Greedy)
Problem: Given nums where nums[i] is the max jump length from index i, return true if
you can reach the last index starting from index 0.
Input:  nums = [2,3,1,1,4]
Output: true
Explanation: Jump 1 step to index 1, then 3 steps to reach the last index.
Constraints: 1 <= nums.length <= 10^4
Approach: greedily track the farthest reachable index while scanning left to right,
fail if current index exceeds it — O(n) time, O(1) space

205.Lemonade Change — (Pattern: Greedy)
Problem: Each lemonade costs $5. Customers pay with a $5, $10, or $20 bill, one at a
time and in order; you start with no change. Return true if you can give every
customer the correct change.
Input:  bills = [5, 5, 5, 10, 20]
Output: true
Explanation: Collect three $5s from the first three customers. The $10 customer gets
one $5 back. The $20 customer gets a $10 + a $5 back (or three $5s) — either way,
correct change is available at every step.
Constraints: 1 <= bills.length <= 10^5, bills[i] is 5, 10, or 20
Approach: greedy — track only counts of $5s and $10s held (never need $20s to make
change); a $10 bill requires one $5 in hand; a $20 bill is best paid with a $10 + a $5
if available (save $5s, since they are the only bill flexible enough to break a $10),
otherwise three $5s — O(n) time, O(1) space

--- Medium ---

167.Jump Game II — (Pattern: Greedy)
Problem: Given nums (guaranteed reachable), return the minimum number of jumps needed
to reach the last index.
Input:  nums = [2,3,1,1,4]
Output: 2
Explanation: Jump 1 step to index 1, then 3 steps to the last index — 2 jumps total.
Constraints: 1 <= nums.length <= 10^4
Approach: greedy layer expansion — track current jump's' farthest boundary and the
farthest reachable overall, increment jumps when boundary is crossed — O(n) time, O(1) space

168.Gas Station — (Pattern: Greedy)
Problem: Given circular gas[i] and cost[i] arrays, return the starting station index
from which a car can complete the circuit once, or -1 if impossible (answer is
unique if it exists).
Input:  gas = [1,2,3,4,5], cost = [3,4,5,1,2]
Output: 3
Explanation: Starting at station 3, the tank never goes negative around the loop.
Constraints: n == gas.length == cost.length, 1 <= n <= 10^5
Approach: a solution exists iff sum(gas) >= sum(cost); track running tank total,
reset the candidate start to i+1 whenever the tank goes negative — O(n) time, O(1) space

169.Meeting Rooms — (Pattern: Greedy / Sorting) — very common Amazon warm-up question
Problem: Given an array of meeting time intervals, determine if one person could
attend every meeting (i.e., no two intervals overlap).
Input:  intervals = [[0,30],[5,10],[15,20]]
Output: false
Explanation: [0,30] overlaps both [5,10] and [15,20].
Constraints: 0 <= intervals.length <= 10^4
Approach: sort by start time, check that each interval's start >= previous interval's
end — O(n log n) time, O(1) space

170.Meeting Rooms II — (Pattern: Greedy + Min-Heap) — extremely common Amazon question
Problem: Given meeting time intervals, return the minimum number of conference rooms
required so no meeting waits.
Input:  intervals = [[0,30],[5,10],[15,20]]
Output: 2
Explanation: [0,30] and [5,10] need separate rooms; once [5,10] ends, its room can be
reused for [15,20].
Constraints: 1 <= intervals.length <= 10^4
Approach: min-heap of active end times — sort by start, for each meeting pop the heap
if its earliest end <= current start (reuse a room), then push the current end; heap
size at the end is the answer. (Equivalent alternative: sort starts and ends
separately, two-pointer sweep.) — O(n log n) time, O(n) space

--- Advanced ---

171.Task Scheduler — (Pattern: Greedy + Max-Heap / Math)
Problem: Given a list of CPU tasks and a cooldown n between two same tasks, return
the minimum number of intervals (including idle slots) needed to finish all tasks.
Input:  tasks = ["A","A","A","B","B","B"], n = 2
Output: 8
Explanation: One valid schedule: A B idle A B idle A B — 8 intervals.
Constraints: 1 <= tasks.length <= 10^4, 0 <= n <= 100
Approach: greedily schedule the most frequent remaining task each round (max-heap by
frequency), or use the closed-form (maxFreq-1)*(n+1) + (count of tasks tied at
maxFreq), capped below by tasks.length — O(n) time, O(1) space (fixed alphabet)

Non-overlapping Intervals (minimum removals) — see Backtracking & Interval Classics
section (sec 40) — same Greedy / Interval Scheduling pattern as Meeting Rooms above

===========================================================================================
32. ADDITIONAL HIGH-FREQUENCY GAPS (Heap / Sliding Window / Sorting-Strings)
===========================================================================================

172.Minimum Size Subarray Sum — (Pattern: Variable Sliding Window)
Problem: Given an array of positive integers and a target, return the minimal length
of a contiguous subarray whose sum is >= target; return 0 if no such subarray exists.
Input:  target = 7, nums = [2,3,1,2,4,3]
Output: 2
Explanation: The subarray [4,3] has sum 7, the smallest length achieving >= target.
Constraints: 1 <= target <= 10^9, 1 <= nums.length <= 10^5
Approach: variable sliding window — expand right, shrink left while sum >= target,
track the minimum window length seen — O(n) time, O(1) space

173.K Closest Points to Origin — (Pattern: Max-Heap / Quickselect) — classic Amazon favorite
Problem: Given an array of points on the X-Y plane and an integer k, return the k
points closest to the origin (any order).
Input:  points = [[1,3],[-2,2]], k = 1
Output: [[-2,2]]
Explanation: distance(-2,2) = sqrt(8) < distance(1,3) = sqrt(10).
Constraints: 1 <= k <= points.length <= 10^4
Approach: max-heap of size k keyed by squared distance (pop the farthest when size
exceeds k), or Quickselect for average O(n) — O(n log k) time (heap), O(k) space

174.Minimum Cost to Connect Sticks — (Pattern: Min-Heap / Huffman-style) — classic Amazon favorite
Problem: Given the lengths of sticks, repeatedly connect any two sticks at a cost
equal to their combined length, until one stick remains; return the minimum total cost.
Input:  sticks = [2,4,3]
Output: 14
Explanation: Connect 2+3 (cost 5) -> sticks [5,4]; connect 5+4 (cost 9); total 5+9=14.
Constraints: 1 <= sticks.length <= 10^4
Approach: min-heap — repeatedly pop the two smallest, push their sum, add the sum to
the running cost — O(n log n) time, O(n) space

175.Reorder Data in Log Files — (Pattern: Custom Comparator / Sorting) — reported Amazon OA question
Problem: Each log is "identifier content...". Letter-logs (content is words) sort
lexicographically by content, ties broken by identifier; digit-logs (content is
digits) keep their original relative order and are placed after all letter-logs.
Input:  logs = ["dig1 8 1 5 1","let1 art can","dig2 3 6","let2 own kit dig","let3 art zero"]
Output: ["let1 art can","let3 art zero","let2 own kit dig","dig1 8 1 5 1","dig2 3 6"]
Explanation: Letter-logs are sorted by content ("art can" < "art zero" < "own kit dig");
digit-logs stay in input order, appended at the end.
Constraints: 0 <= logs.length <= 100
Approach: custom comparator — classify each log as digit/letter, sort with a stable
sort using (content, identifier) as the key for letter-logs while leaving digit-logs
in place at the end — O(n log n * L) time, O(n * L) space

===========================================================================================
33. SORTING ALGORITHMS (was missing entirely — mastery requires implementing these
    from scratch, not just calling a library sort)
===========================================================================================

176.Merge Sort — (Pattern: Divide & Conquer)
Problem: Implement merge sort to sort an array in ascending order from scratch.
Input:  nums = [5, 2, 3, 1]
Output: [1, 2, 3, 5]
Explanation: Recursively split the array in half, sort each half, then merge the two
sorted halves back together.
Constraints: 1 <= nums.length <= 5*10^4
Approach: divide into halves, recurse, merge two sorted halves using an auxiliary
array — O(n log n) time (all cases), O(n) space; stable sort

177.Quick Sort — (Pattern: Divide & Conquer / Partitioning)
Problem: Implement quicksort to sort an array in-place from scratch.
Input:  nums = [5, 2, 3, 1]
Output: [1, 2, 3, 5]
Explanation: Pick a pivot, partition elements smaller/larger around it in-place,
recursively sort each side.
Constraints: 1 <= nums.length <= 5*10^4
Approach: Lomuto or Hoare partition scheme around a pivot, recurse on both sides;
randomize the pivot choice to avoid the worst case on sorted/adversarial input — O(n log n) average / O(n^2) worst time, O(log n) space (recursion stack); not stable

178.Heap Sort — (Pattern: Heap)
Problem: Implement heap sort using an in-place binary heap.
Input:  nums = [5, 2, 3, 1]
Output: [1, 2, 3, 5]
Explanation: Build a max-heap from the array, then repeatedly swap the root (current
max) to the end and sift-down the reduced heap.
Constraints: 1 <= nums.length <= 5*10^4
Approach: heapify the array into a max-heap in O(n), repeatedly extract the max to
the end and sift-down — O(n log n) time (all cases), O(1) space; not stable

Discussion — Counting Sort / Radix Sort (Pattern: Non-comparison Sort)
When the value range is small/bounded (e.g. sorting 0/1/2 as in Sort Colors, or
sorting ages 0-120), a comparison sort's O(n log n) lower bound doesn't apply —
counting sort (bucket by value, O(n + k)) or radix sort (sort digit-by-digit, O(d*(n+k)))
can be faster. Recognize this pattern whenever "the values are bounded by a small k"
appears in constraints.

Discussion — Choosing a sort: quicksort is fastest in practice (cache-friendly,
in-place) but worst-case O(n^2) and unstable; merge sort guarantees O(n log n) and is
stable but needs O(n) extra space (good for linked lists, external sorting); heap
sort is in-place and worst-case O(n log n) but not stable and worse cache behavior
than quicksort in practice.

===========================================================================================
34. PREFIX SUM & DIFFERENCE ARRAY (was implicit only via Q9/Q18 — deserves its own pattern)
===========================================================================================

179.Range Sum Query - Immutable — (Pattern: Prefix Sum)
Problem: Given an integer array (that never changes), design a structure to answer
many sumRange(i, j) queries efficiently.
Input:  nums = [-2,0,3,-5,2,-1]; sumRange(0,2); sumRange(2,5); sumRange(0,5)
Output: 1, -1, -3
Explanation: prefix[i] = sum of nums[0..i-1]; sumRange(i,j) = prefix[j+1] - prefix[i].
Constraints: 1 <= nums.length <= 10^4, up to 10^4 queries
Approach: precompute a prefix-sum array once — O(n) preprocessing, O(1) per query, O(n) space

180.Range Sum Query 2D - Immutable — (Pattern: 2D Prefix Sum)
Problem: Given a 2D matrix (that never changes), design a structure to answer
sumRegion(r1, c1, r2, c2) queries efficiently.
Input:  matrix = [[3,0,1,4,2],[5,6,3,2,1],[1,2,0,1,5],[4,1,0,1,7],[1,0,3,0,5]];
        sumRegion(2,1,4,3)
Output: 8
Explanation: A 2D prefix-sum matrix allows any rectangular region's sum to be
computed' in O(1) via inclusion-exclusion of its four corners.
Constraints: 1 <= rows, cols <= 200
Approach: precompute a 2D prefix-sum matrix once — O(rows*cols) preprocessing, O(1)
per query, O(rows*cols) space

181.Range Update — (Pattern: Difference Array)
Problem: Given multiple range-increment updates [l, r, val] applied to an initially
all-zero array of given length, return the final array after all updates.
Input:  length = 5, updates = [[1,3,2],[2,4,3],[0,2,-2]]
Output: [-2, 0, 3, 5, 3]
Explanation: A difference array lets each update apply in O(1) at its boundaries
(diff[l] += val, diff[r+1] -= val); the final array is the prefix sum of diff.
Constraints: 1 <= length <= 10^5, up to 10^5 updates
Approach: apply each update to a difference array in O(1), take one prefix-sum pass
at the end to recover the final values — O(n + q) time, O(n) space

(See also: Product of Array Except Self, Subarray Sum Equals K — under Arrays/Hashing,
same Prefix Sum family)

===========================================================================================
35. STRING PATTERN MATCHING — ADVANCED (was missing — KMP/Rabin-Karp are fundamental
    algorithms, not just "use built-in substring search")
===========================================================================================

182.KMP Algorithm (optimal strStr) — (Pattern: KMP / LPS Array - Longest Proper Prefix Suffix.)
Problem: Given text and pattern, find occurrences of pattern in text in O(n+m),
without re-scanning already-matched characters on a mismatch (unlike Q22 brute force).
Input:  text = "ababcababcabc", pattern = "abcabc"
Output: first match at index 7
Explanation: A precomputed LPS ("longest proper prefix that is also a suffix") array
tells the pattern pointer exactly how far to fall back on a mismatch, instead of
restarting from scratch.
Constraints: 1 <= pattern.length <= text.length <= 10^5
Approach: build the LPS array for the pattern once (O(m)), then scan the text using
it to skip redundant comparisons — O(n+m) time, O(m) space

183.Rabin-Karp Algorithm — (Pattern: Rolling Hash)
Problem: Find occurrences of pattern in text using a rolling hash to compare each
window in O(1) amortized.
Input:  text = "abcabcabc", pattern = "cab"
Output: matches at indices [2, 5]
Explanation: The rolling hash of each text window is compared against the pattern's
hash; on a hash match', a direct character comparison confirms it (to rule out a
hash collision).
Constraints: 1 <= pattern.length <= text.length <= 10^5
Approach: compute the pattern's hash and the first window's hash, then slide the
window by removing the leftmost char's contribution and adding the new right char's
in O(1) — O(n+m) average time (O(n*m) worst case under heavy collisions), O(1) space

184.Manacher's Algorithm (Longest Palindromic Substring in true O(n)) — (Pattern: Manacher's)
Problem: Same problem as Q25 (Longest Palindromic Substring), but solved in O(n)
instead of O(n^2) — relevant once s.length grows past ~10^4.
Input:  s = "babad"
Output: "bab" (or "aba")
Explanation: Transform the string by inserting separators between characters, then
expand the palindrome radius at each center while reusing previously computed radii
via the mirror property — avoiding the redundant re-expansion that expand-around-center does.
Constraints: 1 <= s.length <= 10^5 (where O(n^2) expand-around-center is too slow)
Approach: maintain the center and right boundary of the rightmost-known palindrome;
mirror the known radius when the current center is inside it, expand only as needed — O(n) time, O(n) space

185. Z Algorithm (Linear-time Pattern Matching) — (Pattern: Z Array / Z-Function)

Problem: Given a text and pattern, find occurrences of the pattern in the text in O(n+m)
using the Z-function, which computes how many characters from each position match the
prefix of the combined string.
Input:  text = "ababcababcabc", pattern = "abcabc"
Output: first match at index 7
Explanation: Combine the pattern and text with a separator:
"abcabc#ababcababcabc"
The Z array stores, for every position, the length of the longest substring starting
there that matches the prefix of the combined string. Whenever Z[i] == pattern.length,
the pattern occurs in the text at index i - pattern.length - 1.
Constraints: 1 <= pattern.length <= text.length <= 10^5
Approach: Build the combined string pattern + separator + text, then compute its Z array
in O(n+m) using a [left, right] window representing the rightmost substring that matches
the prefix. Reuse previously computed Z values whenever the current position lies inside
this window, expanding only when necessary.
Time: O(n+m)
Space: O(n+m)

===========================================================================================
36. SEGMENT TREE / FENWICK TREE — RANGE QUERIES (was missing entirely — the key
    data structure once "immutable" prefix sums (section 34) are not enough)
===========================================================================================

185.Range Sum Query - Mutable — (Pattern: Fenwick Tree / Binary Indexed Tree)
Problem: Design a structure supporting update(i, val) and sumRange(i, j) both in
O(log n) — unlike Q179, the array can change between queries here.
Input:  nums = [1,3,5]; sumRange(0,2); update(1,2); sumRange(0,2)
Output: 9, then 8
Explanation: After updating index 1 from 3 to 2, the range sum reflects the change.
Constraints: 1 <= nums.length <= 3*10^4, up to 3*10^4 calls
Approach: Fenwick Tree (Binary Indexed Tree) — each index owns a range determined by
its lowest set bit; update/query walk the tree by repeatedly adding/subtracting the
lowest set bit — O(log n) time per update/query, O(n) space

186.Range Minimum Query — (Pattern: Segment Tree)
Problem: Design a structure supporting update(i, val) and queryMin(i, j) (minimum
over a range) efficiently, over a mutable array.
Input:  nums = [2,5,1,4,3]; queryMin(1,3); update(2,10); queryMin(1,3)
Output: 1, then 4
Explanation: Each segment-tree node stores an aggregate (here, min) of its range;
updates/queries touch only O(log n) nodes.
Constraints: 1 <= nums.length <= 10^5
Approach: build a segment tree where each node stores an aggregate of its range,
point-update propagates changes up O(log n) levels, range query combines O(log n)
relevant nodes — O(n) build, O(log n) per update/query, O(n) space
(The same template generalizes to sum/max/gcd range queries — only the merge
function at each node changes.)

===========================================================================================
37. MATH / NUMBER THEORY (was missing — recurs constantly in OA rounds and as a
    sub-step inside bigger problems)
===========================================================================================

187.GCD and LCM — (Pattern: Euclidean Algorithm) — Discussion + example
Problem: Compute the greatest common divisor and least common multiple of two integers.
Input:  a = 48, b = 18
Output: gcd = 6, lcm = 144
Explanation: gcd(48,18) = 6 via Euclid's algorithm; lcm = a*b/gcd = 864/6 = 144.
Constraints: 1 <= a, b <= 10^9
Approach: Euclidean algorithm — gcd(a,b) = gcd(b, a mod b), repeat until b == 0 — O(log(min(a,b))) time, O(1) space'

188.Sieve of Eratosthenes — (Pattern: Prime Sieve)
Problem: Given n, return all prime numbers less than n.
Input:  n = 10
Output: primes = [2, 3, 5, 7]
Explanation: Starting from 2, mark every multiple of each found prime as composite;
whatever remains unmarked is prime.
Constraints: 0 <= n <= 5*10^6
Approach: boolean sieve array; for each prime p found starting at 2, mark multiples
of p starting from p*p as composite (smaller multiples are already marked) — O(n log log n) time, O(n) space

189.Modular Exponentiation (Fast Power) — (Pattern: Divide & Conquer)
Problem: Compute (base^exp) % mod efficiently, where exp can be very large.
Input:  base = 2, exp = 10, mod = 1000
Output: 24
Explanation: 2^10 = 1024, 1024 % 1000 = 24.
Constraints: exp can be up to 10^9 or larger
Approach: binary exponentiation — square the base and halve the exponent each step,
multiply the result whenever the current exponent bit is 1, taking mod after every
multiplication to prevent overflow — O(log exp) time, O(1) space

===========================================================================================
38. ADVANCED DYNAMIC PROGRAMMING PATTERNS (section 15 covered the fundamentals —
    these are the pattern FAMILIES that show up again and again with variations)
===========================================================================================

190.Maximum Product Subarray — (Pattern: DP, Kadane variant)
Problem: Given an integer array, find the contiguous subarray with the largest product.
Input:  nums = [2, 3, -2, 4]
Output: 6
Explanation: The subarray [2, 3] has the maximum product, 6.
Constraints: 1 <= nums.length <= 2*10^4
Approach: track BOTH the running max and running min product ending at each index
(a negative number can flip the running min into the new max) — O(n) time, O(1) space

191.Best Time to Buy and Sell Stock II (unlimited transactions) — (Pattern: Greedy/DP)
Problem: Given prices, maximize profit allowing unlimited buy/sell transactions
(must sell before buying again, no holding two positions).
Input:  prices = [7,1,5,3,6,4]
Output: 7
Explanation: Buy at 1, sell at 5 (profit 4); buy at 3, sell at 6 (profit 3): total 7.
Constraints: 1 <= prices.length <= 3*10^4
Approach: greedily sum every positive day-to-day price difference — O(n) time, O(1) space

192.Best Time to Buy and Sell Stock III / IV (at most k transactions) — (Pattern: 2D DP)
Problem: Maximize profit with at most k buy/sell transactions (III is the special
case k=2).
Input:  k = 2, prices = [3,2,6,5,0,3]
Output: 7
Explanation: Buy at 2, sell at 6 (profit 4); buy at 0, sell at 3 (profit 3): total 7.
Constraints: 0 <= k <= 100, 1 <= prices.length <= 1000
Approach: dp[t][i] = max profit using at most t transactions through day i, computed
via a running "best = max(best, dp[t-1][j] - price[j])" term to avoid an O(n) inner
loop — O(n*k) time, O(k) space

193.Best Time to Buy and Sell Stock with Cooldown / with Transaction Fee — (Pattern: State-Machine DP)
Problem: Maximize profit with unlimited transactions, but either (a) a mandatory
1-day cooldown after selling before buying again, or (b) a fixed fee charged per
transaction.
Input:  prices = [1,3,2,8,4,9], fee = 2
Output: 8
Explanation: Buy at 1 sell at 8 (profit 7 - 2 fee = 5), buy at 4 sell at 9 (profit
5 - 2 fee = 3): total 8.
Constraints: 1 <= prices.length <= 5*10^4
Approach: state-machine DP over "holding" / "not holding" (add a "cooldown" state
for that variant; subtract the fee on each sell for the fee variant) — O(n) time, O(1) space

194.Longest Palindromic Subsequence — (Pattern: 2D DP — distinct from Longest
Palindromic SUBSTRING, Q25/Q184; here characters need not be contiguous)
Problem: Given a string, find the length of the longest subsequence that reads the
same forwards and backwards.
Input:  s = "bbbab"
Output: 4
Explanation: "bbbb" is a palindromic subsequence of length 4.
Constraints: 1 <= s.length <= 1000
Approach: identical recurrence to Longest Common Subsequence(s, reverse(s)); or
direct interval DP: dp[i][j] = dp[i+1][j-1]+2 if s[i]==s[j] else
max(dp[i+1][j], dp[i][j-1]) — O(n^2) time, O(n^2) space

195.Palindrome Partitioning II (min cuts) — (Pattern: Interval DP)
Problem: Given a string, return the minimum number of cuts needed so every resulting
substring is a palindrome.
Input:  s = "aab"
Output: 1
Explanation: "aa" | "b" requires only 1 cut.
Constraints: 1 <= s.length <= 2000
Approach: precompute isPalindrome[i][j] with interval DP, then minCuts[i] =
min over all j < i with s[j..i] a palindrome of (minCuts[j-1] + 1) — O(n^2) time, O(n^2) space

196.Egg Drop Puzzle — (Pattern: 2D DP, inverted formulation)
Problem: Given k eggs and n floors, find the minimum number of trials needed in the
worst case to determine the critical floor (below which eggs survive a drop, at/above
which they break).
Input:  k = 2, n = 10
Output: 4
Explanation: With 2 eggs and an optimal strategy, 4 trials suffice in the worst case
to pinpoint the critical floor among 10.
Constraints: 1 <= k <= 100, 1 <= n <= 10^4
Approach: instead of the naive dp[eggs][floors] (O(k*n^2)), invert to
dp[eggs][moves] = max floors distinguishable = dp[eggs-1][moves-1] + dp[eggs][moves-1]
+ 1, find the smallest "moves" where dp[k][moves] >= n — O(k log n) time, O(k log n) space

197.Traveling Salesman Problem (Bitmask DP) — (Pattern: Bitmask DP) — the canonical
"state = subset of items visited" pattern, foundational for advanced DP mastery
Problem: Given a distance matrix between n cities, find the minimum cost to visit
every city exactly once and return to the start.
Input:  dist = [[0,10,15,20],[10,0,35,25],[15,35,0,30],[20,25,30,0]]
Output: 80
Explanation: Route 0->1->3->2->0 costs 10+25+30+15=80, the minimum over all
permutations of visiting order.
Constraints: 1 <= n <= 15 (a bitmask over n cities needs 2^n states — this bounds n)
Approach: dp[mask][i] = min cost having visited exactly the cities in "mask", ending
at city i; transition tries appending each unvisited city — O(n^2 * 2^n) time, O(n * 2^n) space

===========================================================================================
39. ADVANCED GRAPH ALGORITHMS (section 24-30 covered the essentials — these round
    out graph mastery for harder onsite/advanced rounds)
===========================================================================================

198.Floyd-Warshall (All-Pairs Shortest Path) — (Pattern: DP over graphs)
Problem: Given a weighted graph (negative edges allowed, no negative cycle), compute
shortest distances between EVERY pair of nodes at once.
Input:  n = 4, edges = [[0,1,5],[1,2,1],[2,3,1],[0,3,10]] (directed)
Output: dist[0][3] = 7  (via 0->1->2->3 = 5+1+1)
Explanation: Trying every node k as a possible intermediate point relaxes all pairs
(i,j) via dist[i][j] = min(dist[i][j], dist[i][k] + dist[k][j]).
Constraints: 1 <= n <= 400 (the cubic time bounds how large n can be)
Approach: triple nested loop — outer loop over intermediate node k, inner loops over
i and j, relaxing distances — O(V^3) time, O(V^2) space

199.Articulation Points and Bridges — (Pattern: DFS + Low-Link, Tarjan-style)
Problem: Given an undirected graph, find all articulation points (nodes whose
removal increases the number of connected components) and all bridges (edges whose
removal disconnects the graph).
Input:  n = 5, edges = [[0,1],[1,2],[2,0],[1,3],[3,4]]
Output: articulation points = [1, 3]; bridges = [1,3] and [3,4]
Explanation: Removing node 1 disconnects {3,4} from {0,2}; removing node 3
disconnects {4} from the rest.
Constraints: 1 <= n <= 10^5
Approach: DFS tracking each node's discovery time and "low-link" value (the lowest
discovery time reachable via one back-edge from its subtree); a non-root node is an
articulation point if some child's low-link >= its own discovery time (root needs
>=2 DFS children instead); an edge (u,v) is a bridge if child v's low-link > u's
discovery time — O(V+E) time, O(V) space

200.Strongly Connected Components (Kosaraju's / Tarjan's) — (Pattern: DFS-based SCC)
Problem: Given a directed graph, find all strongly connected components (maximal
groups of nodes where every node can reach every other node in the group).
Input:  n = 5, edges = [[0,1],[1,2],[2,0],[2,3],[3,4]]
Output: SCCs = [[0,1,2], [3], [4]]
Explanation: 0, 1, 2 form a cycle and are mutually reachable; 3 and 4 are each their
own singleton SCC.
Constraints: 1 <= n <= 10^5
Approach (Kosaraju's): DFS the graph once to get a finishing-time order, reverse all
edges, DFS again processing nodes in reverse-finish order — each resulting DFS tree
is exactly one SCC — O(V+E) time, O(V+E) space
(Tarjan's finds the same answer in a single DFS pass using discovery time + low-link
+ an explicit on-stack marker — worth knowing both.)

===========================================================================================
40. ADDITIONAL BACKTRACKING & INTERVAL CLASSICS
===========================================================================================

201.Palindrome Partitioning — (Pattern: Backtracking)
Problem: Given a string, return all possible ways to partition it such that every
substring in the partition is a palindrome.
Input:  s = "aab"
Output: [["a","a","b"], ["aa","b"]]
Explanation: Both partitions consist entirely of palindromic substrings.
Constraints: 1 <= s.length <= 16
Approach: backtracking — at each position, try every prefix of the remainder that is
a palindrome, recurse on what is left — O(n * 2^n) worst case time, O(n) space (recursion depth)

202.Sudoku Solver — (Pattern: Backtracking)
Problem: Given a partially filled 9x9 Sudoku board, fill it so every row, column,
and 3x3 sub-box contains the digits 1-9 exactly once.
Input:  board with some cells '.', rest pre-filled per Sudoku rules
Output: the fully solved board
Explanation: Backtracking tries each valid digit in the first empty cell found,
recursing until the board is complete or backtracking out of a dead end.
Constraints: board is always 9x9, guaranteed to have a unique solution
Approach: backtracking with row/column/box "digit used" sets for O(1) validity
checks per placement — O(9^(empty cells)) worst case (heavily pruned in practice), O(1) extra space (fixed-size board)

203.Non-overlapping Intervals (minimum removals) — (Pattern: Greedy / Interval Scheduling)
Problem: Given a list of intervals, return the minimum number that must be removed
so the rest are non-overlapping.
Input:  intervals = [[1,2],[2,3],[3,4],[1,3]]
Output: 1
Explanation: Removing [1,3] leaves [1,2],[2,3],[3,4], which don't overlap.
Constraints: 1 <= intervals.length <= 10^5
Approach: sort by end time, greedily KEEP an interval if its start >= the last kept
interval's end, otherwise discard it (the classic activity-selection greedy proof:
always keep the interval that frees the resource soonest) — O(n log n) time, O(1) space

204.Search a 2D Matrix — (Pattern: Binary Search over a flattened matrix)
Problem: Given an m x n matrix where each row is sorted ascending and the first
element of each row is greater than the last element of the previous row, determine
if a target value exists.
Input:  matrix = [[1,3,5,7],[10,11,16,20],[23,30,34,60]], target = 3
Output: true
Explanation: The matrix can be treated as one sorted array of length m*n via the
index mapping row = mid / n, col = mid % n.
Constraints: 1 <= m, n <= 100
Approach: binary search over the range [0, m*n - 1], mapping each mid to (row, col) — O(log(m*n)) time, O(1) space

===========================================================================================
                    PRIORITY SHORTLIST (minimal prep, maximum coverage)
===========================================================================================
If short on time, these ~40 cover the vast majority of top-company rounds:

Arrays / Strings:
  Two Sum, 3Sum, Best Time to Buy and Sell Stock, Maximum Subarray (Kadane),
  Product of Array Except Self, Merge Intervals, Trapping Rain Water,
  Median of Two Sorted Arrays, Longest Substring Without Repeating Characters,
  Longest Palindromic Substring, Group Anagrams, Minimum Window Substring

Stack / Queue:
  Valid Parentheses, Next Greater Element / Daily Temperatures, Sliding Window Maximum

Sliding Window:
  Longest Substring Without Repeating Characters, Minimum Size Subarray Sum,
  Minimum Window Substring

Greedy:
  Meeting Rooms II, Jump Game, Gas Station, Task Scheduler

Linked List:
  Reverse Linked List, Linked List Cycle, Merge Two Sorted Lists,
  Merge K Sorted Lists, LRU Cache

Recursion / Backtracking:
  Subsets, Permutations, Word Search

Binary Search:
  Classic Binary Search, Search in Rotated Sorted Array

Heap / Trie:
  Top K Frequent Elements, Kth Largest Element, K Closest Points to Origin,
  Minimum Cost to Connect Sticks, Implement Trie

Dynamic Programming:
  Climbing Stairs, House Robber, Longest Increasing Subsequence, 0/1 Knapsack,
  Longest Common Subsequence, Edit Distance, Word Break

Trees:
  Level Order Traversal, Validate BST, Lowest Common Ancestor,
  Diameter of Binary Tree, Serialize and Deserialize Binary Tree, Kth Smallest in BST

Graphs:
  BFS, DFS, Number of Islands, Clone Graph, Course Schedule (Topological Sort),
  Number of Provinces / Union-Find, Network Delay Time (Dijkstra), Bipartite Graph Check

===========================================================================================
                    MASTERY EXTRAS (beyond interview minimums — sections 33-40)
===========================================================================================
The shortlist above is interview-scoped. For genuine DSA mastery and full pattern
recognition, also drill these foundational algorithms/patterns — they recur as
building blocks inside harder problems even when not asked directly:

  Sorting from scratch:      Merge Sort, Quick Sort, Heap Sort (sec 33)
  Prefix Sum family:         Range Sum Query (1D & 2D), Difference Array (sec 34)
  String matching:           KMP, Rabin-Karp, Manacher Algorithm (sec 35)
  Range query structures:    Fenwick Tree (BIT), Segment Tree (sec 36)
  Number theory:             GCD/LCM (Euclid), Sieve of Eratosthenes, Modular
                              Exponentiation (sec 37)
  DP pattern families:       Max Product Subarray, Stock Trading I-IV/Cooldown/Fee,
                              Longest Palindromic Subsequence, Palindrome
                              Partitioning II, Egg Drop, Bitmask DP / TSP (sec 38)
  Advanced graph:            Floyd-Warshall, Articulation Points & Bridges,
                              Strongly Connected Components (sec 39)
  Backtracking/Interval:     Sudoku Solver, Palindrome Partitioning, Non-overlapping
                              Intervals, Search a 2D Matrix (sec 40)

===========================================================================================
                    DSA MASTER PATTERN MAP (one-page mind-map view)
===========================================================================================
Transcribed from the handwritten notebook version of this same map — same branches, same
groupings, just typed out so it stays legible and versioned alongside the rest of this file.
Array and String are merged into one branch below because in the original they both arrow
into the same four patterns (Two Pointers, Sliding Window, Kadane, Binary Search Based) —
that's not a simplification of meaning, it's exactly what the crossing arrows meant: these
patterns are shared between the two topics, not owned by either one alone.

Use this the way you would use the notebook page: as a 10-second "where does this problem live"
check before diving into the Pattern Recognition table (top of file) for the precise signal,
or into the numbered section itself for the full worked problems.

DSA
│
├── ARRAY & STRING  (share the same core patterns — see note above)
│   │
│   ├── Two Pointers
│   │   ├── Opposite Ends            (converge from both sides — Q10, Q15, Q21)
│   │   ├── Same Direction           (slow/fast, read/write — Q5, Q26)
│   │   └── Dutch National Flag      (3-way in-place partition — Q8)
│   │
│   ├── Sliding Window
│   │   ├── Fixed Size               (window length never changes — Q80, Q81)
│   │   └── Variable Size
│   │       ├── Expand / Shrink      (grow right, shrink left on violation — Q24, Q29, Q172)
│   │       └── Monotonic            (deque keeps window max/min — Q48)
│   │
│   ├── Kadane Algorithm           (best running sum/product — Q3, Q190)
│   │
│   └── Binary Search Based
│       ├── On Index                 (classic sorted-array search — Q72, Q74-Q77)
│       └── On Answer                (binary search the answer space — Q78, Q79)
│
├── HASHING
│   ├── Frequency Based              (counts/anagrams — Q20, Q23, Q36)
│   ├── Lookup Based                 (seen-before checks — Q1, Q31, Q35)
│   ├── Set Based                    (membership, sequences — Q37)
│   └── Index / Grouping             (value -> position/group — Q18, Q23)
│
├── STACK
│   ├── Monotonic Stack              (Q40, Q41, Q44)
│   ├── Nearest Element              (next greater/smaller — Q40, Q41)
│   ├── Range / Span                 (largest rectangle, span queries — Q44)
│   ├── Min / Max Tracking           (auxiliary stack — Q39)
│   └── Expression Evaluation        (RPN, nested decode — Q42, Q43)
│
├── QUEUE
│   ├── Level-order Processing       (BFS layer by layer — Q116, Q117)
│   ├── Deque                        (both-end access — Q46, Q48)
│   └── FIFO                         (Q45)
│
├── LINKED LIST
│   ├── Fast / Slow Pointers         (middle, cycle detection — Q50, Q52, Q53)
│   ├── Cycle Detection              (Floyd — Q52, Q53)
│   ├── Reversal                     (whole list or sublist — Q49, Q55)
│   └── Merge Lists                  (Q51, Q59)
│
├── TREE
│   ├── Traversal
│   │   ├── DFS                      (in/pre/postorder — Q114, Q115)
│   │   └── BFS                      (level order — Q116, Q117)
│   ├── Path
│   │   ├── Max Sum                  (Q135)
│   │   └── Height / Depth           (Q118, Q119, Q130, Q131)
│   └── BST  (specialization of Tree — property-driven descent)
│       └── search / insert / delete / kth-smallest / LCA — Q123-Q128
│
├── RECURSION
│   ├── Exploration -> Backtracking  (subsets, permutations, N-Queens — Q64-Q71, Q201, Q202)
│   └── Divide & Conquer
│       ├── Merge Sort               (Q176)
│       ├── Kth Largest              (quickselect — Q90)
│       └── Count Problems           (count-based recursive splits)
│
├── HEAP
│   ├── Top / Kth Element            (Q90, Q173)
│   ├── Greedy + Heap                (Q170, Q171, Q174)
│   └── K-way Merge                  (Q59)
│
├── GRAPH
│   ├── Traversal
│   │   ├── BFS                      (Q141, Q154)
│   │   └── DFS                      (Q142)
│   ├── Cycle Detection              (Q148, Q149)
│   ├── Topological Sort             (Q150-Q153)
│   ├── Shortest Path                (BFS/Dijkstra/Bellman-Ford/Floyd-Warshall — Q154-Q156, Q198)
│   └── Spanning Tree                (Kruskal / Union-Find — Q164)
│
├── TRIE
│   ├── Prefix Based                 (autocomplete, word search — Q92, Q93)
│   └── Bitwise Trie                 (max-XOR-pair style problems — not yet a full worked
│                                      problem in this file; flagged here for later depth)
│
├── DYNAMIC PROGRAMMING
│   ├── Core
│   │   ├── 1D                       (Q98, Q99, Q102)
│   │   └── 2D                       (Q108, Q109, Q194)
│   ├── Digit DP                     (not yet a full worked problem in this file; flagged
│   │                                  here for later depth)
│   ├── Transition Style
│   │   ├── Linear DP                (dp[i] depends on a few prior dp[j] — Q98-Q102)
│   │   └── Grid DP                  (Q104)
│   ├── Pattern
│   │   ├── Knapsack                 (0/1 and Unbounded — Q100, Q101, Q103, Q107)
│   │   └── Interval DP              (Q110, Q112, Q195)
│   └── Approach
│       ├── Memoization              (top-down, cache recursive calls)
│       └── Tabulation               (bottom-up, fill a table iteratively)
│
├── GREEDY
│   ├── Interval Scheduling          (Q169, Q170, Q203)
│   ├── Task Scheduling              (Q171)
│   ├── Huffman-style                (repeatedly combine cheapest two — Q174)
│   ├── Merge Cost                   (Q174)
│   └── Simulation / Running State   (track a running resource, e.g. change on hand — Q205)
│
└── BIT MANIPULATION
    ├── Core: XOR / Bit Tricks       (Q85-Q89)
    └── Usage: Subsets via Bitmask   (bitmask as a subset representation — Q64, Q197)
