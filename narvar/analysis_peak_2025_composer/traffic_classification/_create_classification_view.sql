-- Create Traffic Classification Materialized View: Creates a materialized view for unified traffic classification
-- Purpose: Materializes unified traffic classification results for use in Phase 2+ queries
--
-- This script creates a materialized view that can be referenced by seasonal analysis queries.
-- The view is refreshed periodically to keep classification up-to-date.
--
-- Usage:
--   1. Review and adjust the date range and refresh schedule
--   2. Execute this CREATE MATERIALIZED VIEW statement
--   3. Schedule periodic refreshes (daily or weekly)
--   4. Reference the view in Phase 2+ queries: `narvar-data-lake.analysis_peak_2025.traffic_classification`
--
-- Important:
--   - Materialized views have cost implications for storage and refresh
--   - Consider partitioning by date for large datasets
--   - Adjust refresh frequency based on analysis needs
--   - For initial testing, use smaller date ranges before materializing full history
--
-- Parameters (adjust in the view definition):
--   - Lookback period: Default is 365 days, adjust based on needs
--   - Dataset location: Adjust dataset/project as needed
--
-- Cost Warning: Creating and refreshing this view processes all audit logs.
--               Initial creation may process 100-200GB+ depending on date range.
--               Schedule regular refreshes to keep data current.

-- Note: This is a template. Adjust project, dataset, and table references as needed.

-- Option 1: Create as a Materialized View (BigQuery feature)
-- Note: Materialized views require BigQuery support for materialized views
/*
CREATE MATERIALIZED VIEW `narvar-data-lake.analysis_peak_2025.traffic_classification`
PARTITION BY DATE(start_time)
CLUSTER BY consumer_category, project_id
OPTIONS(
  description="Unified traffic classification from audit logs",
  enable_refresh=true,
  refresh_interval_minutes=1440  -- Refresh daily
)
AS
-- Insert unified_traffic_classification.sql query here
-- Copy the entire query from unified_traffic_classification.sql
-- Adjust interval_in_days as needed (e.g., 730 for 2 years)
;
*/

-- Option 2: Create as a Standard View (lighter weight, always computed on query)
-- Use this if materialized views are not available or for smaller datasets
/*
CREATE OR REPLACE VIEW `narvar-data-lake.analysis_peak_2025.traffic_classification`
OPTIONS(
  description="Unified traffic classification from audit logs (standard view)"
)
AS
-- Insert unified_traffic_classification.sql query here
-- Note: Standard views compute on-demand, so queries may be slower but more current
;
*/

-- Option 3: Create as a Table (best for large datasets, manual refresh control)
-- Use this for maximum control over refresh schedule and cost
/*
CREATE OR REPLACE TABLE `narvar-data-lake.analysis_peak_2025.traffic_classification`
PARTITION BY DATE(start_time)
CLUSTER BY consumer_category, project_id
AS
-- Insert unified_traffic_classification.sql query here
-- After initial creation, use INSERT or MERGE to refresh data
;

-- To refresh the table periodically:
-- DELETE FROM `narvar-data-lake.analysis_peak_2025.traffic_classification`
-- WHERE DATE(start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);
-- INSERT INTO `narvar-data-lake.analysis_peak_2025.traffic_classification`
-- -- Re-run unified_traffic_classification.sql for recent period
;
*/

-- Example: Creating as a partitioned table (recommended for large datasets)
-- Uncomment and adjust the query below, or use one of the options above

/*
CREATE OR REPLACE TABLE `narvar-data-lake.analysis_peak_2025.traffic_classification`
PARTITION BY DATE(start_time)
CLUSTER BY consumer_category, project_id
AS
-- Copy the entire query from unified_traffic_classification.sql
-- Make sure to remove the ORDER BY clause if present (not needed for table creation)
-- Example structure:
WITH monitor_mappings AS (
  -- ... from unified_traffic_classification.sql
),
audit_log_base AS (
  -- ... from unified_traffic_classification.sql
),
-- ... rest of the query
SELECT
  -- All columns from unified_traffic_classification.sql
;
*/

-- Instructions:
-- 1. Choose Option 1 (Materialized View), Option 2 (Standard View), or Option 3 (Table)
-- 2. Copy the entire query from unified_traffic_classification.sql
-- 3. Replace the SELECT statement in the chosen option
-- 4. Adjust project/dataset names and date ranges as needed
-- 5. Execute the CREATE statement
-- 6. Verify the view/table was created successfully
-- 7. Test with a small query: SELECT COUNT(*) FROM `narvar-data-lake.analysis_peak_2025.traffic_classification` LIMIT 10;

