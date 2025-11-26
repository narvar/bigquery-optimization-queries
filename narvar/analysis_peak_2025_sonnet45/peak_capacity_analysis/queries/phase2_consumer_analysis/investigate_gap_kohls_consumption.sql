-- Investigation: Why do Gap and Kohls show zero consumption?
-- Julia confirms they used Monitor in last 90 days
-- Need to check if our logic is missing their queries

-- ============================================================================
-- PART 1: Check if Gap/Kohls have ANY queries in traffic_classification
-- ============================================================================

-- Check all consumer categories for Gap and Kohls
SELECT
  'Part 1: Any queries for Gap/Kohls in last 90 days?' as check_type,
  retailer_moniker,
  consumer_category,
  consumer_subcategory,
  COUNT(*) as query_count,
  SUM(slot_hours) as slot_hours,
  SUM(estimated_slot_cost_usd) as cost_usd,
  MIN(DATE(start_time)) as first_query,
  MAX(DATE(start_time)) as last_query
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND LOWER(retailer_moniker) IN ('gap', 'kohls')
GROUP BY retailer_moniker, consumer_category, consumer_subcategory
ORDER BY retailer_moniker, query_count DESC;

-- ============================================================================
-- PART 2: Check if queries exist but with different consumer_subcategory
-- ============================================================================

SELECT
  'Part 2: Gap/Kohls queries by consumer_subcategory' as check_type,
  retailer_moniker,
  consumer_subcategory,
  COUNT(*) as query_count,
  SUM(estimated_slot_cost_usd) as cost_usd,
  ARRAY_AGG(DISTINCT project_id LIMIT 5) as sample_projects
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND LOWER(retailer_moniker) IN ('gap', 'kohls')
GROUP BY retailer_moniker, consumer_subcategory
ORDER BY retailer_moniker, query_count DESC;

-- ============================================================================
-- PART 3: Sample actual queries to understand what they're doing
-- ============================================================================

SELECT
  'Part 3: Sample Gap/Kohls queries' as check_type,
  retailer_moniker,
  project_id,
  principal_email,
  consumer_category,
  consumer_subcategory,
  DATE(start_time) as query_date,
  execution_time_seconds,
  slot_hours,
  estimated_slot_cost_usd,
  LEFT(query_text_sample, 200) as query_sample
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND LOWER(retailer_moniker) IN ('gap', 'kohls')
ORDER BY start_time DESC
LIMIT 20;

-- ============================================================================
-- PART 4: Check if retailer_moniker exists but consumer_subcategory != 'MONITOR'
-- ============================================================================

SELECT
  'Part 4: Non-MONITOR queries for Gap/Kohls' as check_type,
  retailer_moniker,
  consumer_subcategory,
  COUNT(*) as query_count,
  SUM(estimated_slot_cost_usd) as cost_usd,
  ARRAY_AGG(DISTINCT principal_email LIMIT 5) as sample_users
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND LOWER(retailer_moniker) IN ('gap', 'kohls')
  AND consumer_subcategory != 'MONITOR'
GROUP BY retailer_moniker, consumer_subcategory
ORDER BY retailer_moniker, query_count DESC;

-- ============================================================================
-- PART 5: Check if case sensitivity is an issue
-- ============================================================================

SELECT
  'Part 5: Check retailer_moniker variations' as check_type,
  retailer_moniker,
  COUNT(*) as query_count
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND (
    LOWER(retailer_moniker) = 'gap' 
    OR LOWER(retailer_moniker) = 'kohls'
    OR retailer_moniker LIKE '%gap%'
    OR retailer_moniker LIKE '%kohls%'
  )
GROUP BY retailer_moniker
ORDER BY query_count DESC;

