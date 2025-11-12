-- ============================================================================
-- Query: Get Actual Billing Costs for Peak_2024_2025 Period
-- Purpose: Retrieve actual costs from DoIT billing data for Nov 2024 - Jan 2025
-- Source: narvar-data-lake.doitintl_cmp_bq.costs
-- ============================================================================
-- 
-- Peak_2024_2025 Period: 2024-11-01 00:00:00 to 2025-01-31 23:59:59
-- 
-- Schema: reservation_id, job_id, cost, start_time
-- 
-- Expected Output:
-- - Total costs by reservation type
-- - Monthly breakdown
-- - Jobs and cost per job
-- - Comparison metrics
--
-- ============================================================================

DECLARE peak_start_timestamp TIMESTAMP DEFAULT TIMESTAMP('2024-11-01 00:00:00');
DECLARE peak_end_timestamp TIMESTAMP DEFAULT TIMESTAMP('2025-01-31 23:59:59');

-- ============================================================================
-- PART 1: Monthly Breakdown by Reservation Type
-- ============================================================================
WITH peak_costs AS (
  SELECT
    -- Time dimensions
    FORMAT_TIMESTAMP('%Y-%m', start_time) as year_month,
    EXTRACT(YEAR FROM start_time) as year,
    EXTRACT(MONTH FROM start_time) as month_num,
    
    -- Reservation classification
    CASE 
      WHEN reservation_id = 'unreserved' THEN 'ON_DEMAND'
      WHEN reservation_id = 'default-pipeline' THEN 'RESERVED_PIPELINE'
      WHEN reservation_id LIKE '%bq-narvar-admin%' THEN 'RESERVED_SHARED_POOL'
      ELSE 'OTHER'
    END as reservation_type,
    reservation_id,
    
    -- Metrics
    job_id,
    cost
    
  FROM `narvar-data-lake.doitintl_cmp_bq.costs`
  WHERE start_time BETWEEN peak_start_timestamp AND peak_end_timestamp
),

monthly_summary AS (
  SELECT
    year_month,
    reservation_type,
    reservation_id,
    COUNT(DISTINCT job_id) as total_jobs,
    ROUND(SUM(cost), 2) as total_cost_usd,
    ROUND(SUM(cost) / NULLIF(COUNT(DISTINCT job_id), 0), 6) as cost_per_job
  FROM peak_costs
  GROUP BY year_month, reservation_type, reservation_id
),

period_totals AS (
  SELECT
    'TOTAL (3-month period)' as year_month,
    reservation_type,
    reservation_id,
    COUNT(DISTINCT job_id) as total_jobs,
    ROUND(SUM(cost), 2) as total_cost_usd,
    ROUND(SUM(cost) / NULLIF(COUNT(DISTINCT job_id), 0), 6) as cost_per_job
  FROM peak_costs
  GROUP BY reservation_type, reservation_id
),

grand_total AS (
  SELECT
    'TOTAL (3-month period)' as year_month,
    'ALL RESERVATIONS' as reservation_type,
    'ALL' as reservation_id,
    COUNT(DISTINCT job_id) as total_jobs,
    ROUND(SUM(cost), 2) as total_cost_usd,
    ROUND(SUM(cost) / NULLIF(COUNT(DISTINCT job_id), 0), 6) as cost_per_job
  FROM peak_costs
)

-- Combine all results
SELECT
  year_month,
  reservation_type,
  reservation_id,
  total_jobs,
  total_cost_usd,
  cost_per_job,
  ROUND(total_cost_usd / 3, 2) as avg_monthly_cost_usd
FROM monthly_summary

UNION ALL

SELECT
  year_month,
  reservation_type,
  reservation_id,
  total_jobs,
  total_cost_usd,
  cost_per_job,
  ROUND(total_cost_usd / 3, 2) as avg_monthly_cost_usd
FROM period_totals

UNION ALL

SELECT
  year_month,
  reservation_type,
  reservation_id,
  total_jobs,
  total_cost_usd,
  cost_per_job,
  ROUND(total_cost_usd / 3, 2) as avg_monthly_cost_usd
FROM grand_total

ORDER BY 
  CASE 
    WHEN year_month = 'TOTAL (3-month period)' AND reservation_type = 'ALL RESERVATIONS' THEN 3
    WHEN year_month = 'TOTAL (3-month period)' THEN 2
    ELSE 1
  END,
  year_month,
  total_cost_usd DESC;


-- ============================================================================
-- PART 2: Simple Summary View
-- ============================================================================

SELECT
  '========================================' as divider,
  'PEAK 2024-2025 COST SUMMARY' as title,
  '========================================' as divider2;

SELECT
  CASE 
    WHEN reservation_id = 'unreserved' THEN 'ON_DEMAND'
    WHEN reservation_id = 'default-pipeline' THEN 'RESERVED_PIPELINE'
    WHEN reservation_id LIKE '%bq-narvar-admin%' THEN 'RESERVED_SHARED_POOL'
    ELSE 'OTHER'
  END as reservation_type,
  COUNT(DISTINCT job_id) as total_jobs,
  ROUND(SUM(cost), 2) as total_cost_usd,
  ROUND(SUM(cost) / 3, 2) as avg_monthly_cost_usd,
  ROUND(SUM(cost) / NULLIF(COUNT(DISTINCT job_id), 0), 6) as cost_per_job,
  ROUND(100.0 * SUM(cost) / SUM(SUM(cost)) OVER (), 2) as pct_of_total_cost
FROM `narvar-data-lake.doitintl_cmp_bq.costs`
WHERE start_time BETWEEN TIMESTAMP('2024-11-01 00:00:00') AND TIMESTAMP('2025-01-31 23:59:59')
GROUP BY reservation_type
ORDER BY total_cost_usd DESC;

