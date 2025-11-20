-- fashionnova Sample Coverage Analysis
-- Goal: Understand what % of queries we can analyze for latency/retention
-- Date: 2025-11-19
-- Cost: ~$3-5 (6-month scan)

WITH fashionnova_queries AS (
  SELECT 
    t.job_id,
    t.start_time,
    t.slot_hours,
    t.query_text_sample,
    a.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query as full_query_text
    
  FROM `narvar-data-lake.query_opt.traffic_classification` t
  LEFT JOIN `doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` a
    ON t.job_id = a.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId
  
  WHERE 1=1
    AND t.retailer_moniker = 'fashionnova'
    AND t.consumer_subcategory = 'MONITOR'
    AND DATE(t.start_time) BETWEEN '2024-05-01' AND '2024-10-31'  -- 6 months
)

SELECT 
  '1. Total fashionnova queries' as analysis_step,
  COUNT(*) as query_count,
  SUM(slot_hours) as total_slot_hours,
  ROUND(SUM(slot_hours) * 0.0494, 2) as estimated_cost_usd,
  NULL as percentage

FROM fashionnova_queries

UNION ALL

SELECT
  '2. Have full query text from audit logs',
  COUNT(*),
  SUM(slot_hours),
  ROUND(SUM(slot_hours) * 0.0494, 2),
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
FROM fashionnova_queries
WHERE full_query_text IS NOT NULL

UNION ALL

SELECT
  '3. Have timestamp filters (ship_date)',
  COUNT(*),
  SUM(slot_hours),
  ROUND(SUM(slot_hours) * 0.0494, 2),
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
FROM fashionnova_queries
WHERE (full_query_text LIKE '%ship_date%' OR query_text_sample LIKE '%ship_date%')

UNION ALL

SELECT
  '4. Have timestamp filters (order_date)',
  COUNT(*),
  SUM(slot_hours),
  ROUND(SUM(slot_hours) * 0.0494, 2),
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
FROM fashionnova_queries
WHERE (full_query_text LIKE '%order_date%' OR query_text_sample LIKE '%order_date%')

UNION ALL

SELECT
  '5. Have timestamp filters (delivery_date)',
  COUNT(*),
  SUM(slot_hours),
  ROUND(SUM(slot_hours) * 0.0494, 2),
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
FROM fashionnova_queries
WHERE (full_query_text LIKE '%delivery_date%' OR query_text_sample LIKE '%delivery_date%')

UNION ALL

SELECT
  '6. Have ANY timestamp filter',
  COUNT(*),
  SUM(slot_hours),
  ROUND(SUM(slot_hours) * 0.0494, 2),
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
FROM fashionnova_queries
WHERE (
  full_query_text LIKE '%ship_date%' 
  OR full_query_text LIKE '%order_date%'
  OR full_query_text LIKE '%delivery_date%'
  OR query_text_sample LIKE '%ship_date%'
  OR query_text_sample LIKE '%order_date%'
  OR query_text_sample LIKE '%delivery_date%'
)

UNION ALL

SELECT
  '7. No timestamp filter found',
  COUNT(*),
  SUM(slot_hours),
  ROUND(SUM(slot_hours) * 0.0494, 2),
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
FROM fashionnova_queries
WHERE NOT (
  full_query_text LIKE '%ship_date%' 
  OR full_query_text LIKE '%order_date%'
  OR full_query_text LIKE '%delivery_date%'
  OR query_text_sample LIKE '%ship_date%'
  OR query_text_sample LIKE '%order_date%'
  OR query_text_sample LIKE '%delivery_date%'
)

ORDER BY analysis_step;

-- Expected output: A funnel showing:
-- - Total queries
-- - % with full text
-- - % with each timestamp type
-- - % we can analyze for latency/retention
--
-- This determines confidence level for subsequent analysis


