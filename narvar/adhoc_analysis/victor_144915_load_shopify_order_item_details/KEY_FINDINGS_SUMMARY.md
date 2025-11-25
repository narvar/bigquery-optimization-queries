# VICTOR-144915: Key Findings Summary

**Date**: November 25, 2025  
**Status**: ✅ ROOT CAUSE IDENTIFIED - Continuous Data Backfill

---

## One-Sentence Summary

Old orders (Oct 15-17) are being continuously re-ingested into `v_order_items_atlas` with recent `ingestion_timestamp` values, causing them to legitimately pass the DAG's 48-hour filter and creating 183 distinct dates in the aggregation, which times out after 6 hours.

---

## The Critical Discovery

### What the Filter Does (Working Correctly!)

```sql
WHERE o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('2025-11-20'), INTERVAL 48 HOUR)
```

**Intent**: Get orders ingested in the last 48 hours  
**Actual**: Gets orders ingested in the last 48 hours ✅  
**Problem**: Old orders are being RE-INGESTED continuously with new timestamps ❌

### Proof: Query 13 Results

**Sample of Oct 15-17 orders**:

| order_date | ingestion_timestamp | Days Order→Ingestion | Passes Filter? |
|------------|-------------------|---------------------|----------------|
| 2025-10-16 | 2025-11-25 19:48 | 40 days | ✅ YES |
| 2025-10-15 | 2025-11-25 17:56 | 41 days | ✅ YES |
| 2025-10-17 | 2025-11-25 18:58 | 39 days | ✅ YES |

**ALL 100 sampled records**: Recent ingestion (Nov 25), old order dates (Oct 15-17)

---

## The Numbers

### Retailer Concentration (Query 11)

| Retailer | Very Old Orders | % of Their Total | Date Span |
|----------|----------------|------------------|-----------|
| **nicandzoe** | **342,109** | **99.7%** | 55 days |
| icebreakerapac | 5,840 | 79.7% | 59 days |
| skims | 5,423 | 41.2% | 183 days |
| milly | 3,643 | 91.4% | 76 days |
| stevemadden | 3,118 | 55.1% | 178 days |

**nicandzoe is the outlier**: 94% of all very old orders (342K of 360K)

### Return Activity (Query 10)

| Old Orders (before Nov 13) | Count | % |
|---------------------------|-------|---|
| With recent returns | 35,000 | 2% |
| **With NO returns** | **1,691,000** | **98%** |

**Conclusion**: Backfill is NOT driven by recent return activity. It's pure order data re-ingestion.

---

## Tables and Views Explained

### The Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Upstream ETL/Dataflow Pipeline                               │
│ (Shopify API ingestion + continuous backfill)               │
└─────────────────────┬───────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────┐
│ v_order_items_atlas (BASE TABLE)                            │
│ - Contains: ingestion_timestamp, order_date, order_number   │
│ - Problem: Old orders continuously re-ingested              │
│ - Example: Oct 15 order gets ingestion_timestamp = Nov 25   │
└─────────────────────┬───────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────┐
│ v_order_items (VIEW)                                        │
│ - SELECT ... a.ingestion_timestamp FROM v_order_items_atlas │
│ - Deduplication: ROW_NUMBER() ... ORDER BY ingestion_ts DESC│
│ - Exposes ingestion_timestamp to DAG queries                │
└─────────────────────┬───────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────┐
│ DAG Query (merge_order_item_details task)                   │
│ - Filter: ingestion_timestamp >= execution_date - 48hrs     │
│ - Result: Gets old orders WITH recent ingestion timestamps  │
│ - Problem: 183 distinct order_date values included          │
└─────────────────────┬───────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────┐
│ tmp_order_item_details (TEMP TABLE)                         │
│ - Contains: 4.2M rows, 183 distinct dates                   │
│ - Should contain: 500K rows, 2-3 distinct dates             │
└─────────────────────┬───────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────┐
│ update_product_insights task                                │
│ - GROUP BY: retailer, domain, date, sku, ... (15 dims)     │
│ - Problem: 183 dates creates 10-50M grouping combinations   │
│ - Result: TIMEOUT after 6 hours                             │
└─────────────────────────────────────────────────────────────┘
```

### Key Column: ingestion_timestamp

**Table**: `narvar-data-lake.return_insights_base.v_order_items_atlas`  
**Column**: `ingestion_timestamp` (TIMESTAMP)

**What it tracks**: When the order was ingested/updated in the table (not when order was placed)

**Normal behavior**:
- Order placed Oct 15
- Ingested Oct 15
- `ingestion_timestamp = 2025-10-15`
- After 48 hours: Should be filtered out ✅

**Actual behavior** (causing the problem):
- Order placed Oct 15
- Originally ingested Oct 15
- **Re-ingested Nov 25** (40 days later!)
- `ingestion_timestamp = 2025-11-25` (updated to new value)
- Passes 48-hour filter (Nov 25 - 48hrs = Nov 23) ❌

---

## Why Your Theory Was Partially Correct

You asked: "According to the logic, I think they are legit. Can you check?"

**You were RIGHT!** The old orders ARE legitimate according to the query logic:
1. ✅ They have recent `ingestion_timestamp` (re-ingested Nov 25)
2. ✅ They pass the 48-hour filter correctly
3. ✅ LEFT JOIN allows NULL returns (`OR ri.return_initiation_date IS NULL`)
4. ✅ They satisfy all WHERE clause conditions

**But the result is still problematic** because:
- They create 183 distinct dates in GROUP BY
- Causes aggregation explosion
- Leads to timeout

**The fix**: Add explicit `order_date` filter to prevent old re-ingested orders, regardless of their ingestion timestamp.

---

## Action Items Updated

### Immediate (5 min) - Deploy Explicit Date Filter

**EXACT LOCATION**:
- **File**: `/Users/cezarmihaila/workspace/composer/dags/shopify/load_shopify_order_item_details.py`
- **Task**: `merge_order_item_details` (line 227)
- **WHERE clause**: Lines 335-342
- **Insert after**: Line 340 (after the `INTERVAL 48 HOUR` closing paren)

**See**: 
- [EXACT_CODE_CHANGE.md](./EXACT_CODE_CHANGE.md) ⭐ **Exact line-by-line instructions**
- [DEPLOYMENT_INSTRUCTIONS.md](./DEPLOYMENT_INSTRUCTIONS.md) - Full deployment guide

**The change** (insert these 2 lines after line 340):
```python
                AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)
                AND DATE(o.order_date) <= DATE('{execution_date}')
```

### This Week (4-8 hours)
1. Identify backfill source (who owns `v_order_items_atlas` ingestion?)
2. Understand why backfill happening (intentional or bug?)
3. Coordinate with upstream team to fix:
   - If intentional: Add `is_backfill` flag
   - If bug: Stop continuous re-ingestion

### Critical Questions for Upstream Team

1. **Who owns `v_order_items_atlas` population?**
2. **Why is nicandzoe being continuously backfilled?** (342K old orders!)
3. **Is this a known process or a bug?**
4. **Can we add a backfill indicator to exclude from real-time DAGs?**

---

## Investigation Summary

- ✅ Root cause identified: Continuous data backfill
- ✅ ingestion_timestamp filter working correctly (surprise!)
- ✅ Execution plans analyzed: Aggregation explosion (not cartesian join)
- ✅ Retailer concentration identified: nicandzoe dominates
- ✅ Return activity ruled out: 98% have no returns
- ✅ Fix ready: Add explicit date filter
- 🔲 Upstream coordination needed: Stop unnecessary backfill

**Investigation cost**: $1.77 (9 diagnostic queries)
