-- 1.Retrieve all users from Mumbai ordered by age descending.

SELECT * FROM users 
WHERE city = 'Mumbai'
ORDER BY age DESC;

--------------------------------------------------------------------------------------------------------------
-- 2.Find all products with price between 1,000 and 50,000.

SELECT * FROM products
WHERE price BETWEEN 10000 AND 50000;

--------------------------------------------------------------------------------------------------------------
-- 3.Get all orders created in the last 7 days.

SELECT * FROM orders 
WHERE created_at >= NOW() - INTERVAL '7 days';

--------------------------------------------------------------------------------------------------------------
-- 4.Find users whose email ends with example.com.

SELECT * FROM users
WHERE email LIKE '%example.com';

-- OR
-- This is regex. This can not use B-tree
SELECT * FROM users
WHERE email ~ 'example.com$';

--------------------------------------------------------------------------------------------------------------
-- 5.List all products that currently have stock greater than 10.

SELECT * FROM products
where stock >= 10;

--------------------------------------------------------------------------------------------------------------
-- 6.Retrieve top 3 most expensive products.

SELECT * FROM products
ORDER BY price DESC
LIMIT 3;

--------------------------------------------------------------------------------------------------------------
-- 7.Count how many users are there in each city.

SELECT city, COUNT(*) as 'No. of Users'  FROM users
GROUP BY city;

--------------------------------------------------------------------------------------------------------------
-- 8.Find total number of orders placed by each user.

SELECT user_id, COUNT(*) AS total_orders FROM orders
GROUP BY user_id;

-- OR

SELECT u.id, u.name, COUNT(o.id) AS total_orders FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.name
ORDER BY total_orders DESC;

--------------------------------------------------------------------------------------------------------------
-- 9.List all completed orders.

SELECT * FROM orders
where status = 'completed';

--------------------------------------------------------------------------------------------------------------
-- 10.Retrieve products that belong to the "Electronics" category.

SELECT p.* FROM products p
INNER JOIN categories c
ON c.id = p.category_id
WHERE c.name = 'Electronics'

-- OR using SubQuery

SELECT * FROM products
WHERE category_id = (
	SELECT id FROM categories WHERE name = 'Electronics'
);

--------------------------------------------------------------------------------------------------------------
-- 11.Get all orders along with user name and email.
-- i have used: LEFT JOIN → all orders, even if user is NULL.
-- INNER JOIN → only orders with valid users

SELECT o.*, u.name as user_name, u.email as user_email FROM orders o
LEFT JOIN users u
on o.user_id = u.id

--------------------------------------------------------------------------------------------------------------
-- 12.List all products ordered by user “Alice”.

SELECT u.name as user_name, p.name as product_name FROM users u
INNER JOIN orders o ON u.id = o.user_id
INNER JOIN order_items oi on o.id = oi.order_id
INNER JOIN products p on p.id = oi.product_id
WHERE u.name = 'Alice'

--------------------------------------------------------------------------------------------------------------
-- 13.Find users who have never placed any order.

SELECT u.* FROM users u
LEFT JOIN orders o
ON u.id = o.user_id
WHERE o.id IS NULL;

--------------------------------------------------------------------------------------------------------------
-- 14.Retrieve all orders with their product names and quantities.

SELECT o.*, p.name as product_name, oi.quantity as quantity FROM orders o
INNER JOIN order_items oi ON o.id = oi.order_id
INNER JOIN products p on oi.product_id = p.id

--------------------------------------------------------------------------------------------------------------
-- 15.Find total revenue generated per user.

SELECT u.id, u.name, SUM(o.total_amount) as revenue from users u
INNER JOIN orders o
ON u.id = o.user_id
GROUP BY u.id, u.name

-- OR If total_amount is not reliable:

SELECT u.id, u.name, SUM(oi.price * oi.quantity) AS revenue FROM users u
JOIN orders o ON o.user_id = u.id
JOIN order_items oi ON oi.order_id = o.id
GROUP BY u.id, u.name

--------------------------------------------------------------------------------------------------------------
-- 16.Find total quantity sold per product.

SELECT p.id, p.name, SUM(oi.quantity) AS "Sold Quantity" FROM products p
INNER JOIN order_items oi on oi.product_id = p.id
GROUP BY p.id, p.name
ORDER BY p.id

-- If we wants all products including unsold ones, use LEFT JOIN.

SELECT p.id, p.name, COALESCE(SUM(oi.quantity), 0) AS  "Sold Quantity" FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.id
GROUP BY p.id, p.name 
ORDER BY p.id

--------------------------------------------------------------------------------------------------------------
-- 17.List all products that have never been ordered.

SELECT p.* FROM products p
LEFT JOIN order_items oi 
ON p.id = oi.product_id
WHERE oi.product_id IS NULL

--------------------------------------------------------------------------------------------------------------
-- 18.Find categories that have no products.

SELECT c.* FROM categories c
LEFT JOIN products p
ON c.id = p.category_id
WHERE p.id IS NULL;

-- OR
SELECT *
FROM categories c
WHERE NOT EXISTS (
    SELECT 1
    FROM products p
    WHERE p.category_id = c.id
);

--------------------------------------------------------------------------------------------------------------
-- 19.Retrieve users who placed more than one order.

SELECT u.id, u.name, u.email, COUNT(o.id) as no_of_order FROM users u
INNER JOIN orders o
ON u.id = o.user_id
GROUP BY u.id, u.name, u.email
HAVING COUNT(o.id) > 1
ORDER BY u.id ASC;

-- Why not use WHERE COUNT(o.id) > 1
-- 	Because WHERE executes before aggregation.
-- 	HAVING executes after GROUP BY.

-- Alternative Using Subquery

SELECT *
FROM users
WHERE id IN (
    SELECT user_id
    FROM orders
    GROUP BY user_id
    HAVING COUNT(*) > 1
);

--------------------------------------------------------------------------------------------------------------
-- 20.Find the most recently placed order for each user.

SELECT *
FROM (
        SELECT 
            o.*,
            ROW_NUMBER() OVER (
                PARTITION BY user_id 
                ORDER BY created_at DESC
            ) AS rn
        FROM orders o
    ) sub
WHERE rn = 1;

--------------------------------------------------------------------------------------------------------------
-- 21.Find total revenue generated from completed orders only.

SELECT SUM(total_amount) AS toal_revenue FROM orders
WHERE status = 'completed';

--------------------------------------------------------------------------------------------------------------
-- 22.Find average order value per user.

SELECT u.id, u.name, AVG(o.total_amount) AS average_order FROM users u
INNER JOIN orders o
ON u.id = o.user_id
GROUP BY u.id, u.name
ORDER BY average_order DESC

-- What if a user has no orders?
	-- 	The above query excludes them (because INNER JOIN).
	-- 	To include users with no orders:

SELECT u.id, u.name, COALESCE(AVG(o.total_amount), 0) AS avg_order_value FROM users u
LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.name
ORDER BY u.id;
-- Now: Users without orders show 0 instead of NULL.

-- If only completed orders should count:

SELECT u.id, u.name, AVG(o.total_amount) AS avg_order_value FROM users u
INNER JOIN orders o  
ON o.user_id = u.id
AND o.status = 'completed'
GROUP BY u.id, u.name;

-- If You Want Global Average Alongside Per User then you need a window function:

SELECT user_id, AVG(total_amount) AS user_avg, AVG(total_amount) OVER () AS global_avg
FROM orders
GROUP BY user_id;

-- Here:
	-- 	AVG() → per group
	-- 	AVG() OVER () → over entire result set

--------------------------------------------------------------------------------------------------------------
-- 23.Find the city generating the highest revenue.

SELECT u.city, SUM(o.total_amount) as revenue FROM users u
INNER JOIN orders o
on u.id = o.user_id
GROUP BY u.city
ORDER BY revenue DESC
LIMIT 1


-- More Accurate Version (Using order_items). This ensures revenue is computed from actual line items.

SELECT u.city, SUM(oi.quantity * oi.price) AS total_revenue
FROM users u
JOIN orders o ON o.user_id = u.id
JOIN order_items oi ON oi.order_id = o.id
GROUP BY u.city
ORDER BY total_revenue DESC
LIMIT 1;

-- Advanced. If multiple cities tie for highest revenue:

WITH city_revenue AS (
    SELECT 
        u.city,
        SUM(oi.quantity * oi.price) AS total_revenue
    FROM users u
    JOIN orders o       ON o.user_id = u.id
    JOIN order_items oi ON oi.order_id = o.id
    GROUP BY u.city
)
SELECT *
FROM city_revenue
WHERE total_revenue = (
    SELECT MAX(total_revenue) FROM city_revenue
);

--------------------------------------------------------------------------------------------------------------
-- 24.Find top 3 highest spending users.

SELECT u.id, u.name, SUM(o.total_amount) AS spending FROM users u
INNER JOIN orders o
ON u.id = o.user_id
GROUP BY u.id, u.name
ORDER BY spending DESC
LIMIT 3

-- Advanced Version (Using Window Function). This is useful when multiple users tie for 3rd position.

SELECT *
FROM (
    SELECT 
        u.id,
        u.name,
        SUM(o.total_amount) AS total_spent,
        RANK() OVER (ORDER BY SUM(o.total_amount) DESC) AS rank
    FROM users u
    JOIN orders o ON o.user_id = u.id
    GROUP BY u.id, u.name
) ranked
WHERE rank <= 3;

--------------------------------------------------------------------------------------------------------------
-- 25.Find top-selling product by quantity.

SELECT p.id, p.name, SUM(oi.quantity) AS total_quantity_sold FROM order_items oi
JOIN products p ON p.id = oi.product_id
GROUP BY p.id, p.name
ORDER BY total_quantity_sold DESC
LIMIT 1;

-- If two products have the same highest quantity:

SELECT *
FROM (
    SELECT 
        p.id,
        p.name,
        SUM(oi.quantity) AS total_quantity_sold,
        RANK() OVER (ORDER BY SUM(oi.quantity) DESC) AS rnk
    FROM order_items oi
    JOIN products p ON p.id = oi.product_id
    GROUP BY p.id, p.name
) ranked
WHERE rnk = 1;

-- if we want to include 0 sold products too

SELECT p.id, p.name, COALESCE(SUM(oi.quantity), 0) as sold_qty FROM products p
LEFT JOIN order_items oi
ON oi.product_id = p.id
GROUP BY p.id, p.name
ORDER BY sold_qty DESC

--------------------------------------------------------------------------------------------------------------
-- 26.Find top-selling product by revenue.

SELECT p.id, p.name, SUM(oi.quantity * oi.price) AS total_revenue
FROM order_items oi
JOIN products p 
ON p.id = oi.product_id
GROUP BY p.id, p.name
ORDER BY total_revenue DESC
LIMIT 1;

--------------------------------------------------------------------------------------------------------------
-- 27.Find monthly revenue (group by month).

SELECT DATE_TRUNC('month', o.created_at) AS month, SUM(oi.quantity * oi.price) AS monthly_revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
GROUP BY month
ORDER BY month;

--------------------------------------------------------------------------------------------------------------
-- 28.Find average product price per category.

SELECT c.name, AVG(p.price) as avg_price FROM products p
INNER JOIN categories c
ON c.id = p.category_id
GROUP BY c.id, c.name

-- OR

SELECT 
    COALESCE(c.name, 'Uncategorized') AS category_name,
    AVG(p.price) AS avg_price
FROM products p
LEFT JOIN categories c
    ON c.id = p.category_id
GROUP BY c.name;

--------------------------------------------------------------------------------------------------------------
-- 29.Find users whose total spending is greater than 50,000.

SELECT u.*, o.spending FROM users u
INNER JOIN ( 
		SELECT user_id, SUM(total_amount) AS spending  from orders
		GROUP BY user_id
	) o
ON o.user_id = u.id
WHERE o.spending > 50000


-- OR

SELECT 
    u.id,
    u.name,
    u.email,
    SUM(o.total_amount) AS spending
FROM users u
JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.name, u.email
HAVING SUM(o.total_amount) > 50000;

-- OR

WITH user_spending AS (
    SELECT user_id, SUM(total_amount) AS spending
    FROM orders
    GROUP BY user_id
)
SELECT u.*, us.spending
FROM users u
JOIN user_spending us ON us.user_id = u.id
WHERE us.spending > 50000;

--------------------------------------------------------------------------------------------------------------
-- 30.Find percentage contribution of each category to total revenue.
