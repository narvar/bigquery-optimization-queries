-- QoS Prediction with Current Allocation: Predicts QoS metrics under current 1,700-slot allocation
-- Purpose: Simulates QoS during predicted peak period with current slot constraints
--
-- Predicts query execution times based on:
--   - Predicted slot demand vs. available capacity (1,700 slots)
--   - Historical slot contention → QoS degradation correlations
--   - Queue time predictions when demand exceeds capacity
--
-- Parameters:
--   forecast_scenario: STRING - 'CONSERVATIVE', 'BASE', 'OPTIMISTIC' (default: 'BASE')
--   current_slot_capacity: INT64 - Current total slot capacity (default: 1700)
--
-- Output Schema:
--   consumer_category: STRING - Consumer category
--   forecast_period: STRING - Month/year (e.g., 'Nov 2025')
--   predicted_avg_slot_demand: FLOAT64 - Predicted average slot demand
--   predicted_peak_slot_demand: FLOAT64 - Predicted peak slot demand
--   slot_contention_ratio: FLOAT64 - Ratio of demand to capacity
--   predicted_p95_execution_seconds: FLOAT64 - Predicted P95 execution time
--   predicted_pct_exceeding_threshold: FLOAT64 - Predicted % exceeding QoS threshold
--   queue_time_seconds: FLOAT64 - Estimated queue time when slots exceeded
--
-- Cost Warning: Processes historical data with correlations.

DECLARE forecast_scenario STRING DEFAULT 'BASE';
DECLARE current_slot_capacity INT64 DEFAULT 1700;

WITH projected_load AS (
  -- Use baseline_peak_load_projection.sql results
  SELECT
    consumer_category,
    projected_value_2025 AS projected_slot_ms,
    'BASE' AS scenario
  FROM `narvar-data-lake.analysis_peak_2025.prediction.baseline_projection`
  WHERE metric_name = 'slot_ms'
  -- Inline projection logic if materialized view not available
),
historical_contention_qos AS (
  SELECT
    consumer_category,
    SAFE_DIVIDE(SUM(total_slot_ms), 1700.0 * 86400000) AS avg_slot_utilization,
    APPROX_QUANTILES(execution_time_ms / 1000.0, 100)[OFFSET(95)] AS p95_execution_seconds,
    SAFE_DIVIDE(
      SUM(CASE
        WHEN (consumer_category = 'EXTERNAL_CRITICAL' AND execution_time_ms / 1000.0 > 60)
          OR (consumer_category = 'INTERNAL' AND execution_time_ms / 1000.0 > 600)
        THEN 1 ELSE 0 END),
      COUNT(*)
    ) * 100.0 AS pct_exceeding_threshold
  FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`
  WHERE EXTRACT(MONTH FROM start_time) IN (11, 12, 1)
    AND EXTRACT(YEAR FROM start_time) >= 2022
    AND total_slot_ms IS NOT NULL
  GROUP BY consumer_category
),
slot_demand_estimate AS (
  SELECT
    pl.consumer_category,
    pl.projected_slot_ms / (90.0 * 86400000) AS avg_slot_demand_per_second,
    pl.projected_slot_ms / (90.0 * 86400000) * 1.5 AS peak_slot_demand_per_second
  FROM projected_load pl
),
qos_predictions AS (
  SELECT
    sd.consumer_category,
    'Nov 2025 - Jan 2026' AS forecast_period,
    sd.avg_slot_demand_per_second AS predicted_avg_slot_demand,
    sd.peak_slot_demand_per_second AS predicted_peak_slot_demand,
    SAFE_DIVIDE(sd.peak_slot_demand_per_second, current_slot_capacity) AS slot_contention_ratio,
    hc.p95_execution_seconds * 
      GREATEST(1.0, SAFE_DIVIDE(sd.peak_slot_demand_per_second, current_slot_capacity)) AS predicted_p95_execution_seconds,
    GREATEST(
      hc.pct_exceeding_threshold,
      CASE
        WHEN SAFE_DIVIDE(sd.peak_slot_demand_per_second, current_slot_capacity) > 1.0
        THEN (SAFE_DIVIDE(sd.peak_slot_demand_per_second, current_slot_capacity) - 1.0) * 50.0
        ELSE 0.0
      END
    ) AS predicted_pct_exceeding_threshold,
    CASE
      WHEN SAFE_DIVIDE(sd.peak_slot_demand_per_second, current_slot_capacity) > 1.0
      THEN (SAFE_DIVIDE(sd.peak_slot_demand_per_second, current_slot_capacity) - 1.0) * 30.0
      ELSE 0.0
    END AS queue_time_seconds
  FROM slot_demand_estimate sd
  LEFT JOIN historical_contention_qos hc
    ON sd.consumer_category = hc.consumer_category
)

SELECT
  consumer_category,
  forecast_period,
  predicted_avg_slot_demand,
  predicted_peak_slot_demand,
  slot_contention_ratio,
  predicted_p95_execution_seconds,
  predicted_pct_exceeding_threshold,
  queue_time_seconds
FROM qos_predictions
ORDER BY consumer_category;

