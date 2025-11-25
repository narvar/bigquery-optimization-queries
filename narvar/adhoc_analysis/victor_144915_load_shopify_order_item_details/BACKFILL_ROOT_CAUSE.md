# Root Cause: Continuous Data Backfill in v_order_items_atlas

**Discovery Date**: November 25, 2025 (Evening)  
**Investigation**: Queries 10-13  
**Status**: 🔴 CRITICAL - Ongoing data quality issue

---

## Executive Summary

The DAG timeout is NOT caused by a broken `ingestion_timestamp` filter. The filter is working correctly, but **upstream ETL is continuously re-ingesting historical orders** from May-November 2025, giving them recent `ingestion_timestamp` values that legitimately pass the 48-hour filter.

**Impact**: 5 retailers account for 360K re-ingested old orders, creating 183 distinct dates in aggregations and causing 6-hour timeouts.

---

## The Discovery

### What We Initially Thought

"The `ingestion_timestamp >= TIMESTAMP_SUB(...)` filter isn't working because the column doesn't exist or has NULL values."

### What We Actually Found

1. ✅ `ingestion_timestamp` column **DOES exist** in `v_order_items_atlas`
2. ✅ The filter **IS working correctly** (checking ingestion time, not order time)
3. ❌ **BUT**: Old orders are being continuously re-ingested with NEW timestamps
4. ❌ **Result**: Old orders legitimately pass the filter, causing aggregation explosion

---

## Evidence

### Query 12: View Definition

```sql
-- v_order_items view definition
SELECT 
    a.retailer_moniker,
    a.store_name,
    order_date,
    ...
    a.ingestion_timestamp,  ← Column exists!
    a.event_ts
FROM `narvar-data-lake.return_insights_base.v_order_items_atlas` a
...
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY date(order_date), retailer_moniker, store_name, order_number, order_item_sku
    ORDER BY ingestion_timestamp DESC  ← Uses ingestion_timestamp for deduplication
) = 1
```

**Confirmed**: `ingestion_timestamp` exists and is used for deduplication.

---

### Query 13: Sample Ingestion Timestamps (SMOKING GUN!)

Sampled 100 orders from **Oct 15-17, 2025** (35-41 days old):

| Order Date | Ingestion Timestamp | Days Order→Ingestion | Filter Status |
|------------|---------------------|---------------------|---------------|
| 2025-10-16 12:25:28 | **2025-11-25 19:48:22** | **40 days** | ✅ PASSES 48hr filter |
| 2025-10-16 11:49:34 | **2025-11-25 19:02:41** | **40 days** | ✅ PASSES 48hr filter |
| 2025-10-17 12:24:23 | **2025-11-25 18:58:39** | **39 days** | ✅ PASSES 48hr filter |
| 2025-10-15 01:49:38 | **2025-11-25 17:56:11** | **41 days** | ✅ PASSES 48hr filter |

**Pattern**: Orders placed Oct 15-17 were re-ingested on Nov 25 (today), giving them timestamps within the last 24 hours.

**All 100 sampled records show the same pattern**: Recent ingestion (Nov 25), old orders (Oct 15-17).

---

### Query 11: Retailer Concentration

The backfill is concentrated in specific retailers:

| Retailer | Very Old Orders | % of Data | Date Span | Has Return | No Return |
|----------|----------------|-----------|-----------|------------|-----------|
| **nicandzoe** | **342,109** | **99.7%** | 55 days | 150 | **363,568** |
| **icebreakerapac** | **5,840** | **79.7%** | 59 days | 7 | **10,085** |
| **skims** | **5,423** | **41.2%** | 183 days | 11,131 | **469,080** |
| **milly** | **3,643** | **91.4%** | 76 days | 158 | **4,809** |
| **stevemadden** | **3,118** | **55.1%** | 178 days | 1,712 | **48,987** |

**Top 5 = 360K very old orders = 21% of all problematic records**

**Key observation**: nicandzoe is the outlier with 342K very old orders (94% of all very old orders!).

---

### Query 10: Return Activity Analysis

Checked if old orders are included due to recent return activity:

**Old orders (before Nov 13)**:
- Total: 1,726,249
- With recent returns (last 3 months): ~35,000 (2%)
- With NO returns: ~1,691,000 (**98%**)

**Conclusion**: The backfill is NOT driven by recent return activity. These are pure order re-ingestions.

---

## Why This Causes the DAG to Fail

### The Legitimate Filter Pass

```sql
-- DAG filter
WHERE o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('2025-11-20'), INTERVAL 48 HOUR)
```

**Filter cutoff**: Nov 20 - 48 hours = **Nov 18, 2025 00:00:00**

**Old order ingestion timestamps**: Nov 25, 2025 (various hours)

**Comparison**: Nov 25 > Nov 18 ✅ **PASSES FILTER**

### But Creates Massive Aggregation Load

Even though the filter works, the result is:
1. Temp table gets 4.2M rows with **183 distinct order_date values**
2. Aggregation groups by `order_date` (among 15 dimensions)
3. Creates: 183 dates × 194 retailers × 648K SKUs = 10-50M groups
4. BigQuery runs out of memory
5. Timeout after 6 hours

---

## Root Cause Chain

```
1. Upstream ETL/Dataflow
   └─> Continuously re-ingests historical orders for specific retailers
   
2. v_order_items_atlas table
   └─> Gets old orders with NEW ingestion_timestamp = current_timestamp
   
3. v_order_items view
   └─> Exposes these records with recent ingestion_timestamp
   
4. DAG filter (working correctly!)
   └─> Includes old orders because ingestion_timestamp is recent
   
5. tmp_order_item_details temp table
   └─> Accumulates 183 distinct order_date values (May-Nov)
   
6. update_product_insights aggregation
   └─> Groups by 183 dates × other dimensions
   └─> Creates 10-50M grouping combinations
   └─> Exceeds memory capacity
   └─> TIMEOUT after 6 hours
```

---

## Why Specific Dates Fail

### Nov 18: Slow but Works (113 min)
- Had 183 dates in temp table
- Aggregation took 113 minutes (marginal - on the edge of timeout)
- Barely completed before 6-hour limit

### Nov 19-20: Timeout (6 hours)
- Also had 183 dates in temp table  
- **Hypothesis**: Slightly more data or different data distribution
- **OR**: Resource contention (peak season approaching)
- Pushed aggregation over the edge → timeout

### Nov 24: Back to Normal (5.4 min)
- **Hypothesis**: Cleanup task finally ran, dropped old temp tables
- New temp table created fresh
- Less backfill data on that specific day?
- **Need to verify**: Check Nov 24 temp table date distribution

---

## Who Owns This Data?

### Upstream Source

**Table**: `narvar-data-lake.return_insights_base.v_order_items_atlas`

**Likely populated by**:
- Shopify order ingestion pipeline (Dataflow/Pub/Sub)
- CDC (Change Data Capture) from Shopify API
- Scheduled backfill jobs

**Need to find**:
- Who owns this pipeline?
- Is backfill intentional or bug?
- Can we add `is_backfill` flag to distinguish backfilled vs new records?

---

## Recommended Actions (Updated)

### Immediate (Today - 35 min)

**Option A: Add explicit date filter** (5 min)
```sql
WHERE 
    o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('{execution_date}'), INTERVAL 48 HOUR)
    AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)  -- NEW
    AND DATE(o.order_date) <= DATE('{execution_date}')  -- NEW
```

**Why this works**:
- `ingestion_timestamp` filter catches recently ingested data (working!)
- `order_date` filter prevents old backfilled orders from causing aggregation explosion
- Even if nicandzoe re-ingests Oct 15 orders, they won't be included

**Option B: Clean and retry** (30 min)
- Drop bad Nov 19-20 temp tables
- Retry with fixed query

### This Week (4-8 hours)

**Option C: Investigate and stop backfill**
1. Find who owns `v_order_items_atlas` ingestion pipeline
2. Understand why backfill is happening (intentional or bug?)
3. If intentional: Add `is_backfill` flag to records
4. If bug: Fix the continuous re-ingestion
5. Update DAG to exclude backfilled records: `WHERE is_backfill IS NOT TRUE`

### Next Sprint (2-3 hours)

**Option D: Partition temp tables**
- Reduces scan size even if backfill continues
- Future-proofs against similar issues

---

## Questions for Upstream Team

1. **Who owns `v_order_items_atlas` ingestion?**
   - Dataflow team?
   - Shopify integration team?

2. **Is the continuous backfill intentional?**
   - Data quality fixes?
   - Schema evolution?
   - Historical data refresh?

3. **Why these specific retailers?**
   - nicandzoe: 342K old orders
   - icebreakerapac, skims, milly, stevemadden: 18K combined
   - What's special about them?

4. **Can we add a backfill indicator?**
   - `is_backfill` boolean column
   - Or `ingestion_type` enum (NEW, UPDATE, BACKFILL)
   - Would allow DAG to exclude backfilled records

5. **What's the backfill schedule?**
   - Continuous streaming?
   - Hourly batch?
   - Daily batch?
   - Query 13 shows ingestion at various hours (08:00, 09:00, 12:00, 13:00, etc.)

---

## Investigation Cost

- Queries 1-5: ~$0.27
- Queries 10-13: ~$1.50 (larger scans)
- **Total**: ~$1.77 (comprehensive investigation)

---

## Files for Review

### Core Analysis
- **EXECUTIVE_SUMMARY.md** - Updated with backfill discovery
- **FINDINGS.md** - Complete root cause analysis
- **ANSWER_TO_CEZAR.md** - Answers with backfill explanation

### New Analysis
- **BACKFILL_ROOT_CAUSE.md** (this file) - Detailed backfill investigation
- **PROBLEMATIC_RECORDS_ANALYSIS.md** - Record-level analysis

### Evidence
- `results/10_return_dates_analysis.csv` - 98% have no returns
- `results/11_old_records_by_retailer.csv` - nicandzoe concentration
- `results/12_check_view_definition.csv` - View structure
- `results/13_sample_ingestion_timestamps.csv` - Backfill timestamps proof

