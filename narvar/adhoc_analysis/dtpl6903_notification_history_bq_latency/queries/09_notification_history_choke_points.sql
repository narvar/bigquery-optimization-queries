-- DTPL-6903: Identify 10-minute periods when Notification History queries are most delayed
-- 
-- Purpose: Find the exact time windows when notification history queries are blocked
--          and show what concurrent workload is causing the congestion
--
-- Pattern to match: Queries to messaging.pubsub_rules_engine_pulsar_debug with
--                   retailer_moniker, order_number, event_ts filters (notification history lookups)
--
-- Expected bytes processed: ~50-100 GB (7 days)

DECLARE analysis_start_date TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);
DECLARE analysis_end_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE target_user STRING DEFAULT 'messaging@narvar-data-lake.iam.gserviceaccount.com';
DECLARE target_reservation STRING DEFAULT 'bq-narvar-admin:US.default';

-- Step 1: Identify notification history queries (matching the pattern)
WITH notification_queries AS (
  SELECT
    job_id,
    creation_time,
    start_time,
    end_time,
    TIMESTAMP_TRUNC(creation_time, MINUTE, 'America/Los_Angeles') AS minute_bucket,
    TIMESTAMP_TRUNC(creation_time, HOUR, 'America/Los_Angeles') AS hour_bucket,
    DATE(creation_time, 'America/Los_Angeles') AS date_bucket,
    
    -- Time components for 10-minute bucketing
    EXTRACT(HOUR FROM creation_time AT TIME ZONE 'America/Los_Angeles') AS hour_pst,
    DIV(EXTRACT(MINUTE FROM creation_time AT TIME ZONE 'America/Los_Angeles'), 10) AS ten_min_bucket,
    
    -- Timing metrics
    TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_seconds,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS execution_seconds,
    
    -- Resource metrics
    total_slot_ms / 1000 AS slot_seconds,
    total_bytes_processed / POW(1024, 3) AS gb_processed,
    
    query
    
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time BETWEEN analysis_start_date AND analysis_end_date
    AND user_email = target_user
    AND job_type = 'QUERY'
    AND state = 'DONE'
    -- Pattern matching for notification history queries
    AND (
      LOWER(query) LIKE '%pubsub_rules_engine_pulsar_debug%'
      OR LOWER(query) LIKE '%pubsub_rules_engine_pulsar_debug_v2%'
      OR LOWER(query) LIKE '%pubsub_rules_engine_kafka%'
    )
    AND LOWER(query) LIKE '%retailer_moniker%'
    AND (
      LOWER(query) LIKE '%order_number%'
      OR LOWER(query) LIKE '%tracking_number%'
    )
),

-- Step 2: Aggregate notification queries by 10-minute buckets
notification_metrics AS (
  SELECT
    date_bucket,
    hour_pst,
    ten_min_bucket,
    TIMESTAMP_TRUNC(minute_bucket, MINUTE) AS ten_min_window_start,
    
    COUNT(*) AS notification_queries,
    
    -- Queue time metrics for notification queries
    AVG(queue_seconds) AS avg_queue_sec,
    APPROX_QUANTILES(queue_seconds, 100)[OFFSET(50)] AS p50_queue_sec,
    APPROX_QUANTILES(queue_seconds, 100)[OFFSET(90)] AS p90_queue_sec,
    MAX(queue_seconds) AS max_queue_sec,
    
    -- Execution time
    AVG(execution_seconds) AS avg_exec_sec,
    
    -- Resource consumption
    SUM(gb_processed) AS total_gb,
    
    -- Problem detection
    COUNTIF(queue_seconds > 60) AS queries_delayed_over_1min,
    COUNTIF(queue_seconds > 300) AS queries_delayed_over_5min
    
  FROM notification_queries
  GROUP BY date_bucket, hour_pst, ten_min_bucket, ten_min_window_start
),

-- Step 3: Get ALL reservation activity during the same 10-minute windows
concurrent_workload AS (
  SELECT
    TIMESTAMP_TRUNC(creation_time, MINUTE, 'America/Los_Angeles') AS minute_bucket,
    
    -- Count queries by state at time of creation
    COUNT(*) AS total_queries_submitted,
    
    -- Estimate concurrent running/pending queries
    -- (queries that overlap with this minute)
    COUNT(DISTINCT 
      CASE 
        WHEN state IN ('RUNNING', 'PENDING') 
        THEN job_id 
      END
    ) AS concurrent_active_queries,
    
    -- Slot consumption
    SUM(total_slot_ms) / 60000 AS slot_minutes_consumed,
    
    -- Breakdown by user/service
    COUNT(DISTINCT user_email) AS distinct_users,
    
    -- Service breakdown
    COUNTIF(user_email LIKE '%airflow%') AS airflow_queries,
    COUNTIF(user_email LIKE '%metabase%') AS metabase_queries,
    COUNTIF(user_email LIKE '%messaging%') AS messaging_queries,
    COUNTIF(user_email LIKE '%looker%') AS looker_queries,
    COUNTIF(user_email LIKE '%n8n%') AS n8n_queries,
    
    -- Query types
    COUNTIF(statement_type = 'SELECT') AS select_count,
    COUNTIF(statement_type IN ('MERGE', 'INSERT', 'UPDATE')) AS write_count
    
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time BETWEEN analysis_start_date AND analysis_end_date
    AND reservation_id = target_reservation
    AND job_type = 'QUERY'
  GROUP BY minute_bucket
)

-- Step 4: Join notification metrics with concurrent workload
SELECT
  nm.date_bucket,
  nm.hour_pst,
  nm.ten_min_bucket,
  CONCAT(
    CAST(nm.hour_pst AS STRING), 
    ':', 
    LPAD(CAST(nm.ten_min_bucket * 10 AS STRING), 2, '0')
  ) AS time_window_pst,
  
  -- Notification query performance
  nm.notification_queries,
  ROUND(nm.avg_queue_sec, 1) AS avg_queue_sec,
  nm.p50_queue_sec,
  nm.p90_queue_sec,
  nm.max_queue_sec,
  ROUND(nm.avg_exec_sec, 1) AS avg_exec_sec,
  
  nm.queries_delayed_over_1min,
  nm.queries_delayed_over_5min,
  
  -- Concurrent workload metrics (aggregated across 10 minutes)
  CAST(AVG(cw.total_queries_submitted) AS INT64) AS avg_queries_per_min,
  CAST(MAX(cw.total_queries_submitted) AS INT64) AS max_queries_per_min,
  CAST(AVG(cw.concurrent_active_queries) AS INT64) AS avg_concurrent_active,
  ROUND(AVG(cw.slot_minutes_consumed), 0) AS avg_slot_minutes_per_min,
  ROUND(MAX(cw.slot_minutes_consumed), 0) AS max_slot_minutes_per_min,
  ROUND(AVG(cw.distinct_users), 0) AS avg_distinct_users,
  
  -- Service breakdown during this 10-minute window
  CAST(SUM(cw.airflow_queries) AS INT64) AS airflow_queries_10min,
  CAST(SUM(cw.metabase_queries) AS INT64) AS metabase_queries_10min,
  CAST(SUM(cw.looker_queries) AS INT64) AS looker_queries_10min,
  CAST(SUM(cw.n8n_queries) AS INT64) AS n8n_queries_10min,
  
  -- Identify primary competing service
  CASE
    WHEN SUM(cw.airflow_queries) > SUM(cw.metabase_queries) 
      AND SUM(cw.airflow_queries) > SUM(cw.looker_queries)
      AND SUM(cw.airflow_queries) > SUM(cw.n8n_queries)
    THEN 'Airflow/ETL'
    WHEN SUM(cw.metabase_queries) > SUM(cw.airflow_queries)
      AND SUM(cw.metabase_queries) > SUM(cw.looker_queries)
      AND SUM(cw.metabase_queries) > SUM(cw.n8n_queries)
    THEN 'Metabase'
    WHEN SUM(cw.n8n_queries) > SUM(cw.airflow_queries)
      AND SUM(cw.n8n_queries) > SUM(cw.metabase_queries)
    THEN 'n8n'
    WHEN SUM(cw.looker_queries) > 0 THEN 'Looker'
    ELSE 'Mixed'
  END AS primary_competing_service,
  
  -- Total workload mix
  CAST(AVG(cw.select_count) AS INT64) AS avg_selects_per_min,
  CAST(AVG(cw.write_count) AS INT64) AS avg_writes_per_min

FROM notification_metrics nm
LEFT JOIN concurrent_workload cw
  ON TIMESTAMP_TRUNC(cw.minute_bucket, MINUTE) >= nm.ten_min_window_start
  AND TIMESTAMP_TRUNC(cw.minute_bucket, MINUTE) < TIMESTAMP_ADD(nm.ten_min_window_start, INTERVAL 10 MINUTE)
GROUP BY 
  nm.date_bucket,
  nm.hour_pst,
  nm.ten_min_bucket,
  time_window_pst,
  nm.notification_queries,
  nm.avg_queue_sec,
  nm.p50_queue_sec,
  nm.p90_queue_sec,
  nm.max_queue_sec,
  nm.avg_exec_sec,
  nm.queries_delayed_over_1min,
  nm.queries_delayed_over_5min
HAVING notification_queries > 0
ORDER BY nm.max_queue_sec DESC, nm.p90_queue_sec DESC
LIMIT 100;

