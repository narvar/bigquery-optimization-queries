-- ============================================================================
-- YEAR-OVER-YEAR GROWTH ANALYSIS
-- ============================================================================
-- Purpose: Calculate year-over-year growth rates across peak periods to:
--          - Identify traffic growth trends by consumer category
--          - Detect seasonality patterns and anomalies
--          - Project baseline growth rates for 2025 peak prediction
--          - Understand cost and resource consumption trends
--
-- Compares:
-- - Peak 2022-2023 vs Peak 2023-2024 (YoY growth rate 1)
-- - Peak 2023-2024 vs Peak 2024-2025 (YoY growth rate 2)
-- - Compound Annual Growth Rate (CAGR) across all periods
--
-- Cost estimate: ~20-40GB processed
-- ============================================================================

-- Configuration parameters
DECLARE analysis_start_date DATE DEFAULT '2022-11-01';
DECLARE analysis_end_date DATE DEFAULT CURRENT_DATE();

-- Peak period definitions
DECLARE peak_2022_start DATE DEFAULT '2022-11-01';
DECLARE peak_2022_end DATE DEFAULT '2023-01-31';
DECLARE peak_2023_start DATE DEFAULT '2023-11-01';
DECLARE peak_2023_end DATE DEFAULT '2024-01-31';
DECLARE peak_2024_start DATE DEFAULT '2024-11-01';
DECLARE peak_2024_end DATE DEFAULT '2025-01-31';

-- Service accounts for classification
DECLARE metabase_service_account STRING DEFAULT 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com';
DECLARE hub_service_account STRING DEFAULT 'looker-prod@narvar-data-lake.iam.gserviceaccount.com';
DECLARE automated_service_accounts ARRAY<STRING> DEFAULT [
  'PLACEHOLDER_ACCOUNT@example.iam.gserviceaccount.com'
];

-- ============================================================================
-- MAIN QUERY: Year-over-Year Growth Analysis by Category
-- ============================================================================

WITH
-- Retailer mappings
retailer_mappings AS (
  SELECT DISTINCT 
    retailer_moniker,
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-prod') AS project_id
  FROM `reporting.t_return_details` 
  WHERE DATE(return_created_date) >= '2022-01-01'
),

-- Extract audit log data
audit_data AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime AS start_time,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime AS end_time,
    
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
      SECOND
    ) AS execution_time_seconds,
    
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes AS total_billed_bytes,
    
    SAFE_DIVIDE(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
      TIMESTAMP_DIFF(
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
        MILLISECOND
      )
    ) AS approximate_slot_count,
    
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS row_num
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN analysis_start_date AND analysis_end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
),

-- Deduplicate
audit_deduplicated AS (
  SELECT * EXCEPT(row_num)
  FROM audit_data
  WHERE row_num = 1
),

-- Classify traffic
traffic_classified AS (
  SELECT
    a.*,
    
    -- Consumer category
    CASE
      WHEN rm.project_id IS NOT NULL OR a.project_id LIKE 'monitor-%' OR a.principal_email = hub_service_account 
        THEN 'EXTERNAL'
      WHEN a.principal_email IN UNNEST(automated_service_accounts) 
        OR LOWER(a.principal_email) LIKE '%airflow%' 
        OR LOWER(a.principal_email) LIKE '%composer%'
        OR LOWER(a.principal_email) LIKE '%cdp%' 
        OR LOWER(a.principal_email) LIKE '%dataflow%'
        THEN 'AUTOMATED'
      WHEN a.principal_email = metabase_service_account 
        OR a.principal_email NOT LIKE '%@%.iam.gserviceaccount.com'
        OR a.principal_email LIKE '%@%.iam.gserviceaccount.com'
        THEN 'INTERNAL'
      ELSE 'UNCLASSIFIED'
    END AS consumer_category,
    
    -- Peak period identification
    CASE
      WHEN DATE(a.start_time) BETWEEN peak_2022_start AND peak_2022_end THEN '2022_2023'
      WHEN DATE(a.start_time) BETWEEN peak_2023_start AND peak_2023_end THEN '2023_2024'
      WHEN DATE(a.start_time) BETWEEN peak_2024_start AND peak_2024_end THEN '2024_2025'
    END AS peak_period,
    
    -- Cost
    ROUND(SAFE_DIVIDE(a.total_billed_bytes, POW(1024, 4)) * 5, 4) AS on_demand_cost_usd
    
  FROM audit_deduplicated a
  LEFT JOIN retailer_mappings rm ON a.project_id = rm.project_id
  WHERE DATE(a.start_time) BETWEEN peak_2022_start AND peak_2024_end -- Only peak periods
),

-- Aggregate by peak period and category
period_aggregates AS (
  SELECT
    peak_period,
    consumer_category,
    
    -- Date range
    MIN(DATE(start_time)) AS period_start,
    MAX(DATE(start_time)) AS period_end,
    COUNT(DISTINCT DATE(start_time)) AS days_in_period,
    
    -- Volume metrics
    COUNT(*) AS total_jobs,
    ROUND(COUNT(*) / COUNT(DISTINCT DATE(start_time)), 2) AS avg_jobs_per_day,
    COUNT(DISTINCT principal_email) AS unique_users,
    COUNT(DISTINCT project_id) AS unique_projects,
    
    -- Performance metrics
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
    
    -- Slot metrics
    SUM(total_slot_ms) AS total_slot_ms,
    ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours,
    ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count,
    ROUND(APPROX_QUANTILES(approximate_slot_count, 100)[OFFSET(95)], 2) AS p95_slot_count,
    
    -- Slot hours per day
    ROUND(SUM(total_slot_ms) / 3600000 / COUNT(DISTINCT DATE(start_time)), 2) AS avg_slot_hours_per_day,
    
    -- Cost metrics
    SUM(on_demand_cost_usd) AS total_cost_usd,
    ROUND(SUM(on_demand_cost_usd) / COUNT(DISTINCT DATE(start_time)), 2) AS avg_cost_per_day_usd,
    
    -- Data volume
    SUM(total_billed_bytes) AS total_billed_bytes,
    ROUND(SUM(total_billed_bytes) / POW(1024, 4), 2) AS total_billed_tb
    
  FROM traffic_classified
  WHERE consumer_category != 'UNCLASSIFIED'
    AND peak_period IS NOT NULL
  GROUP BY peak_period, consumer_category
),

-- Calculate YoY growth rates
growth_calculations AS (
  SELECT
    consumer_category,
    
    -- 2022-2023 baseline
    MAX(IF(peak_period = '2022_2023', total_jobs, NULL)) AS jobs_2022,
    MAX(IF(peak_period = '2022_2023', avg_jobs_per_day, NULL)) AS jobs_per_day_2022,
    MAX(IF(peak_period = '2022_2023', total_slot_hours, NULL)) AS slot_hours_2022,
    MAX(IF(peak_period = '2022_2023', avg_slot_hours_per_day, NULL)) AS slot_hours_per_day_2022,
    MAX(IF(peak_period = '2022_2023', total_cost_usd, NULL)) AS cost_2022,
    MAX(IF(peak_period = '2022_2023', unique_users, NULL)) AS users_2022,
    
    -- 2023-2024 metrics
    MAX(IF(peak_period = '2023_2024', total_jobs, NULL)) AS jobs_2023,
    MAX(IF(peak_period = '2023_2024', avg_jobs_per_day, NULL)) AS jobs_per_day_2023,
    MAX(IF(peak_period = '2023_2024', total_slot_hours, NULL)) AS slot_hours_2023,
    MAX(IF(peak_period = '2023_2024', avg_slot_hours_per_day, NULL)) AS slot_hours_per_day_2023,
    MAX(IF(peak_period = '2023_2024', total_cost_usd, NULL)) AS cost_2023,
    MAX(IF(peak_period = '2023_2024', unique_users, NULL)) AS users_2023,
    
    -- 2024-2025 metrics
    MAX(IF(peak_period = '2024_2025', total_jobs, NULL)) AS jobs_2024,
    MAX(IF(peak_period = '2024_2025', avg_jobs_per_day, NULL)) AS jobs_per_day_2024,
    MAX(IF(peak_period = '2024_2025', total_slot_hours, NULL)) AS slot_hours_2024,
    MAX(IF(peak_period = '2024_2025', avg_slot_hours_per_day, NULL)) AS slot_hours_per_day_2024,
    MAX(IF(peak_period = '2024_2025', total_cost_usd, NULL)) AS cost_2024,
    MAX(IF(peak_period = '2024_2025', unique_users, NULL)) AS users_2024
    
  FROM period_aggregates
  GROUP BY consumer_category
)

-- Final output with YoY growth rates and projections
SELECT
  consumer_category,
  
  -- Historical metrics
  jobs_2022,
  jobs_2023,
  jobs_2024,
  
  -- YoY growth rates (jobs)
  ROUND(SAFE_DIVIDE(jobs_2023 - jobs_2022, jobs_2022) * 100, 2) AS yoy_growth_2022_2023_pct,
  ROUND(SAFE_DIVIDE(jobs_2024 - jobs_2023, jobs_2023) * 100, 2) AS yoy_growth_2023_2024_pct,
  
  -- Average YoY growth rate
  ROUND(((SAFE_DIVIDE(jobs_2023, jobs_2022) + SAFE_DIVIDE(jobs_2024, jobs_2023)) / 2 - 1) * 100, 2) AS avg_yoy_growth_pct,
  
  -- CAGR (Compound Annual Growth Rate) over 2 years
  ROUND((POW(SAFE_DIVIDE(jobs_2024, jobs_2022), 1/2) - 1) * 100, 2) AS cagr_2_year_pct,
  
  -- Slot hours growth
  slot_hours_2022,
  slot_hours_2023,
  slot_hours_2024,
  ROUND(SAFE_DIVIDE(slot_hours_2024 - slot_hours_2023, slot_hours_2023) * 100, 2) AS slot_hours_yoy_growth_pct,
  
  -- Slot hours per day growth
  slot_hours_per_day_2022,
  slot_hours_per_day_2023,
  slot_hours_per_day_2024,
  ROUND(SAFE_DIVIDE(slot_hours_per_day_2024 - slot_hours_per_day_2023, slot_hours_per_day_2023) * 100, 2) AS slot_hours_per_day_yoy_growth_pct,
  
  -- Cost growth
  cost_2022,
  cost_2023,
  cost_2024,
  ROUND(SAFE_DIVIDE(cost_2024 - cost_2023, cost_2023) * 100, 2) AS cost_yoy_growth_pct,
  
  -- User growth
  users_2022,
  users_2023,
  users_2024,
  ROUND(SAFE_DIVIDE(users_2024 - users_2023, users_2023) * 100, 2) AS users_yoy_growth_pct,
  
  -- Projected 2025-2026 peak (using average YoY growth rate)
  ROUND(jobs_2024 * (1 + ((SAFE_DIVIDE(jobs_2023, jobs_2022) + SAFE_DIVIDE(jobs_2024, jobs_2023)) / 2 - 1)), 0) AS projected_jobs_2025,
  ROUND(slot_hours_per_day_2024 * (1 + SAFE_DIVIDE(slot_hours_per_day_2024 - slot_hours_per_day_2023, slot_hours_per_day_2023)), 2) AS projected_slot_hours_per_day_2025,
  ROUND(cost_2024 * (1 + SAFE_DIVIDE(cost_2024 - cost_2023, cost_2023)), 2) AS projected_cost_2025,
  
  -- Growth volatility (standard deviation of growth rates)
  ROUND(STDDEV([
    SAFE_DIVIDE(jobs_2023 - jobs_2022, jobs_2022) * 100,
    SAFE_DIVIDE(jobs_2024 - jobs_2023, jobs_2023) * 100
  ]), 2) AS growth_volatility_stddev

FROM growth_calculations
ORDER BY 
  CASE consumer_category
    WHEN 'EXTERNAL' THEN 1
    WHEN 'AUTOMATED' THEN 2
    WHEN 'INTERNAL' THEN 3
  END;

-- ============================================================================
-- MONTHLY TREND ANALYSIS (Uncomment for detailed monthly patterns)
-- ============================================================================
/*
WITH
traffic_classified AS (
  -- Same classification logic as above
  SELECT
    a.*,
    CASE
      WHEN rm.project_id IS NOT NULL OR a.project_id LIKE 'monitor-%' OR a.principal_email = hub_service_account 
        THEN 'EXTERNAL'
      WHEN a.principal_email IN UNNEST(automated_service_accounts) 
        OR LOWER(a.principal_email) LIKE '%airflow%'
        THEN 'AUTOMATED'
      ELSE 'INTERNAL'
    END AS consumer_category,
    EXTRACT(YEAR FROM a.start_time) AS year,
    EXTRACT(MONTH FROM a.start_time) AS month
  FROM audit_deduplicated a
  LEFT JOIN retailer_mappings rm ON a.project_id = rm.project_id
)

SELECT
  consumer_category,
  year,
  month,
  COUNT(*) AS total_jobs,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours,
  SUM(on_demand_cost_usd) AS total_cost_usd
FROM traffic_classified
WHERE consumer_category != 'UNCLASSIFIED'
  AND DATE(start_time) BETWEEN peak_2022_start AND peak_2024_end
GROUP BY consumer_category, year, month
ORDER BY consumer_category, year, month;
*/

-- ============================================================================
-- ANOMALY DETECTION (Uncomment to identify unusual spikes/drops)
-- ============================================================================
/*
WITH
daily_metrics AS (
  SELECT
    DATE(start_time) AS date,
    consumer_category,
    COUNT(*) AS daily_jobs,
    SUM(total_slot_ms) / 3600000 AS daily_slot_hours
  FROM traffic_classified
  WHERE consumer_category != 'UNCLASSIFIED'
  GROUP BY date, consumer_category
),

stats_by_category AS (
  SELECT
    consumer_category,
    AVG(daily_jobs) AS avg_daily_jobs,
    STDDEV(daily_jobs) AS stddev_daily_jobs,
    AVG(daily_slot_hours) AS avg_daily_slot_hours,
    STDDEV(daily_slot_hours) AS stddev_daily_slot_hours
  FROM daily_metrics
  GROUP BY consumer_category
)

SELECT
  dm.date,
  dm.consumer_category,
  dm.daily_jobs,
  dm.daily_slot_hours,
  
  -- Z-score (standard deviations from mean)
  ROUND((dm.daily_jobs - s.avg_daily_jobs) / s.stddev_daily_jobs, 2) AS jobs_zscore,
  ROUND((dm.daily_slot_hours - s.avg_daily_slot_hours) / s.stddev_daily_slot_hours, 2) AS slot_hours_zscore,
  
  -- Anomaly flags (> 2 std devs)
  CASE 
    WHEN ABS((dm.daily_jobs - s.avg_daily_jobs) / s.stddev_daily_jobs) > 2 THEN TRUE 
    ELSE FALSE 
  END AS is_anomaly

FROM daily_metrics dm
JOIN stats_by_category s ON dm.consumer_category = s.consumer_category
WHERE ABS((dm.daily_jobs - s.avg_daily_jobs) / s.stddev_daily_jobs) > 2
ORDER BY ABS((dm.daily_jobs - s.avg_daily_jobs) / s.stddev_daily_jobs) DESC
LIMIT 50;
*/




