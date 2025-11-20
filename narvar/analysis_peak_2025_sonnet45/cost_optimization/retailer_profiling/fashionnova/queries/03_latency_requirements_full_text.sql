-- fashionnova Latency Requirements Analysis (FULL QUERY TEXT)
-- Goal: Understand data freshness requirements using complete queries from audit logs
-- Date: 2025-11-19
-- Cost: ~$0.90 (177 GB - audit log join for 2 months)

WITH fashionnova_full_queries AS (
  SELECT 
    t.job_id,
    t.start_time,
    DATE(t.start_time) as query_date,
    t.slot_hours,
    COALESCE(
      a.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query,
      t.query_text_sample
    ) as full_query_text
    
  FROM `narvar-data-lake.query_opt.traffic_classification` t
  LEFT JOIN `doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` a
    ON t.job_id = a.protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId
  
  WHERE 1=1
    AND t.retailer_moniker = 'fashionnova'
    AND t.consumer_subcategory = 'MONITOR'
    AND DATE(t.start_time) BETWEEN '2024-09-01' AND '2024-10-31'  -- 2 months
),

date_extraction AS (
  SELECT
    *,
    -- Identify filter pattern
    CASE
      WHEN UPPER(full_query_text) LIKE '%CURRENT_DATE()%' 
        OR UPPER(full_query_text) LIKE '%CURRENT_DATE%' THEN 'uses_current_date'
      WHEN UPPER(full_query_text) LIKE '%DATE_SUB%CURRENT_DATE%' THEN 'uses_date_sub'
      WHEN REGEXP_CONTAINS(full_query_text, r"ship_date.*'[0-9]{4}-[0-9]{2}-[0-9]{2}'") THEN 'explicit_ship_date'
      WHEN REGEXP_CONTAINS(full_query_text, r"order_date.*'[0-9]{4}-[0-9]{2}-[0-9]{2}'") THEN 'explicit_order_date'
      WHEN REGEXP_CONTAINS(full_query_text, r"BETWEEN.*'[0-9]{4}") THEN 'date_range'
      ELSE 'no_date_filter'
    END as filter_pattern,
    
    -- Extract all dates from the query
    REGEXP_EXTRACT_ALL(full_query_text, r"'([0-9]{4}-[0-9]{2}-[0-9]{2})'") as extracted_dates,
    
    -- Extract INTERVAL values (e.g., INTERVAL 30 DAY)
    REGEXP_EXTRACT(full_query_text, r"INTERVAL\s+([0-9]+)\s+DAY") as interval_days

  FROM fashionnova_full_queries
),

freshness_calculation AS (
  SELECT
    *,
    -- Calculate data age for queries with extractable dates
    CASE
      WHEN filter_pattern = 'uses_current_date' THEN 0  -- Querying today's data = real-time
      WHEN interval_days IS NOT NULL THEN CAST(interval_days AS INT64)  -- Last N days
      WHEN ARRAY_LENGTH(extracted_dates) > 0 THEN
        -- Find the most recent date in the query (MIN age = most recent data needed)
        DATE_DIFF(
          query_date,
          DATE((SELECT MAX(d) FROM UNNEST(extracted_dates) as d)),
          DAY
        )
      ELSE NULL
    END as data_age_days
  FROM date_extraction
),

freshness_categorization AS (
  SELECT
    *,
    -- Categorize by latency requirement
    CASE
      WHEN data_age_days IS NULL THEN 'Z_cannot_determine'
      WHEN data_age_days = 0 THEN 'A_real_time_today'
      WHEN data_age_days <= 1 THEN 'B_near_time_1hr_24hr'
      WHEN data_age_days <= 7 THEN 'C_last_week'
      WHEN data_age_days <= 30 THEN 'D_last_month'
      WHEN data_age_days <= 90 THEN 'E_last_quarter'
      ELSE 'F_historical_old'
    END as latency_bucket
  FROM freshness_calculation
)

-- Final aggregation
SELECT
  latency_bucket,
  filter_pattern,
  
  COUNT(*) as query_count,
  ROUND(SUM(slot_hours), 2) as total_slot_hours,
  ROUND(SUM(slot_hours) * 0.0494, 2) as cost_2mo_usd,
  ROUND((SUM(slot_hours) * 0.0494) * 12.0 / 2.0, 2) as annualized_cost_usd,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as pct_queries,
  ROUND(100.0 * SUM(slot_hours) / SUM(SUM(slot_hours)) OVER(), 2) as pct_cost,
  
  ROUND(AVG(data_age_days), 1) as avg_data_age_days,
  MIN(data_age_days) as min_data_age_days,
  MAX(data_age_days) as max_data_age_days

FROM freshness_categorization
GROUP BY latency_bucket, filter_pattern
ORDER BY latency_bucket, annualized_cost_usd DESC;

-- Expected insights:
-- - X% of queries (by cost) need data <1 hour old (real-time required)
-- - Y% can tolerate 1-24 hour delays (near-time acceptable)
-- - Z% query historical data (batch processing is fine)
--
-- Decision criteria:
-- - If >80% of COST is from queries using data >6 hours old → 6-hour batching safe
-- - If >90% of COST is from queries using data >24 hours old → daily batching safe


