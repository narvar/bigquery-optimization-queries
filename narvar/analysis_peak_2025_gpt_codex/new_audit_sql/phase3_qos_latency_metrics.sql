-- Phase 3 QoS latency metrics per consumer classification and analysis window.
-- Computes queue time, run time, and total duration quantiles plus slot usage.

DECLARE window_ids ARRAY<STRING> DEFAULT [
  'peak_fy22', 'baseline_fy22',
  'peak_fy23', 'baseline_fy23',
  'peak_fy24', 'baseline_fy24',
  'baseline_fy25',
  'rolling_90d', 'rolling_28d', 'rolling_07d'
];

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
    audit.protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName AS event_name,
    audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS job_project_id,
    audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.createTime AS create_time,
    audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime AS start_time,
    audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime AS end_time,
    audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    audit.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.location AS job_location
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
root_jobs AS (
  SELECT
    *
  FROM
    base_jobs
  WHERE
    create_time IS NOT NULL
    AND start_time IS NOT NULL
    AND end_time IS NOT NULL
    AND end_time >= start_time
    AND start_time >= create_time
),
metrics AS (
  SELECT
    window_id,
    principal_email,
    job_project_id,
    event_name,
    TIMESTAMP_DIFF(start_time, create_time, SECOND) AS queue_seconds,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS run_seconds,
    TIMESTAMP_DIFF(end_time, create_time, SECOND) AS total_seconds,
    COALESCE(total_slot_ms, 0) AS total_slot_ms
  FROM
    root_jobs
),
overrides AS (
  SELECT
    principal_email,
    classification_type,
    classification_subtype,
    retailer_moniker
  FROM
    `narvar-data-lake.analytics.consumer_classification_overrides`
),
classified AS (
  SELECT
    m.window_id,
    m.principal_email,
    m.job_project_id,
    m.event_name,
    m.queue_seconds,
    m.run_seconds,
    m.total_seconds,
    m.total_slot_ms,
    COALESCE(o.classification_type,
             CASE
               WHEN STARTS_WITH(LOWER(COALESCE(m.job_project_id, '')), 'monitor') THEN 'MONITOR_USERS'
               WHEN REGEXP_CONTAINS(LOWER(m.principal_email), r'(looker|metabase|monitor|analytics-api|messaging|n8n)') THEN 'HUB_SERVICE'
               WHEN REGEXP_CONTAINS(LOWER(m.principal_email), r'(airflow|composer|gke|compute@developer|iam\\.gserviceaccount\\.com)') THEN 'AUTOMATION'
               WHEN REGEXP_CONTAINS(LOWER(m.principal_email), r'@narvar\\.com$') THEN 'INTERNAL_USER'
               ELSE 'UNKNOWN'
             END) AS classification_type
  FROM
    metrics AS m
  LEFT JOIN
    overrides AS o
  USING
    (principal_email)
)
SELECT
  window_id,
  classification_type,
  event_name,
  COUNT(*) AS job_count,
  SUM(total_slot_ms) AS total_slot_ms,
  SUM(run_seconds) AS total_run_seconds,
  SUM(CASE WHEN total_seconds > 60 THEN 1 ELSE 0 END) AS jobs_over_60s,
  SAFE_DIVIDE(SUM(CASE WHEN total_seconds > 60 THEN 1 ELSE 0 END), COUNT(*)) AS pct_jobs_over_60s,
  SAFE_DIVIDE(SUM(total_slot_ms), NULLIF(SUM(run_seconds), 0) * 1000) AS avg_active_slots,
  AVG(queue_seconds) AS avg_queue_seconds,
  AVG(run_seconds) AS avg_run_seconds,
  AVG(total_seconds) AS avg_total_seconds,
  APPROX_QUANTILES(queue_seconds, 101)[SAFE_OFFSET(50)] AS p50_queue_seconds,
  APPROX_QUANTILES(queue_seconds, 101)[SAFE_OFFSET(90)] AS p90_queue_seconds,
  APPROX_QUANTILES(queue_seconds, 101)[SAFE_OFFSET(99)] AS p99_queue_seconds,
  APPROX_QUANTILES(run_seconds, 101)[SAFE_OFFSET(50)] AS p50_run_seconds,
  APPROX_QUANTILES(run_seconds, 101)[SAFE_OFFSET(90)] AS p90_run_seconds,
  APPROX_QUANTILES(run_seconds, 101)[SAFE_OFFSET(99)] AS p99_run_seconds,
  APPROX_QUANTILES(total_seconds, 101)[SAFE_OFFSET(50)] AS p50_total_seconds,
  APPROX_QUANTILES(total_seconds, 101)[SAFE_OFFSET(90)] AS p90_total_seconds,
  APPROX_QUANTILES(total_seconds, 101)[SAFE_OFFSET(99)] AS p99_total_seconds,
  MAX(total_seconds) AS max_total_seconds
FROM
  classified
GROUP BY
  window_id,
  classification_type,
  event_name
ORDER BY
  window_id,
  classification_type,
  event_name;
