/* 00_load_data.sql
   Creates the 9 raw tables in schema olist and loads the CSV files into them. Run this file first.
   It needs SQL Server 2017 or later, and the database OlistDB and the schema olist must already exist.

   Before running: copy the 9 CSV files to C:\OlistData\ (the SQL Server service must be able to read
   the folder; Desktop and OneDrive folders often cannot be read). To use another folder, replace
   C:\OlistData\ in this file (Ctrl+H in SSMS).

   How the tables are built:
   - Column names are the ones in the CSV files.
   - No keys or constraints yet: files 01 to 08 test them.
   - Zip code prefixes are text, so leading zeros are kept.
   - Empty fields are loaded as NULL.
   - Running the file again drops and rebuilds the raw tables.

   BULK INSERT options:
     FORMAT = 'CSV'       fields may be quoted or not
     FIRSTROW = 2         the first row holds the column names
     CODEPAGE = '65001'   UTF-8
     ROWTERMINATOR        0x0a for most files; 0x0d0a for order_reviews and
                          product_category_translation
     KEEPNULLS            empty fields become NULL */

USE OlistDB;
GO


-- customers
DROP TABLE IF EXISTS olist.customers;
CREATE TABLE olist.customers (
    customer_id              VARCHAR(50)   NOT NULL,
    customer_unique_id       VARCHAR(50)   NOT NULL,
    customer_zip_code_prefix VARCHAR(5)    NOT NULL,
    customer_city            NVARCHAR(100) NULL,
    customer_state           VARCHAR(2)    NULL
);
BULK INSERT olist.customers
FROM 'C:\OlistData\olist_customers_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', KEEPNULLS);


-- geolocation
DROP TABLE IF EXISTS olist.geolocation;
CREATE TABLE olist.geolocation (
    geolocation_zip_code_prefix VARCHAR(5)    NOT NULL,
    geolocation_lat             FLOAT         NULL,
    geolocation_lng             FLOAT         NULL,
    geolocation_city            NVARCHAR(100) NULL,
    geolocation_state           VARCHAR(2)    NULL
);
BULK INSERT olist.geolocation
FROM 'C:\OlistData\olist_geolocation_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', KEEPNULLS);


-- orders
DROP TABLE IF EXISTS olist.orders;
CREATE TABLE olist.orders (
    order_id                      VARCHAR(50)  NOT NULL,
    customer_id                   VARCHAR(50)  NOT NULL,
    order_status                  VARCHAR(20)  NULL,
    order_purchase_timestamp      DATETIME2(0) NULL,
    order_approved_at             DATETIME2(0) NULL,
    order_delivered_carrier_date  DATETIME2(0) NULL,
    order_delivered_customer_date DATETIME2(0) NULL,
    order_estimated_delivery_date DATETIME2(0) NULL
);
BULK INSERT olist.orders
FROM 'C:\OlistData\olist_orders_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', KEEPNULLS);


-- order_items
DROP TABLE IF EXISTS olist.order_items;
CREATE TABLE olist.order_items (
    order_id            VARCHAR(50)   NOT NULL,
    order_item_id       INT           NOT NULL,
    product_id          VARCHAR(50)   NOT NULL,
    seller_id           VARCHAR(50)   NOT NULL,
    shipping_limit_date DATETIME2(0)  NULL,
    price               DECIMAL(10,2) NULL,
    freight_value       DECIMAL(10,2) NULL
);
BULK INSERT olist.order_items
FROM 'C:\OlistData\olist_order_items_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', KEEPNULLS);


-- order_payments
DROP TABLE IF EXISTS olist.order_payments;
CREATE TABLE olist.order_payments (
    order_id             VARCHAR(50)   NOT NULL,
    payment_sequential   INT           NULL,
    payment_type         VARCHAR(30)   NULL,
    payment_installments INT           NULL,
    payment_value        DECIMAL(10,2) NULL
);
BULK INSERT olist.order_payments
FROM 'C:\OlistData\olist_order_payments_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', KEEPNULLS);


-- order_reviews (line breaks inside some comments are kept; rows end with 0x0d0a)
DROP TABLE IF EXISTS olist.order_reviews;
CREATE TABLE olist.order_reviews (
    review_id               VARCHAR(50)    NOT NULL,
    order_id                VARCHAR(50)    NOT NULL,
    review_score            INT            NULL,
    review_comment_title    NVARCHAR(200)  NULL,
    review_comment_message  NVARCHAR(1000) NULL,
    review_creation_date    DATETIME2(0)   NULL,
    review_answer_timestamp DATETIME2(0)   NULL
);
BULK INSERT olist.order_reviews
FROM 'C:\OlistData\olist_order_reviews_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0d0a', KEEPNULLS);


-- products
DROP TABLE IF EXISTS olist.products;
CREATE TABLE olist.products (
    product_id                 VARCHAR(50)  NOT NULL,
    product_category_name      VARCHAR(100) NULL,
    product_name_lenght        INT          NULL,
    product_description_lenght INT          NULL,
    product_photos_qty         INT          NULL,
    product_weight_g           INT          NULL,
    product_length_cm          INT          NULL,
    product_height_cm          INT          NULL,
    product_width_cm           INT          NULL
);
BULK INSERT olist.products
FROM 'C:\OlistData\olist_products_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', KEEPNULLS);


-- sellers
DROP TABLE IF EXISTS olist.sellers;
CREATE TABLE olist.sellers (
    seller_id              VARCHAR(50)   NOT NULL,
    seller_zip_code_prefix VARCHAR(5)    NOT NULL,
    seller_city            NVARCHAR(100) NULL,
    seller_state           VARCHAR(2)    NULL
);
BULK INSERT olist.sellers
FROM 'C:\OlistData\olist_sellers_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', KEEPNULLS);


-- product_category_translation (rows end with 0x0d0a)
DROP TABLE IF EXISTS olist.product_category_translation;
CREATE TABLE olist.product_category_translation (
    product_category_name         VARCHAR(100) NOT NULL,
    product_category_name_english VARCHAR(100) NULL
);
BULK INSERT olist.product_category_translation
FROM 'C:\OlistData\product_category_name_translation.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0d0a', KEEPNULLS);
GO


/* ---------------------------------------------------------------------
   Validation: every row must show OK.
   --------------------------------------------------------------------- */

SELECT t.table_name, t.rows_loaded, t.rows_expected,
       CASE WHEN t.rows_loaded = t.rows_expected THEN 'OK' ELSE 'CHECK' END AS result
FROM (
    SELECT 'customers' AS table_name, COUNT(*) AS rows_loaded, 99441 AS rows_expected FROM olist.customers
    UNION ALL SELECT 'geolocation',                  COUNT(*), 1000163 FROM olist.geolocation
    UNION ALL SELECT 'orders',                       COUNT(*),   99441 FROM olist.orders
    UNION ALL SELECT 'order_items',                  COUNT(*),  112650 FROM olist.order_items
    UNION ALL SELECT 'order_payments',               COUNT(*),  103886 FROM olist.order_payments
    UNION ALL SELECT 'order_reviews',                COUNT(*),   99224 FROM olist.order_reviews
    UNION ALL SELECT 'products',                     COUNT(*),   32951 FROM olist.products
    UNION ALL SELECT 'sellers',                      COUNT(*),    3095 FROM olist.sellers
    UNION ALL SELECT 'product_category_translation', COUNT(*),      71 FROM olist.product_category_translation
) AS t;
