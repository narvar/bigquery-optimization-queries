-- Internal Users Classification: Identifies and enriches Metabase users from audit logs
-- Purpose: Classifies queries from Metabase service account and enriches with individual user information
--
-- Metabase queries include a comment at the top with the Metabase user ID.
-- This query:
--   1. Extracts Metabase user ID from query comments
--   2. Joins with Metabase DB (BQ linked resource) to enrich with user email and details
--
-- Service Account: metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com
--
-- Parameters:
--   interval_in_days: Number of days in the past to search (default: 365)
--   metabase_db_project: Project ID where Metabase database is located (default: narvar-data-lake)
--   metabase_db_dataset: Dataset name for Metabase database (default: metabase - adjust as needed)
--   metabase_db_table: Table name for Metabase users (default: core_user - adjust as needed)
--
-- Output Schema:
--   job_id: STRING - BigQuery job ID
--   service_account: STRING - Metabase service account email
--   metabase_user_id: STRING - Metabase user ID extracted from query comment
--   metabase_user_email: STRING - User email from Metabase DB (if found)
--   project_id: STRING - Project ID where job ran
--   start_time: TIMESTAMP - Job start time
--   execution_time_ms: INT64 - Job execution time in milliseconds
--   total_slot_ms: INT64 - Total slot milliseconds consumed
--   query_text_preview: STRING - First 500 chars of query text
--
-- Cost Warning: This query processes audit logs and joins with Metabase database.
--               For 365 days, expect to process 10-50GB+ depending on Metabase traffic volume.
--               The query text extraction uses REGEXP which may increase processing cost.

DECLARE interval_in_days INT64 DEFAULT 365;
DECLARE metabase_db_project STRING DEFAULT 'narvar-data-lake';
DECLARE metabase_db_dataset STRING DEFAULT 'metabase';  -- Adjust if Metabase DB is in different dataset
DECLARE metabase_db_table STRING DEFAULT 'core_user';   -- Adjust if table name differs

WITH src AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS service_account,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
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
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE 'query_job_completed'
    AND protopayload_auditlog.authenticationInfo.principalEmail IS NOT NULL
    AND protopayload_auditlog.authenticationInfo.principalEmail != ""
    -- Filter for Metabase service account
    AND protopayload_auditlog.authenticationInfo.principalEmail = 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com'
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
jobsWithUserIds AS (
  SELECT
    jobId,
    service_account,
    project_id,
    startTime,
    endTime,
    execution_time_ms,
    totalSlotMs,
    query_text,
    -- Extract Metabase user ID from query comments
    -- Pattern: Look for comments at the top of query that contain user ID
    -- Common patterns: -- user_id: 123 or -- User: 123 or similar
    -- This regex looks for numeric user IDs in comments (adjust pattern as needed)
    REGEXP_EXTRACT(query_text, r'(?i)--\s*(?:user|user_id|metabase[_\s]*user[_\s]*id)[:\s]*(\d+)', 1) AS metabase_user_id,
    SUBSTR(query_text, 0, 500) AS query_text_preview
  FROM jobsDeduplicated
)

SELECT
  j.jobId AS job_id,
  j.service_account,
  j.metabase_user_id,
  mu.email AS metabase_user_email,
  mu.first_name,
  mu.last_name,
  j.project_id,
  j.startTime AS start_time,
  j.execution_time_ms,
  j.totalSlotMs AS total_slot_ms,
  j.query_text_preview
FROM jobsWithUserIds j
LEFT JOIN (
  SELECT
    CAST(id AS STRING) AS user_id,
    email,
    first_name,
    last_name
  FROM CONCAT(metabase_db_project, '.', metabase_db_dataset, '.', metabase_db_table)
) mu
ON j.metabase_user_id = mu.user_id
ORDER BY j.startTime DESC;

