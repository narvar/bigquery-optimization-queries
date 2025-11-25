-- Query 6: Compare Temp Tables Across Execution Dates
-- Purpose: Understand what's different between Nov 19/20/24 temp tables
-- We know Nov 19 and Nov 20 exist and failed, Nov 24 exists and succeeded
-- Cost: ~5GB (scan 3 temp tables)

WITH temp_table_comparison AS (
    SELECT 
        '2025-11-19' AS execution_date,
        COUNT(*) AS total_rows,
        COUNT(DISTINCT retailer_moniker) AS retailers,
        COUNT(DISTINCT shopify_domain) AS domains,
        COUNT(DISTINCT DATE(order_date)) AS distinct_dates,
        COUNT(DISTINCT order_item_sku) AS skus,
        MIN(DATE(order_date)) AS min_order_date,
        MAX(DATE(order_date)) AS max_order_date,
        -- Check for duplicates in affected_items join keys
        COUNT(DISTINCT CONCAT(
            COALESCE(retailer_moniker, ''), '|',
            COALESCE(shopify_domain, ''), '|',
            COALESCE(CAST(DATE(order_date) AS STRING), ''), '|',
            COALESCE(order_item_sku, '')
        )) AS distinct_join_keys
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-19`
    
    UNION ALL
    
    SELECT 
        '2025-11-20',
        COUNT(*),
        COUNT(DISTINCT retailer_moniker),
        COUNT(DISTINCT shopify_domain),
        COUNT(DISTINCT DATE(order_date)),
        COUNT(DISTINCT order_item_sku),
        MIN(DATE(order_date)),
        MAX(DATE(order_date)),
        COUNT(DISTINCT CONCAT(
            COALESCE(retailer_moniker, ''), '|',
            COALESCE(shopify_domain, ''), '|',
            COALESCE(CAST(DATE(order_date) AS STRING), ''), '|',
            COALESCE(order_item_sku, '')
        ))
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20`
    
    UNION ALL
    
    SELECT 
        '2025-11-24',
        COUNT(*),
        COUNT(DISTINCT retailer_moniker),
        COUNT(DISTINCT shopify_domain),
        COUNT(DISTINCT DATE(order_date)),
        COUNT(DISTINCT order_item_sku),
        MIN(DATE(order_date)),
        MAX(DATE(order_date)),
        COUNT(DISTINCT CONCAT(
            COALESCE(retailer_moniker, ''), '|',
            COALESCE(shopify_domain, ''), '|',
            COALESCE(CAST(DATE(order_date) AS STRING), ''), '|',
            COALESCE(order_item_sku, '')
        ))
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-24`
)
SELECT 
    *,
    -- Calculate duplication ratio
    ROUND(100.0 * distinct_join_keys / NULLIF(total_rows, 0), 2) AS join_key_uniqueness_pct,
    -- Date range span
    DATE_DIFF(max_order_date, min_order_date, DAY) AS date_range_days
FROM 
    temp_table_comparison
ORDER BY 
    execution_date;

