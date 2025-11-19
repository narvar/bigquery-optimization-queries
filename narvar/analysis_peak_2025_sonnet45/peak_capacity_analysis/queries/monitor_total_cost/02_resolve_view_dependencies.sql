-- ============================================================================
-- Monitor Total Cost Analysis - Phase 1, Step 2
-- Resolve View Dependencies Recursively
-- ============================================================================
-- Purpose: For views found in Step 1, extract their base tables
-- Method: Parse view definitions to find underlying tables (up to 3 levels)
-- ============================================================================

-- Input: Tables identified in Step 1
-- Note: In production, this would read from the CSV, but for now we'll hardcode
-- the fashionnova tables found in Step 1

WITH fashionnova_tables AS (
  -- Tables identified in Step 1
  SELECT table_reference
  FROM UNNEST([
    'monitor-a679b28-us-prod.monitor.v_shipments',
    'monitor-a679b28-us-prod.monitor.v_shipments_events',
    'monitor-a679b28-us-prod.monitor.v_benchmark_ft',
    'monitor-a679b28-us-prod.monitor.v_return_details',
    'monitor-a679b28-us-prod.monitor.v_return_rate_agg'
  ]) AS table_reference
),

-- ============================================================================
-- STEP 1: Get view definitions from INFORMATION_SCHEMA
-- ============================================================================
view_definitions AS (
  SELECT
    ft.table_reference AS view_name,
    CONCAT(v.table_catalog, '.', v.table_schema, '.', v.table_name) AS view_full_name,
    v.view_definition,
    1 AS resolution_level
  FROM fashionnova_tables ft
  INNER JOIN `region-us`.INFORMATION_SCHEMA.VIEWS v
    ON ft.table_reference = CONCAT(v.table_catalog, '.', v.table_schema, '.', v.table_name)
),

-- ============================================================================
-- STEP 2: Extract table references from view definitions
-- ============================================================================
level_1_refs AS (
  SELECT
    view_name,
    resolution_level,
    
    -- Extract 3-part names (project.dataset.table)
    ARRAY_CONCAT(
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`'),
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)\s')
    ) AS three_part_refs,
    
    -- Extract 2-part names (dataset.table) - need to qualify with project
    ARRAY_CONCAT(
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`'),
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)\s')
    ) AS two_part_refs,
    
    -- Extract project for qualifying 2-part names
    SPLIT(view_name, '.')[OFFSET(0)] AS view_project
    
  FROM view_definitions
),

-- ============================================================================
-- STEP 3: Qualify and flatten all references from level 1
-- ============================================================================
level_1_flattened AS (
  -- 3-part references (already qualified)
  SELECT
    view_name,
    resolution_level,
    ref AS base_table_reference
  FROM level_1_refs
  CROSS JOIN UNNEST(three_part_refs) AS ref
  WHERE ref IS NOT NULL AND ref != ''
  
  UNION ALL
  
  -- 2-part references (qualify with view's project)
  SELECT
    view_name,
    resolution_level,
    CONCAT(view_project, '.', ref) AS base_table_reference
  FROM level_1_refs
  CROSS JOIN UNNEST(two_part_refs) AS ref
  WHERE ref IS NOT NULL 
    AND ref != ''
    AND LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 1  -- Exactly 1 dot
),

-- ============================================================================
-- STEP 4: Check if any level 1 references are also views (need level 2)
-- ============================================================================
level_2_views AS (
  SELECT DISTINCT
    l1.view_name AS original_view,
    l1.base_table_reference AS intermediate_view,
    v.view_definition,
    2 AS resolution_level
  FROM level_1_flattened l1
  INNER JOIN `region-us`.INFORMATION_SCHEMA.VIEWS v
    ON l1.base_table_reference = CONCAT(v.table_catalog, '.', v.table_schema, '.', v.table_name)
),

-- ============================================================================
-- STEP 5: Extract references from level 2 views
-- ============================================================================
level_2_refs AS (
  SELECT
    original_view,
    intermediate_view,
    resolution_level,
    
    -- Extract 3-part and 2-part references
    ARRAY_CONCAT(
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`'),
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)\s')
    ) AS three_part_refs,
    
    ARRAY_CONCAT(
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+`([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`'),
      REGEXP_EXTRACT_ALL(view_definition, r'(?i)(?:FROM|JOIN)\s+([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)\s')
    ) AS two_part_refs,
    
    SPLIT(intermediate_view, '.')[OFFSET(0)] AS view_project
    
  FROM level_2_views
),

level_2_flattened AS (
  -- 3-part references
  SELECT
    original_view,
    intermediate_view,
    resolution_level,
    ref AS base_table_reference
  FROM level_2_refs
  CROSS JOIN UNNEST(three_part_refs) AS ref
  WHERE ref IS NOT NULL AND ref != ''
  
  UNION ALL
  
  -- 2-part references
  SELECT
    original_view,
    intermediate_view,
    resolution_level,
    CONCAT(view_project, '.', ref) AS base_table_reference
  FROM level_2_refs
  CROSS JOIN UNNEST(two_part_refs) AS ref
  WHERE ref IS NOT NULL 
    AND ref != ''
    AND LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 1
),

-- ============================================================================
-- STEP 6: Combine all levels and determine final table types
-- ============================================================================
all_dependencies AS (
  -- Level 1: Direct references from original views
  SELECT
    view_name,
    view_name AS path,
    base_table_reference,
    resolution_level
  FROM level_1_flattened
  
  UNION ALL
  
  -- Level 2: References through intermediate views
  SELECT
    original_view AS view_name,
    CONCAT(original_view, ' → ', intermediate_view) AS path,
    base_table_reference,
    resolution_level
  FROM level_2_flattened
),

-- Add table type information
dependencies_with_types AS (
  SELECT
    ad.*,
    CASE 
      WHEN v.table_name IS NOT NULL THEN 'VIEW'
      WHEN t.table_name IS NOT NULL THEN 'TABLE'
      ELSE 'UNKNOWN'
    END AS base_table_type,
    
    -- Flag monitor_base.shipments
    REGEXP_CONTAINS(ad.base_table_reference, r'(?i)monitor[-_]base.*shipments') AS is_monitor_base_shipments
    
  FROM all_dependencies ad
  
  -- Check if base reference is a view
  LEFT JOIN `region-us`.INFORMATION_SCHEMA.VIEWS v
    ON ad.base_table_reference = CONCAT(v.table_catalog, '.', v.table_schema, '.', v.table_name)
  
  -- Check if base reference is a table
  LEFT JOIN `region-us`.INFORMATION_SCHEMA.TABLES t
    ON ad.base_table_reference = CONCAT(t.table_catalog, '.', t.table_schema, '.', t.table_name)
)

-- ============================================================================
-- OUTPUT: View Dependencies with Resolution Status
-- ============================================================================
SELECT
  view_name,
  base_table_reference,
  resolution_level,
  base_table_type,
  is_monitor_base_shipments,
  path AS dependency_path,
  
  -- Resolution status
  CASE
    WHEN base_table_type = 'TABLE' THEN 'RESOLVED'
    WHEN base_table_type = 'VIEW' AND resolution_level < 2 THEN 'NEEDS_DEEPER_RESOLUTION'
    WHEN base_table_type = 'VIEW' AND resolution_level >= 2 THEN 'MAX_DEPTH_REACHED'
    WHEN base_table_type = 'UNKNOWN' THEN 'NOT_FOUND_IN_SCHEMA'
    ELSE 'UNKNOWN_STATUS'
  END AS resolution_status

FROM dependencies_with_types

ORDER BY 
  view_name,
  resolution_level,
  base_table_reference;

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. Resolves views up to 2 levels deep (view → view → table)
-- 2. For deeper nesting, manual investigation recommended
-- 3. Handles both 2-part and 3-part table references
-- 4. Flags monitor_base.shipments for special cost attribution
-- ============================================================================

