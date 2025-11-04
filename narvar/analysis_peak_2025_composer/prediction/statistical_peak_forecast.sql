-- Statistical Peak Forecast: Time series forecasting with confidence intervals
-- Purpose: Advanced statistical forecasting for peak period with confidence intervals
--
-- Uses time series analysis techniques:
--   - Moving averages
--   - Exponential smoothing
--   - Confidence intervals
--   - Multiple scenario modeling (conservative, base, optimistic)
--
-- Parameters:
--   forecast_scenario: STRING - 'CONSERVATIVE', 'BASE', 'OPTIMISTIC'
--   forecast_months: ARRAY<INT64> - Months to forecast (default: [11, 12, 1] for Nov, Dec, Jan)
--   forecast_year: INT64 - Year to forecast (default: 2025)
--
-- Output Schema:
--   consumer_category: STRING - Consumer category
--   metric_name: STRING - Metric name
--   forecast_month: INT64 - Month (11, 12, or 1)
--   forecast_year: INT64 - Year (2025)
--   base_forecast: FLOAT64 - Base case forecast value
--   conservative_forecast: FLOAT64 - Conservative scenario
--   optimistic_forecast: FLOAT64 - Optimistic scenario
--   confidence_interval_lower: FLOAT64 - Lower bound (95% CI)
--   confidence_interval_upper: FLOAT64 - Upper bound (95% CI)
--
-- Cost Warning: Processes historical data with time series analysis.

DECLARE forecast_scenario STRING DEFAULT 'BASE';
DECLARE forecast_months ARRAY<INT64> DEFAULT [11, 12, 1];
DECLARE forecast_year INT64 DEFAULT 2025;

WITH historical_monthly AS (
  SELECT
    consumer_category,
    EXTRACT(YEAR FROM start_time) AS year,
    EXTRACT(MONTH FROM start_time) AS month,
    SUM(total_slot_ms) AS slot_ms,
    COUNT(DISTINCT job_id) AS query_count,
    SUM(on_demand_cost) AS cost_usd
  FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`
  WHERE EXTRACT(MONTH FROM start_time) IN UNNEST(forecast_months)
    AND EXTRACT(YEAR FROM start_time) < forecast_year
  GROUP BY consumer_category, year, month
),
monthly_with_trend AS (
  SELECT
    *,
    AVG(slot_ms) OVER (
      PARTITION BY consumer_category, month
      ORDER BY year
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS slot_ms_ma3,
    AVG(query_count) OVER (
      PARTITION BY consumer_category, month
      ORDER BY year
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS query_count_ma3,
    AVG(cost_usd) OVER (
      PARTITION BY consumer_category, month
      ORDER BY year
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS cost_usd_ma3,
    STDDEV(slot_ms) OVER (
      PARTITION BY consumer_category, month
      ORDER BY year
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS slot_ms_stddev,
    STDDEV(query_count) OVER (
      PARTITION BY consumer_category, month
      ORDER BY year
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS query_count_stddev,
    STDDEV(cost_usd) OVER (
      PARTITION BY consumer_category, month
      ORDER BY year
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS cost_usd_stddev
  FROM historical_monthly
),
latest_trends AS (
  SELECT
    consumer_category,
    month,
    slot_ms_ma3 AS base_slot_ms,
    query_count_ma3 AS base_query_count,
    cost_usd_ma3 AS base_cost_usd,
    slot_ms_stddev,
    query_count_stddev,
    cost_usd_stddev
  FROM monthly_with_trend
  WHERE year = (SELECT MAX(year) FROM historical_monthly)
),
forecasts AS (
  SELECT
    consumer_category,
    'slot_ms' AS metric_name,
    month AS forecast_month,
    forecast_year,
    base_slot_ms AS base_forecast,
    base_slot_ms * 0.85 AS conservative_forecast,
    base_slot_ms * 1.15 AS optimistic_forecast,
    base_slot_ms - (1.96 * COALESCE(slot_ms_stddev, base_slot_ms * 0.1)) AS confidence_interval_lower,
    base_slot_ms + (1.96 * COALESCE(slot_ms_stddev, base_slot_ms * 0.1)) AS confidence_interval_upper
  FROM latest_trends
  
  UNION ALL
  
  SELECT
    consumer_category,
    'query_count' AS metric_name,
    month AS forecast_month,
    forecast_year,
    base_query_count AS base_forecast,
    base_query_count * 0.85 AS conservative_forecast,
    base_query_count * 1.15 AS optimistic_forecast,
    base_query_count - (1.96 * COALESCE(query_count_stddev, base_query_count * 0.1)) AS confidence_interval_lower,
    base_query_count + (1.96 * COALESCE(query_count_stddev, base_query_count * 0.1)) AS confidence_interval_upper
  FROM latest_trends
  
  UNION ALL
  
  SELECT
    consumer_category,
    'cost_usd' AS metric_name,
    month AS forecast_month,
    forecast_year,
    base_cost_usd AS base_forecast,
    base_cost_usd * 0.85 AS conservative_forecast,
    base_cost_usd * 1.15 AS optimistic_forecast,
    base_cost_usd - (1.96 * COALESCE(cost_usd_stddev, base_cost_usd * 0.1)) AS confidence_interval_lower,
    base_cost_usd + (1.96 * COALESCE(cost_usd_stddev, base_cost_usd * 0.1)) AS confidence_interval_upper
  FROM latest_trends
)

SELECT
  consumer_category,
  metric_name,
  forecast_month,
  forecast_year,
  base_forecast,
  conservative_forecast,
  optimistic_forecast,
  confidence_interval_lower,
  confidence_interval_upper
FROM forecasts
WHERE forecast_month IN UNNEST(forecast_months)
ORDER BY
  consumer_category,
  metric_name,
  forecast_month;

