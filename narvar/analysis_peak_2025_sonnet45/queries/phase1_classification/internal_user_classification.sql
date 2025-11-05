-- ============================================================================
-- INTERNAL USER CLASSIFICATION
-- ============================================================================
-- Purpose: Identify and classify internal user traffic including:
--          1. Metabase queries (with individual user attribution)
--          2. Ad-hoc queries from internal users
--          3. Other internal analytics tools
--
-- Consumer Category: INTERNAL Users (P1)
-- QoS Target: Query response time < 5-10 minutes (8 min threshold)
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

-- Service account patterns for internal tools (regex-based)
-- Metabase, n8n, and other internal analytics tools
DECLARE metabase_service_account STRING DEFAULT 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com';

-- QoS threshold for internal users (8 minutes = 480 seconds)
DECLARE qos_threshold_seconds INT64 DEFAULT 480;

-- ============================================================================
-- MAIN QUERY: Internal User Traffic Classification
-- ============================================================================

WITH
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
    
    -- Query text (for Metabase user ID extraction)
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    
    -- Reservation info
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservation AS reservation_name,
    
    -- Caller metadata
    protopayload_auditlog.requestMetadata.callerSuppliedUserAgent AS user_agent,
    protopayload_auditlog.requestMetadata.callerIp AS caller_ip,
    
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

-- Classify internal user traffic
internal_classified AS (
  SELECT
    a.*,
    
    -- Extract Metabase user ID (try multiple patterns)
    COALESCE(
      REGEXP_EXTRACT(a.query_text, r'--\s*Metabase::\s*userID:\s*(\d+)'),
      REGEXP_EXTRACT(a.query_text, r'/\*\s*Metabase\s*userID:\s*(\d+)\s*\*/'),
      REGEXP_EXTRACT(a.query_text, r'--\s*metabase_user_id\s*=\s*(\d+)')
    ) AS metabase_user_id,
    
    -- Consumer subcategory classification (regex-based for consistency)
    CASE
      -- Metabase queries (service account)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'metabase.*@.*\.iam\.gserviceaccount\.com')
        THEN 'METABASE'
      
      -- n8n workflow automation (internal analytics automation)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'n8n')
        THEN 'N8N_WORKFLOW'
      
      -- Ad-hoc queries from @narvar.com user emails (human users)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'@narvar\.com$')
        AND NOT STARTS_WITH(LOWER(a.project_id), 'monitor-')
        THEN 'ADHOC_USER'
      
      -- Other BI/Analytics tools (Looker when NOT external, Tableau, PowerBI, etc.)
      WHEN REGEXP_CONTAINS(LOWER(a.user_agent), r'(tableau|powerbi)')
        OR (REGEXP_CONTAINS(LOWER(a.user_agent), r'looker') 
            AND NOT STARTS_WITH(LOWER(a.project_id), 'monitor-'))
        THEN 'OTHER_BI_TOOL'
      
      -- Internal service accounts (not automation, not external, not already classified)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'iam\.gserviceaccount\.com$')
        AND NOT REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer|gke-prod|compute@developer|cdp|dataflow|etl|eddmodel|ml-|looker|metabase)')
        AND NOT STARTS_WITH(LOWER(a.project_id), 'monitor-')
        THEN 'INTERNAL_SERVICE_ACCOUNT'
      
      ELSE NULL
    END AS consumer_subcategory,
    
    -- QoS evaluation for internal users (threshold: 8 minutes)
    CASE 
      WHEN a.execution_time_seconds > qos_threshold_seconds THEN 'QoS_VIOLATION'
      WHEN a.execution_time_seconds <= qos_threshold_seconds THEN 'QoS_MET'
      ELSE 'QoS_UNKNOWN'
    END AS qos_status,
    
    -- Execution time categories
    CASE
      WHEN a.execution_time_seconds <= 60 THEN 'FAST (<1 min)'
      WHEN a.execution_time_seconds <= 300 THEN 'MODERATE (1-5 min)'
      WHEN a.execution_time_seconds <= qos_threshold_seconds THEN 'ACCEPTABLE (5-8 min)'
      WHEN a.execution_time_seconds <= 1800 THEN 'SLOW (8-30 min)'
      ELSE 'VERY_SLOW (>30 min)'
    END AS execution_time_category,
    
    -- Cost calculation (slot-based for reserved capacity)
    -- Blended rate: ~$0.0494/slot-hour
    ROUND(SAFE_DIVIDE(a.total_slot_ms, 3600000) * 0.0494, 4) AS estimated_slot_cost_usd,
    
    -- Analysis period identifier
    analysis_period AS analysis_period
    
  FROM audit_deduplicated a
  
  -- Filter for internal users
  WHERE 
    -- Metabase
    a.principal_email = metabase_service_account
    
    -- Or ad-hoc user queries (not service accounts)
    OR (
      a.principal_email NOT LIKE '%@%.iam.gserviceaccount.com' 
      AND a.principal_email NOT LIKE '%gserviceaccount.com'
      AND a.project_id NOT LIKE 'monitor-%'
    )
    
    -- Or other internal patterns (refine as needed)
    OR (
      a.principal_email LIKE '%@%.iam.gserviceaccount.com'
      AND a.project_id NOT LIKE 'monitor-%'
      AND LOWER(a.principal_email) NOT LIKE '%airflow%'
      AND LOWER(a.principal_email) NOT LIKE '%composer%'
      AND LOWER(a.principal_email) NOT LIKE '%cdp%'
      AND LOWER(a.principal_email) NOT LIKE '%dataflow%'
    )
)

-- Final output: Internal user traffic with full attribution
SELECT
  -- Identifiers
  job_id,
  project_id,
  principal_email,
  location,
  analysis_period,
  
  -- Consumer classification
  'INTERNAL' AS consumer_category,
  consumer_subcategory,
  
  -- Metabase user attribution
  metabase_user_id,
  -- TODO: Join with Metabase DB to populate these fields
  CAST(NULL AS STRING) AS metabase_user_email,
  CAST(NULL AS STRING) AS metabase_user_name,
  
  -- Job details
  job_type,
  start_time,
  end_time,
  execution_time_seconds,
  ROUND(execution_time_seconds / 60.0, 2) AS execution_time_minutes,
  execution_time_category,
  
  -- Resource consumption
  total_slot_ms,
  approximate_slot_count,
  total_billed_bytes,
  ROUND(total_billed_bytes / POW(1024, 3), 2) AS total_billed_gb,
  estimated_slot_cost_usd,
  
  -- QoS metrics
  qos_status,
  CASE WHEN qos_status = 'QoS_VIOLATION' THEN execution_time_seconds - qos_threshold_seconds ELSE 0 END AS qos_violation_seconds,
  
  -- Reservation info
  reservation_name,
  
  -- Additional context
  user_agent,
  caller_ip,
  
  -- Query text sample (for analysis)
  SUBSTR(query_text, 1, 500) AS query_text_sample

FROM internal_classified
WHERE consumer_subcategory IS NOT NULL
ORDER BY start_time DESC, execution_time_seconds DESC;

-- ============================================================================
-- SUMMARY STATISTICS BY SUBCATEGORY
-- ============================================================================
-- Uncomment below to get summary statistics instead of detailed records
/*
SELECT
  consumer_subcategory,
  
  -- Volume metrics
  COUNT(*) AS total_jobs,
  COUNT(DISTINCT principal_email) AS unique_users,
  COUNT(DISTINCT metabase_user_id) AS unique_metabase_users,
  COUNT(DISTINCT project_id) AS unique_projects,
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
  
  -- Execution time distribution
  COUNTIF(execution_time_category = 'FAST (<1 min)') AS fast_queries,
  COUNTIF(execution_time_category = 'MODERATE (1-5 min)') AS moderate_queries,
  COUNTIF(execution_time_category = 'ACCEPTABLE (5-8 min)') AS acceptable_queries,
  COUNTIF(execution_time_category = 'SLOW (8-30 min)') AS slow_queries,
  COUNTIF(execution_time_category = 'VERY_SLOW (>30 min)') AS very_slow_queries,
  
  -- Slot usage statistics
  ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count,
  ROUND(APPROX_QUANTILES(approximate_slot_count, 100)[OFFSET(95)], 2) AS p95_slot_count,
  SUM(total_slot_ms) AS total_slot_ms,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours,
  
  -- Cost metrics
  ROUND(SUM(estimated_slot_cost_usd), 2) AS total_estimated_cost_usd,
  ROUND(AVG(on_demand_cost_usd), 4) AS avg_cost_per_job_usd

FROM internal_classified
WHERE consumer_subcategory IS NOT NULL
GROUP BY consumer_subcategory
ORDER BY total_jobs DESC;
*/

-- ============================================================================
-- TOP INTERNAL USERS BY VOLUME AND COST
-- ============================================================================
-- Uncomment to identify heaviest internal users
/*
SELECT
  consumer_subcategory,
  principal_email,
  metabase_user_id,
  
  -- Volume
  COUNT(*) AS total_queries,
  COUNT(DISTINCT DATE(start_time)) AS active_days,
  
  -- QoS
  COUNTIF(qos_status = 'QoS_VIOLATION') AS qos_violations,
  ROUND(COUNTIF(qos_status = 'QoS_VIOLATION') / COUNT(*) * 100, 2) AS qos_violation_pct,
  
  -- Performance
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
  
  -- Resources
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours,
  SUM(on_demand_cost_usd) AS total_cost_usd

FROM internal_classified
WHERE consumer_subcategory IS NOT NULL
GROUP BY consumer_subcategory, principal_email, metabase_user_id
HAVING total_queries >= 10
ORDER BY total_estimated_cost_usd DESC
LIMIT 50;
*/