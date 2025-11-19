-- ============================================================================
-- EXTERNAL CONSUMER CLASSIFICATION
-- ============================================================================
-- Purpose: Identify and classify external consumer traffic including:
--          1. Monitor projects (retailer-specific, B2B customers)
--          2. Hub traffic (Looker-based, multi-retailer)
--
-- Consumer Category: CRITICAL External Consumers (P0)
-- QoS Target: Query response time < 1 minute
--
-- Data Quality: Filters for jobs with measured slot consumption (totalSlotMs IS NOT NULL)
--               This captures ~94% of execution time and ~99.94% of bytes processed
--               Excluded: cache hits, metadata queries, failed queries (minimal capacity impact)
--
-- Cost estimate: ~5-20GB processed (depends on date range)
-- Recommended: Run with dry_run first for large date ranges
-- ============================================================================

-- Configuration parameters
-- TEST PERIOD: Oct-Nov 2024 (2 months for initial validation)
-- For full analysis, change to broader date ranges
DECLARE start_date DATE DEFAULT '2024-10-01';
DECLARE end_date DATE DEFAULT '2024-11-30';
DECLARE analysis_period STRING DEFAULT '2024-10-11-baseline'; -- for identification

-- Service account patterns for external consumers
-- Hub services: Looker, Metabase (when serving external dashboards)
DECLARE hub_service_accounts ARRAY<STRING> DEFAULT [
  'looker-prod@narvar-data-lake.iam.gserviceaccount.com',
  'looker@narvar-data-lake.iam.gserviceaccount.com'
];

-- ============================================================================
-- MAIN QUERY: External Consumer Traffic Classification
-- ============================================================================

WITH
-- Get retailer to monitor project mappings using MD5 hash
-- This matches the actual monitor project naming convention
retailer_mappings AS (
  SELECT DISTINCT 
    retailer_moniker,
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-prod') AS project_id_prod,
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-qa') AS project_id_qa,
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-stg') AS project_id_stg
  FROM `narvar-data-lake.reporting.t_return_details`
  WHERE DATE(return_created_date) >= '2022-01-01'
    AND retailer_moniker IS NOT NULL
),

-- Extract audit log data with deduplication
audit_data AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.location AS location,
    
    -- Event details
    CASE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName
      WHEN 'query_job_completed' THEN 'QUERY'
      WHEN 'load_job_completed' THEN 'LOAD'
      WHEN 'extract_job_completed' THEN 'EXTRACT'
      WHEN 'table_copy_job_completed' THEN 'TABLE_COPY'
    END AS job_type,
    
    -- Timing metrics
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime AS start_time,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime AS end_time,
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
      SECOND
    ) AS execution_time_seconds,
    
    -- Resource consumption
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes AS total_billed_bytes,
    
    -- Slot usage calculation
    SAFE_DIVIDE(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
      TIMESTAMP_DIFF(
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
        MILLISECOND
      )
    ) AS approximate_slot_count,
    
    -- Query text (for Hub attribution analysis)
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    
    -- Reservation info
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservation AS reservation_name,
    
    -- Deduplication
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS row_num
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN start_date AND end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    -- NULL-TOLERANT FILTER: Only include jobs with measured slot consumption
    -- This captures ~94% of execution time and ~99.94% of bytes processed
    -- Excludes cache hits, metadata queries, and failed queries (minimal capacity impact)
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs IS NOT NULL
),

-- Deduplicated audit data
audit_deduplicated AS (
  SELECT * EXCEPT(row_num)
  FROM audit_data
  WHERE row_num = 1
),

-- Match monitor projects to retailers using MD5-based project IDs
retailer_selected AS (
  SELECT
    a.job_id,
    a.project_id,
    rm.retailer_moniker
  FROM audit_deduplicated a
  INNER JOIN retailer_mappings rm
    ON a.project_id IN (rm.project_id_prod, rm.project_id_qa, rm.project_id_stg)
  WHERE STARTS_WITH(LOWER(a.project_id), 'monitor-')
),

-- Classify external consumer traffic
external_classified AS (
  SELECT
    a.*,
    
    -- Consumer identification
    CASE
      -- Hub traffic (Looker/Metabase service accounts serving external dashboards)
      WHEN a.principal_email IN UNNEST(hub_service_accounts) THEN 'HUB'
      
      -- Monitor project traffic (retailer-specific projects)
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') AND rs.retailer_moniker IS NOT NULL THEN 'MONITOR'
      
      -- Monitor projects without matched retailer
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') AND rs.retailer_moniker IS NULL THEN 'MONITOR_UNMATCHED'
      
      ELSE NULL
    END AS consumer_subcategory,
    
    -- Retailer attribution
    rs.retailer_moniker,
    
    -- QoS evaluation for external consumers (threshold: 60 seconds)
    CASE 
      WHEN a.execution_time_seconds > 60 THEN 'QoS_VIOLATION'
      WHEN a.execution_time_seconds <= 60 THEN 'QoS_MET'
      ELSE 'QoS_UNKNOWN'
    END AS qos_status,
    
    -- Cost calculation (slot-based for reserved capacity)
    -- Blended rate: ~$0.0494/slot-hour
    ROUND(SAFE_DIVIDE(a.total_slot_ms, 3600000) * 0.0494, 4) AS estimated_slot_cost_usd,
    
    -- Analysis period identifier
    analysis_period AS analysis_period
    
  FROM audit_deduplicated a
  LEFT JOIN retailer_selected rs USING (job_id, project_id)
  
  -- Filter for external consumers only
  WHERE a.principal_email IN UNNEST(hub_service_accounts)
     OR STARTS_WITH(LOWER(a.project_id), 'monitor-')
)

-- Final output: External consumer traffic with full attribution
SELECT
  -- Identifiers
  job_id,
  project_id,
  principal_email,
  location,
  analysis_period,
  
  -- Consumer classification
  'EXTERNAL' AS consumer_category,
  consumer_subcategory,
  retailer_moniker,
  
  -- Job details
  job_type,
  start_time,
  end_time,
  execution_time_seconds,
  ROUND(execution_time_seconds / 60.0, 2) AS execution_time_minutes,
  
  -- Resource consumption
  total_slot_ms,
  approximate_slot_count,
  total_billed_bytes,
  ROUND(total_billed_bytes / POW(1024, 3), 2) AS total_billed_gb,
  estimated_slot_cost_usd,
  
  -- QoS metrics
  qos_status,
  CASE WHEN qos_status = 'QoS_VIOLATION' THEN execution_time_seconds - 60 ELSE 0 END AS qos_violation_seconds,
  
  -- Reservation info
  reservation_name,
  
  -- Query text (first 1000 chars for Hub attribution analysis)
  SUBSTR(query_text, 1, 1000) AS query_text_sample

FROM external_classified
ORDER BY start_time DESC, execution_time_seconds DESC;

-- ============================================================================
-- SUMMARY STATISTICS
-- ============================================================================
-- Uncomment below to get summary statistics instead of detailed records
/*
SELECT
  consumer_subcategory,
  retailer_moniker,
  
  -- Volume metrics
  COUNT(*) AS total_jobs,
  COUNT(DISTINCT DATE(start_time)) AS active_days,
  
  -- QoS metrics
  COUNTIF(qos_status = 'QoS_MET') AS qos_met_count,
  COUNTIF(qos_status = 'QoS_VIOLATION') AS qos_violation_count,
  ROUND(COUNTIF(qos_status = 'QoS_VIOLATION') / COUNT(*) * 100, 2) AS qos_violation_pct,
  
  -- Execution time statistics
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS median_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
  MAX(execution_time_seconds) AS max_execution_seconds,
  
  -- Slot usage statistics
  ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count,
  ROUND(APPROX_QUANTILES(approximate_slot_count, 100)[OFFSET(95)], 2) AS p95_slot_count,
  SUM(total_slot_ms) AS total_slot_ms,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours,
  
  -- Cost metrics (slot-based)
  ROUND(SUM(estimated_slot_cost_usd), 2) AS total_estimated_cost_usd,
  ROUND(AVG(estimated_slot_cost_usd), 6) AS avg_cost_per_job_usd

FROM external_classified
GROUP BY consumer_subcategory, retailer_moniker
ORDER BY total_jobs DESC;
*/
