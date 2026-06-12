Question 1: What is active job?
Answer: ActiveJob is a framework inside Rails that provides a unified interface for background jobs.
It is part of Rails core. It does not process jobs by itself.
ActiveJob is an abstraction layer. It needs a backend adapter like sidekiq, async, resque

ActiveJob defines how background jobs are written.
Backend adapter actually runs them.

ActiveJob → Backend adapter (sidekiq, async, resque) i.e job processor → Redis (as message queue i.e database) → workers pulls job from redis and executes them. 

In Rails, we typically use ActiveJob as an abstraction layer for background jobs. It gives us a unified interface, and then we plug in a backend adapter like Sidekiq or Resque to actually process the jobs.

We can also use Sidekiq or Resque directly without ActiveJob. The main difference is that ActiveJob provides flexibility — if we want to switch from Sidekiq to another backend later, we can do that more easily because our code is not tightly coupled to one specific library.

Using active job, we defines a job  like:
Example:
  # app/jobs/send_email_job.rb
  class SendEmailJob < ApplicationJob
    queue_as :default

    def perform(user_id)
      UserMailer.welcome(user_id).deliver_now
    end
  end

  You can then enqueue job from controller or service:
    SendEmailJob.perform_later(user.id)
  
  When using ActiveJob, we did not care about the backend as per code syntax. Code will remain same.

-------------------------------------------------------------------------------------------
Question 2: What is sidekiq?
Answer: Sidekiq is a background job processor.
It is: A separate gem
        Multi-threaded
        Uses Redis
        Extremely fast
        Production-grade

It actually:
  Pulls jobs from Redis
  Executes them in worker threads

Example: Sidekiq worker(without ActiveJob). This code will completely skip Active job.
  # app/workers/send_email_worker.rb
  class EmailWorker
    include Sidekiq::Worker
    sidekiq_options queue: :critical

    def perform(user_id)
      UserMailer.welcome(user_id).deliver_now
    end
  end

  You can then call the worker from controller or service:
    EmailWorker.perform_async(1)

--------------------------------------------------------------------------------------------------------
Question 3: What is Resque?
Answer: Resque is another background job processor for Ruby.
Like Sidekiq, it also:
  Runs jobs in background
  Uses Redis
  Processes queued tasks
  But its architecture is different from sidekiq.

Example: Resque worker(without ActiveJob). This code will completely skip Active job.
  # app/workers/send_email_worker.rb
  class SendEmailWorker
    @queue = :default

    def self.perform(user_id)
      UserMailer.welcome(user_id).deliver_now
    end
  end

You can then call the worker from controller or service:
  Resque.enqueue(SendEmailWorker, user.id)

So:
  ActiveJob → abstraction layer (Rails)
  Sidekiq → job processor
  Resque → job processor

----------------------------------------------------------------------------------------------------------
Question 4: What Is a Queue?
Answer: Queue = A named lists of pending jobs.
Think Redis list:
    critical → [job1, job2]
    default  → [job3, job4]
    mailers  → [job5]

Queues allow:
  Priority separation
  Resource isolation
  Different worker pools

----------------------------------------------------------------------------------------------------------
Question 5: What Is a Worker?
Answer: Worker = A class that defines HOW to process a job. Worker contains execution logic.
  Example:

    class SendEmailWorker
      include Sidekiq::Worker

      def perform(user_id)
        ...
      end
    end

-----------------------------------------------------------------------------------------------------------
Quesion 6: When To Use ActiveJob as abstraction layer and when to use sidekiq directly?
Answer: 
  Use ActiveJob as abstraction layer when:
  You want framework-level abstraction
  You might switch backend later (e.g., Sidekiq → Resque)
  You want Rails conventions

  Use Sidekiq directly when:
    You need advanced features
      Batches
      Middleware
      Unique jobs
      Rate limiting
      High performance tuning
      You want maximum performance
  
  Note: when we use ActiveJob as abstraction layer, then it adds: Serialization overhead, Wrapper layer, Slight performance cost
  So it effects the performance Slightly


  ActiveJob is a Rails abstraction layer for background jobs, while Sidekiq is a Redis-based, multi-threaded background job processor that actually executes those jobs. ActiveJob defines the interface; Sidekiq provides the execution engine.
-----------------------------------------------------------------------------------------------------------
Question 7: What is a process?
Answer: A process is basically a running program.
For example:
  When you start your Rails server → that is one process.
  When you open Google Chrome → that is another process.

  Each process:
    Has its own memory space
    Runs independently
    Is isolated from other processes

  If one process crashes, others usually keep running.

-----------------------------------------------------------------------------------------------------------
Question 8: What is a thread?
Answer: A thread is a smaller unit of execution inside a process.
Think of it like this:
  🧠 Process = one office building
  👩‍💻 Threads = multiple employees working inside that building

All threads share the same memory.
They work simultaneously.
They are lighter and faster than processes.

So we can say: A process is a running program with its own memory space. A thread is a lightweight unit of execution inside a process that shares memory with other threads.

-----------------------------------------------------------------------------------------------------------
Question 9: For Sidekiq when we say: “Sidekiq runs one process with multiple threads”, what does it mean?

Answer: It means:
          Only one program instance is running (one process).
          Inside that process, there are many threads.
          Each thread picks up and runs a job.
          All threads share memory.
          That is why it is fast and memory-efficient.

  Example: If Sidekiq has concurrency set to 10:
              1 process
              10 threads
              10 jobs can run at the same time

NOTE: Resque works differently:
        It starts one main process.
        For each job, it forks a new process.
        Each job runs in its own separate memory space.

      So if you have 10 jobs:
        You may have 10 different processes.
        More memory usage.
        Slower than threads.
        But better isolation.

-----------------------------------------------------------------------------------------------------------
Question 10: What is the difference between Sidekiq and Resque?
Answer: Sidekiq is multi-threaded. It runs a single process with multiple threads inside it. Because of that, it can handle many jobs concurrently within the same process. It is very fast and high performance — it can process thousands of jobs per second with relatively low memory usage.

Resque, on the other hand, is process-based. It forks a new process for each job. That means every job runs in its own separate process. This gives very strong isolation and stability — if one job crashes, it does not affect others. But it uses more memory and is generally slower compared to Sidekiq because process forking is heavier than threading.

So the key architectural difference is:
  Sidekiq uses multi-threading in a single process for performance, while Resque uses separate processes per job for better isolation.

  In most modern Rails applications, Sidekiq is preferred because of its speed and efficiency, unless strict process isolation is specifically required.

NOTE:
  In Resque, each job runs in a separate process, so if one job crashes, it does not affect others because processes are isolated and do not share memory.

  In Sidekiq, jobs run as threads inside a single process. If a job raises a normal Ruby exception, it only affects that thread and other jobs continue running. 
  However, if the entire process crashes, for example: A segmentation fault, Native extension crash, Memory corruption etc 
  then all running jobs are affected because threads share the same memory space. 

  So Resque provides stronger isolation, while Sidekiq provides better performance.

-----------------------------------------------------------------------------------------------------------
Question 11:What is Delayed Job?
Answer: Delayed Job is another background job library for Rails. So we can also use this as an adapter for active job just like sidekiq.

Unlike Sidekiq and Resque which use Redis, Delayed Job stores jobs in the database (Postgres/Mysql) using ActiveRecord. 
It is process-based and typically runs one job per worker process. It is simpler to set up but slower and less scalable compared to Sidekiq. It is suitable for small to medium applications but not ideal for high-throughput systems.
So jobs are stored in a database table called delayed_jobs.


===============================================================================================================

Question 12: In rails, How do we manage concurrency for sidekiq?
Answer: Concurrency in Sidekiq is about controlling how many jobs execute in parallel and ensuring data consistency when multiple workers operate on shared resources.

We manage concurrency at two levels:
  1:Process-Level Concurrency (Threads per Sidekiq Process)
      Sidekiq is multi-threaded.
      Each Sidekiq process runs multiple threads, and each thread processes one job at a time.

      We Configure via config/sidekiq.yml
        :concurrency: 10
        :queues:
          - critical
          - default
          - low

      Or we can just start sidekiq like:
        bundle exec sidekiq -c 10

      This means:
        10 threads
        10 jobs can run simultaneously in one process

      Production Rule of Thumb is: concurrency <= DB connection pool size
      If your DB pool is 5 and Sidekiq concurrency is 10 → you will get connection starvation.

      So, In database.yml:

        production:
          pool: 15

      Then Sidekiq concurrency should be ≤ 15

  2:You can isolate workloads by using multiple queues and dedicated workers.
    For example, if I configure:

      :queues:
        - [critical, 3]
        - [default, 2]
        - [low, 1]

      This does not mean critical gets 3 threads, default gets 2, and low gets 1.
      Instead, those numbers are weights. It means Sidekiq will check the critical queue three times as often as the low queue, and default two times as often. So this setting controls priority, not actual thread allocation.

      All threads in that Sidekiq process are shared across all queues. So if I set concurrency to 10, I have 10 threads total, and any of those threads can process jobs from any queue.

    Now, if I want true isolation — for example, I do not want long-running low-priority jobs to block critical jobs — then I do not rely only on weights.

    Instead, I run separate Sidekiq processes.
    For example:
      sidekiq -q critical -c 5
      sidekiq -q default -c 10

    In this case, I have one process dedicated only to the critical queue with 5 threads, and another process dedicated to the default queue with 10 threads.

    Now critical jobs have guaranteed resources and will not be affected even if default jobs are heavy or slow.

NOTE: Things to take care:
      Data-Level Concurrency (Preventing Race Conditions - Use Optimistic or Pessimistic locking).
      Idempotency (Your jobs must be Idempotent)

----------------------------------------------------------------------------------------------------------
Question:13 How do we run multiple sidekiq process?
Answer: A process is just an OS-level program instance. You simply start Sidekiq multiple times.
    
    1:Simplest Way
      Open multiple terminals and run:
          bundle exec sidekiq -c 10 -q default
      Then in another terminal:
          bundle exec sidekiq -c 10 -q critical

      Now you have:
        Process 1 → 10 threads
        Process 2 → 10 threads
      Total = 20 concurrent jobs

    2:Production Way — Using systemd
      Create a systemd service file:
        /etc/systemd/system/sidekiq@.service

      Example:
        [Unit]
        Description=Sidekiq Instance %i
        After=network.target

        [Service]
        Type=simple
        WorkingDirectory=/var/www/myapp
        ExecStart=/bin/bash -lc 'bundle exec sidekiq -c 10'
        Restart=always
        User=deploy

        [Install]
        WantedBy=multi-user.target

      Now you can start multiple instances:
        sudo systemctl start sidekiq@1
        sudo systemctl start sidekiq@2
        sudo systemctl start sidekiq@3
      Now you have 3 processes on one server.

    3:Using Foreman (Procfile)
      Create Procfile:
      worker1: bundle exec sidekiq -c 10
      worker2: bundle exec sidekiq -c 10
      worker3: bundle exec sidekiq -c 10

      Then run the command:
        foreman start
      This starts multiple processes.

    4:Using Docker / Kubernetes
      In Docker:
        docker-compose up --scale worker=3

      Each container = one Sidekiq process.
------------------------------------------------------------------------------------------------

Question 14: How queues work in Sidekiq? What is the lifecycle of a job in Sidekiq?

=> When you enqueue a job in Sidekiq using MyWorker.perform_async(args)

    Sidekiq serializes job JSON and pushes it to a Redis list corresponding to the queue (e.g., queue:default).
    Redis key: queue:default
    Redis Command: LPUSH queue:default <job_json>

    Queue structure in Redis: 
      queue:default → [job1_json, job2_json, job3_json]
      queue:critical → [job1_json, job2_json, job3_json]
    Each queue is a Redis List.

    In case of Scheduled/Delayed Job enqueued with: MyWorker.perform_in(5.minutes, args)
      Sidekiq uses a Redis Sorted Set to manage scheduled jobs.
      Redis Key: schedule
      Each entry in the sorted set is a job JSON with a score representing the scheduled execution time (timestamp).
      Redis Command: ZADD schedule <timestamp> <job_json>

How workers fetch jobs?
  # Sidekiq server threads continuously poll Redis using: BRPOP queue:critical queue:default queue:low timeout
  Sidekiq server threads continuously wait for jobs from Redis using the blocking BRPOP command: BRPOP queue:critical queue:default queue:low timeout
  This command blocks until a job is available in any of the specified queues. When a job is found, Redis returns the queue name and the job JSON.
  Sidekiq thread then deserializes the job JSON to get the class name and arguments.
  It instantiates the worker class and calls perform with those arguments.

  NOTE: 
    BRPOP is a blocking Redis command. When the queue is empty, the Sidekiq worker thread waits on the Redis connection instead of continuously polling the queue. 
    Redis keeps the connection open and wakes the thread immediately when a new job is pushed into any monitored queue. 
    This reduces CPU usage and unnecessary Redis requests.

Job lifecycle in Sidekiq:
  1. Enqueue: MyWorker.perform_async(args) → Job JSON pushed to Redis list (queue).
  2. Fetch: Sidekiq thread blocks on BRPOP until a job is available.
  3. Deserialize: Sidekiq thread gets job JSON, deserializes it to get class and args.
  4. Execute: Sidekiq thread calls perform on the worker instance with the args.
  5. Complete: If perform succeeds, job is removed from Redis. If it raises an exception, Sidekiq handles retries based on configuration.

------------------------------------------------------------------------------------------------

Question 15: What happens when a job fails?
  => Job is not lost. Goes to retry set (sorted set), Redis Key: retry
  Sidekiq will retry the job after a delay (exponential backoff).
  If it exceeds max retries, it goes to the Dead Job Queue (Redis List: dead).

  Note: If worker crash after Pop, job is lost. To prevent this, we can use reliable fetch (Sidekiq Pro feature) which moves the job to a processing set before execution, allowing recovery if the worker crashes.

  Flow:
    Move job → "in-progress" list
    Process job
    Delete from in-progress after success
-------------------------------------------------------------------------------------------------

Question 16: When raw data is passed instead of object in sidekiq and why?

Case 1: When using Sidekiq Directly (without ActiveJob):
  Sidekiq needs to serialize the job data to store it in Redis. It cannot store Ruby objects directly because Redis is a key-value store that only understands strings. So Sidekiq converts Ruby objects into JSON format (or another serialization format) before pushing them to Redis. When the worker fetches the job, it deserializes the JSON back into Ruby objects to execute the perform method.

  This serialization process allows Sidekiq to store complex data structures in Redis while still being able to reconstruct them when needed.

Example:
  MyWorker.perform_async(user.id)
  Here, we are passing user.id (a simple integer) instead of the entire user object. This is because:
    1: It is more efficient to serialize simple data types like integers or strings than complex objects.
    2: It avoids issues with object serialization, such as circular references or non-serializable attributes.
    3: It reduces the amount of data stored in Redis, which can improve performance and reduce memory usage.
    4: It allows for better decoupling between the job and the data layer. The worker can fetch the necessary data from the database using the ID when it executes, rather than relying on a potentially stale or large object being passed through Redis.

  But, if object is passed like,
    MyWorker.perform_async(user)
  Then Sidekiq will attempt to serialize the entire user object, which can lead to:
    Serialization errors if the object contains non-serializable attributes.
    Increased memory usage in Redis due to storing large objects.
    Potential issues with stale data if the object changes between enqueueing and execution.

Therefore, it is a best practice to pass only simple data types (like IDs) to Sidekiq jobs and let the worker fetch the necessary data from the database when it runs.

Case 2: When using ActiveJob as an abstraction layer:
  ActiveJob provides a layer of abstraction that allows you to pass Ruby objects directly to your jobs.
  It uses GlobalID to serialize and deserialize objects automatically. When you pass an ActiveRecord object (like a User instance) to an ActiveJob, it serializes it using GlobalID, which encodes the class name and the record ID. When the job is executed, ActiveJob uses GlobalID to find the record in the database and reconstruct the object.

  Example:
    SendEmailJob.perform_later(user)
  Here, we are passing the entire user object to the job.

  Under the hood, ActiveJob will serialize the user object using GlobalID, which creates a string like "gid://app/User/1" and stored in Redis(Job JSON).

  When the job runs, ActiveJob will use this GlobalID to fetch the User record with ID 1 from the database and pass it to the perform method.

  However, it is important to note that this convenience comes with some overhead due to the serialization process. If performance is a concern, especially for high-throughput jobs, it may still be better to pass simple data types (like IDs) and fetch the necessary records within the worker.