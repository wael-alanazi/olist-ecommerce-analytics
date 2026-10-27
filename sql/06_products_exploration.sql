/* 06_products_exploration.sql
   A first look at products (one row is one product): structure, quality, and the columns of the
   product dimension (clean.product). The category names come from product_category_translation.
   Nothing is deleted from the table. Filters are applied per question, inside the query or later in Power BI. */

USE OlistDB;
GO


/* 1. First look
   What does the table look like, and what are the data types? Weights and sizes must be numbers to
   be summed or averaged. */
SELECT TOP 10 * FROM olist.products;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'olist' AND TABLE_NAME = 'products'
ORDER BY ORDINAL_POSITION;


/* 2. Keys
   Is product_id unique? The product dimension needs one row per product; a repeated product_id
   would duplicate items in every join.
   Decision: product_id is the key of clean.product. */
SELECT COUNT(*)                   AS count_rows,
       COUNT(DISTINCT product_id) AS distinct_product_id
FROM olist.products;


/* 3. Missing values
   Which columns have NULLs, and do they come together? A product without a category cannot be
   grouped by category, and a missing weight or size affects the freight analysis.
   Decision: products without a category are kept and labelled "unknown" in clean.product ("Other"
   is reserved for grouping small categories in charts). */
SELECT
    SUM(CASE WHEN product_id                 IS NULL THEN 1 ELSE 0 END) AS null_product_id,
    SUM(CASE WHEN product_category_name      IS NULL THEN 1 ELSE 0 END) AS null_category,
    SUM(CASE WHEN product_name_lenght        IS NULL THEN 1 ELSE 0 END) AS null_name_length,
    SUM(CASE WHEN product_description_lenght IS NULL THEN 1 ELSE 0 END) AS null_description_length,
    SUM(CASE WHEN product_photos_qty         IS NULL THEN 1 ELSE 0 END) AS null_photos,
    SUM(CASE WHEN product_weight_g           IS NULL THEN 1 ELSE 0 END) AS null_weight,
    SUM(CASE WHEN product_length_cm          IS NULL THEN 1 ELSE 0 END) AS null_length,
    SUM(CASE WHEN product_height_cm          IS NULL THEN 1 ELSE 0 END) AS null_height,
    SUM(CASE WHEN product_width_cm           IS NULL THEN 1 ELSE 0 END) AS null_width
FROM olist.products;

-- Do the missing category, name length, description length and photos
-- belong to the same products?
SELECT COUNT(*) AS rows_missing_all_four
FROM olist.products
WHERE product_category_name      IS NULL
  AND product_name_lenght        IS NULL
  AND product_description_lenght IS NULL
  AND product_photos_qty         IS NULL;


/* 4. Categories
   How many categories are there, and how are the products spread? A long tail of tiny categories
   makes a bad chart.
   Decision: the dashboard shows the top N categories and groups the rest as "Other"; products
   without a category stay "unknown". */
SELECT COUNT(DISTINCT product_category_name) AS distinct_categories
FROM olist.products;

SELECT TOP 15 product_category_name, COUNT(*) AS products
FROM olist.products
GROUP BY product_category_name
ORDER BY products DESC;

-- Categories with fewer than 10 products
SELECT COUNT(*) AS categories_with_under_10_products
FROM (SELECT product_category_name
      FROM olist.products
      WHERE product_category_name IS NOT NULL
      GROUP BY product_category_name
      HAVING COUNT(*) < 10) t;



/* 5. Translation of categories
   Does every category have an English name? The names are in Portuguese, and a category without a
   translation shows as blank in a dashboard in English.
   Decision: add the missing translations by hand in clean.category (pc_gamer = pc_gamer;
   portateis_cozinha_e_preparadores_de_alimentos = portable_kitchen_food_processors) so no category
   shows blank. */
-- Translations that no product uses
SELECT c.product_category_name, COUNT(*) AS total
FROM olist.product_category_translation c
WHERE NOT EXISTS (SELECT 1
                  FROM olist.products p
                  WHERE p.product_category_name = c.product_category_name)
GROUP BY c.product_category_name;

-- Product categories that have no translation
SELECT p.product_category_name, COUNT(*) AS products
FROM olist.products p
WHERE p.product_category_name IS NOT NULL
  AND NOT EXISTS (SELECT 1
                  FROM olist.product_category_translation t
                  WHERE t.product_category_name = p.product_category_name)
GROUP BY p.product_category_name;


/* 6. Numeric columns
   What are the ranges of weight, size and photos? Zero or extreme values distort the freight and
   weight analysis.
   Decision: keep all rows. Products with weight 0 or NULL are excluded only from the weight and
   freight-per-weight analysis. The largest values are plausible, so nothing is capped. */
SELECT
    MIN(product_weight_g)  AS min_weight_g,  MAX(product_weight_g)  AS max_weight_g,
    CAST(AVG(product_weight_g * 1.0) AS DECIMAL(10,2)) AS avg_weight_g,
    MIN(product_length_cm) AS min_length,    MAX(product_length_cm) AS max_length,
    MIN(product_height_cm) AS min_height,    MAX(product_height_cm) AS max_height,
    MIN(product_width_cm)  AS min_width,     MAX(product_width_cm)  AS max_width,
    MIN(product_photos_qty) AS min_photos,   MAX(product_photos_qty) AS max_photos
FROM olist.products;

SELECT COUNT(*) AS products_with_zero_weight
FROM olist.products
WHERE product_weight_g = 0;



/* 7. Join integrity
   Do products connect to order_items, and are all products sold? Items without a product are lost
   in a JOIN, and products that were never sold only add empty rows to the dimension. */
SELECT COUNT(*) AS items_without_product
FROM olist.order_items i
WHERE NOT EXISTS (SELECT 1 FROM olist.products p WHERE p.product_id = i.product_id);

SELECT COUNT(*) AS products_never_sold
FROM olist.products p
WHERE NOT EXISTS (SELECT 1 FROM olist.order_items i WHERE i.product_id = p.product_id);



/* What the rest of the project takes from this file
   - Key = product_id (unique)
   - Products without a category are kept, labelled "unknown"
   - The category is shown in English through the translation table; the 2 untranslated categories
     get a manual English name
   - Spelling errors in the English names are corrected in clean.category (fashio_female_clothing,
     costruction_tools_garden, costruction_tools_tools, home_confort, arts_and_craftmanship); see
     08_category_translation_exploration.sql
   - Weight analysis excludes products with weight 0 or NULL
   - Charts show the top N categories and group the rest as "Other"
   - Columns kept in clean.product: product_id, category (the Portuguese name, the link to
     clean.category), photos, weight, length, height, width; the name and description lengths are
     not needed
   - clean.category has one row per category with its Portuguese and English names, including
     "unknown" */
