-- Hub Traffic Pattern Analysis: Analyzes Hub traffic to identify retailer attribution patterns
-- Purpose: Discovers patterns in Hub traffic that can be used to attribute queries to retailers
--
-- This query analyzes:
--   1. Referenced tables/datasets for retailer-specific naming patterns
--   2. Query text for retailer moniker mentions
--   3. Query labels for retailer attribution
--   4. Dataset naming conventions (retailer_*, retailer-*, etc.)
--   5. Table naming patterns that indicate retailer
--
-- Parameters:
--   interval_in_days: Number of days to analyze (default: 90 for pattern discovery)
--   min_job_count: Minimum number of jobs per pattern to consider (default: 5)
--
-- Output Schema:
--   pattern_type: STRING - Type of pattern (DATASET_NAME, TABLE_NAME, QUERY_TEXT, LABEL, etc.)
--   pattern_value: STRING - The actual pattern value found
--   retailer_candidate: STRING - Potential retailer name extracted from pattern
--   job_count: INT64 - Number of jobs matching this pattern
--   total_slot_ms: INT64 - Total slot usage for this pattern
--   sample_job_ids: ARRAY<STRING> - Sample job IDs for review
--   confidence: STRING - HIGH, MEDIUM, LOW confidence in attribution
--   notes: STRING - Additional context about the pattern
--
-- Cost Warning: This query processes Hub traffic and extracts patterns from query text and metadata.
--               For 90 days, expect to process 5-20GB depending on Hub traffic volume.
--               Consider starting with 30 days for initial pattern discovery.

DECLARE interval_in_days INT64 DEFAULT 90;
DECLARE min_job_count INT64 DEFAULT 5;

-- Get retailer list for pattern matching
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
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.referencedTables AS referencedTables,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.labels AS labels,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS queryText,
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
-- Pattern 1: Analyze referenced tables/datasets
referenced_tables_expanded AS (
  SELECT
    jd.jobId,
    jd.projectId,
    jd.startTime,
    jd.totalSlotMs,
    jd.queryText,
    ref.projectId AS ref_project_id,
    ref.datasetId AS ref_dataset_id,
    ref.tableId AS ref_table_id,
    CONCAT(ref.projectId, '.', ref.datasetId, '.', ref.tableId) AS full_table_path
  FROM jobs_deduplicated jd
  CROSS JOIN UNNEST(jd.referencedTables) AS ref
),
dataset_patterns AS (
  SELECT
    'DATASET_NAME' AS pattern_type,
    ref_dataset_id AS pattern_value,
    -- Try to extract retailer name from dataset (common patterns: retailer_*, retailer-*, etc.)
    REGEXP_EXTRACT(ref_dataset_id, r'(?:retailer[_-]?)([a-z0-9_]+)', 1) AS retailer_candidate,
    COUNT(DISTINCT rt.jobId) AS job_count,
    SUM(rt.totalSlotMs) AS total_slot_ms,
    ARRAY_AGG(DISTINCT rt.jobId LIMIT 10) AS sample_job_ids
  FROM referenced_tables_expanded rt
  WHERE ref_dataset_id IS NOT NULL
    AND (
      LOWER(ref_dataset_id) LIKE '%retailer%'
      OR LOWER(ref_dataset_id) LIKE '%client%'
      OR LOWER(ref_dataset_id) LIKE '%customer%'
      OR REGEXP_CONTAINS(LOWER(ref_dataset_id), r'^(retailer|client|customer)[_-]?[a-z0-9_]+$')
    )
  GROUP BY ref_dataset_id
  HAVING job_count >= min_job_count
),
table_patterns AS (
  SELECT
    'TABLE_NAME' AS pattern_type,
    ref_table_id AS pattern_value,
    REGEXP_EXTRACT(ref_table_id, r'(?:retailer[_-]?|client[_-]?|customer[_-]?)([a-z0-9_]+)', 1) AS retailer_candidate,
    COUNT(DISTINCT rt.jobId) AS job_count,
    SUM(rt.totalSlotMs) AS total_slot_ms,
    ARRAY_AGG(DISTINCT rt.jobId LIMIT 10) AS sample_job_ids
  FROM referenced_tables_expanded rt
  WHERE ref_table_id IS NOT NULL
    AND (
      LOWER(ref_table_id) LIKE '%retailer%'
      OR LOWER(ref_table_id) LIKE '%client%'
      OR LOWER(ref_table_id) LIKE '%customer%'
    )
  GROUP BY ref_table_id
  HAVING job_count >= min_job_count
),
-- Pattern 2: Query text analysis for retailer mentions
query_text_patterns AS (
  SELECT
    'QUERY_TEXT' AS pattern_type,
    REGEXP_EXTRACT(jd.queryText, r'(?:retailer[_\s]*moniker|retailer_moniker|retailer_name)[\s:=]+[''"]?([a-z0-9_\-]+)', 1) AS pattern_value,
    REGEXP_EXTRACT(jd.queryText, r'(?:retailer[_\s]*moniker|retailer_moniker|retailer_name)[\s:=]+[''"]?([a-z0-9_\-]+)', 1) AS retailer_candidate,
    COUNT(DISTINCT jd.jobId) AS job_count,
    SUM(jd.totalSlotMs) AS total_slot_ms,
    ARRAY_AGG(DISTINCT jd.jobId LIMIT 10) AS sample_job_ids
  FROM jobs_deduplicated jd
  WHERE jd.queryText IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(jd.queryText), r'retailer[_\s]*(?:moniker|name)')
  GROUP BY pattern_value
  HAVING job_count >= min_job_count
    AND pattern_value IS NOT NULL
),
-- Pattern 3: Label-based attribution
label_patterns AS (
  SELECT
    'LABEL' AS pattern_type,
    CONCAT(label.key, '=', label.value) AS pattern_value,
    label.value AS retailer_candidate,
    COUNT(DISTINCT jd.jobId) AS job_count,
    SUM(jd.totalSlotMs) AS total_slot_ms,
    ARRAY_AGG(DISTINCT jd.jobId LIMIT 10) AS sample_job_ids
  FROM jobs_deduplicated jd
  CROSS JOIN UNNEST(jd.labels) AS label
  WHERE jd.labels IS NOT NULL
    AND (
      LOWER(label.key) LIKE '%retailer%'
      OR LOWER(label.key) LIKE '%client%'
      OR LOWER(label.key) LIKE '%customer%'
      OR LOWER(label.key) = 'retailer_moniker'
    )
  GROUP BY label.key, label.value
  HAVING job_count >= min_job_count
),
-- Combine all patterns
all_patterns AS (
  SELECT
    pattern_type,
    pattern_value,
    retailer_candidate,
    job_count,
    total_slot_ms,
    sample_job_ids,
    CASE
      WHEN retailer_candidate IN (SELECT retailer_moniker FROM retailer_list) THEN 'HIGH'
      WHEN retailer_candidate IS NOT NULL AND LENGTH(retailer_candidate) > 2 THEN 'MEDIUM'
      ELSE 'LOW'
    END AS confidence,
    CASE
      WHEN pattern_type = 'DATASET_NAME' THEN CONCAT('Dataset name pattern: ', pattern_value)
      WHEN pattern_type = 'TABLE_NAME' THEN CONCAT('Table name pattern: ', pattern_value)
      WHEN pattern_type = 'QUERY_TEXT' THEN 'Retailer moniker found in query text'
      WHEN pattern_type = 'LABEL' THEN CONCAT('Job label: ', pattern_value)
      ELSE 'Unknown pattern type'
    END AS notes
  FROM dataset_patterns
  
  UNION ALL
  
  SELECT
    pattern_type,
    pattern_value,
    retailer_candidate,
    job_count,
    total_slot_ms,
    sample_job_ids,
    CASE
      WHEN retailer_candidate IN (SELECT retailer_moniker FROM retailer_list) THEN 'HIGH'
      WHEN retailer_candidate IS NOT NULL AND LENGTH(retailer_candidate) > 2 THEN 'MEDIUM'
      ELSE 'LOW'
    END AS confidence,
    CASE
      WHEN pattern_type = 'DATASET_NAME' THEN CONCAT('Dataset name pattern: ', pattern_value)
      WHEN pattern_type = 'TABLE_NAME' THEN CONCAT('Table name pattern: ', pattern_value)
      WHEN pattern_type = 'QUERY_TEXT' THEN 'Retailer moniker found in query text'
      WHEN pattern_type = 'LABEL' THEN CONCAT('Job label: ', pattern_value)
      ELSE 'Unknown pattern type'
    END AS notes
  FROM table_patterns
  
  UNION ALL
  
  SELECT
    pattern_type,
    pattern_value,
    retailer_candidate,
    job_count,
    total_slot_ms,
    sample_job_ids,
    CASE
      WHEN retailer_candidate IN (SELECT retailer_moniker FROM retailer_list) THEN 'HIGH'
      WHEN retailer_candidate IS NOT NULL AND LENGTH(retailer_candidate) > 2 THEN 'MEDIUM'
      ELSE 'LOW'
    END AS confidence,
    CASE
      WHEN pattern_type = 'DATASET_NAME' THEN CONCAT('Dataset name pattern: ', pattern_value)
      WHEN pattern_type = 'TABLE_NAME' THEN CONCAT('Table name pattern: ', pattern_value)
      WHEN pattern_type = 'QUERY_TEXT' THEN 'Retailer moniker found in query text'
      WHEN pattern_type = 'LABEL' THEN CONCAT('Job label: ', pattern_value)
      ELSE 'Unknown pattern type'
    END AS notes
  FROM query_text_patterns
  
  UNION ALL
  
  SELECT
    pattern_type,
    pattern_value,
    retailer_candidate,
    job_count,
    total_slot_ms,
    sample_job_ids,
    CASE
      WHEN retailer_candidate IN (SELECT retailer_moniker FROM retailer_list) THEN 'HIGH'
      WHEN retailer_candidate IS NOT NULL AND LENGTH(retailer_candidate) > 2 THEN 'MEDIUM'
      ELSE 'LOW'
    END AS confidence,
    CASE
      WHEN pattern_type = 'DATASET_NAME' THEN CONCAT('Dataset name pattern: ', pattern_value)
      WHEN pattern_type = 'TABLE_NAME' THEN CONCAT('Table name pattern: ', pattern_value)
      WHEN pattern_type = 'QUERY_TEXT' THEN 'Retailer moniker found in query text'
      WHEN pattern_type = 'LABEL' THEN CONCAT('Job label: ', pattern_value)
      ELSE 'Unknown pattern type'
    END AS notes
  FROM label_patterns
)
SELECT
  pattern_type,
  pattern_value,
  retailer_candidate,
  job_count,
  total_slot_ms,
  sample_job_ids,
  confidence,
  notes
FROM all_patterns
ORDER BY
  confidence DESC,  -- HIGH first
  job_count DESC;   -- Then by job count

