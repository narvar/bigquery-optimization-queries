-- Query 11: Analyze Old Records by Retailer
-- Purpose: Check if old orders (May-Oct) are concentrated in specific retailers
-- Or if this is a platform-wide pattern
-- Cost: ~1.6GB (scan temp debug table)

WITH retailer_analysis AS (
    SELECT 
        retailer_moniker,
        shopify_domain,
        -- Count records by age
        COUNTIF(DATE(order_date) >= '2025-11-18') AS recent_orders_3days,
        COUNTIF(DATE(order_date) < '2025-11-18' AND DATE(order_date) >= '2025-11-13') AS week_old_orders,
        COUNTIF(DATE(order_date) < '2025-11-13' AND DATE(order_date) >= '2025-10-20') AS month_old_orders,
        COUNTIF(DATE(order_date) < '2025-10-20') AS very_old_orders,
        COUNT(*) AS total_records,
        -- Date spans
        MIN(DATE(order_date)) AS oldest_order_date,
        MAX(DATE(order_date)) AS newest_order_date,
        DATE_DIFF(MAX(DATE(order_date)), MIN(DATE(order_date)), DAY) AS date_span_days,
        -- Return info
        COUNTIF(return_initiation_date IS NOT NULL) AS has_return,
        COUNTIF(return_initiation_date IS NULL) AS no_return,
        MIN(DATE(return_initiation_date)) AS oldest_return_date,
        MAX(DATE(return_initiation_date)) AS newest_return_date,
        -- Check ingestion (if available - may not be in debug table)
        COUNT(DISTINCT DATE(order_date)) AS distinct_order_dates
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
    GROUP BY 
        retailer_moniker,
        shopify_domain
)

SELECT 
    retailer_moniker,
    shopify_domain,
    recent_orders_3days,
    week_old_orders,
    month_old_orders,
    very_old_orders,
    total_records,
    oldest_order_date,
    newest_order_date,
    date_span_days,
    has_return,
    no_return,
    oldest_return_date,
    newest_return_date,
    distinct_order_dates,
    -- Calculate % of their data that's old
    ROUND(100.0 * (week_old_orders + month_old_orders + very_old_orders) / NULLIF(total_records, 0), 2) AS pct_old_data,
    -- Classify the problem
    CASE 
        WHEN very_old_orders > 1000 THEN 'CRITICAL: >1K very old orders'
        WHEN month_old_orders > 5000 THEN 'HIGH: >5K month-old orders'
        WHEN week_old_orders > 10000 THEN 'MEDIUM: >10K week-old orders'
        WHEN date_span_days > 30 THEN 'LOW: Wide date span but few records'
        ELSE 'OK: Mostly recent data'
    END AS problem_classification
FROM 
    retailer_analysis
WHERE 
    -- Focus on retailers with significant old data
    (very_old_orders + month_old_orders + week_old_orders) > 100
ORDER BY 
    very_old_orders DESC,
    month_old_orders DESC,
    date_span_days DESC
LIMIT 50;

