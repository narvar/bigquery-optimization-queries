-- Automated Schedules Inference: Infers execution schedules from temporal patterns in audit logs
-- Purpose: Identifies recurring execution patterns for automated processes to understand scheduling
--
-- This query analyzes time-based patterns in service account job executions to infer:
--   - Execution frequency (hourly, daily, weekly, etc.)
--   - Preferred execution windows (time-of-day patterns)
--   - Schedule consistency
--
-- This complements information from GitHub repos and Composer logs by providing
-- actual execution patterns from audit logs.
--
-- Parameters:
--   interval_in_days: Number of days to analyze (default: 90 for quarterly analysis)
--   min_executions: Minimum number of executions to consider for pattern inference (default: 10)
--
-- Output Schema:
--   service_account: STRING - Service account email
--   project_id: STRING - Project ID
--   total_executions: INT64 - Total number of job executions
--   date_range_start: DATE - Start of analysis period
--   date_range_end: DATE - End of analysis period
--   avg_executions_per_day: FLOAT64 - Average executions per day
--   preferred_hour: INT64 - Most common execution hour (0-23)
--   preferred_day_of_week: INT64 - Most common day of week (1=Monday, 7=Sunday)
--   execution_times: ARRAY<TIMESTAMP> - Sample execution times
--   inferred_schedule: STRING - Inferred schedule description
--   schedule_confidence: STRING - Confidence level (HIGH, MEDIUM, LOW)
--
-- Cost Warning: This query processes audit logs and performs temporal analysis.
--               For 90 days, expect to process 5-20GB depending on traffic volume.

DECLARE interval_in_days INT64 DEFAULT 90;
DECLARE min_executions INT64 DEFAULT 10;
DECLARE known_service_accounts_to_exclude ARRAY<STRING> DEFAULT [
  'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com',
  'looker-prod@narvar-data-lake.iam.gserviceaccount.com'
];

WITH src AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS service_account,
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
    AND protopayload_auditlog.authenticationInfo.principalEmail LIKE '%.iam.gserviceaccount.com'
    AND protopayload_auditlog.authenticationInfo.principalEmail NOT IN UNNEST(known_service_accounts_to_exclude)
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId IS NOT NULL
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
),
jobsDeduplicated AS (
  SELECT
    service_account,
    project_id,
    startTime
  FROM
    src
  WHERE
    _rnk = 1
),
temporalFeatures AS (
  SELECT
    service_account,
    project_id,
    startTime,
    EXTRACT(HOUR FROM startTime) AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM startTime) AS day_of_week,  -- 1=Sunday, 7=Saturday
    DATE(startTime) AS execution_date
  FROM jobsDeduplicated
),
aggregated AS (
  SELECT
    service_account,
    project_id,
    COUNT(*) AS total_executions,
    MIN(DATE(startTime)) AS date_range_start,
    MAX(DATE(startTime)) AS date_range_end,
    COUNT(*) / CAST(DATE_DIFF(MAX(DATE(startTime)), MIN(DATE(startTime)), DAY) + 1 AS FLOAT64) AS avg_executions_per_day,
    APPROX_TOP_COUNT(hour_of_day, 1)[OFFSET(0)].value AS preferred_hour,
    APPROX_TOP_COUNT(day_of_week, 1)[OFFSET(0)].value AS preferred_day_of_week,
    ARRAY_AGG(startTime ORDER BY startTime LIMIT 20) AS sample_execution_times
  FROM temporalFeatures
  GROUP BY
    service_account,
    project_id
),
withInferredSchedule AS (
  SELECT
    service_account,
    project_id,
    total_executions,
    date_range_start,
    date_range_end,
    avg_executions_per_day,
    preferred_hour,
    preferred_day_of_week,
    sample_execution_times,
    CASE
      WHEN avg_executions_per_day >= 23 THEN 'HOURLY'
      WHEN avg_executions_per_day >= 1.8 AND avg_executions_per_day < 2.5 THEN 'TWICE_DAILY'
      WHEN avg_executions_per_day >= 0.8 AND avg_executions_per_day < 1.2 THEN 'DAILY'
      WHEN avg_executions_per_day >= 0.13 AND avg_executions_per_day < 0.17 THEN 'WEEKLY'
      WHEN avg_executions_per_day < 0.05 THEN 'MONTHLY_OR_LESS'
      ELSE 'IRREGULAR'
    END AS inferred_schedule,
    CASE
      WHEN total_executions >= 50 THEN 'HIGH'
      WHEN total_executions >= 20 THEN 'MEDIUM'
      ELSE 'LOW'
    END AS schedule_confidence
  FROM aggregated
  WHERE total_executions >= min_executions
)

SELECT
  service_account,
  project_id,
  total_executions,
  date_range_start,
  date_range_end,
  avg_executions_per_day,
  preferred_hour,
  preferred_day_of_week,
  sample_execution_times,
  inferred_schedule,
  schedule_confidence
FROM withInferredSchedule
ORDER BY total_executions DESC;

