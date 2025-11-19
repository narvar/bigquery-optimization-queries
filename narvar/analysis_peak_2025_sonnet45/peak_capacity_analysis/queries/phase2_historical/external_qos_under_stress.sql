-- ============================================================================
-- EXTERNAL CUSTOMER QoS UNDER STRESS CONDITIONS
-- ============================================================================
-- Purpose: Analyze how EXTERNAL customer-facing QoS degrades during capacity
--          stress conditions (WARNING/CRITICAL states)
--
-- Scope: EXTERNAL customer-facing ONLY
--   INCLUDE: MONITOR (individual retailer projects)
--            HUB (Looker dashboards)
--   EXCLUDE: MONITOR_BASE (infrastructure, analyzed separately)
--
-- QoS Threshold: < 60 seconds (customer-facing SLA)
--
-- Method: Compare QoS metrics across stress states
--   - NORMAL: Baseline performance
--   - INFO: Light stress
--   - WARNING: Moderate stress  
--   - CRITICAL: Severe stress
--
-- Prerequisites: Run identify_capacity_stress_periods.sql first to generate stress states
--
-- Cost estimate: ~5-15GB (depends on periods)
-- Runtime estimate: 5-10 minutes
-- ============================================================================

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

-- Periods to analyze
DECLARE analyze_periods ARRAY<STRING> DEFAULT [
  'Peak_2024_2025',
  'Baseline_2025_Sep_Oct',
  'Peak_2023_2024'
];

-- EXTERNAL customer QoS threshold
DECLARE external_qos_threshold_seconds INT64 DEFAULT 60;

-- ============================================================================
-- MAIN ANALYSIS
-- ============================================================================

WITH
-- Get stress state timeline from first query
-- NOTE: This requires saving identify_capacity_stress_periods.sql output to a table
-- OR running it inline (expensive). For now, we'll recalculate stress states.

-- Simplified stress detection (hourly level for this query)
hourly_stress_state AS (
  SELECT
    analysis_period_label,
    TIMESTAMP_TRUNC(start_time, HOUR) AS hour_start,
    
    -- Estimate stress based on P95 execution time (proxy)
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS hour_p95_exec,
    
    -- Classify stress state
    CASE
      WHEN APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)] >= 3000 THEN 'CRITICAL'  -- ≥50 min
      WHEN APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)] >= 1200 THEN 'WARNING'   -- ≥20 min
      WHEN APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)] >= 360 THEN 'INFO'       -- ≥6 min
      ELSE 'NORMAL'
    END AS stress_state
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
  GROUP BY analysis_period_label, hour_start
),

-- Get EXTERNAL customer-facing jobs (exclude monitor-base)
external_customer_jobs AS (
  SELECT
    t.*,
    s.stress_state,
    s.hour_p95_exec,
    
    -- QoS evaluation
    CASE
      WHEN t.execution_time_seconds <= external_qos_threshold_seconds THEN 'QoS_MET'
      WHEN t.execution_time_seconds > external_qos_threshold_seconds THEN 'QoS_VIOLATION'
      ELSE 'QoS_UNKNOWN'
    END AS qos_result,
    
    -- Violation severity
    CASE
      WHEN t.execution_time_seconds > external_qos_threshold_seconds
        THEN t.execution_time_seconds - external_qos_threshold_seconds
      ELSE 0
    END AS violation_seconds
    
  FROM `narvar-data-lake.query_opt.traffic_classification` t
  INNER JOIN hourly_stress_state s
    ON t.analysis_period_label = s.analysis_period_label
    AND TIMESTAMP_TRUNC(t.start_time, HOUR) = s.hour_start
  
  WHERE (analyze_periods IS NULL OR t.analysis_period_label IN UNNEST(analyze_periods))
    AND t.consumer_category = 'EXTERNAL'
    AND t.consumer_subcategory IN ('MONITOR', 'HUB')  -- Exclude MONITOR_BASE
)

-- ============================================================================
-- OUTPUT: QoS Performance by Stress State
-- ============================================================================

SELECT
  analysis_period_label,
  stress_state,
  consumer_subcategory,
  
  -- Volume metrics
  COUNT(*) AS total_jobs,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER(PARTITION BY analysis_period_label) * 100, 2) AS pct_of_period,
  
  -- QoS metrics
  COUNTIF(qos_result = 'QoS_MET') AS qos_met,
  COUNTIF(qos_result = 'QoS_VIOLATION') AS qos_violations,
  ROUND(COUNTIF(qos_result = 'QoS_VIOLATION') / COUNT(*) * 100, 2) AS qos_violation_pct,
  
  -- Execution time distribution
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
  MAX(execution_time_seconds) AS max_execution_seconds,
  
  -- Violation severity
  ROUND(AVG(CASE WHEN qos_result = 'QoS_VIOLATION' THEN violation_seconds END), 2) AS avg_violation_seconds,
  ROUND(MAX(violation_seconds), 2) AS max_violation_seconds,
  
  -- Slot consumption
  ROUND(AVG(slot_hours), 4) AS avg_slot_hours_per_job,
  ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots,
  
  -- Unique attributes
  COUNT(DISTINCT retailer_moniker) AS unique_retailers,
  COUNT(DISTINCT principal_email) AS unique_principals

FROM external_customer_jobs
GROUP BY analysis_period_label, stress_state, consumer_subcategory
ORDER BY analysis_period_label, 
  CASE stress_state WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 WHEN 'INFO' THEN 3 ELSE 4 END,
  total_jobs DESC;

-- ============================================================================
-- STRESS IMPACT SUMMARY
-- ============================================================================
-- Uncomment for high-level summary across all periods
/*
SELECT
  stress_state,
  
  -- Aggregated metrics across all periods
  COUNT(*) AS total_jobs,
  ROUND(AVG(qos_violation_pct), 2) AS avg_violation_pct,
  ROUND(AVG(p95_execution_seconds), 2) AS avg_p95_exec_seconds,
  ROUND(AVG(p99_execution_seconds), 2) AS avg_p99_exec_seconds,
  
  -- Compare to NORMAL baseline
  ROUND(AVG(p95_execution_seconds) / NULLIF(MIN(CASE WHEN stress_state = 'NORMAL' THEN p95_execution_seconds END), 0), 2) AS p95_slowdown_vs_normal,
  ROUND(AVG(qos_violation_pct) / NULLIF(MIN(CASE WHEN stress_state = 'NORMAL' THEN qos_violation_pct END), 0), 2) AS violation_increase_vs_normal

FROM (
  SELECT
    stress_state,
    ROUND(COUNTIF(qos_result = 'QoS_VIOLATION') / COUNT(*) * 100, 2) AS qos_violation_pct,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds
  FROM external_customer_jobs
  GROUP BY stress_state
)
GROUP BY stress_state
ORDER BY CASE stress_state WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 WHEN 'INFO' THEN 3 ELSE 4 END;
*/

-- ============================================================================
-- DETAILED JOB-LEVEL OUTPUT (For Further Analysis)
-- ============================================================================
-- Uncomment to get job-level details for stress period investigation
/*
SELECT
  analysis_period_label,
  stress_state,
  job_id,
  project_id,
  retailer_moniker,
  start_time,
  execution_time_seconds,
  qos_result,
  violation_seconds,
  slot_hours,
  approximate_slot_count
  
FROM external_customer_jobs
WHERE stress_state IN ('WARNING', 'CRITICAL')
  AND qos_result = 'QoS_VIOLATION'
ORDER BY analysis_period_label, start_time, violation_seconds DESC;
*/

-- ============================================================================
-- USAGE NOTES
-- ============================================================================
--
-- This query analyzes EXTERNAL customer-facing QoS during stress conditions.
--
-- KEY FINDINGS TO LOOK FOR:
-- 1. QoS violation rate increase: NORMAL (2-5%) vs CRITICAL (??%)
-- 2. Execution time degradation: P95 during stress vs baseline
-- 3. Which stress state is most problematic
-- 4. Do violations cluster in specific hours/days?
--
-- LIMITATIONS:
-- - Uses hourly stress detection (not 10-minute for simplicity)
-- - For precise 10-minute stress analysis, join with identify_capacity_stress_periods results
-- - Excludes MONITOR_BASE (infrastructure, different SLA)
--
-- NEXT STEPS:
-- 1. Run to understand customer QoS degradation patterns
-- 2. Use findings to determine additional capacity needed
-- 3. Input to Phase 4 simulations (capacity scenarios)
-- ============================================================================

