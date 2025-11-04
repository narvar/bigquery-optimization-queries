-- Classification Accuracy Validation: Spot-checks classification against known patterns
-- Purpose: Validates classification logic by checking specific known service accounts and projects
--
-- This query:
--   1. Verifies known service accounts are classified correctly
--   2. Checks monitor project classification logic
--   3. Identifies potential misclassifications
--   4. Provides sample jobs for manual verification
--
-- Parameters:
--   interval_in_days: Number of days to analyze (default: 7 for focused validation)
--   sample_size_per_category: Number of sample jobs to return per category (default: 10)
--
-- Output Schema:
--   validation_type: STRING - Type of validation check
--   expected_category: STRING - Expected classification
--   actual_category: STRING - Actual classification from unified logic
--   status: STRING - PASS, FAIL, or REVIEW
--   job_id: STRING - Sample job ID for review
--   user_email: STRING - User/service account email
--   project_id: STRING - Project ID
--   notes: STRING - Additional context
--
-- Cost Warning: This query processes audit logs with multiple CTEs.
--               For 7 days, expect to process 1-5GB depending on traffic volume.

DECLARE interval_in_days INT64 DEFAULT 7;
DECLARE sample_size_per_category INT64 DEFAULT 10;

-- Known patterns to validate
WITH known_patterns AS (
  SELECT 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com' AS user_email, NULL AS project_id, 'INTERNAL' AS expected_category, 'Metabase service account' AS description
  UNION ALL SELECT 'looker-prod@narvar-data-lake.iam.gserviceaccount.com', NULL, 'EXTERNAL_CRITICAL', 'Looker/Hub service account'
),
monitor_mappings AS (
  SELECT DISTINCT 
    retailer_moniker, 
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-prod') AS project_id,
    'EXTERNAL_CRITICAL' AS expected_category,
    CONCAT('Monitor project for ', retailer_moniker) AS description
  FROM `reporting.t_return_details` 
  WHERE DATE(return_created_date) >= DATE('2025-01-01')
  LIMIT 10  -- Limit to 10 monitor projects for validation
),
audit_log_base AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS user_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
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
    startTime
  FROM audit_log_base
  WHERE _rnk = 1
),
classified_jobs AS (
  SELECT
    jd.jobId,
    jd.user_email,
    jd.project_id,
    jd.startTime,
    CASE
      WHEN jd.user_email = 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com' THEN 'INTERNAL'
      WHEN jd.user_email = 'looker-prod@narvar-data-lake.iam.gserviceaccount.com' THEN 'EXTERNAL_CRITICAL'
      WHEN jd.project_id IN (SELECT project_id FROM monitor_mappings) THEN 'EXTERNAL_CRITICAL'
      WHEN jd.user_email LIKE '%.iam.gserviceaccount.com' THEN 'AUTOMATED_CRITICAL'
      ELSE 'INTERNAL'
    END AS actual_category
  FROM jobs_deduplicated jd
),
-- Validation 1: Known service accounts
service_account_validation AS (
  SELECT
    'Known Service Account' AS validation_type,
    kp.expected_category,
    cj.actual_category,
    CASE 
      WHEN cj.actual_category = kp.expected_category THEN 'PASS'
      ELSE 'FAIL'
    END AS status,
    cj.jobId,
    cj.user_email,
    cj.project_id,
    cj.startTime,
    kp.description AS notes
  FROM known_patterns kp
  INNER JOIN classified_jobs cj
    ON kp.user_email = cj.user_email
  WHERE kp.user_email IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY kp.description ORDER BY cj.startTime DESC) <= sample_size_per_category
),
-- Validation 2: Monitor projects
monitor_project_validation AS (
  SELECT
    'Monitor Project' AS validation_type,
    mm.expected_category,
    cj.actual_category,
    CASE 
      WHEN cj.actual_category = mm.expected_category THEN 'PASS'
      ELSE 'FAIL'
    END AS status,
    cj.jobId,
    cj.user_email,
    cj.project_id,
    cj.startTime,
    mm.description AS notes
  FROM monitor_mappings mm
  INNER JOIN classified_jobs cj
    ON mm.project_id = cj.project_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY mm.project_id ORDER BY cj.startTime DESC) <= sample_size_per_category
),
-- Validation 3: Other service accounts (should be AUTOMATED_CRITICAL)
other_service_account_validation AS (
  SELECT
    'Other Service Account' AS validation_type,
    'AUTOMATED_CRITICAL' AS expected_category,
    cj.actual_category,
    CASE 
      WHEN cj.actual_category = 'AUTOMATED_CRITICAL' THEN 'PASS'
      WHEN cj.user_email IN ('metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com', 'looker-prod@narvar-data-lake.iam.gserviceaccount.com') THEN 'PASS'  -- Known exceptions
      ELSE 'REVIEW'
    END AS status,
    cj.jobId,
    cj.user_email,
    cj.project_id,
    cj.startTime,
    CONCAT('Service account: ', cj.user_email) AS notes
  FROM classified_jobs cj
  WHERE cj.user_email LIKE '%.iam.gserviceaccount.com'
    AND cj.user_email NOT IN ('metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com', 'looker-prod@narvar-data-lake.iam.gserviceaccount.com')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY cj.user_email ORDER BY cj.startTime DESC) <= sample_size_per_category
)
SELECT * FROM service_account_validation
UNION ALL
SELECT * FROM monitor_project_validation
UNION ALL
SELECT * FROM other_service_account_validation
ORDER BY 
  status DESC,  -- FAIL first, then REVIEW, then PASS
  validation_type,
  startTime DESC;

