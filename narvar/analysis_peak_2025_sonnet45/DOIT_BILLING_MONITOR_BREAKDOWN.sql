-- DoIT Billing Breakdown for Monitor Platform
-- Goal: Identify which GCP services contribute to Monitor costs
-- Focus: monitor-base-us-prod project and related services
-- Date: 2025-11-19

-- This will help us understand:
-- 1. Is the $149,832 from BigQuery compute, Dataflow, or mixed?
-- 2. How much is shipments vs orders infrastructure?
-- 3. What are the specific SKU line items?

-- Note: We need to query the actual DoIT billing CSV or table
-- The file mentioned in docs is: monitor-base 24 months.csv

-- PLACEHOLDER QUERY - needs actual table/file location
-- Structure based on typical GCP billing exports:

/*
SELECT
  service.description as gcp_service,
  sku.description as sku_description,
  
  -- Time aggregation  
  EXTRACT(YEAR FROM usage_start_time) as year,
  EXTRACT(MONTH FROM usage_start_time) as month,
  
  -- Costs
  SUM(cost) as total_cost_usd,
  ROUND(SUM(cost) * 12.0 / 24.0, 2) as annualized_cost_usd,
  
  -- Usage metrics
  SUM(usage.amount) as total_usage,
  usage.unit as usage_unit,
  
  -- Percentage of total
  ROUND(100.0 * SUM(cost) / SUM(SUM(cost)) OVER(), 2) as pct_of_total
  
FROM `<billing_table_or_csv>`
WHERE 1=1
  AND project.id = 'monitor-base-us-prod'
  
  -- Focus on relevant services
  AND service.description IN (
    'Cloud Dataflow',
    'BigQuery',
    'Cloud Pub/Sub',
    'Cloud Storage',
    'Compute Engine',
    'Cloud Run'
  )
  
  -- Last 24 months
  AND DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 24 MONTH)
  
GROUP BY 
  gcp_service, 
  sku_description, 
  year, 
  month,
  usage_unit
  
ORDER BY total_cost_usd DESC;
*/

-- QUESTIONS FOR CEZAR:
-- 1. Where is the DoIT billing data stored?
--    - Is it in a BigQuery table?
--    - Is it the CSV file: "monitor-base 24 months.csv"?
--    - What's the table schema?
--
-- 2. From ORDERS_TABLE_FINAL_COST.md, these billing lines were referenced:
--    Line 4, 7, 14, 15 = Dataflow costs ($21,852/year)
--    Line 21 = Streaming inserts ($820/year)
--    
--    Can we identify similar line items for shipments?
--
-- 3. The $149,832 "shipments compute" - was this calculated as:
--    a) Pure BigQuery slot-hours * $0.0494?
--    b) Including Dataflow infrastructure?
--    c) Including other services?

-- Once we have access to the billing data, we can break down:
-- - Cloud Dataflow costs (by pipeline/job name if available)
-- - BigQuery compute costs (slot reservations)
-- - BigQuery storage costs
-- - Pub/Sub messaging costs
-- - Any other infrastructure costs

