-- Hub Traffic Attribution Patterns: Applies discovered patterns to attribute Hub traffic to retailers
-- Purpose: Uses patterns discovered via hub_traffic_pattern_analysis.sql to attribute Hub queries
--
-- This query applies attribution rules based on discovered patterns:
--   1. Dataset/table name patterns (retailer_*, retailer-*, etc.)
--   2. Query text patterns (retailer_moniker mentions)
--   3. Job label patterns
--   4. Retailer list validation
--
-- Usage:
--   1. Run hub_traffic_pattern_analysis.sql to discover patterns
--   2. Review patterns and validate retailer candidates
--   3. Update attribution rules below based on validated patterns
--   4. Run this query to get Hub traffic with retailer attribution
--   5. Use results to enhance unified_traffic_classification.sql
--
-- Parameters:
--   interval_in_days: Number of days to analyze (default: 90)
--
-- Output Schema:
--   job_id: STRING - BigQuery job ID
--   project_id: STRING - Project ID
--   start_time: TIMESTAMP - Job start time
--   attributed_retailer: STRING - Retailer moniker (or 'HUB_UNKNOWN' if no attribution found)
--   attribution_method: STRING - How attribution was determined (DATASET, TABLE, QUERY_TEXT, LABEL)
--   attribution_confidence: STRING - HIGH, MEDIUM, or LOW
--   execution_time_ms: INT64 - Execution time
--   total_slot_ms: INT64 - Total slot usage
--
-- Cost Warning: This query processes Hub traffic and performs pattern matching.
--               For 90 days, expect to process 5-20GB depending on Hub traffic volume.

DECLARE interval_in_days INT64 DEFAULT 90;

WITH retailer_list AS (
  SELECT DISTINCT retailer_moniker
  FROM `reporting.t_return_details` 
  WHERE DATE(return_created_date) >= DATE('2025-01-01')
),
hub_traffic AS (
  SELECT
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS projectId,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.referencedTables AS referencedTables,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.labels AS labels,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS queryText,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
      MILLISECOND
    ) AS executionTimeMs,
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
    AND protopayload_auditlog.authenticationInfo.principalEmail = 'looker-prod@narvar-data-lake.iam.gserviceaccount.com'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId IS NOT NULL
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL interval_in_days DAY)
),
jobs_deduplicated AS (
  SELECT
    * EXCEPT(_rnk)
  FROM hub_traffic
  WHERE _rnk = 1
),
-- Extract retailer candidates from various sources
retailer_candidates AS (
  SELECT
    jd.jobId,
    jd.projectId,
    jd.startTime,
    jd.endTime,
    jd.executionTimeMs,
    jd.totalSlotMs,
    jd.queryText,
    jd.referencedTables,
    jd.labels,
    -- Method 1: Extract from query text (retailer_moniker patterns)
    REGEXP_EXTRACT(LOWER(jd.queryText), r'(?:retailer[_\s]*(?:moniker|name|id))[\s:=]+[''"]?([a-z0-9_\-]+)', 1) AS candidate_from_query_text,
    -- Method 2: Extract from dataset names
    (SELECT 
      REGEXP_EXTRACT(ref.datasetId, r'(?:retailer[_-]?)([a-z0-9_]+)', 1)
     FROM UNNEST(jd.referencedTables) AS ref
     WHERE REGEXP_EXTRACT(ref.datasetId, r'(?:retailer[_-]?)([a-z0-9_]+)', 1) IS NOT NULL
     LIMIT 1
    ) AS candidate_from_dataset,
    -- Method 3: Extract from table names
    (SELECT 
      REGEXP_EXTRACT(ref.tableId, r'(?:retailer[_-]?|client[_-]?)([a-z0-9_]+)', 1)
     FROM UNNEST(jd.referencedTables) AS ref
     WHERE REGEXP_EXTRACT(ref.tableId, r'(?:retailer[_-]?|client[_-]?)([a-z0-9_]+)', 1) IS NOT NULL
     LIMIT 1
    ) AS candidate_from_table,
    -- Method 4: Extract from labels
    (SELECT label.value
     FROM UNNEST(jd.labels) AS label
     WHERE LOWER(label.key) IN ('retailer', 'retailer_moniker', 'retailer_name', 'client', 'customer')
     LIMIT 1
    ) AS candidate_from_label
  FROM jobs_deduplicated jd
),
-- Apply attribution logic (prioritize highest confidence sources)
attributed_jobs AS (
  SELECT
    rc.jobId AS job_id,
    rc.projectId AS project_id,
    rc.startTime AS start_time,
    rc.executionTimeMs,
    rc.totalSlotMs,
    -- Attribution priority: LABEL > QUERY_TEXT > DATASET > TABLE
    COALESCE(
      -- Check if label candidate is in retailer list (HIGH confidence)
      CASE 
        WHEN rc.candidate_from_label IN (SELECT retailer_moniker FROM retailer_list) 
        THEN rc.candidate_from_label 
        ELSE NULL 
      END,
      -- Check if query text candidate is in retailer list (HIGH confidence)
      CASE 
        WHEN rc.candidate_from_query_text IN (SELECT retailer_moniker FROM retailer_list) 
        THEN rc.candidate_from_query_text 
        ELSE NULL 
      END,
      -- Check if dataset candidate is in retailer list (MEDIUM confidence)
      CASE 
        WHEN rc.candidate_from_dataset IN (SELECT retailer_moniker FROM retailer_list) 
        THEN rc.candidate_from_dataset 
        ELSE NULL 
      END,
      -- Check if table candidate is in retailer list (MEDIUM confidence)
      CASE 
        WHEN rc.candidate_from_table IN (SELECT retailer_moniker FROM retailer_list) 
        THEN rc.candidate_from_table 
        ELSE NULL 
      END,
      -- Fallback to candidates even if not in list (LOW confidence, for review)
      rc.candidate_from_label,
      rc.candidate_from_query_text,
      rc.candidate_from_dataset,
      rc.candidate_from_table,
      'HUB_UNKNOWN'  -- No attribution found
    ) AS attributed_retailer,
    CASE
      WHEN rc.candidate_from_label IN (SELECT retailer_moniker FROM retailer_list) THEN 'LABEL'
      WHEN rc.candidate_from_query_text IN (SELECT retailer_moniker FROM retailer_list) THEN 'QUERY_TEXT'
      WHEN rc.candidate_from_dataset IN (SELECT retailer_moniker FROM retailer_list) THEN 'DATASET'
      WHEN rc.candidate_from_table IN (SELECT retailer_moniker FROM retailer_list) THEN 'TABLE'
      WHEN rc.candidate_from_label IS NOT NULL THEN 'LABEL'
      WHEN rc.candidate_from_query_text IS NOT NULL THEN 'QUERY_TEXT'
      WHEN rc.candidate_from_dataset IS NOT NULL THEN 'DATASET'
      WHEN rc.candidate_from_table IS NOT NULL THEN 'TABLE'
      ELSE 'NONE'
    END AS attribution_method,
    CASE
      WHEN rc.candidate_from_label IN (SELECT retailer_moniker FROM retailer_list) THEN 'HIGH'
      WHEN rc.candidate_from_query_text IN (SELECT retailer_moniker FROM retailer_list) THEN 'HIGH'
      WHEN rc.candidate_from_dataset IN (SELECT retailer_moniker FROM retailer_list) THEN 'MEDIUM'
      WHEN rc.candidate_from_table IN (SELECT retailer_moniker FROM retailer_list) THEN 'MEDIUM'
      WHEN rc.candidate_from_label IS NOT NULL OR rc.candidate_from_query_text IS NOT NULL 
           OR rc.candidate_from_dataset IS NOT NULL OR rc.candidate_from_table IS NOT NULL THEN 'LOW'
      ELSE 'NONE'
    END AS attribution_confidence
  FROM retailer_candidates rc
)
SELECT
  job_id,
  project_id,
  start_time,
  attributed_retailer,
  attribution_method,
  attribution_confidence,
  executionTimeMs AS execution_time_ms,
  totalSlotMs AS total_slot_ms
FROM attributed_jobs
ORDER BY 
  start_time DESC,
  attribution_confidence DESC;

