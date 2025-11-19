-- Shipments Cost Decomposition
-- Goal: Break down the $149,832 "shipments compute" cost into components
-- Method: Replicate the Method A calculation from SHIPMENTS_PRODUCTION_COST.md
-- Date: 2025-11-19

-- From the original analysis:
-- - Total slot-hours: 502,456 (over 18 months = Sep 2023 - Feb 2025)
-- - This represented 24.18% of BQ reservation
-- - Applied to $619,598 annual BQ cost = $149,832

-- Question: What types of jobs contribute to those 502,456 slot-hours?

WITH shipments_related_jobs AS (
  SELECT
    job_id,
    principal_email,
    DATE(start_time) as job_date,
    EXTRACT(YEAR FROM start_time) as year,
    EXTRACT(MONTH FROM start_time) as month,
    job_type,
    
    -- Categorize by operation
    CASE 
      WHEN UPPER(query_text_sample) LIKE '%MERGE%INTO%SHIPMENTS%' THEN 'MERGE_SHIPMENTS'
      WHEN UPPER(query_text_sample) LIKE '%MERGE%' THEN 'MERGE_OTHER'
      WHEN UPPER(query_text_sample) LIKE '%INSERT%SHIPMENTS%' THEN 'INSERT_SHIPMENTS'
      WHEN UPPER(query_text_sample) LIKE '%UPDATE%SHIPMENTS%' THEN 'UPDATE_SHIPMENTS'
      WHEN UPPER(query_text_sample) LIKE '%SELECT%SHIPMENTS%' THEN 'SELECT_FROM_SHIPMENTS'
      WHEN UPPER(query_text_sample) LIKE '%CREATE%REPLACE%' THEN 'CREATE_OR_REPLACE'
      ELSE 'OTHER'
    END as operation_category,
    
    -- Categorize by user/service
    CASE
      WHEN principal_email LIKE '%dataflow%' THEN 'Dataflow'
      WHEN principal_email LIKE '%airflow%' THEN 'Airflow'
      WHEN principal_email LIKE '%appengine%' THEN 'App Engine'
      WHEN principal_email LIKE '%appspot%' THEN 'App Engine'
      WHEN principal_email LIKE '%cloudrun%' THEN 'Cloud Run'
      WHEN principal_email LIKE '%@narvar.com' THEN 'Human User'
      ELSE 'Other Service Account'
    END as service_type,
    
    total_slot_ms,
    slot_hours,
    total_billed_bytes,
    total_billed_gb,
    project_id,
    reservation_name,
    query_text_sample
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE 1=1
    -- Match the original query pattern from SHIPMENTS_PRODUCTION_COST.md
    AND (
      UPPER(query_text_sample) LIKE '%MERGE%'
      OR UPPER(query_text_sample) LIKE '%INSERT%'
      OR UPPER(query_text_sample) LIKE '%UPDATE%'
    )
    AND UPPER(query_text_sample) LIKE '%SHIPMENTS%'
    
    -- Use 18-month period like original analysis (Sep 2023 - Feb 2025)
    AND DATE(start_time) BETWEEN '2023-09-01' AND '2025-02-28'
)

SELECT
  service_type,
  operation_category,
  project_id,
  
  -- Counts and volumes
  COUNT(*) as job_count,
  COUNT(DISTINCT job_date) as days_active,
  ROUND(COUNT(*) * 1.0 / NULLIF(COUNT(DISTINCT job_date), 0), 2) as jobs_per_day,
  
  -- Slot-hours and costs
  ROUND(SUM(slot_hours), 2) as total_slot_hours,
  ROUND(SUM(slot_hours) * 0.0494, 2) as estimated_cost_18mo_usd,
  ROUND((SUM(slot_hours) * 0.0494) * 12.0 / 18.0, 2) as annualized_cost_usd,
  
  -- Percentage of total shipments cost
  ROUND(100.0 * SUM(slot_hours) / SUM(SUM(slot_hours)) OVER(), 2) as pct_of_total_slot_hours,
  
  -- Bytes processed
  ROUND(SUM(total_billed_gb) / 1024, 2) as total_tb_processed,
  ROUND(AVG(total_billed_gb), 2) as avg_gb_per_job

FROM shipments_related_jobs
GROUP BY service_type, operation_category, project_id
ORDER BY total_slot_hours DESC;

-- Summary totals for validation
-- Expected: ~502,456 slot-hours total (matching original analysis)

