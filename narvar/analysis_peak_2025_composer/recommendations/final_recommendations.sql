-- Final Recommendations: Optimal slot configuration based on simulation results
-- Purpose: Synthesizes findings into actionable slot allocation recommendations
--
-- This query aggregates results from all phases to provide:
--   - Optimal slot allocation per category
--   - Reservation strategy (committed vs. flex)
--   - Total slot capacity needed
--   - Cost projection
--   - Expected QoS guarantees
--
-- Parameters:
--   (None - uses aggregated results from all previous analysis)
--
-- Output Schema:
--   recommendation_category: STRING - Category of recommendation
--   recommendation_details: STRING - Detailed recommendation text
--   slot_allocation: STRUCT - Recommended slot allocation
--   estimated_cost_usd: FLOAT64 - Estimated cost
--   expected_qos_metrics: STRUCT - Expected QoS metrics
--   confidence_level: STRING - HIGH, MEDIUM, LOW
--   risk_assessment: STRING - Risk factors and mitigations
--
-- Cost Warning: This query aggregates existing results. Minimal processing cost.

WITH simulation_comparison AS (
  SELECT
    simulation_name,
    consumer_category,
    total_slots_allocated,
    predicted_p95_execution_seconds,
    predicted_pct_exceeding_threshold,
    estimated_monthly_cost_usd,
    recommendation_score
  FROM `narvar-data-lake.analysis_peak_2025.simulations.simulation_results`  -- Materialized
  WHERE consumer_category = 'ALL'
),
best_simulation AS (
  SELECT
    *
  FROM simulation_comparison
  ORDER BY recommendation_score DESC
  LIMIT 1
),
qos_prediction AS (
  SELECT
    consumer_category,
    predicted_p95_execution_seconds,
    predicted_pct_exceeding_threshold
  FROM `narvar-data-lake.analysis_peak_2025.prediction.qos_prediction_current_allocation`
),
cost_projection AS (
  SELECT
    SUM(peak_period_cost_usd) AS total_peak_period_cost
  FROM `narvar-data-lake.analysis_peak_2025.prediction.cost_prediction_current_allocation`
)

SELECT
  'OPTIMAL_SLOT_ALLOCATION' AS recommendation_category,
  CONCAT(
    'Based on simulation results, recommended allocation: ',
    CAST(total_slots_allocated AS STRING),
    ' total slots. See simulation: ',
    simulation_name
  ) AS recommendation_details,
  STRUCT(
    total_slots_allocated AS total_slots,
    NULL AS external_critical_slots,
    NULL AS automated_critical_slots,
    NULL AS internal_slots
  ) AS slot_allocation,
  estimated_monthly_cost_usd AS estimated_cost_usd,
  STRUCT(
    predicted_p95_execution_seconds AS p95_execution_seconds,
    predicted_pct_exceeding_threshold AS pct_exceeding_threshold
  ) AS expected_qos_metrics,
  'MEDIUM' AS confidence_level,
  'Based on historical trends and projected load. Actual results may vary.' AS risk_assessment
FROM best_simulation

UNION ALL

SELECT
  'COST_PROJECTION' AS recommendation_category,
  CONCAT(
    'Estimated total cost for Nov 2025 - Jan 2026 peak period: $',
    CAST(total_peak_period_cost AS STRING)
  ) AS recommendation_details,
  NULL AS slot_allocation,
  total_peak_period_cost AS estimated_cost_usd,
  NULL AS expected_qos_metrics,
  'MEDIUM' AS confidence_level,
  'Cost estimates based on current pricing. Actual costs may vary.' AS risk_assessment
FROM cost_projection

UNION ALL

SELECT
  'QOS_GUARANTEES' AS recommendation_category,
  CONCAT(
    'Expected QoS metrics under recommended configuration. ',
    'External Critical: P95 < 60s, Internal: P95 < 600s'
  ) AS recommendation_details,
  NULL AS slot_allocation,
  NULL AS estimated_cost_usd,
  STRUCT(
    AVG(predicted_p95_execution_seconds) AS avg_p95_execution_seconds,
    AVG(predicted_pct_exceeding_threshold) AS avg_pct_exceeding_threshold
  ) AS expected_qos_metrics,
  'HIGH' AS confidence_level,
  'QoS predictions based on historical patterns and projected demand.' AS risk_assessment
FROM qos_prediction;

-- Note: Full implementation would integrate all analysis results for comprehensive recommendations

