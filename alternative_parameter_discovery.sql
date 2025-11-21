-- Alternative Parameter Discovery (No TABLE_STORAGE access required)
-- Uses only JOBS_BY_PROJECT and data analysis techniques

-- Method 1: Query fingerprint matching with available data
WITH query_patterns AS (
  SELECT 
    job_id,
    creation_time,
    query,
    -- Extract the core query pattern (remove parameters)
    REGEXP_REPLACE(
      REGEXP_REPLACE(query, r"\?", "PARAM"),
      r"'[^']*'", "'VALUE'"
    ) as query_pattern,
    total_bytes_processed,
    total_slot_ms,
    -- Extract parameter count
    ARRAY_LENGTH(REGEXP_EXTRACT_ALL(query, r"\?")) as param_count
  FROM `monitor-a679b28-us-prod.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
  WHERE DATE(creation_time) >= '2025-11-10'
    AND query LIKE '%v_shipments%'
    AND query LIKE '%ontrac%'
    AND query LIKE '%manifest%'
),

-- Method 2: Find similar queries with actual date values
date_pattern_queries AS (
  SELECT 
    job_id,
    creation_time,
    query,
    -- Look for queries with actual date strings
    CASE 
      WHEN REGEXP_CONTAINS(query, r"[0-9]{4}-[0-9]{2}-[0-9]{2}") THEN 'has_dates'
      WHEN REGEXP_CONTAINS(query, r"\?") THEN 'parameterized'
      ELSE 'other'
    END as query_type,
    -- Extract any date patterns
    REGEXP_EXTRACT_ALL(query, r"'([0-9]{4}-[0-9]{2}-[0-9]{2})'") as found_dates,
    total_bytes_processed,
    total_slot_ms
  FROM `monitor-a679b28-us-prod.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
  WHERE DATE(creation_time) >= '2025-11-01'
    AND query LIKE '%v_shipments%'
    AND query LIKE '%ontrac%'
    AND query LIKE '%manifest%'
),

-- Method 3: Volume-based estimation using job statistics
volume_estimation AS (
  SELECT 
    job_id,
    creation_time,
    total_bytes_processed,
    total_slot_ms,
    -- Estimate data volume per day based on job characteristics
    CASE 
      WHEN total_bytes_processed < 50000000000 THEN 'small_range'      -- <50GB
      WHEN total_bytes_processed < 150000000000 THEN 'medium_range'    -- 50-150GB  
      WHEN total_bytes_processed < 300000000000 THEN 'large_range'     -- 150-300GB
      ELSE 'extra_large_range'                                         -- >300GB
    END as volume_category,
    -- Calculate processing efficiency (bytes per slot-ms)
    SAFE_DIVIDE(total_bytes_processed, total_slot_ms) as bytes_per_slot_ms
  FROM `monitor-a679b28-us-prod.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
  WHERE DATE(creation_time) >= '2025-11-10'
    AND query LIKE '%v_shipments%'
    AND query LIKE '%ontrac%'
    AND query LIKE '%manifest%'
)

-- Combined analysis
SELECT 
  'Target Query Analysis' as analysis_type,
  job_id,
  creation_time,
  total_bytes_processed,
  total_slot_ms,
  param_count,
  'Parameterized query - parameters not visible in logs' as finding
FROM query_patterns
WHERE job_id = 'job_fkhGvQtTHmR_KAsgdhRJgZJDTkc0'

UNION ALL

SELECT 
  'Similar Query Patterns' as analysis_type,
  job_id,
  creation_time,
  total_bytes_processed,
  total_slot_ms,
  ARRAY_LENGTH(found_dates) as param_count,
  CASE 
    WHEN ARRAY_LENGTH(found_dates) >= 2 THEN 
      CONCAT('Date range: ', found_dates[OFFSET(0)], ' to ', found_dates[OFFSET(1)])
    WHEN ARRAY_LENGTH(found_dates) = 1 THEN
      CONCAT('Single date: ', found_dates[OFFSET(0)])
    ELSE 'No dates found'
  END as finding
FROM date_pattern_queries
WHERE query_type = 'has_dates'
ORDER BY creation_time DESC
LIMIT 5

UNION ALL

SELECT 
  'Volume-Based Estimation' as analysis_type,
  job_id,
  creation_time,
  total_bytes_processed,
  total_slot_ms,
  0 as param_count,
  CASE volume_category
    WHEN 'small_range' THEN 'Likely 7-30 days'
    WHEN 'medium_range' THEN 'Likely 30-60 days'  
    WHEN 'large_range' THEN 'Likely 60-90 days'
    WHEN 'extra_large_range' THEN 'Likely 90-180 days'
  END as finding
FROM volume_estimation
WHERE job_id = 'job_fkhGvQtTHmR_KAsgdhRJgZJDTkc0';