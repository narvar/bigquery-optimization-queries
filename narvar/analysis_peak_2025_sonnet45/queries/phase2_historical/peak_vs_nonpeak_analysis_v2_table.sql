-- ============================================================================
-- PEAK VS NON-PEAK TRAFFIC ANALYSIS - TABLE CREATION
-- ============================================================================

DECLARE analyze_periods ARRAY<STRING> DEFAULT NULL;  -- NULL = all periods

-- ============================================================================
-- CREATE THE OUTPUT TABLE (YoY Growth - Most useful for Phase 3)
-- ============================================================================

CREATE OR REPLACE TABLE `narvar-data-lake.query_opt.phase2_peak_patterns` AS

WITH
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

hourly_patterns AS (
  SELECT
    t.analysis_period_label,
    pc.period_type,
    DATE(t.start_time) AS date,
    EXTRACT(HOUR FROM t.start_time) AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM t.start_time) AS day_of_week,
    FORMAT_TIMESTAMP('%A', t.start_time) AS day_name,
    
    t.consumer_category,
    t.consumer_subcategory,
    
    COUNT(*) AS jobs,
    COUNT(DISTINCT t.principal_email) AS unique_principals,
    COUNT(DISTINCT t.project_id) AS unique_projects,
    COUNT(DISTINCT t.retailer_moniker) AS unique_retailers,
    
    ROUND(AVG(t.execution_time_seconds), 2) AS avg_exec_seconds,
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_exec_seconds,
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_exec_seconds,
    ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_exec_seconds,
    
    ROUND(SUM(t.slot_hours), 2) AS total_slot_hours,
    ROUND(AVG(t.slot_hours), 4) AS avg_slot_hours_per_job,
    ROUND(AVG(t.approximate_slot_count), 2) AS avg_concurrent_slots,
    
    ROUND(SUM(t.estimated_slot_cost_usd), 2) AS total_cost_usd,
    
    COUNTIF(t.is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(t.is_qos_violation) / NULLIF(COUNTIF(t.qos_status IN ('QoS_MET', 'QoS_VIOLATION')), 0) * 100, 2) AS qos_violation_pct
    
  FROM `narvar-data-lake.query_opt.traffic_classification` t
  INNER JOIN period_classification pc USING (analysis_period_label)
  WHERE (analyze_periods IS NULL OR t.analysis_period_label IN UNNEST(analyze_periods))
  GROUP BY 
    t.analysis_period_label, pc.period_type, date, hour_of_day, 
    day_of_week, day_name, t.consumer_category, t.consumer_subcategory
),

peak_by_year AS (
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
  
  MAX(CASE WHEN year = 2022 THEN total_jobs END) AS jobs_2022,
  MAX(CASE WHEN year = 2022 THEN total_slot_hours END) AS slot_hrs_2022,
  
  MAX(CASE WHEN year = 2023 THEN total_jobs END) AS jobs_2023,
  MAX(CASE WHEN year = 2023 THEN total_slot_hours END) AS slot_hrs_2023,
  ROUND((MAX(CASE WHEN year = 2023 THEN total_slot_hours END) - 
         MAX(CASE WHEN year = 2022 THEN total_slot_hours END)) / 
         NULLIF(MAX(CASE WHEN year = 2022 THEN total_slot_hours END), 0) * 100, 1) AS yoy_2022_2023_pct,
  
  MAX(CASE WHEN year = 2024 THEN total_jobs END) AS jobs_2024,
  MAX(CASE WHEN year = 2024 THEN total_slot_hours END) AS slot_hrs_2024,
  ROUND((MAX(CASE WHEN year = 2024 THEN total_slot_hours END) - 
         MAX(CASE WHEN year = 2023 THEN total_slot_hours END)) / 
         NULLIF(MAX(CASE WHEN year = 2023 THEN total_slot_hours END), 0) * 100, 1) AS yoy_2023_2024_pct

FROM peak_by_year
GROUP BY consumer_category
ORDER BY MAX(CASE WHEN year = 2024 THEN total_slot_hours END) DESC;




