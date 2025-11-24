-- Check for wait time issues since Friday (Nov 21-24)
-- 
-- Purpose: Verify if the latency issue persisted over the weekend
--
-- Expected bytes processed: ~20-30 GB

DECLARE analysis_start_date TIMESTAMP DEFAULT TIMESTAMP('2025-11-21 00:00:00', 'America/Los_Angeles');
DECLARE analysis_end_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE target_user STRING DEFAULT 'messaging@narvar-data-lake.iam.gserviceaccount.com';

WITH daily_metrics AS (
  SELECT
    DATE(creation_time, 'America/Los_Angeles') AS date_pst,
    EXTRACT(DAYOFWEEK FROM creation_time) AS day_of_week,
    CASE EXTRACT(DAYOFWEEK FROM creation_time)
      WHEN 1 THEN 'Sunday'
      WHEN 2 THEN 'Monday'
      WHEN 3 THEN 'Tuesday'
      WHEN 4 THEN 'Wednesday'
      WHEN 5 THEN 'Thursday'
      WHEN 6 THEN 'Friday'
      WHEN 7 THEN 'Saturday'
    END AS day_name,
    
    COUNT(*) AS total_queries,
    
    -- Queue time analysis
    AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
    APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(50)] AS p50_queue_sec,
    APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(90)] AS p90_queue_sec,
    APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] AS p95_queue_sec,
    MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
    
    -- Execution time
    AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS avg_exec_sec,
    MAX(TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS max_exec_sec,
    
    -- Problem detection
    COUNTIF(TIMESTAMP_DIFF(start_time, creation_time, SECOND) > 60) AS delayed_over_1min,
    COUNTIF(TIMESTAMP_DIFF(start_time, creation_time, SECOND) > 300) AS delayed_over_5min,
    COUNTIF(TIMESTAMP_DIFF(start_time, creation_time, SECOND) > 480) AS delayed_over_8min,
    
    -- Percentage delayed
    ROUND(100.0 * COUNTIF(TIMESTAMP_DIFF(start_time, creation_time, SECOND) > 60) / COUNT(*), 2) AS pct_delayed,
    
    -- Resource metrics
    SUM(total_slot_ms) / 1000 AS total_slot_sec,
    SUM(total_bytes_processed) / POW(1024, 3) AS total_gb
    
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time BETWEEN analysis_start_date AND analysis_end_date
    AND user_email = target_user
    AND job_type = 'QUERY'
    AND state = 'DONE'
  GROUP BY date_pst, day_of_week, day_name
)

SELECT
  date_pst,
  day_name,
  total_queries,
  
  -- Queue time metrics
  ROUND(avg_queue_sec, 1) AS avg_queue_sec,
  p50_queue_sec,
  p90_queue_sec,
  p95_queue_sec,
  max_queue_sec,
  
  -- Execution time
  ROUND(avg_exec_sec, 1) AS avg_exec_sec,
  max_exec_sec,
  
  -- Problem severity
  delayed_over_1min,
  delayed_over_5min,
  delayed_over_8min,
  pct_delayed,
  
  -- Resource consumption
  ROUND(total_slot_sec, 0) AS total_slot_sec,
  ROUND(total_gb, 1) AS total_gb,
  
  -- Status
  CASE
    WHEN max_queue_sec > 300 THEN '🔴 CRITICAL'
    WHEN max_queue_sec > 60 THEN '🟡 WARNING'
    WHEN max_queue_sec > 30 THEN '🟢 WATCH'
    ELSE '✅ HEALTHY'
  END AS status

FROM daily_metrics
ORDER BY date_pst DESC;

