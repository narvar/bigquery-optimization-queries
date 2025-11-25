-- Query 1: Table Sizes and Row Counts
-- Purpose: Get current state of all tables involved in the failing query
-- Cost: ~0 (metadata only from INFORMATION_SCHEMA)
-- Uses region-qualified INFORMATION_SCHEMA (must specify US region)

WITH table_info AS (
    SELECT 
        t.table_schema AS dataset,
        t.table_name,
        t.table_type,
        t.creation_time AS created_at,
        s.total_rows AS row_count,
        s.total_logical_bytes AS size_bytes,
        s.active_logical_bytes,
        s.long_term_logical_bytes,
        -- Calculate days since created
        DATE_DIFF(CURRENT_DATE(), DATE(t.creation_time), DAY) AS days_since_created
    FROM 
        `narvar-data-lake.region-us.INFORMATION_SCHEMA.TABLES` t
    LEFT JOIN
        `narvar-data-lake.region-us.INFORMATION_SCHEMA.TABLE_STORAGE` s
        ON t.table_schema = s.table_schema 
        AND t.table_name = s.table_name
    WHERE 
        t.table_schema = 'return_insights_base'
        AND (
            t.table_name IN (
                'order_item_details',
                'product_insights',
                'return_item_details',
                'duplicate_matches'
            )
            OR t.table_name LIKE 'tmp_order_item_details_%'
            OR t.table_name LIKE 'tmp_product_insights_updates_%'
        )
)
SELECT 
    dataset,
    table_name,
    table_type,
    created_at,
    row_count,
    ROUND(size_bytes / POW(1024, 3), 2) AS size_gb,
    ROUND(size_bytes / POW(1024, 4), 2) AS size_tb,
    ROUND(active_logical_bytes / POW(1024, 3), 2) AS active_gb,
    ROUND(long_term_logical_bytes / POW(1024, 3), 2) AS long_term_gb,
    days_since_created
FROM 
    table_info
ORDER BY 
    created_at DESC;

