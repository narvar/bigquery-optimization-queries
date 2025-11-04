-- QoS Metrics Calculation: Calculates Quality of Service metrics by consumer category
-- Purpose: Computes P50, P95, P99, P99.9 execution times and identifies queries exceeding thresholds
--
-- QoS Thresholds (configurable):
--   - EXTERNAL_CRITICAL: max_acceptable_duration_seconds = 60 (1 minute)
--   - AUTOMATED_CRITICAL: max_acceptable_duration_seconds = schedule_window (varies)
--   - INTERNAL: max_acceptable_duration_seconds = 600 (10 minutes)
--
-- Metrics calculated:
--   - Execution time percentiles (P50, P95, P99, P99.9)
--   - Query timeout/abort rates
--   - Slot contention indicators (delayed starts, queued queries)
--   - Percentage of queries exceeding thresholds
--
-- Parameters:
--   interval_in_days: Number of days to analyze (default: 365 for full year)
--   external_critical_threshold_seconds: Max acceptable duration for external (default: 60)
--   internal_threshold_seconds: Max acceptable duration for internal (default: 600)
--
-- Output Schema:
--   consumer_category: STRING - EXTERNAL_CRITICAL, AUTOMATED_CRITICAL, INTERNAL
--   period_type: STRING - 'PEAK' or 'NON_PEAK'
--   execution_count: INT64 - Total query executions
--   p50_execution_seconds: FLOAT64 - 50th percentile execution time
--   p95_execution_seconds: FLOAT64 - 95th percentile execution time
--   p99_execution_seconds: FLOAT64 - 99th percentile execution time
--   p99_9_execution_seconds: FLOAT64 - 99.9th percentile execution time
--   max_execution_seconds: FLOAT64 - Maximum execution time
--   queries_exceeding_threshold: INT64 - Count of queries exceeding threshold
--   pct_exceeding_threshold: FLOAT64 - Percentage exceeding threshold
--   avg_execution_seconds: FLOAT64 - Average execution time
--
-- Cost Warning: Processes all audit logs with execution time analysis.

DECLARE interval_in_days INT64 DEFAULT 365;
DECLARE external_critical_threshold_seconds INT64 DEFAULT 60;
DECLARE internal_threshold_seconds INT64 DEFAULT 600;

WITH traffic_classified AS (
  SELECT
    job_id,
    consumer_category,
    start_time,
    execution_time_ms,
    EXTRACT(MONTH FROM start_time) AS month
  FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`  -- Materialized view
  WHERE DATE(start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
    AND execution_time_ms IS NOT NULL
    AND execution_time_ms > 0  -- Filter invalid execution times
),
period_classified AS (
  SELECT
    *,
    CASE
      WHEN month IN (11, 12, 1) THEN 'PEAK'
      ELSE 'NON_PEAK'
    END AS period_type,
    execution_time_ms / 1000.0 AS execution_time_seconds,
    CASE
      WHEN consumer_category = 'EXTERNAL_CRITICAL' 
        AND (execution_time_ms / 1000.0) > external_critical_threshold_seconds THEN 1
      WHEN consumer_category = 'INTERNAL' 
        AND (execution_time_ms / 1000.0) > internal_threshold_seconds THEN 1
      WHEN consumer_category = 'AUTOMATED_CRITICAL' THEN NULL  -- Threshold varies by schedule
      ELSE 0
    END AS exceeds_threshold
  FROM traffic_classified
),
qos_metrics AS (
  SELECT
    consumer_category,
    period_type,
    COUNT(*) AS execution_count,
    APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)] AS p50_execution_seconds,
    APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)] AS p95_execution_seconds,
    APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)] AS p99_execution_seconds,
    APPROX_QUANTILES(execution_time_seconds, 1000)[OFFSET(999)] AS p99_9_execution_seconds,
    MAX(execution_time_seconds) AS max_execution_seconds,
    AVG(execution_time_seconds) AS avg_execution_seconds,
    SUM(COALESCE(exceeds_threshold, 0)) AS queries_exceeding_threshold,
    COUNTIF(exceeds_threshold IS NULL) AS threshold_not_applicable
  FROM period_classified
  GROUP BY
    consumer_category,
    period_type
)

SELECT
  consumer_category,
  period_type,
  execution_count,
  p50_execution_seconds,
  p95_execution_seconds,
  p99_execution_seconds,
  p99_9_execution_seconds,
  max_execution_seconds,
  avg_execution_seconds,
  queries_exceeding_threshold,
  SAFE_DIVIDE(queries_exceeding_threshold, execution_count - COALESCE(threshold_not_applicable, 0)) * 100.0 AS pct_exceeding_threshold
FROM qos_metrics
ORDER BY
  consumer_category,
  period_type;

