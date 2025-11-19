-- ============================================================================
-- SLOT UTILIZATION HEATMAP ANALYSIS
-- ============================================================================
-- Purpose: Generate detailed slot utilization patterns for heatmap visualization:
--          - Hourly slot consumption by consumer category (stacked analysis)
--          - Peak minute identification (top 100 busiest minutes)
--          - Concurrency patterns by consumer category
--          - Day-of-week and hour-of-day patterns
--
-- Output: Data formatted for heatmap/time-series visualization
--
-- Cost estimate: ~30-60GB processed (minute-level granularity over 3 years)
-- Recommended: Start with single peak period, then expand
-- ============================================================================

-- Configuration parameters
DECLARE analysis_start_date DATE DEFAULT '2024-11-01'; -- Default: most recent peak
DECLARE analysis_end_date DATE DEFAULT '2025-01-31';
DECLARE analysis_period STRING DEFAULT 'Peak_2024_2025';

-- Service accounts for classification
DECLARE metabase_service_account STRING DEFAULT 'metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com';
DECLARE hub_service_account STRING DEFAULT 'looker-prod@narvar-data-lake.iam.gserviceaccount.com';
DECLARE automated_service_accounts ARRAY<STRING> DEFAULT [
  'PLACEHOLDER_ACCOUNT@example.iam.gserviceaccount.com'
];

-- ============================================================================
-- MAIN QUERY: Hourly Slot Utilization by Category (Stacked Heatmap Data)
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
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    
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
    END AS consumer_category
    
  FROM audit_deduplicated a
  LEFT JOIN retailer_mappings rm ON a.project_id = rm.project_id
  WHERE a.start_time IS NOT NULL AND a.end_time IS NOT NULL
),

-- Expand jobs to hourly intervals (for jobs spanning multiple hours)
job_hours AS (
  SELECT
    job_id,
    principal_email,
    consumer_category,
    start_time,
    end_time,
    total_slot_ms,
    approximate_slot_count,
    hour_timestamp
  FROM traffic_classified,
    UNNEST(GENERATE_TIMESTAMP_ARRAY(
      TIMESTAMP_TRUNC(start_time, HOUR),
      TIMESTAMP_TRUNC(end_time, HOUR),
      INTERVAL 1 HOUR
    )) AS hour_timestamp
  WHERE consumer_category != 'UNCLASSIFIED'
),

-- Aggregate by hour and category
hourly_aggregates AS (
  SELECT
    hour_timestamp,
    consumer_category,
    
    -- Temporal dimensions for heatmap
    DATE(hour_timestamp) AS date,
    EXTRACT(HOUR FROM hour_timestamp) AS hour,
    EXTRACT(DAYOFWEEK FROM hour_timestamp) AS day_of_week,
    FORMAT_DATE('%A', DATE(hour_timestamp)) AS day_name,
    EXTRACT(WEEK FROM hour_timestamp) AS week_number,
    
    -- Metrics
    COUNT(DISTINCT job_id) AS job_count,
    COUNT(DISTINCT principal_email) AS unique_users,
    
    -- Slot usage (sum of slot counts at this hour)
    SUM(approximate_slot_count) AS total_slot_demand,
    ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count_per_job,
    ROUND(MAX(approximate_slot_count), 2) AS max_slot_count,
    
    -- Slot milliseconds
    SUM(total_slot_ms) AS total_slot_ms,
    ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours
    
  FROM job_hours
  GROUP BY hour_timestamp, consumer_category, date, hour, day_of_week, day_name, week_number
)

-- Final output: Hourly slot utilization by category (for stacked heatmap)
SELECT
  hour_timestamp,
  date,
  hour,
  day_of_week,
  day_name,
  week_number,
  
  -- Slot demand by category (for stacked visualization)
  SUM(IF(consumer_category = 'EXTERNAL', total_slot_demand, 0)) AS external_slot_demand,
  SUM(IF(consumer_category = 'AUTOMATED', total_slot_demand, 0)) AS automated_slot_demand,
  SUM(IF(consumer_category = 'INTERNAL', total_slot_demand, 0)) AS internal_slot_demand,
  
  -- Total demand
  SUM(total_slot_demand) AS total_slot_demand,
  
  -- Capacity metrics
  1700 AS slot_capacity,
  GREATEST(0, SUM(total_slot_demand) - 1700) AS slot_deficit,
  CASE WHEN SUM(total_slot_demand) > 1700 THEN TRUE ELSE FALSE END AS over_capacity,
  
  -- Job counts by category
  SUM(IF(consumer_category = 'EXTERNAL', job_count, 0)) AS external_jobs,
  SUM(IF(consumer_category = 'AUTOMATED', job_count, 0)) AS automated_jobs,
  SUM(IF(consumer_category = 'INTERNAL', job_count, 0)) AS internal_jobs,
  
  -- Total metrics
  SUM(job_count) AS total_jobs,
  SUM(unique_users) AS total_unique_users,
  
  -- Slot hours by category
  SUM(IF(consumer_category = 'EXTERNAL', total_slot_hours, 0)) AS external_slot_hours,
  SUM(IF(consumer_category = 'AUTOMATED', total_slot_hours, 0)) AS automated_slot_hours,
  SUM(IF(consumer_category = 'INTERNAL', total_slot_hours, 0)) AS internal_slot_hours,
  SUM(total_slot_hours) AS total_slot_hours,
  
  -- Analysis period
  analysis_period AS analysis_period

FROM hourly_aggregates
GROUP BY hour_timestamp, date, hour, day_of_week, day_name, week_number, analysis_period
ORDER BY hour_timestamp;

-- ============================================================================
-- TOP 100 BUSIEST MINUTES (Uncomment for peak minute identification)
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
        OR LOWER(a.principal_email) LIKE '%composer%'
        THEN 'AUTOMATED'
      ELSE 'INTERNAL'
    END AS consumer_category
  FROM audit_deduplicated a
  LEFT JOIN retailer_mappings rm ON a.project_id = rm.project_id
),

job_minutes AS (
  SELECT
    job_id,
    consumer_category,
    start_time,
    approximate_slot_count,
    minute_timestamp
  FROM traffic_classified,
    UNNEST(GENERATE_TIMESTAMP_ARRAY(
      TIMESTAMP_TRUNC(start_time, MINUTE),
      TIMESTAMP_TRUNC(end_time, MINUTE),
      INTERVAL 1 MINUTE
    )) AS minute_timestamp
  WHERE consumer_category != 'UNCLASSIFIED'
),

minute_aggregates AS (
  SELECT
    minute_timestamp,
    SUM(approximate_slot_count) AS total_slot_demand,
    SUM(IF(consumer_category = 'EXTERNAL', approximate_slot_count, 0)) AS external_demand,
    SUM(IF(consumer_category = 'AUTOMATED', approximate_slot_count, 0)) AS automated_demand,
    SUM(IF(consumer_category = 'INTERNAL', approximate_slot_count, 0)) AS internal_demand,
    COUNT(DISTINCT job_id) AS concurrent_jobs
  FROM job_minutes
  GROUP BY minute_timestamp
)

SELECT
  minute_timestamp,
  total_slot_demand,
  external_demand,
  automated_demand,
  internal_demand,
  concurrent_jobs,
  1700 AS slot_capacity,
  GREATEST(0, total_slot_demand - 1700) AS slot_deficit,
  ROUND((total_slot_demand / 1700) * 100, 2) AS capacity_utilization_pct
FROM minute_aggregates
ORDER BY total_slot_demand DESC
LIMIT 100;
*/

-- ============================================================================
-- CONCURRENCY HEATMAP: Jobs running concurrently by category
-- ============================================================================
/*
WITH
traffic_classified AS (
  -- Same classification logic
  SELECT
    a.*,
    CASE
      WHEN rm.project_id IS NOT NULL OR a.project_id LIKE 'monitor-%' OR a.principal_email = hub_service_account 
        THEN 'EXTERNAL'
      WHEN a.principal_email IN UNNEST(automated_service_accounts) 
        OR LOWER(a.principal_email) LIKE '%airflow%'
        THEN 'AUTOMATED'
      ELSE 'INTERNAL'
    END AS consumer_category
  FROM audit_deduplicated a
  LEFT JOIN retailer_mappings rm ON a.project_id = rm.project_id
),

job_minutes AS (
  SELECT
    job_id,
    consumer_category,
    minute_timestamp
  FROM traffic_classified,
    UNNEST(GENERATE_TIMESTAMP_ARRAY(
      TIMESTAMP_TRUNC(start_time, MINUTE),
      TIMESTAMP_TRUNC(end_time, MINUTE),
      INTERVAL 1 MINUTE
    )) AS minute_timestamp
  WHERE consumer_category != 'UNCLASSIFIED'
),

concurrency_by_minute AS (
  SELECT
    minute_timestamp,
    EXTRACT(HOUR FROM minute_timestamp) AS hour,
    EXTRACT(DAYOFWEEK FROM minute_timestamp) AS day_of_week,
    FORMAT_DATE('%A', DATE(minute_timestamp)) AS day_name,
    
    COUNT(DISTINCT IF(consumer_category = 'EXTERNAL', job_id, NULL)) AS external_concurrent,
    COUNT(DISTINCT IF(consumer_category = 'AUTOMATED', job_id, NULL)) AS automated_concurrent,
    COUNT(DISTINCT IF(consumer_category = 'INTERNAL', job_id, NULL)) AS internal_concurrent,
    COUNT(DISTINCT job_id) AS total_concurrent
    
  FROM job_minutes
  GROUP BY minute_timestamp, hour, day_of_week, day_name
)

-- Aggregate to hourly for heatmap
SELECT
  hour,
  day_of_week,
  day_name,
  
  ROUND(AVG(external_concurrent), 2) AS avg_external_concurrent,
  ROUND(AVG(automated_concurrent), 2) AS avg_automated_concurrent,
  ROUND(AVG(internal_concurrent), 2) AS avg_internal_concurrent,
  ROUND(AVG(total_concurrent), 2) AS avg_total_concurrent,
  
  ROUND(MAX(total_concurrent), 2) AS max_total_concurrent

FROM concurrency_by_minute
GROUP BY hour, day_of_week, day_name
ORDER BY day_of_week, hour;
*/




