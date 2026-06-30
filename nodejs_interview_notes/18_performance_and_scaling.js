/*
===============================================================================================
                       PERFORMANCE & SCALING (cluster, worker_threads, PM2)
===============================================================================================
This is where Node's single-threaded model forces different answers than Rails. "How do you
use all CPU cores?" and "how do you handle CPU-bound work?" are near-guaranteed questions.
*/

/*
-----------------------------------------------------------------------------------------------
Question 1: The core problem — one process uses ONE CPU core
-----------------------------------------------------------------------------------------------
Answer -> A single Node process runs JS on one thread, so it uses ONE CPU core no matter how
many the machine has. On an 8-core box, a single Node process leaves 7 cores idle. To use all
cores you run MULTIPLE Node processes. Two built-in tools + the production manager:
  - cluster module        -> fork N worker processes that SHARE the same server port.
  - worker_threads        -> real threads inside one process for CPU-bound JS.
  - PM2                    -> a process manager that runs cluster mode + restarts + monitoring.
  Plus horizontal scaling: multiple machines/containers behind a load balancer.
*/

/*
-----------------------------------------------------------------------------------------------
Question 2: The cluster module (scale across cores — the Puma-workers equivalent)
-----------------------------------------------------------------------------------------------
Answer -> cluster forks the process into a master + N workers. The OS/master load-balances
incoming connections across workers, all sharing one listening port. Each worker is a full
Node process with its own event loop and memory.

  const cluster = require('cluster');
  const os = require('os');

  if (cluster.isPrimary) {
    const cpus = os.cpus().length;
    for (let i = 0; i < cpus; i++) cluster.fork();          // one worker per core
    cluster.on('exit', (worker) => {
      console.log(`worker ${worker.process.pid} died, restarting`);
      cluster.fork();                                         // self-healing
    });
  } else {
    require('./app').listen(3000);                            // each worker runs the server
  }

  Conceptually like Puma running multiple worker PROCESSES. Caveats:
   - Workers DON'T share memory -> in-process cache/state must move to Redis (shared).
   - Sticky sessions needed if using in-memory sessions or WebSockets (or use Redis adapter).
   - In practice you let PM2 or Kubernetes do this instead of hand-rolling cluster.
*/

/*
-----------------------------------------------------------------------------------------------
Question 3: worker_threads (for CPU-bound work — the real fix for blocking)
-----------------------------------------------------------------------------------------------
Answer -> cluster is for handling more REQUESTS; worker_threads is for running CPU-HEAVY JS
off the main thread so it doesn't block the event loop. Use it for image processing, heavy
crypto, big computations, parsing huge files in memory.

  // main.js
  const { Worker } = require('worker_threads');
  function runHeavyTask(data) {
    return new Promise((resolve, reject) => {
      const worker = new Worker('./heavy-worker.js', { workerData: data });
      worker.on('message', resolve);
      worker.on('error', reject);
      worker.on('exit', (code) => { if (code !== 0) reject(new Error(`exit ${code}`)); });
    });
  }

  // heavy-worker.js
  const { parentPort, workerData } = require('worker_threads');
  const result = doExpensiveComputation(workerData);   // runs on its OWN thread
  parentPort.postMessage(result);

  Notes:
   - Threads communicate by message passing (postMessage), not shared variables (mostly);
     SharedArrayBuffer allows true shared memory for advanced cases.
   - Spawning a worker has overhead -> use a POOL (e.g. piscina) for frequent tasks.
   - Alternative: offload to a BullMQ job (a separate worker process) if it doesn't need an
     immediate in-request result. For request-time CPU work, worker_threads; for deferred,
     a job queue.

  INTERVIEW SOUNDBITE: "cluster scales me across cores for more concurrent REQUESTS;
  worker_threads move CPU-heavy work off the event loop so one slow computation doesn't freeze
  every connection. For deferred heavy work I'd use a BullMQ worker instead — the Sidekiq move."
*/

/*
-----------------------------------------------------------------------------------------------
Question 4: PM2 (production process manager)
-----------------------------------------------------------------------------------------------
Answer -> PM2 is the standard way to run Node in production (when not on k8s). It gives you:
  - Cluster mode without writing cluster code:  pm2 start app.js -i max   (-i max = one per core)
  - Auto-restart on crash, zero-downtime reloads:  pm2 reload app
  - Log management, monitoring (pm2 monit), startup scripts (survive server reboot).
  - Memory-limit restarts:  pm2 start app.js --max-memory-restart 500M  (mitigates leaks —
    the Puma-worker-restart trick from my Rails notes).

  ecosystem.config.js:
    module.exports = { apps: [{ name: 'api', script: 'dist/server.js', instances: 'max',
      exec_mode: 'cluster', max_memory_restart: '500M', env: { NODE_ENV: 'production' } }] };

  In containerized setups (Docker/k8s), you often run ONE Node process per container and let
  k8s scale replicas + restart — k8s plays PM2's role. Know both stories.
*/

/*
-----------------------------------------------------------------------------------------------
Question 5: Horizontal scaling & statelessness
-----------------------------------------------------------------------------------------------
Answer -> To scale beyond one machine, run many stateless instances behind a load balancer
(Nginx, ALB, k8s Service). "Stateless" is the key requirement:
  - No in-memory sessions/cache that other instances can't see -> push state to Redis/DB.
  - Sticky sessions only if unavoidable (WebSockets); prefer a Redis pub/sub adapter so any
    instance can serve any client.
  - Background jobs run in their own worker deployment, pulling from the shared Redis queue.
  This mirrors how I'd scale a Rails app: stateless web tier + shared Redis/DB + separate
  worker tier. Same architecture, different runtime.
*/

/*
-----------------------------------------------------------------------------------------------
Question 6: Finding & fixing performance problems
-----------------------------------------------------------------------------------------------
Answer -> "Measure before optimizing" (same discipline as my Rails perf notes).

  PROFILING / DIAGNOSTICS:
   - node --inspect + Chrome DevTools (CPU profile, heap snapshots).
   - clinic.js (doctor/flame/bubbleprof), 0x (flamegraphs) — find hot functions + loop blocking.
   - perf_hooks.monitorEventLoopDelay() / event-loop-lag metrics -> detect blocking.
   - APM: New Relic / Datadog / OpenTelemetry for traces, slow endpoints, DB time.
   - autocannon / k6 for load testing.

  COMMON FIXES (Node flavor of my Rails list):
   - Fix N+1 / add indexes / paginate (most wins are in the DB, same as Rails).
   - Add caching (Redis) for hot reads.
   - Never block the loop: offload CPU work to worker_threads / jobs; avoid sync APIs.
   - Run async I/O in parallel (Promise.all) instead of sequential awaits.
   - Stream large payloads instead of buffering; enable gzip (compression middleware).
   - Bound concurrency to protect the DB pool / downstreams.
   - Scale out: cluster/PM2/replicas; separate the worker tier.
   - Set keep-alive, reuse HTTP agents/connections to downstreams.
*/

/*
-----------------------------------------------------------------------------------------------
Question 7: Memory leaks in Node (the Rails-notes counterpart)
-----------------------------------------------------------------------------------------------
Answer -> Symptoms: memory grows and never plateaus; eventually OOM/crash. Common causes:
  - Unbounded in-memory caches / Maps that never evict.
  - Forgotten event listeners / timers (the EventEmitter leak warning).
  - Closures holding large objects alive; global arrays that keep growing.
  - Accumulating data in a long-running job/worker.

  DIAGNOSE: heap snapshots (Chrome DevTools), compare snapshots over time to find growing
  retained objects; process.memoryUsage(); the --max-old-space-size flag sets the heap cap.

  MITIGATE: fix the root cause; use bounded LRU caches; remove listeners; and as a safety net,
  PM2 max_memory_restart / k8s memory limits restart leaking processes — the same "restart the
  worker to reclaim memory" strategy I described for Puma + Sidekiq in Rails.
*/

/*
-----------------------------------------------------------------------------------------------
Question 8: Putting the scaling story together (one clean answer)
-----------------------------------------------------------------------------------------------
Answer ->
  "Node is single-threaded per process, so I scale on three axes. First, across CPU cores with
   cluster mode / PM2 (or k8s replicas) — multiple processes behind a load balancer, kept
   stateless with shared Redis. Second, I protect the event loop: CPU-heavy work goes to
   worker_threads for in-request needs or to a BullMQ worker tier for deferred work, so one
   heavy task never blocks all users. Third, I scale horizontally — stateless instances + a
   separate worker deployment + shared Redis/DB. And I always measure first with profiling and
   APM, because most wins are still in the database, just like in my Rails work."
*/

module.exports = {};
