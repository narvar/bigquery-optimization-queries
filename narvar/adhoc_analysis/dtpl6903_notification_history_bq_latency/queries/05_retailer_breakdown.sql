-- DTPL-6903: Retailer Breakdown for Messaging Queries
-- 
-- Purpose: Identify which retailers are using Notification History feature
--          and their query patterns/performance
--
-- Key question: Is Lands' End (NT-1363 escalation) experiencing worse
--               performance than other retailers?
--
-- Expected bytes processed: ~20-30 GB

DECLARE analysis_start_date TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);
DECLARE analysis_end_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE target_user STRING DEFAULT 'messaging@narvar-data-lake.iam.gserviceaccount.com';

WITH query_details AS (
  SELECT
    job_id,
    creation_time,
    TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_seconds,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS execution_seconds,
    total_slot_ms / 1000 AS slot_seconds,
    total_bytes_processed / POW(1024, 3) AS gb_processed,
    query,
    
    -- Extract retailer moniker from query
    -- Pattern: retailer_moniker = 'jdsports-emea'
    REGEXP_EXTRACT(
      LOWER(query), 
      r"retailer_moniker\s*=\s*['\"]([a-z0-9\-_]+)['\"]"
    ) AS retailer_moniker,
    
    -- Extract order number for tracking search requests
    REGEXP_EXTRACT(
      query,
      r"upper\(order_number\)\s*=\s*['\"]([0-9]+)['\"]"
    ) AS order_number,
    
    -- Hour of day (to see usage patterns)
    EXTRACT(HOUR FROM creation_time) AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM creation_time) AS day_of_week
    
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time BETWEEN analysis_start_date AND analysis_end_date
    AND user_email = target_user
    AND job_type = 'QUERY'
    AND state = 'DONE'
)

SELECT
  COALESCE(retailer_moniker, 'UNKNOWN') AS retailer,
  
  -- Usage metrics
  COUNT(*) AS total_queries,
  COUNT(DISTINCT order_number) AS distinct_order_searches,
  COUNT(DISTINCT DATE(creation_time)) AS days_active,
  ROUND(COUNT(*) / 7, 1) AS avg_queries_per_day,
  
  -- Queue time analysis (KEY METRIC for latency issue)
  ROUND(AVG(queue_seconds), 1) AS avg_queue_sec,
  APPROX_QUANTILES(queue_seconds, 100)[OFFSET(50)] AS p50_queue_sec,
  APPROX_QUANTILES(queue_seconds, 100)[OFFSET(90)] AS p90_queue_sec,
  APPROX_QUANTILES(queue_seconds, 100)[OFFSET(95)] AS p95_queue_sec,
  MAX(queue_seconds) AS max_queue_sec,
  
  -- Execution time
  ROUND(AVG(execution_seconds), 1) AS avg_exec_sec,
  APPROX_QUANTILES(execution_seconds, 100)[OFFSET(90)] AS p90_exec_sec,
  MAX(execution_seconds) AS max_exec_sec,
  
  -- Resource consumption
  ROUND(AVG(gb_processed), 2) AS avg_gb_per_query,
  ROUND(SUM(gb_processed), 2) AS total_gb_processed,
  ROUND(AVG(slot_seconds), 1) AS avg_slot_seconds,
  
  -- Problem severity
  COUNTIF(queue_seconds > 60) AS searches_waiting_over_1min,
  COUNTIF(queue_seconds > 300) AS searches_waiting_over_5min,
  ROUND(100.0 * COUNTIF(queue_seconds > 60) / COUNT(*), 1) AS pct_delayed,
  
  -- Usage patterns
  APPROX_TOP_COUNT(hour_of_day, 3) AS peak_hours,
  APPROX_TOP_COUNT(day_of_week, 2) AS peak_days,
  
  -- Most recent search
  MAX(creation_time) AS last_search_time,
  
  -- Sample problematic queries
  ARRAY_AGG(
    STRUCT(creation_time, queue_seconds, order_number)
    ORDER BY queue_seconds DESC
    LIMIT 3
  ) AS worst_delays

FROM query_details
GROUP BY retailer
HAVING total_queries >= 5  -- Filter out one-off retailers
ORDER BY total_queries DESC;

