-- ============================================================================
-- Monitor Retailer Performance Profile Analysis
-- ============================================================================
-- Purpose: Analyze Monitor project performance by retailer for 2025 periods
-- Focus: Retailer-level QoS, costs, query patterns, and usage trends
-- Periods: Peak_2024_2025, Baseline_2025_Sep_Oct (recent data)
-- Note: Monitor projects = direct retailer API queries (not Hub dashboards)
-- ============================================================================

-- Configuration
DECLARE target_periods ARRAY<STRING> DEFAULT ['Peak_2024_2025', 'Baseline_2025_Sep_Oct'];

-- ============================================================================
-- MAIN ANALYSIS: Monitor Jobs by Retailer with Reservation Info
-- ============================================================================
WITH monitor_jobs AS (
  SELECT
    -- Identifiers
    job_id,
    project_id,
    principal_email,
    
    -- Period and retailer
    analysis_period_label,
    retailer_moniker,
    
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
    
    -- Keep original estimated cost for comparison
    estimated_slot_cost_usd as original_estimated_cost,
    
    -- QoS metrics
    qos_status,
    is_qos_violation,
    qos_violation_seconds,
    
    -- Query characteristics (from sample)
    query_text_sample,
    LENGTH(query_text_sample) AS query_sample_length,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bJOIN\b') AS has_joins,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bGROUP BY\b') AS has_group_by,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bWINDOW\b|OVER\s*\(') AS has_window_functions,
    REGEXP_CONTAINS(query_text_sample, r'(?i)\bWITH\b') AS has_cte
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE consumer_subcategory = 'MONITOR'  -- Direct retailer queries (not MONITOR_BASE)
    AND analysis_period_label IN UNNEST(target_periods)
    AND total_slot_ms IS NOT NULL
    AND retailer_moniker IS NOT NULL  -- Only attributed retailers
),

-- ============================================================================
-- AGGREGATION 1: Per-Retailer Performance Summary with Reservation Breakdown
-- ============================================================================
retailer_summary AS (
  SELECT
    analysis_period_label,
    retailer_moniker,
    
    -- Primary reservation type (most used by this retailer)
    APPROX_TOP_COUNT(reservation_type, 1)[OFFSET(0)].value AS primary_reservation_type,
    
    -- Reservation breakdown
    COUNTIF(reservation_type = 'RESERVED_SHARED_POOL') AS queries_on_reserved_shared,
    COUNTIF(reservation_type = 'RESERVED_PIPELINE') AS queries_on_reserved_pipeline,
    COUNTIF(reservation_type = 'ON_DEMAND') AS queries_on_demand,
    COUNTIF(reservation_type = 'UNKNOWN') AS queries_unknown_reservation,
    
    -- Volume metrics
    COUNT(*) AS total_queries,
    COUNT(DISTINCT DATE(start_time)) AS active_days,
    COUNT(DISTINCT project_id) AS project_count,
    
    -- Execution time metrics
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS p50_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
    ROUND(MAX(execution_time_seconds), 2) AS max_execution_seconds,
    
    -- Slot consumption metrics
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(AVG(slot_hours), 4) AS avg_slot_hours_per_query,
    ROUND(AVG(approximate_slot_count), 2) AS avg_concurrent_slots,
    ROUND(MAX(approximate_slot_count), 2) AS max_concurrent_slots,
    
    -- Cost metrics (CORRECTED based on reservation type)
    ROUND(SUM(actual_cost_usd), 2) AS total_cost_usd,
    ROUND(AVG(actual_cost_usd), 6) AS avg_cost_per_query_usd,
    
    -- Cost breakdown by reservation type
    ROUND(SUM(IF(reservation_type = 'RESERVED_SHARED_POOL', actual_cost_usd, 0)), 2) AS cost_reserved_shared,
    ROUND(SUM(IF(reservation_type = 'RESERVED_PIPELINE', actual_cost_usd, 0)), 2) AS cost_reserved_pipeline,
    ROUND(SUM(IF(reservation_type = 'ON_DEMAND', actual_cost_usd, 0)), 2) AS cost_on_demand,
    
    -- Data scanned metrics
    ROUND(SUM(total_billed_bytes) / POW(1024, 4), 2) AS total_tb_scanned,
    ROUND(AVG(total_billed_bytes) / POW(1024, 3), 2) AS avg_gb_per_query,
    
    -- QoS metrics
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct,
    ROUND(AVG(IF(is_qos_violation, qos_violation_seconds, NULL)), 2) AS avg_violation_seconds,
    
    -- QoS by reservation type
    ROUND(COUNTIF(is_qos_violation AND reservation_type = 'RESERVED_SHARED_POOL') / 
          NULLIF(COUNTIF(reservation_type = 'RESERVED_SHARED_POOL'), 0) * 100, 2) AS violation_pct_reserved_shared,
    ROUND(COUNTIF(is_qos_violation AND reservation_type = 'ON_DEMAND') / 
          NULLIF(COUNTIF(reservation_type = 'ON_DEMAND'), 0) * 100, 2) AS violation_pct_on_demand,
    
    -- Query complexity metrics
    COUNTIF(has_joins) AS queries_with_joins,
    COUNTIF(has_group_by) AS queries_with_group_by,
    COUNTIF(has_window_functions) AS queries_with_window_functions,
    COUNTIF(has_cte) AS queries_with_cte,
    ROUND(AVG(query_sample_length), 0) AS avg_query_length,
    
    -- Usage patterns
    ROUND(COUNT(*) / COUNT(DISTINCT DATE(start_time)), 2) AS avg_queries_per_day
    
  FROM monitor_jobs
  GROUP BY analysis_period_label, retailer_moniker
),

-- ============================================================================
-- AGGREGATION 2: Hourly Usage Patterns by Retailer
-- ============================================================================
hourly_patterns AS (
  SELECT
    analysis_period_label,
    retailer_moniker,
    hour_of_day,
    
    COUNT(*) AS queries,
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(SUM(actual_cost_usd), 2) AS total_cost_usd
    
  FROM monitor_jobs
  GROUP BY analysis_period_label, retailer_moniker, hour_of_day
),

-- ============================================================================
-- AGGREGATION 3: Daily Trends (Time Series)
-- ============================================================================
daily_trends AS (
  SELECT
    analysis_period_label,
    retailer_moniker,
    job_date,
    
    COUNT(*) AS queries,
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(SUM(actual_cost_usd), 2) AS total_cost_usd,
    COUNTIF(is_qos_violation) AS qos_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct
    
  FROM monitor_jobs
  GROUP BY analysis_period_label, retailer_moniker, job_date
),

-- ============================================================================
-- AGGREGATION 4: Top Expensive Queries per Retailer
-- ============================================================================
expensive_queries_per_retailer AS (
  SELECT
    analysis_period_label,
    retailer_moniker,
    reservation_type,
    job_id,
    start_time,
    execution_time_seconds,
    slot_hours,
    actual_cost_usd,
    approximate_slot_count,
    is_qos_violation,
    query_sample_length,
    has_joins,
    has_group_by,
    ROW_NUMBER() OVER (
      PARTITION BY analysis_period_label, retailer_moniker 
      ORDER BY actual_cost_usd DESC
    ) AS cost_rank_within_retailer
  FROM monitor_jobs
  QUALIFY cost_rank_within_retailer <= 5  -- Top 5 per retailer
),

-- ============================================================================
-- AGGREGATION 5: Overall Period Statistics (for context)
-- ============================================================================
period_stats AS (
  SELECT
    analysis_period_label,
    
    COUNT(*) AS total_queries,
    COUNT(DISTINCT retailer_moniker) AS unique_retailers,
    COUNT(DISTINCT project_id) AS unique_projects,
    
    ROUND(SUM(slot_hours), 2) AS total_slot_hours,
    ROUND(SUM(actual_cost_usd), 2) AS total_cost_usd,
    
    COUNTIF(is_qos_violation) AS total_violations,
    ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) AS violation_pct,
    
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    
    -- Reservation breakdown
    COUNTIF(reservation_type = 'RESERVED_SHARED_POOL') AS queries_reserved_shared,
    COUNTIF(reservation_type = 'RESERVED_PIPELINE') AS queries_reserved_pipeline,
    COUNTIF(reservation_type = 'ON_DEMAND') AS queries_on_demand
    
  FROM monitor_jobs
  GROUP BY analysis_period_label
)

-- ============================================================================
-- OUTPUT: Export Retailer Summary (Main Result)
-- ============================================================================
-- This query returns the per-retailer summary
-- To get other aggregations, uncomment the corresponding SELECT below

SELECT *
FROM retailer_summary
ORDER BY 
  analysis_period_label,
  total_slot_hours DESC;

-- ============================================================================
-- ALTERNATIVE OUTPUTS (uncomment as needed)
-- ============================================================================

-- Get period statistics:
-- SELECT * FROM period_stats ORDER BY analysis_period_label;

-- Get hourly patterns for top 10 retailers:
-- SELECT hp.* 
-- FROM hourly_patterns hp
-- INNER JOIN (
--   SELECT retailer_moniker, SUM(total_slot_hours) as total_slots
--   FROM retailer_summary
--   GROUP BY retailer_moniker
--   ORDER BY total_slots DESC
--   LIMIT 10
-- ) top_retailers ON hp.retailer_moniker = top_retailers.retailer_moniker
-- ORDER BY hp.analysis_period_label, top_retailers.total_slots DESC, hp.hour_of_day;

-- Get daily trends for specific retailer:
-- SELECT * FROM daily_trends 
-- WHERE retailer_moniker = 'rei'  -- Change to retailer of interest
-- ORDER BY analysis_period_label, job_date;

-- Get top expensive queries per retailer:
-- SELECT * FROM expensive_queries_per_retailer
-- ORDER BY analysis_period_label, retailer_moniker, cost_rank_within_retailer;

