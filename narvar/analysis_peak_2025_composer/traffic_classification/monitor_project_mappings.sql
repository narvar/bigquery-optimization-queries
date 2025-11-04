-- Monitor Project Mappings: Maps retailer_moniker to monitor project IDs
-- Purpose: Identifies external consumers by mapping retailers to their corresponding monitor projects
-- 
-- Monitor projects follow the pattern: monitor-<hash>-us-prod
-- where <hash> is the first 7 characters of the MD5 hash of retailer_moniker
--
-- Usage: Run this query to generate a mapping table/view of retailers to monitor projects
-- This mapping is then used to classify traffic from monitor projects as EXTERNAL_CRITICAL
--
-- Parameters:
--   min_date: Minimum date for retailer data (default: 2025-01-01)
--
-- Output Schema:
--   retailer_moniker: STRING - Name of the retailer
--   project_id: STRING - Corresponding monitor project ID
--
-- Cost Warning: This query processes the reporting.t_return_details table.
--               Estimated cost depends on table size and date range.

DECLARE min_date DATE DEFAULT '2025-01-01';

WITH mappings AS (
  SELECT DISTINCT 
    retailer_moniker, 
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-prod') AS project_id
  FROM `reporting.t_return_details` 
  WHERE DATE(return_created_date) >= min_date
)
SELECT 
  retailer_moniker,
  project_id
FROM mappings
ORDER BY retailer_moniker;

