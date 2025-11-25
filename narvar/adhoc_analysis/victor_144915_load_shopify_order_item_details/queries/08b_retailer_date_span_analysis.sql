-- Query 8b: Retailer Date Span Analysis
-- Purpose: Identify which retailers have data spanning the most dates
-- These retailers contribute most to the aggregation explosion
-- Cost: ~1.6GB (scan temp table)

SELECT 
    retailer_moniker,
    shopify_domain,
    COUNT(*) AS total_records,
    COUNT(DISTINCT DATE(order_date)) AS distinct_dates,
    COUNT(DISTINCT order_item_sku) AS distinct_skus,
    MIN(DATE(order_date)) AS min_date,
    MAX(DATE(order_date)) AS max_date,
    DATE_DIFF(MAX(DATE(order_date)), MIN(DATE(order_date)), DAY) AS date_span_days,
    -- Estimate their contribution to aggregation cardinality
    COUNT(DISTINCT DATE(order_date)) * COUNT(DISTINCT order_item_sku) AS estimated_groups_created,
    -- Show % of total records
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total_records,
    -- Categorize the problem
    CASE 
        WHEN DATE_DIFF(MAX(DATE(order_date)), MIN(DATE(order_date)), DAY) > 30 THEN 'CRITICAL: >30 day span'
        WHEN DATE_DIFF(MAX(DATE(order_date)), MIN(DATE(order_date)), DAY) > 7 THEN 'WARNING: >7 day span'
        WHEN DATE_DIFF(MAX(DATE(order_date)), MIN(DATE(order_date)), DAY) > 3 THEN 'CAUTION: >3 day span'
        ELSE 'OK: <=3 day span'
    END AS problem_severity
FROM 
    `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
GROUP BY 
    retailer_moniker,
    shopify_domain
HAVING 
    -- Focus on retailers with wide date spans (the problematic ones)
    DATE_DIFF(MAX(DATE(order_date)), MIN(DATE(order_date)), DAY) > 3
ORDER BY 
    date_span_days DESC,
    estimated_groups_created DESC
LIMIT 50;

