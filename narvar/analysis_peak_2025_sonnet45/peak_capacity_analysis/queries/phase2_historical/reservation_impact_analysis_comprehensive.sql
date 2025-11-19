-- ============================================================================
-- INVESTIGATION 2: COMPREHENSIVE RESERVATION POOL IMPACT ANALYSIS
-- ============================================================================
-- Purpose: Analyze QoS and performance impact of reservation type across ALL projects
--          Test hypothesis: Does shared 1,700-slot pool cause more QoS stress than on-demand?
--
-- Scope: ALL projects (EXTERNAL, AUTOMATED, INTERNAL) not just monitor
-- Question: Are reserved projects more impacted by capacity stress than on-demand?
--
-- Output: narvar-data-lake.query_opt.phase2_reservation_impact
-- Runtime: ~15-20 seconds
-- ============================================================================

DECLARE analyze_periods ARRAY<STRING> DEFAULT [
  'Peak_2024_2025',
  'Baseline_2025_Sep_Oct',
  'Peak_2023_2024'
];

DECLARE external_qos_threshold_seconds INT64 DEFAULT 30;

-- ============================================================================
-- CREATE OUTPUT TABLE
-- ============================================================================

CREATE OR REPLACE TABLE `narvar-data-lake.query_opt.phase2_reservation_impact` AS

WITH
-- Classify all jobs by reservation type
jobs_by_reservation AS (
  SELECT
    analysis_period_label,
    consumer_category,
    consumer_subcategory,
    
    -- Standardize reservation naming
    CASE
      WHEN reservation_name = 'bq-narvar-admin:US.default' THEN 'RESERVED_SHARED_POOL'
      WHEN reservation_name = 'default-pipeline' THEN 'RESERVED_PIPELINE'
      WHEN reservation_name LIKE 'bq-narvar-admin:US.%' THEN CONCAT('RESERVED_', reservation_name)
      WHEN reservation_name = 'unreserved' THEN 'ON_DEMAND'
      WHEN reservation_name IS NULL THEN 'UNKNOWN'
      ELSE reservation_name
    END as reservation_type,
    
    reservation_name as raw_reservation_name,
    project_id,
    job_id,
    start_time,
    end_time,
    execution_time_seconds,
    slot_hours,
    approximate_slot_count,
    is_qos_violation,
    
    -- QoS threshold varies by category
    CASE
      WHEN consumer_category = 'EXTERNAL' THEN external_qos_threshold_seconds
      WHEN consumer_category = 'INTERNAL' THEN 480  -- 8 minutes
      ELSE 1800  -- 30 minutes for AUTOMATED
    END as qos_threshold
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
),

-- Get stress state for each job by joining with stress periods
jobs_with_stress AS (
  SELECT
    j.*,
    COALESCE(s.stress_state, 'NORMAL') as stress_state
  FROM jobs_by_reservation j
  LEFT JOIN (
    SELECT 
      analysis_period_label,
      window_start,
      window_end,
      stress_state
    FROM `narvar-data-lake.query_opt.phase2_stress_periods`
    WHERE is_hourly_aggregate = FALSE
  ) s
    ON j.analysis_period_label = s.analysis_period_label
    -- Job must have started AND finished within the stress window
    AND NOT (j.end_time <= s.window_start OR j.start_time >= s.window_end)
)

-- PART A: Overall Reservation Type Distribution
SELECT
  'PART A: Overall Distribution by Reservation Type' AS analysis_section,
  analysis_period_label,
  reservation_type,
  consumer_category,
  
  COUNT(*) as total_jobs,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER(PARTITION BY analysis_period_label) * 100, 2) as pct_of_period,
  
  ROUND(SUM(slot_hours), 0) as total_slot_hours,
  ROUND(SUM(slot_hours) / SUM(SUM(slot_hours)) OVER(PARTITION BY analysis_period_label) * 100, 2) as pct_of_slots,
  
  ROUND(AVG(execution_time_seconds), 2) as avg_exec_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) as p95_exec_seconds,
  
  COUNTIF(is_qos_violation) as qos_violations,
  ROUND(COUNTIF(is_qos_violation) / NULLIF(COUNTIF(is_qos_violation IS NOT NULL), 0) * 100, 2) as qos_violation_pct,
  
  COUNT(DISTINCT project_id) as unique_projects,
  
  -- Null fields for Part B
  CAST(NULL AS STRING) as stress_state,
  CAST(NULL AS INT64) as jobs_during_stress,
  CAST(NULL AS FLOAT64) as violation_pct_during_stress,
  CAST(NULL AS FLOAT64) as p95_during_stress
  
FROM jobs_by_reservation
GROUP BY analysis_period_label, reservation_type, consumer_category

UNION ALL

-- PART B: QoS During Stress by Reservation Type
SELECT
  'PART B: QoS During Stress by Reservation Type' AS analysis_section,
  analysis_period_label,
  reservation_type,
  consumer_category,
  
  -- Null fields for Part A
  CAST(NULL AS INT64) as total_jobs,
  CAST(NULL AS FLOAT64) as pct_of_period,
  CAST(NULL AS FLOAT64) as total_slot_hours,
  CAST(NULL AS FLOAT64) as pct_of_slots,
  CAST(NULL AS FLOAT64) as avg_exec_seconds,
  CAST(NULL AS FLOAT64) as p95_exec_seconds,
  CAST(NULL AS INT64) as qos_violations,
  CAST(NULL AS FLOAT64) as qos_violation_pct,
  CAST(NULL AS INT64) as unique_projects,
  
  -- Part B specific fields
  stress_state,
  COUNT(*) as jobs_during_stress,
  ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) as violation_pct_during_stress,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) as p95_during_stress
  
FROM jobs_with_stress
WHERE stress_state IN ('INFO', 'WARNING', 'CRITICAL')
GROUP BY analysis_period_label, reservation_type, consumer_category, stress_state

ORDER BY analysis_section, analysis_period_label, reservation_type, consumer_category, stress_state;

-- ============================================================================
-- VALIDATION QUERIES
-- ============================================================================
/*
-- Overall distribution
SELECT
  analysis_period_label,
  reservation_type,
  total_jobs,
  total_slot_hours,
  qos_violation_pct
FROM `narvar-data-lake.query_opt.phase2_reservation_impact`
WHERE analysis_section = 'PART A: Overall Distribution by Reservation Type'
  AND consumer_category = 'EXTERNAL'
ORDER BY analysis_period_label, total_slot_hours DESC;

-- Critical stress comparison
SELECT
  analysis_period_label,
  reservation_type,
  consumer_category,
  jobs_during_stress,
  violation_pct_during_stress,
  p95_during_stress
FROM `narvar-data-lake.query_opt.phase2_reservation_impact`
WHERE analysis_section = 'PART B: QoS During Stress by Reservation Type'
  AND stress_state = 'CRITICAL'
ORDER BY analysis_period_label, violation_pct_during_stress DESC;
*/

