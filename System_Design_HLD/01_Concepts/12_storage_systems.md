# Storage Systems

## Why it matters

Choosing the wrong storage type for the wrong job is one of the most common over-engineering *and* under-engineering mistakes in system design:

- **Storing large binary files (images, videos, backups) directly in a relational database** bloats the database, makes backups slow and expensive, and wastes an expensive, latency-optimized system on something that doesn't need transactional guarantees or indexes — object storage exists specifically for this and is far cheaper and more scalable for it.
- **Running analytical/reporting queries directly against the live production database** (e.g., "generate a report aggregating 2 years of order history") competes for the same resources the live application needs for fast transactional reads/writes, and can degrade or even take down the production app during a big report run.
- **Reaching for a data lake/warehouse in a design that never asked for analytics** adds real operational complexity (ETL pipelines, a second copy of all your data, a second system to run) for a requirement nobody stated — a classic sign of over-engineering an interview answer.

Knowing which storage system maps to which access pattern — and, just as importantly, knowing when *not* to introduce one — is core system design judgment.

## Block storage vs file storage vs object storage

These are three fundamentally different models for storing data, distinguished by how data is addressed and what kind of access pattern they're built for.

- **Block storage**: raw storage volumes, presented to a machine as if they were a physical disk. The machine's own OS formats it with a filesystem and manages it — the storage layer itself has no concept of "files," only fixed-size blocks addressed by location. Example: AWS EBS (Elastic Block Store). Used for things needing low-latency random I/O with full filesystem control, most notably databases — a database engine wants direct, fast, low-level control over how its data is laid out on disk.
- **File storage**: a shared, hierarchical filesystem (directories and files, exactly like a local filesystem) accessible **over a network** by multiple machines at once. Example: AWS EFS, NFS (Network File System). Used when multiple machines need to read/write the same shared files concurrently — e.g., a fleet of application servers sharing uploaded files or shared configuration.
- **Object storage**: a flat namespace of immutable **objects**, each identified by a unique key, stored with associated metadata, and accessed over an HTTP API (not a filesystem mount) — `GET`, `PUT`, `DELETE` on a key. Example: AWS S3. Used for large, unstructured blobs — images, videos, backups, log archives, static assets — anything you write once and read many times, without needing to modify parts of it in place.

| | Block storage | File storage | Object storage |
|---|---|---|---|
| Access unit | Fixed-size blocks | Files in a directory hierarchy | Whole objects via HTTP API |
| Latency | Lowest (near-local-disk) | Low-moderate (network filesystem overhead) | Higher (HTTP request overhead) |
| Scalability | Limited to volume size; scales by attaching more volumes | Moderate — shared but bounded by the filesystem service | Effectively unlimited — designed to scale horizontally |
| Typical access pattern | Random reads/writes, low-level, single machine at a time (usually) | Shared concurrent access, POSIX-like file semantics | Write-once/read-many, large blobs, no in-place partial edits |
| Cost | Higher per GB | Higher per GB | Lowest per GB |
| Example use case | Database data directory | Shared home directories, shared app config across a server fleet | Images, videos, backups, static site assets, data lake files |

## How object storage actually scales

Object storage systems like S3 scale to effectively unlimited size because of a few deliberate design choices that trade flexibility for scalability:

- **Flat key-namespace**: there is no real directory hierarchy underneath — a key like `photos/2024/vacation/img1.jpg` is just one opaque string key, not a chain of nested directory lookups. The "folder" structure you see in a UI/console is a cosmetic illusion built by splitting keys on `/` for display — the storage system itself doesn't need to walk a directory tree to find an object, it just looks up the key directly. This avoids the scaling bottleneck a real hierarchical filesystem has (having to traverse/lock directory structures as they grow).
- **Objects are immutable**: you don't edit part of an object in place — an "update" is really a full replace (upload a new object under the same key, replacing the old one entirely). This massively simplifies replication and caching: since an object never changes underneath a given version, replicas don't need complex in-place-edit coordination, and once cached, cached copies stay valid until explicitly replaced.
- **Distributed and replicated across many nodes**: each object (and often each piece of an object) is stored on multiple physical nodes for durability, and the system can spread both storage and request load across a very large number of nodes rather than being bound to the capacity of one machine.
- **Consistency model**: historically, many object stores were only **eventually consistent** for overwrites (you might briefly read stale data or an old version right after an update, until the change propagates to all replicas). Modern systems have improved this — S3, for example, now provides **strong read-after-write consistency** for both new object PUTs and overwrites/deletes. It's still worth knowing the eventual-consistency model existed and why (propagation across many replicated nodes takes some non-zero time), since it explains why some other/older object stores still behave that way and why you should always check the specific consistency guarantee of whichever object store you're actually using.

The combination of a flat namespace (no hierarchy to traverse/lock) and immutability (no in-place-edit coordination needed) is precisely what lets object storage scale horizontally to essentially unlimited size — every other storage model's scaling limits come from needing to coordinate around structure (a filesystem tree) or in-place mutation (a database row), and object storage deliberately has neither.

### Storage classes / tiering

Most object storage systems let you assign a **storage class** per object, trading retrieval latency/availability for cost — this is a common practical detail interviewers probe for once you've established the basic object-storage answer:

| Class (S3 naming, representative) | Retrieval | Typical use | Relative cost |
|---|---|---|---|
| Standard | Instant | Frequently accessed objects (active user uploads, current assets) | Highest |
| Infrequent Access | Instant, but charged per retrieval | Backups, older data accessed occasionally | Lower storage cost |
| Glacier / cold archive | Minutes to hours to retrieve | Long-term compliance archives, rarely touched | Lowest |

A **lifecycle policy** automatically moves objects between classes as they age (e.g., "move to Infrequent Access after 30 days, Glacier after 180 days") — this is the practical mechanism for keeping storage cost proportional to how "hot" data actually is, without manual intervention.

## Tie-in to CDN

Object storage is commonly used as the **origin** server that a CDN (Content Delivery Network) pulls from and caches at edge locations close to users (see `05_caching.md`'s CDN section for the full treatment of edge caching). A typical setup: images/videos are uploaded to S3, and a CDN is configured in front of the S3 bucket — the first request for a given object is fetched from S3 and cached at the nearest edge location, and every subsequent request for that object, from any nearby user, is served straight from the edge cache without hitting S3 (the origin) again. This combination — object storage for durable origin storage, CDN for low-latency global delivery — is the standard pattern for serving static assets and media at scale.

```text
User --> CDN Edge (cache hit: serve directly)
              |
              v (cache miss: fetch once)
         Object Storage (origin, e.g. S3)
```

## Data lake vs data warehouse

These are two different approaches to storing data for **analytics**, as opposed to storing data to power a live application (see OLTP vs OLAP below for that distinction).

- **Data lake**: stores raw data — structured, semi-structured, or fully unstructured — as-is, cheaply, at large scale, without imposing a schema upfront. This is **schema-on-read**: the structure is interpreted/applied at query time, by whatever job or tool reads the data, rather than enforced when the data is written. Used for flexible, large-scale analytics and machine learning workloads where you want to retain everything (including data whose eventual use isn't fully known yet) without paying the upfront cost of modeling and cleaning it all first.
- **Data warehouse**: stores structured, cleaned, and modeled data, with the schema defined and enforced **before** data is written — **schema-on-write**. Optimized for fast, well-structured business queries (dashboards, reports, BI tools) over data that's already been transformed into a known, query-friendly shape.

| | Data lake | Data warehouse |
|---|---|---|
| Data shape | Raw, unstructured/semi-structured | Structured, cleaned, modeled |
| Schema | Schema-on-read (applied at query time) | Schema-on-write (enforced at write time) |
| Flexibility | High — store anything, figure out structure later | Lower — must fit the predefined schema |
| Query speed for known business questions | Slower — structure must be inferred/parsed per query | Fast — data is pre-shaped for exactly this |
| Typical users | Data scientists, ML pipelines, exploratory analytics | Business analysts, BI dashboards, reporting |
| Cost | Cheap raw storage (often object storage underneath) | More expensive — purpose-built query engines |

### OLTP vs OLAP

This is the more general pattern that data lakes/warehouses map onto:

- **OLTP (Online Transaction Processing)**: the operational databases that power the live application — optimized for **many small, fast reads and writes** (e.g., "insert this order," "update this user's address"), typically normalized, row-oriented, and tuned for low-latency point queries and transactions. This is your everyday application Postgres/MySQL/DynamoDB.
- **OLAP (Online Analytical Processing)**: optimized for **complex aggregate queries over huge historical datasets** (e.g., "total revenue by region by month for the last 3 years") — typically denormalized/columnar, tuned for scanning and aggregating large volumes of data efficiently rather than for fast individual-row lookups. A data warehouse is the classic OLAP system.

The reason these are usually **separate systems** rather than one database doing both: their access patterns are close to opposite (OLTP wants many fast small transactions; OLAP wants efficient scans over huge amounts of data) and optimizing a database engine well for one tends to work against the other — so data is typically written to the OLTP store by the live application, then periodically extracted/transformed/loaded (ETL/ELT) into the OLAP store (warehouse) for analytics, keeping the two workloads from competing for the same resources.

**ETL vs ELT**, the two orderings of that pipeline: **ETL (Extract, Transform, Load)** transforms/cleans the data *before* loading it into the destination — the destination only ever holds already-shaped data, which is the traditional data-warehouse approach. **ELT (Extract, Load, Transform)** loads raw data into the destination first and transforms it afterward, using the destination's own compute to do the transformation — this is the more common pattern with data lakes and modern cloud warehouses (e.g., Snowflake, BigQuery) that have enough compute power to transform data in place cheaply. Object storage formats commonly used to hold that raw lake data efficiently include columnar formats like **Parquet** or **ORC**, which compress well and let analytical queries read only the columns they need rather than scanning whole rows — worth naming if a question goes deep on the lake's internals, but not something to volunteer unprompted.

## When system design interviews call for which storage type

A practical decision guide, and — just as important — a warning about over-including layers that weren't asked for:

- **OLTP relational or NoSQL database** — for the live application's core state (user accounts, orders, posts, sessions). This is the default answer for "where does the app's data live" in almost every design question.
- **Object storage** — for media/blobs (images, videos, file uploads, backups, exports). Pair with a CDN if the design involves serving that media to many users.
- **Data lake/warehouse** — **only** if the question explicitly involves analytics or reporting at scale (e.g., "the company needs a dashboard showing daily active users trends over 2 years," or "run ML training on all user activity"). Most "design X app" interview questions (design Twitter, design an URL shortener, design an e-commerce checkout) never ask for this, and introducing a data lake/warehouse unprompted reads as over-engineering — it signals you're pattern-matching to buzzwords rather than designing to the stated requirements. If in doubt, ask the interviewer whether analytics/reporting is in scope before adding this layer.

## Trade-offs / When to use what

| Need | Storage choice |
|---|---|
| Database's own data directory, low-latency random I/O | Block storage |
| Multiple machines need shared, concurrent file access | File storage (NFS/EFS) |
| Large unstructured blobs (images, video, backups), served at scale | Object storage (+ CDN) |
| Live application transactional state | OLTP database |
| Ad hoc, flexible, large-scale analytics/ML on raw data | Data lake |
| Fast structured business reporting/BI dashboards | Data warehouse (OLAP) |
| A "design X app" question with no stated analytics requirement | Just OLTP DB + object storage — skip lake/warehouse entirely |

## Interview Tips

- If the design involves user-uploaded media (photos, videos, documents), immediately reach for object storage + CDN rather than storing it in the primary database — this is one of the most commonly expected answers and skipping it is a red flag.
- Be ready to justify *why* object storage scales the way it does (flat namespace, immutability) if pushed — "it's just designed to scale" is a weaker answer than explaining the actual mechanism.
- Do not volunteer a data lake/data warehouse/OLAP layer unless the prompt explicitly mentions analytics, reporting, or ML — if you're unsure whether it's in scope, ask the interviewer rather than assuming. Adding it unprompted is a common tell of over-engineering under interview pressure.
- If asked "why not run your analytics queries directly against the production database," the expected answer is resource contention: OLAP-style aggregate queries over huge datasets compete with the live app's OLTP workload for the same database resources, potentially degrading the production app — hence separate OLTP/OLAP systems connected by ETL.
- Know the S3 consistency model detail (strong read-after-write, historically eventual) — it's a common "gotcha" follow-up when a design relies on "upload then immediately read" behavior.

## Quick Recall — Self-Test

**Q1: What's the core difference in access pattern between block storage, file storage, and object storage?**
Block storage exposes raw addressable blocks that a single machine's OS formats and manages itself (for low-latency random I/O, e.g. a database's disk). File storage exposes a shared hierarchical filesystem accessible by multiple machines over a network. Object storage exposes a flat namespace of immutable objects accessed via an HTTP API, built for large blobs written once and read many times.

**Q2: What two design choices let object storage scale to virtually unlimited size, and why does each matter?**
A flat key-namespace avoids the need to traverse or lock a real directory hierarchy as it grows (no structural bottleneck), and immutability (updates are full replaces, not in-place edits) avoids the coordination overhead needed for concurrent in-place mutation, letting replicas and caches stay simple and valid without complex synchronization.

**Q3: What consistency guarantee does S3 provide today for both new objects and overwrites, and why is it worth knowing this changed over time?**
S3 now provides strong read-after-write consistency for both new PUTs and overwrites/deletes. It's worth knowing the history because many object stores historically were only eventually consistent for overwrites (propagation across replicas takes time), so you should always verify the guarantee of whichever specific object store a design relies on rather than assuming strong consistency everywhere.

**Q4: What's the difference between schema-on-read and schema-on-write, and which storage type uses each?**
Schema-on-read means structure is interpreted at query time by whoever reads the data — used by data lakes, which store raw data as-is. Schema-on-write means the schema is defined and enforced before data is written — used by data warehouses, which store already-cleaned, modeled data.

**Q5: Why are OLTP and OLAP typically implemented as separate systems rather than one database serving both?**
Their access patterns are close to opposite: OLTP needs many small, fast transactional reads/writes, while OLAP needs efficient aggregate scans over huge historical datasets. A database engine optimized well for one tends to work against the other, so data is written to the OLTP store by the live app and periodically ETL'd into a separate OLAP store for analytics — keeping the two workloads from contending for the same resources.

**Q6: In a typical "design X app" system design interview, when should you introduce a data lake or warehouse?**
Only when the prompt explicitly involves analytics or reporting at scale (e.g., historical trend dashboards, ML training on user activity) — most app-design questions never need this layer, and adding it unprompted is a common over-engineering mistake; ask the interviewer if you're unsure whether it's in scope.

**Q7: How does object storage typically relate to a CDN in a real architecture?**
Object storage commonly serves as the CDN's origin: the first request for an object is fetched from object storage and cached at the nearest edge location, and subsequent nearby requests are served from that edge cache without hitting the origin again — combining durable, cheap origin storage with low-latency global delivery.

**Q8: Why would storing large uploaded videos directly in a relational database be a mistake?**
It bloats the database with large binary data it wasn't built to handle efficiently, slows down and inflates the cost of backups, and wastes an expensive, latency-optimized transactional system on something that doesn't need indexes or transactional guarantees — object storage is purpose-built and far cheaper/more scalable for large blobs.

**Q9: What does a storage class lifecycle policy do, and why does it matter for cost?**
It automatically moves objects between storage classes (e.g., Standard to Infrequent Access to Glacier) as they age, based on rules like "move after 30 days." This keeps storage cost proportional to how frequently data is actually accessed, without requiring manual reclassification of aging data.

**Q10: What's the difference between ETL and ELT, and why has ELT become more common with modern data lakes/warehouses?**
ETL transforms data before loading it into the destination, so the destination only ever holds already-shaped data. ELT loads raw data first and transforms it afterward using the destination's own compute. ELT has become more common because modern cloud warehouses and lake-adjacent query engines have enough compute power to transform data cheaply in place, avoiding a separate transformation stage before load.
