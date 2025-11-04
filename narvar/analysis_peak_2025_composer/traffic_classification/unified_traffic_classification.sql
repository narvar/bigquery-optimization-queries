-- Unified Traffic Classification: Comprehensive classification of all BigQuery traffic by consumer category
-- Purpose: Categorizes all jobs into EXTERNAL_CRITICAL, AUTOMATED_CRITICAL, or INTERNAL with attribution
--
-- This query combines all classification logic to produce a unified view of traffic:
--   - EXTERNAL_CRITICAL: Monitor projects + Hub traffic (Looker)
--   - AUTOMATED_CRITICAL: Service accounts (excluding Metabase and Looker)
--   - INTERNAL: Metabase queries
--
-- Attribution details:
--   - EXTERNAL_CRITICAL: retailer_moniker (for monitor projects), "HUB" (for Hub traffic)
--   - AUTOMATED_CRITICAL: service_account name
--   - INTERNAL: metabase_user_id and metabase_user_email
--
-- Parameters:
--   interval_in_days: Number of days in the past to search (default: 365)
--   min_date_for_retailer_mapping: Minimum date for retailer mapping (default: 2025-01-01)
--
-- Output Schema:
--   job_id: STRING - BigQuery job ID
--   consumer_category: STRING - EXTERNAL_CRITICAL, AUTOMATED_CRITICAL, or INTERNAL
--   attribution_retailer: STRING - Retailer moniker (for monitor projects), NULL otherwise
--   attribution_service_account: STRING - Service account (for automated processes)
--   attribution_metabase_user_id: STRING - Metabase user ID (for internal users)
--   attribution_metabase_user_email: STRING - Metabase user email (for internal users)
--   project_id: STRING - Project ID where job ran
--   start_time: TIMESTAMP - Job start time
--   end_time: TIMESTAMP - Job end time
--   execution_time_ms: INT64 - Job execution time in milliseconds
--   total_slot_ms: INT64 - Total slot milliseconds consumed
--   approximate_slot_count: FLOAT64 - Approximate number of slots used
--   total_billed_bytes: INT64 - Total bytes billed
--   slot_cost_usd: FLOAT64 - Estimated slot cost in USD (based on weighted average $2.820306 per slot-hour)
--   job_type: STRING - QUERY, LOAD, EXTRACT, TABLE_COPY
--
-- Cost Warning: This query processes all audit logs and performs multiple joins.
--               For 365 days, expect to process 50-200GB+ depending on total traffic volume.
--               STRONGLY RECOMMEND using dry-run first and consider smaller date ranges for initial analysis.

DECLARE interval_in_days INT64 DEFAULT 365;
DECLARE min_date_for_retailer_mapping DATE DEFAULT '2025-01-01';
DECLARE metabase_db_project STRING DEFAULT 'narvar-data-lake';
DECLARE metabase_db_dataset STRING DEFAULT 'metabase';
DECLARE metabase_db_table STRING DEFAULT 'core_user';

-- Step 1: Monitor project mappings
WITH monitor_mappings AS (
  SELECT DISTINCT 
    retailer_moniker, 
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-prod') AS project_id
  FROM `reporting.t_return_details` 
  WHERE DATE(return_created_date) >= min_date_for_retailer_mapping
),
-- Step 2: Base audit log data
audit_log_base AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS user_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    CASE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName
      WHEN 'query_job_completed' THEN 'QUERY'
      WHEN 'load_job_completed' THEN 'LOAD'
      WHEN 'extract_job_completed' THEN 'EXTRACT'
      WHEN 'table_copy_job_completed' THEN 'TABLE_COPY'
      ELSE 'OTHER'
    END AS job_type,
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS _rnk
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
    AND protopayload_auditlog.authenticationInfo.principalEmail IS NOT NULL
    AND protopayload_auditlog.authenticationInfo.principalEmail != ""
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId IS NOT NULL
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
),
jobs_deduplicated AS (
  SELECT
    * EXCEPT(_rnk)
  FROM audit_log_base
  WHERE _rnk = 1
),
-- Step 3: Classify jobs
classified_jobs AS (
  SELECT
    jobId,
    user_email,
    project_id,
    startTime,
    endTime,
    totalBilledBytes,
    totalSlotMs,
    query_text,
    job_type,
    TIMESTAMP_DIFF(endTime, startTime, MILLISECOND) AS execution_time_ms,
    SAFE_DIVIDE(
      totalSlotMs,
      TIMESTAMP_DIFF(endTime, startTime, MILLISECOND)
    ) AS approximate_slot_count,
    -- Cost calculation: Based on slot-hours using weighted average cost per slot-hour
    -- Weighted average: (700 paygo × $3.4247 + 500 1yr × $2.7397 + 500 3yr × $2.0548) / 1700 = $2.820306/slot-hour
    ROUND(
      SAFE_DIVIDE(COALESCE(totalSlotMs, 0), 3600000.0) * 2.820306,
      2
    ) AS slot_cost_usd,
    -- Classification logic
    CASE
      -- INTERNAL: Metabase service account
      WHEN user_email = 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com' THEN 'INTERNAL'
      -- EXTERNAL_CRITICAL: Looker/Hub service account
      WHEN user_email = 'looker-prod@narvar-data-lake.iam.gserviceaccount.com' THEN 'EXTERNAL_CRITICAL'
      -- EXTERNAL_CRITICAL: Monitor projects (matching pattern)
      WHEN project_id IN (SELECT project_id FROM monitor_mappings) THEN 'EXTERNAL_CRITICAL'
      -- AUTOMATED_CRITICAL: Other service accounts
      WHEN user_email LIKE '%.iam.gserviceaccount.com' THEN 'AUTOMATED_CRITICAL'
      -- Default: treat as INTERNAL (human users, etc.)
      ELSE 'INTERNAL'
    END AS consumer_category,
    -- Extract Metabase user ID for INTERNAL category
    CASE
      WHEN user_email = 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com'
      THEN REGEXP_EXTRACT(query_text, r'(?i)--\s*(?:user|user_id|metabase[_\s]*user[_\s]*id)[:\s]*(\d+)', 1)
      ELSE NULL
    END AS metabase_user_id
  FROM jobs_deduplicated
),
-- Step 4: Add attribution details
with_attribution AS (
  SELECT
    cj.jobId AS job_id,
    cj.consumer_category,
    -- Attribution: retailer for monitor projects
    CASE
      WHEN cj.consumer_category = 'EXTERNAL_CRITICAL' 
       AND cj.project_id IN (SELECT project_id FROM monitor_mappings)
      THEN mm.retailer_moniker
      WHEN cj.consumer_category = 'EXTERNAL_CRITICAL' 
       AND cj.user_email = 'looker-prod@narvar-data-lake.iam.gserviceaccount.com'
      THEN 'HUB'
      ELSE NULL
    END AS attribution_retailer,
    -- Attribution: service account for automated processes
    CASE
      WHEN cj.consumer_category = 'AUTOMATED_CRITICAL' THEN cj.user_email
      ELSE NULL
    END AS attribution_service_account,
    -- Attribution: Metabase user info for internal users
    cj.metabase_user_id AS attribution_metabase_user_id,
    cj.project_id,
    cj.startTime AS start_time,
    cj.endTime AS end_time,
    cj.execution_time_ms,
    cj.totalSlotMs AS total_slot_ms,
    cj.approximate_slot_count,
    cj.totalBilledBytes AS total_billed_bytes,
        cj.slot_cost_usd,
    cj.job_type
  FROM classified_jobs cj
  LEFT JOIN monitor_mappings mm
    ON cj.project_id = mm.project_id
)
-- Step 5: Enrich with Metabase user email (optional - may fail if Metabase DB not accessible)
SELECT
  wa.*,
  mu.email AS attribution_metabase_user_email
FROM with_attribution wa
LEFT JOIN (
  SELECT
    CAST(id AS STRING) AS user_id,
    email
  FROM CONCAT(metabase_db_project, '.', metabase_db_dataset, '.', metabase_db_table)
) mu
ON wa.attribution_metabase_user_id = mu.user_id
ORDER BY wa.start_time DESC;

