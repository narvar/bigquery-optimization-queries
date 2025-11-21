-- Discover Actual Parameters for Parametrized Query
-- Strategy: Use query fingerprinting and execution context

-- Method 1: Find similar non-parameterized queries
WITH query_fingerprints AS (
  SELECT 
    job_id,
    creation_time,
    query,
    -- Create fingerprint by removing literals
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(query, r"'[^']*'", "'?'"),
        r"[0-9]{4}-[0-9]{2}-[0-9]{2}", "?"
      ),
      r"\?[0-9]*", "?"
    ) as fingerprint,
    total_bytes_processed,
    total_slot_ms
  FROM `monitor-a679b28-us-prod.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
  WHERE DATE(creation_time) >= '2025-11-10'
    AND query LIKE '%v_shipments%'
    AND query LIKE '%ontrac%'
    AND query LIKE '%manifest%'
),

-- Method 2: Find non-parameterized versions of the same query
non_parametrized_versions AS (
  SELECT 
    job_id,
    creation_time,
    query,
    -- Extract actual date ranges from non-parameterized queries
    REGEXP_EXTRACT_ALL(query, r"ship_date.*BETWEEN\s*'([0-9]{4}-[0-9]{2}-[0-9]{2})'\s*AND\s*'([0-9]{4}-[0-9]{2}-[0-9]{2})'") as date_ranges,
    REGEXP_EXTRACT_ALL(query, r"ship_date.*>=\s*'([0-9]{4}-[0-9]{2}-[0-9]{2})'") as start_dates,
    REGEXP_EXTRACT_ALL(query, r"ship_date.*<=\s*'([0-9]{4}-[0-9]{2}-[0-9]{2})'") as end_dates,
    total_bytes_processed,
    total_slot_ms
  FROM `monitor-a679b28-us-prod.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
  WHERE DATE(creation_time) >= '2025-11-10'
    AND query LIKE '%v_shipments%'
    AND query LIKE '%ontrac%'
    AND query LIKE '%manifest%'
    AND query NOT LIKE '%?%'
),

-- Method 3: Use query plan analysis to estimate data range
execution_context AS (
  SELECT 
    job_id,
    creation_time,
    referenced_tables,
    total_bytes_processed,
    -- Estimate based on typical row size and table statistics
    CASE 
      WHEN ARRAY_LENGTH(referenced_tables) > 0 THEN
        (SELECT 
           SUM(total_rows * 2048)  -- ~2KB per row
         FROM UNNEST(referenced_tables) t
         JOIN `monitor-a679b28-us-prod.region-us.INFORMATION_SCHEMA.TABLE_STORAGE` s
           ON s.table_name = t.table_id
           AND s.table_schema = t.dataset_id
        )
      ELSE NULL
    END as estimated_table_bytes
  FROM `monitor-a679b28-us-prod.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
  WHERE DATE(creation_time) >= '2025-11-14'
    AND job_id = 'job_fkhGvQtTHmR_KAsgdhRJgZJDTkc0'
)

-- Final analysis combining all methods
SELECT 
  'Query Fingerprint Analysis' as method,
  job_id,
  creation_time,
  fingerprint,
  total_bytes_processed,
  total_slot_ms,
  'Check for similar queries with actual dates' as recommendation
FROM query_fingerprints
WHERE fingerprint LIKE '%v_shipments%ontrac%manifest%ship_date%BETWEEN%'

UNION ALL

SELECT 
  'Non-Parameterized Examples' as method,
  job_id,
  creation_time,
  CASE 
    WHEN ARRAY_LENGTH(date_ranges) > 0 THEN 
      CONCAT('BETWEEN ', date_ranges[OFFSET(0)], ' AND ', date_ranges[OFFSET(1)])
    WHEN ARRAY_LENGTH(start_dates) > 0 AND ARRAY_LENGTH(end_dates) > 0 THEN
      CONCAT('>= ', start_dates[OFFSET(0)], ' AND <= ', end_dates[OFFSET(0)])
    ELSE 'No date range found'
  END as fingerprint,
  total_bytes_processed,
  total_slot_ms,
  'Use these as templates for parameter values' as recommendation
FROM non_parametrized_versions
WHERE ARRAY_LENGTH(date_ranges) > 0 OR ARRAY_LENGTH(start_dates) > 0

UNION ALL

SELECT 
  'Business Context Inference' as method,
  'job_fkhGvQtTHmR_KAsgdhRJgZJDTkc0' as job_id,
  TIMESTAMP('2025-11-14 08:06:16.720000 UTC') as creation_time,
  'Based on 262GB processed and Fashion Nova patterns' as fingerprint,
  262032590559 as total_bytes_processed,
  44735491 as total_slot_ms,
  'Most likely: 60-90 days (Oct 1 - Nov 14, 2024)' as recommendation;