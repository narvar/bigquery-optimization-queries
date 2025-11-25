-- Query 8c: Aggregation Cardinality Estimation
-- Purpose: Predict how many groups the final aggregation will create
-- This helps explain why the query times out
-- Cost: ~1.6GB (scan temp table)

WITH affected_items_simulation AS (
    -- Simulate the affected_items CTE
    SELECT DISTINCT
        retailer_moniker,
        shopify_domain,
        DATE(order_date) AS order_date,
        order_checkout_locale,
        order_item_product_id,
        order_item_description,
        order_item_name,
        order_item_sku,
        order_item_vendor,
        order_item_size,
        order_item_color,
        order_item_product_type,
        order_item_variant_id,
        order_item_variant_title,
        return_outcome
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
)

SELECT 
    'OVERALL_CARDINALITY' AS metric_type,
    -- Count distinct values for each grouping dimension
    COUNT(*) AS total_distinct_combinations,
    COUNT(DISTINCT retailer_moniker) AS distinct_retailers,
    COUNT(DISTINCT shopify_domain) AS distinct_domains,
    COUNT(DISTINCT order_date) AS distinct_dates,
    COUNT(DISTINCT order_checkout_locale) AS distinct_locales,
    COUNT(DISTINCT order_item_product_id) AS distinct_product_ids,
    COUNT(DISTINCT order_item_sku) AS distinct_skus,
    COUNT(DISTINCT order_item_vendor) AS distinct_vendors,
    COUNT(DISTINCT order_item_size) AS distinct_sizes,
    COUNT(DISTINCT order_item_color) AS distinct_colors,
    COUNT(DISTINCT order_item_product_type) AS distinct_product_types,
    COUNT(DISTINCT return_outcome) AS distinct_outcomes,
    -- Estimate maximum theoretical groups (product of all dimensions)
    -- This would be the WORST case if every combination existed
    COUNT(DISTINCT retailer_moniker) * 
    COUNT(DISTINCT order_date) * 
    COUNT(DISTINCT order_item_sku) AS estimated_max_groups_conservative,
    -- The actual will be less than this, but still huge with 183 dates
    CAST(NULL AS INT64) AS actual_groups_created_approx
FROM 
    affected_items_simulation

UNION ALL

-- Break down by date to show the problem
SELECT 
    CONCAT('BY_DATE: ', CAST(order_date AS STRING)) AS metric_type,
    COUNT(*) AS combinations_for_this_date,
    COUNT(DISTINCT retailer_moniker) AS retailers,
    COUNT(DISTINCT shopify_domain) AS domains,
    1 AS dates,  -- Always 1 since we're grouping by date
    COUNT(DISTINCT order_checkout_locale) AS locales,
    COUNT(DISTINCT order_item_product_id) AS product_ids,
    COUNT(DISTINCT order_item_sku) AS skus,
    COUNT(DISTINCT order_item_vendor) AS vendors,
    COUNT(DISTINCT order_item_size) AS sizes,
    COUNT(DISTINCT order_item_color) AS colors,
    COUNT(DISTINCT order_item_product_type) AS product_types,
    COUNT(DISTINCT return_outcome) AS outcomes,
    CAST(NULL AS INT64) AS max_groups,
    CAST(NULL AS INT64) AS actual_groups
FROM 
    affected_items_simulation
GROUP BY 
    order_date
ORDER BY 
    order_date DESC
LIMIT 20;  -- Show top 20 dates

