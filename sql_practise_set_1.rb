1:Open Postgres Sql console:
    psql -U postgres
     OR 
    sudo -u postgres psql
2:create DataBase:
    CREATE DATABASE interview_practice;
3:Switch to database:
    \c interview_practice;
4:Create Tables:

  CREATE TABLE users (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      email VARCHAR(150) UNIQUE NOT NULL,
      age INT CHECK (age > 0),
      city VARCHAR(100),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE categories (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) UNIQUE NOT NULL
  );

  CREATE TABLE products (
      id SERIAL PRIMARY KEY,
      name VARCHAR(150) NOT NULL,
      price NUMERIC(10,2) NOT NULL CHECK (price > 0),
      stock INT DEFAULT 0,
      category_id INT REFERENCES categories(id) ON DELETE SET NULL
  );

  CREATE TABLE orders (
      id SERIAL PRIMARY KEY,
      user_id INT REFERENCES users(id) ON DELETE CASCADE,
      total_amount NUMERIC(10,2),
      status VARCHAR(50) DEFAULT 'pending',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE order_items (
      id SERIAL PRIMARY KEY,
      order_id INT REFERENCES orders(id) ON DELETE CASCADE,
      product_id INT REFERENCES products(id) ON DELETE CASCADE,
      quantity INT CHECK (quantity > 0),
      price NUMERIC(10,2) NOT NULL
  );

  CREATE TABLE employees (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100),
      manager_id INT REFERENCES employees(id)
  );

5:insert Data into tables:

  INSERT INTO users (name, email, age, city) VALUES
  ('Alice', 'alice@example.com', 25, 'Mumbai'),
  ('Bob', 'bob@example.com', 30, 'Delhi'),
  ('Charlie', 'charlie@example.com', 35, 'Bangalore'),
  ('David', 'david@example.com', 28, 'Mumbai'),
  ('Eva', 'eva@example.com', 40, 'Chennai');


  INSERT INTO categories (name) VALUES
  ('Electronics'),
  ('Books'),
  ('Footwear'),
  ('Clothing');

  INSERT INTO products (name, price, stock, category_id) VALUES
  ('Laptop', 75000, 10, 1),
  ('Mobile', 30000, 20, 1),
  ('Novel', 500, 100, 2),
  ('T-Shirt', 800, 50, 3),
  ('Jeans', 2000, 12, NULL)
  ('Headphones', 2000, 15, 1);


  INSERT INTO orders (user_id, total_amount, status) VALUES
  (1, 80000, 'completed'),
  (2, 30500, 'completed'),
  (1, 500, 'pending'),
  (3, 2000, 'completed');

  INSERT INTO orders (user_id, total_amount, status) VALUES
  (1, 60000, 'completed');


  INSERT INTO order_items (order_id, product_id, quantity, price) VALUES
  (1, 1, 1, 75000),
  (2, 5, 1, 2000),
  (3, 2, 1, 30000),
  (4, 3, 1, 500),
  (5, 3, 1, 500),
  (6, 5, 1, 2000);


  INSERT INTO employees (name, manager_id) VALUES
  ('CEO', NULL),
  ('Manager1', 1),
  ('Manager2', 1),
  ('Employee1', 2),
  ('Employee2', 2),
  ('Employee3', 3);

Exit the psql console.

Now open PgAdmin workbench. 
  Right click on "Server". Then "Register", then "Server".
  In General tab: Give a name to server like : PanKajDataBaseServer
  In Connection tab:
    Enter Host name/Address: localhost
    Enter username: postgres (bydefault)
    Enter password for above postgres user. Toggle on Save password.
    Then click save Button.

Now Expand the created server. Here we created "PanKajDataBaseServer".
Expand Database inside it. It will list all databases.
Right click on desired database and then select "Query Tool" option. It will open the Query area for the selected DataBase.
After writing query you can execute it by click play button from top bar.

Now practise below Question.
NOTE: For column name use double quoted sting and for value use single quoted sting.
      SELECT "age" FROM users;  -- column name
      SELECT 'age';             -- string value

Fundamentals:
---------------------
1.Retrieve all users from Mumbai ordered by age descending.
2.Find all products with price between 1,000 and 50,000.
3.Get all orders created in the last 7 days.
4.Find users whose email ends with example.com.
5.List all products that currently have stock greater than 10.
6.Retrieve top 3 most expensive products.
7.Count how many users are there in each city.
8.Find total number of orders placed by each user.
9.List all completed orders.
10.Retrieve products that belong to the "Electronics" category.

Joins:
-------
11.Get all orders along with user name and email.
12.List all products ordered by user “Alice”.
13.Find users who have never placed any order.
14.Retrieve all orders with their product names and quantities.
15.Find total revenue generated per user.
16.Find total quantity sold per product.
17.List all products that have never been ordered.
18.Find categories that have no products.
19.Retrieve users who placed more than one order.
20.Find the most recently placed order for each user.

Aggregation & Business Logic:
-----------------------------
21.Find total revenue generated from completed orders only.
22.Find average order value per user.
23.Find the city generating the highest revenue.
24.Find top 3 highest spending users.
25.Find top-selling product by quantity.
26.Find top-selling product by revenue.
27.Find monthly revenue (group by month).
28.Find average product price per category.
29.Find users whose total spending is greater than 50,000.
30.Find percentage contribution of each category to total revenue.

Subqueries & CTE
-----------------
31.Find users who placed an order with total_amount greater than average order amount.
32.Find products priced above average product price.
33.Find users who bought at least one product from Electronics category.
34.Find second highest priced product.
35.Find users who purchased all products in category "Books".
36.Using CTE, find total revenue per category.
37.Using CTE, find users whose average order value is above overall average order value.
38.Find products that were ordered more than once in the same order (edge case thinking).

Window Functions
----------------
39.Rank users by total spending.
40.Find running total revenue ordered by order date.
41.Find highest order per city.
42.Assign row number to orders per user ordered by created_at.
43.Find top 2 most expensive products per category.
44.Find difference between current order amount and previous order amount per user.

Self Join & Hierarchy
----------------------
45.Show each employee with their manager name.
46.Find employees who do not manage anyone.
47.Count number of subordinates under each manager.
48.Find top-level manager (CEO).

Advanced / Real Backend Scenarios
---------------------------------
49.Simulate stock deduction:
    Write a query that shows remaining stock after all completed orders.
50.Identify users whose total spending increased month-over-month (growth analysis).