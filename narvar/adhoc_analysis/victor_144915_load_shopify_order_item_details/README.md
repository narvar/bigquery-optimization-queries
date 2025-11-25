# VICTOR-144915: load_shopify_order_item_details DAG Timeout Investigation

## Problem Summary

**DAG**: `load_shopify_order_item_details`  
**Failing Task**: `update_product_insights`  
**Error**: `Request timed out` after ~6 hours execution  
**First Failure**: November 19, 2025  
**Job ID Example**: `job_GfBO-8zBmqLqbOcAErnuRkaa0LQO` (Nov 20 execution)

**Key Metrics from Failed Job**:
- Execution time: 6 hours (06:38 to 12:38)
- Total slot-ms: 309,102,626 (~85,862 slot-hours)
- Bytes processed: 0 (misleading - script job)
- Error location: Line 3:9 of the script

## Investigation Strategy

### Phase B: Current State Analysis (FIRST)
1. **Table Sizes & Row Counts**
   - `tmp_order_item_details_2025-11-20` (source temp table)
   - `order_item_details` (fact table being joined)
   - `product_insights` (target table)
   - Recent growth trends

2. **Data Quality Checks**
   - Join key distributions (retailer_moniker, shopify_domain, order_date, order_item_sku)
   - Duplicate detection
   - Null value analysis
   - Check for cartesian join risk

3. **Recent Data Anomalies**
   - New retailers onboarded (last 30 days)
   - Volume spikes in v_order_items or return_item_details
   - Data skew by retailer

### Phase A: Historical Job Comparison (SECOND)
1. **Find Historical Runs**
   - Pattern: `CREATE OR REPLACE TABLE` + `tmp_product_insights_updates_`
   - Last 30 days of executions
   - Compare: slot consumption, execution time, bytes processed

2. **Trend Analysis**
   - When did degradation start?
   - Gradual or sudden change?
   - Correlation with data volume?

### Phase C: Resource Contention Analysis (THIRD)
1. **Concurrent Workload**
   - What else was running Nov 19-21?
   - BQ reservation saturation?
   - Peak season impact (Black Friday approaching)

2. **Query Plan Analysis**
   - EXPLAIN plan for current query
   - Partition pruning effectiveness
   - Clustering effectiveness

## Hypothesis

**Primary**: Data volume spike or join explosion (cartesian join from bad data quality)  
**Secondary**: Peak season resource contention (Nov 19-21 approaching Black Friday)  
**Tertiary**: Partition/cluster degradation causing full table scans

## Files

### Queries
- `01_table_sizes_and_counts.sql` - Current state of all tables
- `02_temp_table_analysis.sql` - Analyze recent temp tables
- `03_join_key_distribution.sql` - Check for join explosion risk
- `04_recent_data_volume_trends.sql` - 30-day volume trends
- `05_historical_job_comparison.sql` - Find and compare past runs
- `06_resource_contention_analysis.sql` - Concurrent workload check
- `07_query_plan_analysis.sql` - EXPLAIN plan investigation

### Results
- CSV and JSON outputs from each query
- Analysis summaries

## Timeline

**Started**: November 25, 2025  
**Target Completion**: Same day (6-8 hours investigation)

