-- ============================================================================
-- Recursive View Resolution for ALL Monitor Views
-- ============================================================================
-- Purpose: Trace all 9 Monitor views to their root base tables
-- Method: Recursive CTE following view definitions until reaching actual tables
-- Input: Eric's authoritative list of 9 views used by Monitor retailers
-- ============================================================================

-- Eric's 9 views (replicated across ~1800 retailer projects)
-- We'll use fashionnova's project as example: monitor-a679b28-us-prod
DECLARE sample_project STRING DEFAULT 'monitor-a679b28-us-prod';
DECLARE sample_dataset STRING DEFAULT 'monitor';

-- ============================================================================
-- STEP 1: Start with the 9 views from Eric's list
-- ============================================================================
WITH initial_views AS (
  SELECT view_name, 1 AS depth_level
  FROM UNNEST([
    'v_shipments',
    'v_shipments_events',
    'v_shipments_transposed',
    'v_orders',
    'v_order_items',
    'v_return_details',
    'v_return_rate_agg',
    'v_benchmark_tnt',
    'v_benchmark_ft'
  ]) AS view_name
),

-- ============================================================================
-- STEP 2: Get view definitions from INFORMATION_SCHEMA
-- ============================================================================
-- Note: This will get definitions from multiple catalogs since views reference
-- tables across projects (monitor-base-us-prod, narvar-data-lake, etc.)
-- ============================================================================

-- Level 0: Initial views in retailer project
level_0_views AS (
  SELECT
    iv.view_name AS original_view_name,
    CONCAT(sample_project, '.', sample_dataset, '.', iv.view_name) AS full_view_name,
    iv.view_name AS current_view_name,
    0 AS resolution_level,
    v.view_definition,
    'INITIAL' AS view_source
  FROM initial_views iv
  LEFT JOIN `region-us`.INFORMATION_SCHEMA.VIEWS v
    ON v.table_catalog = sample_project
    AND v.table_schema = sample_dataset
    AND v.table_name = iv.view_name
),

-- Extract table references from level 0 view definitions
level_0_refs AS (
  SELECT
    original_view_name,
    full_view_name AS parent_view,
    0 AS resolution_level,
    
    -- Extract all table references (both 2-part and 3-part)
    ARRAY_CONCAT(
      -- 3-part: project.dataset.table
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`?([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`?'),
      -- 2-part: dataset.table (need to qualify later)
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`?([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`?\s')
    ) AS table_refs
    
  FROM level_0_views
  WHERE view_definition IS NOT NULL
),

-- Flatten level 0 references
level_0_flattened AS (
  SELECT DISTINCT
    original_view_name,
    parent_view,
    resolution_level,
    -- Qualify 2-part names with sample project
    CASE
      WHEN LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 2 THEN ref  -- Already 3-part
      WHEN LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 1 THEN CONCAT(sample_project, '.', ref)  -- 2-part, qualify
      ELSE ref
    END AS referenced_table
  FROM level_0_refs
  CROSS JOIN UNNEST(table_refs) AS ref
  WHERE ref IS NOT NULL 
    AND ref != ''
    -- Filter obvious false positives
    AND NOT REGEXP_CONTAINS(ref, r'(?i)INFORMATION_SCHEMA|gserviceaccount|region-')
),

-- ============================================================================
-- STEP 3: Check which level 0 references are views (need level 1 resolution)
-- ============================================================================
level_1_views AS (
  SELECT DISTINCT
    l0.original_view_name,
    l0.parent_view,
    l0.referenced_table AS view_name,
    1 AS resolution_level,
    v.view_definition
  FROM level_0_flattened l0
  INNER JOIN `region-us`.INFORMATION_SCHEMA.VIEWS v
    ON l0.referenced_table = CONCAT(v.table_catalog, '.', v.table_schema, '.', v.table_name)
),

-- Extract references from level 1 views
level_1_refs AS (
  SELECT
    original_view_name,
    view_name AS parent_view,
    resolution_level,
    ARRAY_CONCAT(
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`?([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`?'),
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`?([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`?\s')
    ) AS table_refs,
    -- Extract project from parent view for qualifying 2-part names
    SPLIT(view_name, '.')[OFFSET(0)] AS parent_project
  FROM level_1_views
  WHERE view_definition IS NOT NULL
),

level_1_flattened AS (
  SELECT DISTINCT
    original_view_name,
    parent_view,
    resolution_level,
    CASE
      WHEN LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 2 THEN ref
      WHEN LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 1 THEN CONCAT(parent_project, '.', ref)
      ELSE ref
    END AS referenced_table
  FROM level_1_refs
  CROSS JOIN UNNEST(table_refs) AS ref
  WHERE ref IS NOT NULL 
    AND ref != ''
    AND NOT REGEXP_CONTAINS(ref, r'(?i)INFORMATION_SCHEMA|gserviceaccount|region-')
),

-- ============================================================================
-- STEP 4: Level 2 resolution
-- ============================================================================
level_2_views AS (
  SELECT DISTINCT
    l1.original_view_name,
    l1.parent_view,
    l1.referenced_table AS view_name,
    2 AS resolution_level,
    v.view_definition
  FROM level_1_flattened l1
  INNER JOIN `region-us`.INFORMATION_SCHEMA.VIEWS v
    ON l1.referenced_table = CONCAT(v.table_catalog, '.', v.table_schema, '.', v.table_name)
),

level_2_refs AS (
  SELECT
    original_view_name,
    view_name AS parent_view,
    resolution_level,
    ARRAY_CONCAT(
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`?([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`?'),
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`?([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`?\s')
    ) AS table_refs,
    SPLIT(view_name, '.')[OFFSET(0)] AS parent_project
  FROM level_2_views
  WHERE view_definition IS NOT NULL
),

level_2_flattened AS (
  SELECT DISTINCT
    original_view_name,
    parent_view,
    resolution_level,
    CASE
      WHEN LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 2 THEN ref
      WHEN LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 1 THEN CONCAT(parent_project, '.', ref)
      ELSE ref
    END AS referenced_table
  FROM level_2_refs
  CROSS JOIN UNNEST(table_refs) AS ref
  WHERE ref IS NOT NULL 
    AND ref != ''
    AND NOT REGEXP_CONTAINS(ref, r'(?i)INFORMATION_SCHEMA|gserviceaccount|region-')
),

-- ============================================================================
-- STEP 5: Level 3 resolution (one more level for deep nesting)
-- ============================================================================
level_3_views AS (
  SELECT DISTINCT
    l2.original_view_name,
    l2.parent_view,
    l2.referenced_table AS view_name,
    3 AS resolution_level,
    v.view_definition
  FROM level_2_flattened l2
  INNER JOIN `region-us`.INFORMATION_SCHEMA.VIEWS v
    ON l2.referenced_table = CONCAT(v.table_catalog, '.', v.table_schema, '.', v.table_name)
),

level_3_refs AS (
  SELECT
    original_view_name,
    view_name AS parent_view,
    resolution_level,
    ARRAY_CONCAT(
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`?([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`?'),
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`?([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`?\s')
    ) AS table_refs,
    SPLIT(view_name, '.')[OFFSET(0)] AS parent_project
  FROM level_3_views
  WHERE view_definition IS NOT NULL
),

level_3_flattened AS (
  SELECT DISTINCT
    original_view_name,
    parent_view,
    resolution_level,
    CASE
      WHEN LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 2 THEN ref
      WHEN LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 1 THEN CONCAT(parent_project, '.', ref)
      ELSE ref
    END AS referenced_table
  FROM level_3_refs
  CROSS JOIN UNNEST(table_refs) AS ref
  WHERE ref IS NOT NULL 
    AND ref != ''
    AND NOT REGEXP_CONTAINS(ref, r'(?i)INFORMATION_SCHEMA|gserviceaccount|region-')
),

-- ============================================================================
-- STEP 6: Combine all levels and identify base tables vs views
-- ============================================================================
all_references AS (
  SELECT original_view_name, parent_view, resolution_level, referenced_table
  FROM level_0_flattened
  
  UNION ALL
  
  SELECT original_view_name, parent_view, resolution_level, referenced_table
  FROM level_1_flattened
  
  UNION ALL
  
  SELECT original_view_name, parent_view, resolution_level, referenced_table
  FROM level_2_flattened
  
  UNION ALL
  
  SELECT original_view_name, parent_view, resolution_level, referenced_table
  FROM level_3_flattened
),

-- Check if each reference is a view or table
references_with_types AS (
  SELECT
    ar.*,
    CASE
      WHEN v.table_name IS NOT NULL THEN 'VIEW'
      WHEN t.table_name IS NOT NULL THEN 'TABLE'
      ELSE 'UNKNOWN'
    END AS object_type
  FROM all_references ar
  
  LEFT JOIN `region-us`.INFORMATION_SCHEMA.VIEWS v
    ON ar.referenced_table = CONCAT(v.table_catalog, '.', v.table_schema, '.', v.table_name)
  
  LEFT JOIN `region-us`.INFORMATION_SCHEMA.TABLES t
    ON ar.referenced_table = CONCAT(t.table_catalog, '.', t.table_schema, '.', t.table_name)
)

-- ============================================================================
-- OUTPUT 1: Complete Dependency Tree
-- ============================================================================
SELECT
  original_view_name,
  parent_view,
  resolution_level,
  referenced_table,
  object_type,
  CASE
    WHEN object_type = 'TABLE' THEN '✅ BASE TABLE (need production cost)'
    WHEN object_type = 'VIEW' AND resolution_level >= 3 THEN '⚠️ VIEW - MAX DEPTH REACHED'
    WHEN object_type = 'VIEW' THEN '🔄 VIEW - needs further resolution'
    ELSE '❓ UNKNOWN - investigate'
  END AS resolution_status
FROM references_with_types
ORDER BY 
  original_view_name,
  resolution_level,
  referenced_table;

-- ============================================================================
-- OUTPUT 2: Unique Base Tables Summary (for audit log search)
-- ============================================================================
-- Uncomment to get just the base tables:
-- SELECT DISTINCT
--   referenced_table AS base_table,
--   COUNT(DISTINCT original_view_name) AS used_by_n_views,
--   STRING_AGG(DISTINCT original_view_name ORDER BY original_view_name) AS used_by_views
-- FROM references_with_types
-- WHERE object_type = 'TABLE'
-- GROUP BY referenced_table
-- ORDER BY used_by_n_views DESC, referenced_table;

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. Resolves up to 3 levels deep (view → view → view → table)
-- 2. Handles both 2-part and 3-part table references
-- 3. Cross-project references (monitor-base-us-prod, narvar-data-lake)
-- 4. Next step: Search audit logs for production costs of base tables
-- ============================================================================

