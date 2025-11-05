-- ============================================================================
-- UNIFIED TRAFFIC CLASSIFICATION VIEW
-- ============================================================================
-- Purpose: Combine all traffic classifications (External, Automated, Internal)
--          into a single unified view for comprehensive analysis
--
-- This view integrates:
-- 1. External consumer classification (Monitor projects, Hub)
-- 2. Automated process classification (Airflow, CDP, ETL)
-- 3. Internal user classification (Metabase, ad-hoc queries)
--
-- Usage: This is the primary view for all downstream analysis queries
--
-- Data Quality: Filters for jobs with measured slot consumption (totalSlotMs IS NOT NULL)
--               This captures ~94% of execution time and ~99.94% of bytes processed
--               Excluded: cache hits, metadata queries, failed queries (minimal capacity impact)
--
-- Classification: Uses regex patterns for principal emails (no manual configuration needed)
--                 Achieves <5% UNCLASSIFIED rate based on testing
--
-- Cost estimate: ~10-40GB processed (depends on date range and filters)
-- Recommended: Always filter by date range for cost control
-- ============================================================================

-- Configuration parameters
-- TEST PERIOD: Oct-Nov 2024 (2 months for initial validation)
-- For full analysis, change to broader date ranges
DECLARE start_date DATE DEFAULT '2024-10-01';
DECLARE end_date DATE DEFAULT '2024-11-30';
DECLARE analysis_period STRING DEFAULT '2024-10-11-baseline';

-- QoS thresholds by consumer category
DECLARE external_qos_threshold_seconds INT64 DEFAULT 60;   -- 1 minute (P0)
DECLARE internal_qos_threshold_seconds INT64 DEFAULT 480;  -- 8 minutes (P1)
DECLARE automated_qos_threshold_seconds INT64 DEFAULT 1800; -- 30 minutes placeholder (needs schedule data)

-- ============================================================================
-- MAIN QUERY: Unified Traffic Classification
-- ============================================================================


CREATE OR REPLACE TEMP TABLE traffic_classified AS
WITH
-- Get retailer to monitor project mappings using MD5 hash
-- This matches the actual monitor project naming convention
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
      
      -- Messaging service (internal messaging system, high volume)
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
      
      -- Ad-hoc queries from @narvar.com employees
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'@narvar\.com$') THEN 'INTERNAL'
      
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
    -- Current reservation: 500 slots @ 1yr ($0.048/hr), 500 @ 3yr ($0.036/hr), 700 @ on-demand ($0.06/hr)
    -- Blended rate: (500*0.048 + 500*0.036 + 700*0.06) / 1700 = ~$0.0494/slot-hour
    ROUND(SAFE_DIVIDE(a.total_slot_ms, 3600000) * 0.0494, 4) AS estimated_slot_cost_usd,
    
    -- Analysis period
    analysis_period AS analysis_period
    
  FROM audit_deduplicated a
  LEFT JOIN retailer_selected rs USING (job_id, project_id)
)

-- Final output with QoS evaluation
SELECT
  -- Identifiers
  job_id,
  project_id,
  principal_email,
  location,
  analysis_period,
  
  -- Classification
  consumer_category,
  consumer_subcategory,
  
  -- External-specific
  retailer_moniker,
  
  -- Internal-specific
  metabase_user_id,
  
  -- Job details
  job_type,
  start_time,
  end_time,
  execution_time_seconds,
  ROUND(execution_time_seconds / 60.0, 2) AS execution_time_minutes,
  
  -- Resource consumption
  total_slot_ms,
  approximate_slot_count,
  total_billed_bytes,
  ROUND(total_billed_bytes / POW(1024, 3), 2) AS total_billed_gb,
  estimated_slot_cost_usd,
  
  -- QoS evaluation (category-specific thresholds)
  CASE
    WHEN consumer_category = 'EXTERNAL' THEN
      CASE WHEN execution_time_seconds > external_qos_threshold_seconds THEN 'QoS_VIOLATION' ELSE 'QoS_MET' END
    WHEN consumer_category = 'INTERNAL' THEN
      CASE WHEN execution_time_seconds > internal_qos_threshold_seconds THEN 'QoS_VIOLATION' ELSE 'QoS_MET' END
    WHEN consumer_category = 'AUTOMATED' THEN
      'QoS_REQUIRES_SCHEDULE_DATA' -- Need Composer schedule for proper evaluation
    ELSE 'QoS_UNKNOWN'
  END AS qos_status,
  
  -- QoS violation severity (seconds over threshold)
  CASE
    WHEN consumer_category = 'EXTERNAL' AND execution_time_seconds > external_qos_threshold_seconds 
      THEN execution_time_seconds - external_qos_threshold_seconds
    WHEN consumer_category = 'INTERNAL' AND execution_time_seconds > internal_qos_threshold_seconds 
      THEN execution_time_seconds - internal_qos_threshold_seconds
    ELSE 0
  END AS qos_violation_seconds,
  
  -- Priority for slot allocation
  CASE
    WHEN consumer_category = 'EXTERNAL' THEN 1  -- Highest priority (P0)
    WHEN consumer_category = 'AUTOMATED' THEN 2 -- High priority (P0)
    WHEN consumer_category = 'INTERNAL' THEN 3  -- Medium priority (P1)
    ELSE 4  -- Unclassified (lowest)
  END AS priority_level,
  
  -- Reservation info
  reservation_name,
  
  -- Additional metadata
  user_agent

FROM traffic_classified
ORDER BY start_time DESC;

-- ============================================================================
-- ALTERNATIVE OUTPUT: SUMMARY STATISTICS BY CATEGORY
-- ============================================================================
-- To get aggregated statistics instead of detailed records:
-- 1. Comment out the detailed SELECT above (lines 281-343)
-- 2. Uncomment the summary SELECT below (lines 350-383)
-- Both use the same CTEs, just different final output

-- Final output: Summary statistics instead of detailed records
SELECT
  consumer_category,
  consumer_subcategory,
  priority_level,
  
  -- Volume
  COUNT(*) AS total_jobs,
  COUNT(DISTINCT principal_email) AS unique_users,
  COUNT(DISTINCT project_id) AS unique_projects,
  COUNT(DISTINCT DATE(start_time)) AS active_days,
  
  -- QoS
  COUNTIF(qos_status = 'QoS_MET') AS qos_met,
  COUNTIF(qos_status = 'QoS_VIOLATION') AS qos_violations,
  ROUND(COUNTIF(qos_status = 'QoS_VIOLATION') / NULLIF(COUNTIF(qos_status IN ('QoS_MET', 'QoS_VIOLATION')), 0) * 100, 2) AS qos_violation_pct,
  
  -- Performance
  ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) AS median_execution_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) AS p95_execution_seconds,
  
  -- Resources
  ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count,
  SUM(total_slot_ms) AS total_slot_ms,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS total_slot_hours,
  
  -- Cost (slot-based pricing)
  ROUND(SUM(estimated_slot_cost_usd), 2) AS total_estimated_cost_usd,
  ROUND(AVG(estimated_slot_cost_usd), 6) AS avg_cost_per_job_usd

FROM traffic_classified
GROUP BY consumer_category, consumer_subcategory, priority_level
ORDER BY priority_level, total_jobs DESC;

-- ============================================================================
-- CLASSIFICATION DIAGNOSTICS
-- ============================================================================
-- Purpose: Investigate unclassified and misclassified traffic
-- Requires: traffic_classified temp table from vw_traffic_classification.sql
-- 
-- Usage: Run these queries after creating traffic_classified temp table
-- ============================================================================

-- ============================================================================
-- DIAGNOSTIC 1: MONITOR_UNMATCHED Analysis
-- ============================================================================
-- Problem: 70% of external traffic (407,640 jobs) has no retailer attribution
-- Goal: Understand which monitor projects aren't matching

-- Top unmatched monitor projects
SELECT -- DIAGNOSTIC 1: MONITOR_UNMATCHED Analysis
  'Monitor Projects - Top Unmatched' AS diagnostic,
  project_id,
  principal_email,
  COUNT(*) as job_count,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS slot_hours,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 2) AS pct_of_unmatched,
  
  -- Sample project ID patterns to understand naming
  ARRAY_AGG(DISTINCT SUBSTR(project_id, 1, 20) LIMIT 5) AS sample_project_ids

FROM traffic_classified
WHERE consumer_subcategory = 'MONITOR_UNMATCHED'
GROUP BY project_id, principal_email
ORDER BY job_count DESC
LIMIT 30;

-- ============================================================================

-- Analyze monitor project naming patterns
SELECT -- Analyze monitor project naming patterns
  'Monitor Project Patterns' AS diagnostic,
  REGEXP_EXTRACT(project_id, r'(monitor-[a-z0-9]{7})-.*') AS project_pattern,
  COUNT(DISTINCT project_id) AS unique_projects,
  COUNT(*) as total_jobs,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS slot_hours

FROM traffic_classified
WHERE consumer_subcategory = 'MONITOR_UNMATCHED'
GROUP BY project_pattern
ORDER BY total_jobs DESC
LIMIT 20;

-- ============================================================================
-- DIAGNOSTIC 2: SERVICE_ACCOUNT_OTHER Analysis
-- ============================================================================
-- Problem: 281,116 jobs (7.4%) from unclassified service accounts
-- Goal: Identify which service accounts need classification patterns

SELECT -- DIAGNOSTIC 2: SERVICE_ACCOUNT_OTHER Analysis
  'Service Accounts - Unclassified' AS diagnostic,
  principal_email,
  COUNT(*) as job_count,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS slot_hours,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 2) AS pct_of_unclassified,
  
  -- Identify patterns in the email
  CASE 
    WHEN REGEXP_CONTAINS(LOWER(principal_email), r'dataform') THEN 'DATAFORM'
    WHEN REGEXP_CONTAINS(LOWER(principal_email), r'cloud-run') THEN 'CLOUD_RUN'
    WHEN REGEXP_CONTAINS(LOWER(principal_email), r'scheduler') THEN 'SCHEDULER'
    WHEN REGEXP_CONTAINS(LOWER(principal_email), r'workflow') THEN 'WORKFLOW'
    WHEN REGEXP_CONTAINS(LOWER(principal_email), r'firebase') THEN 'FIREBASE'
    WHEN REGEXP_CONTAINS(LOWER(principal_email), r'appengine') THEN 'APP_ENGINE'
    WHEN REGEXP_CONTAINS(LOWER(principal_email), r'cloudbuild') THEN 'CLOUD_BUILD'
    WHEN REGEXP_CONTAINS(LOWER(principal_email), r'dbt') THEN 'DBT'
    ELSE 'OTHER'
  END AS suggested_category,
  
  -- Sample projects to understand context
  ARRAY_AGG(DISTINCT project_id LIMIT 5) AS sample_projects,
  
  -- QoS insights
  ROUND(AVG(execution_time_seconds), 2) AS avg_exec_seconds,
  ROUND(AVG(approximate_slot_count), 2) AS avg_slot_count

FROM traffic_classified
WHERE consumer_subcategory = 'SERVICE_ACCOUNT_OTHER'
GROUP BY principal_email
ORDER BY job_count DESC
LIMIT 50;

-- ============================================================================
-- DIAGNOSTIC 3: AUTOMATED → ADHOC_USER Anomaly
-- ============================================================================
-- Problem: 5,352 jobs classified as AUTOMATED but subcategory is ADHOC_USER
-- Goal: Understand if this is correct or a classification bug

SELECT -- DIAGNOSTIC 3: AUTOMATED → ADHOC_USER Anomaly
  'Automated ADHOC_USER Anomaly' AS diagnostic,
  principal_email,
  project_id,
  COUNT(*) as job_count,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS slot_hours,
  ROUND(AVG(execution_time_seconds), 2) AS avg_exec_seconds,
  
  -- Check if these are actually user emails or service accounts
  CASE 
    WHEN REGEXP_CONTAINS(principal_email, r'@narvar\.com$') THEN 'HUMAN_USER'
    WHEN REGEXP_CONTAINS(principal_email, r'iam\.gserviceaccount\.com$') THEN 'SERVICE_ACCOUNT'
    ELSE 'UNKNOWN'
  END AS email_type

FROM traffic_classified
WHERE consumer_category = 'AUTOMATED' 
  AND consumer_subcategory = 'ADHOC_USER'
GROUP BY principal_email, project_id
ORDER BY job_count DESC
LIMIT 30;

-- ============================================================================
-- DIAGNOSTIC 4: Classification Coverage Summary
-- ============================================================================
-- Overall health check of classification

SELECT -- DIAGNOSTIC 4: Classification Coverage Summary
  'Classification Coverage' AS metric,
  consumer_category,
  consumer_subcategory,
  COUNT(*) AS job_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 2) AS pct_of_total,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS slot_hours,
  ROUND(SUM(total_slot_ms) / SUM(SUM(total_slot_ms)) OVER() * 100, 2) AS pct_of_slots,
  COUNT(DISTINCT principal_email) AS unique_principals,
  COUNT(DISTINCT project_id) AS unique_projects

FROM traffic_classified
GROUP BY consumer_category, consumer_subcategory
ORDER BY job_count DESC;

-- ============================================================================
-- DIAGNOSTIC 5: Retailer Match Success Rate
-- ============================================================================
-- Compare matched vs unmatched monitor projects

SELECT -- DIAGNOSTIC 5: Retailer Match Success Rate
  'Retailer Attribution' AS metric,
  CASE 
    WHEN consumer_subcategory = 'MONITOR' THEN 'Matched'
    WHEN consumer_subcategory = 'MONITOR_UNMATCHED' THEN 'Unmatched'
    ELSE 'Not Monitor'
  END AS match_status,
  COUNT(*) AS job_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 2) AS pct_of_total,
  COUNT(DISTINCT project_id) AS unique_projects,
  COUNT(DISTINCT retailer_moniker) AS unique_retailers,
  ROUND(SUM(total_slot_ms) / 3600000, 2) AS slot_hours

FROM traffic_classified
WHERE consumer_category = 'EXTERNAL'
  AND consumer_subcategory IN ('MONITOR', 'MONITOR_UNMATCHED')
GROUP BY match_status;

-- ============================================================================
-- DIAGNOSTIC 6: Sample Successful Retailer Matches
-- ============================================================================
-- See examples of successful matches to understand pattern

SELECT -- DIAGNOSTIC 6: Sample Successful Retailer Matches
  'Successful Matches - Sample' AS diagnostic,
  retailer_moniker,
  project_id,
  COUNT(*) as job_count

FROM traffic_classified
WHERE consumer_subcategory = 'MONITOR'
  AND retailer_moniker IS NOT NULL
GROUP BY retailer_moniker, project_id
ORDER BY job_count DESC
LIMIT 20;

-- ============================================================================
-- DIAGNOSTIC 7: Compare Retailer Names in Database vs Project IDs
-- ============================================================================
-- This helps identify why matching fails

-- Get retailer tokens from database
WITH retailer_tokens AS ( -- DIAGNOSTIC 7: Compare Retailer Names in Database vs Project IDs
  SELECT DISTINCT
    retailer AS retailer_moniker,
    LOWER(REGEXP_REPLACE(retailer, r'[^a-z0-9]', '')) AS retailer_token,
    LENGTH(REGEXP_REPLACE(retailer, r'[^a-z0-9]', '')) AS token_length
  FROM `narvar-data-lake.reporting.manual_retailer_categories`
  WHERE retailer IS NOT NULL
    AND LENGTH(REGEXP_REPLACE(retailer, r'[^a-z0-9]', '')) >= 3
),

-- Get sample unmatched project IDs
unmatched_projects AS (
  SELECT DISTINCT
    project_id,
    COUNT(*) as job_count
  FROM traffic_classified
  WHERE consumer_subcategory = 'MONITOR_UNMATCHED'
  GROUP BY project_id
  ORDER BY job_count DESC
  LIMIT 10
)

SELECT 
  'Matching Attempt' AS diagnostic,
  up.project_id,
  up.job_count,
  rt.retailer_moniker,
  rt.retailer_token,
  
  -- Try to find any token that appears in the project ID
  CASE 
    WHEN REGEXP_CONTAINS(LOWER(up.project_id), rt.retailer_token) THEN 'POTENTIAL_MATCH'
    ELSE 'NO_MATCH'
  END AS match_status

FROM unmatched_projects up
CROSS JOIN retailer_tokens rt
WHERE REGEXP_CONTAINS(LOWER(up.project_id), rt.retailer_token)
ORDER BY up.job_count DESC, rt.token_length DESC
LIMIT 50;

-- ============================================================================
-- END OF DIAGNOSTICS
-- ============================================================================
-- Next Steps:
-- 1. Review output from each diagnostic
-- 2. Identify patterns in unclassified accounts
-- 3. Add new regex patterns to classification queries
-- 4. Re-run vw_traffic_classification.sql with improved patterns
-- ============================================================================


