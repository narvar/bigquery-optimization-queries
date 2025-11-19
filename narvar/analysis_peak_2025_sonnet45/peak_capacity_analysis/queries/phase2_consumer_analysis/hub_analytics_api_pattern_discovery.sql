-- ============================================================================
-- Hub Analytics API Pattern Discovery - Sample Analysis
-- ============================================================================
-- Purpose: Sample Hub Analytics API queries to discover retailer attribution patterns
-- Goal: Identify if/how retailer_moniker appears in Hub Analytics queries
-- Cost: ~40-50GB (audit log join for full query text)
-- Consumer: ANALYTICS_API (analytics-api-bigquery-access service account)
-- ============================================================================

-- Configuration
DECLARE sample_size INT64 DEFAULT 200;
DECLARE target_periods ARRAY<STRING> DEFAULT ['Peak_2024_2025', 'Baseline_2025_Sep_Oct'];

-- ============================================================================
-- STEP 1: Sample Hub Analytics API Jobs from Classification Table
-- ============================================================================
WITH hub_analytics_sample AS (
  SELECT
    job_id,
    project_id,
    principal_email,
    analysis_period_label,
    start_time,
    execution_time_seconds,
    slot_hours,
    estimated_slot_cost_usd,
    approximate_slot_count,
    total_billed_bytes,
    is_qos_violation,
    qos_violation_seconds,
    query_text_sample AS partial_query_text,  -- 500 chars only
    
    -- Stratified sampling metadata
    CASE
      WHEN execution_time_seconds <= 5 THEN 'fast'
      WHEN execution_time_seconds <= 30 THEN 'medium'
      ELSE 'slow'
    END AS speed_category,
    
    CASE
      WHEN is_qos_violation THEN 'violating'
      ELSE 'compliant'
    END AS qos_category
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE consumer_subcategory = 'ANALYTICS_API'  -- Hub Analytics API
    AND analysis_period_label IN UNNEST(target_periods)
    AND total_slot_ms IS NOT NULL
),

-- Stratified sample to get diverse query types
stratified_sample AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY analysis_period_label, speed_category, qos_category 
      ORDER BY RAND()
    ) AS sample_rank
  FROM hub_analytics_sample
),

sampled_jobs AS (
  SELECT * EXCEPT(sample_rank, speed_category, qos_category)
  FROM stratified_sample
  WHERE sample_rank <= 10  -- 10 per stratum = ~120-200 total jobs
),

-- ============================================================================
-- STEP 2: Join to Audit Logs to Get FULL Query Text
-- ============================================================================
full_query_text AS (
  SELECT
    sj.job_id,
    sj.project_id,
    sj.principal_email,
    sj.analysis_period_label,
    sj.start_time,
    sj.execution_time_seconds,
    sj.slot_hours,
    sj.estimated_slot_cost_usd,
    sj.approximate_slot_count,
    ROUND(sj.total_billed_bytes / POW(1024, 3), 2) AS gb_scanned,
    sj.is_qos_violation,
    sj.qos_violation_seconds,
    sj.partial_query_text,
    
    -- Get FULL query text from audit logs
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS full_query_text,
    
    -- Get query length for comparison
    LENGTH(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query) AS full_query_length,
    LENGTH(sj.partial_query_text) AS partial_query_length
    
  FROM sampled_jobs sj
  INNER JOIN `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` audit
    ON sj.job_id = protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId
    AND DATE(audit.timestamp) BETWEEN '2024-11-01' AND '2025-10-31'  -- Cover both 2025 periods
  WHERE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
),

-- ============================================================================
-- STEP 3: Pattern Extraction - Try Multiple Regex Patterns
-- ============================================================================
pattern_extraction AS (
  SELECT
    fqt.job_id,
    fqt.project_id,
    fqt.principal_email,
    fqt.analysis_period_label,
    fqt.start_time,
    fqt.execution_time_seconds,
    fqt.slot_hours,
    fqt.estimated_slot_cost_usd,
    fqt.approximate_slot_count,
    fqt.gb_scanned,
    fqt.is_qos_violation,
    fqt.qos_violation_seconds,
    fqt.full_query_length,
    fqt.partial_query_length,
    
    -- Pattern 1: WHERE retailer_moniker = 'value'
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)\(?\s*retailer_moniker\s*\)?\s*=\s*['\"]([^'\"]+)['\"]") AS pattern_1_retailer_equals,
    
    -- Pattern 2: WHERE retailer_moniker IN ('value1', 'value2', ...)
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)retailer_moniker\s+IN\s*\(\s*['\"]([^'\"]+)['\"]") AS pattern_2_retailer_in,
    
    -- Pattern 3: JOIN on retailer conditions
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)ON\s+.*?retailer[_\w]*\s*=\s*['\"]([^'\"]+)['\"]") AS pattern_3_join_retailer,
    
    -- Pattern 4: API parameter in comment (-- retailer: value)
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)--\s*retailer[:\s]+([^\n,]+)") AS pattern_4_comment_retailer,
    
    -- Pattern 5: JSON parameter in comment ({"retailer": "value"})
    REGEXP_EXTRACT(fqt.full_query_text, r'''(?i)"retailer":\s*"([^"]+)"''') AS pattern_5_json_retailer,
    
    -- Pattern 6: URL parameter in comment (?retailer=value)
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)[?&]retailer=([^&\s]+)") AS pattern_6_url_retailer,
    
    -- Pattern 7: Table names with retailer (FROM retailer_specific_table)
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)FROM\s+[\w.]+_([a-z]+)\s") AS pattern_7_table_suffix,
    
    -- Check if retailer_moniker exists anywhere (debugging)
    REGEXP_CONTAINS(fqt.full_query_text, r"(?i)retailer_moniker") AS has_retailer_moniker_field,
    REGEXP_CONTAINS(fqt.full_query_text, r"(?i)retailer") AS has_retailer_word,
    
    -- API-specific patterns
    REGEXP_CONTAINS(fqt.full_query_text, r"(?i)--\s*(API|analytics-api|hub)") AS has_api_comment,
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)--\s*(API|analytics)[^\n]+") AS api_comment_line,
    
    -- Query structure analysis
    REGEXP_CONTAINS(fqt.full_query_text, r"(?i)\bJOIN\b") AS has_joins,
    REGEXP_CONTAINS(fqt.full_query_text, r"(?i)\bGROUP BY\b") AS has_group_by,
    REGEXP_CONTAINS(fqt.full_query_text, r"(?i)\bWINDOW\b|OVER\s*\(") AS has_window_functions,
    REGEXP_CONTAINS(fqt.full_query_text, r"(?i)\bWITH\b") AS has_cte,
    REGEXP_CONTAINS(fqt.full_query_text, r"(?i)\bPARTITION\b") AS has_partition_filter,
    
    -- Count of tables referenced
    (LENGTH(fqt.full_query_text) - LENGTH(REGEXP_REPLACE(fqt.full_query_text, r"(?i)\bFROM\b", ""))) / 4 AS approx_from_clauses,
    
    -- Store first 1000 chars for manual review
    SUBSTR(fqt.full_query_text, 1, 1000) AS query_preview_1000,
    
    -- Store full query for detailed analysis
    fqt.full_query_text
    
  FROM full_query_text fqt
)

-- ============================================================================
-- OUTPUT: Pattern Discovery Results
-- ============================================================================
SELECT
  -- Job identification
  job_id,
  analysis_period_label,
  start_time,
  
  -- Performance metrics
  execution_time_seconds,
  slot_hours,
  estimated_slot_cost_usd,
  approximate_slot_count,
  gb_scanned,
  is_qos_violation,
  qos_violation_seconds,
  
  -- Query size
  full_query_length,
  partial_query_length,
  ROUND(partial_query_length / full_query_length * 100, 1) AS pct_captured_in_sample,
  
  -- Extracted patterns (these are what we're testing!)
  pattern_1_retailer_equals,
  pattern_2_retailer_in,
  pattern_3_join_retailer,
  pattern_4_comment_retailer,
  pattern_5_json_retailer,
  pattern_6_url_retailer,
  pattern_7_table_suffix,
  has_retailer_moniker_field,
  has_retailer_word,
  has_api_comment,
  api_comment_line,
  
  -- Use best pattern (COALESCE tries patterns in order)
  COALESCE(
    pattern_1_retailer_equals,
    pattern_2_retailer_in,
    pattern_3_join_retailer,
    pattern_4_comment_retailer,
    pattern_5_json_retailer,
    pattern_6_url_retailer,
    'NO_RETAILER'
  ) AS best_retailer_match,
  
  -- Success flag
  CASE
    WHEN pattern_1_retailer_equals IS NOT NULL THEN TRUE
    WHEN pattern_2_retailer_in IS NOT NULL THEN TRUE
    WHEN pattern_3_join_retailer IS NOT NULL THEN TRUE
    WHEN pattern_4_comment_retailer IS NOT NULL THEN TRUE
    WHEN pattern_5_json_retailer IS NOT NULL THEN TRUE
    WHEN pattern_6_url_retailer IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS retailer_extraction_success,
  
  -- Query structure
  has_joins,
  has_group_by,
  has_window_functions,
  has_cte,
  has_partition_filter,
  approx_from_clauses,
  
  -- Preview for manual inspection
  query_preview_1000,
  
  -- Full text (CAUTION: Large output)
  full_query_text

FROM pattern_extraction

ORDER BY 
  -- Prioritize: fastest queries first (typical of Hub Analytics)
  execution_time_seconds ASC;

-- ============================================================================
-- SUMMARY STATISTICS (Uncomment to run separately)
-- ============================================================================
/*
SELECT
  analysis_period_label,
  COUNT(*) AS total_sampled,
  
  -- Pattern success rates
  COUNTIF(pattern_1_retailer_equals IS NOT NULL) AS pattern_1_success,
  COUNTIF(pattern_2_retailer_in IS NOT NULL) AS pattern_2_success,
  COUNTIF(pattern_3_join_retailer IS NOT NULL) AS pattern_3_success,
  COUNTIF(pattern_4_comment_retailer IS NOT NULL) AS pattern_4_comment,
  COUNTIF(pattern_5_json_retailer IS NOT NULL) AS pattern_5_json,
  COUNTIF(pattern_6_url_retailer IS NOT NULL) AS pattern_6_url,
  
  -- Field presence
  COUNTIF(has_retailer_moniker_field) AS has_retailer_field,
  COUNTIF(has_retailer_word) AS has_retailer_word,
  COUNTIF(has_api_comment) AS has_api_metadata,
  
  -- Overall success
  COUNTIF(COALESCE(pattern_1_retailer_equals, pattern_2_retailer_in, pattern_3_join_retailer, 
                   pattern_4_comment_retailer, pattern_5_json_retailer, pattern_6_url_retailer) IS NOT NULL) AS any_pattern_success,
  ROUND(COUNTIF(COALESCE(pattern_1_retailer_equals, pattern_2_retailer_in, pattern_3_join_retailer,
                         pattern_4_comment_retailer, pattern_5_json_retailer, pattern_6_url_retailer) IS NOT NULL) / COUNT(*) * 100, 1) AS success_rate_pct,
  
  -- Performance stats
  ROUND(AVG(execution_time_seconds), 2) AS avg_exec_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_exec_seconds,
  COUNTIF(is_qos_violation) AS qos_violations,
  
  -- Query complexity
  ROUND(AVG(full_query_length), 0) AS avg_query_length,
  COUNTIF(has_joins) AS queries_with_joins,
  COUNTIF(has_group_by) AS queries_with_group_by,
  COUNTIF(has_cte) AS queries_with_cte,
  COUNTIF(has_partition_filter) AS queries_with_partition
  
FROM pattern_extraction
GROUP BY analysis_period_label
ORDER BY analysis_period_label;
*/

