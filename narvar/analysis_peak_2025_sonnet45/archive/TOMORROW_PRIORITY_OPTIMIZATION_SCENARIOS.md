# Tomorrow's Priority - Cost Optimization Scenarios

**Date Created:** November 17, 2025  
**For:** Julia Le (Data Engineering) + Product Team  
**Requested By:** Julia Le  
**Priority:** 🚨 TOP PRIORITY (before other analysis)  
**Estimated Time:** 7.5 hours (full day)  
**Status:** 📋 Ready to start

**Key Addition:** Query pattern profiling to understand actual data freshness and retention needs

---

## 🎯 Request Summary

**From Julia's feedback:**

> "I assume the highest impact levers for cost reduction are still:
> 1. Changing data latency SLA from near-real time to daily
> 2. Keeping only 1 year of data for visualization
> 
> Could we try a few different numbers, like 1/6/12/24 hours for latency, and similarly for retention?
> 
> Goal is to see the relative impact of each one and by how much."

**Julia's philosophy:** "Bring not only problems but also potential solutions" ✅

---

## 📊 Analysis Scope

### Optimization Lever #1: Data Latency SLA

**Current state:**
- **shipments:** Near-real-time via App Engine MERGE (continuous)
- **orders:** Real-time via Dataflow streaming (continuous)
- **return_item_details:** 30-minute via CDC + Airflow

**Test scenarios:**
1. **Baseline:** Near-real-time (current) - $0 savings
2. **1-hour batching** - Estimated savings
3. **6-hour batching** - Estimated savings
4. **12-hour batching** - Estimated savings
5. **24-hour batching (daily)** - Estimated savings

**For each scenario, calculate:**
- App Engine cost reduction (fewer MERGE operations)
- Dataflow cost reduction (batch mode vs streaming)
- Pub/Sub cost reduction (message batching)
- CDC/Airflow frequency reduction
- **Total cost impact**

**Tables impacted:** shipments ($177K), orders ($45K), return_item_details ($12K)

---

### Optimization Lever #2: Data Retention

**Current state:**
- **orders:** 23.76B rows, 88.7 TB (includes 2022-2023 data = 85 TB!)
- **shipments:** 19.1 TB
- **return_item_details:** 40 GB
- **Total storage cost:** $25,260/year

**Test scenarios:**
1. **Baseline:** Current (all historical) - $0 savings
2. **2-year retention** - Delete pre-2023 data
3. **1-year retention** - Delete pre-2024 data
4. **6-month retention** - Operational only
5. **3-month retention** - Minimal operational

**For each scenario, calculate:**
- Storage savings (direct reduction)
- Compute savings (smaller tables = faster queries)
- Query performance improvement
- **Total cost impact**

**Primary target:** orders table (82% of storage = $20,430/year)

**Data-driven approach:** Profile actual query patterns to understand realistic retention needs
- Parse date filters from query_text_sample (ship_date, order_date, etc.)
- Calculate lookback period distribution (1 month, 3 months, 6 months, 1 year, >1 year)
- Example: "95% of queries filter to last 90 days" → 6-month retention is safe
- Example: "Only 3 retailers query >1 year" → Archive old data, keep accessible separately

---

### Combined Scenarios (Matrix)

**Test high-impact combinations:**

| Scenario | Latency | Retention | Est. Savings |
|----------|---------|-----------|--------------|
| Conservative | 12-hour | 1-year | $40K-$60K |
| Moderate | 6-hour | 2-year | $50K-$70K |
| Aggressive | 24-hour | 6-month | $80K-$120K |

---

## 📋 Analysis Plan (7.5 hours)

### Morning Session (4.5 hours)

**1. Latency Scenario Analysis (2 hours)**

**Tasks:**
- [ ] Analyze current Dataflow worker patterns (continuous vs batch potential)
- [ ] Model App Engine MERGE frequency reduction (hourly, 6-hour, 12-hour, daily batches)
- [ ] Calculate Pub/Sub message batching savings
- [ ] Research batch mode pricing for Dataflow (potential CUD savings)
- [ ] Create cost reduction table for each latency scenario

**Deliverable:** Latency scenarios with cost savings + technical feasibility

---

**2. Query Pattern Analysis - Date Range & Freshness Profiling (1.5 hours)**

**Part A: How far back do customers query? (Retention insights)**

**Tasks:**
- [ ] Profile shipments queries: Date range lookback patterns
  - Analyze ship_date, order_date filters in query_text_sample
  - Calculate: % queries covering last 1 month, 3 months, 6 months, 1 year, >1 year
  - Break down by retailer (fashionnova vs others)
- [ ] Profile orders queries: Date range patterns
- [ ] Profile return_item_details queries: Date range patterns
- [ ] Identify which queries actually need >1 year of data

**Example insights for retention:**
- "99% of queries cover only last 3 months"
- "Only 5 retailers query >1 year historical data"
- "fashionnova queries last 6 months 95% of the time"

---

**Part B: How fresh does data need to be? (Latency insights)**

**Tasks:**
- [ ] Calculate data freshness requirements from query patterns:
  - Compare query execution time vs data dates queried
  - Example: Query runs at 3pm, filters for ship_date = today → needs real-time
  - Example: Query runs at 3pm, filters for ship_date = yesterday → can tolerate 24hr delay
- [ ] Analyze: "Age of data when queried"
  - Calculate: query_time - MAX(ship_date in filter)
  - Distribution: % queries looking at <1 hour old, <6 hours, <24 hours, >24 hours old data
- [ ] Identify time-sensitive use cases:
  - Which queries filter for "today" or "last hour"?
  - Which retailers need near-real-time?
  - Which dashboards are operational vs analytical?

**Example insights for latency:**
- "87% of queries look at data >24 hours old" → Daily batch is sufficient
- "Only 12% of queries filter to 'today'" → Most don't need real-time
- "fashionnova's queries average 3 days old data" → 24-hour latency OK
- "5 retailers query within last hour" → These need real-time, others don't

**Technical approach:**
```sql
-- Calculate data freshness at query time
SELECT 
  retailer_moniker,
  -- Extract ship_date from WHERE clause
  -- Compare: TIMESTAMP_DIFF(start_time, ship_date_filter, HOUR)
  -- This shows: "How old is the data they're querying?"
  CASE 
    WHEN data_age_hours < 1 THEN 'Real-time (<1 hour)'
    WHEN data_age_hours < 6 THEN 'Near-time (<6 hours)'
    WHEN data_age_hours < 24 THEN 'Same-day (<24 hours)'
    ELSE 'Historical (>24 hours)'
  END as freshness_requirement,
  COUNT(*) as queries
GROUP BY 1, 2
```

**Deliverable:** Data-driven retention AND latency needs based on actual usage patterns

---

**3. Retention Scenario Analysis (1 hour)**

**Tasks:**
- [ ] Query current data distribution by year (orders, shipments, returns)
- [ ] Calculate storage savings for each retention period
- [ ] Estimate compute savings (smaller table scans)
- [ ] **Use query pattern analysis** to validate realistic scenarios
- [ ] Identify business impact (which queries/dashboards would break?)

**Deliverable:** Retention scenarios with cost savings + business impact + usage validation

---

### Afternoon Session (3 hours)

**4. Combined Scenario Matrix (1 hour)**

**Tasks:**
- [ ] Create scenario comparison matrix
- [ ] Calculate combined savings for Conservative/Moderate/Aggressive
- [ ] Identify optimal combinations
- [ ] Document trade-offs

**Deliverable:** Decision matrix with recommendations

---

**5. Technical Feasibility Assessment (1.5 hours)**

**Tasks:**
- [ ] How to implement batch MERGE operations (Airflow modifications)
- [ ] How to migrate Dataflow from streaming to batch
- [ ] How to implement data archival/deletion (partition management)
- [ ] Estimate engineering effort for each scenario
- [ ] Risk assessment (data availability, query failures, etc.)

**Deliverable:** Implementation roadmap for each scenario

---

**6. Documentation & Recommendations (0.5 hours)**

**Tasks:**
- [ ] Create comprehensive scenario report
- [ ] Executive summary with recommendations
- [ ] Cost vs business impact trade-off analysis
- [ ] Next steps and decision points

**Deliverable:** `MONITOR_COST_OPTIMIZATION_SCENARIOS.md`

---

## 🎯 Expected Outcomes

### Cost Savings Estimates (Rough - To Validate)

**Latency changes (24-hour daily batch):**
- App Engine/MERGE: $45K-$60K (30-40% reduction)
- Dataflow: $11K-$15K (50-70% reduction to batch mode)
- Pub/Sub: $4K-$6K (20-30% reduction)
- **Subtotal: $60K-$81K**

**Retention changes (1-year):**
- Storage: $14K-$16K (70-80% of orders storage)
- Compute: $16K-$32K (10-20% faster queries)
- **Subtotal: $30K-$48K**

**Combined aggressive (24-hour + 6-month):**
- **Total savings: $90K-$129K** (34-49% platform reduction!)
- **New platform cost: $134K-$173K** (from $263K)

---

## ⚠️ Key Questions to Answer

### Technical Feasibility:

1. Can App Engine MERGE handle batch mode? (Architecture question)
2. Can Dataflow switch to batch without data loss? (Pub/Sub retention limits)
3. What's the engineering effort for each change?
4. What are the risks and rollback plans?

### Business Impact:

1. Which dashboards/queries need real-time data?
2. Can customers accept 24-hour latency?
3. What historical data is actually used? (vs stored "just in case")
4. Impact on Monitor value proposition?

---

## 📁 Deliverable Document Structure

**MONITOR_COST_OPTIMIZATION_SCENARIOS.md**

**Contents:**
1. Executive Summary (savings overview)
2. Current State Analysis (baseline costs)
3. Latency Scenarios (1/6/12/24 hours)
4. Retention Scenarios (3mo/6mo/1yr/2yr)
5. Combined Scenario Matrix
6. Technical Feasibility Assessment
7. Business Impact Analysis
8. Recommendations & Decision Framework
9. Implementation Roadmap
10. Risk Assessment

---

## 🚀 Tomorrow's Schedule

**Priority Order:**
1. ✅ **TOP PRIORITY:** Cost Optimization Scenarios (7.5 hours) - Julia's request
   - Includes query pattern profiling for data-driven retention AND latency recommendations
   - Profile: How far back do customers query? (retention)
   - Profile: How fresh does data need to be? (latency)
2. ⏸️ **DEFERRED:** fashionnova dashboard analysis
3. ⏸️ **DEFERRED:** Scale to all 284 retailers

---

## 💭 My Initial Thoughts (To Explore Tomorrow)

### Latency SLA Reduction: HIGH IMPACT ⭐

**Why high impact:**
- shipments ($177K) could drop to $100K-$120K with daily batch
- orders ($45K) could drop to $20K-$25K with batch Dataflow
- Combined: **$60K-$80K savings** (23-30% platform reduction)

**Technical complexity:** Medium
- Need to modify App Engine → Airflow batch job
- Dataflow streaming → batch mode migration
- Pub/Sub message accumulation (< 7 days retention)

**Business impact:** Medium-High
- Need to validate customer latency requirements
- Some dashboards may require near-real-time
- Most analytics can tolerate daily updates

---

### Data Retention Reduction: MEDIUM IMPACT ⭐

**Why medium impact:**
- orders storage ($20K) could drop to $4K-$6K with 1-year retention
- Faster queries (smaller tables) → 10-20% compute savings
- Combined: **$30K-$48K savings** (11-18% platform reduction)

**Technical complexity:** Low
- Simple DELETE or partition expiration
- Can implement incrementally

**Business impact:** Low-Medium
- Need to identify which dashboards/queries use >1 year data
- Most operational dashboards focus on recent data
- May need data archival for compliance/historical analysis

---

## ✅ Ready to Start Tomorrow

**I'll begin with:**
1. **Query pattern profiling** - How far back do customers actually query? (date range analysis)
2. **Current state data analysis** - Data distribution by age, query patterns by latency
3. **Cost modeling** for each latency and retention scenario
4. **Technical feasibility** research and implementation planning
5. **Comprehensive report** for Julia with recommendations

**Key Addition (per Cezar):**
- Profile queries to understand actual date range usage
- Example: If 99% of queries only look at last month, then keeping 3 years of data is wasteful
- This will give us **data-driven retention recommendations** instead of guessing

**Expected completion:** End of day tomorrow  
**Output:** Decision-ready scenarios with costs, trade-offs, implementation plans, and ACTUAL usage data

---

**Does this plan look good for tomorrow, Cezar?** 🚀

Let me know if you want any adjustments before I start tomorrow!

