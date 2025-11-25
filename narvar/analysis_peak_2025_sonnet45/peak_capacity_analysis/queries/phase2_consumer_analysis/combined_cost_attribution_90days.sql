-- Combined Cost Attribution: Shipments + Orders + Returns (90-Day Consistent Window)
-- Purpose: Merge all three production cost tables into a single retailer view
-- IMPORTANT: All tables use the same 90-day lookback window for accurate comparison
--
-- Time Period: Last 90 days from query execution date (consistent across all sources)
--
-- Cost Calculation: Pro-rated from annual costs for 90-day period
--   Shipments: $176,556/year * (90/365) = $43,449 for 90 days
--   Orders: $45,302/year * (90/365) = $11,157 for 90 days
--   Returns: $11,871/year * (90/365) = $2,923 for 90 days
--

WITH shipments_data AS (
  SELECT 
    retailer_moniker,
    COUNT(*) as shipment_count,
    -- Pro-rated cost: $176,556 annual * (90/365) = $43,449
    ROUND(43449 * (COUNT(*) / SUM(COUNT(*)) OVER()), 2) as shipments_cost_usd
  FROM `monitor-base-us-prod.monitor_base.shipments`
  WHERE retailer_moniker IS NOT NULL
    -- Using atlas_created_ts (Atlas ingestion timestamp)
    AND atlas_created_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  GROUP BY retailer_moniker
),

orders_data AS (
  SELECT 
    retailer_moniker,
    COUNT(*) as order_count,
    -- Pro-rated cost: $45,302 annual * (90/365) = $11,157
    ROUND(11157 * (COUNT(*) / SUM(COUNT(*)) OVER()), 2) as orders_cost_usd
  FROM `monitor-base-us-prod.monitor_base.orders`
  WHERE retailer_moniker IS NOT NULL
    AND order_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  GROUP BY retailer_moniker
),

returns_data AS (
  SELECT 
    retailer_moniker,
    COUNT(*) as return_count,
    -- Pro-rated cost: $11,871 annual * (90/365) = $2,923
    ROUND(2923 * (COUNT(*) / SUM(COUNT(*)) OVER()), 2) as returns_cost_usd
  FROM `narvar-data-lake.reporting.t_return_details`
  WHERE return_created_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
    AND retailer_moniker IS NOT NULL
  GROUP BY retailer_moniker
),

consumption_data AS (
  SELECT
    retailer_moniker,
    SUM(estimated_slot_cost_usd) as consumption_cost_usd,
    SUM(slot_hours) as consumption_slot_hours,
    COUNT(*) as query_count,
    MIN(DATE(start_time)) as first_query_date,
    MAX(DATE(start_time)) as last_query_date
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
    AND consumer_subcategory = 'MONITOR'
  GROUP BY retailer_moniker
),

combined AS (
  SELECT
    COALESCE(s.retailer_moniker, o.retailer_moniker, r.retailer_moniker, c.retailer_moniker) as retailer_moniker,
    
    -- Volume metrics
    COALESCE(s.shipment_count, 0) as shipment_count,
    COALESCE(o.order_count, 0) as order_count,
    COALESCE(r.return_count, 0) as return_count,
    
    -- Production costs
    COALESCE(s.shipments_cost_usd, 0) as shipments_production_cost_usd,
    COALESCE(o.orders_cost_usd, 0) as orders_production_cost_usd,
    COALESCE(r.returns_cost_usd, 0) as returns_production_cost_usd,
    
    -- Total production cost
    COALESCE(s.shipments_cost_usd, 0) + COALESCE(o.orders_cost_usd, 0) + COALESCE(r.returns_cost_usd, 0) as total_production_cost_usd,
    
    -- Consumption metrics
    COALESCE(c.consumption_cost_usd, 0) as consumption_cost_usd,
    COALESCE(c.consumption_slot_hours, 0) as consumption_slot_hours,
    COALESCE(c.query_count, 0) as query_count,
    c.first_query_date,
    c.last_query_date
    
  FROM shipments_data s
  FULL OUTER JOIN orders_data o ON s.retailer_moniker = o.retailer_moniker
  FULL OUTER JOIN returns_data r ON COALESCE(s.retailer_moniker, o.retailer_moniker) = r.retailer_moniker
  FULL OUTER JOIN consumption_data c ON COALESCE(s.retailer_moniker, o.retailer_moniker, r.retailer_moniker) = c.retailer_moniker
)

SELECT
  retailer_moniker,
  
  -- Volume
  shipment_count,
  order_count,
  return_count,
  
  -- Production costs by table
  shipments_production_cost_usd,
  orders_production_cost_usd,
  returns_production_cost_usd,
  total_production_cost_usd,
  
  -- Consumption metrics
  consumption_cost_usd,
  consumption_slot_hours,
  query_count,
  
  -- Query activity period
  first_query_date,
  last_query_date,
  DATE_DIFF(COALESCE(last_query_date, CURRENT_DATE()), COALESCE(first_query_date, CURRENT_DATE()), DAY) + 1 as query_days_active,
  
  -- Queries per day (handle division by zero)
  CASE 
    WHEN query_count > 0 AND first_query_date IS NOT NULL AND last_query_date IS NOT NULL 
    THEN ROUND(query_count / NULLIF(DATE_DIFF(last_query_date, first_query_date, DAY) + 1, 0), 2)
    ELSE 0.0
  END as avg_queries_per_day,
  
  -- Total cost
  total_production_cost_usd + consumption_cost_usd as total_cost_usd,
  
  -- Ratios
  ROUND(consumption_cost_usd / NULLIF(total_production_cost_usd, 0), 4) as consumption_to_production_ratio,
  ROUND(consumption_cost_usd / NULLIF(total_production_cost_usd + consumption_cost_usd, 0), 4) as consumption_pct_of_total
  
FROM combined
WHERE total_production_cost_usd > 0 OR consumption_cost_usd > 0
ORDER BY total_cost_usd DESC;
-- Removed LIMIT 100 to get ALL retailers

-- ============================================================================
-- METADATA QUERY: Run this separately to see actual time periods covered
-- ============================================================================
-- SELECT 
--   'Analysis Configuration' as metric,
--   DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) as intended_start_date,
--   CURRENT_DATE() as intended_end_date,
--   90 as intended_days,
--   DATE(CURRENT_TIMESTAMP()) as query_run_date;

-- SELECT 
--   'Consumption Data Coverage' as metric,
--   MIN(DATE(start_time)) as actual_start_date,
--   MAX(DATE(start_time)) as actual_end_date,
--   DATE_DIFF(MAX(DATE(start_time)), MIN(DATE(start_time)), DAY) + 1 as actual_days_covered
-- FROM `narvar-data-lake.query_opt.traffic_classification`
-- WHERE DATE(start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
--   AND consumer_subcategory = 'MONITOR';
