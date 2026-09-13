# Design a Search Typeahead / Autocomplete System

## Problem Statement

"Design the typeahead suggestions feature you see in a search box — as the
user types each character, show a ranked list of likely completions (like
Google Search's dropdown). It needs to feel instantaneous, keystroke by
keystroke, and the suggestions should reflect what's actually popular, not
just what technically starts with the typed prefix."

This tests a specific and often underestimated skill: designing for an
extremely tight per-request latency budget (every keystroke is a request)
by moving expensive work out of the request path entirely.

## Step 1: Clarify Requirements

**Functional Requirements**
- Given a partial query (prefix) typed so far, return the top K (e.g., top
  5-10) most likely completions.
- Suggestions should be ranked by relevance — generally a function of
  historical popularity/frequency of that full query, not just
  alphabetical or "first match."
- Support incremental updates as popularity shifts over time (yesterday's
  trending query shouldn't dominate suggestions forever).
- Suggestions should update on every keystroke, not just after the user
  finishes typing or hits enter.

**Non-Functional Requirements**
- **Latency is the defining constraint**: because a request fires on
  *every keystroke*, the round-trip (network + lookup + ranking) needs to
  complete in well under 100ms end-to-end for the UI to feel responsive —
  we'll target under 20ms of that budget for the actual server-side
  lookup, leaving headroom for network and rendering.
- **Read-heavy, extremely read-heavy**: every keystroke from every active
  user is a read; writes (new queries entering the popularity data) happen
  at a completely different, much lower, and non-latency-sensitive
  cadence.
- **Approximate freshness is acceptable**: suggestions do not need to
  reflect the most recent few seconds of query traffic — "eventually
  reflects recent trends, refreshed periodically" is a fine and, as we'll
  see, load-bearing relaxation of the requirement.
- **Scale**: must serve a very high volume of keystroke-level requests
  (quantified in Step 2) from a dataset of a very large number of distinct
  historical queries.
- **Availability**: a typeahead outage should degrade gracefully (empty
  suggestion list, search still works via direct submission) rather than
  breaking the search box entirely — it's an enhancement, not
  load-bearing infrastructure for the core search function.

## Step 2: Back-of-Envelope Estimation

**Assumptions**: a search product with 500 million searches/day; average
query length of 20 characters typed (meaning roughly 20 keystrokes could
each trigger a suggestion request, though real clients typically debounce
and don't fire on literally every keystroke).

**Request QPS**
- 500,000,000 searches/day, and assume on average a client fires ~5
  typeahead requests per completed search (after debouncing — not 20, since
  clients wait a short idle interval, e.g. 100-150ms, before firing, so
  fast typists trigger fewer requests than characters typed).
- 500,000,000 x 5 = 2,500,000,000 typeahead requests/day.
- 2,500,000,000 / 86,400 ≈ 28,935 requests/sec average.
- At a 3x peak multiplier: ≈ 86,806 requests/sec peak — this is the number
  the serving tier must be provisioned for, and it's an order of magnitude
  larger than the actual "search submitted" QPS (500M/86,400 ≈ 5,787/sec
  average), underscoring how much more request volume the *suggestion*
  path carries than the *search* path itself.

**Trie size / storage**
- Assume 50 million distinct historical queries worth tracking (long-tail
  queries beyond some minimum frequency threshold are pruned — a query
  typed exactly once by exactly one person ever isn't worth indexing).
- Average query length: 20 characters. A naive per-character trie node
  count would be enormous, but nodes are shared across common prefixes
  (that's the entire point of a trie), so actual node count is far lower
  than `50M x 20`. As a rough working estimate for capacity planning,
  assume an effective ~150 million trie nodes after prefix-sharing, each
  node costing roughly 100-150 bytes (child pointers/map, a small
  top-K cached list, metadata) ≈ 15-22 GB total. This comfortably fits in
  memory on a modestly sized fleet, which matters because the whole design
  depends on the trie being served from RAM, not disk (see Step 6.1).

**Bandwidth**
- Each response: top 5-10 suggestions, each a short string (~30 bytes avg)
  plus small metadata ≈ 300-500 bytes per response.
- 86,806 requests/sec x ~400 bytes ≈ 34.7 MB/sec at peak — modest, request
  *rate* and lookup latency are the binding constraints, not payload size.

**Update/ingestion volume**
- 500M searches/day worth of query-log events need to be aggregated into
  popularity counts — this is a batch/offline workload (Step 6.3), not a
  per-request one, so it's sized for throughput over a processing window
  (e.g., "aggregate the last N hours' logs within M minutes"), not for
  request-path latency.

## Step 3: High-Level Design

The critical design decision, driven directly by the latency budget in
Step 1, is a firm **separation between the write/update path (offline,
batch, relaxed latency) and the read/query path (online, in-memory,
extremely latency-sensitive)** — they barely interact except that the
offline path periodically publishes a new version of the data structure
the online path serves from.

```text
   OFFLINE / BATCH PATH (runs periodically, e.g. every few hours)
   +----------------+     +------------------+     +--------------------+
   |  Search/Query    | -> |  Log Aggregation  | -> |  Trie Builder Job   |
   |  Logs (raw events)|    |  (batch job:       |    |  - build trie        |
   |                   |    |   count query       |    |  - compute + cache   |
   |                   |    |   frequency over     |    |    top-K per node     |
   |                   |    |   the window)         |    |  - serialize snapshot  |
   +----------------+     +------------------+     +----------+---------+
                                                                |
                                                                v
                                                     +--------------------+
                                                     |  Trie Snapshot Store |
                                                     |  (blob storage,       |
                                                     |   versioned)           |
                                                     +----------+---------+
                                                                | (periodic pull/push)
   ONLINE / SERVING PATH (the hot path, per keystroke)          v
   +----------+     +------------------+     +--------------------------+
   |  Client   | --> |  API / LB         | --> |  Typeahead Service        |
   |  (search  |     |  (routes by       |     |  instances (N, sharded    |
   |   box UI, |     |   prefix shard,    |     |  by first char/prefix     |
   |   debounced|     |   see Step 6.4)     |     |  range, Step 6.4)          |
   |   requests)|     +------------------+     |  - trie held fully in-      |
   +----------+                                 |    memory                  |
        ^                                        |  - O(prefix length) walk    |
        |                                        |    + O(1) top-K read at      |
        +----------------------------------------+    the terminal node         |
             suggestions (top-K, <20ms)          +--------------------------+
                                                                |
                                          hottest prefixes cached in a
                                          front-tier cache (Redis/CDN),
                                          see Step 6.4
```

The online serving path never computes rankings on the fly — it only ever
does an O(prefix length) trie walk followed by an O(1) read of a
precomputed list, which is what makes the sub-20ms per-keystroke budget
achievable at ~87,000 requests/sec peak.

## Step 4: API Design

**`GET /v1/suggest?q={prefix}&limit=10` — the hot path, called per keystroke**
```
Request:  GET /v1/suggest?q=syst&limit=5
Response: {
  "prefix": "syst",
  "suggestions": [
    { "text": "system design interview questions", "score": 98234 },
    { "text": "systematic review", "score": 45210 },
    { "text": "system32 error fix", "score": 30112 },
    { "text": "systeme.io pricing", "score": 21044 },
    { "text": "system requirements checker", "score": 18877 }
  ]
}
```

**`POST /internal/v1/query-log` — ingestion of raw query events (fire-and-forget, async, not on any user-facing latency path)**
```json
Request: {
  "query": "system design interview questions",
  "user_id": "u_9182",
  "timestamp": "2026-09-13T10:00:00Z"
}
Response: { "status": "accepted" }
```

**`POST /internal/v1/trie/rebuild` — trigger the offline aggregation + rebuild job (ops/cron-triggered, not user-facing)**
```json
Request:  { "window_hours": 6 }
Response: { "job_id": "rebuild-88213", "status": "queued" }
```

**`GET /internal/v1/trie/version` — used by serving instances to check for a newer snapshot to pull**
```json
Response: { "current_version": "v2026091310", "built_at": "2026-09-13T10:00:00Z" }
```

## Step 5: Data Model

Two very different shapes, matching the two very different paths:

**Online serving structure — an in-memory trie**, not a traditional
database at all for the hot path. This is the right call because the
query pattern (repeatedly narrowing a prefix, character by character, and
needing the answer in single-digit milliseconds) doesn't match what a disk-
backed database is good at — it matches exactly what an in-memory tree
structure is good at. Conceptually:
```
TrieNode {
  children: Map<char, TrieNode>       // one entry per next possible character
  top_k: [ { text, score }, ... ]      // precomputed, sorted, at THIS node
  is_terminal: bool                    // true if a full query ends here
}
```

**Offline aggregation output (before being compiled into the trie) — a
key-value or wide-column store**, since this stage is really just "count
occurrences of each query string over a time window," a straightforward
aggregation workload:
```
query_frequency: {
  query_text: "system design interview questions",
  count_last_window: 4021,
  decayed_score: 98234    // recency-weighted, see Step 6.2
}
```

**Raw query logs** feeding the aggregation are naturally an **append-only
event log / stream** (e.g., Kafka or a similar log store — see
`01_Concepts/10_message_queues_and_streaming.md`), not a queryable
database — they're write-once, read-sequentially-in-batch, which is
exactly a log's access pattern.

**Trie snapshots** are versioned, immutable blobs (serialized trie
structure or an equivalent compact encoding) held in **object storage**
(see `01_Concepts/12_storage_systems.md`), because each rebuild produces a
complete new artifact that serving instances pull wholesale — this is not
a row-level update pattern, so a SQL/NoSQL database would be the wrong
fit; a versioned blob store is.

## Step 6: Deep Dive

### 6.1 Trie construction for prefix matching

A trie (prefix tree) is the natural structure because its defining
property — every node represents one prefix, and all queries sharing that
prefix share the path down to that node — is exactly the access pattern
typeahead needs: "given everything typed so far, what comes next."

- Each edge from a node is labeled with one character; walking from the
  root by the characters of the typed prefix (`s` -> `y` -> `s` -> `t` for
  "syst") lands at the node representing that exact prefix.
- **Lookup cost is O(L)** where L is the length of the typed prefix (a
  handful of characters in practice, since prefixes are short by
  definition — the whole point of typeahead is suggesting before the full
  query is typed), completely independent of how many total queries are
  indexed. This is what makes the trie scale to tens of millions of
  indexed queries without lookup latency growing.
- Common prefixes are **structurally shared** — "system", "systematic",
  and "systeme.io" all share the same first 6 nodes (`s-y-s-t-e-m`) before
  diverging, which is both what keeps the node count in Step 2's estimate
  far below a naive per-query character count and what makes a single trie
  walk simultaneously "aware of" every completion sharing that prefix.
- Each node marked `is_terminal = true` corresponds to a complete
  historical query ending exactly at that point, distinct from a node that
  is merely a prefix of longer queries passing through it (both can be
  true for the same node — e.g., "cat" might be both a complete query in
  its own right and a prefix of "category").

### 6.2 Ranking suggestions — precomputing top-K at every node

This is the single most important optimization in the whole design, and
directly answers the tight latency budget from Step 1.

- **The naive approach**: on each request, walk to the node for the typed
  prefix, then traverse the *entire subtree* below that node, collect every
  complete query in it, sort by popularity, and return the top K. This
  works correctness-wise but is disastrous for latency — a popular short
  prefix like "a" or "th" might have a subtree containing millions of
  distinct completions, and traversing + sorting that subtree on every one
  of tens of thousands of requests/sec is nowhere close to the <20ms
  budget, and gets worse, not better, as the dataset grows.
- **The fix — precompute and cache the top-K list at every single trie
  node, at build time, not at request time.** During the offline rebuild
  (Step 6.3), after computing popularity scores for every complete query,
  a bottom-up pass propagates each query's score up through every node on
  its path from the root, and at each node, the K highest-scoring queries
  passing through it are retained (a small, fixed-size, pre-sorted list) —
  everything else is discarded from that node's cached list (though still
  present deeper in the actual trie structure for nodes further down the
  path).
- **Why this trade-off matters specifically here**: it converts the
  request-path cost from "traverse a subtree of unbounded size and sort
  it" to "walk O(prefix length) nodes, then read a pre-sorted list of size
  K that's already sitting at the terminal node" — an O(1) read relative
  to dataset size. The cost of this precomputation (extra memory per node
  to store the top-K list, and CPU time during the offline rebuild to
  propagate scores) is paid entirely **offline**, exactly where the
  latency budget is relaxed (Step 1), in exchange for making the **online**
  path — where the latency budget is brutally tight — nearly free. This is
  the textbook example of moving cost from the hot path to the cold path
  when the hot path has a much stricter constraint.
- **Popularity scoring detail**: raw frequency count alone tends to
  over-favor old, steady queries over newly trending ones — production
  systems typically use a **time-decayed score** (e.g., exponentially
  weighting recent occurrences more heavily than older ones, or computing
  frequency over a rolling recent window rather than all-time), so a
  suddenly trending query can surface in suggestions within the next
  rebuild cycle rather than being permanently buried under a
  high-all-time-volume but no-longer-relevant query.

### 6.3 How the trie/ranking data gets updated

- Search queries are **not** incorporated into the trie synchronously as
  they happen — doing so would mean every search mutates a shared,
  latency-critical data structure that millions of concurrent typeahead
  requests are reading from, which would either serialize writes against
  reads (killing read latency) or require complex fine-grained concurrency
  control for a benefit (100%-fresh-to-the-second popularity data) the
  requirements explicitly said isn't needed (Step 1).
- Instead, an **offline/batch pipeline** runs periodically (every few
  hours is typical, though the exact cadence is a product decision — more
  frequent for a fast-moving news/trending context, less frequent for a
  stable product-catalog search):
  1. Raw query events accumulate in an append-only log (Step 5).
  2. A batch aggregation job (e.g., a MapReduce/Spark-style job) counts
     query frequency over the aggregation window and computes the
     decayed popularity score per query (Step 6.2).
  3. A trie-builder job constructs a brand-new trie from scratch
     (or incrementally updates one, though full rebuilds are often simpler
     to reason about and verify at this data size) with the precomputed
     top-K lists baked into every node.
  4. The new trie is serialized and published as a new versioned snapshot
     to object storage.
  5. Serving instances detect the new version (via polling or a
     notification) and **swap** to it — typically by loading the new
     snapshot into memory alongside the old one and atomically flipping a
     pointer once fully loaded, so there's no window where requests are
     served from a half-loaded, inconsistent structure, and no downtime
     during the swap.
- **Why batch instead of real-time is the right call here, specifically**:
  the functional requirement was "reflects recent trends, refreshed
  periodically" (Step 1) — real-time-exact popularity was explicitly
  called out as unnecessary. This relaxation is what licenses the entire
  offline/online split; a hypothetical variant of this problem that
  genuinely required second-by-second popularity accuracy would need a
  fundamentally different (and much harder) streaming-update design.

### 6.4 Sharding the trie and caching hot prefixes

- **Sharding by first character (or a short prefix range)**: once the
  full trie is too large for a single machine's memory (Step 2 estimated
  15-22 GB at 50M queries — comfortably single-machine today, but the
  design should scale past that), split it across multiple serving
  instances by the first one or two characters of the prefix — e.g.,
  instance group 1 serves all prefixes starting `a`-`h`, group 2 serves
  `i`-`p`, and so on. A routing layer in front (Step 3's API/LB) inspects
  the incoming prefix and forwards to the correct shard.
  - This works because a typeahead lookup only ever needs the single
    subtree rooted at the typed prefix — there's no cross-shard join or
    aggregation needed at request time, unlike many sharding schemes that
    require scatter-gather. A request for "syst" only ever needs the `s`
    shard.
  - Shard boundaries should be chosen to balance load, not just
    alphabetically evenly — some starting characters (and short prefixes)
    are far more heavily queried than others in most languages/domains, so
    boundaries are usually tuned from real traffic distribution rather
    than a naive 26-way alphabetic split.
- **Caching the hottest prefixes**: very short prefixes ("a", "th", "wh")
  are typed by an enormous fraction of all users (nearly everyone types
  through a 1- and 2-character prefix state on the way to a longer query)
  and their result sets change relatively rarely between rebuild cycles —
  this makes them the ideal candidate for a **front-tier cache** (Redis or
  even a CDN edge cache, per `01_Concepts/05_caching.md`) sitting in front
  of the sharded trie servers entirely.
  - A cache lookup for `"a"` or `"th"` is even cheaper than a trie walk
    (no network hop to a trie shard at all if served from an edge cache),
    and because these ultra-short prefixes are requested by a
    disproportionate share of all traffic, caching just the handful of
    1-2 character prefixes can absorb a large fraction of total request
    volume before it ever reaches the trie-serving tier.
  - Cache TTL is naturally tied to the rebuild cadence from Step 6.3 —
    there's no point caching a prefix's results longer than the data
    itself remains current, so a cache invalidation (or simply a TTL
    matching the rebuild window) is triggered whenever a new trie snapshot
    is published.
  - Longer, rarer prefixes are not worth caching individually (low reuse
    per entry, and there are combinatorially many of them) — they're left
    to hit the trie-serving tier directly, where the O(1)-ish precomputed
    top-K lookup (Step 6.2) is already fast enough on its own.

## Step 7: Bottlenecks & Trade-offs

- **What breaks first**: the online serving tier's request rate (~87,000
  requests/sec peak from Step 2) is the dominant scaling pressure — far
  higher than the actual "searches submitted" rate, because every keystroke
  generates a request. This is why sharding (Step 6.4) and front-tier
  caching of hot prefixes exist — without them, a single logical trie
  service would need to absorb the full peak QPS on every request with no
  offload.
- **Staleness window**: because updates are batched (Step 6.3), there's an
  inherent lag between a query becoming newly popular and that popularity
  showing up in suggestions — bounded by the rebuild cadence (e.g., up to
  6 hours in the earlier example). This is an accepted trade-off given the
  relaxed freshness requirement, but it's a real limitation for
  genuinely time-sensitive use cases (e.g., breaking-news search), which
  would need a shorter rebuild cycle or a hybrid design that layers a
  small, frequently-updated "trending now" boost on top of the base trie
  rather than trying to make the whole trie real-time.
- **Memory pressure per instance**: the entire design assumes the (shard
  of the) trie fits in RAM — this is what makes lookups fast, but it caps
  how much vocabulary a single shard can hold before needing further
  sharding or aggressive pruning of low-frequency long-tail queries (Step
  2's "queries below some minimum frequency threshold are pruned"
  assumption is doing real work here, not just simplifying the estimate).
- **Trade-off — precomputed top-K vs. exact real-time ranking**: Step 6.2's
  central trade-off restated — a request never sees a perfectly
  up-to-the-second-accurate ranking, only "as of the last rebuild," in
  exchange for the O(1)-ish lookup that makes the whole latency budget
  achievable. Reversing this trade-off (compute rankings live) would
  blow the latency budget at this request volume.
- **Cold-start problem**: a brand-new query with zero historical volume has
  no path in the trie yet and won't appear in any suggestions until it
  survives at least one aggregation cycle and accumulates enough frequency
  to make some node's top-K list — an inherent limitation of a
  popularity-driven design, sometimes mitigated by blending in
  content-based signals (e.g., catalog/dictionary matches) for prefixes
  with sparse historical data.

## Follow-up Questions an Interviewer Might Ask

- **"How would you personalize suggestions per user (e.g., their own
  search history)?"** Layer a small, per-user recent-history list on top
  of the global trie results — checked first and merged/deduplicated with
  the global top-K — rather than building a separate full trie per user,
  since a per-user global trie doesn't scale and most of the ranking
  signal is legitimately global/shared popularity, not personal.
- **"How do you handle typos or fuzzy prefixes (the user typed 'systm' by
  mistake)?"** A pure trie only matches exact prefixes — fuzzy matching
  needs a separate mechanism layered on top, such as also querying a small
  edit-distance-tolerant index (or generating likely corrections and
  re-querying the trie with the corrected prefix) when the exact-prefix
  trie walk returns too few or no results.
- **"How would you support suggestions in multiple languages/scripts?"**
  Shard by language (detected from the user's locale/input) into
  separate tries rather than one shared trie, since character sets and
  meaningful prefix structure differ fundamentally across scripts (e.g., a
  Latin-alphabet trie's prefix logic doesn't transfer to CJK input
  methods), and route requests to the right language's trie shard using
  the same routing layer described in Step 6.4.
- **"What if the trie rebuild job itself becomes too slow to keep up as
  query volume grows?"** Move from full rebuilds to incremental updates —
  periodically merge only the newest aggregation window's score deltas
  into the existing trie's top-K lists rather than reconstructing the
  whole structure from scratch each cycle, trading rebuild-job simplicity
  for reduced rebuild latency and lower recurring compute cost.
- **"How would you A/B test a new ranking algorithm without risking the
  production suggestion quality?"** Build both the old and new trie
  snapshots from the same rebuild job, route a small percentage of live
  traffic to serving instances loaded with the new snapshot, and compare
  engagement metrics (click-through rate on suggestions) before rolling
  the new version out fleet-wide — enabled directly by the versioned
  snapshot design in Step 5, since snapshots are already immutable,
  independently loadable artifacts.
- **"How do you keep the front-tier cache from serving stale suggestions
  right after a trie rebuild?"** Tie cache invalidation to the trie
  version rather than a fixed wall-clock TTL alone — include the trie
  snapshot version in the cache key (or explicitly flush the hot-prefix
  cache as the final step of the snapshot-swap process in Step 6.3), so a
  new snapshot's results can't be masked by a still-live cache entry
  computed against the previous version.
