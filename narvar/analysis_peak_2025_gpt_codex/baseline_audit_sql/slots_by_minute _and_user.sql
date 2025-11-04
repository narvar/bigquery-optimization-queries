-- This query returns how many slots were used on a per minute basis by user.
-- Adds reusable root-job filtering (parentJobName) and fixes user alias.

DECLARE interval_in_days INT64 DEFAULT 7;
DECLARE include_child_jobs BOOL DEFAULT FALSE;

WITH raw_events AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS user_email,
    CASE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName
      WHEN 'query_job_completed' THEN 'QUERY'
      WHEN 'load_job_completed' THEN 'LOAD'
      WHEN 'extract_job_completed' THEN 'EXTRACT'
      WHEN 'table_copy_job_completed' THEN 'TABLE COPY'
    END AS eventType,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.load,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.extract,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.tableCopy,
    timestamp,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS jobId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.parentJobName AS parentJobName,
    COALESCE(
      protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.parentJobName,
      protopayload_auditlog.servicedata_v1_bigquery.job.jobName.jobId
    ) AS rootJobId,
    protopayload_auditlog.servicedata_v1_bigquery.job.jobName.location,
    protopayload_auditlog.servicedata_v1_bigquery.job.jobName.projectId AS billingProjectId,
    protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.startTime,
    protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.endTime,
    protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.totalBilledBytes,
    protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.totalSlotMs,
    SAFE_DIVIDE(
      protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.totalSlotMs,
      TIMESTAMP_DIFF(
        protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.endTime,
        protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.startTime,
        MILLISECOND
      )
    ) AS slotCount
  FROM
    `<project>.<dataset>.cloudaudit_googleapis_com_data_access`
  WHERE
    protopayload_auditlog.servicedata_v1_bigquery.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
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
    * EXCEPT(int)
  FROM
    differences,
    UNNEST(int) AS minute
)

SELECT
  minute,
  user_email,
  eventType,
  SUM(slotCount) AS slotCount
FROM
  byMinutes
WHERE
  slotCount IS NOT NULL
GROUP BY
  minute,
  eventType,
  user_email
ORDER BY
  minute ASC;
