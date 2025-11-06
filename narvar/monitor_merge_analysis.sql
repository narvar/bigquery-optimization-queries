-- ============================================================================
-- AUTOMATED MONITOR MERGE COST ANALYSIS
-- ============================================================================
-- Purpose: Calculate the percentage of AUTOMATED slots consumed by merge 
--          operations writing to monitor projects
--
-- Usage: Run this query in BigQuery console to get the merge percentage
--        Then use that percentage in the cost calculation
--
-- Date: 2025-11-06
-- ============================================================================

DECLARE start_date DATE DEFAULT '2024-09-01';
DECLARE end_date DATE DEFAULT '2024-10-31';

-- ============================================================================
-- MAIN ANALYSIS: Find AUTOMATED merge jobs writing to monitor projects
-- ============================================================================

WITH traffic_data AS (
  SELECT
    job_id,
    job_type,
    consumer_category,
    consumer_subcategory,
    project_id,
    query_text_sample,
    total_slot_ms,
    execution_time_seconds,
    estimated_slot_cost_usd,
    
    -- Identify MERGE operations writing to monitor projects
    CASE 
      WHEN (UPPER(query_text_sample) LIKE '%MERGE%INTO%' 
            OR UPPER(query_text_sample) LIKE '%MERGE INTO%')
        AND REGEXP_CONTAINS(UPPER(query_text_sample), r'MERGE\s+INTO\s+[`\[]?monitor-[a-z0-9]+-us-[a-z]+')
        THEN TRUE
      ELSE FALSE
    END AS is_monitor_merge_job
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE DATE(start_time) BETWEEN start_date AND end_date
    AND total_slot_ms IS NOT NULL
    AND consumer_category = 'AUTOMATED'  -- Only AUTOMATED category
)

SELECT
  '=' AS divider,
  'AUTOMATED MONITOR MERGE ANALYSIS (Sep-Oct 2024)' AS report_title,
  '=' AS divider2,
  
  -- Overall AUTOMATED metrics
  COUNT(*) AS total_automated_jobs,
  COUNTIF(is_monitor_merge_job) AS monitor_merge_jobs,
  ROUND(COUNTIF(is_monitor_merge_job) / COUNT(*) * 100, 2) AS monitor_merge_job_pct,
  
  -- Slot consumption (AUTOMATED only)
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_automated_slot_hours,
  ROUND(SUM(CASE WHEN is_monitor_merge_job THEN total_slot_ms ELSE 0 END) / 3600000, 2) AS monitor_merge_slot_hours,
  ROUND(SUM(CASE WHEN is_monitor_merge_job THEN total_slot_ms ELSE 0 END) / SUM(total_slot_ms) * 100, 2) AS monitor_merge_slot_pct,
  
  -- Cost metrics (AUTOMATED only, 2-month baseline)
  ROUND(SUM(estimated_slot_cost_usd), 2) AS total_automated_cost_usd,
  ROUND(SUM(CASE WHEN is_monitor_merge_job THEN estimated_slot_cost_usd ELSE 0 END), 2) AS monitor_merge_cost_usd,
  ROUND(SUM(CASE WHEN is_monitor_merge_job THEN estimated_slot_cost_usd ELSE 0 END) / SUM(estimated_slot_cost_usd) * 100, 2) AS monitor_merge_cost_pct,
  
  -- Execution time
  ROUND(SUM(execution_time_seconds) / 3600, 2) AS total_automated_exec_hours,
  ROUND(SUM(CASE WHEN is_monitor_merge_job THEN execution_time_seconds ELSE 0 END) / 3600, 2) AS monitor_merge_exec_hours
  
FROM traffic_data;

-- ============================================================================
-- SAMPLE QUERIES: Validate regex pattern
-- ============================================================================

SELECT
  '=' AS divider,
  'SAMPLE MONITOR MERGE QUERIES (Top 10 by slot hours)' AS section,
  '=' AS divider2,
  '' AS blank_line;

SELECT
  project_id,
  consumer_subcategory,
  ROUND(total_slot_ms / 3600000, 4) AS slot_hours,
  ROUND(estimated_slot_cost_usd, 4) AS cost_usd,
  SUBSTR(query_text_sample, 1, 200) AS query_sample
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE DATE(start_time) BETWEEN start_date AND end_date
  AND total_slot_ms IS NOT NULL
  AND consumer_category = 'AUTOMATED'
  AND (
    UPPER(query_text_sample) LIKE '%MERGE%INTO%' 
    OR UPPER(query_text_sample) LIKE '%MERGE INTO%'
  )
  AND REGEXP_CONTAINS(UPPER(query_text_sample), r'MERGE\s+INTO\s+[`\[]?monitor-[a-z0-9]+-us-[a-z]+')
ORDER BY slot_hours DESC
LIMIT 10;

-- ============================================================================
-- BREAKDOWN BY SUBCATEGORY
-- ============================================================================

SELECT
  '=' AS divider,
  'MONITOR MERGE BY AUTOMATED SUBCATEGORY' AS section,
  '=' AS divider2,
  '' AS blank_line;

WITH traffic_data AS (
  SELECT
    consumer_subcategory,
    total_slot_ms,
    estimated_slot_cost_usd,
    CASE 
      WHEN (UPPER(query_text_sample) LIKE '%MERGE%INTO%' 
            OR UPPER(query_text_sample) LIKE '%MERGE INTO%')
        AND REGEXP_CONTAINS(UPPER(query_text_sample), r'MERGE\s+INTO\s+[`\[]?monitor-[a-z0-9]+-us-[a-z]+')
        THEN TRUE
      ELSE FALSE
    END AS is_monitor_merge_job
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE DATE(start_time) BETWEEN start_date AND end_date
    AND total_slot_ms IS NOT NULL
    AND consumer_category = 'AUTOMATED'
)

SELECT
  consumer_subcategory,
  COUNT(*) AS total_jobs,
  COUNTIF(is_monitor_merge_job) AS monitor_merge_jobs,
  ROUND(COUNTIF(is_monitor_merge_job) / COUNT(*) * 100, 2) AS merge_job_pct,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours,
  ROUND(SUM(CASE WHEN is_monitor_merge_job THEN total_slot_ms ELSE 0 END) / 3600000, 2) AS merge_slot_hours,
  ROUND(SUM(estimated_slot_cost_usd), 2) AS total_cost_usd,
  ROUND(SUM(CASE WHEN is_monitor_merge_job THEN estimated_slot_cost_usd ELSE 0 END), 2) AS merge_cost_usd
FROM traffic_data
GROUP BY consumer_subcategory
HAVING COUNTIF(is_monitor_merge_job) > 0
ORDER BY merge_slot_hours DESC;

-- ============================================================================
-- INSTRUCTIONS
-- ============================================================================
-- 
-- After running this query, use the 'monitor_merge_slot_pct' value to calculate:
--
-- Annual Monitor Merge Cost = 
--   (Total BQ Reservation API Cost × monitor_merge_slot_pct / 100) +
--   Storage Costs (monitor-base-us-prod) +
--   Pub/Sub Costs (monitor-base-us-prod)
--
-- From DoIT CSV:
--   - Total BQ Reservation API: $619,598.41/year
--   - Storage (monitor-base-us-prod): $24,899.45/year  
--   - Pub/Sub (monitor-base-us-prod): $26,226.46/year
--
-- ============================================================================

