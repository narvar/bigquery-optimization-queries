-- ============================================================================
-- MONITOR_BASE STRESS ANALYSIS
-- ============================================================================
-- Purpose: Two-part analysis of monitor-base infrastructure workload:
--   Part A: Separate QoS tracking (30-minute SLA, infrastructure workload)
--   Part B: Causation analysis (does monitor-base CAUSE customer QoS stress?)
--
-- Context: monitor-base is shared infrastructure serving all retailers
--   - Consumes 85% of EXTERNAL slot capacity (8.74M slot-hours!)
--   - Continuous batch processing (new batch starts when prior completes)
--   - Cannot be deprioritized (provides "as fresh as possible" data)
--   - Different SLA than customer-facing (30 min vs 60 sec)
--
-- Key Questions:
--   1. Does monitor-base meet its 30-minute SLA?
--   2. When does monitor-base run (time-of-day patterns)?
--   3. Does monitor-base running correlate with customer QoS violations?
--   4. Does monitor-base cause capacity stress (slot starvation)?
--
-- Cost estimate: ~10-20GB
-- Runtime estimate: 10-15 minutes
-- ============================================================================

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

DECLARE analyze_periods ARRAY<STRING> DEFAULT [
  'Peak_2024_2025',
  'Baseline_2025_Sep_Oct',
  'Peak_2023_2024'
];

-- QoS thresholds
DECLARE monitor_base_qos_threshold_seconds INT64 DEFAULT 1800;  -- 30 minutes
DECLARE customer_qos_threshold_seconds INT64 DEFAULT 60;        -- 60 seconds

-- ============================================================================
-- PART A: MONITOR_BASE SEPARATE QoS TRACKING
-- ============================================================================

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
    
    -- QoS evaluation (30-minute threshold)
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
    
    -- Time classification
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
    
    -- Volume
    COUNT(*) AS total_jobs,
    ROUND(SUM(slot_hours), 0) AS total_slot_hours,
    
    -- QoS metrics
    COUNTIF(qos_result = 'QoS_MET') AS qos_met,
    COUNTIF(qos_result = 'QoS_VIOLATION') AS qos_violations,
    ROUND(COUNTIF(qos_result = 'QoS_VIOLATION') / COUNT(*) * 100, 2) AS qos_violation_pct,
    
    -- Execution time distribution
    ROUND(AVG(execution_time_seconds), 2) AS avg_exec_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_exec_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_exec_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_exec_seconds,
    
    -- Violation severity
    ROUND(AVG(violation_seconds), 2) AS avg_violation_seconds,
    MAX(violation_seconds) AS max_violation_seconds,
    
    -- Slot consumption
    ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count,
    MAX(approximate_slot_count) AS max_slot_count
    
  FROM monitor_base_jobs
  GROUP BY analysis_period_label
),

-- ============================================================================
-- PART B: CAUSATION ANALYSIS - Does monitor-base CAUSE customer stress?
-- ============================================================================

-- Step 1: Time-of-day patterns (when does monitor-base run?)
monitor_base_hourly_pattern AS (
  SELECT
    hour_of_day,
    day_name,
    
    COUNT(*) AS jobs,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 2) AS pct_of_total,
    ROUND(AVG(execution_time_seconds), 0) AS avg_exec_seconds,
    ROUND(SUM(slot_hours), 0) AS total_slot_hours
    
  FROM monitor_base_jobs
  GROUP BY hour_of_day, day_name
),

-- Step 2: Get customer-facing jobs for correlation
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

-- Step 3: Hourly overlap analysis
hourly_overlap AS (
  SELECT
    TIMESTAMP_TRUNC(mb.start_time, HOUR) AS hour_start,
    mb.analysis_period_label,
    
    -- monitor-base activity in this hour
    COUNT(DISTINCT mb.job_id) AS monitor_base_jobs,
    ROUND(SUM(mb.slot_hours), 2) AS monitor_base_slot_hours,
    ROUND(AVG(mb.approximate_slot_count), 2) AS monitor_base_avg_concurrent_slots,
    
    -- Customer activity in this hour
    COUNT(DISTINCT cf.start_time) AS customer_jobs,
    SUM(cf.is_violation) AS customer_violations,
    ROUND(SUM(cf.is_violation) / COUNT(DISTINCT cf.start_time) * 100, 2) AS customer_violation_pct
    
  FROM monitor_base_jobs mb
  LEFT JOIN customer_facing_jobs cf
    ON mb.analysis_period_label = cf.analysis_period_label
    AND TIMESTAMP_TRUNC(cf.start_time, HOUR) = TIMESTAMP_TRUNC(mb.start_time, HOUR)
  GROUP BY hour_start, mb.analysis_period_label
),

-- Step 4: Correlation analysis
causation_analysis AS (
  SELECT
    analysis_period_label,
    
    -- Categorize hours by monitor-base activity level
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

-- ============================================================================
-- FINAL OUTPUT: Combined Analysis
-- ============================================================================

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

-- ============================================================================
-- ALTERNATIVE OUTPUT: SIMPLIFIED CAUSATION TEST
-- ============================================================================
-- Uncomment for cleaner causation hypothesis testing
/*
SELECT
  analysis_period_label,
  monitor_base_intensity,
  
  -- Sample size
  COUNT(*) AS hour_count,
  
  -- monitor-base metrics
  ROUND(AVG(monitor_base_slot_hours), 0) AS avg_monitor_base_slot_hrs,
  ROUND(AVG(monitor_base_avg_concurrent_slots), 0) AS avg_monitor_base_concurrent_slots,
  
  -- Customer impact metrics
  ROUND(AVG(customer_jobs), 0) AS avg_customer_jobs,
  ROUND(AVG(customer_violations), 0) AS avg_customer_violations,
  ROUND(AVG(customer_violation_pct), 2) AS avg_customer_violation_pct,
  
  -- Statistical test: Is there a difference in customer violations?
  ROUND(
    AVG(customer_violation_pct) / 
    NULLIF(MIN(CASE WHEN monitor_base_intensity = 'LOW_MONITOR_BASE' THEN customer_violation_pct END), 0), 
    2
  ) AS violation_ratio_vs_low_monitor_base

FROM causation_analysis
GROUP BY analysis_period_label, monitor_base_intensity
ORDER BY analysis_period_label, monitor_base_intensity;
*/

-- ============================================================================
-- TIME-OF-DAY PATTERNS
-- ============================================================================
-- Uncomment to see when monitor-base runs (continuous batch analysis)
/*
SELECT
  hour_of_day,
  day_name,
  jobs AS monitor_base_jobs,
  pct_of_total,
  avg_exec_seconds,
  total_slot_hours
FROM monitor_base_hourly_pattern
ORDER BY hour_of_day, day_name;
*/

-- ============================================================================
-- USAGE NOTES
-- ============================================================================
--
-- PART A: MONITOR_BASE QoS PERFORMANCE
-- - Evaluates monitor-base against 30-minute SLA (infrastructure workload)
-- - Shows violation rates, execution times, slot consumption
-- - Different from customer-facing 60-second SLA
--
-- PART B: CAUSATION ANALYSIS
-- Tests hypothesis: "monitor-base causes customer QoS degradation"
--
-- Method:
-- 1. Categorize hours by monitor-base intensity (HIGH/MEDIUM/LOW slot consumption)
-- 2. Measure customer violation rates in each category
-- 3. Compare: Do customer violations increase when monitor-base is heavy?
--
-- Interpretation:
-- - If customer_violation_pct is similar across HIGH/MEDIUM/LOW monitor-base
--   → monitor-base does NOT cause customer stress (capacity is sufficient)
--
-- - If customer_violation_pct is significantly higher during HIGH monitor-base
--   → monitor-base competes for slots with customers (capacity issue)
--   → Recommendation: Separate reservation or off-peak scheduling
--
-- KEY FINDINGS TO LOOK FOR:
-- 1. monitor-base QoS: Is 30-min SLA being met?
-- 2. Time patterns: Does monitor-base run 24/7 or peak at certain hours?
-- 3. Correlation: customer_violation_pct during HIGH vs LOW monitor-base
-- 4. Slot competition: Total concurrent slots when both run simultaneously
--
-- NEXT STEPS:
-- 1. Run to understand monitor-base patterns and customer impact
-- 2. If causation found: Recommend separate reservation or scheduling changes
-- 3. If no causation: Focus optimization elsewhere (other categories causing stress)
-- ============================================================================

