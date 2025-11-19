-- Cost Breakdown: Shipments vs Orders Pipeline
-- Goal: Understand the $149,832 "shipments" cost attribution
-- Date: 2025-11-19

-- Step 1: Identify all jobs related to monitor_base.shipments table
-- Look for MERGE, INSERT, UPDATE, SELECT operations

WITH shipments_jobs AS (
  SELECT
    job_id,
    principal_email,
    DATE(start_time) as job_date,
    job_type,
    CASE 
      WHEN UPPER(query_text_sample) LIKE '%MERGE%' THEN 'MERGE'
      WHEN UPPER(query_text_sample) LIKE '%INSERT%' THEN 'INSERT'
      WHEN UPPER(query_text_sample) LIKE '%UPDATE%' THEN 'UPDATE'
      WHEN UPPER(query_text_sample) LIKE '%CREATE%REPLACE%' THEN 'CREATE_OR_REPLACE'
      ELSE 'OTHER'
    END as operation_type,
    total_slot_ms,
    slot_hours,
    total_billed_bytes,
    total_billed_gb,
    project_id,
    consumer_subcategory,
    query_text_sample
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE 1=1
    -- Focus on shipments table references
    AND UPPER(query_text_sample) LIKE '%SHIPMENTS%'
    -- Exclude consumer queries (focus on ETL/production)
    AND consumer_category != 'EXTERNAL'
    -- Baseline period for comparison
    AND DATE(start_time) BETWEEN '2024-09-01' AND '2024-10-31'
),

orders_jobs AS (
  SELECT
    job_id,
    principal_email,
    DATE(start_time) as job_date,
    job_type,
    CASE 
      WHEN UPPER(query_text_sample) LIKE '%INSERT%' THEN 'INSERT'
      WHEN UPPER(query_text_sample) LIKE '%CREATE%REPLACE%' THEN 'CREATE_OR_REPLACE'
      ELSE 'OTHER'
    END as operation_type,
    total_slot_ms,
    slot_hours,
    total_billed_bytes,
    total_billed_gb,
    project_id,
    consumer_subcategory,
    query_text_sample
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE 1=1
    -- Focus on orders table references
    AND UPPER(query_text_sample) LIKE '%ORDERS%'
    -- Exclude consumer queries
    AND consumer_category != 'EXTERNAL'
    -- Exclude shipments jobs (avoid double-counting)
    AND NOT UPPER(query_text_sample) LIKE '%SHIPMENTS%'
    AND DATE(start_time) BETWEEN '2024-09-01' AND '2024-10-31'
)

-- Shipments Pipeline Analysis
SELECT
  'SHIPMENTS' as pipeline,
  operation_type,
  principal_email,
  project_id,
  COUNT(*) as job_count,
  SUM(slot_hours) as total_slot_hours,
  ROUND(SUM(slot_hours) * 0.0494, 2) as estimated_cost_usd,  -- Reserved pricing
  ROUND(AVG(total_billed_gb), 2) as avg_gb_processed,
  ROUND(SUM(total_billed_gb) / 1024, 2) as total_tb_processed
FROM shipments_jobs
GROUP BY pipeline, operation_type, principal_email, project_id

UNION ALL

-- Orders Pipeline Analysis
SELECT
  'ORDERS' as pipeline,
  operation_type,
  principal_email,
  project_id,
  COUNT(*) as job_count,
  SUM(slot_hours) as total_slot_hours,
  ROUND(SUM(slot_hours) * 0.0494, 2) as estimated_cost_usd,
  ROUND(AVG(total_billed_gb), 2) as avg_gb_processed,
  ROUND(SUM(total_billed_gb) / 1024, 2) as total_tb_processed
FROM orders_jobs
GROUP BY pipeline, operation_type, principal_email, project_id

ORDER BY pipeline, estimated_cost_usd DESC;

