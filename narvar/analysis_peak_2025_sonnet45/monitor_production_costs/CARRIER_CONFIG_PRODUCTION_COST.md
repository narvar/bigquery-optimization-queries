# Production Cost Analysis: monitor_base.carrier_config

**Table:** `monitor-base-us-prod.monitor_base.carrier_config`  
**Analysis Date:** November 14, 2025  
**Time Periods:** Peak_2024_2025 + Baseline_2025_Sep_Oct

---

## 🎯 EXECUTIVE SUMMARY

### **Annual Cost: $0.00**

**Classification:** ✅ **NEGLIGIBLE** (effectively $0)

This is a reference/configuration table with virtually no production costs.

---

## 📊 KEY FINDINGS

### ETL Operations

**Timeframe:** 5 months  
**Total Jobs:** 10 operations (manual updates)  
**Frequency:** ~0.07 operations/day (<1 per week)  
**Operations:** INSERT (18), UPDATE (1)

### Resource Consumption

| Metric | 5-Month Total | Annual Estimate |
|--------|--------------|-----------------|
| **ETL Jobs** | 10 | 24 |
| **Slot-Hours** | 0.02 | 0.05 |
| **Annual Cost** | - | **~$0** |

### Service Accounts (Manual Updates)

- cezar.mihaila@narvar.com (1 UPDATE, 1 INSERT)
- julia.le@narvar.com (2 INSERTs)
- eric.rops@narvar.com (18 INSERTs)

---

## 🔍 DETAILED ANALYSIS

### Table Type

**Classification:** Reference/Configuration Data

**Update Pattern:** Manual, infrequent updates to carrier configuration

**Purpose:** Stores carrier settings and monitoring eligibility flags

### Used By Monitor Views

- v_shipments_events (JOIN with carrier_config for monitor_eligible filter)
- v_shipments (likely)
- v_shipments_transposed (likely)

---

## ✅ CONCLUSION

**Classification:** NEGLIGIBLE

**Evidence:**
- Annual cost: ~$0 (rounds to zero)
- Very low frequency: <1 update per week
- Manual operations (not automated ETL)
- Reference data table (small, infrequent changes)

**Recommendation:** No cost attribution needed. Can be ignored in pricing strategy calculations.

---

**Table Type:** Reference/Configuration  
**Production Process:** Manual updates by data team  
**Status:** ✅ Cost proven negligible ($0) - no further action needed

