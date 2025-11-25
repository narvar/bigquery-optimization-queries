-- Query 12: Check v_order_items View Definition
-- Purpose: Verify if ingestion_timestamp column exists and how it's populated
-- Cost: ~0 (metadata only)

-- Get the view definition
SELECT 
    table_name,
    view_definition
FROM 
    `narvar-data-lake.region-us.INFORMATION_SCHEMA.VIEWS`
WHERE 
    table_schema = 'return_insights_base'
    AND table_name = 'v_order_items';

