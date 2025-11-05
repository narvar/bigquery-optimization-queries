<<<<<<< Current (Your changes)
=======
-- ============================================================================
-- EXTRACT AIRFLOW/COMPOSER SERVICE ACCOUNTS
-- ============================================================================
-- Purpose: Identify potential Airflow/Composer service accounts from audit logs
--          by analyzing service account patterns, job scheduling patterns,
--          and caller metadata
--
-- This query helps build the initial list of automated process service accounts
-- User should review and validate the results
--
-- Cost estimate: ~2-10GB processed (depends on date range)
-- ============================================================================

-- Configuration parameters
DECLARE start_date DATE DEFAULT '2024-09-01';
DECLARE end_date DATE DEFAULT '2024-10-31';
DECLARE min_jobs_threshold INT64 DEFAULT 100; -- Minimum jobs to be considered automated

-- ============================================================================
-- MAIN QUERY: Service Account Pattern Analysis
-- ============================================================================

WITH
-- Extract all service account activity
service_account_activity AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime AS start_time,
    
    -- Caller information (hints at Airflow/Composer)
    protopayload_auditlog.requestMetadata.callerSuppliedUserAgent AS user_agent,
    protopayload_auditlog.requestMetadata.callerIp AS caller_ip,
    
    -- Job configuration hints
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.labels AS job_labels,
    
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS row_num
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN start_date AND end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
    AND protopayload_auditlog.authenticationInfo.principalEmail IS NOT NULL
    AND protopayload_auditlog.authenticationInfo.principalEmail != ""
    -- Filter for service accounts only
    AND protopayload_auditlog.authenticationInfo.principalEmail LIKE '%@%.iam.gserviceaccount.com'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
),

-- Deduplicate
deduplicated AS (
  SELECT * EXCEPT(row_num)
  FROM service_account_activity
  WHERE row_num = 1
),

-- Aggregate by service account with pattern analysis
service_account_patterns AS (
  SELECT
    principal_email,
    
    -- Volume metrics
    COUNT(*) AS total_jobs,
    COUNT(DISTINCT project_id) AS unique_projects,
    COUNT(DISTINCT DATE(start_time)) AS active_days,
    COUNT(DISTINCT DATE_TRUNC(start_time, WEEK)) AS active_weeks,
    
    -- Temporal patterns (hints at scheduling)
    COUNT(DISTINCT EXTRACT(HOUR FROM start_time)) AS unique_hours_active,
    COUNT(DISTINCT EXTRACT(DAYOFWEEK FROM start_time)) AS unique_days_of_week,
    
    -- Calculate job frequency (jobs per day)
    ROUND(COUNT(*) / COUNT(DISTINCT DATE(start_time)), 2) AS avg_jobs_per_day,
    
    -- User agent analysis
    ARRAY_AGG(DISTINCT user_agent IGNORE NULLS LIMIT 10) AS user_agents,
    
    -- Project list
    ARRAY_AGG(DISTINCT project_id LIMIT 20) AS projects,
    
    -- IP addresses (Composer typically uses consistent IPs)
    COUNT(DISTINCT caller_ip) AS unique_ips,
    ARRAY_AGG(DISTINCT caller_ip IGNORE NULLS LIMIT 5) AS caller_ips,
    
    -- Time range
    MIN(start_time) AS first_seen,
    MAX(start_time) AS last_seen,
    
    -- Pattern scoring for automation likelihood
    -- High score = likely automated
    (
      -- Regular daily activity
      CASE WHEN COUNT(*) / COUNT(DISTINCT DATE(start_time)) > 10 THEN 10 ELSE 0 END +
      
      -- Consistent scheduling (not spread across all hours)
      CASE WHEN COUNT(DISTINCT EXTRACT(HOUR FROM start_time)) < 12 THEN 5 ELSE 0 END +
      
      -- Active across multiple weeks
      CASE WHEN COUNT(DISTINCT DATE_TRUNC(start_time, WEEK)) >= 4 THEN 5 ELSE 0 END +
      
      -- High volume
      CASE WHEN COUNT(*) > 1000 THEN 10 WHEN COUNT(*) > 500 THEN 5 ELSE 0 END +
      
      -- Consistent IP usage
      CASE WHEN COUNT(DISTINCT caller_ip) <= 3 THEN 5 ELSE 0 END
      
    ) AS automation_score
    
  FROM deduplicated
  GROUP BY principal_email
),

-- Classify service accounts
classified_accounts AS (
  SELECT
    *,
    
    -- Classification based on patterns and naming
    CASE
      -- Airflow/Composer patterns
      WHEN LOWER(principal_email) LIKE '%airflow%' 
        OR LOWER(principal_email) LIKE '%composer%' 
        OR LOWER(principal_email) LIKE '%orchestr%' THEN 'AIRFLOW_COMPOSER'
      
      -- Looker/BI tools
      WHEN LOWER(principal_email) LIKE '%looker%' 
        OR LOWER(principal_email) LIKE '%metabase%' 
        OR principal_email = 'looker-prod@narvar-data-lake.iam.gserviceaccount.com'
        OR principal_email = 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com' THEN 'BI_TOOL'
      
      -- CDP patterns
      WHEN LOWER(principal_email) LIKE '%cdp%' 
        OR LOWER(principal_email) LIKE '%customer-data%' THEN 'CDP'
      
      -- ETL/Data processing
      WHEN LOWER(principal_email) LIKE '%etl%' 
        OR LOWER(principal_email) LIKE '%dataflow%' 
        OR LOWER(principal_email) LIKE '%data-processing%' THEN 'ETL_DATAFLOW'
      
      -- ML/Model serving
      WHEN LOWER(principal_email) LIKE '%ml-%' 
        OR LOWER(principal_email) LIKE '%-ml@%' 
        OR LOWER(principal_email) LIKE '%model%' THEN 'ML_INFERENCE'
      
      -- API/Service backends
      WHEN LOWER(principal_email) LIKE '%api%' 
        OR LOWER(principal_email) LIKE '%service%' THEN 'API_SERVICE'
      
      -- High automation score but unclear category
      WHEN automation_score >= 20 THEN 'AUTOMATED_UNKNOWN'
      
      ELSE 'MANUAL_OR_LOW_VOLUME'
    END AS account_classification,
    
    -- Confidence level
    CASE
      WHEN automation_score >= 30 THEN 'HIGH'
      WHEN automation_score >= 20 THEN 'MEDIUM'
      WHEN automation_score >= 10 THEN 'LOW'
      ELSE 'VERY_LOW'
    END AS automation_confidence
    
  FROM service_account_patterns
  WHERE total_jobs >= min_jobs_threshold
)

-- Final output: Service accounts ranked by automation likelihood
SELECT
  principal_email,
  account_classification,
  automation_confidence,
  automation_score,
  
  -- Volume metrics
  total_jobs,
  avg_jobs_per_day,
  unique_projects,
  active_days,
  active_weeks,
  
  -- Temporal patterns
  unique_hours_active,
  unique_days_of_week,
  
  -- Network patterns
  unique_ips,
  caller_ips,
  
  -- User agents (hints at client type)
  user_agents,
  
  -- Time range
  first_seen,
  last_seen,
  DATE_DIFF(DATE(last_seen), DATE(first_seen), DAY) AS days_active_span,
  
  -- Projects
  projects,
  
  -- Recommendation
  CASE
    WHEN account_classification = 'AIRFLOW_COMPOSER' AND automation_confidence IN ('HIGH', 'MEDIUM') 
      THEN '✓ INCLUDE in Automated Process list'
    WHEN account_classification = 'BI_TOOL' 
      THEN '⚠ BI Tool - classify separately'
    WHEN account_classification IN ('CDP', 'ETL_DATAFLOW') AND automation_confidence IN ('HIGH', 'MEDIUM')
      THEN '✓ INCLUDE in Automated Process list'
    WHEN account_classification = 'AUTOMATED_UNKNOWN' AND automation_confidence = 'HIGH'
      THEN '? REVIEW - likely automated'
    ELSE '✗ Exclude or review manually'
  END AS recommendation

FROM classified_accounts
ORDER BY 
  automation_score DESC,
  total_jobs DESC;

-- ============================================================================
-- USER AGENT ANALYSIS (Uncomment to see detailed user agent patterns)
-- ============================================================================
/*
WITH
service_account_activity AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    protopayload_auditlog.requestMetadata.callerSuppliedUserAgent AS user_agent,
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS row_num
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN start_date AND end_date
    AND protopayload_auditlog.authenticationInfo.principalEmail LIKE '%@%.iam.gserviceaccount.com'
    AND protopayload_auditlog.requestMetadata.callerSuppliedUserAgent IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
)

SELECT
  user_agent,
  COUNT(*) AS job_count,
  COUNT(DISTINCT principal_email) AS unique_service_accounts,
  ARRAY_AGG(DISTINCT principal_email LIMIT 10) AS sample_accounts
FROM service_account_activity
WHERE row_num = 1
GROUP BY user_agent
ORDER BY job_count DESC
LIMIT 50;
*/
>>>>>>> Incoming (Background Agent changes)
