-- Query 2: Join Key Distribution Analysis
-- Purpose: Check for potential cartesian join or join explosion
-- The failing query joins on: retailer_moniker, shopify_domain, order_date, order_item_sku
-- Cost: Will scan the temp table (~1.6GB) and sample order_item_details

-- Part A: Check how many distinct join key combinations exist in temp table
WITH temp_table_keys AS (
    SELECT 
        COUNT(*) AS total_rows,
        COUNT(DISTINCT retailer_moniker) AS distinct_retailers,
        COUNT(DISTINCT shopify_domain) AS distinct_domains,
        COUNT(DISTINCT DATE(order_date)) AS distinct_dates,
        COUNT(DISTINCT order_item_sku) AS distinct_skus,
        COUNT(DISTINCT CONCAT(
            COALESCE(retailer_moniker, 'NULL'), '|',
            COALESCE(shopify_domain, 'NULL'), '|',
            COALESCE(CAST(DATE(order_date) AS STRING), 'NULL'), '|',
            COALESCE(order_item_sku, 'NULL')
        )) AS distinct_join_keys,
        -- Check for nulls in join keys
        COUNTIF(retailer_moniker IS NULL) AS null_retailer,
        COUNTIF(shopify_domain IS NULL) AS null_domain,
        COUNTIF(order_date IS NULL) AS null_date,
        COUNTIF(order_item_sku IS NULL) AS null_sku
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20`
),

-- Part B: Check how many rows in order_item_details could match these keys
-- Sampling last 7 days to estimate
order_item_sample AS (
    SELECT 
        COUNT(*) AS sample_rows,
        COUNT(DISTINCT retailer_moniker) AS sample_retailers,
        COUNT(DISTINCT shopify_domain) AS sample_domains,
        COUNT(DISTINCT DATE(order_date)) AS sample_dates,
        COUNT(DISTINCT order_item_sku) AS sample_skus,
        COUNT(DISTINCT CONCAT(
            COALESCE(retailer_moniker, 'NULL'), '|',
            COALESCE(shopify_domain, 'NULL'), '|',
            COALESCE(CAST(DATE(order_date) AS STRING), 'NULL'), '|',
            COALESCE(order_item_sku, 'NULL')
        )) AS sample_join_keys
    FROM 
        `narvar-data-lake.return_insights_base.order_item_details`
    WHERE 
        DATE(order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
)

SELECT 
    'temp_table' AS source,
    t.*
FROM temp_table_keys t

UNION ALL

SELECT 
    'order_item_details_7day_sample' AS source,
    s.sample_rows AS total_rows,
    s.sample_retailers AS distinct_retailers,
    s.sample_domains AS distinct_domains,
    s.sample_dates AS distinct_dates,
    s.sample_skus AS distinct_skus,
    s.sample_join_keys AS distinct_join_keys,
    0 AS null_retailer,
    0 AS null_domain,
    0 AS null_date,
    0 AS null_sku
FROM order_item_sample s;

