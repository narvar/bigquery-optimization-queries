<<<<<<< Current (Your changes)
=======
-- ============================================================================
-- QOS VIOLATIONS HISTORICAL ANALYSIS
-- ============================================================================
-- Purpose: Identify and analyze Quality of Service violations across
--          historical peak periods to understand:
--          - Frequency and severity of QoS violations by consumer category
--          - Time periods with highest QoS impact
--          - Slot starvation periods (demand > 1,700 slots capacity)
--          - Query throttling and queue wait patterns
--
-- QoS Thresholds:
-- - External: 60 seconds (1 minute)
-- - Internal: 480 seconds (8 minutes)
-- - Automated: Requires schedule data (placeholder: 1800 seconds / 30 min)
--
-- Cost estimate: ~20-50GB processed (full 3-year analysis)
-- ============================================================================

-- Configuration parameters
DECLARE analysis_start_date DATE DEFAULT '2022-11-01'; -- Start from first peak period
DECLARE analysis_end_date DATE DEFAULT CURRENT_DATE();

-- QoS thresholds by category (in seconds)
DECLARE external_qos_threshold INT64 DEFAULT 60;
DECLARE internal_qos_threshold INT64 DEFAULT 480;
DECLARE automated_qos_threshold INT64 DEFAULT 1800; -- Placeholder until we have schedule data

-- Slot capacity threshold
DECLARE total_slot_capacity INT64 DEFAULT 1700;

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
-- MAIN QUERY: QoS Violations Analysis
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

-- Extract audit log data with timing
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
    
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservation AS reservation_name,
    
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS row_num
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN analysis_start_date AND analysis_end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName = 'query_job_completed' -- Focus on queries
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
),

-- Deduplicate
audit_deduplicated AS (
  SELECT * EXCEPT(row_num)
  FROM audit_data
  WHERE row_num = 1
),

-- Classify and evaluate QoS
qos_evaluated AS (
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
    
    -- QoS threshold for this category
    CASE
      WHEN rm.project_id IS NOT NULL OR a.project_id LIKE 'monitor-%' OR a.principal_email = hub_service_account 
        THEN external_qos_threshold
      WHEN a.principal_email IN UNNEST(automated_service_accounts) 
        OR LOWER(a.principal_email) LIKE '%airflow%' 
        OR LOWER(a.principal_email) LIKE '%composer%'
        OR LOWER(a.principal_email) LIKE '%cdp%' 
        OR LOWER(a.principal_email) LIKE '%dataflow%'
        THEN automated_qos_threshold
      ELSE internal_qos_threshold
    END AS qos_threshold_seconds,
    
    -- Temporal dimensions
    DATE(a.start_time) AS job_date,
    EXTRACT(HOUR FROM a.start_time) AS hour,
    FORMAT_DATE('%A', DATE(a.start_time)) AS day_name,
    
    -- Cost
    ROUND(SAFE_DIVIDE(a.total_billed_bytes, POW(1024, 4)) * 5, 4) AS on_demand_cost_usd
    
  FROM audit_deduplicated a
  LEFT JOIN retailer_mappings rm ON a.project_id = rm.project_id
),

-- Identify QoS violations
qos_violations AS (
  SELECT
    *,
    
    -- QoS status
    CASE
      WHEN execution_time_seconds > qos_threshold_seconds THEN 'QoS_VIOLATION'
      ELSE 'QoS_MET'
    END AS qos_status,
    
    -- Violation severity (seconds over threshold)
    GREATEST(0, execution_time_seconds - qos_threshold_seconds) AS violation_seconds,
    
    -- Violation severity category
    CASE
      WHEN execution_time_seconds <= qos_threshold_seconds THEN 'NO_VIOLATION'
      WHEN execution_time_seconds <= qos_threshold_seconds * 1.5 THEN 'MINOR (1-1.5x threshold)'
      WHEN execution_time_seconds <= qos_threshold_seconds * 2 THEN 'MODERATE (1.5-2x threshold)'
      WHEN execution_time_seconds <= qos_threshold_seconds * 3 THEN 'MAJOR (2-3x threshold)'
      ELSE 'CRITICAL (>3x threshold)'
    END AS violation_severity
    
  FROM qos_evaluated
  WHERE consumer_category != 'UNCLASSIFIED'
)

-- Summary: QoS violations by period and category
SELECT
  period_type,
  consumer_category,
  
  -- Volume
  COUNT(*) AS total_queries,
  COUNT(DISTINCT job_date) AS days_analyzed,
  
  -- QoS metrics
  COUNTIF(qos_status = 'QoS_MET') AS qos_met_count,
  COUNTIF(qos_status = 'QoS_VIOLATION') AS qos_violation_count,
  ROUND(COUNTIF(qos_status = 'QoS_VIOLATION') / COUNT(*) * 100, 2) AS qos_violation_pct,
  
  -- Violation severity breakdown
  COUNTIF(violation_severity = 'MINOR (1-1.5x threshold)') AS minor_violations,
  COUNTIF(violation_severity = 'MODERATE (1.5-2x threshold)') AS moderate_violations,
  COUNTIF(violation_severity = 'MAJOR (2-3x threshold)') AS major_violations,
  COUNTIF(violation_severity = 'CRITICAL (>3x threshold)') AS critical_violations,
  
  -- Execution time stats (for violations only)
  ROUND(AVG(IF(qos_status = 'QoS_VIOLATION', execution_time_seconds, NULL)), 2) AS avg_violation_execution_seconds,
  ROUND(AVG(IF(qos_status = 'QoS_VIOLATION', violation_seconds, NULL)), 2) AS avg_violation_severity_seconds,
  ROUND(MAX(violation_seconds), 2) AS max_violation_severity_seconds,
  
  -- QoS threshold for reference
  MAX(qos_threshold_seconds) AS qos_threshold_seconds,
  
  -- Resource impact
  ROUND(SUM(IF(qos_status = 'QoS_VIOLATION', total_slot_ms, 0)) / 3600000, 2) AS violation_slot_hours,
  ROUND(SUM(IF(qos_status = 'QoS_VIOLATION', on_demand_cost_usd, 0)), 2) AS violation_cost_usd,
  
  -- Worst days (count of days with >10% violation rate)
  COUNTIF(qos_status = 'QoS_VIOLATION') / COUNT(DISTINCT job_date) AS avg_violations_per_day

FROM qos_violations
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
-- WORST QOS VIOLATION PERIODS (Uncomment for hourly violation patterns)
-- ============================================================================
/*
SELECT
  period_type,
  consumer_category,
  job_date,
  hour,
  
  COUNT(*) AS total_queries,
  COUNTIF(qos_status = 'QoS_VIOLATION') AS violations,
  ROUND(COUNTIF(qos_status = 'QoS_VIOLATION') / COUNT(*) * 100, 2) AS violation_pct,
  
  ROUND(AVG(IF(qos_status = 'QoS_VIOLATION', violation_seconds, NULL)), 2) AS avg_violation_seconds,
  
  -- Slot demand during this hour
  ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count,
  ROUND(MAX(approximate_slot_count), 2) AS max_slot_count

FROM qos_violations
WHERE qos_status = 'QoS_VIOLATION'
  AND period_type != 'Non_Peak'
GROUP BY period_type, consumer_category, job_date, hour
HAVING violation_pct > 10
ORDER BY violation_pct DESC, avg_violation_seconds DESC
LIMIT 100;
*/

-- ============================================================================
-- SLOT STARVATION ANALYSIS (Uncomment to identify capacity bottlenecks)
-- ============================================================================
/*
WITH
minute_aggregates AS (
  SELECT
    TIMESTAMP_TRUNC(start_time, MINUTE) AS minute,
    consumer_category,
    SUM(approximate_slot_count) AS total_slot_demand,
    COUNT(*) AS concurrent_queries,
    AVG(execution_time_seconds) AS avg_execution_seconds
  FROM qos_violations
  WHERE period_type != 'Non_Peak'
  GROUP BY minute, consumer_category
)

SELECT
  minute,
  SUM(total_slot_demand) AS total_demand_all_categories,
  
  -- Demand by category
  SUM(IF(consumer_category = 'EXTERNAL', total_slot_demand, 0)) AS external_demand,
  SUM(IF(consumer_category = 'AUTOMATED', total_slot_demand, 0)) AS automated_demand,
  SUM(IF(consumer_category = 'INTERNAL', total_slot_demand, 0)) AS internal_demand,
  
  -- Slot starvation flag
  CASE 
    WHEN SUM(total_slot_demand) > total_slot_capacity THEN TRUE 
    ELSE FALSE 
  END AS slot_starvation,
  
  -- Deficit
  GREATEST(0, SUM(total_slot_demand) - total_slot_capacity) AS slot_deficit

FROM minute_aggregates
GROUP BY minute
HAVING slot_starvation = TRUE
ORDER BY slot_deficit DESC
LIMIT 100;
*/
>>>>>>> Incoming (Background Agent changes)
