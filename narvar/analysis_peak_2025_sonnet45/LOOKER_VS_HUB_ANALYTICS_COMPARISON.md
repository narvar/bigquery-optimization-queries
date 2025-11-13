# Looker vs Hub Analytics API - Comparison Summary

**Date**: November 12, 2025  
**Purpose**: Clarify naming and compare the two dashboard platforms

---

## ⚠️ IMPORTANT NAMING CLARIFICATION

Based on feedback from Eric Rops, there was confusion in naming:

**BEFORE** (Incorrect):
- Called everything "Hub" 
- Didn't distinguish between Looker and Hub Analytics API

**AFTER** (Correct):
- **Looker**: consumer_subcategory = 'HUB' (looker service accounts)
- **Hub Analytics API**: consumer_subcategory = 'ANALYTICS_API' (analytics-api-bigquery-access)

---

## 📊 Side-by-Side Comparison

| Metric | Looker (HUB subcategory) | Hub Analytics API (ANALYTICS_API) | Winner |
|--------|--------------------------|-----------------------------------|--------|
| **Queries (Total)** | 235,977 | 812,010 | Hub 🏆 3.4x more |
| **Queries (Peak)** | 132,389 | 489,457 | Hub 🏆 3.7x more |
| **Queries (Baseline)** | 103,588 | 322,553 | Hub 🏆 3.1x more |
| **Queries/Day** | ~1,600 | ~5,300 | Hub 🏆 3.3x more |
| **Monthly Cost** | $148 | $226 | Looker 🏆 35% cheaper |
| **Cost per Query** | $0.0075 | $0.0031 | Hub 🏆 2.4x cheaper! |
| **QoS Violations** | 2.6% | **0.0%** | Hub 🏆 PERFECT! |
| **P95 Execution** | 16s | 10s | Hub 🏆 1.6x faster |
| **Avg Execution** | 7.3s | 3.5s | Hub 🏆 2.1x faster |
| **Reservation** | Mixed | 100% RESERVED | - |
| **Retailer Attribution** | 72.9% | N/A* | - |

*Hub Analytics API doesn't have retailer attribution in queries (serves all retailers via API)

---

## 🔑 Key Insights

### **1. Hub Analytics API is LARGER and BETTER**
- **3.4x more queries** than Looker (812K vs 236K)
- **0% QoS violations** vs Looker's 2.6%
- **2x faster** average execution (3.5s vs 7.3s)
- **2.4x cheaper per query** ($0.0031 vs $0.0075)

**Implication**: Hub Analytics API is the **primary dashboard platform** at Narvar, with Looker being a smaller supplementary tool.

### **2. Different Use Cases**
- **Looker**: Retailer-specific dashboards (72.9% have retailer attribution)
  - Dashboard views for individual retailers
  - More complex queries (80% have GROUP BY)
  - Higher QoS violations (2.6%)
  
- **Hub Analytics API**: Backend API serving all retailers
  - Programmatic API calls (not interactive dashboards)
  - Simpler, more optimized queries
  - Perfect QoS (0% violations!)

### **3. Cost Efficiency**
- **Hub Analytics**: $226/month for 812K queries = **$0.0031/query**
- **Looker**: $148/month for 236K queries = **$0.0075/query**
- Hub Analytics is **2.4x more cost-efficient** per query

**Why?**
- Hub Analytics uses optimized API queries (simpler, faster)
- Looker uses ad-hoc dashboard queries (more complex, slower)
- Both use RESERVED_SHARED_POOL, but Hub queries are better optimized

---

## 💰 Combined Dashboard Platform Costs

| Platform | Monthly Cost | % of Total | Queries/Month | Cost/Query |
|----------|--------------|------------|---------------|------------|
| **Hub Analytics API** | $226 | 60% | 67,668 | $0.0031 |
| **Looker** | $148 | 40% | 19,665 | $0.0075 |
| **Total Dashboard Platforms** | **$374** | **100%** | **87,333** | **$0.0043** |

**Context**: Combined dashboard costs ($374/month) represent ~0.9% of total BigQuery monthly costs (~$41K/month historical average).

---

## 🚨 Revised Priorities Based on Correct Naming

### **Looker (HUB subcategory)** - Issues Remain:
- ✅ 2.6% overall violations (acceptable)
- 🚨 3.5% Peak violations (needs improvement)
- 🚨 Aggregate dashboards slow (top 10 cost $19.20, all violate SLA)
- **Priority**: Optimize aggregate dashboards before peak

### **Hub Analytics API (ANALYTICS_API)** - Excellent Performance:
- ✅ 0% violations (PERFECT!)
- ✅ Fast execution (P95=10s)
- ✅ Cost-efficient ($0.0031/query)
- ✅ High volume (812K queries) handled well
- **Priority**: No immediate action needed - serving as good reference for optimization

---

## 📋 Updated Action Items

### **For Looker** (consumer_subcategory = 'HUB'):
1. Optimize aggregate dashboards (top 10 queries)
2. Implement peak period controls (auto-refresh restrictions)
3. Query result caching for frequently accessed dashboards

### **For Hub Analytics API** (consumer_subcategory = 'ANALYTICS_API'):
1. ✅ **No optimization needed** - performing excellently!
2. Use as benchmark for query optimization best practices
3. Document what makes Hub Analytics queries so efficient

### **Cross-Platform**:
1. Understand why Hub Analytics (ANALYTICS_API) has 0% violations while Looker has 2.6%
2. Apply Hub Analytics optimization patterns to Looker queries
3. Investigate if Looker can adopt Hub Analytics query strategies

---

## 📚 Reports Available

**Looker Analysis**:
- `LOOKER_2025_ANALYSIS_REPORT.md` - 235,977 queries, 72.9% retailer attribution
- `queries/phase2_consumer_analysis/looker_full_2025_analysis.sql`
- `scripts/run_looker_full_analysis.py`

**Hub Analytics API Analysis** (New):
- Results: `results/hub_analytics_api_performance_20251112_205931.csv`
- Query: `queries/phase2_consumer_analysis/hub_analytics_api_performance.sql`
- Script: `scripts/run_hub_analytics_api_analysis.py`

**Monitor Analysis**:
- `MONITOR_2025_ANALYSIS_REPORT.md` - 205,483 queries, 284 retailers

---

**Status**: ✅ **Naming corrected, real Hub Analytics discovered and analyzed**

**Next**: Create full Hub Analytics API report similar to Looker/Monitor reports (if needed)

