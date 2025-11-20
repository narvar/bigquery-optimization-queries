-- fashionnova Latency Requirements Analysis
-- Goal: Understand data freshness requirements - how old is data when queried?
-- Date: 2025-11-19
-- Cost: <$0.10 (traffic_classification only, 6 months)

-- Analysis approach:
-- 1. Extract date filters from query_text_sample (500 chars)
-- 2. Identify the latest date being queried
-- 3. Calculate: query_time - max_date_in_filter = "data age when queried"
-- 4. Distribute into buckets: real-time, near-time, same-day, historical

WITH fashionnova_queries AS (
  SELECT 
    job_id,
    start_time,
    DATE(start_time) as query_date,
    slot_hours,
    query_text_sample,
    
    -- Extract date-related patterns
    CASE
      WHEN UPPER(query_text_sample) LIKE '%CURRENT_DATE()%' 
        OR UPPER(query_text_sample) LIKE '%CURRENT_DATE%' THEN 'uses_current_date'
      WHEN UPPER(query_text_sample) LIKE '%DATE_SUB%CURRENT_DATE%' THEN 'uses_date_sub'
      WHEN REGEXP_CONTAINS(query_text_sample, r"ship_date.*'[0-9]{4}-[0-9]{2}-[0-9]{2}'") THEN 'explicit_date'
      WHEN REGEXP_CONTAINS(query_text_sample, r"ship_date.*BETWEEN") THEN 'date_range'
      ELSE 'no_parseable_filter'
    END as filter_pattern,
    
    -- Try to extract explicit dates (ship_date >= '2024-10-15' pattern)
    REGEXP_EXTRACT(query_text_sample, r"ship_date[^']*'([0-9]{4}-[0-9]{2}-[0-9]{2})'") as extracted_date
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE 1=1
    AND retailer_moniker = 'fashionnova'
    AND consumer_subcategory = 'MONITOR'
    AND DATE(start_time) BETWEEN '2024-09-01' AND '2024-10-31'  -- 2 months
),

date_freshness AS (
  SELECT
    *,
    -- Calculate data age (days between query and data being queried)
    CASE
      WHEN filter_pattern = 'uses_current_date' THEN 0  -- Querying today's data
      WHEN filter_pattern = 'no_parseable_filter' THEN NULL  -- Can't determine
      WHEN extracted_date IS NOT NULL THEN DATE_DIFF(query_date, DATE(extracted_date), DAY)
      ELSE NULL
    END as data_age_days,
    
    -- Categorize freshness requirement
    CASE
      WHEN filter_pattern = 'uses_current_date' THEN 'A_realtime_today'
      WHEN filter_pattern = 'uses_date_sub' THEN 'B_near_time_last_N_days'
      WHEN extracted_date IS NOT NULL AND DATE_DIFF(query_date, DATE(extracted_date), DAY) <= 1 THEN 'C_same_day_yesterday_today'
      WHEN extracted_date IS NOT NULL AND DATE_DIFF(query_date, DATE(extracted_date), DAY) <= 7 THEN 'D_last_week'
      WHEN extracted_date IS NOT NULL AND DATE_DIFF(query_date, DATE(extracted_date), DAY) <= 30 THEN 'E_last_month'
      WHEN extracted_date IS NOT NULL THEN 'F_historical_older'
      ELSE 'Z_cannot_determine'
    END as freshness_category
  FROM fashionnova_queries
)

-- Summary by freshness category
SELECT
  freshness_category,
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

FROM date_freshness
GROUP BY freshness_category, filter_pattern
ORDER BY freshness_category;

-- Expected insights:
-- - X% of queries need real-time data (CURRENT_DATE)
-- - Y% can tolerate 6-hour delays
-- - Z% can tolerate 24-hour delays
-- - Remaining are historical queries (batch is fine)
--
-- Limitations:
-- - 500-char truncation may miss filters in complex queries (27.9% of queries)
-- - DATE_SUB patterns need manual parsing (flagged as "near_time")
-- - BETWEEN ranges need both dates extracted (flagged as "date_range")


