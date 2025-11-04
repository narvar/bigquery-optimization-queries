-- Hub Traffic Analysis: Identifies and analyzes Hub traffic from Looker service account
-- Purpose: Identifies all queries from looker-prod service account for Hub traffic attribution
-- 
-- Hub traffic is defined as queries executed by the looker-prod@narvar-data-lake.iam.gserviceaccount.com
-- service account. This traffic needs to be attributed to retailers to classify as EXTERNAL_CRITICAL.
--
-- This query provides the foundation for discovering attribution patterns by analyzing:
--   - Query text patterns
--   - Referenced tables/datasets
--   - Query labels
--   - Temporal patterns
--
-- Parameters:
--   interval_in_days: Number of days in the past to search (default: 365 for full year analysis)
--
-- Output Schema:
--   jobId: STRING - BigQuery job ID
--   user: STRING - Service account email
--   projectId: STRING - Project ID where job ran
--   startTime: TIMESTAMP - Job start time
--   endTime: TIMESTAMP - Job end time
--   executionTimeMs: INT64 - Job execution time in milliseconds
--   totalSlotMs: INT64 - Total slot milliseconds consumed
--   approximateSlotCount: FLOAT64 - Approximate number of slots used
--   queryText: STRING - Full query text (for pattern analysis)
--   referencedTables: ARRAY<STRUCT> - List of referenced tables
--   labels: ARRAY<STRUCT> - Job labels (if present)
--   slotCost: FLOAT64 - Estimated slot cost in USD (based on weighted average $2.820306 per slot-hour)
--
-- Cost Warning: This query processes audit logs for the specified interval.
--               For 365 days, expect to process 10-50GB+ depending on traffic volume.
--               Consider using dry-run or smaller intervals for initial exploration.

DECLARE interval_in_days INT64 DEFAULT 365;

WITH src AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS user,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS projectId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.referencedTables AS referencedTables,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.labels AS labels,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS queryText,
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
      MILLISECOND
    ) AS executionTimeMs,
    ROUND(
      SAFE_DIVIDE(
        COALESCE(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs, 0),
        3600000.0
      ) * 0.04,
      2
    ) AS slotCost,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS totalSlotMs,
    SAFE_DIVIDE(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
      TIMESTAMP_DIFF(
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
        MILLISECOND
      )
    ) AS approximateSlotCount,
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS _rnk
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%' -- filter BQ script child jobs
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
    AND protopayload_auditlog.authenticationInfo.principalEmail IS NOT NULL
    AND protopayload_auditlog.authenticationInfo.principalEmail != ""
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId IS NOT NULL
    -- Filter for looker-prod service account (Hub traffic)
    AND protopayload_auditlog.authenticationInfo.principalEmail = 'looker-prod@narvar-data-lake.iam.gserviceaccount.com'
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
),
jobsDeduplicated AS (
  SELECT
    * EXCEPT(_rnk)
  FROM
    src
  WHERE
    _rnk = 1
)

SELECT
  jobId,
  user,
  projectId,
  startTime,
  endTime,
  executionTimeMs,
  totalSlotMs,
  approximateSlotCount,
  queryText,
  referencedTables,
  labels,
  slotCost
FROM jobsDeduplicated
ORDER BY startTime DESC;

