-- ============================================================================
-- ORDERS VALIDATION QUERY #3: Check View Usage and Definition
-- ============================================================================
-- Purpose: Determine if v_orders/v_order_items are actually used by retailers
-- Expected: If used, costs should be attributed; if not, pipeline may be deprecated
-- ============================================================================

-- Part A: Get v_orders view definition
SELECT
  table_catalog,
  table_schema,
  table_name,
  view_definition,
  
  -- Check what the view actually queries
  CASE
    WHEN view_definition LIKE '%monitor_base.orders%' THEN 'Queries orders table ✓'
    WHEN view_definition LIKE '%monitor_base.shipments%' THEN 'Queries shipments table (orders not needed!)'
    ELSE 'Unknown source'
  END AS view_source_table
  
FROM `monitor-base-us-prod.monitor_base.INFORMATION_SCHEMA.VIEWS`
WHERE table_name IN ('v_orders', 'v_order_items')
ORDER BY table_name;

-- ============================================================================

-- Part B: Check if retailers actually query these views
-- (Uncomment and run separately if needed)
/*
SELECT
  -- Usage counts
  COUNT(DISTINCT job_id) AS total_queries,
  COUNT(DISTINCT retailer_moniker) AS retailers_using_orders,
  
  -- Sample retailers
  STRING_AGG(DISTINCT retailer_moniker ORDER BY retailer_moniker LIMIT 10) AS sample_retailers,
  
  -- Monthly breakdown
  FORMAT_DATE('%Y-%m', DATE(creation_time)) AS year_month,
  COUNT(*) AS queries_per_month
  
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE DATE(creation_time) >= '2024-10-01'
  AND consumer_subcategory = 'MONITOR'
  AND (
    referenced_tables LIKE '%v_orders%' OR 
    referenced_tables LIKE '%v_order_items%' OR
    query_text_sample LIKE '%monitor_base.orders%'
  )
GROUP BY year_month
ORDER BY year_month;
*/

-- ============================================================================
-- INTERPRETATION:
-- ============================================================================
-- If view_definition contains 'monitor_base.orders':
--   → View uses orders table
--   → Dataflow pipeline is necessary
--   → Include Dataflow costs
--
-- If view_definition contains 'monitor_base.shipments':
--   → View doesn't actually use orders table!
--   → Dataflow pipeline might be deprecated/unused
--   → Dataflow costs are NOT for orders
--   → Orders table cost = $0
--
-- If Part B shows zero queries:
--   → No retailers use v_orders/v_order_items
--   → Pipeline not needed
--   → Consider deprecating
-- ============================================================================

