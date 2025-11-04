-- Baseline Peak Load Projection: Projects expected load for Nov 2025 - Jan 2026 peak period
-- Purpose: Applies growth rates to most recent peak period to predict 2025 peak load
--
-- Methodology:
--   1. Takes most recent peak period (Nov 2024 - Jan 2025) as baseline
--   2. Applies historical growth rates (from historical_trend_analysis.sql)
--   3. Accounts for seasonal multipliers (peak vs. non-peak ratios)
--   4. Projects slot consumption, query volume, and cost
--
-- Parameters:
--   growth_scenario: STRING - 'CONSERVATIVE', 'BASE', 'OPTIMISTIC' (default: 'BASE')
--   manual_growth_rate_pct: FLOAT64 - Manual override for growth rate (NULL = use calculated)
--
-- Output Schema:
--   consumer_category: STRING - Consumer category
--   metric_name: STRING - slot_ms, query_count, cost_usd
--   baseline_value: FLOAT64 - Value from Nov 2024 - Jan 2025 peak
--   projected_value_2025: FLOAT64 - Projected value for Nov 2025 - Jan 2026
--   growth_rate_pct: FLOAT64 - Growth rate applied
--   seasonal_multiplier: FLOAT64 - Peak vs. non-peak multiplier
--
-- Cost Warning: Processes audit logs for recent peak periods. Expect 50-100GB+.

DECLARE growth_scenario STRING DEFAULT 'BASE';
DECLARE manual_growth_rate_pct FLOAT64 DEFAULT NULL;

WITH recent_peak_baseline AS (
  SELECT
    consumer_category,
    SUM(total_slot_ms) AS total_slot_ms,
    COUNT(DISTINCT job_id) AS query_count,
    SUM(on_demand_cost) AS total_cost_usd
  FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`
  WHERE EXTRACT(YEAR FROM start_time) = 2024
    AND EXTRACT(MONTH FROM start_time) IN (11, 12)
    OR (EXTRACT(YEAR FROM start_time) = 2025 AND EXTRACT(MONTH FROM start_time) = 1)
  GROUP BY consumer_category
),
historical_growth AS (
  SELECT
    consumer_category,
    metric_name,
    AVG(yoy_growth_pct) AS avg_growth_rate_pct
  FROM (
    -- Use results from historical_trend_analysis.sql
    SELECT
      consumer_category,
      metric_name,
      yoy_growth_pct
    FROM `narvar-data-lake.analysis_peak_2025.prediction.historical_trends`  -- Materialized
    WHERE metric_name IN ('slot_ms', 'query_count', 'cost_usd')
  )
  GROUP BY consumer_category, metric_name
),
growth_rates AS (
  SELECT
    consumer_category,
    CASE
      WHEN growth_scenario = 'CONSERVATIVE' THEN avg_growth_rate_pct * 0.7
      WHEN growth_scenario = 'OPTIMISTIC' THEN avg_growth_rate_pct * 1.3
      ELSE avg_growth_rate_pct
    END AS applied_growth_rate_pct,
    metric_name
  FROM historical_growth
  WHERE COALESCE(manual_growth_rate_pct, applied_growth_rate_pct) IS NOT NULL
),
projections AS (
  SELECT
    rpb.consumer_category,
    'slot_ms' AS metric_name,
    rpb.total_slot_ms AS baseline_value,
    rpb.total_slot_ms * (1 + COALESCE(manual_growth_rate_pct, gr.applied_growth_rate_pct, 0) / 100.0) AS projected_value_2025,
    COALESCE(manual_growth_rate_pct, gr.applied_growth_rate_pct, 0) AS growth_rate_pct
  FROM recent_peak_baseline rpb
  LEFT JOIN growth_rates gr
    ON rpb.consumer_category = gr.consumer_category
    AND gr.metric_name = 'slot_ms'
  
  UNION ALL
  
  SELECT
    rpb.consumer_category,
    'query_count' AS metric_name,
    rpb.query_count AS baseline_value,
    rpb.query_count * (1 + COALESCE(manual_growth_rate_pct, gr.applied_growth_rate_pct, 0) / 100.0) AS projected_value_2025,
    COALESCE(manual_growth_rate_pct, gr.applied_growth_rate_pct, 0) AS growth_rate_pct
  FROM recent_peak_baseline rpb
  LEFT JOIN growth_rates gr
    ON rpb.consumer_category = gr.consumer_category
    AND gr.metric_name = 'query_count'
  
  UNION ALL
  
  SELECT
    rpb.consumer_category,
    'cost_usd' AS metric_name,
    rpb.total_cost_usd AS baseline_value,
    rpb.total_cost_usd * (1 + COALESCE(manual_growth_rate_pct, gr.applied_growth_rate_pct, 0) / 100.0) AS projected_value_2025,
    COALESCE(manual_growth_rate_pct, gr.applied_growth_rate_pct, 0) AS growth_rate_pct
  FROM recent_peak_baseline rpb
  LEFT JOIN growth_rates gr
    ON rpb.consumer_category = gr.consumer_category
    AND gr.metric_name = 'cost_usd'
)

SELECT
  consumer_category,
  metric_name,
  baseline_value,
  projected_value_2025,
  growth_rate_pct,
  1.0 AS seasonal_multiplier  -- Baseline is already from peak period
FROM projections
ORDER BY
  consumer_category,
  metric_name;

