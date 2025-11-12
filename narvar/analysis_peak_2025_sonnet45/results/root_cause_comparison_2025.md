# Root Cause Comparison: 2025 vs Historical

**Analysis Date**: November 10, 2025

---

## Summary Counts

### 2025 Periods (Peak_2024_2025 + Baseline_2025_Sep_Oct)

**Peak_2024_2025** (Nov 2024 - Jan 2025): 60 incidents
- AUTOMATED: 35 (58.3%)
- INTERNAL: 18 (30.0%)
- EXTERNAL: 7 (11.7%)

**Baseline_2025_Sep_Oct** (Sep-Oct 2025): 69 incidents
- AUTOMATED: 54 (78.3%)
- INTERNAL: 12 (17.4%)
- EXTERNAL: 3 (4.3%)

**Combined 2025 Total**: 129 incidents
- AUTOMATED: 89 (69.0%)
- INTERNAL: 30 (23.3%)
- EXTERNAL: 10 (7.7%)

---

## Comparison with Overall Historical Average

| Category | Overall (All 3 Periods) | 2025 Only | Difference |
|----------|-------------------------|-----------|------------|
| **AUTOMATED** | 199/243 = 81.6% | 89/129 = 69.0% | **-12.6pp** ⬇️ |
| **INTERNAL** | 30/243 = 12.3% | 30/129 = 23.3% | **+11.0pp** ⬆️ |
| **EXTERNAL** | 14/243 = 6.1% | 10/129 = 7.7% | **+1.6pp** ⬆️ |

**pp = percentage points**

---

## 🚨 KEY FINDING: Significant Shift in 2025!

### INTERNAL incidents nearly DOUBLED as a percentage

**Historical (Peak_2023_2024)**:
- 114 total incidents
- Estimated INTERNAL: ~0 (based on comparison)
- INTERNAL was NOT a major factor in 2023-2024

**Recent (2025 periods)**:
- 129 total incidents  
- INTERNAL: 30 incidents (23.3%)
- **INTERNAL incidents increased significantly!**

---

## Detailed Breakdown by Period

### Peak_2024_2025 (Most Recent Peak)

**60 incidents total**:
- AUTOMATED: 35 (58.3%)
- INTERNAL: 18 (30.0%) 🚨
- EXTERNAL: 7 (11.7%)

**Notable INTERNAL Incident Clusters**:
1. **Dec 4, 11:40-11:50**: 2 consecutive INTERNAL incidents
2. **Dec 16, 08:30-08:50**: 3 consecutive INTERNAL incidents (30-64 high-impact queries!)
3. **Dec 19, 11:20-11:30**: 2 consecutive INTERNAL incidents
4. **Dec 23, 12:00-12:50**: 6 consecutive INTERNAL incidents (!)
5. **Jan 10, 10:00**: 1 INTERNAL incident (13 high-impact queries)
6. **Jan 10, 11:50**: 1 INTERNAL incident
7. **Jan 16, 10:40-10:50**: 2 INTERNAL incidents (37 and 64 high-impact queries! Massive!)

**Pattern**: INTERNAL incidents often appear in **clusters** during business hours (08:00-14:00, 10:00-12:00)

---

### Baseline_2025_Sep_Oct (Most Recent Baseline)

**69 incidents total**:
- AUTOMATED: 54 (78.3%)
- INTERNAL: 12 (17.4%)
- EXTERNAL: 3 (4.3%)

**INTERNAL Incident Pattern**:
- More spread out, less clustered than Peak
- Still present during business hours
- Lower percentage than Peak but still significant

---

## 🔍 What Changed Between 2023-2024 and 2024-2025?

### Hypothesis 1: Increased Metabase/Analytics Usage

**Evidence**:
- INTERNAL incidents increased from ~0% (2023-2024) to 30% (Peak_2024_2025)
- Clusters occur during business hours (8am-2pm)
- Some incidents show 30-64 high-impact INTERNAL queries simultaneously

**Possible Causes**:
- More Metabase users/dashboards added
- Heavier internal analytics workloads
- Dashboard auto-refresh during business hours
- Year-end/peak period reporting needs

### Hypothesis 2: Better AUTOMATED Process Management

**Evidence**:
- AUTOMATED dropped from ~82% (overall historical) to 58% (Peak_2024_2025)
- Could indicate pipeline optimization work has paid off
- Or could indicate INTERNAL grew faster than AUTOMATED optimization

### Hypothesis 3: EXTERNAL Remains Low and Stable

**Evidence**:
- EXTERNAL: 6.1% (historical) vs 7.7% (2025) - essentially stable
- Customers are NOT the problem
- External load spikes remain rare edge cases

---

## 📊 Pattern Analysis: When Do Incidents Occur?

### Peak_2024_2025 Time Patterns

**EXTERNAL incidents** (7 total):
- Dec 16: 08:00-08:20 (morning - 3 incidents, 39+8+5 high-impact queries)
- Dec 30: 17:00-17:50 (afternoon - 4 incidents)
- **Pattern**: Specific dates, specific times (likely holiday shopping events)

**INTERNAL incidents** (18 total):
- Dec 4: 11:40-11:50
- Dec 16: 08:30-08:50
- Dec 19: 11:20-11:30
- Dec 23: 12:00-12:50 (6 consecutive!)
- Jan 10: 10:00, 11:50
- Jan 16: 10:40-10:50 (MASSIVE: 37+64 high-impact queries!)
- **Pattern**: Business hours (08:00-14:00), end-of-month, end-of-year reporting

**AUTOMATED incidents** (35 total):
- Distributed across all times of day
- Clusters: Nov 29 early morning (06:00-06:50)
- Clusters: Dec 5 mid-morning (10:00-10:50)
- Clusters: Jan 10-16 late morning (10:00-11:50)
- **Pattern**: Batch job windows, scheduled ETL runs

---

## 🎯 Strategic Implications for Nov 2025-Jan 2026

### The INTERNAL Problem is Growing

**2023-2024 Peak**: INTERNAL was negligible  
**2024-2025 Peak**: INTERNAL caused 30% of incidents  
**Trend**: INTERNAL load is increasing

**This Actually SUPPORTS the Ad-Hoc Strategy**:

1. **INTERNAL is P1** (lower priority than external customers)
2. **Metabase Garbage Collector is the right tool** (kills INTERNAL queries during stress)
3. **INTERNAL incidents are during business hours** (predictable, monitorable)
4. **Pre-loading capacity would benefit INTERNAL users** (not customers!) - wasteful!

### Updated Root Cause Percentages for 2025

**For the executive report, use 2025-only data** (more relevant):

| Category | 2025 Incidents | Percentage | Interpretation |
|----------|----------------|------------|----------------|
| AUTOMATED | 89/129 | **69.0%** | Pipelines still dominant but declining |
| INTERNAL | 30/129 | **23.3%** | Growing concern - analytics/dashboards |
| EXTERNAL | 10/129 | **7.7%** | Stable - customers rarely cause issues |

---

## 💡 Revised Executive Summary Statement

**Previous (all historical data)**:
> "81.6% caused by automated processes, 12.3% by internal users, 6.1% by external load"

**Updated (2025 data only - more relevant)**:
> "In 2025, **69% of critical incidents stem from automated processes**, **23% from internal users** (growing trend), and only **8% from external customer load**"

**Key Message**: 
- Automated processes still dominant (69%) but improving
- Internal usage growing (12% → 23%) - Metabase garbage collector increasingly important
- External customers remain minor factor (8%) - low risk

---

## 📋 Recommendations Based on 2025 Trends

### Priority 1: Address Growing INTERNAL Load

**Actions**:
1. **Audit Metabase dashboards** added in 2024-2025 (likely cause of spike)
2. **Implement query cost estimation** in Metabase before execution
3. **Restrict dashboard auto-refresh** during peak hours (08:00-14:00)
4. **Tighten Metabase garbage collector** thresholds during peak
5. **User education** on query efficiency

### Priority 2: Continue AUTOMATED Optimization

**Actions**:
- AUTOMATED dropped from 82% to 69% (good progress!)
- Continue pipeline query optimization
- Focus on worst offenders (high blame scores)
- Schedule distribution to avoid concurrent runs

### Priority 3: Monitor EXTERNAL (But Don't Overreact)

**Actions**:
- EXTERNAL stable at 8% (was 6%)
- Continue monitoring but don't pre-load capacity for this
- Temporary capacity burst is sufficient for rare EXTERNAL spikes

---

## Conclusion

The 2025 data shows a **significant shift toward INTERNAL incidents** (12% → 23%), while AUTOMATED remains dominant but declining (82% → 69%). This **strengthens the ad-hoc strategy** because:

1. **INTERNAL is P1** - appropriate to kill during incidents
2. **Metabase garbage collector addresses 23% of incidents** - validates the tool
3. **69% + 23% = 92% are internal to Narvar** - optimizable without capacity expansion
4. **Only 8% are external customers** - low risk justifies not pre-loading

The findings support reactive management over expensive capacity pre-commitment.





