-- DTPL-6903: Messaging Notification History - Queue Time Analysis
-- 
-- Purpose: Analyze queue wait times for messaging service account queries
-- Focus: Last 7 days to identify when delays started occurring
--
-- Key Metrics:
-- - Queue time = start_time - creation_time (time spent waiting for slots)
-- - Execution time = end_time - start_time (actual query runtime)
-- - Total time = end_time - creation_time
--
-- Expected bytes processed: ~50-100 GB (7 days of audit logs)

DECLARE analysis_start_date TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);
DECLARE analysis_end_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE target_user STRING DEFAULT 'messaging@narvar-data-lake.iam.gserviceaccount.com';

WITH job_timing AS (
  SELECT
    job_id,
    user_email,
    project_id,
    reservation_id,
    creation_time,
    start_time,
    end_time,
    state,
    error_result,
    
    -- Calculate timing metrics
    TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_time_seconds,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS execution_time_seconds,
    TIMESTAMP_DIFF(end_time, creation_time, SECOND) AS total_time_seconds,
    
    -- Resource metrics
    total_slot_ms,
    total_bytes_processed,
    total_bytes_billed,
    
    -- Query metadata
    statement_type,
    referenced_tables,
    SUBSTR(query, 1, 200) AS query_sample
    
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time BETWEEN analysis_start_date AND analysis_end_date
    AND user_email = target_user
    AND job_type = 'QUERY'
    AND state = 'DONE'
)

SELECT
  -- Time bucketing
  DATE(creation_time) AS query_date,
  EXTRACT(HOUR FROM creation_time) AS query_hour,
  
  -- Volume metrics
  COUNT(*) AS query_count,
  
  -- Queue time analysis (THE KEY METRIC)
  MIN(queue_time_seconds) AS min_queue_seconds,
  APPROX_QUANTILES(queue_time_seconds, 100)[OFFSET(50)] AS p50_queue_seconds,
  APPROX_QUANTILES(queue_time_seconds, 100)[OFFSET(90)] AS p90_queue_seconds,
  APPROX_QUANTILES(queue_time_seconds, 100)[OFFSET(95)] AS p95_queue_seconds,
  MAX(queue_time_seconds) AS max_queue_seconds,
  AVG(queue_time_seconds) AS avg_queue_seconds,
  
  -- Execution time analysis
  APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)] AS p50_execution_seconds,
  APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(90)] AS p90_execution_seconds,
  MAX(execution_time_seconds) AS max_execution_seconds,
  
  -- Total time
  APPROX_QUANTILES(total_time_seconds, 100)[OFFSET(50)] AS p50_total_seconds,
  APPROX_QUANTILES(total_time_seconds, 100)[OFFSET(90)] AS p90_total_seconds,
  MAX(total_time_seconds) AS max_total_seconds,
  
  -- Resource consumption
  SUM(total_slot_ms) / 1000 AS total_slot_seconds,
  SUM(total_bytes_processed) / POW(1024, 3) AS total_gb_processed,
  
  -- Problem detection: queries with >60 second wait
  COUNTIF(queue_time_seconds > 60) AS queries_waiting_over_1min,
  COUNTIF(queue_time_seconds > 300) AS queries_waiting_over_5min,
  COUNTIF(queue_time_seconds > 480) AS queries_waiting_over_8min

FROM job_timing
GROUP BY query_date, query_hour
ORDER BY query_date DESC, query_hour DESC;

