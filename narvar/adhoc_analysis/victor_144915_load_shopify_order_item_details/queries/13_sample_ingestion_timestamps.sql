-- Query 13: Sample Ingestion Timestamps from v_order_items
-- Purpose: Check if ingestion_timestamp column exists and has reasonable values
-- Specifically check for old orders (Oct 15-17) to see their ingestion timestamps
-- Cost: Will depend on view size - estimate 10-50GB

-- Sample orders from the problematic dates
SELECT 
    retailer_moniker,
    store_name,
    order_date,
    order_number,
    order_item_sku,
    ingestion_timestamp,
    -- Calculate days between order and ingestion
    DATE_DIFF(DATE(ingestion_timestamp), DATE(order_date), DAY) AS days_order_to_ingestion,
    -- Check if it would pass the 48-hour filter for execution date 2025-11-20
    CASE 
        WHEN ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('2025-11-20'), INTERVAL 48 HOUR)
            THEN 'PASSES 48hr filter'
        WHEN ingestion_timestamp IS NULL
            THEN 'NULL ingestion_timestamp'
        ELSE 'FAILS 48hr filter (too old)'
    END AS filter_status,
    -- Show exact timestamp comparison
    TIMESTAMP_DIFF(TIMESTAMP('2025-11-20'), ingestion_timestamp, HOUR) AS hours_before_execution
FROM 
    `narvar-data-lake.return_insights_base.v_order_items` o
WHERE 
    -- Focus on the Oct 15-17 spike dates (the big anomaly)
    DATE(order_date) BETWEEN '2025-10-15' AND '2025-10-17'
    -- And retailers we know have old data
    AND retailer_moniker IN ('nicandzoe', 'skims', 'stevemadden', 'icebreakerapac')
ORDER BY 
    ingestion_timestamp DESC
LIMIT 100;

