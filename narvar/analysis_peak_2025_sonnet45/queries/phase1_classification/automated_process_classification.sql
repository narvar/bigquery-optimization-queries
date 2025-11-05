-- ============================================================================
-- AUTOMATED PROCESS CLASSIFICATION
-- ============================================================================
-- Purpose: Identify and classify automated process traffic including:
--          1. Airflow/Composer scheduled jobs
--          2. CDP (Customer Data Platform) pipelines
--          3. Other automated ETL/processing systems
--
-- Consumer Category: CRITICAL Automated Processes (P0)
-- QoS Target: Execute within scheduled time windows (before next run)
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

-- ============================================================================
-- MAIN QUERY: Automated Process Traffic Classification
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
    
    -- Query text (for pattern analysis)
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    
    -- Reservation info
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservation AS reservation_name,
    
    -- Job status
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatus.state AS job_state,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatus.error AS job_error,
    
    -- Caller metadata
    protopayload_auditlog.requestMetadata.callerSuppliedUserAgent AS user_agent,
    
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

-- Classify automated process traffic using regex patterns
automated_classified AS (
  SELECT
    a.*,
    
    -- Consumer subcategory classification (regex-based, no manual configuration needed)
    CASE
      -- Airflow/Composer (service accounts containing airflow or composer)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer)')
        THEN 'AIRFLOW_COMPOSER'
      
      -- GKE service accounts (Kubernetes workloads)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gke-prod|gke-[a-z0-9]+-sumatra')
        THEN 'GKE_WORKLOAD'
      
      -- Compute Engine default service accounts
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'\d+-compute@developer\.gserviceaccount\.com')
        THEN 'COMPUTE_ENGINE'
      
      -- CDP (Customer Data Platform)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(cdp|customer-data)')
        OR REGEXP_CONTAINS(LOWER(a.project_id), r'cdp')
        THEN 'CDP'
      
      -- ETL/Dataflow
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(dataflow|etl)')
        THEN 'ETL_DATAFLOW'
      
      -- ML/AI model serving and training
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(ml-|eddmodel|ai-platform)')
        OR REGEXP_CONTAINS(LOWER(a.project_id), r'ml-')
        THEN 'ML_INFERENCE'
      
      -- Analytics API and service backends (not external-facing)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'analytics-api-bigquery-access')
        THEN 'ANALYTICS_API'
      
      -- Generic service accounts (catch-all for remaining service accounts)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'iam\.gserviceaccount\.com$')
        AND NOT REGEXP_CONTAINS(LOWER(a.principal_email), r'(looker|metabase|monitor)')
        THEN 'SERVICE_ACCOUNT_OTHER'
      
      ELSE NULL
    END AS consumer_subcategory,
    
    -- QoS evaluation for automated processes
    -- Note: Proper QoS requires Composer schedule data (to be added in Phase 2)
    -- For now, using execution time as proxy (>30 min = potential issue)
    CASE 
      WHEN a.execution_time_seconds > 1800 THEN 'POTENTIALLY_SLOW'
      WHEN a.execution_time_seconds <= 1800 THEN 'NORMAL'
      ELSE 'UNKNOWN'
    END AS execution_speed_category,
    
    -- Job success/failure
    CASE 
      WHEN a.job_state = 'DONE' AND a.job_error IS NULL THEN 'SUCCESS'
      WHEN a.job_error IS NOT NULL THEN 'FAILED'
      ELSE 'UNKNOWN'
    END AS job_outcome,
    
    -- Cost calculation (slot-based for reserved capacity)
    -- Blended rate: ~$0.0494/slot-hour
    ROUND(SAFE_DIVIDE(a.total_slot_ms, 3600000) * 0.0494, 4) AS estimated_slot_cost_usd,
    
    -- Analysis period identifier
    analysis_period AS analysis_period
    
  FROM audit_deduplicated a
  
  -- Filter for automated processes only (use regex patterns)
  WHERE REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer|gke-prod|compute@developer|cdp|dataflow|etl|eddmodel|ml-|analytics-api)')
     OR REGEXP_CONTAINS(LOWER(a.project_id), r'(cdp|ml-)')
)

-- Final output: Automated process traffic with full attribution
SELECT
  -- Identifiers
  job_id,
  project_id,
  principal_email,
  location,
  analysis_period,
  
  -- Consumer classification
  'AUTOMATED' AS consumer_category,
  consumer_subcategory,
  
  -- Job details
  job_type,
  start_time,
  end_time,
  execution_time_seconds,
  ROUND(execution_time_seconds / 60.0, 2) AS execution_time_minutes,
  execution_speed_category,
  
  -- Job outcome
  job_outcome,
  job_state,
  SUBSTR(COALESCE(job_error.message, 'No error'), 1, 200) AS error_message_sample,
  
  -- Resource consumption
  total_slot_ms,
  approximate_slot_count,
  total_billed_bytes,
  ROUND(total_billed_bytes / POW(1024, 3), 2) AS total_billed_gb,
  estimated_slot_cost_usd,
  
  -- Reservation info
  reservation_name,
  
  -- Additional context
  user_agent,
  
  -- Query text sample for pattern analysis
  SUBSTR(query_text, 1, 500) AS query_text_sample

FROM automated_classified
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
  COUNT(DISTINCT principal_email) AS unique_service_accounts,
  COUNT(DISTINCT project_id) AS unique_projects,
  COUNT(DISTINCT DATE(start_time)) AS active_days,
  COUNT(DISTINCT airflow_dag_id) AS unique_dags,
  
  -- Success metrics
  COUNTIF(job_outcome = 'SUCCESS') AS success_count,
  COUNTIF(job_outcome = 'FAILED') AS failure_count,
  ROUND(COUNTIF(job_outcome = 'SUCCESS') / COUNT(*) * 100, 2) AS success_rate_pct,
  
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
  
  -- Cost metrics
  ROUND(SUM(estimated_slot_cost_usd), 2) AS total_estimated_cost_usd,
  ROUND(AVG(on_demand_cost_usd), 4) AS avg_cost_per_job_usd,
  
  -- Job type breakdown
  COUNTIF(job_type = 'QUERY') AS query_jobs,
  COUNTIF(job_type = 'LOAD') AS load_jobs,
  COUNTIF(job_type = 'EXTRACT') AS extract_jobs,
  COUNTIF(job_type = 'TABLE_COPY') AS copy_jobs

FROM automated_classified
GROUP BY consumer_subcategory
ORDER BY total_jobs DESC;
*/

-- ============================================================================
-- AIRFLOW DAG ANALYSIS (if DAG labels are available)
-- ============================================================================
-- Uncomment below to analyze performance by Airflow DAG
/*
SELECT
  airflow_dag_id,
  COUNT(*) AS total_executions,
  COUNT(DISTINCT airflow_task_id) AS unique_tasks,
  COUNTIF(job_outcome = 'SUCCESS') AS success_count,
  COUNTIF(job_outcome = 'FAILED') AS failure_count,
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
  SUM(on_demand_cost_usd) AS total_cost_usd
FROM automated_classified
WHERE airflow_dag_id IS NOT NULL
GROUP BY airflow_dag_id
ORDER BY total_executions DESC;
*/
>>>>>>> Incoming (Background Agent changes)
