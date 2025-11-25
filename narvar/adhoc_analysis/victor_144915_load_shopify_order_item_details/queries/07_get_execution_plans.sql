-- Query 7: Get Execution Plans for Comparison
-- Purpose: Extract query execution statistics and plans for failed vs successful jobs
-- This will help identify the cartesian join or scan explosion
-- Cost: ~10-20GB (JOBS_BY_PROJECT scan)

WITH job_list AS (
    -- Failed Nov 19 jobs (update_product_insights)
    SELECT 'job_Wi2G9fWfLVPbs-EpgkjU7AfugSoG' AS job_id, 'Nov 19 Failed (1st attempt)' AS job_label
    UNION ALL SELECT 'job_uGCk9mLHF5NP2TNo2GtVxlBZluXj', 'Nov 19 Failed (2nd attempt)'
    UNION ALL SELECT 'job_KaXz5GqUT4AoJhwDFg8RMm1XUQPY', 'Nov 19 Failed (3rd attempt)'
    UNION ALL SELECT 'job_s6sJ9_blGH6ZgNFFS2zMO6j4mATV', 'Nov 19 Failed (4th attempt)'
    
    -- Failed Nov 20 jobs (update_product_insights)
    UNION ALL SELECT 'job_RJqlqB05dKtu4tpLG6e5Xae1ykJ0', 'Nov 20 Failed (1st attempt)'
    UNION ALL SELECT 'job_GfBO-8zBmqLqbOcAErnuRkaa0LQO', 'Nov 20 Failed (2nd attempt)'
    
    -- Successful Nov 24 job (update_product_insights)
    UNION ALL SELECT 'job_1zkKHJkoV9X2I-EreeiClsHpn2ix', 'Nov 24 Success (SCRIPT wrapper)'
    
    -- Need to find the child job IDs for the successful run
    -- These are the actual CREATE TABLE jobs within the script
    UNION ALL SELECT 'script_job_b2654d592228ccb1e1d6ebe7619a1c74_0', 'Nov 24 Success (CREATE agg temp)'
)

SELECT 
    j.job_id,
    jl.job_label,
    j.creation_time,
    j.start_time,
    j.end_time,
    TIMESTAMP_DIFF(j.end_time, j.start_time, SECOND) AS duration_seconds,
    j.total_slot_ms,
    ROUND(j.total_slot_ms / 3600000, 2) AS slot_hours,
    j.total_bytes_processed,
    ROUND(j.total_bytes_processed / POW(1024, 3), 2) AS gb_processed,
    j.total_bytes_billed,
    j.state,
    j.error_result.reason AS error_reason,
    -- Query plan statistics
    j.timeline,
    j.query_plan,
    -- For analysis
    ARRAY_LENGTH(j.timeline) AS num_timeline_entries,
    ARRAY_LENGTH(j.query_plan) AS num_query_plan_stages,
    -- Extract first few stages for preview
    ARRAY_TO_STRING(
        ARRAY(
            SELECT CONCAT(
                'Stage ', stage.name, 
                ': ', stage.status,
                ' (', CAST(stage.shuffle_output_bytes AS STRING), ' bytes shuffled)'
            )
            FROM UNNEST(j.query_plan) AS stage
            LIMIT 3
        ),
        '; '
    ) AS query_plan_preview
FROM 
    job_list jl
LEFT JOIN
    `narvar-data-lake.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT` j
    ON j.job_id = jl.job_id
WHERE
    j.creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
ORDER BY 
    j.creation_time DESC;

