# Design a Web Crawler

## Problem Statement

"Design a web crawler. Given a set of seed URLs, the system should systematically discover and download pages from the web — starting from the seeds, extracting hyperlinks from each downloaded page, and following those links to discover more pages — at the scale of billions of pages, without hammering any single website, without getting stuck in infinite loops, and while keeping already-crawled content reasonably fresh over time." This is the system that sits at the front of a search engine's indexing pipeline (think an early Googlebot), or that powers any large-scale web data collection product.

## Step 1: Clarify Requirements

### Functional Requirements

- Given a set of seed URLs, crawl outward by following hyperlinks discovered on each page.
- Download and persist the raw content (HTML at minimum) of every crawled page for a downstream indexing/processing pipeline.
- Extract and normalize links from each page's HTML to discover new candidate URLs.
- Avoid recrawling the same URL more often than a freshness policy dictates — this is not a one-shot crawl, it runs continuously.
- Prioritize crawling: some pages (high-authority news sites, frequently-updated pages) should be crawled sooner and more often than an obscure, static personal blog.
- Respect `robots.txt` and any per-site `Crawl-delay` directive.
- Be extensible to new content types later (images, PDFs, video metadata) — the core pipeline shouldn't assume HTML-only, even if HTML parsing is the only thing built now.

### Non-Functional Requirements

- **Scale**: sustain roughly 1 billion pages crawled per month (mid-size search engine scale, not planet-scale, but well beyond a toy script).
- **Throughput**: average and peak fetch rate that keeps up with that monthly target, with headroom for bursty re-indexing campaigns.
- **Politeness**: never issue more than one request to the same domain within some minimum interval (a few hundred ms to multiple seconds, depending on the site) — this is a hard constraint, not a nice-to-have.
- **Scalability**: horizontally scalable on every axis — more crawler workers, more frontier capacity, more storage — because both the URL space and the content volume grow without bound.
- **Fault tolerance**: a crawler worker crashing mid-fetch should not lose significant progress or cause large-scale duplicate work when it (or a replacement) restarts.
- **Extensibility**: freshness/priority policy should be tunable per domain or per content category without redeploying the system.
- **Consistency**: none needed in the strong sense — the crawl frontier and crawled-page index are inherently eventually consistent; "the page is a few hours stale" is an acceptable, expected state, not a bug.
- **Safety**: bounded resource usage per domain — the design must actively prevent unbounded URL spaces (crawler traps) from consuming the entire crawl budget.

## Step 2: Back-of-Envelope Estimation

**Assumptions** (stated explicitly, as a candidate should):
- Target: 1 billion pages crawled per month.
- Average fetched page size: 500 KB raw HTML (a reasonable middle ground between text-light API-driven pages and image-heavy inline markup — this is the download itself, not embedded assets, which most crawlers skip or fetch separately).
- Average out-degree: ~30 links discovered per page.
- Known URL space (seen, whether crawled or not) is roughly 10x the pages actually crawled in a month, because a crawl policy only revisits a fraction of the frontier each month while discovering new links continuously — call it 10 billion known URLs.

**Fetch QPS**

```
1,000,000,000 pages / month
  ÷ (30 days × 24 hours × 3600 sec) = 2,592,000 sec/month
  ≈ 386 pages/sec average
```

Assume a 3x peak multiplier for re-indexing pushes or catching up after downtime:

```
386 × 3 ≈ 1,160 pages/sec peak
```

**Bandwidth**

```
Average: 386 pages/sec × 500 KB = 193,000 KB/sec ≈ 188 MB/s ≈ 1.5 Gbps sustained
Peak:    1,160 pages/sec × 500 KB ≈ 566 MB/s ≈ 4.5 Gbps
```

This is a meaningful, but not exotic, amount of outbound+inbound bandwidth — well within what a handful of well-connected data-center links or a cloud provider's network tier can sustain.

**Storage (raw content)**

```
1e9 pages/month × 500 KB = 5e11 KB = 5e8 MB = 500,000 GB = 500 TB/month raw
```

Applying ~4:1 gzip compression on HTML (text compresses very well):

```
500 TB / 4 ≈ 125 TB/month compressed
→ ~1.5 PB/year compressed
```

This is object-storage territory (see `12_storage_systems.md`), not a filesystem or a relational database.

**URL frontier / dedup structure**

Known URL space: 10 billion URLs. Two ways to track "have we seen this URL before":

- **Naive hash set of full URLs**: average URL length ~60 bytes. `10e9 × 60 bytes = 600 GB` just to hold the set, before any indexing overhead — and that's assuming no hash-table load-factor waste, which in practice adds 30-50% more.
- **Bloom filter at a 1% false-positive rate**: needs roughly 9.6 bits per element (the standard Bloom filter sizing formula for ~1% FPR). `10e9 × 9.6 bits = 9.6e10 bits ≈ 12 GB`.

That's a **50x** memory reduction (600 GB → 12 GB) for accepting a small, bounded false-positive rate — the concrete number that makes the Bloom filter the obvious choice at this scale (detailed in Step 6).

**URL metadata storage** (frontier state — status, priority, last-crawled time, per known URL):

```
10e9 URLs × ~100 bytes/record (url, hash, domain, status, priority, last_crawled_at, next_crawl_at)
≈ 1,000,000,000,000 bytes = 1 TB
```

Comfortably fits a distributed wide-column store, sharded by URL hash.

**Concurrent connections and DNS load**

At peak (1,160 pages/sec) with an average fetch taking roughly 2 seconds end-to-end (DNS + connect + TLS handshake + download), Little's Law gives the number of connections that must be in flight simultaneously:

```
Concurrent in-flight fetches ≈ throughput × latency = 1,160 pages/sec × 2 sec ≈ 2,320 concurrent connections
```

Each of those connections typically starts with a DNS lookup unless the target domain's IP is already cached, so a caching DNS resolver layer sitting in front of the worker fleet is close to mandatory at this volume — hitting public DNS directly for every fetch would add tens to hundreds of milliseconds of avoidable latency per new-domain request and risks the crawler itself being rate-limited by upstream resolvers.

**Content dedup checksum storage**

Beyond URL-level dedup (Step 6's Bloom filter), the system also stores a `content_hash` per crawled page (Step 5) to detect byte-identical or near-identical recrawls. At one hash per crawled page per month:

```
1e9 pages/month × 20 bytes/hash (SHA-1 truncated) = 2e10 bytes = 20 GB/month of pure hash data
```

Negligible next to the 125 TB/month of raw content — cheap to keep resident in the same metadata store already tracking crawl status.

**Crawler worker count**

Assume each worker holds ~50 concurrent in-flight connections, and each fetch (including DNS, connect, TLS, download, and the politeness wait folded in as amortized queue time) averages 2 seconds of wall time per connection slot:

```
Throughput per worker ≈ 50 connections / 2 sec ≈ 25 pages/sec
```

```
Workers needed at average load: 386 / 25 ≈ 16
Workers needed at peak load:    1,160 / 25 ≈ 47, round up to ~60 for headroom
```

So the fleet size is "tens of machines," not thousands — the bottleneck in a real crawler is almost never raw worker count, it's politeness constraints and frontier management (Step 6).

## Step 3: High-Level Design

```text
                         +------------------+
                         |   Seed URL List   |
                         +---------+--------+
                                   |
                                   v
   +---------------+     +------------------+     +-------------------+
   |  URL Filter /  |<----|   URL Frontier   |---->|  Politeness Layer |
   |  Bloom Filter  |     | (per-domain      |     | (per-domain rate  |
   |  dedup         |     |  priority queues)|     |  limiter + robots |
   +-------+--------+     +--------+---------+     |  .txt cache)      |
           ^                       |                +---------+---------+
           |                       v                          |
           |              +------------------+                v
           |              |  Crawler Workers |<----------------+
           |              | (fetch, follow   |
           |              |  redirects, DNS) |
           |              +--------+---------+
           |                       |
           |                       v
           |              +------------------+       +------------------+
           |              |  HTML Parser &   |------>|   Content Store  |
           |              |  Link Extractor  |       |  (object storage,|
           |              +--------+---------+       |   compressed)    |
           |                       |                 +------------------+
           |                       v
           |              +------------------+
           +--------------|  New URLs found  |
                           +------------------+
                                   |
                                   v (loop back into Frontier)
                         +------------------+
                         |  URL Metadata DB |  (status, priority, next_crawl_at)
                         +------------------+
                                   |
                                   v
                         +------------------+
                         | Downstream Index |  (out of scope: search index build)
                         +------------------+
```

**Flow**: a worker pulls a batch of URLs from the frontier (already filtered for politeness — the frontier only hands out URLs whose domain isn't currently rate-limited), fetches the page, hands the raw bytes to the content store, and hands the HTML to the parser. The parser extracts links, normalizes them (resolve relative URLs, strip fragments, lowercase host), and pushes each one through the Bloom filter dedup check before it's allowed back into the frontier as a new candidate. The URL metadata DB is the durable source of truth for "what state is this URL in" (queued, in-progress, done, failed) — the frontier itself is more like a fast, partially-volatile work queue built from that state.

**Key components**:
- **URL Frontier**: the prioritized, per-domain-partitioned work queue — the actual bottleneck of the whole system (Step 6).
- **Politeness Layer**: enforces per-domain crawl-delay and caches parsed `robots.txt` per domain so it isn't re-fetched on every request.
- **URL Filter / Bloom Filter**: fast, memory-cheap "have I seen this URL" check before spending a fetch on it.
- **Crawler Workers**: stateless fetch-and-parse processes; horizontally scalable, disposable, no local state that can't be rebuilt from the frontier + metadata DB.
- **Content Store**: object storage (S3-like) holding raw/compressed page bytes, keyed by a hash of the URL.
- **URL Metadata DB**: durable record of every known URL's crawl status and scheduling info.

**Walking through one URL end to end**: (1) the frontier's per-domain scheduler checks whether `example.com` is currently past its `next_allowed_fetch_time`; if not, the URL stays queued and the scheduler moves to the next eligible domain. (2) Once eligible, a worker dequeues a batch that includes this URL, checks the cached `robots.txt` rules for `example.com` to confirm the path isn't disallowed, and issues the fetch. (3) On a successful response, the raw bytes are written to the content store and a `content_hash` is computed. (4) The HTML is parsed, links are extracted and normalized. (5) Each extracted link is checked against the Bloom filter; new-looking links are written to the URL metadata DB as `discovered` and pushed onto the appropriate domain's frontier queue (which may be a different partition than the page that discovered them, since the link can point to any domain). (6) The metadata DB record for the just-crawled URL is updated: `status = crawled`, `last_crawled_at = now`, `next_crawl_at` recomputed from the freshness policy (Step 6), and the domain's `next_allowed_fetch_time` in the politeness layer is advanced. This loop — dequeue, politeness check, fetch, parse, dedup-and-requeue, update metadata — is the entire system's steady-state behavior, running continuously across all domain partitions in parallel.

## Step 4: API Design

Most of a crawler's "API" is internal (frontier ↔ worker RPCs), but the system also needs an operator-facing surface:

**Add seed URLs**
```
POST /seeds
{ "urls": ["https://example.com", "https://news.example.org"] }
→ 202 Accepted { "accepted": 2 }
```

**Query crawl status of a URL**
```
GET /crawl/status?url=https://example.com/page
→ 200 OK
{
  "url": "https://example.com/page",
  "status": "crawled",
  "last_crawled_at": "2026-09-10T04:12:00Z",
  "next_crawl_at": "2026-09-17T04:12:00Z",
  "content_hash": "a1b2c3..."
}
```

**Adjust crawl policy for a domain** (operator/admin control)
```
POST /policy/domain
{ "domain": "news.example.org", "priority": "high", "recrawl_interval_hours": 6 }
→ 200 OK
```

**Fleet stats** (for monitoring/ops)
```
GET /stats
→ 200 OK
{ "pages_crawled_last_hour": 1390000, "frontier_size": 842000000, "active_workers": 58 }
```

**Internal frontier RPC** (worker ↔ frontier, not public)
```
Frontier.Dequeue(worker_id, batch_size=50) → [ {url, domain, priority}, ... ]
Frontier.ReportResult(url, status, discovered_links=[...], content_hash) → ack
```

## Step 5: Data Model

**URL Metadata table** — wide-column NoSQL (Cassandra/DynamoDB-style), partitioned by `url_hash` for even distribution:

| Field | Type | Notes |
|---|---|---|
| `url_hash` (PK) | string | SHA-1/MD5 of normalized URL |
| `url` | string | full normalized URL |
| `domain` | string | secondary index — used for per-domain queries |
| `status` | enum | `discovered`, `queued`, `in_progress`, `crawled`, `failed` |
| `priority` | int | derived from domain authority + change frequency |
| `last_crawled_at` | timestamp | |
| `next_crawl_at` | timestamp | drives recrawl scheduling |
| `content_hash` | string | detects unchanged content across recrawls |
| `discovered_at` | timestamp | |

NoSQL/wide-column is the right fit: access is almost always a point lookup or a scan by `next_crawl_at`/`domain`, write volume is enormous (billions of rows churned per month), and there are no cross-record relational joins to justify SQL's overhead.

**URL Frontier** — not a table at all, but a distributed priority-queue structure, commonly implemented as per-domain queues in a system like Redis (sorted sets scored by `next_allowed_fetch_time`) or a dedicated queueing layer. It's intentionally kept separate from the metadata DB because the frontier needs to be *fast* (millions of dequeue/enqueue ops) while the metadata DB needs to be *durable* — the frontier can be partially rebuilt from the metadata DB if lost.

**Content Store** — object storage (S3-class), key = `url_hash`, value = compressed raw HTML bytes + a small header (content-type, fetch timestamp, HTTP status). Object storage is the right fit because content is large, immutable once written (a recrawl writes a new object rather than updating in place), and accessed by simple key — no need for a database's query capabilities.

**robots.txt cache** — small key-value cache (Redis), key = domain, value = parsed rule set + `fetched_at`, TTL'd (e.g., 24 hours) so it's periodically refreshed without hitting every domain's `robots.txt` on every single page fetch.

**Bloom filter** — not a database at all; an in-memory (or sharded-in-memory-across-nodes) probabilistic structure, detailed next.

**Storage choice justification, summarized**:

| Component | Storage type | Why |
|---|---|---|
| URL metadata | Wide-column NoSQL | Massive write volume, point/scan access by hash or domain, no joins |
| Frontier queue | In-memory sorted structure (Redis-like) | Needs fast enqueue/dequeue at millions of ops/sec, rebuildable from metadata DB |
| Content store | Object storage | Large, immutable blobs, simple key-based access, cheapest at this volume |
| robots.txt cache | Key-value cache with TTL | Small, hot, read on every fetch, tolerates brief staleness |
| Bloom filter | In-memory probabilistic set | Needs to answer membership at fetch-time speed for 10B+ URLs within realistic memory |

## Step 6: Deep Dive

### URL Frontier: Prioritization and Freshness

The frontier is the system's real bottleneck and its most interesting design surface — it's not a plain FIFO queue, because two competing goals have to be balanced simultaneously: **breadth** (discover new pages) and **freshness** (revisit important pages before they go stale).

**Structure**: the frontier is organized as many small per-domain queues rather than one global queue. Each domain's queue is ordered by priority score, and a separate scheduler decides which domain queues are "eligible to dequeue from" right now, based on the politeness rule (Step 6, next section) — a domain whose last fetch was too recent simply isn't offered up, no matter how high-priority its next URL is.

**Prioritization signals**, combined into a single priority score per URL:
- **Domain authority / importance**: pages on high-traffic, high-inbound-link domains (major news sites, popular reference sites) get crawled more eagerly — approximated via inbound link count or a PageRank-style score computed offline from the link graph already being built by the crawl itself.
- **Historical change frequency**: a page that has changed content (different `content_hash`) on the last several recrawls gets a shorter `next_crawl_at` interval; a page that's been byte-identical for a year gets pushed out to a much longer interval. This is what makes freshness policy per-page instead of a single fixed interval for the whole web — a static "About Us" page and a live sports score page have wildly different ideal recrawl rates, and the system should learn that from observed history rather than have it configured by hand.
- **Depth from seed / discovery recency**: newly discovered URLs get a modest priority boost so the crawl doesn't stall entirely on recrawling old pages and never finish discovering new ones — this is the breadth-vs-freshness knob, typically tuned as a weighted mix rather than one strictly dominating the other.

**Why this matters concretely**: without differentiated freshness, the only two options are "recrawl everything on a fixed schedule" (wastes enormous fetch budget re-downloading pages that never change) or "never recrawl" (index goes stale). A frequency-aware frontier spends its ~386 pages/sec budget where it actually buys freshness.

**Implementation shape**: a common way to realize this is to store each URL's priority score as a numeric field in the metadata DB (Step 5), recomputed after every crawl using a simple formula such as `priority = domain_authority_weight × change_frequency_weight`, and to have the frontier's per-domain queue actually be a min-heap (or a sorted-set) ordered by `next_crawl_at` rather than insertion order — dequeuing always pulls whichever eligible URL is most overdue relative to its own target interval, not simply the oldest-enqueued one. When a URL's `content_hash` comes back unchanged across two or three consecutive recrawls, its `next_crawl_at` interval is multiplicatively backed off (similar in spirit to exponential backoff for retries); when it changes, the interval is tightened. This makes the freshness policy self-correcting without an operator manually tuning per-domain schedules.

### Politeness: Rate Limiting and robots.txt

**Per-domain rate limiting** is a hard constraint, not a performance optimization — hitting a single web server with hundreds of concurrent requests can knock it over or trigger the target's own DDoS protections, at which point the crawler gets IP-banned and loses access to that domain entirely. The politeness layer enforces a minimum delay between consecutive requests to the same domain (commonly a few seconds by default, or whatever the site's own `Crawl-delay` directive specifies), tracked as a `next_allowed_fetch_time` per domain, checked before the frontier hands out a URL for that domain.

**`robots.txt`** is a plain-text file (`https://domain.com/robots.txt`) that a site publishes to tell automated crawlers which paths they may and may not access, and at what rate. A typical file looks like:

```
User-agent: *
Disallow: /admin/
Disallow: /search
Crawl-delay: 5

User-agent: GoodBot
Disallow:
```

Compliance matters for two concrete reasons: **ethically**, the file is the site owner's explicit statement of what they consent to being crawled (some paths are disallowed because they're expensive to render, private, or simply not meant for indexing), and ignoring it is a real breach of that consent; **practically**, ignoring `robots.txt` (or its `Crawl-delay`) is how crawlers get their IP ranges permanently blocked, which is a far more expensive failure than respecting the file in the first place — one banned IP range can silently remove an entire major domain from future crawls. The crawler fetches and caches each domain's `robots.txt` once (Step 5's robots cache) rather than re-fetching it before every single page, and re-validates it periodically since site owners do change their rules.

### Deduplication at Scale: Bloom Filters

At 10 billion+ known URLs, the question "have we already discovered/queued this URL?" has to be answered on essentially every link the parser extracts — that's a check happening at a rate proportional to fetch throughput times average out-degree (386 pages/sec × 30 links ≈ 11,600 checks/sec at average load, several times that at peak). A plain hash set answers this exactly, but at real cost (Step 2: ~600 GB+ for the full URL set) — too large to comfortably keep in memory on a single node, and expensive to keep replicated/sharded consistently.

A **Bloom filter** is a probabilistic set-membership structure: a fixed-size bit array plus several independent hash functions. To add an element, you hash it k times and set those k bit positions to 1. To check membership, you hash the candidate the same k ways and check whether *all* those bits are set — if any is 0, the element is **definitely not** in the set (no false negatives, ever); if all are 1, the element is **probably** in the set, but it might be a **false positive** (a different combination of elements happened to set the same bits).

That asymmetry is exactly the right trade-off for URL dedup: a **false negative** would mean silently never crawling a URL the system thinks it's already seen — a real, permanent gap in coverage. A **false positive** just means occasionally skipping a URL that was actually new — a small, bounded, and statistically tunable amount of missed coverage (1% at the sizing chosen in Step 2), in exchange for a 50x memory reduction. Missing 1% of newly discovered URLs in a system that's continuously rediscovering most URLs through multiple inbound links anyway is a cost worth paying for keeping the entire "seen" set resident in fast memory instead of spread across a much larger, slower structure.

In practice, the Bloom filter is sharded across the same domain-hash partitioning as the frontier (next section), so each partition owns both the frontier queue and the dedup filter for its slice of the URL space, keeping the "is this new" check local and fast rather than a cross-cluster round trip.

**Two dedup layers, not one**: URL-level dedup (the Bloom filter, checked before a fetch is even scheduled) answers "have we discovered this URL before" — but it says nothing about content. A different URL can serve identical or near-identical content (mirrors, URL parameters that don't change the page, syndicated articles republished verbatim). That's why the `content_hash` computed after every fetch (Step 2, Step 5) exists as a second, independent dedup signal — checked *after* the fetch, since you can't know a page's content without downloading it. A URL passing the Bloom filter (looks new) but producing a `content_hash` that already exists in the metadata DB is flagged as a content duplicate, which is useful to the downstream indexer (don't index the same content twice) even though the crawl itself still had to spend one fetch on it.

**Bloom filter growth over time**: a fixed-size Bloom filter's false-positive rate rises as more elements are added beyond its designed capacity (more bits get set to 1, increasing collision odds). Since the known URL space grows continuously, the filter has to be sized for projected growth (e.g., built for 2-3x the current 10 billion URLs) or periodically rebuilt at a larger size — an operational detail worth mentioning as a follow-up to show awareness that "12 GB" from Step 2 isn't a one-time, static number.

### Distributed Coordination and Crawler Traps

**Partitioning the frontier across workers**: with dozens to hundreds of crawler workers, naively letting any worker fetch any URL breaks politeness — two different workers could both decide it's safe to fetch `example.com` right now, unaware of each other. The standard fix is to **partition the URL space by a hash of the domain**, so a specific domain's queue, its politeness state (`next_allowed_fetch_time`), and its `robots.txt` cache entry all live on one specific frontier partition/owner. Workers are assigned (or dynamically pull from) specific partitions, which means all URLs for a given domain flow through a single point of politeness enforcement — no cross-partition coordination needed to answer "is it safe to fetch this domain right now." This is the same domain-hash partitioning idea used for the Bloom filter shard above, letting both structures colocate for a given domain.

**Crawler traps**: some URL spaces are effectively infinite by construction — a calendar page with a "next month" link generates a new, technically-distinct URL forever; a site with session IDs embedded in every URL (`?sessionid=...`) generates infinite unique-looking URLs for the same content; auto-generated faceted search/filter combinations on an e-commerce site can combine into billions of URL permutations. Left unchecked, a single such domain can consume the entire crawl budget indefinitely and starve every other domain. Mitigations, applied at the politeness/frontier layer per domain:
- **Max crawl depth**: cap how many link-hops deep from a seed the crawler will follow within a domain before deprioritizing further descent.
- **Max URLs per domain per time window**: a hard budget cap — once a domain has consumed its allotted fetch budget for the period, its queue is deprioritized regardless of how many more URLs it has queued.
- **URL pattern heuristics**: detect and downrank URLs that differ from an already-crawled URL only in a known-junk query parameter (session IDs, sort/filter permutations that don't change substantive content) — often paired with content-hash comparison (Step 6, frontier section) so that even if such a URL is fetched once, an identical `content_hash` to a recently-crawled page short-circuits deeper traversal from it.

**Summary of frontier prioritization signals**:

| Signal | What it captures | Effect on priority score |
|---|---|---|
| Domain authority | Inbound link count / PageRank-style score | Higher authority → crawled sooner, more often |
| Historical change frequency | How often `content_hash` differs across recrawls | Frequently-changing → shorter `next_crawl_at` interval |
| Discovery recency | How recently the URL was first found | Newly discovered → modest boost, to keep breadth moving |
| Per-domain budget remaining | Fetches already spent on this domain this period | Budget exhausted → deprioritized regardless of other signals |

## Step 7: Bottlenecks & Trade-offs

- **The frontier, not raw fetch throughput, is the real bottleneck.** Step 2 showed only ~16-60 worker machines are needed for the target throughput — the actual scaling challenge is keeping a frontier of 10 billion+ URLs, correctly partitioned and politeness-aware, fast enough to keep every worker fed without violating per-domain limits. A poorly partitioned frontier (e.g., hashing by full URL instead of by domain) would scatter one domain's politeness state across many partitions and make rate-limit enforcement require cross-partition coordination — exactly what partitioning by domain hash avoids.
- **Hot domains dominate.** A domain with millions of pages (Wikipedia, a major e-commerce catalog) creates a single frontier partition with enormously more backlog than a typical domain, and politeness caps how fast that backlog can be drained regardless of how many idle workers exist elsewhere — this is an inherent trade-off of politeness, not a bug to engineer away.
- **Storage grows without bound.** 125 TB/month compressed (Step 2) means storage cost, not compute, becomes the dominant long-run cost; the trade-off is retention policy — older, unchanged crawls can be more aggressively compressed or moved to colder/cheaper storage tiers, at the cost of slower re-access if ever needed.
- **Bloom filter false positives are a permanent, accepted gap**, not a bug to fix — the entire point of choosing a Bloom filter over an exact set was trading a small, bounded miss rate for a 50x memory win; driving the false-positive rate toward zero would mean giving that memory savings back.
- **DNS resolution and connection setup latency** dominate the per-fetch time far more than the actual download for small-to-medium pages — a production crawler typically runs its own caching DNS resolver layer in front of workers rather than hitting public DNS per request, which isn't in the core diagram above but is a near-mandatory addition at this scale.
- **Freshness vs. coverage is a permanent dial, not a solved problem** — every unit of fetch budget spent recrawling an already-known page is a unit not spent discovering a new one, and the "right" balance shifts depending on whether the product goal is maximum coverage (a new search engine trying to index the web for the first time) or maximum freshness (a mature system that already has broad coverage and is optimizing for how current its index is).
- **Worker fleet size is cheap to scale, frontier correctness is not.** Adding more crawler workers (Step 2: going from 60 to 120 machines) is a trivial horizontal scale-out; it does nothing to fix a poorly partitioned frontier or an under-provisioned dedup structure, which is why interviewers probing "how would you scale this 10x" are really asking whether the candidate understands that the bottleneck moved, not whether they know to add more boxes.
- **A single slow or unresponsive domain shouldn't stall the whole fleet** — because workers are assigned or pull from specific domain partitions, a domain that's slow to respond (not down, just latent) only throttles the workers currently serving that partition; the politeness layer's per-domain budget naturally bounds how much fleet-wide capacity any one slow domain can consume, but this still needs per-fetch timeouts so a single hung connection doesn't tie up a worker slot indefinitely.

**Bottleneck-to-mitigation summary**:

| Bottleneck | Mitigation | Cost accepted |
|---|---|---|
| Frontier partitioning/politeness coordination | Partition by domain hash, colocate politeness state | Uneven partition sizes for domains with very different page counts |
| Hot/huge domains dominate a partition | Per-domain fetch budget cap per time window | Slower full coverage of very large single domains |
| Unbounded storage growth | Compression + tiered/cold storage for old, unchanged crawls | Slower re-access of archived content |
| Bloom filter false positives | Accept ~1% miss rate | Small permanent gap in URL coverage |
| DNS/connect latency per fetch | Caching DNS resolver layer, connection pooling | Extra infrastructure component to operate |
| Crawler traps (infinite URL spaces) | Max depth, max URLs/domain, pattern heuristics | Occasionally deprioritizing legitimate deep content |

## Follow-up Questions an Interviewer Might Ask

**How would you rank crawled pages by importance, not just decide what to crawl next?**
Compute an offline importance score (PageRank-style, or a simpler inbound-link-count heuristic) from the link graph the crawl itself is building, run periodically as a batch job over the accumulated graph, and feed the resulting score back into the frontier's priority calculation (Step 6) — this closes the loop between "what the crawl has learned about the web's structure" and "what it should prioritize crawling next."

**How would you detect and avoid recrawling near-duplicate content across different URLs (mirrors, syndicated articles)?**
Compare a content similarity signature (e.g., MinHash/SimHash of the page body, cheaper than exact hashing when near-identical-but-not-byte-identical content is common) against previously seen signatures; if a strong match is found, record the new URL as a duplicate pointing at the canonical crawled copy instead of storing and re-indexing the content again, saving both storage and downstream indexing work.

**How would you extend this to crawl JavaScript-heavy single-page applications where content is rendered client-side?**
Route a subset of URLs (detected via low extracted-content-to-HTML-size ratio, or domain allowlisting) through a headless-browser rendering tier that executes JavaScript before handing off HTML to the parser — this is far more expensive per page (real CPU/memory for rendering, not just a network fetch), so it's applied selectively rather than to the whole crawl.

**How do you handle a site that starts blocking your crawler's IP addresses or serving CAPTCHAs?**
Treat elevated 403/429 response rates from a domain as a signal to back off that domain's crawl rate automatically (beyond its stated `Crawl-delay`), rotate across a pool of IP ranges for legitimate large-scale crawling (not to evade blocking maliciously, but because a single IP naturally looks like abuse at this volume even when compliant), and maintain a clear, identifiable `User-Agent` string with contact info so site owners can reach out instead of just blocking outright.

**How would you scale this to 10x the current throughput?**
Add more frontier partitions and worker capacity proportionally (both scale near-linearly since partitioning is by domain hash), but recognize the ceiling isn't infrastructure — it's the number of distinct domains available to parallelize across under politeness constraints; at extreme throughput the bottleneck shifts to having enough breadth in the frontier (enough distinct, currently-eligible domains) to keep that many workers busy without violating per-domain rate limits.

**What legal/ethical constraints should shape this design beyond robots.txt?**
Respect `noindex`/`nofollow` meta tags and `X-Robots-Tag` headers on individual pages (finer-grained than domain-level `robots.txt`), avoid crawling content behind authentication or explicitly paywalled without permission, and keep crawl rate limits conservative enough that the crawler is never a meaningful fraction of a site's total traffic — these are the practical lines between a good-citizen crawler and one that generates abuse complaints and IP blocks.
