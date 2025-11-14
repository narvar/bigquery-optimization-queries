-- ============================================================================
-- ORDERS VALIDATION QUERY #1: Check Table Status
-- ============================================================================
-- Purpose: Verify if orders table exists and is actively being populated
-- Expected: If active, should show recent last_modified timestamp
-- ============================================================================

SELECT
  table_id AS table_name,
  row_count,
  ROUND(size_bytes / POW(1024, 3), 2) AS size_gb,
  TIMESTAMP_MILLIS(creation_time) AS table_created,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified,
  DATE_DIFF(CURRENT_DATE(), DATE(TIMESTAMP_MILLIS(last_modified_time)), DAY) AS days_since_last_update,
  
  -- Status indicator
  CASE
    WHEN DATE_DIFF(CURRENT_DATE(), DATE(TIMESTAMP_MILLIS(last_modified_time)), DAY) <= 7 
      THEN 'ACTIVE - Updated this week'
    WHEN DATE_DIFF(CURRENT_DATE(), DATE(TIMESTAMP_MILLIS(last_modified_time)), DAY) <= 30 
      THEN 'ACTIVE - Updated this month'
    WHEN DATE_DIFF(CURRENT_DATE(), DATE(TIMESTAMP_MILLIS(last_modified_time)), DAY) <= 90
      THEN 'STALE - Last updated 1-3 months ago'
    ELSE 'DEPRECATED - Not updated in 90+ days'
  END AS table_status
  
FROM `monitor-base-us-prod.monitor_base.__TABLES__`
WHERE table_id = 'orders';

-- ============================================================================
-- INTERPRETATION:
-- ============================================================================
-- If table_status = 'ACTIVE': 
--   → Pipeline is running
--   → Include Dataflow costs in orders attribution
--   → Use $16K-$22K estimate
--
-- If table_status = 'DEPRECATED':
--   → Pipeline stopped
--   → Dataflow costs are NOT for orders table
--   → Orders cost = $0
-- ============================================================================

