-- ============================================================================
-- Search Audit Logs for Base Table Production Costs
-- ============================================================================
-- Purpose: Find ETL operations and costs for known Monitor base tables
-- Tables: reporting.t_return_details, return_insights_base.return_item_details, 
--         monitor_base.carrier_config
-- Period: Sep 2024 - Oct 2025 (match consumption analysis)
-- ============================================================================

DECLARE analysis_start_date DATE DEFAULT '2024-09-01';
DECLARE analysis_end_date DATE DEFAULT '2025-10-31';

-- ============================================================================
-- Target base tables (from view resolution)
-- ============================================================================
WITH target_base_tables AS (
  SELECT table_name, priority
  FROM UNNEST([
    STRUCT('t_return_details' AS table_name, 1 AS priority),  -- HIGH PRIORITY
    STRUCT('return_item_details' AS table_name, 2 AS priority),
    STRUCT('carrier_config' AS table_name, 3 AS priority)
  ])
),

-- ============================================================================
-- Search audit logs for ETL operations on these tables
-- ============================================================================
etl_operations AS (
  SELECT
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    timestamp AS job_timestamp,
    
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
    
    -- Reservation info (it's an array, get first element)
    ARRAY_LENGTH(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservationUsage) AS reservation_count,
    CASE 
      WHEN ARRAY_LENGTH(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservationUsage) > 0 
      THEN protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservationUsage[OFFSET(0)].name
      ELSE 'unreserved'
    END AS reservation_name
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN analysis_start_date AND analysis_end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.statementType IN ('INSERT', 'MERGE', 'CREATE_TABLE_AS_SELECT', 'UPDATE')
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.tableId IN (
      SELECT table_name FROM target_base_tables
    )
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs IS NOT NULL
),

-- ============================================================================
-- Classify and aggregate by table and service account
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
),

-- Aggregate by table
table_summary AS (
  SELECT
    full_table_name,
    statement_type,
    etl_source_type,
    principal_email,
    
    COUNT(*) AS etl_job_count,
    SUM(total_slot_ms) / 3600000 AS total_slot_hours,
    SUM(job_cost_usd) AS period_cost_usd,
    AVG(job_cost_usd) AS avg_cost_per_job,
    
    MIN(job_timestamp) AS first_seen,
    MAX(job_timestamp) AS last_seen,
    
    -- Calculate jobs per day
    COUNT(*) / DATE_DIFF(analysis_end_date, analysis_start_date, DAY) AS avg_jobs_per_day
    
  FROM etl_classified
  GROUP BY full_table_name, statement_type, etl_source_type, principal_email
),

-- Annualize costs (5 months → 12 months)
annual_costs AS (
  SELECT
    full_table_name,
    statement_type,
    etl_source_type,
    principal_email,
    etl_job_count,
    ROUND(total_slot_hours, 2) AS total_slot_hours,
    ROUND(period_cost_usd, 2) AS period_cost_usd,
    ROUND(period_cost_usd * (12.0 / 5.0), 2) AS annual_cost_usd,
    ROUND(avg_cost_per_job, 4) AS avg_cost_per_job,
    ROUND(avg_jobs_per_day, 2) AS avg_jobs_per_day,
    first_seen,
    last_seen
  FROM table_summary
)

-- ============================================================================
-- OUTPUT: Production Costs by Base Table
-- ============================================================================
SELECT
  full_table_name,
  statement_type,
  etl_source_type,
  principal_email,
  etl_job_count,
  total_slot_hours,
  period_cost_usd,
  annual_cost_usd,
  avg_cost_per_job,
  avg_jobs_per_day,
  first_seen,
  last_seen
FROM annual_costs
ORDER BY full_table_name, annual_cost_usd DESC;

-- ============================================================================
-- Also output: Summary by table (aggregate all ETL sources)
-- ============================================================================
-- Uncomment to see totals per table:
-- SELECT
--   full_table_name,
--   SUM(etl_job_count) AS total_etl_jobs,
--   SUM(total_slot_hours) AS total_slot_hours,
--   SUM(annual_cost_usd) AS total_annual_cost_usd,
--   STRING_AGG(DISTINCT principal_email ORDER BY principal_email) AS service_accounts
-- FROM annual_costs
-- GROUP BY full_table_name
-- ORDER BY total_annual_cost_usd DESC;

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. Searches for INSERT, MERGE, CREATE_TABLE_AS_SELECT, UPDATE operations
-- 2. Period matches consumption analysis (Sep 2024 - Oct 2025)
-- 3. Annualizes costs using 12/5 multiplier
-- 4. Handles both RESERVED and ON_DEMAND pricing
-- 5. Expected to find reporting.t_return_details with significant costs
-- ============================================================================

