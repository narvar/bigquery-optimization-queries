-- Seasonal Slot Patterns by Category: Analyzes slot consumption patterns during peak vs. non-peak periods
-- Purpose: Identifies seasonal patterns in slot usage by consumer category
--
-- This query compares slot consumption:
--   - Peak periods: November - January (Nov, Dec, Jan)
--   - Non-peak periods: All other months
--
-- Metrics analyzed:
--   - Hourly slot usage patterns
--   - Daily slot usage patterns
--   - Peak hour identification (time-of-day, day-of-week)
--   - Concurrency patterns
--
-- Parameters:
--   analysis_start_date: Start date for analysis (default: 2022-04-19, earliest available)
--   analysis_end_date: End date for analysis (default: CURRENT_DATE)
--
-- Output Schema:
--   period_type: STRING - 'PEAK' or 'NON_PEAK'
--   consumer_category: STRING - EXTERNAL_CRITICAL, AUTOMATED_CRITICAL, INTERNAL
--   hour_of_day: INT64 - Hour of day (0-23)
--   day_of_week: INT64 - Day of week (1=Sunday, 7=Saturday)
--   avg_slot_count: FLOAT64 - Average slot count for this hour/day
--   max_slot_count: FLOAT64 - Maximum slot count for this hour/day
--   p95_slot_count: FLOAT64 - 95th percentile slot count
--   total_slot_ms: INT64 - Total slot milliseconds
--   execution_count: INT64 - Number of job executions
--
-- Cost Warning: This query processes all audit logs with traffic classification.
--               For full history (3+ years), expect to process 200-500GB+.
--               STRONGLY RECOMMEND starting with smaller date ranges or using materialized views.

DECLARE analysis_start_date DATE DEFAULT '2022-04-19';  -- Earliest available data
DECLARE analysis_end_date DATE DEFAULT CURRENT_DATE();

-- Use unified traffic classification as base
WITH traffic_classified AS (
  SELECT
    job_id,
    consumer_category,
    project_id,
    start_time,
    end_time,
    execution_time_ms,
    total_slot_ms,
    approximate_slot_count,
    job_type
  FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`  -- This would be a materialized view
  -- Or use unified_traffic_classification.sql as a CTE (for smaller date ranges)
  WHERE DATE(start_time) >= analysis_start_date
    AND DATE(start_time) <= analysis_end_date
),
-- Alternative: If using unified_traffic_classification.sql inline, uncomment and use this CTE:
/*
traffic_classified AS (
  -- Copy logic from unified_traffic_classification.sql here for inline classification
  -- This is computationally expensive, so prefer materialized view approach
),
*/
period_classified AS (
  SELECT
    *,
    CASE
      WHEN EXTRACT(MONTH FROM start_time) IN (11, 12, 1) THEN 'PEAK'
      ELSE 'NON_PEAK'
    END AS period_type,
    EXTRACT(HOUR FROM start_time) AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM start_time) AS day_of_week,
    TIMESTAMP_TRUNC(start_time, HOUR) AS hour_timestamp,
    DATE(start_time) AS date_value
  FROM traffic_classified
),
hourly_aggregated AS (
  SELECT
    period_type,
    consumer_category,
    hour_of_day,
    day_of_week,
    hour_timestamp,
    AVG(approximate_slot_count) AS avg_slot_count,
    MAX(approximate_slot_count) AS max_slot_count,
    APPROX_QUANTILES(approximate_slot_count, 100)[OFFSET(95)] AS p95_slot_count,
    SUM(total_slot_ms) AS total_slot_ms,
    COUNT(*) AS execution_count
  FROM period_classified
  WHERE approximate_slot_count IS NOT NULL
  GROUP BY
    period_type,
    consumer_category,
    hour_of_day,
    day_of_week,
    hour_timestamp
)

SELECT
  period_type,
  consumer_category,
  hour_of_day,
  day_of_week,
  AVG(avg_slot_count) AS avg_slot_count,
  MAX(max_slot_count) AS max_slot_count,
  APPROX_QUANTILES(p95_slot_count, 100)[OFFSET(95)] AS p95_slot_count,
  SUM(total_slot_ms) AS total_slot_ms,
  SUM(execution_count) AS execution_count
FROM hourly_aggregated
GROUP BY
  period_type,
  consumer_category,
  hour_of_day,
  day_of_week
ORDER BY
  period_type,
  consumer_category,
  hour_of_day,
  day_of_week;

