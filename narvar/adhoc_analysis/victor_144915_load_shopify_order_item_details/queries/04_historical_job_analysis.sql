-- Query 4: Historical Job Analysis
-- Purpose: Find past executions of merge_order_item_details and update_product_insights
-- Look for when the problem started (degradation in performance)
-- Cost: ~10-20GB (will scan INFORMATION_SCHEMA.JOBS_BY_PROJECT)

-- Find all executions of the problematic query in the last 30 days
SELECT 
    creation_time,
    job_id,
    user_email,
    statement_type,
    -- Extract date from query if present
    REGEXP_EXTRACT(query, r'tmp_order_item_details_(\d{4}-\d{2}-\d{2})') AS execution_date,
    REGEXP_EXTRACT(query, r'tmp_product_insights_updates_(\d{4}-\d{2}-\d{2})') AS update_date,
    -- Performance metrics
    total_slot_ms,
    ROUND(total_slot_ms / 3600000, 2) AS slot_hours,
    total_bytes_processed,
    ROUND(total_bytes_processed / POW(1024, 3), 2) AS gb_processed,
    total_bytes_billed,
    -- Timing
    start_time,
    end_time,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS duration_seconds,
    ROUND(TIMESTAMP_DIFF(end_time, start_time, MINUTE), 2) AS duration_minutes,
    -- Status
    state,
    error_result.reason AS error_reason,
    error_result.message AS error_message,
    -- Job type
    CASE 
        WHEN query LIKE '%CREATE OR REPLACE TABLE%tmp_order_item_details_%' THEN 'create_temp_table'
        WHEN query LIKE '%CREATE OR REPLACE TABLE%tmp_product_insights_updates_%' THEN 'create_agg_temp'
        WHEN query LIKE '%MERGE%product_insights%' THEN 'merge_product_insights'
        ELSE 'other'
    END AS job_type
FROM 
    `narvar-data-lake.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE 
    creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND user_email = 'airflow-bq-job-user-2@narvar-data-lake.iam.gserviceaccount.com'
    AND (
        query LIKE '%tmp_order_item_details_%'
        OR query LIKE '%tmp_product_insights_updates_%'
        OR (query LIKE '%product_insights%' AND query LIKE '%MERGE%')
    )
    AND job_type != 'QUERY'  -- Only actual query jobs, not metadata
ORDER BY 
    creation_time DESC
LIMIT 100;

