-- Query 5: Find Specific Failed Job
-- Purpose: Look up the specific job that failed (job_GfBO-8zBmqLqbOcAErnuRkaa0LQO)
-- And find similar jobs in the last 30 days
-- Cost: ~10-20GB

SELECT 
    creation_time,
    job_id,
    user_email,
    statement_type,
    -- Performance metrics
    total_slot_ms,
    ROUND(total_slot_ms / 3600000, 2) AS slot_hours,
    total_bytes_processed,
    ROUND(total_bytes_processed / POW(1024, 3), 2) AS gb_processed,
    -- Timing
    start_time,
    end_time,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS duration_seconds,
    ROUND(TIMESTAMP_DIFF(end_time, start_time, MINUTE), 2) AS duration_minutes,
    -- Status
    state,
    error_result.reason AS error_reason,
    LEFT(error_result.message, 200) AS error_message_preview,
    -- Query preview
    LEFT(query, 500) AS query_preview
FROM 
    `narvar-data-lake.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE 
    creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND user_email = 'airflow-bq-job-user-2@narvar-data-lake.iam.gserviceaccount.com'
    AND (
        job_id = 'job_GfBO-8zBmqLqbOcAErnuRkaa0LQO'
        OR query LIKE '%tmp_product_insights_updates_%'
        OR query LIKE '%CREATE OR REPLACE TABLE `narvar-data-lake.return_insights_base.tmp_%'
    )
ORDER BY 
    creation_time DESC
LIMIT 100;

