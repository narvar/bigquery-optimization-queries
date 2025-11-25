-- Orders Cost Attribution by Retailer
-- Purpose: Distribute the $45,302/year orders cost based on actual record counts

-- Note: This query will scan the entire orders table to get counts
-- Estimated cost: ~$1-2 (scanning ~88TB)
-- Orders table requires partition filtering on order_date

-- Orders table info:
-- - 23.76 billion rows
-- - 88.7 TB of data
-- - Technology: Cloud Dataflow streaming pipeline
-- - Cost breakdown: $21,852 Dataflow + $20,430 Storage + $820 Streaming + $2,200 Pub/Sub

WITH orders_volume AS (
  SELECT 
    retailer_moniker,
    COUNT(*) as order_count,
    COUNT(*) / SUM(COUNT(*)) OVER() as volume_share
  FROM `monitor-base-us-prod.monitor_base.orders`
  WHERE retailer_moniker IS NOT NULL
    AND order_date >= '2024-01-01'  -- Partition filter required
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

orders_cost AS (
  SELECT
    o.retailer_moniker,
    o.order_count,
    o.volume_share,
    -- Orders Production Cost: $45,302/year
    ROUND(45302 * o.volume_share, 2) as attributed_orders_cost_usd
  FROM orders_volume o
)

SELECT
  COALESCE(o.retailer_moniker, c.retailer_moniker) as retailer_moniker,
  
  -- Orders Production (Data Maintenance)
  COALESCE(o.order_count, 0) as order_count,
  COALESCE(o.attributed_orders_cost_usd, 0) as orders_production_cost_usd,
  COALESCE(o.volume_share, 0) as orders_volume_share,
  
  -- Consumption (Query Usage)
  COALESCE(c.consumption_cost_usd, 0) as consumption_cost_usd,
  COALESCE(c.consumption_slot_hours, 0) as consumption_slot_hours,
  COALESCE(c.query_count, 0) as query_count,
  
  -- Comparison
  ROUND(COALESCE(c.consumption_cost_usd, 0) / NULLIF(COALESCE(o.attributed_orders_cost_usd, 0), 0), 4) as consumption_to_production_ratio,
  ROUND(COALESCE(o.attributed_orders_cost_usd, 0) - COALESCE(c.consumption_cost_usd, 0), 2) as net_cost_imbalance
  
FROM orders_cost o
FULL OUTER JOIN consumption_cost c ON o.retailer_moniker = c.retailer_moniker
ORDER BY orders_production_cost_usd DESC
LIMIT 100;

