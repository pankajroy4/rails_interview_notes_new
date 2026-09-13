# Design a Web Search Engine

## Problem Statement

"Design a simplified web search engine, like Google Search. Given a text query,
return a ranked list of the most relevant web pages out of an index covering a
large fraction of the public web, in well under a second." This question
deliberately composes two subsystems you've likely already designed separately — a
web crawler to acquire content, and a search/indexing system built on an inverted
index to retrieve it — so a strong candidate should spend little time re-deriving
those and instead focus on what's genuinely new at this scale: how the index is
sharded across a fleet of machines, and how results are ranked well, cheaply, at
that scale.

## Step 1: Clarify Requirements

**Functional Requirements**

- Accept free-text search queries and return a ranked list of relevant web page
  results (URL, title, snippet).
- Continuously discover and index new and updated pages from across the web.
- Support standard query features: multi-word queries (implicit AND of terms),
  phrase queries, basic operators.
- Rank results by genuine relevance, not just keyword match — combining textual
  relevance with page authority/quality signals.
- Support autosuggest/typeahead as a secondary feature (briefly — not the focus of
  this design).

**Non-Functional Requirements**

- Query latency: end-to-end under ~200-300ms for the vast majority of queries,
  since search is a synchronous, user-facing, latency-sensitive product.
- Massive read scale: the query path must serve a very high, globally distributed
  QPS with high availability.
- Massive index scale: the corpus is on the order of tens to hundreds of billions
  of pages.
- Freshness: new/changed content should become searchable within a reasonable
  window (minutes to hours for most pages, faster for high-priority sources like
  breaking news) without requiring a full corpus reindex.
- Consistency is relaxed: it's acceptable for a brand-new page to take some time
  to appear in results (eventual, not immediate, consistency) — this is a
  read-heavy system that favors availability and latency over strict freshness
  guarantees.
- Cost efficiency at scale: index storage and per-query compute cost both need to
  be controlled given the sheer size of the corpus and query volume.

## Step 2: Back-of-Envelope Estimation

**Assumptions**

- Indexed corpus: 50 billion web pages (a reasonable order-of-magnitude for a
  large web search engine).
- Average page, after HTML stripping and text extraction, contains roughly 1,000
  indexable terms (with repetition; distinct terms per page are fewer).
- Query volume: 50,000 queries/sec average globally, peaking around 150,000
  queries/sec.

**Index size**

- A classic inverted index entry (a "posting") stores, per (term, document) pair,
  at least a document ID and typically position/frequency information for ranking
  — call it roughly 8-12 bytes per posting after compression (real search engines
  invest heavily in posting-list compression techniques; assume compressed).
- Total postings, if every page contributed ~1,000 term occurrences and we
  conservatively assume ~300 non-trivial distinct indexed terms per page after
  stopword removal and dedup: 50 billion pages x 300 distinct terms ≈ 15 trillion
  postings.
- At ~10 bytes/posting compressed: 15 trillion x 10 bytes = 150 TB for the core
  postings data alone. Add the term dictionary (mapping terms to posting-list
  locations — small relative to postings, tens of GB) and this confirms the index
  cannot live on one machine; it must be sharded across a large fleet (see Step
  6).

**Query fan-out cost**

- Under document-partitioning (the approach this design adopts, see Step 6), each
  query fans out to every shard. If the index is split across, say, 1,000 shards,
  one query becomes 1,000 parallel sub-queries.
- At 150,000 queries/sec peak x 1,000 shards = 150,000,000 sub-query
  operations/sec system-wide at peak. This is the number that justifies why each
  shard must be able to answer its local sub-query extremely cheaply (a few
  milliseconds), since it's doing this at enormous aggregate rate.

**Crawl and ingestion volume** (briefly — full detail belongs to
`05_web_crawler.md`)

- Assume the crawler refreshes/discovers roughly 5 billion pages/day to keep a
  50-billion-page corpus reasonably fresh (a ~1% daily refresh rate blended across
  high- and low-churn content). At an average page size of 100 KB raw HTML: 5
  billion x 100 KB = 500 TB/day of raw crawl bandwidth — a very large number,
  which is precisely why `05_web_crawler.md`'s design (politeness limits,
  distributed fetching, prioritization by page-change-frequency) is treated as its
  own subsystem rather than re-derived here.

**Ranking compute cost**

- If retrieval (Step 6) narrows 50 billion pages down to, say, the top 10,000
  candidates per query before expensive ranking is applied, and expensive ranking
  costs roughly 1ms of compute per candidate: 10,000 x 1ms = 10 seconds of ranking
  compute per query if done serially — clearly requiring heavy parallelization
  across many machines/cores per query to hit the sub-300ms latency budget,
  reinforcing why the two-stage retrieve-then-rank split (Step 6) is not optional
  at this scale.

**Index shard fleet sizing**

- With 150 TB of compressed postings (worked out below in Step 6) and a target of
  keeping each shard's data comfortably servable from fast local storage/memory —
  say 150 GB of postings per shard, a size that keeps per-shard query latency low
  and fits reasonably on a well-provisioned host — that implies roughly 150 TB /
  150 GB = 1,000 shards, consistent with the fan-out assumption used above. Each
  shard also needs replicas for both availability and query-serving capacity (a
  single replica per shard can't absorb 150,000 QPS x 1 sub-query each =
  150,000,000 sub-queries/sec alone); assuming each shard replica can serve on the
  order of 2,000-5,000 cheap local sub-queries/sec, serving the full fan-out load
  at peak requires roughly 150,000,000 / 3,000 ≈ 50,000 shard-replica instances
  system-wide — a genuinely large fleet, and the clearest illustration in this
  whole design of why document-partitioning's "predictable, parallelizable"
  fan-out cost (Step 6) matters: this is a lot of machines, but it's a lot of
  *identical, independently scalable* machines, not a lot of *specialized,
  hard-to-balance* ones.

## Step 3: High-Level Design

This system composes two subsystems already covered elsewhere in this question
bank, plus a ranking layer that's new here:

- **Crawler** (full design in `05_web_crawler.md`): discovers URLs, respects
  robots.txt/politeness, fetches pages, and hands raw content downstream. Not
  re-derived in detail here.
- **Content processing pipeline**: parses raw HTML into clean text, extracts the
  link graph (which pages link to which — feeds the authority/PageRank-style
  signal), deduplicates near-identical content, and tokenizes text into indexable
  terms.
- **Indexer**: builds the inverted index (core structure covered in
  `13_search_and_indexing.md`) from processed content, sharded across many
  machines (Step 6).
- **Link-graph / authority processor**: a periodic, large batch job that computes
  page-authority scores (conceptually PageRank-like) from the crawled link graph
  across the whole corpus (Step 6).
- **Query service (retrieval tier)**: receives a query, fans it out to all index
  shards, gets back a candidate set of matching documents with cheap relevance
  scores, and merges results.
- **Ranking service**: takes the merged candidate set (now much smaller —
  thousands, not billions) and applies a more expensive, higher-quality ranking
  model, blending text relevance with authority and other signals, to produce the
  final ordered result list.
- **Serving cache**: caches results for very common/repeated queries to avoid
  redoing full retrieve-and-rank work for identical popular queries.

```text
                         CRAWLING & INDEXING (offline/near-line)
  +-----------+     +-------------------+     +-----------------+
  |  Crawler   |---->| Content Processing |---->|   Indexer        |
  | (see doc   |     | (parse, dedup,     |     | (builds sharded    |
  |  05)       |     |  tokenize, extract |     |  inverted index,   |
  +-----------+     |  link graph)        |     |  see doc 13)       |
                      +---------+---------+     +--------+---------+
                                |                          |
                                v                          v
                      +-------------------+       +------------------+
                      | Link-Graph /       |       | Index Shards      |
                      | Authority Batch Job |------>| (doc-partitioned, |
                      | (PageRank-style,     |       |  ~1000 shards)    |
                      |  periodic, whole-     |       +------------------+
                      |  corpus)              |
                      +-------------------+

                         QUERY PATH (online, latency-critical)
   User Query
       |
       v
 +--------------+     fan out to ALL shards      +------------------+
 | Query Service |-------------------------------->| Index Shard 1..N |
 | (retrieval)   |<--------------------------------|  (cheap TF-IDF/   |
 +------+--------+     merged candidate list        |   BM25 scoring)   |
        |                                            +------------------+
        v
 +----------------+
 | Ranking Service |   <- blends text relevance + authority score
 | (expensive model|      + freshness + other signals, applied ONLY
 |  on top-K only) |         to the small candidate set
 +--------+--------+
          |
          v
 +----------------+
 | Serving Cache    |  (hot/repeated queries)
 +--------+--------+
          |
          v
      Ranked Results -> User
```

## Step 4: API Design

**Search query (primary, latency-critical endpoint)**
```
GET /search?q=best+ramen+in+sf&page=1&pageSize=10
<- {
     query: "best ramen in sf",
     totalEstimated: 4820000,
     results: [
       { url: "https://...", title: "...", snippet: "...", rank: 1 },
       ...
     ],
     latencyMs: 187
   }
```

**Internal: shard-local retrieval (Query Service -> each Index Shard)**
```
POST /shard/{shardId}/retrieve
{ terms: ["ramen", "sf"], topK: 200 }
-> { candidates: [{ docId, termScore }], shardId }
```

**Internal: ranking request (Query Service -> Ranking Service)**
```
POST /rank
{ query: "best ramen in sf", candidateDocIds: [ ...merged top ~2000 from all shards ] }
-> { rankedResults: [{ docId, finalScore }] }
```

**Autosuggest (secondary feature)**
```
GET /suggest?prefix=best+ram
<- { suggestions: ["best ramen in sf", "best ramen recipe", ...] }
```

**Admin/internal: trigger reindex of a specific URL (incremental update path)**
```
POST /internal/index/update { url: "https://example.com/page", content: "...", crawledAt: "..." }
-> 202 Accepted
```

## Step 5: Data Model

**Inverted index (core retrieval structure, detailed in
`13_search_and_indexing.md`)**: a specialized search index structure (e.g.
Lucene/Elasticsearch-style segments, or a custom-built structure), not a
general-purpose database, because the read pattern is entirely "given a term, get
its posting list" rather than relational access.

```
term_dictionary (per shard)
  term            string   -- e.g. "ramen"
  postingListPtr  offset   -- location of this term's posting list

posting_list (per term)
  [ { docId, termFrequency, positions[], fieldWeight }, ... ]  -- sorted by docId within a shard
```

**Document store (raw/processed content, for snippet generation and re-ranking
features)**: a distributed key-value or wide-column store keyed by docId, since
access is always a direct lookup by ID, never a scan or join.

```
documents (key: docId)
  url            string
  title          string
  cleanedText    text
  outboundLinks  [url]
  crawledAt      timestamp
  authorityScore float     -- last computed by the batch link-graph job
```

**Link graph (input to the authority batch job)**: naturally a graph structure;
stored either as an edge list in a distributed store or directly within a
graph-processing framework's own storage during the batch computation, since the
access pattern (traverse links between nodes across the whole corpus) is
graph-shaped, not relational or key-value.

```
links (edge list)
  fromDocId
  toDocId
```

## Step 6: Deep Dive

### Sharding the inverted index: term-partitioning vs document-partitioning

At 150 TB of compressed postings (Step 2), the index cannot live on a single
machine, and how it's split across machines has first-order consequences for both
query cost and ingestion cost.

**Term-partitioning**: each shard owns the complete posting lists for a range of
terms (e.g. shard 1 owns all postings for terms A-C, shard 2 owns D-F, and so on)
across the *entire* corpus. A single-term query is cheap and clean — it hits
exactly one shard, which returns the complete, authoritative posting list for that
term. The problem shows up on multi-term queries, which are the overwhelming
majority of real search traffic: a query for "best ramen sf" needs the posting
lists for three terms that likely live on three different shards, and computing
their intersection (which documents contain ALL three terms) requires pulling
potentially very large posting lists across the network to a coordinating node, or
doing complex distributed intersection logic — either way, a significant
coordination cost that scales poorly as query term count grows, and one term's
posting list can be enormous and imbalanced relative to another's (the posting
list for "the" is astronomically larger than for a rare term), making shard load
inherently uneven.

**Document-partitioning**: each shard instead owns the complete inverted index for
a *subset of the document corpus* — e.g. shard 1 has a full mini-inverted-index
(all terms, all postings) for documents 1 through 50 million, shard 2 for the next
50 million, and so on. Every shard can independently answer ANY query for its
slice of documents, since it holds a complete index over whatever documents it
owns. This means every query must fan out to every shard (as reflected in the Step
2 estimation), each shard does its own local term-intersection and scoring
entirely independently, and the Query Service merges the per-shard result lists
(typically taking each shard's local top-K and merging into a global top-K).

**Document-partitioning is what large real-world search engines actually use, for
two concrete reasons.** First, ingesting new documents scales far more evenly:
adding a newly-crawled page just means inserting it into whichever document shard
currently has room (or a shard chosen by a simple rotation/consistent-hash
scheme), a local, independent operation — whereas under term-partitioning,
indexing a single new document touches potentially hundreds of different
term-owning shards (one for every distinct term the new document contains), since
that document's postings need to be distributed across whichever shards own each
of its terms. Second, query fan-out cost under document-partitioning is
predictable and embarrassingly parallel: every query does the same amount of work
(query all N shards, each doing a bounded amount of local work over its bounded
document slice), which is a much easier capacity-planning and latency-tail problem
than term-partitioning's highly variable, data-dependent coordination cost that
spikes unpredictably based on which specific terms a query happens to combine.

### Two-stage retrieve-then-rank architecture

A query like "best ramen in sf" might textually match tens of millions of pages
across a 50-billion-page corpus (Step 2's `totalEstimated: 4,820,000` in the API
example). If a high-quality ranking model — one that considers dozens or hundreds
of features (click-through history, page quality signals, personalization,
freshness, semantic relevance beyond raw term matching) — were run against every
single matching document, the compute cost would be entirely infeasible within a
sub-300ms latency budget; running an expensive model against millions of documents
per query, multiplied across 150,000 queries/sec at peak, is not a quantity of
compute any reasonably-sized fleet can absorb.

The solution is splitting ranking into two stages with very different cost
profiles:

1. **Retrieval (cheap, broad)**: each index shard scores its local matching
   documents using a relatively simple, fast text-relevance function, conceptually
   TF-IDF or BM25 — scoring based on how rare a term is across the whole corpus (a
   term appearing in few documents is a stronger signal than a common one)
   weighted against how frequently it appears in *this* document (and normalized
   for document length, in BM25's case). This is cheap enough to run against every
   matching document within a shard, because it requires only the statistics
   already sitting in the posting lists themselves (term frequency, document
   frequency) with no external model inference. Each shard returns only its local
   top-K (e.g. top 200) candidates by this cheap score, not its full match set —
   collapsing what could be millions of matches per shard down to a few hundred
   before anything leaves the shard.
2. **Ranking (expensive, narrow)**: the Query Service merges each shard's top-K
   into a combined candidate set — now on the order of a few thousand documents
   system-wide, regardless of how many millions matched in total — and only THIS
   much smaller set is handed to the expensive ranking model, which can now afford
   to compute rich, costly features per candidate (blending in authority score,
   freshness, personalization, and more) since it's doing so for thousands of
   documents, not millions.

This retrieve-then-rank split is the standard way to reconcile "the ranking model
needs to be sophisticated to produce good results" with "the system needs to
answer in under 300ms" — cheap-and-broad first to shrink the problem,
expensive-and-narrow second to solve it well.

**A worked BM25-style example, to make "cheap retrieval scoring" concrete.**
Suppose the query is "ramen sf" and a candidate document is a short blog post.
BM25 combines, per query term, the term's inverse document frequency (rarer terms
across the corpus score higher) with its frequency within this specific document
(saturating, not linear, so a document that repeats "ramen" 50 times doesn't score
50x higher than one with it once), normalized against document length (so a short,
focused document isn't unfairly penalized against a long one that happens to
contain the term more times simply by having more words). Concretely: if "ramen"
appears in 2 million of the 50 billion indexed documents (rare — high
inverse-document-frequency weight) and "sf" appears in 4 billion documents (common
— low weight, since it's a weak discriminator), a document containing "ramen" 3
times in a 200-word post scores much higher on the "ramen" term than a 5,000-word
document containing "ramen" once, even before "sf" is factored in at all — and
critically, all of these numbers (term frequency, document frequency, document
length) are already sitting directly in the shard's local posting lists and term
dictionary, so this score is computable with no network calls, no model inference,
and no per-query training data lookup, which is exactly why it's cheap enough to
run against every local match in a shard rather than reserved for the smaller
candidate set.

### Blending text relevance with link-graph authority

TF-IDF/BM25 retrieval scores measure how well a document's *text* matches the
query, but say nothing about whether the page is trustworthy, authoritative, or
high-quality — a page can be textually a perfect keyword match for "best ramen in
sf" while being a low-quality spam page nobody should see above a
well-established, widely-cited restaurant review site. This is why ranking blends
in a second, independent family of signal: page authority, conceptually captured
by something like PageRank — the idea that a page is more authoritative if many
*other* authoritative pages link to it, computed from the structure of the crawled
link graph across the whole corpus (an approach conceptually similar to
graph-centrality algorithms; the interview-relevant point is the idea of authority
propagating through links, not the exact linear-algebra derivation). Text
relevance (does this page match what was asked) and authority (is this generally a
trustworthy/important page) are deliberately kept as two distinct signals — a page
can be highly relevant but low authority (a brand-new, accurate blog post) or
highly authoritative but low relevance to a specific query (a major news homepage,
for an unrelated query) — and the final ranking model's job is combining these
(plus other signals like freshness, click-through data, personalization) into one
final score, rather than collapsing them into a single measure prematurely.

### Freshness vs full reindexing

The web changes constantly — pages are edited, created, deleted — but the corpus
is enormous (tens of billions of documents, ~150 TB of postings), so rebuilding
the entire index from scratch every time content changes anywhere is completely
infeasible; a full reindex at this scale is a large, expensive, slow batch
operation that cannot realistically run on anything like a per-change basis. The
design therefore splits updates into two very different cadences based on what
kind of signal is changing:

- **Incremental, fast updates**: when a specific page is newly crawled or has
  changed, only that document's entry within its owning shard needs to be updated
  — insert/update its postings in that one document-partitioned shard's local
  index (the `POST /internal/index/update` endpoint in Step 4), without touching
  any other shard or any other document. This keeps text-relevance freshness (a
  changed page's *content* becoming searchable) fast — achievable within minutes
  to hours — because it's a small, localized, independent write, consistent with
  document-partitioning's ingestion advantage described above.
- **Periodic, batch recomputation**: authority/link-graph scores, by contrast, are
  inherently a whole-corpus property — a single new inbound link to a page is, in
  principle, a tiny input into a computation that considers the entire link
  structure of the crawled web to converge on stable authority scores. Recomputing
  this exactly on every single link change is not just expensive, it doesn't even
  make sense as an incremental operation the way a document's own text content
  does. So authority scores are instead recomputed periodically (e.g. as a large
  batch job run on some regular cadence, from daily to weekly depending on the
  engine's freshness/cost trade-off), over a big offline processing framework
  operating on the full link graph, and the results are pushed out to update each
  document's stored `authorityScore` field, picked up by the next ranking pass
  without requiring any reindexing of postings themselves.

This split — fast/local/incremental for content-specific signals,
slow/global/batch for corpus-wide structural signals — is what lets the system
stay reasonably fresh on the signals that can be updated cheaply and
independently, while still being able to afford the expensive signals that
fundamentally require whole-corpus context.

### Query understanding: tokenization, stemming, and query expansion

Before a raw query string can even reach the index, it has to be turned into the
same kind of normalized term representation that documents were indexed with —
mismatches here silently break retrieval regardless of how good the ranking model
downstream is. This involves several concrete steps, applied consistently to both
documents at index time and queries at query time: **tokenization** (splitting
text into discrete terms, handling punctuation, casing, and language-specific
rules — "SF" and "sf" must normalize to the same indexed term, and word boundaries
differ across languages); **stemming/lemmatization** (reducing words to a common
root, so a document containing "ran" or "running" is still retrieved for a query
containing "run," by indexing and querying against the same normalized stem); and
**stopword handling** (very common, low-signal words like "the" or "in" are often
excluded from the index entirely, both to save the storage cost noted in Step 7
and because their posting lists are enormous and contribute little to
discriminating between documents, per the BM25 intuition above).

Beyond straightforward normalization, **query expansion** widens the retrieval net
without the user having to phrase things perfectly: transparently including
synonyms or closely related terms (expanding "sf" to also consider "san
francisco," or "cheap" to also consider "affordable" / "budget") when searching,
so relevant documents that happen to use different but equivalent wording aren't
missed by an overly literal term match. This expansion needs to happen carefully
and conservatively — over-aggressive expansion pulls in irrelevant results and
undermines precision — and is typically informed by a combination of curated
synonym dictionaries and statistical co-occurrence signals mined from large query
logs and corpus text, rather than expanding purely off a static dictionary. The
interview-relevant point is that this entire layer sits *before* retrieval even
happens, and any inconsistency between how documents were tokenized/stemmed at
index time and how the incoming query is processed at query time will silently and
invisibly degrade recall — a document that logically matches simply never gets
found, with no error to surface the problem, which is why real systems test
tokenization/query-processing consistency as rigorously as the ranking logic
itself.

## Step 7: Bottlenecks & Trade-offs

- **Query fan-out means the slowest shard determines the query's latency** (tail
  latency amplification): with ~1,000 shards queried per request, even a small
  per-shard chance of a slow response (GC pause, disk hiccup, transient overload)
  means a much larger chance that *at least one* of the 1,000 shards involved in
  any given query is slow. Mitigated with aggressive per-shard timeouts and "good
  enough" partial results (return the best answer obtainable from shards that
  responded in time, rather than blocking the whole query on stragglers) — an
  availability/completeness trade-off, not a free fix.
- **Document-partitioning means every query touches every shard**, so total system
  query cost scales with (queries/sec x shard count), not just queries/sec —
  adding more shards to accommodate corpus growth directly increases the per-query
  fan-out cost, requiring the retrieval stage per shard to stay cheap (bounded
  top-K, simple scoring) as the corpus and shard count both grow.
- **Hot/viral queries create thundering-herd load on the same set of
  documents/shards** repeatedly — the serving cache absorbs much of this for
  popular, repeated queries, but the cache is far less effective for the long tail
  of unique or rare queries, which still pay the full retrieve-then-rank cost
  every time.
- **Authority-score staleness is an accepted trade-off**: because it's computed in
  a periodic batch job, a page's authority score can lag its true, current
  standing by as much as the batch cadence (e.g. up to a week) — acceptable
  because authority changes slowly and gradually for the vast majority of pages,
  but a poor fit for anything requiring instant authority signal (mitigated
  separately, if needed, by giving very recent/breaking content its own
  freshness-weighted ranking boost rather than relying on authority alone).
- **Index storage cost at 150+ TB compressed drives real infrastructure
  decisions**: posting-list compression techniques and dropping low-value terms
  (extremely common stopwords, contributing little discriminative signal relative
  to their storage cost) are standard levers, trading a small amount of retrieval
  completeness for materially lower storage and faster shard-local scans.

## Follow-up Questions an Interviewer Might Ask

**How would you support phrase queries (e.g. "best ramen in sf" as an exact
phrase, not just all four terms present anywhere)?** Extend posting lists to store
term *positions* within each document (already reflected in the `positions[]`
field in the data model), so the retrieval stage can check not just that all
phrase terms are present in a candidate document but that they appear in the
correct consecutive positions — more expensive per candidate than a plain
multi-term AND match, which is part of why it's still applied at the cheap
retrieval stage on posting-list data rather than deferred to the expensive ranking
stage.

**How would you personalize results per user?** Add personalization as one more
signal blended into the expensive ranking stage only (never the cheap retrieval
stage, which should stay generic and cacheable across users) — e.g. boosting
candidates based on a user's location, search history, or prior click behavior on
similar queries, applied to the same small merged candidate set the base ranking
model already operates on.

**How do you handle spam and low-quality content gaming the ranking (e.g. link
farms artificially inflating authority scores)?** This is a large topic on its
own; at a system-design level, the answer is that the link-graph authority
computation and the content-processing/dedup pipeline both need spam-detection
heuristics (detecting unnatural linking patterns, near-duplicate spam clusters,
thin/auto-generated content) that discount or exclude manipulated signals before
they ever reach the ranking model, rather than trying to catch spam purely at
query time.

**How would you reduce tail latency caused by querying all 1,000 shards for every
request?** Beyond per-shard timeouts and partial-result tolerance (mentioned in
Step 7), consider a cheap pre-filtering/routing layer that can skip shards
unlikely to contain any relevant documents for very selective queries (e.g. via
lightweight per-shard Bloom filters or term-presence summaries), trading a small
chance of missing a rare match on a skipped shard for meaningfully lower average
fan-out.

**How does this design change for a niche vertical search engine (e.g. searching
only within one company's product catalog) versus general web search?** At smaller
corpus scale, term-partitioning's downsides (uneven shard load, complex multi-term
coordination) become far less painful since posting lists and shard counts are
both dramatically smaller, so it becomes a more viable alternative — the
document-partitioning recommendation in Step 6 is explicitly a consequence of
web-scale corpus size and ingestion rate, not a universal rule.

**How would you support autosuggest/typeahead efficiently?** Briefly: a separate,
much smaller index structure (e.g. a trie or a precomputed top-N-completions table
keyed by prefix) built from query logs and popular terms, served from a small,
fast, heavily-cached store distinct from the main document index — a different
problem shape (prefix matching over a bounded vocabulary of query strings) from
full-text document retrieval, which is why it's called out as a secondary feature
rather than folded into the core index design.
