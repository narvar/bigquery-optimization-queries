-- Retailer Production vs Consumption Analysis
-- Purpose: Compare production cost (attributed by volume) vs consumption cost (direct query usage)

WITH retailer_volume AS (
  -- Using t_return_details as a proxy for retailer volume share
  -- We assume returns volume is roughly proportional to shipments/orders volume
  SELECT 
    retailer_moniker,
    COUNT(*) as total_records,
    COUNT(*) / SUM(COUNT(*)) OVER() as volume_share
  FROM `narvar-data-lake.reporting.t_return_details`
  WHERE DATE(return_created_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) -- Last 90 days for recent volume
  GROUP BY retailer_moniker
),

consumption_cost AS (
  SELECT
    retailer_moniker,
    SUM(estimated_slot_cost_usd) as consumption_cost_usd, -- Using estimated cost from classification
    SUM(slot_hours) as consumption_slot_hours,
    COUNT(*) as query_count
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE analysis_period_label = 'Peak_2024_2025'
    AND consumer_subcategory = 'MONITOR'
  GROUP BY retailer_moniker
),

production_cost AS (
  SELECT
    r.retailer_moniker,
    r.volume_share,
    -- t_return_details Production Cost: $11,871/year
    -- Source: RETURN_ITEM_DETAILS_FINAL_COST.md
    ROUND(11871 * r.volume_share, 2) as attributed_production_cost_usd
  FROM retailer_volume r
)

SELECT
  COALESCE(p.retailer_moniker, c.retailer_moniker) as retailer_moniker,
  
  -- Production (Data Maintenance)
  COALESCE(p.attributed_production_cost_usd, 0) as production_cost_usd,
  COALESCE(p.volume_share, 0) as production_volume_share,
  
  -- Consumption (Query Usage)
  COALESCE(c.consumption_cost_usd, 0) as consumption_cost_usd,
  COALESCE(c.consumption_slot_hours, 0) as consumption_slot_hours,
  COALESCE(c.query_count, 0) as query_count,
  
  -- Comparison
  ROUND(COALESCE(c.consumption_cost_usd, 0) / NULLIF(COALESCE(p.attributed_production_cost_usd, 0), 0), 4) as consumption_to_production_ratio,
  ROUND(COALESCE(p.attributed_production_cost_usd, 0) - COALESCE(c.consumption_cost_usd, 0), 2) as net_cost_imbalance
  
FROM production_cost p
FULL OUTER JOIN consumption_cost c ON p.retailer_moniker = c.retailer_moniker
ORDER BY production_cost_usd DESC
LIMIT 100;
