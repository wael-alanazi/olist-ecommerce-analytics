/* 05_order_reviews_exploration.sql
   A first look at order_reviews (one row is one review of an order): structure, quality, and how to
   link one review to one order before joining it to anything.
   Nothing is deleted from the table. Filters are applied per question, inside the query or later in Power BI. */

USE OlistDB;
GO


/* 1. First look
   What does the table look like, and what are the data types? Comment texts can contain line breaks
   that break a CSV load; if the row count is far from the CSV, the load needs a fix. */
SELECT TOP 10 * FROM olist.order_reviews;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'olist' AND TABLE_NAME = 'order_reviews'
ORDER BY ORDINAL_POSITION;

SELECT COUNT(*) AS count_rows FROM olist.order_reviews;


/* 2. Keys and reviews per order
   Is review_id unique, and does each order have one review? An order with 2 reviews joined to orders
   doubles that order in every count and average. This section sets the rule that makes the link one
   review per order.
   Decision: key = (review_id, order_id). To get one review per order, keep the latest by
   review_creation_date (ties: the latest review_answer_timestamp). */
SELECT COUNT(*)                  AS count_rows,
       COUNT(DISTINCT review_id) AS distinct_review_id,
       COUNT(DISTINCT order_id)  AS distinct_order_id
FROM olist.order_reviews;

-- Is the pair (review_id, order_id) unique? No rows returned = unique
SELECT review_id, order_id, COUNT(*) AS n
FROM olist.order_reviews
GROUP BY review_id, order_id
HAVING COUNT(*) > 1;

-- How many reviews does each order have?
SELECT reviews_in_order,
       COUNT(*) AS orders,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_orders
FROM (SELECT order_id, COUNT(*) AS reviews_in_order
      FROM olist.order_reviews
      GROUP BY order_id) t
GROUP BY reviews_in_order
ORDER BY reviews_in_order;

-- Review_ids that appear on more than one row (look at a few)
SELECT TOP 10 review_id, COUNT(*) AS n, COUNT(DISTINCT order_id) AS orders
FROM olist.order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY n DESC;


/* 3. Missing values
   Which columns are empty? Titles and comments are optional; the score and the order link are not.
   Empty text can be stored as NULL or as '', so both are counted.
   Decision: title and message are optional and kept as they are; an empty text counts as
   "no comment". */
SELECT
    SUM(CASE WHEN review_id               IS NULL THEN 1 ELSE 0 END) AS null_review_id,
    SUM(CASE WHEN order_id                IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN review_score            IS NULL THEN 1 ELSE 0 END) AS null_score,
    SUM(CASE WHEN review_comment_title    IS NULL THEN 1 ELSE 0 END) AS null_title,
    SUM(CASE WHEN review_comment_message  IS NULL THEN 1 ELSE 0 END) AS null_message,
    SUM(CASE WHEN review_creation_date    IS NULL THEN 1 ELSE 0 END) AS null_creation,
    SUM(CASE WHEN review_answer_timestamp IS NULL THEN 1 ELSE 0 END) AS null_answer
FROM olist.order_reviews;

SELECT
    SUM(CASE WHEN LTRIM(RTRIM(review_comment_title))   = '' THEN 1 ELSE 0 END) AS empty_title,
    SUM(CASE WHEN LTRIM(RTRIM(review_comment_message)) = '' THEN 1 ELSE 0 END) AS empty_message
FROM olist.order_reviews;


/* 4. Review score
   Which scores exist and how are they spread? The score should be a whole number from 1 to 5;
   anything else would distort every average.
   Decision: no cleaning is needed. The dashboard shows the distribution next to the average,
   because an average alone hides how the scores are spread. */
SELECT review_score,
       COUNT(*) AS reviews,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_reviews
FROM olist.order_reviews
GROUP BY review_score
ORDER BY review_score;

SELECT MIN(review_score)                          AS min_score,
       MAX(review_score)                          AS max_score,
       CAST(AVG(review_score * 1.0) AS DECIMAL(4,2)) AS avg_score
FROM olist.order_reviews;


/* 5. Comments (preview)
   How many reviews carry a written comment? This decides whether text analysis is worth doing. */
SELECT
    COUNT(*) AS reviews,
    SUM(CASE WHEN review_comment_message IS NOT NULL
              AND LTRIM(RTRIM(review_comment_message)) <> '' THEN 1 ELSE 0 END) AS with_message,
    SUM(CASE WHEN review_comment_title IS NOT NULL
              AND LTRIM(RTRIM(review_comment_title)) <> '' THEN 1 ELSE 0 END)   AS with_title
FROM olist.order_reviews;

-- Share of reviews with a message, by score
SELECT review_score,
       COUNT(*) AS reviews,
       SUM(CASE WHEN review_comment_message IS NOT NULL
                 AND LTRIM(RTRIM(review_comment_message)) <> '' THEN 1 ELSE 0 END) AS with_message,
       CAST(SUM(CASE WHEN review_comment_message IS NOT NULL
                      AND LTRIM(RTRIM(review_comment_message)) <> '' THEN 1 ELSE 0 END)
            * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS pct_with_message
FROM olist.order_reviews
GROUP BY review_score
ORDER BY review_score;


/* 6. Dates
   What period do the reviews cover, and is the date order logical? A review answered before it was
   created is a data error, and the review period should match the order period.
   Decision: reviews dated before the purchase day are kept (the score analysis does not use their
   dates); date-based review metrics should exclude them. */
SELECT MIN(review_creation_date)    AS first_creation,
       MAX(review_creation_date)    AS last_creation,
       MIN(review_answer_timestamp) AS first_answer,
       MAX(review_answer_timestamp) AS last_answer
FROM olist.order_reviews;

SELECT COUNT(*) AS answered_before_created
FROM olist.order_reviews
WHERE review_answer_timestamp < review_creation_date;

-- Reviews created on a day before the purchase day
SELECT COUNT(*) AS review_before_purchase
FROM olist.order_reviews r
JOIN olist.orders o ON o.order_id = r.order_id
WHERE CAST(r.review_creation_date AS DATE) < CAST(o.order_purchase_timestamp AS DATE);


/* 7. Join integrity
   Do reviews connect to orders, and do orders have reviews? Orders without a review are normal (not
   every customer reviews), but the size of the gap decides how to read the satisfaction results.
   Decision: satisfaction metrics cover only orders that have a review. */
SELECT COUNT(*) AS reviews_without_order
FROM olist.order_reviews r
WHERE NOT EXISTS (SELECT 1 FROM olist.orders o WHERE o.order_id = r.order_id);

SELECT o.order_status, COUNT(*) AS orders_without_review
FROM olist.orders o
WHERE NOT EXISTS (SELECT 1 FROM olist.order_reviews r WHERE r.order_id = o.order_id)
GROUP BY o.order_status
ORDER BY orders_without_review DESC;


/* What the rest of the project takes from this file
   - Key = (review_id, order_id); review_id alone is not unique
   - One review per order: the latest by review_creation_date (ties: latest review_answer_timestamp),
     before any join to orders
   - Score 1 to 5, valid as it is; report the distribution together with the average
   - Empty or NULL message = no comment
   - Satisfaction metrics cover orders that have a review; the delivery vs satisfaction analysis uses
     delivered orders in the delivery scope (02_orders) that have a review */
