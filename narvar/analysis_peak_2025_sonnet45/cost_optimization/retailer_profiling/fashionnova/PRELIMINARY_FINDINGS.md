# fashionnova Preliminary Findings

**Date:** November 19, 2025  
**Status:** ⚠️ **CRITICAL DISCREPANCY IDENTIFIED**  
**Analysis Period:** 2 months (Sep-Oct 2024)

---

## 🚨 Critical Finding - Cost Discrepancy

**Original Estimate (from FASHIONNOVA_TOTAL_COST_ANALYSIS.md):**
- Annual cost: $99,718
- 37.8% of platform cost
- 74.89% of platform slot-hours

**Today's Analysis (from traffic_classification):**
- Queries: 4,015
- Slot-hours: 8,816
- **Annual cost: $869** (using RESERVED pricing $0.0494/slot-hour)

**Discrepancy: $98,849 (114x difference)**

---

## 📊 Coverage Analysis Results

**Total fashionnova queries (Sep-Oct 2024):**
- Queries: 4,015
- Slot-hours: 8,816.39
- 6-month cost: $435.53
- Annualized: $868.68

**Date filter visibility (500-char sample):**
- ship_date filters: 2,893 queries (72.05%, 8,769 slot-hours, $864/year)
- order_date filters: 16 queries (0.4%, 0.22 slot-hours)
- delivery_date filters: 18 queries (0.45%, 1.26 slot-hours)
- **ANY date filter: 2,895 queries (72.1%, 8,769 slot-hours, $864/year)**
- No visible filter: 1,120 queries (27.9%, 47 slot-hours, $5/year)

**Analysis coverage:** 
- Can analyze 72.1% of queries for latency/retention
- These represent 99.5% of cost (queries with date filters are the expensive ones)
- 27.9% without visible filters are mostly cheap queries (<0.5% of cost)

---

## ❓ Questions to Resolve

### 1. Where does the $99,718 come from?

**Hypothesis A:** Original analysis used different data source
- Maybe includes ETL/production costs (MERGEs to shipments table)
- Maybe uses a different attribution model (40/30/30 hybrid mentioned)
- Maybe includes infrastructure costs

**Hypothesis B:** traffic_classification is incomplete
- Maybe doesn't capture all fashionnova queries
- Maybe only captures certain query types
- Maybe the classification itself filters some queries out

**Hypothesis C:** Different time periods
- Original used different baseline period
- Sep-Oct 2024 might be unusually low for fashionnova
- Need to check historical trends

**Action needed:** Review FASHIONNOVA_TOTAL_COST_ANALYSIS.md to understand methodology

---

### 2. Why are there only 4,015 queries?

**Context:**
- fashionnova is supposedly the highest-traffic retailer (74.89% of slot-hours)
- But 4,015 queries over 2 months = 67 queries/day
- This seems LOW for the highest-traffic retailer

**Possible explanations:**
- fashionnova runs very expensive queries (high slot-hours per query)
- Most fashionnova cost is ETL (not captured in traffic_classification consumer queries)
- The classification filters out certain query types
- fashionnova had reduced activity in Sep-Oct 2024

---

## 🔍 What We Can Still Analyze

Despite the cost discrepancy, we can proceed with profiling the 4,015 queries we have:

**Latency Analysis (72% coverage):**
- 2,893 queries with ship_date filters
- Representing 99% of fashionnova's consumption cost
- Can determine: "How fresh does data need to be for these queries?"

**Retention Analysis (72% coverage):**
- Same 2,893 queries
- Can determine: "How far back do these queries look?"

**Limitation:**
- Only analyzing consumption queries, not ETL
- Only analyzing Sep-Oct 2024 (2-month sample)
- Missing 28% of queries (but they're only 0.5% of cost)

---

## 🎯 Recommended Next Steps

**Option A: Pause and reconcile costs first**
- Review FASHIONNOVA_TOTAL_COST_ANALYSIS.md methodology
- Understand where $99,718 comes from
- Determine if we're analyzing the right queries
- **Pro:** Avoids analyzing wrong dataset
- **Con:** Delays profiling work

**Option B: Continue with profiling, reconcile later**
- Create latency/retention queries for the 4,015 queries
- Document findings with caveat about cost discrepancy
- Reconcile costs after we have behavioral insights
- **Pro:** Makes progress on profiling
- **Con:** Might be profiling incomplete dataset

**My recommendation:** Option A - reconcile costs first. A 114x discrepancy suggests we might be looking at the wrong data or missing major cost components. Better to understand what we're analyzing before drawing conclusions.

---

## 📁 Files Status

**Queries created:**
- `00_test_audit_log_join.sql` - ✅ Validated (but too slow for main analysis)
- `01_sample_coverage_simple.sql` - ✅ Complete (4,015 queries, 72% have date filters)
- `02_cost_breakdown.sql` - ⚠️ Bug identified (showing incorrect totals)

**Results saved:**
- `audit_log_join_test.txt` - 20 sample queries with full text
- `coverage_analysis.txt` - Coverage funnel results
- `cost_breakdown.txt` - Has bug, numbers don't reconcile

**Not created yet:**
- Latency analysis query
- Retention analysis query
- fashionnova findings document

---

**Created by:** Sophia (AI)  
**Date:** November 19, 2025  
**Status:** Blocked pending cost reconciliation



