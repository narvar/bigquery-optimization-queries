# Retailer Usage Profiling - Phase 1

**Status:** In Progress  
**Timeline:** 2-4 weeks  
**Priority:** HIGH - Required before any optimization decisions  
**Date Started:** November 19, 2025

---

## 🎯 Objectives

Understand actual retailer behavior to validate cost optimization scenarios:

1. **Latency Requirements** - How fresh does data need to be?
2. **Retention Requirements** - How far back do customers query?
3. **Cost Attribution** - What does each retailer actually cost?
4. **Usage Segmentation** - Group retailers by behavior patterns

---

## 📁 Analysis Structure

### **fashionnova/** ⭐ **HIGHEST PRIORITY**

**Why priority:**
- Highest cost retailer: $99,718/year (37.8% of platform)
- Highest compute consumption: 74.89% of Monitor slot-hours
- Most customization and integration
- **Their behavior likely drives platform requirements**

**Deliverables:**
- Latency requirements (query freshness analysis)
- Retention requirements (historical data lookback)
- Cost breakdown by table and operation type
- Query pattern analysis
- Dashboard usage patterns

**Timeline:** Week 1-2

---

### **all_retailers/**

**Purpose:** Segment all 284 retailers by behavior and cost

**Deliverables:**
- Cost distribution (top 20 retailers = 80% of costs)
- Latency requirement distribution
- Retention requirement distribution
- Usage pattern clustering

**Timeline:** Week 2-3

---

## 📊 Segmentation Framework

### Category 1: Dashboard Type (Business Function)
- Operations: Real-time tracking, alerts, exceptions
- Analytics: Trends, performance metrics, comparisons
- Executive: Weekly/monthly summaries, KPIs
- Ad-hoc: Exploration, one-off analysis

### Category 2: Frequency of Use
- High frequency: >100 queries/day
- Medium frequency: 10-100 queries/day
- Low frequency: <10 queries/day
- Inactive: No queries in last 30 days

### Category 3: Minimum Acceptable Latency ⭐ **CRITICAL**
- Real-time required: Query data <1 hour old
- Near-time acceptable: Query data 1-6 hours old
- Same-day acceptable: Query data 6-24 hours old
- Historical: Query data >24 hours old

**Method:** Analyze query_time - MAX(date_field_in_query) distribution

### Category 4: Minimum Acceptable Retention ⭐ **CRITICAL**
- 3 months: Query data from last 90 days only
- 6 months: Query data from last 180 days
- 1 year: Query data from last 365 days
- >1 year: Query historical data beyond 1 year

**Method:** Analyze MAX(lookback_period) from query date filters

---

## 🔬 Analysis Methodology

### Data Source
`narvar-data-lake.query_opt.traffic_classification`

**Key columns:**
- `retailer_moniker` - Identify retailer
- `start_time` - When query ran
- `query_text_sample` - Extract date filters (500 char sample)
- `slot_hours` - Cost proxy
- `consumer_subcategory` - Filter for 'MONITOR'

### Analysis Approach

**Latency Analysis:**
```sql
-- Extract date from query filters
-- Calculate: start_time - MAX(data_date_in_filter)
-- This shows: "How old was the data when queried?"
-- Distribution tells us latency requirements
```

**Retention Analysis:**
```sql
-- Extract date range from query filters
-- Calculate: MAX(end_date - start_date) in filters
-- This shows: "How far back do they query?"
-- Distribution tells us retention requirements
```

**Challenges:**
- Query text is truncated to 500 characters
- Date filters have many formats (CURRENT_DATE(), DATE_SUB(), explicit dates, BETWEEN)
- Need robust regex patterns to capture most queries

---

## 📈 Expected Outcomes

**Phase 1 Results Will Determine:**

1. **Is latency optimization viable?**
   - IF >80% of queries use data >6 hours old → 6-hour batching is safe
   - IF >90% of queries use data >24 hours old → daily batching is safe
   - IF fashionnova needs real-time → consider tiered SLA model

2. **Is retention optimization viable?**
   - IF >90% of queries look back <6 months → 1-year retention is safe
   - IF >95% of queries look back <1 year → 2-year retention is safe
   - IF some retailers need >2 years → archive old data separately

3. **What are realistic cost savings?**
   - Conservative scenario: Based on 80th percentile behavior
   - Aggressive scenario: Based on 95th percentile behavior

---

## 🚀 Work Plan

**Week 1:**
- fashionnova latency analysis
- fashionnova retention analysis
- fashionnova cost breakdown
- fashionnova query pattern classification

**Week 2:**
- All retailers latency distribution
- All retailers retention distribution
- Retailer clustering by behavior
- Cost distribution analysis

**Week 3:**
- Validate optimization scenarios with profiling data
- Update cost savings estimates
- Create retailer segmentation report
- Document findings

**Week 4:**
- Buffer for validation and refinement
- Prepare Product team presentation
- Update pricing strategy with profiling results

---

## 📂 File Organization

Each analysis subdirectory (fashionnova/, all_retailers/) contains:

```
queries/          SQL queries used
results/          CSV/TXT query results
*.md              Analysis findings and documentation
```

**Consolidated deliverable:** `RETAILER_USAGE_PROFILING_RESULTS.md` (combines both analyses)

---

**Last Updated:** November 19, 2025  
**Status:** Ready to begin fashionnova analysis

