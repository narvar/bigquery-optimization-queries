-- ============================================================================
-- PEAK VS NON-PEAK TRAFFIC ANALYSIS (Updated for Physical Table)
-- ============================================================================
-- Purpose: Compare overall traffic patterns between peak (Nov-Jan) and
--          non-peak periods to understand:
--          - Peak multipliers by category
--          - Hour-of-day and day-of-week patterns
--          - Resource consumption differences
--          - Growth trends year-over-year
--
-- Method: Uses pre-classified traffic_classification table (Phase 1 output)
--         Hourly granularity for overall patterns (Track 1)
--
-- Covers: 9 periods (Sep 2022 - Oct 2025), 21 months
--
-- Cost estimate: ~1-5GB (queries classified table, not raw audit logs!)
-- Runtime estimate: 2-5 minutes (much faster than inline classification)
-- ============================================================================

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

-- Analyze all periods or filter to specific ones
DECLARE analyze_periods ARRAY<STRING> DEFAULT NULL;  -- NULL = all periods

-- ============================================================================
-- MAIN ANALYSIS
-- ============================================================================

CREATE OR REPLACE TEMP TABLE hourly_patterns AS
WITH
-- Classify periods as PEAK or NON_PEAK
period_classification AS (
  SELECT DISTINCT
    analysis_period_label,
    CASE 
      WHEN analysis_period_label LIKE 'Peak%' THEN 'PEAK'
      ELSE 'NON_PEAK'
    END AS period_type,
    analysis_start_date,
    analysis_end_date,
    DATE_DIFF(analysis_end_date, analysis_start_date, DAY) AS period_days
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
),

-- Hourly aggregation (Track 1: Overall patterns)
hourly_patterns AS (
  SELECT
    t.analysis_period_label,
    pc.period_type,
    DATE(t.start_time) AS date,
    EXTRACT(HOUR FROM t.start_time) AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM t.start_time) AS day_of_week,
    FORMAT_TIMESTAMP('%A', t.start_time) AS day_name,
    
    -- Consumer category breakdown
    t.consumer_category,
    t.consumer_subcategory,
    
    -- Volume metrics
    COUNT(*) AS jobs,
    COUNT(DISTINCT t.principal_email) AS unique_principals,
    COUNT(DISTINCT t.project_id) AS unique_projects,
    COUNT(DISTINCT t.retailer_moniker) AS unique_retailers,
    
    -- Execution time metrics
    ROUND(AVG(t.execution_time_seconds), 2) AS avg_exec_seconds,
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_exec_seconds,
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_exec_seconds,
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_exec_seconds,
    
    -- Slot consumption
    ROUND(SUM(t.slot_hours), 2) AS total_slot_hours,
    ROUND(AVG(t.slot_hours), 4) AS avg_slot_hours_per_job,
    ROUND(AVG(t.approximate_slot_count), 2) AS avg_concurrent_slots,
    
    -- Cost
    ROUND(SUM(t.estimated_slot_cost_usd), 2) AS total_cost_usd,
    
    -- QoS metrics
    COUNTIF(t.is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(t.is_qos_violation) / NULLIF(COUNTIF(t.qos_status IN ('QoS_MET', 'QoS_VIOLATION')), 0) * 100, 2) AS qos_violation_pct
    
  FROM `narvar-data-lake.query_opt.traffic_classification` t
  INNER JOIN period_classification pc USING (analysis_period_label)
  WHERE (analyze_periods IS NULL OR t.analysis_period_label IN UNNEST(analyze_periods))
  GROUP BY 
    t.analysis_period_label, pc.period_type, date, hour_of_day, 
    day_of_week, day_name, t.consumer_category, t.consumer_subcategory
)
SELECT * FROM hourly_patterns;

-- ============================================================================
-- OUTPUT 1: Peak vs Non-Peak Summary by Category
-- ============================================================================

SELECT -- OUTPUT 1: Peak vs Non-Peak Summary by Category
  period_type,
  consumer_category,
  consumer_subcategory,
  
  -- Volume metrics
  SUM(jobs) AS total_jobs,
  ROUND(SUM(jobs) / SUM(SUM(jobs)) OVER(PARTITION BY period_type) * 100, 2) AS pct_of_period_jobs,
  COUNT(DISTINCT analysis_period_label) AS num_periods,
  ROUND(SUM(jobs) / COUNT(DISTINCT analysis_period_label), 0) AS avg_jobs_per_period,
  
  -- Execution time
  ROUND(AVG(avg_exec_seconds), 2) AS avg_exec_seconds,
  ROUND(AVG(p95_exec_seconds), 2) AS avg_p95_exec_seconds,
  ROUND(AVG(p99_exec_seconds), 2) AS avg_p99_exec_seconds,
  
  -- Slot consumption
  ROUND(SUM(total_slot_hours), 0) AS total_slot_hours,
  ROUND(SUM(total_slot_hours) / SUM(SUM(total_slot_hours)) OVER(PARTITION BY period_type) * 100, 2) AS pct_of_period_slots,
  ROUND(SUM(total_slot_hours) / COUNT(DISTINCT analysis_period_label), 0) AS avg_slot_hours_per_period,
  ROUND(AVG(avg_slot_hours_per_job), 4) AS avg_slot_hours_per_job,
  
  -- Cost
  ROUND(SUM(total_cost_usd), 0) AS total_cost_usd,
  
  -- QoS
  ROUND(AVG(qos_violation_pct), 2) AS avg_qos_violation_pct
  
FROM hourly_patterns
GROUP BY period_type, consumer_category, consumer_subcategory
ORDER BY period_type, total_slot_hours DESC;

-- ============================================================================
-- OUTPUT 2: Peak Multipliers (Peak vs Non-Peak Ratios)
-- ============================================================================
-- Uncomment to see peak multipliers by category

WITH peak_summary AS ( -- OUTPUT 2: Peak Multipliers (Peak vs Non-Peak Ratios)
  SELECT
    consumer_category,
    SUM(jobs) / COUNT(DISTINCT analysis_period_label) AS avg_jobs_per_peak_period,
    SUM(total_slot_hours) / COUNT(DISTINCT analysis_period_label) AS avg_slot_hours_per_peak_period
  FROM hourly_patterns
  WHERE period_type = 'PEAK'
  GROUP BY consumer_category
),
nonpeak_summary AS (
  SELECT
    consumer_category,
    SUM(jobs) / COUNT(DISTINCT analysis_period_label) AS avg_jobs_per_nonpeak_period,
    SUM(total_slot_hours) / COUNT(DISTINCT analysis_period_label) AS avg_slot_hours_per_nonpeak_period
  FROM hourly_patterns
  WHERE period_type = 'NON_PEAK'
  GROUP BY consumer_category
)

SELECT
  COALESCE(p.consumer_category, n.consumer_category) AS consumer_category,
  ROUND(n.avg_jobs_per_nonpeak_period, 0) AS avg_jobs_nonpeak,
  ROUND(p.avg_jobs_per_peak_period, 0) AS avg_jobs_peak,
  ROUND(p.avg_jobs_per_peak_period / NULLIF(n.avg_jobs_per_nonpeak_period, 0), 2) AS job_peak_multiplier,
  ROUND(n.avg_slot_hours_per_nonpeak_period, 0) AS avg_slot_hrs_nonpeak,
  ROUND(p.avg_slot_hours_per_peak_period, 0) AS avg_slot_hrs_peak,
  ROUND(p.avg_slot_hours_per_peak_period / NULLIF(n.avg_slot_hours_per_nonpeak_period, 0), 2) AS slot_peak_multiplier
FROM peak_summary p
FULL OUTER JOIN nonpeak_summary n USING (consumer_category)
ORDER BY avg_slot_hrs_peak DESC;


-- ============================================================================
-- OUTPUT 3: Hour-of-Day Patterns
-- ============================================================================
-- Uncomment to see traffic distribution by hour of day

SELECT -- OUTPUT 3: Hour-of-Day Patterns
  period_type,
  consumer_category,
  hour_of_day,
  
  SUM(jobs) AS total_jobs,
  ROUND(SUM(total_slot_hours), 0) AS total_slot_hours,
  ROUND(AVG(avg_exec_seconds), 2) AS avg_exec_seconds,
  ROUND(AVG(p95_exec_seconds), 2) AS avg_p95_exec_seconds
  
FROM hourly_patterns
GROUP BY period_type, consumer_category, hour_of_day
ORDER BY period_type, consumer_category, hour_of_day;


-- ============================================================================
-- OUTPUT 4: Day-of-Week Patterns
-- ============================================================================
-- Uncomment to see traffic distribution by day of week

SELECT -- OUTPUT 4: Day-of-Week Patterns
  period_type,
  consumer_category,
  day_of_week,
  day_name,
  
  SUM(jobs) AS total_jobs,
  ROUND(SUM(total_slot_hours), 0) AS total_slot_hours,
  ROUND(AVG(qos_violation_pct), 2) AS avg_qos_violation_pct
  
FROM hourly_patterns
GROUP BY period_type, consumer_category, day_of_week, day_name
ORDER BY period_type, consumer_category, day_of_week;


-- ============================================================================
-- OUTPUT 5: Year-over-Year Growth (Peak Periods Only)
-- ============================================================================
-- Uncomment to see growth trends

WITH peak_by_year AS ( -- OUTPUT 5: Year-over-Year Growth (Peak Periods Only)
  SELECT
    EXTRACT(YEAR FROM date) AS year,
    consumer_category,
    SUM(jobs) AS total_jobs,
    ROUND(SUM(total_slot_hours), 0) AS total_slot_hours
  FROM hourly_patterns
  WHERE period_type = 'PEAK'
  GROUP BY year, consumer_category
)

SELECT
  consumer_category,
  
  -- 2022-2023 metrics
  MAX(CASE WHEN year = 2022 THEN total_jobs END) AS jobs_2022,
  MAX(CASE WHEN year = 2022 THEN total_slot_hours END) AS slot_hrs_2022,
  
  -- 2023-2024 metrics
  MAX(CASE WHEN year = 2023 THEN total_jobs END) AS jobs_2023,
  MAX(CASE WHEN year = 2023 THEN total_slot_hours END) AS slot_hrs_2023,
  ROUND((MAX(CASE WHEN year = 2023 THEN total_slot_hours END) - 
         MAX(CASE WHEN year = 2022 THEN total_slot_hours END)) / 
         NULLIF(MAX(CASE WHEN year = 2022 THEN total_slot_hours END), 0) * 100, 1) AS yoy_2022_2023_pct,
  
  -- 2024-2025 metrics
  MAX(CASE WHEN year = 2024 THEN total_jobs END) AS jobs_2024,
  MAX(CASE WHEN year = 2024 THEN total_slot_hours END) AS slot_hrs_2024,
  ROUND((MAX(CASE WHEN year = 2024 THEN total_slot_hours END) - 
         MAX(CASE WHEN year = 2023 THEN total_slot_hours END)) / 
         NULLIF(MAX(CASE WHEN year = 2023 THEN total_slot_hours END), 0) * 100, 1) AS yoy_2023_2024_pct

FROM peak_by_year
GROUP BY consumer_category
ORDER BY MAX(CASE WHEN year = 2024 THEN total_slot_hours END) DESC;


-- ============================================================================
-- USAGE NOTES
-- ============================================================================
--
-- This query provides OVERALL TRENDS (Track 1) for capacity planning.
-- Uses pre-classified traffic_classification table (much faster than inline classification).
--
-- OUTPUT MODES (uncomment desired section):
-- 1. Summary by category: Peak vs non-peak comparison (default)
-- 2. Peak multipliers: How much higher is peak than baseline
-- 3. Hour-of-day patterns: Traffic distribution by hour
-- 4. Day-of-week patterns: Weekday vs weekend differences
-- 5. Year-over-year growth: Historical growth trends
--
-- PERFORMANCE:
-- - ~2-5 minutes (vs 30-60 minutes for old inline classification approach)
-- - Queries only classified table (~20GB) vs raw audit logs (~200GB+)
--
-- COMPLEMENTS:
-- - identify_capacity_stress_periods.sql: Stress detection (Track 2)
-- - external_qos_under_stress.sql: Customer QoS during stress
-- - monitor_base_stress_analysis.sql: Infrastructure analysis
--
-- KEY INSIGHTS TO LOOK FOR:
-- 1. Peak multipliers: How much does traffic increase during Nov-Jan?
-- 2. Category shifts: Does category mix change peak vs non-peak?
-- 3. Hourly patterns: When are the peak hours within peak periods?
-- 4. Growth rates: Which categories are growing fastest?
--
-- NEXT STEPS:
-- 1. Run to understand overall traffic patterns
-- 2. Combine with stress analysis for complete picture
-- 3. Use peak multipliers in Phase 3 projections
-- ============================================================================

