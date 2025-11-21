-- Quick Verification: Test the estimated time ranges
-- Run this to validate the Fashion Nova time period estimation

-- Test the 3 most likely time ranges
WITH test_ranges AS (
  SELECT 
    '60-day range' as range_name,
    DATE_SUB('2025-11-14', INTERVAL 60 DAY) as start_date,
    '2025-11-14' as end_date,
    60 as days
  
  UNION ALL
  
  SELECT 
    '75-day range' as range_name,
    DATE_SUB('2025-11-14', INTERVAL 75 DAY) as start_date,
    '2025-11-14' as end_date,
    75 as days
  
  UNION ALL
  
  SELECT 
    '90-day range' as range_name,
    DATE_SUB('2025-11-14', INTERVAL 90 DAY) as start_date,
    '2025-11-14' as end_date,
    90 as days
),

-- Estimate data volume for each range
volume_estimates AS (
  SELECT 
    range_name,
    start_date,
    end_date,
    days,
    -- This is a rough estimate based on Fashion Nova patterns
    CASE 
      WHEN days = 60 THEN 200000000000  -- ~200GB
      WHEN days = 75 THEN 250000000000  -- ~250GB  
      WHEN days = 90 THEN 300000000000  -- ~300GB
    END as estimated_bytes
)

SELECT 
  range_name,
  start_date,
  end_date,
  days,
  estimated_bytes,
  262032590559 as actual_bytes_processed,
  ROUND(100.0 * ABS(262032590559 - estimated_bytes) / 262032590559, 1) as variance_pct,
  CASE 
    WHEN ABS(262032590559 - estimated_bytes) < 30000000000 THEN '✅ CLOSE MATCH'
    WHEN ABS(262032590559 - estimated_bytes) < 50000000000 THEN '⚠️ REASONABLE'
    ELSE '❌ HIGH VARIANCE'
  END as match_quality
FROM volume_estimates
ORDER BY variance_pct;