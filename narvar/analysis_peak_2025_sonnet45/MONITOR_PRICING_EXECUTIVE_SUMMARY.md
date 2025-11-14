# Monitor Platform Pricing Strategy - Executive Summary

**For:** Product Management  
**Date:** November 14, 2025  
**Status:** Phase 1 Complete (fashionnova PoC) | Phase 2 Planned (Complete Cost Audit)

---

## 🎯 Bottom Line

**Monitor platform costs ~$207K/year** (conservative estimate, validation in progress) to serve 284 retailers who currently receive it free/bundled.

**Key Finding:** Production costs (ETL, storage, infrastructure) are **97% of total costs**. Traditional query-cost analysis misses almost everything.

**Decision Needed:** How should we price Monitor for cost recovery and/or profitability?

---

## 💰 Cost Breakdown

### Platform Economics (Conservative Estimate)

| Component | Annual Cost | % |
|-----------|-------------|---|
| **Production** (ETL + Storage + Pub/Sub) | $200,957 | 97% |
| **Consumption** (Query Execution) | $6,418 | 3% |
| **TOTAL** | **~$207,375** | **100%** |

**Note:** Additional production costs being validated (reporting.t_return_details table, etc.). Total may be $250K-$350K.

### Per-Retailer Costs (Highly Variable)

- **Average:** $730/year
- **Median:** ~$200/year (due to concentration)
- **Range:** <$100 to $70K+ per year

### fashionnova Case Study

**Total Annual Cost:** $69,941 (34% of platform!)

- Consumption: $1,616 (2.3%)
- Production: $68,325 (97.7%)  
- **79x more expensive than average retailer**

**Why?** Consumes 54.5% of platform slot-hours with only 2.9% of queries (inefficient query patterns)

---

## 💡 Pricing Strategy Options

### Option 1: Tiered Pricing (RECOMMENDED for MVP)

**Simple, predictable pricing tiers:**

| Tier | Monthly Price | Annual | Target Retailers | Example |
|------|--------------|--------|------------------|---------|
| Light | $50 | $600 | ~180 (63%) | Small retailers |
| Standard | $350 | $4,200 | ~80 (28%) | Mid-market |
| Premium | $2,500 | $30,000 | ~20 (7%) | High-volume |
| Enterprise | $7,000+ | $84,000+ | ~4 (1%) | fashionnova, etc. |

**Revenue Projection:** $1.2M-$1.4M/year (6-7x cost recovery!)

**Pros:** Simple, predictable, high customer acceptance  
**Cons:** Less fair (within-tier variance), may overcharge small or undercharge large

---

### Option 2: Usage-Based Pricing

**Charge based on attributed cost + margin:**

fashionnova example: $77,368 cost × 1.20 margin = **$7,737/month**

**Pros:** Most fair, aligns with actual costs  
**Cons:** Unpredictable billing, complexity, potential sticker shock

---

### Option 3: Hybrid (Tier + Overage)

**Base tier price + overage for heavy usage:**

Example: $350/month base + $0.50 per extra query + $5 per extra slot-hour

**Pros:** Balance predictability and fairness  
**Cons:** More complex to administer

---

## 🎯 Cost Attribution Model

**How we calculate "fair share" of production costs:**

### Recommended: Cost-Component Aligned (50/30/20)

```
Retailer's Share = 
  50% × (slot_hours / total_slot_hours)     [Compute: 75% of costs]
  30% × (queries / total_queries)           [Pub/Sub: 13% of costs]
  20% × (TB_scanned / total_TB_scanned)     [Storage: 12% of costs]
```

**Rationale:** Weights mirror actual cost drivers

**Alternative:** Balanced Hybrid (40/30/30) - simpler to explain but less accurate

---

## 📊 Financial Scenarios

### Scenario A: Tiered Pricing (Conservative)

- **Revenue:** $1,380,000/year (assumes 100% retention)
- **Cost:** $207,375/year (conservative estimate)
- **Profit:** $1,172,625/year (566% margin!)

**Implication:** Even conservative pricing generates massive profit. Consider:
- Lower prices (more competitive)
- Invest in platform improvements
- Fund customer acquisition

### Scenario B: Usage-Based (20% Margin)

- **Revenue:** $248,850/year  
- **Cost:** $207,375/year
- **Profit:** $41,475/year (20% margin)

**Implication:** More conservative, sustainable, fair to customers

---

## ⚠️ Key Risks & Decisions Needed

### Risk 1: Customer Churn
High-cost retailers (fashionnova @ $84K/year) may churn when pricing announced

**Mitigation:** Grandfathering, gradual rollout, optimization partnerships

### Risk 2: Incomplete Cost Picture
Currently validated: $207K. In progress: Additional base tables may add $50K-$150K.

**Decision:** Proceed with $207K (conservative) or wait for complete audit?

### Risk 3: Competitive Pressure
Need to research what competitors charge for similar services

**Decision:** Price based on costs (current approach) or market (competitive research)?

---

## 📋 Decisions Needed from Product Team

**Critical (Need Answers):**

1. **What's Monitor's strategic role?**
   - [ ] Loss leader (drive other sales)
   - [ ] Standalone profit center
   - [ ] Platform/competitive asset
   - [ ] Other: ___________

2. **What margin target?**
   - [ ] 0% (break-even / cost recovery)
   - [ ] 20% (industry standard)
   - [ ] 50%+ (premium positioning)
   - [ ] Other: ___%

3. **Preferred pricing model?**
   - [ ] Tiered (simple, recommended)
   - [ ] Usage-based (fair, complex)
   - [ ] Hybrid
   - [ ] Other: ___________

4. **Who must we retain (can't afford to lose)?**
   - List strategic accounts: ___________
   - Acceptable churn rate: ___%

5. **Rollout timeline?**
   - [ ] Immediate (3-6 month notice)
   - [ ] Gradual (12-24 months)
   - [ ] Pilot first
   - [ ] Other: ___________

---

## 📚 Supporting Documentation

**Detailed Analysis (Read in Order):**

1. **[Pricing Strategy Options](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/docs/monitor_total_cost/PRICING_STRATEGY_OPTIONS.md)** - Comprehensive analysis of all pricing models with SWOT analysis

2. **[fashionnova Total Cost Analysis](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/docs/monitor_total_cost/FASHIONNOVA_TOTAL_COST_ANALYSIS.md)** - Detailed case study ($69,941/year)

3. **[Cost Attribution Methodology](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/docs/monitor_total_cost/FASHIONNOVA_COST_ATTRIBUTION.md)** - How we calculate fair share

4. **[Optimization Playbook](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/docs/monitor_total_cost/OPTIMIZATION_PLAYBOOK.md)** - Cost reduction strategies ($100K-$200K/year potential)

**Technical Details:**

5. **[Complete Plan](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/MONITOR_TOTAL_COST_ANALYSIS_PLAN.md)** - Full methodology and execution plan

6. **[Execution Summary](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/MONITOR_TOTAL_COST_EXECUTION_SUMMARY.md)** - What we've completed

7. **[Scaling Framework](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/docs/monitor_total_cost/SCALING_FRAMEWORK.md)** - How to extend to all 284 retailers

**Background:**

8. **[Monitor Consumption Analysis](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/MONITOR_2025_ANALYSIS_REPORT.md)** - Original report (consumption costs only)

9. **[Monitor Merge Cost Analysis](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/MONITOR_MERGE_COST_FINAL_RESULTS.md)** - monitor_base.shipments production cost ($200,957/year)

---

## 🚀 Next Steps

### This Week (In Progress)

**Phase 2: Complete Cost Audit**
- ✅ Recursive view resolution to all base tables
- ✅ Search audit logs for production costs of ALL base tables
- ✅ Document questions for Data Engineering team
- ✅ Update cost estimates with complete picture

**Timeline:** 1-2 days  
**Cost:** $1.50-$3.00 in BigQuery

### Next Week (Pending Decisions)

**Scale to All Retailers:**
- Extend analysis to all 284 retailers
- Generate pricing tier assignments
- Create revenue projections
- Build business case presentation

### Within 2-3 Weeks

**Product Team Workshop:**
- Review complete findings
- Decide on pricing model
- Approve margin targets
- Define rollout strategy

---

## 📞 Questions?

**For technical details:** Review supporting documentation (links above)  
**For strategic discussion:** Contact Data Engineering + Product teams  
**For immediate questions:** See [Product Team Review Document](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/MONITOR_TOTAL_COST_REVIEW_FOR_PRODUCT_TEAM.md)

---

**Prepared by:** Data Engineering + AI Analysis  
**Review Status:** Technical analysis complete, strategic decisions pending  
**Confidence Level:** 75% (pending complete cost audit)  
**Recommendation:** Complete cost audit, then finalize pricing strategy

---

*This is a conservative estimate using $207K platform cost. Complete cost audit in progress may reveal $250K-$350K total (higher costs → different pricing implications).*

