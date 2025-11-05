# Phase 2: Historical Analysis - Scope Definition

**Date**: November 5, 2025  
**Status**: Scope Approved, Ready to Execute  
**Duration**: 1-2 days

---

## 🎯 Primary Goal

**Understand EXTERNAL customer-facing performance degradation during capacity stress conditions to inform Nov 2025-Jan 2026 peak slot allocation decisions.**

---

## 📊 Two-Track Analysis Approach

### **Track 1: Overall Trends** (Baseline Understanding)
**Granularity**: Hourly  
**Purpose**: General capacity planning and growth trends  
**Periods**: All 9 periods (Sep 2022 - Oct 2025)

### **Track 2: Stress Condition Analysis** (QoS Impact)
**Granularity**: 10-minute windows  
**Purpose**: Understand customer QoS during capacity exhaustion  
**Periods**: Peak periods + high-stress non-peak periods  
**Focus**: EXTERNAL customer-facing (MONITOR, HUB) - **exclude monitor-base**

---

## 🎓 QoS Definitions (Approved)

### **EXTERNAL - Customer-Facing**:
```
MONITOR (retailer queries):     SLA < 60 seconds
HUB (Looker dashboards):        SLA < 60 seconds
```

### **EXTERNAL - Infrastructure**:
```
MONITOR_BASE (data processing): SLA < 30 minutes
- Continuous batch processing (new batch starts when prior completes)
- Cannot be deprioritized (provides "as fresh as possible" data)
- Different QoS threshold due to batch nature
```

### **INTERNAL**:
```
METABASE:     SLA < 8-10 minutes (480-600 seconds)
ADHOC_USER:   SLA < 8-10 minutes (480-600 seconds)
```

### **AUTOMATED** (Hybrid Approach):
```
Track 3 metrics:

1. Execution Time Anomaly (Category-Specific):
   - Baseline P95 from NORMAL conditions only
   - Flag: execution_time > 2× baseline_p95
   - Interpretation: "Query is slower than normal"

2. Stress Condition Correlation:
   - Flag jobs running during WARNING/CRITICAL windows
   - Interpretation: "Slowness likely due to capacity stress"

3. Estimated SLA Risk (Proxy):
   - If execution_time > 50 minutes during stress
   - Interpretation: "May miss typical hourly schedules"

Categories:
- AIRFLOW_COMPOSER: (different baseline than...)
- GKE_WORKLOAD, COMPUTE_ENGINE, MESSAGING, etc.
```

---

## 🚨 Capacity Stress State Definitions

**Based on production monitoring** (10-minute heartbeat):

| State | Concurrent Jobs | P95 Pending Wait | P95 Running Time |
|-------|----------------|------------------|------------------|
| **NORMAL** | <20 | <6 min | <6 min |
| **INFO** | 20-29 | 6-19 min | 6-19 min |
| **WARNING** | 30-59 | 20-49 min | 20-49 min |
| **CRITICAL** | ≥60 | ≥50 min | ≥50 min |

**Detection Method** (Hybrid):
1. **Hourly screening**: Identify hours with high P95 execution times
2. **10-minute precision**: Calculate actual concurrent jobs for stress hours
3. **Apply thresholds**: Classify each 10-minute window

---

## 📋 Phase 2 Deliverables

### **Query 1: Stress Period Identification** 🚨
**File**: `queries/phase2_historical/identify_capacity_stress_periods.sql` (NEW)

**Method**:
- Step 1: Hourly aggregation (P95 execution time, job volume)
- Step 2: Flag stress hours (P95 > 20 min = potential stress)
- Step 3: 10-minute concurrent job analysis for flagged hours
- Step 4: Apply INFO/WARNING/CRITICAL thresholds

**Output**:
```
10-minute window timeline with:
- window_start, window_end
- concurrent_jobs (actual count with overlapping start/end times)
- p95_execution_time
- p95_pending_wait (estimated from queue time)
- stress_state (NORMAL, INFO, WARNING, CRITICAL)
- dominant_category (which category has most concurrent jobs)
```

**Metrics**:
- % of time in each state by period
- Frequency of stress events
- Average duration of stress events
- Time-of-day/day-of-week patterns

---

### **Query 2: EXTERNAL Customer QoS Under Stress** ⚡
**File**: `queries/phase2_historical/external_qos_under_stress.sql` (NEW)

**Scope**: 
- **INCLUDE**: MONITOR (individual retailer projects), HUB (Looker)
- **EXCLUDE**: MONITOR_BASE (analyzed separately)

**Analysis**:
```sql
Compare EXTERNAL customer-facing performance:

NORMAL conditions (baseline):
- QoS violation rate (<60s threshold)
- P95, P99 execution times
- Average queue wait time

WARNING conditions:
- QoS violation rate (expected increase)
- P95, P99 execution times
- Queue wait time increase

CRITICAL conditions:
- QoS violation rate (severe degradation)
- P95, P99 execution times  
- Queue wait time (slot starvation)
```

**Output**:
```
Stress State | Jobs | Violation Rate | P95 Exec | P99 Exec | Avg Queue Wait
-------------|------|----------------|----------|----------|---------------
NORMAL       | 80%  | 2.5%          | 8s       | 25s      | 0.5s
INFO         | 12%  | 4.2%          | 12s      | 35s      | 2.1s
WARNING      | 6%   | 8.7%          | 18s      | 58s      | 8.3s
CRITICAL     | 2%   | 22.4%         | 45s      | 125s     | 35.2s
```

**Key Metric**: "During CRITICAL stress, EXTERNAL violation rate increases from 2.5% → 22.4%"

---

### **Query 3: Overall Peak vs. Non-Peak Patterns** 📈
**File**: `queries/phase2_historical/peak_vs_nonpeak_analysis.sql` (UPDATE existing)

**Granularity**: Hourly

**Analysis**:
```
For each period and category:
- Total jobs, slot consumption
- Peak multipliers (peak vs. baseline)
- Hourly patterns (traffic distribution by hour of day)
- Day-of-week patterns
- Category mix changes (peak vs. non-peak)
```

**Output**:
```
Category    | Avg Jobs/Hr (Non-Peak) | Avg Jobs/Hr (Peak) | Multiplier
------------|------------------------|-------------------|------------
EXTERNAL    | 2,184                 | 4,312             | 1.97x
AUTOMATED   | 3,704                 | 6,048             | 1.63x
INTERNAL    | 720                   | 950               | 1.32x
```

Plus hourly heatmaps showing traffic patterns.

---

### **Query 4: monitor-base Analysis** 🏗️
**File**: `queries/phase2_historical/monitor_base_stress_analysis.sql` (NEW)

**Two-part analysis**:

**Part A: monitor-base Separate QoS Tracking**
```
QoS Threshold: < 30 minutes (vs 60s for customer-facing)

Metrics:
- Violation rate (<30 min threshold)
- P95, P99 execution times
- Job completion patterns
- Performance during stress vs. normal
```

**Part B: Causation Analysis - Does monitor-base CAUSE stress?**
```
Questions:
1. Time overlap:
   - When does monitor-base run? (hour of day distribution)
   - When do customer queries peak? (hour of day)
   - Overlap percentage?

2. Concurrent load correlation:
   - During CRITICAL windows: monitor-base concurrent jobs vs total
   - Does monitor-base contribute to the 60+ concurrent job threshold?

3. QoS impact:
   - EXTERNAL customer violations: with vs without monitor-base concurrency
   - Is there slot starvation correlation?

4. Capacity consumption:
   - monitor-base slot demand during stress windows
   - % of total concurrent slots consumed by monitor-base
```

**Output**:
```
Hypothesis Testing Results:

H1: "monitor-base causes customer QoS degradation during stress"
- Evidence: 73% of CRITICAL windows have high monitor-base concurrency
- Evidence: Customer violations are 3.2x higher when monitor-base runs
- Conclusion: [SUPPORTED / NOT SUPPORTED]

H2: "monitor-base runs continuously (always consuming capacity)"
- Evidence: monitor-base present in 98% of 10-minute windows
- Average concurrent monitor-base jobs: 15-25
- Conclusion: Continuous batch processing confirmed

Recommendation:
- [If H1 supported]: Separate reservation for monitor-base
- [If H1 not supported]: Current setup acceptable, stress from other sources
```

---

## 📊 Phase 2 Success Criteria

| Deliverable | Output | Status |
|------------|--------|--------|
| Stress periods identified | Timeline with NORMAL/INFO/WARNING/CRITICAL | ⏳ |
| EXTERNAL customer QoS quantified | Violation rates by stress state | ⏳ |
| monitor-base causation determined | Supported or not supported with evidence | ⏳ |
| Peak multipliers calculated | By category with confidence | ⏳ |
| Stress frequency measured | % time in stress, events/day | ⏳ |
| Growth trends established | 2023-2025 reliable growth rates | ⏳ |
| Phase 3 inputs prepared | Baseline capacity, burst capacity, growth rates | ⏳ |

---

## 🎯 Key Questions Phase 2 Will Answer

### **For Immediate Capacity Planning (Nov 2025-Jan 2026)**:

1. **How often does capacity stress occur?**
   - "Peak periods spend X% of time in WARNING/CRITICAL states"
   - "Stress events occur Y times per day during peak"

2. **What happens to customer QoS during stress?**
   - "EXTERNAL violations increase from 2% → X% during CRITICAL"
   - "Customer queries wait average of Y seconds in queue during stress"

3. **What causes the stress?**
   - "monitor-base contributes Z% to concurrent job load"
   - "CRITICAL conditions are driven by [category]"

4. **How much additional capacity do we need?**
   - "Need +X slots to prevent WARNING conditions"
   - "Need +Y slots to prevent CRITICAL conditions"
   - "Z% of stress could be eliminated by optimizing monitor-base"

### **For Long-Term Planning**:

5. **Is stress getting worse?**
   - "WARNING/CRITICAL frequency growing at X% per year"
   - "Expected 2025-2026: Y% of time in stress"

6. **Which categories drive growth?**
   - "AUTOMATED slot growth: +125% (2023→2024)"
   - "EXTERNAL slot growth: +46% (2023→2024)"

---

## 💡 Phase 2 → Phase 3 Handoff

**Phase 2 will provide**:

**For Baseline Capacity**:
- Slot demand during NORMAL conditions (90% of time)
- Category distribution
- Hourly patterns

**For Burst Capacity**:
- Additional slots needed for WARNING conditions (target: 95% of time)
- Additional slots needed for CRITICAL prevention (target: 99% of time)
- Frequency and duration of burst needs

**For QoS Assurance**:
- EXTERNAL violation baseline (NORMAL conditions)
- Acceptable degradation during brief stress
- Maximum tolerable stress duration

**For Growth Projection**:
- Reliable growth rates (2023-2025)
- Category-specific trends
- 2025-2026 projected demand

**Phase 3 will then**:
- Apply growth rates to 2025 baseline
- Project 2025-2026 peak demand
- Simulate different stress scenarios
- Recommend slot allocation (baseline + burst)

---

## 🚀 Phase 2 Execution Plan

### **Step 1: Create 4 New/Updated Queries** (3-4 hours)
1. `identify_capacity_stress_periods.sql` (NEW)
2. `external_qos_under_stress.sql` (NEW)
3. `monitor_base_stress_analysis.sql` (NEW)
4. `peak_vs_nonpeak_analysis.sql` (UPDATE)

### **Step 2: Run Queries** (1-2 hours)
- Test on 1-2 periods first
- Validate results
- Run full analysis

### **Step 3: Analyze & Document** (2-3 hours)
- Interpret findings
- Answer key questions
- Create PHASE2_REPORT.md
- Prepare Phase 3 inputs

**Total**: 1-2 days

---

## ✅ Approved Approach Summary

| Decision Point | Approach | Rationale |
|---------------|----------|-----------|
| AUTOMATED QoS | Option C+ (Hybrid) | Category baselines + stress correlation + SLA risk |
| Stress Detection | Hybrid (Hourly → 10-min) | Computational efficiency + precision |
| Granularity | Hybrid | Overall=hourly, Stress=10-min |
| monitor-base SLA | 30 minutes | Different from customer-facing (60s) |
| monitor-base Priority | Cannot deprioritize | Continuous batch, provides fresh data |
| monitor-base Analysis | Both (separate + causation) | Track infrastructure QoS + test if it causes customer stress |

---

**Ready to build the queries!** 🚀



