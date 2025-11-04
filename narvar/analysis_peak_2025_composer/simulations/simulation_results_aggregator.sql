-- Simulation Results Aggregator: Compares all simulation scenarios
-- Purpose: Generates comprehensive comparison of all slot allocation simulations
--
-- Compares:
--   - QoS Metrics (P50, P95, P99, % exceeding thresholds)
--   - Cost Metrics (reservation costs, on-demand spillover, total cost)
--   - Utilization Metrics (slot utilization, idle time, contention)
--   - Trade-off Analysis (cost vs. QoS)
--
-- Parameters:
--   (None - aggregates results from all simulations)
--
-- Output Schema:
--   simulation_name: STRING - Name of simulation scenario
--   consumer_category: STRING - Consumer category (or 'ALL' for totals)
--   total_slots_allocated: INT64 - Total slots allocated
--   predicted_p95_execution_seconds: FLOAT64 - Predicted P95 execution time
--   predicted_pct_exceeding_threshold: FLOAT64 - Predicted % exceeding QoS threshold
--   estimated_monthly_cost_usd: FLOAT64 - Estimated monthly cost
--   estimated_peak_period_cost_usd: FLOAT64 - Estimated cost for Nov 2025 - Jan 2026
--   slot_utilization_pct: FLOAT64 - Average slot utilization percentage
--   recommendation_score: FLOAT64 - Composite score for recommendation (higher = better)
--
-- Cost Warning: Aggregates simulation results. Minimal processing cost.

WITH simulation_1_results AS (
  SELECT
    'Simulation 1: Isolated Internal' AS simulation_name,
    consumer_category,
    1700 AS total_slots_allocated,
    NULL AS predicted_p95_execution_seconds,  -- Would come from full simulation
    NULL AS predicted_pct_exceeding_threshold,
    0.0 AS estimated_monthly_cost_usd,
    0.0 AS estimated_peak_period_cost_usd,
    NULL AS slot_utilization_pct
  FROM UNNEST(['EXTERNAL_CRITICAL', 'AUTOMATED_CRITICAL', 'INTERNAL']) AS consumer_category
),
simulation_2_results AS (
  SELECT
    'Simulation 2: Fully Segmented' AS simulation_name,
    consumer_category,
    1700 AS total_slots_allocated,
    NULL AS predicted_p95_execution_seconds,
    NULL AS predicted_pct_exceeding_threshold,
    0.0 AS estimated_monthly_cost_usd,
    0.0 AS estimated_peak_period_cost_usd,
    NULL AS slot_utilization_pct
  FROM UNNEST(['EXTERNAL_CRITICAL', 'AUTOMATED_CRITICAL', 'INTERNAL']) AS consumer_category
),
all_simulations AS (
  SELECT * FROM simulation_1_results
  UNION ALL
  SELECT * FROM simulation_2_results
  -- Add results from other simulations
),
with_totals AS (
  SELECT
    simulation_name,
    consumer_category,
    total_slots_allocated,
    predicted_p95_execution_seconds,
    predicted_pct_exceeding_threshold,
    estimated_monthly_cost_usd,
    estimated_peak_period_cost_usd,
    slot_utilization_pct
  FROM all_simulations
  
  UNION ALL
  
  SELECT
    simulation_name,
    'ALL' AS consumer_category,
    SUM(DISTINCT total_slots_allocated) AS total_slots_allocated,
    AVG(predicted_p95_execution_seconds) AS predicted_p95_execution_seconds,
    AVG(predicted_pct_exceeding_threshold) AS predicted_pct_exceeding_threshold,
    SUM(estimated_monthly_cost_usd) AS estimated_monthly_cost_usd,
    SUM(estimated_peak_period_cost_usd) AS estimated_peak_period_cost_usd,
    AVG(slot_utilization_pct) AS slot_utilization_pct
  FROM all_simulations
  GROUP BY simulation_name
),
with_scores AS (
  SELECT
    *,
    -- Composite recommendation score (higher = better)
    -- Weight: QoS (40%), Cost efficiency (30%), Utilization (30%)
    SAFE_DIVIDE(100 - COALESCE(predicted_pct_exceeding_threshold, 50), 100.0) * 0.4 +
    SAFE_DIVIDE(100 - COALESCE(slot_utilization_pct, 50), 100.0) * 0.3 +
    SAFE_DIVIDE(1000 - COALESCE(estimated_monthly_cost_usd, 1000), 1000.0) * 0.3 AS recommendation_score
  FROM with_totals
)

SELECT
  simulation_name,
  consumer_category,
  total_slots_allocated,
  predicted_p95_execution_seconds,
  predicted_pct_exceeding_threshold,
  estimated_monthly_cost_usd,
  estimated_peak_period_cost_usd,
  slot_utilization_pct,
  recommendation_score
FROM with_scores
ORDER BY
  simulation_name,
  CASE consumer_category
    WHEN 'ALL' THEN 999
    ELSE 1
  END,
  consumer_category;

-- Note: Full implementation would integrate actual results from all simulation queries

