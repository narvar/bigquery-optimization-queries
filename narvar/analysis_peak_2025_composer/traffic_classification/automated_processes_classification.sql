-- Automated Processes Classification: Identifies and categorizes automated BigQuery processes
-- Purpose: Classifies service account-based workloads (Airflow, CDP, etc.) as AUTOMATED_CRITICAL
--
-- This query identifies service accounts that are NOT Metabase or Looker (Hub) service accounts,
-- which are likely automated processes such as:
--   - Airflow workflows
--   - CDP (Customer Data Platform) processes
--   - Other scheduled/automated data pipelines
--
-- Known service accounts to exclude:
--   - metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com (INTERNAL)
--   - looker-prod@narvar-data-lake.iam.gserviceaccount.com (EXTERNAL_CRITICAL - Hub)
--
-- Parameters:
--   interval_in_days: Number of days in the past to search (default: 365)
--
-- Output Schema:
--   service_account: STRING - Service account email
--   project_id: STRING - Project ID where jobs ran
--   job_count: INT64 - Number of jobs executed
--   total_slot_ms: INT64 - Total slot milliseconds consumed
--   total_billed_bytes: INT64 - Total bytes billed
--   avg_execution_time_ms: FLOAT64 - Average job execution time
--   job_types: ARRAY<STRING> - List of job types (QUERY, LOAD, EXTRACT, etc.)
--   sample_job_ids: ARRAY<STRING> - Sample job IDs for investigation
--
-- Cost Warning: This query processes audit logs for all service accounts.
--               For 365 days, expect to process 20-100GB+ depending on traffic volume.
--               Consider using smaller intervals or filtering by specific service accounts for exploration.

DECLARE interval_in_days INT64 DEFAULT 365;
DECLARE known_service_accounts_to_exclude ARRAY<STRING> DEFAULT [
  'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com',
  'looker-prod@narvar-data-lake.iam.gserviceaccount.com'
];

WITH src AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS service_account,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId,
    CASE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName
      WHEN 'query_job_completed' THEN 'QUERY'
      WHEN 'load_job_completed' THEN 'LOAD'
      WHEN 'extract_job_completed' THEN 'EXTRACT'
      WHEN 'table_copy_job_completed' THEN 'TABLE_COPY'
      ELSE 'OTHER'
    END AS job_type,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
      MILLISECOND
    ) AS execution_time_ms,
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS _rnk
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
    AND protopayload_auditlog.authenticationInfo.principalEmail IS NOT NULL
    AND protopayload_auditlog.authenticationInfo.principalEmail != ""
    -- Filter for service accounts only (end with .iam.gserviceaccount.com)
    AND protopayload_auditlog.authenticationInfo.principalEmail LIKE '%.iam.gserviceaccount.com'
    -- Exclude known service accounts (Metabase, Looker)
    AND protopayload_auditlog.authenticationInfo.principalEmail NOT IN UNNEST(known_service_accounts_to_exclude)
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId IS NOT NULL
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
),
jobsDeduplicated AS (
  SELECT
    * EXCEPT(_rnk)
  FROM
    src
  WHERE
    _rnk = 1
),
aggregated AS (
  SELECT
    service_account,
    project_id,
    COUNT(DISTINCT jobId) AS job_count,
    SUM(totalSlotMs) AS total_slot_ms,
    SUM(totalBilledBytes) AS total_billed_bytes,
    AVG(execution_time_ms) AS avg_execution_time_ms,
    ARRAY_AGG(DISTINCT job_type) AS job_types,
    ARRAY_AGG(DISTINCT jobId LIMIT 10) AS sample_job_ids
  FROM jobsDeduplicated
  GROUP BY
    service_account,
    project_id
)

SELECT
  service_account,
  project_id,
  job_count,
  total_slot_ms,
  total_billed_bytes,
  avg_execution_time_ms,
  job_types,
  sample_job_ids
FROM aggregated
ORDER BY total_slot_ms DESC;

