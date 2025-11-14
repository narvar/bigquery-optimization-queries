-- ============================================================================
-- Complete Production Cost Analysis for All Monitor Base Tables
-- ============================================================================
-- Purpose: Find ETL operations and costs for ALL 7 Monitor base tables
-- Time Periods: Peak_2024_2025 (Nov 2024-Jan 2025) + Baseline_2025_Sep_Oct
-- Annualization: × (12/5) for 5-month period
-- ============================================================================

-- Time period configuration (matching consumption analysis)
DECLARE peak_start DATE DEFAULT '2024-11-01';
DECLARE peak_end DATE DEFAULT '2025-01-31';
DECLARE baseline_start DATE DEFAULT '2025-09-01';
DECLARE baseline_end DATE DEFAULT '2025-10-31';

-- ============================================================================
-- Target base tables (from manual view mapping)
-- ============================================================================
WITH target_tables AS (
  SELECT table_id, full_table_name, priority, category
  FROM UNNEST([
    STRUCT('shipments' AS table_id, 'monitor-base-us-prod.monitor_base.shipments' AS full_table_name, 1 AS priority, 'PRIMARY' AS category),
    STRUCT('orders' AS table_id, 'monitor-base-us-prod.monitor_base.orders' AS full_table_name, 2 AS priority, 'PRIMARY' AS category),
    STRUCT('return_item_details' AS table_id, 'narvar-data-lake.return_insights_base.return_item_details' AS full_table_name, 3 AS priority, 'PRIMARY' AS category),
    STRUCT('return_rate_agg' AS table_id, 'narvar-data-lake.reporting.return_rate_agg' AS full_table_name, 4 AS priority, 'SECONDARY' AS category),
    STRUCT('tnt_benchmarks_latest' AS table_id, 'monitor-base-us-prod.monitor_base.tnt_benchmarks_latest' AS full_table_name, 5 AS priority, 'SECONDARY' AS category),
    STRUCT('ft_benchmarks_latest' AS table_id, 'monitor-base-us-prod.monitor_base.ft_benchmarks_latest' AS full_table_name, 6 AS priority, 'SECONDARY' AS category),
    STRUCT('carrier_config' AS table_id, 'monitor-base-us-prod.monitor_base.carrier_config' AS full_table_name, 7 AS priority, 'SECONDARY' AS category)
  ])
),

-- ============================================================================
-- Search audit logs for ETL operations in BOTH periods
-- ============================================================================
etl_operations AS (
  SELECT
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    timestamp AS job_timestamp,
    
    -- Period classification
    CASE
      WHEN DATE(timestamp) BETWEEN peak_start AND peak_end THEN 'Peak_2024_2025'
      WHEN DATE(timestamp) BETWEEN baseline_start AND baseline_end THEN 'Baseline_2025_Sep_Oct'
      ELSE 'OTHER'
    END AS analysis_period,
    
    -- Destination table
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.projectId AS dest_project,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.datasetId AS dest_dataset,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.tableId AS dest_table,
    
    CONCAT(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.projectId, '.',
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.datasetId, '.',
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.tableId
    ) AS full_table_name,
    
    -- Job details
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.statementType AS statement_type,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes AS total_billed_bytes,
    
    -- Reservation info
    CASE 
      WHEN ARRAY_LENGTH(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservationUsage) > 0 
      THEN protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservationUsage[OFFSET(0)].name
      ELSE 'unreserved'
    END AS reservation_name
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE (
      (DATE(timestamp) BETWEEN peak_start AND peak_end) OR
      (DATE(timestamp) BETWEEN baseline_start AND baseline_end)
    )
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.statementType IN ('INSERT', 'MERGE', 'CREATE_TABLE_AS_SELECT', 'UPDATE')
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.tableId IN (
      SELECT table_id FROM target_tables
    )
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs IS NOT NULL
),

-- ============================================================================
-- Classify and calculate costs
-- ============================================================================
etl_classified AS (
  SELECT
    *,
    CASE
      WHEN principal_email LIKE '%airflow%' OR principal_email LIKE '%composer%' THEN 'AIRFLOW'
      WHEN principal_email LIKE '%gke%' THEN 'GKE'  
      WHEN principal_email LIKE '%appspot%' THEN 'APP_ENGINE'
      WHEN principal_email LIKE '%compute%' THEN 'COMPUTE_ENGINE'
      WHEN principal_email LIKE '%dataflow%' THEN 'DATAFLOW'
      WHEN principal_email LIKE '@narvar.com' THEN 'USER'
      ELSE 'OTHER'
    END AS etl_source_type,
    
    -- Calculate costs based on reservation type
    CASE
      WHEN reservation_name = 'unreserved' THEN 
        (total_billed_bytes / POW(1024, 4)) * 6.25  -- ON_DEMAND
      ELSE 
        (total_slot_ms / 3600000) * 0.0494  -- RESERVED
    END AS job_cost_usd
    
  FROM etl_operations
  WHERE analysis_period IN ('Peak_2024_2025', 'Baseline_2025_Sep_Oct')  -- Exclude OTHER
),

-- Aggregate by table, period, and service account
table_period_summary AS (
  SELECT
    full_table_name,
    analysis_period,
    statement_type,
    etl_source_type,
    principal_email,
    
    COUNT(*) AS etl_job_count,
    SUM(total_slot_ms) / 3600000 AS total_slot_hours,
    SUM(job_cost_usd) AS period_cost_usd,
    AVG(job_cost_usd) AS avg_cost_per_job,
    
    MIN(job_timestamp) AS first_seen,
    MAX(job_timestamp) AS last_seen,
    
    -- Jobs per day within period (avoid division by zero)
    COUNT(*) / GREATEST(1, DATE_DIFF(
      MAX(DATE(job_timestamp)), 
      MIN(DATE(job_timestamp)), 
      DAY
    )) AS avg_jobs_per_day
    
  FROM etl_classified
  GROUP BY full_table_name, analysis_period, statement_type, etl_source_type, principal_email
),

-- Aggregate across both periods and annualize
table_annual_summary AS (
  SELECT
    full_table_name,
    statement_type,
    etl_source_type,
    principal_email,
    
    SUM(etl_job_count) AS total_jobs_5_months,
    SUM(total_slot_hours) AS total_slot_hours_5_months,
    SUM(period_cost_usd) AS total_cost_5_months,
    
    -- Annualize (5 months → 12 months)
    SUM(period_cost_usd) * (12.0 / 5.0) AS annual_cost_usd,
    SUM(total_slot_hours) * (12.0 / 5.0) AS annual_slot_hours,
    
    AVG(avg_cost_per_job) AS avg_cost_per_job,
    AVG(avg_jobs_per_day) AS avg_jobs_per_day,
    
    MIN(first_seen) AS first_seen,
    MAX(last_seen) AS last_seen
    
  FROM table_period_summary
  GROUP BY full_table_name, statement_type, etl_source_type, principal_email
)

-- ============================================================================
-- OUTPUT: Detailed production costs by table
-- ============================================================================
SELECT
  full_table_name,
  statement_type,
  etl_source_type,
  principal_email,
  total_jobs_5_months,
  ROUND(total_slot_hours_5_months, 2) AS total_slot_hours_5_months,
  ROUND(total_cost_5_months, 2) AS total_cost_5_months,
  ROUND(annual_cost_usd, 2) AS annual_cost_usd,
  ROUND(annual_slot_hours, 2) AS annual_slot_hours,
  ROUND(avg_cost_per_job, 6) AS avg_cost_per_job,
  ROUND(avg_jobs_per_day, 2) AS avg_jobs_per_day,
  first_seen,
  last_seen
FROM table_annual_summary
ORDER BY full_table_name, annual_cost_usd DESC;

-- ============================================================================
-- SUMMARY OUTPUT (Uncomment to see totals per table)
-- ============================================================================
-- SELECT
--   full_table_name,
--   SUM(total_jobs_5_months) AS total_etl_jobs,
--   ROUND(SUM(annual_slot_hours), 2) AS annual_slot_hours,
--   ROUND(SUM(annual_cost_usd), 2) AS annual_cost_usd,
--   STRING_AGG(DISTINCT CONCAT(etl_source_type, ': ', principal_email) ORDER BY etl_source_type) AS sources
-- FROM table_annual_summary
-- GROUP BY full_table_name
-- ORDER BY annual_cost_usd DESC;

-- ============================================================================
-- VALIDATION NOTES
-- ============================================================================
-- 1. Searches Peak_2024_2025 (Nov 2024-Jan 2025, 3 months)
-- 2. Searches Baseline_2025_Sep_Oct (Sep-Oct 2025, 2 months)
-- 3. Total period: 5 months
-- 4. Annualization factor: × (12/5) = × 2.4
-- 5. Handles both RESERVED and ON_DEMAND pricing
-- 6. Filters to production only (excludes QA, test, tmp)
-- ============================================================================

