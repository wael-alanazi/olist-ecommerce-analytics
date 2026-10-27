/* 03_order_items_exploration.sql
   A first look at order_items (one row is one item of an order): structure, quality, and the
   definition of revenue.
   Nothing is deleted from the table. Filters are applied per question, inside the query or later in Power BI. */

USE OlistDB;
GO


/* 1. First look
   Are price and freight numbers? Text values cannot be summed. */
SELECT TOP 10 * FROM olist.order_items;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'olist' AND TABLE_NAME = 'order_items'
ORDER BY ORDINAL_POSITION;


/* 2. Keys
   Is order_id alone unique? An order has one row per item, so the key is the pair
   (order_id, order_item_id). Joining on order_id alone multiplies rows. */
SELECT COUNT(*)                 AS count_rows,
       COUNT(DISTINCT order_id) AS distinct_order_id
FROM olist.order_items;

-- If this returns no rows, the pair (order_id, order_item_id) is unique
SELECT order_id, order_item_id, COUNT(*) AS n
FROM olist.order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;


/* 3. Missing values
   Which columns have NULLs? No revenue can be computed from a row without a price or a seller. */
SELECT
    SUM(CASE WHEN order_id            IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN order_item_id       IS NULL THEN 1 ELSE 0 END) AS null_order_item_id,
    SUM(CASE WHEN product_id          IS NULL THEN 1 ELSE 0 END) AS null_product_id,
    SUM(CASE WHEN seller_id           IS NULL THEN 1 ELSE 0 END) AS null_seller_id,
    SUM(CASE WHEN shipping_limit_date IS NULL THEN 1 ELSE 0 END) AS null_shipping_limit_date,
    SUM(CASE WHEN price               IS NULL THEN 1 ELSE 0 END) AS null_price,
    SUM(CASE WHEN freight_value       IS NULL THEN 1 ELSE 0 END) AS null_freight_value
FROM olist.order_items;


/* 4. Items per order
   How many items does an order usually have? This separates "number of orders" from "number of
   items": mixing them changes every KPI.
   Decision: always count orders with COUNT(DISTINCT order_id), never rows. */
SELECT items_in_order,
       COUNT(*) AS orders,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_orders
FROM (SELECT order_id, COUNT(*) AS items_in_order
      FROM olist.order_items
      GROUP BY order_id) t
GROUP BY items_in_order
ORDER BY items_in_order;


/* 5. Price and freight
   What are the minimum, maximum and average of price and freight? One extreme or zero value
   distorts revenue and averages.
   Decision: keep all rows. A high maximum price can still be real. */
SELECT MIN(price)                                AS min_price,
       MAX(price)                                AS max_price,
       CAST(AVG(price) AS DECIMAL(10,2))         AS avg_price,
       MIN(freight_value)                        AS min_freight,
       MAX(freight_value)                        AS max_freight,
       CAST(AVG(freight_value) AS DECIMAL(10,2)) AS avg_freight
FROM olist.order_items;

SELECT SUM(CASE WHEN price <= 0 THEN 1 ELSE 0 END)         AS price_zero_or_negative,
       SUM(CASE WHEN freight_value < 0 THEN 1 ELSE 0 END)  AS freight_negative,
       SUM(CASE WHEN freight_value = 0 THEN 1 ELSE 0 END)  AS free_shipping_rows
FROM olist.order_items;


/* 6. Freight share of price (preview)
   How large is shipping compared with the product price? It is reviewed again in the analysis phase. */
SELECT CAST(SUM(freight_value) * 100.0 / SUM(price) AS DECIMAL(5,2))   AS freight_pct_of_total_price,
       SUM(CASE WHEN freight_value > price THEN 1 ELSE 0 END)          AS items_freight_above_price,
       CAST(SUM(CASE WHEN freight_value > price THEN 1 ELSE 0 END) * 100.0
            / COUNT(*) AS DECIMAL(5,2))                                AS pct_items_freight_above_price
FROM olist.order_items;


/* 7. Revenue definition
   Is revenue the price only, or price + freight_value? I decide it once, then use it in every query
   and every Power BI measure.
   Decision:
   - revenue = SUM(price); freight is a shipping cost, not product sales
   - freight = SUM(freight_value), shown as a separate measure
   - total paid by customers = SUM(price + freight_value), only when needed
   - orders = COUNT(DISTINCT order_id)
   - average order value = SUM(price) / COUNT(DISTINCT order_id)
   - the cross-check with the payments table is in 04_order_payments */
SELECT CAST(SUM(price) AS DECIMAL(14,2))                 AS total_price,
       CAST(SUM(freight_value) AS DECIMAL(14,2))         AS total_freight,
       CAST(SUM(price + freight_value) AS DECIMAL(14,2)) AS total_paid
FROM olist.order_items;


/* 8. Seller deadline vs carrier handover (preview)
   Do sellers hand the package to the carrier before the shipping limit date? This helps separate
   seller delay from carrier delay when late deliveries are explained.
   Method: an order can have several items, each with its own shipping_limit_date, so the check is
   made per order using the latest deadline among its items (the lenient choice: late only if after
   all deadlines). Compared by date, like the late-delivery rule.
   Scope: delivered orders with a carrier date, without the carrier-before-purchase rows (see
   02_orders, section 7).
   Note: because the latest deadline is used, the result is the minimum share of late handovers.
   Whether they explain the late deliveries is tested in the analysis phase, not here. */
WITH order_deadline AS (
    SELECT order_id, MAX(shipping_limit_date) AS last_shipping_limit
    FROM olist.order_items
    GROUP BY order_id
)
SELECT COUNT(*) AS orders_checked,
       SUM(CASE WHEN CAST(o.order_delivered_carrier_date AS DATE)
                    > CAST(d.last_shipping_limit AS DATE) THEN 1 ELSE 0 END) AS handed_over_late,
       CAST(SUM(CASE WHEN CAST(o.order_delivered_carrier_date AS DATE)
                    > CAST(d.last_shipping_limit AS DATE) THEN 1 ELSE 0 END) * 100.0
            / COUNT(*) AS DECIMAL(5,2)) AS pct_handed_over_late
FROM olist.orders o
JOIN order_deadline d ON d.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_carrier_date IS NOT NULL
  AND o.order_delivered_carrier_date >= o.order_purchase_timestamp;


/* 9. Join integrity
   Do items connect to orders, products and sellers? An unmatched row is silently lost in any JOIN.
   Only key existence is tested here; products and sellers have their own exploration files. */
SELECT
    (SELECT COUNT(*) FROM olist.order_items i
     WHERE NOT EXISTS (SELECT 1 FROM olist.orders o   WHERE o.order_id   = i.order_id))   AS items_without_order,
    (SELECT COUNT(*) FROM olist.order_items i
     WHERE NOT EXISTS (SELECT 1 FROM olist.products p WHERE p.product_id = i.product_id)) AS items_without_product,
    (SELECT COUNT(*) FROM olist.order_items i
     WHERE NOT EXISTS (SELECT 1 FROM olist.sellers s  WHERE s.seller_id  = i.seller_id))  AS items_without_seller;


/* 10. Monthly revenue (preview)
   How does revenue move month by month? It is the first number of the Sales page.
   Scope: orders that are not canceled or unavailable; purchase date 2017-01 to 2018-08.
   Note: the join items to orders is many to one, so it does not multiply rows. Order count and
   average order value use COUNT(DISTINCT order_id), never item rows. These figures are a baseline
   for the Sales page, not the final analysis. */
SELECT YEAR(o.order_purchase_timestamp)                                     AS yr,
       MONTH(o.order_purchase_timestamp)                                    AS mth,
       COUNT(DISTINCT o.order_id)                                           AS orders,
       CAST(SUM(i.price) AS DECIMAL(14,2))                                  AS revenue,
       CAST(SUM(i.freight_value) AS DECIMAL(14,2))                          AS freight,
       CAST(SUM(i.price) / COUNT(DISTINCT o.order_id) AS DECIMAL(10,2))     AS avg_order_value
FROM olist.order_items i
JOIN olist.orders o ON o.order_id = i.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY YEAR(o.order_purchase_timestamp), MONTH(o.order_purchase_timestamp)
ORDER BY yr, mth;


/* What the rest of the project takes from this file
   Definitions
   - revenue = SUM(price)
   - freight = SUM(freight_value), a separate measure
   - orders = COUNT(DISTINCT order_id)
   - average order value = SUM(price) / COUNT(DISTINCT order_id)
   Scope
   - sales metrics: orders that are not canceled or unavailable; trend charts 2017-01 to 2018-08
   - seller vs carrier analysis: delivered orders, per order, without the carrier-before-purchase rows
   - time axis: the purchase date of the order (from olist.orders)
   Joins
   - order_items to orders is many to one: safe for revenue
   - orders to order_items is one to many: count with DISTINCT order_id
   Columns to keep: order_id, order_item_id, product_id, seller_id, shipping_limit_date, price,
   freight_value */
