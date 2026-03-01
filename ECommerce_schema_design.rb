Question:Write an SQL schema for an e-commerce business.
Answer: Minimal relational schema model might include:

🔸Customers

  CREATE TABLE customers (
      customer_id       UUID PRIMARY KEY,
      name              VARCHAR(100) NOT NULL,
      email             VARCHAR(100) UNIQUE NOT NULL,
      phone             VARCHAR(15),
      created_at        TIMESTAMP DEFAULT NOW()
  );

🔸Products

  CREATE TABLE products (
      product_id        UUID PRIMARY KEY,
      name              VARCHAR(200) NOT NULL,
      sku               VARCHAR(50) UNIQUE NOT NULL,
      price             DECIMAL(10,2) NOT NULL,
      stock_quantity    INT DEFAULT 0,
      created_at        TIMESTAMP DEFAULT NOW()
  );

🔸Orders

  CREATE TABLE orders (
      order_id          UUID PRIMARY KEY,
      customer_id       UUID REFERENCES customers(customer_id),
      status            VARCHAR(30),
      total_amount      DECIMAL(12,2),
      placed_at         TIMESTAMP DEFAULT NOW()
  );

🔸OrderItems

  CREATE TABLE order_items (
      order_item_id     UUID PRIMARY KEY,
      order_id          UUID REFERENCES orders(order_id),
      product_id        UUID REFERENCES products(product_id),
      quantity          INT NOT NULL,
      unit_price        DECIMAL(10,2) NOT NULL
  );

🔸Inventory

  CREATE TABLE inventory (
      warehouse_id      UUID,
      product_id        UUID REFERENCES products(product_id),
      available_qty     INT DEFAULT 0,
      PRIMARY KEY (warehouse_id, product_id)
  );

------------------------------------------------------------------------------------------------------------
Question:Find total sales per product last month.
Answer:

  SELECT p.product_id, p.name, SUM(oi.quantity * oi.unit_price) as total_sales
  FROM order_items oi
  JOIN orders o ON o.order_id = oi.order_id
  JOIN products p ON p.product_id = oi.product_id
  WHERE o.placed_at >= now() - INTERVAL '1 month'
  GROUP BY p.product_id, p.name;

------------------------------------------------------------------------------------------------------------
Question: What is Order Management in an e-commerce platform?
Answer: It is a central system that tracks order life cycles from placement to delivery, manages inventory allotment, routing to warehouses, returns, and fulfillment. Anchanto’s OMS can route orders to nearest warehouses and split based on stock priorities.

------------------------------------------------------------------------------------------------------------
Question: How does a Warehouse Management System (WMS) support e-commerce?
Answer:Tracks real inventory locations
Manages pick/pack/dispatch flow
Provides real-time stock levels across multiple facilities
Prevents overselling

------------------------------------------------------------------------------------------------------------
Question: Describe Integrations in e-commerce systems.
Answer: Integrations connect marketplaces (Amazon, eBay), web stores, POS, carriers, and ERP systems. They sync data for orders, inventory, pricing, and tracking in real-time using APIs or webhooks. Scalability, retries, and idempotency are key concerns in such systems.

-------------------------------------------------------------------------------------------------------------
Question: What is SKU and why is it important?
Answer: SKU stands for Stock Keeping Unit — a unique identifier for products used in tracking inventory and sales.

-------------------------------------------------------------------------------------------------------------
Question: How do you handle inventory stockouts programmatically?
Answer: Reserve stock at order placement
Implement backorders
Real-time stock sync with marketplace APIs
Alerts when low stock thresholds reached