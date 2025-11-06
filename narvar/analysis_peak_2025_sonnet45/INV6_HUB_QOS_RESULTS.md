# Investigation 6: HUB vs MONITOR QoS Analysis - RESULTS

**Date**: November 6, 2025  
**Status**: ✅ COMPLETE  
**Duration**: 20 minutes  
**Priority**: 🚨 HIGH (39% HUB violation rate detected)

---

## Objective

Separate HUB (Looker dashboard users) from MONITOR (retailer queries) to understand:
- Are HUB users impacted differently than retailers during stress?
- Why does HUB show 39% violations during Peak_2024_2025 CRITICAL stress?
- Is this a Looker-specific issue or capacity-related?

---

## Critical Findings

### ⚠️ FINDING 1: HUB Severe Degradation in Peak_2024_2025

**HUB QoS During CRITICAL Stress:**
```
Period                  | Jobs | Violations | Rate   | P95 Exec | P99 Exec
------------------------|------|------------|--------|----------|----------
Baseline_2025_Sep_Oct   | 318  | 14         | 4.4%   | 27s      | 108s
Peak_2023_2024          | 244  | 29         | 11.9%  | 685s     | 1,101s
Peak_2024_2025          | 170  | 67         | 39.4%  | 1,521s   | 2,118s (!)
```

**⚠️ KEY OBSERVATIONS:**
- **4x increase** in violation rate: 11.9% → 39.4%
- **2.2x increase** in P95 execution: 685s → 1,521s (25 minutes!)
- **Fewer jobs** but much worse performance (170 vs 244 jobs)

---

### ✅ FINDING 2: MONITOR Relatively Stable

**MONITOR QoS During CRITICAL Stress:**
```
Period                  | Jobs | Violations | Rate   | P95 Exec | P99 Exec
------------------------|------|------------|--------|----------|----------
Baseline_2025_Sep_Oct   | 784  | 39         | 5.0%   | 15s      | 50,560s
Peak_2023_2024          | 411  | 32         | 7.8%   | 73s      | 7,948s
Peak_2024_2025          | 296  | 25         | 8.5%   | 34s      | 82s
```

**✅ OBSERVATIONS:**
- Stable violation rates: 5-8.5% (acceptable range)
- P95 execution reasonable: 15-73s
- Consistent performance across periods

---

### 📊 FINDING 3: Comparison Summary

**Peak_2024_2025 CRITICAL Stress - HUB vs MONITOR:**

| Metric                    | HUB      | MONITOR  | HUB/MONITOR Ratio |
|---------------------------|----------|----------|-------------------|
| Total Jobs                | 170      | 296      | 0.57x             |
| QoS Violations            | 67       | 25       | 2.68x             |
| Violation Rate            | 39.4%    | 8.5%     | **4.64x** (!)     |
| P95 Execution Time        | 1,521s   | 34s      | **44.7x** (!)     |
| Avg Execution Time        | 353.8s   | 8.8s     | 40.2x             |
| Avg Concurrent Slots      | 52.87    | 44.79    | 1.18x             |

**💡 INSIGHT:** HUB queries are taking **44x longer** than MONITOR queries during the same CRITICAL stress windows!

---

## Root Cause Hypotheses

### Hypothesis 1: Looker Dashboard Query Complexity

**Evidence:**
- HUB P95=1,521s vs MONITOR P95=34s during same stress periods
- Not just slower - **dramatically** slower (44x)
- Suggests complex dashboard queries hitting capacity limits

**Possible Causes:**
- Large aggregations across multiple tables
- Inefficient joins or subqueries
- Dashboard auto-refresh during peak load
- Multiple concurrent dashboard users

---

### Hypothesis 2: Peak_2024_2025 Specific Issue

**Evidence:**
- Peak_2023_2024: HUB 11.9% violations, P95=685s
- Peak_2024_2025: HUB 39.4% violations, P95=1,521s (**3.3x worse**)
- MONITOR remained stable (7.8% → 8.5%)

**Possible Causes:**
- New dashboard(s) launched before Peak_2024_2025
- Increased Looker user adoption
- Data volume growth affecting dashboard queries disproportionately
- Specific retailer dashboards with poor performance

---

### Hypothesis 3: Slot Contention vs Query Efficiency

**Evidence:**
- HUB avg concurrent slots: 52.87
- MONITOR avg concurrent slots: 44.79
- **Only 1.18x difference** in slot usage

**Conclusion:** 
- Slot consumption is similar
- **Performance gap is due to query efficiency**, not just resource availability
- HUB queries are inherently slower/less optimized

---

## Detailed Metrics

### All Stress States - HUB Performance

```
Period                  | Stress    | Jobs | Violations | Rate   | P95 Exec
------------------------|-----------|------|------------|--------|----------
Baseline_2025_Sep_Oct   | CRITICAL  | 318  | 14         | 4.4%   | 27s
Peak_2023_2024          | CRITICAL  | 244  | 29         | 11.9%  | 685s
Peak_2024_2025          | CRITICAL  | 170  | 67         | 39.4%  | 1,521s
```

### All Stress States - MONITOR Performance

```
Period                  | Stress    | Jobs | Violations | Rate   | P95 Exec
------------------------|-----------|------|------------|--------|----------
Baseline_2025_Sep_Oct   | CRITICAL  | 784  | 39         | 5.0%   | 15s
Peak_2023_2024          | CRITICAL  | 411  | 32         | 7.8%   | 73s
Peak_2024_2025          | CRITICAL  | 296  | 25         | 8.5%   | 34s
```

**Pattern:** MONITOR is consistently faster and more stable than HUB

---

## Recommendations

### 🚨 IMMEDIATE (Before Nov 2025-Jan 2026 Peak)

**1. Identify Problematic HUB Queries:**
   - Use `monitor-base-us-prod.monitor_audit.v_query_execution` tables
   - Find slowest Looker queries during Peak_2024_2025
   - Identify specific dashboards causing P95=1,521s

**2. Optimization Targets:**
   - Queries taking >30s during CRITICAL stress
   - Dashboards with auto-refresh enabled
   - Multiple concurrent users hitting same dashboard

**3. Quick Wins:**
   - Disable auto-refresh on heavy dashboards during peak
   - Add query result caching
   - Optimize top 5 slowest queries

---

### 📊 MEDIUM-TERM

**4. Capacity Planning:**
   - Consider separate reservation for Looker if optimization doesn't help
   - Monitor HUB workload growth more closely
   - Set P95 target for dashboard queries (e.g., <60s)

**5. Dashboard Governance:**
   - Establish dashboard performance SLA
   - Review/optimize dashboards quarterly
   - Deprecate unused/slow dashboards

---

### 🔍 FURTHER INVESTIGATION NEEDED

**Next Steps (Investigation 7 - HUB Deep Dive):**

1. **Identify Worst Queries:**
   ```sql
   -- Find slowest HUB queries during Peak_2024_2025 CRITICAL stress
   SELECT job_id, execution_time_seconds, query_text_sample
   FROM traffic_classification
   WHERE consumer_subcategory = 'HUB'
     AND analysis_period_label = 'Peak_2024_2025'
     AND execution_time_seconds > 300  -- 5+ minutes
     AND start_time BETWEEN [CRITICAL stress windows]
   ORDER BY execution_time_seconds DESC
   LIMIT 20
   ```

2. **Dashboard Attribution** (if available in monitor_audit):
   - Map queries to specific dashboard names
   - Identify most problematic dashboards
   - Find peak usage times

3. **User Activity Analysis:**
   - Concurrent dashboard users during stress
   - Auto-refresh patterns
   - Peak hour correlation

---

## Data Quality Notes

**Sample Sizes:**
```
Period                  | HUB Jobs | MONITOR Jobs | HUB %
------------------------|----------|--------------|-------
Baseline_2025_Sep_Oct   | 318      | 784          | 28.9%
Peak_2024_2025          | 170      | 296          | 36.5%
Peak_2023_2024          | 244      | 411          | 37.2%
```

- HUB represents 29-37% of EXTERNAL customer jobs during CRITICAL stress
- Sufficient sample size for analysis
- HUB impact is significant, not negligible

---

## Output Table

**Table:** `narvar-data-lake.query_opt.phase2_hub_qos_analysis`

**Query for Quick Review:**
```sql
SELECT
  analysis_period_label,
  consumer_subcategory,
  stress_state,
  total_jobs,
  qos_violation_pct,
  p95_execution_seconds
FROM `narvar-data-lake.query_opt.phase2_hub_qos_analysis`
WHERE stress_state = 'CRITICAL'
ORDER BY analysis_period_label, qos_violation_pct DESC;
```

---

## Conclusion

### ✅ KEY TAKEAWAYS:

1. **HUB is the weak link** in customer QoS during Peak_2024_2025
   - 39% violation rate vs 8.5% for MONITOR
   - 25-minute P95 execution vs 34s for MONITOR

2. **This is a Peak_2024_2025 specific issue**
   - Previous peak: 11.9% HUB violations
   - Current peak: 39.4% HUB violations
   - Something changed (new dashboards? more users? data growth?)

3. **Query optimization needed, not just capacity**
   - Similar slot consumption (52 vs 45 avg slots)
   - 44x execution time difference suggests inefficient queries
   - Capacity increase alone won't fix this

4. **Urgent action required before Nov 2025-Jan 2026 peak**
   - Identify and optimize slow Looker dashboards
   - Consider usage restrictions during peak hours
   - May need dedicated Looker capacity if optimization insufficient

---

**Completion Date**: November 6, 2025  
**Next Step**: Investigation 7 - Detailed HUB query analysis with monitor_audit tables  
**Status**: 🚨 HIGH PRIORITY - Needs immediate attention before next peak

