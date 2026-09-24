/*
 * C++ STL CHEAT SHEET — quick revision before/during LeetCode contests
 * -----------------------------------------------------------------
 * Contest boilerplate:
 */
#include <bits/stdc++.h>
using namespace std;

int main() {
    // Untie cin/cout from C's stdio buffer. Normally cin/cout stay synced
    // with scanf/printf so you can freely mix them; that sync has overhead.
    // Disabling it speeds up cin/cout — but then never mix cin/cout with
    // scanf/printf in the same program, output order can get scrambled.
    ios_base::sync_with_stdio(false);

    // By default cin is "tied" to cout: every cin >> first flushes cout,
    // so any pending prompt prints before the program waits for input.
    // cin.tie(NULL) removes that auto-flush, saving time on heavy I/O.
    cin.tie(NULL);

    // Together these two lines are the standard "fast I/O" trick for
    // competitive programming with large cin/cout traffic (e.g. Codeforces).
    // Not needed on LeetCode, since input arrives as function arguments,
    // not via cin — but harmless to keep as habit.
    return 0;
}

/* =========================================================
 * 1. VECTOR  (dynamic array) — O(1) amortized push_back, O(1) random access
 * ========================================================= */
void vector_demo() {
    
    vector<int> v;                    // empty
    vector<int> v2(5);                // size 5, all 0
    vector<int> v3(5, -1);            // size 5, all -1
    vector<int> v4 = {1, 2, 3};        // init list
    vector<vector<int>> grid(3, vector<int>(4, 0)); // 3x4 2D vector

    v.push_back(10);
    v.emplace_back(20);               // constructs in place, prefer over push_back
    v.pop_back();                     // removes last, O(1)
    v.insert(v.begin() + 1, 99);      // insert at index, O(n)
    v.erase(v.begin() + 1);           // erase at index, O(n)
    v.erase(v.begin(), v.begin() + 2);// erase range
    v.clear();

    v = {5, 3, 1, 4, 2};
    v.size();                         // number of elements
    v.empty();                        // true if size == 0
    v.front(); v.back();
    v[0]; v.at(0);                    // at() bounds-checks (throws)
    v.resize(10);                     // grow/shrink, new elems = 0
    v.reserve(100);                   // preallocate capacity (avoid reallocs)

    sort(v.begin(), v.end());                       // ascending
    sort(v.begin(), v.end(), greater<int>());        // descending
    sort(v.begin(), v.end(), [](int a, int b){       // custom comparator
        return a > b;
    });
    reverse(v.begin(), v.end());

    // remove-erase idiom (actually delete elements matching a value/predicate)
    v.erase(remove(v.begin(), v.end(), 3), v.end());
    v.erase(remove_if(v.begin(), v.end(), [](int x){ return x % 2 == 0; }), v.end());

    // 2D vector iteration
    for (auto &row : grid) for (auto &cell : row) cell = 1;

    // Iterating a vector<pair<int,int>>
    vector<pair<int,int>> vp = {{1,2},{3,4}};
    for (auto &[a, b] : vp) { /* structured bindings, C++17 */ }
}

/* =========================================================
 * 2. PAIR / TUPLE
 * ========================================================= */
void pair_tuple_demo() {
    pair<int, string> p = {1, "a"};
    p.first; p.second;
    auto p2 = make_pair(1, 2.5);

    tuple<int, string, double> t = {1, "x", 2.5};
    get<0>(t); get<1>(t); get<2>(t);
    auto [a, b, c] = t;                // structured bindings

    // pairs sort lexicographically by default: first, then second
    vector<pair<int,int>> v = {{2,1},{1,5},{1,2}};
    sort(v.begin(), v.end());          // -> {1,2},{1,5},{2,1}
}

/* =========================================================
 * 3. STRING
 * ========================================================= */
void string_demo() {
    string s = "hello world";
    s.size(); s.length();              // same thing
    s.substr(2, 3);                    // "llo" (start=2, len=3)
    s.substr(6);                       // from index 6 to end
    s.find("wor");                     // index or string::npos
    s.find("zz") == string::npos;      // not found check
    s += " end";                       // concat
    s.push_back('!');
    s.pop_back();
    reverse(s.begin(), s.end());
    sort(s.begin(), s.end());          // sort chars
    to_string(123);                    // int -> string
    stoi("123"); stol("123"); stoll("123"); stod("1.5"); // string -> number
    transform(s.begin(), s.end(), s.begin(), ::tolower); // lowercase
    transform(s.begin(), s.end(), s.begin(), ::toupper); // uppercase
    isalpha('a'); isdigit('5'); isupper('A'); islower('a');

    // splitting a string by delimiter (STL has no direct split)
    stringstream ss("a,b,c");
    string token; vector<string> tokens;
    while (getline(ss, token, ',')) tokens.push_back(token);

    // building strings efficiently
    ostringstream oss;
    oss << "x=" << 5 << ", y=" << 10;
    string result = oss.str();
}

/* =========================================================
 * 4. SET  (ordered, unique, sorted) — RB-tree, O(log n) ops
 * ========================================================= */
void set_demo() {
    set<int> s = {5, 1, 4, 1, 3};      // stored sorted: {1,3,4,5}, duplicates dropped
    s.insert(2);
    s.erase(3);                        // erase by value
    s.count(4);                        // 0 or 1 (existence check)
    s.find(4) != s.end();              // existence check (preferred, avoids double lookup)
    *s.begin();                        // smallest
    *s.rbegin();                       // largest

    // lower_bound / upper_bound — must use member function on set (not <algorithm>'s),
    // because set iterators aren't random-access
    auto it = s.lower_bound(3);        // first element >= 3
    auto it2 = s.upper_bound(3);       // first element > 3
    if (it != s.end()) { /* *it */ }

    multiset<int> ms = {1, 1, 2, 3};   // allows duplicates, still sorted
    ms.erase(ms.find(1));              // erase ONE occurrence (ms.erase(1) removes ALL!)
    ms.count(1);                       // number of occurrences
}

/* =========================================================
 * 5. UNORDERED_SET (hash set) — O(1) avg, O(n) worst case ops
 * ========================================================= */
void unordered_set_demo() {
    unordered_set<int> us = {1, 2, 3};
    us.insert(4);
    us.erase(2);
    us.count(3);                       // 0 or 1
    us.find(3) != us.end();
    // NOT sorted, no lower_bound/upper_bound, no *us.begin() min/max guarantee
    // Use when you only need existence/membership checks, not ordering.
}

/* =========================================================
 * 6. MAP (ordered key->value, sorted by key) — O(log n) ops
 * ========================================================= */
void map_demo() {
    map<string, int> m;
    m["apple"] = 3;                    // insert or update; DEFAULT-CONSTRUCTS if missing (0 for int)
    m.insert({"banana", 5});
    m["banana"]++;

    if (m.count("apple")) { /* exists */ }        // safe existence check
    if (m.find("apple") != m.end()) { /* exists */ }

    // WARNING: m["missing"] CREATES the key with default value as a side effect.
    // For read-only existence check, use count()/find(), not m["key"].

    for (auto &[key, val] : m) { /* iterates in sorted key order */ }

    m.erase("apple");

    // map is sorted by key -> iterating gives sorted order for free
    // First/last key:
    m.begin()->first;                  // smallest key
    m.rbegin()->first;                 // largest key

    auto it = m.lower_bound("b");      // first key >= "b"
}

/* =========================================================
 * 7. UNORDERED_MAP (hash map) — O(1) avg ops, most common for freq counting
 * ========================================================= */
void unordered_map_demo() {
    unordered_map<int, int> freq;
    vector<int> nums = {1, 2, 2, 3, 3, 3};
    for (int n : nums) freq[n]++;      // classic frequency count pattern

    if (freq.count(2)) { /* exists */ }
    if (freq.find(2) != freq.end()) { /* exists */ }

    for (auto &[key, val] : freq) { /* order is UNSPECIFIED */ }

    // reserve to avoid rehashing if size is known (perf trick for contests)
    freq.reserve(nums.size());
}

/* =========================================================
 * 8. STACK / QUEUE / DEQUE
 * ========================================================= */
void stack_queue_deque_demo() {
    stack<int> st;
    st.push(1); st.top(); st.pop(); st.empty(); st.size();

    queue<int> q;
    q.push(1); q.front(); q.back(); q.pop(); q.empty();

    deque<int> dq;                     // double-ended queue, O(1) push/pop both ends
    dq.push_back(1); dq.push_front(0);
    dq.pop_back(); dq.pop_front();
    dq.front(); dq.back();
    dq[0];                             // random access supported, unlike list
}

/* =========================================================
 * 9. PRIORITY_QUEUE (heap) — default is MAX-heap
 * ========================================================= */
void priority_queue_demo() {
    priority_queue<int> maxHeap;                 // max at top
    maxHeap.push(3); maxHeap.push(1); maxHeap.push(4);
    maxHeap.top();                               // 4
    maxHeap.pop();

    priority_queue<int, vector<int>, greater<int>> minHeap; // min at top
    minHeap.push(3); minHeap.push(1);
    minHeap.top();                               // 1

    // custom comparator (e.g. min-heap of pairs by first element)
    auto cmp = [](pair<int,int> a, pair<int,int> b) {
        return a.first > b.first;                // smallest first at top
    };
    priority_queue<pair<int,int>, vector<pair<int,int>>, decltype(cmp)> pq(cmp);
}

/* =========================================================
 * 10. <ALGORITHM> HEADER — the workhorses
 * ========================================================= */
void algorithm_demo() {
    vector<int> v = {5, 3, 1, 4, 1, 5, 9};

    sort(v.begin(), v.end());
    bool found = binary_search(v.begin(), v.end(), 4);   // needs sorted range

    // lower_bound: first element NOT LESS than target (>= target)
    // upper_bound: first element GREATER than target (> target)
    auto lo = lower_bound(v.begin(), v.end(), 4);
    auto hi = upper_bound(v.begin(), v.end(), 4);
    int idx = lo - v.begin();                            // index via iterator arithmetic
    int countOf4 = upper_bound(v.begin(), v.end(), 4) - lower_bound(v.begin(), v.end(), 4);

    *max_element(v.begin(), v.end());
    *min_element(v.begin(), v.end());
    accumulate(v.begin(), v.end(), 0);                   // sum, 0 = initial value
    accumulate(v.begin(), v.end(), 1, multiplies<int>()); // product

    unique(v.begin(), v.end());        // removes CONSECUTIVE dupes, returns new logical end
                                        // -> sort first, then unique, then erase:
    v.erase(unique(v.begin(), v.end()), v.end());  // classic dedupe-a-vector idiom

    count(v.begin(), v.end(), 5);                        // count occurrences of value
    count_if(v.begin(), v.end(), [](int x){ return x > 3; });

    find(v.begin(), v.end(), 5) != v.end();              // linear search

    next_permutation(v.begin(), v.end());                // rearranges to next lexicographic perm
    prev_permutation(v.begin(), v.end());

    fill(v.begin(), v.end(), 0);                         // set all to a value
    iota(v.begin(), v.end(), 0);                         // fill with 0,1,2,3... (sequential)

    swap(v[0], v[1]);
    rotate(v.begin(), v.begin() + 2, v.end());           // left-rotate by 2

    __gcd(12, 18);                                       // gcd builtin
    // lcm(a,b) = a / __gcd(a,b) * b   (no built-in lcm before C++17; std::lcm exists in C++17)
    std::gcd(12, 18); std::lcm(4, 6);                    // <numeric>, C++17
}

/* =========================================================
 * 11. USEFUL BIT TRICKS / BUILTINS
 * ========================================================= */
void bit_tricks_demo() {
    int x = 12;
    __builtin_popcount(x);             // number of set bits (int)
    __builtin_popcountll(x);           // for long long
    __builtin_clz(x);                  // count leading zeros (undefined if x==0)
    __builtin_ctz(x);                  // count trailing zeros (undefined if x==0)
    (x & (x - 1));                     // clears lowest set bit
    (x & -x);                          // isolates lowest set bit
    (x >> 1); (x << 1);
    bitset<32> b(x);                   // bitset for fixed-width bit manipulation
    b.to_string(); b.count();
}

/* =========================================================
 * 12. COMPLEXITY CHEAT TABLE (avg case unless noted)
 * =========================================================
 * vector:          push_back O(1)*, insert/erase middle O(n), access O(1)
 * deque:           push/pop front&back O(1), random access O(1)
 * list:            insert/erase O(1) (with iterator), no random access
 * set/map:         insert/erase/find O(log n)  [ordered, tree-based]
 * unordered_set/map: insert/erase/find O(1) avg, O(n) worst  [hash-based]
 * priority_queue:  push/pop O(log n), top O(1)
 * stack/queue:     push/pop/top/front/back O(1)
 * sort:            O(n log n)
 * binary_search / lower_bound / upper_bound: O(log n), needs sorted range
 *
 * RULE OF THUMB:
 * - Need sorted order / range queries (lower_bound etc.) -> set / map
 * - Just need existence / frequency counting, no order -> unordered_set / unordered_map
 * - Need min/max repeatedly -> priority_queue
 * - Need both ends fast -> deque
 */

/* =========================================================
 * 13. GOTCHAS (things that bite in contests)
 * ========================================================= */
void gotchas() {
    // 1. m["key"] on a map/unordered_map INSERTS "key" with default value if absent.
    //    Use count()/find() for pure existence checks when you don't want insertion.

    // 2. multiset::erase(value) removes ALL occurrences of value.
    //    Use ms.erase(ms.find(value)) to remove just one.

    // 3. unique() does NOT remove all duplicates, only consecutive ones.
    //    Always sort() before unique() if you want all dupes gone.

    // 4. set/unordered_set: erasing while iterating invalidates the iterator.
    //    Use: it = s.erase(it); instead of s.erase(it); ++it;

    // 5. Integer overflow: int overflows at ~2.1e9. Use long long for sums/products
    //    that could exceed that, especially in DP problems.

    // 6. vector<bool> is a bitset-like specialization, NOT a normal vector —
    //    avoid taking references to its elements (bool& b = v[0] doesn't work as expected).

    // 7. Passing large containers by value copies them — pass by reference (&)
    //    in function signatures unless you intend to copy.

    // 8. auto& vs auto in range-for: use auto& to avoid copying elements
    //    (important for vector<vector<int>> or vector<string>).
}
