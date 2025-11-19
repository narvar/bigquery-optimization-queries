-- ============================================================================
-- CAPACITY STRESS PERIOD IDENTIFICATION - TABLE CREATION
-- ============================================================================
-- This version creates the permanent table directly
-- ============================================================================

-- Periods to analyze
DECLARE analyze_periods ARRAY<STRING> DEFAULT [
  'Peak_2024_2025',
  'Baseline_2025_Sep_Oct',
  'Peak_2023_2024'
];

-- Stress detection thresholds
DECLARE info_concurrent_threshold INT64 DEFAULT 20;
DECLARE warning_concurrent_threshold INT64 DEFAULT 30;
DECLARE critical_concurrent_threshold INT64 DEFAULT 60;

DECLARE info_p95_threshold_seconds INT64 DEFAULT 360;
DECLARE warning_p95_threshold_seconds INT64 DEFAULT 1200;
DECLARE critical_p95_threshold_seconds INT64 DEFAULT 3000;

-- ============================================================================
-- CREATE THE OUTPUT TABLE
-- ============================================================================

CREATE OR REPLACE TABLE `narvar-data-lake.query_opt.phase2_stress_periods` AS

WITH
hourly_aggregates AS (
  SELECT
    analysis_period_label,
    DATE(start_time) AS date,
    EXTRACT(HOUR FROM start_time) AS hour,
    TIMESTAMP_TRUNC(start_time, HOUR) AS hour_start,
    
    COUNT(*) AS total_jobs,
    COUNT(DISTINCT principal_email) AS unique_principals,
    
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
    MAX(execution_time_seconds) AS max_execution_seconds,
    
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots,
    ROUND(MAX(approximate_slot_count), 2) AS max_concurrent_slots,
    
    COUNTIF(consumer_category = 'EXTERNAL') AS external_jobs,
    COUNTIF(consumer_category = 'AUTOMATED') AS automated_jobs,
    COUNTIF(consumer_category = 'INTERNAL') AS internal_jobs
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
  GROUP BY analysis_period_label, date, hour, hour_start
),

hourly_screening AS (
  SELECT
    *,
    CASE
      WHEN p95_execution_seconds >= critical_p95_threshold_seconds THEN 'POTENTIAL_CRITICAL'
      WHEN p95_execution_seconds >= warning_p95_threshold_seconds THEN 'POTENTIAL_WARNING'
      WHEN p95_execution_seconds >= info_p95_threshold_seconds THEN 'POTENTIAL_INFO'
      ELSE 'LIKELY_NORMAL'
    END AS screening_flag
  FROM hourly_aggregates
),

ten_minute_windows AS (
  SELECT
    h.analysis_period_label,
    h.date,
    h.hour,
    h.hour_start,
    h.screening_flag,
    TIMESTAMP_ADD(h.hour_start, INTERVAL window_offset MINUTE) AS window_start,
    TIMESTAMP_ADD(h.hour_start, INTERVAL window_offset + 10 MINUTE) AS window_end,
    window_offset AS window_number
  FROM hourly_screening h
  CROSS JOIN UNNEST([0, 10, 20, 30, 40, 50]) AS window_offset
  WHERE h.screening_flag != 'LIKELY_NORMAL'
),

concurrent_job_analysis AS (
  SELECT
    w.analysis_period_label,
    w.date,
    w.hour,
    w.window_start,
    w.window_end,
    w.window_number,
    w.screening_flag,
    
    COUNT(*) AS concurrent_jobs,
    
    COUNTIF(t.consumer_category = 'EXTERNAL') AS concurrent_external,
    COUNTIF(t.consumer_category = 'AUTOMATED') AS concurrent_automated,
    COUNTIF(t.consumer_category = 'INTERNAL') AS concurrent_internal,
    
    COUNTIF(t.consumer_subcategory = 'MONITOR_BASE') AS concurrent_monitor_base,
    COUNTIF(t.consumer_subcategory IN ('MONITOR', 'HUB')) AS concurrent_customer_facing,
    
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_execution_seconds,
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
    
    ROUND(SUM(t.approximate_slot_count), 2) AS total_concurrent_slots,
    ROUND(AVG(t.approximate_slot_count), 2) AS avg_slot_count,
    
    CASE
      WHEN COUNTIF(t.consumer_category = 'AUTOMATED') > COUNTIF(t.consumer_category = 'EXTERNAL') 
        AND COUNTIF(t.consumer_category = 'AUTOMATED') > COUNTIF(t.consumer_category = 'INTERNAL')
        THEN 'AUTOMATED'
      WHEN COUNTIF(t.consumer_category = 'EXTERNAL') > COUNTIF(t.consumer_category = 'INTERNAL')
        THEN 'EXTERNAL'
      ELSE 'INTERNAL'
    END AS dominant_category
    
  FROM ten_minute_windows w
  INNER JOIN `narvar-data-lake.query_opt.traffic_classification` t
    ON w.analysis_period_label = t.analysis_period_label
    AND t.start_time < w.window_end
    AND t.end_time > w.window_start
  GROUP BY 
    w.analysis_period_label, w.date, w.hour, w.window_start, w.window_end, 
    w.window_number, w.screening_flag
),

stress_classification AS (
  SELECT
    *,
    
    CASE
      WHEN concurrent_jobs >= critical_concurrent_threshold 
        OR p95_execution_seconds >= critical_p95_threshold_seconds
        THEN 'CRITICAL'
      WHEN concurrent_jobs >= warning_concurrent_threshold
        OR p95_execution_seconds >= warning_p95_threshold_seconds
        THEN 'WARNING'
      WHEN concurrent_jobs >= info_concurrent_threshold
        OR p95_execution_seconds >= info_p95_threshold_seconds
        THEN 'INFO'
      ELSE 'NORMAL'
    END AS stress_state,
    
    CASE
      WHEN concurrent_jobs >= critical_concurrent_threshold AND p95_execution_seconds >= critical_p95_threshold_seconds
        THEN 'BOTH_TRIGGERS'
      WHEN concurrent_jobs >= critical_concurrent_threshold
        THEN 'HIGH_CONCURRENCY'
      WHEN p95_execution_seconds >= critical_p95_threshold_seconds
        THEN 'SLOW_EXECUTION'
      ELSE NULL
    END AS trigger_reason
    
  FROM concurrent_job_analysis
),

normal_hours AS (
  SELECT
    analysis_period_label,
    date,
    hour,
    hour_start AS window_start,
    TIMESTAMP_ADD(hour_start, INTERVAL 1 HOUR) AS window_end,
    0 AS window_number,
    screening_flag,
    
    CAST(total_jobs / 6 AS INT64) AS concurrent_jobs,
    CAST(external_jobs / 6 AS INT64) AS concurrent_external,
    CAST(automated_jobs / 6 AS INT64) AS concurrent_automated,
    CAST(internal_jobs / 6 AS INT64) AS concurrent_internal,
    
    CAST(NULL AS INT64) AS concurrent_monitor_base,
    CAST(NULL AS INT64) AS concurrent_customer_facing,
    
    p50_execution_seconds,
    p95_execution_seconds,
    p99_execution_seconds,
    
    total_slot_hours AS total_concurrent_slots,
    avg_concurrent_slots AS avg_slot_count,
    
    CASE
      WHEN automated_jobs > external_jobs AND automated_jobs > internal_jobs THEN 'AUTOMATED'
      WHEN external_jobs > internal_jobs THEN 'EXTERNAL'
      ELSE 'INTERNAL'
    END AS dominant_category,
    
    'NORMAL' AS stress_state,
    CAST(NULL AS STRING) AS trigger_reason
    
  FROM hourly_screening
  WHERE screening_flag = 'LIKELY_NORMAL'
)

SELECT
  analysis_period_label,
  date,
  hour,
  window_start,
  window_end,
  EXTRACT(DAYOFWEEK FROM window_start) AS day_of_week,
  FORMAT_TIMESTAMP('%A', window_start) AS day_name,
  
  stress_state,
  trigger_reason,
  
  concurrent_jobs,
  concurrent_external,
  concurrent_automated,
  concurrent_internal,
  concurrent_monitor_base,
  concurrent_customer_facing,
  
  p50_execution_seconds,
  p95_execution_seconds,
  p99_execution_seconds,
  
  total_concurrent_slots,
  avg_slot_count,
  
  dominant_category,
  
  CASE WHEN window_number = 0 THEN TRUE ELSE FALSE END AS is_hourly_aggregate,
  screening_flag

FROM (
  SELECT * FROM stress_classification
  UNION ALL
  SELECT * FROM normal_hours
)
ORDER BY analysis_period_label, window_start;
