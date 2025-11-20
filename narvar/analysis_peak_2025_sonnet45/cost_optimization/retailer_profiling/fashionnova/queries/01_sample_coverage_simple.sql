-- fashionnova Sample Coverage Analysis (SIMPLE VERSION)
-- Goal: Understand what % of queries we can analyze using 500-char sample
-- Date: 2025-11-19
-- Cost: <$0.10 (traffic_classification only, no audit log join)

WITH fashionnova_queries AS (
  SELECT 
    job_id,
    start_time,
    slot_hours,
    query_text_sample
    
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE 1=1
    AND retailer_moniker = 'fashionnova'
    AND consumer_subcategory = 'MONITOR'
    AND DATE(start_time) BETWEEN '2024-05-01' AND '2024-10-31'  -- 6 months
)

SELECT 
  analysis_step,
  query_count,
  total_slot_hours,
  cost_6mo_usd,
  annualized_cost_usd,
  percentage

FROM (
  SELECT 
    '1_TOTAL' as analysis_step,
    COUNT(*) as query_count,
    ROUND(SUM(slot_hours), 2) as total_slot_hours,
    ROUND(SUM(slot_hours) * 0.0494, 2) as cost_6mo_usd,
    ROUND((SUM(slot_hours) * 0.0494) * 365.0 / 183, 2) as annualized_cost_usd,
    CAST(100.0 AS FLOAT64) as percentage
  FROM fashionnova_queries

  UNION ALL

  SELECT
    '2_has_ship_date_filter',
    COUNT(*),
    ROUND(SUM(slot_hours), 2),
    ROUND(SUM(slot_hours) * 0.0494, 2),
    ROUND((SUM(slot_hours) * 0.0494) * 365.0 / 183, 2),
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
  FROM fashionnova_queries
  WHERE UPPER(query_text_sample) LIKE '%SHIP_DATE%'

  UNION ALL

  SELECT
    '3_has_order_date_filter',
    COUNT(*),
    ROUND(SUM(slot_hours), 2),
    ROUND(SUM(slot_hours) * 0.0494, 2),
    ROUND((SUM(slot_hours) * 0.0494) * 365.0 / 183, 2),
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
  FROM fashionnova_queries
  WHERE UPPER(query_text_sample) LIKE '%ORDER_DATE%'

  UNION ALL

  SELECT
    '4_has_delivery_date_filter',
    COUNT(*),
    ROUND(SUM(slot_hours), 2),
    ROUND(SUM(slot_hours) * 0.0494, 2),
    ROUND((SUM(slot_hours) * 0.0494) * 365.0 / 183, 2),
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
  FROM fashionnova_queries
  WHERE UPPER(query_text_sample) LIKE '%DELIVERY_DATE%'

  UNION ALL

  SELECT
    '5_has_ANY_date_filter',
    COUNT(*),
    ROUND(SUM(slot_hours), 2),
    ROUND(SUM(slot_hours) * 0.0494, 2),
    ROUND((SUM(slot_hours) * 0.0494) * 365.0 / 183, 2),
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
  FROM fashionnova_queries
  WHERE (
    UPPER(query_text_sample) LIKE '%SHIP_DATE%'
    OR UPPER(query_text_sample) LIKE '%ORDER_DATE%'
    OR UPPER(query_text_sample) LIKE '%DELIVERY_DATE%'
  )

  UNION ALL

  SELECT
    '6_no_date_filter_visible',
    COUNT(*),
    ROUND(SUM(slot_hours), 2),
    ROUND(SUM(slot_hours) * 0.0494, 2),
    ROUND((SUM(slot_hours) * 0.0494) * 365.0 / 183, 2),
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fashionnova_queries), 2)
  FROM fashionnova_queries
  WHERE NOT (
    UPPER(query_text_sample) LIKE '%SHIP_DATE%'
    OR UPPER(query_text_sample) LIKE '%ORDER_DATE%'
    OR UPPER(query_text_sample) LIKE '%DELIVERY_DATE%'
  )
)

ORDER BY analysis_step;

-- Note: 183 days = 6 months (May 1 - Oct 31)
-- This shows coverage based on 500-char sample only
-- Limitation: Date filters may be beyond char 500 in complex queries

