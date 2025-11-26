-- Create Retailer → Monitor Project ID Mapping
-- Purpose: Map MD5-based project IDs to retailer names
-- Used to resolve audit log hashes to readable names

-- The Monitor platform creates project IDs using MD5 hash:
-- monitor-{FIRST_7_CHARS_OF_MD5_HEX}-us-prod
-- e.g., "gap" → MD5 → a679b28... → "monitor-a679b28-us-prod"

WITH retailer_list AS (
  -- Get all retailers from shipments table
  SELECT DISTINCT retailer_moniker
  FROM `monitor-base-us-prod.monitor_base.shipments`
  WHERE retailer_moniker IS NOT NULL
    AND retailer_moniker != ''
)

SELECT
  retailer_moniker,
  -- Generate the production project ID
  CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 1, 7), '-us-prod') AS project_id_prod,
  -- Generate QA project ID
  CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 1, 7), '-us-qa') AS project_id_qa,
  -- Generate staging project ID  
  CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 1, 7), '-us-stg') AS project_id_stg,
  -- Also store the hash for matching
  SUBSTR(TO_HEX(MD5(retailer_moniker)), 1, 7) AS md5_hash
FROM retailer_list
ORDER BY retailer_moniker;

