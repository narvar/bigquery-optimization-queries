-- ============================================================================
-- UNIFIED TRAFFIC CLASSIFICATION - PHYSICAL TABLE VERSION
-- ============================================================================
-- Purpose: Classify all BigQuery traffic into consumer categories and save to
--          physical table for reuse across all Phase 2+ analysis queries
--
-- Output Table: narvar-data-lake.query_opt.traffic_classification
-- Partitioning: By DATE(start_time) for efficient peak period queries
-- Clustering: By consumer_category, classification_date for fast category analysis
--
-- Classification Categories:
-- - EXTERNAL (P0): Monitor projects, Hub traffic
-- - AUTOMATED (P0): Airflow, GKE, ML, CDP, ETL, service backends
-- - INTERNAL (P1): Metabase, ad-hoc user queries
--
-- Data Quality: Filters for jobs with measured slot consumption (totalSlotMs IS NOT NULL)
--               This captures ~94% of execution time and ~99.94% of bytes processed
--               Excludes: cache hits, metadata queries, failed queries (minimal capacity impact)
--
-- Cost estimate: ~5-20GB per 2-month period, ~50-100GB for full 3-year history
-- ============================================================================

-- ============================================================================
-- CONFIGURATION PARAMETERS
-- ============================================================================
-- Adjust these for each classification run

-- Analysis period (REQUIRED: Update for each run)
DECLARE start_date DATE DEFAULT '2024-09-01';
DECLARE end_date DATE DEFAULT '2024-10-31';
DECLARE analysis_period_label STRING DEFAULT 'Baseline_2024_Sep_Oct';

-- Classification metadata (Update version if improving patterns)
DECLARE classification_version STRING DEFAULT 'v1.0';

-- QoS thresholds by consumer category
DECLARE external_qos_threshold_seconds INT64 DEFAULT 60;   -- 1 minute (P0)
DECLARE internal_qos_threshold_seconds INT64 DEFAULT 480;  -- 8 minutes (P1)
DECLARE automated_qos_threshold_seconds INT64 DEFAULT 1800; -- 30 minutes placeholder

-- Slot cost calculation (blended reservation rate)
DECLARE slot_cost_per_hour FLOAT64 DEFAULT 0.0494;
-- Calculation: (500 slots @ $0.048/hr + 500 @ $0.036/hr + 700 @ $0.06/hr) / 1700

-- ============================================================================
-- EXECUTION MODE
-- ============================================================================
-- For FIRST RUN or to REPLACE all data:
--   Use: CREATE OR REPLACE TABLE (line 68 active)
--
-- For SUBSEQUENT RUNS (appending new periods):
--   Comment out line 68-71 (CREATE OR REPLACE TABLE)
--   Uncomment line 72 (INSERT INTO)
--
-- CURRENT MODE: CREATE OR REPLACE (set for first run)
-- ============================================================================

-- ============================================================================
-- MAIN QUERY: Traffic Classification with Metadata
-- ============================================================================

-- ============================================================================
-- OUTPUT TO PHYSICAL TABLE
-- ============================================================================
-- FIRST RUN: Use CREATE OR REPLACE TABLE (line below is active)
-- SUBSEQUENT RUNS: Comment out CREATE OR REPLACE, uncomment INSERT INTO (line 66)

--TRUNCATE TABLE `narvar-data-lake.query_opt.traffic_classification`;

-- CREATE OR REPLACE TABLE `narvar-data-lake.query_opt.traffic_classification`
-- PARTITION BY DATE(start_time)
-- CLUSTER BY consumer_category, classification_date
-- AS
INSERT INTO `narvar-data-lake.query_opt.traffic_classification`  -- Use this for subsequent runs

WITH
-- Get retailer to monitor project mappings using MD5 hash
-- This matches the actual monitor project naming convention: monitor-{MD5_7char}-us-{env}
retailer_mappings AS (
  SELECT DISTINCT 
    retailer_moniker,
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-prod') AS project_id_prod,
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-qa') AS project_id_qa,
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-stg') AS project_id_stg
  FROM `narvar-data-lake.reporting.t_return_details`
  WHERE DATE(return_created_date) >= '2022-01-01'
    AND retailer_moniker IS NOT NULL
),

-- Extract and deduplicate audit log data
audit_data AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.location AS location,
    
    -- Event details
    CASE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName
      WHEN 'query_job_completed' THEN 'QUERY'
      WHEN 'load_job_completed' THEN 'LOAD'
      WHEN 'extract_job_completed' THEN 'EXTRACT'
      WHEN 'table_copy_job_completed' THEN 'TABLE_COPY'
    END AS job_type,
    
    -- Timing metrics
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime AS start_time,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime AS end_time,
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
      SECOND
    ) AS execution_time_seconds,
    
    -- Resource consumption
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes AS total_billed_bytes,
    
    -- Slot calculation
    SAFE_DIVIDE(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
      TIMESTAMP_DIFF(
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
        MILLISECOND
      )
    ) AS approximate_slot_count,
    
    -- Query text
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    
    -- Job metadata
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservation AS reservation_name,
    protopayload_auditlog.requestMetadata.callerSuppliedUserAgent AS user_agent,
    
    -- Deduplication
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS row_num
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN start_date AND end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    -- NULL-TOLERANT FILTER: Only include jobs with measured slot consumption
    -- This captures ~94% of execution time and ~99.94% of bytes processed
    -- Excludes cache hits, metadata queries, and failed queries (minimal capacity impact)
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs IS NOT NULL
),

-- Deduplicate
audit_deduplicated AS (
  SELECT * EXCEPT(row_num)
  FROM audit_data
  WHERE row_num = 1
),

-- Match monitor projects to retailers using MD5-based project IDs
retailer_selected AS (
  SELECT
    a.job_id,
    a.project_id,
    rm.retailer_moniker
  FROM audit_deduplicated a
  INNER JOIN retailer_mappings rm
    ON a.project_id IN (rm.project_id_prod, rm.project_id_qa, rm.project_id_stg)
  WHERE STARTS_WITH(LOWER(a.project_id), 'monitor-')
),

-- Classify all traffic using regex patterns (no manual configuration needed)
traffic_classified AS (
  SELECT
    a.*,
    rs.retailer_moniker,
    
    -- Extract Metabase user ID (try multiple patterns)
    COALESCE(
      REGEXP_EXTRACT(a.query_text, r'--\s*Metabase::\s*userID:\s*(\d+)'),
      REGEXP_EXTRACT(a.query_text, r'/\*\s*Metabase\s*userID:\s*(\d+)\s*\*/'),
      REGEXP_EXTRACT(a.query_text, r'--\s*metabase_user_id\s*=\s*(\d+)')
    ) AS metabase_user_id,
    
    -- ========================================================================
    -- PRIMARY CLASSIFICATION: Determine consumer category (EXTERNAL, AUTOMATED, INTERNAL)
    -- ========================================================================
    CASE
      -- ===================
      -- EXTERNAL CONSUMERS (P0) - Customer-facing APIs and services
      -- ===================
      
      -- Monitor projects (retailer-specific projects)
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') THEN 'EXTERNAL'
      
      -- Hub traffic (Looker service accounts)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'looker.*@.*\.iam\.gserviceaccount\.com') THEN 'EXTERNAL'
      
      -- ===================
      -- AUTOMATED PROCESSES (P0) - Scheduled jobs and pipelines
      -- ===================
      
      -- Airflow/Composer
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer)') THEN 'AUTOMATED'
      
      -- GKE workloads
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gke-prod|gke-[a-z0-9]+-sumatra') THEN 'AUTOMATED'
      
      -- Compute Engine default service accounts
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'\d+-compute@developer\.gserviceaccount\.com') THEN 'AUTOMATED'
      
      -- CDP (Customer Data Platform) - check EMAIL only, not project
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(cdp|customer-data)') THEN 'AUTOMATED'
      
      -- ETL/Dataflow
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(dataflow|etl)') THEN 'AUTOMATED'
      
      -- ML/AI model serving - check EMAIL only (eddmodel is the big one)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(eddmodel|ai-platform)') THEN 'AUTOMATED'
      
      -- Analytics API (backend service, not external-facing)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'analytics-api-bigquery-access') THEN 'AUTOMATED'
      
      -- Messaging service (internal messaging system, high volume - 188K jobs!)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'^messaging@') THEN 'AUTOMATED'
      
      -- Shopify integration runners
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'shopify.*runner') THEN 'AUTOMATED'
      
      -- iPaaS integration services
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'ipaas-integration') THEN 'AUTOMATED'
      
      -- GrowthBook (feature flagging/experimentation)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'growthbook') THEN 'AUTOMATED'
      
      -- Metric layer service
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'metric-layer') THEN 'AUTOMATED'
      
      -- Retool (internal tools platform)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'retool') THEN 'AUTOMATED'
      
      -- Service accounts in domain projects (nub-tenant, carriers, etc.)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(nub-tenant|carrierstest|service-samoa)@') THEN 'AUTOMATED'
      
      -- DoIt CMP monitoring
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'doit-cmp') THEN 'AUTOMATED'
      
      -- BigQuery Data Transfer Service
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gcp-sa-bigquerydatatransfer') THEN 'AUTOMATED'
      
      -- AI Platform service accounts
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gcp-sa-aiplatform') THEN 'AUTOMATED'
      
      -- QA automation services
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'qa-automation-bigquery') THEN 'AUTOMATED'
      
      -- ===================
      -- INTERNAL USERS (P1) - Employee analytics and ad-hoc queries
      -- ===================
      -- IMPORTANT: Check for human users BEFORE project patterns to avoid misclassification
      
      -- Ad-hoc queries from @narvar.com employees (CHECK THIS FIRST!)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'@narvar\.com$') THEN 'INTERNAL'
      
      -- Metabase
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'metabase.*@.*\.iam\.gserviceaccount\.com') THEN 'INTERNAL'
      
      -- n8n workflow automation
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'n8n') THEN 'INTERNAL'
      
      -- Other BI tools (Tableau, PowerBI, etc.)
      WHEN REGEXP_CONTAINS(LOWER(a.user_agent), r'(tableau|powerbi)') THEN 'INTERNAL'
      
      -- ===================
      -- UNCLASSIFIED - Everything else
      -- ===================
      ELSE 'UNCLASSIFIED'
    END AS consumer_category,
    
    -- ========================================================================
    -- SECONDARY CLASSIFICATION: Determine subcategory (more specific than category)
    -- ========================================================================
    CASE
      -- External subcategories
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') AND rs.retailer_moniker IS NOT NULL THEN 'MONITOR'
      WHEN a.project_id IN ('monitor-base-us-prod', 'monitor-base-us-qa', 'monitor-base-us-stg') THEN 'MONITOR_BASE'
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') AND rs.retailer_moniker IS NULL THEN 'MONITOR_UNMATCHED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'looker.*@.*\.iam\.gserviceaccount\.com') THEN 'HUB'
      
      -- Automated subcategories
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer)') THEN 'AIRFLOW_COMPOSER'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gke-prod|gke-[a-z0-9]+-sumatra') THEN 'GKE_WORKLOAD'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'\d+-compute@developer\.gserviceaccount\.com') THEN 'COMPUTE_ENGINE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(cdp|customer-data)') THEN 'CDP'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(dataflow|etl)') THEN 'ETL_DATAFLOW'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(eddmodel|ai-platform)') THEN 'ML_INFERENCE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'analytics-api-bigquery-access') THEN 'ANALYTICS_API'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'^messaging@') THEN 'MESSAGING'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'shopify.*runner') THEN 'SHOPIFY_INTEGRATION'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'ipaas-integration') THEN 'IPAAS_INTEGRATION'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'growthbook') THEN 'GROWTHBOOK'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'metric-layer') THEN 'METRIC_LAYER'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'retool') THEN 'RETOOL'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'doit-cmp') THEN 'DOIT_CMP'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gcp-sa-bigquerydatatransfer') THEN 'BQ_DATA_TRANSFER'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gcp-sa-aiplatform') THEN 'AI_PLATFORM'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(nub-tenant|carrierstest|service-samoa)@') THEN 'DOMAIN_SERVICE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'qa-automation-bigquery') THEN 'QA_AUTOMATION'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'iam\.gserviceaccount\.com$')
        AND NOT REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer|gke|compute|cdp|dataflow|etl|eddmodel|analytics-api|messaging|shopify|ipaas|growthbook|metric-layer|retool|doit-cmp|bigquerydatatransfer|aiplatform|looker|metabase|n8n)')
        THEN 'SERVICE_ACCOUNT_OTHER'
      
      -- Internal subcategories
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'metabase.*@.*\.iam\.gserviceaccount\.com') THEN 'METABASE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'n8n') THEN 'N8N_WORKFLOW'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'@narvar\.com$') THEN 'ADHOC_USER'
      WHEN REGEXP_CONTAINS(LOWER(a.user_agent), r'(tableau|powerbi)') THEN 'OTHER_BI_TOOL'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'iam\.gserviceaccount\.com$') THEN 'INTERNAL_SERVICE_ACCOUNT'
      
      ELSE 'UNCLASSIFIED'
    END AS consumer_subcategory,
    
    -- Cost calculation (slot-based for reserved capacity)
    ROUND(SAFE_DIVIDE(a.total_slot_ms, 3600000) * slot_cost_per_hour, 4) AS estimated_slot_cost_usd,
    
    -- QoS evaluation (category-specific thresholds)
    CASE
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') OR REGEXP_CONTAINS(LOWER(a.principal_email), r'looker.*@.*\.iam\.gserviceaccount\.com') THEN
        CASE WHEN a.execution_time_seconds > external_qos_threshold_seconds THEN 'QoS_VIOLATION' ELSE 'QoS_MET' END
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(metabase|@narvar\.com$)') THEN
        CASE WHEN a.execution_time_seconds > internal_qos_threshold_seconds THEN 'QoS_VIOLATION' ELSE 'QoS_MET' END
      ELSE 'QoS_REQUIRES_SCHEDULE_DATA' -- Automated processes need schedule data for proper QoS
    END AS qos_status,
    
    -- QoS violation severity (seconds over threshold)
    CASE
      WHEN (STARTS_WITH(LOWER(a.project_id), 'monitor-') OR REGEXP_CONTAINS(LOWER(a.principal_email), r'looker.*@.*\.iam\.gserviceaccount\.com'))
        AND a.execution_time_seconds > external_qos_threshold_seconds 
        THEN a.execution_time_seconds - external_qos_threshold_seconds
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(metabase|@narvar\.com$)')
        AND a.execution_time_seconds > internal_qos_threshold_seconds 
        THEN a.execution_time_seconds - internal_qos_threshold_seconds
      ELSE 0
    END AS qos_violation_seconds,
    
    -- Priority for slot allocation
    CASE
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') OR REGEXP_CONTAINS(LOWER(a.principal_email), r'looker.*@.*\.iam\.gserviceaccount\.com') 
        THEN 1  -- EXTERNAL (P0)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer|gke|compute|cdp|dataflow|etl|eddmodel|analytics-api|messaging|shopify|ipaas|growthbook|metric-layer|retool)')
        THEN 2  -- AUTOMATED (P0)
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(metabase|@narvar\.com$|n8n)')
        THEN 3  -- INTERNAL (P1)
      ELSE 4  -- UNCLASSIFIED
    END AS priority_level
    
  FROM audit_deduplicated a
  LEFT JOIN retailer_selected rs USING (job_id, project_id)
)

-- Final SELECT with metadata columns
SELECT
  -- ========================================================================
  -- CLASSIFICATION METADATA (NEW!)
  -- ========================================================================
  CURRENT_DATE() AS classification_date,
  start_date AS analysis_start_date,
  end_date AS analysis_end_date,
  analysis_period_label,
  classification_version,
  
  -- ========================================================================
  -- JOB IDENTIFIERS
  -- ========================================================================
  job_id,
  project_id,
  principal_email,
  location,
  
  -- ========================================================================
  -- CLASSIFICATION
  -- ========================================================================
  consumer_category,
  consumer_subcategory,
  priority_level,
  
  -- External-specific attribution
  retailer_moniker,
  
  -- Internal-specific attribution
  metabase_user_id,
  
  -- ========================================================================
  -- JOB DETAILS
  -- ========================================================================
  job_type,
  start_time,
  end_time,
  execution_time_seconds,
  ROUND(execution_time_seconds / 60.0, 2) AS execution_time_minutes,
  
  -- ========================================================================
  -- RESOURCE CONSUMPTION
  -- ========================================================================
  total_slot_ms,
  approximate_slot_count,
  ROUND(total_slot_ms / 3600000, 2) AS slot_hours,
  total_billed_bytes,
  ROUND(total_billed_bytes / POW(1024, 3), 2) AS total_billed_gb,
  estimated_slot_cost_usd,
  
  -- ========================================================================
  -- QoS METRICS
  -- ========================================================================
  qos_status,
  qos_violation_seconds,
  CASE 
    WHEN qos_status = 'QoS_VIOLATION' THEN TRUE
    WHEN qos_status = 'QoS_MET' THEN FALSE
    ELSE NULL
  END AS is_qos_violation,
  
  -- ========================================================================
  -- ADDITIONAL METADATA
  -- ========================================================================
  reservation_name,
  user_agent,
  
  -- Query text sample (first 500 chars, useful for debugging classification)
  SUBSTR(query_text, 1, 500) AS query_text_sample

FROM traffic_classified;

-- ============================================================================
-- POST-RUN VALIDATION QUERY
-- ============================================================================
-- Run this after table creation to validate classification quality
-- ============================================================================
/*
SELECT
  'Classification Summary' AS report,
  analysis_period_label,
  classification_date,
  classification_version,
  consumer_category,
  consumer_subcategory,
  
  -- Volume metrics
  COUNT(*) AS total_jobs,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER(PARTITION BY analysis_period_label) * 100, 2) AS pct_of_period,
  COUNT(DISTINCT principal_email) AS unique_principals,
  COUNT(DISTINCT project_id) AS unique_projects,
  COUNT(DISTINCT retailer_moniker) AS unique_retailers,
  
  -- Resource metrics
  ROUND(SUM(slot_hours), 2) AS total_slot_hours,
  ROUND(SUM(slot_hours) / SUM(SUM(slot_hours)) OVER(PARTITION BY analysis_period_label) * 100, 2) AS pct_of_slots,
  
  -- Cost metrics
  ROUND(SUM(estimated_slot_cost_usd), 2) AS total_cost_usd,
  
  -- QoS metrics
  COUNTIF(is_qos_violation) AS qos_violations,
  ROUND(COUNTIF(is_qos_violation) / NULLIF(COUNTIF(qos_status IN ('QoS_MET', 'QoS_VIOLATION')), 0) * 100, 2) AS qos_violation_pct

FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE analysis_period_label = 'Baseline_2024_Sep_Oct'  -- Adjust for each run
  AND classification_date = CURRENT_DATE()  -- Latest run
GROUP BY 
  analysis_period_label, 
  classification_date, 
  classification_version,
  consumer_category, 
  consumer_subcategory
ORDER BY total_jobs DESC;
*/

-- ============================================================================
-- USAGE INSTRUCTIONS
-- ============================================================================
-- 
-- FIRST RUN (Create Table):
-- 1. Set parameters: start_date, end_date, analysis_period_label (lines 29-31)
-- 2. Ensure line 68-71 is active: CREATE OR REPLACE TABLE
-- 3. Ensure line 72 is commented: -- INSERT INTO
-- 4. Run query (expect ~8-15 minutes for 2-month period)
-- 5. Validate results using validation query above (lines 435-472)
--
-- SUBSEQUENT RUNS (Append Data):
-- 1. Update parameters for new period (e.g., Nov 2024, or historical peaks)
-- 2. Comment out lines 68-71: -- CREATE OR REPLACE TABLE ... AS
-- 3. Uncomment line 72: INSERT INTO
-- 4. Update classification_version if patterns improved (e.g., 'v1.1')
-- 5. Run query
-- 6. Validate with validation query (filter by new analysis_period_label)
--
-- RE-CLASSIFICATION (Improve Patterns for Same Period):
-- 1. Keep same start_date, end_date, analysis_period_label
-- 2. Update classification_version (e.g., 'v1.0' → 'v1.1')
-- 3. Use INSERT INTO (creates new version, keeps old)
-- 4. Downstream queries can choose version or use latest
--
-- RECOMMENDED EXECUTION SEQUENCE:
-- Run 1: Sep-Oct 2024 (Baseline_2024_Sep_Oct, v1.0) - discover patterns
-- Run 2: Nov 2024 (Peak_2024_2025_Partial_Nov, v1.0) - current peak
-- Run 3: Nov 2023-Jan 2024 (Peak_2023_2024, v1.0) - historical peak
-- Run 4: Nov 2022-Jan 2023 (Peak_2022_2023, v1.0) - historical peak
--
-- After each run, check UNCLASSIFIED rate. If high, improve patterns and re-run.
-- ============================================================================

-- ============================================================================
-- QUERY TO COMPARE MULTIPLE PERIODS
-- ============================================================================
-- Use this to compare classification across different time periods
-- ============================================================================
/*
SELECT
  analysis_period_label,
  consumer_category,
  COUNT(*) AS jobs,
  ROUND(SUM(slot_hours), 2) AS slot_hours,
  ROUND(AVG(execution_time_seconds), 2) AS avg_exec_sec,
  COUNTIF(is_qos_violation) AS qos_violations,
  COUNT(DISTINCT retailer_moniker) AS unique_retailers

FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE classification_date = (
  SELECT MAX(classification_date)
  FROM `narvar-data-lake.query_opt.traffic_classification`
)  -- Use latest classification version
GROUP BY analysis_period_label, consumer_category
ORDER BY analysis_period_label, jobs DESC;
*/

-- ============================================================================
-- QUERY TO GET LATEST CLASSIFICATION FOR EACH JOB
-- ============================================================================
-- If you have multiple classification versions, use this to get latest
-- ============================================================================
/*
WITH latest_classification AS (
  SELECT
    *,
    ROW_NUMBER() OVER(
      PARTITION BY job_id 
      ORDER BY classification_date DESC, classification_version DESC
    ) AS recency_rank
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE analysis_period_label = 'Peak_2023_2024'  -- Adjust as needed
)
SELECT * EXCEPT(recency_rank)
FROM latest_classification
WHERE recency_rank = 1;
*/

-- ============================================================================
-- END OF QUERY
-- ============================================================================

