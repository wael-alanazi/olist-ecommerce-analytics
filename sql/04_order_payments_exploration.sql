/* 04_order_payments_exploration.sql
   A first look at order_payments (one row is one payment of an order): structure, quality, and a
   check that the payments agree with the order items.
   Nothing is deleted from the table. Filters are applied per question, inside the query or later in Power BI. */

USE OlistDB;
GO


/* 1. First look
   Are the values and the installments numbers? Text values cannot be summed. */
SELECT TOP 10 * FROM olist.order_payments;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'olist' AND TABLE_NAME = 'order_payments'
ORDER BY ORDINAL_POSITION;


/* 2. Keys
   Which columns identify one row? An order can be paid in several payments, so order_id alone is
   not unique. The key is the pair (order_id, payment_sequential). */
SELECT COUNT(*)                 AS count_rows,
       COUNT(DISTINCT order_id) AS distinct_order_id
FROM olist.order_payments;

-- If this returns no rows, the pair (order_id, payment_sequential) is unique
SELECT order_id, payment_sequential, COUNT(*) AS n
FROM olist.order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;


/* 3. Missing values
   Which columns have NULLs? A payment without a value or a type cannot be used. */
SELECT
    SUM(CASE WHEN order_id             IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN payment_sequential   IS NULL THEN 1 ELSE 0 END) AS null_payment_sequential,
    SUM(CASE WHEN payment_type         IS NULL THEN 1 ELSE 0 END) AS null_payment_type,
    SUM(CASE WHEN payment_installments IS NULL THEN 1 ELSE 0 END) AS null_payment_installments,
    SUM(CASE WHEN payment_value        IS NULL THEN 1 ELSE 0 END) AS null_payment_value
FROM olist.order_payments;


/* 4. Payment types
   Which payment types exist, and how common is each? Unexpected values (for example "not_defined")
   must be known before grouping by type in the dashboard.
   Decision: not_defined rows are kept and grouped as "Other" in the dashboard. */
SELECT payment_type,
       COUNT(*)                                                         AS payments,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2))   AS pct_of_payments,
       CAST(SUM(payment_value) AS DECIMAL(14,2))                        AS total_value
FROM olist.order_payments
GROUP BY payment_type
ORDER BY payments DESC;


/* 5. Payments per order and installments
   How many payments does an order have, and how many installments? An order with several payments
   (for example voucher + card) must not be counted as several orders.
   Decision: count orders with COUNT(DISTINCT order_id), never payment rows. Rows with 0 installments
   are kept (negligible; treat them as 1 if installments are ever analyzed). */
SELECT payments_in_order,
       COUNT(*) AS orders,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_orders
FROM (SELECT order_id, COUNT(*) AS payments_in_order
      FROM olist.order_payments
      GROUP BY order_id) t
GROUP BY payments_in_order
ORDER BY payments_in_order;

SELECT MIN(payment_installments)                              AS min_installments,
       MAX(payment_installments)                              AS max_installments,
       CAST(AVG(payment_installments * 1.0) AS DECIMAL(5,2))  AS avg_installments,
       SUM(CASE WHEN payment_installments = 0 THEN 1 ELSE 0 END) AS zero_installments
FROM olist.order_payments;


/* 6. Payment value
   What are the minimum, maximum and average payment values? Zero, negative or extreme values
   distort totals.
   Decision: keep all rows. A 0.00 row is not an error by itself (a voucher can sit beside another
   payment); what matters is the order total, checked below. */
SELECT MIN(payment_value)                         AS min_value,
       MAX(payment_value)                         AS max_value,
       CAST(AVG(payment_value) AS DECIMAL(10,2))  AS avg_value
FROM olist.order_payments;

SELECT p.order_id, p.payment_value, p.payment_type, o.order_status
FROM olist.order_payments p
LEFT JOIN olist.orders o ON o.order_id = p.order_id
WHERE p.payment_value <= 0;

-- Orders whose TOTAL payment is zero
SELECT p.order_id, o.order_status, SUM(p.payment_value) AS paid
FROM olist.order_payments p
JOIN olist.orders o ON o.order_id = p.order_id
GROUP BY p.order_id, o.order_status
HAVING SUM(p.payment_value) = 0;


/* 7. Join integrity
   Do payments connect to orders, and do orders have payments? An unmatched row is silently lost in
   any JOIN. */
SELECT COUNT(*) AS payments_without_order
FROM olist.order_payments p
WHERE NOT EXISTS (SELECT 1 FROM olist.orders o WHERE o.order_id = p.order_id);

SELECT o.order_status, COUNT(*) AS orders_without_payment
FROM olist.orders o
WHERE NOT EXISTS (SELECT 1 FROM olist.order_payments p WHERE p.order_id = o.order_id)
GROUP BY o.order_status;


/* 8. Sanity check: payments vs items
   Does what customers paid agree with price + freight of the items? If the two sources disagree,
   revenue would change depending on the table it is taken from. This tests the data, it is not an
   analysis.
   Method: aggregate each table per order first, then join the two results (joining items and
   payments row by row would multiply rows).
   Decision: sales revenue stays SUM(price) from order_items; the payment value is used only for the
   payment-method analysis. */
SELECT CAST(SUM(payment_value) AS DECIMAL(14,2)) AS total_payments
FROM olist.order_payments;

WITH pay AS (
    SELECT order_id, SUM(payment_value) AS paid
    FROM olist.order_payments
    GROUP BY order_id
),
itm AS (
    SELECT order_id, SUM(price + freight_value) AS items_total
    FROM olist.order_items
    GROUP BY order_id
)
SELECT COUNT(*)                                                           AS orders_compared,
       SUM(CASE WHEN ABS(p.paid - i.items_total) <= 1 THEN 1 ELSE 0 END) AS matching_within_1,
       SUM(CASE WHEN p.paid - i.items_total > 1 THEN 1 ELSE 0 END)        AS paid_more,
       SUM(CASE WHEN i.items_total - p.paid > 1 THEN 1 ELSE 0 END)        AS paid_less
FROM pay p
JOIN itm i ON i.order_id = p.order_id;

-- Payments of orders that have no items (part of the 165,318.88 gap)
SELECT COUNT(*)                            AS orders_paid_without_items,
       CAST(SUM(p.paid) AS DECIMAL(14,2))  AS paid_without_items
FROM (SELECT order_id, SUM(payment_value) AS paid
      FROM olist.order_payments
      GROUP BY order_id) p
WHERE NOT EXISTS (SELECT 1 FROM olist.order_items i WHERE i.order_id = p.order_id);


/* What the rest of the project takes from this file
   - Key = (order_id, payment_sequential); orders = COUNT(DISTINCT order_id), never payment rows
   - Payment methods: credit_card, boleto, voucher, debit_card; not_defined is grouped as "Other"
   - Payment value is used for the payment-method analysis only; sales revenue stays SUM(price)
     from order_items
   - Rows with 0 installments are kept
   - A delivered order without a payment is kept: it has no effect on sales */
