-- ============================================================================
-- Query: Explore DoIT Costs Table Schema
-- Purpose: Understand the structure and available fields in the costs table
-- Source: narvar-data-lake.doitintl_cmp_bq.costs
-- ============================================================================
-- 
-- This query will help us understand:
-- 1. What columns are available
-- 2. Date range of data
-- 3. Sample values for key fields
--
-- Estimated Scan: <1 MB (LIMIT 5)
-- ============================================================================

-- Sample rows to see schema
SELECT *
FROM `narvar-data-lake.doitintl_cmp_bq.costs`
LIMIT 5;

-- Get column information (if INFORMATION_SCHEMA is accessible)
-- Uncomment if you want to see full schema:
/*
SELECT
  column_name,
  data_type,
  is_nullable
FROM `narvar-data-lake.doitintl_cmp_bq.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'costs'
ORDER BY ordinal_position;
*/




