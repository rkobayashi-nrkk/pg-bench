\set customer_id random(1, 1000000)
SELECT order_id, order_date, total_amount, status FROM orders WHERE customer_id = :customer_id AND status = 'Shipped';