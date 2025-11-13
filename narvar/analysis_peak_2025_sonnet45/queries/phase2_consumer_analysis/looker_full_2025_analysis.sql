-- ============================================================================
-- HUB Full 2025 Analysis with Retailer Attribution
-- ============================================================================
-- Purpose: Complete Hub analysis for 2025 periods with improved retailer extraction
-- Based on: Pattern discovery findings (60% initial success, improved patterns)
-- Periods: Peak_2024_2025, Baseline_2025_Sep_Oct
-- Cost: ~40-50GB (includes audit log join for full query text)
-- ============================================================================

-- Configuration
DECLARE target_periods ARRAY<STRING> DEFAULT ['Peak_2024_2025', 'Baseline_2025_Sep_Oct'];

-- ============================================================================
-- STEP 1: Get Hub Jobs from Classification Table
-- ============================================================================
WITH hub_jobs AS (
  SELECT
    job_id,
    project_id,
    principal_email,
    analysis_period_label,
    start_time,
    end_time,
    execution_time_seconds,
    total_slot_ms,
    approximate_slot_count,
    slot_hours,
    total_billed_bytes,
    estimated_slot_cost_usd,
    qos_status,
    is_qos_violation,
    qos_violation_seconds,
    query_text_sample  -- Partial text (500 chars)
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE consumer_subcategory = 'HUB'
    AND analysis_period_label IN UNNEST(target_periods)
    AND total_slot_ms IS NOT NULL
),

-- ============================================================================
-- STEP 2: Join to Audit Logs for FULL Query Text
-- ============================================================================
hub_with_full_text AS (
  SELECT
    hj.*,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS full_query_text
  FROM hub_jobs hj
  LEFT JOIN `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` audit
    ON hj.job_id = protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId
    AND DATE(audit.timestamp) = DATE(hj.start_time)  -- Partition pruning
  WHERE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
),

-- ============================================================================
-- STEP 3: Extract Retailer with IMPROVED Patterns
-- ============================================================================
hub_with_retailer AS (
  SELECT
    *,
    
    -- Pattern 1: Standard equals (with optional parentheses)
    -- Matches: retailer_moniker = 'value' OR (retailer_moniker) = 'value'
    COALESCE(
      REGEXP_EXTRACT(full_query_text, r"(?i)\(?\s*retailer_moniker\s*\)?\s*=\s*['\"]([^'\"]+)['\"]"),
      REGEXP_EXTRACT(query_text_sample, r"(?i)\(?\s*retailer_moniker\s*\)?\s*=\s*['\"]([^'\"]+)['\"]")
    ) AS pattern_1_equals,
    
    -- Pattern 2: IN clause (first value)
    COALESCE(
      REGEXP_EXTRACT(full_query_text, r"(?i)retailer_moniker\s+IN\s*\(\s*['\"]([^'\"]+)['\"]"),
      REGEXP_EXTRACT(query_text_sample, r"(?i)retailer_moniker\s+IN\s*\(\s*['\"]([^'\"]+)['\"]")
    ) AS pattern_2_in,
    
    -- Pattern 3: JOIN conditions
    -- Matches: ON table.retailer_moniker = other_table.retailer OR ... = 'value'
    COALESCE(
      REGEXP_EXTRACT(full_query_text, r"(?i)ON\s+\w+\.retailer[_\w]*\s*=\s*\w+\.\w+"),
      REGEXP_EXTRACT(full_query_text, r"(?i)ON\s+.*?retailer[_\w]*\s*=\s*['\"]([^'\"]+)['\"]")
    ) AS pattern_3_join,
    
    -- Pattern 4: LIKE patterns (extract if not wildcard)
    -- Matches: LIKE 'value' but NOT LIKE '%' or LIKE '% %'
    CASE
      WHEN COALESCE(full_query_text, query_text_sample) LIKE "%retailer_moniker%LIKE '%%%'%" THEN NULL
      ELSE COALESCE(
        REGEXP_EXTRACT(full_query_text, r"(?i)retailer_moniker\s+LIKE\s+['\"]([^'\"]+)['\"]"),
        REGEXP_EXTRACT(query_text_sample, r"(?i)retailer_moniker\s+LIKE\s+['\"]([^'\"]+)['\"]")
      )
    END AS pattern_4_like,
    
    -- Pattern 5: In CTEs/Subqueries (search deeper)
    REGEXP_EXTRACT(full_query_text, r"(?i)WITH\s+\w+\s+AS\s*\([^)]*retailer_moniker\s*=\s*['\"]([^'\"]+)['\"]") AS pattern_5_cte,
    
    -- Aggregate Query Detection (no specific retailer)
    CASE
      WHEN REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)GROUP\s+BY") 
        AND NOT REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)retailer_moniker\s*[=]")
        AND NOT REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)WHERE.*retailer")
      THEN TRUE
      ELSE FALSE
    END AS is_aggregate_query,
    
    -- Check if retailer_moniker exists anywhere (debugging)
    REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)retailer_moniker") AS has_retailer_moniker_field
    
  FROM hub_with_full_text
),

-- ============================================================================
-- STEP 4: Determine Best Retailer Match with Classification Logic
-- ============================================================================
hub_classified AS (
  SELECT
    *,
    
    -- Best retailer extraction (try all patterns in order)
    COALESCE(
      pattern_1_equals,
      pattern_2_in,
      pattern_3_join,
      pattern_4_like,
      pattern_5_cte,
      CASE 
        WHEN is_aggregate_query THEN 'ALL_RETAILERS'
        WHEN NOT has_retailer_moniker_field THEN 'NO_RETAILER_FIELD'
        ELSE 'UNMATCHED'
      END
    ) AS retailer_attribution,
    
    -- Attribution quality
    CASE
      WHEN pattern_1_equals IS NOT NULL THEN 'HIGH'  -- Direct equals
      WHEN pattern_2_in IS NOT NULL THEN 'HIGH'      -- IN clause
      WHEN pattern_3_join IS NOT NULL THEN 'MEDIUM'  -- Join condition
      WHEN pattern_4_like IS NOT NULL THEN 'MEDIUM'  -- LIKE pattern
      WHEN pattern_5_cte IS NOT NULL THEN 'MEDIUM'   -- CTE/Subquery
      WHEN is_aggregate_query THEN 'AGGREGATE'      -- Multi-retailer dashboard
      WHEN NOT has_retailer_moniker_field THEN 'NOT_APPLICABLE'  -- No retailer field
      ELSE 'FAILED'                                 -- Pattern extraction failed
    END AS attribution_quality,
    
    -- Which pattern succeeded
    CASE
      WHEN pattern_1_equals IS NOT NULL THEN 'EQUALS'
      WHEN pattern_2_in IS NOT NULL THEN 'IN'
      WHEN pattern_3_join IS NOT NULL THEN 'JOIN'
      WHEN pattern_4_like IS NOT NULL THEN 'LIKE'
      WHEN pattern_5_cte IS NOT NULL THEN 'CTE'
      WHEN is_aggregate_query THEN 'AGGREGATE_DASHBOARD'
      WHEN NOT has_retailer_moniker_field THEN 'NO_FIELD'
      ELSE 'NO_MATCH'
    END AS extraction_method
    
  FROM hub_with_retailer
)

-- ============================================================================
-- OUTPUT: Final Analysis Results
-- ============================================================================
SELECT
  -- Identifiers
  job_id,
  project_id,
  principal_email,
  analysis_period_label,
  
  -- Timing
  start_time,
  end_time,
  execution_time_seconds,
  EXTRACT(HOUR FROM start_time) AS hour_of_day,
  EXTRACT(DAYOFWEEK FROM start_time) AS day_of_week,
  FORMAT_TIMESTAMP('%A', start_time) AS day_name,
  DATE(start_time) AS job_date,
  
  -- Resource consumption
  approximate_slot_count,
  slot_hours,
  estimated_slot_cost_usd,
  ROUND(total_billed_bytes / POW(1024, 3), 2) AS gb_scanned,
  
  -- QoS metrics
  qos_status,
  is_qos_violation,
  qos_violation_seconds,
  
  -- Retailer attribution (PRIMARY OUTPUT)
  retailer_attribution,
  attribution_quality,
  extraction_method,
  
  -- Query characteristics
  LENGTH(COALESCE(full_query_text, query_text_sample)) AS query_length,
  REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)\bJOIN\b") AS has_joins,
  REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)\bGROUP BY\b") AS has_group_by,
  REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)\bWINDOW\b|OVER\s*\(") AS has_window_functions,
  REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)\bWITH\b") AS has_cte,
  
  -- Store query for review (first 1000 chars only to reduce size)
  SUBSTR(COALESCE(full_query_text, query_text_sample), 1, 1000) AS query_preview

FROM hub_classified

ORDER BY 
  analysis_period_label,
  start_time;

-- ============================================================================
-- SUMMARY STATISTICS (Uncomment to run separately)
-- ============================================================================
/*
SELECT
  analysis_period_label,
  
  -- Volume
  COUNT(*) AS total_queries,
  COUNT(DISTINCT principal_email) AS unique_users,
  COUNT(DISTINCT retailer_attribution) AS unique_retailers,
  
  -- Retailer attribution success
  COUNTIF(attribution_quality IN ('HIGH', 'MEDIUM')) AS successful_attributions,
  COUNTIF(attribution_quality = 'AGGREGATE') AS aggregate_dashboards,
  COUNTIF(attribution_quality = 'FAILED') AS failed_attributions,
  ROUND(COUNTIF(attribution_quality IN ('HIGH', 'MEDIUM')) / COUNT(*) * 100, 1) AS success_rate_pct,
  
  -- Extraction methods
  COUNTIF(extraction_method = 'EQUALS') AS method_equals,
  COUNTIF(extraction_method = 'IN') AS method_in,
  COUNTIF(extraction_method = 'JOIN') AS method_join,
  COUNTIF(extraction_method = 'LIKE') AS method_like,
  COUNTIF(extraction_method = 'CTE') AS method_cte,
  COUNTIF(extraction_method = 'AGGREGATE_DASHBOARD') AS aggregate_count,
  
  -- Performance
  ROUND(AVG(execution_time_seconds), 2) AS avg_exec_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_exec_seconds,
  ROUND(SUM(slot_hours), 2) AS total_slot_hours,
  ROUND(SUM(estimated_slot_cost_usd), 2) AS total_cost_usd,
  
  -- QoS
  COUNTIF(is_qos_violation) AS qos_violations,
  ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 1) AS violation_rate_pct

FROM hub_classified
GROUP BY analysis_period_label
ORDER BY analysis_period_label;
*/

