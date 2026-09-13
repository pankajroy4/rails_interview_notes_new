# Design a Video Streaming Platform

## Problem Statement

"Design a video streaming platform like YouTube or Netflix. Users can upload
videos, and other users can watch them. Playback should adapt to the
viewer's network conditions, video should start quickly, and popular content
should stream smoothly even under massive concurrent viewership. Assume
hundreds of millions of users worldwide."

## Step 1: Clarify Requirements

### Functional Requirements

- Users can upload a video file; the platform processes it into a
  streamable form.
- Users can watch a video, with playback quality that adapts to their
  current network speed rather than being fixed.
- Basic metadata is shown and browsable: title, description, uploader,
  duration, view count, likes.
- Users can search for videos (out of scope for the deep dive here beyond
  noting it reuses the pattern in `../01_Concepts/13_search_and_indexing.md`).
- Recommendations/"up next" exist at the product level but are explicitly
  scoped out of the core design (Step 6.4) — it's a separate ML system.

### Non-Functional Requirements

- **Fast start time**: video should begin playing within roughly 1-2 seconds
  of pressing play — this is one of the most heavily optimized metrics in
  real video platforms, because every additional second of start-up latency
  measurably increases abandonment.
- **Smooth playback under varying/poor network conditions**: the player
  should degrade quality gracefully (lower resolution) rather than buffer
  and stall, and recover quality when the network improves.
- **Massive read amplification**: a single popular video is watched millions
  of times; the system must be architected around "write once, read many
  millions of times," which is close to the ideal CDN use case.
- **Asynchronous, non-blocking uploads**: the upload response should not
  wait for full processing (transcoding) to complete — that can take
  minutes for a long video.
- **Global low-latency delivery**: viewers are distributed worldwide, and
  video is bandwidth-heavy, making physical distance to the content the
  dominant latency factor if not addressed.
- **High availability for playback** over strict consistency for
  metadata — a slightly stale view count is fine; a video that fails to play
  is not.
- **Storage cost efficiency at scale**: video is the largest storage cost
  driver in the whole system by a wide margin (Step 2), so storage tiering
  and popularity-aware caching matter more here than in most systems.

## Step 2: Back-of-Envelope Estimation

**Assumptions:**

- 200 million daily active users (DAU).
- Each DAU watches an average of 5 videos/day (view events).
- 500 hours of new video content uploaded per minute, platform-wide (this is
  the real order of magnitude YouTube has cited historically, and a useful
  anchor figure).
- Original uploaded video averages roughly 1 GB per hour of footage at a
  reasonable source bitrate (~2.2 Mbps average across resolutions/content
  types — a simplification, but good enough for order-of-magnitude
  estimation).
- Each uploaded video is transcoded into 5 renditions (e.g., 1080p, 720p,
  480p, 360p, 240p) whose *combined* storage footprint is roughly 1.5x the
  original source size (lower renditions are much smaller, and modern
  codecs used for the renditions are more efficient than a typical source
  upload, so the sum across all 5 doesn't multiply storage 5x).
- Peak traffic (viewing) runs ~3x the daily average.

**Upload volume and storage**

```
Video uploaded/day = 500 hours/min x 60 min/hour x 24 hours/day
                    = 500 x 1,440 = 720,000 hours of video/day

Raw source storage/day = 720,000 hours x 1 GB/hour = 720,000 GB = 720 TB/day

Transcoded (all renditions) storage/day = 720 TB x 1.5 ≈ 1,080 TB ≈ 1.08 PB/day

Total storage added per day (source + renditions) ≈ 720 TB + 1,080 TB ≈ 1.8 PB/day

Yearly storage growth (raw) ≈ 1.8 PB x 365 ≈ 657 PB/year
With replication/durability overhead (~1.5x, since object storage systems
like S3 already handle redundancy internally at a lower overhead than a 3x
naive replica count) ≈ ~985 PB/year — roughly 1 exabyte/year.
```

This number is intentionally enormous — it's the reason video platforms are
one of the largest storage consumers on the planet, and it's why storage
tiering (Step 6.3) and not simply "buy more disks" is a required part of any
credible design at this scale.

**View / playback QPS**

```
Views/day = 200,000,000 DAU x 5 views/day = 1,000,000,000 (1B) views/day

Average view-start QPS = 1,000,000,000 / 86,400 ≈ 11,574 views/sec
Peak view-start QPS ≈ 11,574 x 3 ≈ 34,700 views/sec
```

Each "view" then generates sustained streaming bandwidth for the duration of
the watch, not just a single request — this is the key difference from a
typical request/response system.

**Bandwidth**

```
Assume an average viewing bitrate of 3 Mbps (a mix of resolutions, weighted
toward what adaptive streaming actually settles most viewers into) and an
average concurrent-viewer count derived from view rate x average watch
duration (assume 8 minutes average watch time):

Concurrent viewers ≈ average view-start QPS x average watch duration (sec)
                   ≈ 11,574 x 480 ≈ 5,555,520 concurrent streams (average)

Total average bandwidth ≈ 5,555,520 streams x 3 Mbps ≈ 16.67 Tbps average

Peak bandwidth (3x) ≈ 50 Tbps
```

This bandwidth figure is the strongest possible argument for why virtually
all of this traffic must be served from CDN edge nodes rather than origin
servers (Step 6.3) — no reasonably sized origin fleet serves tens of
terabits per second directly to end users.

## Step 3: High-Level Design

Two largely independent pipelines: an **asynchronous upload/processing
pipeline** (slow, write-path, not latency-sensitive) and a **playback/
delivery path** (must be fast, read-path, extremely high fan-out). They only
meet at the point where processed video chunks land in object storage.

```text
   UPLOAD PATH
   ┌────────┐      ┌────────────────┐      ┌──────────────────────┐
   │ Client  │─────►│ Upload Service   │─────►│ Raw Video Object       │
   │(uploader)│     │ (accepts file,   │      │ Storage (source files) │
   └────────┘      │  returns quickly)│      └──────────┬─────────────┘
                    └───────┬──────────┘                 │
                            │ publish "video uploaded"     │ triggers
                            ▼                              ▼
                 ┌────────────────────┐          ┌──────────────────────┐
                 │ Message Queue        │─────────►│ Transcoding Workers    │
                 │ (async job trigger)  │          │ (produce N renditions, │
                 └────────────────────┘          │  chunk into segments)  │
                                                    └──────────┬─────────────┘
                                                                │
                                                                ▼
                                                    ┌──────────────────────┐
                                                    │ Processed Video Object │
                                                    │ Storage (chunked, per- │
                                                    │ rendition segments)    │
                                                    └──────────┬─────────────┘
                                                                │ replicated to
                                                                ▼
                                                    ┌──────────────────────┐
                                                    │         CDN             │
                                                    │  (edge caches, global)  │
                                                    └──────────────────────┘

   PLAYBACK PATH
   ┌────────┐   1. request manifest    ┌────────────────┐
   │ Viewer  │─────────────────────────►│ Metadata Service │
   │ Client  │◄─────────────────────────│ (video info, DB)  │
   └───┬────┘   2. manifest (.m3u8/     └────────────────┘
       │            .mpd) w/ CDN URLs
       │ 3. request segments, one quality level at a time,
       │    adapting based on measured throughput
       ▼
   ┌────────────────┐   cache MISS (rare, long-tail)   ┌───────────────────┐
   │      CDN Edge     │─────────────────────────────────►│ Processed Video     │
   │  (cache HIT, common)│                                │ Object Storage      │
   └────────────────┘                                    │ (origin)            │
                                                            └───────────────────┘
```

**Upload flow**: client uploads the raw file to the Upload Service, which
streams it directly into object storage and immediately returns success —
the response does not wait for transcoding. A message is published onto a
queue, and transcoding workers pick it up asynchronously, producing multiple
resolution/bitrate renditions chunked into short segments, written back to
processed-video object storage, which then gets pushed to (or pulled by, on
first request) the CDN.

**Playback flow**: the client first asks the Metadata Service for the video
and receives a **manifest file** (HLS `.m3u8` or DASH `.mpd`) listing
available quality levels and the CDN URLs for their segments. The player
then requests segments one at a time, choosing quality level per segment
based on currently measured network throughput — almost always served
straight from a nearby CDN edge cache, only occasionally falling through to
origin object storage.

## Step 4: API Design

**1. Initiate upload**

```
POST /v1/videos/upload
Request:  { "uploader_id": "u123", "title": "How CDNs work", "file_size_bytes": 524288000 }
Response: { "video_id": "v-9f31...", "upload_url": "https://upload.example.com/put/v-9f31...", "status": "PENDING_UPLOAD" }
```
`upload_url` is typically a pre-signed direct-to-object-storage URL so the
raw bytes don't have to be proxied through an application server at all —
same principle as direct-to-object-storage upload patterns in
`../01_Concepts/12_storage_systems.md`.

**2. Check processing status**

```
GET /v1/videos/{video_id}/status
Response: { "video_id": "v-9f31...", "status": "TRANSCODING", "progress_pct": 62 }
```
Statuses progress: `PENDING_UPLOAD -> UPLOADED -> TRANSCODING -> READY ->
(FAILED, on error)`. The client polls this (or subscribes via a webhook/push)
rather than the original upload call blocking.

**3. Get playback manifest**

```
GET /v1/videos/{video_id}/manifest
Response: {
  "video_id": "v-9f31...",
  "manifest_url": "https://cdn.example.com/v-9f31/master.m3u8",
  "duration_sec": 734,
  "available_renditions": ["1080p", "720p", "480p", "360p", "240p"]
}
```
The actual adaptive-bitrate logic (which segment, which quality) happens
client-side inside the player once it has this manifest — see Step 6.2.

**4. Get video metadata**

```
GET /v1/videos/{video_id}
Response: {
  "video_id": "v-9f31...", "title": "How CDNs work", "uploader_id": "u123",
  "duration_sec": 734, "view_count": 184213, "like_count": 6420,
  "created_at": "2026-09-01T12:00:00Z"
}
```

**5. Record a view**

```
POST /v1/videos/{video_id}/view
Request:  { "user_id": "u456", "watched_sec": 12 }
Response: { "status": "ACCEPTED" }
```
Deliberately fire-and-forget from the client's perspective — this does not
synchronously increment a counter in a database row; see Step 6.4.

**6. Search videos**

```
GET /v1/search?q=cdn+architecture&limit=20
Response: { "videos": [ { "video_id": "...", "title": "...", "relevance_score": 9.1 }, ... ] }
```

## Step 5: Data Model

**1. Video bytes (source and transcoded renditions) — object storage**

Both the raw uploaded file and every transcoded rendition's segments are
opaque blobs, accessed by key, never queried or filtered by content — the
textbook case for object storage (S3-style) rather than a filesystem or
database, as covered in `../01_Concepts/12_storage_systems.md`. Object
storage's durability model (data replicated across multiple devices/zones
automatically) is also why the yearly storage estimate in Step 2 used a
lighter overhead multiplier than a naive 3x application-level replica count.

```
Bucket layout (conceptual):
  raw/{video_id}/source.mp4
  processed/{video_id}/1080p/segment_000.ts ... segment_NNN.ts
  processed/{video_id}/720p/segment_000.ts ... segment_NNN.ts
  processed/{video_id}/master.m3u8   (manifest referencing all renditions)
```

**2. Video metadata — relational database**

```
Table: videos
video_id | uploader_id | title | description | duration_sec | status | created_at

Table: view_counts (or a separate fast counting store, see 6.4)
video_id | approximate_view_count | last_aggregated_at
```
Chosen because metadata is exactly the kind of structured, relatively
low-volume-per-row, query-by-multiple-fields data relational databases excel
at (look up by uploader, filter by status, join with channel/user data) —
and critically, it is a **completely separate database from the video bytes
themselves**, so metadata queries never compete with, or get blocked by, the
enormous read/write volume of the actual video content.

**3. Manifests — generated files, stored alongside segments in object storage (or served dynamically by a small manifest-generation service)**

The manifest itself is small text (a list of segment URLs and bitrates) and
is either pre-generated once at transcode time and cached at the CDN like
any other static asset, or generated on the fly by a lightweight service —
either way it is not part of the hot video-byte storage path.

**4. View/engagement events — append-only log, feeding an async aggregation pipeline**

```
Event: { video_id, user_id, watched_sec, event_time }
```
Written to a stream (`../01_Concepts/10_message_queues_and_streaming.md`)
rather than directly incrementing a row — the aggregation pipeline that
consumes this and produces `approximate_view_count` is covered in Step 6.4.

## Step 6: Deep Dive

### 6.1 Upload and the Asynchronous Transcoding Pipeline

The upload response must return quickly — a user should not sit staring at
a spinner for the minutes it can take to fully process a long video. The
design achieves this by strictly separating "accept the bytes" from "process
the bytes": the Upload Service's only job is to get the raw file safely into
object storage (Step 5) as fast as possible, often via a pre-signed URL that
lets the client upload directly to storage without the application server
proxying the bytes at all, and then it immediately returns success with a
`PENDING_UPLOAD`/`UPLOADED` status.

Actual transcoding — decoding the source and re-encoding it into multiple
target resolutions/bitrates/formats — is CPU-intensive and slow (a
multi-minute job for a long video, even on capable hardware, since
video encoding is one of the more computationally expensive common server
workloads) and is handled entirely out-of-band: the "video uploaded" event
is published onto a message queue (`../01_Concepts/10_message_queues_and_streaming.md`),
and a fleet of transcoding worker processes consumes from that queue,
each picking up one job, producing the configured set of renditions, and
writing results back to processed-video storage. This decoupling gives two
things a synchronous design couldn't: the upload path stays fast and
simple regardless of transcoding load, and the transcoding worker fleet can
be scaled independently (and elastically, since transcoding demand spikes
with upload volume, not viewing volume) without touching the upload path at
all. The client polls (or is pushed) status updates as the job progresses
through the queue and workers.

### 6.2 Adaptive Bitrate Streaming (HLS / DASH)

Serving every viewer the same fixed video quality is a poor fit for a
global audience with wildly different network conditions — a viewer on fast
fiber and a viewer on a congested mobile connection have fundamentally
different bandwidth budgets, and picking one fixed quality either wastes
bandwidth for the first viewer or causes constant buffering for the second.

Adaptive bitrate streaming solves this by restructuring the video itself,
not just the player: each rendition (1080p, 720p, etc., produced during
transcoding in 6.1) is split into short segments — typically a few seconds
each — and a **manifest file** (HLS uses `.m3u8`, DASH uses `.mpd`) lists,
for every quality level, the URLs of its sequence of segments. The player
downloads the manifest once, then requests segments **one at a time**,
continuously measuring its own recent download throughput and choosing
which quality level to request for the *next* segment based on current
conditions — not committing to one quality for the whole video. If the
network degrades mid-playback, the very next segment can be requested at a
lower bitrate, and playback continues without a stall; if conditions
improve, the next segment can step back up. Because segments across
different quality levels are aligned to the same time boundaries, switching
quality between segments produces no visible glitch or restart — the
player is just choosing a different source for the next few seconds of the
same timeline.

This is why the transcoding pipeline in 6.1 must produce not one output
file per rendition but a **chunked** one: adaptive streaming's entire
mechanism depends on being able to independently request and switch between
segments, not just between whole files.

### 6.3 CDN Distribution and the Long Tail

Video is close to the ideal CDN workload: once transcoded, a video's
segments are completely static (immutable — the same bytes are served to
every viewer, forever, until the video is deleted or re-processed) and
overwhelmingly read-heavy (Step 2's bandwidth math — millions of playbacks
of the same underlying bytes). This is exactly the profile
`../01_Concepts/05_caching.md`'s CDN section describes as the strongest CDN
use case: content that doesn't change per-request and is requested by huge
numbers of geographically distributed users.

In practice this means the overwhelming majority of playback bandwidth
(Step 2's ~17-50 Tbps) is served from CDN edge caches, not origin object
storage — an edge cache hit costs the origin nothing and serves the viewer
from a nearby location, minimizing both load and latency. But CDN edge
storage is finite and not every video benefits equally: **popular and
recent videos** are watched by enough concurrent viewers, from enough
different edge regions, that their segments stay hot in cache almost
everywhere — a classic power-law access pattern. A **long tail of
rarely-watched videos** (older uploads, niche content, a video with a
handful of total views) may see so few requests per edge region that their
segments get evicted between requests, or in extreme cases never get cached
at a given edge at all — those requests "hit origin" (processed video
object storage) more often, at higher latency per request but at far lower
absolute volume in aggregate, which is an acceptable trade-off precisely
because so little total bandwidth is spent serving that tail. This
popularity-driven caching behavior is also why release-day/trending
content is sometimes proactively pushed (push-CDN style) to edge locations
ahead of expected demand rather than waiting for organic pull-based caching
to catch up, the push-vs-pull CDN trade-off described generally in
`../01_Concepts/05_caching.md`.

### 6.4 Metadata Storage and View-Count Aggregation

Video metadata (title, description, uploader, duration — Step 5) lives in a
relational database entirely separate from the video bytes, both because it
is a structurally different access pattern (small structured records,
queried/filtered/joined) and because keeping it separate means metadata
reads and writes never contend with, or get bottlenecked by, the vastly
higher-volume video-byte traffic.

View count specifically deserves its own explanation because the obvious
implementation — `UPDATE videos SET view_count = view_count + 1 WHERE
video_id = ?` on every single playback — creates a severe write hotspot on
popular content. A viral video receiving thousands of concurrent views per
second would mean thousands of concurrent `UPDATE`s to the *same row*,
serializing through that row's lock and turning the metadata database into
the bottleneck for the platform's most successful content — exactly
backwards from what you want.

Instead, view counts are **batched or approximated** rather than
incremented synchronously per view. The `POST /view` call (Step 4) simply
emits an event onto a stream (Step 5's append-only event log) and returns
immediately, doing no synchronous database write at all. A separate
counting/aggregation pipeline — either a dedicated counting service that
holds approximate in-memory counters per video and periodically flushes
them to the metadata store, or a stream-processing job that windows and
sums view events (the same conceptual pattern used for trending-topic
counting in `10_twitter_x.md`) — updates `view_count` in batched,
infrequent writes (e.g., once every few seconds or minutes per video,
coalescing potentially thousands of individual view events into one write).
The number shown to users is therefore always a close approximation, lagging
true real-time count by a small, bounded window — an explicitly accepted
trade-off, since exact real-time view counts are not something users or the
product meaningfully depend on, but a write-hotspot-induced outage on
popular videos absolutely would be.

## Step 7: Bottlenecks & Trade-offs

- **Transcoding capacity is the throughput ceiling on the upload side.**
  Encoding is CPU-bound and comparatively expensive; a spike in upload
  volume (or a backlog of large/long videos) queues up behind finite worker
  capacity, delaying time-to-availability for new uploads — this is
  mitigated by prioritizing renditions (e.g., produce a lower-resolution
  rendition first so the video is watchable sooner, then backfill higher
  resolutions), trading initial quality for faster availability.
- **CDN cache misses on long-tail content push cost and latency onto
  origin storage**, and origin object storage, while durable and cheap per
  byte, is not designed to be a low-latency, high-QPS playback origin at
  the same tier of performance as an edge cache — a design serving a
  catalog with a very long tail (as most large platforms do) needs origin
  capacity sized for its miss rate, not just its total catalog size.
- **Storage growth is effectively unbounded and dominated by transcoded
  renditions** (Step 2's ~1 exabyte/year). This is mitigated by storage
  tiering: move rarely-accessed old renditions (or lower-priority
  resolutions of unpopular videos) to cheaper, higher-latency cold storage
  tiers, and consider re-transcoding on demand rather than storing every
  rendition forever for content nobody watches — a direct storage-cost
  vs. on-demand-compute trade-off.
- **View-count approximation means the product never shows a perfectly
  real-time number**, which is fine for view counts but means the same
  batching pattern cannot be blindly reused for anything requiring strong
  consistency (e.g., ad billing/impression counts, which need exact,
  auditable figures) — those require a different, consistency-prioritized
  pipeline.
- **Recommendations are explicitly out of scope here** (Step 6.5 note
  below) but in a real system are a major additional subsystem with its own
  data pipeline, and interviewers who push on personalization are
  effectively asking a different, ML-systems question layered on top of
  this one.

### 6.5 Recommendations: explicitly out of scope

Recommending "up next" or homepage videos is a substantial, separate ML
subsystem — training and serving personalization/ranking models over
watch history, engagement signals, and content features — and is
deliberately scoped out of this design, the same way feed ranking is scoped
out of `08_news_feed.md`. The core streaming design above is what makes a
recommendation *servable* once computed (fast metadata lookups, fast
manifest/CDN delivery for whatever video gets recommended); it says nothing
about how the recommendation itself is chosen.

## Follow-up Questions an Interviewer Might Ask

**How would you support live streaming instead of only pre-recorded video?**
Live streaming replaces the batch transcoding pipeline with a low-latency
real-time one: the incoming stream is transcoded into multiple bitrates in
near-real-time (segments produced continuously, seconds after being
captured, rather than all at once after a full upload), and the manifest is
continuously appended to rather than generated once — the CDN distribution
and adaptive-bitrate playback mechanics from Step 6.2 and 6.3 stay largely
the same, but the acceptable end-to-end latency budget (capture to viewer)
becomes a first-class design constraint in a way it isn't for on-demand
video.

**How would you reduce video start-up latency further?**
Techniques include serving the first segment at a lower, fast-to-fetch
resolution before the player has measured real throughput (so playback
starts almost instantly rather than waiting for a throughput estimate),
prefetching the manifest and first segment as soon as a user hovers/taps a
thumbnail rather than waiting for an explicit play action, and ensuring
popular content's first segments are aggressively edge-cached given they're
requested by definition every time that video starts.

**How would you handle copyright/content moderation at upload time?**
This is typically an additional asynchronous pipeline stage alongside
transcoding — e.g., a content-fingerprinting/matching service consumes the
same "video uploaded" event, and a video can be held from `READY` status
(Step 4) pending a moderation decision, without blocking or slowing the
transcoding pipeline itself.

**How do you handle a very large video (multi-hour, high resolution) differently from a short clip?**
Large uploads use chunked/resumable upload (so a network interruption
doesn't require restarting a multi-gigabyte upload from scratch) and the
transcoding job for a long video can itself be parallelized by splitting
the source into segments and transcoding them concurrently across multiple
workers, then reassembling the manifest — rather than one worker processing
hours of footage serially.

**How would you support offline downloads (watch without a network connection)?**
This reuses the same segment-and-rendition structure from adaptive
streaming (6.2): instead of the player fetching segments over the network
just-in-time, it pre-fetches and stores a chosen rendition's segments
locally on the device ahead of time, subject to DRM/licensing constraints
that are a separate concern from the core delivery architecture.

**Why store video in object storage instead of a traditional file system on application servers?**
Object storage is purpose-built for exactly this shape of data — huge
immutable blobs, accessed by key, needing to scale to exabytes and be
durable across failures without an application server owning any physical
disk — and decouples storage capacity/durability entirely from the
compute fleet serving requests, unlike a traditional filesystem tied to a
specific machine's disks; see `../01_Concepts/12_storage_systems.md`.
