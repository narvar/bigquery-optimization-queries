-- ============================================================================
-- Storage Cost Analysis by Table for monitor-base-us-prod
-- ============================================================================
-- Purpose: Allocate $24,899/year storage cost by actual table sizes
-- Question: How much storage cost for orders vs shipments vs other tables?
-- ============================================================================

WITH table_storage_details AS (
  SELECT 
    table_catalog AS project_id,
    table_schema AS dataset_id,
    table_name,
    total_rows,
    
    -- Logical storage (GB)
    ROUND(total_logical_bytes / POW(1024, 3), 2) AS total_logical_gb,
    ROUND(active_logical_bytes / POW(1024, 3), 2) AS active_logical_gb,
    ROUND(long_term_logical_bytes / POW(1024, 3), 2) AS long_term_logical_gb,
    
    -- Physical storage (GB)
    ROUND(total_physical_bytes / POW(1024, 3), 2) AS total_physical_gb,
    ROUND(active_physical_bytes / POW(1024, 3), 2) AS active_physical_gb,
    ROUND(long_term_physical_bytes / POW(1024, 3), 2) AS long_term_physical_gb,
    
    -- Compression ratio
    ROUND(SAFE_DIVIDE(total_logical_bytes, total_physical_bytes), 2) AS compression_ratio,
    
    -- Timestamps
    TIMESTAMP_MILLIS(creation_time) AS table_created,
    TIMESTAMP_MILLIS(last_modified_time) AS last_modified,
    DATE_DIFF(CURRENT_DATE(), DATE(TIMESTAMP_MILLIS(last_modified_time)), DAY) AS days_since_update
    
  FROM `monitor-base-us-prod.monitor_base.INFORMATION_SCHEMA.TABLE_STORAGE`
  WHERE deleted = FALSE
    AND table_type = 'BASE TABLE'
),

-- Calculate dataset totals for percentage calculation
dataset_totals AS (
  SELECT
    SUM(total_logical_gb) AS dataset_total_logical_gb,
    SUM(total_physical_gb) AS dataset_total_physical_gb,
    SUM(active_logical_gb) AS dataset_active_logical_gb,
    SUM(long_term_logical_gb) AS dataset_long_term_logical_gb,
    SUM(active_physical_gb) AS dataset_active_physical_gb,
    SUM(long_term_physical_gb) AS dataset_long_term_physical_gb
  FROM table_storage_details
),

-- Calculate costs per table
table_costs AS (
  SELECT
    t.*,
    
    -- Percentage of total storage
    ROUND(t.total_logical_gb / dt.dataset_total_logical_gb * 100, 2) AS pct_of_total_storage,
    
    -- Monthly storage costs (Logical billing model)
    ROUND(t.active_logical_gb * 0.02, 2) AS monthly_active_logical_cost,
    ROUND(t.long_term_logical_gb * 0.01, 2) AS monthly_longterm_logical_cost,
    ROUND((t.active_logical_gb * 0.02) + (t.long_term_logical_gb * 0.01), 2) AS monthly_total_logical_cost,
    
    -- Monthly storage costs (Physical billing model)  
    ROUND(t.active_physical_gb * 0.04, 2) AS monthly_active_physical_cost,
    ROUND(t.long_term_physical_gb * 0.02, 2) AS monthly_longterm_physical_cost,
    ROUND((t.active_physical_gb * 0.04) + (t.long_term_physical_gb * 0.02), 2) AS monthly_total_physical_cost,
    
    -- Annual costs
    ROUND(((t.active_logical_gb * 0.02) + (t.long_term_logical_gb * 0.01)) * 12, 2) AS annual_logical_cost,
    ROUND(((t.active_physical_gb * 0.04) + (t.long_term_physical_gb * 0.02)) * 12, 2) AS annual_physical_cost,
    
    -- Attribution of known $24,899 annual cost
    ROUND(24899 * (t.total_logical_gb / dt.dataset_total_logical_gb), 2) AS attributed_annual_cost_from_billing
    
  FROM table_storage_details t
  CROSS JOIN dataset_totals dt
)

SELECT
  table_name,
  FORMAT("%'d", total_rows) AS total_rows_formatted,
  total_logical_gb,
  total_physical_gb,
  compression_ratio,
  pct_of_total_storage,
  
  -- Focus on attributed cost from actual billing
  attributed_annual_cost_from_billing AS annual_storage_cost_usd,
  monthly_total_logical_cost,
  
  -- Calculated costs for validation
  annual_logical_cost AS calculated_annual_logical,
  
  -- Activity status
  CASE
    WHEN days_since_update <= 7 THEN 'ACTIVE'
    WHEN days_since_update <= 30 THEN 'RECENT'
    WHEN days_since_update <= 90 THEN 'STALE'
    ELSE 'DEPRECATED'
  END AS activity_status,
  
  last_modified

FROM table_costs
WHERE total_logical_gb > 0.1  -- Filter out tiny tables
ORDER BY total_logical_gb DESC;

-- ============================================================================
-- SUMMARY OUTPUT
-- ============================================================================
-- Uncomment to see dataset-level summary:
/*
SELECT
  'DATASET SUMMARY' AS summary_type,
  SUM(total_logical_gb) AS total_logical_gb,
  SUM(total_physical_gb) AS total_physical_gb,
  ROUND(AVG(compression_ratio), 2) AS avg_compression,
  SUM(monthly_total_logical_cost) AS monthly_cost_logical,
  SUM(annual_logical_cost) AS annual_cost_logical,
  24899.00 AS actual_annual_billing_from_doit
FROM table_costs;
*/

-- ============================================================================
-- INTERPRETATION GUIDE
-- ============================================================================
-- attributed_annual_cost_from_billing:
--   This allocates the known $24,899 annual cost by % of storage
--
-- If orders = 98% of storage:
--   → Orders gets: $24,899 × 98% = $24,401/year
--   → Shipments gets: $24,899 × 2% = $498/year
--
-- If calculated_annual_logical differs from $24,899:
--   → Billing model might be PHYSICAL not LOGICAL
--   → Or prices have changed
--   → Use attributed_annual_cost (from actual billing) not calculated
-- ============================================================================

