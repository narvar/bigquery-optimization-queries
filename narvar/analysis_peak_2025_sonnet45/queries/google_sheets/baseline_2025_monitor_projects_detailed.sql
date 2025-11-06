-- ============================================================================
-- GOOGLE CONNECTED SHEET QUERY: Baseline 2025 Monitor Projects
-- ============================================================================
-- Purpose: Comprehensive view of ALL monitor projects (excluding monitor-base)
--          Classified by environment (PROD/QA/STG) and mapping status
--
-- Usage: Copy this query into Google Sheets → Data → Data connectors → 
--        BigQuery → Connect to a query
--
-- Last Updated: 2025-11-06
-- ============================================================================

SELECT
  -- Project identification
  project_id,
  
  -- Environment classification (PROD/QA/STG)
  CASE
    WHEN project_id LIKE '%-us-prod' THEN 'PROD'
    WHEN project_id LIKE '%-us-qa' THEN 'QA'
    WHEN project_id LIKE '%-us-stg' THEN 'STG'
    ELSE 'UNKNOWN'
  END as environment,
  
  -- Slot allocation type (RESERVED vs ON-DEMAND)
  CASE
    WHEN reservation_name = 'bq-narvar-admin:US.default' THEN 'RESERVED'
    WHEN reservation_name = 'unreserved' THEN 'ON_DEMAND'
    ELSE reservation_name
  END as slot_type,
  
  -- Mapping status (MATCHED/UNMATCHED)
  CASE
    WHEN consumer_subcategory = 'MONITOR' THEN 'MATCHED'
    WHEN consumer_subcategory = 'MONITOR_UNMATCHED' THEN 'UNMATCHED'
    ELSE consumer_subcategory
  END as mapping_status,
  
  -- Retailer name (NULL if unmatched)
  retailer_moniker,
  
  -- === TIME PERIOD ===
  MIN(DATE(start_time)) as first_job_date,
  MAX(DATE(start_time)) as last_job_date,
  DATE_DIFF(MAX(DATE(start_time)), MIN(DATE(start_time)), DAY) + 1 as days_span,
  
  -- === VOLUME METRICS ===
  COUNT(*) as total_jobs,
  COUNT(DISTINCT DATE(start_time)) as active_days,
  
  -- === RESOURCE CONSUMPTION ===
  ROUND(SUM(slot_hours), 2) as total_slot_hours,
  ROUND(AVG(slot_hours), 4) as avg_slot_hours_per_job,
  ROUND(AVG(approximate_slot_count), 2) as avg_concurrent_slots,
  
  -- === EXECUTION TIME METRICS ===
  ROUND(AVG(execution_time_seconds), 2) as avg_exec_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) as p50_exec_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) as p95_exec_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) as p99_exec_seconds,
  MAX(execution_time_seconds) as max_exec_seconds,
  
  -- === QoS METRICS (30s threshold) ===
  COUNTIF(is_qos_violation) as qos_violations,
  ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) as qos_violation_pct,
  
  -- === COST ===
  ROUND(SUM(estimated_slot_cost_usd), 2) as total_cost_usd

FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE analysis_period_label = 'Baseline_2025_Sep_Oct'
  AND consumer_subcategory IN ('MONITOR', 'MONITOR_UNMATCHED')  -- EXCLUDE MONITOR_BASE
GROUP BY project_id, consumer_subcategory, retailer_moniker, reservation_name
ORDER BY 
  environment,              -- PROD first, then QA, then STG
  total_slot_hours DESC;    -- Within each environment, highest consumers first

-- ============================================================================
-- EXPECTED RESULTS:
-- - PROD projects: ~68 matched + ~29 unmapped
-- - QA projects: Various test projects
-- - STG projects: Staging environments
-- Total: ~97 unique monitor projects (excluding monitor-base)
-- ============================================================================

