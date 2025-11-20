-- Test: Can we join traffic_classification with audit logs?
-- Goal: Validate we can get full query text for fashionnova queries
-- Date: 2025-11-19

-- Test query to check join feasibility
SELECT 
  t.job_id,
  t.start_time,
  t.slot_hours,
  t.retailer_moniker,
  t.consumer_subcategory,
  LENGTH(t.query_text_sample) as sample_length,
  LENGTH(a.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query) as full_query_length,
  
  -- Check if we get full query text
  CASE 
    WHEN a.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query IS NOT NULL 
      THEN 'FULL_TEXT_AVAILABLE'
    ELSE 'NO_FULL_TEXT'
  END as query_text_status

FROM `narvar-data-lake.query_opt.traffic_classification` t
LEFT JOIN `doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` a
  ON t.job_id = a.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId

WHERE 1=1
  AND t.retailer_moniker = 'fashionnova'
  AND t.consumer_subcategory = 'MONITOR'
  AND DATE(t.start_time) = '2024-10-01'  -- Single day test to reduce cost
  
ORDER BY t.slot_hours DESC
LIMIT 20;

-- Expected output:
-- - If most rows show FULL_TEXT_AVAILABLE: proceed with full text analysis
-- - If most show NO_FULL_TEXT: fall back to 500-char sample analysis
-- - Check avg full_query_length to understand query complexity

