/* 11_delivery_satisfaction_analysis.sql
   Delivery and satisfaction: how often are orders late, and does lateness hurt the reviews?
   Delivery scope, trend from 2017-01 to 2018-08. The definitions are in the README. */

USE OlistDB;
GO


/* 1. Headline numbers
   The delivery KPIs of the dashboard. */
SELECT COUNT(*)                                                     AS delivered_orders,
       CAST(AVG(delivery_days * 1.0) AS DECIMAL(5,2))               AS avg_days,
       MIN(delivery_days)                                           AS min_days,
       MAX(delivery_days)                                           AS max_days,
       SUM(is_late)                                                 AS late_orders,
       CAST(SUM(is_late) * 100.0 / COUNT(*) AS DECIMAL(5,2))        AS late_pct
FROM clean.orders
WHERE in_delivery_scope = 1;

SELECT DISTINCT
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days) OVER () AS median_days
FROM clean.orders
WHERE in_delivery_scope = 1;


/* 2. Delivery time groups
   An average hides the long deliveries. */
SELECT delivery_group,
       COUNT(*)                                                      AS orders,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_orders
FROM (
    SELECT CASE WHEN delivery_days <=  7 THEN '1) 0-7 days'
                WHEN delivery_days <= 14 THEN '2) 8-14 days'
                WHEN delivery_days <= 21 THEN '3) 15-21 days'
                WHEN delivery_days <= 30 THEN '4) 22-30 days'
                WHEN delivery_days <= 60 THEN '5) 31-60 days'
                ELSE                          '6) over 60 days'
           END AS delivery_group
    FROM clean.orders
    WHERE in_delivery_scope = 1
) AS t
GROUP BY delivery_group
ORDER BY delivery_group;


/* 3. Late rate by month
   Peaks show when the logistics could not follow the demand. The month is the purchase month. */
SELECT YEAR(purchase_date)                                          AS yr,
       MONTH(purchase_date)                                         AS mth,
       COUNT(*)                                                     AS delivered_orders,
       SUM(is_late)                                                 AS late_orders,
       CAST(SUM(is_late) * 100.0 / COUNT(*) AS DECIMAL(5,2))        AS late_pct,
       CAST(AVG(delivery_days * 1.0) AS DECIMAL(5,2))               AS avg_days
FROM clean.orders
WHERE in_delivery_scope = 1
  AND purchase_date >= '2017-01-01'
  AND purchase_date <  '2018-09-01'
GROUP BY YEAR(purchase_date), MONTH(purchase_date)
ORDER BY yr, mth;


/* 4. Late rate by customer state
   Shows where the delivery problem is. States with fewer than 500 delivered orders are left out,
   because the rate of a small state moves too much. */
SELECT c.customer_state,
       COUNT(*)                                                     AS delivered_orders,
       SUM(o.is_late)                                               AS late_orders,
       CAST(SUM(o.is_late) * 100.0 / COUNT(*) AS DECIMAL(5,2))      AS late_pct,
       CAST(AVG(o.delivery_days * 1.0) AS DECIMAL(5,2))             AS avg_days
FROM clean.orders o
JOIN clean.customer c ON c.customer_unique_id = o.customer_unique_id
WHERE o.in_delivery_scope = 1
GROUP BY c.customer_state
HAVING COUNT(*) >= 500
ORDER BY late_pct DESC;


/* 5. How late are the late orders
   One day late and two weeks late are different problems. Days late = days between the estimated
   date and the delivery date. */
SELECT late_group,
       COUNT(*)                                                      AS late_orders,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_late_orders
FROM (
    SELECT CASE WHEN DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) <=  3 THEN '1) 1-3 days late'
                WHEN DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) <=  7 THEN '2) 4-7 days late'
                WHEN DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) <= 14 THEN '3) 8-14 days late'
                ELSE                                                                                       '4) over 14 days late'
           END AS late_group
    FROM clean.orders
    WHERE in_delivery_scope = 1
      AND is_late = 1
) AS t
GROUP BY late_group
ORDER BY late_group;


/* 6. Reviews: coverage and scores
   The review analysis is only as good as its coverage. */
-- 6a. coverage and average score
SELECT COUNT(*)                                                       AS delivered_orders,
       COUNT(r.order_id)                                              AS orders_with_review,
       CAST(COUNT(r.order_id) * 100.0 / COUNT(*) AS DECIMAL(5,2))     AS pct_with_review,
       CAST(AVG(r.review_score * 1.0) AS DECIMAL(4,2))                AS avg_score
FROM clean.orders o
LEFT JOIN clean.reviews r ON r.order_id = o.order_id
WHERE o.in_delivery_scope = 1;

-- 6b. score distribution
SELECT r.review_score,
       COUNT(*)                                                      AS reviews,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_reviews
FROM clean.orders o
JOIN clean.reviews r ON r.order_id = o.order_id
WHERE o.in_delivery_scope = 1
GROUP BY r.review_score
ORDER BY r.review_score;


/* 7. Review score: late vs on time
   This is the main question of the file. */
SELECT CASE WHEN o.is_late = 1 THEN 'late' ELSE 'on time' END          AS delivery,
       COUNT(*)                                                        AS reviews,
       CAST(AVG(r.review_score * 1.0) AS DECIMAL(4,2))                 AS avg_score,
       CAST(SUM(CASE WHEN r.review_score = 1 THEN 1 ELSE 0 END) * 100.0
            / COUNT(*) AS DECIMAL(5,2))                                AS pct_1_star,
       CAST(SUM(CASE WHEN r.review_score = 5 THEN 1 ELSE 0 END) * 100.0
            / COUNT(*) AS DECIMAL(5,2))                                AS pct_5_star
FROM clean.orders o
JOIN clean.reviews r ON r.order_id = o.order_id
WHERE o.in_delivery_scope = 1
GROUP BY o.is_late
ORDER BY o.is_late;


/* 8. Review score by days late
   A gradual fall would show that the delay itself matters. */
SELECT delay_group,
       COUNT(*)                                                        AS reviews,
       CAST(AVG(review_score * 1.0) AS DECIMAL(4,2))                   AS avg_score,
       CAST(SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END) * 100.0
            / COUNT(*) AS DECIMAL(5,2))                                AS pct_1_star
FROM (
    SELECT r.review_score,
           CASE WHEN o.is_late = 0 THEN '0) on time'
                WHEN DATEDIFF(DAY, o.order_estimated_delivery_date, o.order_delivered_customer_date) <=  3 THEN '1) 1-3 days late'
                WHEN DATEDIFF(DAY, o.order_estimated_delivery_date, o.order_delivered_customer_date) <=  7 THEN '2) 4-7 days late'
                WHEN DATEDIFF(DAY, o.order_estimated_delivery_date, o.order_delivered_customer_date) <= 14 THEN '3) 8-14 days late'
                ELSE                                                                                           '4) over 14 days late'
           END AS delay_group
    FROM clean.orders o
    JOIN clean.reviews r ON r.order_id = o.order_id
    WHERE o.in_delivery_scope = 1
) AS t
GROUP BY delay_group
ORDER BY delay_group;
