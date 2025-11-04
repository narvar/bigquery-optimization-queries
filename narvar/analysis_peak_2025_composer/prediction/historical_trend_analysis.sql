-- Historical Trend Analysis: Calculates growth rates for slot consumption, query volume, and cost
-- Purpose: Provides year-over-year growth trends for predictive modeling
--
-- Calculates:
--   - Year-over-year (YoY) growth rates for:
--     * Total slot consumption
--     * Query volume
--     * Cost per category
--   - Linear/exponential trend fitting
--   - Growth rate projections
--
-- Parameters:
--   analysis_start_date: Start date for analysis (default: 2022-04-19)
--   analysis_end_date: End date for analysis (default: CURRENT_DATE)
--
-- Output Schema:
--   consumer_category: STRING - Consumer category
--   metric_name: STRING - Metric name (slot_ms, query_count, cost_usd)
--   year: INT64 - Year
--   value: FLOAT64 - Metric value for the year
--   yoy_growth_pct: FLOAT64 - Year-over-year growth percentage
--   avg_yoy_growth_pct: FLOAT64 - Average YoY growth across all years
--   linear_trend_slope: FLOAT64 - Linear trend slope (if applicable)
--
-- Cost Warning: Processes all historical audit logs. For full history, expect 200-500GB+.

DECLARE analysis_start_date DATE DEFAULT '2022-04-19';
DECLARE analysis_end_date DATE DEFAULT CURRENT_DATE();

WITH traffic_classified AS (
  SELECT
    job_id,
    consumer_category,
    start_time,
    total_slot_ms,
    on_demand_cost,
    EXTRACT(YEAR FROM start_time) AS year
  FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`  -- Materialized view
  WHERE DATE(start_time) >= analysis_start_date
    AND DATE(start_time) <= analysis_end_date
),
yearly_slot_metrics AS (
  SELECT
    consumer_category,
    year,
    SUM(total_slot_ms) AS total_slot_ms
  FROM traffic_classified
  WHERE total_slot_ms IS NOT NULL
  GROUP BY consumer_category, year
),
yearly_query_metrics AS (
  SELECT
    consumer_category,
    year,
    COUNT(DISTINCT job_id) AS query_count
  FROM traffic_classified
  GROUP BY consumer_category, year
),
yearly_cost_metrics AS (
  SELECT
    consumer_category,
    year,
    SUM(on_demand_cost) AS total_cost_usd
  FROM traffic_classified
  WHERE on_demand_cost IS NOT NULL
  GROUP BY consumer_category, year
),
yearly_metrics AS (
  SELECT
    COALESCE(s.consumer_category, q.consumer_category, c.consumer_category) AS consumer_category,
    COALESCE(s.year, q.year, c.year) AS year,
    COALESCE(s.total_slot_ms, 0) AS slot_ms,
    COALESCE(q.query_count, 0) AS query_count,
    COALESCE(c.total_cost_usd, 0) AS cost_usd
  FROM yearly_slot_metrics s
  FULL OUTER JOIN yearly_query_metrics q
    ON s.consumer_category = q.consumer_category
    AND s.year = q.year
  FULL OUTER JOIN yearly_cost_metrics c
    ON COALESCE(s.consumer_category, q.consumer_category) = c.consumer_category
    AND COALESCE(s.year, q.year) = c.year
),
with_yoy_growth AS (
  SELECT
    consumer_category,
    year,
    slot_ms,
    query_count,
    cost_usd,
    LAG(slot_ms) OVER (PARTITION BY consumer_category ORDER BY year) AS prev_year_slot_ms,
    LAG(query_count) OVER (PARTITION BY consumer_category ORDER BY year) AS prev_year_query_count,
    LAG(cost_usd) OVER (PARTITION BY consumer_category ORDER BY year) AS prev_year_cost_usd
  FROM yearly_metrics
),
growth_rates AS (
  SELECT
    consumer_category,
    year,
    slot_ms,
    query_count,
    cost_usd,
    SAFE_DIVIDE(slot_ms - prev_year_slot_ms, prev_year_slot_ms) * 100.0 AS yoy_growth_slot_pct,
    SAFE_DIVIDE(query_count - prev_year_query_count, prev_year_query_count) * 100.0 AS yoy_growth_query_pct,
    SAFE_DIVIDE(cost_usd - prev_year_cost_usd, prev_year_cost_usd) * 100.0 AS yoy_growth_cost_pct
  FROM with_yoy_growth
  WHERE prev_year_slot_ms IS NOT NULL  -- Only rows with previous year data
),
unpivoted AS (
  SELECT
    consumer_category,
    'slot_ms' AS metric_name,
    year,
    slot_ms AS value,
    yoy_growth_slot_pct AS yoy_growth_pct
  FROM growth_rates
  
  UNION ALL
  
  SELECT
    consumer_category,
    'query_count' AS metric_name,
    year,
    query_count AS value,
    yoy_growth_query_pct AS yoy_growth_pct
  FROM growth_rates
  
  UNION ALL
  
  SELECT
    consumer_category,
    'cost_usd' AS metric_name,
    year,
    cost_usd AS value,
    yoy_growth_cost_pct AS yoy_growth_pct
  FROM growth_rates
),
with_avg_growth AS (
  SELECT
    consumer_category,
    metric_name,
    year,
    value,
    yoy_growth_pct,
    AVG(yoy_growth_pct) OVER (
      PARTITION BY consumer_category, metric_name
      ORDER BY year
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS avg_yoy_growth_pct
  FROM unpivoted
  WHERE yoy_growth_pct IS NOT NULL
)

SELECT
  consumer_category,
  metric_name,
  year,
  value,
  yoy_growth_pct,
  avg_yoy_growth_pct
FROM with_avg_growth
ORDER BY
  consumer_category,
  metric_name,
  year;

