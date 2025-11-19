-- ============================================================================
-- HUB Pattern Discovery - Sample Analysis (Phase A)
-- ============================================================================
-- Purpose: Sample 200 Hub jobs to discover retailer attribution patterns
-- Goal: Identify how to extract retailer_moniker from full query text
-- Cost: Low (~1-2GB) - samples from both 2025 periods
-- Next Step: Use discovered patterns for full 2025 analysis
-- ============================================================================

-- Configuration
DECLARE sample_size INT64 DEFAULT 200;
DECLARE target_periods ARRAY<STRING> DEFAULT ['Peak_2024_2025', 'Baseline_2025_Sep_Oct'];

-- ============================================================================
-- STEP 1: Sample Hub Jobs from Classification Table
-- ============================================================================
WITH hub_sample AS (
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
      WHEN execution_time_seconds <= 30 THEN 'fast'
      WHEN execution_time_seconds <= 120 THEN 'medium'
      ELSE 'slow'
    END AS speed_category,
    
    CASE
      WHEN is_qos_violation THEN 'violating'
      ELSE 'compliant'
    END AS qos_category
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE consumer_subcategory = 'HUB'
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
  FROM hub_sample
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
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)retailer_moniker\s*=\s*['\"]([^'\"]+)['\"]") AS pattern_1_retailer_equals,
    
    -- Pattern 2: WHERE retailer_moniker IN ('value1', 'value2', ...)
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)retailer_moniker\s+IN\s*\(['\"]([^'\"]+)['\"]") AS pattern_2_retailer_in,
    
    -- Pattern 3: JOIN on retailer conditions
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)ON\s+.*?retailer[_a-z]*\s*=\s*['\"]([^'\"]+)['\"]") AS pattern_3_join_retailer,
    
    -- Pattern 4: Looker-specific comment (-- Looker Query Context: {...})
    REGEXP_CONTAINS(fqt.full_query_text, r"(?i)--\s*Looker") AS has_looker_comment,
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)--\s*Looker[^\n]+") AS looker_comment_line,
    
    -- Pattern 5: Dashboard or view name in comment
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)--\s*Dashboard:\s*([^\n]+)") AS dashboard_name,
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)--\s*View:\s*([^\n]+)") AS view_name,
    
    -- Pattern 6: Table names containing retailer identifiers
    REGEXP_CONTAINS(fqt.full_query_text, r"(?i)FROM\s+[^\s]+\.retailer_") AS references_retailer_table,
    
    -- Pattern 7: Metabase-style comment (in case Hub uses Metabase backend)
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)--\s*Metabase::\s*([^\n]+)") AS metabase_comment,
    
    -- Pattern 8: User email in query (sometimes embedded in BI tools)
    REGEXP_EXTRACT(fqt.full_query_text, r"(?i)--\s*User:\s*([^\n]+)") AS user_from_comment,
    
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
    
    -- Store full query for detailed analysis (will be large output)
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
  has_looker_comment,
  looker_comment_line,
  dashboard_name,
  view_name,
  references_retailer_table,
  metabase_comment,
  user_from_comment,
  
  -- Use best pattern (COALESCE tries patterns in order)
  COALESCE(
    pattern_1_retailer_equals,
    pattern_2_retailer_in,
    pattern_3_join_retailer,
    'UNKNOWN'
  ) AS best_retailer_match,
  
  -- Success flag
  CASE
    WHEN pattern_1_retailer_equals IS NOT NULL THEN TRUE
    WHEN pattern_2_retailer_in IS NOT NULL THEN TRUE
    WHEN pattern_3_join_retailer IS NOT NULL THEN TRUE
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
  
  -- Full text (CAUTION: Large output - comment out if not needed)
  full_query_text

FROM pattern_extraction

ORDER BY 
  -- Prioritize: QoS violations, then slowest queries
  is_qos_violation DESC,
  execution_time_seconds DESC;

-- ============================================================================
-- SUMMARY STATISTICS
-- ============================================================================
-- Uncomment to get pattern success rates instead of individual rows
/*
SELECT
  analysis_period_label,
  COUNT(*) AS total_sampled,
  COUNTIF(pattern_1_retailer_equals IS NOT NULL) AS pattern_1_success,
  COUNTIF(pattern_2_retailer_in IS NOT NULL) AS pattern_2_success,
  COUNTIF(pattern_3_join_retailer IS NOT NULL) AS pattern_3_success,
  COUNTIF(has_looker_comment) AS has_looker_metadata,
  COUNTIF(dashboard_name IS NOT NULL) AS has_dashboard_name,
  COUNTIF(COALESCE(pattern_1_retailer_equals, pattern_2_retailer_in, pattern_3_join_retailer) IS NOT NULL) AS any_pattern_success,
  ROUND(COUNTIF(COALESCE(pattern_1_retailer_equals, pattern_2_retailer_in, pattern_3_join_retailer) IS NOT NULL) / COUNT(*) * 100, 1) AS success_rate_pct,
  
  -- Performance stats
  ROUND(AVG(execution_time_seconds), 2) AS avg_exec_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_exec_seconds,
  COUNTIF(is_qos_violation) AS qos_violations,
  ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 1) AS violation_rate_pct,
  
  -- Query complexity
  ROUND(AVG(full_query_length), 0) AS avg_query_length,
  ROUND(AVG(approx_from_clauses), 1) AS avg_from_clauses,
  COUNTIF(has_joins) AS queries_with_joins,
  COUNTIF(has_cte) AS queries_with_cte
  
FROM pattern_extraction
GROUP BY analysis_period_label
ORDER BY analysis_period_label;
*/

