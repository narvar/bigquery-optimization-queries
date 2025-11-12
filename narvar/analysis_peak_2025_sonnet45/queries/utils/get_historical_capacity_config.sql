-- ============================================================================
-- Query: Historical Capacity Configuration for Dec 2024 - Jan 2025
-- Purpose: Show the actual reservation and commitment configuration during peak
-- ============================================================================
-- 
-- This query retrieves:
-- 1. Capacity commitments (slot counts, pricing, plans)
-- 2. Reservation configurations
-- 3. Changes over time
--
-- Period: December 2024 - January 2025
-- ============================================================================

DECLARE peak_start TIMESTAMP DEFAULT TIMESTAMP('2024-12-01 00:00:00');
DECLARE peak_end TIMESTAMP DEFAULT TIMESTAMP('2025-01-31 23:59:59');

-- ============================================================================
-- PART 1: Capacity Commitments History
-- ============================================================================

SELECT 
  '=== CAPACITY COMMITMENTS (Dec 2024 - Jan 2025) ===' as section;

WITH commitments AS (
  SELECT
    DATE(ts) as config_date,
    project,
    region,
    name as commitment_name,
    slot_count,
    CASE plan
      WHEN 1 THEN 'FLEX (monthly)'
      WHEN 2 THEN 'MONTHLY'
      WHEN 3 THEN 'ANNUAL (1-year)'
      WHEN 4 THEN 'THREE_YEAR'
      ELSE CONCAT('UNKNOWN (', CAST(plan AS STRING), ')')
    END as plan_type,
    CASE edition
      WHEN 1 THEN 'STANDARD'
      WHEN 2 THEN 'ENTERPRISE'
      WHEN 3 THEN 'ENTERPRISE_PLUS'
      ELSE CONCAT('UNKNOWN (', CAST(edition AS STRING), ')')
    END as edition_type,
    slot_hour_price,
    ROUND(slot_count * slot_hour_price * 720, 2) as estimated_monthly_cost,
    ts
  FROM `narvar-data-lake.doitintl_cmp_bq.capacity_commitments_history`
  WHERE ts BETWEEN peak_start AND peak_end
    AND region = 'US'
),

-- Get distinct configurations (deduplicate same-day records)
distinct_configs AS (
  SELECT DISTINCT
    config_date,
    project,
    region,
    commitment_name,
    slot_count,
    plan_type,
    edition_type,
    slot_hour_price,
    estimated_monthly_cost
  FROM commitments
)

SELECT
  config_date,
  project,
  commitment_name,
  slot_count,
  plan_type,
  edition_type,
  slot_hour_price,
  estimated_monthly_cost
FROM distinct_configs
ORDER BY config_date DESC, slot_count DESC;

-- ============================================================================
-- PART 2: Summary by Plan Type
-- ============================================================================

SELECT 
  '=== COMMITMENT SUMMARY BY PLAN TYPE ===' as section;

SELECT
  plan_type,
  SUM(slot_count) as total_slots,
  AVG(slot_hour_price) as avg_slot_hour_price,
  SUM(estimated_monthly_cost) as total_monthly_cost,
  COUNT(DISTINCT commitment_name) as num_commitments
FROM (
  SELECT DISTINCT
    CASE plan
      WHEN 1 THEN 'FLEX (monthly)'
      WHEN 2 THEN 'MONTHLY'
      WHEN 3 THEN 'ANNUAL (1-year)'
      WHEN 4 THEN 'THREE_YEAR'
      ELSE 'UNKNOWN'
    END as plan_type,
    name as commitment_name,
    slot_count,
    slot_hour_price,
    ROUND(slot_count * slot_hour_price * 720, 2) as estimated_monthly_cost
  FROM `narvar-data-lake.doitintl_cmp_bq.capacity_commitments_history`
  WHERE ts BETWEEN peak_start AND peak_end
    AND region = 'US'
)
GROUP BY plan_type
ORDER BY total_slots DESC;

-- ============================================================================
-- PART 3: Configuration Changes Over Time
-- ============================================================================

SELECT 
  '=== CONFIGURATION CHANGES (if any) ===' as section;

WITH daily_totals AS (
  SELECT
    DATE(ts) as config_date,
    SUM(slot_count) as total_committed_slots,
    ROUND(SUM(slot_count * slot_hour_price * 720), 2) as total_monthly_cost,
    COUNT(DISTINCT name) as num_commitments
  FROM `narvar-data-lake.doitintl_cmp_bq.capacity_commitments_history`
  WHERE ts BETWEEN peak_start AND peak_end
    AND region = 'US'
  GROUP BY config_date
),

changes AS (
  SELECT
    config_date,
    total_committed_slots,
    total_monthly_cost,
    num_commitments,
    LAG(total_committed_slots) OVER (ORDER BY config_date) as prev_slots,
    LAG(total_monthly_cost) OVER (ORDER BY config_date) as prev_cost
  FROM daily_totals
)

SELECT
  config_date,
  total_committed_slots,
  total_monthly_cost,
  num_commitments,
  CASE 
    WHEN prev_slots IS NULL THEN 'INITIAL'
    WHEN total_committed_slots != prev_slots THEN CONCAT('CHANGED (', 
      CAST(total_committed_slots - prev_slots AS STRING), ' slots)')
    ELSE 'NO CHANGE'
  END as change_status
FROM changes
ORDER BY config_date;

-- ============================================================================
-- PART 4: Sample - Most Recent Configuration
-- ============================================================================

SELECT 
  '=== MOST RECENT CONFIGURATION ===' as section;

WITH latest_config AS (
  SELECT
    name as commitment_name,
    slot_count,
    CASE plan
      WHEN 3 THEN 'ANNUAL (1-year)'
      WHEN 4 THEN 'THREE_YEAR'
      WHEN 1 THEN 'FLEX (monthly)'
      ELSE CAST(plan AS STRING)
    END as plan_type,
    CASE edition
      WHEN 2 THEN 'ENTERPRISE'
      WHEN 3 THEN 'ENTERPRISE_PLUS'
      ELSE CAST(edition AS STRING)
    END as edition_type,
    slot_hour_price,
    ROUND(slot_count * slot_hour_price, 2) as hourly_cost,
    ROUND(slot_count * slot_hour_price * 720, 2) as monthly_cost,
    ts
  FROM `narvar-data-lake.doitintl_cmp_bq.capacity_commitments_history`
  WHERE ts BETWEEN peak_start AND peak_end
    AND region = 'US'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY name ORDER BY ts DESC) = 1
)

SELECT
  commitment_name,
  slot_count,
  plan_type,
  edition_type,
  slot_hour_price,
  hourly_cost,
  monthly_cost,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', ts) as last_updated
FROM latest_config
ORDER BY slot_count DESC;

SELECT
  'TOTAL COMMITTED SLOTS' as metric,
  SUM(slot_count) as value
FROM latest_config
UNION ALL
SELECT
  'TOTAL MONTHLY COST',
  SUM(monthly_cost)
FROM latest_config;

