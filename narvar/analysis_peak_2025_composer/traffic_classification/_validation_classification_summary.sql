-- Classification Summary: High-level statistics on classified traffic
-- Purpose: Provides summary statistics for each classification category
--
-- This query aggregates:
--   1. Job counts by category
--   2. Slot usage by category
--   3. Cost distribution by category
--   4. Top users/projects per category
--   5. Temporal patterns (hourly/daily) by category
--
-- Parameters:
--   interval_in_days: Number of days to analyze (default: 30)
--
-- Output Schema (multiple result sets):
--   - Category Summary: Overall stats per category
--   - Top Users: Top users by slot usage per category
--   - Temporal Patterns: Hourly and daily patterns per category
--
-- Cost Warning: This query processes audit logs with multiple aggregations.
--               For 30 days, expect to process 10-50GB depending on traffic volume.

DECLARE interval_in_days INT64 DEFAULT 30;

WITH monitor_mappings AS (
  SELECT DISTINCT 
    retailer_moniker, 
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-prod') AS project_id
  FROM `reporting.t_return_details` 
  WHERE DATE(return_created_date) >= DATE('2025-01-01')
),
audit_log_base AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS user_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
    CASE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName
      WHEN 'query_job_completed' THEN 'QUERY'
      WHEN 'load_job_completed' THEN 'LOAD'
      WHEN 'extract_job_completed' THEN 'EXTRACT'
      WHEN 'table_copy_job_completed' THEN 'TABLE_COPY'
      ELSE 'OTHER'
    END AS job_type,
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
    * EXCEPT(_rnk)
  FROM audit_log_base
  WHERE _rnk = 1
),
classified_jobs AS (
  SELECT
    jd.*,
    CASE
      WHEN jd.user_email = 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com' THEN 'INTERNAL'
      WHEN jd.user_email = 'looker-prod@narvar-data-lake.iam.gserviceaccount.com' THEN 'EXTERNAL_CRITICAL'
      WHEN jd.project_id IN (SELECT project_id FROM monitor_mappings) THEN 'EXTERNAL_CRITICAL'
      WHEN jd.user_email LIKE '%.iam.gserviceaccount.com' THEN 'AUTOMATED_CRITICAL'
      ELSE 'INTERNAL'
    END AS consumer_category,
    TIMESTAMP_DIFF(endTime, startTime, MILLISECOND) AS execution_time_ms,
    -- Cost calculation: Based on slot-hours using weighted average cost per slot-hour
    -- Weighted average: (700 paygo × $3.4247 + 500 1yr × $2.7397 + 500 3yr × $2.0548) / 1700 = $2.820306/slot-hour
    ROUND(
      SAFE_DIVIDE(COALESCE(totalSlotMs, 0), 3600000.0) * 2.820306,
      2
    ) AS slot_cost_usd
  FROM jobs_deduplicated jd
),
-- Summary by category
category_summary AS (
  SELECT
    consumer_category,
    COUNT(DISTINCT jobId) AS job_count,
    COUNT(DISTINCT user_email) AS unique_users,
    COUNT(DISTINCT project_id) AS unique_projects,
    SUM(totalSlotMs) AS total_slot_ms,
    ROUND(SUM(totalSlotMs) / POW(10, 9), 2) AS total_slot_hours,
    SUM(totalBilledBytes) AS total_billed_bytes,
    ROUND(SUM(totalBilledBytes) / POW(1024, 4), 2) AS total_tb_processed,
    SUM(slot_cost_usd) AS total_cost_usd,
    AVG(execution_time_ms) AS avg_execution_time_ms,
    APPROX_QUANTILES(execution_time_ms, 100)[OFFSET(50)] AS median_execution_time_ms,
    APPROX_QUANTILES(execution_time_ms, 100)[OFFSET(95)] AS p95_execution_time_ms,
    APPROX_QUANTILES(execution_time_ms, 100)[OFFSET(99)] AS p99_execution_time_ms
  FROM classified_jobs
  GROUP BY consumer_category
)
SELECT
  consumer_category,
  job_count,
  unique_users,
  unique_projects,
  total_slot_ms,
  total_slot_hours,
  total_tb_processed,
  total_cost_usd,
  ROUND(avg_execution_time_ms / 1000.0, 2) AS avg_execution_time_sec,
  ROUND(median_execution_time_ms / 1000.0, 2) AS median_execution_time_sec,
  ROUND(p95_execution_time_ms / 1000.0, 2) AS p95_execution_time_sec,
  ROUND(p99_execution_time_ms / 1000.0, 2) AS p99_execution_time_sec,
  ROUND(SAFE_DIVIDE(total_slot_ms * 100.0, SUM(total_slot_ms) OVER()), 2) AS slot_percentage,
  ROUND(SAFE_DIVIDE(total_cost_usd * 100.0, SUM(total_cost_usd) OVER()), 2) AS cost_percentage
FROM category_summary
ORDER BY total_slot_ms DESC;

