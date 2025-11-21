-- DTPL-6903: Time Series Trend Analysis (3-week view)
-- 
-- Purpose: Identify when the latency issue started and if it's getting worse
--
-- Key questions:
-- - Is this a new problem or chronic?
-- - Is it getting worse over time?
-- - Are there specific days/times when it's worse?
--
-- Expected bytes processed: ~150-200 GB (21 days of audit logs)

DECLARE analysis_start_date TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 21 DAY);
DECLARE analysis_end_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE target_user STRING DEFAULT 'messaging@narvar-data-lake.iam.gserviceaccount.com';

WITH daily_metrics AS (
  SELECT
    DATE(creation_time) AS query_date,
    EXTRACT(DAYOFWEEK FROM creation_time) AS day_of_week,
    EXTRACT(HOUR FROM creation_time) AS hour,
    
    COUNT(*) AS query_count,
    
    -- Queue time metrics
    AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_seconds,
    APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(50)] AS p50_queue_seconds,
    APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(90)] AS p90_queue_seconds,
    APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] AS p95_queue_seconds,
    MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_seconds,
    
    -- Execution time
    AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS avg_execution_seconds,
    
    -- Resource consumption
    SUM(total_slot_ms) / 1000 AS total_slot_seconds,
    SUM(total_bytes_processed) / POW(1024, 3) AS total_gb_processed,
    
    -- Problem indicators
    COUNTIF(TIMESTAMP_DIFF(start_time, creation_time, SECOND) > 60) AS queries_delayed_over_1min,
    COUNTIF(TIMESTAMP_DIFF(start_time, creation_time, SECOND) > 300) AS queries_delayed_over_5min
    
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time BETWEEN analysis_start_date AND analysis_end_date
    AND user_email = target_user
    AND job_type = 'QUERY'
    AND state = 'DONE'
  GROUP BY query_date, day_of_week, hour
)

SELECT
  query_date,
  CASE day_of_week
    WHEN 1 THEN 'Sunday'
    WHEN 2 THEN 'Monday'
    WHEN 3 THEN 'Tuesday'
    WHEN 4 THEN 'Wednesday'
    WHEN 5 THEN 'Thursday'
    WHEN 6 THEN 'Friday'
    WHEN 7 THEN 'Saturday'
  END AS day_name,
  
  -- Aggregate to day level
  SUM(query_count) AS daily_queries,
  
  -- Queue time statistics
  ROUND(AVG(avg_queue_seconds), 1) AS avg_queue_sec,
  MAX(p50_queue_seconds) AS worst_p50_queue_sec,
  MAX(p90_queue_seconds) AS worst_p90_queue_sec,
  MAX(p95_queue_seconds) AS worst_p95_queue_sec,
  MAX(max_queue_seconds) AS worst_delay_sec,
  
  -- Execution time
  ROUND(AVG(avg_execution_seconds), 1) AS avg_exec_sec,
  
  -- Resource totals
  ROUND(SUM(total_slot_seconds), 0) AS total_slot_sec,
  ROUND(SUM(total_gb_processed), 1) AS total_gb,
  
  -- Problem severity indicators
  SUM(queries_delayed_over_1min) AS delayed_over_1min,
  SUM(queries_delayed_over_5min) AS delayed_over_5min,
  ROUND(100.0 * SUM(queries_delayed_over_1min) / SUM(query_count), 1) AS pct_delayed,
  
  -- Peak hours
  STRING_AGG(
    CAST(hour AS STRING), ', ' ORDER BY hour
  ) AS active_hours

FROM daily_metrics
GROUP BY query_date, day_of_week, day_name
ORDER BY query_date DESC;

