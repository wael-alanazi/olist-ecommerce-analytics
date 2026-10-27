/* 13_reconciliation_sql_vs_powerbi.sql
   The SQL value of every dashboard number, to compare with the Power BI cards. Same scopes and
   definitions as the dashboard (see the README). Run each query, clear all slicers in Power BI, and
   compare the cards. */

USE OlistDB;
GO


/* 1. Sales page
   Orders, customers, revenue, freight and average order value must match the cards. */
SELECT COUNT(DISTINCT i.order_id)                                       AS orders,
       COUNT(DISTINCT o.customer_unique_id)                             AS customers,
       CAST(SUM(i.price) AS DECIMAL(14,2))                              AS revenue,
       CAST(SUM(i.freight_value) AS DECIMAL(14,2))                      AS freight,
       CAST(SUM(i.price) / COUNT(DISTINCT i.order_id) AS DECIMAL(10,2)) AS avg_order_value
FROM clean.order_items i
JOIN clean.orders o ON o.order_id = i.order_id
WHERE i.in_sales_scope = 1;


/* 2. Delivery page: delivery
   Delivered orders, late orders, late % and delivery days must match the cards. */
SELECT COUNT(*)                                             AS delivered_orders,
       SUM(is_late)                                         AS late_orders,
       CAST(SUM(is_late) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS late_pct,
       CAST(AVG(delivery_days * 1.0) AS DECIMAL(5,2))       AS avg_delivery_days
FROM clean.orders
WHERE in_delivery_scope = 1;


/* 3. Delivery page: review score
   Average score of late and on-time orders must match the two cards. */
SELECT o.is_late,
       COUNT(*)                                       AS reviews,
       CAST(AVG(r.review_score * 1.0) AS DECIMAL(4,2)) AS avg_score
FROM clean.orders o
JOIN clean.reviews r ON r.order_id = o.order_id
WHERE o.in_delivery_scope = 1
GROUP BY o.is_late
ORDER BY o.is_late;


/* 4. Customers page: orders and customers
   This page counts all sales-scope orders, so it can differ from the Sales page
   (see "Data Validation" in the README). */
SELECT COUNT(*)                            AS orders,
       COUNT(DISTINCT customer_unique_id)  AS customers
FROM clean.orders
WHERE in_sales_scope = 1;


/* 5. Customers page: repeat rate
   The share of customers with more than one order must match the card. */
SELECT COUNT(*)                                                          AS customers,
       SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END)                       AS repeat_customers,
       CAST(SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) * 100.0
            / COUNT(*) AS DECIMAL(5,2))                                  AS repeat_rate_pct
FROM (
    SELECT customer_unique_id, COUNT(*) AS orders
    FROM clean.orders
    WHERE in_sales_scope = 1
    GROUP BY customer_unique_id
) AS t;
