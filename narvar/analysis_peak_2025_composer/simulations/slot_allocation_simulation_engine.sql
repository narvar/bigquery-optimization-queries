-- Slot Allocation Simulation Engine: Reusable engine for simulating slot allocation scenarios
-- Purpose: Core simulation logic for evaluating QoS/cost under different slot allocations
--
-- This query provides the base simulation engine that:
--   1. Takes predicted load from Phase 3
--   2. Applies slot constraints per category
--   3. Models slot contention and queuing
--   4. Estimates query execution times based on available slots
--   5. Calculates QoS metrics
--
-- Parameters (from simulation_config.sql):
--   See simulation_config.sql for all configurable parameters
--
-- Output Schema:
--   consumer_category: STRING - Consumer category
--   simulation_timestamp: TIMESTAMP - Hour being simulated
--   predicted_slot_demand: FLOAT64 - Predicted slot demand
--   available_slots: FLOAT64 - Available slots for this category
--   slot_utilization_ratio: FLOAT64 - Demand / Available slots
--   estimated_execution_time_factor: FLOAT64 - Execution time multiplier due to contention
--   predicted_p95_execution_seconds: FLOAT64 - Predicted P95 execution time
--   predicted_pct_exceeding_threshold: FLOAT64 - Predicted % exceeding QoS threshold
--
-- Cost Warning: Processes predicted load data. Expect 1-10GB depending on granularity.

-- Import parameters from simulation_config.sql (copy DECLARE statements)

WITH projected_load AS (
  SELECT
    consumer_category,
    projected_value_2025 AS projected_slot_ms,
    'slot_ms' AS metric_name
  FROM `narvar-data-lake.analysis_peak_2025.prediction.baseline_projection`
  WHERE metric_name = 'slot_ms'
  -- Alternative: Use inline projection if materialized view not available
),
hourly_load_distribution AS (
  SELECT
    consumer_category,
    projected_slot_ms / (90.0 * 24 * 3600 * 1000) AS avg_slots_per_second,
    projected_slot_ms / (90.0 * 24 * 3600 * 1000) * 1.5 AS peak_slots_per_second
  FROM projected_load
),
slot_allocation AS (
  SELECT
    consumer_category,
    CASE
      WHEN consumer_category = 'EXTERNAL_CRITICAL' 
        THEN COALESCE(external_critical_slots, total_slot_capacity * 0.5)
      WHEN consumer_category = 'AUTOMATED_CRITICAL'
        THEN COALESCE(automated_critical_slots, total_slot_capacity * 0.3)
      WHEN consumer_category = 'INTERNAL'
        THEN COALESCE(internal_slots, total_slot_capacity * 0.2)
      ELSE total_slot_capacity * 0.1
    END AS allocated_slots
  FROM (
    SELECT DISTINCT consumer_category FROM projected_load
  )
),
historical_performance_baseline AS (
  SELECT
    consumer_category,
    APPROX_QUANTILES(execution_time_ms / 1000.0, 100)[OFFSET(95)] AS baseline_p95_seconds,
    AVG(execution_time_ms / 1000.0) AS baseline_avg_seconds,
    SAFE_DIVIDE(
      SUM(CASE
        WHEN (consumer_category = 'EXTERNAL_CRITICAL' AND execution_time_ms / 1000.0 > external_critical_threshold_seconds)
          OR (consumer_category = 'INTERNAL' AND execution_time_ms / 1000.0 > internal_threshold_seconds)
        THEN 1 ELSE 0 END),
      COUNT(*)
    ) * 100.0 AS baseline_pct_exceeding
  FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`
  WHERE EXTRACT(MONTH FROM start_time) IN (11, 12, 1)
    AND EXTRACT(YEAR FROM start_time) >= 2022
  GROUP BY consumer_category
),
simulation_results AS (
  SELECT
    hld.consumer_category,
    sa.allocated_slots AS available_slots,
    hld.peak_slots_per_second AS predicted_slot_demand,
    SAFE_DIVIDE(hld.peak_slots_per_second, sa.allocated_slots) AS slot_utilization_ratio,
    GREATEST(1.0, SAFE_DIVIDE(hld.peak_slots_per_second, sa.allocated_slots)) AS estimated_execution_time_factor,
    hpb.baseline_p95_seconds * GREATEST(1.0, SAFE_DIVIDE(hld.peak_slots_per_second, sa.allocated_slots)) AS predicted_p95_execution_seconds,
    GREATEST(
      hpb.baseline_pct_exceeding,
      CASE
        WHEN SAFE_DIVIDE(hld.peak_slots_per_second, sa.allocated_slots) > 1.0
        THEN (SAFE_DIVIDE(hld.peak_slots_per_second, sa.allocated_slots) - 1.0) * 30.0
        ELSE 0.0
      END
    ) AS predicted_pct_exceeding_threshold
  FROM hourly_load_distribution hld
  JOIN slot_allocation sa
    ON hld.consumer_category = sa.consumer_category
  LEFT JOIN historical_performance_baseline hpb
    ON hld.consumer_category = hpb.consumer_category
)

SELECT
  consumer_category,
  CURRENT_TIMESTAMP() AS simulation_timestamp,
  predicted_slot_demand,
  available_slots,
  slot_utilization_ratio,
  estimated_execution_time_factor,
  predicted_p95_execution_seconds,
  predicted_pct_exceeding_threshold
FROM simulation_results
ORDER BY consumer_category;

