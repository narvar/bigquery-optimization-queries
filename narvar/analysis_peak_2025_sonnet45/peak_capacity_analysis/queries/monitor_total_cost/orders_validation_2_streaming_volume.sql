-- ============================================================================
-- ORDERS VALIDATION QUERY #2: Check Monthly Streaming Insert Volume
-- ============================================================================
-- Purpose: Correlate data volume with streaming insert costs from billing
-- Expected: Volume pattern should match billing cost pattern
-- ============================================================================

-- Note: Table appears not to be partitioned by _PARTITIONTIME
-- Using simple row count instead

SELECT
  'orders' AS table_name,
  COUNT(*) AS total_rows,
  ROUND(COUNT(*) / 1000000.0, 2) AS millions_of_rows,
  ROUND(COUNT(*) / 1000000000.0, 2) AS billions_of_rows,
  
  -- Estimate total data size (assuming ~350 bytes per row)
  ROUND(COUNT(*) * 350 / POW(1024, 4), 2) AS estimated_tb_total,
  
  -- Date range
  MIN(order_date) AS earliest_order,
  MAX(order_date) AS latest_order,
  DATE_DIFF(MAX(DATE(order_date)), MIN(DATE(order_date)), DAY) AS days_of_data,
  
  -- Unique orders
  APPROX_COUNT_DISTINCT(order_number) AS unique_orders
  
FROM `monitor-base-us-prod.monitor_base.orders`
WHERE order_date >= '2024-01-01';

-- ============================================================================
-- Note: Since table isn't partitioned, we can't get monthly insert patterns
-- But we can validate against billing data:
-- - Total size should match storage costs
-- - If table is 88 TB, streaming that data would cost significant $
-- ============================================================================

-- ============================================================================
-- INTERPRETATION:
-- ============================================================================
-- If estimated_streaming_cost ≈ actual_billing_streaming_cost (±30%):
--   → Orders table receives most/all streaming inserts
--   → Validate attribution
--
-- If estimated_streaming_cost << actual_billing_streaming_cost:
--   → Other tables also use streaming inserts
--   → Need to share costs
--
-- If rows_inserted shows drop in April 2025:
--   → Confirms pipeline was scaled down
--   → Matches Dataflow cost reduction
-- ============================================================================

