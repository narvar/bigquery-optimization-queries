-- Phase 3 QoS: 10-minute slot usage aggregates per consumer classification and analysis window.
-- Adjust the DECLARE statements to control which windows are processed.

DECLARE window_ids ARRAY<STRING> DEFAULT [
  'peak_fy22', 'baseline_fy22',
  'peak_fy23', 'baseline_fy23',
  'peak_fy24', 'baseline_fy24',
  'baseline_fy25',
  'rolling_90d', 'rolling_28d', 'rolling_07d'
];
DECLARE interval_minutes INT64 DEFAULT 10;
DECLARE interval_seconds INT64 DEFAULT interval_minutes * 60;

WITH qos_windows AS (
  SELECT *
  FROM (
    SELECT 'peak_fy22' AS window_id,
           TIMESTAMP('2021-11-01') AS start_ts,
           TIMESTAMP('2022-01-15') AS end_ts UNION ALL
    SELECT 'baseline_fy22', TIMESTAMP('2021-08-01'), TIMESTAMP('2021-10-31') UNION ALL
    SELECT 'peak_fy23', TIMESTAMP('2022-11-01'), TIMESTAMP('2023-01-15') UNION ALL
    SELECT 'baseline_fy23', TIMESTAMP('2022-08-01'), TIMESTAMP('2022-10-31') UNION ALL
    SELECT 'peak_fy24', TIMESTAMP('2023-11-01'), TIMESTAMP('2024-01-15') UNION ALL
    SELECT 'baseline_fy24', TIMESTAMP('2023-08-01'), TIMESTAMP('2023-10-31') UNION ALL
    SELECT 'baseline_fy25', TIMESTAMP('2025-08-01'), TIMESTAMP('2025-10-31') UNION ALL
    SELECT 'rolling_90d', TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY), CURRENT_TIMESTAMP() UNION ALL
    SELECT 'rolling_28d', TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 28 DAY), CURRENT_TIMESTAMP() UNION ALL
    SELECT 'rolling_07d', TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY), CURRENT_TIMESTAMP()
  )
  WHERE window_id IN UNNEST(window_ids)
),
base_jobs AS (
  SELECT
    w.window_id,
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS job_project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.createTime AS create_time,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime AS start_time,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime AS end_time,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id
  FROM
    `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` AS audit,
    qos_windows AS w
  WHERE
    audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND audit.protopayload_auditlog.authenticationInfo.principalEmail IS NOT NULL
    AND audit.protopayload_auditlog.authenticationInfo.principalEmail != ''
    AND audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
    AND audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime BETWEEN w.start_ts AND w.end_ts
),
metrics AS (
  SELECT
    window_id,
    principal_email,
    job_project_id,
    TIMESTAMP_SECONDS(DIV(UNIX_SECONDS(start_time), interval_seconds) * interval_seconds) AS bucket_ts,
    TIMESTAMP_DIFF(start_time, create_time, SECOND) AS queue_seconds,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS run_seconds,
    TIMESTAMP_DIFF(end_time, create_time, SECOND) AS total_seconds,
    COALESCE(total_slot_ms, 0) AS total_slot_ms
  FROM
    base_jobs
  WHERE
    create_time IS NOT NULL AND start_time IS NOT NULL AND end_time IS NOT NULL
    AND end_time >= start_time
    AND start_time >= create_time
),
overrides AS (
  SELECT
    principal_email,
    classification_type,
    classification_subtype
  FROM
    `narvar-data-lake.analytics.consumer_classification_overrides`
),
classified AS (
  SELECT
    m.window_id,
    m.bucket_ts,
    COALESCE(o.classification_type,
             CASE
               WHEN REGEXP_CONTAINS(LOWER(m.principal_email), r'(looker|metabase|monitor|analytics-api|messaging|n8n)') THEN 'HUB_SERVICE'
               WHEN REGEXP_CONTAINS(LOWER(m.principal_email), r'(airflow|composer|gke|compute@developer|iam\\.gserviceaccount\\.com)') THEN 'AUTOMATION'
               WHEN REGEXP_CONTAINS(LOWER(m.principal_email), r'@narvar\\.com$') THEN 'INTERNAL_USER'
               ELSE 'UNKNOWN'
             END) AS classification_type,
    m.principal_email,
    m.job_project_id,
    m.queue_seconds,
    m.run_seconds,
    m.total_seconds,
    m.total_slot_ms
  FROM
    metrics AS m
  LEFT JOIN
    overrides AS o
  USING
    (principal_email)
)
SELECT
  window_id,
  bucket_ts,
  classification_type,
  COUNT(*) AS job_count,
  SUM(total_slot_ms) AS total_slot_ms,
  SUM(queue_seconds) AS sum_queue_seconds,
  SUM(run_seconds) AS sum_run_seconds,
  SUM(total_seconds) AS sum_total_seconds
FROM
  classified
GROUP BY
  window_id,
  bucket_ts,
  classification_type
ORDER BY
  window_id,
  bucket_ts,
  classification_type;
