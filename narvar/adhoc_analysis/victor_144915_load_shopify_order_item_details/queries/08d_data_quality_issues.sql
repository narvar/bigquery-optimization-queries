-- Query 8d: Data Quality Issues
-- Purpose: Identify NULL values, duplicates, and other data quality problems
-- These can cause unexpected join behavior or aggregation issues
-- Cost: ~1.6GB (scan temp table)

WITH data_quality_checks AS (
    SELECT 
        -- Check for NULLs in join keys (critical!)
        COUNTIF(retailer_moniker IS NULL) AS null_retailer_moniker,
        COUNTIF(shopify_domain IS NULL) AS null_shopify_domain,
        COUNTIF(order_date IS NULL) AS null_order_date,
        COUNTIF(order_item_sku IS NULL) AS null_order_item_sku,
        
        -- Check for NULLs in grouping dimensions
        COUNTIF(order_checkout_locale IS NULL) AS null_order_checkout_locale,
        COUNTIF(order_item_product_id IS NULL) AS null_order_item_product_id,
        COUNTIF(order_item_description IS NULL) AS null_order_item_description,
        COUNTIF(order_item_name IS NULL) AS null_order_item_name,
        COUNTIF(order_item_vendor IS NULL) AS null_order_item_vendor,
        COUNTIF(order_item_size IS NULL) AS null_order_item_size,
        COUNTIF(order_item_color IS NULL) AS null_order_item_color,
        COUNTIF(order_item_product_type IS NULL) AS null_order_item_product_type,
        COUNTIF(return_outcome IS NULL) AS null_return_outcome,
        
        -- Check for empty strings
        COUNTIF(TRIM(retailer_moniker) = '') AS empty_retailer_moniker,
        COUNTIF(TRIM(shopify_domain) = '') AS empty_shopify_domain,
        COUNTIF(TRIM(order_item_sku) = '') AS empty_order_item_sku,
        
        -- Total records
        COUNT(*) AS total_records
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
),

-- Check for potential duplicates in affected_items
duplicate_check AS (
    SELECT 
        retailer_moniker,
        shopify_domain,
        DATE(order_date) AS order_date,
        order_item_sku,
        return_outcome,
        COUNT(*) AS duplicate_count
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
    GROUP BY 
        retailer_moniker,
        shopify_domain,
        DATE(order_date),
        order_item_sku,
        return_outcome
    HAVING 
        COUNT(*) > 100  -- More than 100 identical combinations
),

-- Find SKUs that appear across many dates (high cardinality contributors)
high_cardinality_skus AS (
    SELECT 
        order_item_sku,
        COUNT(DISTINCT DATE(order_date)) AS dates_spanned,
        COUNT(DISTINCT retailer_moniker) AS retailers_using_it,
        COUNT(*) AS total_records,
        -- Estimate contribution to final groups
        COUNT(DISTINCT DATE(order_date)) * COUNT(DISTINCT retailer_moniker) AS estimated_groups_contributed
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
    GROUP BY 
        order_item_sku
    HAVING 
        COUNT(DISTINCT DATE(order_date)) > 30  -- SKUs appearing across >30 dates
    ORDER BY 
        estimated_groups_contributed DESC
    LIMIT 20
)

-- Output all checks
SELECT 'DATA_QUALITY_SUMMARY' AS check_type, 
       TO_JSON_STRING(data_quality_checks) AS details
FROM data_quality_checks

UNION ALL

SELECT 'DUPLICATE_COMBINATIONS' AS check_type,
       TO_JSON_STRING(STRUCT(
           retailer_moniker,
           shopify_domain,
           order_date,
           order_item_sku,
           return_outcome,
           duplicate_count
       )) AS details
FROM duplicate_check
ORDER BY duplicate_count DESC
LIMIT 20

UNION ALL

SELECT 'HIGH_CARDINALITY_SKUS' AS check_type,
       TO_JSON_STRING(STRUCT(
           order_item_sku,
           dates_spanned,
           retailers_using_it,
           total_records,
           estimated_groups_contributed
       )) AS details
FROM high_cardinality_skus;

