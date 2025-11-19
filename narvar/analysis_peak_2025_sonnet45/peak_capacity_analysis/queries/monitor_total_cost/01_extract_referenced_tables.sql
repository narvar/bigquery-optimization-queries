-- ============================================================================
-- Monitor Total Cost Analysis - Phase 1, Step 1
-- Extract Referenced Tables for fashionnova Queries
-- ============================================================================
-- Purpose: Identify all tables/views referenced in fashionnova Monitor queries
-- Method: Extract from query_text_sample, handle both 2-part and 3-part names
-- ============================================================================

DECLARE target_retailer STRING DEFAULT 'fashionnova';
DECLARE target_periods ARRAY<STRING> DEFAULT ['Peak_2024_2025', 'Baseline_2025_Sep_Oct'];

-- ============================================================================
-- STEP 1: Get fashionnova queries with project context
-- ============================================================================
WITH fashionnova_jobs AS (
  SELECT 
    job_id,
    project_id,  -- Needed to qualify 2-part table names
    retailer_moniker,
    analysis_period_label,
    total_slot_ms,
    slot_hours,
    estimated_slot_cost_usd,
    total_billed_bytes,
    execution_time_seconds,
    is_qos_violation,
    query_text_sample,
    reservation_name,
    CASE
      WHEN reservation_name = 'bq-narvar-admin:US.default' THEN 'RESERVED_SHARED_POOL'
      WHEN reservation_name = 'default-pipeline' THEN 'RESERVED_PIPELINE'
      WHEN reservation_name = 'unreserved' THEN 'ON_DEMAND'
      WHEN reservation_name IS NULL THEN 'UNKNOWN'
      ELSE reservation_name
    END as reservation_type
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE retailer_moniker = target_retailer
    AND consumer_subcategory = 'MONITOR'
    AND analysis_period_label IN UNNEST(target_periods)
    AND total_slot_ms IS NOT NULL
    AND query_text_sample IS NOT NULL
),

-- ============================================================================
-- STEP 2: Extract table references (both 2-part and 3-part names)
-- ============================================================================
table_references_extracted AS (
  SELECT
    job_id,
    project_id,
    retailer_moniker,
    analysis_period_label,
    slot_hours,
    estimated_slot_cost_usd,
    total_billed_bytes,
    reservation_type,
    
    -- Extract 3-part names (project.dataset.table)
    ARRAY_CONCAT(
      REGEXP_EXTRACT_ALL(query_text_sample, r'(?i)(?:FROM|JOIN)\s+`([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`'),
      REGEXP_EXTRACT_ALL(query_text_sample, r'(?i)(?:FROM|JOIN)\s+([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)\s')
    ) AS three_part_refs,
    
    -- Extract 2-part names (dataset.table) - need to qualify with project later
    ARRAY_CONCAT(
      REGEXP_EXTRACT_ALL(query_text_sample, r'(?i)(?:FROM|JOIN)\s+`([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`'),
      REGEXP_EXTRACT_ALL(query_text_sample, r'(?i)(?:FROM|JOIN)\s+([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)\s')
    ) AS two_part_refs
    
  FROM fashionnova_jobs
),

-- ============================================================================
-- STEP 3: Process and qualify table references
-- ============================================================================
qualified_references AS (
  -- Process 3-part references (already fully qualified)
  SELECT
    job_id,
    project_id,
    retailer_moniker,
    analysis_period_label,
    slot_hours,
    estimated_slot_cost_usd,
    total_billed_bytes,
    reservation_type,
    ref AS table_reference
  FROM table_references_extracted
  CROSS JOIN UNNEST(three_part_refs) AS ref
  WHERE ref IS NOT NULL AND ref != ''
  
  UNION ALL
  
  -- Process 2-part references (qualify with project_id)
  SELECT
    job_id,
    project_id,
    retailer_moniker,
    analysis_period_label,
    slot_hours,
    estimated_slot_cost_usd,
    total_billed_bytes,
    reservation_type,
    CONCAT(project_id, '.', ref) AS table_reference
  FROM table_references_extracted
  CROSS JOIN UNNEST(two_part_refs) AS ref
  WHERE ref IS NOT NULL 
    AND ref != ''
    -- Filter out obvious false positives from 2-part extraction
    AND NOT REGEXP_CONTAINS(ref, r'(?i)INFORMATION_SCHEMA|gserviceaccount|region-')
    -- Ensure it's actually a 2-part name (exactly 1 dot)
    AND LENGTH(ref) - LENGTH(REPLACE(ref, '.', '')) = 1
),

-- ============================================================================
-- STEP 4: Deduplicate and aggregate by table reference
-- ============================================================================
job_table_references AS (
  SELECT DISTINCT
    job_id,
    retailer_moniker,
    analysis_period_label,
    slot_hours,
    estimated_slot_cost_usd,
    total_billed_bytes,
    reservation_type,
    table_reference
  FROM qualified_references
  WHERE table_reference IS NOT NULL
),

table_usage_summary AS (
  SELECT
    table_reference,
    
    -- Usage metrics
    COUNT(DISTINCT job_id) AS reference_count,
    COUNT(DISTINCT analysis_period_label) AS periods_used,
    
    -- Resource consumption
    SUM(slot_hours) AS total_slot_hours,
    AVG(slot_hours) AS avg_slot_hours_per_query,
    SUM(estimated_slot_cost_usd) AS total_cost_usd,
    AVG(estimated_slot_cost_usd) AS avg_cost_per_query,
    
    -- Data volume
    SUM(total_billed_bytes) / POW(1024, 4) AS total_tb_scanned,
    AVG(total_billed_bytes) / POW(1024, 3) AS avg_gb_per_query,
    
    -- Reservation breakdown
    COUNTIF(reservation_type = 'RESERVED_SHARED_POOL') AS queries_on_reserved,
    COUNTIF(reservation_type = 'ON_DEMAND') AS queries_on_demand,
    
    -- Temporal info
    MIN(analysis_period_label) AS first_seen_period,
    MAX(analysis_period_label) AS last_seen_period,
    
    -- Flag for monitor_base.shipments (special handling)
    REGEXP_CONTAINS(table_reference, r'(?i)monitor[-_]base.*\.shipments') AS is_monitor_base_shipments
    
  FROM job_table_references
  GROUP BY table_reference
),

-- ============================================================================
-- STEP 5: Add table type information (TABLE vs VIEW)
-- ============================================================================
table_with_types AS (
  SELECT
    tus.*,
    
    -- Check if it's a view (try to match with INFORMATION_SCHEMA)
    CASE 
      WHEN v.table_name IS NOT NULL THEN 'VIEW'
      WHEN t.table_name IS NOT NULL THEN 'TABLE'
      ELSE 'UNKNOWN'
    END AS table_type,
    
    -- Mark if view definition is available
    v.view_definition IS NOT NULL AS has_view_definition
    
  FROM table_usage_summary tus
  
  -- Try to match with VIEWS (extract project.dataset.table components)
  LEFT JOIN `region-us`.INFORMATION_SCHEMA.VIEWS v 
    ON tus.table_reference = CONCAT(v.table_catalog, '.', v.table_schema, '.', v.table_name)
  
  -- Try to match with TABLES
  LEFT JOIN `region-us`.INFORMATION_SCHEMA.TABLES t
    ON tus.table_reference = CONCAT(t.table_catalog, '.', t.table_schema, '.', t.table_name)
)

-- ============================================================================
-- OUTPUT: fashionnova Referenced Tables Summary
-- ============================================================================
SELECT
  -- Table identification
  table_reference,
  table_type,
  is_monitor_base_shipments,
  
  -- Usage metrics
  reference_count,
  periods_used,
  
  -- Resource consumption
  ROUND(total_slot_hours, 2) AS total_slot_hours,
  ROUND(avg_slot_hours_per_query, 4) AS avg_slot_hours_per_query,
  ROUND(total_cost_usd, 2) AS total_cost_usd,
  ROUND(avg_cost_per_query, 6) AS avg_cost_per_query,
  
  -- Data volume
  ROUND(total_tb_scanned, 2) AS total_tb_scanned,
  ROUND(avg_gb_per_query, 2) AS avg_gb_per_query,
  
  -- Reservation info
  queries_on_reserved,
  queries_on_demand,
  
  -- Table metadata
  has_view_definition,
  
  -- Temporal
  first_seen_period,
  last_seen_period

FROM table_with_types

ORDER BY total_slot_hours DESC;

-- ============================================================================
-- NOTES & LIMITATIONS
-- ============================================================================
-- 1. Uses query_text_sample (first 500 chars) - may miss tables in longer queries
-- 2. Handles both 2-part (dataset.table) and 3-part (project.dataset.table) names
-- 3. 2-part names are qualified with the job's project_id
-- 4. Focuses on FROM and JOIN clauses to avoid false positives
-- ============================================================================
