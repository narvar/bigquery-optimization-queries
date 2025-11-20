-- fashionnova Cost Breakdown Analysis
-- Goal: Understand where fashionnova's $99,718/year cost comes from
-- Date: 2025-11-19
-- Cost: <$0.10 (uses traffic_classification only, no audit log join)

DECLARE analysis_start_date DATE DEFAULT '2024-09-01';
DECLARE analysis_end_date DATE DEFAULT '2024-10-31';
DECLARE days_in_period INT64 DEFAULT DATE_DIFF(DATE '2024-10-31', DATE '2024-09-01', DAY) + 1;

-- Summary by table and operation
SELECT
  primary_table,
  operation_type,
  user_type,
  
  COUNT(*) as query_count,
  ROUND(SUM(slot_hours), 2) as total_slot_hours,
  ROUND(SUM(slot_hours) * 0.0494, 2) as cost_2mo_usd,
  ROUND((SUM(slot_hours) * 0.0494) * 365.0 / days_in_period, 2) as annualized_cost_usd,
  ROUND(100.0 * SUM(slot_hours) / SUM(SUM(slot_hours)) OVER(), 2) as pct_of_total_cost

FROM (
  SELECT 
    job_id,
    start_time,
    slot_hours,
    query_text_sample,
    
    -- Identify which table/view is being queried
    CASE
      WHEN UPPER(query_text_sample) LIKE '%V_SHIPMENTS%' 
        OR UPPER(query_text_sample) LIKE '%MONITOR_BASE.SHIPMENTS%' THEN 'shipments'
      WHEN UPPER(query_text_sample) LIKE '%V_ORDERS%' 
        OR UPPER(query_text_sample) LIKE '%V_ORDER_ITEMS%'
        OR UPPER(query_text_sample) LIKE '%MONITOR_BASE.ORDERS%' THEN 'orders'
      WHEN UPPER(query_text_sample) LIKE '%V_RETURN%' 
        OR UPPER(query_text_sample) LIKE '%RETURN_ITEM_DETAILS%' THEN 'returns'
      WHEN UPPER(query_text_sample) LIKE '%BENCHMARK%' THEN 'benchmarks'
      ELSE 'other/unknown'
    END as primary_table,
    
    -- Identify operation type
    CASE
      WHEN UPPER(query_text_sample) LIKE '%MERGE%' THEN 'ETL_MERGE'
      WHEN UPPER(query_text_sample) LIKE '%INSERT%' THEN 'ETL_INSERT'
      WHEN UPPER(query_text_sample) LIKE '%CREATE%REPLACE%' THEN 'ETL_CREATE'
      WHEN UPPER(query_text_sample) LIKE '%SELECT%' THEN 'CONSUMPTION'
      ELSE 'OTHER'
    END as operation_type,
    
    -- Identify user type
    CASE
      WHEN principal_email LIKE '%dataflow%' THEN 'Dataflow (ETL)'
      WHEN principal_email LIKE '%airflow%' THEN 'Airflow (ETL)'
      WHEN principal_email LIKE '%appspot%' THEN 'App Engine (ETL)'
      WHEN principal_email LIKE '%metabase%' THEN 'Metabase (Dashboards)'
      WHEN principal_email LIKE '%@narvar.com' THEN 'Internal User'
      ELSE 'Other Service Account'
    END as user_type,
    
    principal_email
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE 1=1
    AND retailer_moniker = 'fashionnova'
    AND consumer_subcategory = 'MONITOR'
    AND DATE(start_time) BETWEEN analysis_start_date AND analysis_end_date
)

GROUP BY primary_table, operation_type, user_type
ORDER BY annualized_cost_usd DESC;

-- Expected insights:
-- - What % of cost is shipments vs orders vs returns?
-- - What % of cost is ETL (MERGE/INSERT) vs consumption (SELECT)?
-- - What % of cost is automated (Dataflow/Airflow) vs interactive (users/dashboards)?
-- - Does annualized cost match the $99,718 estimate?
