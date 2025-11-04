-- Sample Verification Query: Provides random samples for manual classification verification
-- Purpose: Generates random samples of classified jobs for manual spot-checking
--
-- This query provides:
--   1. Random samples from each category for manual review
--   2. Key fields needed for verification (user, project, query preview)
--   3. Classification reasoning context
--
-- Parameters:
--   interval_in_days: Number of days to sample from (default: 7)
--   samples_per_category: Number of random samples per category (default: 20)
--
-- Output Schema:
--   consumer_category: STRING - Classification category
--   job_id: STRING - BigQuery job ID
--   user_email: STRING - User/service account email
--   project_id: STRING - Project ID
--   start_time: TIMESTAMP - Job start time
--   execution_time_ms: INT64 - Execution time
--   query_preview: STRING - First 200 chars of query (if available)
--   classification_reason: STRING - Explanation of why this was classified this way
--
-- Cost Warning: This query processes audit logs and includes query text extraction.
--               For 7 days, expect to process 1-5GB depending on traffic volume.

DECLARE interval_in_days INT64 DEFAULT 7;
DECLARE samples_per_category INT64 DEFAULT 20;

WITH monitor_mappings AS (
  SELECT DISTINCT 
    retailer_moniker, 
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-prod') AS project_id
  FROM `reporting.t_return_details` 
  WHERE DATE(return_created_date) >= DATE('2025-01-01')
),
audit_log_base AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS user_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
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
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId IS NOT NULL
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
),
jobs_deduplicated AS (
  SELECT
    user_email,
    jobId,
    project_id,
    startTime,
    endTime,
    query_text,
    TIMESTAMP_DIFF(endTime, startTime, MILLISECOND) AS execution_time_ms
  FROM audit_log_base
  WHERE _rnk = 1
),
classified_jobs AS (
  SELECT
    jd.*,
    CASE
      WHEN jd.user_email = 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com' THEN 'INTERNAL'
      WHEN jd.user_email = 'looker-prod@narvar-data-lake.iam.gserviceaccount.com' THEN 'EXTERNAL_CRITICAL'
      WHEN jd.project_id IN (SELECT project_id FROM monitor_mappings) THEN 'EXTERNAL_CRITICAL'
      WHEN jd.user_email LIKE '%.iam.gserviceaccount.com' THEN 'AUTOMATED_CRITICAL'
      ELSE 'INTERNAL'
    END AS consumer_category,
    CASE
      WHEN jd.user_email = 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com' THEN 'Metabase service account'
      WHEN jd.user_email = 'looker-prod@narvar-data-lake.iam.gserviceaccount.com' THEN 'Looker/Hub service account'
      WHEN jd.project_id IN (SELECT project_id FROM monitor_mappings) THEN CONCAT('Monitor project: ', mm.retailer_moniker)
      WHEN jd.user_email LIKE '%.iam.gserviceaccount.com' THEN 'Service account-based automated process'
      ELSE 'Human user or other'
    END AS classification_reason
  FROM jobs_deduplicated jd
  LEFT JOIN monitor_mappings mm
    ON jd.project_id = mm.project_id
),
sampled_jobs AS (
  SELECT
    consumer_category,
    jobId AS job_id,
    user_email,
    project_id,
    startTime AS start_time,
    execution_time_ms,
    SUBSTR(COALESCE(query_text, ''), 0, 200) AS query_preview,
    classification_reason
  FROM classified_jobs
  WHERE RAND() < (samples_per_category * 1.0 / COUNT(*) OVER (PARTITION BY consumer_category))
)
SELECT
  consumer_category,
  job_id,
  user_email,
  project_id,
  start_time,
  execution_time_ms,
  query_preview,
  classification_reason
FROM sampled_jobs
QUALIFY ROW_NUMBER() OVER (PARTITION BY consumer_category ORDER BY RAND()) <= samples_per_category
ORDER BY 
  consumer_category,
  RAND();

