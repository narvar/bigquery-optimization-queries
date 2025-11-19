-- ============================================================================
-- INVESTIGATION 3: MONITOR MAPPING QUALITY ANALYSIS
-- ============================================================================
-- Purpose: Assess MD5-based mapping quality between monitor projects and retailer_moniker
--          Review ~34% match rate and identify unmapped projects
--
-- Output: narvar-data-lake.query_opt.phase2_monitor_mapping_quality
-- Runtime: ~5-10 seconds
-- ============================================================================

DECLARE analyze_periods ARRAY<STRING> DEFAULT [
  'Peak_2024_2025',
  'Baseline_2025_Sep_Oct',
  'Peak_2023_2024'
];

-- ============================================================================
-- CREATE OUTPUT TABLE
-- ============================================================================

CREATE OR REPLACE TABLE `narvar-data-lake.query_opt.phase2_monitor_mapping_quality` AS

WITH
-- Overall mapping statistics by period
mapping_stats AS (
  SELECT 
    analysis_period_label,
    COUNT(*) as total_monitor_jobs,
    COUNTIF(retailer_moniker IS NOT NULL) as matched_jobs,
    COUNTIF(retailer_moniker IS NULL) as unmapped_jobs,
    ROUND(COUNTIF(retailer_moniker IS NOT NULL) / COUNT(*) * 100, 2) as match_rate_pct,
    
    -- Resource consumption
    SUM(slot_hours) as total_slot_hours,
    SUM(CASE WHEN retailer_moniker IS NOT NULL THEN slot_hours ELSE 0 END) as matched_slot_hours,
    SUM(CASE WHEN retailer_moniker IS NULL THEN slot_hours ELSE 0 END) as unmapped_slot_hours,
    
    -- Unique counts
    COUNT(DISTINCT project_id) as unique_projects,
    COUNT(DISTINCT retailer_moniker) as unique_retailers,
    
    -- Environment breakdown
    COUNTIF(project_id LIKE '%-us-prod') as prod_jobs,
    COUNTIF(project_id LIKE '%-us-qa') as qa_jobs,
    COUNTIF(project_id LIKE '%-us-stg') as stg_jobs
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
    AND consumer_subcategory = 'MONITOR'  -- Matched monitor projects
  GROUP BY analysis_period_label
),

-- Unmapped projects (top 20 by volume)
top_unmapped_projects AS (
  SELECT
    analysis_period_label,
    project_id,
    COUNT(*) as job_count,
    SUM(slot_hours) as slot_hours,
    ROUND(AVG(execution_time_seconds), 2) as avg_exec_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) as p95_exec_seconds,
    
    -- Detect patterns
    CASE
      WHEN project_id LIKE '%-us-prod' THEN 'PROD'
      WHEN project_id LIKE '%-us-qa' THEN 'QA'
      WHEN project_id LIKE '%-us-stg' THEN 'STG'
      ELSE 'UNKNOWN'
    END AS environment,
    
    ROW_NUMBER() OVER(PARTITION BY analysis_period_label ORDER BY COUNT(*) DESC) as rank_by_jobs
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
    AND consumer_subcategory = 'MONITOR_UNMATCHED'  -- Unmapped monitor projects
  GROUP BY analysis_period_label, project_id
  QUALIFY rank_by_jobs <= 20
),

-- Monitor-base projects (excluded from retailer mapping)
monitor_base_stats AS (
  SELECT
    analysis_period_label,
    COUNT(*) as monitor_base_jobs,
    SUM(slot_hours) as monitor_base_slot_hours,
    ROUND(AVG(execution_time_seconds), 2) as avg_exec_seconds
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE (analyze_periods IS NULL OR analysis_period_label IN UNNEST(analyze_periods))
    AND consumer_subcategory = 'MONITOR_BASE'
  GROUP BY analysis_period_label
)

-- Part A: Overall Mapping Statistics
SELECT
  'PART A: Overall Mapping Statistics' AS analysis_section,
  m.analysis_period_label,
  m.total_monitor_jobs,
  m.matched_jobs,
  m.unmapped_jobs,
  m.match_rate_pct,
  m.total_slot_hours,
  m.matched_slot_hours,
  m.unmapped_slot_hours,
  m.unique_projects,
  m.unique_retailers,
  m.prod_jobs,
  m.qa_jobs,
  m.stg_jobs,
  
  -- Monitor-base context
  mb.monitor_base_jobs,
  mb.monitor_base_slot_hours,
  
  -- Null fields for Part B
  CAST(NULL AS STRING) AS project_id,
  CAST(NULL AS INT64) AS job_count,
  CAST(NULL AS FLOAT64) AS slot_hours_project,
  CAST(NULL AS FLOAT64) AS avg_exec_seconds,
  CAST(NULL AS FLOAT64) AS p95_exec_seconds,
  CAST(NULL AS STRING) AS environment,
  CAST(NULL AS INT64) AS rank_by_jobs
  
FROM mapping_stats m
LEFT JOIN monitor_base_stats mb USING(analysis_period_label)

UNION ALL

-- Part B: Top 20 Unmapped Projects by Period
SELECT
  'PART B: Top Unmapped Projects' AS analysis_section,
  u.analysis_period_label,
  
  -- Null fields for Part A
  CAST(NULL AS INT64) AS total_monitor_jobs,
  CAST(NULL AS INT64) AS matched_jobs,
  CAST(NULL AS INT64) AS unmapped_jobs,
  CAST(NULL AS FLOAT64) AS match_rate_pct,
  CAST(NULL AS FLOAT64) AS total_slot_hours,
  CAST(NULL AS FLOAT64) AS matched_slot_hours,
  CAST(NULL AS FLOAT64) AS unmapped_slot_hours,
  CAST(NULL AS INT64) AS unique_projects,
  CAST(NULL AS INT64) AS unique_retailers,
  CAST(NULL AS INT64) AS prod_jobs,
  CAST(NULL AS INT64) AS qa_jobs,
  CAST(NULL AS INT64) AS stg_jobs,
  CAST(NULL AS INT64) AS monitor_base_jobs,
  CAST(NULL AS FLOAT64) AS monitor_base_slot_hours,
  
  -- Part B specific fields
  u.project_id,
  u.job_count,
  u.slot_hours AS slot_hours_project,
  u.avg_exec_seconds,
  u.p95_exec_seconds,
  u.environment,
  u.rank_by_jobs
  
FROM top_unmapped_projects u

ORDER BY analysis_section, analysis_period_label, rank_by_jobs;

-- ============================================================================
-- VALIDATION QUERY (run after table creation)
-- ============================================================================
/*
SELECT
  analysis_section,
  analysis_period_label,
  match_rate_pct,
  unique_retailers,
  unmapped_jobs,
  unmapped_slot_hours
FROM `narvar-data-lake.query_opt.phase2_monitor_mapping_quality`
WHERE analysis_section = 'PART A: Overall Mapping Statistics'
ORDER BY analysis_period_label;
*/

