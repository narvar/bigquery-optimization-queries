-- Cost Prediction with Current Allocation: Estimates costs under current 1,700-slot allocation
-- Purpose: Predicts total cost for peak period including on-demand spillover
--
-- Estimates:
--   - Reservation costs (existing commitments)
--   - On-demand spillover (if slots exceeded)
--   - Total cost for Nov 2025 - Jan 2026 peak period
--
-- Parameters:
--   forecast_scenario: STRING - 'CONSERVATIVE', 'BASE', 'OPTIMISTIC'
--   current_slot_capacity: INT64 - Current total slot capacity (default: 1700)
--   reservation_1yr_slots: INT64 - 1-year commitment slots (default: 500)
--   reservation_3yr_slots: INT64 - 3-year commitment slots (default: 500)
--   reservation_paygo_slots: INT64 - Pay-as-you-go slots (default: 700)
--   cost_per_slot_1yr_monthly: FLOAT64 - Monthly cost per 1yr slot (USD, adjust as needed)
--   cost_per_slot_3yr_monthly: FLOAT64 - Monthly cost per 3yr slot (USD, adjust as needed)
--
-- Output Schema:
--   cost_category: STRING - RESERVATION_1YR, RESERVATION_3YR, RESERVATION_PAYGO, ONDEMAND_SPILLOVER, TOTAL
--   monthly_cost_usd: FLOAT64 - Monthly cost in USD
--   peak_period_cost_usd: FLOAT64 - Total cost for Nov 2025 - Jan 2026 (3 months)
--   notes: STRING - Additional notes/assumptions
--
-- Cost Warning: This is a cost estimation query, not a processing query.

DECLARE forecast_scenario STRING DEFAULT 'BASE';
DECLARE current_slot_capacity INT64 DEFAULT 1700;
DECLARE reservation_1yr_slots INT64 DEFAULT 500;
DECLARE reservation_3yr_slots INT64 DEFAULT 500;
DECLARE reservation_paygo_slots INT64 DEFAULT 700;
DECLARE cost_per_slot_1yr_monthly FLOAT64 DEFAULT 2000.0;  -- Adjust based on actual pricing
DECLARE cost_per_slot_3yr_monthly FLOAT64 DEFAULT 1500.0;  -- Adjust based on actual pricing
DECLARE cost_per_slot_paygo_monthly FLOAT64 DEFAULT 2500.0;  -- Adjust based on actual pricing
DECLARE ondemand_cost_per_slot_hour FLOAT64 DEFAULT 0.04;  -- On-demand slot pricing per hour

WITH projected_slot_demand AS (
  SELECT
    SUM(projected_value_2025) AS total_projected_slot_ms
  FROM `narvar-data-lake.analysis_peak_2025.prediction.baseline_projection`
  WHERE metric_name = 'slot_ms'
),
reservation_costs AS (
  SELECT
    'RESERVATION_1YR' AS cost_category,
    reservation_1yr_slots * cost_per_slot_1yr_monthly AS monthly_cost_usd,
    reservation_1yr_slots * cost_per_slot_1yr_monthly * 3 AS peak_period_cost_usd,
    CONCAT('1-year commitment: ', CAST(reservation_1yr_slots AS STRING), ' slots') AS notes
  UNION ALL
  SELECT
    'RESERVATION_3YR' AS cost_category,
    reservation_3yr_slots * cost_per_slot_3yr_monthly AS monthly_cost_usd,
    reservation_3yr_slots * cost_per_slot_3yr_monthly * 3 AS peak_period_cost_usd,
    CONCAT('3-year commitment: ', CAST(reservation_3yr_slots AS STRING), ' slots') AS notes
  UNION ALL
  SELECT
    'RESERVATION_PAYGO' AS cost_category,
    reservation_paygo_slots * cost_per_slot_paygo_monthly AS monthly_cost_usd,
    reservation_paygo_slots * cost_per_slot_paygo_monthly * 3 AS peak_period_cost_usd,
    CONCAT('Pay-as-you-go: ', CAST(reservation_paygo_slots AS STRING), ' slots') AS notes
),
spillover_estimate AS (
  SELECT
    CASE
      WHEN (psd.total_projected_slot_ms / (90.0 * 86400000)) > current_slot_capacity
      THEN ((psd.total_projected_slot_ms / (90.0 * 86400000)) - current_slot_capacity) * 730.0 * ondemand_cost_per_slot_hour
      ELSE 0
    END AS monthly_spillover_cost,
    CASE
      WHEN (psd.total_projected_slot_ms / (90.0 * 86400000)) > current_slot_capacity
      THEN ((psd.total_projected_slot_ms / (90.0 * 86400000)) - current_slot_capacity) * 730.0 * ondemand_cost_per_slot_hour * 3
      ELSE 0
    END AS peak_period_spillover_cost
  FROM projected_slot_demand psd
),
spillover_cost AS (
  SELECT
    'ONDEMAND_SPILLOVER' AS cost_category,
    monthly_spillover_cost AS monthly_cost_usd,
    peak_period_spillover_cost AS peak_period_cost_usd,
    'Estimated spillover when demand exceeds capacity' AS notes
  FROM spillover_estimate
),
all_costs AS (
  SELECT * FROM reservation_costs
  UNION ALL
  SELECT * FROM spillover_cost
)

SELECT
  *,
  SUM(peak_period_cost_usd) OVER () AS total_peak_period_cost
FROM all_costs
UNION ALL
SELECT
  'TOTAL' AS cost_category,
  SUM(monthly_cost_usd) AS monthly_cost_usd,
  SUM(peak_period_cost_usd) AS peak_period_cost_usd,
  'Sum of all cost categories' AS notes,
  SUM(peak_period_cost_usd) AS total_peak_period_cost
FROM all_costs
ORDER BY
  CASE cost_category
    WHEN 'TOTAL' THEN 999
    ELSE 1
  END,
  cost_category;

