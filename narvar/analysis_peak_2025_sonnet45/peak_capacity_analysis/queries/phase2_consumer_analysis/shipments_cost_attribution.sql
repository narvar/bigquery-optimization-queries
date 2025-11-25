-- Shipments Cost Attribution by Retailer
-- Purpose: Distribute the $176,556/year shipments cost based on actual record counts

-- Note: This query will scan the entire shipments table to get counts
-- Estimated cost: ~$0.50-$1.00 (scanning ~3TB)

WITH shipments_volume AS (
  SELECT 
    retailer_moniker,
    COUNT(*) as shipment_count,
    COUNT(*) / SUM(COUNT(*)) OVER() as volume_share
  FROM `monitor-base-us-prod.monitor_base.shipments`
  WHERE retailer_moniker IS NOT NULL
  GROUP BY retailer_moniker
),

consumption_cost AS (
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

shipments_cost AS (
  SELECT
    s.retailer_moniker,
    s.shipment_count,
    s.volume_share,
    -- Shipments Production Cost: $176,556/year
    ROUND(176556 * s.volume_share, 2) as attributed_shipments_cost_usd
  FROM shipments_volume s
)

SELECT
  COALESCE(s.retailer_moniker, c.retailer_moniker) as retailer_moniker,
  
  -- Shipments Production (Data Maintenance)
  COALESCE(s.shipment_count, 0) as shipment_count,
  COALESCE(s.attributed_shipments_cost_usd, 0) as shipments_production_cost_usd,
  COALESCE(s.volume_share, 0) as shipments_volume_share,
  
  -- Consumption (Query Usage)
  COALESCE(c.consumption_cost_usd, 0) as consumption_cost_usd,
  COALESCE(c.consumption_slot_hours, 0) as consumption_slot_hours,
  COALESCE(c.query_count, 0) as query_count,
  
  -- Comparison
  ROUND(COALESCE(c.consumption_cost_usd, 0) / NULLIF(COALESCE(s.attributed_shipments_cost_usd, 0), 0), 4) as consumption_to_production_ratio,
  ROUND(COALESCE(s.attributed_shipments_cost_usd, 0) - COALESCE(c.consumption_cost_usd, 0), 2) as net_cost_imbalance
  
FROM shipments_cost s
FULL OUTER JOIN consumption_cost c ON s.retailer_moniker = c.retailer_moniker
ORDER BY shipments_production_cost_usd DESC
LIMIT 100;
