/* 10_sales_analysis.sql
   Sales: how much do we sell, when, where, and what? Sales scope, trend from 2017-01 to 2018-08.
   The definitions are in the README. */

USE OlistDB;
GO


/* 1. Headline numbers
   The base numbers every other section is compared with. */
SELECT COUNT(DISTINCT i.order_id)                                              AS orders,
       COUNT(*)                                                                AS items,
       COUNT(DISTINCT o.customer_unique_id)                                    AS customers,
       CAST(SUM(i.price) AS DECIMAL(14,2))                                     AS revenue,
       CAST(SUM(i.freight_value) AS DECIMAL(14,2))                             AS freight,
       CAST(SUM(i.price) / COUNT(DISTINCT i.order_id) AS DECIMAL(10,2))        AS avg_order_value
FROM clean.order_items i
JOIN clean.orders o ON o.order_id = i.order_id
WHERE i.in_sales_scope = 1;


/* 2. Monthly trend
   Shows growth, seasonality and the peak month. */
WITH monthly AS (
    SELECT YEAR(purchase_date)         AS yr,
           MONTH(purchase_date)        AS mth,
           COUNT(DISTINCT order_id)    AS orders,
           SUM(price)                  AS revenue
    FROM clean.order_items
    WHERE in_sales_scope = 1
      AND purchase_date >= '2017-01-01'
      AND purchase_date <  '2018-09-01'
    GROUP BY YEAR(purchase_date), MONTH(purchase_date)
)
SELECT yr, mth, orders,
       CAST(revenue AS DECIMAL(14,2))          AS revenue,
       CAST(revenue / orders AS DECIMAL(10,2)) AS avg_order_value,
       CAST((revenue - LAG(revenue) OVER (ORDER BY yr, mth)) * 100.0
            / LAG(revenue) OVER (ORDER BY yr, mth) AS DECIMAL(6,2)) AS revenue_change_pct
FROM monthly
ORDER BY yr, mth;


/* 3. Top categories
   Shows where the money comes from. An order with several categories counts in each of them, so the
   category orders do not add up to the total. */
WITH category_sales AS (
    SELECT p.category_en,
           COUNT(DISTINCT i.order_id) AS orders,
           SUM(i.price)               AS revenue
    FROM clean.order_items i
    JOIN clean.product p ON p.product_id = i.product_id
    WHERE i.in_sales_scope = 1
    GROUP BY p.category_en
)
SELECT TOP 10
       category_en,
       orders,
       CAST(revenue AS DECIMAL(14,2))                         AS revenue,
       CAST(revenue * 100.0 / SUM(revenue) OVER () AS DECIMAL(5,2)) AS pct_of_revenue,
       CAST(SUM(revenue) OVER (ORDER BY revenue DESC
                               ROWS UNBOUNDED PRECEDING) * 100.0
            / SUM(revenue) OVER () AS DECIMAL(5,2))           AS cumulative_pct
FROM category_sales
ORDER BY revenue DESC;


/* 4. Category concentration
   A few categories carrying most of the revenue is a risk, and shows where to focus. */
WITH category_sales AS (
    SELECT p.category_en, SUM(i.price) AS revenue
    FROM clean.order_items i
    JOIN clean.product p ON p.product_id = i.product_id
    WHERE i.in_sales_scope = 1
    GROUP BY p.category_en
),
cumulative AS (
    SELECT category_en,
           SUM(revenue) OVER (ORDER BY revenue DESC
                              ROWS UNBOUNDED PRECEDING) * 100.0
           / SUM(revenue) OVER ()                        AS cumulative_pct
    FROM category_sales
)
SELECT COUNT(*)                                   AS categories_total,
       SUM(CASE WHEN cumulative_pct <= 80 THEN 1 ELSE 0 END) + 1 AS categories_for_80_pct
FROM cumulative;


/* 5. Revenue by customer state and region
   Shows where the demand is. The state of a customer is the state of the latest order
   (clean.customer). */
-- 5a. top 10 states
SELECT TOP 10
       c.customer_state,
       COUNT(DISTINCT i.order_id)                                       AS orders,
       CAST(SUM(i.price) AS DECIMAL(14,2))                              AS revenue,
       CAST(SUM(i.price) * 100.0 / SUM(SUM(i.price)) OVER () AS DECIMAL(5,2)) AS pct_of_revenue,
       CAST(SUM(i.price) / COUNT(DISTINCT i.order_id) AS DECIMAL(10,2)) AS avg_order_value
FROM clean.order_items i
JOIN clean.orders   o ON o.order_id = i.order_id
JOIN clean.customer c ON c.customer_unique_id = o.customer_unique_id
WHERE i.in_sales_scope = 1
GROUP BY c.customer_state
ORDER BY revenue DESC;

-- 5b. all regions
SELECT c.region,
       COUNT(DISTINCT i.order_id)                                       AS orders,
       CAST(SUM(i.price) AS DECIMAL(14,2))                              AS revenue,
       CAST(SUM(i.price) * 100.0 / SUM(SUM(i.price)) OVER () AS DECIMAL(5,2)) AS pct_of_revenue,
       CAST(SUM(i.price) / COUNT(DISTINCT i.order_id) AS DECIMAL(10,2)) AS avg_order_value
FROM clean.order_items i
JOIN clean.orders   o ON o.order_id = i.order_id
JOIN clean.customer c ON c.customer_unique_id = o.customer_unique_id
WHERE i.in_sales_scope = 1
GROUP BY c.region
ORDER BY revenue DESC;


/* 6. Freight by customer region
   High freight can reduce demand in distant regions. */
SELECT c.region,
       CAST(SUM(i.price) AS DECIMAL(14,2))                     AS revenue,
       CAST(SUM(i.freight_value) AS DECIMAL(14,2))             AS freight,
       CAST(SUM(i.freight_value) * 100.0 / SUM(i.price) AS DECIMAL(5,2)) AS freight_pct_of_price
FROM clean.order_items i
JOIN clean.orders   o ON o.order_id = i.order_id
JOIN clean.customer c ON c.customer_unique_id = o.customer_unique_id
WHERE i.in_sales_scope = 1
GROUP BY c.region
ORDER BY freight_pct_of_price DESC;


/* 7. Seller concentration
   A marketplace that depends on a few sellers is fragile. Sellers are ranked by revenue and split
   into 10 equal groups (NTILE); group 1 holds the biggest sellers. */
WITH seller_sales AS (
    SELECT seller_id, SUM(price) AS revenue
    FROM clean.order_items
    WHERE in_sales_scope = 1
    GROUP BY seller_id
),
seller_groups AS (
    SELECT revenue,
           NTILE(10) OVER (ORDER BY revenue DESC) AS seller_group
    FROM seller_sales
)
SELECT seller_group,
       COUNT(*)                                                   AS sellers,
       CAST(SUM(revenue) AS DECIMAL(14,2))                        AS revenue,
       CAST(SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER () AS DECIMAL(5,2)) AS pct_of_revenue
FROM seller_groups
GROUP BY seller_group
ORDER BY seller_group;


/* 8. How customers pay
   Shows which payment methods matter. Amounts come from clean.payments (one row per order);
   percentages are shares of the amount paid. */
SELECT CAST(SUM(p.total_paid) AS DECIMAL(14,2))                                      AS total_paid,
       CAST(SUM(p.paid_credit_card) * 100.0 / SUM(p.total_paid) AS DECIMAL(5,2))     AS pct_credit_card,
       CAST(SUM(p.paid_boleto)      * 100.0 / SUM(p.total_paid) AS DECIMAL(5,2))     AS pct_boleto,
       CAST(SUM(p.paid_voucher)     * 100.0 / SUM(p.total_paid) AS DECIMAL(5,2))     AS pct_voucher,
       CAST(SUM(p.paid_debit_card)  * 100.0 / SUM(p.total_paid) AS DECIMAL(5,2))     AS pct_debit_card,
       CAST(SUM(p.paid_other)       * 100.0 / SUM(p.total_paid) AS DECIMAL(5,2))     AS pct_other
FROM clean.payments p
JOIN clean.orders o ON o.order_id = p.order_id
WHERE o.in_sales_scope = 1;
