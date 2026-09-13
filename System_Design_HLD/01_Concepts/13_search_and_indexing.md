# Search and Indexing

## Why it matters

Almost every product eventually needs "find the thing matching this text" — search a product catalog, search messages, search users, autocomplete a search box. A naive implementation (`LIKE '%query%'` against a relational table) works at small scale and then falls over: it can't rank results by relevance, it forces a full table scan (or a near-full scan even with a B-tree index, since B-tree indexes are built for equality/range lookups on a column, not for "does this blob of text contain this word"), and it has no vocabulary for "match some of these words, rank by how good the match is." Search engines like Elasticsearch exist specifically to solve full-text search at scale, and understanding the data structure underneath them (the inverted index) is what lets you reason about their behavior — indexing lag, relevance, sharding — instead of treating them as a black box.

This file also covers typeahead/autocomplete, which is a distinct problem (prefix matching against a small, ranked set of strings, answered in milliseconds as the user types) that shows up constantly as its own interview question.

## The problem with searching text in a regular database

A relational database's index (a B-tree, typically) is excellent at "find rows where `column = X`" or "find rows where `column` is between X and Y," because a B-tree stores sorted keys and can binary-search them. It is not built to answer "find rows where this large text column *contains* one of these words, ranked by how well it matches." A `LIKE '%word%'` query with a leading wildcard cannot use a B-tree index at all — the database must scan every row and check each one, which is O(n) in the number of rows and gets slower as the corpus grows.

Full-text search needs a completely different structure: instead of indexing rows by a value, you index the *individual words inside* the text, and store which documents each word appears in. That structure is the inverted index.

## Inverted index: the core data structure

A **forward index** maps documents → the terms (words) they contain — that's just... the document itself, or a simple `doc_id -> [word1, word2, ...]` table. It's what you'd build naturally, and it's useless for search: to answer "which documents contain 'redis'," you'd have to scan every document's word list.

An **inverted index** flips this: it maps each term → the list of documents containing that term (called a **postings list**). This is the "opposite" (inverse) of the forward index, hence the name. It turns "which documents contain this word" from a full scan into a single hash/tree lookup.

### Worked example

Four tiny documents:

```text
Doc 1: "redis is a fast cache"
Doc 2: "postgres is a durable database"
Doc 3: "redis is used as a cache and a queue"
Doc 4: "elasticsearch is a fast search database"
```

Step 1 — **tokenize** each document (split into words, lowercase, usually strip common "stopwords" like "a," "is," "as," "and" — omitted here for clarity but a real system would drop or down-weight them):

```text
Doc 1: [redis, fast, cache]
Doc 2: [postgres, durable, database]
Doc 3: [redis, used, cache, queue]
Doc 4: [elasticsearch, fast, search, database]
```

Step 2 — **invert**: build a map from each term to the list of doc IDs containing it.

```text
cache         -> [1, 3]
database      -> [2, 4]
durable       -> [2]
elasticsearch -> [4]
fast          -> [1, 4]
postgres      -> [2]
queue         -> [3]
redis         -> [1, 3]
search        -> [4]
used          -> [3]
```

Step 3 — **query**. A search for `"redis cache"` (find documents matching both terms) becomes:

1. Look up `redis` → `[1, 3]`
2. Look up `cache` → `[1, 3]`
3. Intersect the two postings lists → `[1, 3]`

No document was scanned. The whole query is two hash lookups plus a list intersection, and this stays fast whether the corpus has 4 documents or 4 billion — postings lists are also typically sorted by doc ID, which makes the intersection itself a fast linear merge (like merging two sorted arrays) instead of a nested-loop comparison.

Real inverted indexes store more than just doc IDs in each postings list entry — commonly the term frequency (how many times the term appears in that doc, used for ranking, see below) and the positions where it appears (needed to support phrase queries like `"fast cache"` matching only when the words are adjacent).

## Elasticsearch / Lucene basics

**Lucene** is the underlying Java library that implements an inverted index (plus the query engine, scoring, and on-disk storage format) for a single machine. **Elasticsearch** is a distributed system built on top of Lucene — it adds horizontal scaling, replication, a JSON HTTP API, and cluster management around Lucene's single-node index. (**Solr** is another well-known Lucene-based search server; the interview-relevant point is the same either way: distributed system wrapping a Lucene-style inverted index.)

Enough to reason about it in an interview:

- **Documents are indexed into shards.** An Elasticsearch "index" (roughly: a table) is split into multiple **shards**, each of which is a self-contained Lucene inverted index holding a subset of the documents. This is the same horizontal-partitioning idea as database sharding (see `07_database_scaling.md`) — it lets you spread both the storage and the query load for one logical index across many machines, and a query fans out to all relevant shards and merges the results.
- **Near-real-time (NRT) search, not instant.** When a document is written, it isn't immediately searchable. Elasticsearch batches writes into an in-memory buffer and periodically "refreshes" it into a searchable Lucene segment (by default roughly every second). This means there's a small window (typically under a second, but tunable and sometimes longer under load) between "write acknowledged" and "document shows up in search results." This is an important trade-off to name explicitly in an interview: search is a great fit for read-heavy, latency-tolerant-on-writes use cases, and a poor fit for anything requiring the searcher to see a write immediately (e.g., "I just posted a comment, and it must appear in search results in the same request cycle").
- **Relevance scoring (TF-IDF / BM25), conceptually.** Once multiple documents match a query, they need to be ranked by relevance, not just returned in an arbitrary order. The classic intuition (TF-IDF — Term Frequency, Inverse Document Frequency — and BM25, a refined, more modern version of the same idea used by default in Elasticsearch/Lucene) is:
  - A term that appears **often in a specific document** is probably important to that document (term frequency).
  - A term that appears **in almost every document in the corpus** (like "the" or "is") carries very little distinguishing signal, so it should count for less (inverse document frequency — rare-across-the-corpus terms are weighted up, common ones weighted down).
  - Combine the two: a document scores highest for a query term when that term is frequent *in it* but rare *across the corpus overall*. You do not need the exact formula for an interview — the intuition ("rare-but-locally-frequent terms score higher") is what matters.

```text
                     ┌──────────────┐
  client query  ───► │ Elasticsearch │
                     │  coordinator  │
                     └───────┬──────┘
              fan out to relevant shards
        ┌────────────┬───────┴───────┬────────────┐
        ▼             ▼               ▼            ▼
   Shard 1        Shard 2         Shard 3       Shard 4
 (Lucene idx)   (Lucene idx)    (Lucene idx)  (Lucene idx)
        │             │               │            │
        └────────────┴───────┬───────┴────────────┘
                  merge + rank results
                              ▼
                     results returned
```

## Typeahead / autocomplete, conceptually

Typeahead is a different problem from full-text search: instead of "find documents containing these words anywhere," it's "as the user types character by character, suggest complete strings that start with what they've typed so far, ranked by likely relevance" — and it must respond within milliseconds of every keystroke.

- **Prefix matching via a trie.** A **trie** (prefix tree) is a tree where each node represents one character, and a path from the root spells out a string. Walking down the trie one character at a time as the user types naturally narrows the set of matching strings to exactly the ones sharing that prefix — the moment you're at the node for `"ca"`, every string reachable below that node starts with `"ca"`. This is a good structural fit because it makes "give me everything starting with this prefix" a direct tree traversal instead of a filter over a full list of strings.

```text
        (root)
        /    \
       c      d
       |      |
       a      o
      / \      \
     r   t      g
     |   |
     e   ...
   "care"      "cat"
```

- **Ranking suggestions by popularity, not just prefix match.** A prefix can match thousands of strings (every product name starting with "c"), so you can't just return "all of them" — you need to rank by something like search frequency/popularity. Rather than recomputing "the top-k most popular completions for this prefix" on every keystroke (expensive if the popularity data is large), a common approach is to **precompute and cache the top-k suggestions at each trie node** (offline or periodically), so a request for a given prefix is just "walk to that node, return its cached top-k list" — O(prefix length) plus a cache read, not a live ranking computation.

- **This is a conceptual sketch only.** The full worked design — how to keep suggestion popularity updated in near-real-time as new searches come in, personalization (ranking differently per user), and how to cache hot prefixes to survive high request volume — is worked through end-to-end in **`02_Interview_Questions/04_typeahead_autocomplete.md`**. Treat this section as the vocabulary you need going into that file, not the full design.

## Analyzers: what happens to text before it's indexed

The tokenization step in the worked example above ("split into words, lowercase") is actually a pipeline called an **analyzer** in Lucene/Elasticsearch terms, and it's worth naming explicitly because it's where a lot of real search quality is won or lost:

- **Tokenization** — split raw text into individual terms (usually on whitespace/punctuation).
- **Lowercasing** — so `"Redis"` and `"redis"` match the same postings list entry.
- **Stopword removal** — drop extremely common, low-signal words ("a," "the," "is") so they don't bloat postings lists or dilute relevance scoring.
- **Stemming/lemmatization** — reduce words to a root form (`"running"`, `"ran"` → `"run"`) so a search for one form matches documents using another.

The same query string can produce very different results depending on the analyzer configuration — this is why two search systems indexing the "same" data can behave differently, and it's a reasonable thing to mention if an interviewer asks about search quality/relevance tuning.

## Replication for search shards

Just like a sharded database, each Elasticsearch shard is normally backed by one or more **replica shards** — full copies of that shard's data on other nodes. Replicas serve two purposes: fault tolerance (if the node holding the primary shard dies, a replica is promoted and no data is lost) and read throughput (queries can be served by any in-sync replica, spreading read load). This mirrors the primary/replica vocabulary from `07_database_scaling.md` — it's the same underlying idea (copy data across nodes for durability and read scale) applied inside a search cluster instead of a relational database.

## Index types compared

A quick reference for when an interviewer asks "why not just use X" about any of these:

| Structure | Answers | Weak at |
|---|---|---|
| B-tree (relational DB index) | Equality/range lookups on a column (`WHERE price BETWEEN 10 AND 50`) | Full-text search inside a text blob |
| Hash index | Exact-match lookup (`WHERE id = X`) | Range queries, prefix queries, text search |
| Inverted index | "Which documents contain these words," ranked by relevance | Range queries on numeric fields (Elasticsearch layers other structures in for that) |
| Trie | Prefix matching (autocomplete, IP routing tables) | Full-text "contains this word anywhere" search, relevance ranking |

## Trade-offs

| Approach | Good for | Bad for |
|---|---|---|
| `LIKE '%x%'` in your primary DB | Tiny datasets, infrequent search, zero extra infra | Any real scale — full scan, no relevance ranking, no fuzzy/prefix features |
| Full-text index in your DB (e.g., Postgres `tsvector`/GIN index) | Medium scale, avoids running a separate search cluster, keeps data consistent with the source of truth | Ranking and query features are less sophisticated than a dedicated engine; still lives on your primary DB's hardware and competes with transactional load |
| Dedicated search engine (Elasticsearch/Solr) | Large scale, rich relevance ranking, faceting/aggregations, horizontal scale via shards | Extra system to run and keep in sync (usually via a change-data-capture or dual-write pipeline from the source of truth), near-real-time not instant, eventual consistency between the DB and the index |
| Trie-based prefix index | Autocomplete/typeahead — prefix queries need to be fast and ranked | Wrong tool for "contains this word anywhere" full-text search |

## When to use what

- Small dataset, infrequent search, exact-ish matches acceptable → don't build a search system, a DB query is fine.
- Need relevance-ranked full-text search over a large, growing corpus → dedicated search engine (Elasticsearch-style), accept the sync lag between source-of-truth DB and index.
- Need instant, ranked, prefix-based suggestions as a user types → trie (or a search engine's built-in "completion suggester," which is the same idea productionized) with precomputed/cached top-k per prefix, not a live full-text query per keystroke.

## Interview Tips

- If a question involves "search," immediately clarify whether it means full-text search (rank by relevance) or exact lookup (a plain index or key-value store is enough) — candidates often reach for Elasticsearch when a simple indexed column would do.
- Explicitly name the consistency trade-off: the search index is a derived, denormalized copy of the source-of-truth data, updated asynchronously, so a write may take a moment to become searchable. State this instead of implying search is transactionally consistent with writes.
- Tie shard count back to what you already know about database sharding: same idea (split data across nodes to scale reads/writes/storage horizontally), same problems (uneven shard sizes, needing to fan out and merge on query).
- For typeahead specifically, don't over-explain in this section of an interview — say "trie with precomputed top-k per node, refreshed periodically or via a write-behind update," and save the deep detail (real-time popularity updates, personalization, hot-prefix caching) for when the interviewer wants to go deeper.

## Quick Recall — Self-Test

**Q1: What is an inverted index, and how is it different from a forward index?**
An inverted index maps each term to the list of documents containing it (term → doc IDs). A forward index maps each document to the terms it contains (doc → terms), which is the natural representation but useless for fast search, since answering "which docs contain X" would require scanning every document's term list.

**Q2: Why can't a standard relational B-tree index efficiently answer "does this text column contain this word"?**
A B-tree is built for equality and range lookups on sorted keys, not for testing whether a substring/word appears inside a large text blob. A `LIKE '%word%'` query with a leading wildcard can't use it and falls back to scanning every row.

**Q3: What does "near-real-time search" mean in Elasticsearch, and why does it matter for a design?**
Newly written documents aren't searchable instantly — they sit in an in-memory buffer until a periodic refresh (often about once a second) makes them queryable. It matters because a design that needs a write to be immediately reflected in search results (same request cycle) can't rely on this refresh delay.

**Q4: What is the intuition behind TF-IDF/BM25 relevance scoring, without the formula?**
A term contributes more to a document's relevance score when it appears frequently in that specific document (term frequency) but rarely across the whole corpus (inverse document frequency) — common words like "the" score low everywhere, while a rare term that's frequent in one document is a strong signal that document matches.

**Q5: How does sharding in Elasticsearch relate to database sharding you already know?**
Same underlying idea: split one logical index's data across multiple machines (shards) so storage and query load scale horizontally. A query fans out to the relevant shards and the coordinator merges results, just as a sharded database query (or scatter-gather) would.

**Q6: Why is a trie a good structural fit for autocomplete?**
Each node represents a character, and the path from root to a node spells a prefix — so all strings sharing that prefix live in the subtree below that node. Walking the trie as the user types directly narrows the candidate set with each keystroke, in time proportional to the prefix length, not the size of the whole dataset.

**Q7: Why precompute top-k suggestions at each trie node instead of ranking live on every request?**
Ranking "most popular completions for this prefix" from scratch on every keystroke is expensive when there are many matches and popularity data is large. Precomputing (periodically or via write-behind updates) means a request is just a tree walk to the node plus a cached-list read — fast and cheap even under heavy keystroke-driven request volume.

**Q8: Where should you look for the full end-to-end typeahead design, and what does this file's coverage stop short of?**
`02_Interview_Questions/04_typeahead_autocomplete.md` covers the full design — real-time popularity updates, personalization, and caching hot prefixes. This file only gives the conceptual building blocks (trie, precomputed ranking) needed to follow that design.
