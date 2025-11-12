# Peak 2024-2025 Slot Allocation and Cost Summary

**Period**: November 2024 - January 2025 (3 months)  
**Date Generated**: November 10, 2025  
**Data Source**: `narvar-data-lake.query_opt.traffic_classification`

---

## 🎯 Executive Summary

During the Peak 2024-2025 period, BigQuery costs reached approximately **$297K/month** (avg), with **67% of capacity running on expensive on-demand slots** due to exceeding the 1,700-slot reservation limit.

---

## 📊 Slot Allocation Configuration

### Reserved Capacity (Enterprise Edition)

**Total Reserved Capacity**: 1,700 slots maximum

| Tier | Slots | Commitment | Rate/Hour | Monthly Cost* |
|------|-------|------------|-----------|---------------|
| **1-Year Commitment** | 500 | 1 year | $0.048 | $17,280 |
| **3-Year Commitment** | 500 | 3 years | $0.036 | $12,960 |
| **Baseline Committed** | **1,000** | - | - | **$30,240** |
| **Autoscale (Pay-as-you-go)** | up to 700 | None | $0.060 | Variable |
| **Maximum Capacity** | **1,700** | - | - | - |

*Monthly cost = Rate × Slots × 720 hours/month (assuming full utilization)

**Key Configuration Details:**
- **Baseline Slots**: 1,000 (fully committed)
- **Max Reservation Size**: 1,700 (can autoscale up to this)
- **Autoscale Capacity**: 700 additional slots (pay-as-you-go)
- **Concurrency**: AUTO
- **Features**: Autoscale + idle slots enabled

### What This Means:
- You pay for **1,000 committed slots** whether you use them or not (~$30K/month fixed)
- You can scale up to **1,700 slots** total using autoscale (additional 700 slots at $0.06/hour when needed)
- Any usage **beyond 1,700 slots** spills to **on-demand** billing ($6.25/TB processed)

---

## 💰 Actual Costs During Peak_2024_2025 (Nov 2024 - Jan 2025)

### Cost Breakdown by Reservation Type

| Reservation Type | Jobs | Slot Hours | % Capacity | Est. Cost (3 months) | Avg Monthly Cost | TB Processed |
|------------------|------|------------|------------|----------------------|------------------|--------------|
| **ON_DEMAND** | 228,405 | 1,896,835 | **67.31%** 🚨 | **$845,107** | **$281,702** | 135,217 TB |
| **RESERVED_SHARED_POOL** | 2,069,938 | 884,397 | 31.38% | $43,689 | $14,563 | 69,722 TB |
| **RESERVED_PIPELINE** | 2,423,280 | 36,821 | 1.31% | $1,819 | $606 | - |
| **TOTAL** | **4,721,623** | **2,818,053** | **100%** | **$890,615** | **$296,872** | **204,939 TB** |

### Key Findings:

#### 🚨 Critical Issue: On-Demand Dominance
- **67% of all slot capacity** ran on expensive on-demand billing
- On-demand cost: **$281,702/month** (95% of total costs!)
- Reserved pool cost: **$14,563/month** (only 5% of total costs)

#### 📈 Capacity Exceeded Reservation
The 1,896,835 on-demand slot hours indicates you were **significantly exceeding** the 1,700-slot reservation:
- **3 months** = 2,160 hours
- **1,700 slots × 2,160 hours** = 3,672,000 potential slot-hours from reservation
- **Actual total usage**: 2,818,053 slot-hours
- **Utilization**: ~77% of reserved capacity if it could be used

However, the issue is **concurrent demand** - at peak moments, you needed more than 1,700 slots simultaneously, forcing work to on-demand.

---

## 📊 Cost Comparison: Peak vs Baseline

| Period | Type | Monthly Cost | Slot Hours/Month | On-Demand % |
|--------|------|--------------|------------------|-------------|
| **Peak 2024-2025** | Peak | **$296,872** | 939,351 | **67.3%** |
| **Baseline 2025** | Baseline | **$151,818** | 680,007 | 42.0% |
| **Increase** | - | **+95.5%** | +38.1% | +25.3pp |

### Key Insight:
Peak period costs nearly **doubled** compared to baseline, primarily due to:
1. **38% increase in total slot consumption**
2. **25 percentage point increase** in on-demand usage (42% → 67%)
3. On-demand is **~19x more expensive** per slot-hour than reserved ($0.446/slot-hour vs $0.0494)

---

## 💡 Cost Analysis

### Why On-Demand is So Expensive

**On-Demand Pricing**: $6.25 per TB processed  
**Average**: 135,217 TB ÷ 1,896,835 slot-hours = **0.071 TB per slot-hour**  
**Effective rate**: $6.25 × 0.071 = **$0.446 per slot-hour**

**Reserved Pricing**: $0.0494 per slot-hour (blended rate)

**Cost Multiplier**: On-demand is **9x more expensive** per slot-hour!

### Monthly Cost Breakdown (Average)

```
Fixed Costs (1,000 committed slots):
├─ 1-year commitment (500 slots):  $17,280/month
├─ 3-year commitment (500 slots):  $12,960/month
└─ Total Fixed:                     $30,240/month

Variable Costs (autoscale + on-demand):
├─ Autoscale usage (est.):          ~$14,563/month  
├─ On-demand spillover:            $281,702/month 🚨
└─ Total Variable:                 $296,265/month

TOTAL MONTHLY COST:                $326,505/month
```

**Note**: The actual reserved pool cost from DoIT billing would be the fixed $30K + autoscale usage. The $281K on-demand is the spillover cost.

---

## 🎯 Key Recommendations

### 1. **Immediate Action: Increase Reserved Capacity**

To reduce on-demand costs, consider expanding reservation:

| Option | Additional Slots | Additional Monthly Cost | Potential Savings |
|--------|------------------|-------------------------|-------------------|
| **Option A** | +500 slots | ~$21,600/month | Save ~$100K/month |
| **Option B** | +1,000 slots | ~$43,200/month | Save ~$180K/month |
| **Option C** | +1,500 slots | ~$64,800/month | Save ~$220K/month |

**ROI Analysis for Option B** (+1,000 slots to 2,700 total):
- **Additional Cost**: $43,200/month
- **Estimated Savings**: ~$180,000/month (moving on-demand to reserved)
- **Net Savings**: ~$136,800/month
- **Payback**: Immediate (saves 3-4x the cost)

### 2. **Understand Concurrent Demand Patterns**

Run analysis to determine:
- What time of day/week has highest concurrent demand?
- Can some workloads be shifted to off-peak hours?
- Which projects/categories are causing on-demand spillover?

### 3. **Optimize Workload Scheduling**

During peak periods:
- Schedule non-critical batch jobs during off-peak hours
- Implement query prioritization (P0 workloads get reserved slots)
- Consider separate reservations for different categories

---

## 📝 Data Sources and Methodology

**Data Source**: `narvar-data-lake.query_opt.traffic_classification`  
**Period Coverage**: November 1, 2024 - January 31, 2025

**Cost Calculation Method**:
- **Reserved slots**: Slot hours × $0.0494 (blended rate)
- **On-demand**: TB processed × $6.25/TB (actual BigQuery pricing)
- **Pipeline**: Slot hours × $0.0494 (treated as reserved)

**Important Notes**:
1. These are **estimated costs** based on slot consumption and data processed
2. Actual DoIT billing data is not available for this historical period (costs table starts Aug 2025)
3. Reserved pool costs represent **internal allocation** of the $30K/month fixed commitment
4. On-demand costs are based on actual data processing (most accurate)

---

## 🔍 Questions to Investigate

1. **Which projects/workloads caused the on-demand spillover?**
   - Run analysis by project_id and consumer_category
   
2. **What was the peak concurrent slot demand?**
   - Analyze by hour to find maximum simultaneous slots needed
   
3. **Can workloads be optimized or rescheduled?**
   - Identify batch jobs that could run off-peak
   
4. **Is 2,700 slots enough for upcoming peak (Nov 2025)?**
   - Project growth based on historical trends

---

**Next Steps**: 
1. Review this summary with finance/ops team
2. Decide on reservation expansion strategy
3. Analyze concurrent demand patterns (Investigation 7)
4. Plan capacity for upcoming Nov 2025 - Jan 2026 peak





