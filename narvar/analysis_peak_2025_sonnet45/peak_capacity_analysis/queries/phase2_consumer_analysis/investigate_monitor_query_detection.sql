-- Deep Investigation: How are Monitor queries classified?
-- Julia says Gap/Kohls used Monitor, but we show zero consumption
-- Need to understand Monitor query detection logic

-- ============================================================================
-- HYPOTHESIS 1: retailer_moniker is NOT populated for Monitor queries
-- ============================================================================

-- Check Monitor queries WITHOUT retailer_moniker
SELECT
  'H1: Monitor queries with NULL retailer_moniker' as hypothesis,
  consumer_subcategory,
  COUNT(*) as query_count,
  SUM(estimated_slot_cost_usd) as cost_usd,
  ARRAY_AGG(DISTINCT project_id LIMIT 5) as sample_projects,
  ARRAY_AGG(DISTINCT principal_email LIMIT 5) as sample_users
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND consumer_subcategory = 'MONITOR'
  AND retailer_moniker IS NULL
GROUP BY consumer_subcategory;

-- ============================================================================
-- HYPOTHESIS 2: Monitor queries are classified differently
-- ============================================================================

-- Check all consumer_subcategory values for external/monitor projects
SELECT
  'H2: Monitor project queries by subcategory' as hypothesis,
  consumer_subcategory,
  COUNT(*) as query_count,
  SUM(estimated_slot_cost_usd) as cost_usd,
  ARRAY_AGG(DISTINCT project_id LIMIT 10) as sample_projects
FROM `narvar-data-lake.query_opt.traffic_classification`  
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND (
    project_id LIKE 'monitor-%'
    OR principal_email LIKE '%monitor%'
  )
GROUP BY consumer_subcategory
ORDER BY query_count DESC;

-- ============================================================================
-- HYPOTHESIS 3: Check how retailer_moniker is extracted
-- ============================================================================

-- Sample 20 Monitor queries to see retailer_moniker pattern
SELECT
  'H3: Sample Monitor queries with retailer context' as hypothesis,
  retailer_moniker,
  project_id,
  consumer_subcategory,
  LEFT(query_text_sample, 300) as query_sample
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND consumer_subcategory = 'MONITOR'
  AND retailer_moniker IS NOT NULL
ORDER BY RAND()
LIMIT 20;

-- ============================================================================
-- HYPOTHESIS 4: Check classification logic in traffic_classification table
-- ============================================================================

-- How is consumer_subcategory = 'MONITOR' determined?
-- Check the classification patterns
SELECT
  'H4: MONITOR classification patterns' as hypothesis,
  project_id,
  consumer_category,
  consumer_subcategory,
  COUNT(*) as query_count,
  COUNT(DISTINCT retailer_moniker) as unique_retailers,
  SUM(estimated_slot_cost_usd) as cost_usd
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND consumer_subcategory = 'MONITOR'
GROUP BY project_id, consumer_category, consumer_subcategory
ORDER BY query_count DESC
LIMIT 20;

