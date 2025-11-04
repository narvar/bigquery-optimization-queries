-- Classification Coverage Validation: Verifies all jobs are classified and identifies gaps
-- Purpose: Validates that unified_traffic_classification.sql properly classifies all traffic
--
-- This query:
--   1. Compares total job counts between raw audit logs and unified classification
--   2. Identifies any unclassified jobs
--   3. Shows classification distribution across categories
--   4. Flags potential classification gaps
--
-- Parameters:
--   interval_in_days: Number of days to analyze (default: 30 for validation)
--
-- Output Schema:
--   metric: STRING - Metric name
--   value: INT64/FLOAT64 - Metric value
--   percentage: FLOAT64 - Percentage of total (where applicable)
--
-- Cost Warning: This query processes audit logs twice (once for baseline, once for classification).
--               For 30 days, expect to process 5-20GB depending on traffic volume.
--               Start with 7 days for initial validation.

DECLARE interval_in_days INT64 DEFAULT 30;

-- Step 1: Get baseline job count from audit logs
WITH audit_log_baseline AS (
  SELECT
    COUNT(DISTINCT protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId) AS total_jobs
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
-- Step 2: Get classified job counts (reusing logic from unified_traffic_classification.sql)
min_date_for_retailer_mapping AS (
  SELECT DATE('2025-01-01') AS min_date
),
monitor_mappings AS (
  SELECT DISTINCT 
    retailer_moniker, 
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-prod') AS project_id
  FROM `reporting.t_return_details` 
  WHERE DATE(return_created_date) >= (SELECT min_date FROM min_date_for_retailer_mapping)
),
audit_log_base AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS user_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
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
    project_id
  FROM audit_log_base
  WHERE _rnk = 1
),
classified_jobs AS (
  SELECT
    jobId,
    CASE
      WHEN user_email = 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com' THEN 'INTERNAL'
      WHEN user_email = 'looker-prod@narvar-data-lake.iam.gserviceaccount.com' THEN 'EXTERNAL_CRITICAL'
      WHEN project_id IN (SELECT project_id FROM monitor_mappings) THEN 'EXTERNAL_CRITICAL'
      WHEN user_email LIKE '%.iam.gserviceaccount.com' THEN 'AUTOMATED_CRITICAL'
      ELSE 'INTERNAL'
    END AS consumer_category
  FROM jobs_deduplicated
),
classification_summary AS (
  SELECT
    consumer_category,
    COUNT(DISTINCT jobId) AS classified_jobs
  FROM classified_jobs
  GROUP BY consumer_category
)
-- Step 3: Compare and report
SELECT
  'Total Jobs (Audit Log Baseline)' AS metric,
  CAST(alb.total_jobs AS INT64) AS value,
  100.0 AS percentage
FROM audit_log_baseline alb

UNION ALL

SELECT
  'Total Jobs (Classified)' AS metric,
  CAST(SUM(cs.classified_jobs) AS INT64) AS value,
  100.0 AS percentage
FROM classification_summary cs

UNION ALL

SELECT
  CONCAT('Classified as ', cs.consumer_category) AS metric,
  CAST(cs.classified_jobs AS INT64) AS value,
  ROUND(SAFE_DIVIDE(cs.classified_jobs * 100.0, alb.total_jobs), 2) AS percentage
FROM classification_summary cs
CROSS JOIN audit_log_baseline alb

UNION ALL

SELECT
  'Classification Gap' AS metric,
  CAST(alb.total_jobs - SUM(cs.classified_jobs) AS INT64) AS value,
  ROUND(SAFE_DIVIDE((alb.total_jobs - SUM(cs.classified_jobs)) * 100.0, alb.total_jobs), 2) AS percentage
FROM classification_summary cs
CROSS JOIN audit_log_baseline alb
GROUP BY alb.total_jobs

ORDER BY 
  CASE metric
    WHEN 'Total Jobs (Audit Log Baseline)' THEN 1
    WHEN 'Total Jobs (Classified)' THEN 2
    WHEN 'Classification Gap' THEN 9
    WHEN 'Classified as INTERNAL' THEN 3
    WHEN 'Classified as EXTERNAL_CRITICAL' THEN 4
    WHEN 'Classified as AUTOMATED_CRITICAL' THEN 5
    ELSE 6
  END;

