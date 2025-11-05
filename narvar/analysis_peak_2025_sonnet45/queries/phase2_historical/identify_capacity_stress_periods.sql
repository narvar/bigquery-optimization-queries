-- ============================================================================
-- CAPACITY STRESS PERIOD IDENTIFICATION
-- ============================================================================
-- Purpose: Identify when BigQuery capacity was under stress using production
--          monitoring thresholds (10-minute heartbeat analysis)
--
-- Method: Hybrid approach for computational efficiency:
--   Step 1: Hourly screening to identify potential stress periods
--   Step 2: 10-minute concurrent job analysis for identified stress hours
--   Step 3: Apply INFO/WARNING/CRITICAL thresholds from production monitoring
--
-- Thresholds (from production monitoring DAG):
--   INFO:     20-29 concurrent jobs OR P95 6-19 min
--   WARNING:  30-59 concurrent jobs OR P95 20-49 min
--   CRITICAL: ≥60 concurrent jobs OR P95 ≥50 min
--
-- Output: 10-minute window timeline with stress state classification
--
-- Cost estimate: ~10-30GB (depends on periods analyzed)
-- Runtime estimate: 15-30 minutes (concurrent job calculation is expensive)
-- ============================================================================

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

-- Periods to analyze (can filter to specific periods or analyze all)
DECLARE analyze_periods ARRAY<STRING> DEFAULT [
  'Peak_2024_2025',
  'Baseline_2025_Sep_Oct',
  'Peak_2023_2024'
  -- Add more periods as needed, or use NULL to analyze all
];

-- Stress detection thresholds (from production monitoring)
DECLARE info_concurrent_threshold INT64 DEFAULT 20;
DECLARE warning_concurrent_threshold INT64 DEFAULT 30;
DECLARE critical_concurrent_threshold INT64 DEFAULT 60;

DECLARE info_p95_threshold_seconds INT64 DEFAULT 360;      -- 6 minutes
DECLARE warning_p95_threshold_seconds INT64 DEFAULT 1200;  -- 20 minutes
DECLARE critical_p95_threshold_seconds INT64 DEFAULT 3000; -- 50 minutes

-- ============================================================================
-- STEP 1: HOURLY SCREENING - Identify potential stress periods
-- ============================================================================

WITH
-- First compute hourly aggregates
hourly_aggregates AS (
  SELECT
    analysis_period_label,
    DATE(start_time) AS date,
    EXTRACT(HOUR FROM start_time) AS hour,
    TIMESTAMP_TRUNC(start_time, HOUR) AS hour_start,
    
    -- Volume metrics
    COUNT(*) AS total_jobs,
    COUNT(DISTINCT principal_email) AS unique_principals,
    
    -- Execution time metrics (identify slow hours)
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
    MAX(execution_time_seconds) AS max_execution_seconds,
    
    -- Slot consumption
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots,
    ROUND(MAX(approximate_slot_count), 2) AS max_concurrent_slots,
    
    -- Category breakdown
    COUNTIF(consumer_category = 'EXTERNAL') AS external_jobs,
    COUNTIF(consumer_category = 'AUTOMATED') AS automated_jobs,
    COUNTIF(consumer_category = 'INTERNAL') AS internal_jobs
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
  GROUP BY analysis_period_label, date, hour, hour_start
),

-- Then apply screening flag based on computed percentiles
hourly_screening AS (
  SELECT
    *,
    -- Flag potential stress hours (for Step 2 detailed analysis)
    CASE
      WHEN p95_execution_seconds >= critical_p95_threshold_seconds THEN 'POTENTIAL_CRITICAL'
      WHEN p95_execution_seconds >= warning_p95_threshold_seconds THEN 'POTENTIAL_WARNING'
      WHEN p95_execution_seconds >= info_p95_threshold_seconds THEN 'POTENTIAL_INFO'
      ELSE 'LIKELY_NORMAL'
    END AS screening_flag
  FROM hourly_aggregates
),

-- ============================================================================
-- STEP 2: 10-MINUTE CONCURRENT JOB ANALYSIS
-- ============================================================================
-- Only analyze hours flagged as potential stress (optimization)

-- Generate 10-minute time windows for stress hours only
ten_minute_windows AS (
  SELECT
    h.analysis_period_label,
    h.date,
    h.hour,
    h.hour_start,
    h.screening_flag,
    -- Generate 6 windows per hour (10-minute intervals)
    TIMESTAMP_ADD(h.hour_start, INTERVAL window_offset MINUTE) AS window_start,
    TIMESTAMP_ADD(h.hour_start, INTERVAL window_offset + 10 MINUTE) AS window_end,
    window_offset AS window_number
  FROM hourly_screening h
  CROSS JOIN UNNEST([0, 10, 20, 30, 40, 50]) AS window_offset
  WHERE h.screening_flag != 'LIKELY_NORMAL'  -- Only analyze flagged hours
),

-- Calculate concurrent jobs for each 10-minute window
concurrent_job_analysis AS (
  SELECT
    w.analysis_period_label,
    w.date,
    w.hour,
    w.window_start,
    w.window_end,
    w.window_number,
    w.screening_flag,
    
    -- Count jobs that overlap with this window
    -- Job is concurrent if: job.start_time < window.end AND job.end_time > window.start
    COUNT(*) AS concurrent_jobs,
    
    -- Concurrent jobs by category
    COUNTIF(t.consumer_category = 'EXTERNAL') AS concurrent_external,
    COUNTIF(t.consumer_category = 'AUTOMATED') AS concurrent_automated,
    COUNTIF(t.consumer_category = 'INTERNAL') AS concurrent_internal,
    
    -- EXTERNAL sub-breakdown
    COUNTIF(t.consumer_subcategory = 'MONITOR_BASE') AS concurrent_monitor_base,
    COUNTIF(t.consumer_subcategory IN ('MONITOR', 'HUB')) AS concurrent_customer_facing,
    
    -- Execution time percentiles for jobs in this window
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_execution_seconds,
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
    
    -- Slot consumption during window
    ROUND(SUM(t.approximate_slot_count), 2) AS total_concurrent_slots,
    ROUND(AVG(t.approximate_slot_count), 2) AS avg_slot_count,
    
    -- Dominant category (which category has most concurrent jobs)
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
    -- Job overlaps window if it starts before window ends AND ends after window starts
    AND t.start_time < w.window_end
    AND t.end_time > w.window_start
  GROUP BY 
    w.analysis_period_label, w.date, w.hour, w.window_start, w.window_end, 
    w.window_number, w.screening_flag
),

-- ============================================================================
-- STEP 3: APPLY STRESS STATE CLASSIFICATION
-- ============================================================================

stress_classification AS (
  SELECT
    *,
    
    -- Apply production monitoring thresholds
    CASE
      -- CRITICAL: ≥60 concurrent jobs OR P95 ≥50 min
      WHEN concurrent_jobs >= critical_concurrent_threshold 
        OR p95_execution_seconds >= critical_p95_threshold_seconds
        THEN 'CRITICAL'
      
      -- WARNING: 30-59 concurrent jobs OR P95 20-49 min
      WHEN concurrent_jobs >= warning_concurrent_threshold
        OR p95_execution_seconds >= warning_p95_threshold_seconds
        THEN 'WARNING'
      
      -- INFO: 20-29 concurrent jobs OR P95 6-19 min
      WHEN concurrent_jobs >= info_concurrent_threshold
        OR p95_execution_seconds >= info_p95_threshold_seconds
        THEN 'INFO'
      
      -- NORMAL: Below all thresholds
      ELSE 'NORMAL'
    END AS stress_state,
    
    -- Identify the trigger (what caused the state)
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

-- ============================================================================
-- Add back NORMAL hours (from hourly screening) for complete timeline
-- ============================================================================

normal_hours AS (
  SELECT
    analysis_period_label,
    date,
    hour,
    hour_start AS window_start,
    TIMESTAMP_ADD(hour_start, INTERVAL 1 HOUR) AS window_end,
    0 AS window_number,  -- Aggregate hour, not 10-min window
    screening_flag,
    
    -- Use hourly estimates for NORMAL periods (not precise concurrent count)
    CAST(total_jobs / 6 AS INT64) AS concurrent_jobs,  -- Rough estimate: jobs/hour ÷ 6 windows
    CAST(external_jobs / 6 AS INT64) AS concurrent_external,
    CAST(automated_jobs / 6 AS INT64) AS concurrent_automated,
    CAST(internal_jobs / 6 AS INT64) AS concurrent_internal,
    
    -- No detailed breakdown for NORMAL hours (optimization)
    CAST(NULL AS INT64) AS concurrent_monitor_base,
    CAST(NULL AS INT64) AS concurrent_customer_facing,
    
    -- Use hourly percentiles
    p50_execution_seconds,
    p95_execution_seconds,
    p99_execution_seconds,
    
    total_slot_hours AS total_concurrent_slots,
    avg_concurrent_slots AS avg_slot_count,
    
    -- Dominant category based on job counts
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

-- ============================================================================
-- FINAL OUTPUT: Combined timeline with stress states
-- ============================================================================

SELECT
  -- Time identifiers
  analysis_period_label,
  date,
  hour,
  window_start,
  window_end,
  EXTRACT(DAYOFWEEK FROM window_start) AS day_of_week,
  FORMAT_TIMESTAMP('%A', window_start) AS day_name,
  
  -- Stress state classification
  stress_state,
  trigger_reason,
  
  -- Concurrent job metrics
  concurrent_jobs,
  concurrent_external,
  concurrent_automated,
  concurrent_internal,
  concurrent_monitor_base,
  concurrent_customer_facing,
  
  -- Execution time metrics
  p50_execution_seconds,
  p95_execution_seconds,
  p99_execution_seconds,
  
  -- Slot metrics
  total_concurrent_slots,
  avg_slot_count,
  
  -- Attribution
  dominant_category,
  
  -- Helper flags
  CASE WHEN window_number = 0 THEN TRUE ELSE FALSE END AS is_hourly_aggregate,
  screening_flag

FROM (
  SELECT * FROM stress_classification
  UNION ALL
  SELECT * FROM normal_hours
)
ORDER BY analysis_period_label, window_start;

-- ============================================================================
-- SUMMARY STATISTICS BY STRESS STATE
-- ============================================================================
-- Uncomment to get summary instead of detailed timeline
/*
SELECT
  analysis_period_label,
  stress_state,
  
  -- Frequency metrics
  COUNT(*) AS window_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER(PARTITION BY analysis_period_label) * 100, 2) AS pct_of_time,
  
  -- Duration metrics
  ROUND(COUNT(*) * 10 / 60, 2) AS total_hours,  -- 10-min windows → hours
  ROUND(AVG(concurrent_jobs), 0) AS avg_concurrent_jobs,
  ROUND(MAX(concurrent_jobs), 0) AS max_concurrent_jobs,
  
  -- Performance during stress
  ROUND(AVG(p95_execution_seconds), 2) AS avg_p95_exec_seconds,
  ROUND(MAX(p95_execution_seconds), 2) AS max_p95_exec_seconds,
  
  -- Category attribution
  ROUND(AVG(concurrent_monitor_base), 0) AS avg_concurrent_monitor_base,
  ROUND(AVG(concurrent_customer_facing), 0) AS avg_concurrent_customer_facing,
  
  -- Slot consumption
  ROUND(AVG(total_concurrent_slots), 0) AS avg_concurrent_slots,
  ROUND(MAX(total_concurrent_slots), 0) AS max_concurrent_slots

FROM (
  SELECT * FROM stress_classification
  -- Exclude hourly aggregates from summary (only use 10-min windows)
  WHERE window_number != 0
)
GROUP BY analysis_period_label, stress_state
ORDER BY analysis_period_label, 
  CASE stress_state 
    WHEN 'CRITICAL' THEN 1 
    WHEN 'WARNING' THEN 2 
    WHEN 'INFO' THEN 3 
    ELSE 4 
  END;
*/

-- ============================================================================
-- TIME-OF-DAY STRESS PATTERNS
-- ============================================================================
-- Uncomment to see when stress occurs (hour of day, day of week)
/*
SELECT
  stress_state,
  hour,
  day_name,
  
  COUNT(*) AS occurrences,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER(PARTITION BY stress_state) * 100, 2) AS pct_of_stress_state,
  ROUND(AVG(concurrent_jobs), 0) AS avg_concurrent_jobs,
  ROUND(AVG(p95_execution_seconds), 2) AS avg_p95_exec_seconds

FROM stress_classification
WHERE stress_state IN ('WARNING', 'CRITICAL')
GROUP BY stress_state, hour, day_name
ORDER BY stress_state, occurrences DESC;
*/

-- ============================================================================
-- STRESS EVENT CLUSTERING
-- ============================================================================
-- Group consecutive stress windows into "events" for duration analysis
/*
WITH stress_events AS (
  SELECT
    *,
    -- Detect event boundaries (stress → normal or normal → stress)
    CASE 
      WHEN stress_state IN ('WARNING', 'CRITICAL') 
        AND LAG(stress_state) OVER(PARTITION BY analysis_period_label ORDER BY window_start) NOT IN ('WARNING', 'CRITICAL')
        THEN 1
      ELSE 0
    END AS is_event_start,
    
  FROM stress_classification
  WHERE stress_state IN ('WARNING', 'CRITICAL')
),

events_numbered AS (
  SELECT
    *,
    SUM(is_event_start) OVER(PARTITION BY analysis_period_label ORDER BY window_start) AS event_id
  FROM stress_events
)

SELECT
  analysis_period_label,
  event_id,
  MIN(window_start) AS event_start,
  MAX(window_end) AS event_end,
  COUNT(*) AS window_count,
  ROUND(COUNT(*) * 10 / 60, 2) AS event_duration_hours,
  
  -- Event severity
  MAX(CASE stress_state WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END) AS max_severity,
  CASE MAX(CASE stress_state WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END)
    WHEN 1 THEN 'CRITICAL'
    WHEN 2 THEN 'WARNING'
    ELSE 'INFO'
  END AS event_severity,
  
  -- Event characteristics
  ROUND(AVG(concurrent_jobs), 0) AS avg_concurrent_jobs,
  MAX(concurrent_jobs) AS peak_concurrent_jobs,
  ROUND(AVG(p95_execution_seconds), 2) AS avg_p95_exec_seconds,
  MAX(p95_execution_seconds) AS max_p95_exec_seconds,
  
  -- Attribution
  APPROX_TOP_COUNT(dominant_category, 1)[OFFSET(0)].value AS primary_category

FROM events_numbered
GROUP BY analysis_period_label, event_id
ORDER BY analysis_period_label, event_start;
*/

-- ============================================================================
-- USAGE NOTES
-- ============================================================================
-- 
-- This query identifies capacity stress periods using production monitoring logic.
-- 
-- OUTPUT MODES (uncomment desired section):
-- 1. Detailed timeline: 10-minute windows with stress states (default)
-- 2. Summary statistics: % time in each state, avg metrics
-- 3. Time-of-day patterns: When stress occurs (hour, day of week)
-- 4. Stress events: Clustered consecutive stress windows
--
-- PERFORMANCE:
-- - Hourly screening: Fast (~1-2 min for all periods)
-- - 10-minute concurrent analysis: Expensive (15-30 min for stress periods)
-- - Optimization: Only calculates 10-min windows for flagged hours
--
-- THRESHOLDS:
-- - Based on production monitoring DAG (query_opt_monitor_bq_load.py)
-- - INFO: 20 jobs OR P95 6 min
-- - WARNING: 30 jobs OR P95 20 min  
-- - CRITICAL: 60 jobs OR P95 50 min
--
-- NEXT STEPS:
-- 1. Run this query to generate stress timeline
-- 2. Use output in external_qos_under_stress.sql (join on window times)
-- 3. Use output in monitor_base_stress_analysis.sql (causation analysis)
-- ============================================================================



