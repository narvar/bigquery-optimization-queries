-- Query 10: Analyze Return Initiation Dates for Old Orders
-- Purpose: Test hypothesis that old orders (May-Oct) are included because they have RECENT returns
-- This would explain why ingestion_timestamp filter appears to not work
-- Cost: ~1.6GB (scan temp debug table)

WITH old_order_analysis AS (
    SELECT 
        DATE(order_date) AS order_date,
        DATE(return_initiation_date) AS return_initiation_date,
        CASE 
            WHEN return_initiation_date IS NULL THEN 'No return'
            WHEN DATE(return_initiation_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH) 
                THEN 'Recent return (last 3 months)'
            ELSE 'Old return (>3 months ago)'
        END AS return_recency,
        COUNT(*) AS record_count,
        COUNT(DISTINCT retailer_moniker) AS retailers,
        COUNT(DISTINCT order_item_sku) AS skus
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
    WHERE 
        -- Focus on old orders (more than 7 days before execution)
        DATE(order_date) < '2025-11-13'
    GROUP BY 
        DATE(order_date),
        DATE(return_initiation_date),
        return_recency
)

SELECT 
    order_date,
    return_recency,
    SUM(record_count) AS total_records,
    COUNT(DISTINCT return_initiation_date) AS distinct_return_dates,
    SUM(retailers) AS total_retailers,
    ROUND(100.0 * SUM(record_count) / SUM(SUM(record_count)) OVER (), 2) AS pct_of_old_orders
FROM 
    old_order_analysis
GROUP BY 
    order_date,
    return_recency
ORDER BY 
    order_date DESC,
    return_recency
LIMIT 100;

