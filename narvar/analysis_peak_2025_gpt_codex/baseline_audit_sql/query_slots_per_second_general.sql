-- Slots consumed per second for query jobs across all billing projects with root-job filtering.

DECLARE interval_in_days INT64 DEFAULT 7;
DECLARE include_child_jobs BOOL DEFAULT FALSE;

WITH raw_events AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS user_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query,
    'QUERY' AS eventType,
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
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
    AND protopayload_auditlog.authenticationInfo.principalEmail IS NOT NULL
    AND protopayload_auditlog.authenticationInfo.principalEmail != ""
    AND DATE(protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.startTime) >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND protopayload_auditlog.servicedata_v1_bigquery.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.job.jobName.projectId IS NOT NULL
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
    GENERATE_TIMESTAMP_ARRAY(startTime, endTime, INTERVAL 1 SECOND) AS int
  FROM
    jobsDeduplicated
),
bySeconds AS (
  SELECT
    * EXCEPT(int)
  FROM
    differences,
    UNNEST(int) AS second
)

SELECT
  second,
  eventType,
  SUM(slotCount) AS slotCount
FROM
  bySeconds
WHERE
  slotCount IS NOT NULL
GROUP BY
  second,
  eventType
ORDER BY
  second ASC;
