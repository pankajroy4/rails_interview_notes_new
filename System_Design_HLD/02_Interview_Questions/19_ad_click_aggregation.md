# Design an Ad Click Aggregation System

## Problem Statement

"Design a system that ingests ad impression and click events from web and mobile
clients at massive scale, and aggregates them into per-ad, per-campaign counters —
both for near-real-time dashboards that advertisers watch, and for exact,
authoritative numbers that feed billing. Advertisers pay based on these numbers,
so undercounting loses revenue and overcounting is effectively charging someone
for clicks that didn't happen."

This question is really about two things at once: handling a huge, bursty firehose
of small events, and reconciling the tension between "fast and approximate" and
"slow but exact" when money is on the line.

## Step 1: Clarify Requirements

**Functional Requirements**

- Ingest ad click and impression events from many client sources (web pixels,
  mobile SDKs, server-to-server callbacks from ad exchanges).
- Aggregate counts per ad, per campaign, per advertiser, over configurable time
  windows (per-minute, per-hour, per-day).
- Provide near-real-time dashboards to advertisers (e.g. "clicks in the last
  hour," updated within a couple of minutes).
- Produce exact, authoritative daily (or finer) totals that drive advertiser
  billing.
- Support distinct-user counts (unique reach) per ad/campaign, in addition to raw
  click/impression counts.
- Detect and filter obviously fraudulent or duplicate clicks (bot traffic,
  double-fires) — at least at a basic level.

**Non-Functional Requirements**

- Extremely high write throughput with bursty peaks (e.g. a popular livestream or
  major sporting event spikes impression volume by 10x for a short window).
- At-least-once delivery is acceptable/expected from ingestion, but aggregation
  must be idempotent — no double-counting on redelivery.
- Billing numbers must be exact — zero tolerance for systematic over- or
  under-counting, even though dashboards can tolerate small approximation error.
- Near-real-time dashboard latency: results visible within roughly 1-2 minutes of
  the event occurring.
- Durability: raw events must never be silently dropped before being durably
  recorded, since they're the only source for later exact reconciliation.
- High availability for ingestion specifically — a brief aggregation outage is
  tolerable, but losing raw events because ingestion was down is not.

## Step 2: Back-of-Envelope Estimation

**Assumptions**

- A large ad network serving 5 billion ad impressions per day, with a typical
  click-through rate of 0.5%, giving 25 million clicks/day.
- Traffic is not uniform: assume peak hour carries 3x the average hourly rate
  (evening/prime-time concentration), and within peak hour, short bursts (e.g. a
  viral moment) can spike another 2-3x briefly.

**Impression event throughput**

- Average: 5,000,000,000 / 86,400 sec ≈ 58,000 impressions/sec average.
- Peak hour average: 58,000 x 3 ≈ 174,000 impressions/sec.
- Short-burst peak: 174,000 x 2.5 ≈ 435,000 impressions/sec — this is the number
  the ingestion layer must be provisioned to absorb without falling over, even
  though it's not the sustained rate.

**Click event throughput**

- 25,000,000 / 86,400 ≈ 290 clicks/sec average, peaking around 290 x 3 x 2.5 ≈
  2,175 clicks/sec. Clicks are two orders of magnitude lower volume than
  impressions, which matters: it means click-specific processing (e.g. more
  careful fraud checks) can afford to be more expensive per-event than impression
  processing.

**Event size and bandwidth**

- Each event (ad_id, campaign_id, user_id/device_id, timestamp, event_type,
  metadata like geo/device) serializes to roughly 200-300 bytes; call it 250
  bytes.
- Peak impression bandwidth: 435,000 events/sec x 250 bytes ≈ 109 MB/sec ≈ 872
  Mbps sustained during burst — meaningful but well within what a properly
  partitioned Kafka cluster and modern networking handles.

**Storage**

- Daily raw event volume: 5.025 billion events/day x 250 bytes ≈ 1.26 TB/day of
  raw event data.
- Over a 1-year retention window for raw events (needed for exact
  reprocessing/audits): 1.26 TB x 365 ≈ 460 TB. This is the justification for
  tiering: keep raw events in cheap, compressed, append-only storage (e.g. object
  storage / a data lake), not in the hot aggregation database.
- Aggregated counters are far smaller: assume 10 million distinct (ad, hour)
  buckets per day x ~100 bytes per counter row ≈ 1 GB/day of aggregate data —
  trivial to keep in a fast-access store for years.

**Aggregation processing throughput**

- The stream processing layer must sustain ~435,000 events/sec at peak. Assuming a
  single stream-processing task can handle roughly 20,000-50,000 simple
  counter-increment events/sec, this implies on the order of 10-20 parallel
  partitions/consumer tasks at peak, which is a very achievable scale-out factor
  for a Kafka-consumer-group-based stream processor.

**Kafka cluster sizing**

- To sustain 435,000 events/sec at ~250 bytes each (≈109 MB/sec) with headroom,
  and assuming a single Kafka broker comfortably handles on the order of 20-30
  MB/sec of sustained produce+replicate traffic before becoming a bottleneck, this
  implies roughly 5-8 brokers just for raw ingest throughput; in practice, teams
  provision meaningfully more (a few dozen brokers) to get partition-count
  headroom for parallelism, replication factor 3 for durability (which roughly
  triples the effective write bandwidth consumed), and room for the periodic burst
  multiplier. This is a useful sanity check that "durable log in front of
  aggregation" is not a free abstraction — it has its own real infrastructure
  footprint, just one that's far easier to scale horizontally than a stateful
  aggregation database would be under the same load.
- Partition count should be provisioned for future growth, not just current peak —
  under-partitioning a Kafka topic is expensive to fix later (repartitioning
  existing topics is disruptive), so a topic sized for 3-5x current peak
  partition-consumer parallelism is a reasonable starting point.

## Step 3: High-Level Design

Core components:

- **Ad servers / SDKs**: emit raw click/impression events, fire-and-forget (with
  local retry/buffering) toward the ingestion endpoint.
- **Ingestion API (thin, stateless)**: validates and minimally enriches events
  (e.g. attaches server-side timestamp, does basic bot-signature filtering), then
  writes them to a durable log.
- **Durable event log (Kafka)**: the shock absorber — buffers the bursty firehose
  so nothing downstream needs to be provisioned for instantaneous peak; also the
  replayable source of truth for exact reprocessing.
- **Stream aggregation layer**: consumes the log, maintains windowed counters
  (tumbling windows per ad/campaign), applies deduplication for idempotency, and
  writes rolling aggregates to a fast-access store for dashboards. Uses
  approximate structures (HyperLogLog, Count-Min Sketch) where exactness isn't
  required.
- **Fast aggregate store**: serves near-real-time dashboard queries (e.g. a
  key-value or time-series store, updated incrementally).
- **Raw event data lake**: the same events, durably archived in a cheap
  columnar/object store, partitioned by time.
- **Batch reconciliation job**: a nightly (or otherwise periodic) exact batch
  computation over the raw event log in the data lake, producing the authoritative
  counts used for billing.
- **Billing store**: the exact, immutable, audit-friendly ledger of billable
  events per advertiser per billing period.

```text
 Ad Servers / SDKs (web pixels, mobile, exchange callbacks)
        |
        v
 +-------------------+
 |  Ingestion API      |  (stateless, validate + light enrich)
 +---------+-----------+
           |
           v
 +----------------------------+
 |   Kafka (durable event log)  |   <-- shock absorber for bursty firehose
 |   partitioned by ad_id hash  |
 +------+----------------+------+
        |                |
        v                v
+---------------+   +--------------------------+
| Stream         |   |  Raw Event Data Lake      |
| Aggregation    |   |  (S3-like, partitioned     |
| (windowed,      |   |   by day/hour, cheap,      |
|  dedup, HLL/CMS) |   |   long retention)          |
+-------+--------+   +-------------+--------------+
        |                            |
        v                            v
 +-----------------+       +--------------------------+
 |  Fast Aggregate  |       |  Nightly Batch            |
 |  Store           |       |  Reconciliation Job        |
 |  (dashboards,    |       |  (exact counts, dedup       |
 |   near-real-time)|       |   against raw log)          |
 +-----------------+       +-------------+--------------+
                                          |
                                          v
                                +--------------------+
                                |  Billing Store       |
                                |  (authoritative,      |
                                |   immutable ledger)   |
                                +--------------------+
```

## Step 4: API Design

**Record an ad event (called from SDK/pixel, extremely high volume — must be
cheap)**
```
POST /events/track
{
  "eventId": "uuid-generated-client-side",   // used for idempotency/dedup downstream
  "adId": "ad_88213",
  "campaignId": "camp_4471",
  "eventType": "click" | "impression",
  "userId": "device_hash_or_user_id",
  "clientTimestamp": 1732000000123,
  "metadata": { "geo": "US-CA", "device": "mobile", "placement": "feed" }
}
-> 202 Accepted   // fire-and-forget; do not block the ad-serving critical path on this
```

**Query near-real-time aggregate (dashboard-facing)**
```
GET /stats/realtime?adId=ad_88213&window=1h
<- { adId: "ad_88213", windowStart: "...", clicks: 4820, impressions: 962000,
     estimatedUniqueUsers: 391000 }   // note: "estimated" — approximate structures
```

**Query exact billing totals**
```
GET /stats/billing?campaignId=camp_4471&date=2026-09-01
<- { campaignId: "camp_4471", date: "2026-09-01",
     exactClicks: 118422, exactImpressions: 23684000, status: "finalized" }
```

**Trigger/inspect reconciliation job status (internal/ops)**
```
GET /internal/reconciliation/status?date=2026-09-01
<- { date: "2026-09-01", status: "completed", discrepancyVsRealtime: "+0.3%" }
```

## Step 5: Data Model

**Raw event log (Kafka topic, then archived to data lake)**: not a traditional
database — an append-only, partitioned log. Partition key is typically `ad_id` or
`campaign_id` hash, so all events for a given ad land on the same partition, which
matters for maintaining per-ad ordering during windowed aggregation.

```
ad_events (Kafka topic, partitioned by hash(ad_id))
  eventId          string   -- client-generated, used for dedup
  adId             string
  campaignId       string
  eventType        enum(click, impression)
  userId           string
  clientTimestamp  int64
  serverTimestamp  int64    -- set at ingestion, used for watermarking
  metadata         json
```

**Fast aggregate store (dashboards)**: a key-value or wide-column store optimized
for fast incrementing counters and range reads by time window — e.g. Redis (for
the most recent, hottest windows) backed by/rolled into a wide-column store like
Cassandra for slightly older windows still needed on dashboards. This maps well
because access is almost always "increment this counter" or "read counters for
this key over a time range," not relational joins.

```
realtime_counters  (key: adId + windowStart, e.g. "ad_88213:2026-09-01T14:32")
  clicks            int
  impressions       int
  hll_sketch        bytes   -- HyperLogLog register set for unique-user estimate
  cms_sketch        bytes   -- Count-Min Sketch for frequency estimation (optional, per use case)
```

**Billing store (authoritative)**: a relational database, because billing demands
strong consistency, transactional guarantees, exact numeric correctness, and
auditability (row-level history, no silent overwrite) — properties relational
engines are built for, and the volume here (aggregated per campaign per day) is
orders of magnitude smaller than raw events, so the usual "relational doesn't
scale to this volume" objection doesn't apply.

```
billing_ledger
  campaign_id    string
  billing_date   date
  exact_clicks   bigint
  exact_impressions bigint
  computed_at    timestamp
  status         enum(pending, finalized, disputed)
  PRIMARY KEY (campaign_id, billing_date)
```

## Step 6: Deep Dive

### Why a durable message log sits in front of aggregation

If ad servers wrote click/impression events directly into an aggregation database
(incrementing counters synchronously), the aggregation database's write throughput
would need to be provisioned for the absolute peak burst rate (435,000 events/sec
in our estimate) at all times, and any transient slowdown in that database (a
compaction, a failover, a hot partition) would immediately back-pressure all the
way to the ad-serving path — the one path in the whole system that must never be
slowed down, since ad serving is the actual revenue-generating user-facing
product. Putting Kafka in between decouples these concerns completely: the
ingestion API's only job is to durably append the event to the log as fast as
possible (an operation Kafka is built to make extremely cheap and horizontally
scalable via partitioning), and it returns success the moment the write is
durable, regardless of how fast or slow downstream aggregation is running. If the
aggregation layer falls behind during a burst, events simply queue up in Kafka
(which is designed to buffer large backlogs cheaply on disk) and aggregation
catches up once the burst subsides — nothing is lost, and the burst never
propagates back to affect ad serving or ingestion latency. This is precisely the
shock-absorber role for bursty firehoses described generally in
`10_message_queues_and_streaming.md`, applied here to click/impression events
specifically.

### Stream aggregation with tumbling windows and the late-arriving-data problem

The stream aggregation layer groups events into fixed, non-overlapping tumbling
windows — e.g. "count all clicks for ad X with a timestamp between 14:32:00 and
14:33:00." A naive implementation would aggregate a window and consider it "final"
the instant wall-clock time passes the window's end (e.g. treat the 14:32-14:33
window as done at 14:33:00). The problem is that events don't always arrive at the
aggregator in the order they logically occurred: a mobile client might batch
several clicks locally and flush them over a slow network minutes later, or a
network hiccup might delay a batch of impression events; the *event's own
timestamp* might fall inside the 14:32 window even though it doesn't physically
arrive at the aggregator until 14:36. If the window was already finalized and
flushed at 14:33, this late event either gets dropped or incorrectly counted into
whatever window is currently open — either way, the 14:32 window's count becomes
wrong, and since these numbers eventually roll up into billing, "wrong" here has a
direct dollar cost.

The standard mitigation is a **watermark** (equivalently, a grace period): rather
than finalizing a window the instant its wall-clock end passes, the aggregator
waits an additional buffer — e.g. 5 minutes — past the window's nominal end before
treating it as closed and flushing its count downstream. Any event that arrives
within that grace period, even though it's "late," still gets correctly folded
into its proper window before finalization. This explicitly trades a small amount
of dashboard latency (results are available 5 minutes later than they otherwise
would be) for materially better correctness. Events that arrive even later than
the watermark allows are either dropped from the real-time path (acceptable, since
the real-time path is explicitly the approximate one) or handled specially, but
critically, they are NOT lost from the raw event log itself — they're still
durably recorded there and will be correctly included by the exact batch
reconciliation job, which doesn't have a watermark problem at all since it
operates over the complete historical log well after the fact.

**A worked timeline, to make this concrete.** Consider the 14:32:00-14:33:00
tumbling window for ad X, with a 5-minute watermark:

- 14:32:07 — a click event with `clientTimestamp` 14:32:07 arrives at the
  aggregator at 14:32:07 (normal case, no delay). Counted immediately into the
  open window.
- 14:32:51 — a mobile client goes into a network dead zone right after generating
  a click with `clientTimestamp` 14:32:51; the SDK buffers it locally.
- 14:33:00 — wall clock passes the window's nominal end. Under the naive
  (no-watermark) design, the window would close here. Under this design, it stays
  open, accumulating any further arrivals, because the watermark hasn't elapsed
  yet.
- 14:34:40 — the mobile client regains connectivity and flushes its buffered
  click. It arrives at the aggregator now, 1 minute 49 seconds after the window's
  nominal end, but well within the 5-minute watermark — the aggregator recognizes
  its `clientTimestamp` falls inside the 14:32-14:33 window and correctly folds it
  in.
- 14:38:00 — the watermark for the 14:32-14:33 window elapses (5 minutes past
  14:33:00). The window is now finalized and flushed to the fast aggregate store,
  correctly including the delayed click from 14:34:40. Any event with a
  `clientTimestamp` in this window arriving after 14:38:00 is either dropped from
  the real-time counter (acceptable — the fast path is explicitly approximate) or
  logged as a "very late" metric for monitoring purposes; it is untouched in the
  raw event log and will still be counted exactly by the next batch reconciliation
  run.

This walkthrough is also why `serverTimestamp` (set at ingestion) and
`clientTimestamp` (set when the event actually happened) are both stored on every
event: windowing and correctness logic operate on `clientTimestamp` (when the
click genuinely occurred), while `serverTimestamp` is what lets the system measure
and monitor how much lateness is actually occurring in practice, which in turn is
what an operator uses to tune the watermark duration itself.

### Idempotency and deduplication under at-least-once delivery

Kafka (like most durable messaging systems) guarantees at-least-once delivery by
default: under certain failure/retry scenarios (a consumer crashes after
processing but before committing its offset, a producer retries a write it wasn't
sure succeeded), the same event can be delivered and processed more than once. If
aggregation counters are simply incremented on every event received, a redelivered
click event gets counted twice — directly inflating the click count that ad
billing is based on. Since this system's numbers translate straight into money
charged to advertisers, double-counting isn't a cosmetic bug, it's effectively
overbilling a customer, which carries real business and trust consequences.

The fix is making aggregation idempotent via deduplication on a unique event ID:
every event carries a client-generated `eventId` (a UUID generated once, at the
moment the event is created, before any retries), and the aggregation layer tracks
which event IDs have already been counted within a relevant time window (e.g. a
set or bloom-filter-backed dedup cache keyed by eventId, with a TTL matched to how
long redelivery could plausibly occur — typically minutes, bounded by consumer
retry/rebalance behavior). When a redelivered event arrives with an eventId
already seen, it's recognized and skipped rather than double-counted. The exact
batch reconciliation job performs the same deduplication, but more rigorously and
exhaustively, since it processes the complete raw log at leisure rather than under
real-time pressure — this is part of why it's trusted as the authoritative source
for billing even when the real-time path's dedup cache might theoretically miss an
edge case (e.g. a redelivery arriving after the dedup cache's TTL expired).

### Approximate counting structures: HyperLogLog and Count-Min Sketch

Not every number this system produces needs to be exact, and recognizing which
ones don't is what makes the real-time path affordable at this scale.

**HyperLogLog (HLL)** solves cardinality estimation — "how many *distinct* users
saw this ad" (unique reach), as opposed to raw impression count. Computing this
exactly would require tracking a set of every unique user ID seen per ad, which at
billions of events/day could require gigabytes of memory per popular ad if done
naively (a hash set scales linearly with the number of distinct elements). HLL
instead maintains a small, fixed-size array of registers (typically a few KB,
regardless of whether the true cardinality is a thousand or a billion) that
probabilistically estimates the count of distinct elements via bit-pattern
statistics on hashed inputs, with a well-understood, bounded standard error
(typically under 2% with common configurations). The memory savings — fixed
KB-scale structures instead of memory that grows with true cardinality — are what
make it feasible to maintain a live unique-reach estimate per ad, per time window,
for millions of ads simultaneously.

**Count-Min Sketch (CMS)** solves frequency estimation — e.g. "roughly how many
times has this specific user clicked this specific ad" (useful as a fraud/abuse
signal: a user clicking the same ad hundreds of times in a minute is suspicious) —
using a small fixed-size grid of counters updated via multiple hash functions per
event, again trading a small, bounded amount of over-counting error for large
space savings versus tracking exact per-(user, ad) frequency pairs, of which there
could be an enormous combinatorial number.

**The explicit line**: both structures are appropriate for the *real-time
dashboard and internal fraud-signal* path, where a couple of percent of estimation
error is an acceptable trade for constant, tiny memory footprint and speed.
Neither is acceptable for the actual numbers used in advertiser billing — an
advertiser being charged based on a probabilistically-estimated count, even with
small expected error, is not defensible, both practically (advertisers audit their
bills) and often contractually. Billing must be computed from exact counts, which
is precisely what the batch reconciliation path (operating on the complete raw
log, doing exact deduplicated counting with no space constraints since it's not
running as a real-time streaming job) is for.

### The two-speed Lambda architecture

Putting the above pieces together yields a deliberate two-path design commonly
called a Lambda architecture: a **fast/approximate path** — stream aggregation
with tumbling windows, watermarks, and approximate structures — that powers
dashboards advertisers check throughout the day, valuing low latency over perfect
precision; and a **slow/exact path** — a batch job (e.g. nightly) that reprocesses
the complete, immutable raw event log from the data lake, performs rigorous exact
deduplication and counting with no time pressure, and produces the numbers that
actually appear on invoices. The reason this split exists, rather than trying to
make the real-time path itself perfectly exact, is that exactness and real-time
speed are genuinely in tension here: exact counting requires waiting long enough
to be sure no late/duplicate events are still outstanding (which conflicts with
low latency) and/or unbounded memory for exact distinct-count tracking (which
conflicts with the constant-time, constant-memory processing that real-time
streaming at this event rate requires). Rather than compromise both goals
simultaneously, the design cleanly separates them: the fast path optimizes purely
for latency and accepts small, bounded error; the slow path optimizes purely for
correctness and accepts latency measured in hours. Reconciliation between the two
(the `discrepancyVsRealtime` figure in the status API above) is itself a useful
operational signal — a persistently large gap between the real-time estimate and
the exact batch number indicates something is wrong upstream (e.g. a dedup TTL
misconfigured, a watermark set too short) even though the batch number, not the
real-time one, is what's actually billed.

### Window granularity as its own trade-off

Choosing the tumbling window size (a minute vs an hour vs a day) is a separate
dial from the watermark, and worth calling out explicitly because it trades off in
a different direction. A fine-grained window (per-minute) gives advertisers a more
responsive-feeling dashboard (they can see a spike within a couple of minutes of
it happening) but multiplies the number of distinct counter keys the fast
aggregate store must maintain — per Step 2's estimate, moving from hourly to
per-minute buckets increases the number of live (ad, window) counter rows by
roughly 60x, directly increasing write load and storage churn on the fast
aggregate store. A coarser window (hourly) is cheaper to maintain and still gives
a reasonably useful picture of campaign performance, but delays how quickly a
sudden change in click volume becomes visible. Many real systems resolve this by
maintaining multiple granularities simultaneously — fine-grained windows for a
short recent retention period (e.g. per-minute counters for the last few hours,
useful for live monitoring and budget pacing), rolling up into coarser windows for
longer retention (hourly for the last month, daily beyond that) — trading a bit of
extra rollup/compaction complexity for the best of both responsiveness and
long-term storage efficiency.

## Step 7: Bottlenecks & Trade-offs

- **A single hot ad or campaign can create a skewed Kafka partition**: if
  partitioning is by `ad_id` hash, one viral ad can concentrate a disproportionate
  share of events onto one partition, creating a hot spot that limits that ad's
  aggregation throughput even though the cluster overall has capacity. Mitigation:
  sub-partition very hot keys (e.g. append a random shard suffix for the
  highest-volume ads and merge their sub-aggregates downstream), at the cost of
  added aggregation complexity.
- **Watermark/grace-period length is a direct latency-vs-completeness dial**: a
  longer grace period catches more late events correctly but delays when
  dashboards show "final-ish" numbers for a window; a shorter one shows numbers
  sooner but at higher risk of undercounting late arrivals in the fast path (which
  is fine, since the fast path is explicitly approximate — but too aggressive a
  setting makes the dashboard noticeably and confusingly inaccurate relative to
  the eventual billed number).
- **Dedup cache size/TTL is a memory-vs-correctness trade-off in the fast path**:
  too short a TTL risks double-counting genuinely delayed redeliveries; too long a
  TTL costs more memory across a very high-cardinality stream of event IDs. The
  batch path's exhaustive dedup over the full log is what ultimately guards
  against any fast-path dedup misses reaching billing.
- **Batch reconciliation job runtime grows with raw event volume**, and at some
  point a purely nightly cadence may not be frequent enough for advertisers
  wanting same-day finalized billing visibility — the trade-off is between batch
  job frequency/cost (more frequent runs cost more compute and I/O against the
  data lake) and how quickly "final" numbers become available.
- **Data lake storage cost for a full year of raw events (hundreds of terabytes,
  per Step 2) is nontrivial** — mitigated by compression and by the fact that this
  is cold, rarely-accessed-in-bulk storage (only touched by the batch job and
  occasional audits/disputes), a good fit for cheap object storage tiers rather
  than hot database storage.

## Follow-up Questions an Interviewer Might Ask

**How would you detect click fraud (bots, click farms)?** Extend the
ingestion/stream-aggregation path with fraud-signal features — velocity checks
(Count-Min-Sketch-estimated click frequency per user/IP over short windows),
device/browser fingerprint anomalies, known bot IP-range filtering — and flag
suspicious events for exclusion from billing counts either automatically (for
high-confidence fraud signals) or via a review queue, while still retaining the
raw events in the data lake unfiltered for audit purposes.

**How do you handle a late correction — e.g. discovering after billing has been
finalized that some clicks were fraudulent?** Treat the billing ledger as
append-only/immutable per period rather than mutable: issue a correcting
adjustment entry (a credit) referencing the original finalized period rather than
rewriting history, preserving a clean audit trail — the same principle
event-sourced systems use generally.

**How would you extend this to support real-time budget pacing (pausing an ad
campaign automatically once its daily budget is spent)?** This needs a much lower
end-to-end latency guarantee than dashboards (seconds, not a couple of minutes)
since overspend accrues continuously; typically handled by a separate,
tighter-loop spend-tracking path using the same event stream but prioritizing
speed with a wider error tolerance (better to pause slightly early/conservatively
than overspend), distinct from the billing-accuracy path.

**How would you scale the stream aggregation layer as ad volume grows 10x?**
Increase Kafka topic partition count and aggregation consumer-group parallelism
proportionally (the design is already horizontally partitioned by ad_id, so this
mostly means adding more partitions and consumer instances), while watching for
hot-key skew becoming more pronounced at higher scale, per the bottleneck above.

**Why not just make the real-time path exact by waiting long enough and using
exact data structures?** Push on the tension directly: exact unique-count tracking
requires memory proportional to true cardinality (unlike HLL's fixed footprint),
and waiting long enough to be fully sure no more late/duplicate events will arrive
conflicts directly with the "near-real-time" latency requirement — you'd
effectively be rebuilding the batch path, just poorly, with tighter latency
constraints it can't meet.

**How would you reconcile a discrepancy an advertiser disputes on their bill?**
Because the raw event log is retained and immutable, a dispute can be resolved by
re-running the exact batch computation over the specific disputed date/campaign's
raw events as an audit, and because every event carries a durable `eventId` and
full metadata, individual events can be inspected directly rather than only
trusting an aggregate number.
