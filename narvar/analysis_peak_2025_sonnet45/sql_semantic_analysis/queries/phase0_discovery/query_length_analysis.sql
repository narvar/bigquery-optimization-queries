-- ============================================================================
-- QUERY LENGTH & TRUNCATION ANALYSIS
-- ============================================================================
-- Purpose: Determine if 500-char query samples in traffic_classification
--          are sufficient or if we need full query text from audit logs
--
-- Decision Point:
--   - If <10% truncated → Use traffic_classification (fast, free)
--   - If >20% truncated → Need audit log JOIN (slower but complete)
--
-- Cost estimate: ~2-5GB processed
-- ============================================================================

DECLARE start_date DATE DEFAULT '2024-11-01';
DECLARE end_date DATE DEFAULT '2025-10-31';

-- ============================================================================
-- MAIN ANALYSIS
-- ============================================================================

WITH query_stats AS (
  SELECT
    analysis_period_label,
    consumer_category,
    consumer_subcategory,
    job_id,
    
    -- Query length from traffic_classification (sample, max 500 chars)
    LENGTH(query_text_sample) AS query_sample_length,
    
    -- Indicators
    CASE 
      WHEN LENGTH(query_text_sample) >= 500 THEN TRUE 
      ELSE FALSE 
    END AS likely_truncated,
    
    CASE
      WHEN LENGTH(query_text_sample) = 0 OR query_text_sample IS NULL THEN 'empty'
      WHEN LENGTH(query_text_sample) < 100 THEN 'very_short'
      WHEN LENGTH(query_text_sample) < 250 THEN 'short'
      WHEN LENGTH(query_text_sample) < 500 THEN 'medium'
      WHEN LENGTH(query_text_sample) >= 500 THEN 'long_truncated'
    END AS length_category,
    
    -- Performance metrics for context
    execution_time_seconds,
    slot_hours,
    is_qos_violation,
    
    -- Query complexity indicators (from sample)
    REGEXP_CONTAINS(query_text_sample, r'\bJOIN\b') AS has_join,
    REGEXP_CONTAINS(query_text_sample, r'\bWITH\b') AS has_cte,
    REGEXP_CONTAINS(query_text_sample, r'\bUNION\b') AS has_union,
    REGEXP_CONTAINS(query_text_sample, r'\bWINDOW\b|\bOVER\s*\(') AS has_window_function
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE analysis_period_label IN (
    'Baseline_2023_2024',
    'Peak_2023_2024', 
    'PostPeak_2023_2024',
    'Baseline_2024_2025',
    'Peak_2024_2025'
  )
    AND consumer_category IN ('EXTERNAL', 'INTERNAL', 'AUTOMATED')
    AND query_text_sample IS NOT NULL
)

SELECT
  -- Overall statistics
  'OVERALL' AS breakdown_type,
  'ALL' AS breakdown_value,
  
  -- Volume
  COUNT(*) AS total_queries,
  COUNT(DISTINCT job_id) AS unique_jobs,
  
  -- Truncation analysis
  COUNTIF(likely_truncated) AS truncated_count,
  ROUND(COUNTIF(likely_truncated) / COUNT(*) * 100, 2) AS truncated_pct,
  
  -- Length statistics
  ROUND(AVG(query_sample_length), 2) AS avg_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(50)] AS median_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(95)] AS p95_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(99)] AS p99_length,
  MAX(query_sample_length) AS max_length,
  
  -- Length distribution
  COUNTIF(length_category = 'empty') AS empty_count,
  COUNTIF(length_category = 'very_short') AS very_short_count,
  COUNTIF(length_category = 'short') AS short_count,
  COUNTIF(length_category = 'medium') AS medium_count,
  COUNTIF(length_category = 'long_truncated') AS long_truncated_count,
  
  -- Complexity indicators (from samples)
  COUNTIF(has_join) AS queries_with_joins,
  COUNTIF(has_cte) AS queries_with_ctes,
  COUNTIF(has_union) AS queries_with_unions,
  COUNTIF(has_window_function) AS queries_with_windows,
  
  -- Performance context
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(SUM(slot_hours), 2) AS total_slot_hours,
  COUNTIF(is_qos_violation) AS qos_violation_count

FROM query_stats

UNION ALL

-- By consumer category
SELECT
  'CONSUMER_CATEGORY' AS breakdown_type,
  consumer_category AS breakdown_value,
  
  COUNT(*) AS total_queries,
  COUNT(DISTINCT job_id) AS unique_jobs,
  COUNTIF(likely_truncated) AS truncated_count,
  ROUND(COUNTIF(likely_truncated) / COUNT(*) * 100, 2) AS truncated_pct,
  ROUND(AVG(query_sample_length), 2) AS avg_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(50)] AS median_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(95)] AS p95_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(99)] AS p99_length,
  MAX(query_sample_length) AS max_length,
  COUNTIF(length_category = 'empty') AS empty_count,
  COUNTIF(length_category = 'very_short') AS very_short_count,
  COUNTIF(length_category = 'short') AS short_count,
  COUNTIF(length_category = 'medium') AS medium_count,
  COUNTIF(length_category = 'long_truncated') AS long_truncated_count,
  COUNTIF(has_join) AS queries_with_joins,
  COUNTIF(has_cte) AS queries_with_ctes,
  COUNTIF(has_union) AS queries_with_unions,
  COUNTIF(has_window_function) AS queries_with_windows,
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(SUM(slot_hours), 2) AS total_slot_hours,
  COUNTIF(is_qos_violation) AS qos_violation_count

FROM query_stats
GROUP BY consumer_category

UNION ALL

-- By consumer subcategory
SELECT
  'CONSUMER_SUBCATEGORY' AS breakdown_type,
  consumer_subcategory AS breakdown_value,
  
  COUNT(*) AS total_queries,
  COUNT(DISTINCT job_id) AS unique_jobs,
  COUNTIF(likely_truncated) AS truncated_count,
  ROUND(COUNTIF(likely_truncated) / COUNT(*) * 100, 2) AS truncated_pct,
  ROUND(AVG(query_sample_length), 2) AS avg_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(50)] AS median_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(95)] AS p95_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(99)] AS p99_length,
  MAX(query_sample_length) AS max_length,
  COUNTIF(length_category = 'empty') AS empty_count,
  COUNTIF(length_category = 'very_short') AS very_short_count,
  COUNTIF(length_category = 'short') AS short_count,
  COUNTIF(length_category = 'medium') AS medium_count,
  COUNTIF(length_category = 'long_truncated') AS long_truncated_count,
  COUNTIF(has_join) AS queries_with_joins,
  COUNTIF(has_cte) AS queries_with_ctes,
  COUNTIF(has_union) AS queries_with_unions,
  COUNTIF(has_window_function) AS queries_with_windows,
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(SUM(slot_hours), 2) AS total_slot_hours,
  COUNTIF(is_qos_violation) AS qos_violation_count

FROM query_stats
GROUP BY consumer_subcategory

UNION ALL

-- By period
SELECT
  'PERIOD' AS breakdown_type,
  analysis_period_label AS breakdown_value,
  
  COUNT(*) AS total_queries,
  COUNT(DISTINCT job_id) AS unique_jobs,
  COUNTIF(likely_truncated) AS truncated_count,
  ROUND(COUNTIF(likely_truncated) / COUNT(*) * 100, 2) AS truncated_pct,
  ROUND(AVG(query_sample_length), 2) AS avg_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(50)] AS median_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(95)] AS p95_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(99)] AS p99_length,
  MAX(query_sample_length) AS max_length,
  COUNTIF(length_category = 'empty') AS empty_count,
  COUNTIF(length_category = 'very_short') AS very_short_count,
  COUNTIF(length_category = 'short') AS short_count,
  COUNTIF(length_category = 'medium') AS medium_count,
  COUNTIF(length_category = 'long_truncated') AS long_truncated_count,
  COUNTIF(has_join) AS queries_with_joins,
  COUNTIF(has_cte) AS queries_with_ctes,
  COUNTIF(has_union) AS queries_with_unions,
  COUNTIF(has_window_function) AS queries_with_windows,
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(SUM(slot_hours), 2) AS total_slot_hours,
  COUNTIF(is_qos_violation) AS qos_violation_count

FROM query_stats
GROUP BY analysis_period_label

UNION ALL

-- By length category
SELECT
  'LENGTH_CATEGORY' AS breakdown_type,
  length_category AS breakdown_value,
  
  COUNT(*) AS total_queries,
  COUNT(DISTINCT job_id) AS unique_jobs,
  COUNTIF(likely_truncated) AS truncated_count,
  ROUND(COUNTIF(likely_truncated) / COUNT(*) * 100, 2) AS truncated_pct,
  ROUND(AVG(query_sample_length), 2) AS avg_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(50)] AS median_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(95)] AS p95_length,
  APPROX_QUANTILES(query_sample_length, 100)[OFFSET(99)] AS p99_length,
  MAX(query_sample_length) AS max_length,
  COUNTIF(length_category = 'empty') AS empty_count,
  COUNTIF(length_category = 'very_short') AS very_short_count,
  COUNTIF(length_category = 'short') AS short_count,
  COUNTIF(length_category = 'medium') AS medium_count,
  COUNTIF(length_category = 'long_truncated') AS long_truncated_count,
  COUNTIF(has_join) AS queries_with_joins,
  COUNTIF(has_cte) AS queries_with_ctes,
  COUNTIF(has_union) AS queries_with_unions,
  COUNTIF(has_window_function) AS queries_with_windows,
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(SUM(slot_hours), 2) AS total_slot_hours,
  COUNTIF(is_qos_violation) AS qos_violation_count

FROM query_stats
GROUP BY length_category

ORDER BY 
  CASE breakdown_type
    WHEN 'OVERALL' THEN 1
    WHEN 'CONSUMER_CATEGORY' THEN 2
    WHEN 'CONSUMER_SUBCATEGORY' THEN 3
    WHEN 'PERIOD' THEN 4
    WHEN 'LENGTH_CATEGORY' THEN 5
  END,
  breakdown_value;

-- ============================================================================
-- SAMPLE QUERIES BY LENGTH
-- ============================================================================
-- Uncomment to see examples of queries by length category
/*
WITH query_samples AS (
  SELECT
    consumer_subcategory,
    LENGTH(query_text_sample) AS query_length,
    CASE
      WHEN LENGTH(query_text_sample) = 0 OR query_text_sample IS NULL THEN 'empty'
      WHEN LENGTH(query_text_sample) < 100 THEN 'very_short'
      WHEN LENGTH(query_text_sample) < 250 THEN 'short'
      WHEN LENGTH(query_text_sample) < 500 THEN 'medium'
      WHEN LENGTH(query_text_sample) >= 500 THEN 'long_truncated'
    END AS length_category,
    query_text_sample,
    execution_time_seconds,
    slot_hours,
    ROW_NUMBER() OVER(
      PARTITION BY 
        consumer_subcategory,
        CASE
          WHEN LENGTH(query_text_sample) = 0 OR query_text_sample IS NULL THEN 'empty'
          WHEN LENGTH(query_text_sample) < 100 THEN 'very_short'
          WHEN LENGTH(query_text_sample) < 250 THEN 'short'
          WHEN LENGTH(query_text_sample) < 500 THEN 'medium'
          WHEN LENGTH(query_text_sample) >= 500 THEN 'long_truncated'
        END
      ORDER BY RAND()
    ) AS rn
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE analysis_period_label IN ('Peak_2024_2025')
    AND consumer_category IN ('EXTERNAL', 'INTERNAL', 'AUTOMATED')
    AND query_text_sample IS NOT NULL
)
SELECT
  consumer_subcategory,
  length_category,
  query_length,
  query_text_sample,
  execution_time_seconds,
  slot_hours
FROM query_samples
WHERE rn <= 3  -- 3 samples per category per platform
ORDER BY consumer_subcategory, length_category;
*/

