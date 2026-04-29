1. Find 3rd heighest salary from emplyees table.

Answer 1:

  SELECT DISTINCT salary
  FROM employees
  ORDER BY salary DESC
  Limit 1 OFFSET 2;

Answer 2: 

    SELECT salary FROM
      (
        SELECT DISTINCT salary FROM employees
        ORDER BY salary DESC
        LIMIT 3
      ) as top_salary
    ORDER_BY salary ASC 
    LIMIT 1;

Answer 3: 
  SELECT salary FROM (
    SELECT salary, 
      DENSE_RANK() OVER(ORDER_BY salary DESC) as rank 
    FROM employees
  ) as ranked_tbl
  WHERE rank = 3
  LIMIT 1;

Answer 4:

  WITH ranked_tbl AS (
     SELECT salary, 
      DENSE_RANK() OVER(ORDER_BY salary DESC) as rank 
     FROM employees
  )

  SELECT salary FROM ranked_tbl
  WHERE rank = 3
  LIMIT 1;

------------------------------------------------------------------------------------------
What is the differecne between select and join ?
Answer -> In Rails, select and joins serve very different purposes, although both are used while querying data.

select is used to control which columns we want to fetch from the database. By default, Rails selects all columns using SELECT *, but with select, we can limit that to only required fields, which improves performance.
  For example:
    User.select(:id, :email)

  This will only fetch id and email, instead of loading the full user object with all columns.

On the other hand, joins is used to combine data from multiple tables based on associations. It generates an SQL INNER JOIN.
  For example:
    User.joins(:posts)
    
    This will return users who have associated posts by joining the users and posts tables.

We often use them together. For example:
  User.joins(:posts).select('users.name, posts.title')
  
  Here, we are joining tables and selecting only specific fields from both.

one important point is:
  🔸joins does not load associated records like includes does. It is mainly used for filtering or querying.
  🔸select can return partial objects, so accessing non-selected attributes can raise errors.

-----------------------------------------------------------------------------------------------
What is the differecne between find, find_by and find_each? Can we pass an array in find method?
Answer ->🔸find is used to fetch records by primary key (usually id). Example: User.find(1)
It raises an error (ActiveRecord::RecordNotFound) if the record is not found.
It always expects an ID (or IDs).

We can also pass an array to find method. Example: User.find([1, 2, 3])
This returns multiple records i.e an array of objects.
But important point: If any one ID is missing, it will raise an error.

🔸find_by is used to fetch a record based on conditions or by a column.
  Example: User.find_by(email: "test@example.com")

  It returns the first matching record.
  If nothing is found, it returns nil (no exception).
  So compared to find, it is safer when we are not sure the record exists.

  I usually use find_by! if I want behavior similar to find but with custom conditions, because it raises an exception if no record is found.