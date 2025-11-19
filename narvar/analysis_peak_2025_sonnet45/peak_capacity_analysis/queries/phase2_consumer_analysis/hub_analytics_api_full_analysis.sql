-- ============================================================================
-- Hub Analytics API Full 2025 Analysis with Retailer Attribution
-- ============================================================================
-- Purpose: Complete Hub Analytics API analysis with retailer extraction
-- Based on: Pattern discovery findings (80% success rate!)
-- Periods: Peak_2024_2025, Baseline_2025_Sep_Oct
-- Cost: ~40-50GB (includes audit log join for full query text)
-- ============================================================================

-- Configuration
DECLARE target_periods ARRAY<STRING> DEFAULT ['Peak_2024_2025', 'Baseline_2025_Sep_Oct'];

-- ============================================================================
-- STEP 1: Get Hub Analytics API Jobs from Classification Table
-- ============================================================================
WITH hub_analytics_jobs AS (
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
    query_text_sample,
    reservation_name
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE consumer_subcategory = 'ANALYTICS_API'
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
  FROM hub_analytics_jobs hj
  LEFT JOIN `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` audit
    ON hj.job_id = protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId
    AND DATE(audit.timestamp) = DATE(hj.start_time)  -- Partition pruning
  WHERE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
),

-- ============================================================================
-- STEP 3: Extract Retailer with Patterns (Based on 80% Success Rate)
-- ============================================================================
hub_with_retailer AS (
  SELECT
    *,
    
    -- Pattern 1: Standard equals (with optional parentheses) - 80% success rate
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
    COALESCE(
      REGEXP_EXTRACT(full_query_text, r"(?i)ON\s+.*?retailer[_\w]*\s*=\s*['\"]([^'\"]+)['\"]")
    ) AS pattern_3_join,
    
    -- Pattern 4: Comment metadata (-- retailer: value)
    REGEXP_EXTRACT(full_query_text, r"(?i)--\s*retailer[:\s]+([^\n,]+)") AS pattern_4_comment,
    
    -- Aggregate Query Detection (no specific retailer)
    CASE
      WHEN REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)GROUP\s+BY") 
        AND NOT REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)retailer_moniker\s*[=]")
        AND NOT REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)WHERE.*retailer")
      THEN TRUE
      ELSE FALSE
    END AS is_aggregate_query,
    
    -- Check if retailer_moniker exists anywhere
    REGEXP_CONTAINS(COALESCE(full_query_text, query_text_sample), r"(?i)retailer_moniker") AS has_retailer_moniker_field,
    
    -- Reservation type mapping
    CASE
      WHEN reservation_name = 'bq-narvar-admin:US.default' THEN 'RESERVED_SHARED_POOL'
      WHEN reservation_name = 'default-pipeline' THEN 'RESERVED_PIPELINE'
      WHEN reservation_name = 'unreserved' THEN 'ON_DEMAND'
      WHEN reservation_name IS NULL THEN 'UNKNOWN'
      ELSE reservation_name
    END as reservation_type,
    
    -- Correct cost calculation
    CASE
      WHEN reservation_name = 'unreserved' THEN 
        ROUND((total_billed_bytes / POW(1024, 4)) * 6.25, 4)
      ELSE 
        ROUND((total_slot_ms / 3600000) * 0.0494, 4)
    END as actual_cost_usd
    
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
      pattern_4_comment,
      CASE 
        WHEN is_aggregate_query THEN 'ALL_RETAILERS'
        WHEN NOT has_retailer_moniker_field THEN 'NO_RETAILER_FIELD'
        ELSE 'UNMATCHED'
      END
    ) AS retailer_attribution,
    
    -- Attribution quality
    CASE
      WHEN pattern_1_equals IS NOT NULL THEN 'HIGH'
      WHEN pattern_2_in IS NOT NULL THEN 'HIGH'
      WHEN pattern_3_join IS NOT NULL THEN 'MEDIUM'
      WHEN pattern_4_comment IS NOT NULL THEN 'MEDIUM'
      WHEN is_aggregate_query THEN 'AGGREGATE'
      WHEN NOT has_retailer_moniker_field THEN 'NOT_APPLICABLE'
      ELSE 'FAILED'
    END AS attribution_quality,
    
    -- Which pattern succeeded
    CASE
      WHEN pattern_1_equals IS NOT NULL THEN 'EQUALS'
      WHEN pattern_2_in IS NOT NULL THEN 'IN'
      WHEN pattern_3_join IS NOT NULL THEN 'JOIN'
      WHEN pattern_4_comment IS NOT NULL THEN 'COMMENT'
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
  actual_cost_usd,
  ROUND(total_billed_bytes / POW(1024, 3), 2) AS gb_scanned,
  
  -- Reservation info
  reservation_type,
  
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

