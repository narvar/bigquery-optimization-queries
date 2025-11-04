-- Drill-Down: AUTOMATED_CRITICAL Service Account Analysis
-- Purpose: Identifies service accounts responsible for 90% of jobs and 90% of slot usage
--
-- This query provides:
--   1. Service accounts ranked by job count (with cumulative %)
--   2. Service accounts ranked by slot usage (with cumulative %)
--   3. Top service accounts reaching 90% thresholds
--   4. Detailed statistics per service account
--
-- Parameters:
--   interval_in_days: Number of days to analyze (default: 30)
--   threshold_percentage: Percentage threshold to identify (default: 90.0)
--
-- Output Schema (multiple result sets):
--   - By Job Count: Service accounts sorted by job volume
--   - By Slot Usage: Service accounts sorted by slot consumption
--   - Top Contributors: Service accounts reaching threshold
--
-- Cost Warning: This query processes audit logs for all AUTOMATED_CRITICAL traffic.
--               For 30 days, expect to process 10-50GB depending on traffic volume.

DECLARE interval_in_days INT64 DEFAULT 30;
DECLARE threshold_percentage FLOAT64 DEFAULT 90.0;

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
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
      MILLISECOND
    ) AS execution_time_ms,
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
    -- Filter for AUTOMATED_CRITICAL: service accounts (excluding Metabase and Looker)
    AND protopayload_auditlog.authenticationInfo.principalEmail LIKE '%.iam.gserviceaccount.com'
    AND protopayload_auditlog.authenticationInfo.principalEmail != 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com'
    AND protopayload_auditlog.authenticationInfo.principalEmail != 'looker-prod@narvar-data-lake.iam.gserviceaccount.com'
    -- Exclude monitor projects (they should be EXTERNAL_CRITICAL)
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId NOT IN (SELECT project_id FROM monitor_mappings)
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
),
jobs_deduplicated AS (
  SELECT
    * EXCEPT(_rnk)
  FROM audit_log_base
  WHERE _rnk = 1
),
service_account_aggregated AS (
  SELECT
    user_email AS service_account,
    project_id,
    COUNT(DISTINCT jobId) AS job_count,
    SUM(totalSlotMs) AS total_slot_ms,
    SUM(totalBilledBytes) AS total_billed_bytes,
    -- Cost calculation: Based on slot-hours using weighted average cost per slot-hour
    -- Weighted average: (700 paygo × $3.4247 + 500 1yr × $2.7397 + 500 3yr × $2.0548) / 1700 = $2.820306/slot-hour
    ROUND(SAFE_DIVIDE(SUM(totalSlotMs), 3600000.0) * 2.820306, 2) AS estimated_cost_usd,
    AVG(execution_time_ms) AS avg_execution_time_ms,
    APPROX_QUANTILES(execution_time_ms, 100)[OFFSET(50)] AS median_execution_time_ms,
    APPROX_QUANTILES(execution_time_ms, 100)[OFFSET(95)] AS p95_execution_time_ms,
    ARRAY_AGG(DISTINCT job_type) AS job_types,
    MIN(startTime) AS first_job_time,
    MAX(startTime) AS last_job_time
  FROM jobs_deduplicated
  GROUP BY user_email, project_id
),
-- Calculate totals for percentages
totals AS (
  SELECT
    SUM(job_count) AS total_jobs,
    SUM(total_slot_ms) AS total_slot_ms
  FROM service_account_aggregated
),
-- Rank by job count
ranked_by_jobs AS (
  SELECT
    sa.*,
    ROW_NUMBER() OVER (ORDER BY sa.job_count DESC) AS rank_by_jobs,
    SUM(sa.job_count) OVER (ORDER BY sa.job_count DESC) AS cumulative_jobs,
    ROUND(SAFE_DIVIDE(SUM(sa.job_count) OVER (ORDER BY sa.job_count DESC), t.total_jobs) * 100, 2) AS cumulative_job_percentage
  FROM service_account_aggregated sa
  CROSS JOIN totals t
),
-- Rank by slot usage
ranked_by_slots AS (
  SELECT
    sa.*,
    ROW_NUMBER() OVER (ORDER BY sa.total_slot_ms DESC) AS rank_by_slots,
    SUM(sa.total_slot_ms) OVER (ORDER BY sa.total_slot_ms DESC) AS cumulative_slot_ms,
    ROUND(SAFE_DIVIDE(SUM(sa.total_slot_ms) OVER (ORDER BY sa.total_slot_ms DESC), t.total_slot_ms) * 100, 2) AS cumulative_slot_percentage
  FROM service_account_aggregated sa
  CROSS JOIN totals t
),
-- Identify service accounts reaching 90% threshold by jobs
top_by_jobs AS (
  SELECT
    service_account,
    project_id,
    job_count,
    total_slot_ms / POW(10, 9) AS total_slot_hours,
    estimated_cost_usd,
    cumulative_job_percentage,
    'Top by Job Count' AS analysis_type
  FROM ranked_by_jobs
  WHERE cumulative_job_percentage <= threshold_percentage
    OR rank_by_jobs = 1  -- Include the top one even if over threshold
),
-- Identify service accounts reaching 90% threshold by slots
top_by_slots AS (
  SELECT
    service_account,
    project_id,
    job_count,
    total_slot_ms / POW(10, 9) AS total_slot_hours,
    estimated_cost_usd,
    cumulative_slot_percentage,
    'Top by Slot Usage' AS analysis_type
  FROM ranked_by_slots
  WHERE cumulative_slot_percentage <= threshold_percentage
    OR rank_by_slots = 1  -- Include the top one even if over threshold
),
-- Result: Service accounts ranked by job count (first 50)
ranked_by_jobs_result AS (
  SELECT
    'RANKED_BY_JOB_COUNT' AS result_type,
    CAST(rj.rank_by_jobs AS INT64) AS rank,
    rj.service_account,
    rj.project_id,
    CAST(rj.job_count AS INT64) AS job_count,
    CAST(rj.total_slot_ms / POW(10, 9) AS FLOAT64) AS total_slot_hours,
    CAST(rj.estimated_cost_usd AS FLOAT64) AS estimated_cost_usd,
    CAST(rj.cumulative_job_percentage AS FLOAT64) AS cumulative_percentage,
    CAST(ARRAY_LENGTH(rj.job_types) AS INT64) AS job_type_count,
    CAST(ARRAY_TO_STRING(rj.job_types, ', ') AS STRING) AS job_types
  FROM ranked_by_jobs rj
  ORDER BY rj.rank_by_jobs
  LIMIT 50
),
-- Result: Service accounts ranked by slot usage (first 50)
ranked_by_slots_result AS (
  SELECT
    'RANKED_BY_SLOT_USAGE' AS result_type,
    CAST(rs.rank_by_slots AS INT64) AS rank,
    rs.service_account,
    rs.project_id,
    CAST(rs.job_count AS INT64) AS job_count,
    CAST(rs.total_slot_ms / POW(10, 9) AS FLOAT64) AS total_slot_hours,
    CAST(rs.estimated_cost_usd AS FLOAT64) AS estimated_cost_usd,
    CAST(rs.cumulative_slot_percentage AS FLOAT64) AS cumulative_percentage,
    CAST(ARRAY_LENGTH(rs.job_types) AS INT64) AS job_type_count,
    CAST(ARRAY_TO_STRING(rs.job_types, ', ') AS STRING) AS job_types
  FROM ranked_by_slots rs
  ORDER BY rs.rank_by_slots
  LIMIT 50
)
SELECT * FROM ranked_by_jobs_result
UNION ALL
SELECT * FROM ranked_by_slots_result
ORDER BY result_type, rank;

