/* 12_customer_analysis.sql
   Customers: who are they, where are they, and do they come back? Sales scope. A customer is a
   customer_unique_id and a repeat customer has 2 or more orders. The definitions are in the README. */

USE OlistDB;
GO


/* 1. Headline numbers
   The base of every customer measure.
   Note: file 10 counts only orders that have items, so it shows fewer orders and customers than this
   file (a few orders have no items yet). */
SELECT (SELECT COUNT(*) FROM clean.customer)                          AS customers_total,
       COUNT(DISTINCT customer_unique_id)                             AS customers_with_sales,
       COUNT(*)                                                       AS orders_in_sales_scope,
       CAST(COUNT(*) * 1.0 / COUNT(DISTINCT customer_unique_id) AS DECIMAL(4,2)) AS orders_per_customer
FROM clean.orders
WHERE in_sales_scope = 1;


/* 2. Orders per customer
   The repeat rate tells whether the marketplace keeps its customers. */
-- 2a. customers by number of orders
WITH customer_orders AS (
    SELECT customer_unique_id, COUNT(*) AS orders
    FROM clean.orders
    WHERE in_sales_scope = 1
    GROUP BY customer_unique_id
)
SELECT CASE WHEN orders = 1 THEN '1 order'
            WHEN orders = 2 THEN '2 orders'
            WHEN orders = 3 THEN '3 orders'
            ELSE                 '4 or more orders'
       END                                                              AS order_group,
       COUNT(*)                                                         AS customers,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2))   AS pct_of_customers
FROM customer_orders
GROUP BY CASE WHEN orders = 1 THEN '1 order'
              WHEN orders = 2 THEN '2 orders'
              WHEN orders = 3 THEN '3 orders'
              ELSE                 '4 or more orders'
         END
ORDER BY order_group;

-- 2b. repeat rate
WITH customer_orders AS (
    SELECT customer_unique_id, COUNT(*) AS orders
    FROM clean.orders
    WHERE in_sales_scope = 1
    GROUP BY customer_unique_id
)
SELECT COUNT(*)                                                         AS customers,
       SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END)                      AS repeat_customers,
       CAST(SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) * 100.0
            / COUNT(*) AS DECIMAL(5,2))                                 AS repeat_rate_pct
FROM customer_orders;


/* 3. Repeat rate by region and state
   Shows where retention is stronger or weaker. */
-- 3a. by region
WITH customer_orders AS (
    SELECT customer_unique_id, COUNT(*) AS orders
    FROM clean.orders
    WHERE in_sales_scope = 1
    GROUP BY customer_unique_id
)
SELECT c.region,
       COUNT(*)                                                         AS customers,
       SUM(CASE WHEN co.orders > 1 THEN 1 ELSE 0 END)                   AS repeat_customers,
       CAST(SUM(CASE WHEN co.orders > 1 THEN 1 ELSE 0 END) * 100.0
            / COUNT(*) AS DECIMAL(5,2))                                 AS repeat_rate_pct
FROM customer_orders co
JOIN clean.customer c ON c.customer_unique_id = co.customer_unique_id
GROUP BY c.region
ORDER BY repeat_rate_pct DESC;

-- 3b. top 10 states by customers
WITH customer_orders AS (
    SELECT customer_unique_id, COUNT(*) AS orders
    FROM clean.orders
    WHERE in_sales_scope = 1
    GROUP BY customer_unique_id
)
SELECT TOP 10
       c.customer_state,
       COUNT(*)                                                         AS customers,
       SUM(CASE WHEN co.orders > 1 THEN 1 ELSE 0 END)                   AS repeat_customers,
       CAST(SUM(CASE WHEN co.orders > 1 THEN 1 ELSE 0 END) * 100.0
            / COUNT(*) AS DECIMAL(5,2))                                 AS repeat_rate_pct
FROM customer_orders co
JOIN clean.customer c ON c.customer_unique_id = co.customer_unique_id
GROUP BY c.customer_state
ORDER BY customers DESC;


/* 4. Days to the second order
   Tells when a reminder or an offer would make sense. The orders of each customer are numbered by
   purchase date (ROW_NUMBER); order 1 is compared with order 2. */
WITH numbered AS (
    SELECT customer_unique_id,
           purchase_date,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                              ORDER BY order_purchase_timestamp, order_id) AS order_number
    FROM clean.orders
    WHERE in_sales_scope = 1
),
gaps AS (
    SELECT DATEDIFF(DAY, a.purchase_date, b.purchase_date) AS days_to_second_order
    FROM numbered a
    JOIN numbered b
      ON b.customer_unique_id = a.customer_unique_id
     AND a.order_number = 1
     AND b.order_number = 2
)
SELECT CASE WHEN days_to_second_order =   0 THEN '0) same day'
            WHEN days_to_second_order <= 30 THEN '1) 1-30 days'
            WHEN days_to_second_order <= 90 THEN '2) 31-90 days'
            WHEN days_to_second_order <= 180 THEN '3) 91-180 days'
            WHEN days_to_second_order <= 365 THEN '4) 181-365 days'
            ELSE                                   '5) over 365 days'
       END                                                              AS gap_group,
       COUNT(*)                                                         AS repeat_customers,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2))   AS pct_of_repeat_customers,
       CAST(AVG(days_to_second_order * 1.0) AS DECIMAL(6,1))            AS avg_days
FROM gaps
GROUP BY CASE WHEN days_to_second_order =   0 THEN '0) same day'
              WHEN days_to_second_order <= 30 THEN '1) 1-30 days'
              WHEN days_to_second_order <= 90 THEN '2) 31-90 days'
              WHEN days_to_second_order <= 180 THEN '3) 91-180 days'
              WHEN days_to_second_order <= 365 THEN '4) 181-365 days'
              ELSE                                   '5) over 365 days'
         END
ORDER BY gap_group;


/* 5. Customers and value by state and region
   Separates places with many customers from places with big customers.
   Check: the 5 regions add up to the revenue of file 10. */
-- 5a. top 10 states by customers
SELECT TOP 10
       c.customer_state,
       COUNT(DISTINCT o.customer_unique_id)                              AS customers,
       CAST(SUM(i.price) AS DECIMAL(14,2))                               AS revenue,
       CAST(SUM(i.price) / COUNT(DISTINCT o.customer_unique_id) AS DECIMAL(10,2)) AS revenue_per_customer
FROM clean.order_items i
JOIN clean.orders   o ON o.order_id = i.order_id
JOIN clean.customer c ON c.customer_unique_id = o.customer_unique_id
WHERE i.in_sales_scope = 1
GROUP BY c.customer_state
ORDER BY customers DESC;

-- 5b. all regions
SELECT c.region,
       COUNT(DISTINCT o.customer_unique_id)                              AS customers,
       CAST(COUNT(DISTINCT o.customer_unique_id) * 100.0
            / SUM(COUNT(DISTINCT o.customer_unique_id)) OVER () AS DECIMAL(5,2)) AS pct_of_customers,
       CAST(SUM(i.price) AS DECIMAL(14,2))                               AS revenue,
       CAST(SUM(i.price) / COUNT(DISTINCT o.customer_unique_id) AS DECIMAL(10,2)) AS revenue_per_customer
FROM clean.order_items i
JOIN clean.orders   o ON o.order_id = i.order_id
JOIN clean.customer c ON c.customer_unique_id = o.customer_unique_id
WHERE i.in_sales_scope = 1
GROUP BY c.region
ORDER BY customers DESC;


/* 6. One-time vs repeat customers
   Shows whether the small group that comes back is worth a special effort. */
WITH order_revenue AS (
    SELECT order_id, SUM(price) AS revenue
    FROM clean.order_items
    GROUP BY order_id
),
customer_value AS (
    SELECT o.customer_unique_id,
           COUNT(*)                    AS orders,
           SUM(ISNULL(r.revenue, 0))   AS revenue
    FROM clean.orders o
    LEFT JOIN order_revenue r ON r.order_id = o.order_id
    WHERE o.in_sales_scope = 1
    GROUP BY o.customer_unique_id
)
SELECT CASE WHEN orders = 1 THEN 'one order' ELSE '2 or more orders' END AS customer_type,
       COUNT(*)                                                         AS customers,
       CAST(SUM(revenue) AS DECIMAL(14,2))                              AS revenue,
       CAST(SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER () AS DECIMAL(5,2)) AS pct_of_revenue,
       CAST(SUM(revenue) / COUNT(*) AS DECIMAL(10,2))                   AS revenue_per_customer
FROM customer_value
GROUP BY CASE WHEN orders = 1 THEN 'one order' ELSE '2 or more orders' END
ORDER BY customer_type DESC;


/* 7. First delivery, first review and coming back
   Links the delivery question (file 11) to the customer question.
   Scope: customers whose first order is in the delivery scope, has a review and was placed before
   2018-01-01. */
WITH numbered AS (
    SELECT o.customer_unique_id,
           o.order_id,
           o.purchase_date,
           o.in_delivery_scope,
           o.is_late,
           ROW_NUMBER() OVER (PARTITION BY o.customer_unique_id
                              ORDER BY o.order_purchase_timestamp, o.order_id) AS order_number,
           COUNT(*)     OVER (PARTITION BY o.customer_unique_id)               AS total_orders
    FROM clean.orders o
    WHERE o.in_sales_scope = 1
),
first_orders AS (
    SELECT n.customer_unique_id, n.is_late, r.review_score,
           CASE WHEN n.total_orders > 1 THEN 1 ELSE 0 END AS came_back
    FROM numbered n
    JOIN clean.reviews r ON r.order_id = n.order_id
    WHERE n.order_number = 1
      AND n.in_delivery_scope = 1
      AND n.purchase_date < '2018-01-01'
)
-- 7a. first order late or on time
SELECT CASE WHEN is_late = 1 THEN 'first order late' ELSE 'first order on time' END AS first_delivery,
       COUNT(*)                                                         AS customers,
       SUM(came_back)                                                   AS came_back,
       CAST(SUM(came_back) * 100.0 / COUNT(*) AS DECIMAL(5,2))          AS came_back_pct
FROM first_orders
GROUP BY is_late
ORDER BY is_late;
GO

-- 7b. score of the first order
WITH numbered AS (
    SELECT o.customer_unique_id,
           o.order_id,
           o.purchase_date,
           o.in_delivery_scope,
           ROW_NUMBER() OVER (PARTITION BY o.customer_unique_id
                              ORDER BY o.order_purchase_timestamp, o.order_id) AS order_number,
           COUNT(*)     OVER (PARTITION BY o.customer_unique_id)               AS total_orders
    FROM clean.orders o
    WHERE o.in_sales_scope = 1
),
first_orders AS (
    SELECT n.customer_unique_id, r.review_score,
           CASE WHEN n.total_orders > 1 THEN 1 ELSE 0 END AS came_back
    FROM numbered n
    JOIN clean.reviews r ON r.order_id = n.order_id
    WHERE n.order_number = 1
      AND n.in_delivery_scope = 1
      AND n.purchase_date < '2018-01-01'
)
SELECT review_score                                                     AS first_order_score,
       COUNT(*)                                                         AS customers,
       SUM(came_back)                                                   AS came_back,
       CAST(SUM(came_back) * 100.0 / COUNT(*) AS DECIMAL(5,2))          AS came_back_pct
FROM first_orders
GROUP BY review_score
ORDER BY review_score;
