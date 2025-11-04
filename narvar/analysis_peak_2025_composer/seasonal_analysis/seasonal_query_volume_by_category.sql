-- Seasonal Query Volume by Category: Analyzes query execution volume during peak vs. non-peak periods
-- Purpose: Identifies volume patterns and peak multipliers by consumer category
--
-- Compares query counts and execution frequency:
--   - Peak periods: November - January
--   - Non-peak periods: All other months
--
-- Parameters:
--   analysis_start_date: Start date for analysis (default: 2022-04-19)
--   analysis_end_date: End date for analysis (default: CURRENT_DATE)
--
-- Output Schema:
--   period_type: STRING - 'PEAK' or 'NON_PEAK'
--   consumer_category: STRING - EXTERNAL_CRITICAL, AUTOMATED_CRITICAL, INTERNAL
--   year: INT64 - Year
--   month: INT64 - Month (1-12)
--   query_count: INT64 - Total number of queries
--   avg_queries_per_day: FLOAT64 - Average queries per day
--   peak_multiplier: FLOAT64 - Ratio of peak to non-peak (if applicable)
--
-- Cost Warning: Processes all audit logs. For full history, expect 200-500GB+.

DECLARE analysis_start_date DATE DEFAULT '2022-04-19';
DECLARE analysis_end_date DATE DEFAULT CURRENT_DATE();

-- Note: This query should reference the unified_traffic_classification.sql results
-- For production, consider materializing unified classification results
WITH traffic_classified AS (
  -- In practice, this would reference materialized results or inline unified_traffic_classification
  -- For now, showing structure - actual implementation depends on materialization strategy
  SELECT
    job_id,
    consumer_category,
    DATE(start_time) AS execution_date,
    EXTRACT(YEAR FROM start_time) AS year,
    EXTRACT(MONTH FROM start_time) AS month
  FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`  -- Materialized view
  WHERE DATE(start_time) >= analysis_start_date
    AND DATE(start_time) <= analysis_end_date
    AND job_type = 'QUERY'  -- Focus on queries
),
period_classified AS (
  SELECT
    *,
    CASE
      WHEN month IN (11, 12, 1) THEN 'PEAK'
      ELSE 'NON_PEAK'
    END AS period_type
  FROM traffic_classified
),
monthly_aggregated AS (
  SELECT
    period_type,
    consumer_category,
    year,
    month,
    COUNT(DISTINCT job_id) AS query_count,
    COUNT(DISTINCT job_id) / CAST(COUNT(DISTINCT execution_date) AS FLOAT64) AS avg_queries_per_day
  FROM period_classified
  GROUP BY
    period_type,
    consumer_category,
    year,
    month
),
peak_nonpeak_comparison AS (
  SELECT
    consumer_category,
    year,
    AVG(CASE WHEN period_type = 'PEAK' THEN avg_queries_per_day END) AS peak_avg_per_day,
    AVG(CASE WHEN period_type = 'NON_PEAK' THEN avg_queries_per_day END) AS nonpeak_avg_per_day
  FROM monthly_aggregated
  GROUP BY consumer_category, year
)

SELECT
  ma.period_type,
  ma.consumer_category,
  ma.year,
  ma.month,
  ma.query_count,
  ma.avg_queries_per_day,
  SAFE_DIVIDE(pnc.peak_avg_per_day, pnc.nonpeak_avg_per_day) AS peak_multiplier
FROM monthly_aggregated ma
LEFT JOIN peak_nonpeak_comparison pnc
  ON ma.consumer_category = pnc.consumer_category
  AND ma.year = pnc.year
ORDER BY
  ma.year,
  ma.month,
  ma.consumer_category;

