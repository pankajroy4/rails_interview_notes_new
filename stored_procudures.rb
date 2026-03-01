=================== BASIC STRUCTURE OF STORED PROCEDURES (MYSQL) ==================================
🔸Creating procedure:

    DELIMITER //
    CREATE PROCEDURE procedure_name()
    BEGIN
      -- SQL statements
    END //
    DELIMITER ;

🔸Calling Procedure:
    CALL procedure_name();

Example: Return All Active Users

  DELIMITER //
  CREATE PROCEDURE get_active_users()
  BEGIN
    SELECT * FROM users WHERE status = 'active';
  END //
  DELIMITER ;

  We can call it like:
    CALL get_active_users();

  We have to change the delimiter because MySQL normally ends statements with ;
  But procedure contains multiple ;
  So we temporarily change delimiter to // , we can change it to any smybol.
  In last we reset the delimiter to default i.e ;

🔸Parameters in Stored Procedures:
  There are three types of parameters in Stored Procedures.

    | Type  |        Meaning        |
    |-------|-----------------------|
    | IN    | Input parameter       |
    | OUT   | Output parameter      |
    | INOUT | Both input and output |

🔸IN Parameter:
    It is Default type.
    Used to pass value into procedure.
    An IN parameter cannot be modified outside the procedure

    It means:
      The procedure receives a copy of the value.
      Any changes made to that parameter inside the procedure do not affect the original variable in the caller.

    DELIMITER //
    CREATE PROCEDURE get_user_by_id(IN user_id INT)
    BEGIN
      SELECT * FROM users WHERE id = user_id;
    END //
    DELIMITER ;

    We can call it like:
      CALL get_user_by_id(5);

🔸OUT Parameter:
    Used to return value back from procedure.

    DELIMITER //
    CREATE PROCEDURE GetUserCount(OUT total INT)
    BEGIN
        SELECT COUNT(*) INTO total FROM users;
    END //
    DELIMITER ;

    Call it:
      CALL GetUserCount(@count);
      SELECT @count;

🔸INOUT Parameter:
  Acts as both input and output.

    DELIMITER //
    CREATE PROCEDURE IncreaseValue(INOUT num INT)
    BEGIN
        SET num = num + 10;
    END //
    DELIMITER ;

    Call it:
      SET @number = 5;
      CALL IncreaseValue(@number);
      SELECT @number;  

    We will get output: 15

🔸Transactions Inside Procedure
  Stored procedures fully support transactions.
  We can use: START TRANSACTION, COMMIT, ROLLBACK

  Example:

    DELIMITER //
    CREATE PROCEDURE TransferMoney(
        IN from_user INT,
        IN to_user INT,
        IN amount DECIMAL(10,2)
    )
    BEGIN
        DECLARE current_balance DECIMAL(10,2);

        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            ROLLBACK;
        END;

        START TRANSACTION;

        -- Get current balance
        SELECT balance INTO current_balance
        FROM accounts
        WHERE id = from_user
        FOR UPDATE;

        -- Check sufficient balance
        IF current_balance < amount THEN
            ROLLBACK;
        ELSE
            UPDATE accounts 
            SET balance = balance - amount 
            WHERE id = from_user;

            UPDATE accounts 
            SET balance = balance + amount 
            WHERE id = to_user;

            COMMIT;
        END IF;

    END //
    DELIMITER ;


  If you want to raise an error when balance is insufficient:

    IF current_balance < amount THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient balance';
    END IF;

  This will automatically trigger the EXIT HANDLER and rollback.

🔸Stored Procedure with Logic:
  Stored procedures support:
    IF
    CASE
    LOOP
    WHILE
    Variables
    Error handling

  Example:

    DELIMITER //
    CREATE PROCEDURE check_user_status(IN user_id INT)
    BEGIN
      DECLARE user_status VARCHAR(20);

      SELECT status INTO user_status
      FROM users
      WHERE id = user_id;

      IF user_status = 'active' THEN
          SELECT 'User is active';
      ELSE
          SELECT 'User is inactive';
      END IF;

    END //
    DELIMITER ;

======================================================================================================
Question 1: What is Stored Procedure?
Answer 1: A stored procedure is a precompiled SQL program stored inside the database. It allows us to encapsulate complex SQL logic, accept parameters, and execute multiple queries in a single call.

It improves performance because the execution plan is cached, reduces network round trips, and enhances security since users can execute the procedure without direct table access.

Stored procedures support variables, loops, conditional statements, and transactions, making them suitable for complex business logic, reporting, or bulk operations.

However, in frameworks like Rails, we typically keep business logic in the application layer unless there is a performance-critical requirement.


Answer 2: A stored procedure is a precompiled set of SQL statements stored inside the database that can be executed by calling its name.

Instead of sending multiple SQL queries from the application, we can write the logic once inside the database as a stored procedure and reuse it.

It can contain:
  SQL queries (SELECT, INSERT, UPDATE, DELETE)
  Conditional logic (IF, CASE)
  Loops
  Transactions
  Error handling

-------------------------------------------------------------------------------------------------------------
Question 2: What are the Benefits of Stored Procedures?
Answer:
  🔸Performance:
    Stored procedures are precompiled.
    Execution plan is cached.
    Reduces network round trips between app and database.

  🔸Reusability:
    Centralized logic.
    Multiple applications can call the same procedure.

  🔸Security:
    Users can be given permission to execute procedure without giving direct table access.
    Helps prevent SQL injection if used properly.

  🔸Maintainability:
    Business logic inside DB can be updated without redeploying application.

  🔸Reduced Network Traffic:
    Instead of sending multiple SQL statements, we send a single CALL statement.



Spoken Answer:
  I would avoid stored procedures in the following cases:

    ➤When Business Logic Changes Frequently:
      If requirements change often, maintaining logic inside the database becomes harder because:
        Version control is weaker compared to application code.
        CI/CD pipelines are more complex.
        Deployment becomes tightly coupled with DB changes.
        For fast-moving startup environments, application-layer logic is usually better.

    ➤When You Want Database Portability
      Stored procedures are database-specific.
      MySQL procedures are different from PostgreSQL procedures or SQL Server procedures

      If we plan to switch databases later, heavy use of stored procedures increases migration cost.

    ➤When Application Logic Is Complex
      Complex business workflows:
        External API calls
        Background jobs
        Caching (Redis)
        Messaging queues

      These are better handled in application code, not in the database.

    ➤When It Hurts Testability
      In Rails, I can easily:
        Write RSpec tests
        Mock dependencies
        Use service objects

      Testing stored procedures is harder and less integrated into the app’s testing framework.

------------------------------------------------------------------------------------------------------------
Question 3: Write a stored procedure that pauses invoice payments if total exceeds certain amount.
Answer:
  DELIMITER //
  CREATE PROCEDURE pause_large_invoices(IN limit_amount DECIMAL(10,2))
  BEGIN
    UPDATE invoices
    SET paused_payment = TRUE
    WHERE total_amount > limit_amount;
  END //
  DELIMITER ;

  Call it like:
    CALL pause_large_invoices(10000);

-------------------------------------------------------------------------------------------------------------
Question 4: Stored Procedure vs Function
Answer: The main difference is that a function must return exactly one value and can be used inside a SELECT statement, while a stored procedure may return multiple values or result sets and cannot be directly used inside SELECT.
Procedures are generally used for performing actions like inserts or updates, while functions are used for computations.


                |       Stored Procedure          |       Function        |
                | ------------------------------- | --------------------- |
                | Can return multiple result sets | Returns single value  |
                | Called using CALL               | Used in SELECT        |
                | Can modify data                 | Usually returns value |
                | More flexible                   | More restrictive      |



    |   Feature      |        Stored Procedure             |            Function                    |
    | -------------- | ----------------------------------- | -------------------------------------- |
    | Return value   | May return 0, 1, or multiple values | Must return exactly one value          |
    | Used in SELECT | Cannot be used inside SELECT        | Can be used inside SELECT              |
    | Call method    | CALL procedure_name()               | SELECT function_name()                 |
    | Transactions   | Can use transactions                | Cannot commit/rollback inside function |
    | Purpose        | Complex operations                  | Calculations                           |
  

  Example for Function:
    CREATE FUNCTION get_user_count()
    RETURNS INT
    DETERMINISTIC
    RETURN (SELECT COUNT(*) FROM users);

  We can use this like:
    SELECT get_user_count();

------------------------------------------------------------------------------------------------------------
Question 5:When NOT to Use Stored Procedures?
Answer: We should not use SP:
  When business logic changes frequently
  When app is microservice based
  When using ORMs like ActiveRecord heavily
  When you want database portability

  Because stored procedures are database-specific.
  
  In Rails ecosystem we usually keep business logic in models/services, but for performance-critical reporting or bulk data processing, stored procedures can be beneficial.
    
-----------------------------------------------------------------------------------------------------------------
Question 6: Where Should Business Logic Live — DB or Application?
Answer: In most modern architectures, I believe core business logic should live in the application layer, not the database.

The database should mainly be responsible for storing data, enforcing constraints, managing indexes, and handling heavy data processing. Its job is to protect and efficiently manage the data itself.

The reason I prefer keeping business logic in the application layer is that it’s much easier to version control, properly test, and maintain. It also creates a clean separation of concerns, which makes the system easier to understand and onboard new developers into.

For example, in a Rails-style architecture, models typically handle data-related logic, services manage business workflows, and controllers handle orchestration. That structure keeps responsibilities clear and organized.

However, there are situations where database-level logic absolutely makes sense. If data integrity is critical and the logic must always run no matter which application touches the database, then putting it in the database can be the safer choice. It is also useful for high-performance bulk operations, complex reporting queries, or batch processing millions of rows — cases where pushing work closer to the data improves performance.

So overall, I would say: default to keeping business logic in the application layer, but use the database strategically when integrity or performance truly requires it.

-----------------------------------------------------------------------------------------------------------------
Question 7: What are the Performance Tradeoffs of Stored procedure?
Answer: When we talk about performance tradeoffs, stored procedures can absolutely provide real advantages — but they come with architectural costs.

On the performance side, one major benefit is reduced network latency. Instead of the application making multiple round trips to the database, it can make a single call to a stored procedure. That cuts down network overhead significantly, especially in chatty systems.

Another advantage is execution plan caching. Stored procedures are precompiled and their execution plans are often cached by the database engine. That can reduce parsing and planning time for frequently executed operations.

They are also very efficient for bulk operations. If you are looping over large datasets or doing batch updates, executing that logic inside the database is typically much faster than pulling data into the application and sending multiple update calls back. Keeping the computation close to the data minimizes I/O overhead.

However, there are important downsides.

First, horizontal scaling becomes harder. If most of your business logic lives in the database, scaling the application layer will not relieve pressure. The database becomes the bottleneck, and scaling databases horizontally is much more complex than scaling stateless app servers.

Second, you increase database CPU load. The database is no longer just a data store — it becomes a compute engine. That can impact overall system stability and performance under load.

And third, caching strategies become more complicated. When logic lives in the application layer, it is easier to use tools like Redis to cache computed results. But when the computation happens inside stored procedures, it is harder to intercept and cache at the application level.

So my summary would be: stored procedures can reduce network overhead and improve performance for certain workloads, but they centralize computation in the database. That can improve efficiency in the short term, but it may hurt scalability and architectural flexibility in the long run.

--------------------------------------------------------------------------------------------------------------
Question 8: How Do Stored Procedures Affect Scaling in Microservices?

Answer: In a microservices architecture, heavy use of stored procedures can create tight coupling to a specific database, which goes against some core microservices principles.

Ideally, each microservice should own its data and be able to scale independently. But if a lot of the business logic lives inside the database, then scaling the application instances does not actually scale the logic. The database becomes the bottleneck.

It also reduces flexibility. In microservices, we often want polyglot persistence — meaning different services can choose different types of databases depending on their needs. But if business logic is embedded in stored procedures tied to one database technology, that flexibility disappears.

There are a few major concerns here.

First, the database can become a centralized bottleneck. In microservices, we are trying to avoid creating another monolith — especially at the data layer. If multiple services rely heavily on shared stored procedures, the database effectively becomes a monolithic dependency.

Second, independent deployments become harder. If you change a stored procedure that multiple services depend on, you risk breaking them. That tight coupling reduces service autonomy.

Third, putting cross-service logic inside the database is generally considered an anti-pattern. Microservices should communicate through well-defined APIs or events — not through shared database procedures.

That said, stored procedures are still acceptable in certain situations. Within a single service boundary, they can make sense — especially for performance-critical batch jobs or reporting workloads where efficiency matters.

So my closing view would be: in monolithic architectures, stored procedures can be very powerful and practical. But in microservices, we need to be cautious, because they increase database coupling and reduce service independence — which are exactly the things microservices are trying to avoid.

---------------------------------------------------------------------------------------------------------------
Question 9: Design a high-volume order processing system — where would you use stored procedures?

Answer: For a high-volume e-commerce system handling around 10,000 to 50,000 orders per minute, I’d design it as a distributed architecture.

At a high level, I would have an API layer sitting in front of dedicated services like an Order Service, Payment Service, and Inventory Service. Each service would own its own database. I’d use a message queue like Kafka or RabbitMQ for asynchronous communication, Redis for caching, and background workers for async processing like email notifications or shipment updates.

Now, the important architectural decision: I would not put the core business workflow inside stored procedures.

Things like order validation, applying discounts, calling the payment provider, handling retries, or orchestrating multi-step workflows — that logic belongs in the application layer. It needs to be testable, version-controlled, and independently deployable.

However, there are very specific places where I would use stored procedures.

The first is inventory reservation, which is a critical section in a high-volume system. When an order comes in, we need to check stock, deduct it, and fail immediately if there is not enough inventory. That operation must be atomic, race-condition safe, and extremely fast.

In that case, a stored procedure wrapping the stock check and deduction inside a single transaction makes sense. It reduces round trips between the application and database, guarantees atomicity, and runs close to the data.

The second place I would use stored procedures is for bulk settlement or end-of-day reconciliation. If I am processing millions of rows to aggregate sales data or update reporting tables, doing that inside the database is far more efficient than pulling data into the application layer.

Third, financial ledger updates are another strong candidate. If I need strict ACID guarantees across multiple writes, encapsulating that in a transaction inside a stored procedure can provide stronger consistency and reduce risk.

Where I would not use stored procedures is for business rule validation, discount logic, coupon engines, external API calls, or workflow orchestration. Those need flexibility and frequent changes, so they belong in the application layer.

So my overall philosophy is: in a high-volume system, use stored procedures only for performance-critical, data-intensive, atomic operations — but keep orchestration and business workflows in the application layer for scalability and maintainability.

-------------------------------------------------------------------------------------------------------------
Question 10: How Would You Refactor a Legacy System That Heavily Uses Stored Procedures?

Answer: That is a migration strategy question, and the key thing is: I would not rewrite everything. That is risky, expensive, and usually unnecessary.

Instead, I would take an incremental and structured approach.

First, I would audit and categorize all stored procedures. Not all procedures are equal. I would classify them into data-heavy batch operations, core business logic, utility or helper procedures, and reporting queries. The goal is to understand what each one actually does before deciding whether it should be moved.

Second, I would analyze risk and coupling. I would ask questions like: Which procedures are called by multiple services? Which ones contain complex branching logic? Which change frequently? Which are performance-critical? That helps me prioritize what should be refactored versus what should remain in place.

For the actual refactoring strategy, I would start by extracting business logic into the application layer. If a stored procedure contains complex IF/ELSE rules, pricing calculations, or business conditions, that logic likely belongs in service objects — especially in something like a Rails architecture. I would reimplement that logic in the application layer while keeping the database interactions simple and focused on persistence.

At the same time, I would not remove performance-critical procedures blindly. If a procedure processes millions of rows efficiently, leverages optimized indexing, and has proven performance value, I would likely keep it. Refactoring should improve maintainability without degrading performance.

Another important step is proper version control. I would move procedure definitions into migration files or version-controlled SQL scripts and integrate them into the CI pipeline. That way, database logic becomes traceable and reviewable like application code.

Before changing anything, I would also add strong test coverage. I would write integration tests to capture current behavior so that we do not introduce regressions during the migration.

And instead of replacing procedures immediately, I would use a safe migration strategy. I would implement the new application-based logic, run both versions in parallel — maybe in shadow mode — compare outputs, monitor performance, and then gradually switch over.

So overall, I would not eliminate stored procedures blindly. I would separate data-intensive logic from business orchestration, move what clearly belongs in the application layer, and retain what genuinely benefits from being close to the data. The goal is better maintainability and scalability — without sacrificing stability or performance.