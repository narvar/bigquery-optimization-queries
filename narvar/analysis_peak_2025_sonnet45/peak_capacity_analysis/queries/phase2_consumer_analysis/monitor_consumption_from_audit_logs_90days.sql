-- Monitor Consumption Analysis - Direct from Audit Logs (Last 90 Days)
-- Purpose: Validate Gap/Kohls consumption using source data
-- Bypasses traffic_classification to get real-time last 90 days
--
-- WARNING: This queries raw audit logs - more expensive than traffic_classification
-- Expected cost: ~5-10 GB (90 days of Monitor projects only)

DECLARE lookback_days INT64 DEFAULT 90;
DECLARE monitor_service_account STRING DEFAULT 'looker-prod@narvar-data-lake.iam.gserviceaccount.com';

WITH audit_data AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.projectId AS destination_project,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime AS start_time,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime AS end_time,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes AS total_billed_bytes,
    resource.labels.project_id AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id
  FROM 
    `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE
    -- Last 90 days
    DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL lookback_days DAY)
                        AND CURRENT_DATE()
    -- Monitor projects or Hub service account
    AND (
      resource.labels.project_id LIKE 'monitor-%'
      OR protopayload_auditlog.authenticationInfo.principalEmail = monitor_service_account
    )
    -- Completed queries only
    AND protopayload_auditlog.methodName = 'jobservice.jobcompleted'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
    -- Exclude errors and cache hits
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatus.state = 'DONE'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatus.error.code IS NULL
    -- Has slot consumption (not cache hit)
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs IS NOT NULL
),

-- Extract retailer_moniker from query text using same logic as traffic_classification
retailer_extraction AS (
  SELECT
    *,
    -- Try to extract retailer_moniker from WHERE clauses
    CASE
      -- Pattern 1: WHERE retailer_moniker = 'value'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r"retailer_moniker\s*=\s*['\"]([^'\"]+)['\"]")
        THEN REGEXP_EXTRACT(LOWER(query_text), r"retailer_moniker\s*=\s*['\"]([^'\"]+)['\"]")
      -- Pattern 2: WHERE retailer_moniker IN ('value')
      WHEN REGEXP_CONTAINS(LOWER(query_text), r"retailer_moniker\s+in\s*\(\s*['\"]([^'\"]+)['\"]")
        THEN REGEXP_EXTRACT(LOWER(query_text), r"retailer_moniker\s+in\s*\(\s*['\"]([^'\"]+)['\"]")
      -- Pattern 3: project_id contains retailer hash (monitor-{retailer}-us-prod)
      WHEN project_id LIKE 'monitor-%'
        AND project_id NOT LIKE 'monitor-base%'
        THEN REGEXP_EXTRACT(project_id, r'monitor-([^-]+)-')
      ELSE NULL
    END AS retailer_moniker,
    -- Calculate slot hours
    SAFE_DIVIDE(total_slot_ms, 1000 * 60 * 60) AS slot_hours,
    -- Calculate execution time (start_time and end_time are already TIMESTAMP type)
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS execution_time_seconds
  FROM audit_data
),

-- Calculate costs using reservation pricing (Method A approach)
monitor_consumption AS (
  SELECT
    retailer_moniker,
    COUNT(*) as query_count,
    SUM(slot_hours) as total_slot_hours,
    -- Use reserved pricing: $0.0494 per slot-hour (Method A)
    SUM(slot_hours * 0.0494) as estimated_cost_usd,
    MIN(DATE(start_time)) as first_query_date,
    MAX(DATE(start_time)) as last_query_date,
    COUNT(DISTINCT DATE(start_time)) as active_days,
    AVG(execution_time_seconds) as avg_execution_seconds,
    MAX(execution_time_seconds) as max_execution_seconds
  FROM retailer_extraction
  WHERE retailer_moniker IS NOT NULL
  GROUP BY retailer_moniker
)

SELECT
  retailer_moniker,
  query_count,
  total_slot_hours,
  ROUND(estimated_cost_usd, 2) as estimated_cost_usd,
  first_query_date,
  last_query_date,
  active_days,
  ROUND(query_count / NULLIF(active_days, 0), 2) as avg_queries_per_day,
  ROUND(avg_execution_seconds, 2) as avg_execution_seconds,
  ROUND(max_execution_seconds, 2) as max_execution_seconds
FROM monitor_consumption
ORDER BY estimated_cost_usd DESC;

-- Run this separately for summary stats:
-- SELECT
--   'Summary' as metric,
--   COUNT(DISTINCT retailer_moniker) as unique_retailers,
--   SUM(query_count) as total_queries,
--   ROUND(SUM(estimated_cost_usd), 2) as total_cost_usd,
--   MIN(first_query_date) as earliest_query,
--   MAX(last_query_date) as latest_query
-- FROM monitor_consumption;

