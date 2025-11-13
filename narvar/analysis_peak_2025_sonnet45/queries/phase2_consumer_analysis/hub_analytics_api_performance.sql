-- ============================================================================
-- Hub Analytics API Performance Analysis
-- ============================================================================
-- Purpose: Analyze Hub analytics dashboards (analytics-api-bigquery-access)
-- Consumer Subcategory: ANALYTICS_API (the REAL Hub analytics dashboards)
-- Periods: Peak_2024_2025, Baseline_2025_Sep_Oct
-- Note: Different from Looker (consumer_subcategory = 'HUB')
-- ============================================================================

-- Configuration
DECLARE target_periods ARRAY<STRING> DEFAULT ['Peak_2024_2025', 'Baseline_2025_Sep_Oct'];

-- ============================================================================
-- MAIN ANALYSIS: Hub Analytics API Jobs
-- ============================================================================
WITH hub_analytics_jobs AS (
  SELECT
    -- Identifiers
    job_id,
    project_id,
    principal_email,
    
    -- Period
    analysis_period_label,
    
    -- Reservation information
    reservation_name,
    CASE
      WHEN reservation_name = 'bq-narvar-admin:US.default' THEN 'RESERVED_SHARED_POOL'
      WHEN reservation_name = 'default-pipeline' THEN 'RESERVED_PIPELINE'
      WHEN reservation_name = 'unreserved' THEN 'ON_DEMAND'
      WHEN reservation_name IS NULL THEN 'UNKNOWN'
      ELSE reservation_name
    END as reservation_type,
    
    -- Timing
    start_time,
    end_time,
    execution_time_seconds,
    EXTRACT(HOUR FROM start_time) AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM start_time) AS day_of_week,
    FORMAT_TIMESTAMP('%A', start_time) AS day_name,
    DATE(start_time) AS job_date,
    
    -- Resource consumption
    total_slot_ms,
    approximate_slot_count,
    slot_hours,
    total_billed_bytes,
    
    -- Correct cost calculation based on reservation type
    CASE
      -- ON_DEMAND: Billed by TB processed at $6.25/TB
      WHEN reservation_name = 'unreserved' THEN 
        ROUND((total_billed_bytes / POW(1024, 4)) * 6.25, 4)
      -- RESERVED (both types): Billed by slot-hours at $0.0494/slot-hour
      ELSE 
        ROUND((total_slot_ms / 3600000) * 0.0494, 4)
    END as actual_cost_usd,
    
    -- QoS metrics (same 60-second threshold as Looker and Monitor)
    qos_status,
    is_qos_violation,
    qos_violation_seconds,
    
    -- Query characteristics
    query_text_sample,
    LENGTH(query_text_sample) AS query_sample_length,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bJOIN\b') AS has_joins,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bGROUP BY\b') AS has_group_by,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bWINDOW\b|OVER\s*\(') AS has_window_functions,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bWITH\b') AS has_cte
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE consumer_subcategory = 'ANALYTICS_API'  -- Real Hub analytics dashboards
    AND analysis_period_label IN UNNEST(target_periods)
    AND total_slot_ms IS NOT NULL
),

-- ============================================================================
-- AGGREGATION 1: Overall Period Statistics
-- ============================================================================
period_stats AS (
  SELECT
    analysis_period_label,
    
    -- Volume
    COUNT(*) AS total_queries,
    COUNT(DISTINCT principal_email) AS unique_users,
    COUNT(DISTINCT project_id) AS unique_projects,
    COUNT(DISTINCT DATE(start_time)) AS days_in_period,
    
    -- Execution time metrics
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
    ROUND(MAX(execution_time_seconds), 2) AS max_execution_seconds,
    
    -- Slot consumption
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots,
    
    -- Cost (corrected by reservation type)
    ROUND(SUM(actual_cost_usd), 2) AS total_cost_usd,
    ROUND(AVG(actual_cost_usd), 6) AS avg_cost_per_query_usd,
    
    -- Cost breakdown by reservation
    ROUND(SUM(IF(reservation_type = 'RESERVED_SHARED_POOL', actual_cost_usd, 0)), 2) AS cost_reserved_shared,
    ROUND(SUM(IF(reservation_type = 'ON_DEMAND', actual_cost_usd, 0)), 2) AS cost_on_demand,
    
    -- Data scanned
    ROUND(SUM(total_billed_bytes) / POW(1024, 4), 2) AS total_tb_scanned,
    ROUND(AVG(total_billed_bytes) / POW(1024, 3), 2) AS avg_gb_per_query,
    
    -- QoS metrics
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct,
    
    -- QoS by reservation type
    ROUND(COUNTIF(is_qos_violation AND reservation_type = 'RESERVED_SHARED_POOL') / 
          NULLIF(COUNTIF(reservation_type = 'RESERVED_SHARED_POOL'), 0) * 100, 2) AS violation_pct_reserved,
    ROUND(COUNTIF(is_qos_violation AND reservation_type = 'ON_DEMAND') / 
          NULLIF(COUNTIF(reservation_type = 'ON_DEMAND'), 0) * 100, 2) AS violation_pct_on_demand,
    
    -- Reservation breakdown
    COUNTIF(reservation_type = 'RESERVED_SHARED_POOL') AS queries_reserved_shared,
    COUNTIF(reservation_type = 'ON_DEMAND') AS queries_on_demand,
    COUNTIF(reservation_type = 'RESERVED_PIPELINE') AS queries_reserved_pipeline,
    
    -- Query complexity
    COUNTIF(has_joins) AS queries_with_joins,
    COUNTIF(has_group_by) AS queries_with_group_by,
    COUNTIF(has_window_functions) AS queries_with_window_functions,
    COUNTIF(has_cte) AS queries_with_cte,
    ROUND(AVG(query_sample_length), 0) AS avg_query_length
    
  FROM hub_analytics_jobs
  GROUP BY analysis_period_label
),

-- ============================================================================
-- AGGREGATION 2: Top 20 Most Expensive Queries
-- ============================================================================
expensive_queries AS (
  SELECT
    analysis_period_label,
    job_id,
    start_time,
    reservation_type,
    execution_time_seconds,
    slot_hours,
    actual_cost_usd,
    approximate_slot_count,
    ROUND(total_billed_bytes / POW(1024, 3), 2) AS gb_scanned,
    is_qos_violation,
    has_joins,
    has_group_by,
    has_cte,
    SUBSTR(query_text_sample, 1, 200) AS query_preview,
    ROW_NUMBER() OVER (PARTITION BY analysis_period_label ORDER BY actual_cost_usd DESC) AS cost_rank
  FROM hub_analytics_jobs
  QUALIFY cost_rank <= 20
),

-- ============================================================================
-- AGGREGATION 3: Hourly Usage Patterns
-- ============================================================================
hourly_patterns AS (
  SELECT
    analysis_period_label,
    hour_of_day,
    
    COUNT(*) AS queries,
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct,
    ROUND(SUM(actual_cost_usd), 2) AS total_cost_usd
    
  FROM hub_analytics_jobs
  GROUP BY analysis_period_label, hour_of_day
),

-- ============================================================================
-- AGGREGATION 4: Daily Time Series
-- ============================================================================
daily_time_series AS (
  SELECT
    analysis_period_label,
    job_date,
    
    COUNT(*) AS queries,
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(SUM(actual_cost_usd), 2) AS total_cost_usd,
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct
    
  FROM hub_analytics_jobs
  GROUP BY analysis_period_label, job_date
)

-- ============================================================================
-- OUTPUT: Period Statistics (Main Result)
-- ============================================================================
SELECT *
FROM period_stats
ORDER BY analysis_period_label;

-- ============================================================================
-- ALTERNATIVE OUTPUTS (uncomment as needed)
-- ============================================================================

-- Get top 20 expensive queries:
-- SELECT * FROM expensive_queries ORDER BY analysis_period_label, cost_rank;

-- Get hourly patterns:
-- SELECT * FROM hourly_patterns ORDER BY analysis_period_label, hour_of_day;

-- Get daily time series:
-- SELECT * FROM daily_time_series ORDER BY analysis_period_label, job_date;

