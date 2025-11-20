-- fashionnova Retention Requirements Analysis (FULL QUERY TEXT)
-- Goal: Understand historical data requirements using complete queries from audit logs
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

date_range_extraction AS (
  SELECT
    *,
    -- Extract all dates from the query
    REGEXP_EXTRACT_ALL(full_query_text, r"'([0-9]{4}-[0-9]{2}-[0-9]{2})'") as extracted_dates,
    
    -- Extract INTERVAL patterns
    REGEXP_EXTRACT(full_query_text, r"INTERVAL\s+([0-9]+)\s+DAY") as interval_days,
    REGEXP_EXTRACT(full_query_text, r"INTERVAL\s+([0-9]+)\s+MONTH") as interval_months,
    REGEXP_EXTRACT(full_query_text, r"INTERVAL\s+([0-9]+)\s+YEAR") as interval_years,
    
    -- Identify range pattern type
    CASE
      WHEN UPPER(full_query_text) LIKE '%INTERVAL%DAY%' THEN 'interval_days'
      WHEN UPPER(full_query_text) LIKE '%INTERVAL%MONTH%' THEN 'interval_months'
      WHEN UPPER(full_query_text) LIKE '%INTERVAL%YEAR%' THEN 'interval_years'
      WHEN REGEXP_CONTAINS(full_query_text, r"BETWEEN.*'[0-9]{4}") THEN 'explicit_range'
      WHEN REGEXP_CONTAINS(full_query_text, r"(ship_date|order_date|delivery_date)\s*>=?") THEN 'single_date_filter'
      ELSE 'no_date_filter'
    END as range_pattern

  FROM fashionnova_full_queries
),

lookback_calculation AS (
  SELECT
    *,
    -- Calculate maximum lookback period (how far back the query looks)
    CASE
      -- INTERVAL patterns: Use the interval value
      WHEN interval_days IS NOT NULL THEN CAST(interval_days AS INT64)
      WHEN interval_months IS NOT NULL THEN CAST(interval_months AS INT64) * 30
      WHEN interval_years IS NOT NULL THEN CAST(interval_years AS INT64) * 365
      
      -- Explicit dates: Find the oldest date (maximum lookback)
      WHEN ARRAY_LENGTH(extracted_dates) > 0 THEN
        DATE_DIFF(
          query_date,
          DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)),  -- Oldest date = max lookback
          DAY
        )
      ELSE NULL
    END as lookback_days,
    
    -- Categorize retention requirement
    CASE
      WHEN interval_days IS NOT NULL THEN
        CASE
          WHEN CAST(interval_days AS INT64) <= 30 THEN 'B_last_month_30days'
          WHEN CAST(interval_days AS INT64) <= 90 THEN 'C_last_quarter_90days'
          WHEN CAST(interval_days AS INT64) <= 180 THEN 'D_last_6months'
          WHEN CAST(interval_days AS INT64) <= 365 THEN 'E_last_year'
          ELSE 'F_more_than_1year'
        END
      WHEN interval_months IS NOT NULL THEN
        CASE
          WHEN CAST(interval_months AS INT64) <= 3 THEN 'C_last_quarter_90days'
          WHEN CAST(interval_months AS INT64) <= 6 THEN 'D_last_6months'
          WHEN CAST(interval_months AS INT64) <= 12 THEN 'E_last_year'
          ELSE 'F_more_than_1year'
        END
      WHEN interval_years IS NOT NULL THEN 'F_more_than_1year'
      WHEN ARRAY_LENGTH(extracted_dates) > 0 THEN
        CASE
          WHEN DATE_DIFF(query_date, DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)), DAY) <= 30 
            THEN 'B_last_month_30days'
          WHEN DATE_DIFF(query_date, DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)), DAY) <= 90 
            THEN 'C_last_quarter_90days'
          WHEN DATE_DIFF(query_date, DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)), DAY) <= 180 
            THEN 'D_last_6months'
          WHEN DATE_DIFF(query_date, DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)), DAY) <= 365 
            THEN 'E_last_year'
          WHEN DATE_DIFF(query_date, DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)), DAY) <= 730 
            THEN 'G_last_2years'
          ELSE 'H_more_than_2years'
        END
      ELSE 'Z_cannot_determine'
    END as retention_category
  FROM date_range_extraction
)

-- Final aggregation
SELECT
  retention_category,
  range_pattern,
  
  COUNT(*) as query_count,
  ROUND(SUM(slot_hours), 2) as total_slot_hours,
  ROUND(SUM(slot_hours) * 0.0494, 2) as cost_2mo_usd,
  ROUND((SUM(slot_hours) * 0.0494) * 12.0 / 2.0, 2) as annualized_cost_usd,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as pct_queries,
  ROUND(100.0 * SUM(slot_hours) / SUM(SUM(slot_hours)) OVER(), 2) as pct_cost,
  
  ROUND(AVG(lookback_days), 1) as avg_lookback_days,
  MIN(lookback_days) as min_lookback_days,
  MAX(lookback_days) as max_lookback_days

FROM lookback_calculation
GROUP BY retention_category, range_pattern
ORDER BY retention_category, annualized_cost_usd DESC;

-- Expected insights:
-- - X% of queries (by cost) look back <3 months (3-month retention sufficient)
-- - Y% look back <6 months (6-month retention sufficient)
-- - Z% look back <1 year (1-year retention sufficient)
-- - Remaining need >1 year (archive strategy or long retention)
--
-- Decision criteria:
-- - If >90% of COST looks back <6 months → 1-year retention is safe (save $16K-$18K)
-- - If >95% of COST looks back <1 year → 2-year retention is safe (save $14K-$16K)


