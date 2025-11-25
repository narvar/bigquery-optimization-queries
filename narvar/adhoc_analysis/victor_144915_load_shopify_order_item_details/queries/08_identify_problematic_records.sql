-- Query 8: Identify Problematic Records in Temp Table
-- Purpose: Find records that cause aggregation explosion
-- These are records that create excessive grouping combinations

-- Part 1: Date distribution - which dates have most data?
WITH date_stats AS (
    SELECT 
        DATE(order_date) AS order_date,
        COUNT(*) AS row_count,
        COUNT(DISTINCT retailer_moniker) AS distinct_retailers,
        COUNT(DISTINCT shopify_domain) AS distinct_domains,
        COUNT(DISTINCT order_item_sku) AS distinct_skus,
        COUNT(DISTINCT order_item_product_id) AS distinct_products,
        COUNT(DISTINCT CONCAT(
            COALESCE(retailer_moniker, ''), '|',
            COALESCE(shopify_domain, ''), '|',
            COALESCE(order_item_sku, '')
        )) AS distinct_retailer_sku_combos,
        -- Check for nulls in join keys
        COUNTIF(retailer_moniker IS NULL) AS null_retailer,
        COUNTIF(shopify_domain IS NULL) AS null_domain,
        COUNTIF(order_item_sku IS NULL) AS null_sku,
        COUNTIF(order_date IS NULL) AS null_date
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
    GROUP BY 
        DATE(order_date)
),

-- Part 2: Retailer distribution - which retailers have most data across dates?
retailer_stats AS (
    SELECT 
        retailer_moniker,
        shopify_domain,
        COUNT(*) AS row_count,
        COUNT(DISTINCT DATE(order_date)) AS distinct_dates,
        COUNT(DISTINCT order_item_sku) AS distinct_skus,
        MIN(DATE(order_date)) AS min_date,
        MAX(DATE(order_date)) AS max_date,
        DATE_DIFF(MAX(DATE(order_date)), MIN(DATE(order_date)), DAY) AS date_span_days
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
    GROUP BY 
        retailer_moniker,
        shopify_domain
),

-- Part 3: Identify records from OLD dates (the problematic ones)
old_date_records AS (
    SELECT 
        DATE(order_date) AS order_date,
        retailer_moniker,
        shopify_domain,
        COUNT(*) AS record_count,
        COUNT(DISTINCT order_item_sku) AS sku_count,
        -- Sample some records
        ARRAY_AGG(order_number LIMIT 5) AS sample_order_numbers,
        ARRAY_AGG(order_item_sku LIMIT 5) AS sample_skus
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
    WHERE 
        -- Focus on dates that should NOT be in the temp table
        DATE(order_date) < DATE('2025-11-17')  -- More than 3 days before execution date
    GROUP BY 
        DATE(order_date),
        retailer_moniker,
        shopify_domain
),

-- Part 4: Aggregation cardinality estimation
affected_items_preview AS (
    SELECT 
        COUNT(*) AS total_records,
        COUNT(DISTINCT retailer_moniker) AS distinct_retailers,
        COUNT(DISTINCT shopify_domain) AS distinct_domains,
        COUNT(DISTINCT DATE(order_date)) AS distinct_dates,
        COUNT(DISTINCT order_item_sku) AS distinct_skus,
        COUNT(DISTINCT order_item_product_id) AS distinct_products,
        COUNT(DISTINCT order_checkout_locale) AS distinct_locales,
        COUNT(DISTINCT return_outcome) AS distinct_outcomes,
        -- Estimate final grouping cardinality (conservative)
        COUNT(DISTINCT CONCAT(
            COALESCE(retailer_moniker, ''), '|',
            COALESCE(shopify_domain, ''), '|',
            COALESCE(CAST(DATE(order_date) AS STRING), ''), '|',
            COALESCE(order_item_sku, '')
        )) AS estimated_min_groups
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
)

-- Output the analysis
SELECT 'DATE_DISTRIBUTION' AS analysis_type, 
       CAST(NULL AS STRING) AS key1, 
       CAST(NULL AS STRING) AS key2,
       CAST(NULL AS INT64) AS metric1,
       CAST(NULL AS INT64) AS metric2,
       CAST(NULL AS INT64) AS metric3,
       TO_JSON_STRING(date_stats) AS details
FROM date_stats
UNION ALL
SELECT 'RETAILER_DISTRIBUTION', 
       retailer_moniker, 
       shopify_domain,
       row_count,
       distinct_dates,
       distinct_skus,
       TO_JSON_STRING(STRUCT(min_date, max_date, date_span_days)) AS details
FROM retailer_stats
ORDER BY row_count DESC
LIMIT 20
UNION ALL
SELECT 'OLD_DATE_RECORDS', 
       CAST(order_date AS STRING), 
       retailer_moniker,
       record_count,
       sku_count,
       CAST(NULL AS INT64),
       TO_JSON_STRING(STRUCT(sample_order_numbers, sample_skus)) AS details
FROM old_date_records
ORDER BY order_date DESC
LIMIT 50
UNION ALL
SELECT 'CARDINALITY_ESTIMATE',
       CAST(NULL AS STRING),
       CAST(NULL AS STRING),
       total_records,
       distinct_dates,
       estimated_min_groups,
       TO_JSON_STRING(affected_items_preview) AS details
FROM affected_items_preview;

