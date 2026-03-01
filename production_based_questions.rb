Question 1: What is a memory leak in Rails? How do you identify and fix it?
Answer: A memory leak happens when objects are allocated in memory but not released, so memory usage keeps increasing over time.
In Rails, this usually happens due to large object retention, global variables, class-level caching, or long-running background jobs.

To identify memory leaks, I monitor memory usage using tools like top, htop, or NewRelic. If memory keeps growing without stabilizing, it is suspicious.

I also use gems like memory_profiler, derailed_benchmarks, or stackprof to analyze object allocation.

To fix it, I check for:
  Unnecessary caching of large objects
  Not clearing arrays or hashes
  Large ActiveRecord queries loading full objects instead of using pluck
  Background jobs accumulating data in memory

In production, I also configure Puma workers properly so that memory resets after worker restart.

--------------------------------------------------------------------------------------------------------------
Question 2: How does Puma help prevent memory leaks?
Answer: Puma runs multiple worker processes.
If one worker consumes too much memory due to a leak, restarting that worker frees the memory.

So even if there is a small leak, it does not crash the entire application.
We can also configure worker_timeout or use phased restart to manage memory growth.

--------------------------------------------------------------------------------------------------------------
Question 3: What is Redis and why is it used in Rails?
Answer: Redis is an in-memory key-value data store.
It is extremely fast because it stores data in RAM.

In Rails, we use Redis mainly for:
  Caching
  Session storage
  Background job queue (Sidekiq)
  Rate limiting

Since Redis is in-memory, read/write operations are very fast compared to database queries.

--------------------------------------------------------------------------------------------------------------
Question 4: Why is Redis faster than PostgreSQL?
Answer: PostgreSQL stores data on disk and uses complex query planning.
Redis stores data in memory and follows a simple key-value structure.
So Redis avoids disk I/O and complex joins, making it much faster for simple read/write operations.

--------------------------------------------------------------------------------------------------------------
Question 5: How does Sidekiq work internally?
Answer: Sidekiq uses Redis as a job queue.
When we call perform_async, the job is serialized into JSON and pushed into Redis.
Sidekiq workers pull jobs from Redis and execute them.

It is multi-threaded, so it can process multiple jobs concurrently within the same process.

--------------------------------------------------------------------------------------------------------------
Question 6: What problems can happen with Sidekiq?
Answer: Some common issues are:
Job retries causing duplicate execution
Memory growth in long-running workers
Dead jobs in retry queue
Redis connection pool exhaustion

To handle this, we:
  Make jobs idempotent
  Configure retry limits
  Monitor queues regularly

--------------------------------------------------------------------------------------------------------------
Question 7: Why does CPU spike in a Rails application?
Answer: CPU spike usually happens due to high computation or blocking operations.

Common causes in Rails are:
  N+1 queries causing excessive database calls
  Infinite loops or heavy Ruby computation
  Large JSON rendering
  Missing indexes in database
  Too many concurrent Sidekiq jobs
  High traffic without enough Puma workers

When CPU spikes, I:
  Check logs for slow endpoints
  Use EXPLAIN ANALYZE for slow queries
  Monitor Sidekiq queue
  Profile code using stackprof

Then I optimize queries, add indexes, or move heavy work to background jobs.

--------------------------------------------------------------------------------------------------------------
Question 8: If memory is stable but CPU is 100% , what could be the issue?
Answer: If memory is stable but CPU is high, it means computation is heavy rather than object accumulation.
So likely:
  Inefficient loops
  Sorting large arrays in Ruby instead of database
  Expensive JSON serialization
  Regex-heavy processing

I would profile CPU using stackprof or rbspy to identify hot methods.
