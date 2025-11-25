-- Combined Cost Attribution: Shipments + Orders + Returns
-- Purpose: Merge all three production cost tables into a single retailer view

WITH shipments_data AS (
  SELECT 
    retailer_moniker,
    COUNT(*) as shipment_count,
    ROUND(176556 * (COUNT(*) / SUM(COUNT(*)) OVER()), 2) as shipments_cost_usd
  FROM `monitor-base-us-prod.monitor_base.shipments`
  WHERE retailer_moniker IS NOT NULL
  GROUP BY retailer_moniker
),

orders_data AS (
  SELECT 
    retailer_moniker,
    COUNT(*) as order_count,
    ROUND(45302 * (COUNT(*) / SUM(COUNT(*)) OVER()), 2) as orders_cost_usd
  FROM `monitor-base-us-prod.monitor_base.orders`
  WHERE retailer_moniker IS NOT NULL
    AND order_date >= '2024-01-01'
  GROUP BY retailer_moniker
),

returns_data AS (
  SELECT 
    retailer_moniker,
    COUNT(*) as return_count,
    ROUND(11871 * (COUNT(*) / SUM(COUNT(*)) OVER()), 2) as returns_cost_usd
  FROM `narvar-data-lake.reporting.t_return_details`
  WHERE DATE(return_created_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    AND retailer_moniker IS NOT NULL
  GROUP BY retailer_moniker
),

consumption_data AS (
  SELECT
    retailer_moniker,
    SUM(estimated_slot_cost_usd) as consumption_cost_usd,
    SUM(slot_hours) as consumption_slot_hours,
    COUNT(*) as query_count
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE analysis_period_label = 'Peak_2024_2025'
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
    
    -- Consumption cost
    COALESCE(c.consumption_cost_usd, 0) as consumption_cost_usd,
    COALESCE(c.consumption_slot_hours, 0) as consumption_slot_hours,
    COALESCE(c.query_count, 0) as query_count
    
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
  
  -- Consumption
  consumption_cost_usd,
  consumption_slot_hours,
  query_count,
  
  -- Total cost
  total_production_cost_usd + consumption_cost_usd as total_cost_usd,
  
  -- Ratios
  ROUND(consumption_cost_usd / NULLIF(total_production_cost_usd, 0), 4) as consumption_to_production_ratio,
  ROUND(consumption_cost_usd / NULLIF(total_production_cost_usd + consumption_cost_usd, 0), 4) as consumption_pct_of_total
  
FROM combined
WHERE total_production_cost_usd > 0 OR consumption_cost_usd > 0
ORDER BY total_cost_usd DESC
LIMIT 100;
