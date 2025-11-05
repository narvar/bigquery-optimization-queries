<<<<<<< Current (Your changes)
=======
-- ============================================================================
-- METABASE USER MAPPING
-- ============================================================================
-- Purpose: Extract Metabase user IDs from query comments and map to user emails
--          using the Metabase database linked resource
--
-- Metabase queries typically include comments like:
-- -- Metabase:: userID: 123
-- This query parses those comments and joins with Metabase user table
--
-- Cost estimate: ~2-10GB processed (depends on date range)
-- ============================================================================

-- Configuration parameters
DECLARE start_date DATE DEFAULT '2024-10-01';
DECLARE end_date DATE DEFAULT '2024-10-31';
DECLARE metabase_service_account STRING DEFAULT 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com';

-- ============================================================================
-- MAIN QUERY: Metabase User ID Extraction and Mapping
-- ============================================================================

WITH
-- Extract Metabase queries with user ID parsing
metabase_queries AS (
  SELECT
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime AS start_time,
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    
    -- Extract Metabase user ID from query comments
    -- Pattern 1: -- Metabase:: userID: 123
    REGEXP_EXTRACT(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query,
      r'--\s*Metabase::\s*userID:\s*(\d+)'
    ) AS metabase_user_id_pattern1,
    
    -- Pattern 2: /* Metabase userID: 123 */
    REGEXP_EXTRACT(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query,
      r'/\*\s*Metabase\s*userID:\s*(\d+)\s*\*/'
    ) AS metabase_user_id_pattern2,
    
    -- Pattern 3: -- metabase_user_id=123
    REGEXP_EXTRACT(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query,
      r'--\s*metabase_user_id\s*=\s*(\d+)'
    ) AS metabase_user_id_pattern3,
    
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS row_num
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN start_date AND end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
    AND protopayload_auditlog.authenticationInfo.principalEmail = metabase_service_account
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
),

-- Deduplicate and consolidate user ID extraction patterns
metabase_deduplicated AS (
  SELECT
    job_id,
    start_time,
    principal_email,
    query_text,
    
    -- Use first non-null pattern
    COALESCE(
      metabase_user_id_pattern1,
      metabase_user_id_pattern2,
      metabase_user_id_pattern3
    ) AS metabase_user_id,
    
    -- Track which pattern matched
    CASE
      WHEN metabase_user_id_pattern1 IS NOT NULL THEN 'Pattern 1: -- Metabase:: userID: N'
      WHEN metabase_user_id_pattern2 IS NOT NULL THEN 'Pattern 2: /* Metabase userID: N */'
      WHEN metabase_user_id_pattern3 IS NOT NULL THEN 'Pattern 3: -- metabase_user_id=N'
      ELSE 'No pattern matched'
    END AS pattern_matched
    
  FROM metabase_queries
  WHERE row_num = 1
)

-- Output: Metabase queries with extracted user IDs
SELECT
  job_id,
  start_time,
  principal_email,
  metabase_user_id,
  pattern_matched,
  
  -- Query text sample (first 500 chars)
  SUBSTR(query_text, 1, 500) AS query_text_sample,
  
  -- TODO: Join with Metabase database to get user email
  -- Example join (uncomment and adjust once Metabase DB connection is configured):
  -- LEFT JOIN `metabase_db.users` mb ON CAST(md.metabase_user_id AS INT64) = mb.id
  
  CAST(NULL AS STRING) AS metabase_user_email, -- Placeholder for user email from Metabase DB
  CAST(NULL AS STRING) AS metabase_user_name   -- Placeholder for user name from Metabase DB

FROM metabase_deduplicated
ORDER BY start_time DESC;

-- ============================================================================
-- PATTERN ANALYSIS: Check comment format prevalence
-- ============================================================================
-- Uncomment to analyze which comment patterns are being used
/*
WITH
metabase_queries AS (
  SELECT
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    REGEXP_EXTRACT(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query,
      r'--\s*Metabase::\s*userID:\s*(\d+)'
    ) AS pattern1,
    REGEXP_EXTRACT(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query,
      r'/\*\s*Metabase\s*userID:\s*(\d+)\s*\*/'
    ) AS pattern2,
    REGEXP_EXTRACT(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query,
      r'--\s*metabase_user_id\s*=\s*(\d+)'
    ) AS pattern3,
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS row_num
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN start_date AND end_date
    AND protopayload_auditlog.authenticationInfo.principalEmail = metabase_service_account
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query IS NOT NULL
)

SELECT
  COUNTIF(pattern1 IS NOT NULL) AS pattern1_matches,
  COUNTIF(pattern2 IS NOT NULL) AS pattern2_matches,
  COUNTIF(pattern3 IS NOT NULL) AS pattern3_matches,
  COUNTIF(pattern1 IS NULL AND pattern2 IS NULL AND pattern3 IS NULL) AS no_pattern_matches,
  COUNT(*) AS total_queries,
  ROUND(COUNTIF(pattern1 IS NOT NULL OR pattern2 IS NOT NULL OR pattern3 IS NOT NULL) / COUNT(*) * 100, 2) AS pct_with_user_id
FROM metabase_queries
WHERE row_num = 1;
*/

-- ============================================================================
-- USER ID DISTRIBUTION
-- ============================================================================
-- Uncomment to see distribution of Metabase users
/*
WITH
metabase_queries AS (
  SELECT
    COALESCE(
      REGEXP_EXTRACT(
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query,
        r'--\s*Metabase::\s*userID:\s*(\d+)'
      ),
      REGEXP_EXTRACT(
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query,
        r'/\*\s*Metabase\s*userID:\s*(\d+)\s*\*/'
      ),
      REGEXP_EXTRACT(
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query,
        r'--\s*metabase_user_id\s*=\s*(\d+)'
      )
    ) AS metabase_user_id,
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS row_num
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN start_date AND end_date
    AND protopayload_auditlog.authenticationInfo.principalEmail = metabase_service_account
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
)

SELECT
  metabase_user_id,
  COUNT(*) AS query_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 2) AS pct_of_total
FROM metabase_queries
WHERE row_num = 1 AND metabase_user_id IS NOT NULL
GROUP BY metabase_user_id
ORDER BY query_count DESC
LIMIT 50;
*/

-- ============================================================================
-- NOTES FOR USER
-- ============================================================================
-- 1. Run this query first to understand Metabase query comment patterns
-- 2. Update REGEXP patterns if your Metabase instance uses different format
-- 3. Configure Metabase DB connection and uncomment JOIN to get user emails
-- 4. Sample Metabase DB schema (typical):
--    - Table: metabase.users
--    - Columns: id, email, first_name, last_name, is_active
-- 5. If Metabase DB is not accessible, use metabase_user_id as identifier
>>>>>>> Incoming (Background Agent changes)
