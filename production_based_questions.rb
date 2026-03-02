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

--------------------------------------------------------------------------------------------------------------
Question 8: What happens when you run rails assets:precompile in production?
Answer: When you run RAILS_ENV=production rails assets:precompile, Rails first loads the production environment. 
Then, depending on your setup, Sprockets in older Rails versions or Propshaft in Rails 7+, it compiles your assets like CSS, JavaScript, and images.

During this process, Rails generates fingerprinted, digested files for example, application-abc123.css or application-def456.js and stores them in the public/assets directory. 
The reason for digesting is cache busting: if an asset changes, its hash changes, so the browser knows to download the new version rather than using a cached one.

A few more points: 
  if you are using Importmap, there is no bundling. 
  if you are using Webpacker or ESBuild, JavaScript gets bundled separately. 
  Also, in production, it is recommended to set config.assets.compile = false, so Rails does not try to compile assets at runtime, which improves performance.

--------------------------------------------------------------------------------------------------------------
Question 9: Difference Between Puma and Passenger?
Answer: So, the main difference between Puma and Passenger is in how they handle requests and how they are deployed.

Puma is a multi-threaded application server and is the default Rails server. It works really well on platforms like Heroku, but in production, it usually needs a reverse proxy like Nginx. 
Puma is great for high-concurrency applications because you can configure multiple workers and threads,
for example, 4 workers with 5 threads each, giving you 20 concurrent requests.

Passenger, on the other hand, is more of an integrated app server and web server solution. It is easier to set up on a traditional VPS(Virtual private network) because it handles both serving the web and running the app.

So, if your app has high concurrency, Puma with properly configured workers and threads generally gives better performance. 
Passenger is simpler for smaller setups or VPS hosting, but Puma gives you more fine-grained control for scaling Rails apps.

--------------------------------------------------------------------------------------------------------------
Question 10: How do you handle database migrations in production?
Answer: In production, I handle database migrations very carefully to avoid downtime or breaking running processes. My main principle is to always follow a backward-compatible and zero-downtime deployment strategy.

First, I deploy code that works with both the old schema and the new schema. I never make destructive changes immediately.

For example, if I need to replace a column, I first add the new column using a migration. I deploy that safely without removing anything.

Then I update the application code to write to both columns temporarily. This ensures that both old and new versions of the application can function correctly.

If the table is large, I avoid doing heavy data updates inside the migration because that can lock the table. Instead, I use a background job, usually with Sidekiq, to backfill data in batches using find_each.

Once the data is consistent and stable, I update the code to read only from the new column.

Only in a later deploy — after confirming that no running servers or Sidekiq workers are using the old column — I remove the old column with a separate migration.

I avoid running remove_column in the same deployment where the column is still referenced, because that can immediately crash background jobs or web processes.

For PostgreSQL, I also use safe techniques like add_index with algorithm: :concurrently and disable DDL transactions when required to prevent long table locks.

So overall, my approach is: make migrations backward-compatible, deploy in small safe steps, avoid long locks, and never combine schema deletion with active code usage.

--------------------------------------------------------------------------------------------------------------
Question 11: What causes 502 Bad Gateway in Rails deployment?
Answer: Usually is happens due to:
          Puma not running
          Wrong socket path
          Nginx misconfigured
          Timeout issue

--------------------------------------------------------------------------------------------------------------
Question 12: What if user refreshes page after payment?
Answer:We do not depend on frontend redirect.
We check payment status from database, which is updated only after webhook verification.

--------------------------------------------------------------------------------------------------------------
Question 13: What are the Real-World payment Failure Cases? How you would handle them?
Answer: In real-world payment integrations, I never assume the payment flow is perfect. There are several failure scenarios we must handle carefully.

  For example:
    One common case is a gateway timeout, but the money actually gets deducted. In this situation, the client may see a failure message, but the payment provider may have already processed the transaction.

    Another scenario is duplicate webhooks. Sometimes the payment gateway sends the same webhook multiple times. If our system is not idempotent, we may mark the order as paid twice or create duplicate records.

    A third scenario is payment succeeded, but the database crashes before we save the transaction status. So the payment provider thinks it is successful, but our system shows it as pending.

    Also, there can be a network error after capture — for example, the capture API succeeds, but the response does not reach our server.

  How I handle these cases:
    First, I always implement idempotent updates.

    That means before updating an order to 'paid', I check if it is already marked as paid. I also store a unique payment_id from the gateway and add a unique DB constraint to prevent duplicates.

    Second, I rely on webhooks instead of trusting only frontend responses. Webhooks are treated as the source of truth.

    Third, I implement a background reconciliation job using Sidekiq. This job periodically checks all pending or uncertain transactions and calls the payment providers status API to verify the final state.

    For example, if an order is in 'processing' state for more than 10 minutes, the reconciliation job fetches its real status from the provider and updates the database accordingly.

    Additionally, I sometimes implement status polling for critical flows, especially when webhooks are delayed.

  So overall, my strategy is:
    Never trust client response alone
    Make updates idempotent
    Use webhooks as source of truth
    Add background reconciliation for safety
    Use polling when necessary

  Because in payment systems, consistency and correctness are more important than speed.

--------------------------------------------------------------------------------------------------------------
Question 14: How do you improve Rails performance using NGINX?
Answer: In production, improving Rails performance using NGINX mainly means reducing load on the Rails application server and optimizing how requests are handled before they even reach Rails.

I usually focus on five key optimizations.
  1:First, I enable gzip compression in NGINX.
    This reduces the size of responses like HTML, CSS, JavaScript, and JSON before sending them to the client.
    So instead of sending a 500KB response, we might send 80-100 KB.
    That reduces bandwidth usage and improves response time, especially for API-heavy Rails apps.”
    Example config conceptually:
      gzip on;
      gzip_types text/plain application/json text/css application/javascript;

  2:Second, I configure NGINX to serve static assets directly and cache them aggressively.
    In Rails production, assets are fingerprinted — for example: application-abc123.js
    Since the filename changes when the content changes, we can safely set a long expiration time.
    Example:
      location ~ ^/assets/ {
        expires 1y;
        add_header Cache-Control public;
      }
    This prevents repeated requests from hitting Rails entirely.

  3:Third, I tune worker processes and worker connections to optimize the worker_connections.
    NGINX is event-driven, so it can handle thousands of concurrent connections efficiently — but only if worker_connections is configured properly.
    If traffic increases and this is set too low, users may experience connection drops.”
    Example:
      worker_processes auto;
      events {
        worker_connections 10240;
      }

    This ensures NGINX can handle high concurrency before requests even reach Puma or Unicorn.

  4:Fourth, I enable HTTP/2.
    HTTP/2 allows multiplexing — meaning multiple requests can be sent over a single TCP connection.
    This improves performance significantly for Rails apps with many assets, like CSS, JS, fonts, etc.
    Example:
      listen 443 ssl http2;
    It reduces latency and improves page load speed.

  5:Fifth, I configure keepalive_timeout.
    This controls how long a connection stays open.
    If it is too low, clients reconnect frequently — which adds overhead.
    If it is too high, connections remain open unnecessarily and consume memory.
    So I set it to a balanced value like 30-65 seconds depending on traffic.
    Example:
      keepalive_timeout 65;

--------------------------------------------------------------------------------------------------------------
Question 15: What is reverse proxy - NGINX?
Answer: A reverse proxy sits between client and application servers. It receives client requests and forwards them to backend servers. It improves security, scalability, and allows load balancing.

--------------------------------------------------------------------------------------------------------------
Question 16: Why use Nginx in Rails production?
Answer:
    Handles high concurrency (event-driven architecture)
    Serves static assets efficiently
    SSL termination
    Load balancing
    Protects Rails app from direct exposure
  
--------------------------------------------------------------------------------------------------------------
Question 17: How does Nginx handle concurrency?
Answer: Event-driven, non-blocking architecture
        Unlike Apache (process-based), Nginx can handle thousands of connections with low memory usage
  
--------------------------------------------------------------------------------------------------------------
Question 18: Where is Nginx config file located?
Answer: Most Common location is 
        /etc/nginx/nginx.conf
        /etc/nginx/sites-available/
        /etc/nginx/sites-enabled/

--------------------------------------------------------------------------------------------------------------
Question 19: How to restart Nginx?
Answer: sudo systemctl restart nginx
        sudo service nginx restart