Rails Database Optimizations (Basic and general optimization. Part -1 )
=======================================================================
➤ Select Only What You Need:
    Rails by default loads all columns with SELECT *. Bad for performance when you only need 1-2 fields.
      User.select(:id, :email).where(active: true)
      SELECT "users"."id", "users"."email" FROM "users" WHERE "users"."active" = TRUE

➤ Avoid N+1 Queries Using includes, eager_load, preload

➤ Use .pluck Instead of .map(&:field)
    User.where(active: true).map(&:email) => Inefficient as it loads entire User objects just to get emails.
    User.where(active: true).pluck(:email) => Optimized

➤ Use .exists? Instead of .present? or .any?
    User.where(email: 'x@example.com').present? => Inefficient as it loads records into memory.
    User.exists?(email: 'x@example.com') => Optimized

➤ Batch Processing with .find_each / .in_batches
  🔸Slow & Memory-heavy:
      User.all.each do |user|
        process(user)
      end
    
  🔸Efficient:
      User.find_each(batch_size: 100) do |user|
        process(user)
      end

➤ Use counter_cache to Avoid Count Queries
    N+1 Count:
      user.posts.count => Executes SQL each time.

    The counter_cache (column of type int) value is stored in the parent table (i.e., the table that has has_many). Suppose:
      A User has_many posts
      A Post belongs_to a user
    So, we add the posts_count column to the users table:
      class User < ApplicationRecord
        has_many :posts
      end

      class Post < ApplicationRecord
        belongs_to :user, counter_cache: true
      end      
    Then just use:
      user.posts_count

➤ Use scoped / readonly for Security
    User.readonly.first.update(name: "New") => Avoid accidental updates
    # => ActiveRecord::ReadOnlyRecord error

➤ Use EXPLAIN ANALYZE in SQL to Detect Slow Queries
    In Rails console:
      ActiveRecord::Base.connection.execute("EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'x@example.com'")
    For a query object:
      User.where(email: 'x@example.com').explain


Database Indexing in Rails (Part - 2)
=====================================
 - Think of a database index like the index of a book — it helps find records fast without scanning the entire table.
 - Instead of searching 1 million rows, it jumps right to where the data lives.

  ╰┈➤What is EXPLAIN?
      EXPLAIN is used to see how the database executes a query.
        Example:
          EXPLAIN SELECT * FROM users WHERE email = 'a@test.com';

        It shows:
          Which index is used
          Whether it does full table scan
          Join type
          Estimated rows
          Cost

        Important Terms in result of EXPLAIN:
          Seq Scan → Full table scan (bad for large tables)
          Index Scan → Using index
          Index Only Scan → Using covering index
          Rows → Estimated rows
          Cost → Planners estimated cost

  Types of Indexes
  ----------------
  ╰┈➤ Single-Column Index
        add_index :users, :email => Add index in users table on email column.
        
        This will optimize => User.find_by(email: "a@example.com")

  ╰┈➤ Multi-Column (Composite) Index 
        A composite index (also called multi-column index) is an index created on more than one column.
        This creates a single index using more than once column.
        We use it when queries filter using multiple columns together.

        add_index :orders, [:user_id, :status] => Add index in orders table on user_id  and statsu column together.
        This will optimize => Order.where(user_id: 1, status: 'shipped')

        NOTE: In composite Index, order matters.
        Because composite index follows left-most prefix rule.
        Database can use the index only from left to right.

        Why order matters in composite index?
          Suppose index is: INDEX(email, status) then:
            WHERE email = 'a@test.com'     -> This will work and use indexing.
            WHERE email = 'a@test.com' AND status = 'active' -> This will also work and use indexing.
            But
            WHERE status = 'active' -> This will not use the indexing because composite index follows left-most prefix rule.

  ╰┈➤ Covering Index
        A covering index is an index that contains all columns required by the query, so database does NOT need to go to the actual table.

        Example:  INDEX(email, status, id)
        Query:
            SELECT id FROM users
            WHERE email = 'a@test.com' AND status = 'active';
          
          If all selected columns are inside the index then database reads only the index (faster).
          This avoids table lookup (heap lookup). Big performance improvement.

  ╰┈➤ Unique Index
        Prevents duplicate records at the DB level.
        add_index :users, :email, unique: true
    
  ╰┈➤ Partial Index
        add_index :orders, :user_id, where: "status = 'completed'"

        Only indexes completed orders → lighter & faster for certain queries.
          Order.where(user_id: 1, status: 'completed') # uses index

  ╰┈➤ Function/Expression Index (PostgreSQL only)
        add_index :users, "LOWER(email)", name: "index_users_on_lower_email"

        Now this is optimized:
        User.find_by("LOWER(email) = ?", input.downcase)
      
  ╰┈➤ Foreign Key Indexes
        Always index foreign keys:
          t.references :user, index: true, foreign_key: true
        Optimizes:
          Joins
          WHERE user_id = ?
          Eager loading

  ➤ Use EXPLAIN to Check If Index Is Used
      In Rails console:
        User.where(email: "x@x.com").explain
      Sample output:
        Index Scan using index_users_on_email on users
    
  ➤ Over-Indexing Is Dangerous
      Too many indexes will results in
       🔸Slower INSERT/UPDATE
       🔸Higher storage usage
       🔸More bloat

      🎯 Golden Rule: Index only what you query.

  ➤ How to Know What to Index
      Ask yourself:
  
        | If your query has... | You need index on... |
        | -------------------- | -------------------- |
        | WHERE condition      | the filtered columns |
        | JOIN condition       | the joining column   |
        | ORDER BY             | the sorted column    |
        | Foreign keys         | always index them    |


Transactions and Isolation Levels in Rails (Advance)
======================================================================
  ➤ These are critical concepts when multiple users hit your app at once — e.g., ticket bookings, payments, inventory updates.
  
  ➤ What Is a Transaction?
     - A transaction groups multiple database operations into one atomic unit:
     - Either all succeed or all fail — never partial. It prevents from data inconsistency!

      ActiveRecord::Base.transaction do
        user.update!(balance: user.balance - 100)
        order.update!(status: 'paid')
      end

    - If any .update! fails, none of the changes are committed.

  ➤ What Are Isolation Levels?
     - Isolation Levels are part of Database Transactions — a fundamental concept to ensure data integrity when multiple users access the database at the same time.

     - when we write:
        ActiveRecord::Base.transaction do
          user.update!(balance: user.balance - 100)
          account.update!(total: account.total + 100)
        end

        Here, we are creating a transaction — a block that should:
          🔸Complete fully (commit), or
          🔸Be undone entirely (rollback) if anything fails

        Now imagine many users do this at the same time.
         To avoid data inconsistencies (like overspending), databases isolate each transaction from others transaction using "Isolation Levels".

      - There are 4 types of Isolation Levels and there are 3 kinds of problems that may occur during concurrent transactions.

  ➤ Three kinds of problems during concurrent transactions:
     ╰┈➤ Dirty Read:
          - A transaction reads data written by another uncommitted transaction

     ╰┈➤ Non-Repeatable Read:
          - A row you read once changes if you read it again in the same transaction

     ╰┈➤ Phantom Read:
          - You run a query, and rerun it and get different rows (e.g. new rows added)
      
  ➤ Four types of Isolation Levels:
     ╰┈➤ Read Uncommitted (Lowest isolation): Rails does not use this. It is very unsafe.
          🔸Dirty Read allowed → Can read uncommitted data from others transaction.
          🔸Non-repeatable Read → Same row may change mid-transaction.
          🔸Phantom Read → Query result may change due to new inserts.

     ╰┈➤ Read Committed: (Rails default in PostgreSQL)
          🔸No Dirty Reads → Cannot see uncommitted data
          🔸Non-Repeatable Reads → A row you read may change if someone commits new data i.e by other transaction.
          🔸Phantom Read → A repeated query may return new rows.

          → You may get a different value on reload even inside the same transaction. This is non-repeatable read.
          ActiveRecord::Base.transaction do
            product = Product.find(1)
            # Suppose User B updates product price at this stage.
            product.reload # New price!
          end

          → This is Phantom read.
          ActiveRecord::Base.transaction do
            users = User.where(active: true)
            # Someone adds a new active user in parallel
            users = User.where(active: true) # New row appears: Phantom Read
          end

     ╰┈➤ Repeatable Read
          🔸No Dirty Reads → Cannot see uncommitted data
          🔸No Non-Repeatable Reads → Rows you read will not change
          🔸Phantom Read → A repeated query may return new rows.

          ActiveRecord::Base.transaction(isolation: :repeatable_read) do
            # safer but heavier
          end

     ╰┈➤ Serializable (Strictest)
          🔸No Dirty Reads
          🔸No Non-Repeatable Reads
          🔸No Phantom Read

          - Acts like only one transaction is running at a time.
          - But it does not actually queue transactions — it uses conflict detection and may throw:
              ActiveRecord::SerializationFailure (could not serialize access)

    ➤ In SERIALIZABLE isolation level:
        PostgreSQL (and other modern databases) does not queue transactions like a mutex (i.e., one-at-a-time locking).
        Instead, it uses MVCC (Multi-Version Concurrency Control) + conflict detection to simulate serial behavior.

        If it detects that two transactions could have interfered with each other in a way that violates serializability, one of them is rolled back with:
          ActiveRecord::SerializationFailure (could not serialize access due to concurrent update)
        So instead of queueing, it lets both run and detects problems after the fact.

    ➤ But in a system like IRCTC?
        IRCTC has to prevent overbooking in scenarios like Tatkal, where:
          🔸1000+ users try to book 1 ticket at exactly 10:00 AM.
          🔸If two people are shown “1 seat available”, both should not book it.

        Such systems often queue at the application level, not just DB.

      Here is how they might ensure strict control:
          
          1.Application-Level Queuing (Real Queueing)
            🔸Use Redis queues, Kafka, RabbitMQ, etc.
            🔸Requests go into a queue.
            🔸A background job or worker processes one at a time.
            🔸Others wait in line (just like IRL ticket counters).
            🔸This is true queuing, unlike DB isolation levels.

              class BookingWorker
                include Sidekiq::Worker

                def perform(user_id, train_id)
                  ActiveRecord::Base.transaction(isolation: :serializable) do
                    seat = Seat.lock.find_by(train_id: train_id, available: true)
                    raise "No seats" unless seat

                    seat.update!(available: false, user_id: user_id)
                  end
                end
              end
              
            user requests will be enqueue like: BookingWorker.perform_async(current_user.id, train.id)

          2.Optimistic Locking or Pessimistic Locking
              Another technique IRCTC-like systems might use is row-level locking:
               Pessimistic Lock (Rails):
            
               Seat.lock("FOR UPDATE").find(id) => It locks the row until the transaction is done.
              Other users trying to access it will wait (this is queuing via locking).
            
          3.Rate-Limiting & Load Shedding
              Sometimes, the app itself refuses to serve too many concurrent booking attempts, to protect the DB.


    ➤ What Sidekiq Queue Actually Guarantees? 
        class BookingWorker
          include Sidekiq::Worker

          def perform(user_id, train_id)
            ActiveRecord::Base.transaction(isolation: :serializable) do
              seat = Seat.lock.find_by(train_id: train_id, available: true) 
                #or: seat = Seat.lock("FOR UPDATE").find_by(train_id: train_id, available: true) #Rails convert like this internally.
              raise "No seats" unless seat

              seat.update!(available: false, user_id: user_id)
            end
          end
        end

      Here we might think that: Since Sidekiq jobs already run one by one in a queue, why do we still need transaction(isolation: :serializable) or locking inside them?

        ➤ Sidekiq guarantees job-level FIFO within a queue.
          BUT:
            It does not guarantee only one job runs at a time across the whole app.
            You can have many workers (threads/processes) processing jobs in parallel.
          
          So if 1000 users click "Book Now", and you do:
            BookingWorker.perform_async(user.id, train.id)
          All 1000 jobs enter Redis queue.
          If you have 10 Sidekiq threads, 10 jobs run simultaneously.

          Each job:
            Grabs a connection.
            Starts a transaction.
            Queries for an available seat.
            Now if two threads find the same seat is available, they may try to book it at the same time. This is what the problem might occur.

 Race Conditions in DB
 ========================
  ➤ A race condition occurs when two or more concurrent operations access the same data, and at least one of them modifies it, causing unintended or incorrect results.
  Example (Bank Transfer). Assume account has ₹10.

    account = Account.find(1)
    account.balance -= 5
    account.save
  
  Now if two threads/users do this at the same time, both fetch balance as ₹10 and both save ₹5. But it should have been ₹5 and ₹0.
  This is a race condition: because both read before any write is committed.

  ➤ There are different ways to solve race conditons:
     
     ╰┈➤ Pessimistic Locking (SELECT ... FOR UPDATE)
         🔸Assumes conflicts are likely. Locks the row at database level. Other transactions must wait.
         🔸You lock the row during the transaction, so no other process can read or write until you are done.

          Rails lock the row in two ways: 1. lock() and 2. with_lock()
        
          ActiveRecord::Base.transaction do
            account = Account.lock.find(1) # SELECT * FROM accounts WHERE id = 1 FOR UPDATE
            account.balance -= 5
            account.save!
          end

         🔸Row is locked until transaction ends.
         🔸Useful when you want to process queue-like jobs from DB rows, and skip locked rows.

          ActiveRecord::Base.transaction do
            ticket = Ticket.where(status: 'pending').lock("FOR UPDATE SKIP LOCKED").first
            ticket.update!(status: 'processing')
          end
          
         🔸Locks row until transaction ends.
         🔸Other transactions trying to SELECT ... FOR UPDATE  or SELECT ... FOR UPDATE SKIP LOCKED must wait or skip.

          product.with_lock do
            product.stock -= 1
            product.save!
          end

          This: Starts transaction, Locks row, Executes block, Commits

         🔸When to use:
           - High-concurrency writes. For example Inventory, ticket booking, bank balance.
           - You must prevent simultaneous updates. 

     ╰┈➤ Atomic Updates using update_counters or raw SQL
         🔸An atomic update is a single SQL operation that reads and writes in one step, so there is no chance of race condition.
         🔸Unlike the usual read → modify → write, atomic updates do not read the value first in Ruby. They just tell the DB:
               "Go and decrement/increment this value directly!"

          ⭐ Atomic Way — Using update_counters
              User.update_counters(1, coins: -10)
             This generates SQL like: UPDATE users SET coins = coins - 10 WHERE id = 1
            
            It tells the database: "You handle this. Subtract 10 from coins."
            Since this SQL is executed atomically by the DB, no other operation can sneak in between.

          ⭐ Atomic Way — Using Raw SQL (update_all)
              User.where(id: 1).update_all("coins = coins - 10")
             This generates SQL like: UPDATE users SET coins = coins - 10 WHERE id = 1
            
            Works the same as update_counters, but update_all is more flexible — you can use expressions, conditions, and more complex SQL.

         🔸When to use:
           - You are only modifying a numeric value (e.g., coins, likes, view_count).
           - You do not need to validate or run callbacks.
           - Performance matters — it is faster, since it is just one SQL query.
          
          Example:
            Instead of:
              post = Post.find(1)
              post.likes += 1
              post.save
            we should do:
              Post.update_counters(1, likes: 1)
            Or we should do:
              Post.where(id: 1).update_all("likes = likes + 1")


     ╰┈➤ Optimistic Locking (lock_version)
          It Assumes conflicts are rare.
          No database-level lock is held. It means:
          The database does NOT prevent other transactions from reading or modifying that row while you are working with it.
          There is no SELECT ... FOR UPDATE, no row-level lock, no blocking.

          This will allow concurrent reads, but detect conflict at save.
          Detect and prevent conflicting updates when multiple users/processes try to update the same database record at the same time.
          It does not lock the row in the database like pessimistic locking. Instead, it checks:
              "Has this record changed since I last read it?"
          If yes → it throws an error and blocks the update.

          ⭐ How it Works in Rails:
              Add lock_version to the table. In migration:
                  add_column :users, :lock_version, :integer, default: 0, null: false
                This column keeps track of how many times the row has been updated.

              Rails handle it automatically. We do not need to write special logic. ActiveRecord will:
               🔸Read lock_version when loading the object.
               🔸Add a condition in the UPDATE like this: UPDATE users SET name = 'Roy', lock_version = 1 WHERE id = 1 AND lock_version = 0

              If the lock_version of row is not 0, this update fails

          Example: 
            Two processes load same record:
              # User A and User B
              user = User.find(1)  # lock_version = 0
            User A updates name:
              user.name = "Roy"
              user.save  # Succeeds → lock_version becomes 1
            Now User B updates email:
              user.email = "test@example.com"
              user.save  # Fails → raises ActiveRecord::StaleObjectError
            Why? Because User B’s object has lock_version = 0, but DB now has lock_version = 1.

          ⭐ What Happens Internally?
            - Rails adds this condition to the SQL: WHERE id = 1 AND lock_version = 0
            - If no rows match, Rails knows someone else already changed it.

          ⭐ What to Do When it Fails?
            - We handle the ActiveRecord::StaleObjectError:
                begin
                  user.save!
                rescue ActiveRecord::StaleObjectError
                  puts "Another process updated this record first. Please reload and try again."
                end

          You can:
            - Reload the record and retry
            - Show a message to user
            - Use conflict resolution strategies (like merging fields)

         🔸When to use:
           - Lower chance of collisions.
           - Want to avoid locking but detect and handle conflicts.
           - Ideal for web forms, background workers, or slow UIs.


Deadlocks, Queueing, and Locking Strategies in High-Concurrency Apps
=====================================================================
➤ Deadlocks:
   - A deadlock happens when two or more processes wait on each other to release locks, and none can proceed.
     Example: 
        Transaction A locks row 1 → waits for row 2
        Transaction B locks row 2 → waits for row 1
     Both are stuck → deadlock error. ActiveRecord::Deadlocked

  How Rails/DB handles deadlock?
    DB (like PostgreSQL or MySQL) detects deadlocks.
    It kills one transaction with an error: PG::DeadlockDetected: ERROR: deadlock detected


  ⭐Preventing Deadlocks
  ----------------------
    ╰┈➤Best Practices:
        🔸Access tables/rows in consistent order: Always lock Train → then Seats
        🔸Keep transactions short: Do not perform heavy logic or I/O inside a transaction
        🔸Avoid unnecessary locks: Use .select instead of .find if you do not plan to update
        🔸Use DB indexes wisely: Without indexes, locks may escalate to table-level
        🔸Use advisory locks (Postgres only):
            ActiveRecord::Base.connection.execute("SELECT pg_advisory_lock(12345)")
            # Perform critical work
            ActiveRecord::Base.connection.execute("SELECT pg_advisory_unlock(12345)")
         🔹 Note: Advisory locks do not block other operations unless all parties use them.

    ╰┈➤App-level Lock( Redis + Sidekiq) And Database-level Lock(Optimistic Locking):
        🔹App-level locking (Redis): Prevents multiple workers from starting booking logic for the same user/train combo.
            lock_key = "booking_lock:user:#{user_id}:train:#{train_id}"
            locked = Redis.current.set(lock_key, "locked", nx: true, ex: 30)

            nx: true => Set only if not already set (non-blocking lock)
            ex: 30 => Auto-expire after 30s (avoids deadlock if job crashes)

        🔹DB-level locking (Postgres): Guarantees only one booking can succeed by locking the seat row.

        🛡 Use App-Level Lock (Redis) to avoid starting duplicate jobs.
        🔒 Use DB-Level Lock to guarantee consistency even under race conditions.

         Example:
          class BookingWorker
            include Sidekiq::Worker

            def perform(user_id, train_id)
              lock_key = "booking_lock:user:#{user_id}:train:#{train_id}"
              locked = Redis.current.set(lock_key, "locked", nx: true, ex: 30)
              unless locked
                logger.info "Booking already in progress for user #{user_id}"
                return
              end

              begin
                User.transaction(isolation: :serializable) do
                  seat = Seat.lock("FOR UPDATE SKIP LOCKED").find_by(train_id: train_id, available: true)
                  raise "No seats available" unless seat

                  seat.update!(available: false, user_id: user_id)
                end
              ensure
                Redis.current.del(lock_key)
              end
            end
          end


    ╰┈➤Logging and Monitoring Concurrency:
        Detect Deadlocks
          Enable DB logs: log_min_error_statement = 'error' in PostgreSQL
          Check Sidekiq retries (failed jobs)
        Use Monitoring Tools
          New Relic, Datadog, or Skylight to monitor DB load
          Redis + Sidekiq dashboard for queue inspection

---------------------------------------------------------------------------------------------------------------
Question: You have a user model, You need to create a seperate model called ActiveUser which only gives us data for user where active is true and blocked is false but we do not want to create another table and keep using the user table, how can you do this without a default scope?

Answer: If I need a separate model that only returns users where active = true and blocked = false, but I do not want to create a new table and I also do not want to use default_scope, the cleanest solution is to use a database view.

A database view is basically a virtual table backed by a SQL query. It does not store data physically. Instead, it dynamically fetches data from the underlying table.

So in this case, I would create a view like:
  CREATE VIEW active_users AS
    SELECT * FROM users
    WHERE active = true AND blocked = false;
  
This ensures the filtering happens at the database level, not at the Rails level. That means the condition cannot be accidentally bypassed.

In Rails, I would create a migration to create database view like this:

  class CreateActiveUsersView < ActiveRecord::Migration[7.0]
    def up
      execute <<~SQL
        CREATE VIEW active_users AS
        SELECT *
        FROM users
        WHERE active = true AND blocked = false;
      SQL
    end

    def down
      execute "DROP VIEW active_users;"
    end
  end

  Here, I am using execute because Rails does not have built-in helpers for creating views.

Then I define a new model:
  class ActiveUser < ApplicationRecord
    self.table_name = "active_users"
  end

  Now, what happens when we define self.table_name = "active_users"?

    Normally, Rails infers the table name from the model name.
      For example:
        User → users
        ActiveUser → active_users
    But Rails expects that table to physically exist.

    Here, we are telling ActiveRecord explicitly:
      Do not look for a physical table called active_users. Use whatever exists in the database under this name — which in this case is a view.
      Here, ActiveRecord will treat the virtual table (i.e view) as a real active_users table.

    ActiveRecord does not care whether it is a real table or a view. As long as the database responds to queries, Rails treats it like a normal table.

  So now we can call:
    ActiveUser.all
    ActiveUser.where(role: "driver")
    ActiveUser.count

  And under the hood, ActiveRecord will generate SQL like:
    SELECT * FROM active_users WHERE role = 'driver';

  The database then internally executes the view definition, which applies:
    WHERE active = true AND blocked = false
  So the filtering is always enforced.

NOTE:
  Read-only behavior:
    By default, database views are usually read-only unless specifically configured to be updatable.
    So typically this model is used for querying only.

  Primary key:
    If the view includes the id column from users, ActiveRecord will work normally.
    If not, we may need this in ActiveUser model:
      self.primary_key = :id

  Performance
    Since it is just a query wrapper, performance depends on indexes on users.
    So we should ensure indexes exist on active and blocked.