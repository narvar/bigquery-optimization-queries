-- fashionnova Retention Requirements Analysis
-- Goal: Understand historical data requirements - how far back do queries look?
-- Date: 2025-11-19
-- Cost: <$0.10 (traffic_classification only, 6 months)

-- Analysis approach:
-- 1. Extract date range filters from query_text_sample
-- 2. Calculate maximum lookback period
-- 3. Distribute into retention buckets: 3mo, 6mo, 1yr, >1yr
-- 4. Determine: What % of queries need >1 year of historical data?

WITH fashionnova_queries AS (
  SELECT 
    job_id,
    start_time,
    DATE(start_time) as query_date,
    slot_hours,
    query_text_sample,
    
    -- Extract explicit dates from ship_date filters
    REGEXP_EXTRACT_ALL(query_text_sample, r"'([0-9]{4}-[0-9]{2}-[0-9]{2})'") as extracted_dates,
    
    -- Identify date range patterns
    CASE
      WHEN UPPER(query_text_sample) LIKE '%INTERVAL%DAY%' THEN 'interval_days'
      WHEN UPPER(query_text_sample) LIKE '%INTERVAL%MONTH%' THEN 'interval_months'
      WHEN UPPER(query_text_sample) LIKE '%INTERVAL%YEAR%' THEN 'interval_years'
      WHEN REGEXP_CONTAINS(query_text_sample, r"BETWEEN.*'[0-9]{4}") THEN 'explicit_range'
      WHEN REGEXP_CONTAINS(query_text_sample, r"ship_date\s*>=?\s*'[0-9]{4}") THEN 'single_date_filter'
      ELSE 'no_parseable_filter'
    END as range_pattern
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE 1=1
    AND retailer_moniker = 'fashionnova'
    AND consumer_subcategory = 'MONITOR'
    AND DATE(start_time) BETWEEN '2024-09-01' AND '2024-10-31'  -- 2 months
),

lookback_calculation AS (
  SELECT
    *,
    -- Calculate lookback period for queries with extractable dates
    CASE
      WHEN ARRAY_LENGTH(extracted_dates) > 0 THEN
        DATE_DIFF(
          query_date,
          DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)),
          DAY
        )
      ELSE NULL
    END as lookback_days,
    
    -- Categorize retention requirement
    CASE
      WHEN range_pattern = 'interval_days' THEN 'A_last_N_days'
      WHEN range_pattern = 'interval_months' THEN 'B_last_N_months'
      WHEN range_pattern = 'interval_years' THEN 'C_last_N_years'
      WHEN ARRAY_LENGTH(extracted_dates) > 0 THEN
        CASE
          WHEN DATE_DIFF(query_date, DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)), DAY) <= 90 
            THEN 'D_last_3_months'
          WHEN DATE_DIFF(query_date, DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)), DAY) <= 180 
            THEN 'E_last_6_months'
          WHEN DATE_DIFF(query_date, DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)), DAY) <= 365 
            THEN 'F_last_1_year'
          WHEN DATE_DIFF(query_date, DATE((SELECT MIN(d) FROM UNNEST(extracted_dates) as d)), DAY) <= 730 
            THEN 'G_last_2_years'
          ELSE 'H_more_than_2_years'
        END
      ELSE 'Z_cannot_determine'
    END as retention_category
  FROM fashionnova_queries
)

-- Summary by retention category
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
ORDER BY retention_category;

-- Expected insights:
-- - X% of queries look back <3 months (3-month retention sufficient)
-- - Y% of queries look back <6 months (6-month retention sufficient)
-- - Z% of queries look back <1 year (1-year retention sufficient)
-- - Remaining queries need >1 year (long retention or archive strategy)
--
-- Limitations:
-- - 500-char truncation may miss date ranges in complex queries
-- - INTERVAL patterns need manual interpretation (flagged separately)
-- - Some queries may have multiple date filters (we use MIN date = max lookback)


