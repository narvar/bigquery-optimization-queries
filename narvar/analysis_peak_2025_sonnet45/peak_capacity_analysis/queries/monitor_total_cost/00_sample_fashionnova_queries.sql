-- Sample fashionnova queries to understand table reference patterns

DECLARE target_retailer STRING DEFAULT 'fashionnova';

WITH fashionnova_sample AS (
  SELECT 
    job_id,
    query_text_sample,
    slot_hours,
    total_billed_bytes / POW(1024, 3) AS gb_scanned
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE retailer_moniker = target_retailer
    AND consumer_subcategory = 'MONITOR'
    AND analysis_period_label = 'Peak_2024_2025'
    AND total_slot_ms IS NOT NULL
  ORDER BY slot_hours DESC
  LIMIT 20
)

SELECT * FROM fashionnova_sample;

