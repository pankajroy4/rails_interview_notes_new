🔸Aggregate Functions (Used with GROUP BY):
  These operate on multiple rows and return a single value.
    COUNT()
    SUM()
    AVG()
    MIN()
    MAX()

  Example: SELECT SUM(salary) FROM employees;

🔸Comparison Operators (Used in WHERE / HAVING):
    =        -- equal
    !=       -- not equal
    <>       -- not equal (standard SQL)
    >        -- greater than
    <        -- less than
    >=       -- greater than or equal
    <=       -- less than or equal

  Example: WHERE age > 25

🔸Logical Operators:
    AND
    OR
    NOT

  Example: WHERE age > 25 AND city = 'Mumbai'

🔸Range & Set Operators
    BETWEEN        -- range check
    NOT BETWEEN
    IN             -- matches any value in list
    NOT IN

  Example:  WHERE age BETWEEN 20 AND 30
            WHERE city IN ('Mumbai', 'Delhi')

🔸Pattern Matching
    LIKE
    NOT LIKE
    ILIKE        -- case-insensitive (PostgreSQL) - MySQL does not support ILIKE.
    SIMILAR TO
    ~            -- regular expressions

  ➤Wildcards:
    %  -- any number of characters
    _  -- single character

    Examples:
    ➤1:Starts With, Ends with and Contains: 

      SELECT * FROM users
      WHERE name LIKE 'Pan%';

    % → matches any sequence of characters

    'Pan%' → means string starts with "Pan"
    '%ar' → means string ends with "ar"
    '%abc%' → means string contains with "abc"

    SELECT * FROM users
    WHERE name LIKE 'P_n'

    _ (underscore) Matches exactly one character.
    It will match strings of length 3, starts with P and ends with n.
    It will match something like: Pan,Pin,Pun
    It will not match: Paan,Piin,Puan, Pansa

    SELECT * FROM users
    WHERE name LIKE 'P__'

    It will match strings of length 3, start with P
    It will match: Paa, Pbc etc.
    It will not match: Abc, Apdcs etc.

    ➤1:Combining _ and %

      SELECT * FROM users
      WHERE name LIKE 'P__%'

      It means:
        Starts with P.
        Next 2 characters anything.
        Then anything any number of times.

      '_a%' It means second character must be 'a'

    ➤1:Escaping Special Characters:
      We use escaping i.e (\) when we need to match Special symbol like _ , %

        SELECT * FROM 
        WHERE name LIKE '100\%' ESCAPE '\'

      Without ESCAPE, % acts as wildcard'.

    NOTE: Indexing can only work when prefix is fixed.
          'abc%'  -> Here Indexing will be used.
          '_bc%'	-> Here Indexing will not be used.
          '%abc'	-> Here Indexing will not be used.

🔸Regex Pattern Symbols:
  NOTE: Indexing do not works in regex. Regex normally causes full table scan unless combined with trigram index.

  Regex is used with:
    column ~ 'pattern'
    column ~* 'pattern'  -- case insensitive
  
  🔹Anchors:
      ^	      :Start of string
      $	      :End of string
      .       :Matches exactly one character. Same idea of _ (underscore)
      !       :Negation (i.e not match)
      [ ]     :Character Classes

  🔹 Quantifiers
      *	      :0 or more
      +	      :1 or more
      ?	      :0 or 1 (Optional)
      {n}	    :Exactly n
      {n,m}	  :Between n and m
  
  Examples:
      WHERE name ~ '^Pan'             -> Starts With Pan
      WHERE name ~ 'kumar$'           -> Ends With kumar
      WHERE name ~* '^Pan'            -> Starts With Pan (Case-Insensitive)
      WHERE name ~ '[0-9]'            -> Contains Digit
      WHERE name !~ '[0-9]'.          -> Does not Contains Digit
      WHERE name ~ '[A-Za-z]'         -> Contains Alphabets
      WHERE name ~ '^P[a-z]{2,5}$'    -> The string must start with P, followed by 2 to 5 lowercase letters, and nothing else. So Total length = 1 (P) + 2 to 5 letters = 3 to 6 characters

      WHERE name ~ '^[A-Za-z]+$'.     -> The name must contain only English alphabet letters (A-Z, a-z) and must be at least one character long.

🔸Performance Note:
  LIKE 'prefix%' → can use index (B-tree)
  LIKE '%suffix' → cannot use index efficiently

  Leading wildcard (%abc) → full table scan

  Index do not works in regex. Regex normally causes full table scan unless combined with trigram index.
  If performance matters:
    Use prefix%
    Or use pg_trgm extension for suffix/contains search

    Example:
      CREATE EXTENSION pg_trgm;
      CREATE INDEX idx_users_name_trgm ON users USING gin (name gin_trgm_ops);

  🔹ILIKE (Case-Insensitive LIKE)
    WHERE name ILIKE 'pan%'  -> PostgreSQL specific.
    Equivalent to: LOWER(name) LIKE LOWER('pan%')
    
    Index will not be used unless you create a functional index:
      CREATE INDEX idx_users_lower_name ON users (LOWER(name));

🔸NULL Handling
    IS NULL
    IS NOT NULL
    COALESCE()
    NULLIF()

  Example: WHERE phone IS NULL
           SELECT COALESCE(phone, 'N/A')

🔸String Functions
    UPPER()
    LOWER()
    LENGTH()
    TRIM()
    LTRIM()
    RTRIM()
    SUBSTRING()
    CONCAT()
    REPLACE()

  Example: SELECT UPPER(name) FROM users;

🔸Numeric Functions
    ROUND()
    CEIL() / CEILING()
    FLOOR()
    ABS()
    MOD()
    POWER()
    SQRT()

🔸Date & Time Functions
    NOW()
    CURRENT_DATE
    CURRENT_TIME
    EXTRACT()
    INTERVAL Example: SELECT * FROM orders WHERE created_date >= NOW() - INTERVAL '7 days';
    DATE_PART()
    DATE_TRUNC()

    AGE()         -- PostgreSQL
    DATEDIFF()    -- MySQL
      In PostgreSQL instead of DATEDIFF(), we can use:
        SELECT date2 - date1;  or 
        SELECT AGE(date2, date1);   This calculates the precise interval (years, months, days) between two timestamps

        AGE(timestamp)   This assumes current date for the first argument.

        SELECT AGE('2024-01-01', '2000-01-01'); returns 24 years


    Example: SELECT EXTRACT(YEAR FROM created_at)

🔸Conditional Expressions
    CASE WHEN ... THEN ... END

  Example:
    SELECT 
      CASE 
        WHEN age >= 18 THEN 'Adult'
        ELSE 'Minor'
      END
    FROM users;

🔸Join Keywords
    INNER JOIN
    LEFT JOIN
    RIGHT JOIN
    FULL JOIN
    CROSS JOIN

🔸Sorting & Limiting
    ORDER BY
    ASC
    DESC
    LIMIT
    OFFSET


🔸SQL Clause Order (Syntactic Order):
    SELECT
    FROM
    WHERE
    GROUP BY
    HAVING
    ORDER BY
    LIMIT

🔸Logical Execution Order (How SQL Engine Thinks)
  Even though we write:

    SELECT ...
    FROM ...
    WHERE ...
    ORDER BY ...

  Internally, SQL processes roughly like this:

    FROM → get table data
    WHERE → filter rows
    GROUP BY
    HAVING
    SELECT → choose columns
    ORDER BY → sort final result

  This is the actual order.

🔸FILTER Clause - This is postgres Specific.
  Postgres supports:
    SUM(amount) FILTER (WHERE status = 'paid')
  This is very powerful and not universally supported in all databases.

🔸What Are Window Functions?
    Window functions:
      Operate on a set of rows related to the current row
      Do NOT collapse rows (unlike GROUP BY)
      Use the OVER() clause

    Basic structure:
      FUNCTION_NAME() OVER (
          PARTITION BY column
          ORDER BY column
      )

🔸Ranking Functions
  🔹 ROW_NUMBER():
  🔹 RANK():
  🔹 DENSE_RANK():
  🔹 NTILE(n):
      Divides rows into n equal buckets.

      NTILE(4) OVER (ORDER BY salary DESC)

    Use case: Quartile analysis.

🔸Aggregate Window Functions:
  These look like normal aggregates, but do not collapse rows.
    SUM() OVER ()
    AVG() OVER ()
    COUNT() OVER ()
    MIN() OVER ()
    MAX() OVER ()

🔸Value Functions
  🔹LAG()
    Access previous row.
    Example: LAG(salary) OVER (ORDER BY id)
    Use case: Compare current row with previous.

  🔹LEAD()
    Access next row.
    Example:LEAD(salary) OVER (ORDER BY id)

  🔹FIRST_VALUE()
    FIRST_VALUE(salary) OVER (PARTITION BY department ORDER BY salary DESC)
    
  🔹NTH_VALUE()
  
  🔹LAST_VALUE()
    Returns last value in window frame.
    Important Note: Often requires explicit frame definition.

    ➤Important PostgreSQL-Specific Behavior for LAST_VALUE() 
      In Postgres, LAST_VALUE() can confuse people because of the default frame:
      Default frame is: RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW

      So this:
        LAST_VALUE(salary) OVER (ORDER BY salary)
        Does NOT give the last row of the partition.

      To get true last value:

        LAST_VALUE(salary) OVER (
          ORDER BY salary
          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        )     

      This is commonly asked in interviews.

🔸Difference: GROUP BY vs WINDOW
  ➤GROUP BY:
    Collapses rows	
    Returns 1 row per group
    Cannot mix easily with non-grouped columns

  ➤Window Function
    Keeps all rows
    Returns 1 row per original row
    Can be mix easily with non-grouped columns	

🔸What is the difference between RANK and DENSE_RANK?
  Both assign same rank to tied rows. RANK leaves gaps after ties, while DENSE_RANK does not.

🔸Most Asked Advanced Questions
  Top N per group?
  Running totals?
  Find duplicates using window functions?
  Detect consecutive events?
  Difference between ROWS vs RANGE?

====================================================================================================
🔸What Is a Window Function?
Answer: A window function performs a calculation across a set of rows that are related to the current row — without collapsing rows like GROUP BY does.
  
  🔴GROUP BY:
    Reduces rows
    One output row per group

  🟢Window Function:
    Does NOT reduce rows
    Returns value for each row
    Can “look around” other rows

  Example: Let we have this order table:

        +---------------------------------+
        |  id | user_id |  total_amount   |    
        |---------------------------------|
        |  1  |    1    |       100       |
        |  2  |    1    |       200       |
        |  3  |    2    |       300       |
        |  4  |    2    |       150       |    
        |  5  |    2    |       50        |  
        +---------------------------------+   

    ➤Problem Without Window Function
      Question: Show each order AND also show total spent by that user.
        🔹Using GROUP BY (Wrong for this case):

          SELECT user_id, SUM(total_amount) AS user_total
          FROM orders
          GROUP BY user_id;

          This will be the result. We LOST individual order rows.

            | id | user_total   |
            |-------------------| 
            | 1  |     300      |
            | 2  |     500      |

        🔹Using window function:

          SELECT id, user_id, total_amount,
              SUM(total_amount) OVER (PARTITION BY user_id) AS user_total
          FROM orders;

          This will be the result:

            +--------------------------------------+
            | id |  user_id | total |  user_total  |
            |--------------------------------------|
            | 1  |   1      | 100   |     300      |
            | 2  |   1      | 200   |     300      |
            | 3  |   2      | 300   |     500      |
            | 4  |   2      | 150   |     500      |
            | 5  |   2      | 50    |     500      |
            +--------------------------------------+

          Here, Rows are NOT collapsed. Calculation happens “over a window”.

    ⭐NOTE:
      ➤Without PARTITION BY
        ROW_NUMBER() OVER (ORDER BY total_amount DESC)
      The entire table is one partition

      ➤ORDER BY inside OVER() defines the logical order used to calculate the window function within each partition — it does NOT order the final result set. 
      In simple words - ORDER BY defines the ordering logic within each partition for the window function.

  ╰➤Understanding the Syntax of window function:
      Syntax: 
          FUNCTION() OVER (window_definition)

      Inside the OVER(), we define the window. For window definition we can use:
        🔹PARTITION BY
            Just like GROUP BY, but does NOT collapse rows.

        🔹ORDER BY
            Defines row ordering inside window.

        🔹Frame Clause (Advanced)
            Defines which rows relative to current row are included.

  ╰➤Most Important Window Functions:

    🔸Aggregate Window Functions
      Same as normal aggregates but used with OVER.
        SUM(), AVG(), COUNT(), MIN(), MAX()
      
      Example:
        AVG(total_amount) OVER (PARTITION BY user_id)
    
    🔸Ranking window Functions.
      ROW_NUMBER(), RANK(), DENSE_RANK()
      Ranking resets for each partition. If PARTITION BY is not used then entire table is one partition.

      🔹ROW_NUMBER():
        This function gives unique sequential number to each row within a partition. Numbering resets for each partition.
        Example:

          SELECT id, user_id, total_amount,
            ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY total_amount DESC) AS rank
          FROM orders;

          Result:
            | id | user_id | total_amount |  rank  |
            |----+---------+--------------+--------|
            | 2  |   1     |    200       |    1   |
            | 1  |   1     |    100       |    2   |
            | 3  |   2     |    300       |    1   | -> Ranking resets(Next partition)
            | 4  |   2     |    150       |    2   |
            | 5  |   2     |    50        |    3   |

        Example: Top 3 Salaries Per Department
          SELECT *
          FROM (
            SELECT 
              *,
              ROW_NUMBER() OVER (
                PARTITION BY department 
                ORDER BY salary DESC
              ) AS rn
            FROM employees
          ) sub
          WHERE rn <= 3;

      🔹RANK():
        Within a partition
          It gives the same rank to tied values.
          It skips the next rank number after a tie.
        Ranking resets for each partition.
      
        Suppose we have this table of Order:
          | id | user_id | total_amount |
          |----+---------+--------------|
          | 1  |    2    |    300       |
          | 2  |    2    |    300       |
          | 3  |    2    |    150       |
          | 4  |    3    |    50        |
          | 5  |    3    |    200       |

        Example:
          SELECT id, user_id, total_amount,
            RANK() OVER (PARTITION BY user_id ORDER BY total_amount DESC) AS rank
          FROM orders;

          Result:
            | id | user_id | total_amount | rank |
            |----+---------+--------------+------|
            | 1  |    2    |    300       |   1  |
            | 2  |    2    |    300       |   1  |
            | 3  |    2    |    150       |   3  |  -> Skipped 2
            | 5  |    3    |    200       |   1  |  -> Ranking resets.
            | 4  |    3    |    50        |   2  |

          We can notice that:
            Both 300s get rank 1
            Next rank becomes 3 (rank 2 is skipped)

      🔹DENSE_RANK():
        Within a partition
          It gives the same rank to ties and keeps ranking numbers continuous (no gaps).
        Ranking resets for each partition.

        Suppose we have this table of Order:

          | id | user_id | total_amount |
          |----+---------+--------------|
          | 1  |    2    |     300      |
          | 2  |    2    |     300      |
          | 3  |    2    |     150      |
          | 4  |    3    |     50       |
          | 5  |    3    |     600      |


        Example:
          SELECT id, user_id, total_amount,
            DENSE_RANK() OVER (PARTITION BY user_id ORDER BY total_amount DESC) AS rank
          FROM orders;

          Result:
            | id | user_id | total_amount | rank |
            |----+---------+--------------+------|
            | 1  |    2    |     300      |   1  |
            | 2  |    2    |     300      |   1  |
            | 3  |    2    |     150      |   2  | -> No Skipping.
            | 5  |    3    |     600      |   1  | -> Ranking resets.
            | 4  |    3    |     50       |   2  |

          We can notice:
            Both 300s get rank 1
            Next rank is 2 (no skipping)

    🔸LAG() and LEAD()
      LAG() and LEAD() are window functions used to access data from previous or next rows — without using self joins. It is used to access or compare rows.

    🔸LAG()
      LAG() gives you data from a previous row.
        Syntax:
          LAG(column, offset, default_value)
          OVER (
              PARTITION BY column
              ORDER BY column
          )

          Here: 
            column → what you want from previous row
            offset → how many rows back (default = 1)
            default_value → what to return if no previous row, for eg NULL, N/A etc (Default = NULL)
        
        Example 1: Compare Current Order with Previous Order
          Assume we have this table:
            
            | id | user_id | total_amount |
            |----+---------+--------------|
            | 1  |    1    |    100       |
            | 2  |    1    |    200       |
            | 3  |    1    |    150       |
            | 4  |    2    |    400       |
            | 5  |    2    |    50        |
            | 6  |    2    |    600       |

          SELECT
            id,
            user_id,
            total_amount,
            LAG(total_amount) OVER (
                PARTITION BY user_id
                ORDER BY id
            ) AS previous_amount
          FROM orders;

          Result will be:
            | id | user_id | total_amount | previous_amount |
            |----+---------+--------------+-----------------+
            | 1  |    1    |      100     |     NULL        |
            | 2  |    1    |      200     |     100         |
            | 3  |    1    |      150     |     200         |
            | 4  |    2    |      400     |     NULL        |  -> As we have used PARTITION BY user_id
            | 5  |    2    |      50      |     400         |
            | 6  |    2    |      600     |     50          |

        Example 2. Find difference between current and previous order. This is real use case.
          Assume we have same table as in above example.
           NOTE: 
              anything - NULL = NULL
              NULL - anything = NULL

          SELECT id, total_amount,
            total_amount - LAG(total_amount) OVER (ORDER BY id) AS difference
          FROM orders;

          Result will be:

            | id | user_id | total_amount | difference |
            |----+---------+--------------+------------|
            | 1  |    1    |    100       |   NULL     |
            | 2  |    1    |    200       |   100      |
            | 3  |    1    |    150       |   -50      |
            | 4  |    2    |    400       |   250      |
            | 5  |    2    |    50        |   -350     |
            | 6  |    2    |    600       |   550      |


    🔸LEAD()
        It gives you data from the next row.

        SELECT id, user_id, total_amount,
          LEAD(total_amount) OVER (ORDER BY id) AS next_amount
        FROM orders;

        Result will be:

          | id | user_id  | total_amount | next_amount |
          |----+----------+--------------+-------------|
          | 1  |    1     |    100        |    200     |
          | 2  |    1     |    200        |    150     |
          | 3  |    1     |    150        |    400     |
          | 4  |    2     |    400        |    50      |  -> As we have not used PARTITION BY.
          | 5  |    2     |    50         |    600     |     Whole table as one Partition.
          | 6  |    2     |    600        |    NULL    |
    
    🔸FIRST_VALUE()
      Returns the value of a column from the first row in the window.
      Syntax:
        FIRST_VALUE(column) 
          OVER (
              [PARTITION BY partition_column]
              ORDER BY sort_column
              [ROWS BETWEEN ...]
        )
      
      Here:
        PARTITION BY → optional, groups rows
        ORDER BY → defines row order
        Frame → sometimes important for LAST_VALUE()

      Example: First Order amount Per User
        Let we have this table.

        | id | user_id | total_amount |
        |----+---------+--------------|
        | 1  |    1    |    100       |
        | 2  |    1    |    200       |
        | 3  |    1    |    150       |
        | 4  |    2    |    400       |
        | 5  |    2    |    50        |
        | 6  |    2    |    600       |

        SELECT id, user_id, total_amount,
          FIRST_VALUE(total_amount) OVER (
              PARTITION BY user_id
              ORDER BY id
          ) AS first_order
        FROM orders;

        Result will be: All rows in a partition “see” the first value.

          | id | user_id | total_amount | first_order |
          |----+---------+--------------+-------------|
          | 1  |    1    |    100       |    100      |
          | 2  |    1    |    200       |    100      |
          | 3  |    1    |    150       |    100      |
          | 4  |    2    |    400       |    400      | -> First value for next partition
          | 5  |    2    |    50        |    400      |
          | 6  |    2    |    600       |    400      |

    🔸LAST_VALUE()
      Returns the value of a column from the last row in the window.
      Important Note:
        Default frame = RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        This causes a “gotcha”: LAST_VALUE() might return the current row value, not the true last row unless you adjust the frame.

      Example: Last Order amount Per User
        SELECT id, user_id, total_amount,
          LAST_VALUE(total_amount) OVER (
              PARTITION BY user_id
              ORDER BY id
              ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ) AS last_order
        FROM orders;

        Result will be:
          | id | user_id | total_amount | last_order |
          |----+---------+--------------+------------|
          | 1  |    1    |    100       |    150     |
          | 2  |    1    |    200       |    150     |
          | 3  |    1    |    150       |    150     |
          | 4  |    2    |    400       |    600     |
          | 5  |    2    |    50        |    600     |
          | 6  |    2    |    600       |    600     |

    🔸NTH_VALUE()
      Returns the N-th row’s value in the window.
      Syntax:
        NTH_VALUE(column, n) 
        OVER (
            PARTITION BY partition_column
            ORDER BY sort_column
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        )

        Note:
          n = which row you want (1 = first, 2 = second, …)
          Always specify frame to avoid default-frame “current row” behavior.

      Example:2nd Order amount Per User
        SELECT id, user_id, total_amount,
            NTH_VALUE(total_amount, 2) OVER (
                PARTITION BY user_id
                ORDER BY id
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ) AS second_order
        FROM orders;
                    
        Result will be: 
          | id | user_id | total_amount | second_order |
          |----+---------+--------------+--------------|
          | 1  |    1    |      100     |      200     |
          | 2  |    1    |      200     |      200     |
          | 3  |    1    |      150     |      200     |
          | 4  |    2    |      400     |      50      |
          | 5  |    2    |      50      |      50      |
          | 6  |    2    |      600     |      50      |

    🔸NTILE()
      NTILE(n) divides the rows in a partition into n approximately equal groups and assigns a bucket number to each row.
        Bucket numbers start at 1
        Each bucket gets roughly total_rows/n rows
        NOTE:
          Buckets may not be perfectly equal if total rows ÷ n is not exact. 
          Extra rows go to lower-numbered buckets (Not to lower placed buckets).
          For example: 
              If we have 3 rows in a partiton window. We want 2 bucket.
              So no. of rows per bucket = 3/2 = 1.5
              Here, .5 is extra. Actually we can not have half row. So 2 row will be place is 1st bucket, not in 2nd bucket. Becase 1 < 2 i.e. Extra row placed in lower-numbered bucket.

        Common Use Cases of NTILE():
          Quartiles / percentiles of sales, deciles, revenue, or scores
          Risk scoring: divide clients into top/mid/bottom buckets
          Performance ranking per team or per department
          Gamification points, top 10%, etc,

      Syntax:
        NTILE(n) OVER (
            [PARTITION BY partition_column]
            ORDER BY sort_column
        )

        Here:
          n → number of buckets
          PARTITION BY → optional, splits data into groups
          ORDER BY → defines the order of rows before assigning buckets

      Example 1: Divide Orders Into 3 Buckets by Total Amount
        Let we have this table:

          | id | user_id | total_amount |
          |----+---------+--------------|
          | 1  |    1    |     100      |
          | 2  |    1    |     200      |
          | 3  |    1    |     150      |
          | 4  |    2    |     400      |
          | 5  |    2    |     50       |
          | 6  |    2    |     600      |

        SELECT id, user_id, total_amount,
            NTILE(3) OVER (ORDER BY total_amount DESC) AS bucket
        FROM orders;

        Result will be:
          | id | total_amount | bucket |
          |----+--------------+--------|
          | 6  |      600     |   1    |
          | 4  |      400     |   1    |
          | 2  |      200     |   2    |
          | 3  |      150     |   2    |
          | 1  |      100     |   3    |
          | 5  |      50      |   3    |

        Explanation:
          First, it will get Order by total_amount desc.
          Then, partition window (here full table) gets splited into n = 3 buckets (6 rows ÷ 3 = 2 rows per bucket)
          So
            Bucket 1 = top 2 highest,
            Bucket 2 = middle 2, 
            Bucket 3 = bottom 2.
      
      Example 2: Divide Orders Into 2 Buckets by Total Amount Per User (PARTITION BY)

        SELECT id, user_id, total_amount,
            NTILE(2) OVER (
                PARTITION BY user_id
                ORDER BY total_amount DESC
            ) AS user_bucket
        FROM orders;

        Result will be:
          | id | user_id | total_amount | user_bucket |
          | -- | ------- | ------------ | ----------- |
          | 2  | 1       | 200          | 1           |
          | 3  | 1       | 150          | 1           | -> Extra row placed in lower-numbered bucket.
          | 1  | 1       | 100          | 2           |
          |     ------- partition : 2 --------        |
          |    |         |              |             |
          | 6  | 2       | 600          | 1           |
          | 4  | 2       | 400          | 1           |
          | 5  | 2       | 50           | 2           |

        Explanation:
          Partiton will be on the basis of user_id. So total 2 Partiton window.

          In, 1st window there are 3 rows.
          So the window gets splited into n = 2 buckets (3 rows ÷ 2 = 1.5 rows per bucket)
          Here the extra row will be placed in lower-numbered bucket. So 2 row in 1st bucket.

          Same logic for 2nd partiton window.
      
      Example 3: Percentiles. Top 25% (4 buckets):
        NTILE(4) OVER (ORDER BY total_amount DESC) AS quartile

          Bucket 1 → top 25%
          Bucket 2 → 25-50%
          Bucket 3 → 50-75%
          Bucket 4 → bottom 25%

          
  ╰➤The Advanced Concept: Frame Clause
    A frame clause is used with window functions in SQL.
    It defines which rows are included in the calculation for each row inside a window.
    It is part of the OVER() clause.

    The frame clause defines: For each row, which surrounding rows should be included in the calculation.

   🔹Frame Clause Syntax:
        ROWS BETWEEN <start> AND <end>
      also:
        RANGE BETWEEN <start> AND <end>

   🔹Some common options for frame clause:
        +---------------------+---------------------+
        |     Start           |     End             |
        |---------------------+---------------------|
        | UNBOUNDED PRECEDING | CURRENT ROW         |
        | UNBOUNDED PRECEDING | UNBOUNDED FOLLOWING |
        | 1 PRECEDING         | CURRENT ROW         |
        | CURRENT ROW         | UNBOUNDED FOLLOWING |
        | 3 PRECEDING         | 3 FOLLOWING         |
        +---------------------+---------------------+

   🔹Frame Clause is part of OVER() caluse. Syntax is:
      OVER (
        PARTITION BY column
        ORDER BY column
        ROWS | RANGE BETWEEN ...
      )

      Here, The ROWS BETWEEN ... (or RANGE BETWEEN ...) part is the frame clause.

   🔹Default Behaviour of frame clause:
      If ORDER BY is present then default Behaviour is:
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      
        It means: From beginning of partition → current row.

   🔹Difference between ROWS and RANGE
      ROWS: Counts physical rows.
          ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
      
          It means exactly 2 rows before.

      RANGE: Uses value-based range, not row count.
          RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW

          It means all rows within last 7 days

   🔹Examples:
      ➤Running Total:
        SELECT
          id,
          amount,
          SUM(amount) OVER (
            ORDER BY id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          ) AS running_total
        FROM orders;

        It means: For each row, sum from the first row (due to UNBOUNDED PRECEDING) up to the current row.

      ➤Moving Average (Last 3 Rows)
        SELECT
          id,
          amount,
          AVG(amount) OVER (
            ORDER BY id
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
          ) AS moving_avg
        FROM orders;
        
        It means: For each row, average the current row and the previous 2 rows.
  
  ╰➤Second highest:

      ➤Find second highest order (Ignore tied). It will return one row which has second highest order.
          SELECT *
          FROM (
              SELECT *,
                    ROW_NUMBER() OVER (
                        ORDER BY total_amount DESC
                    ) AS rn
              FROM orders
          ) sub
          WHERE rn = 2;

      ➤Find second highest order (Inludes tied). It will return all rows which has second highest order.
         SELECT *
          FROM (
              SELECT *,
                    DENSE_RANK() OVER (
                        ORDER BY total_amount DESC
                    ) AS rnk
              FROM orders
          ) sub
          WHERE rnk = 2;

      ➤Find second highest order (without Window function). It will return the value of second highest, not row.

        SELECT MAX(total_amount)
          FROM orders
          WHERE total_amount < (
              SELECT MAX(total_amount) FROM orders
        );

      ➤Find second highest order (without Window function, using offset). It will return 1 row.

        OFFSET is used in SQL to skip a number of rows before returning results.
        It is usually used together with LIMIT.
          NOTE:
            If we use: 
              OFFSET 100000
              The database still scans 100000 rows and throws them away i.e skip them.

        SELECT *
        FROM orders
        ORDER BY total_amount DESC
        OFFSET 1
        LIMIT 1;

      ➤Find second highest order (without Window function). t will return all rows which has second highest order.

          SELECT *
            FROM orders
            WHERE total_amount = (
                SELECT MAX(total_amount)
                FROM orders
                WHERE total_amount < (
                    SELECT MAX(total_amount) FROM orders
                )
          );

      ➤Find Second Highest order Per User.
        Note: Here we have to find on per user, so we have to use partition.

        SELECT *
          FROM (
              SELECT *,
                    ROW_NUMBER() OVER (
                        PARTITION BY user_id
                        ORDER BY total_amount DESC
                    ) AS rn
              FROM orders
          ) sub
          WHERE rn = 2;