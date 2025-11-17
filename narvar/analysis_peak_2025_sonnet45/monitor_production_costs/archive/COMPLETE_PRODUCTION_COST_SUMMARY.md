# Monitor Platform - Complete Production Cost Summary

**Analysis Date:** November 14, 2025  
**Time Periods:** Peak_2024_2025 (Nov 2024-Jan 2025) + Baseline_2025_Sep_Oct (Sep-Oct 2025)  
**Status:** ✅ PARTIAL COMPLETE - 3 tables need validation

---

## 🎯 EXECUTIVE SUMMARY

### **Total Monitor Platform Cost: $598,347.56/year**

**Breakdown:**
- Production Costs: $591,930/year (98.9%)
- Consumption Costs: $6,418/year (1.1%)

**vs Conservative Estimate:** $207,375/year  
**Multiplier:** **2.9x higher**

---

## 📊 PRODUCTION COST BREAKDOWN (7 Base Tables)

### Confirmed Tables (4 of 7)

| Table | Annual Cost | % of Production | Status | Evidence |
|-------|-------------|-----------------|--------|----------|
| **monitor_base.shipments** | **$467,922** | 79.0% | ✅ CONFIRMED | 13,576 ETL jobs found |
| **return_item_details** | **$123,717** | 20.9% | ✅ CONFIRMED | 8,716 ETL jobs found |
| **return_rate_agg** | $291 | 0.0% | ✅ NEGLIGIBLE | 153 ETL jobs found |
| **carrier_config** | $0 | 0.0% | ✅ NEGLIGIBLE | 10 manual updates |
| **Subtotal (Confirmed)** | **$591,930** | **100%** | | |

### Unconfirmed Tables (3 of 7)

| Table | Estimated Cost | Status | Next Action |
|-------|----------------|--------|-------------|
| **orders** | $0-$? | ❓ NOT FOUND | Verify table exists, get view definition |
| **tnt_benchmarks_latest** | $0-$100 | ❓ NOT FOUND | Verify table type, update frequency |
| **ft_benchmarks_latest** | $0-$100 | ❓ NOT FOUND | Verify table type, update frequency |
| **Subtotal (Unknown)** | **$0-$200?** | | |

### Platform Total

**Known Costs:** $591,930  
**Unknown Costs:** $0-$200 (likely negligible)  
**Consumption:** $6,418  
**Total Platform:** **~$598,348/year**

---

## 🔍 DETAILED FINDINGS BY TABLE

### 1. monitor_base.shipments - $467,922/year ✅

**ETL Pattern:**
- 13,576 MERGE operations in 5 months
- ~90 merges/day (every ~16 minutes)
- Service: monitor-base-us-prod@appspot.gserviceaccount.com

**Used By:** v_shipments, v_shipments_events, v_shipments_transposed, and indirectly by v_orders, v_order_items, benchmarks

**Note:** Different from previous $200,957 estimate (used different baseline period)

**See:** `SHIPMENTS_PRODUCTION_COST_UPDATED.md`

---

### 2. return_insights_base.return_item_details - $123,717/year ✅

**ETL Pattern:**
- 8,716 MERGE operations in 5 months
- ~58 merges/day (every ~25 minutes)
- Service: airflow-bq-job-user-2@narvar-data-lake.iam.gserviceaccount.com

**Used By:** v_return_details (via analytics.v_unified_returns_base)

**Purpose:** Shopify returns data processing

**See:** `RETURN_ITEM_DETAILS_PRODUCTION_COST.md`

---

### 3. reporting.return_rate_agg - $291/year ✅

**ETL Pattern:**
- 153 MERGE operations in 5 months
- ~1 merge/day (nightly batch)
- Service: airflow-bq-job-user-2@narvar-data-lake.iam.gserviceaccount.com

**Classification:** NEGLIGIBLE (<0.05% of costs)

**See:** `RETURN_RATE_AGG_PRODUCTION_COST.md`

---

### 4. monitor_base.carrier_config - $0/year ✅

**ETL Pattern:**
- 10 manual operations in 5 months
- Infrequent manual updates by data team
- INSERT/UPDATE by cezar.mihaila, julia.le, eric.rops

**Classification:** NEGLIGIBLE (effectively $0)

**See:** `CARRIER_CONFIG_PRODUCTION_COST.md`

---

### 5. monitor_base.orders - UNKNOWN ❓

**Audit Log Result:** 0 operations found

**Hypothesis:** Likely a VIEW on monitor_base.shipments (not a separate base table)

**Action Required:** 
- Verify table exists
- Get v_orders and v_order_items view definitions
- Confirm it references shipments (no separate production cost)

**See:** `ORDERS_TABLE_PRODUCTION_COST.md`

---

### 6. monitor_base.tnt_benchmarks_latest - UNKNOWN ❓

**Audit Log Result:** 0 operations found

**Hypothesis:** Infrequent update table or view

**Estimated Cost:** $0-$100/year (likely negligible)

**See:** `TNT_BENCHMARKS_PRODUCTION_COST.md`

---

### 7. monitor_base.ft_benchmarks_latest - UNKNOWN ❓

**Audit Log Result:** 0 operations found

**Hypothesis:** Infrequent update table or view

**Estimated Cost:** $0-$100/year (likely negligible)

**Usage:** fashionnova uses minimally (1.53 slot-hours total)

**See:** `FT_BENCHMARKS_PRODUCTION_COST.md`

---

## 📈 PLATFORM COST EVOLUTION

| Estimate | Amount | Method | Status |
|----------|--------|--------|--------|
| **Initial Conservative** | $207,375 | monitor_base.shipments only ($201K) + consumption | ✅ Complete |
| **Partial Discovery** | $554,843 | Wrong annualization (14 months) | ❌ Error |
| **Current (Partial)** | $598,348 | 4 confirmed tables + consumption | ✅ Current Best Estimate |
| **Final (Pending)** | $598,348-$598,548 | After validating 3 unknown tables | 📋 Pending |

**Best Current Estimate:** **~$598,000/year**

---

## 💰 COST ALLOCATION FOR PRICING

### Production Costs by Component

**Primary Production (97.9%):**
- monitor_base.shipments: $467,922 (79.0%)
- return_item_details: $123,717 (20.9%)

**Secondary Production (0.1%):**
- return_rate_agg: $291
- All others: ~$0

**Consumption (1.1%):**
- Query execution: $6,418

### Attribution Model

**For retailers using shipment views only:**
```
Cost share = % of (shipments production + consumption)
         = % of ($467,922 + $6,418) = % of $474,340
```

**For retailers using return views:**
```
Additional cost = % of return_item_details production
                = % of $123,717
```

**Example: fashionnova**
- Uses shipment views: 99.6% of query volume
- Uses return views: 0.4% of query volume
- Shipment attribution (34%): $467,922 × 0.34 = $159,094
- Return attribution (TBD%): $123,717 × TBD% = $?
- Consumption: $1,616
- **Total: ~$160K-$165K/year** (preliminary)

---

## ⚠️ CRITICAL ISSUES & NEXT STEPS

### Issue 1: Discrepancy with Previous Shipments Cost

**Problem:** New analysis shows $467,922 vs previous $200,957 (2.3x higher)

**Resolution Needed:**
- Validate which figure is more accurate
- Understand if this represents growth or methodology difference
- Decide which to use for pricing strategy

**Impact:** Affects all pricing calculations significantly

---

### Issue 2: Unknown Tables (3 of 7)

**Problem:** orders, tnt_benchmarks_latest, ft_benchmarks_latest not found in audit logs

**Resolution Needed:**
- Get view definitions for v_orders, v_order_items, v_benchmark_tnt, v_benchmark_ft
- Verify if these reference separate base tables or use shipments directly
- Confirm production costs (likely $0-$200 total)

**Impact:** Minor (likely <$200/year), but need to confirm for completeness

---

### Issue 3: fashionnova Return Usage Attribution

**Problem:** Need to calculate fashionnova's share of return_item_details costs

**Resolution Needed:**
- Calculate what % of Monitor platform return queries come from fashionnova
- Apply attribution model to $123,717 return_item_details cost
- Add to fashionnova total cost

**Impact:** Could add $10K-$50K to fashionnova's total cost

---

## 📋 QUESTIONS FOR DATA ENGINEERING TEAM

### Critical (Blocking Completion)

1. **Shipments cost validation:** Is $467,922/year realistic for 2025, or should we use $200,957 from 2024 baseline?

2. **Orders table:** Does monitor_base.orders exist as a base table, or do v_orders/v_order_items query shipments directly?

3. **Benchmark tables:** Are tnt_benchmarks_latest and ft_benchmarks_latest actual tables or views? If tables, what's their production cost?

### Secondary (Nice to Have)

4. **Airflow DAGs:** Which DAGs populate shipments and return_item_details?

5. **Optimization opportunities:** Can MERGE frequency be reduced (90/day for shipments, 58/day for returns)?

6. **Non-BigQuery costs:** Any Dataflow, GCS, or other infrastructure costs not captured in BigQuery audit logs?

---

## 🎯 RECOMMENDED PLATFORM COST FOR PRICING

**Conservative Approach:** Use confirmed costs only

**Platform Total (Conservative):** **$598,348/year**
- monitor_base.shipments: $467,922
- return_item_details: $123,717
- Other confirmed: $291
- Consumption: $6,418

**Platform Total (If 3 unknowns are negligible):** **~$598,350/year**

**Average per Retailer:** $2,107/year

---

## 📁 INDIVIDUAL TABLE REPORTS

1. **SHIPMENTS_PRODUCTION_COST.md** - Original $200,957 analysis (for reference)
2. **SHIPMENTS_PRODUCTION_COST_UPDATED.md** - New $467,922 analysis
3. **RETURN_ITEM_DETAILS_PRODUCTION_COST.md** - $123,717 analysis
4. **RETURN_RATE_AGG_PRODUCTION_COST.md** - $291 (negligible)
5. **CARRIER_CONFIG_PRODUCTION_COST.md** - $0 (negligible)
6. **ORDERS_TABLE_PRODUCTION_COST.md** - Unknown, needs investigation
7. **TNT_BENCHMARKS_PRODUCTION_COST.md** - Unknown, likely negligible
8. **FT_BENCHMARKS_PRODUCTION_COST.md** - Unknown, likely negligible

---

**Prepared by:** AI Analysis  
**Data Source:** BigQuery audit logs (Peak_2024_2025 + Baseline_2025_Sep_Oct)  
**Confidence Level:** 70% (4 of 7 tables confirmed, 3 pending validation)  
**Status:** ⚠️ Needs Data Engineering validation before finalizing

---

*This summary will be updated when the 3 unknown tables are resolved*

