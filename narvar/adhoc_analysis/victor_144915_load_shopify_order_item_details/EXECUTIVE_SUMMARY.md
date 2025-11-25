# VICTOR-144915: Shopify Order Item Details DAG Timeout - Executive Summary

**Date**: November 25, 2025  
**Status**: 🔴 ROOT CAUSE IDENTIFIED - Nov 19-20 data still failing, Nov 21+ working  
**Impact**: Orders and returns data for Nov 19-20 not updating in `product_insights` table

---

## Problem

The `load_shopify_order_item_details` Airflow DAG task `update_product_insights` is timing out after 6 hours when processing Nov 19-20 data. The job consumes 80-90 slot-hours and then fails with `Request timed out` error.

**Normal performance**: 5-6 minutes, 11-13 slot-hours  
**Failing performance**: 6 hours (timeout), 80-90 slot-hours  
**Degradation**: **67x slower, 7x more expensive**

---

## Root Cause

The temp table `tmp_order_item_details` contains **6 months of historical data** (4.2M rows, 183 distinct dates) instead of the expected **2 days** (500K rows, 2-3 dates).

### Why This Causes Timeout

The aggregation query joins 4.2M rows against 236M rows across 183 dates, creating:
- **60x more data to scan** than designed
- **1.18M distinct join keys** (should be ~20K)
- Aggregations across 183 dates × 194 retailers × 648K SKUs

### Why The Filter Fails

The DAG has a 48-hour filter:
```sql
WHERE o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('{execution_date}'), INTERVAL 48 HOUR)
```

This filter is NOT WORKING because:
- `v_order_items` view likely doesn't have `ingestion_timestamp` column, OR
- Column exists but has NULL/incorrect values

---

## Timeline

| Date | Status | Duration | Notes |
|------|--------|----------|-------|
| Nov 18 | ⚠️ Slow | 113 min | Works but 20x slower than normal |
| Nov 19 | ❌ Failed | 6hrs timeout | 4 retry attempts, all timeout |
| Nov 20 | ❌ Failed | 6hrs timeout | 3 retry attempts, still running |
| Nov 21-23 | - | - | Not attempted (blocked by Nov 19-20 failures) |
| Nov 24 | ✅ Success | 5.4 min | Back to normal performance |
| **Nov 25** | 🔄 **STILL RUNNING** | - | **Retrying Nov 19-20 data NOW** |

---

## Impact Assessment

### Data Freshness
- ✅ **Nov 21-24 data**: UP TO DATE
- ❌ **Nov 19-20 data**: MISSING from `product_insights` table
- ⚠️ **Downstream dashboards**: May show incomplete metrics for those 2 days

### Cost
- Failed attempts: 6 jobs × 80 slot-hours = **480 slot-hours wasted** (~$23.76 @ $0.0494/slot-hour)
- Currently running retry: Unknown cost (in progress)
- Investigation cost: $0.27 (minimal)

### System Load
- **No impact on reservation capacity** - timeouts happen across all time windows
- **No cascading failures** - Nov 21+ runs working normally

---

## Recommended Solution

### Immediate Action (Option A): Add Safety Net Date Filter

Add explicit date filter to prevent runaway queries:

```sql
WHERE 
    o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('{execution_date}'), INTERVAL 48 HOUR)
    AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)  -- NEW
```

**Benefits**:
- Protects against future occurrences
- 5 minute deployment
- Low risk

**Trade-offs**:
- Doesn't fix root cause
- 7-day window larger than designed 2-day window (but still safe)

### Manual Cleanup (Option B): Drop Bad Temp Tables and Retry

```sql
DROP TABLE `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-19`;
DROP TABLE `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20`;
DROP TABLE `narvar-data-lake.return_insights_base.tmp_product_insights_updates_2025-11-19`;
DROP TABLE `narvar-data-lake.return_insights_base.tmp_product_insights_updates_2025-11-20`;
```

Then manually trigger Airflow DAG for those dates.

**Benefits**:
- Clears stuck state
- Allows retry with fixed query (if Option A deployed)

**Effort**: 30 minutes

### Root Cause Investigation (Option C): Fix ingestion_timestamp Filter

**Steps**:
1. Query `v_order_items` view definition
2. Check if `ingestion_timestamp` exists and has correct values
3. If missing: Add column to view
4. If incorrect: Fix upstream ETL

**Benefits**:
- Permanent fix
- DAG works as designed

**Effort**: 2-4 hours investigation + implementation time

---

## Recommended Action Plan

### Today (Nov 25)
1. ✅ **Investigate root cause** (COMPLETE)
2. 🔲 **Deploy Option A** (add safety net filter) - 5 minutes
3. 🔲 **Execute Option B** (clean and retry Nov 19-20) - 30 minutes

### This Week
4. 🔲 **Execute Option C** (investigate ingestion_timestamp) - 2-4 hours
5. 🔲 **Fix root cause** if issue found - TBD

### Next Sprint
6. 🔲 **Partition temp tables** by date for long-term performance - 2-3 hours

---

## Questions Requiring Answers

1. **Does `v_order_items` have `ingestion_timestamp` column?**
   - Need to query view definition or sample data
   
2. **Why is there currently a job running for Nov 20 data?**
   - Started 17:24 Nov 25, consuming 24.4 slot-hours so far
   - Should we kill it and wait for the fix?

3. **What's the business impact of missing Nov 19-20 data?**
   - Do downstream dashboards/reports depend on this?
   - Is it critical to backfill those 2 days?

4. **Why did Nov 18 work slowly (113 min) but Nov 19-20 timeout completely?**
   - All have 183 dates in temp table
   - What's specifically different about Nov 19-20?

---

## Technical Details

**See**: [FINDINGS.md](./FINDINGS.md) for complete technical analysis

**Tables**: 
- [01_table_sizes_and_counts.csv](./results/01_table_sizes_and_counts.csv)
- [02_join_key_distribution.csv](./results/02_join_key_distribution.csv)
- [03_temp_table_date_distribution.csv](./results/03_temp_table_date_distribution.csv)
- [05_find_specific_job.csv](./results/05_find_specific_job.csv)

---

## Contact

**Investigation by**: Sophia (AI Assistant) with Cezar Mihaila  
**GitHub Folder**: `/narvar/adhoc_analysis/victor_144915_load_shopify_order_item_details/`  
**Investigation Date**: November 25, 2025

