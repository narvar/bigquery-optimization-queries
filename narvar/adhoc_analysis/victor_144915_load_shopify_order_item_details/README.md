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

## Hypothesis Evolution

### Initial Hypothesis
**Primary**: Data volume spike or join explosion (cartesian join from bad data quality)  
**Secondary**: Peak season resource contention (Nov 19-21 approaching Black Friday)  
**Tertiary**: Partition/cluster degradation causing full table scans

### ✅ CONFIRMED ROOT CAUSE (After Investigation)

**NOT a cartesian join** - Join filtering works correctly (20M rows from 237M input)

**ACTUAL ROOT CAUSE**: **Continuous data backfill in `v_order_items_atlas`**
- Old orders (Oct 15-17, May-Nov) being re-ingested with recent `ingestion_timestamp`
- They legitimately pass the 48-hour filter (filter is working!)
- Create 183 distinct dates in GROUP BY → Aggregation explosion
- Concentrated in 5 retailers (nicandzoe = 342K old orders, 94% of problem!)
- 98% have NO returns (not return-driven)
- Results in 61x more grouping combinations → 6-hour timeout

## Files

### Documentation (10 Markdown files)
1. **KEY_FINDINGS_SUMMARY.md** ⭐ **START HERE** - One-page summary
2. **EXECUTIVE_SUMMARY.md** - For VictorOps ticket/stakeholders
3. **BACKFILL_ROOT_CAUSE.md** - Continuous backfill analysis
4. **ANSWER_TO_CEZAR.md** - Job IDs and execution plan analysis
5. **FINDINGS.md** - Complete technical investigation
6. **EXECUTION_PLAN_ANALYSIS.md** - Stage-by-stage comparison
7. **JOB_IDS_FOR_COMPARISON.md** - BigQuery Console links
8. **PROBLEMATIC_RECORDS_ANALYSIS.md** - Record-level analysis
9. **NEXT_STEPS.md** - Action plan with SQL commands
10. **SLACK_UPDATE.md** - Team communication template

### Queries (13 SQL files)
- `01_table_sizes_and_counts.sql` - Table metadata (236M row fact table found)
- `02_join_key_distribution.sql` - Join key analysis (1.18M distinct keys)
- `03_temp_table_date_distribution.sql` - **183 distinct dates discovered**
- `05_find_specific_job.sql` - **Job history (67x degradation)**
- `07_get_execution_plans.sql` - Execution plan extraction
- `10_return_dates_analysis.sql` - **98% have NO returns**
- `11_old_records_by_retailer.sql` - **nicandzoe 342K old orders found**
- `12_check_view_definition.sql` - **View structure verified**
- `13_sample_ingestion_timestamps.sql` - **SMOKING GUN: Nov 25 timestamps for Oct orders**
- Plus 4 other diagnostic queries

### Results (13 files)
- 10 CSV result files from executed queries
- 3 JSON execution plans (failed and successful jobs)
- Complete evidence trail proving continuous data backfill

## Timeline

**Started**: November 25, 2025 11:00 AM  
**Completed**: November 25, 2025 8:00 PM  
**Duration**: 9 hours (comprehensive investigation)  
**Investigation Cost**: $1.77

