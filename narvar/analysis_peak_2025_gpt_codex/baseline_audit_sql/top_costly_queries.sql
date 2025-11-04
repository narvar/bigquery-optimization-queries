-- Returns queries with highest billed bytes over the configured lookback.
-- Adds reusable parentJobName filtering to avoid double counting child script jobs.

DECLARE interval_in_days INT64 DEFAULT 700;
DECLARE include_child_jobs BOOL DEFAULT FALSE;

WITH raw_events AS (
  SELECT
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS jobId,
    protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.parentJobName AS parentJobName,
    COALESCE(
      protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.parentJobName,
      protopayload_auditlog.servicedata_v1_bigquery.job.jobName.jobId
    ) AS rootJobId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS queryText,
    SHA256(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query) AS hashed,
    COALESCE(protopayload_auditlog.servicedata_v1_bigquery.job.jobStatistics.totalBilledBytes, 0) AS totalBilledBytes,
    timestamp
  FROM
    `<project>.<dataset>.cloudaudit_googleapis_com_data_access`
  WHERE
    protopayload_auditlog.servicedata_v1_bigquery.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
    AND protopayload_auditlog.authenticationInfo.principalEmail IS NOT NULL
    AND protopayload_auditlog.authenticationInfo.principalEmail != ""
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
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
aggregated AS (
  SELECT
    queryText,
    hashed,
    COUNT(*) AS queryCount,
    SUM(totalBilledBytes) AS totalBytesBilled
  FROM
    jobsDeduplicated
  GROUP BY
    queryText,
    hashed
)

SELECT
  queryText AS query,
  queryCount,
  ROUND(COALESCE(totalBytesBilled, 0), 2) AS totalBytesBilled,
  ROUND(COALESCE(totalBytesBilled, 0) / POW(1024, 2), 2) AS totalMegabytesBilled,
  ROUND(COALESCE(totalBytesBilled, 0) / POW(1024, 3), 2) AS totalGigabytesBilled,
  ROUND(COALESCE(totalBytesBilled, 0) / POW(1024, 4), 2) AS totalTerabytesBilled,
  ROUND(SAFE_DIVIDE(totalBytesBilled, POW(1024, 4)) * 5, 2) AS onDemandCost
FROM
  aggregated
ORDER BY
  onDemandCost DESC;
