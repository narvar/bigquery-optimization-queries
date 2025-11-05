-- ============================================================================
-- MONITOR_BASE STRESS ANALYSIS - TABLE CREATION
-- ============================================================================

DECLARE analyze_periods ARRAY<STRING> DEFAULT [
  'Peak_2024_2025',
  'Baseline_2025_Sep_Oct',
  'Peak_2023_2024'
];

DECLARE monitor_base_qos_threshold_seconds INT64 DEFAULT 1800;  -- 30 minutes
DECLARE customer_qos_threshold_seconds INT64 DEFAULT 60;

-- ============================================================================
-- CREATE THE OUTPUT TABLE
-- ============================================================================

CREATE OR REPLACE TABLE `narvar-data-lake.query_opt.phase2_monitor_base` AS

WITH
monitor_base_jobs AS (
  SELECT
    analysis_period_label,
    job_id,
    project_id,
    start_time,
    end_time,
    execution_time_seconds,
    slot_hours,
    approximate_slot_count,
    
    CASE
      WHEN execution_time_seconds <= monitor_base_qos_threshold_seconds THEN 'QoS_MET'
      WHEN execution_time_seconds > monitor_base_qos_threshold_seconds THEN 'QoS_VIOLATION'
      ELSE 'QoS_UNKNOWN'
    END AS qos_result,
    
    CASE
      WHEN execution_time_seconds > monitor_base_qos_threshold_seconds
        THEN execution_time_seconds - monitor_base_qos_threshold_seconds
      ELSE 0
    END AS violation_seconds,
    
    EXTRACT(HOUR FROM start_time) AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM start_time) AS day_of_week,
    FORMAT_TIMESTAMP('%A', start_time) AS day_name
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
    AND consumer_subcategory = 'MONITOR_BASE'
),

monitor_base_qos_summary AS (
  SELECT
    analysis_period_label,
    
    COUNT(*) AS total_jobs,
    ROUND(SUM(slot_hours), 0) AS total_slot_hours,
    
    COUNTIF(qos_result = 'QoS_MET') AS qos_met,
    COUNTIF(qos_result = 'QoS_VIOLATION') AS qos_violations,
    ROUND(COUNTIF(qos_result = 'QoS_VIOLATION') / COUNT(*) * 100, 2) AS qos_violation_pct,
    
    ROUND(AVG(execution_time_seconds), 2) AS avg_exec_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_exec_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_exec_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_exec_seconds,
    
    ROUND(AVG(violation_seconds), 2) AS avg_violation_seconds,
    MAX(violation_seconds) AS max_violation_seconds,
    
    ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count,
    MAX(approximate_slot_count) AS max_slot_count
    
  FROM monitor_base_jobs
  GROUP BY analysis_period_label
),

customer_facing_jobs AS (
  SELECT
    analysis_period_label,
    start_time,
    end_time,
    execution_time_seconds,
    CASE
      WHEN execution_time_seconds > customer_qos_threshold_seconds THEN 1
      ELSE 0
    END AS is_violation
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
    AND consumer_category = 'EXTERNAL'
    AND consumer_subcategory IN ('MONITOR', 'HUB')
),

hourly_overlap AS (
  SELECT
    TIMESTAMP_TRUNC(mb.start_time, HOUR) AS hour_start,
    mb.analysis_period_label,
    
    COUNT(DISTINCT mb.job_id) AS monitor_base_jobs,
    ROUND(SUM(mb.slot_hours), 2) AS monitor_base_slot_hours,
    ROUND(AVG(mb.approximate_slot_count), 2) AS monitor_base_avg_concurrent_slots,
    
    COUNT(DISTINCT cf.start_time) AS customer_jobs,
    SUM(cf.is_violation) AS customer_violations,
    ROUND(SUM(cf.is_violation) / NULLIF(COUNT(DISTINCT cf.start_time), 0) * 100, 2) AS customer_violation_pct
    
  FROM monitor_base_jobs mb
  LEFT JOIN customer_facing_jobs cf
    ON mb.analysis_period_label = cf.analysis_period_label
    AND TIMESTAMP_TRUNC(cf.start_time, HOUR) = TIMESTAMP_TRUNC(mb.start_time, HOUR)
  GROUP BY hour_start, mb.analysis_period_label
),

causation_analysis AS (
  SELECT
    analysis_period_label,
    
    CASE
      WHEN monitor_base_slot_hours > PERCENTILE_CONT(monitor_base_slot_hours, 0.75) OVER(PARTITION BY analysis_period_label) 
        THEN 'HIGH_MONITOR_BASE'
      WHEN monitor_base_slot_hours > PERCENTILE_CONT(monitor_base_slot_hours, 0.25) OVER(PARTITION BY analysis_period_label)
        THEN 'MEDIUM_MONITOR_BASE'
      ELSE 'LOW_MONITOR_BASE'
    END AS monitor_base_intensity,
    
    monitor_base_jobs,
    monitor_base_slot_hours,
    monitor_base_avg_concurrent_slots,
    customer_jobs,
    customer_violations,
    customer_violation_pct
    
  FROM hourly_overlap
)

SELECT
  'PART A: MONITOR_BASE QoS PERFORMANCE' AS analysis_section,
  analysis_period_label,
  total_jobs,
  total_slot_hours,
  qos_met,
  qos_violations,
  qos_violation_pct,
  p50_exec_seconds,
  p95_exec_seconds,
  p99_exec_seconds,
  avg_violation_seconds,
  max_violation_seconds,
  avg_slot_count,
  max_slot_count,
  CAST(NULL AS STRING) AS monitor_base_intensity,
  CAST(NULL AS INT64) AS monitor_base_concurrent_jobs,
  CAST(NULL AS FLOAT64) AS monitor_base_concurrent_slot_hours,
  CAST(NULL AS INT64) AS customer_concurrent_jobs,
  CAST(NULL AS INT64) AS customer_concurrent_violations,
  CAST(NULL AS FLOAT64) AS customer_concurrent_violation_pct
  
FROM monitor_base_qos_summary

UNION ALL

SELECT
  'PART B: CAUSATION - Customer QoS vs monitor-base Activity' AS analysis_section,
  analysis_period_label,
  CAST(NULL AS INT64) AS total_jobs,
  CAST(NULL AS FLOAT64) AS total_slot_hours,
  CAST(NULL AS INT64) AS qos_met,
  CAST(NULL AS INT64) AS qos_violations,
  CAST(NULL AS FLOAT64) AS qos_violation_pct,
  CAST(NULL AS FLOAT64) AS p50_exec_seconds,
  CAST(NULL AS FLOAT64) AS p95_exec_seconds,
  CAST(NULL AS FLOAT64) AS p99_exec_seconds,
  CAST(NULL AS FLOAT64) AS avg_violation_seconds,
  CAST(NULL AS FLOAT64) AS max_violation_seconds,
  CAST(NULL AS FLOAT64) AS avg_slot_count,
  CAST(NULL AS FLOAT64) AS max_slot_count,
  monitor_base_intensity,
  CAST(AVG(monitor_base_jobs) AS INT64) AS monitor_base_concurrent_jobs,
  AVG(monitor_base_slot_hours) AS monitor_base_concurrent_slot_hours,
  CAST(AVG(customer_jobs) AS INT64) AS customer_concurrent_jobs,
  CAST(AVG(customer_violations) AS INT64) AS customer_concurrent_violations,
  AVG(customer_violation_pct) AS customer_concurrent_violation_pct
  
FROM causation_analysis
GROUP BY analysis_section, analysis_period_label, monitor_base_intensity

ORDER BY analysis_section, analysis_period_label;

