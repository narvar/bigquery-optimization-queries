-- ============================================================================
-- EXTERNAL CUSTOMER QoS UNDER STRESS CONDITIONS - FIXED VERSION
-- ============================================================================
-- FIXED: Now uses phase2_stress_periods table directly instead of 
--        recalculating stress states, ensuring consistency with Query 1
-- ============================================================================

DECLARE analyze_periods ARRAY<STRING> DEFAULT [
  'Peak_2024_2025',
  'Baseline_2025_Sep_Oct',
  'Peak_2023_2024'
];

DECLARE external_qos_threshold_seconds INT64 DEFAULT 60;

-- ============================================================================
-- CREATE THE OUTPUT TABLE
-- ============================================================================

CREATE OR REPLACE TABLE `narvar-data-lake.query_opt.phase2_external_qos` AS

WITH
-- Use stress periods from Query 1 (10-minute windows)
stress_windows AS (
  SELECT
    analysis_period_label,
    window_start,
    window_end,
    stress_state
  FROM `narvar-data-lake.query_opt.phase2_stress_periods`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
    AND is_hourly_aggregate = FALSE  -- Use 10-min windows, not hourly aggregates
),

-- Get EXTERNAL customer-facing jobs and their stress state
external_customer_jobs AS (
  SELECT
    t.analysis_period_label,
    t.consumer_subcategory,
    s.stress_state,
    t.job_id,
    t.execution_time_seconds,
    t.slot_hours,
    t.approximate_slot_count,
    t.retailer_moniker,
    t.principal_email,
    
    -- QoS evaluation
    CASE
      WHEN t.execution_time_seconds <= external_qos_threshold_seconds THEN 'QoS_MET'
      WHEN t.execution_time_seconds > external_qos_threshold_seconds THEN 'QoS_VIOLATION'
      ELSE 'QoS_UNKNOWN'
    END AS qos_result,
    
    CASE
      WHEN t.execution_time_seconds > external_qos_threshold_seconds
        THEN t.execution_time_seconds - external_qos_threshold_seconds
      ELSE 0
    END AS violation_seconds
    
  FROM `narvar-data-lake.query_opt.traffic_classification` t
  INNER JOIN stress_windows s
    ON t.analysis_period_label = s.analysis_period_label
    -- Job overlaps with stress window
    AND t.start_time < s.window_end
    AND t.end_time > s.window_start
  
  WHERE (analyze_periods IS NULL OR t.analysis_period_label IN UNNEST(analyze_periods))
    AND t.consumer_category = 'EXTERNAL'
    AND t.consumer_subcategory IN ('MONITOR', 'HUB')  -- Exclude MONITOR_BASE
)

-- Aggregate by stress state
SELECT
  analysis_period_label,
  stress_state,
  consumer_subcategory,
  
  COUNT(*) AS total_jobs,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER(PARTITION BY analysis_period_label) * 100, 2) AS pct_of_period,
  
  COUNTIF(qos_result = 'QoS_MET') AS qos_met,
  COUNTIF(qos_result = 'QoS_VIOLATION') AS qos_violations,
  ROUND(COUNTIF(qos_result = 'QoS_VIOLATION') / COUNT(*) * 100, 2) AS qos_violation_pct,
  
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
  MAX(execution_time_seconds) AS max_execution_seconds,
  
  ROUND(AVG(CASE WHEN qos_result = 'QoS_VIOLATION' THEN violation_seconds END), 2) AS avg_violation_seconds,
  ROUND(MAX(violation_seconds), 2) AS max_violation_seconds,
  
  ROUND(AVG(slot_hours), 4) AS avg_slot_hours_per_job,
  ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots,
  
  COUNT(DISTINCT retailer_moniker) AS unique_retailers,
  COUNT(DISTINCT principal_email) AS unique_principals

FROM external_customer_jobs
GROUP BY analysis_period_label, stress_state, consumer_subcategory
ORDER BY analysis_period_label, 
  CASE stress_state WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 WHEN 'INFO' THEN 3 ELSE 4 END,
  total_jobs DESC;

