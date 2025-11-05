-- ============================================================================
-- AUDIT LOG COMPLETENESS VALIDATION
-- ============================================================================
-- Purpose: Validate that audit log data is complete and consistent for the
--          3 historical peak periods (Nov-Jan 2022/23, 2023/24, 2024/25)
--
-- Expected output: Daily record counts, gap detection, data quality metrics
-- Cost estimate: ~1-5GB processed (depends on date range)
-- ============================================================================

-- Configuration parameters
-- TEST PERIOD: Oct-Nov 2024 (2 months for initial validation)
-- For full 3-year analysis, change to: '2022-04-19' and CURRENT_DATE()
DECLARE start_date DATE DEFAULT '2024-10-01';
DECLARE end_date DATE DEFAULT '2024-11-30';

-- Peak period definitions
DECLARE peak_2022_start DATE DEFAULT '2022-11-01';
DECLARE peak_2022_end DATE DEFAULT '2023-01-31';
DECLARE peak_2023_start DATE DEFAULT '2023-11-01';
DECLARE peak_2023_end DATE DEFAULT '2024-01-31';
DECLARE peak_2024_start DATE DEFAULT '2024-11-01';
DECLARE peak_2024_end DATE DEFAULT '2025-01-31';

-- ============================================================================
-- MAIN QUERY: Daily audit log statistics with gap detection
-- ============================================================================

WITH 
-- Generate continuous date range for comparison
date_spine AS (
  SELECT date_day
  FROM UNNEST(GENERATE_DATE_ARRAY(start_date, end_date, INTERVAL 1 DAY)) AS date_day
),

-- Aggregate audit log data by day
daily_stats AS (
  SELECT
    DATE(timestamp) AS log_date,
    COUNT(*) AS total_records,
    COUNT(DISTINCT protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId) AS unique_jobs,
    COUNT(DISTINCT protopayload_auditlog.authenticationInfo.principalEmail) AS unique_users,
    COUNT(DISTINCT protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId) AS unique_projects,
    
    -- Job type breakdown
    COUNTIF(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed') AS query_jobs,
    COUNTIF(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'load_job_completed') AS load_jobs,
    COUNTIF(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'extract_job_completed') AS extract_jobs,
    COUNTIF(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'table_copy_job_completed') AS copy_jobs,
    
    -- Slot usage aggregates
    SUM(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs) AS total_slot_ms,
    SUM(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes) AS total_billed_bytes,
    
    -- Data quality indicators
    COUNTIF(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs IS NULL) AS null_slot_records,
    COUNTIF(protopayload_auditlog.authenticationInfo.principalEmail IS NULL OR protopayload_auditlog.authenticationInfo.principalEmail = '') AS null_user_records
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN start_date AND end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
  GROUP BY log_date
),

-- Join with date spine to identify gaps
data_with_gaps AS (
  SELECT
    ds.date_day,
    COALESCE(s.total_records, 0) AS total_records,
    COALESCE(s.unique_jobs, 0) AS unique_jobs,
    COALESCE(s.unique_users, 0) AS unique_users,
    COALESCE(s.unique_projects, 0) AS unique_projects,
    COALESCE(s.query_jobs, 0) AS query_jobs,
    COALESCE(s.load_jobs, 0) AS load_jobs,
    COALESCE(s.extract_jobs, 0) AS extract_jobs,
    COALESCE(s.copy_jobs, 0) AS copy_jobs,
    COALESCE(s.total_slot_ms, 0) AS total_slot_ms,
    COALESCE(s.total_billed_bytes, 0) AS total_billed_bytes,
    COALESCE(s.null_slot_records, 0) AS null_slot_records,
    COALESCE(s.null_user_records, 0) AS null_user_records,
    
    -- Classify into peak periods
    CASE
      WHEN ds.date_day BETWEEN peak_2022_start AND peak_2022_end THEN 'Peak_2022_2023'
      WHEN ds.date_day BETWEEN peak_2023_start AND peak_2023_end THEN 'Peak_2023_2024'
      WHEN ds.date_day BETWEEN peak_2024_start AND peak_2024_end THEN 'Peak_2024_2025'
      ELSE 'Non_Peak'
    END AS period_classification,
    
    -- Gap detection flags
    CASE WHEN s.total_records IS NULL OR s.total_records = 0 THEN TRUE ELSE FALSE END AS is_gap,
    CASE WHEN s.total_records > 0 AND s.total_records < 1000 THEN TRUE ELSE FALSE END AS is_suspiciously_low,
    
    -- Data quality flags
    CASE 
      WHEN s.total_records > 0 AND SAFE_DIVIDE(s.null_slot_records, s.total_records) > 0.1 THEN TRUE 
      ELSE FALSE 
    END AS high_null_slot_rate,
    CASE 
      WHEN s.total_records > 0 AND SAFE_DIVIDE(s.null_user_records, s.total_records) > 0.1 THEN TRUE 
      ELSE FALSE 
    END AS high_null_user_rate
    
  FROM date_spine ds
  LEFT JOIN daily_stats s ON ds.date_day = s.log_date
)

-- Final output with comprehensive daily statistics
SELECT
  date_day,
  period_classification,
  total_records,
  unique_jobs,
  unique_users,
  unique_projects,
  query_jobs,
  load_jobs,
  extract_jobs,
  copy_jobs,
  ROUND(total_slot_ms / 1000000, 2) AS total_slot_hours,
  ROUND(total_billed_bytes / POW(1024, 4), 2) AS total_billed_tb,
  
  -- Data quality metrics
  null_slot_records,
  null_user_records,
  ROUND(SAFE_DIVIDE(null_slot_records, total_records) * 100, 2) AS pct_null_slot,
  ROUND(SAFE_DIVIDE(null_user_records, total_records) * 100, 2) AS pct_null_user,
  
  -- Gap and quality flags
  is_gap,
  is_suspiciously_low,
  high_null_slot_rate,
  high_null_user_rate,
  
  -- Day of week for pattern analysis
  FORMAT_DATE('%A', date_day) AS day_of_week
  
FROM data_with_gaps
ORDER BY date_day DESC;

-- ============================================================================
-- SUMMARY STATISTICS BY PEAK PERIOD
-- ============================================================================
-- Uncomment the section below to get summary statistics instead of daily details
/*
WITH 
date_spine AS (
  SELECT date_day
  FROM UNNEST(GENERATE_DATE_ARRAY(start_date, end_date, INTERVAL 1 DAY)) AS date_day
),

daily_stats AS (
  SELECT
    DATE(timestamp) AS log_date,
    COUNT(*) AS total_records,
    COUNT(DISTINCT protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId) AS unique_jobs,
    SUM(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs) AS total_slot_ms
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN start_date AND end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
  GROUP BY log_date
),

data_with_gaps AS (
  SELECT
    ds.date_day,
    COALESCE(s.total_records, 0) AS total_records,
    COALESCE(s.unique_jobs, 0) AS unique_jobs,
    COALESCE(s.total_slot_ms, 0) AS total_slot_ms,
    CASE
      WHEN ds.date_day BETWEEN peak_2022_start AND peak_2022_end THEN 'Peak_2022_2023'
      WHEN ds.date_day BETWEEN peak_2023_start AND peak_2023_end THEN 'Peak_2023_2024'
      WHEN ds.date_day BETWEEN peak_2024_start AND peak_2024_end THEN 'Peak_2024_2025'
      ELSE 'Non_Peak'
    END AS period_classification,
    CASE WHEN s.total_records IS NULL OR s.total_records = 0 THEN TRUE ELSE FALSE END AS is_gap
  FROM date_spine ds
  LEFT JOIN daily_stats s ON ds.date_day = s.log_date
)

SELECT
  period_classification,
  COUNT(*) AS total_days,
  COUNTIF(is_gap) AS days_with_gaps,
  COUNTIF(NOT is_gap) AS days_with_data,
  ROUND(COUNTIF(is_gap) / COUNT(*) * 100, 2) AS pct_days_with_gaps,
  SUM(total_records) AS total_audit_records,
  SUM(unique_jobs) AS total_unique_jobs,
  ROUND(AVG(total_records), 0) AS avg_records_per_day,
  ROUND(AVG(unique_jobs), 0) AS avg_jobs_per_day,
  ROUND(SUM(total_slot_ms) / 1000000 / 3600, 2) AS total_slot_hours,
  MIN(date_day) AS period_start,
  MAX(date_day) AS period_end
FROM data_with_gaps
WHERE period_classification != 'Non_Peak'
GROUP BY period_classification
ORDER BY period_classification;
*/
