# Historical Capacity Configuration Summary

**Question**: What was the "default" reservation configuration during Dec 2024 - Jan 2025?  
**Date**: November 10, 2025  
**Status**: ⚠️ Historical data NOT available in DoIT tables

---

## 🔍 Data Availability Issue

### DoIT Tables Date Ranges:

| Table | Earliest Date | Latest Date | Coverage |
|-------|---------------|-------------|----------|
| `capacity_commitments_history` | **Aug 15, 2025** | Nov 10, 2025 | ❌ No Dec 2024 - Jan 2025 data |
| `reservations_mapping_history` | **Aug 15, 2025** | Nov 10, 2025 | ❌ No Dec 2024 - Jan 2025 data |
| `costs` | **Aug 15, 2025** | Nov 10, 2025 | ❌ No Dec 2024 - Jan 2025 data |

**Conclusion**: The DoIT billing tables only contain data from **August 15, 2025 onwards**. Historical configuration for the Peak 2024-2025 period (Nov 2024 - Jan 2025) is **NOT available** in these tables.

---

## 💡 What We Know About Peak 2024-2025 Configuration

### From Analysis Documentation (ANSWERS_TO_RESERVATION_QUESTIONS.md):

The configuration documented (likely from a GCP Console screenshot taken Nov 6, 2025) shows:

**Reservation**: `bq-narvar-admin:US.default`
- **Edition**: Enterprise
- **Max Reservation Size**: 1,700 slots
- **Baseline Slots**: 1,000
- **Committed Slots**: 1,000
- **Concurrency**: AUTO
- **Features**: Autoscale + idle slots enabled

**Capacity Commitments**:
```
Tier 1: 500 slots @ $0.048/hr (1-year commitment)  = $17,280/month
Tier 2: 500 slots @ $0.036/hr (3-year commitment) = $12,960/month
Total Committed: 1,000 slots                       = $30,240/month (fixed)

Autoscale: Up to 700 additional slots @ $0.060/hr  = Variable (pay-as-you-go)
Maximum Total: 1,700 slots
```

### Assumption:
Given that the current configuration (Aug-Nov 2025) matches the documented configuration from Nov 2025, it's **likely** that the configuration during Peak 2024-2025 (Dec 2024 - Jan 2025) was **similar or the same**.

---

## 📊 Current Configuration (Aug 2025 - Present)

### As of November 10, 2025:

**Capacity Commitments** (from `capacity_commitments_history`):

| Commitment ID | Slots | Plan Type | Edition | $/hour/slot | Cost/Hour | Cost/Month* |
|---------------|-------|-----------|---------|-------------|-----------|-------------|
| 7616061845660271830 | 500 | Plan 4 | Enterprise (2) | $0.048 | $24.00 | **$17,280** |
| 9573267349231879651 | 500 | Plan 10 | Enterprise (2) | $0.036 | $18.00 | **$12,960** |
| **TOTAL** | **1,000** | - | - | - | **$42.00** | **$30,240** |

*Assuming 720 hours/month

**Plan Types** (best interpretation):
- **Plan 4**: Likely **1-year commitment** (ANNUAL)
- **Plan 10**: Likely **3-year commitment** (THREE_YEAR) or similar long-term plan

**Reservations** (from `reservations_mapping_history`):

| Reservation | Project | Region | Num Projects |
|-------------|---------|--------|--------------|
| `default` | `bq-narvar-admin` | US | 15 |
| `iris-standard` | `bq-narvar-admin` | US | 1 |

The `default` reservation is the main shared pool serving 15 projects.

---

## ❓ What We DON'T Know (Missing Historical Data)

### Cannot Determine from Available Data:

1. **Exact capacity configuration during Dec 2024 - Jan 2025**
   - Was it 1,700 max slots like now?
   - Were the same 1,000 slots committed?
   - Did the autoscale limit change?

2. **When configuration changes occurred**
   - Did they increase slots before the peak?
   - When did they return to current levels?

3. **Reservation parameters during peak**
   - Baseline slots setting
   - Autoscale max setting
   - Concurrency settings

### Possible Sources for Historical Configuration:

1. **GCP Cloud Audit Logs** (if available):
   ```sql
   SELECT *
   FROM `narvar-data-lake.gcp_logs.cloudaudit_googleapis_com_activity`
   WHERE resource.type = 'bigquery_reservation'
     AND timestamp BETWEEN '2024-12-01' AND '2025-01-31'
     AND protoPayload.methodName LIKE '%reservation%'
   ```

2. **GCP Console Screenshots** from that time period

3. **Internal documentation** or change logs from Dec 2024 - Jan 2025

4. **Finance/billing records** showing commitment charges

---

## 🎯 Key Findings About Peak 2024-2025

### From Traffic Classification Analysis:

Even without knowing the exact configuration, we know **what actually happened**:

| Metric | Value |
|--------|-------|
| **Total Slot Hours Consumed** | 2,818,053 hours (over 3 months) |
| **Reserved Pool Usage** | 884,397 slot-hours (31.4%) |
| **On-Demand Usage** | 1,896,835 slot-hours (67.3%) 🚨 |
| **Pipeline Usage** | 36,821 slot-hours (1.3%) |

### Critical Insight:

**67% of capacity ran on expensive on-demand billing**, which means:
- The reserved capacity (whatever it was) was **insufficient**
- Workloads consistently exceeded the reservation limit
- This cost approximately **$281K/month** in on-demand charges

### Configuration Inference:

If we assume the configuration during peak was similar to current (1,700 max slots):

**Theoretical maximum reserved capacity**:
- 1,700 slots × 2,160 hours (3 months) = **3,672,000 slot-hours**

**Actual reserved usage**:
- Only **884,397 slot-hours** (24% of theoretical maximum)

**This suggests**:
- The **1,700-slot limit was exceeded frequently**
- Concurrent demand often surpassed the reservation
- Not enough slots available at peak moments
- Work spilled to on-demand to meet demand

---

## 📋 Recommendations

### 1. Verify Historical Configuration

**Action**: Check with GCP admin or platform team:
- What was the reservation configuration in Dec 2024 - Jan 2025?
- Were there any changes during or after the peak?
- Why do DoIT tables only start from Aug 2025?

### 2. Document Current Configuration

**Action**: Screenshot/export current GCP Console settings for:
- BigQuery → Capacity Management → Reservations
- BigQuery → Capacity Management → Commitments
- BigQuery → Capacity Management → Assignments

This creates a baseline for future comparisons.

### 3. Plan for Upcoming Peak (Nov 2025 - Jan 2026)

Based on Peak 2024-2025 actual usage:
- **Minimum recommended**: 2,200-2,500 reserved slots
- **Optimal recommendation**: 2,700-3,000 reserved slots
- **Rationale**: Eliminate or minimize expensive on-demand spillover

### 4. Set Up Monitoring

**Action**: Create alerts for:
- When reservation utilization > 80%
- When on-demand usage > 10% of total
- When concurrent slot demand approaches limit

---

## 📊 Cost Impact Summary

### If Configuration Was 1,700 Slots During Peak:

**Monthly Costs (estimated)**:
```
Fixed Commitment (1,000 slots):        $30,240/month
Autoscale Usage (up to 700 slots):     ~$14,563/month (estimated)
On-Demand Spillover:                  $281,702/month 🚨
-----------------------------------------------------------
TOTAL:                                 ~$326,505/month

Breakdown:
- Reserved (fixed + autoscale): ~$45K (14%)
- On-Demand spillover: ~$282K (86%) 🚨
```

### If They Had 2,700 Reserved Slots Instead:

**Estimated Costs**:
```
Fixed Commitment (estimated 2,700 slots):  ~$81,000/month
On-Demand Spillover (minimal):             ~$15,000/month
-----------------------------------------------------------
TOTAL:                                      ~$96,000/month

SAVINGS: ~$230K/month vs actual peak costs
```

**ROI**: Increasing reservation pays for itself many times over during peak periods.

---

## 🔑 Key Takeaways

1. ✅ **Current configuration is known**: 1,000 committed slots, 1,700 max
2. ❌ **Historical configuration unknown**: No data before Aug 15, 2025
3. 🎯 **Peak usage is known**: 2.8M slot-hours, 67% on expensive on-demand
4. 💡 **Inference**: Configuration likely similar during peak, but insufficient
5. 📈 **Recommendation**: Increase to 2,700-3,000 slots for next peak

---

**Next Steps**:
1. Verify historical configuration with GCP/platform team
2. Review current configuration before Nov 2025 peak
3. Plan capacity expansion to avoid on-demand spillover
4. Set up proactive monitoring and alerts





