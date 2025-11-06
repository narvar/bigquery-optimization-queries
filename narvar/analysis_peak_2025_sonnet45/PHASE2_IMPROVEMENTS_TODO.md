# Phase 2 Improvements & Deep Dive Analysis

**Date**: November 6, 2025  
**Status**: Ready for next session  
**Context**: Phase 2 analysis complete with critical findings. Team feedback requires classification changes and deeper investigation.

---

## 🎯 Session Objectives

### Priority Changes (Quick Fixes)

1. **Reclassify monitor-base**: Change from EXTERNAL to AUTOMATED category
   - Team decision: monitor-base is infrastructure/automation, not customer-facing
   - Impact: Affects category distributions, capacity planning
   - Files to update: Phase 1 classification queries

2. **Update QoS threshold**: Change from 60s to 30s for EXTERNAL customer queries
   - Aligns with updated business requirements
   - Impact: QoS violation rates will change
   - Files to update: Query 2 (external_qos_under_stress)

---

## 🔍 Deep Dive Investigations

### Investigation 1: WARNING Stress Analysis

**Question**: Why is WARNING stress 0.0% of time? Expected higher percentage.

**Context**:
- Current thresholds: INFO (≥20 jobs OR P95 ≥6min), WARNING (≥30 jobs OR P95 ≥20min), CRITICAL (≥60 jobs OR P95 ≥50min)
- Results show: NORMAL 93%, INFO 0.05%, WARNING 0%, CRITICAL 4.9%
- Possible causes:
  - Jobs jump directly from INFO to CRITICAL without hitting WARNING range
  - P95-based detection vs concurrent job count mismatch
  - Hourly aggregates vs 10-minute windows inconsistency

**Analysis Required**:
- Review `phase2_stress_periods` table for WARNING window count
- Check distribution of concurrent jobs: how many in 20-30, 30-60, ≥60 ranges?
- Examine P95 distribution: how many in 6-20min, 20-50min, ≥50min ranges?
- Verify trigger_reason breakdown (HIGH_CONCURRENCY vs SLOW_EXECUTION)

**Expected Deliverable**: Understanding of why WARNING is rare and if thresholds need adjustment

---

### Investigation 2: Monitor Project Segmentation

**Question**: Distinguish shared slot (enterprise) vs on-demand monitor projects

**Context**:
- Current: All monitor projects treated as one category
- Team insight: Some retailers share enterprise slot pool, others use on-demand
- Business value: Understand if on-demand projects have different QoS profile
- Phase 4 consideration: Separate slot allocation for on-demand projects

**Analysis Required**:
1. **Identify project types**:
   - Extract project_id patterns from `traffic_classification`
   - Classify as `MONITOR_SHARED` vs `MONITOR_ONDEMAND`
   - Criteria: TBD (may need team input on project naming patterns)

2. **Compare performance**:
   - Slot consumption by type
   - Execution time distributions
   - QoS violation rates
   - Peak vs non-peak behavior

3. **Stress correlation**:
   - Do on-demand projects contribute to CRITICAL stress?
   - Are they impacted differently during stress?

**Expected Deliverable**: 
- Segmented analysis of monitor projects
- Recommendation for Phase 4 scenario: separate on-demand allocation

**SQL Pattern** (example):
```sql
CASE 
  WHEN project_id LIKE 'monitor-%-on-demand%' THEN 'MONITOR_ONDEMAND'
  WHEN project_id LIKE 'monitor-%' THEN 'MONITOR_SHARED'
  ELSE 'OTHER'
END AS monitor_type
```

---

### Investigation 3: Monitor → Retailer Mapping Quality

**Question**: Review MD5-based mapping between monitor projects and retailer names

**Context**:
- Current method: `monitor-{MD5_7char}-us-{env}` matched to `t_return_details`
- Phase 1 report: ~34% match rate (excluding monitor-base)
- Concern: Too many unmapped projects may skew retailer-level analysis

**Analysis Required**:
1. **Mapping statistics**:
   ```sql
   SELECT 
     COUNT(*) as total_monitor_jobs,
     COUNTIF(retailer_moniker IS NOT NULL) as matched,
     COUNTIF(retailer_moniker IS NULL) as unmapped,
     ROUND(COUNTIF(retailer_moniker IS NOT NULL) / COUNT(*) * 100, 2) as match_rate_pct
   FROM traffic_classification
   WHERE consumer_subcategory = 'MONITOR'
   GROUP BY analysis_period_label
   ```

2. **Sample unmapped projects**:
   - List top 20 unmapped monitor projects by job volume
   - Check if patterns exist (env-specific, region-specific, etc.)

3. **Impact assessment**:
   - Does low match rate affect stress analysis?
   - Can we improve matching logic?

**Expected Deliverable**: 
- Match rate report by period
- Assessment of whether mapping quality affects findings
- Recommendations for improvement (if needed)

---

### Investigation 4: Top Monitor Retailers Deep Dive

**Question**: Identify most active retailers and their query patterns

**Analysis Required**:
1. **Top retailers by activity**:
   ```sql
   SELECT 
     retailer_moniker,
     COUNT(*) as total_jobs,
     SUM(slot_hours) as total_slot_hours,
     ROUND(AVG(execution_time_seconds), 2) as avg_exec_seconds,
     COUNTIF(is_qos_violation) as qos_violations,
     ROUND(AVG(approximate_slot_count), 2) as avg_concurrent_slots
   FROM traffic_classification
   WHERE consumer_subcategory = 'MONITOR'
     AND retailer_moniker IS NOT NULL
   GROUP BY retailer_moniker
   ORDER BY total_slot_hours DESC
   LIMIT 20
   ```

2. **Query pattern analysis** (for top 5-10 retailers):
   - Common query characteristics (execution time, bytes processed, slot usage)
   - Temporal patterns (hour of day, day of week)
   - Correlation with specific dashboards (if dashboard_id available)
   - QoS violation patterns

3. **Stress period behavior**:
   - Which retailers run during CRITICAL stress?
   - Do specific retailers trigger stress?

**Expected Deliverable**: 
- Top 20 retailer report
- Detailed profile for top 5-10 retailers
- Potential optimization targets

---

### Investigation 5: Stress Period Root Cause Analysis

**Question**: Detailed distribution and root causes of CRITICAL/WARNING periods

**Analysis Required**:
1. **Temporal distribution**:
   ```sql
   SELECT 
     EXTRACT(HOUR FROM window_start) as hour_of_day,
     EXTRACT(DAYOFWEEK FROM window_start) as day_of_week,
     FORMAT_TIMESTAMP('%A', window_start) as day_name,
     stress_state,
     COUNT(*) as occurrences,
     AVG(concurrent_jobs) as avg_concurrent,
     AVG(p95_execution_seconds) as avg_p95
   FROM phase2_stress_periods
   WHERE stress_state IN ('WARNING', 'CRITICAL')
     AND is_hourly_aggregate = FALSE
   GROUP BY hour_of_day, day_of_week, day_name, stress_state
   ORDER BY occurrences DESC
   ```

2. **Trigger analysis**:
   - Breakdown by trigger_reason (HIGH_CONCURRENCY vs SLOW_EXECUTION vs BOTH_TRIGGERS)
   - Category attribution during stress (EXTERNAL vs AUTOMATED vs INTERNAL)

3. **Job-level investigation**:
   - Sample individual jobs during worst CRITICAL windows
   - Identify repeat offenders (specific projects/queries causing stress)

**Expected Deliverable**:
- Heatmap: stress by hour/day
- Trigger reason distribution
- List of problematic jobs/projects

---

### Investigation 6: HUB User QoS During Stress

**Question**: Analyze HUB (Looker dashboard) user experience during WARNING/CRITICAL periods

**Context**:
- Current analysis: Combined MONITOR + HUB as "customer-facing"
- HUB users are internal Looker dashboard users
- May have different QoS expectations than retailer MONITOR queries

**Analysis Required**:
```sql
SELECT 
  s.stress_state,
  COUNT(*) as hub_jobs,
  ROUND(AVG(t.execution_time_seconds), 2) as avg_exec,
  ROUND(APPROX_QUANTILES(t.execution_time_seconds, 100)[OFFSET(95)], 2) as p95_exec,
  COUNTIF(t.execution_time_seconds > 30) as qos_violations,
  ROUND(COUNTIF(t.execution_time_seconds > 30) / COUNT(*) * 100, 2) as violation_pct
FROM phase2_stress_periods s
INNER JOIN traffic_classification t
  ON s.analysis_period_label = t.analysis_period_label
  AND t.start_time >= s.window_start 
  AND t.start_time < s.window_end
WHERE s.is_hourly_aggregate = FALSE
  AND t.consumer_subcategory = 'HUB'
GROUP BY s.stress_state
ORDER BY CASE s.stress_state 
  WHEN 'CRITICAL' THEN 1 
  WHEN 'WARNING' THEN 2 
  WHEN 'INFO' THEN 3 
  ELSE 4 END
```

**Expected Deliverable**:
- HUB QoS report separated from MONITOR
- Comparison of HUB vs MONITOR QoS during stress
- Assessment of whether HUB users are impacted differently

---

## 📋 Recommended Execution Order

1. **Start with quick fixes** (30 min):
   - Reclassify monitor-base → AUTOMATED
   - Update QoS threshold → 30s
   - Re-run affected queries

2. **Investigation 3** (30 min): Monitor mapping quality check
   - Quick SQL query to assess match rates
   - Determine if this affects other investigations

3. **Investigation 1** (1 hour): WARNING stress analysis
   - Understand threshold behavior
   - May inform Investigation 5

4. **Investigation 5** (1-2 hours): Detailed stress root cause
   - Build on Investigation 1 findings
   - Create heatmaps and trigger analysis

5. **Investigation 2** (2-3 hours): Monitor project segmentation
   - Most complex, may require team input on project patterns
   - Critical for Phase 4 scenario planning

6. **Investigation 4** (1-2 hours): Top retailer deep dive
   - Depends on Investigation 3 (mapping quality)
   - Use findings for optimization recommendations

7. **Investigation 6** (30 min): HUB user QoS
   - Quick separate analysis
   - Complements customer QoS findings

**Total estimated time**: 8-10 hours

---

## 📂 Files to Modify

### Phase 1 (Reclassification):
- `queries/phase1_classification/vw_traffic_classification_to_table.sql`
- Re-run classification for 3 periods (Peak_2024_2025, Baseline_2025_Sep_Oct, Peak_2023_2024)

### Phase 2 (QoS threshold):
- `queries/phase2_historical/external_qos_under_stress_FIXED.sql`
- Change `DECLARE external_qos_threshold_seconds INT64 DEFAULT 60;` to `30`

### New Analyses:
- Create `queries/phase2_historical/monitor_segmentation_analysis.sql`
- Create `queries/phase2_historical/stress_root_cause_analysis.sql`  
- Create `queries/phase2_historical/hub_qos_analysis.sql`

### Notebook Updates:
- Add new sections to `phase2_analysis.ipynb` for deep dive findings

---

## 🎯 Success Criteria

By end of next session:
- ✅ monitor-base reclassified as AUTOMATED
- ✅ QoS threshold updated to 30s
- ✅ Understanding of why WARNING = 0%
- ✅ Monitor project segmentation complete
- ✅ Mapping quality assessed
- ✅ Top 5-10 retailer profiles created
- ✅ Stress root cause heatmaps generated
- ✅ HUB user QoS analyzed separately

---

## 💡 Prompt for Next Session

**Copy/paste this into your next chat:**

```
I'm continuing Phase 2 BigQuery capacity analysis. Previous session completed:
✅ Stress detection (4.9% CRITICAL, 0% WARNING)  
✅ Customer QoS analysis (6.34% violations during CRITICAL)
✅ Monitor-base causation test (H1 NOT SUPPORTED - no causation)

CONTEXT FILES:
- @PHASE2_IMPROVEMENTS_TODO.md - This session's action items
- @PHASE2_READY.md - Phase 2 summary with actual findings
- @phase2_analysis.ipynb - Current analysis notebook
- @PHASE2_SCOPE.md - Original methodology

REQUIRED CHANGES:

1. RECLASSIFICATION (CRITICAL):
   - Change monitor-base from EXTERNAL to AUTOMATED category
   - Team decision: it's infrastructure, not customer-facing
   - Re-run Phase 1 classification for 3 periods
   - Update all Phase 2 analyses accordingly

2. QoS THRESHOLD UPDATE:
   - Change EXTERNAL QoS threshold: 60s → 30s
   - Update Query 2 (external_qos_under_stress_FIXED.sql)
   - Re-analyze violation rates with new threshold

INVESTIGATIONS NEEDED:

3. WARNING Stress Analysis:
   - Why is WARNING 0.0% of time?
   - Expected higher percentage between INFO and CRITICAL
   - Review concurrent job distributions
   - Check if jobs jump directly from INFO to CRITICAL

4. Monitor Project Segmentation:
   - Distinguish shared enterprise slots vs on-demand projects
   - Pattern: Identify naming convention differences
   - Compare QoS, slot usage, stress impact
   - Phase 4 scenario: Separate on-demand allocation

5. Mapping Quality Review:
   - Check monitor project_id → retailer_moniker match rate
   - Current: ~34% match rate (seems low)
   - Sample unmapped projects
   - Assess impact on analysis accuracy

6. Top Retailer Deep Dive:
   - Identify top 20 retailers by slot consumption
   - Profile top 5-10: query patterns, QoS, stress behavior
   - Relate to specific dashboards (if possible)
   - Find optimization targets

7. Stress Root Cause Details:
   - Time-of-day/day-of-week heatmaps for CRITICAL/WARNING
   - Trigger reason breakdown (concurrency vs slow execution)
   - Sample worst CRITICAL windows
   - Identify repeat offender jobs/projects

8. HUB User QoS Separate Analysis:
   - Currently combined with MONITOR in "customer-facing"
   - HUB = internal Looker users, different from retailers
   - Analyze HUB QoS during stress periods separately
   - Compare HUB vs MONITOR impact

TECHNICAL DETAILS:

Current data:
- 43.8M jobs classified across 9 periods
- 6,123 stress windows analyzed (3 periods)
- 2,223 customer jobs during CRITICAL stress
- Tables: phase2_stress_periods, phase2_external_qos, phase2_monitor_base

Tools available:
- BigQuery tables in `narvar-data-lake.query_opt`
- Jupyter notebook: notebooks/phase2_analysis.ipynb
- Python with pandas, matplotlib, plotly, seaborn

EXECUTION ORDER:
1. Priority changes (reclassify + QoS threshold) - 30 min
2. Mapping quality check - 30 min
3. WARNING stress analysis - 1 hour
4. Stress root cause details - 1-2 hours
5. Monitor segmentation - 2-3 hours  
6. Top retailer deep dive - 1-2 hours
7. HUB user QoS - 30 min

Total: ~8-10 hours

Please start with Priority Changes #1 and #2, then proceed with investigations in recommended order.
```

---

## 📝 Quick Reference

### Current Key Metrics (Before Changes):
- Stress: 4.9% CRITICAL, 0% WARNING
- Customer violations: 6.34% during CRITICAL
- Monitor-base causation: 0.82x (NOT SUPPORTED)
- Sample size: 2,223 customer jobs during CRITICAL

### After Changes Will Show:
- Different EXTERNAL category distribution (monitor-base → AUTOMATED)
- Higher QoS violation rates (30s threshold vs previous 60s)
- Potentially different stress patterns if monitor-base excluded from EXTERNAL

### SQL Tables Reference:
- `traffic_classification` - Phase 1 classifications (43.8M rows)
- `phase2_stress_periods` - Stress timeline (6,123 windows)
- `phase2_external_qos` - Customer QoS by stress state
- `phase2_monitor_base` - Monitor-base performance + causation

---

**Good luck with the next session! All context documented above.** 🚀

