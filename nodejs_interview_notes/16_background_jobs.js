/*
===============================================================================================
                       BACKGROUND JOBS (BullMQ / Bull / Agenda)
===============================================================================================
This is almost a 1:1 with my Sidekiq experience. Everything I know about queues, retries,
idempotency, dead jobs, and Redis carries over. BullMQ is the modern Sidekiq of Node.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: Why background jobs in Node? (same reason as Rails, plus an extra one)
-----------------------------------------------------------------------------------------------
Answer -> Move slow/heavy/unreliable work OUT of the request-response cycle so the API responds
fast: sending emails, processing uploads, calling third-party APIs, generating reports, bulk
imports, webhooks.

  Two reasons in Node specifically:
   1. Same as Rails: don't make the user wait; improve responsiveness; add retries/reliability.
   2. EXTRA (Node-specific): the event loop is single-threaded, so CPU-heavy work in a request
      blocks EVERY user. Offloading to a separate worker process protects the web process.

  In a Node interview I tie this straight to my resume: "In Rails I offloaded bulk imports,
  webhook processing, and notifications to Sidekiq, cutting request latency ~20%. In Node I do
  the same with BullMQ on Redis — same architecture, same Redis."
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: The library landscape
-----------------------------------------------------------------------------------------------
Answer ->
  - BullMQ   -> the modern standard. Redis-backed, robust, supports retries, rate limiting,
                delayed/repeatable jobs, priorities, flows (job dependencies). My default.
  - Bull     -> BullMQ's predecessor; still common in older apps.
  - Agenda   -> MongoDB-backed scheduler (good if you're already on Mongo and want cron-like jobs).
  - bee-queue-> lightweight, high-throughput, simpler feature set.
  - Kafka/RabbitMQ -> message brokers (not job queues per se) for cross-service event streaming
                at scale — different tool, see 25_microservices.js.

  Sidekiq -> BullMQ is the cleanest mental mapping (both Redis-backed worker queues).
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: BullMQ — Queue (producer) and Worker (consumer)
-----------------------------------------------------------------------------------------------
Answer -> Architecture mirrors Sidekiq exactly: producer pushes jobs to Redis, a separate
worker PROCESS pulls and runs them.

  // queue.js — the PRODUCER (used by your web/API process)
  const { Queue } = require('bullmq');
  const connection = { host: '127.0.0.1', port: 6379 };
  const emailQueue = new Queue('email', { connection });

  // enqueue a job (Sidekiq's perform_async)
  await emailQueue.add('welcome', { userId: 42 }, {
    attempts: 5,                                   // retry up to 5 times
    backoff: { type: 'exponential', delay: 1000 }, // 1s, 2s, 4s, ...
    removeOnComplete: 1000,                         // keep last 1000 completed (trim Redis)
    removeOnFail: 5000,
  });

  // worker.js — the CONSUMER (run as a SEPARATE process, like `sidekiq`)
  const { Worker } = require('bullmq');
  const worker = new Worker('email', async (job) => {
    if (job.name === 'welcome') {
      await sendWelcomeEmail(job.data.userId);
    }
  }, { connection, concurrency: 10 });             // process 10 jobs at once

  worker.on('completed', (job) => logger.info(`job ${job.id} done`));
  worker.on('failed', (job, err) => logger.error(`job ${job?.id} failed`, err));

  KEY POINT: run the worker as its OWN process (separate from the web server), so heavy job
  work never blocks the API's event loop. In production: `node worker.js` under PM2 / a
  separate container / k8s deployment. Same separation as a Sidekiq process next to Puma.
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: Retries, backoff, and the Dead Letter Queue (failed jobs)
-----------------------------------------------------------------------------------------------
Answer -> Same reliability concerns as Sidekiq:
  - attempts + backoff: auto-retry transient failures (network blips, API 503s) with
    exponential backoff so you don't hammer a struggling dependency.
  - When attempts are exhausted, the job moves to the FAILED set (BullMQ's "dead" jobs) — the
    Dead Letter Queue concept. You inspect/retry them via Bull Board (the Sidekiq dashboard
    equivalent) or programmatically.
  - Custom backoff strategies and per-job options are supported.

  // manual/strategic retry of failed jobs
  const failed = await emailQueue.getFailed();
  for (const job of failed) await job.retry();
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: IDEMPOTENCY — the single most important job concept
-----------------------------------------------------------------------------------------------
Answer -> Because jobs RETRY (and can occasionally run more than once — "at-least-once"
delivery), every job must be IDEMPOTENT: running it twice has the same effect as running it
once. Otherwise retries cause double emails, double charges, duplicate records.

  Techniques (same as my Sidekiq notes):
   - Use a stable jobId / dedup key so the same logical job isn't enqueued twice:
       emailQueue.add('welcome', data, { jobId: `welcome:${userId}` });  // de-dupes
   - Guard inside the handler: check "already done?" before acting (e.g. unique constraint,
     a processed-flag, an idempotency key row).
   - Make DB writes upserts, not blind inserts.
   - For payments: an idempotency key passed to the payment provider so a retry doesn't double-charge.

  INTERVIEW SOUNDBITE: "I design every job to be idempotent because queues guarantee
  at-least-once, not exactly-once, delivery. A retry must never double-charge or duplicate —
  exactly the discipline I applied to Sidekiq webhook and notification pipelines."
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Rate limiting & the WhatsApp project story
-----------------------------------------------------------------------------------------------
Answer -> BullMQ has a built-in limiter — perfect for respecting third-party API limits (Meta
WhatsApp Cloud API), which is exactly my resume project.

  const worker = new Worker('whatsapp', sendMessage, {
    connection,
    limiter: { max: 80, duration: 1000 },   // at most 80 jobs per second (API rate limit)
  });

  My WhatsApp answer for a Node interview:
   "I'd receive webhooks on a thin Express endpoint, validate + ACK fast (Meta requires a
    quick 200), and push each event onto a BullMQ queue. A separate worker processes them with
    a limiter to respect Meta's rate limits, with attempts + exponential backoff for transient
    failures, and idempotent handlers keyed on the message id so duplicate webhook deliveries
    don't double-process. Same fault-tolerant pipeline I built with Sidekiq — Node is actually
    a better fit because webhook ingestion is I/O-bound, Node's sweet spot."
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Scheduled / repeatable / delayed jobs (cron equivalent)
-----------------------------------------------------------------------------------------------
Answer ->
  // delayed job — run 1 hour from now
  await queue.add('reminder', data, { delay: 60 * 60 * 1000 });

  // repeatable job — cron-like (the sidekiq-cron / whenever equivalent)
  await queue.add('nightly-report', {}, { repeat: { pattern: '0 2 * * *' } }); // 2am daily

  For simple in-process scheduling without a queue, `node-cron` exists, but for anything that
  must survive restarts / scale across instances, use a Redis-backed repeatable job so only one
  instance runs it.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: Common job-system problems (mirror of my Sidekiq notes)
-----------------------------------------------------------------------------------------------
Answer ->
  - Duplicate execution from retries        -> idempotency (above).
  - Memory growth in long-running workers    -> process jobs in batches, avoid accumulating
                                                data in memory, restart workers periodically.
  - Redis connection exhaustion              -> reuse a shared ioredis connection; size pools;
                                                BullMQ wants `maxRetriesPerRequest: null`.
  - Poison messages (a job that always fails)-> cap attempts, route to failed set, alert.
  - Job ordering                             -> queues are roughly FIFO but concurrency breaks
                                                strict order; use BullMQ flows / groups if order matters.
  - Long jobs blocking shutdown              -> graceful shutdown: worker.close() lets the
                                                current job finish before exit (see 08_error_handling.js).
  - Observability                            -> Bull Board UI + metrics on queue depth, failure
                                                rate, processing time (queue depth spiking = workers
                                                can't keep up -> scale workers).
*/

module.exports = {};
