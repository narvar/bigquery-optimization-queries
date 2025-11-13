-- ============================================================================
-- HUB QoS Deep Dive Analysis
-- ============================================================================
-- Purpose: Investigate 39.4% violation rate during Peak_2024_2025 CRITICAL stress
-- Critical Finding: Hub is 44x slower than Monitor (P95: 1,521s vs 34s)
-- Focus: Recent periods (Peak_2024_2025, Baseline_2025_Sep_Oct)
-- ============================================================================

-- Configuration
DECLARE target_periods ARRAY<STRING> DEFAULT ['Peak_2024_2025', 'Baseline_2025_Sep_Oct'];

-- ============================================================================
-- MAIN ANALYSIS: Hub Job Details
-- ============================================================================
WITH hub_jobs AS (
  SELECT
    -- Identifiers
    job_id,
    project_id,
    principal_email,
    
    -- Period classification
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
    total_slot_ms,
    approximate_slot_count,
    slot_hours,
    total_billed_bytes,
    estimated_slot_cost_usd,
    
    -- QoS metrics
    qos_status,
    is_qos_violation,
    qos_violation_seconds,
    
    -- Query information
    query_text_sample,
    
    -- Query complexity indicators (derived from available fields)
    LENGTH(query_text_sample) AS query_text_length,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bJOIN\b') AS has_joins,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bGROUP BY\b') AS has_group_by,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bWINDOW\b|OVER\s*\(') AS has_window_functions,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bWITH\b') AS has_cte,
    
    -- Calculate complexity score (0-5)
    (
      CAST(REGEXP_CONTAINS(query_text_sample, r'(?i)\bJOIN\b') AS INT64) +
      CAST(REGEXP_CONTAINS(query_text_sample, r'(?i)\bGROUP BY\b') AS INT64) +
      CAST(REGEXP_CONTAINS(query_text_sample, r'(?i)\bWINDOW\b|OVER\s*\(') AS INT64) +
      CAST(REGEXP_CONTAINS(query_text_sample, r'(?i)\bWITH\b') AS INT64) +
      CAST(LENGTH(query_text_sample) > 400 AS INT64)
    ) AS query_complexity_score
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE consumer_subcategory = 'HUB'
    AND analysis_period_label IN UNNEST(target_periods)
    AND total_slot_ms IS NOT NULL  -- Filter null slots per project standards
),

-- ============================================================================
-- AGGREGATION 1: Overall Period Statistics
-- ============================================================================
period_stats AS (
  SELECT
    analysis_period_label,
    
    -- Volume metrics
    COUNT(*) AS total_jobs,
    COUNT(DISTINCT principal_email) AS unique_users,
    COUNT(DISTINCT project_id) AS unique_projects,
    COUNT(DISTINCT DATE(start_time)) AS days_in_period,
    
    -- Execution time metrics
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
    ROUND(MAX(execution_time_seconds), 2) AS max_execution_seconds,
    
    -- Slot consumption metrics
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(AVG(slot_hours), 4) AS avg_slot_hours_per_job,
    ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots,
    ROUND(MAX(approximate_slot_count), 2) AS max_concurrent_slots,
    
    -- Cost metrics
    ROUND(SUM(estimated_slot_cost_usd), 2) AS total_cost_usd,
    ROUND(AVG(estimated_slot_cost_usd), 4) AS avg_cost_per_job_usd,
    
    -- Data scanned metrics
    ROUND(SUM(total_billed_bytes) / POW(1024, 4), 2) AS total_tb_scanned,
    ROUND(AVG(total_billed_bytes) / POW(1024, 3), 2) AS avg_gb_per_job,
    
    -- QoS metrics
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct,
    ROUND(AVG(IF(is_qos_violation, qos_violation_seconds, NULL)), 2) AS avg_violation_seconds,
    
    -- Query complexity metrics
    ROUND(AVG(query_complexity_score), 2) AS avg_complexity_score,
    COUNTIF(has_joins) AS jobs_with_joins,
    COUNTIF(has_group_by) AS jobs_with_group_by,
    COUNTIF(has_window_functions) AS jobs_with_window_functions,
    COUNTIF(has_cte) AS jobs_with_cte,
    
    -- Usage patterns
    ROUND(COUNT(*) / COUNT(DISTINCT DATE(start_time)), 2) AS avg_jobs_per_day,
    ROUND(COUNT(*) / COUNT(DISTINCT principal_email), 2) AS avg_jobs_per_user
    
  FROM hub_jobs
  GROUP BY analysis_period_label
),

-- ============================================================================
-- AGGREGATION 2: Top 20 Slowest Queries
-- ============================================================================
slowest_queries AS (
  SELECT
    analysis_period_label,
    job_id,
    start_time,
    principal_email,
    execution_time_seconds,
    approximate_slot_count,
    slot_hours,
    estimated_slot_cost_usd,
    ROUND(total_billed_bytes / POW(1024, 3), 2) AS gb_scanned,
    is_qos_violation,
    qos_violation_seconds,
    query_complexity_score,
    has_joins,
    has_group_by,
    has_window_functions,
    has_cte,
    query_text_sample,
    ROW_NUMBER() OVER (PARTITION BY analysis_period_label ORDER BY execution_time_seconds DESC) AS rank_in_period
  FROM hub_jobs
  WHERE execution_time_seconds > 60  -- Only queries exceeding SLA threshold
  QUALIFY rank_in_period <= 20
),

-- ============================================================================
-- AGGREGATION 3: User Activity Analysis
-- ============================================================================
user_activity AS (
  SELECT
    analysis_period_label,
    principal_email,
    
    -- Volume
    COUNT(*) AS total_jobs,
    COUNT(DISTINCT DATE(start_time)) AS active_days,
    
    -- Performance
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    
    -- Resources
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(SUM(estimated_slot_cost_usd), 2) AS total_cost_usd,
    
    -- QoS
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct,
    
    -- Complexity
    ROUND(AVG(query_complexity_score), 2) AS avg_complexity_score,
    
    ROW_NUMBER() OVER (PARTITION BY analysis_period_label ORDER BY SUM(slot_hours) DESC) AS rank_by_slots,
    ROW_NUMBER() OVER (PARTITION BY analysis_period_label ORDER BY COUNTIF(is_qos_violation) DESC) AS rank_by_violations
    
  FROM hub_jobs
  GROUP BY analysis_period_label, principal_email
),

-- ============================================================================
-- AGGREGATION 4: Hourly Usage Patterns
-- ============================================================================
hourly_patterns AS (
  SELECT
    analysis_period_label,
    hour_of_day,
    
    -- Volume
    COUNT(*) AS jobs,
    ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots,
    
    -- Performance
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    
    -- QoS
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct,
    
    -- Cost
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(SUM(estimated_slot_cost_usd), 2) AS total_cost_usd
    
  FROM hub_jobs
  GROUP BY analysis_period_label, hour_of_day
),

-- ============================================================================
-- AGGREGATION 5: Daily Usage Patterns
-- ============================================================================
daily_patterns AS (
  SELECT
    analysis_period_label,
    day_of_week,
    day_name,
    
    -- Volume
    COUNT(*) AS jobs,
    ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots,
    
    -- Performance
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    
    -- QoS
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct,
    
    -- Cost
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(SUM(estimated_slot_cost_usd), 2) AS total_cost_usd
    
  FROM hub_jobs
  GROUP BY analysis_period_label, day_of_week, day_name
),

-- ============================================================================
-- AGGREGATION 6: Time Series (Daily Trends)
-- ============================================================================
daily_time_series AS (
  SELECT
    analysis_period_label,
    job_date,
    
    -- Volume
    COUNT(*) AS jobs,
    COUNT(DISTINCT principal_email) AS unique_users,
    
    -- Performance
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    
    -- Resources
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots,
    
    -- QoS
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct,
    
    -- Cost
    ROUND(SUM(estimated_slot_cost_usd), 2) AS total_cost_usd
    
  FROM hub_jobs
  GROUP BY analysis_period_label, job_date
),

-- ============================================================================
-- AGGREGATION 7: Query Complexity vs QoS Performance
-- ============================================================================
complexity_qos AS (
  SELECT
    analysis_period_label,
    query_complexity_score,
    
    -- Volume
    COUNT(*) AS jobs,
    
    -- Performance
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    
    -- QoS
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct,
    
    -- Resources
    ROUND(AVG(slot_hours), 4) AS avg_slot_hours,
    ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots
    
  FROM hub_jobs
  GROUP BY analysis_period_label, query_complexity_score
),

-- ============================================================================
-- AGGREGATION 8: Most Expensive Queries (Top 20 by Cost)
-- ============================================================================
expensive_queries AS (
  SELECT
    analysis_period_label,
    job_id,
    start_time,
    principal_email,
    execution_time_seconds,
    slot_hours,
    estimated_slot_cost_usd,
    approximate_slot_count,
    ROUND(total_billed_bytes / POW(1024, 3), 2) AS gb_scanned,
    is_qos_violation,
    query_complexity_score,
    query_text_sample,
    ROW_NUMBER() OVER (PARTITION BY analysis_period_label ORDER BY estimated_slot_cost_usd DESC) AS rank_in_period
  FROM hub_jobs
  QUALIFY rank_in_period <= 20
)

-- ============================================================================
-- OUTPUT: Combine all results for export
-- ============================================================================
-- Note: BigQuery doesn't support multiple result sets in one query
-- We'll export each CTE separately or union them with identifiers

-- Export Period Stats
SELECT 'period_stats' AS result_type, TO_JSON_STRING(t) AS data
FROM period_stats t

UNION ALL

-- Export Slowest Queries metadata (not full query text - too large)
SELECT 'slowest_queries' AS result_type, TO_JSON_STRING(STRUCT(
  analysis_period_label,
  job_id,
  CAST(start_time AS STRING) AS start_time,
  principal_email,
  execution_time_seconds,
  approximate_slot_count,
  slot_hours,
  estimated_slot_cost_usd,
  gb_scanned,
  is_qos_violation,
  qos_violation_seconds,
  query_complexity_score,
  has_joins,
  has_group_by,
  has_window_functions,
  has_cte,
  rank_in_period,
  SUBSTR(query_text_sample, 1, 200) AS query_preview  -- First 200 chars only
)) AS data
FROM slowest_queries

UNION ALL

-- Export User Activity (top 10 per period)
SELECT 'user_activity' AS result_type, TO_JSON_STRING(t) AS data
FROM user_activity t
WHERE rank_by_slots <= 10 OR rank_by_violations <= 10

UNION ALL

-- Export Hourly Patterns
SELECT 'hourly_patterns' AS result_type, TO_JSON_STRING(t) AS data
FROM hourly_patterns t

UNION ALL

-- Export Daily Patterns
SELECT 'daily_patterns' AS result_type, TO_JSON_STRING(t) AS data
FROM daily_patterns t

UNION ALL

-- Export Daily Time Series
SELECT 'daily_time_series' AS result_type, TO_JSON_STRING(STRUCT(
  analysis_period_label,
  CAST(job_date AS STRING) AS job_date,
  jobs,
  unique_users,
  avg_execution_seconds,
  p95_execution_seconds,
  total_slot_hours,
  avg_concurrent_slots,
  qos_violations,
  violation_pct,
  total_cost_usd
)) AS data
FROM daily_time_series t

UNION ALL

-- Export Complexity vs QoS
SELECT 'complexity_qos' AS result_type, TO_JSON_STRING(t) AS data
FROM complexity_qos t

UNION ALL

-- Export Expensive Queries metadata
SELECT 'expensive_queries' AS result_type, TO_JSON_STRING(STRUCT(
  analysis_period_label,
  job_id,
  CAST(start_time AS STRING) AS start_time,
  principal_email,
  execution_time_seconds,
  slot_hours,
  estimated_slot_cost_usd,
  approximate_slot_count,
  gb_scanned,
  is_qos_violation,
  query_complexity_score,
  rank_in_period,
  SUBSTR(query_text_sample, 1, 200) AS query_preview
)) AS data
FROM expensive_queries

ORDER BY result_type, data;

