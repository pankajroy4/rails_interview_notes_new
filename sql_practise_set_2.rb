1:Open Postgres Sql console:
    psql -U postgres
2:create DataBase:
    CREATE DATABASE sql_interview_lab;
3:Switch to database:
    \c sql_interview_lab;
4:Create Tables:

------------------------------------------------------------
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE UNIQUE INDEX idx_users_email_unique ON users(email);
-------------------------------------------------------------
CREATE TABLE products (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    category VARCHAR(100) NOT NULL,
    price NUMERIC(10,2) NOT NULL CHECK (price > 0)
);

CREATE INDEX idx_products_category ON products(category);
-------------------------------------------------------------
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    total_amount NUMERIC(10,2) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_created_at ON orders(created_at);
CREATE INDEX idx_orders_user_created ON orders(user_id, created_at DESC);
-------------------------------------------------------------
CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    product_id BIGINT REFERENCES products(id),
    quantity INT CHECK (quantity > 0),
    price NUMERIC(10,2) NOT NULL
);

CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_order_items_product ON order_items(product_id);
-------------------------------------------------------------
CREATE TABLE payments (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    amount NUMERIC(10,2) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payments_order ON payments(order_id);
-------------------------------------------------------------
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id),
    event_name VARCHAR(100),
    meta JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_events_user ON events(user_id);
CREATE INDEX idx_events_meta_gin ON events USING GIN(meta);
-------------------------------------------------------------

5:insert Data into tables:

INSERT INTO users (name, email, created_at) VALUES
('Pankaj', 'pankaj@gmail.com', NOW() - INTERVAL '6 months'),
('Amit', 'amit@gmail.com', NOW() - INTERVAL '5 months'),
('Neha', 'neha@gmail.com', NOW() - INTERVAL '4 months'),
('Riya', 'riya@gmail.com', NOW() - INTERVAL '3 months'),
('Vikas', 'vikas@gmail.com', NOW() - INTERVAL '2 months'),
('Sara', 'sara@gmail.com', NOW() - INTERVAL '1 month'),
('John', 'john@gmail.com', NOW() - INTERVAL '20 days'),
('Priya', 'priya@gmail.com', NOW() - INTERVAL '15 days'),
('Rahul', 'rahul@gmail.com', NOW() - INTERVAL '10 days'),
('Ankit', 'ankit@gmail.com', NOW() - INTERVAL '5 days');


INSERT INTO products (name, category, price) VALUES
('iPhone', 'Electronics', 80000),
('Laptop', 'Electronics', 70000),
('Headphones', 'Electronics', 3000),
('T-Shirt', 'Clothing', 1000),
('Jeans', 'Clothing', 2500),
('Novel', 'Books', 500),
('Notebook', 'Books', 200),
('Shoes', 'Clothing', 4000),
('Watch', 'Accessories', 5000),
('Bag', 'Accessories', 3000);


INSERT INTO orders (user_id, total_amount, status, created_at) VALUES
(1, 80000, 'paid', NOW() - INTERVAL '5 months'),
(1, 3000, 'paid', NOW() - INTERVAL '4 months'),
(2, 70000, 'paid', NOW() - INTERVAL '3 months'),
(3, 2500, 'paid', NOW() - INTERVAL '2 months'),
(4, 500, 'paid', NOW() - INTERVAL '40 days'),
(5, 1000, 'pending', NOW() - INTERVAL '20 days'),
(6, 4000, 'failed', NOW() - INTERVAL '10 days'),
(7, 3000, 'paid', NOW() - INTERVAL '5 days'),
(8, 5000, 'paid', NOW() - INTERVAL '3 days'),
(9, 70000, 'paid', NOW() - INTERVAL '2 days'),
(10, 80000, 'paid', NOW() - INTERVAL '1 day');


INSERT INTO order_items (order_id, product_id, quantity, price) VALUES
(1,1,1,80000),
(2,3,1,3000),
(3,2,1,70000),
(4,5,1,2500),
(5,6,1,500),
(6,4,1,1000),
(7,8,1,4000),
(8,10,1,3000),
(9,9,1,5000),
(10,2,1,70000),
(11,1,1,80000);


INSERT INTO payments (order_id, amount, status, created_at) VALUES
(1,80000,'success', NOW() - INTERVAL '5 months'),
(2,3000,'success', NOW() - INTERVAL '4 months'),
(3,70000,'success', NOW() - INTERVAL '3 months'),
(4,2500,'success', NOW() - INTERVAL '2 months'),
(5,500,'success', NOW() - INTERVAL '39 days'),
(6,1000,'pending', NOW() - INTERVAL '19 days'),
(7,4000,'failed', NOW() - INTERVAL '9 days'),
(8,3000,'success', NOW() - INTERVAL '5 days'),
(9,5000,'success', NOW() - INTERVAL '3 days'),
(10,70000,'success', NOW() - INTERVAL '2 days'),
(10,70000,'success', NOW() - INTERVAL '2 days'); -- duplicate payment anomaly



INSERT INTO events (user_id, event_name, meta, created_at) VALUES
(1,'api_call','{"latency_ms":120}',NOW()-INTERVAL '1 day'),
(1,'api_call','{"latency_ms":900}',NOW()-INTERVAL '1 day'),
(2,'login','{"ip":"1.2.3.4"}',NOW()-INTERVAL '2 days'),
(3,'purchase','{"device":"mobile"}',NOW()-INTERVAL '3 days');

Now practise below Question.

Miscellaneous:
--------------
1.Find top 3 users by total revenue.
2.Find orders where payment amount ≠ order total.
3.Find users with duplicate successful payments.
4.Find users whose last order was more than 30 days ago.
5.Find revenue per category.
6.Find running revenue month-over-month.
7.Find products contributing to 80% revenue (Pareto).
8.Find users who made purchases in consecutive months.
9.Find orders placed but never paid successfully.
10.Find most common product pair bought together.
11.Find average latency from events JSONB.
12.Find users with multiple orders within 10 minutes.
13.Find users whose spending increased every order.
14.Find top category by revenue in last 30 days.
15.Find users who ordered but never had any successful payment.
16.Find 95th percentile order amount.
17.Find “power users” top 10% by order count.
18.Find orders stuck in pending > 15 days.
19.Find duplicate emails (case insensitive).
20.Find user retention: how many users ordered again within 30 days of first order.

Data Integrity/Debugging:
-------------------------
21.Find orders where total_amount is less than sum of order_items.
22.Find payments that happened before the order was created (data bug).
23.Find users who have more successful payments than paid orders.
24.Find products that were ordered but later deleted (simulate orphan product).
25.Find orders with multiple successful payments.
26.Find users whose total paid payments ≠ total paid order amounts.
27.Find orders marked paid but having no successful payment.
28.Find payments marked success but order status is failed.
29.Find users who never generated any events.
30.Find events without valid users (orphan analytics rows).

Performance/Optimization Thinking:
------------------------------------
31.Write a query to fetch latest 20 orders for a user efficiently. (Then explain what index you would create.)
32.Rewrite “users who never ordered” using NOT EXISTS instead of LEFT JOIN.
33.Find top 5 products by revenue in last 90 days, optimized for large dataset.
34.Rewrite revenue per category without subquery.
35.Find users who ordered in last 30 days but not before that.
36.Find the most expensive order per month.
37.Find average order amount per user but only for users with ≥ 3 orders.
38.Find daily active users (DAU) from events table.
39.Find monthly active users (MAU).
40.Find user churn rate month-over-month.

Window Function Mastery:
------------------------
41.For each user, show difference between current and previous order amount.
42.For each product, calculate cumulative quantity sold over time.
43.Find users ranked by revenue per category.
44.Find 2nd highest order per user.
45.Find first successful payment per order.
46.Find time gap (in minutes) between consecutive orders per user.
47.Find users whose last 3 orders were increasing in value.
48.Find daily revenue growth percentage compared to previous day.
49.Find products whose sales dropped 2 consecutive months.
50.Assign quartiles to users based on total spending.

Business Logic/Real Analytics:
------------------------------
51.Find lifetime value (LTV) per user.
52.Find average number of days between signup and first order.
53.Find conversion rate:
    (users who had event 'api_call' and later placed an order) / total api_call users.
54.Find users who bought from ≥ 2 different categories.
55.Find most profitable category per month.
56.Find users whose first order was the highest among all their orders.
57.Find orders placed outside business hours (9am - 6pm).
58.Find users who only placed 1 order ever and never returned.
59.Find revenue contribution of top 10% users.
60.Find median order amount per month.

Extremely Hard/Senior Level:
----------------------------
61.Detect potential fraud:
  Users placing > 3 orders within 5 minutes.
62.Find users whose payment success rate < 50% .
63.Find products often bought together with product_id = 1.
64.Detect users with abnormal spending spike (order > 3 * their average).
65.Find cohort retention table:
    Month 0, Month 1, Month 2 retention.
66.Find top 3 fastest growing products month-over-month.
67.Find revenue anomaly days (revenue > 2 * monthly average).
68.Find users whose average event latency is above global average.
69.Find percentage of users who never converted after signup.
70.Simulate leaderboard:
    Top 10 users by revenue, but tie-break by most recent order.