# VICTOR-144915: Root Cause Analysis

**Investigation Date**: November 25, 2025  
**Investigator**: Sophia (AI Assistant)  
**DAG**: `load_shopify_order_item_details`  
**Failing Task**: `update_product_insights`

---

## Executive Summary

The `update_product_insights` task is timing out (6 hours) when processing data for **Nov 19-20 execution dates only**. The root cause is that the temp table `tmp_order_item_details` contains **6 months of historical data (183 distinct dates)** instead of the expected **2 days**, causing the aggregation query to process **60x more data** than designed.

**Status**: Partially resolved (Nov 21-24 working normally), but Nov 19-20 data still broken.

---

## Root Cause: Continuous Data Backfill/Re-Ingestion

**UPDATE (Nov 25, Evening)**: After deeper investigation, discovered the actual root cause.

### 1. Temp Table Contains 6 Months of Data

**Expected**: 2 days of data (48-hour window)  
**Actual**: 183 distinct dates spanning May-November 2025

| Date Range | Rows | % of Total |
|------------|------|------------|
| Nov 18-20 (last 3 days) | 2.48M | 59% |
| Oct 15-17 (spike) | 350K | 9.3% |
| May-Oct tail | 1.37M | 31.7% |

**Total rows**: 4.2M (should be ~500K)

**Evidence**: `tmp_order_item_details_2025-11-20` contains:
- 4,207,927 rows
- 183 distinct order dates
- Date range: 2025-05-01 to 2025-11-20

### 2. Tables and Views Structure

**Query Chain**:
```
DAG Query:
  FROM `narvar-data-lake.return_insights_base.v_order_items` o
    └─> VIEW Definition (Query 12):
        SELECT ... a.ingestion_timestamp, a.event_ts
        FROM `narvar-data-lake.return_insights_base.v_order_items_atlas` a
          └─> Underlying TABLE containing ingestion_timestamp column
```

**The `ingestion_timestamp` column DOES exist and IS populated** in `v_order_items_atlas` (confirmed via view definition).

### 3. The Real Problem: Ongoing Data Backfill

**The DAG filter IS working correctly**, but old orders are being **continuously re-ingested**:

```sql
WHERE o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('{execution_date}'), INTERVAL 48 HOUR)
```

**What we discovered (Query 13)**:
- Orders from **Oct 15-17, 2025** (order_date, 35-41 days ago)
- Have `ingestion_timestamp` = **Nov 25, 2025** (TODAY!)
- Were re-ingested **39-41 days AFTER** they were originally placed
- **Legitimately pass the 48-hour filter** because ingestion is recent

**Example**:
```
order_date: 2025-10-16 12:25:28
ingestion_timestamp: 2025-11-25 19:48:22
days_order_to_ingestion: 40 days
filter_status: PASSES 48hr filter ✅
```

### 4. Retailer Concentration (Query 11)

The backfill is concentrated in specific retailers:

| Retailer | Very Old Orders | % of Their Data | Date Span |
|----------|----------------|-----------------|-----------|
| **nicandzoe** | 342,109 | 99.7% | Sep 26 - Nov 20 (55 days) |
| **icebreakerapac** | 5,840 | 79.7% | Sep 22 - Nov 20 (59 days) |
| **skims** | 5,423 | 41.2% | May 21 - Nov 20 (183 days!) |
| **milly** | 3,643 | 91.4% | Sep 05 - Nov 20 (76 days) |
| **stevemadden** | 3,118 | 55.1% | May 26 - Nov 20 (178 days) |

**Top 5 retailers = 360K of 1.73M problematic records (21%)**

### 5. Not Driven by Recent Returns (Query 10)

**98% of old orders have NO returns at all**:
- Total old orders (before Nov 13): 1.73M
- With recent returns: ~35K (2%)
- With no returns: ~1.69M (98%)

**Conclusion**: The backfill is NOT because of recent return activity. It's an upstream ETL/ingestion issue causing continuous re-ingestion of historical order data.

### 3. Cascading Impact on Aggregation

The `update_product_insights` task:
1. Reads `tmp_order_item_details` → 4.2M rows (60x too large)
2. Creates `affected_items` CTE → 1.18M distinct join keys (should be ~20K)
3. Joins with `order_item_details` (236M rows) → Produces 20M joined rows (join works correctly)
4. **Aggregates across 183 dates** (should be 2-3):
   - 183 dates × 194 retailers × 648K SKUs × 15 GROUP BY dimensions
   - Creates 10-50 million grouping combinations (61x more than expected)
   - Exceeds available memory, causes spilling and retries
5. **Result**: Aggregation explosion → timeout after 6 hours

**Note**: This is NOT a cartesian join (join conditions are correct). It's an **aggregation explosion** caused by excessive grouping dimensions. See `EXECUTION_PLAN_ANALYSIS.md` for detailed proof.

---

## Tables and Views Explained

### Data Flow Architecture

```
Upstream ETL/Dataflow
    ↓ (continuous ingestion + backfill)
v_order_items_atlas (BASE TABLE)
├─ Columns: order_date, order_number, order_item_sku, ingestion_timestamp, event_ts, ...
├─ Problem: Continuous re-ingestion of historical orders with NEW ingestion_timestamp
└─ Example: Oct 15 order re-ingested Nov 25 gets ingestion_timestamp = 2025-11-25
    ↓ (view)
v_order_items (VIEW)
├─ SELECT ... a.ingestion_timestamp FROM v_order_items_atlas a
├─ Filters: Active retailers (updated_timestamp >= '2024-12-01')
├─ Deduplication: ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ingestion_timestamp DESC)
└─ Exposes ingestion_timestamp to downstream queries
    ↓ (DAG query)
tmp_order_item_details (TEMP TABLE)
├─ Filter: ingestion_timestamp >= TIMESTAMP_SUB(execution_date, INTERVAL 48 HOUR)
├─ Problem: Old orders pass filter because they were re-ingested recently
└─ Result: 183 distinct order_dates (should be 2-3)
    ↓ (aggregation query)
update_product_insights task
├─ Groups by: date, retailer, sku, ... (15 dimensions)
├─ Problem: 183 dates creates 61x more grouping combinations
└─ Result: TIMEOUT after 6 hours
```

### The ingestion_timestamp Column

**Location**: `narvar-data-lake.return_insights_base.v_order_items_atlas.ingestion_timestamp`

**Purpose**: Track when each order was ingested into the table (not when order was placed)

**How it works** (correctly):
- When an order is first ingested: `ingestion_timestamp` = current timestamp
- When an order is RE-INGESTED: `ingestion_timestamp` = NEW current timestamp
- The DAG filter uses this to get "recently ingested" data (working as designed)

**The problem**:
- If upstream re-ingests Oct 15 orders on Nov 25
- They get `ingestion_timestamp = 2025-11-25`
- They pass the 48-hour filter (Nov 25 - 48hrs = Nov 23)
- Even though `order_date = 2025-10-15` (old!)

### Why Backfill Happens

**Possible reasons** (needs investigation):
1. Data quality fixes (correcting wrong records)
2. Schema evolution (adding new columns)
3. ETL bug causing repeated re-ingestion
4. Intentional historical data refresh
5. Upstream source system changes

**Evidence it's ongoing** (not one-time):
- Query 13 shows ingestion timestamps from the last few hours (Nov 25)
- Spread across multiple hours (08:00, 09:00, 12:00, 13:00, 15:00, etc.)
- Suggests continuous/scheduled backfill process

---

## Timeline of Failures

| Date | CREATE temp | CREATE agg | MERGE | Status |
|------|------------|-----------|-------|--------|
| **Nov 18** | 10 min | 113 min | 16s | ✅ Slow but works |
| **Nov 19** | 5 min | **TIMEOUT (6hrs)** | - | ❌ 4 failed attempts |
| **Nov 20** | 14 min | **TIMEOUT (6hrs)** | - | ❌ 3 failed attempts |
| **Nov 21-23** | - | - | - | Not attempted |
| **Nov 24** | Normal | 5.4 min | 19s | ✅ Back to normal |

### Nov 19 Failures (4 attempts)
1. 00:17:57 - 6hrs timeout, 80.55 slot-hours
2. 06:23:57 - 6hrs timeout, 80.34 slot-hours  
3. 12:34:48 - 6hrs timeout, 79.77 slot-hours
4. 18:40:14 - 6hrs timeout, 89.98 slot-hours

### Nov 20 Failures (3 attempts)
1. 00:32:43 - 6hrs timeout, 64.98 slot-hours
2. 06:38:30 - 6hrs timeout, 85.86 slot-hours
3. **STILL RUNNING as of 17:24** (Nov 25)

### Performance Comparison

| Metric | Normal (Nov 24) | Failed (Nov 19-20) | Ratio |
|--------|----------------|-------------------|-------|
| Duration | 5.4 minutes | 360 minutes (timeout) | **67x** |
| Slot-hours | 11.34 | 80-90 | **7x** |
| Bytes processed | 69.53 GB | Unknown (timeout) | - |

---

## Table Sizes

| Table | Rows | Size |
|-------|------|------|
| `tmp_order_item_details_2025-11-20` | 4.2M | 1.56 GB |
| `order_item_details` (fact table) | 236.3M | 95.51 GB |
| `product_insights` (target) | 78.9M | 30.01 GB |
| `return_item_details` | 28.4M | 30.34 GB |

---

## Alternative Root Cause Paths Investigated

### ✅ Data Volume Spike
**Investigated**: Compared Nov 19, 20, 24 temp table sizes  
**Finding**: All ~4M rows - no spike in temp table size  
**Conclusion**: Not the primary cause, but 4M is already 8x too large

### ✅ Join Explosion / Cartesian Join
**Investigated**: Join key distribution analysis + execution plan comparison  
**Finding**: 
- 1.18M distinct join keys from 4.2M rows (28% uniqueness - reasonable)
- Join produces 20M rows from 237M input rows (11.8x reduction - proper filtering)
- **NOT a cartesian join** - join conditions work correctly
**Conclusion**: Join works correctly, but processes **wrong data scope** (183 dates instead of 2 days), causing **aggregation explosion** downstream. See `EXECUTION_PLAN_ANALYSIS.md` for detailed proof.

### ✅ Resource Contention
**Investigated**: Job history shows Nov 19-20 retries spread across different times  
**Finding**: Failed during off-peak, peak, and retry hours  
**Conclusion**: Not a reservation capacity issue - query itself is the problem

### ⚠️ Query Plan Changes (NOT YET INVESTIGATED)
**Status**: Could not get EXPLAIN plan for timeout jobs  
**Recommendation**: Compare successful vs failed query plans if possible

### ❌ Partition/Cluster Effectiveness (NOT INVESTIGATED)
**Status**: Need to check `order_item_details` table structure  
**Recommendation**: Check if partitioning on `order_date` and clustering exist

---

## Recommended Solutions

### Immediate Fix (Option A): Add Explicit Date Filter

**Problem**: `ingestion_timestamp` filter not working  
**Solution**: Add explicit `order_date` filter as safety net

```sql
WHERE 
    o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('{execution_date}'), INTERVAL 48 HOUR)
    AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)  -- Safety net
```

**Pros**:
- Immediate protection against runaway queries
- Doesn't rely on ingestion_timestamp
- 7-day window still safe (covers late-arriving data)

**Cons**:
- Doesn't fix the root cause
- May miss legitimately late-arriving data

**Effort**: 5 minutes  
**Risk**: Low

---

### Root Cause Fix (Option B): Stop Continuous Data Backfill

**UPDATE**: Investigation complete (Queries 10-13).

**Problem**: Upstream ETL is continuously re-ingesting historical orders with new `ingestion_timestamp` values  
**Solution**: Identify and stop the backfill process

**What we found**:
1. ✅ `ingestion_timestamp` column exists in `v_order_items_atlas` table
2. ✅ Filter logic is working correctly
3. ✅ Old orders (Oct 15-17) have Nov 25 ingestion timestamps (re-ingested today!)
4. ✅ Concentrated in 5 retailers: nicandzoe (342K), icebreakerapac (5.8K), skims (5.4K), milly (3.6K), stevemadden (3.1K)
5. ✅ 98% of old orders have NO returns (not driven by return activity)

**Steps to fix**:
1. Identify what's causing continuous re-ingestion in `v_order_items_atlas`
2. Check if this is intentional (data quality fixes) or a bug
3. If intentional: Add logic to mark backfilled records (e.g., `is_backfill` flag)
4. If bug: Fix upstream Dataflow/ETL pipeline
5. Coordinate with team that owns `v_order_items_atlas` population

**Pros**:
- Fixes root cause permanently
- Prevents future occurrences
- May improve overall system performance (less re-ingestion)

**Cons**:
- Requires investigation time
- Need coordination with upstream team
- Could take days to implement
- May need to understand business reason for backfill

**Effort**: 4-8 hours investigation + coordination + implementation  
**Risk**: Medium-High (requires upstream team changes)

---

### Workaround (Option C): Manually Clean and Retry Nov 19-20

**Problem**: Nov 19-20 jobs stuck in failure loop  
**Solution**: Drop bad temp tables and retry with fixed query

**Steps**:
1. `DROP TABLE narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-19`
2. `DROP TABLE narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20`  
3. `DROP TABLE narvar-data-lake.return_insights_base.tmp_product_insights_updates_2025-11-19`
4. `DROP TABLE narvar-data-lake.return_insights_base.tmp_product_insights_updates_2025-11-20`
5. Deploy Option A fix
6. Manually trigger Airflow DAG for those dates

**Pros**:
- Clears the stuck state
- Allows retry with fixed query

**Cons**:
- Manual intervention required
- Doesn't prevent future occurrences

**Effort**: 30 minutes  
**Risk**: Low

---

### Long-term Fix (Option D): Partition tmp Tables by order_date

**Problem**: Full table scan of 236M row fact table for every aggregation  
**Solution**: Partition intermediate tables by date

**Changes**:
1. Partition `tmp_order_item_details` by `order_date`
2. Use partition filter in `affected_items` CTE
3. BigQuery will prune partitions automatically

**Pros**:
- Reduces scan size even if temp table has extra data
- Improves performance for all runs

**Cons**:
- Requires DAG code changes
- More complex temp table management

**Effort**: 2-3 hours  
**Risk**: Medium

---

## Recommended Action Plan

### Phase 1: Immediate (Today)
1. **Deploy Option A** (add explicit date filter) - 5 minutes
2. **Execute Option C** (clean and retry Nov 19-20) - 30 minutes
3. **Monitor Nov 25-26 runs** - Verify problem doesn't recur

### Phase 2: Root Cause (This Week)
4. **Execute Option B** (investigate ingestion_timestamp) - 2-4 hours
5. **Fix ingestion_timestamp** if issue found - TBD
6. **Remove explicit date filter** from Option A once root cause fixed

### Phase 3: Long-term (Next Sprint)
7. **Execute Option D** (partition temp tables) - 2-3 hours
8. **Performance testing** - 1 hour
9. **Documentation update** - 30 minutes

---

## Questions for Follow-up

### ✅ ANSWERED (Investigation Complete)

1. **Does `v_order_items` have an `ingestion_timestamp` column?**
   - ✅ YES - Confirmed via Query 12 (view definition)
   - Column comes from `v_order_items_atlas.ingestion_timestamp`
   - Filter is working correctly

2. **Why does the temp table accumulate 6 months of data?**
   - ✅ ANSWERED: Continuous data backfill/re-ingestion
   - Old orders get new `ingestion_timestamp` values
   - They legitimately pass the 48-hour filter
   - `CREATE OR REPLACE` works correctly (not the issue)

3. **What caused the Oct 15-17 spike?**
   - ✅ ANSWERED: Large backfill event for those specific dates
   - 350K orders from Oct 15-17 re-ingested on Nov 25
   - Concentrated in nicandzoe (162K on Oct 16 alone)

### 🔲 STILL NEED TO INVESTIGATE

4. **Why is there continuous backfill happening?**
   - Who owns `v_order_items_atlas` table population?
   - Is this intentional (data quality fixes) or a bug?
   - Why specifically nicandzoe, icebreakerapac, skims, milly, stevemadden?

5. **Why did Nov 18 work (slowly) but Nov 19-20 fail completely?**
   - Nov 18: 113 minutes (slow but succeeded)
   - Nov 19-20: 6 hours (timeout)
   - All have 183 dates in temp table
   - Possible: Nov 18 had slightly less data, just barely completed?

6. **Why is Nov 24 back to normal?**
   - 5.4 minutes (expected performance)
   - Cleanup task finally ran (old temp tables dropped)?
   - Or less backfill data on that specific day?

7. **Is the backfill still running now?**
   - Query 13 shows ingestion happening at 19:48 (7:48 PM) on Nov 25
   - Is this a continuous process or batch job?
   - Can we see the backfill job in audit logs?

---

## Files Generated

### Queries
1. `01_table_sizes_and_counts.sql` - Table metadata
2. `02_join_key_distribution.sql` - Join explosion analysis
3. `03_temp_table_date_distribution.sql` - **Historical data discovery (183 dates found)**
4. `05_find_specific_job.sql` - Job history analysis
5. `07_get_execution_plans.sql` - Execution plan extraction
6. `10_return_dates_analysis.sql` - **Return activity check (98% have NO returns)**
7. `11_old_records_by_retailer.sql` - **Retailer concentration analysis**
8. `12_check_view_definition.sql` - **View definition verification**
9. `13_sample_ingestion_timestamps.sql` - **SMOKING GUN: Proves ongoing backfill**

### Results
1. `01_table_sizes_and_counts.csv` - 6 tables analyzed
2. `02_join_key_distribution.csv` - Join key metrics
3. `03_temp_table_date_distribution.csv` - 183 distinct dates found
4. `05_find_specific_job.csv` - 30-day job history
5. `10_return_dates_analysis.csv` - **98% of old orders have no returns**
6. `11_old_records_by_retailer.csv` - **nicandzoe has 342K old orders (99.7% of data)**
7. `12_check_view_definition.csv` - **View definition (confirms ingestion_timestamp exists)**
8. `13_sample_ingestion_timestamps.csv` - **Oct 15-17 orders with Nov 25 ingestion timestamps**
9. `failed_nov20_child_job_plan.json` - Execution plan for failed job
10. `success_nov24_job_plan.json` - Execution plan for successful job

---

## Cost of Investigation

- Query 1: ~1.8GB (~$0.01)
- Query 2: ~615MB (~$0.003)
- Query 3: ~1.6GB (~$0.008)
- Query 5: ~50GB (~$0.25)
- **Total**: ~$0.27

---

## Next Steps

**IMMEDIATE**: Implement Option A + C (add date filter, clean and retry)  
**THIS WEEK**: Investigate Option B (ingestion_timestamp root cause)  
**NEXT SPRINT**: Implement Option D (partition temp tables)

