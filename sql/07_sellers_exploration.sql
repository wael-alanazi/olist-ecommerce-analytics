/* 07_sellers_exploration.sql
   A first look at sellers (one row is one seller): structure, quality, and the columns of the seller
   dimension (clean.seller).
   Nothing is deleted from the table. Filters are applied per question, inside the query or later in Power BI. */

USE OlistDB;
GO


/* 1. First look
   Types and the row count are checked before any other test. */
SELECT TOP 10 * FROM olist.sellers;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'olist' AND TABLE_NAME = 'sellers'
ORDER BY ORDINAL_POSITION;


/* 2. Keys
   Is seller_id unique? The seller dimension needs one row per seller; a repeated seller_id would
   duplicate items in every join.
   Decision: seller_id is the key of clean.seller. */
SELECT COUNT(*)                   AS count_rows,
       COUNT(DISTINCT seller_id)  AS distinct_seller_id
FROM olist.sellers;


/* 3. Missing values
   Which columns have NULLs or empty values? An empty city or state shows as a blank group in charts. */
SELECT
    SUM(CASE WHEN seller_zip_code_prefix IS NULL THEN 1 ELSE 0 END)               AS null_zip,
    SUM(CASE WHEN LTRIM(RTRIM(seller_zip_code_prefix)) = '' THEN 1 ELSE 0 END)    AS empty_zip,
    SUM(CASE WHEN seller_city IS NULL THEN 1 ELSE 0 END)                          AS null_city,
    SUM(CASE WHEN LTRIM(RTRIM(seller_city)) = '' THEN 1 ELSE 0 END)               AS empty_city,
    SUM(CASE WHEN seller_state IS NULL THEN 1 ELSE 0 END)                         AS null_state,
    SUM(CASE WHEN LTRIM(RTRIM(seller_state)) = '' THEN 1 ELSE 0 END)              AS empty_state
FROM olist.sellers;


/* 4. Geography (preview)
   Where are the sellers, and how concentrated are they? Compare with the geography of the customers
   (01_customers).
   Decision: geography charts use the state and show the top N states. */
SELECT COUNT(DISTINCT seller_state)           AS states,
       COUNT(DISTINCT seller_city)            AS cities_raw,
       COUNT(DISTINCT seller_zip_code_prefix) AS zip_prefixes
FROM olist.sellers;

-- Seller states that have no customer
SELECT s.seller_state
FROM (SELECT DISTINCT seller_state FROM olist.sellers) s
WHERE NOT EXISTS (SELECT 1
                  FROM olist.customers c
                  WHERE c.customer_state = s.seller_state);

-- Customer states that have no seller
SELECT c.customer_state
FROM (SELECT DISTINCT customer_state FROM olist.customers) c
WHERE NOT EXISTS (SELECT 1
                  FROM olist.sellers s
                  WHERE s.seller_state = c.customer_state);

-- Sellers by state: top 10 and share of all sellers
WITH st AS (
    SELECT seller_state, COUNT(*) AS sellers
    FROM olist.sellers
    GROUP BY seller_state
)
SELECT TOP 10 seller_state, sellers,
       CAST(sellers * 100.0 / (SELECT SUM(sellers) FROM st) AS DECIMAL(5,2)) AS pct_of_sellers
FROM st
ORDER BY sellers DESC;


/* 5. Text quality
   Are city and state values clean? Spelling variants split one city into several groups.
   Decision:
   - the state is clean and is the main level for geography charts
   - the city is typed by hand (typos, e-mails, zip codes, state names), so clean.seller does not
     keep it and the sellers are analyzed by state
   - the city names in customers are clean (file 01), so they would be the reference spelling,
     e.g. santa barbara d'oeste (sellers also have d´oeste and d oeste) */
-- Leading or trailing spaces. "<>" ignores trailing spaces in SQL Server,
-- so the lengths in bytes are compared instead.
SELECT COUNT(*) AS values_with_extra_spaces
FROM olist.sellers
WHERE DATALENGTH(seller_city)  <> DATALENGTH(LTRIM(RTRIM(seller_city)))
   OR DATALENGTH(seller_state) <> DATALENGTH(LTRIM(RTRIM(seller_state)));

-- Cities with any character other than a-z and a space (digits, accents,
-- "/", ",", "-", "@", apostrophes), or with a double space
SELECT seller_city, COUNT(*) AS sellers
FROM olist.sellers
WHERE seller_city COLLATE Latin1_General_BIN LIKE '%[^a-z ]%'
   OR seller_city LIKE '%  %'
GROUP BY seller_city
ORDER BY seller_city;

-- Number of sellers affected by these cases
SELECT COUNT(*) AS sellers_with_problem_city
FROM olist.sellers
WHERE seller_city COLLATE Latin1_General_BIN LIKE '%[^a-z ]%'
   OR seller_city LIKE '%  %';


/* 6. Join integrity
   Do sellers connect to order_items, and do all sellers sell? Items without a seller are lost in a
   JOIN, and sellers with no sales only add empty rows to the seller dimension. */
SELECT COUNT(*) AS sellers_without_items
FROM olist.sellers s
WHERE NOT EXISTS (SELECT 1 FROM olist.order_items i WHERE i.seller_id = s.seller_id);

SELECT COUNT(*) AS items_without_seller
FROM olist.order_items i
WHERE NOT EXISTS (SELECT 1 FROM olist.sellers s WHERE s.seller_id = i.seller_id);


/* 7. Seller activity (preview)
   How are orders and items spread across sellers? If a few sellers make most of the sales, charts
   by seller need a top N, and averages can mislead.
   Scope: sales scope (all orders except canceled and unavailable).
   Decision: seller charts show a top N (top 10), not all sellers, and per-seller averages are not
   used alone. All sellers stay in clean.seller. */
-- Top 10 sellers by revenue and their share of total revenue
WITH seller_sales AS (
    SELECT i.seller_id,
           COUNT(DISTINCT i.order_id) AS orders,
           SUM(i.price)               AS revenue
    FROM olist.order_items i
    JOIN olist.orders o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY i.seller_id
)
SELECT TOP 10 seller_id, orders, revenue,
       CAST(revenue * 100.0 / (SELECT SUM(revenue) FROM seller_sales) AS DECIMAL(5,2)) AS pct_of_revenue
FROM seller_sales
ORDER BY revenue DESC;

-- Share of revenue made by the top 10% of sellers
WITH seller_sales AS (
    SELECT i.seller_id, SUM(i.price) AS revenue
    FROM olist.order_items i
    JOIN olist.orders o ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY i.seller_id
)
SELECT (SELECT COUNT(*) FROM seller_sales) AS sellers_with_sales,
       CAST(100.0 * (SELECT SUM(revenue)
                     FROM (SELECT TOP 10 PERCENT revenue
                           FROM seller_sales
                           ORDER BY revenue DESC) t)
            / (SELECT SUM(revenue) FROM seller_sales) AS DECIMAL(5,2)) AS pct_revenue_top_10pct_sellers;


/* What the rest of the project takes from this file
   - Key = seller_id (unique, never NULL)
   - No seller is filtered out
   - Geography is by state; some customer states have no seller
   - The city is not kept in clean.seller (typed by hand, inconsistent)
   - Columns kept in clean.seller: seller_id, state, and a region derived from the state
     (the zip prefix is not kept: the geolocation table is not used)
   - Sellers are concentrated, so seller and state charts show a top N */
