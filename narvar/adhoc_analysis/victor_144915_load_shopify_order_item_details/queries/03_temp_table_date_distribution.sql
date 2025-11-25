-- Query 3: Temp Table Date Distribution
-- Purpose: Understand why tmp_order_item_details has 183 distinct dates
-- This should only have 1-2 days of data based on 48-hour filter
-- Cost: ~1.6GB (scan full temp table)

WITH date_stats AS (
    SELECT 
        DATE(order_date) AS order_date,
        COUNT(*) AS row_count,
        COUNT(DISTINCT retailer_moniker) AS retailers,
        COUNT(DISTINCT order_item_sku) AS skus,
        MIN(order_date) AS min_order_timestamp,
        MAX(order_date) AS max_order_timestamp
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20`
    GROUP BY 
        DATE(order_date)
)
SELECT 
    order_date,
    row_count,
    retailers,
    skus,
    -- Calculate % of total rows
    ROUND(100.0 * row_count / SUM(row_count) OVER (), 2) AS pct_of_total,
    -- Calculate cumulative %
    ROUND(100.0 * SUM(row_count) OVER (ORDER BY order_date DESC) / SUM(row_count) OVER (), 2) AS cumulative_pct,
    min_order_timestamp,
    max_order_timestamp
FROM 
    date_stats
ORDER BY 
    order_date DESC
LIMIT 50;  -- Show most recent 50 days

