/* 08_category_translation_exploration.sql
   Checking that the category list is clean and complete, and deciding how to fix the problems.
   Nothing is deleted from the raw table. Fixes are made in the dimension (clean.category). */

USE OlistDB;
GO


/* 1. First look
   What does the table look like, and what are the data types? The column names and types are checked
   before any other test. */
SELECT TOP 10 * FROM olist.product_category_translation;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'olist' AND TABLE_NAME = 'product_category_translation'
ORDER BY ORDINAL_POSITION;


/* 2. Keys
   Does each category appear once, in both languages? A category that appears twice would repeat its
   products in every join, and two Portuguese names with the same English name would split one
   category in two.
   Decision: the Portuguese name is the key of clean.category and the link from clean.product. */
SELECT COUNT(*)                                     AS row_count,
       COUNT(DISTINCT product_category_name)         AS distinct_portuguese,
       COUNT(DISTINCT product_category_name_english) AS distinct_english
FROM olist.product_category_translation;


/* 3. Missing values
   Are there NULL or empty names? An empty name shows as a blank bar in a chart. */
SELECT
    SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END)                       AS null_portuguese,
    SUM(CASE WHEN LTRIM(RTRIM(product_category_name)) = '' THEN 1 ELSE 0 END)            AS empty_portuguese,
    SUM(CASE WHEN product_category_name_english IS NULL THEN 1 ELSE 0 END)               AS null_english,
    SUM(CASE WHEN LTRIM(RTRIM(product_category_name_english)) = '' THEN 1 ELSE 0 END)    AS empty_english
FROM olist.product_category_translation;


/* 4. Text quality
   Are the names written in a clean way? A name with a hidden space does not match the products
   table, and capital letters or symbols show that a name was typed differently from the others. */
-- Spaces at the start or end (DATALENGTH counts the spaces at the end too)
SELECT COUNT(*) AS names_with_extra_spaces
FROM olist.product_category_translation
WHERE DATALENGTH(product_category_name)         <> DATALENGTH(LTRIM(RTRIM(product_category_name)))
   OR DATALENGTH(product_category_name_english) <> DATALENGTH(LTRIM(RTRIM(product_category_name_english)));

-- Names with anything other than a-z, 0-9 and "_" (capital letters, spaces,
-- accents, symbols)
SELECT product_category_name, product_category_name_english
FROM olist.product_category_translation
WHERE product_category_name         COLLATE Latin1_General_BIN LIKE '%[^a-z0-9_]%'
   OR product_category_name_english COLLATE Latin1_General_BIN LIKE '%[^a-z0-9_]%';


/* 5. English names
   Are the English names spelled correctly? The English name is the one shown in the dashboard, so a
   spelling error would be visible in a chart.
   Decision: the misspelled names are corrected in clean.category (the raw table is not changed):
   fashio_female_clothing -> fashion_female_clothing, costruction_tools_garden ->
   construction_tools_garden, costruction_tools_tools -> construction_tools_tools,
   home_confort -> home_comfort, arts_and_craftmanship -> arts_and_craftsmanship. */
-- The whole list, to read the names one by one
SELECT product_category_name, product_category_name_english
FROM olist.product_category_translation
ORDER BY product_category_name_english;

-- The 5 names known to have errors
SELECT product_category_name, product_category_name_english
FROM olist.product_category_translation
WHERE product_category_name_english IN ('fashio_female_clothing', 'costruction_tools_garden',
                                        'costruction_tools_tools', 'home_confort',
                                        'arts_and_craftmanship');


/* 6. Join integrity
   Does every product category have an English name, and is every translated category used by a
   product? A category without a translation shows as blank in a dashboard in English; a translation
   that no product uses only adds an empty row.
   Decision: add the missing translations by hand in clean.category (pc_gamer = pc_gamer;
   portateis_cozinha_e_preparadores_de_alimentos = portable_kitchen_food_processors). Products
   without a category use the category "unknown" (a row "unknown" is added to clean.category). */
-- Translations that no product uses
SELECT t.product_category_name
FROM olist.product_category_translation t
WHERE NOT EXISTS (SELECT 1 FROM olist.products p
                  WHERE p.product_category_name = t.product_category_name);

-- Product categories that have no translation
SELECT p.product_category_name, COUNT(*) AS products
FROM olist.products p
WHERE p.product_category_name IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM olist.product_category_translation t
                  WHERE t.product_category_name = p.product_category_name)
GROUP BY p.product_category_name;


/* What the rest of the project takes from this file
   - Key = product_category_name (Portuguese); it links clean.product to clean.category.
   - clean.category has one row per category with its Portuguese and English names.
   - The categories without a translation get an English name by hand.
   - The English names with spelling errors are corrected in the dimension; the raw table is not
     changed. security_and_services is kept as it is.
   - Products without a category use the category "unknown" (a row "unknown" is added to
     clean.category). */
