# Databases — Fundamentals

Before you can reason about scaling a database (`07_database_scaling.md`) or
its consistency guarantees under failure (`08_cap_theorem_and_consistency.md`),
you need a solid model of what a database is actually promising you, and why
different databases promise different things. This file covers the
vocabulary: relational databases and ACID, the major NoSQL categories and
BASE, indexing, and normalization — the foundation everything else in this
folder builds on.

## Why it matters

Picking a database isn't a stylistic choice — it's a bet on your access
patterns and consistency requirements that's expensive to unwind later.
Without understanding these fundamentals:

- You might pick a database that can't express your query patterns
  efficiently (e.g., a key-value store for data that needs complex joins and
  ad-hoc queries), forcing painful application-level workarounds.
- You might assume transactional guarantees a NoSQL store never promised,
  and lose money or data integrity in production (double-charging a user
  because two concurrent writes weren't isolated).
- You might over-normalize a read-heavy system into a maze of joins that
  can't hit its latency targets, or under-normalize a write-heavy system
  into a swamp of inconsistent duplicated data.
- You won't be able to answer the single most common system design
  interview question: "why did you choose this database?"

## Relational (SQL) Databases and ACID

A **relational database** organizes data into tables (**relations**) of
rows and columns, where relationships between tables are expressed through
**foreign keys**, and data is queried via a declarative language (SQL) that
lets you join across tables. Examples: PostgreSQL, MySQL, SQL Server,
Oracle.

What makes it "relational" isn't just "has tables" — it's that the schema
is fixed and enforced (every row in a table has the same columns, of the
same declared types) and relationships between entities are modeled
explicitly via keys, letting the database engine enforce referential
integrity (you can't have an order pointing to a customer that doesn't
exist) and execute multi-table queries (joins) efficiently.

The defining guarantee of relational databases is **ACID** — four
properties a database transaction (a group of operations that must succeed
or fail as one unit) guarantees. Running example throughout: **transferring
$100 from Alice's account to Bob's account** (two writes: debit Alice,
credit Bob).

- **Atomicity**: the transaction is all-or-nothing. If the debit from
  Alice's account succeeds but the credit to Bob's account fails (server
  crash mid-transaction), the *entire* transaction rolls back — Alice's
  account is restored to its original balance. You never end up in a state
  where money vanished because one half of a two-part operation completed.
- **Consistency**: the transaction moves the database from one valid state
  to another, respecting all defined rules (constraints, triggers, foreign
  keys). If there's a constraint that account balances can never go
  negative, a transfer that would overdraw Alice's account is rejected
  entirely — the database never allows a state that violates its own rules,
  even transiently.
- **Isolation**: concurrent transactions don't see each other's
  intermediate, uncommitted state. If Alice's transfer to Bob is
  in-progress at the same time as a separate transaction is *reading* both
  balances (say, for a bank statement), that read either sees the state
  fully before the transfer or fully after — never a half-applied state
  where Alice has been debited but Bob hasn't been credited yet.
- **Durability**: once a transaction is committed (the bank confirms "your
  transfer succeeded"), it survives any subsequent crash — a power outage
  one second later cannot un-commit it. This is normally achieved via
  write-ahead logging to durable storage before acknowledging the commit.

ACID is what lets you treat a multi-step operation as a single logical
unit and trust the database to never leave you in a partially-applied,
inconsistent state — which is exactly what you want for money, inventory
counts, or anything where "half-done" is worse than "not done."

## NoSQL Database Types

**NoSQL** ("not only SQL") is an umbrella term for databases that don't use
the relational table/row/join model, typically trading some of SQL's
strict schema and transactional guarantees for flexibility, horizontal
scalability, or performance on a specific access pattern. There are four
major categories, each purpose-built for a different shape of data and
access pattern — the category matters more than any individual product.

| Type | Definition | Example DB | Canonical use case |
|---|---|---|---|
| Key-Value | Data stored as opaque values addressed by a unique key, no querying into the value's structure | Redis, DynamoDB | Session storage, caching, shopping carts — anything looked up purely by ID |
| Document | Semi-structured documents (usually JSON/BSON) with flexible, nested, per-record schemas | MongoDB | Content management, product catalogs, user profiles — data that varies in shape record to record |
| Column-family (wide-column) | Data stored by column groups rather than rows, optimized for massive writes and range scans over a partition key | Cassandra, HBase | Write-heavy time-series data, logging, IoT sensor data at very large scale |
| Graph | Data modeled as nodes and edges, optimized for traversing relationships | Neo4j | Social graphs, recommendation engines, fraud-detection networks — data where the *connections* are the point |

A bit more on each:

- **Key-value stores** are the simplest possible model: `get(key)` and
  `set(key, value)`, nothing more. That simplicity is the point — it's what
  makes them extremely fast and trivially shardable (you don't need to
  understand a value's structure to route it to a shard). Good for data
  accessed only by a known ID, bad the moment you need to query *by* a
  value's contents.
- **Document stores** relax the fixed-schema requirement — two "documents"
  in the same collection can have different fields. This suits data whose
  shape legitimately varies or evolves quickly (a product catalog where
  a shoe has a "size" field and a book doesn't) without requiring a schema
  migration for every change. The trade-off: no enforced schema means the
  application is responsible for data consistency the database used to
  guarantee.
- **Column-family stores** physically group data by column rather than by
  row, and partition data across nodes by a partition key with data ordered
  by a clustering key. This is what makes them exceptional at high-volume
  sequential writes and range scans within a partition (e.g., "all sensor
  readings for device X between time A and B") — a pattern relational
  databases handle far worse at extreme write volume.
- **Graph databases** store relationships as first-class citizens (edges
  with their own properties, not foreign-key joins computed at query time).
  Traversing "friends of friends of friends" is a constant-time
  pointer-following operation in a graph DB versus an expensive
  multi-way join in a relational DB — this is the entire reason they exist.

### BASE — the NoSQL-World Contrast to ACID

Many NoSQL systems (especially those built for horizontal scale across many
nodes) relax ACID in favor of **BASE**:

- **Basically Available**: the system guarantees availability (a response
  to every request) even during a partial failure, prioritizing uptime over
  perfect correctness.
- **Soft state**: the state of the system may change over time even
  without new input, because of replication catching up in the background
  — the data isn't a single fixed, immediately-consistent value the way it
  is under ACID.
- **Eventually consistent**: given enough time with no new writes, all
  replicas will converge to the same value — but at any given instant,
  different nodes might return different (stale) answers.

BASE isn't "worse" than ACID — it's a different trade for a different goal:
BASE systems generally sacrifice immediate consistency to gain availability
and horizontal write scalability that strict ACID systems struggle to
achieve across many distributed nodes. See `08_cap_theorem_and_consistency.md`
for the theoretical basis of this trade-off.

## Indexing

An **index** is an auxiliary data structure that lets the database find rows
matching a query without scanning the entire table. Without an index,
looking up "the user with email X" out of 10 million rows means checking up
to 10 million rows one by one (a full table scan, O(n)).

The dominant structure is the **B-tree** (or its variant, the B+tree): a
sorted, balanced tree structure where each node can have many children,
keeping the tree shallow even for huge datasets. Conceptually, it's the
generalization of binary search into a disk-friendly structure — instead of
scanning linearly, the database narrows the search space at each level of
the tree, giving **O(log n)** lookups instead of O(n). Because the structure
stays shallow (a B-tree over millions of rows might only be 3-4 levels
deep), a lookup takes only a handful of disk reads instead of potentially
millions.

```text
Without index (full scan):        With B-tree index:
[row1][row2][row3]...[row_n]         [root: splits into ranges]
  scan every row, O(n)                /        |         \
                                  [range]   [range]    [range]
                                    /  \       ...        ...
                               [leaf][leaf]  -> matching row(s), O(log n)
```

**The fundamental trade-off**: an index makes reads dramatically faster,
but every index also has to be updated on every `INSERT`, `UPDATE`, or
`DELETE` that touches an indexed column — so writes get slower, and every
index consumes additional disk space. A table with five indexes pays the
write-amplification cost of updating all five structures on every write.
This is why you index the columns you actually filter/sort/join on, not
every column reflexively — indexing everything trades away the write
performance you might need.

## Normalization vs Denormalization

**Normalization** is the process of structuring relational data to
eliminate redundancy — each fact is stored in exactly one place, and
related data is split into separate tables linked by foreign keys. Its
purpose is to prevent **update anomalies**: if a user's email is stored
redundantly in 50 rows across different tables, updating it means finding
and updating all 50 (or risking inconsistent copies if you miss one).
Normalization fixes this by storing it once, in a `users` table, and having
everything else reference it by ID.

**Denormalization** deliberately reintroduces redundancy — duplicating
data across tables/documents — to avoid the cost of joining at read time.
System design interviews frequently favor denormalization for read-heavy
systems, because the calculus that favors normalization (minimize storage,
avoid anomalies) is secondary to the calculus that matters at scale
(minimize read latency and query complexity).

**Concrete example**: a social feed needs to render each post along with
its author's display name. Normalized approach: `posts` table stores
`author_id`; every feed read does a `JOIN` against `users` to fetch the
name. At feed-rendering scale (thousands of reads per second, each showing
dozens of posts), that's a join executed constantly for data that rarely
changes. Denormalized approach: store `author_name` directly on the post
record (or post document) at write time. Reading a feed is now a single
query with no join — faster, and simpler to scale (see federation in
`07_database_scaling.md`, where joins across separately-scaled databases
aren't even possible). The cost: if a user changes their display name, you
now must update it on every post they've ever written (or accept that old
posts show the old name until some backfill process catches up) — the
classic update-anomaly risk normalization exists to prevent, now
reintroduced on purpose because reads vastly outnumber writes for this
field.

| | Normalization | Denormalization |
|---|---|---|
| Redundancy | Minimized — each fact stored once | Deliberately duplicated |
| Read performance | Slower (requires joins) | Faster (no joins needed) |
| Write/update complexity | Simple (update one place) | Complex (update every duplicate, or tolerate staleness) |
| Storage | Smaller | Larger |
| Best for | Write-heavy, consistency-critical data (financial records) | Read-heavy data where join cost dominates (feeds, catalogs) |

## SQL vs NoSQL — Decision Framework

| Choose SQL when... | Choose NoSQL when... |
|---|---|
| Data is naturally structured/relational | Schema is flexible or evolves frequently |
| You need multi-row/multi-table transactions (ACID) | Access patterns are simple and known in advance (lookup by key) |
| Strong consistency is required (financial data, inventory counts) | You need massive horizontal write scale beyond what a single-leader relational DB can offer |
| Complex queries, joins, and ad-hoc reporting are common | Data is naturally document-, graph-, or wide-column-shaped |
| Data volume fits comfortably with vertical scaling + read replicas | Eventual consistency is an acceptable trade for availability/throughput |

In practice, most non-trivial systems use **polyglot persistence** —
multiple database types, each for the part of the system it fits best,
rather than forcing one database to serve every need. A concrete example:
an e-commerce platform typically uses a relational database (PostgreSQL/
MySQL) for **orders and inventory**, where ACID transactions matter (you
cannot sell the same unit of inventory twice, and an order + payment +
inventory decrement must succeed or fail together) — but uses a document
store (MongoDB) for the **product catalog**, where each product category
has wildly different attributes (a shirt has "size" and "color," a laptop
has "RAM" and "screen size") and catalog reads vastly outnumber catalog
writes, making flexible schema and simple key-based lookups a better fit
than rigid relational tables.

## Trade-offs

| Decision | SQL / ACID | NoSQL / BASE |
|---|---|---|
| Consistency | Strong, immediate | Eventual (usually), tunable in some stores |
| Schema | Fixed, enforced | Flexible, per-record |
| Horizontal write scale | Harder (needs sharding, see `07_database_scaling.md`) | Built-in from the ground up in most designs |
| Query flexibility | High (joins, ad-hoc SQL) | Low-to-medium, access patterns often must be known upfront |
| Transactional guarantees | Multi-row/table transactions | Usually limited to single-document/single-key atomicity |

None of these is "better" in the abstract — SQL's rigidity is a feature
when correctness matters more than raw scale; NoSQL's flexibility is a
feature when scale and schema evolution matter more than multi-row
transactional guarantees.

## Interview Tips

- "Why this database?" is one of the most commonly asked follow-ups in any
  system design interview. A strong answer names the specific access
  pattern (read-heavy? write-heavy? need joins? need transactions?) and
  ties it to the database category — not just a product name.
- Don't say "I'd use NoSQL because it scales better" without qualifying
  *why* — interviewers want to hear that you understand NoSQL scales better
  for certain access patterns by relaxing specific guarantees (schema
  rigidity, multi-row transactions, immediate consistency), not that NoSQL
  is unconditionally faster.
- Be ready to defend polyglot persistence — proposing two or three
  different databases for different parts of one system is usually a sign
  of maturity, not overengineering, as long as you can justify each choice
  individually.
- When asked about ACID, always ground each property in a concrete failure
  mode it prevents (as in the bank transfer example above) rather than
  reciting definitions — interviewers are checking you understand *why*
  each property exists, not that you memorized the acronym.
- If you propose denormalization, proactively mention the write-side cost
  (keeping duplicates in sync, or tolerating temporary staleness) — this is
  exactly the kind of trade-off acknowledgment interviewers are listening
  for.

## Quick Recall — Self-Test

**1. In the bank transfer example, which ACID property prevents a state where Alice is debited but Bob is never credited?**
Atomicity — the transaction is all-or-nothing, so if the credit to Bob fails, the debit from Alice is rolled back too, rather than leaving the transaction half-applied.

**2. What's the difference between isolation and durability?**
Isolation concerns concurrent transactions not seeing each other's uncommitted intermediate state (no one reads a half-applied transfer). Durability concerns a *committed* transaction surviving subsequent failures like a crash or power loss — once confirmed, it cannot be undone by a later failure.

**3. Why would you pick a column-family store like Cassandra over a document store like MongoDB for IoT sensor data?**
Column-family stores are optimized for extremely high write throughput and range scans over a partition key (e.g., all readings for a device across a time range), which is exactly the access pattern of IoT/time-series data at massive scale — document stores are more general-purpose and not specifically optimized for that write/range-scan pattern.

**4. Explain "eventually consistent" in one sentence, and give a real symptom a user might notice.**
Given no new writes, all replicas will eventually converge to the same value, but at any given instant different nodes may return different (stale) data. A concrete symptom: a user updates their profile photo, but a friend viewing their profile a second later still briefly sees the old photo because the read hit a replica that hasn't caught up yet.

**5. Why does adding an index speed up reads but slow down writes?**
An index is a separate sorted structure (typically a B-tree) that lets lookups skip most of the table (O(log n) instead of O(n) scan). But every insert/update/delete that touches an indexed column must also update that structure, so more indexes mean more work per write and more disk space consumed.

**6. Give a concrete example of denormalization trading redundancy for read speed.**
Storing `author_name` directly on a post record instead of only storing `author_id` and joining to a `users` table on every read. Feed reads become a single query with no join, at the cost that a user's name change requires updating every post they've written (or accepting temporary staleness).

**7. What does "polyglot persistence" mean, and why would an e-commerce system use it?**
Using multiple types of databases within one system, each chosen for the part of the system it fits best, rather than one database for everything. An e-commerce system might use a relational DB for orders/inventory (needs ACID transactions to avoid overselling) and a document store for the product catalog (needs flexible, per-category schema and fast key-based reads).

**8. A candidate says "NoSQL is always more scalable than SQL." What's the more precise version of this claim?**
NoSQL databases are typically designed from the ground up for horizontal write scaling by relaxing specific guarantees — strict schema enforcement, multi-row ACID transactions, and immediate consistency. It's not that NoSQL is unconditionally faster; it scales differently because it gives up specific things relational databases hold onto, and those trade-offs are only worth it for certain access patterns.
