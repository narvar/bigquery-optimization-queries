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
SELECT 
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
SELECT 
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

SELECT 
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

SELECT 
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

SELECT 
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

SELECT 
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

SELECT 
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
WITH retailer_tokens AS (
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

