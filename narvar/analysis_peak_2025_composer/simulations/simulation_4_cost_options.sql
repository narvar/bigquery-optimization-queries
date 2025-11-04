-- Simulation 4: Cost-Optimized Scenarios
-- Purpose: Evaluates cost of additional slots vs. QoS improvement
--
-- Scenarios evaluated:
--   - Current: 1,700 slots
--   - Option A: 1,700 + 100 pay-as-you-go slots
--   - Option B: 1,700 + 500 committed slots (1yr/3yr)
--
-- Calculates incremental cost vs. QoS improvement for each option.

DECLARE peak_period_start DATE DEFAULT '2025-11-01';
DECLARE peak_period_end DATE DEFAULT '2026-01-31';
DECLARE baseline_slot_capacity INT64 DEFAULT 1700;

-- Additional slot options
DECLARE option_a_additional_slots INT64 DEFAULT 100;
DECLARE option_b_additional_slots INT64 DEFAULT 500;

-- Cost parameters
DECLARE cost_per_slot_1yr_monthly FLOAT64 DEFAULT 2000.0;
DECLARE cost_per_slot_3yr_monthly FLOAT64 DEFAULT 1500.0;
DECLARE cost_per_slot_paygo_monthly FLOAT64 DEFAULT 2500.0;
DECLARE ondemand_cost_per_slot_hour FLOAT64 DEFAULT 0.04;

WITH cost_scenarios AS (
  SELECT
    'BASELINE' AS scenario_name,
    baseline_slot_capacity AS total_slots,
    0 AS additional_slots,
    0.0 AS additional_monthly_cost,
    0.0 AS additional_peak_period_cost
  UNION ALL
  SELECT
    'OPTION_A_PAYGO' AS scenario_name,
    baseline_slot_capacity + option_a_additional_slots AS total_slots,
    option_a_additional_slots AS additional_slots,
    option_a_additional_slots * cost_per_slot_paygo_monthly AS additional_monthly_cost,
    option_a_additional_slots * cost_per_slot_paygo_monthly * 3 AS additional_peak_period_cost
  UNION ALL
  SELECT
    'OPTION_B_1YR_COMMITMENT' AS scenario_name,
    baseline_slot_capacity + option_b_additional_slots AS total_slots,
    option_b_additional_slots AS additional_slots,
    option_b_additional_slots * cost_per_slot_1yr_monthly AS additional_monthly_cost,
    option_b_additional_slots * cost_per_slot_1yr_monthly * 3 AS additional_peak_period_cost
  UNION ALL
  SELECT
    'OPTION_B_3YR_COMMITMENT' AS scenario_name,
    baseline_slot_capacity + option_b_additional_slots AS total_slots,
    option_b_additional_slots AS additional_slots,
    option_b_additional_slots * cost_per_slot_3yr_monthly AS additional_monthly_cost,
    option_b_additional_slots * cost_per_slot_3yr_monthly * 3 AS additional_peak_period_cost
)

SELECT
  scenario_name,
  total_slots,
  additional_slots,
  additional_monthly_cost,
  additional_peak_period_cost,
  'Evaluate QoS improvement vs. cost increase' AS evaluation_note,
  CURRENT_TIMESTAMP() AS simulation_timestamp
FROM cost_scenarios
ORDER BY
  CASE scenario_name
    WHEN 'BASELINE' THEN 1
    WHEN 'OPTION_A_PAYGO' THEN 2
    WHEN 'OPTION_B_1YR_COMMITMENT' THEN 3
    WHEN 'OPTION_B_3YR_COMMITMENT' THEN 4
  END;

-- Note: Full implementation would run QoS predictions for each scenario and compare

