/*
===============================================================================================
                       DATABASE SCALING STRATEGIES
===============================================================================================
(Mirrors my database_scaling_strategies.rb. These strategies are about the DATABASE, so they're
identical to my Rails notes — the DB is the same Postgres/Mongo. This file restates them and shows
the Node/ORM-specific wiring. Complements file 18 performance and file 14 ORMs.)
*/

/*
-----------------------------------------------------------------------------------------------
Q1: The five scaling options (memorize this table)
-----------------------------------------------------------------------------------------------
Answer ->
  TYPE                 WHAT IT MEANS                                  WHEN TO USE
  ------------------   --------------------------------------------   --------------------------
  Vertical scaling     Bigger box: more CPU/RAM/SSD on one DB         Early stages, quick win
  Horizontal scaling   More servers/nodes to share load               Very large systems
  Read replicas        Read-only copies serve SELECTs                 Read-heavy workloads
  Partitioning         Split one big table into pieces (same DB)      Huge tables (logs, orders)
  Sharding             Split data across multiple databases           Massive / region-specific data

  Rule of thumb: scale vertically first (simplest), then add read replicas (most apps are read-
  heavy), then partition big tables, and only shard when you truly must (it's the most complex).
*/

/*
-----------------------------------------------------------------------------------------------
Q2: Vertical vs Horizontal scaling
-----------------------------------------------------------------------------------------------
Answer ->
  VERTICAL (scale UP): upgrade the existing server — more CPU cores, more RAM, faster SSD, or a
  higher managed-DB tier. No code change; just point at the same DB. Simple, but has a ceiling and
  is a single point of failure.

  HORIZONTAL (scale OUT): add more nodes and spread load, usually behind a load balancer. Better
  for high availability (one node down, system stays up) and very high read+write volume, but more
  complex (replication, consistency, routing).

  For the Node APP TIER, horizontal scaling = multiple stateless instances (cluster/PM2/k8s
  replicas) behind an ALB (file 18). For the DB tier, it's replicas/partitioning/sharding below.
*/

/*
-----------------------------------------------------------------------------------------------
Q3: Read replicas (the most common DB scaling move)
-----------------------------------------------------------------------------------------------
Answer -> Read replicas are copies of the primary DB that serve ONLY reads. The primary handles
writes (authoritative); replicas serve SELECTs. Replication is usually ASYNCHRONOUS, so there's a
small REPLICATION LAG between primary and replicas.

  In Node you route reads to a replica connection and writes to the primary:
   - Sequelize: built-in read replication config.
       new Sequelize('db', user, pass, {
         replication: { read: [{ host: 'replica1' }, { host: 'replica2' }], write: { host: 'primary' } },
       });
     Sequelize then sends SELECTs to replicas and writes to the primary automatically.
   - Prisma: typically use the read-replicas extension or separate clients (primary + replica).
   - Manual: keep two pools (writePool, readPool) and choose per query.

  THE GOTCHA — read-your-writes: because of replication lag, a user who just wrote may read stale
  data from a replica (the "stale data after update" scenario, file 26 Q7). Fix: route the
  immediate post-write read to the PRIMARY, or wait for replication. This is exactly the same lag
  caveat from my Rails connected_to(role: :reading) notes.
*/

/*
-----------------------------------------------------------------------------------------------
Q4: Partitioning (split one big table within the same database)
-----------------------------------------------------------------------------------------------
Answer -> Partitioning breaks one logically-single, huge table into smaller physical pieces so
queries scan less data and maintenance (vacuum, index) is cheaper. Same DB, transparent to the app.
  - RANGE partitioning: by a range, e.g. orders by month/year (great for time-series, logs).
  - LIST partitioning: by a discrete value, e.g. region.
  - HASH partitioning: spread evenly by a hash of a key.
  Postgres declarative partitioning (PARTITION BY RANGE) is the typical tool. Old partitions can be
  dropped cheaply (data retention) instead of slow DELETEs. The app/ORM mostly doesn't change — it
  queries the parent table.
*/

/*
-----------------------------------------------------------------------------------------------
Q5: Sharding (split data across multiple databases — the heavy artillery)
-----------------------------------------------------------------------------------------------
Answer -> Sharding splits data ACROSS MULTIPLE DATABASES/servers by a SHARD KEY (e.g. user_id,
tenant_id, region). Each shard holds a subset; no single DB holds everything. Scales writes (the
thing replicas DON'T help with) and total data size.

  Trade-offs to mention (this is the senior part):
   - Choosing the shard key is critical — a bad key causes hot shards / uneven load.
   - CROSS-SHARD queries and JOINs are hard/expensive; you design to avoid them.
   - Cross-shard transactions are very hard (back to eventual consistency / sagas — file 25).
   - Rebalancing shards is operationally painful.
  In Node you'd route by computing the shard from the key (a routing layer / a tool like Vitess for
  MySQL, Citus for Postgres, or Mongo's native sharding). MongoDB has built-in sharding — relevant
  since Horizon used Mongo.

  "Sharding is the last resort — it scales writes and data size but adds real complexity, so I'd
   exhaust vertical scaling, replicas, partitioning, and caching first."
*/

/*
-----------------------------------------------------------------------------------------------
Q6: Things that reduce DB load BEFORE you scale hardware (cheaper wins first)
-----------------------------------------------------------------------------------------------
Answer -> Often you don't need to scale the DB — you need to stop hammering it:
  - INDEXES on filtered/joined/sorted columns (the single biggest win — file 14).
  - Fix N+1 queries (eager load — file 14).
  - CACHING hot reads in Redis (file 17) so they never hit the DB.
  - CONNECTION POOLING sized correctly + PgBouncer (file 28) so connections aren't the bottleneck.
  - Move heavy reporting to read replicas; move heavy writes to background jobs/batches (file 16/27).
  - Select only needed columns; paginate (keyset for deep pages).
  "Measure first — most 'we need a bigger DB' problems are actually a missing index, an N+1, or no
   caching. I scale hardware after I've optimized queries and added caching." (Same discipline I
   applied in Rails — pluck/select, find_each batching, includes, counter caches.)
*/

/*
-----------------------------------------------------------------------------------------------
Q7: CAP-ish reality + consistency talk (in case they probe)
-----------------------------------------------------------------------------------------------
Answer -> As you distribute the DB (replicas/shards), you trade strict consistency for availability
+ scale. Async replication = eventual consistency = possible stale reads. Decide per use case:
  - Money/critical reads -> read from primary / strong consistency.
  - Feeds, search, analytics -> eventual consistency is fine and much cheaper to scale.
  Knowing WHEN stale data is acceptable is the real skill — it drives whether you can use replicas/
  caching aggressively or must hit the primary.
*/

module.exports = {};
