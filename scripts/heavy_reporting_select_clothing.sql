\set start_date_offset random(0, 364)
\set end_date_offset random(0, 30)
SELECT p.category, p.product_name, COUNT(oi.order_item_id) AS total_items_sold, SUM(oi.quantity * oi.unit_price) AS total_revenue
FROM products p
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id
WHERE p.category = 'Clothing'
  AND o.order_date BETWEEN '2024-01-01'::timestamp + (:start_date_offset * INTERVAL '1 day')
  AND '2024-01-01'::timestamp + ((:start_date_offset + :end_date_offset) * INTERVAL '1 day')
GROUP BY p.category, p.product_name
ORDER BY total_items_sold DESC
LIMIT 100;