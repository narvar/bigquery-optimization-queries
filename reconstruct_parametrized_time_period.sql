-- Reconstruct Time Period for Parametrized Query
-- Target: The query with job_id 'job_fkhGvQtTHmR_KAsgdhRJgZJDTkc0'
-- Pattern: datetime_trunc(ship_date, day) BETWEEN ? AND ?
-- Context: Fashion Nova, carrier='ontrac', manifest events

-- Step 1: Analyze data distribution for similar queries
WITH similar_queries AS (
  SELECT 
    job_id,
    creation_time,
    query,
    total_bytes_processed,
    total_slot_ms,
    -- Extract potential date patterns from query text
    REGEXP_EXTRACT_ALL(query, r"ship_date.*BETWEEN\s*'([^']+)'\s*AND\s*'([^']+)'") as date_ranges,
    REGEXP_EXTRACT_ALL(query, r"ship_date.*>=\s*'([^']+)'") as start_dates,
    REGEXP_EXTRACT_ALL(query, r"ship_date.*<=\s*'([^']+)'") as end_dates
  FROM `monitor-a679b28-us-prod.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
  WHERE DATE(creation_time) >= '2025-11-01'
    AND query LIKE '%v_shipments%'
    AND query LIKE '%ontrac%'
    AND query LIKE '%manifest%'
    AND statement_type = 'SELECT'
),

-- Step 2: Look at the actual data being queried to infer time range
data_distribution AS (
  SELECT 
    DATE_TRUNC(ship_date, DAY) as ship_day,
    COUNT(*) as shipment_count,
    COUNTIF(carrier_moniker = 'ontrac') as ontrac_count,
    COUNTIF(carrier_moniker = 'ontrac' 
            AND EXISTS (
              SELECT 1 
              FROM UNNEST(events) e 
              WHERE LOWER(e.detailed_event_status) LIKE '%manifest%'
            )) as ontrac_manifest_count
  FROM `monitor.v_shipments`
  WHERE ship_date >= '2024-01-01'
    AND carrier_moniker = 'ontrac'
  GROUP BY ship_day
  ORDER BY ship_day DESC
),

-- Step 3: Estimate query time range based on data volume
volume_analysis AS (
  SELECT 
    ship_day,
    shipment_count,
    ontrac_manifest_count,
    SUM(shipment_count) OVER (ORDER BY ship_day DESC) as cumulative_count,
    SUM(ontrac_manifest_count) OVER (ORDER BY ship_day DESC) as cumulative_manifest_count,
    -- Estimate bytes based on typical row size (~2KB per shipment row)
    SUM(shipment_count) OVER (ORDER BY ship_day DESC) * 2048 as estimated_bytes
  FROM data_distribution
)

-- Step 4: Find the time range that matches the 262GB processed
SELECT 
  'Query Analysis' as analysis_type,
  job_id,
  creation_time,
  total_bytes_processed,
  total_slot_ms,
  -- Calculate days of data based on bytes processed
  CAST(total_bytes_processed / 2048.0 / (
    SELECT AVG(shipment_count) 
    FROM data_distribution 
    WHERE ship_day >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  ) AS INT64) as estimated_days_of_data
FROM similar_queries
WHERE job_id = 'job_fkhGvQtTHmR_KAsgdhRJgZJDTkc0'

UNION ALL

-- Step 5: Data-driven time range estimation
SELECT 
  'Data-Driven Estimation' as analysis_type,
  'N/A' as job_id,
  TIMESTAMP('2025-11-14 08:06:16.720000 UTC') as creation_time,
  262032590559 as total_bytes_processed,
  44735491 as total_slot_ms,
  -- Find the date range that would process ~262GB
  (SELECT COUNT(*) 
   FROM volume_analysis 
   WHERE estimated_bytes <= 262032590559) as estimated_days_of_data
FROM (SELECT 1)

UNION ALL

-- Step 6: Most likely time periods based on Fashion Nova patterns
SELECT 
  'Fashion Nova Pattern' as analysis_type,
  'Typical Range' as job_id,
  TIMESTAMP('2025-11-14 08:06:16.720000 UTC') as creation_time,
  262032590559 as total_bytes_processed,
  44735491 as total_slot_ms,
  CASE 
    WHEN 262032590559 < 100000000000 THEN 30  -- <100GB = 30 days
    WHEN 262032590559 < 200000000000 THEN 60  -- 100-200GB = 60 days  
    WHEN 262032590559 < 400000000000 THEN 90  -- 200-400GB = 90 days
    ELSE 180  -- >400GB = 180 days
  END as estimated_days_of_data
FROM (SELECT 1);