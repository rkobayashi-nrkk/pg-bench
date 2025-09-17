\set start_date_offset random(0, 364)
\set end_date_offset random(0, 30)
SELECT p.category, p.product_name, COUNT(oi.order_item_id) AS total_items_sold, SUM(oi.quantity * oi.unit_price) AS total_revenue
FROM products p
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id
WHERE p.category = 'Books'
  AND o.order_date BETWEEN ('2024-01-01'::date + (:start_date_offset::int || ' day')::interval)
  AND ('2024-01-01'::date + ((:start_date_offset::int + :end_date_offset::int) || ' day')::interval)
GROUP BY p.category, p.product_name
ORDER BY total_items_sold DESC
LIMIT 100;
