-- Query 8a: Identify Records from OLD Dates (Problematic Records)
-- Purpose: Find records that should NOT be in the temp table
-- These are the primary cause of aggregation explosion
-- Cost: ~1.6GB (scan temp table)

-- Find all records older than 7 days from execution date (2025-11-20)
-- These should have been filtered out by the 48-hour ingestion_timestamp filter
SELECT 
    DATE(order_date) AS order_date,
    retailer_moniker,
    shopify_domain,
    COUNT(*) AS record_count,
    COUNT(DISTINCT order_item_sku) AS distinct_skus,
    COUNT(DISTINCT order_number) AS distinct_orders,
    -- Show percentage of total temp table
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
    -- Sample some records for verification
    ARRAY_AGG(order_number LIMIT 3) AS sample_order_numbers,
    MIN(order_date) AS min_order_timestamp,
    MAX(order_date) AS max_order_timestamp
FROM 
    `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
WHERE 
    -- Records more than 7 days old (should not be here!)
    DATE(order_date) < DATE_SUB(DATE('2025-11-20'), INTERVAL 7 DAY)
GROUP BY 
    DATE(order_date),
    retailer_moniker,
    shopify_domain
ORDER BY 
    order_date DESC,
    record_count DESC
LIMIT 100;

