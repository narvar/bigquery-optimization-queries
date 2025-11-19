-- ============================================================================
-- Analysis: Ruban's Vertex/BQ Job Cost
-- Job ID: narvar-research:US.bquxjob_7348b1fb_19a3575a172
-- User: rubanpreet.sran@narvar.com
-- Date: Oct 30-31, 2025
-- ============================================================================

-- QUERY 1: Get Exact Cost from DoIT Billing (Authoritative Source)
-- Verifies the actual charge incurred
SELECT
  job_id,
  cost,
  reservation_id,
  start_time
FROM `narvar-data-lake.doitintl_cmp_bq.costs`
WHERE
  DATE(start_time) BETWEEN '2025-10-30' AND '2025-10-31'
  AND job_id = 'bquxjob_7348b1fb_19a3575a172';

-- QUERY 2: Get Job Execution Details & Pricing Metadata
-- Verifies the pricing model (On-Demand vs Reserved) and Job Type
SELECT
  job_id,
  job_type,
  query_text_sample,
  total_billed_bytes / POW(1024, 4) as tb_billed,
  slot_hours,
  reservation_name
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE job_id = 'bquxjob_7348b1fb_19a3575a172';

-- QUERY 3: Check Project-Level Reservation Status
-- Determines if the project is generally Reserved or Hybrid
SELECT 
  reservation_name, 
  COUNT(*) as job_count, 
  SUM(total_slot_ms)/3600000 as total_slot_hours 
FROM `narvar-data-lake.query_opt.traffic_classification` 
WHERE 
  project_id = 'narvar-research' 
  AND start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY) 
GROUP BY reservation_name;
