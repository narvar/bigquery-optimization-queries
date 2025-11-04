-- Audit helper: quantifies how often parentJobName is populated per job event type.
-- Recommended usage: run as a dry run first, then widen interval cautiously to avoid >10 GB scans.

DECLARE interval_in_days INT64 DEFAULT 7;

WITH jobs AS (
  SELECT
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName AS event_name,
    JSON_VALUE(
      TO_JSON_STRING(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics),
      '$.parentJobName'
    ) AS parent_job_name
  FROM
    `<project>.<dataset>.cloudaudit_googleapis_com_data_access`
  WHERE
    DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
)

SELECT
  event_name,
  COUNTIF(parent_job_name IS NULL) AS null_parent_jobs,
  COUNT(*) AS total_jobs,
  SAFE_DIVIDE(COUNTIF(parent_job_name IS NULL), COUNT(*)) AS null_parent_ratio
FROM
  jobs
GROUP BY
  event_name
ORDER BY
  total_jobs DESC
LIMIT 10;
