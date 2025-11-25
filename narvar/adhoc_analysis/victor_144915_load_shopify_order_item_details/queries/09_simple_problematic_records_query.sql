-- Query 9: Simple Query to Identify Problematic Records
-- Purpose: Easy-to-run query showing which records cause aggregation explosion
-- Cost: ~300MB (scan temp table with aggregations)

-- Show date distribution with problem classification
SELECT 
    DATE(order_date) AS order_date,
    COUNT(*) AS record_count,
    COUNT(DISTINCT retailer_moniker) AS retailers,
    COUNT(DISTINCT order_item_sku) AS skus,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
    -- Days before execution date (2025-11-20)
    DATE_DIFF(DATE('2025-11-20'), DATE(order_date), DAY) AS days_before_execution,
    -- Problem classification
    CASE 
        WHEN DATE_DIFF(DATE('2025-11-20'), DATE(order_date), DAY) <= 2 
            THEN '✅ EXPECTED (0-2 days old)'
        WHEN DATE_DIFF(DATE('2025-11-20'), DATE(order_date), DAY) <= 7 
            THEN '⚠️ RECENT (3-7 days old)'
        WHEN DATE_DIFF(DATE('2025-11-20'), DATE(order_date), DAY) <= 30 
            THEN '❌ OLD (8-30 days old)'
        ELSE '❌❌ CRITICAL (>30 days old)'
    END AS problem_classification
FROM 
    `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
GROUP BY 
    DATE(order_date)
ORDER BY 
    order_date DESC;

