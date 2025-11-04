-- Seasonal Cost Analysis: Analyzes costs by category during peak vs. non-peak periods
-- Purpose: Compares cost patterns and identifies cost drivers by period and category
--
-- Analyzes:
--   - Cost per category during peak vs. non-peak
--   - On-demand vs. reservation cost breakdowns
--   - Cost efficiency metrics (cost per query, cost per TB)
--   - Cost multipliers (peak vs. non-peak)
--
-- Parameters:
--   analysis_start_date: Start date for analysis (default: 2022-04-19)
--   analysis_end_date: End date for analysis (default: CURRENT_DATE)
--   on_demand_price_per_tb: On-demand pricing per TB (default: 5.0)
--
-- Output Schema:
--   period_type: STRING - 'PEAK' or 'NON_PEAK'
--   consumer_category: STRING - Consumer category
--   year: INT64 - Year
--   month: INT64 - Month
--   total_cost_usd: FLOAT64 - Total on-demand cost in USD
--   total_billed_tb: FLOAT64 - Total terabytes billed
--   query_count: INT64 - Total query count
--   cost_per_query: FLOAT64 - Average cost per query
--   cost_per_tb: FLOAT64 - Cost per terabyte (should match on_demand_price_per_tb)
--   peak_cost_multiplier: FLOAT64 - Ratio of peak to non-peak cost
--
-- Cost Warning: Processes all audit logs. For full history, expect 200-500GB+.

DECLARE analysis_start_date DATE DEFAULT '2022-04-19';
DECLARE analysis_end_date DATE DEFAULT CURRENT_DATE();
DECLARE on_demand_price_per_tb FLOAT64 DEFAULT 5.0;

WITH traffic_classified AS (
  SELECT
    job_id,
    consumer_category,
    start_time,
    total_billed_bytes,
    on_demand_cost,
    EXTRACT(YEAR FROM start_time) AS year,
    EXTRACT(MONTH FROM start_time) AS month
  FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`  -- Materialized view
  WHERE DATE(start_time) >= analysis_start_date
    AND DATE(start_time) <= analysis_end_date
    AND total_billed_bytes IS NOT NULL
),
period_classified AS (
  SELECT
    *,
    CASE
      WHEN month IN (11, 12, 1) THEN 'PEAK'
      ELSE 'NON_PEAK'
    END AS period_type,
    total_billed_bytes / POW(1024, 4) AS total_billed_tb
  FROM traffic_classified
),
monthly_aggregated AS (
  SELECT
    period_type,
    consumer_category,
    year,
    month,
    SUM(on_demand_cost) AS total_cost_usd,
    SUM(total_billed_tb) AS total_billed_tb,
    COUNT(DISTINCT job_id) AS query_count
  FROM period_classified
  GROUP BY
    period_type,
    consumer_category,
    year,
    month
),
with_efficiency_metrics AS (
  SELECT
    *,
    SAFE_DIVIDE(total_cost_usd, query_count) AS cost_per_query,
    SAFE_DIVIDE(total_cost_usd, total_billed_tb) AS cost_per_tb
  FROM monthly_aggregated
),
peak_nonpeak_comparison AS (
  SELECT
    consumer_category,
    year,
    AVG(CASE WHEN period_type = 'PEAK' THEN total_cost_usd END) AS peak_avg_cost,
    AVG(CASE WHEN period_type = 'NON_PEAK' THEN total_cost_usd END) AS nonpeak_avg_cost
  FROM monthly_aggregated
  GROUP BY consumer_category, year
)

SELECT
  wem.period_type,
  wem.consumer_category,
  wem.year,
  wem.month,
  wem.total_cost_usd,
  wem.total_billed_tb,
  wem.query_count,
  wem.cost_per_query,
  wem.cost_per_tb,
  SAFE_DIVIDE(pnc.peak_avg_cost, pnc.nonpeak_avg_cost) AS peak_cost_multiplier
FROM with_efficiency_metrics wem
LEFT JOIN peak_nonpeak_comparison pnc
  ON wem.consumer_category = pnc.consumer_category
  AND wem.year = pnc.year
ORDER BY
  wem.year,
  wem.month,
  wem.consumer_category;

