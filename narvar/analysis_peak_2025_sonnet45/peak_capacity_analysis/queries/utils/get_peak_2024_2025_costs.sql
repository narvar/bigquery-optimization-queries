-- ============================================================================
-- Query: Get Actual Billing Costs for Peak_2024_2025 Period
-- Purpose: Retrieve actual costs from DoIT billing data for Nov 2024 - Jan 2025
-- Source: narvar-data-lake.doitintl_cmp_bq.costs
-- ============================================================================
-- 
-- Peak_2024_2025 Period: 2024-11-01 to 2025-01-31 (3 months)
-- 
-- Expected Output:
-- - Total costs by reservation type
-- - Monthly breakdown
-- - Jobs and cost per job
-- - Comparison to baseline periods
--
-- Estimated Scan: Unknown (costs table size unknown)
-- ============================================================================

DECLARE peak_start_date DATE DEFAULT '2024-11-01';
DECLARE peak_end_date DATE DEFAULT '2025-01-31';

-- Get cost breakdown by reservation type for Peak_2024_2025
WITH peak_costs AS (
  SELECT
    -- Time dimensions
    DATE_TRUNC(usage_date, MONTH) as month,
    EXTRACT(YEAR FROM usage_date) as year,
    EXTRACT(MONTH FROM usage_date) as month_num,
    FORMAT_DATE('%Y-%m', usage_date) as year_month,
    
    -- Reservation info
    CASE 
      WHEN reservation_id = 'unreserved' THEN 'ON_DEMAND'
      WHEN reservation_id = 'default-pipeline' THEN 'RESERVED_PIPELINE'
      WHEN reservation_id LIKE '%bq-narvar-admin%' THEN 'RESERVED_SHARED_POOL'
      ELSE COALESCE(reservation_id, 'UNKNOWN')
    END as reservation_type,
    reservation_id,
    
    -- Metrics
    COUNT(DISTINCT job_id) as total_jobs,
    SUM(cost) as total_cost_usd,
    SUM(bytes_processed) as total_bytes_processed,
    
  FROM `narvar-data-lake.doitintl_cmp_bq.costs`
  WHERE usage_date BETWEEN peak_start_date AND peak_end_date
    AND service = 'BigQuery'
  GROUP BY month, year, month_num, year_month, reservation_type, reservation_id
),

monthly_summary AS (
  SELECT
    year_month,
    reservation_type,
    reservation_id,
    total_jobs,
    total_cost_usd,
    total_bytes_processed,
    ROUND(total_bytes_processed / POW(1024, 4), 2) as total_tb_processed,
    ROUND(total_cost_usd / NULLIF(total_jobs, 0), 4) as cost_per_job,
    ROUND(total_cost_usd / NULLIF(total_bytes_processed / POW(1024, 4), 0), 2) as cost_per_tb
  FROM peak_costs
),

period_totals AS (
  SELECT
    'PERIOD_TOTAL' as year_month,
    reservation_type,
    reservation_id,
    SUM(total_jobs) as total_jobs,
    SUM(total_cost_usd) as total_cost_usd,
    SUM(total_bytes_processed) as total_bytes_processed,
    ROUND(SUM(total_bytes_processed) / POW(1024, 4), 2) as total_tb_processed,
    ROUND(SUM(total_cost_usd) / NULLIF(SUM(total_jobs), 0), 4) as cost_per_job,
    ROUND(SUM(total_cost_usd) / NULLIF(SUM(total_bytes_processed) / POW(1024, 4), 0), 2) as cost_per_tb
  FROM peak_costs
  GROUP BY reservation_type, reservation_id
)

-- Combine monthly and period totals
SELECT
  year_month,
  reservation_type,
  reservation_id,
  total_jobs,
  total_cost_usd,
  total_tb_processed,
  cost_per_job,
  cost_per_tb
FROM monthly_summary

UNION ALL

SELECT
  year_month,
  reservation_type,
  reservation_id,
  total_jobs,
  total_cost_usd,
  total_tb_processed,
  cost_per_job,
  cost_per_tb
FROM period_totals

ORDER BY 
  CASE 
    WHEN year_month = 'PERIOD_TOTAL' THEN 2
    ELSE 1
  END,
  year_month,
  total_cost_usd DESC;

-- Additional summary: Grand totals
SELECT
  '=== PEAK_2024_2025 GRAND TOTALS ===' as summary,
  FORMAT_DATE('%Y-%m-%d', DATE '2024-11-01') as period_start,
  FORMAT_DATE('%Y-%m-%d', DATE '2025-01-31') as period_end,
  COUNT(DISTINCT reservation_id) as num_reservations,
  COUNT(DISTINCT job_id) as total_jobs,
  ROUND(SUM(cost), 2) as total_cost_usd,
  ROUND(SUM(cost) / 3, 2) as avg_monthly_cost_usd,
  ROUND(SUM(bytes_processed) / POW(1024, 4), 2) as total_tb_processed,
  ROUND(SUM(cost) / NULLIF(COUNT(DISTINCT job_id), 0), 4) as avg_cost_per_job
FROM `narvar-data-lake.doitintl_cmp_bq.costs`
WHERE usage_date BETWEEN DATE '2024-11-01' AND DATE '2025-01-31'
  AND service = 'BigQuery';






