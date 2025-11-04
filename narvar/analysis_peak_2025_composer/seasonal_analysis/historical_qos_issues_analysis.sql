-- Historical QoS Issues Analysis: Identifies and analyzes past Quality of Service violations
-- Purpose: Analyzes queries exceeding QoS thresholds and correlates with slot utilization
--
-- This query identifies:
--   - Queries exceeding QoS thresholds
--   - Slot utilization during QoS violations
--   - Correlation between QoS issues and:
--     * Total slot consumption (when slots exceeded capacity)
--     * Category mix (contention between categories)
--     * Time-of-day patterns
--
-- Parameters:
--   analysis_start_date: Start date for analysis (default: 2022-04-19)
--   analysis_end_date: End date for analysis (default: CURRENT_DATE)
--   external_critical_threshold_seconds: Max acceptable duration for external (default: 60)
--   internal_threshold_seconds: Max acceptable duration for internal (default: 600)
--
-- Output Schema:
--   period_type: STRING - 'PEAK' or 'NON_PEAK'
--   consumer_category: STRING - Consumer category
--   violation_date: DATE - Date of QoS violation
--   violation_hour: INT64 - Hour of violation (0-23)
--   total_violations: INT64 - Number of violations in this hour
--   avg_slot_utilization: FLOAT64 - Average slot utilization during violations
--   max_slot_utilization: FLOAT64 - Maximum slot utilization
--   concurrent_categories: INT64 - Number of categories active during violations
--
-- Cost Warning: Processes all audit logs and performs slot utilization correlation.
--               For full history, expect 300-600GB+.

DECLARE analysis_start_date DATE DEFAULT '2022-04-19';
DECLARE analysis_end_date DATE DEFAULT CURRENT_DATE();
DECLARE external_critical_threshold_seconds INT64 DEFAULT 60;
DECLARE internal_threshold_seconds INT64 DEFAULT 600;

WITH traffic_classified AS (
  SELECT
    job_id,
    consumer_category,
    start_time,
    end_time,
    execution_time_ms,
    total_slot_ms,
    approximate_slot_count,
    DATE(start_time) AS execution_date,
    EXTRACT(HOUR FROM start_time) AS execution_hour,
    EXTRACT(MONTH FROM start_time) AS month
  FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`  -- Materialized view
  WHERE DATE(start_time) >= analysis_start_date
    AND DATE(start_time) <= analysis_end_date
    AND execution_time_ms IS NOT NULL
),
period_classified AS (
  SELECT
    *,
    CASE
      WHEN month IN (11, 12, 1) THEN 'PEAK'
      ELSE 'NON_PEAK'
    END AS period_type,
    CASE
      WHEN consumer_category = 'EXTERNAL_CRITICAL' 
        AND (execution_time_ms / 1000.0) > external_critical_threshold_seconds THEN TRUE
      WHEN consumer_category = 'INTERNAL' 
        AND (execution_time_ms / 1000.0) > internal_threshold_seconds THEN TRUE
      ELSE FALSE
    END AS is_qos_violation,
    TIMESTAMP_TRUNC(start_time, HOUR) AS violation_hour_timestamp
  FROM traffic_classified
),
qos_violations AS (
  SELECT
    *
  FROM period_classified
  WHERE is_qos_violation = TRUE
),
hourly_slot_utilization AS (
  SELECT
    violation_hour_timestamp,
    consumer_category,
    SUM(approximate_slot_count) AS total_slots,
    COUNT(*) AS job_count
  FROM period_classified
  WHERE approximate_slot_count IS NOT NULL
  GROUP BY
    violation_hour_timestamp,
    consumer_category
),
hourly_category_mix AS (
  SELECT
    violation_hour_timestamp,
    COUNT(DISTINCT consumer_category) AS concurrent_categories,
    SUM(total_slots) AS total_slots_all_categories
  FROM hourly_slot_utilization
  GROUP BY violation_hour_timestamp
)

SELECT
  qv.period_type,
  qv.consumer_category,
  qv.execution_date AS violation_date,
  qv.execution_hour AS violation_hour,
  COUNT(*) AS total_violations,
  AVG(hsu.total_slots) AS avg_slot_utilization,
  MAX(hsu.total_slots) AS max_slot_utilization,
  AVG(hcm.concurrent_categories) AS avg_concurrent_categories,
  AVG(hcm.total_slots_all_categories) AS avg_total_slots_all_categories
FROM qos_violations qv
LEFT JOIN hourly_slot_utilization hsu
  ON qv.violation_hour_timestamp = hsu.violation_hour_timestamp
  AND qv.consumer_category = hsu.consumer_category
LEFT JOIN hourly_category_mix hcm
  ON qv.violation_hour_timestamp = hcm.violation_hour_timestamp
GROUP BY
  qv.period_type,
  qv.consumer_category,
  qv.execution_date,
  qv.execution_hour
ORDER BY
  qv.period_type,
  qv.consumer_category,
  qv.execution_date,
  qv.execution_hour;

