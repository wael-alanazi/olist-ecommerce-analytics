/* 01_customers_exploration.sql
   A first look at the customers table: its structure, its quality, and what the rest of the project keeps.
   Nothing is deleted from the table. Real customers are counted with COUNT(DISTINCT customer_unique_id),
   because customer_id changes with every order. */

USE OlistDB;
GO


/* 1. First look
   Column types and the row count come first, before any other test. */
SELECT TOP 10 * FROM olist.customers;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'olist' AND TABLE_NAME = 'customers'
ORDER BY ORDINAL_POSITION;


/* 2. What is a "customer" in this table?
   customer_id is created for every order, while customer_unique_id is the real person, so counting
   rows would overstate the customers. From here on customers are counted with
   COUNT(DISTINCT customer_unique_id). */
SELECT COUNT(*)                           AS total_rows,
       COUNT(DISTINCT customer_id)        AS distinct_customer_id,
       COUNT(DISTINCT customer_unique_id) AS distinct_real_customers
FROM olist.customers;

-- Real customers that appear in more than one row (they ordered again)
SELECT TOP 10 customer_unique_id, COUNT(*) AS rows_for_this_customer
FROM olist.customers
GROUP BY customer_unique_id
HAVING COUNT(*) > 1
ORDER BY rows_for_this_customer DESC;


/* 3. Missing values
   An empty city or state would show up as a blank group in the charts. */
SELECT
  SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END)              AS null_customer_id,
  SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END)       AS null_unique_id,
  SUM(CASE WHEN customer_zip_code_prefix IS NULL THEN 1 ELSE 0 END) AS null_zip,
  SUM(CASE WHEN customer_city IS NULL
            OR LTRIM(RTRIM(customer_city)) = '' THEN 1 ELSE 0 END)  AS empty_city,
  SUM(CASE WHEN customer_state IS NULL
            OR LTRIM(RTRIM(customer_state)) = '' THEN 1 ELSE 0 END) AS empty_state
FROM olist.customers;


/* 4. Geography (preview)
   Where are the customers? The count and the total both use DISTINCT, so the percentages add up to 100.
   State and city stay as geographic attributes of clean.customer. */
SELECT customer_state,
       COUNT(DISTINCT customer_unique_id) AS customers,
       CAST(100.0 * COUNT(DISTINCT customer_unique_id)
            / (SELECT COUNT(DISTINCT customer_unique_id) FROM olist.customers)
            AS DECIMAL(5,2)) AS pct_of_customers
FROM olist.customers
GROUP BY customer_state
ORDER BY customers DESC;

SELECT TOP 10 customer_city, customer_state,
       COUNT(DISTINCT customer_unique_id) AS customers
FROM olist.customers
GROUP BY customer_city, customer_state
ORDER BY customers DESC;

SELECT COUNT(DISTINCT customer_state) AS states,
       COUNT(DISTINCT customer_city)  AS cities
FROM olist.customers;


/* 5. Text quality
   Spelling variants would split one city into several groups. These city names are also the
   reference spelling when the seller cities are checked. */

-- Extra spaces in city names. "<>" ignores trailing spaces in
-- SQL Server, so the lengths in bytes are compared.
SELECT COUNT(*) AS cities_with_extra_spaces
FROM olist.customers
WHERE DATALENGTH(customer_city) <> DATALENGTH(LTRIM(RTRIM(customer_city)));

-- Same city written in different ways
SELECT LOWER(LTRIM(RTRIM(customer_city))) AS city_clean,
       COUNT(DISTINCT customer_city)      AS spelling_variants
FROM olist.customers
GROUP BY LOWER(LTRIM(RTRIM(customer_city)))
HAVING COUNT(DISTINCT customer_city) > 1;

-- Zip code length
SELECT LEN(customer_zip_code_prefix + 'x') - 1 AS zip_length, COUNT(*) AS n
FROM olist.customers
GROUP BY LEN(customer_zip_code_prefix + 'x') - 1
ORDER BY zip_length;

-- State code must be exactly 2 letters
SELECT customer_state, COUNT(*) AS n
FROM olist.customers
WHERE LEN(customer_state) <> 2
GROUP BY customer_state;

-- Cities with any character other than a-z and a space, or a double space
SELECT customer_city, COUNT(*) AS customers
FROM olist.customers
WHERE customer_city COLLATE Latin1_General_BIN LIKE '%[^a-z ]%'
   OR customer_city LIKE '%  %'
GROUP BY customer_city
ORDER BY customer_city;


/* 6. Join integrity
   Does customers match the orders table? An unmatched row is silently lost in any JOIN.
   NOT EXISTS is used because its meaning is clear and it is safe with NULLs. */
SELECT COUNT(*) AS customers_without_orders
FROM olist.customers c
WHERE NOT EXISTS (SELECT 1 FROM olist.orders o WHERE o.customer_id = c.customer_id);

SELECT COUNT(*) AS orders_without_customer
FROM olist.orders o
WHERE NOT EXISTS (SELECT 1 FROM olist.customers c WHERE c.customer_id = o.customer_id);


/* 7. Repeat purchase (preview)
   Do customers come back? Retention is one of the three business questions.
   The denominator must be the distinct customers, not the number of orders: dividing by orders
   would understate the rate. */

-- Orders per customer: distribution
SELECT orders_per_customer,
       COUNT(*) AS customers
FROM (
  SELECT c.customer_unique_id,
         COUNT(DISTINCT o.order_id) AS orders_per_customer
  FROM olist.customers c
  JOIN olist.orders o ON o.customer_id = c.customer_id
  GROUP BY c.customer_unique_id
) t
GROUP BY orders_per_customer
ORDER BY orders_per_customer;

-- Repeat purchase rate
WITH repeated_customers AS (
    SELECT customer_unique_id, COUNT(customer_id) AS total_orders
    FROM olist.customers
    GROUP BY customer_unique_id
    HAVING COUNT(customer_id) > 1
)
SELECT COUNT(*)                                   AS repeat_customers,
       (SELECT COUNT(DISTINCT customer_unique_id)
        FROM olist.customers)                     AS total_customers,
       CAST(COUNT(*) * 100.0 /
            (SELECT COUNT(DISTINCT customer_unique_id)
             FROM olist.customers) AS DECIMAL(10,2)) AS repeat_rate_pct
FROM repeated_customers;


/* What the rest of the project takes from this file
   - A customer is COUNT(DISTINCT customer_unique_id). A repeat customer has 2 or more orders.
   - Keep customer_id (the link to orders), customer_unique_id, customer_state and customer_city.
   - Skip the zip prefix: it is only useful for a map, and the geolocation table is not used.
   - This table needs no cleaning. */
