-- Peak vs. Non-Peak QoS Comparison: Compares Quality of Service metrics between peak and non-peak periods
-- Purpose: Identifies QoS degradation patterns during peak periods
--
-- Compares:
--   - Execution time percentiles (P50, P95, P99, P99.9)
--   - Query timeout/abort rates
--   - Percentage of queries exceeding thresholds
--   - Degradation percentages
--
-- Parameters:
--   analysis_start_date: Start date for analysis (default: 2022-04-19)
--   analysis_end_date: End date for analysis (default: CURRENT_DATE)
--   external_critical_threshold_seconds: Max acceptable duration for external (default: 60)
--   internal_threshold_seconds: Max acceptable duration for internal (default: 600)
--
-- Output Schema:
--   consumer_category: STRING - Consumer category
--   metric_name: STRING - Metric name (P50, P95, P99, etc.)
--   peak_value: FLOAT64 - Value during peak period
--   nonpeak_value: FLOAT64 - Value during non-peak period
--   degradation_pct: FLOAT64 - Percentage degradation ((peak-nonpeak)/nonpeak * 100)
--   degradation_absolute: FLOAT64 - Absolute difference (peak - nonpeak)
--
-- Cost Warning: Processes all audit logs. For full history, expect 200-500GB+.

DECLARE analysis_start_date DATE DEFAULT '2022-04-19';
DECLARE analysis_end_date DATE DEFAULT CURRENT_DATE();
DECLARE external_critical_threshold_seconds INT64 DEFAULT 60;
DECLARE internal_threshold_seconds INT64 DEFAULT 600;

WITH qos_metrics AS (
  -- Use qos_metrics_calculation.sql logic
  SELECT
    consumer_category,
    period_type,
    p50_execution_seconds,
    p95_execution_seconds,
    p99_execution_seconds,
    p99_9_execution_seconds,
    avg_execution_seconds,
    pct_exceeding_threshold
  FROM (
    -- Inline qos_metrics_calculation logic (or reference materialized results)
    SELECT
      consumer_category,
      CASE
        WHEN EXTRACT(MONTH FROM start_time) IN (11, 12, 1) THEN 'PEAK'
        ELSE 'NON_PEAK'
      END AS period_type,
      APPROX_QUANTILES(execution_time_ms / 1000.0, 100)[OFFSET(50)] AS p50_execution_seconds,
      APPROX_QUANTILES(execution_time_ms / 1000.0, 100)[OFFSET(95)] AS p95_execution_seconds,
      APPROX_QUANTILES(execution_time_ms / 1000.0, 100)[OFFSET(99)] AS p99_execution_seconds,
      APPROX_QUANTILES(execution_time_ms / 1000.0, 1000)[OFFSET(999)] AS p99_9_execution_seconds,
      AVG(execution_time_ms / 1000.0) AS avg_execution_seconds,
      SAFE_DIVIDE(
        SUM(CASE
          WHEN (consumer_category = 'EXTERNAL_CRITICAL' AND execution_time_ms / 1000.0 > external_critical_threshold_seconds)
            OR (consumer_category = 'INTERNAL' AND execution_time_ms / 1000.0 > internal_threshold_seconds)
          THEN 1 ELSE 0 END),
        COUNT(*)
      ) * 100.0 AS pct_exceeding_threshold
    FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`
    WHERE DATE(start_time) >= analysis_start_date
      AND DATE(start_time) <= analysis_end_date
      AND execution_time_ms IS NOT NULL
    GROUP BY consumer_category, period_type
  )
),
peak_metrics AS (
  SELECT
    consumer_category,
    p50_execution_seconds AS p50,
    p95_execution_seconds AS p95,
    p99_execution_seconds AS p99,
    p99_9_execution_seconds AS p99_9,
    avg_execution_seconds AS avg_exec,
    pct_exceeding_threshold AS pct_exceeding
  FROM qos_metrics
  WHERE period_type = 'PEAK'
),
nonpeak_metrics AS (
  SELECT
    consumer_category,
    p50_execution_seconds AS p50,
    p95_execution_seconds AS p95,
    p99_execution_seconds AS p99,
    p99_9_execution_seconds AS p99_9,
    avg_execution_seconds AS avg_exec,
    pct_exceeding_threshold AS pct_exceeding
  FROM qos_metrics
  WHERE period_type = 'NON_PEAK'
),
comparison AS (
  SELECT
    COALESCE(p.consumer_category, n.consumer_category) AS consumer_category,
    'P50' AS metric_name,
    p.p50 AS peak_value,
    n.p50 AS nonpeak_value,
    SAFE_DIVIDE(p.p50 - n.p50, n.p50) * 100.0 AS degradation_pct,
    p.p50 - n.p50 AS degradation_absolute
  FROM peak_metrics p
  FULL OUTER JOIN nonpeak_metrics n
    ON p.consumer_category = n.consumer_category
  
  UNION ALL
  
  SELECT
    COALESCE(p.consumer_category, n.consumer_category) AS consumer_category,
    'P95' AS metric_name,
    p.p95 AS peak_value,
    n.p95 AS nonpeak_value,
    SAFE_DIVIDE(p.p95 - n.p95, n.p95) * 100.0 AS degradation_pct,
    p.p95 - n.p95 AS degradation_absolute
  FROM peak_metrics p
  FULL OUTER JOIN nonpeak_metrics n
    ON p.consumer_category = n.consumer_category
  
  UNION ALL
  
  SELECT
    COALESCE(p.consumer_category, n.consumer_category) AS consumer_category,
    'P99' AS metric_name,
    p.p99 AS peak_value,
    n.p99 AS nonpeak_value,
    SAFE_DIVIDE(p.p99 - n.p99, n.p99) * 100.0 AS degradation_pct,
    p.p99 - n.p99 AS degradation_absolute
  FROM peak_metrics p
  FULL OUTER JOIN nonpeak_metrics n
    ON p.consumer_category = n.consumer_category
  
  UNION ALL
  
  SELECT
    COALESCE(p.consumer_category, n.consumer_category) AS consumer_category,
    'AVG' AS metric_name,
    p.avg_exec AS peak_value,
    n.avg_exec AS nonpeak_value,
    SAFE_DIVIDE(p.avg_exec - n.avg_exec, n.avg_exec) * 100.0 AS degradation_pct,
    p.avg_exec - n.avg_exec AS degradation_absolute
  FROM peak_metrics p
  FULL OUTER JOIN nonpeak_metrics n
    ON p.consumer_category = n.consumer_category
  
  UNION ALL
  
  SELECT
    COALESCE(p.consumer_category, n.consumer_category) AS consumer_category,
    'PCT_EXCEEDING_THRESHOLD' AS metric_name,
    p.pct_exceeding AS peak_value,
    n.pct_exceeding AS nonpeak_value,
    SAFE_DIVIDE(p.pct_exceeding - n.pct_exceeding, n.pct_exceeding) * 100.0 AS degradation_pct,
    p.pct_exceeding - n.pct_exceeding AS degradation_absolute
  FROM peak_metrics p
  FULL OUTER JOIN nonpeak_metrics n
    ON p.consumer_category = n.consumer_category
)

SELECT
  consumer_category,
  metric_name,
  peak_value,
  nonpeak_value,
  degradation_pct,
  degradation_absolute
FROM comparison
WHERE consumer_category IS NOT NULL
ORDER BY
  consumer_category,
  metric_name;

