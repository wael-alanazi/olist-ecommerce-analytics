/* 09_clean_views.sql
   The cleaning and transformation layer: one view per raw table, in schema clean. The raw tables
   (schema olist) are never changed. The analysis files (10 onward) and Power BI read only from clean.

   The objects are created in this order: schema clean, then clean.category, clean.product,
   clean.customer, clean.seller, clean.orders, clean.order_items, clean.payments, clean.reviews.

   Each step says what the view is for, what is cleaned and which columns are added, followed by the
   view and a validation query with the expected result.
   Dates: Power BI generates its own date table; SQL groups with YEAR() and MONTH(). */


/* ---------------------------------------------------------------------
   Step 1. Schema clean
   Purpose : separates the clean views from the raw tables (olist).
   --------------------------------------------------------------------- */
CREATE SCHEMA clean;
GO

-- CHECK 1 : must return one row with the name clean
SELECT name AS schema_name FROM sys.schemas WHERE name = 'clean';


/* ---------------------------------------------------------------------
   Step 2. clean.category
   Source  : olist.product_category_translation (71 rows, file 08)

   Cleaning
     - 5 English names with spelling errors are corrected:
         fashio_female_clothing   -> fashion_female_clothing
         costruction_tools_garden -> construction_tools_garden
         costruction_tools_tools  -> construction_tools_tools
         home_confort             -> home_comfort
         arts_and_craftmanship    -> arts_and_craftsmanship
       (security_and_services is kept as it is.)
     - 2 categories used by products have no translation and are named
       manually:
         pc_gamer (3 products)                  -> pc_gamer
         portateis_cozinha_e_preparadores_de_alimentos (10 products)
                                    -> portable_kitchen_food_processors
   Transformation
     - Row 'unknown' for the 610 products without a category (file 06).
   Result  : 71 + 2 + 1 = 74 rows.
   --------------------------------------------------------------------- */
CREATE VIEW clean.category AS
SELECT t.product_category_name AS category_pt,
       CASE t.product_category_name_english
            WHEN 'fashio_female_clothing'   THEN 'fashion_female_clothing'
            WHEN 'costruction_tools_garden' THEN 'construction_tools_garden'
            WHEN 'costruction_tools_tools'  THEN 'construction_tools_tools'
            WHEN 'home_confort'             THEN 'home_comfort'
            WHEN 'arts_and_craftmanship'    THEN 'arts_and_craftsmanship'
            ELSE t.product_category_name_english
       END AS category_en
FROM olist.product_category_translation t
UNION ALL SELECT 'pc_gamer', 'pc_gamer'
UNION ALL SELECT 'portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_food_processors'
UNION ALL SELECT 'unknown', 'unknown';
GO

-- CHECK 2.1 : expected 74 rows and 74 different Portuguese names
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT category_pt) AS distinct_pt
FROM clean.category;

-- CHECK 2.2 : expected 8 rows (5 corrected + 2 named by hand + unknown)
SELECT category_pt, category_en
FROM clean.category
WHERE category_en IN ('fashion_female_clothing', 'construction_tools_garden',
                      'construction_tools_tools', 'home_comfort',
                      'arts_and_craftsmanship', 'pc_gamer',
                      'portable_kitchen_food_processors', 'unknown');

-- CHECK 2.3 : expected 0 rows. Every category used by a product must exist.
SELECT DISTINCT p.product_category_name
FROM olist.products p
WHERE p.product_category_name IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM clean.category c
                  WHERE c.category_pt = p.product_category_name);


/* ---------------------------------------------------------------------
   Step 3. clean.product
   Source  : olist.products (32,951 rows, file 06)

   Cleaning
     - Products without a category are labelled 'unknown' (610).
     - Products with weight 0 or NULL (6) are kept and flagged.
   Transformation
     - category_en       English category name (from clean.category)
     - has_valid_weight  1 if weight > 0, otherwise 0
   --------------------------------------------------------------------- */
GO
CREATE VIEW clean.product AS
SELECT p.product_id,
       ISNULL(p.product_category_name, 'unknown') AS category_pt,
       c.category_en,
       p.product_photos_qty  AS photos_qty,
       p.product_weight_g    AS weight_g,
       p.product_length_cm   AS length_cm,
       p.product_height_cm   AS height_cm,
       p.product_width_cm    AS width_cm,
       CASE WHEN p.product_weight_g > 0 THEN 1 ELSE 0 END AS has_valid_weight
FROM olist.products p
LEFT JOIN clean.category c
       ON c.category_pt = ISNULL(p.product_category_name, 'unknown');
GO

-- CHECK 3 : expected 32,951 rows; 610 'unknown'; 6 without valid weight;
--           0 products without an English category
SELECT COUNT(*)                                            AS total_rows,
       SUM(CASE WHEN category_pt = 'unknown' THEN 1 ELSE 0 END)    AS unknown_category,
       SUM(CASE WHEN has_valid_weight = 0 THEN 1 ELSE 0 END)       AS without_valid_weight,
       SUM(CASE WHEN category_en IS NULL THEN 1 ELSE 0 END)        AS without_english_name
FROM clean.product;


/* ---------------------------------------------------------------------
   Step 4. clean.customer
   Source  : olist.customers joined to olist.orders (file 01)
   Grain   : one row per customer_unique_id (96,096)

   Cleaning
     - customer_id is generated per order, so customers are identified by
       customer_unique_id.
     - A customer with several orders keeps the city and state of the
       latest order (ROW_NUMBER ordered by purchase time, then customer_id).
     - The zip prefix is not kept (geolocation is not used, file 08).
   Transformation
     - region  North / Northeast / Central-West / Southeast / South,
               derived from the state
   --------------------------------------------------------------------- */
GO
CREATE VIEW clean.customer AS
WITH ranked_customers AS (
    SELECT
        c.customer_unique_id,
        c.customer_state,
        c.customer_city,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp DESC,
                     c.customer_id DESC
        ) AS rn
    FROM olist.customers c
    JOIN olist.orders o
        ON c.customer_id = o.customer_id
)
SELECT
    customer_unique_id,
    customer_state,
    CASE
        WHEN customer_state IN ('AC','AP','AM','PA','RO','RR','TO')
            THEN 'North'
        WHEN customer_state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE')
            THEN 'Northeast'
        WHEN customer_state IN ('DF','GO','MT','MS')
            THEN 'Central-West'
        WHEN customer_state IN ('ES','MG','RJ','SP')
            THEN 'Southeast'
        WHEN customer_state IN ('PR','RS','SC')
            THEN 'South'
    END AS region,
    customer_city
FROM ranked_customers
WHERE rn = 1;
GO

-- CHECK 4 : expected 96,096 rows (= distinct customer_unique_id in the raw
--           table), no customer repeated, 5 regions
SELECT (SELECT COUNT(*) FROM clean.customer)                          AS rows_in_view,
       (SELECT COUNT(DISTINCT customer_unique_id) FROM clean.customer) AS distinct_customers,
       (SELECT COUNT(DISTINCT customer_unique_id) FROM olist.customers) AS in_raw_table,
       (SELECT COUNT(DISTINCT region) FROM clean.customer)            AS regions;


/* ---------------------------------------------------------------------
   Step 5. clean.seller
   Source  : olist.sellers (3,095 rows, file 07)
   Grain   : one row per seller_id

   Cleaning
     - seller_city is not kept: it is entered by hand and contains typos
       and extra text, and sellers are analysed by state (clean).
   Transformation
     - region  derived from seller_state, as for customers
   --------------------------------------------------------------------- */
GO
CREATE VIEW clean.seller AS
SELECT s.seller_id,
       s.seller_state,
       CASE WHEN s.seller_state IN ('AC','AP','AM','PA','RO','RR','TO')           THEN 'North'
            WHEN s.seller_state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Northeast'
            WHEN s.seller_state IN ('DF','GO','MT','MS')                          THEN 'Central-West'
            WHEN s.seller_state IN ('ES','MG','RJ','SP')                          THEN 'Southeast'
            WHEN s.seller_state IN ('PR','RS','SC')                               THEN 'South'
       END AS region
FROM olist.sellers s;
GO

-- CHECK 5.1 : expected 3,095 rows in the view and in the raw table,
--             no seller repeated
SELECT (SELECT COUNT(*) FROM clean.seller) AS rows_in_view,
       (SELECT COUNT(DISTINCT seller_id) FROM clean.seller) AS distinct_sellers,
       (SELECT COUNT(*) FROM olist.sellers) AS rows_in_raw;

-- CHECK 5.2 : sellers per region (expected 5 regions, none empty)
SELECT region, COUNT(*) AS sellers
FROM clean.seller
GROUP BY region
ORDER BY sellers DESC;


/* ---------------------------------------------------------------------
   Step 6. clean.orders
   Source  : olist.orders joined to olist.customers (99,441 rows, file 02)
   Grain   : one row per order

   Cleaning
     - customer_unique_id is added (customer_id changes with every order).
     - Orders with dates out of sequence (carrier before purchase, delivery
       before carrier) are kept and flagged.
   Transformation (project definitions)
     in_sales_scope     0 for canceled and unavailable orders, else 1
     in_delivery_scope  1 if delivered and a delivery date exists (96,470)
     delivery_days      DATEDIFF(DAY, purchase, customer delivery)
                        (delivery scope only)
     is_late            1 if delivered date > estimated date, compared by
                        date (delivery scope only; 6,534 = 6.77%)
     stage_dates_ok     0 if the dates are out of sequence, else 1
   --------------------------------------------------------------------- */
GO
CREATE VIEW clean.orders AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    o.order_status,
    CAST(o.order_purchase_timestamp AS DATE) AS purchase_date,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN 0 ELSE 1 END AS in_sales_scope,
    CASE WHEN o.order_status = 'delivered'
          AND o.order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END    AS in_delivery_scope,
    CASE WHEN o.order_status = 'delivered'
          AND o.order_delivered_customer_date IS NOT NULL
         THEN DATEDIFF(DAY, o.order_purchase_timestamp, o.order_delivered_customer_date)
    END AS delivery_days,
    CASE WHEN o.order_status = 'delivered'
          AND o.order_delivered_customer_date IS NOT NULL
         THEN CASE WHEN CAST(o.order_delivered_customer_date AS DATE)
                        > CAST(o.order_estimated_delivery_date AS DATE) THEN 1 ELSE 0 END
    END AS is_late,
    CASE WHEN o.order_delivered_carrier_date  < o.order_purchase_timestamp     THEN 0
         WHEN o.order_delivered_customer_date < o.order_delivered_carrier_date THEN 0
         ELSE 1 END AS stage_dates_ok
FROM olist.orders o
JOIN olist.customers c ON c.customer_id = o.customer_id;
GO

-- CHECK 6 : expected 99,441 rows; delivery scope 96,470; late 6,534
SELECT COUNT(*)                                     AS total_rows,
       SUM(in_delivery_scope)                       AS delivery_scope_orders,
       SUM(is_late)                                 AS late_orders,
       SUM(CASE WHEN in_sales_scope = 0 THEN 1 ELSE 0 END) AS outside_sales_scope
FROM clean.orders;


/* ---------------------------------------------------------------------
   Step 7. clean.order_items
   Source  : olist.order_items (112,650 rows, file 03)
   Grain   : one row per item of an order

   Cleaning
     - None required.
   Transformation
     - purchase_date and in_sales_scope are taken from clean.orders.
   Metrics : revenue = SUM(price); freight = SUM(freight_value).
   --------------------------------------------------------------------- */
GO
CREATE VIEW clean.order_items AS
SELECT i.order_id,
       i.order_item_id,
       i.product_id,
       i.seller_id,
       o.purchase_date,
       o.in_sales_scope,
       i.shipping_limit_date,
       i.price,
       i.freight_value
FROM olist.order_items i
JOIN clean.orders o ON o.order_id = i.order_id;
GO

-- CHECK 7 : the rows and the revenue must be the same in view and raw table
SELECT (SELECT COUNT(*)   FROM clean.order_items) AS rows_in_view,
       (SELECT COUNT(*)   FROM olist.order_items) AS rows_in_raw,
       (SELECT SUM(price) FROM clean.order_items) AS revenue_in_view,
       (SELECT SUM(price) FROM olist.order_items) AS revenue_in_raw;


/* ---------------------------------------------------------------------
   Step 8. clean.payments
   Source  : olist.order_payments (103,886 rows, file 04)
   Grain   : one row per order

   An order can have several payment rows, so payments are aggregated per
   order to avoid repeating the order in joins.
   Transformation
     payments            number of payment rows
     total_paid          sum of the payment values
     paid_credit_card, paid_boleto, paid_voucher, paid_debit_card,
     paid_other          sum by payment type
   --------------------------------------------------------------------- */
GO
CREATE VIEW clean.payments AS
SELECT order_id,
       COUNT(*)           AS payments,
       SUM(payment_value) AS total_paid,
       SUM(CASE WHEN payment_type = 'credit_card' THEN payment_value ELSE 0 END) AS paid_credit_card,
       SUM(CASE WHEN payment_type = 'boleto'      THEN payment_value ELSE 0 END) AS paid_boleto,
       SUM(CASE WHEN payment_type = 'voucher'     THEN payment_value ELSE 0 END) AS paid_voucher,
       SUM(CASE WHEN payment_type = 'debit_card'  THEN payment_value ELSE 0 END) AS paid_debit_card,
       SUM(CASE WHEN payment_type NOT IN ('credit_card','boleto','voucher','debit_card')
                THEN payment_value ELSE 0 END)                                   AS paid_other
FROM olist.order_payments
GROUP BY order_id;
GO

-- CHECK 8 : one row per order; total paid must equal the raw total
SELECT (SELECT COUNT(*) FROM clean.payments)                         AS rows_in_view,
       (SELECT COUNT(DISTINCT order_id) FROM olist.order_payments)   AS orders_in_raw,
       (SELECT SUM(total_paid)    FROM clean.payments)               AS total_in_view,
       (SELECT SUM(payment_value) FROM olist.order_payments)         AS total_in_raw;


/* ---------------------------------------------------------------------
   Step 9. clean.reviews
   Source  : olist.order_reviews (99,224 rows, file 05)
   Grain   : one row per order

   Cleaning
     - An order can have several reviews; the latest is kept (ROW_NUMBER
       ordered by creation date, answer time, then review_id).
   Transformation
     - has_comment  1 if the review has a written message, else 0
   --------------------------------------------------------------------- */
GO
CREATE VIEW clean.reviews AS
WITH ranked_reviews AS (
    SELECT r.order_id,
           r.review_id,
           r.review_score,
           r.review_creation_date,
           r.review_answer_timestamp,
           CASE WHEN LTRIM(RTRIM(ISNULL(r.review_comment_message, N''))) <> N''
                THEN 1 ELSE 0 END AS has_comment,
           ROW_NUMBER() OVER (
               PARTITION BY r.order_id
               ORDER BY r.review_creation_date DESC,
                        r.review_answer_timestamp DESC,
                        r.review_id DESC
           ) AS rn
    FROM olist.order_reviews r
)
SELECT order_id, review_id, review_score, review_creation_date,
       review_answer_timestamp, has_comment
FROM ranked_reviews
WHERE rn = 1;
GO

-- CHECK 9 : expected one row per order (rows = distinct orders) and the
--           average score 4.09 (file 05)
SELECT COUNT(*)                                   AS rows_in_view,
       COUNT(DISTINCT order_id)                   AS distinct_orders,
       CAST(AVG(review_score * 1.0) AS DECIMAL(4,2)) AS avg_score
FROM clean.reviews;


/* =====================================================================
   Usage rules
     - Analysis files and Power BI read only from schema clean.
     - Sales and revenue: clean.order_items (in_sales_scope = 1).
     - Delivery: clean.orders. Payments: clean.payments.
       Reviews: clean.reviews. Join them to orders by order_id.
     - Customers are counted with clean.customer (customer_unique_id).
     - Do not join clean.payments or clean.reviews to clean.order_items:
       they are per order and the items would repeat them.

   Remove everything
     DROP VIEW clean.reviews;      DROP VIEW clean.payments;
     DROP VIEW clean.order_items;  DROP VIEW clean.orders;
     DROP VIEW clean.seller;       DROP VIEW clean.customer;
     DROP VIEW clean.product;      DROP VIEW clean.category;
     DROP SCHEMA clean;
   ===================================================================== */
