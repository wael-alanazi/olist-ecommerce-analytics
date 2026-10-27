/* 02_orders_exploration.sql
   A first look at the orders table (one row is one order): structure, quality, and which orders count
   for which question.
   Nothing is deleted from the table. Filters are applied per question, inside the query or later in Power BI. */

USE OlistDB;
GO


/* 1. First look
   Are the dates real dates? Text dates cannot be subtracted, so the types come first. */
SELECT TOP 10 * FROM olist.orders;

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'olist' AND TABLE_NAME = 'orders'
ORDER BY ORDINAL_POSITION;


/* 2. Keys: NULLs and uniqueness
   Is every order exactly one row, with its own customer_id? A repeated order_id would silently
   double every revenue and delivery number later. */
SELECT
    COUNT(*)                     AS row_count,
    COUNT(order_id)              AS order_id_non_null,
    COUNT(DISTINCT order_id)     AS order_id_unique,
    COUNT(customer_id)           AS customer_id_non_null,
    COUNT(DISTINCT customer_id)  AS customer_id_unique
FROM olist.orders;


/* 3. Order status
   Which statuses exist, and how big is each? Delivery and revenue cannot be measured for orders that
   were canceled or never shipped, so I need to know what to exclude.
   Decision:
   - delivery and late analysis use status = 'delivered' only
   - sales analysis excludes 'canceled' and 'unavailable' */
SELECT order_status,
       COUNT(*) AS orders,
       CAST(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM olist.orders) AS DECIMAL(5,2)) AS pct
FROM olist.orders
GROUP BY order_status
ORDER BY orders DESC;


/* 4. Missing dates, by status
   Which date columns have NULLs, and are they expected? A missing delivery date is normal for a
   canceled or not yet shipped order, but a 'delivered' order without one is a data error.
   Totals alone can hide errors that cancel each other, so the count is split by status.
   Decision:
   - delivered orders without a delivery date are left out of the delivery metrics only (no delivery
     time can be computed) and stay in sales
   - canceled orders that have a delivery date are ignored, since canceled orders are excluded from
     the analysis anyway */
SELECT order_status,
       COUNT(*) AS orders,
       SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END)              AS null_approved,
       SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END)   AS null_carrier,
       SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END)  AS null_customer,
       SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END)  AS null_estimated
FROM olist.orders
GROUP BY order_status
ORDER BY orders DESC;


/* 5. Date range
   What period does the data cover, and are there impossible dates? Future or very old dates would
   point to a loading problem. */
SELECT MIN(order_purchase_timestamp)       AS min_purchase,
       MAX(order_purchase_timestamp)       AS max_purchase,
       MIN(order_delivered_customer_date)  AS min_delivered,
       MAX(order_delivered_customer_date)  AS max_delivered,
       MIN(order_estimated_delivery_date)  AS min_estimated,
       MAX(order_estimated_delivery_date)  AS max_estimated
FROM olist.orders;


/* 6. Orders per month
   Are all months complete? Min and max do not show gaps, and months with very few orders distort
   the trend lines.
   Note: these counts include every status, so they are higher than the monthly order counts in
   03_order_items, which leave out canceled and unavailable orders.
   Decision:
   - trend charts use only 2017-01 to 2018-08 (20 full months), through a date filter in Power BI;
     no rows are deleted
   - 2016 and 2018-09/10 are left out of the trend visuals only
   - the spike in November 2017 is most likely Black Friday: it is real and stays */
SELECT YEAR(order_purchase_timestamp)  AS yr,
       MONTH(order_purchase_timestamp) AS mth,
       COUNT(*)                        AS orders
FROM olist.orders
GROUP BY YEAR(order_purchase_timestamp), MONTH(order_purchase_timestamp)
ORDER BY yr, mth;


/* 7. Logical date order
   Do the dates follow the real sequence? purchase <= approved <= carrier <= customer delivery.
   A delivery before the purchase would break the delivery time.
   How: each column counts the orders that break one rule (1 = problem). NULL dates are skipped on
   purpose, they are covered in section 4. Dates are compared with their time, because the exact order
   of events matters. Only delivered orders are checked.
   Decision:
   - carrier before approval is probably normal (the seller shipped before the approval was recorded)
   - carrier before purchase and customer before carrier are data errors: those rows are excluded
     from the stage metrics only (purchase to carrier, carrier to customer). No rows are deleted.
   - total delivery time and the late flag are not affected
   - order_approved_at is not used for the stage analysis */
SELECT
    SUM(CASE WHEN order_approved_at             < order_purchase_timestamp      THEN 1 ELSE 0 END) AS approved_before_purchase,
    SUM(CASE WHEN order_delivered_carrier_date  < order_approved_at             THEN 1 ELSE 0 END) AS carrier_before_approved,
    SUM(CASE WHEN order_delivered_carrier_date  < order_purchase_timestamp      THEN 1 ELSE 0 END) AS carrier_before_purchase,
    SUM(CASE WHEN order_delivered_customer_date < order_delivered_carrier_date  THEN 1 ELSE 0 END) AS customer_before_carrier,
    SUM(CASE WHEN order_delivered_customer_date < order_purchase_timestamp      THEN 1 ELSE 0 END) AS customer_before_purchase
FROM olist.orders
WHERE order_status = 'delivered';


/* 8. Delivery time and late flag (definition and preview)
   How long does delivery take, and how many orders are late? These are the core metrics of the
   Delivery page.
   Scope: status = 'delivered' AND a delivery date exists.
   Definitions used everywhere, in SQL and in Power BI:
     delivery_days = DATEDIFF(DAY, purchase, customer delivery)
     is_late       = delivered DATE > estimated DATE
     late_rate     = late orders / delivered orders in scope
   Lateness is compared by date, not by time. The estimated dates are always 00:00:00, so comparing
   times would wrongly mark orders delivered on the promised day as late. */
WITH delivered_scope AS (
    SELECT order_id,
           DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date) AS delivery_days,
           CASE WHEN CAST(order_delivered_customer_date AS DATE)
                   > CAST(order_estimated_delivery_date AS DATE) THEN 1 ELSE 0 END AS is_late
    FROM olist.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
)
SELECT COUNT(*)                                          AS delivered_orders,
       MIN(delivery_days)                                AS min_days,
       CAST(AVG(delivery_days * 1.0) AS DECIMAL(5,2))    AS avg_days,
       MAX(delivery_days)                                AS max_days,
       SUM(is_late)                                      AS late_orders,
       CAST(SUM(is_late) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS late_rate_pct
FROM delivered_scope;


/* 9. Extreme delivery times
   How many deliveries take more than 60 days, and do they distort the average?
   Decision: keep them. They are real, very late deliveries, and their effect on the average is small. */
WITH delivered_scope AS (
    SELECT order_id,
           DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date) AS delivery_days
    FROM olist.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
)
SELECT SUM(CASE WHEN delivery_days > 60 THEN 1 ELSE 0 END)                    AS orders_over_60_days,
       COUNT(*)                                                               AS delivered_orders,
       CAST(SUM(CASE WHEN delivery_days > 60 THEN 1 ELSE 0 END) * 100.0
            / COUNT(*) AS DECIMAL(5,2))                                       AS pct_over_60_days
FROM delivered_scope;


/* 10. Join integrity
   Do orders connect correctly to items, payments and customers? Revenue comes from order_items and
   order_payments, so every order that should have items or a payment must have them.
   Note: order_items has many rows per order, so orders are always counted with
   COUNT(DISTINCT order_id). Missing matches are checked with NOT EXISTS (clear meaning, safe with
   NULLs), never with NOT IN. */

-- 10a. Delivered orders that have at least one item
SELECT COUNT(DISTINCT o.order_id) AS delivered_orders_with_items
FROM olist.orders o
JOIN olist.order_items i ON i.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- 10b. Orders with NO items, by status
SELECT o.order_status, COUNT(*) AS orders_without_items
FROM olist.orders o
WHERE NOT EXISTS (SELECT 1 FROM olist.order_items i WHERE i.order_id = o.order_id)
GROUP BY o.order_status
ORDER BY orders_without_items DESC;

-- 10c. Orders with NO payment, by status
SELECT o.order_status, COUNT(*) AS orders_without_payment
FROM olist.orders o
WHERE NOT EXISTS (SELECT 1 FROM olist.order_payments p WHERE p.order_id = o.order_id)
GROUP BY o.order_status
ORDER BY orders_without_payment DESC;

-- 10d. Orders whose customer_id does not exist in customers
SELECT COUNT(*) AS orphan_orders
FROM olist.orders o
WHERE NOT EXISTS (SELECT 1 FROM olist.customers c WHERE c.customer_id = o.customer_id);


/* Optional: key constraint (run once, after all checks)
   Enforces uniqueness and speeds up joins. Running 00_load_data.sql again rebuilds the tables and
   removes it. */
-- ALTER TABLE olist.orders ALTER COLUMN order_id VARCHAR(50) NOT NULL;
-- ALTER TABLE olist.orders ADD CONSTRAINT PK_orders PRIMARY KEY (order_id);
-- CREATE INDEX IX_orders_customer_id ON olist.orders (customer_id);


/* What the rest of the project takes from this file
   Scope
   - Delivery metrics: order_status = 'delivered' AND a delivery date
   - Stage metrics: also exclude the carrier-before-purchase and customer-before-carrier rows
   - Sales metrics: exclude 'canceled' and 'unavailable'
   - Trend charts: purchase date from 2017-01 to 2018-08
   - Time axis: order_purchase_timestamp (the month an order belongs to)
   Definitions
   - delivery_days = DATEDIFF(DAY, purchase, customer delivery)
   - late order = delivered DATE > estimated DATE
   Columns to keep: order_id, customer_id, order_status, order_purchase_timestamp,
   order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date.
   order_approved_at is kept but not used for the stage analysis. */
