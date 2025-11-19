<<<<<<< Current (Your changes)
=======
-- ============================================================================
-- PEAK VS NON-PEAK TRAFFIC ANALYSIS
-- ============================================================================
-- Purpose: Compare traffic patterns between peak periods (Nov-Jan) and
--          non-peak periods across multiple years to identify:
--          - Seasonal traffic increases
--          - Hour-of-day and day-of-week patterns
--          - Resource consumption differences by consumer category
--
-- This analysis covers 3 historical peak periods:
-- - Peak 2022-2023: Nov 1, 2022 - Jan 31, 2023
-- - Peak 2023-2024: Nov 1, 2023 - Jan 31, 2024
-- - Peak 2024-2025: Nov 1, 2024 - Jan 31, 2025
--
-- Cost estimate: ~20-50GB processed (full 3-year analysis)
-- Recommended: Run with dry_run first
-- ============================================================================

-- Configuration parameters - Analyze all available history
DECLARE analysis_start_date DATE DEFAULT '2022-04-19'; -- First available audit log date
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

-- TODO: Update with actual Airflow/Composer service accounts
DECLARE automated_service_accounts ARRAY<STRING> DEFAULT [
  'PLACEHOLDER_ACCOUNT@example.iam.gserviceaccount.com'
];

-- ============================================================================
-- MAIN QUERY: Peak vs Non-Peak Comparison
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
    
    -- Timing
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime AS start_time,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime AS end_time,
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
      SECOND
    ) AS execution_time_seconds,
    
    -- Resources
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
    
    -- Job type
    CASE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName
      WHEN 'query_job_completed' THEN 'QUERY'
      WHEN 'load_job_completed' THEN 'LOAD'
      WHEN 'extract_job_completed' THEN 'EXTRACT'
      WHEN 'table_copy_job_completed' THEN 'TABLE_COPY'
    END AS job_type,
    
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
    rm.retailer_moniker,
    
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
    
    -- Period classification
    CASE
      WHEN DATE(a.start_time) BETWEEN peak_2022_start AND peak_2022_end THEN 'Peak_2022_2023'
      WHEN DATE(a.start_time) BETWEEN peak_2023_start AND peak_2023_end THEN 'Peak_2023_2024'
      WHEN DATE(a.start_time) BETWEEN peak_2024_start AND peak_2024_end THEN 'Peak_2024_2025'
      ELSE 'Non_Peak'
    END AS period_type,
    
    -- Extract year for grouping
    EXTRACT(YEAR FROM a.start_time) AS year,
    
    -- Extract temporal dimensions
    EXTRACT(MONTH FROM a.start_time) AS month,
    EXTRACT(DAY FROM a.start_time) AS day,
    EXTRACT(HOUR FROM a.start_time) AS hour,
    EXTRACT(DAYOFWEEK FROM a.start_time) AS day_of_week, -- 1=Sunday, 7=Saturday
    FORMAT_DATE('%A', DATE(a.start_time)) AS day_name,
    
    -- Is peak period flag
    CASE
      WHEN DATE(a.start_time) BETWEEN peak_2022_start AND peak_2022_end THEN TRUE
      WHEN DATE(a.start_time) BETWEEN peak_2023_start AND peak_2023_end THEN TRUE
      WHEN DATE(a.start_time) BETWEEN peak_2024_start AND peak_2024_end THEN TRUE
      ELSE FALSE
    END AS is_peak_period,
    
    -- Cost
    ROUND(SAFE_DIVIDE(a.total_billed_bytes, POW(1024, 4)) * 5, 4) AS on_demand_cost_usd
    
  FROM audit_deduplicated a
  LEFT JOIN retailer_mappings rm ON a.project_id = rm.project_id
)

-- Aggregated comparison: Peak vs Non-Peak by category
SELECT
  period_type,
  consumer_category,
  
  -- Time range
  MIN(DATE(start_time)) AS period_start_date,
  MAX(DATE(start_time)) AS period_end_date,
  COUNT(DISTINCT DATE(start_time)) AS days_in_period,
  
  -- Volume metrics
  COUNT(*) AS total_jobs,
  ROUND(COUNT(*) / COUNT(DISTINCT DATE(start_time)), 2) AS avg_jobs_per_day,
  COUNT(DISTINCT principal_email) AS unique_users,
  COUNT(DISTINCT project_id) AS unique_projects,
  
  -- Job type breakdown
  COUNTIF(job_type = 'QUERY') AS query_jobs,
  COUNTIF(job_type = 'LOAD') AS load_jobs,
  COUNTIF(job_type = 'EXTRACT') AS extract_jobs,
  COUNTIF(job_type = 'TABLE_COPY') AS copy_jobs,
  
  -- Execution time statistics
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS median_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) AS p99_execution_seconds,
  MAX(execution_time_seconds) AS max_execution_seconds,
  
  -- Slot usage statistics
  SUM(total_slot_ms) AS total_slot_ms,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours,
  ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count,
  ROUND(APPROX_QUANTILES(approximate_slot_count, 100)[OFFSET(95)], 2) AS p95_slot_count,
  ROUND(MAX(approximate_slot_count), 2) AS max_slot_count,
  
  -- Slot hours per day
  ROUND(SUM(total_slot_ms) / 3600000 / COUNT(DISTINCT DATE(start_time)), 2) AS avg_slot_hours_per_day,
  
  -- Cost metrics
  SUM(on_demand_cost_usd) AS total_cost_usd,
  ROUND(SUM(on_demand_cost_usd) / COUNT(DISTINCT DATE(start_time)), 2) AS avg_cost_per_day_usd,
  ROUND(AVG(on_demand_cost_usd), 4) AS avg_cost_per_job_usd,
  
  -- Bytes processed
  SUM(total_billed_bytes) AS total_billed_bytes,
  ROUND(SUM(total_billed_bytes) / POW(1024, 4), 2) AS total_billed_tb

FROM traffic_classified
WHERE consumer_category != 'UNCLASSIFIED'
GROUP BY period_type, consumer_category
ORDER BY 
  CASE period_type
    WHEN 'Peak_2022_2023' THEN 1
    WHEN 'Peak_2023_2024' THEN 2
    WHEN 'Peak_2024_2025' THEN 3
    WHEN 'Non_Peak' THEN 4
  END,
  CASE consumer_category
    WHEN 'EXTERNAL' THEN 1
    WHEN 'AUTOMATED' THEN 2
    WHEN 'INTERNAL' THEN 3
  END;

-- ============================================================================
-- HOURLY PATTERN ANALYSIS (Uncomment for detailed time-of-day patterns)
-- ============================================================================
/*
SELECT
  period_type,
  consumer_category,
  hour,
  
  -- Volume
  COUNT(*) AS total_jobs,
  COUNT(DISTINCT DATE(start_time)) AS days_observed,
  ROUND(COUNT(*) / COUNT(DISTINCT DATE(start_time)), 2) AS avg_jobs_per_hour,
  
  -- Slots
  ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count,
  ROUND(APPROX_QUANTILES(approximate_slot_count, 100)[OFFSET(95)], 2) AS p95_slot_count,
  
  -- Slot hours
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours

FROM traffic_classified
WHERE consumer_category != 'UNCLASSIFIED'
  AND is_peak_period = TRUE  -- Focus on peak periods
GROUP BY period_type, consumer_category, hour
ORDER BY period_type, consumer_category, hour;
*/

-- ============================================================================
-- DAY OF WEEK PATTERN ANALYSIS (Uncomment for weekly patterns)
-- ============================================================================
/*
SELECT
  period_type,
  consumer_category,
  day_of_week,
  day_name,
  
  -- Volume
  COUNT(*) AS total_jobs,
  COUNT(DISTINCT DATE(start_time)) AS days_observed,
  ROUND(COUNT(*) / COUNT(DISTINCT DATE(start_time)), 2) AS avg_jobs_per_day,
  
  -- Slots
  ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours,
  
  -- Cost
  ROUND(SUM(on_demand_cost_usd), 2) AS total_cost_usd

FROM traffic_classified
WHERE consumer_category != 'UNCLASSIFIED'
  AND is_peak_period = TRUE
GROUP BY period_type, consumer_category, day_of_week, day_name
ORDER BY period_type, consumer_category, day_of_week;
*/
>>>>>>> Incoming (Background Agent changes)
