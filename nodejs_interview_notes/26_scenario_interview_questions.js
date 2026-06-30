/*
===============================================================================================
                       REAL-WORLD / SCENARIO-BASED NODE INTERVIEW QUESTIONS
===============================================================================================
These are the "tell me how you'd handle X in production" questions — the most important kind for
someone with 3.6 yrs experience. Spoken-answer style, like my Rails scenario notes. Each one ties
back to real experience where possible.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: Your Node API suddenly gets slow / unresponsive under load. How do you debug it?
-----------------------------------------------------------------------------------------------
Answer -> First I MEASURE before guessing — same discipline as my Rails perf work.

  1. Check whether the EVENT LOOP is blocked: rising event-loop lag (perf_hooks
     monitorEventLoopDelay, or APM) means synchronous CPU work is freezing the loop. That's
     Node-specific and the first thing I rule out, because in Node one blocking operation
     freezes ALL requests, not just one.
  2. Look at APM/traces (New Relic/Datadog) to see WHERE time goes: DB, downstream API, or CPU.
  3. If it's the DB (usually is): hunt N+1 queries, missing indexes, slow queries, and check the
     connection pool isn't exhausted (requests queuing for a connection).
  4. If it's CPU on the main thread: find the hot path (clinic flame / 0x), and offload it to
     worker_threads or a background job.
  5. Check memory: if it's climbing without plateauing, a leak may be triggering GC pauses /
     restarts — take heap snapshots.
  6. Check downstream calls: are they timing out? Missing timeouts make a slow dependency hang
     all your requests; I add timeouts + circuit breakers.

  Then fix the biggest contributor first: add an index, fix the N+1, add caching, offload CPU,
  or scale out with cluster/replicas. "Profile, find the bottleneck, fix the top one, repeat."
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: One endpoint does heavy CPU work (e.g. PDF/report generation) and slows everything.
-----------------------------------------------------------------------------------------------
Answer -> This is the classic Node trap: a CPU-heavy synchronous operation on the single thread
blocks every other request. I have three levers depending on the requirement:

  - If the user can wait for an async result: push it to a BACKGROUND JOB (BullMQ). The endpoint
    enqueues the work, returns 202 Accepted with a job/status id, and the client polls or gets
    notified (WebSocket/webhook/email) when it's done. This is exactly how I offloaded heavy work
    to Sidekiq in Rails — same pattern, BullMQ instead.
  - If it must be done IN the request: run it in a WORKER THREAD (or a worker pool like piscina)
    so the main event loop stays free.
  - If it's a distinct concern: extract a separate service sized for CPU.

  I'd also cache the result if the same report is requested repeatedly. The key insight I'd
  state: "never do heavy CPU on the main thread — it doesn't just slow that request, it stalls
  the whole process."
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: How would you process a 2GB CSV/EDI file without running out of memory?
   (this is literally my Horizon story — own it)
-----------------------------------------------------------------------------------------------
Answer -> Stream it, don't load it. I did exactly this kind of optimization on Horizon (2M EDI
records, 24h -> 6min).

  - createReadStream(file).pipe(parser) so the file flows through in chunks; memory stays flat.
    Backpressure pauses the read when downstream can't keep up.
  - Accumulate records into BATCHES (a few thousand) and write each batch with a single BULK
    operation: bulkWrite (Mongo) / bulkCreate / createMany (SQL), with ordered:false so an
    error on one row doesn't stop the batch and the driver parallelizes.
  - Ensure an INDEX on the upsert key, or every upsert is a full scan.
  - Run the whole thing in a BullMQ WORKER so it doesn't tie up the web process, with progress
    tracking and the ability to resume.
  - Validate per-record and collect errors to a report instead of failing the whole import.

  "The three levers are streaming (constant memory), batching, and bulk DB ops — the same ones
   that gave me the 99.6% improvement in Rails, just expressed with Node streams + bulkWrite."
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: A third-party API you call has a strict rate limit and is sometimes down.
   How do you build a reliable integration? (my WhatsApp/Meta API experience)
-----------------------------------------------------------------------------------------------
Answer -> I make the integration asynchronous and fault-tolerant:

  - Put the calls behind a BullMQ queue with a LIMITER (e.g. max N/sec) so I never exceed their
    rate limit, even under a spike. (BullMQ has a built-in limiter.)
  - RETRIES with exponential backoff + jitter for transient failures (429/5xx/timeouts);
    respect Retry-After headers if provided.
  - TIMEOUTS on every call + a CIRCUIT BREAKER so when they're down I stop hammering them and
    fail fast / queue for later instead of piling up.
  - IDEMPOTENCY: keyed on a stable id (message id) so retries don't double-send — critical since
    queues are at-least-once.
  - DLQ for permanently-failed jobs + alerting, so nothing is silently lost.
  - For incoming webhooks: ACK fast (return 200 quickly — Meta requires it), then process
    asynchronously off the queue.

  "This is the exact fault-tolerant pipeline I built for the WhatsApp Cloud API with Sidekiq —
   rate-limited workers, retries, idempotent handlers — and Node is actually a better fit
   because webhook ingestion and API I/O are I/O-bound."
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: How do you prevent the same job/payment from running twice?
-----------------------------------------------------------------------------------------------
Answer -> Idempotency, because queues guarantee at-least-once delivery (a job can run more than
once after a retry or a worker crash mid-job).

  - Use a stable IDEMPOTENCY KEY for the operation (e.g. orderId, or a client-supplied key for
    payments). Store processed keys; before acting, check "already processed?" and short-circuit.
  - Prefer UPSERTS and unique constraints so a duplicate insert is a no-op/conflict, not a dupe.
  - For payments: pass an idempotency key to the payment provider (Razorpay/Stripe support this)
    so even a duplicated charge request results in a single charge.
  - Use a stable BullMQ jobId so the same logical job isn't even enqueued twice.

  "I design every job and every money-moving operation to be safely re-runnable — that's the
   only correct assumption when delivery is at-least-once."
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: How do you scale a Node app to use all 8 CPU cores and handle more traffic?
-----------------------------------------------------------------------------------------------
Answer -> One Node process uses one core, so I scale on multiple axes:
  - Across cores: cluster mode via PM2 (`pm2 start -i max`) or k8s replicas — multiple
    processes behind a load balancer.
  - Keep instances STATELESS: sessions/cache/queues live in shared Redis, not process memory,
    so any instance can serve any request (and so cluster workers stay consistent).
  - Protect the event loop: CPU-heavy work -> worker_threads or a BullMQ worker tier.
  - Scale the DB appropriately: connection pooling sized to total instances, read replicas /
    caching for read-heavy load, indexes.
  - Horizontally scale the worker tier separately from the web tier (they have different load).
  This is the same stateless-web-tier + shared-Redis + separate-worker-tier architecture I'd
  use in Rails — just cluster/PM2 instead of Puma workers.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Users report intermittent "stale data" right after they update something.
-----------------------------------------------------------------------------------------------
Answer -> This smells like a CACHING or REPLICATION lag issue.
  - Caching: a write updated the DB but didn't invalidate the cached value, so reads serve the
    old one. Fix: pair every write with cache invalidation (delete/refresh the key), use short
    TTLs, or version/namespace keys. For lists/aggregates, prefer short TTLs or explicit busts.
  - Read replicas: if reads go to a replica, replication lag means a just-written value isn't
    there yet. Fix: read-your-writes by routing the immediate post-write read to the primary,
    or wait for replication.
  - Multiple instances with IN-PROCESS caches: each instance has its own stale copy. Fix: move
    the cache to shared Redis so invalidation is global.
  - Eventual consistency in a distributed/event-driven flow: set expectations + reconcile.
  I'd reproduce, check the cache/replica path, and fix the invalidation or routing accordingly.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: Your process keeps crashing in production. How do you make it resilient?
-----------------------------------------------------------------------------------------------
Answer ->
  - First, find WHY: structured logs + an error tracker (Sentry) to capture the stack. Hook
    process.on('uncaughtException') and 'unhandledRejection') to LOG fatally, then exit cleanly.
  - Don't try to "keep running" after an uncaughtException — the state may be corrupt; I crash
    and let a process manager (PM2/k8s/systemd) restart a fresh process. "Let it crash" + auto-
    restart is more reliable than limping along.
  - Add GRACEFUL SHUTDOWN on SIGTERM (finish in-flight requests/jobs, close DB/Redis) so deploys
    and restarts don't drop work.
  - Fix the root cause: usually an unhandled rejection (missing await/.catch), an unhandled
    stream 'error' event, or a memory leak triggering OOM. As a safety net, PM2
    max_memory_restart / k8s memory limits recycle leaking processes.
  - Harden inputs (validation at the edge) so bad data becomes a clean 4xx instead of a crash.
*/

/*
-----------------------------------------------------------------------------------------------
Question 9: How do you do a zero-downtime deploy?
-----------------------------------------------------------------------------------------------
Answer ->
  - Run MULTIPLE instances behind a load balancer and do a ROLLING deploy: take one instance out
    of rotation, deploy it, health-check it, put it back, repeat (PM2 reload / k8s rolling update).
  - GRACEFUL SHUTDOWN on each instance: on SIGTERM stop accepting new connections, drain
    in-flight requests, finish/return current jobs, then exit — so no request is dropped mid-deploy.
  - HEALTH + READINESS probes so the LB only routes to instances that are actually ready.
  - BACKWARD-COMPATIBLE DB MIGRATIONS: expand-then-contract (add nullable column / new table
    first, deploy code that handles both old+new, backfill, then later remove the old) so old and
    new code versions can run simultaneously during the rollout. (Same migration discipline as
    Rails — never ship a migration that breaks the currently-running code.)
  - Feature flags for risky changes; quick rollback path.
*/

/*
-----------------------------------------------------------------------------------------------
Question 10: How do you keep secrets and config out of code? (env-specific config)
-----------------------------------------------------------------------------------------------
Answer -> Config that varies by environment goes in environment variables, not code.
  - Locally: a .env file loaded by dotenv, NEVER committed (.gitignore it); commit a
    .env.example with keys but no values.
  - Production: a secrets manager (AWS Secrets Manager/SSM, Vault, k8s secrets) injected as env
    vars at runtime — not files on disk.
  - VALIDATE env at startup with a schema (Zod/envalid) so a missing/invalid var fails fast at
    boot with a clear message, not at 2am in a request.
  - Centralize: one config module reads process.env once and exports typed values; the rest of
    the app imports config, never raw process.env.
  - Never log secrets. This is the Node version of Rails credentials.yml.enc / ENV discipline.
*/

/*
-----------------------------------------------------------------------------------------------
Question 11: Two requests update the same record at once — how do you avoid lost updates?
-----------------------------------------------------------------------------------------------
Answer -> A race condition / concurrency problem. Options depending on the case:
  - OPTIMISTIC LOCKING: a version column; on update, `WHERE id = ? AND version = ?` and bump
    version. If 0 rows updated, someone else changed it -> reject/retry (409 Conflict). Great for
    low-contention web flows. (ActiveRecord had this with lock_version; Sequelize/Prisma can too.)
  - PESSIMISTIC LOCKING: SELECT ... FOR UPDATE inside a transaction to lock the row while you
    work. Use for high-contention critical sections (inventory, balances). Keep the tx short.
  - ATOMIC DB OPERATIONS: push the logic into the DB — `UPDATE accounts SET balance =
    balance - 100 WHERE ...` or Mongo's $inc — so there's no read-modify-write race at all.
  - For distributed coordination across instances: a Redis distributed lock (Redlock), used
    carefully.
  I'd pick atomic operations when possible (simplest + safe), optimistic locking for typical web
  edits, pessimistic for hot contended resources.
*/

/*
-----------------------------------------------------------------------------------------------
Question 12: Walk me through what happens from `node server.js` to serving a request.
-----------------------------------------------------------------------------------------------
Answer ->
  1. Node starts, V8 initializes, libuv sets up the event loop and thread pool.
  2. It runs server.js top-to-bottom (require modules — synchronous + cached, connect to DB/
     Redis, build the Express app, register middleware + routes).
  3. app.listen opens a listening socket; that open handle keeps the process alive.
  4. The loop idles in the POLL phase waiting for I/O.
  5. A request arrives -> libuv/OS notifies the loop -> the HTTP server's callback runs.
  6. Express runs the request through the middleware chain -> router -> route handler.
  7. The handler `await`s I/O (DB query); await YIELDS control back to the loop, which serves
     other requests while the DB works (this is how one thread handles high concurrency).
  8. The DB responds -> the callback is queued -> the loop drains microtasks then resumes the
     handler's continuation -> it sends res.json -> response goes back to the client.
  9. On SIGTERM, graceful shutdown stops accepting connections, drains, and exits.
  Telling this end-to-end story (especially the "await yields the loop" part) signals real
  understanding, not memorized facts.
*/

/*
-----------------------------------------------------------------------------------------------
Question 13: Coming from Rails — what was the hardest mental shift, and how do you handle it?
   (a likely behavioral/transition question — have an honest, strong answer)
-----------------------------------------------------------------------------------------------
Answer -> "The biggest shift was the concurrency model. In Rails I could write blocking code
freely because each request had its own worker/thread. In Node there's a single event loop, so
a blocking or CPU-heavy operation freezes every user, not just one request. So I retrained myself
to think 'never block the loop' — keep I/O async, push CPU-heavy work to worker_threads or
BullMQ, and run independent I/O in parallel with Promise.all. The second shift was that Express
gives no structure, unlike Rails' conventions — so I deliberately impose a layered architecture
(controller -> service -> repository) and reach for NestJS when I want Rails-style opinions. And
third, I leaned into TypeScript to get the safety Rails gave me through convention and tests.
Everything else — REST/GraphQL APIs, Redis-backed background jobs, MongoDB, ORMs, N+1, caching,
testing discipline, Docker/CI-CD — transferred almost directly from my Rails experience."
*/

module.exports = {};
