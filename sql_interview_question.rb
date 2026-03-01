=================================== SQL ==================================================
Question 1: What is SQL?

Answer -> SQL is a language used to interact with relational databases. It allows us to query data, insert/update/delete data, and manage schema objects like tables, indexes, and constraints. In Rails, ActiveRecord generates SQL under the hood, but for debugging and performance work, understanding SQL is essential.

------------------------------------------------------------------------------------------------------
Question 2: What is the difference between a database, a table, and a row?

Answer -> A database is the overall container of data. A table is a structured collection of data inside the database. A row represents a single record, and columns represent attributes.

------------------------------------------------------------------------------------------------------
Question 3: What is a primary key?

Answer -> A primary key uniquely identifies each row in a table. It should be unique and not null. In Rails, the default primary key is id, usually a big integer.

------------------------------------------------------------------------------------------------------
Question 4: What is a foreign key?

Answer -> A foreign key is a column that references a primary key in another table. It enforces referential integrity — for example, an orders.user_id referencing users.id ensures orders always belong to a valid user.

------------------------------------------------------------------------------------------------------
Question 5: Difference between DELETE, TRUNCATE, DROP?

Answer -> DELETE removes rows and can use a WHERE condition; it logs each row deletion and can be rolled back. TRUNCATE removes all rows very fast but is more aggressive and has restrictions. DROP deletes the entire table structure along with its data.

------------------------------------------------------------------------------------------------------
Question 6: What is the difference between WHERE and HAVING?

Answer -> WHERE filters rows before grouping happens. HAVING filters results after GROUP BY aggregation. So if I want to filter aggregated values like COUNT > 5, I use HAVING.

------------------------------------------------------------------------------------------------------
Question 7: Difference between UNION and UNION ALL?

Answer -> UNION removes duplicates, so it does extra work. UNION ALL keeps duplicates and is faster. In most cases, if duplicates are okay, UNION ALL is preferred.

🔹 UNION
    Removes duplicate rows
    Internally performs a DISTINCT operation
    Slightly slower because it has to compare rows and eliminate duplicates

🔹 UNION ALL
    Keeps duplicates
    Does not perform duplicate checking
    Faster and more efficient

------------------------------------------------------------------------------------------------------
Question 8: What are joins in SQL?

Answer -> Joins combine rows from two or more tables based on a related column. In practical systems, joins are used constantly — like fetching orders with users, payments with invoices, etc.

------------------------------------------------------------------------------------------------------
Question 9: INNER JOIN vs LEFT JOIN?

Answer -> INNER JOIN returns only matching rows from both tables. LEFT JOIN returns all rows from left table, and matching rows from right table — if no match exists, right side columns become NULL.

------------------------------------------------------------------------------------------------------
Question 10: When do you use LEFT JOIN?

Answer -> When I want all records from the main table even if related record does not exist. Example: all users with their last order, even if some users never ordered.

------------------------------------------------------------------------------------------------------
Question 11: What is CROSS JOIN?

Answer -> A CROSS JOIN creates a cartesian product — every row in table A matches with every row in table B. It is rarely used intentionally, and usually if we see it in production queries it is a bug.

------------------------------------------------------------------------------------------------------
Question 12: What is a self join?

Answer -> A self join is joining a table with itself. For example, an employees table where each employee has a manager_id referencing another employee.

------------------------------------------------------------------------------------------------------
Question 13: Find top 5 highest paid employees

SELECT * FROM employees
ORDER BY salary DESC
LIMIT 5;

This sorts salaries descending and returns only top 5 using LIMIT.

------------------------------------------------------------------------------------------------------
Question 14: Find duplicate emails in users table

SELECT email, COUNT(*) 
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

We group by email, count occurrences, and use HAVING to filter duplicates.

------------------------------------------------------------------------------------------------------
Question 15: Fetch users who never placed an order

SELECT u.*
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE o.id IS NULL;

LEFT join ensures users remain. NULL order id means no matching order.

------------------------------------------------------------------------------------------------------
Question 16: Fetch total orders per user

SELECT u.id, u.name, COUNT(o.id) AS total_orders
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.name;

------------------------------------------------------------------------------------------------------
Question 17: Fetch latest order for each user

Option 1 (Postgres DISTINCT ON):

  SELECT DISTINCT ON (user_id) *
  FROM orders
  ORDER BY user_id, created_at DESC;

Option 2 (Window function - universal):

  SELECT *
  FROM (
    SELECT o.*,
          ROW_NUMBER() OVER(PARTITION BY user_id ORDER BY created_at DESC) AS rn
    FROM orders o
  ) x
  WHERE rn = 1;

------------------------------------------------------------------------------------------------------
Question 18: What is an index?

Answer -> An index is a data structure that speeds up lookup queries. Instead of scanning the full table, the database uses the index to locate rows quickly. Indexes are essential for performance but they also slow down writes because indexes need to be updated.

------------------------------------------------------------------------------------------------------
Question 19: When do indexes help?

Answer -> Indexes help with WHERE conditions, JOIN columns, sorting (ORDER BY), and sometimes GROUP BY. They are especially useful on high-cardinality columns like user_id, email, created_at.

------------------------------------------------------------------------------------------------------
Question 20: When indexes do NOT help?

Answer -> Indexes do not help much when the query returns a very large portion of rows, or when columns have very low uniqueness like a boolean status. Sometimes DB still chooses sequential scan.

------------------------------------------------------------------------------------------------------
Question 21: What is a composite index?

Answer -> A composite index is an index on multiple columns, like (user_id, created_at). It helps queries that filter or sort by those columns in that order.

------------------------------------------------------------------------------------------------------
Question 22: What is the leftmost prefix rule? (important)

Answer -> In composite indexes, the database can use the index efficiently only if the query filters by the leftmost columns first. For example, index (user_id, created_at) helps queries filtering by user_id, but not queries filtering only by created_at.

------------------------------------------------------------------------------------------------------
Question 23: How do you decide which columns need indexes?

Answer -> I check slow queries and see where clauses, joins, and order by. Then I run EXPLAIN ANALYZE to see whether sequential scan is happening. If query frequently filters by a column and table is large, indexing that column usually helps.

------------------------------------------------------------------------------------------------------
Question 24: What is EXPLAIN / EXPLAIN ANALYZE?

Answer -> EXPLAIN shows the query plan — how database will execute the query. EXPLAIN ANALYZE actually runs the query and shows real execution time, rows scanned, and whether indexes were used.

------------------------------------------------------------------------------------------------------
Question 25: What is a transaction?

Answer -> A transaction groups multiple operations into a single atomic unit. Either all succeed or all rollback. It helps maintain data consistency.

------------------------------------------------------------------------------------------------------
Question 26: What is ACID?

Answer -> ACID stands for Atomicity, Consistency, Isolation, and Durability. It is the guarantee database provides for transactions.

------------------------------------------------------------------------------------------------------
Question 27: What is a deadlock?

Answer -> A deadlock happens when two transactions lock resources in a way that both wait for each other, and neither can proceed. Database detects it and aborts one transaction.

------------------------------------------------------------------------------------------------------
Question 28: How do you handle deadlocks?

Answer -> I reduce lock duration by keeping transactions small, lock rows in consistent order, and add retries for deadlock errors in application.

------------------------------------------------------------------------------------------------------
Question 29: What is isolation level?

Answer -> Isolation level defines how transactions interact with each other, specifically what kind of intermediate data can be seen.

Common levels:
  Read committed
  Repeatable read
  Serializable

------------------------------------------------------------------------------------------------------
Question 30: What is a UNIQUE constraint?

Answer -> It ensures no duplicate values in a column. For example, users email must be unique.

------------------------------------------------------------------------------------------------------
Question 31: Difference between UNIQUE constraint vs unique index?

Answer -> Practically, both create uniqueness enforcement. In Postgres, UNIQUE constraint is implemented using a unique index. The difference is semantic: constraints are about data integrity.

------------------------------------------------------------------------------------------------------
Question 32: What is NOT NULL constraint?

Answer -> It prevents null values in that column. Helps enforce required fields.

------------------------------------------------------------------------------------------------------
Question 33: What is ON DELETE CASCADE?

Answer -> It automatically deletes child records when parent is deleted. Example: deleting a user deletes all their orders.

------------------------------------------------------------------------------------------------------
Question 34: When do you write raw SQL in Rails?

Answer -> When ActiveRecord becomes inefficient or complicated — like heavy reporting queries, window functions, or complex joins. In those cases, I use Arel or raw SQL carefully and keep it well-tested.

------------------------------------------------------------------------------------------------------
Question 35: What is N+1 query problem?

Answer -> N+1 happens when Rails loads one record, then loads associated records one by one. It increases queries heavily. Fix is eager loading using includes/preload/eager_load.

------------------------------------------------------------------------------------------------------
Question 36: includes vs joins?

Answer -> joins generates SQL join and doesn’t load associations automatically. includes eager loads associations and can use separate queries or joins depending on access pattern.

------------------------------------------------------------------------------------------------------
Question 37: Tell me about a time you solved a production performance issue using SQL.

Answer -> Yes. We noticed an API endpoint was slow. I checked logs and used Rails query logs and rack-mini-profiler. I found a slow query doing sequential scan. Then I ran EXPLAIN ANALYZE, confirmed missing index on a filtering column, added composite index, and reduced response time significantly. We also fixed N+1 queries using includes.

------------------------------------------------------------------------------------------------------
Question 38: What would you do if a query suddenly becomes slow after deployment?

Answer -> I would first check query logs and compare before/after. Then check EXPLAIN ANALYZE for query plan changes. It could be missing index, increased data volume, or bad query. Also sometimes stats are outdated — so analyze/vacuum helps in Postgres.

------------------------------------------------------------------------------------------------------
Question 39: You added an index but query still slow. Why?

Answer -> It could be because query returns many rows so DB chooses sequential scan. Or index is not matching query pattern, like wrong column order in composite index. Or query uses functions on indexed columns, which prevents index usage.

------------------------------------------------------------------------------------------------------
Question 40: You need to backfill millions of records. How do you do safely?

Answer -> I do it in batches to avoid locks and long transactions. I use background jobs and update records in chunks, like 5k or 10k per batch, and track progress. Also I avoid callbacks if unnecessary and monitor DB load.

------------------------------------------------------------------------------------------------------
Question 41: What are window functions?

Answer -> Window functions allow calculations across sets of rows without collapsing them like GROUP BY. Example: rank, row_number, running totals.

------------------------------------------------------------------------------------------------------
Question 42: What is ROW_NUMBER()?

Answer -> It assigns a sequential number to rows in each partition. It is commonly used to fetch latest record per group.

------------------------------------------------------------------------------------------------------
Question 43: What is CTE (WITH clause)?

Answer -> A Common Table Expression is like a temporary named result that improves readability and allows complex queries to be built step-by-step.

------------------------------------------------------------------------------------------------------
Question 44: What is an execution plan?

Answer -> It is how DB decides to execute query — index scan, sequential scan, nested loop join, hash join. We use EXPLAIN to inspect it.

------------------------------------------------------------------------------------------------------
Question 45: What is normalization?

Answer ->  Normalization is the process of designing database tables to reduce redundancy and avoid anomalies (update/insert/delete issues).
The idea is: store each fact in one place, and use relationships instead of duplicate columns.

Example: instead of storing user_name in every order row, store user_id and join with users table.

------------------------------------------------------------------------------------------------------
Question 46: What is 1NF - First Normal Form ?

Answer -> Each column should contain atomic (single) values
No repeating groups / arrays in columns
Example: phone_numbers should not store 123,456. Use separate table.

------------------------------------------------------------------------------------------------------
Question 47: What is 2NF ?

Anser -> Must be in 1NF. Every non-key column must depend on the whole primary key (important for composite PK)
Example: If PK is (student_id, course_id), then student_name depends only on student_id → move to student table.

------------------------------------------------------------------------------------------------------
Question 48: What is 3NF ?

Answer -> Must be in 2NF. No transitive dependency: non-key column should not depend on another non-key column
Example: user_id, zipcode, city — city depends on zipcode, not user_id → move zipcode-city mapping.

------------------------------------------------------------------------------------------------------
Question 49: What is denormalization?

Answer -> Denormalization is intentionally adding redundancy to improve read performance.
We do it when many joins slow down queries or for reporting.
Example: storing user_name in orders for faster display (but requires keeping it updated).

------------------------------------------------------------------------------------------------------
Question 50: What is a view?

Answer -> A view is a virtual table created from a SQL query. It stores the query definition, not the data.
Used to:
simplify complex queries
provide a stable interface
restrict access (security)

------------------------------------------------------------------------------------------------------
Question 51: Materialized view?

Answer -> A materialized view is like a view, but it stores the computed data physically.
It is faster for reads, but must be refreshed to stay updated.
Use case: heavy reporting dashboards.

------------------------------------------------------------------------------------------------------
Question 52: Stored procedures?

Answer -> Stored procedures are predefined SQL logic stored in the database. They can contain logic like loops, variables, and multiple statements.
Pros:
  faster execution sometimes
  centralize logic
Cons:
  logic becomes DB-dependent
  harder to version and test compared to app code

------------------------------------------------------------------------------------------------------
Question 53: Triggers?

Answer -> Triggers are database rules that automatically run when an event happens:
BEFORE INSERT / UPDATE / DELETE
AFTER INSERT / UPDATE / DELETE

Use case:
  audit logs
  enforcing rules
  But triggers can make debugging harder.

------------------------------------------------------------------------------------------------------
Question 54: What is GROUP BY?

Answer -> GROUP BY is used to aggregate rows into groups.
Usually used with COUNT, SUM, AVG, MAX, MIN.
Example: count orders per user.

------------------------------------------------------------------------------------------------------
Question 55: COUNT(*) vs COUNT(column)?

Answer -> COUNT(*) counts all rows, including nulls
COUNT(column) counts only rows where column is NOT NULL

------------------------------------------------------------------------------------------------------
Question 56: Index scan vs sequential scan?

Answer -> Index scan: DB uses index to locate rows fast (good when you return small subset)
Sequential scan: DB reads entire table row-by-row (sometimes faster when most rows needed)

------------------------------------------------------------------------------------------------------
Question 57: What is VACUUM/ANALYZE in Postgres?

Answer -> Postgres uses MVCC, so deleted/updated rows create “dead tuples”.
VACUUM removes dead tuples and frees space
ANALYZE updates statistics so planner chooses better query plans
Autovacuum runs automatically, but sometimes manual vacuum helps.

------------------------------------------------------------------------------------------------------
Question 58: What is MVCC?

Answer -> MVCC (Multi-Version Concurrency Control) allows multiple transactions to read/write simultaneously without blocking each other heavily.
Instead of updating rows in place, DB creates new row versions.
This improves concurrency.

------------------------------------------------------------------------------------------------------
Question 59: Upsert?

Answer -> Upsert means: insert if not exists, otherwise update.
Very common in syncing data / idempotent operations.

------------------------------------------------------------------------------------------------------
Question 60: ON CONFLICT in Postgres?

Answer -> Postgres supports upsert using:

    INSERT INTO users(email, name)
    VALUES ('a@a.com','A')
    ON CONFLICT (email)
    DO UPDATE SET name = EXCLUDED.name;

EXCLUDED refers to the row that caused conflict.

------------------------------------------------------------------------------------------------------
Question 61: Pagination: offset vs cursor?

Answer ->  Offset pagination: LIMIT 20 OFFSET 100
Cursor pagination: WHERE id > last_id LIMIT 20 (or created_at cursor)
Cursor pagination is better for large datasets.

------------------------------------------------------------------------------------------------------
Question 62: Why offset pagination slow?

Answer -> Because OFFSET makes DB scan and discard N rows first.
So OFFSET 500000 becomes very slow.
Cursor pagination avoids that.

------------------------------------------------------------------------------------------------------
Question 63: Explain lock escalation?

Answer -> Lock escalation means DB might upgrade from many row locks to a higher-level lock (table lock) to reduce lock management overhead.
Postgres generally does not do classic lock escalation like SQL Server, but large operations can still acquire heavier locks.

------------------------------------------------------------------------------------------------------
Question 64: Optimistic vs pessimistic locking?

Answer -> Optimistic locking: Assumes conflicts are rare. Uses version column (Rails: lock_version) to detect conflicts during update.
Pessimistic locking: Locks the row immediately using SELECT ... FOR UPDATE, preventing others from updating.

------------------------------------------------------------------------------------------------------
Question 65: How to avoid race conditions?

Answer -> Common ways:
use database constraints (UNIQUE)
use transactions
use row locking (FOR UPDATE)
use upsert (ON CONFLICT)
use idempotency keys

Best solution: enforce correctness at DB layer.

------------------------------------------------------------------------------------------------------
Question 66: SERIALIZABLE isolation?

Answer -> Serializable is the strictest isolation level. It makes concurrent transactions behave as if executed one by one. It prevents anomalies but increases:
blocking
transaction failures (serialization errors)

------------------------------------------------------------------------------------------------------
Question 67: Dirty read, phantom read?

Answer -> Dirty read: reading uncommitted changes from another transaction (Postgres prevents this)
Phantom read: re-running a query returns new rows because another transaction inserted rows matching condition.
Serializable prevents these.

------------------------------------------------------------------------------------------------------
Question 68: How to troubleshoot deadlocks?
Answer -> Steps:
Identify deadlock error logs
Find which queries/transactions involved
Reduce lock time (short transactions)
Lock rows in consistent order
Add retry logic for deadlocks

------------------------------------------------------------------------------------------------------
Question 69: Use case of partial indexes?

Answer -> Partial index indexes only subset of rows.
Example: active users only:

CREATE INDEX idx_users_active ON users(id)
WHERE active = true;

Great when most rows are inactive.

------------------------------------------------------------------------------------------------------
Question 70: What is a covering index?

Answer -> A covering index includes all columns needed by query, so DB does not need table lookup.
Example: CREATE INDEX idx_orders_user_created_at ON orders(user_id, created_at);

Query filtering user_id and ordering by created_at can be served fully by index.

------------------------------------------------------------------------------------------------------
Question 71: When to use JSONB?

Answer -> Use JSONB when:
schema is flexible / dynamic fields
metadata, settings, configuration
integration payload storage
But do NOT replace relational design unnecessarily.

------------------------------------------------------------------------------------------------------
Question 72: Indexing JSONB?

Answer -> Two common indexes:
  GIN index for JSON containment queries (@>)
  expression indexes for specific keys

Example:
  CREATE INDEX idx_meta_gin ON events USING GIN(meta);
  CREATE INDEX idx_meta_user ON events ((meta->>'user_id'));

------------------------------------------------------------------------------------------------------
Question 73: What is replication?

Answer -> Replication copies data from primary DB to replica(s) for:
  high availability
  scaling reads
  failover

------------------------------------------------------------------------------------------------------
Question 74: Read replicas?

Answer -> Read replicas are secondary DB instances used for read-only queries.
Writes still go to primary. Used to scale read-heavy workloads.

------------------------------------------------------------------------------------------------------
Question 75: How to prevent SQL injection?

Answer -> use parameterized queries / prepared statements
avoid string interpolation
validate input when needed
Rails: use ActiveRecord query bindings: User.where("email = ?", params[:email])

------------------------------------------------------------------------------------------------------
Question 76: Prepared statements?

Answer -> Prepared statements compile query once and execute many times with different parameters.
Benefits: prevents SQL injection
Improves performance for repeated queries

===================================== 50 SQL Coding Interview Questions ===============================
Assume tables:

  users(id, name, email, created_at)
  orders(id, user_id, total_amount, status, created_at)
  order_items(id, order_id, product_id, quantity, price)
  products(id, name, category, price)
  payments(id, order_id, amount, status, created_at)

------------------------------------------------------------------------------------------------------
Question 77: Find users created in last 30 days

  SELECT *
  FROM users
  WHERE created_at >= NOW() - INTERVAL '30 days';

------------------------------------------------------------------------------------------------------
Question 78: Find duplicate emails

  SELECT email, COUNT(*)
  FROM users
  GROUP BY email
  HAVING COUNT(*) > 1;

------------------------------------------------------------------------------------------------------
Question 79: Users with no orders

  SELECT u.*
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id
  WHERE o.id IS NULL;

------------------------------------------------------------------------------------------------------
Question 80: Total revenue

  SELECT SUM(total_amount) AS revenue
  FROM orders
  WHERE status = 'paid';

------------------------------------------------------------------------------------------------------
Question 81: Revenue per day (last 7 days)

  SELECT DATE(created_at) AS day, SUM(total_amount) AS revenue
  FROM orders
  WHERE status = 'paid'
    AND created_at >= NOW() - INTERVAL '7 days'
  GROUP BY day
  ORDER BY day;

------------------------------------------------------------------------------------------------------
Question 82: Latest order per user (window function)

  SELECT * FROM (
    SELECT o.*,
          ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) AS rn
    FROM orders o
  ) x
  WHERE rn = 1;

------------------------------------------------------------------------------------------------------
Question 83: Orders with payment status

  SELECT o.id, o.total_amount, p.status AS payment_status
  FROM orders o
  LEFT JOIN payments p ON p.order_id = o.id;

------------------------------------------------------------------------------------------------------
Question 84: Orders where payment missing

  SELECT o.* FROM orders o
  LEFT JOIN payments p ON p.order_id = o.id
  WHERE p.id IS NULL;

------------------------------------------------------------------------------------------------------
Question 85: Total items in each order

  SELECT order_id, SUM(quantity) AS total_items
  FROM order_items
  GROUP BY order_id;

------------------------------------------------------------------------------------------------------
Question 86: Most sold products (top 5)

  SELECT p.id, p.name, SUM(oi.quantity) AS sold_qty
  FROM products p
  JOIN order_items oi ON oi.product_id = p.id
  GROUP BY p.id, p.name
  ORDER BY sold_qty DESC
  LIMIT 5;

------------------------------------------------------------------------------------------------------
Question 87:  Revenue per product

  SELECT p.id, p.name, SUM(oi.quantity * oi.price) AS revenue
  FROM products p
  JOIN order_items oi ON oi.product_id = p.id
  GROUP BY p.id, p.name
  ORDER BY revenue DESC;

------------------------------------------------------------------------------------------------------
Question 88: Count orders by status

  SELECT status, COUNT(*)
  FROM orders
  GROUP BY status;

------------------------------------------------------------------------------------------------------
Question 89: Users who placed an order this month

  SELECT DISTINCT u.*
  FROM users u
  JOIN orders o ON o.user_id = u.id
  WHERE o.created_at >= date_trunc('month', NOW());

------------------------------------------------------------------------------------------------------
Question 90: Average order value

  SELECT AVG(total_amount) AS avg_order
  FROM orders
  WHERE status = 'paid';


------------------------------------------------------------------------------------------------------
Question 91: Find users who spent more than 10,000

  SELECT u.id, u.name, SUM(o.total_amount) AS total_spent
  FROM users u
  JOIN orders o ON o.user_id = u.id
  WHERE o.status = 'paid'
  GROUP BY u.id, u.name
  HAVING SUM(o.total_amount) > 10000;

------------------------------------------------------------------------------------------------------
Question 92: Products never ordered

  SELECT p.*
  FROM products p
  LEFT JOIN order_items oi ON oi.product_id = p.id
  WHERE oi.id IS NULL;

------------------------------------------------------------------------------------------------------
Question 93: Second highest order amount

  SELECT DISTINCT total_amount
  FROM orders
  ORDER BY total_amount DESC
  OFFSET 1
  LIMIT 1;

------------------------------------------------------------------------------------------------------
Question 94: Top order per day

  SELECT *
  FROM (
    SELECT o.*,
          ROW_NUMBER() OVER (PARTITION BY DATE(created_at) ORDER BY total_amount DESC) AS rn
    FROM orders o
  ) x
  WHERE rn = 1;

------------------------------------------------------------------------------------------------------
Question 95: Users with at least 3 orders

  SELECT u.id, u.name
  FROM users u
  JOIN orders o ON o.user_id = u.id
  GROUP BY u.id, u.name
  HAVING COUNT(o.id) >= 3;


------------------------------------------------------------------------------------------------------
Question 96: Orders in last hour

  SELECT *
  FROM orders
  WHERE created_at >= NOW() - INTERVAL '1 hour';

------------------------------------------------------------------------------------------------------
Question 97: Delete inactive users (example)

  DELETE FROM users
  WHERE created_at < NOW() - INTERVAL '2 years';

------------------------------------------------------------------------------------------------------
Question 98: Update all pending orders to cancelled older than 30 days

  UPDATE orders
  SET status = 'cancelled'
  WHERE status = 'pending'
    AND created_at < NOW() - INTERVAL '30 days';

------------------------------------------------------------------------------------------------------
Question 99: Insert user (basic)

  INSERT INTO users(name, email, created_at)
  VALUES ('Pankaj', 'pankaj@test.com', NOW());

------------------------------------------------------------------------------------------------------
Question 100: Upsert user by email (Postgres)

  INSERT INTO users(name, email)
  VALUES ('Pankaj', 'pankaj@test.com')
  ON CONFLICT (email)
  DO UPDATE SET name = EXCLUDED.name;

------------------------------------------------------------------------------------------------------
Question 101: Find orders where total doesn’t match sum(order_items)

  SELECT o.id
  FROM orders o
  JOIN (
    SELECT order_id, SUM(quantity * price) AS calc_total
    FROM order_items
    GROUP BY order_id
  ) t ON t.order_id = o.id
  WHERE o.total_amount <> t.calc_total;

------------------------------------------------------------------------------------------------------
Question 102: Find user with maximum spending

  SELECT u.id, u.name, SUM(o.total_amount) AS spent
  FROM users u
  JOIN orders o ON o.user_id = u.id
  WHERE o.status = 'paid'
  GROUP BY u.id, u.name
  ORDER BY spent DESC
  LIMIT 1;

------------------------------------------------------------------------------------------------------
Question 103: Rank users by spending (window)

  SELECT u.id, u.name,
        SUM(o.total_amount) AS spent,
        RANK() OVER (ORDER BY SUM(o.total_amount) DESC) AS rank
  FROM users u
  JOIN orders o ON o.user_id = u.id
  WHERE o.status = 'paid'
  GROUP BY u.id, u.name;

------------------------------------------------------------------------------------------------------
Question 104: Running total revenue (daily)

  SELECT day,
        revenue,
        SUM(revenue) OVER (ORDER BY day) AS running_total
  FROM (
    SELECT DATE(created_at) AS day, SUM(total_amount) AS revenue
    FROM orders
    WHERE status='paid'
    GROUP BY day
  ) x
  ORDER BY day;

------------------------------------------------------------------------------------------------------
Question 105: Find products in category 'Books'

  SELECT *
  FROM products
  WHERE category = 'Books';

------------------------------------------------------------------------------------------------------
Question 106: Find orders containing a specific product_id = 10

  SELECT DISTINCT o.*
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.id
  WHERE oi.product_id = 10;

------------------------------------------------------------------------------------------------------
Question 107: Count users per month

  SELECT date_trunc('month', created_at) AS month, COUNT(*)
  FROM users
  GROUP BY month
  ORDER BY month;

------------------------------------------------------------------------------------------------------
Question 108: Pagination using cursor (id-based)

  SELECT *
  FROM orders
  WHERE id > :last_id
  ORDER BY id
  LIMIT 20;

------------------------------------------------------------------------------------------------------
Question 109: Find failed payments in last 24 hours

  SELECT *
  FROM payments
  WHERE status = 'failed'
    AND created_at >= NOW() - INTERVAL '24 hours';

------------------------------------------------------------------------------------------------------
Question 110: Orders with more than 5 items

  SELECT oi.order_id
  FROM order_items oi
  GROUP BY oi.order_id
  HAVING SUM(oi.quantity) > 5;

------------------------------------------------------------------------------------------------------
Question 111: Orders paid but payment amount mismatch

  SELECT o.id, o.total_amount, p.amount
  FROM orders o
  JOIN payments p ON p.order_id = o.id
  WHERE o.status='paid' AND p.amount <> o.total_amount;

------------------------------------------------------------------------------------------------------
Question 112: Find users who bought from category 'Electronics'

  SELECT DISTINCT u.*
  FROM users u
  JOIN orders o ON o.user_id = u.id
  JOIN order_items oi ON oi.order_id = o.id
  JOIN products p ON p.id = oi.product_id
  WHERE p.category = 'Electronics';

------------------------------------------------------------------------------------------------------
Question 113: Find most recent payment per order

  SELECT *
  FROM (
    SELECT p.*,
          ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY created_at DESC) rn
    FROM payments p
  ) x
  WHERE rn = 1;

------------------------------------------------------------------------------------------------------
Question 114: Find users who haven’t ordered in 6 months

  SELECT u.*
  FROM users u
  LEFT JOIN orders o
    ON o.user_id = u.id
    AND o.created_at >= NOW() - INTERVAL '6 months'
  WHERE o.id IS NULL;

------------------------------------------------------------------------------------------------------
Question 115: Soft-delete pattern example (update deleted_at)

  UPDATE users
  SET deleted_at = NOW()
  WHERE id = 10;

------------------------------------------------------------------------------------------------------
Question 116: Find orders with NULL status

  SELECT *
  FROM orders
  WHERE status IS NULL;

------------------------------------------------------------------------------------------------------
Question 117: Fetch orders with user info
SELECT o.*, u.name, u.email
FROM orders o
JOIN users u ON u.id = o.user_id;

------------------------------------------------------------------------------------------------------
Question 118: Find top category by revenue

  SELECT p.category, SUM(oi.quantity * oi.price) AS revenue
  FROM products p
  JOIN order_items oi ON oi.product_id = p.id
  GROUP BY p.category
  ORDER BY revenue DESC
  LIMIT 1;

------------------------------------------------------------------------------------------------------
Question 119: Find users who placed orders on 3 consecutive days (advanced)

  WITH days AS (
    SELECT user_id, DATE(created_at) d
    FROM orders
    GROUP BY user_id, DATE(created_at)
  ),
  seq AS (
    SELECT user_id, d,
          d - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY d))::int AS grp
    FROM days
  )
  SELECT user_id
  FROM seq
  GROUP BY user_id, grp
  HAVING COUNT(*) >= 3;

------------------------------------------------------------------------------------------------------
Question 120: Find duplicate orders by same user same amount same day

  SELECT user_id, total_amount, DATE(created_at), COUNT(*)
  FROM orders
  GROUP BY user_id, total_amount, DATE(created_at)
  HAVING COUNT(*) > 1;

------------------------------------------------------------------------------------------------------
Question 121: Find products priced above average

  SELECT *
  FROM products
  WHERE price > (SELECT AVG(price) FROM products);

------------------------------------------------------------------------------------------------------
Question 122: Find users with multiple pending orders

  SELECT user_id, COUNT(*)
  FROM orders
  WHERE status='pending'
  GROUP BY user_id
  HAVING COUNT(*) > 1;

------------------------------------------------------------------------------------------------------
Question 123: Identify orphan order_items without order

  SELECT oi.*
  FROM order_items oi
  LEFT JOIN orders o ON o.id = oi.order_id
  WHERE o.id IS NULL;

========================== 50 Advanced SQL Coding Questions =========================================
Tables

users(id, name, email, created_at)
orders(id, user_id, total_amount, status, created_at)
order_items(id, order_id, product_id, quantity, price)
products(id, name, category, price)
payments(id, order_id, amount, status, created_at)
events(id, user_id, event_name, created_at) (for analytics)
------------------------------------------------------------------------------------------------------
Question 124: Top 3 most expensive orders per user

  SELECT *
  FROM (
    SELECT o.*,
          ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY total_amount DESC) AS rn
    FROM orders o
  ) x
  WHERE rn <= 3;

------------------------------------------------------------------------------------------------------
Question 125: Latest successful payment per order

SELECT *
FROM (
  SELECT p.*,
         ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY created_at DESC) rn
  FROM payments p
  WHERE status = 'success'
) x
WHERE rn = 1;

------------------------------------------------------------------------------------------------------
Question 126: Users ranked by total revenue (dense rank)

SELECT u.id, u.name,
       SUM(o.total_amount) AS revenue,
       DENSE_RANK() OVER (ORDER BY SUM(o.total_amount) DESC) AS rank
FROM users u
JOIN orders o ON o.user_id = u.id
WHERE o.status = 'paid'
GROUP BY u.id, u.name;

------------------------------------------------------------------------------------------------------
Question 127: Find orders with duplicate total_amount by same user on same day

SELECT user_id, DATE(created_at) AS day, total_amount, COUNT(*) AS cnt
FROM orders
GROUP BY user_id, DATE(created_at), total_amount
HAVING COUNT(*) > 1;

------------------------------------------------------------------------------------------------------
Question 128: Show revenue % contribution of each user

WITH user_rev AS (
  SELECT user_id, SUM(total_amount) AS revenue
  FROM orders
  WHERE status='paid'
  GROUP BY user_id
),
tot AS (
  SELECT SUM(revenue) AS total_revenue FROM user_rev
)
SELECT u.user_id, u.revenue,
       ROUND((u.revenue * 100.0 / t.total_revenue), 2) AS pct
FROM user_rev u CROSS JOIN tot t
ORDER BY pct DESC;

------------------------------------------------------------------------------------------------------
Question 129: Moving average revenue (7-day rolling)

WITH daily AS (
  SELECT DATE(created_at) day, SUM(total_amount) revenue
  FROM orders
  WHERE status='paid'
  GROUP BY day
)
SELECT day, revenue,
       AVG(revenue) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ma_7
FROM daily
ORDER BY day;

------------------------------------------------------------------------------------------------------
Question 130: Detect revenue drop > 30% compared to previous day

WITH daily AS (
  SELECT DATE(created_at) day, SUM(total_amount) revenue
  FROM orders
  WHERE status='paid'
  GROUP BY day
),
x AS (
  SELECT day, revenue,
         LAG(revenue) OVER (ORDER BY day) AS prev
  FROM daily
)
SELECT *
FROM x
WHERE prev IS NOT NULL
  AND revenue < prev * 0.7;

------------------------------------------------------------------------------------------------------
Question 131: Find users who made purchases in 3 consecutive months

WITH months AS (
  SELECT user_id, date_trunc('month', created_at) m
  FROM orders
  WHERE status='paid'
  GROUP BY user_id, date_trunc('month', created_at)
),
seq AS (
  SELECT user_id, m,
         (EXTRACT(YEAR FROM m) * 12 + EXTRACT(MONTH FROM m))
         - ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY m) AS grp
  FROM months
)
SELECT user_id
FROM seq
GROUP BY user_id, grp
HAVING COUNT(*) >= 3;

------------------------------------------------------------------------------------------------------
Question 132: Top 1 product per category by revenue

WITH prod_rev AS (
  SELECT p.category, p.id, p.name,
         SUM(oi.quantity * oi.price) AS revenue
  FROM products p
  JOIN order_items oi ON oi.product_id = p.id
  GROUP BY p.category, p.id, p.name
),
ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY category ORDER BY revenue DESC) rn
  FROM prod_rev
)
SELECT category, id, name, revenue
FROM ranked
WHERE rn = 1;

------------------------------------------------------------------------------------------------------
Question 133: Find orders where payment happened before order creation (data bug)

SELECT o.id, o.created_at AS order_time, p.created_at AS payment_time
FROM orders o
JOIN payments p ON p.order_id = o.id
WHERE p.created_at < o.created_at;


------------------------------------------------------------------------------------------------------
Question 134: Find users with increasing order amounts (strictly increasing sequence)

WITH x AS (
  SELECT o.*,
         LAG(total_amount) OVER (PARTITION BY user_id ORDER BY created_at) AS prev_amt
  FROM orders o
  WHERE status='paid'
)
SELECT user_id
FROM x
GROUP BY user_id
HAVING BOOL_AND(prev_amt IS NULL OR total_amount > prev_amt);

------------------------------------------------------------------------------------------------------
Question 135: Find users who placed orders on weekends only

SELECT user_id
FROM orders
GROUP BY user_id
HAVING BOOL_AND(EXTRACT(DOW FROM created_at) IN (0,6));

------------------------------------------------------------------------------------------------------
Question 136: Calculate running total revenue per user over time

SELECT user_id, created_at, total_amount,
       SUM(total_amount) OVER (PARTITION BY user_id ORDER BY created_at) AS running_total
FROM orders
WHERE status='paid'
ORDER BY user_id, created_at;

------------------------------------------------------------------------------------------------------
Question 137: Sessionize events (new session after 30 mins idle)

WITH x AS (
  SELECT e.*,
         LAG(created_at) OVER (PARTITION BY user_id ORDER BY created_at) AS prev_time
  FROM events e
),
y AS (
  SELECT *,
         CASE WHEN prev_time IS NULL OR created_at - prev_time > INTERVAL '30 minutes'
              THEN 1 ELSE 0 END AS new_session
  FROM x
),
z AS (
  SELECT *,
         SUM(new_session) OVER (PARTITION BY user_id ORDER BY created_at) AS session_id
  FROM y
)
SELECT user_id, session_id,
       MIN(created_at) AS session_start,
       MAX(created_at) AS session_end,
       COUNT(*) AS events_count
FROM z
GROUP BY user_id, session_id
ORDER BY user_id, session_id;

------------------------------------------------------------------------------------------------------
Question 138: Find users whose last order is older than 90 days

SELECT user_id, MAX(created_at) AS last_order_at
FROM orders
GROUP BY user_id
HAVING MAX(created_at) < NOW() - INTERVAL '90 days';

------------------------------------------------------------------------------------------------------
Question 139: Find products with price above category average

WITH cat_avg AS (
  SELECT category, AVG(price) avg_price
  FROM products
  GROUP BY category
)
SELECT p.*
FROM products p
JOIN cat_avg a ON a.category = p.category
WHERE p.price > a.avg_price;

------------------------------------------------------------------------------------------------------
Question 140: Find “power users”: top 5% users by order count

WITH cnt AS (
  SELECT user_id, COUNT(*) AS order_count
  FROM orders
  GROUP BY user_id
),
x AS (
  SELECT *,
         NTILE(20) OVER (ORDER BY order_count DESC) AS bucket
  FROM cnt
)
SELECT user_id, order_count
FROM x
WHERE bucket = 1;

------------------------------------------------------------------------------------------------------
Question 141: Gap detection: find missing order IDs

SELECT t.id + 1 AS missing_id
FROM orders t
LEFT JOIN orders t2 ON t2.id = t.id + 1
WHERE t2.id IS NULL
ORDER BY missing_id;

------------------------------------------------------------------------------------------------------
Question 142: Find duplicate products by name (case-insensitive)

SELECT LOWER(name) AS key_name, COUNT(*)
FROM products
GROUP BY LOWER(name)
HAVING COUNT(*) > 1;

------------------------------------------------------------------------------------------------------
Question 143: Update duplicates: keep latest, mark older as archived (conceptual)

WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (PARTITION BY LOWER(email) ORDER BY created_at DESC) rn
  FROM users
)
UPDATE users
SET archived = true
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

------------------------------------------------------------------------------------------------------
Question 144: Return percentage of paid orders out of all orders per day

SELECT day,
       paid_count,
       total_count,
       ROUND(paid_count * 100.0 / total_count, 2) AS paid_pct
FROM (
  SELECT DATE(created_at) day,
         COUNT(*) FILTER (WHERE status='paid') AS paid_count,
         COUNT(*) AS total_count
  FROM orders
  GROUP BY day
) x
ORDER BY day;

------------------------------------------------------------------------------------------------------
Question 145: Find users who ordered but never paid

SELECT o.user_id
FROM orders o
LEFT JOIN payments p ON p.order_id = o.id AND p.status='success'
GROUP BY o.user_id
HAVING COUNT(o.id) > 0 AND COUNT(p.id) = 0;

------------------------------------------------------------------------------------------------------
Question 146: Find first purchase date per user
SELECT user_id, MIN(created_at) AS first_purchase_at
FROM orders
WHERE status='paid'
GROUP BY user_id;

------------------------------------------------------------------------------------------------------
Question 147: Cohort: users grouped by signup month, count paid orders in month+1

WITH cohort AS (
  SELECT id AS user_id, date_trunc('month', created_at) cohort_month
  FROM users
),
orders_m1 AS (
  SELECT user_id, date_trunc('month', created_at) order_month
  FROM orders
  WHERE status='paid'
)
SELECT c.cohort_month,
       COUNT(DISTINCT c.user_id) AS users_in_cohort,
       COUNT(o.user_id) FILTER (WHERE o.order_month = c.cohort_month + INTERVAL '1 month') AS orders_next_month
FROM cohort c
LEFT JOIN orders_m1 o ON o.user_id = c.user_id
GROUP BY c.cohort_month
ORDER BY c.cohort_month;

------------------------------------------------------------------------------------------------------
Question 148: Find churned users: active last month but not this month

WITH last_month AS (
  SELECT DISTINCT user_id
  FROM orders
  WHERE created_at >= date_trunc('month', NOW()) - INTERVAL '1 month'
    AND created_at <  date_trunc('month', NOW())
),
this_month AS (
  SELECT DISTINCT user_id
  FROM orders
  WHERE created_at >= date_trunc('month', NOW())
)
SELECT l.user_id
FROM last_month l
LEFT JOIN this_month t ON t.user_id = l.user_id
WHERE t.user_id IS NULL;

------------------------------------------------------------------------------------------------------
Question 149: Find order totals using items and compare to stored total (performance)

SELECT o.id, o.total_amount, t.calc_total
FROM orders o
JOIN (
  SELECT order_id, SUM(quantity * price) calc_total
  FROM order_items
  GROUP BY order_id
) t ON t.order_id = o.id
WHERE o.total_amount <> t.calc_total;

------------------------------------------------------------------------------------------------------
Question 150: Return first and last order per user with amounts

SELECT user_id,
       FIRST_VALUE(total_amount) OVER w AS first_amt,
       LAST_VALUE(total_amount)  OVER w AS last_amt
FROM orders
WINDOW w AS (PARTITION BY user_id ORDER BY created_at
             ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING);

------------------------------------------------------------------------------------------------------
Question 151: Median order amount (Postgres percentile)

SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_amount) AS median
FROM orders
WHERE status='paid';

------------------------------------------------------------------------------------------------------
Question 152: Find users who placed order every day for last 7 days

WITH d AS (
  SELECT user_id, DATE(created_at) day
  FROM orders
  WHERE created_at >= NOW() - INTERVAL '7 days'
  GROUP BY user_id, DATE(created_at)
)
SELECT user_id
FROM d
GROUP BY user_id
HAVING COUNT(*) = 7;

------------------------------------------------------------------------------------------------------
Question 153: Find the 95th percentile latency-like metric (example from events)

SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY (meta->>'latency_ms')::int) AS p95
FROM events
WHERE event_name='api_call';

------------------------------------------------------------------------------------------------------
Question 154: Find “repeat buyers”: users with orders in >= 2 different months

SELECT user_id
FROM (
  SELECT user_id, date_trunc('month', created_at) m
  FROM orders
  WHERE status='paid'
  GROUP BY user_id, date_trunc('month', created_at)
) x
GROUP BY user_id
HAVING COUNT(*) >= 2;

------------------------------------------------------------------------------------------------------
Question 155: Find products where sales dropped week-over-week

WITH weekly AS (
  SELECT oi.product_id,
         date_trunc('week', o.created_at) wk,
         SUM(oi.quantity) qty
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  GROUP BY oi.product_id, wk
),
x AS (
  SELECT *,
         LAG(qty) OVER (PARTITION BY product_id ORDER BY wk) prev_qty
  FROM weekly
)
SELECT *
FROM x
WHERE prev_qty IS NOT NULL AND qty < prev_qty;

------------------------------------------------------------------------------------------------------
Question 156: Find orders that contain at least 3 unique products

SELECT order_id
FROM order_items
GROUP BY order_id
HAVING COUNT(DISTINCT product_id) >= 3;

------------------------------------------------------------------------------------------------------
Question 157: Find users whose last 2 orders are both refunds/failed

WITH ranked AS (
  SELECT o.*,
         ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) rn
  FROM orders o
)
SELECT user_id
FROM ranked
WHERE rn <= 2
GROUP BY user_id
HAVING BOOL_AND(status IN ('failed','refunded'));

------------------------------------------------------------------------------------------------------
Question 158: Efficient pagination (keyset pagination) by created_at + id

SELECT *
FROM orders
WHERE (created_at, id) < (:last_created_at, :last_id)
ORDER BY created_at DESC, id DESC
LIMIT 20;

------------------------------------------------------------------------------------------------------
Question 159: Find “orphan payments” where order missing

SELECT p.*
FROM payments p
LEFT JOIN orders o ON o.id = p.order_id
WHERE o.id IS NULL;


------------------------------------------------------------------------------------------------------
Question 160: Find users with same email domain, count them

SELECT split_part(email, '@', 2) AS domain, COUNT(*) cnt
FROM users
GROUP BY domain
ORDER BY cnt DESC;

------------------------------------------------------------------------------------------------------
Question 161: Find average time between signup and first order

WITH first_order AS (
  SELECT user_id, MIN(created_at) first_order_at
  FROM orders
  WHERE status='paid'
  GROUP BY user_id
)
SELECT AVG(f.first_order_at - u.created_at) AS avg_delay
FROM users u
JOIN first_order f ON f.user_id = u.id;

------------------------------------------------------------------------------------------------------
Question 162: Find products that contribute to 80% revenue (Pareto)

WITH prod AS (
  SELECT p.id, p.name,
         SUM(oi.quantity * oi.price) rev
  FROM products p
  JOIN order_items oi ON oi.product_id = p.id
  GROUP BY p.id, p.name
),
x AS (
  SELECT *,
         SUM(rev) OVER () total_rev,
         SUM(rev) OVER (ORDER BY rev DESC) running_rev
  FROM prod
)
SELECT id, name, rev
FROM x
WHERE running_rev <= total_rev * 0.8
ORDER BY rev DESC;

------------------------------------------------------------------------------------------------------
Question 163: Find users who made the very first order of each day

SELECT *
FROM (
  SELECT o.*,
         ROW_NUMBER() OVER (PARTITION BY DATE(created_at) ORDER BY created_at) rn
  FROM orders o
) x
WHERE rn = 1;

------------------------------------------------------------------------------------------------------
Question 164: Find “stuck orders”: pending > 1 hour with no payment attempts

SELECT o.*
FROM orders o
LEFT JOIN payments p ON p.order_id = o.id
WHERE o.status='pending'
  AND o.created_at < NOW() - INTERVAL '1 hour'
  AND p.id IS NULL;

------------------------------------------------------------------------------------------------------
Question 165: Find users whose order amounts vary a lot (high stddev)

SELECT user_id, STDDEV_POP(total_amount) AS std
FROM orders
WHERE status='paid'
GROUP BY user_id
HAVING STDDEV_POP(total_amount) > 500;

------------------------------------------------------------------------------------------------------
Question 166: Find top 10 fastest-growing products month-over-month

WITH m AS (
  SELECT oi.product_id,
         date_trunc('month', o.created_at) mon,
         SUM(oi.quantity) qty
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  GROUP BY oi.product_id, mon
),
x AS (
  SELECT *,
         LAG(qty) OVER (PARTITION BY product_id ORDER BY mon) prev_qty
  FROM m
)
SELECT product_id, mon, qty, prev_qty,
       (qty - prev_qty) AS growth
FROM x
WHERE prev_qty IS NOT NULL
ORDER BY growth DESC
LIMIT 10;

------------------------------------------------------------------------------------------------------
Question 167: Find users with overlapping duplicate events within 5 seconds (fraud)

WITH x AS (
  SELECT e.*,
         LAG(created_at) OVER (PARTITION BY user_id, event_name ORDER BY created_at) prev_time
  FROM events e
)
SELECT *
FROM x
WHERE prev_time IS NOT NULL
  AND created_at - prev_time <= INTERVAL '5 seconds';


------------------------------------------------------------------------------------------------------
Question 168: Optimize query: filter early before join (pattern)
Task: Only join paid orders from last 30 days.

WITH recent_paid AS (
  SELECT *
  FROM orders
  WHERE status='paid'
    AND created_at >= NOW() - INTERVAL '30 days'
)
SELECT u.id, u.name, SUM(r.total_amount) rev
FROM users u
JOIN recent_paid r ON r.user_id = u.id
GROUP BY u.id, u.name;

------------------------------------------------------------------------------------------------------
Question 169: Find “multi-cart” orders: same user placed multiple orders within 10 minutes

WITH x AS (
  SELECT o.*,
         LAG(created_at) OVER (PARTITION BY user_id ORDER BY created_at) prev_time
  FROM orders o
)
SELECT *
FROM x
WHERE prev_time IS NOT NULL
  AND created_at - prev_time <= INTERVAL '10 minutes';

------------------------------------------------------------------------------------------------------
Question 170: Find most common product pair bought together (advanced)

SELECT LEAST(a.product_id, b.product_id) p1,
       GREATEST(a.product_id, b.product_id) p2,
       COUNT(*) cnt
FROM order_items a
JOIN order_items b
  ON a.order_id = b.order_id
 AND a.product_id < b.product_id
GROUP BY p1, p2
ORDER BY cnt DESC
LIMIT 1;

------------------------------------------------------------------------------------------------------
Question 171: Find users who bought same product 3+ times on different dates

WITH x AS (
  SELECT o.user_id, oi.product_id, DATE(o.created_at) d
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.id
  WHERE o.status='paid'
  GROUP BY o.user_id, oi.product_id, DATE(o.created_at)
)
SELECT user_id, product_id
FROM x
GROUP BY user_id, product_id
HAVING COUNT(*) >= 3;

------------------------------------------------------------------------------------------------------
Question 172: Identify slow query cause: missing index suggestion (pattern)
Task query

SELECT *
FROM orders
WHERE user_id = 10
ORDER BY created_at DESC
LIMIT 20;

Suggested index:
CREATE INDEX idx_orders_user_created_at ON orders(user_id, created_at DESC);

------------------------------------------------------------------------------------------------------
Question 173: Find orders that are “payments anomaly”: multiple successful payments

SELECT order_id, COUNT(*) AS success_payments
FROM payments
WHERE status='success'
GROUP BY order_id
HAVING COUNT(*) > 1;
