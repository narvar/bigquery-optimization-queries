-- ============================================================================
-- Search for Production Costs of 4 Missing Tables
-- ============================================================================
-- Purpose: Find ETL operations that populate the 4 tables used by fashionnova
-- Tables: v_shipments_events, v_benchmark_ft, v_return_details, v_return_rate_agg
-- Method: Search audit logs for INSERT/MERGE/CREATE operations
-- ============================================================================

DECLARE analysis_start_date DATE DEFAULT '2024-09-01';
DECLARE analysis_end_date DATE DEFAULT '2025-10-31';

-- Target tables (from Phase 1 results)
DECLARE target_tables ARRAY<STRING> DEFAULT [
  'v_shipments_events',
  'v_benchmark_ft', 
  'v_return_details',
  'v_return_rate_agg'
];

-- ============================================================================
-- STEP 1: Search for ETL operations on target tables
-- ============================================================================
WITH etl_operations AS (
  SELECT
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    timestamp AS job_timestamp,
    
    -- Destination table info
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.projectId AS dest_project,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.datasetId AS dest_dataset,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.tableId AS dest_table,
    
    -- Job details
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.statementType AS statement_type,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes AS total_billed_bytes,
    
    -- Query text (to verify it's actually populating these tables)
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN analysis_start_date AND analysis_end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.tableId IN UNNEST(target_tables)
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs IS NOT NULL
),

-- Also search in query text for these table names (they might be referenced without being destination)
query_text_references AS (
  SELECT
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    timestamp AS job_timestamp,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    
    -- Extract which table is referenced
    CASE
      WHEN REGEXP_CONTAINS(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query, r'(?i)v_shipments_events') THEN 'v_shipments_events'
      WHEN REGEXP_CONTAINS(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query, r'(?i)v_benchmark_ft') THEN 'v_benchmark_ft'
      WHEN REGEXP_CONTAINS(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query, r'(?i)v_return_details') THEN 'v_return_details'
      WHEN REGEXP_CONTAINS(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query, r'(?i)v_return_rate_agg') THEN 'v_return_rate_agg'
    END AS referenced_table,
    
    -- Check if it's INSERT/MERGE/CREATE
    REGEXP_CONTAINS(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query, r'(?i)INSERT|MERGE|CREATE') AS is_write_operation
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN analysis_start_date AND analysis_end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND (
      REGEXP_CONTAINS(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query, r'(?i)v_shipments_events') OR
      REGEXP_CONTAINS(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query, r'(?i)v_benchmark_ft') OR
      REGEXP_CONTAINS(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query, r'(?i)v_return_details') OR
      REGEXP_CONTAINS(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query, r'(?i)v_return_rate_agg')
    )
  LIMIT 1000  -- Safety limit for exploratory query
),

-- ============================================================================
-- STEP 2: Aggregate ETL operations by table
-- ============================================================================
etl_summary AS (
  SELECT
    CONCAT(dest_project, '.', dest_dataset, '.', dest_table) AS table_reference,
    statement_type,
    principal_email,
    COUNT(*) AS etl_job_count,
    SUM(total_slot_ms) / 3600000 AS total_slot_hours,
    SUM(total_slot_ms) / 3600000 * 0.0494 AS estimated_cost_usd,
    MIN(job_timestamp) AS first_seen,
    MAX(job_timestamp) AS last_seen,
    COUNT(*) / DATE_DIFF(analysis_end_date, analysis_start_date, DAY) AS avg_jobs_per_day
  FROM etl_operations
  WHERE total_slot_ms IS NOT NULL
  GROUP BY table_reference, statement_type, principal_email
),

-- Annualize costs (from 5 months to 12 months)
etl_annual_costs AS (
  SELECT
    table_reference,
    statement_type,
    principal_email,
    etl_job_count,
    total_slot_hours,
    estimated_cost_usd,
    estimated_cost_usd * (12.0 / 5.0) AS annual_estimated_cost_usd,
    avg_jobs_per_day,
    first_seen,
    last_seen
  FROM etl_summary
)

-- ============================================================================
-- OUTPUT: Production Costs for Missing Tables
-- ============================================================================
SELECT
  table_reference,
  statement_type,
  principal_email,
  etl_job_count,
  ROUND(total_slot_hours, 2) AS total_slot_hours,
  ROUND(estimated_cost_usd, 2) AS period_cost_usd,
  ROUND(annual_estimated_cost_usd, 2) AS annual_estimated_cost_usd,
  ROUND(avg_jobs_per_day, 2) AS avg_jobs_per_day,
  first_seen,
  last_seen
FROM etl_annual_costs
ORDER BY table_reference, annual_estimated_cost_usd DESC;

-- ============================================================================
-- Also output query text reference analysis
-- ============================================================================
-- Uncomment to see which tables are referenced in write operations:
-- SELECT
--   referenced_table,
--   is_write_operation,
--   COUNT(*) as reference_count,
--   COUNT(DISTINCT principal_email) as unique_service_accounts
-- FROM query_text_references
-- WHERE referenced_table IS NOT NULL
-- GROUP BY referenced_table, is_write_operation
-- ORDER BY reference_count DESC;

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. These tables may be VIEWS, not base tables (no ETL operations)
-- 2. If 0 results, tables are likely materialized views or populated via streaming
-- 3. Check if these are views on monitor_base.shipments (production cost already captured)
-- 4. May need to check INFORMATION_SCHEMA.VIEWS for view definitions
-- ============================================================================

