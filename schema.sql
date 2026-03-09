-- schema.sql
CREATE TABLE IF NOT EXISTS e_orders (
    order_id VARCHAR(50) PRIMARY KEY, -- Will become PK
    customer_id VARCHAR(50),          -- Will become SK
    product_name VARCHAR(100),        -- Regular attribute
    amount DECIMAL(10,2)              -- Regular attribute
);

INSERT INTO e_orders (order_id, customer_id, product_name, amount) VALUES 
('ORD#101', 'CUST#99', 'Laptop', 1200.00),
('ORD#102', 'CUST#88', 'Mouse', 25.50),
('ORD#103', 'CUST#99', 'Keyboard', 75.00),
('ORD#104', 'CUST#77', 'Monitor', 300.00),
('ORD#105', 'CUST#88', 'Webcam', 45.00),
('ORD#106', 'CUST#99', 'Headphones', 50.00);