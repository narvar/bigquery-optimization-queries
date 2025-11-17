# Archive Folder - Superseded Documents

**Date Archived:** November 17, 2025  
**Reason:** Superseded by FINAL cost analysis documents

---

## 📁 What's in This Archive

This folder contains intermediate and outdated cost analysis documents that have been superseded by final validated versions.

**These files are kept for historical reference only. Do NOT use for current analysis.**

---

## 📋 Archived Files

### Superseded by FINAL Documents:

| Archived File | Superseded By | Reason |
|--------------|---------------|---------|
| RETURN_ITEM_DETAILS_PRODUCTION_COST.md | RETURN_ITEM_DETAILS_FINAL_COST.md | Used incorrect Method B ($124K vs $12K) |
| RETURN_RATE_AGG_PRODUCTION_COST.md | RETURN_RATE_AGG_FINAL_COST.md | Old calculation, missing workload details |
| FT_BENCHMARKS_PRODUCTION_COST.md | BENCHMARKS_FINAL_COST.md | Missing ETL costs |
| TNT_BENCHMARKS_PRODUCTION_COST.md | BENCHMARKS_FINAL_COST.md | Missing ETL costs |
| ORDERS_PRODUCTION_COST.md | ORDERS_TABLE_FINAL_COST.md | Incomplete analysis |
| ORDERS_TABLE_PRODUCTION_COST.md | ORDERS_TABLE_FINAL_COST.md | Duplicate/intermediate |
| ORDERS_TABLE_COST_ANALYSIS.md | ORDERS_TABLE_FINAL_COST.md | Intermediate analysis |
| ORDERS_TABLE_COST_ASSESSMENT_PLAN.md | ORDERS_TABLE_FINAL_COST.md | Planning document |

### Superseded by MONITOR_PLATFORM_COMPLETE_COST_ANALYSIS.md:

| Archived File | Reason |
|--------------|---------|
| COMPLETE_PRODUCTION_COST_SUMMARY.md | Old platform summary |
| PRIORITY_3_COMPLETE_SUMMARY.md | Intermediate summary |
| CLEANUP_SUMMARY.md | Cleanup tracking (completed) |

### Superseded by Updated Methodology:

| Archived File | Reason |
|--------------|---------|
| SHIPMENTS_COST_METHOD_COMPARISON.md | Merged into PRIORITY_1_SUMMARY.md |
| SHIPMENTS_COST_RESOLUTION.md | Merged into SHIPMENTS_PRODUCTION_COST.md |

---

## ✅ Current Authoritative Documents

**Use these documents for all current analysis:**

### Individual Table Costs (6 documents):
1. `../SHIPMENTS_PRODUCTION_COST.md` - $176,556/year
2. `../ORDERS_TABLE_FINAL_COST.md` - $45,302/year
3. `../RETURN_ITEM_DETAILS_FINAL_COST.md` - $11,871/year
4. `../BENCHMARKS_FINAL_COST.md` - $586/year (ft + tnt combined)
5. `../RETURN_RATE_AGG_FINAL_COST.md` - $194/year
6. Carrier_config: $0 (negligible - no dedicated doc needed)

### Platform Summaries (3 documents):
7. `../MONITOR_PLATFORM_COMPLETE_COST_ANALYSIS.md` - Comprehensive technical report
8. `../MONITOR_COST_SUMMARY_TABLE.md` - Quick reference tables
9. `../../MONITOR_COST_EXECUTIVE_SUMMARY.md` - Executive summary

### Methodology (2 documents):
10. `../CORRECT_COST_CALCULATION_METHODOLOGY.md` - Method A approach
11. `../PRIORITY_1_SUMMARY.md` - Method A vs B comparison (shipments)

### Discovery/Findings (2 documents):
12. `../ORDERS_TABLE_CRITICAL_FINDINGS.md` - How orders table was discovered
13. `../CRITICAL_FINDING_COST_CALCULATION_ERROR.md` - Method B bug explained

---

## ⚠️ Important Notes

1. **Never use Method B** (audit log analysis) - Use Method A (traffic_classification) always
2. **All FINAL documents** include complete code/data/billing references
3. **Platform cost is $263,084/year** - Validated Nov 17, 2025
4. **Confidence level: 95%** - All tables validated

---

**Archived:** November 17, 2025  
**Reason:** Superseded by validated FINAL cost analyses  
**Safe to delete:** Yes, after 30-day retention period

