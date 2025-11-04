-- Investigate Slow Internal User Queries: Identifies and analyzes slow Metabase queries
-- Purpose: Finds slow internal user queries for optimization opportunities
--
-- This query identifies:
--   1. Slowest queries by execution time (P95, P99, etc.)
--   2. Queries that exceed QoS thresholds
--   3. Resource-intensive queries (high slot usage, high data scanned)
--   4. User patterns (who runs slow queries)
--   5. Time-of-day patterns (when slow queries occur)
--   6. Query characteristics (query text patterns, referenced tables)
--
-- Parameters:
--   interval_in_days: Number of days to analyze (default: 30)
--   min_execution_time_seconds: Minimum execution time to consider "slow" (default: 60 seconds)
--   top_n_slowest: Number of slowest queries to return (default: 100)
--
-- Output Schema (multiple result sets):
--   - Slow Queries: Individual slow queries with details
--   - User Analysis: Users with slow queries
--   - Time Patterns: When slow queries occur
--   - Resource Analysis: Slot and cost analysis of slow queries
--
-- Cost Warning: This query processes internal user audit logs and query text.
--               For 30 days, expect to process 5-20GB depending on traffic volume.

DECLARE interval_in_days INT64 DEFAULT 30;
DECLARE min_execution_time_seconds INT64 DEFAULT 60;  -- Queries slower than 1 minute
DECLARE top_n_slowest INT64 DEFAULT 100;
DECLARE internal_threshold_seconds INT64 DEFAULT 600;  -- 10 minutes QoS threshold

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
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.referencedTables AS referencedTables,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
      MILLISECOND
    ) AS execution_time_ms,
    SAFE_DIVIDE(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
      TIMESTAMP_DIFF(
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
        MILLISECOND
      )
    ) AS approximate_slot_count,
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS _rnk
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE 'query_job_completed'
    -- Filter for INTERNAL category (Metabase service account)
    AND protopayload_auditlog.authenticationInfo.principalEmail = 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId IS NOT NULL
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
),
jobs_deduplicated AS (
  SELECT
    * EXCEPT(_rnk)
  FROM audit_log_base
  WHERE _rnk = 1
    AND execution_time_ms IS NOT NULL
    AND execution_time_ms > 0
),
slow_queries AS (
  SELECT
    jobId AS job_id,
    user_email,
    project_id,
    startTime,
    endTime,
    execution_time_ms,
    execution_time_ms / 1000.0 AS execution_time_seconds,
    approximate_slot_count,
    totalSlotMs,
    totalBilledBytes,
    -- Cost calculation: Based on slot-hours using weighted average cost per slot-hour
    -- Weighted average: (700 paygo × $3.4247 + 500 1yr × $2.7397 + 500 3yr × $2.0548) / 1700 = $2.820306/slot-hour
    ROUND(SAFE_DIVIDE(totalSlotMs, 3600000.0) * 2.820306, 2) AS estimated_cost_usd,
    query_text,
    referencedTables,
    -- Extract Metabase user ID from query comment if present
    REGEXP_EXTRACT(query_text, r'(?i)--\s*(?:user|user_id|metabase[_\s]*user[_\s]*id)[:\s]*(\d+)', 1) AS metabase_user_id,
    EXTRACT(HOUR FROM startTime) AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM startTime) AS day_of_week,
    DATE(startTime) AS execution_date,
    CASE
      WHEN execution_time_ms / 1000.0 >= internal_threshold_seconds THEN 'EXCEEDS_QOS_THRESHOLD'
      WHEN execution_time_ms / 1000.0 >= min_execution_time_seconds THEN 'SLOW'
      ELSE 'NORMAL'
    END AS performance_category
  FROM jobs_deduplicated
  WHERE execution_time_ms / 1000.0 >= min_execution_time_seconds
),
-- Top slowest queries
top_slowest AS (
  SELECT
    job_id,
    user_email,
    project_id,
    startTime,
    execution_time_seconds,
    approximate_slot_count,
    estimated_cost_usd,
    totalBilledBytes / POW(1024, 3) AS data_scanned_gb,
    SUBSTR(query_text, 0, 500) AS query_preview,
    metabase_user_id,
    performance_category,
    ARRAY_LENGTH(referencedTables) AS tables_referenced_count
  FROM slow_queries
  ORDER BY execution_time_seconds DESC
  LIMIT top_n_slowest
),
-- User analysis: Who runs slow queries?
user_analysis AS (
  SELECT
    user_email,
    metabase_user_id,
    COUNT(DISTINCT job_id) AS slow_query_count,
    COUNT(DISTINCT CASE WHEN performance_category = 'EXCEEDS_QOS_THRESHOLD' THEN job_id END) AS qos_violation_count,
    AVG(execution_time_seconds) AS avg_execution_time_seconds,
    APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)] AS median_execution_time_seconds,
    APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)] AS p95_execution_time_seconds,
    MAX(execution_time_seconds) AS max_execution_time_seconds,
    SUM(estimated_cost_usd) AS total_cost_usd,
    SUM(totalSlotMs) / POW(10, 6) AS total_slot_seconds
  FROM slow_queries
  GROUP BY user_email, metabase_user_id
),
-- Time pattern analysis
time_patterns AS (
  SELECT
    hour_of_day,
    day_of_week,
    COUNT(DISTINCT job_id) AS slow_query_count,
    AVG(execution_time_seconds) AS avg_execution_time_seconds,
    SUM(estimated_cost_usd) AS total_cost_usd
  FROM slow_queries
  GROUP BY hour_of_day, day_of_week
),
-- Resource analysis
resource_analysis AS (
  SELECT
    'Slow Queries Resource Usage' AS metric_type,
    COUNT(DISTINCT job_id) AS query_count,
    SUM(estimated_cost_usd) AS total_cost_usd,
    SUM(totalSlotMs) / POW(10, 9) AS total_slot_hours,
    SUM(totalBilledBytes) / POW(1024, 4) AS total_tb_scanned,
    AVG(execution_time_seconds) AS avg_execution_time_seconds
  FROM slow_queries
)
-- Return top slowest queries with details
SELECT
  'SLOWEST_QUERIES' AS result_type,
  CAST(job_id AS STRING) AS job_id,
  CAST(execution_time_seconds AS FLOAT64) AS execution_time_seconds,
  CAST(approximate_slot_count AS FLOAT64) AS slot_count,
  CAST(data_scanned_gb AS FLOAT64) AS data_scanned_gb,
  CAST(estimated_cost_usd AS FLOAT64) AS cost_usd,
  CAST(metabase_user_id AS STRING) AS metabase_user_id,
  CAST(startTime AS STRING) AS start_time,
  CAST(performance_category AS STRING) AS performance_category,
  CAST(tables_referenced_count AS INT64) AS tables_referenced_count,
  query_preview
FROM top_slowest

UNION ALL

SELECT
  'USER_ANALYSIS' AS result_type,
  CAST(CONCAT(user_email, COALESCE(' (User ID: ', metabase_user_id, ')'), ')') AS STRING) AS job_id,
  CAST(avg_execution_time_seconds AS FLOAT64) AS execution_time_seconds,
  CAST(total_slot_seconds AS FLOAT64) AS slot_count,
  CAST(NULL AS FLOAT64) AS data_scanned_gb,
  CAST(total_cost_usd AS FLOAT64) AS cost_usd,
  CAST(metabase_user_id AS STRING) AS metabase_user_id,
  CAST(CONCAT('Slow queries: ', CAST(slow_query_count AS STRING), ', QoS violations: ', CAST(qos_violation_count AS STRING)) AS STRING) AS start_time,
  CAST(CONCAT('P95: ', CAST(ROUND(p95_execution_time_seconds, 2) AS STRING), 's') AS STRING) AS performance_category,
  CAST(slow_query_count AS INT64) AS tables_referenced_count,
  CAST('User summary' AS STRING) AS query_preview
FROM user_analysis
ORDER BY result_type, execution_time_seconds DESC;

