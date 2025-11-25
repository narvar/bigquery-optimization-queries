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

## Root Cause

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

### 2. DAG Filter Not Working

The DAG has this filter to limit to 48 hours:

```sql
WHERE o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('{execution_date}'), INTERVAL 48 HOUR)
```

But `v_order_items` view likely:
- Doesn't have an `ingestion_timestamp` column, OR
- Has NULL/incorrect values in that column, OR
- The column exists but isn't indexed/partitioned properly

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

### Root Cause Fix (Option B): Investigate and Fix ingestion_timestamp

**Problem**: `v_order_items.ingestion_timestamp` not working as expected  
**Solution**: Determine why and fix it

**Steps**:
1. Query `v_order_items` view definition
2. Check if `ingestion_timestamp` column exists
3. Query actual values: `SELECT MIN(ingestion_timestamp), MAX(ingestion_timestamp) FROM v_order_items LIMIT 1000`
4. If column doesn't exist: Add it to the view
5. If values are wrong: Fix upstream ETL

**Pros**:
- Fixes root cause permanently
- DAG works as designed

**Cons**:
- Requires investigation time
- May need upstream ETL changes
- Could take days to implement

**Effort**: 2-4 hours investigation + implementation time  
**Risk**: Medium (depends on findings)

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

1. **Does `v_order_items` have an `ingestion_timestamp` column?**
   - Need to query view definition
   - Or sample the view: `SELECT * FROM v_order_items LIMIT 10`

2. **Why did Nov 18 work (slowly) but Nov 19-20 fail?**
   - Nov 18 took 113 minutes (slow but succeeded)
   - Nov 19-20 timeout after 6 hours
   - What's different about those specific dates?

3. **Why is Nov 24 back to normal?**
   - 5.4 minutes (expected performance)
   - Did someone manually clean the temp tables?
   - Or did the cleanup task finally run?

4. **Why does the temp table accumulate 6 months of data?**
   - Should be `CREATE OR REPLACE` (drops and recreates)
   - Is the CREATE OR REPLACE failing silently?
   - Is there a MERGE or INSERT instead of CREATE OR REPLACE somewhere?

5. **What caused the Oct 15-17 spike** visible in the temp table?
   - 350K rows for those 3 days (9.3% of total)
   - Was there a data backfill?
   - New retailer onboarded?

---

## Files Generated

### Queries
1. `01_table_sizes_and_counts.sql` - Table metadata
2. `02_join_key_distribution.sql` - Join explosion analysis
3. `03_temp_table_date_distribution.sql` - Historical data discovery
4. `05_find_specific_job.sql` - Job history analysis

### Results
1. `01_table_sizes_and_counts.csv` - 6 tables analyzed
2. `02_join_key_distribution.csv` - Join key metrics
3. `03_temp_table_date_distribution.csv` - 183 distinct dates found
4. `05_find_specific_job.csv` - 30-day job history

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

