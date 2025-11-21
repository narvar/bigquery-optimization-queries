-- DTPL-6903: Messaging Query Pattern Classification
-- 
-- Purpose: Classify messaging queries by business use case/pattern
--          Based on table accessed and query structure
--
-- Expected patterns per NoFlakeQueryService.java:
-- - 10 tables queried per notification history search
-- - Each query filters by: retailer, order_number, date range
-- - All are SELECT queries (no writes)
--
-- Expected bytes processed: ~20-30 GB (focusing on messaging user only)

DECLARE analysis_start_date TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);
DECLARE analysis_end_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE target_user STRING DEFAULT 'messaging@narvar-data-lake.iam.gserviceaccount.com';

WITH query_analysis AS (
  SELECT
    job_id,
    creation_time,
    TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_seconds,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS execution_seconds,
    total_slot_ms / 1000 AS slot_seconds,
    total_bytes_processed / POW(1024, 3) AS gb_processed,
    statement_type,
    query,
    referenced_tables,
    
    -- Extract table being queried
    CASE
      WHEN LOWER(query) LIKE '%pubsub_rules_engine_pulsar_debug_v2%' THEN 'pulsar_debug_v2'
      WHEN LOWER(query) LIKE '%pubsub_rules_engine_pulsar_debug%' THEN 'pulsar_debug'
      WHEN LOWER(query) LIKE '%pubsub_rules_engine_kafka%' THEN 'kafka'
      WHEN LOWER(query) LIKE '%pubsub_notification_service%' THEN 'notification_service'
      WHEN LOWER(query) LIKE '%pubsub_pulsar_notification_bus%' THEN 'pulsar_notification_bus'
      WHEN LOWER(query) LIKE '%pubsub_rules_engine%' THEN 'rules_engine_other'
      ELSE 'other_table'
    END AS target_table,
    
    -- Extract metric/event type being searched
    CASE
      WHEN LOWER(query) LIKE '%notification_event_not_triggered%' THEN 'NOT_TRIGGERED'
      WHEN LOWER(query) LIKE '%notification_sent%' THEN 'SENT'
      WHEN LOWER(query) LIKE '%notification_dropped%' THEN 'DROPPED'
      WHEN LOWER(query) LIKE '%notification_failed%' THEN 'FAILED'
      ELSE 'OTHER_METRIC'
    END AS event_type,
    
    -- Check if filtering by order number (primary use case)
    REGEXP_CONTAINS(LOWER(query), r'order_number\s*=|upper\(order_number\)') AS filters_order_number,
    
    -- Check if filtering by retailer
    REGEXP_CONTAINS(LOWER(query), r'retailer_moniker\s*=') AS filters_retailer,
    
    -- Check date range filtering
    REGEXP_CONTAINS(LOWER(query), r'event_ts\s+between|timestamp\s+between') AS has_date_filter,
    
    -- Identify if part of parallel batch (queries within 1 second)
    LAG(creation_time) OVER (ORDER BY creation_time) AS prev_query_time,
    LEAD(creation_time) OVER (ORDER BY creation_time) AS next_query_time
    
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time BETWEEN analysis_start_date AND analysis_end_date
    AND user_email = target_user
    AND job_type = 'QUERY'
    AND state = 'DONE'
),

-- Identify parallel query batches (10 queries within 1-2 seconds = 1 user search)
query_batches AS (
  SELECT
    *,
    CASE
      WHEN TIMESTAMP_DIFF(creation_time, prev_query_time, SECOND) <= 2 
        OR TIMESTAMP_DIFF(next_query_time, creation_time, SECOND) <= 2
      THEN TRUE
      ELSE FALSE
    END AS is_parallel_query
  FROM query_analysis
)

SELECT
  -- Pattern classification
  target_table,
  event_type,
  
  -- Query characteristics
  filters_order_number,
  filters_retailer,
  has_date_filter,
  is_parallel_query,
  
  -- Volume metrics
  COUNT(*) AS query_count,
  COUNT(DISTINCT DATE(creation_time)) AS days_active,
  ROUND(COUNT(*) / 7, 1) AS avg_queries_per_day,
  
  -- Performance metrics
  ROUND(AVG(queue_seconds), 1) AS avg_queue_sec,
  APPROX_QUANTILES(queue_seconds, 100)[OFFSET(90)] AS p90_queue_sec,
  MAX(queue_seconds) AS max_queue_sec,
  
  ROUND(AVG(execution_seconds), 1) AS avg_exec_sec,
  MAX(execution_seconds) AS max_exec_sec,
  
  -- Resource consumption
  ROUND(AVG(gb_processed), 2) AS avg_gb_per_query,
  ROUND(AVG(slot_seconds), 1) AS avg_slot_seconds,
  ROUND(SUM(gb_processed), 2) AS total_gb_processed,
  
  -- Problem detection
  COUNTIF(queue_seconds > 60) AS queries_waiting_over_1min,
  COUNTIF(queue_seconds > 300) AS queries_waiting_over_5min,
  
  -- Sample query
  ANY_VALUE(SUBSTR(query, 1, 300)) AS sample_query

FROM query_batches
GROUP BY 
  target_table,
  event_type,
  filters_order_number,
  filters_retailer,
  has_date_filter,
  is_parallel_query
ORDER BY query_count DESC;

