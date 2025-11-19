# Next Session: Monitor & Hub Consumer Analysis

**Use this as your starting prompt for the next AI session**

---

```markdown
I'm working on BigQuery capacity optimization for Narvar's 1,700-slot reservation.

**PROJECT STATUS** (November 12, 2025):
- Phase 1: ✅ COMPLETE (43.8M jobs classified across 9 periods)
- Phase 2: ✅ COMPLETE (Root cause analysis, executive strategy approved)
- **Current Task**: Deep dive into Monitor projects and Hub dashboard performance

**CONTEXT FILES TO READ** (Priority order):
1. @AI_SESSION_CONTEXT.md - Complete project context, Phase 1 & 2 findings
2. @INV6_HUB_QOS_RESULTS.md - Hub QoS crisis (39% violations - CRITICAL ISSUE)
3. @PEAK_2025_2026_STRATEGY_EXEC_REPORT.md - Executive recommendation (for background)
4. @ROOT_CAUSE_ANALYSIS_FINDINGS.md - Root cause distribution (69/23/8%)

**PHYSICAL TABLE AVAILABLE**:
`narvar-data-lake.query_opt.traffic_classification`
- 43.8M jobs, 9 periods (Sep 2022 - Oct 2025)
- Latest baseline: Baseline_2025_Sep_Oct (most recent data)
- Schema and query examples in AI_SESSION_CONTEXT.md

**CRITICAL FINDINGS FROM PHASE 2**:
1. **Hub QoS Crisis** 🚨:
   - 39.4% violation rate during Peak_2024_2025 CRITICAL stress
   - vs. 8.5% for Monitor (retailer queries)
   - **44x slower execution** (P95: 1,521s vs 34s for Monitor)
   - Growing worse: 11.9% (2023-2024) → 39.4% (2024-2025)

2. **Root Cause Distribution** (2025 data, 129 incidents):
   - 69% AUTOMATED (inefficient pipelines)
   - 23% INTERNAL (growing concern - up from 12%)
   - 8% EXTERNAL (minimal customer issues)

3. **Reservation Impact**:
   - Shared 1,700-slot pool causes QoS degradation during stress
   - 49.6% violations on reserved vs 1.5% on on-demand
   - ON_DEMAND dominated Peak_2024_2025 (56.75% of capacity, massive cost)

4. **Monitor-base Reclassification**:
   - Moved EXTERNAL → AUTOMATED (it's batch infrastructure, not customer queries)
   - New capacity split: EXTERNAL 6%, AUTOMATED 79%, INTERNAL 15%

**STRATEGIC DECISION MADE**:
- Monitoring-based approach (not pre-loading capacity)
- Focus: Process optimization + automated controls
- Cost avoidance: $58K-$173K

---

## 🎯 CURRENT OBJECTIVE: Monitor & Hub Consumer Analysis

**Goal**: Deep dive into individual consumer behavior, costs, and QoS patterns

**TWO SEPARATE ANALYSES** (not comparative study):

### **Analysis 1: Monitor Project Performance Profiles**

**Questions to Answer**:
1. **Who does the most work?**
   - Top 20 retailers by job volume
   - Top 20 by slot consumption
   - Trends over time (growing vs stable retailers)

2. **Costs per retailer**:
   - Slot-hours consumed
   - Estimated monthly cost per retailer
   - Cost trends (Sep-Oct 2024 vs 2025)
   - Identify cost optimization targets

3. **Type of activity**:
   - Query patterns (simple selects vs complex aggregations)
   - Execution time distribution
   - Usage frequency (queries/day, queries/hour)
   - Peak usage times (hour-of-day, day-of-week)

4. **QoS issues per retailer**:
   - Which retailers have highest violation rates?
   - QoS trends over time (improving or degrading?)
   - Correlation with query complexity or volume
   - Identify retailers needing query optimization

**Deliverables**:
- SQL query: `queries/phase2_consumer_analysis/retailer_performance_profile.sql`
- Jupyter notebook: `notebooks/monitor_retailer_analysis.ipynb` with visualizations
- Report: `MONITOR_RETAILER_PERFORMANCE.md` with findings and recommendations
- Images: Save charts to `images/monitor_*` (cost rankings, QoS heatmaps, usage patterns)

**Data Available**:
- `results/baseline_2025_monitor_projects_FINAL.csv` - All 100 monitor projects
- Classification table with `retailer_moniker` field (207-565 retailers per period)
- 9 periods for trend analysis

---

### **Analysis 2: Hub Dashboard Deep Dive** 🚨 CRITICAL

**Critical Issue**: 39.4% violation rate during Peak_2024_2025 (vs 8.5% for Monitor)

**Questions to Answer**:
1. **Which specific queries/dashboards violate SLA?**
   - Identify slowest 20 Hub queries
   - Query patterns (what kind of analysis?)
   - Data volume scanned per query
   - Dashboard IDs if available in query metadata

2. **Who is using Hub and how?**
   - Concurrent Hub users during stress periods
   - Usage frequency (queries/day)
   - Auto-refresh patterns (are dashboards auto-refreshing?)
   - Peak usage correlation with CRITICAL stress

3. **What drives the costs?**
   - Slot consumption by query type
   - Bytes scanned patterns
   - Most expensive queries (top 20)
   - Cost trends over time

4. **QoS pattern analysis**:
   - When do violations occur? (time-of-day, stress correlation)
   - Are violations clustered? (specific users, specific dashboards)
   - Performance during NORMAL vs WARNING vs CRITICAL states
   - Historical trend: Why 3.3x worse in 2024-2025 vs 2023-2024?

5. **Why is Hub 44x slower than Monitor?**
   - Query complexity comparison (joins, aggregations)
   - Data model differences
   - Looker-specific overhead?
   - Inefficient query patterns

**Deliverables**:
- SQL query: `queries/phase2_consumer_analysis/hub_qos_deep_dive.sql`
- Jupyter notebook: `notebooks/hub_dashboard_analysis.ipynb`
- Report: `HUB_QOS_OPTIMIZATION_PLAN.md` with:
  * Top 10 slowest queries to optimize
  * Dashboard governance recommendations
  * Query optimization opportunities
  * Potential need for separate Hub reservation
  * Expected QoS improvement from optimizations
- Images: Save charts to `images/hub_*` (violation trends, query distribution, time patterns)

**Data Available**:
- Hub data in classification table (consumer_subcategory = 'HUB')
- `INV6_HUB_QOS_RESULTS.md` has initial findings
- Can analyze query_text_sample field for query patterns
- 3 periods for trend analysis (2023-2024, 2024-2025, 2025 baseline)

---

## 🛠️ **Approach & Tools**:

### **SQL Analysis Queries**:
```sql
-- Example: Per-Retailer Performance
SELECT
  retailer_moniker,
  COUNT(*) as jobs,
  ROUND(SUM(slot_hours), 2) as total_slot_hours,
  ROUND(SUM(estimated_slot_cost_usd), 2) as estimated_cost,
  ROUND(AVG(execution_time_seconds), 2) as avg_exec_seconds,
  COUNTIF(is_qos_violation) as qos_violations,
  ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) as violation_pct
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE consumer_subcategory = 'MONITOR'
  AND analysis_period_label IN ('Baseline_2025_Sep_Oct', 'Peak_2024_2025')
  AND retailer_moniker IS NOT NULL
GROUP BY retailer_moniker
ORDER BY total_slot_hours DESC
LIMIT 20;
```

### **Jupyter Notebook Structure**:
```python
# 1. Import data from BigQuery
# 2. Exploratory analysis
# 3. Create visualizations:
#    - Cost ranking charts
#    - QoS violation heatmaps  
#    - Usage pattern time series
#    - Query complexity distributions
# 4. Save images to /images folder
# 5. Generate insights and recommendations
```

### **Visualization Types Needed**:
- **Bar charts**: Top retailers by cost, top Hub queries by violation rate
- **Heatmaps**: Hour-of-day × day-of-week usage patterns
- **Time series**: QoS trends over periods, cost trends
- **Scatter plots**: Cost vs QoS quality, volume vs violations
- **Distribution plots**: Execution time histograms

---

## 📊 **Expected Outputs**:

### **For Monitor Analysis**:
1. **Top 20 retailers** by cost (with trends)
2. **Bottom 20 retailers** by QoS compliance (optimization targets)
3. **Usage patterns**: When retailers query most (hour-of-day heatmaps)
4. **Cost efficiency ranking**: Cost per query, cost per slot-hour
5. **Recommendations**: Which retailers need optimization, governance policies

### **For Hub Analysis** (URGENT):
1. **Root cause** of 39% violation rate (query complexity, concurrency, or both?)
2. **Top 10 problematic queries** with optimization suggestions
3. **Dashboard governance** recommendations (auto-refresh policies, usage limits)
4. **Capacity assessment**: Does Hub need separate reservation?
5. **Expected QoS improvement** if optimizations implemented

---

## ⚠️ **Important Considerations**:

### **Data Limitations**:
- Monitor retailer matching: ~34% match rate (limited by t_return_details)
- 207-565 unique retailers per period (sufficient sample)
- Hub query text: Limited to 500-char sample (may not show full complexity)
- No dashboard attribution in audit logs (can't map to specific dashboards)

### **QoS Thresholds**:
- Monitor: <60 seconds (customer-facing SLA)
- Hub: <60 seconds (customer-facing dashboards)
- Both are P0 (external customer impact)

### **Key Insight from INV6**:
Hub violations are NOT just capacity-related:
- Similar slot consumption (52 vs 45 avg concurrent slots)
- But 44x execution time difference
- **Suggests query optimization needed, not just more capacity**

---

## 🚀 **Execution Plan**:

### **Step 1: Create Analysis Queries** (2-3 hours)
1. `retailer_performance_profile.sql` - Per-retailer metrics
2. `hub_qos_deep_dive.sql` - Hub-specific analysis
3. Test queries on Peak_2024_2025 and Baseline_2025_Sep_Oct

### **Step 2: Run Queries & Extract Data** (30-60 min)
1. Execute SQL queries
2. Export results to CSV
3. Load into Jupyter notebook

### **Step 3: Create Visualizations** (2-3 hours)
1. Setup notebook environment
2. Create all charts and heatmaps
3. Save to /images folder
4. Generate insights from visual patterns

### **Step 4: Document Findings** (1-2 hours)
1. MONITOR_RETAILER_PERFORMANCE.md
2. HUB_QOS_OPTIMIZATION_PLAN.md (priority!)
3. Summary of recommendations

**Total Estimated Time**: 1-2 days

---

## 💾 **Available Data & Results**:

**CSV Files**:
- `results/baseline_2025_monitor_projects_FINAL.csv` - 100 monitor projects
- `results/customer_qos_summary.csv` - QoS metrics
- `results/stress_state_summary.csv` - Stress analysis

**BigQuery Tables**:
- `narvar-data-lake.query_opt.traffic_classification` - Main classified data (43.8M jobs)
- `narvar-data-lake.query_opt.phase2_stress_periods` - Stress timeline (if created)
- Various Phase 2 analysis tables (check query_opt schema)

**Existing Analysis**:
- INV6 has initial Hub vs Monitor comparison
- Can build on those findings for deeper analysis

---

## 🎯 **Success Criteria**:

### **For Monitor Analysis**:
- [ ] Top 20 retailers identified (cost and usage)
- [ ] QoS problem retailers identified
- [ ] Usage pattern insights documented
- [ ] Optimization recommendations provided
- [ ] Visualizations created and saved

### **For Hub Analysis** (CRITICAL):
- [ ] Root cause of 39% violations identified
- [ ] Top 10 problematic queries documented
- [ ] Optimization plan created (with expected QoS improvement estimate)
- [ ] Dashboard governance recommendations
- [ ] Decision: separate reservation needed or query optimization sufficient?

---

Let's start by creating the SQL analysis queries for both Monitor and Hub!
```

---

**Repository**: https://github.com/narvar/bigquery-optimization-queries/tree/main/narvar/analysis_peak_2025_sonnet45

**Key Files**:
- AI Context: https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/AI_SESSION_CONTEXT.md
- Hub Crisis: https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/INV6_HUB_QOS_RESULTS.md

**Start the new session with this prompt!** 🚀

