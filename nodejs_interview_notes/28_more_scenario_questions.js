/*
===============================================================================================
                       MORE SCENARIO-BASED NODE INTERVIEW QUESTIONS  (set 2)
===============================================================================================
Additional "how would you handle X in production" questions beyond file 26. Spoken-answer style.
These cover ground a 3.5-year interview commonly probes: debugging, concurrency, data, deploys,
real-world failure modes. Many tie back to my real projects (file 27).
*/

/*
-----------------------------------------------------------------------------------------------
Q1: A user uploads a 500MB file to your API. How do you handle it without crashing the server?
-----------------------------------------------------------------------------------------------
Answer -> Never buffer a large upload in memory. I STREAM it straight to its destination.
  - Use multer with disk/stream storage, or busboy, and pipe the upload stream directly to S3
    (multipart upload) or to disk — so memory stays flat regardless of file size.
  - Set a SIZE LIMIT (multer limits / express body limits) so a malicious 50GB upload is rejected
    early, not after filling the disk.
  - Do the heavy processing (virus scan, parse, transcode) ASYNCHRONOUSLY in a BullMQ worker; the
    endpoint just stores the file + returns 202 with a job id. (This is the EDI-import instinct:
    stream + offload, never block the request or the event loop.)
  - For very large client uploads, prefer PRESIGNED S3 URLs so the file goes client -> S3 directly
    and never transits my Node process at all — best for scale.
*/

/*
-----------------------------------------------------------------------------------------------
Q2: Your API response times are fine on average but the p99 is terrible. What's going on?
-----------------------------------------------------------------------------------------------
Answer -> Averages hide tail latency; a bad p99 in Node usually means something INTERMITTENTLY
blocks the single event loop. I'd look for:
  - Occasional CPU-heavy work on the main thread (a big JSON.parse/stringify, a sync crypto call,
    a large sort) that freezes ALL requests for that moment -> spikes everyone's latency. Fix:
    offload to worker_threads / a job, or chunk it.
  - GC pauses from memory pressure / a leak -> periodic stop-the-world stalls. Fix: find the leak
    (heap snapshots), reduce allocations, bound caches.
  - Connection-pool exhaustion: under bursts, requests QUEUE waiting for a DB/Redis connection ->
    tail latency. Fix: size the pool, add timeouts, scale out.
  - A slow downstream dependency without a timeout, occasionally hanging.
  I'd confirm with event-loop-lag metrics + APM percentile traces, then fix the specific cause.
  "Tail latency in Node is the event-loop-blocking smell — I chase blocking, GC, and pool queuing."
*/

/*
-----------------------------------------------------------------------------------------------
Q3: You need to call 5 microservices to build one response. How do you make it fast and resilient?
-----------------------------------------------------------------------------------------------
Answer ->
  - PARALLELIZE the independent calls with Promise.all instead of awaiting them one by one
    (max(latencies) instead of sum). Only sequence the ones that genuinely depend on each other.
  - TIMEOUT every outbound call (e.g. AbortController / a timeout wrapper) so one slow service
    can't hang the whole response and pile up pending work on the loop.
  - Use Promise.allSettled when some services are NON-critical, so one failure degrades gracefully
    (return partial data) instead of failing the whole request.
  - CIRCUIT BREAKERS (opossum) + retries-with-backoff for flaky dependencies; cache stable results.
  - Bound concurrency to downstreams so a burst doesn't overwhelm them.
    const [a, b, c] = await Promise.all([
      withTimeout(svcA(), 800), withTimeout(svcB(), 800), withTimeout(svcC(), 800),
    ]);
  "Fan out in parallel, time-box every call, and degrade gracefully when a non-critical service is down."
*/

/*
-----------------------------------------------------------------------------------------------
Q4: A scheduled job must run exactly once across your 4 app instances. How?
-----------------------------------------------------------------------------------------------
Answer -> If I naively put a node-cron in the app, ALL 4 instances fire it -> 4x execution.
Options:
  - Use a Redis-backed REPEATABLE BullMQ job: the queue schedules it once and exactly one worker
    picks it up — the cleanest fix and consistent with the rest of my stack.
  - Or a DISTRIBUTED LOCK: before running, acquire a Redis lock (SET key val NX EX ttl / Redlock);
    only the instance that wins the lock runs it; others skip.
  - Or run the scheduler as a SEPARATE single-replica deployment (a dedicated cron service / k8s
    CronJob) so there's only ever one scheduler.
  And make the job IDEMPOTENT regardless, so an accidental double-run is harmless.
  "Don't schedule inside every replica — centralize it with a Redis-backed queue, a distributed
   lock, or a dedicated single-instance scheduler, and keep the job idempotent."
*/

/*
-----------------------------------------------------------------------------------------------
Q5: How do you implement rate limiting that works across multiple instances?
-----------------------------------------------------------------------------------------------
Answer -> An in-memory counter per instance is wrong — with 4 instances a "100/min" limit becomes
400/min. The counter must be SHARED, so I keep it in Redis.
  - express-rate-limit with a Redis store (rate-limit-redis), or a custom atomic INCR + EXPIRE.
  - Algorithm choice: fixed window (simple, but allows bursts at window edges), sliding window
    (smoother), or token bucket (allows controlled bursts). I'd usually use a sliding-window or
    token-bucket implementation in Redis for fairness.
  - Key by user id / API key / IP depending on the policy; return 429 + Retry-After when exceeded.
  // sketch: atomic per-window counter in Redis
  const n = await redis.incr(key);
  if (n === 1) await redis.expire(key, windowSeconds);
  if (n > limit) return res.status(429).set('Retry-After', windowSeconds).end();
  This is also exactly how I throttled outbound WhatsApp traffic to respect Meta's limits (file 27).
*/

/*
-----------------------------------------------------------------------------------------------
Q6: A webhook from a payment/messaging provider sometimes arrives twice. How do you avoid
    double-processing? (directly my WhatsApp webhook experience)
-----------------------------------------------------------------------------------------------
Answer -> Providers guarantee at-least-once delivery, so webhooks WILL occasionally duplicate. I
make processing idempotent:
  - VERIFY the signature first (reject forgeries).
  - ACK fast (200) and process asynchronously off a queue.
  - DE-DUPE on the provider's event/message id: use it as the BullMQ jobId, and/or store processed
    ids with a unique index so a duplicate insert is a no-op.
  - Make the side effects idempotent (upserts, "already handled?" checks) so even if it slips
    through twice, the outcome is identical.
  "Verify, ack fast, process async, and key everything on the provider's id so a redelivered
   webhook is harmless — exactly how I handled WhatsApp delivery receipts and inbound messages."
*/

/*
-----------------------------------------------------------------------------------------------
Q7: Your Node service's memory keeps climbing until it OOM-restarts every few hours. Debug it.
-----------------------------------------------------------------------------------------------
Answer ->
  1. Confirm it's a leak (memory grows and never plateaus) vs just high baseline — watch
     process.memoryUsage().heapUsed over time / container metrics.
  2. Take HEAP SNAPSHOTS at intervals (Chrome DevTools via --inspect, or heapdump) and DIFF them
     to find which object type keeps growing and what's retaining it.
  3. Usual suspects: an unbounded in-memory cache/Map, forgotten event listeners or timers (the
     EventEmitter leak warning), closures holding big objects, accumulating data in a long-running
     worker, or a global array that only grows.
  4. Fix the root cause: bound caches (LRU + TTL), remove listeners / use once(), don't accumulate
     in workers (process in batches).
  5. Safety net: PM2 max_memory_restart / k8s memory limits recycle a leaking process cleanly while
     I fix it — the same "restart to reclaim memory" tactic I'd use for Puma/Sidekiq in Rails.
*/

/*
-----------------------------------------------------------------------------------------------
Q8: How do you safely run a DB migration that adds a NOT NULL column to a 50M-row table, with
    zero downtime?
-----------------------------------------------------------------------------------------------
Answer -> A naive "add NOT NULL column with default" can lock the table and break the running app.
I use the EXPAND -> BACKFILL -> CONTRACT pattern (same discipline as my Rails migrations):
  1. EXPAND: add the column as NULLABLE (fast, no rewrite). Deploy app code that WRITES the new
     column but doesn't yet require it — so old and new code can both run during the rollout.
  2. BACKFILL existing rows in BATCHES (a background job, a few thousand rows at a time) to avoid
     long locks / replication lag. (My EDI batching instinct applies here too.)
  3. CONTRACT: once backfilled, add the NOT NULL constraint (and any index, created CONCURRENTLY in
     Postgres to avoid locking), then deploy code that relies on it.
  Each deploy is backward-compatible, so a rolling deploy never has a version that breaks.
  "Never ship a migration that locks a huge table or breaks the currently-running code — expand,
   backfill in batches, then contract."
*/

/*
-----------------------------------------------------------------------------------------------
Q9: Two requests try to book the last available seat/inventory item at the same time. Prevent
    overselling.
-----------------------------------------------------------------------------------------------
Answer -> This is a race condition on a hot resource; a read-check-then-write has a window where
both see "1 available." Options, best-first for this case:
  - ATOMIC CONDITIONAL UPDATE in the DB: `UPDATE inventory SET qty = qty - 1 WHERE id = ? AND
    qty > 0` and check rows-affected; if 0, it's sold out. No read-modify-write race at all.
  - PESSIMISTIC LOCK: SELECT ... FOR UPDATE inside a transaction to serialize the critical section
    (good for high contention, keep the tx short).
  - DISTRIBUTED LOCK (Redis/Redlock) if the coordination spans services, used carefully with a TTL.
  - For high-scale flash-sale style: decrement a Redis counter atomically (DECR) as the source of
    truth and reconcile to the DB asynchronously.
  I'd default to the atomic conditional UPDATE — simplest and correct. (Same family as the
  optimistic-locking answer for concurrent claim edits in file 27.)
*/

/*
-----------------------------------------------------------------------------------------------
Q10: How do you handle secrets, config, and environment differences in a Node deploy?
-----------------------------------------------------------------------------------------------
Answer -> (short, since file 19/26 cover it) Env vars via process.env; dotenv in dev (never commit
.env, commit a .env.example); a secrets manager (AWS Secrets Manager/SSM, Vault, k8s secrets) in
prod; VALIDATE env at boot with a Zod/envalid schema so missing vars fail fast; centralize in one
typed config module; never log secrets. NODE_ENV gates behavior. The credentials.yml.enc/ENV
discipline from Rails.
*/

/*
-----------------------------------------------------------------------------------------------
Q11: A third-party API you depend on goes down for 10 minutes. How does your app behave?
-----------------------------------------------------------------------------------------------
Answer -> It should DEGRADE, not collapse:
  - TIMEOUTS on every call so requests fail fast instead of hanging (and exhausting the loop/pool).
  - CIRCUIT BREAKER (opossum): after a failure threshold, trip OPEN and stop calling for a cooldown
    — fail fast / serve a fallback instead of piling thousands of doomed requests. Half-open probes
    test recovery, then close.
  - RETRIES with exponential backoff + jitter for transient blips (idempotent ops only).
  - FALLBACKS: serve cached/last-known-good data for non-critical reads; queue writes for later.
  - For async flows: jobs retry with backoff and land in a DLQ if the outage outlasts retries —
    nothing is lost, it processes when the API recovers.
  This is precisely the circuit-breaker + backoff design I used for the Meta API (file 27).
*/

/*
-----------------------------------------------------------------------------------------------
Q12: You're seeing "too many connections" errors from Postgres in production. Why and fix?
-----------------------------------------------------------------------------------------------
Answer -> Node serves many concurrent requests from each process sharing a connection POOL, and I'm
running multiple processes — so total connections = (instances/cluster workers) x (pool size), and
it's exceeding Postgres' max_connections.
  - Right-size the pool per instance and count ALL instances (e.g. 4 cluster workers x pool 10 = 40
    from one box; multiply by replicas).
  - Put a CONNECTION POOLER in front (PgBouncer / RDS Proxy / Prisma Accelerate) so the DB sees a
    bounded number of connections regardless of app process count — essential for serverless too.
  - Make sure connections are actually RELEASED (no leaked transactions/clients holding connections;
    always release in finally / use the pool's managed query).
  - Add acquire timeouts so a request fails fast rather than hanging when the pool is drained.
  "It's almost always pool-size x process-count overrunning max_connections — cap the pool and add
   PgBouncer."
*/

/*
-----------------------------------------------------------------------------------------------
Q13: How would you design a notification system that sends email + SMS + push, reliably?
-----------------------------------------------------------------------------------------------
Answer -> (ties my WhatsApp/notification pipeline experience)
  - An API/event drops a notification request onto a BullMQ queue (don't send inline).
  - A worker fans out per channel, each channel behind an ADAPTER (email via SES/nodemailer, SMS via
    Twilio, push via FCM) so providers are swappable.
  - Per-channel: retries with backoff, rate limiting to respect provider limits, circuit breakers
    for provider outages, and a DLQ for permanent failures.
  - IDEMPOTENCY keyed on a notification id so a retry doesn't double-send.
  - Track delivery status (queued/sent/delivered/failed) persisted in the DB for auditing, updated
    from provider webhooks (like WhatsApp delivery receipts).
  - User preferences / quiet-hours / dedup checked before sending.
  "Queue it, fan out per channel behind adapters, make each idempotent + rate-limited + retried, and
   persist delivery status — the same fault-tolerant pipeline shape as my WhatsApp delivery system."
*/

/*
-----------------------------------------------------------------------------------------------
Q14: How do you structure logging and tracing so you can debug a problem in production?
-----------------------------------------------------------------------------------------------
Answer ->
  - STRUCTURED JSON logs (pino) — searchable/aggregatable in ELK/Datadog/CloudWatch — not console.log.
  - A CORRELATION / REQUEST ID per request (middleware sets req.id + a child logger), propagated to
    downstream calls and jobs, so I can trace ONE request/message across the whole system — exactly
    the correlation-id approach I used in the WhatsApp CRM.
  - Use AsyncLocalStorage to carry the request context implicitly (the Rails CurrentAttributes idea).
  - Log levels, no secrets/PII, errors with full context + an error tracker (Sentry).
  - METRICS (prom-client -> Prometheus/Grafana): request rate, error rate, latency percentiles,
    queue depth, event-loop lag. DISTRIBUTED TRACING (OpenTelemetry) for multi-service requests.
  - Health/readiness endpoints for the LB and k8s probes.
  "Structured logs + a correlation id threaded everywhere + metrics + tracing is what turns a 2am
   incident from guesswork into following one request end-to-end."
*/

module.exports = {};
