-- Concurrent query jobs by minute with root-job filtering.
DECLARE interval_in_days INT64 DEFAULT 7;
DECLARE include_child_jobs BOOL DEFAULT FALSE;

BEGIN
WITH raw_events AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS user_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS jobId,
    protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.parentJobName AS parentJobName,
    COALESCE(
      protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.parentJobName,
      protopayload_auditlog.servicedata_v1_bigquery.job.jobName.jobId
    ) AS rootJobId,
    TIMESTAMP_TRUNC(protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.startTime, MINUTE) AS startTime,
    TIMESTAMP_TRUNC(protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.endTime, MINUTE) AS endTime,
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.startTime,
      MINUTE
    ) AS diff,
    timestamp
  FROM
    `<project>.<dataset>.cloudaudit_googleapis_com_data_access`
  WHERE
    protopayload_auditlog.servicedata_v1_bigquery.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
    AND protopayload_auditlog.authenticationInfo.principalEmail IS NOT NULL
    AND protopayload_auditlog.authenticationInfo.principalEmail != ""
    AND DATE(protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.startTime) >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND protopayload_auditlog.servicedata_v1_bigquery.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.job.jobName.projectId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.job.jobName.projectId = '<project-name>'
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
),
root_ranked AS (
  SELECT
    raw_events.*,
    ROW_NUMBER() OVER (PARTITION BY rootJobId ORDER BY timestamp DESC) AS root_rnk
  FROM
    raw_events
  WHERE
    include_child_jobs
    OR raw_events.parentJobName IS NULL
),
jobsDeduplicated AS (
  SELECT
    * EXCEPT(root_rnk)
  FROM
    root_ranked
  WHERE
    root_rnk = 1
),
differences AS (
  SELECT
    *,
    GENERATE_TIMESTAMP_ARRAY(startTime, endTime, INTERVAL 1 MINUTE) AS int
  FROM
    jobsDeduplicated
),
byMinutes AS (
  SELECT
    *
  FROM
    differences,
    UNNEST(int) AS minute
)

SELECT
  COUNT(*) AS jobCounter,
  minute
FROM
  byMinutes
GROUP BY
  minute
ORDER BY
  minute ASC;
END;
