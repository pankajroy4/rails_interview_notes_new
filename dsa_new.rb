===========================================================================================
                    DSA INTERVIEW QUESTION BANK (Top-Company Prep)
===========================================================================================
Format: Question — (Pattern used)
Progression per topic: Easy -> Medium -> Advanced
Cross-referenced items are noted instead of repeated.

===========================================================================================
1. ARRAYS
===========================================================================================
Easy:
  - Two Sum: return indices of two numbers adding up to target — (Pattern: Hashing)
  - Best Time to Buy and Sell Stock: max profit from a single buy-sell — (Pattern: One-pass Greedy)
  - Maximum Subarray: largest sum contiguous subarray — (Pattern: Kadane's Algorithm)
  - Move Zeroes: move all zeroes to end, keep relative order — (Pattern: Two Pointers)
  - Remove Duplicates from Sorted Array: remove in-place, return new length — (Pattern: Two Pointers)
  - Merge Sorted Array: merge two sorted arrays in-place into the first — (Pattern: Two Pointers)

Medium:
  - 3Sum: find all unique triplets that sum to zero — (Pattern: Sorting + Two Pointers)
  - Sort Colors: sort an array of 0s, 1s, 2s in one pass — (Pattern: Dutch National Flag)
  - Product of Array Except Self: each index = product of all other elements, no division — (Pattern: Prefix/Suffix Product)
  - Container With Most Water: two lines forming the container with most water — (Pattern: Two Pointers)
  - Merge Intervals: merge all overlapping intervals — (Pattern: Sort + Sweep)
  - Insert Interval: insert a new interval into a sorted non-overlapping list — (Pattern: Intervals)
  - Rotate Array: rotate array right by k steps — (Pattern: Reversal Trick)
  - Next Permutation: rearrange to the next lexicographically greater permutation — (Pattern: Array Manipulation)

Advanced:
  - Trapping Rain Water: total water trapped between elevation bars — (Pattern: Two Pointers / Prefix Max)
  - Median of Two Sorted Arrays: find median in O(log(min(m,n))) — (Pattern: Binary Search)
  - Majority Element: element appearing more than n/2 times — (Pattern: Boyer-Moore Voting)
  - Subarray Sum Equals K: count subarrays summing to k — (Pattern: Prefix Sum + Hashing)

===========================================================================================
2. STRINGS
===========================================================================================
Easy:
  - Reverse String: reverse in-place without built-ins — (Pattern: Two Pointers)
  - Valid Anagram: check if two strings are anagrams — (Pattern: Frequency Count)
  - Valid Palindrome: check palindrome ignoring non-alphanumeric chars — (Pattern: Two Pointers)
  - Implement strStr(): find first occurrence of needle in haystack — (Pattern: String Matching)

Medium:
  - Group Anagrams: group strings that are anagrams of each other — (Pattern: Hashing)
  - Longest Substring Without Repeating Characters: length of longest substring with unique chars — (Pattern: Sliding Window)
  - Longest Palindromic Substring: find the longest palindromic substring — (Pattern: Expand Around Center / DP)
  - String Compression: compress using counts of repeated chars — (Pattern: Two Pointers)
  - String to Integer (atoi): implement atoi handling edge cases — (Pattern: String Parsing)
  - Check if One String is a Rotation of Another — (Pattern: Concatenation Trick)

Advanced:
  - Minimum Window Substring: smallest substring containing all chars of target — (Pattern: Sliding Window + Hashing)
  - Regular Expression Matching: implement matching with '.' and '*' — (Pattern: DP)

===========================================================================================
3. HASHING / FREQUENCY MAP
===========================================================================================
Easy:
  - Contains Duplicate: check if array has any duplicate — (Pattern: Hashing)
  - First Non-Repeating Character in a String — (Pattern: Frequency Map)
  - Isomorphic Strings: check if two strings follow the same char-mapping pattern — (Pattern: Hashing)
  - Happy Number: does the number eventually reach 1 via sum of squares of digits? — (Pattern: Hashing / Cycle Detection)

Medium:
  - Contains Duplicate II: duplicate exists within distance k — (Pattern: Hashing + Sliding Window)
  - Top K Frequent Elements: return k most frequent elements — (Pattern: Hashing + Heap/Bucket Sort)
  - Longest Consecutive Sequence: length of longest consecutive elements run, in O(n) — (Pattern: Hashing)
  (See also: Two Sum, Subarray Sum Equals K, Group Anagrams — under Arrays/Strings, same Hashing pattern)

===========================================================================================
4. STACK
===========================================================================================
Easy:
  - Valid Parentheses: check if brackets are balanced — (Pattern: Stack)

Medium:
  - Min Stack: design a stack supporting getMin() in O(1) — (Pattern: Stack + Auxiliary Stack)
  - Next Greater Element: next greater element for each array element — (Pattern: Monotonic Stack)
  - Daily Temperatures: days to wait until a warmer temperature — (Pattern: Monotonic Stack)
  - Evaluate Reverse Polish Notation: evaluate a postfix expression — (Pattern: Stack)
  - Decode String: decode strings like "3[a2[c]]" — (Pattern: Stack)

Advanced:
  - Largest Rectangle in Histogram: max rectangle area in a histogram — (Pattern: Monotonic Stack)

===========================================================================================
5. QUEUE / DEQUE
===========================================================================================
Easy:
  - Implement Queue using Stacks — (Pattern: Stack/Queue Design)

Medium:
  - First Negative Number in Every Window of Size K — (Pattern: Deque)
  - Rotten Oranges: min time for all oranges to rot (multi-source) — (Pattern: BFS)

Advanced:
  - Sliding Window Maximum: max in every window of size k — (Pattern: Monotonic Deque)

===========================================================================================
6. LINKED LIST
===========================================================================================
Easy:
  - Reverse Linked List — (Pattern: Pointer Manipulation)
  - Middle of the Linked List — (Pattern: Fast/Slow Pointers)
  - Merge Two Sorted Lists — (Pattern: Two Pointers)

Medium:
  - Linked List Cycle: detect if a cycle exists — (Pattern: Floyd's Algorithm)
  - Linked List Cycle II: find the node where the cycle begins — (Pattern: Floyd's Algorithm)
  - Remove Nth Node From End of List, in one pass — (Pattern: Two Pointers)
  - Reverse Linked List II: reverse nodes between position m and n — (Pattern: Pointer Manipulation)
  - Intersection of Two Linked Lists — (Pattern: Two Pointers)
  - Add Two Numbers: add numbers represented as linked lists — (Pattern: Simulation)
  - Copy List with Random Pointer: deep copy a list with random pointers — (Pattern: Hashing / Interweaving)

Advanced:
  - Merge K Sorted Lists — (Pattern: Heap / Divide & Conquer)
  - LRU Cache: design with O(1) get/put — (Pattern: HashMap + Doubly Linked List) [see also Design]

===========================================================================================
7. RECURSION / BACKTRACKING
===========================================================================================
Easy:
  - Fibonacci Number, optimized with memoization — (Pattern: Recursion + DP)
  - Factorial of a Number — (Pattern: Recursion)
  - Pow(x, n): fast exponentiation — (Pattern: Divide & Conquer)

Medium:
  - Subsets: generate all subsets of a set — (Pattern: Backtracking)
  - Subsets II: subsets of a set with duplicates — (Pattern: Backtracking)
  - Permutations: generate all permutations of an array — (Pattern: Backtracking)
  - Letter Combinations of a Phone Number — (Pattern: Backtracking)
  - Combination Sum: combinations summing to target, reuse allowed — (Pattern: Backtracking)
  - Combination Sum II: combinations summing to target, no reuse, has duplicates — (Pattern: Backtracking)

Advanced:
  - N-Queens: place N queens so none attack each other — (Pattern: Backtracking)
  - Word Search: does the word exist via adjacent cells in a grid? — (Pattern: Backtracking + DFS)

===========================================================================================
8. BINARY SEARCH
===========================================================================================
Easy:
  - Classic Binary Search in a sorted array — (Pattern: Binary Search)
  - Sqrt(x): integer square root — (Pattern: Binary Search)

Medium:
  - First and Last Position of Element in Sorted Array — (Pattern: Binary Search)
  - Search in Rotated Sorted Array — (Pattern: Modified Binary Search)
  - Find Minimum in Rotated Sorted Array — (Pattern: Binary Search)
  - Find Peak Element — (Pattern: Binary Search)

Advanced:
  - Median of Two Sorted Arrays (see Arrays)
  - Capacity To Ship Packages Within D Days — (Pattern: Binary Search on Answer)
  - Koko Eating Bananas: min eating speed to finish in time — (Pattern: Binary Search on Answer)

===========================================================================================
9. SLIDING WINDOW
===========================================================================================
Easy:
  - Maximum Sum Subarray of Size K — (Pattern: Fixed Sliding Window)

Medium:
  - Longest Substring Without Repeating Characters (see Strings)
  - Permutation in String: does s2 contain a permutation of s1? — (Pattern: Sliding Window)
  - Subarray Product Less Than K: count subarrays with product < k — (Pattern: Variable Sliding Window)
  - Longest Repeating Character Replacement: longest substring after replacing at most k chars — (Pattern: Sliding Window)

Advanced:
  - Minimum Window Substring (see Strings)

===========================================================================================
10. BIT MANIPULATION (was missing — high frequency in screening rounds)
===========================================================================================
Easy:
  - Single Number: every element appears twice except one — (Pattern: XOR)
  - Number of 1 Bits: count set bits in an integer — (Pattern: Bit Manipulation)
  - Power of Two: check if a number is a power of two — (Pattern: Bit Manipulation)

Medium:
  - Counting Bits: count set bits for every number 0..n — (Pattern: DP + Bit Manipulation)
  - Missing Number: find the missing number in 0..n — (Pattern: XOR / Sum)
  - Single Number II/III (variants where elements repeat 3x or two uniques exist) — (Pattern: Bit Manipulation)

===========================================================================================
11. HEAP / PRIORITY QUEUE (was missing as an explicit pattern)
===========================================================================================
Medium:
  - Kth Largest Element in an Array — (Pattern: Min-Heap / Quickselect)
  - Top K Frequent Elements (see Hashing)

Advanced:
  - Merge K Sorted Lists (see Linked List)
  - Find Median from Data Stream: design a structure with O(log n) insert — (Pattern: Two Heaps)

===========================================================================================
12. TRIE (was missing entirely)
===========================================================================================
Medium:
  - Implement Trie (Prefix Tree): insert, search, startsWith — (Pattern: Trie)
  - Design Add and Search Words Data Structure: search with wildcard '.' — (Pattern: Trie + DFS)

===========================================================================================
13. DESIGN PROBLEMS (was missing — LRU Cache is asked constantly)
===========================================================================================
Medium:
  - Min Stack (see Stack)

Advanced:
  - LRU Cache: get/put in O(1) — (Pattern: HashMap + Doubly Linked List)
  - LFU Cache: evict least-frequently-used entry — (Pattern: HashMap + Frequency Buckets)

===========================================================================================
14. MATRIX (was missing entirely)
===========================================================================================
Medium:
  - Rotate Image: rotate an n x n matrix 90 degrees in-place — (Pattern: Layer-by-Layer Swap)
  - Spiral Matrix: return all elements in spiral order — (Pattern: Boundary Simulation)
  - Set Matrix Zeroes: if an element is 0, set its row & column to 0, in-place — (Pattern: Matrix Marking)

===========================================================================================
15. DYNAMIC PROGRAMMING
===========================================================================================
Basic:
  - Climbing Stairs — (Pattern: 1D DP)
  - House Robber — (Pattern: 1D DP)
  - Coin Change (minimum coins) — (Pattern: Unbounded Knapsack)
  - Coin Change II (number of ways) — (Pattern: Unbounded Knapsack)
  - Longest Increasing Subsequence — (Pattern: 1D DP / Binary Search)
  - 0/1 Knapsack — (Pattern: 2D DP)
  - Unique Paths: count paths in an m x n grid — (Pattern: Grid DP)
  - Target Sum: ways to assign +/- to reach a target — (Pattern: DP as Subset Sum)

Medium / Classic:
  - Word Break: can the string be segmented into dictionary words? — (Pattern: 1D DP)
  - Partition Equal Subset Sum — (Pattern: Subset Sum DP)
  - Longest Common Subsequence — (Pattern: 2D DP)
  - Edit Distance — (Pattern: 2D DP)
  - Matrix Chain Multiplication — (Pattern: Interval DP)

Advanced:
  - Weighted Job Scheduling — (Pattern: DP + Binary Search)
  - DP on Intervals (e.g. Burst Balloons) — (Pattern: Interval DP)
  - DP on Trees, basic idea (e.g. House Robber III) — (Pattern: Tree DP)

===========================================================================================
16. TIME & SPACE COMPLEXITY / CONCEPTUAL
===========================================================================================
  - Why does HashMap give O(1) average lookup?
  - What is the worst case of HashMap, and why?
  - What is amortized time complexity?
  - Practical difference between O(n log n) and O(n^2)?
  - Space complexity of a recursive call stack?
  - Why is quicksort's worst case O(n^2)?

===========================================================================================
17. BINARY TREE TRAVERSALS (MUST)
===========================================================================================
  - Inorder, Preorder, Postorder Traversal (recursive) — (Pattern: DFS)
  - Iterative Traversal using a Stack — (Pattern: DFS, iterative)
  - Level Order Traversal — (Pattern: BFS)
  - Binary Tree Zigzag Level Order Traversal — (Pattern: BFS + direction flag)

===========================================================================================
18. BASIC TREE PROPERTIES
===========================================================================================
  - Maximum Depth of Binary Tree
  - Minimum Depth of Binary Tree
  - Check if Two Trees are Identical
  - Invert Binary Tree
  - Check if a Tree is Symmetric

===========================================================================================
19. BINARY SEARCH TREE (BST)
===========================================================================================
  - Validate BST
  - Search in a BST
  - Insert into a BST
  - Delete a Node in a BST
  - Lowest Common Ancestor of a BST
  - Kth Smallest Element in a BST

===========================================================================================
20. IMPORTANT BINARY TREE PROBLEMS
===========================================================================================
  - Lowest Common Ancestor of a Binary Tree (general, not BST)
  - Diameter of Binary Tree
  - Balanced Binary Tree: check height-balance
  - Path Sum: does a root-to-leaf path sum to target?
  - Binary Tree Right Side View
  - Count Good Nodes
  - Binary Tree Maximum Path Sum

===========================================================================================
21. TREE CONSTRUCTION
===========================================================================================
  - Construct Binary Tree from Preorder and Inorder Traversal
  - Construct Binary Tree from Inorder and Postorder Traversal

===========================================================================================
22. ADVANCED TREE PROBLEMS
===========================================================================================
  - Serialize and Deserialize Binary Tree
  - Flatten Binary Tree to Linked List
  - Vertical Order Traversal of a Binary Tree

===========================================================================================
23. TREE CONCEPTUAL QUESTIONS
===========================================================================================
  - Difference between Binary Tree and BST?
  - Why is average BST time O(log n)? When does it degrade?
  - What makes a tree "balanced"?
  - Height vs Depth — what's the difference?
  - Full vs Complete vs Perfect Binary Tree — differences?

===========================================================================================
24. GRAPH TRAVERSALS & REPRESENTATION (MUST)
===========================================================================================
  - BFS Traversal of a Graph
  - DFS Traversal, recursive and iterative
  - Implement Graph Representation using an Adjacency List
  - Implement Graph Representation using an Adjacency Matrix
  - Directed vs Undirected Graph — when to use which representation?

===========================================================================================
25. CONNECTED COMPONENTS
===========================================================================================
  - Number of Connected Components in an Undirected Graph
  - Number of Provinces — (Pattern: DFS/Union-Find)
  - Number of Islands — count connected land cells in a grid — (Pattern: DFS/BFS on Grid)

===========================================================================================
26. CYCLE DETECTION
===========================================================================================
  - Detect Cycle in an Undirected Graph — (Pattern: DFS/Union-Find)
  - Detect Cycle in a Directed Graph — (Pattern: DFS + Recursion Stack)

===========================================================================================
27. TOPOLOGICAL SORT
===========================================================================================
  - Topological Sort, DFS based
  - Kahn's Algorithm, BFS based
  - Course Schedule: can all courses be finished given prerequisites? — (Pattern: Topological Sort)
  - Course Schedule II: return a valid course order — (Pattern: Topological Sort)

===========================================================================================
28. SHORTEST PATH
===========================================================================================
  - Shortest Path in an Unweighted Graph — (Pattern: BFS)
  - Dijkstra's Algorithm: Network Delay Time — (Pattern: Dijkstra / Min-Heap)
  - Bellman-Ford: theory + when to use over Dijkstra (negative weights)

===========================================================================================
29. GRID BASED GRAPH PROBLEMS
===========================================================================================
  - Number of Islands (see Connected Components)
  - Max Area of Island
  - Rotten Oranges (see Queue)
  - Flood Fill
  - Shortest Path in a Binary Matrix — (Pattern: BFS)

===========================================================================================
30. ADVANCED GRAPH PROBLEMS
===========================================================================================
  - Clone Graph — (Pattern: DFS/BFS + Hashing)
  - Word Ladder: shortest transformation sequence — (Pattern: BFS)
  - Union-Find / Disjoint Set: implement find & union with path compression
  - Redundant Connection: find the edge that creates a cycle — (Pattern: Union-Find)
  - Minimum Spanning Tree, basic idea — (Pattern: Kruskal's Algorithm)
  - Bipartite Graph Check — (Pattern: BFS/DFS coloring)

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

Linked List:
  Reverse Linked List, Linked List Cycle, Merge Two Sorted Lists,
  Merge K Sorted Lists, LRU Cache

Recursion / Backtracking:
  Subsets, Permutations, Word Search

Binary Search:
  Classic Binary Search, Search in Rotated Sorted Array

Heap / Trie:
  Top K Frequent Elements, Kth Largest Element, Implement Trie

Dynamic Programming:
  Climbing Stairs, House Robber, Longest Increasing Subsequence, 0/1 Knapsack,
  Longest Common Subsequence, Edit Distance, Word Break

Trees:
  Level Order Traversal, Validate BST, Lowest Common Ancestor,
  Diameter of Binary Tree, Serialize and Deserialize Binary Tree, Kth Smallest in BST

Graphs:
  BFS, DFS, Number of Islands, Clone Graph, Course Schedule (Topological Sort),
  Number of Provinces / Union-Find, Network Delay Time (Dijkstra), Bipartite Graph Check
