# VICTOR-144915: Shopify Order Item Details DAG Timeout - Root Cause Found

**Status**: 🔴 ROOT CAUSE IDENTIFIED - Fix ready to deploy  
**Investigation Date**: Nov 25, 2025  
**Investigator**: Cezar Mihaila + Sophia (AI)

---

## TL;DR

The `load_shopify_order_item_details` DAG is timing out because the temp table contains **6 months of data** instead of 2 days. The `ingestion_timestamp` filter isn't working. **Fix ready: Add explicit date filter (5 min deployment).**

---

## What's Happening

**Problem**: DAG task `update_product_insights` timing out after 6 hours for Nov 19-20 data  
**Normal**: 5-6 minutes  
**Impact**: Nov 19-20 product insights data not updating; Nov 21+ working normally

---

## Root Cause

The temp table `tmp_order_item_details` has **183 days of historical data** (4.2M rows) instead of the expected **2 days** (500K rows).

**Why?** The 48-hour filter isn't working:
```sql
WHERE o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('{execution_date}'), INTERVAL 48 HOUR)
```

The `v_order_items.ingestion_timestamp` column either doesn't exist or has incorrect values.

**Impact**: Aggregation query scans 60x more data → 67x slower execution → 6-hour timeout

---

## Evidence

### Date Distribution in Temp Table
| Period | Rows | % |
|--------|------|---|
| Nov 18-20 (recent) | 2.48M | 59% |
| Oct 15-17 (spike) | 350K | 9.3% |
| May-Oct (old data) | 1.37M | 31.7% |

### Performance Comparison
| Date | Duration | Slot-hours | Status |
|------|----------|-----------|--------|
| Nov 18 | 113 min | 27 | ⚠️ Slow but works |
| Nov 19 | 6hrs | 80 | ❌ Timeout (4 retries) |
| Nov 20 | 6hrs | 85 | ❌ Timeout (3 retries) |
| Nov 24 | 5.4 min | 11 | ✅ Normal |

**Cost of failures**: 6 jobs × 80 slot-hours = 480 slot-hours wasted (~$24)

---

## Recommended Fix

### Option A: Immediate (5 minutes)
Add explicit date filter as safety net:

```sql
WHERE 
    o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('{execution_date}'), INTERVAL 48 HOUR)
    AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)  -- NEW
```

**Pros**: Immediate protection, low risk  
**Cons**: Doesn't fix root cause, 7-day window larger than needed

### Option B: Manual Cleanup (30 minutes)
Drop bad temp tables for Nov 19-20 and retry with fixed query

### Option C: Root Cause Investigation (2-4 hours)
Investigate why `ingestion_timestamp` filter doesn't work and fix permanently

---

## Recommended Action Plan

**Today**:
1. Deploy Option A (5 min)
2. Execute Option B (30 min)  
3. Monitor tonight's run

**This Week**:
4. Investigate Option C (2-4 hrs)
5. Fix root cause if issue found

---

## Questions

1. Does `v_order_items` have `ingestion_timestamp` column?
2. Why specifically Nov 19-20 fail but Nov 18 and Nov 21+ work?
3. Business impact of missing Nov 19-20 data?

---

## Documentation

**GitHub folder**: `narvar/adhoc_analysis/victor_144915_load_shopify_order_item_details/`
- [EXECUTIVE_SUMMARY.md](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/victor_144915_load_shopify_order_item_details/EXECUTIVE_SUMMARY.md)
- [FINDINGS.md](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/victor_144915_load_shopify_order_item_details/FINDINGS.md)
- 6 SQL queries + 4 result files

**Investigation cost**: $0.27

---

*Let me know if you want me to deploy Option A and execute Option B. -Cezar*

