# Monitor Pricing Strategy - Next Session Handoff

**Date:** November 14, 2025  
**Project:** Monitor Total Cost Analysis for Pricing Strategy  
**Status:** Phase 1 & 2 Complete | Phase 3 Pending Validation  
**For:** Future AI agents and team collaboration

---

## 🎯 PROJECT OBJECTIVE

**Primary Goal:** Support Product team in developing Monitor pricing strategy

**Current State:** Monitor platform costs ~$598K/year, serves 284 retailers for free/bundled

**Decision Needed:** How to price Monitor for cost recovery and/or profitability?

---

## 📊 CURRENT FINDINGS (As of Nov 14, 2025)

### Platform Economics

**Total Annual Cost:** **$598,348/year** (2.9x initial conservative estimate of $207K)

| Component | Annual Cost | % | Status |
|-----------|-------------|---|--------|
| **Production - monitor_base.shipments** | $467,922 | 78.2% | ✅ Confirmed |
| **Production - return_item_details** | $123,717 | 20.7% | ✅ Confirmed |
| **Production - return_rate_agg** | $291 | 0.0% | ✅ Negligible |
| **Production - carrier_config** | $0 | 0.0% | ✅ Negligible |
| **Production - orders** | $0-$? | 0.0% | ❓ Not found in audit logs |
| **Production - tnt_benchmarks_latest** | $0-$100 | 0.0% | ❓ Not found in audit logs |
| **Production - ft_benchmarks_latest** | $0-$100 | 0.0% | ❓ Not found in audit logs |
| **Consumption (queries)** | $6,418 | 1.1% | ✅ Known |
| **TOTAL** | **~$598,348** | **100%** | **Pending validation** |

### fashionnova Case Study (Preliminary)

**Estimated Total Cost:** $160,000-$165,000/year
- Consumption: $1,616
- Production (shipments, 34% attribution): $159,094
- Production (returns, TBD% attribution): $5,000-$10,000 (estimate)

**vs Initial Estimate:** $69,941 (2.3-2.4x higher)

---

## ⚠️ CRITICAL DISCREPANCY TO RESOLVE

### Shipments Cost: $467,922 vs $200,957

**Two different analyses, two different results:**

**Analysis A (MONITOR_MERGE_COST_FINAL_RESULTS.md - Nov 6, 2025):**
- Period: Sep-Oct 2024 (2 months)
- Method: Percentage of total BQ reservation (24.18%) × annual reservation cost
- Result: **$200,957/year**
- Source: DoIT billing data + traffic classification

**Analysis B (This analysis - Nov 14, 2025):**
- Period: Peak_2024_2025 (Nov 2024-Jan 2025) + Baseline_2025_Sep_Oct (Sep-Oct 2025)
- Method: Direct audit log search, sum slot-hours, annualize
- Result: **$467,922/year**
- Source: BigQuery audit logs

**Difference:** 2.3x

**Possible Reasons:**
1. Growth: 2025 workload higher than 2024
2. Peak period effect: Nov-Jan higher than Sep-Oct
3. Methodology: Direct measurement vs extrapolation
4. Data source: Audit logs vs billing data

**URGENT:** Validate with Data Engineering which figure to use for pricing strategy

---

## 📁 FILE STRUCTURE & KEY DOCUMENTS

### Start Here

**📄 THIS FILE** - Complete context and handoff

### Production Cost Analysis (monitor_production_costs/ folder)

**Base Table Reports (7 files):**
1. `SHIPMENTS_PRODUCTION_COST.md` - Original $200,957 analysis (reference)
2. `SHIPMENTS_PRODUCTION_COST_UPDATED.md` - New $467,922 analysis ⚠️ Discrepancy
3. `RETURN_ITEM_DETAILS_PRODUCTION_COST.md` - $123,717 analysis
4. `RETURN_RATE_AGG_PRODUCTION_COST.md` - $291 (negligible)
5. `CARRIER_CONFIG_PRODUCTION_COST.md` - $0 (negligible)
6. `ORDERS_TABLE_PRODUCTION_COST.md` - Not found, needs validation
7. `TNT_BENCHMARKS_PRODUCTION_COST.md` - Not found, likely negligible
8. `FT_BENCHMARKS_PRODUCTION_COST.md` - Not found, likely negligible
9. **`COMPLETE_PRODUCTION_COST_SUMMARY.md`** - Aggregates all 7 tables ⭐

### Pricing Strategy Documents (docs/monitor_total_cost/ folder)

**For Product Team:**
- `PRICING_STRATEGY_OPTIONS.md` - All pricing models with SWOT analysis
- `FASHIONNOVA_TOTAL_COST_ANALYSIS.md` - Case study (needs update with new costs)
- `FASHIONNOVA_COST_ATTRIBUTION.md` - Attribution methodology
- `OPTIMIZATION_PLAYBOOK.md` - Cost reduction strategies

**Technical:**
- `COMPLETE_VIEW_TO_BASE_TABLE_MAPPING.md` - View → table dependencies
- `ERIC_VIEW_LIST_AND_NEXT_STEPS.md` - Eric's authoritative 9-view list
- `SCALING_FRAMEWORK.md` - How to extend to all 284 retailers

### Executive Summaries

- **`MONITOR_PRICING_EXECUTIVE_SUMMARY.md`** - For Product team (uses conservative $207K - needs update)
- **`SESSION_SUMMARY_2025_11_14.md`** - Today's work summary
- **`MONITOR_COST_UPDATE_CRITICAL_FINDINGS.md`** - Major cost discovery notes

### Data & Queries

**SQL Queries (queries/monitor_total_cost/):**
- `01_extract_referenced_tables.sql` - fashionnova table extraction
- `06_all_base_tables_production_analysis.sql` - Complete production cost search

**Results (results/monitor_total_cost/):**
- `all_base_tables_production_detailed.csv` - Full audit log results
- `production_cost_summary.csv` - Summary by table
- `fashionnova_referenced_tables.csv` - fashionnova's 5 views

**Scripts (scripts/):**
- `analyze_all_base_tables.py` - Executes production cost analysis
- `find_base_table_costs.py` - Helper script

---

## 🚀 PENDING WORK (Priority Order)

### Phase 3: Validation & Completion (URGENT)

**Priority 1: Resolve Shipments Cost Discrepancy**
- [ ] Validate with Data Engineering: Is $467,922 or $200,957 correct?
- [ ] Understand why 2.3x difference
- [ ] Decide which figure to use for pricing strategy
- **Impact:** Affects all pricing calculations

**Priority 2: Validate Unknown Tables (3 of 7)**
- [ ] Verify if monitor_base.orders exists (check INFORMATION_SCHEMA)
- [ ] Get view definitions for v_orders, v_order_items, v_benchmark_tnt, v_benchmark_ft
- [ ] Confirm if they reference separate tables or use shipments directly
- [ ] Calculate any additional production costs (likely <$200 total)
- **Impact:** Minor for costs, critical for completeness

**Priority 3: Calculate fashionnova Return Usage Attribution**
- [ ] Determine fashionnova's share of return_item_details usage
- [ ] Apply attribution model to $123,717
- [ ] Update fashionnova total cost estimate
- **Impact:** Adds $5K-$50K to fashionnova's cost

---

### Phase 4: Scale to All Retailers (After Validation)

**Extend analysis to all 284 retailers:**
- [ ] Modify SQL queries to process all retailers (remove fashionnova filter)
- [ ] Calculate each retailer's usage of shipment vs return views
- [ ] Apply attribution model to production costs
- [ ] Generate comprehensive cost rankings

**Timeline:** 1-2 days  
**Cost:** $1-5 BigQuery  
**Deliverable:** All-retailer total cost analysis

---

### Phase 5: Finalize Pricing Recommendations

**Update pricing models with final costs:**
- [ ] Revise tiered pricing (adjust for ~$598K platform cost)
- [ ] Update usage-based pricing calculations
- [ ] Recalculate revenue projections
- [ ] Update business case scenarios

**Deliverable:** Final pricing recommendations for Product team

---

## 📋 QUESTIONS FOR DATA ENGINEERING TEAM

### Critical (Blocking Progress)

**Q1: Shipments Cost**
- Is $467,922/year realistic for monitor_base.shipments in 2025?
- Or should we use $200,957 from 2024 baseline?
- What's the actual annual cost from billing data?

**Q2: Orders Table**
- Does `monitor-base-us-prod.monitor_base.orders` exist as a base table?
- Or is it a view on shipments?
- If it exists, how is it populated and what's the cost?

**Q3: View Definitions**
- Can you provide SQL definitions for: v_orders, v_order_items, v_benchmark_tnt, v_benchmark_ft?
- What base tables do they actually reference?

**Q4: Benchmark Tables**
- Do tnt_benchmarks_latest and ft_benchmarks_latest exist?
- If yes, how are they populated and what's the cost?
- If no, what do v_benchmark_tnt and v_benchmark_ft actually query?

### Secondary (For Optimization)

**Q5: DAG Identification**
- Which Airflow DAG runs the shipments MERGE operations (90/day)?
- Which DAG runs the return_item_details MERGE operations (58/day)?

**Q6: Optimization Opportunities**
- Can MERGE frequencies be reduced?
- Partition strategies in use?
- Known optimization initiatives?

---

## 💡 KEY INSIGHTS FOR PRICING STRATEGY

### Insight 1: Production Costs Dominate (98.9%)

**Traditional view:** Focus on query costs ($6,418)  
**Reality:** Production costs are $591,930 (98.9% of total)

**Implication:** Pricing must recover production costs, not just query execution

---

### Insight 2: Two-Table Model

**98.9% of production costs come from just 2 tables:**
- monitor_base.shipments: 79%
- return_insights_base.return_item_details: 21%

**Implication:** Can simplify attribution model to these 2 primary tables

---

### Insight 3: Shipment vs Return Users

**Retailers segment into:**
- Shipment-only users (use v_shipments, v_shipments_events only)
- Full-suite users (use shipments + returns + orders)

**Implication:** Two-tier attribution:
- Base cost: Shipment usage
- Add-on cost: Return usage

---

### Insight 4: Platform Cost Uncertainty

**Range:** $200,957 (old baseline) to $598,348 (new analysis) = 3x variance

**Implication:** Need to validate costs before presenting to Product team

---

## 🎯 RECOMMENDED NEXT ACTIONS

### Tomorrow Morning

1. **Email Eric/Data Engineering** with critical questions (Q1-Q4 above)
2. **Validate shipments cost** - Get definitive answer on $467K vs $201K
3. **Get missing view definitions** - Resolve orders, benchmark tables

### Tomorrow Afternoon (After Validation)

4. **Update all cost analyses** with validated figures
5. **Recalculate fashionnova** with complete costs
6. **Finalize platform total** (remove unknowns)

### Next 2-3 Days

7. **Scale to all 284 retailers** using finalized costs
8. **Generate pricing tier assignments** per retailer
9. **Create revenue projections** for different pricing models
10. **Present to Product team** with recommendations

---

## 📚 REFERENCE: View → Base Table Mapping (From Manual Input)

**Eric provided 9 views, you provided base table mappings:**

```
v_shipments → [monitor_base.shipments, monitor_base.carrier_config]
v_shipments_events → [monitor_base.shipments, monitor_base.carrier_config]
v_shipments_transposed → [monitor_base.shipments, monitor_base.carrier_config]
v_orders → [monitor_base.orders, monitor_base.carrier_config]
v_order_items → [monitor_base.orders, monitor_base.carrier_config]
v_return_details → [return_insights_base.return_item_details]
v_return_rate_agg → [reporting.return_rate_agg]
v_benchmark_tnt → [monitor_base.tnt_benchmarks_latest]
v_benchmark_ft → [monitor_base.ft_benchmarks_latest]
```

**Status:**
- ✅ shipments, carrier_config - Confirmed
- ✅ return_item_details, return_rate_agg - Confirmed
- ❓ orders, tnt_benchmarks_latest, ft_benchmarks_latest - Not found, need validation

---

## 💰 PROVISIONAL PRICING RECOMMENDATIONS (Pending Validation)

### Platform Cost Scenarios

**Scenario A: Use Old Baseline ($207K)**
- Most conservative
- Based on 2024 data
- May underestimate 2025 costs

**Scenario B: Use New Analysis ($598K)**
- Uses Peak + Baseline 2025 periods
- Direct audit log measurement
- Consistent with consumption analysis periods
- **RECOMMENDED for final pricing**

**Scenario C: Average of Both ($403K)**
- Hedge against uncertainty
- May be reasonable compromise

### Preliminary Tiered Pricing (Based on $598K)

| Tier | Monthly Price | Annual | Target Retailers |
|------|--------------|--------|------------------|
| Light | $140 | $1,680 | ~180 (63%) |
| Standard | $840 | $10,080 | ~80 (28%) |
| Premium | $6,000 | $72,000 | ~20 (7%) |
| Enterprise | $17,000 | $204,000 | ~4 (1%) |

**Revenue Projection:** $3.0M-$3.5M/year (5-6x cost recovery)

**Note:** Prices subject to change after cost validation and Product team input

---

## 🚨 BLOCKERS & RISKS

### Blocker 1: Cost Validation

**Issue:** $467,922 vs $200,957 discrepancy for shipments

**Risk:** Using wrong figure could over/under-price by 2.3x

**Resolution:** Get Data Engineering validation (URGENT)

### Blocker 2: Unknown Tables

**Issue:** 3 tables not found in audit logs (orders, 2 benchmark tables)

**Risk:** Could be missing significant costs

**Resolution:** Get view definitions, verify table existence

### Blocker 3: fashionnova Return Attribution

**Issue:** Don't know fashionnova's share of $123,717 return_item_details cost

**Risk:** fashionnova total cost could be $160K-$200K (uncertainty affects Enterprise tier pricing)

**Resolution:** Calculate return usage attribution

---

## 🔧 HOW TO CONTINUE THIS WORK

### For New AI Agent

**Step 1: Read context files (in order):**
1. This file (`MONITOR_PRICING_NEXT_SESSION.md`) - Complete context
2. `monitor_production_costs/COMPLETE_PRODUCTION_COST_SUMMARY.md` - Cost findings
3. `MONITOR_PRICING_EXECUTIVE_SUMMARY.md` - Current Product team summary
4. `docs/monitor_total_cost/PRICING_STRATEGY_OPTIONS.md` - Detailed pricing analysis

**Step 2: Understand current state:**
- Platform cost: ~$598K/year (pending validation)
- fashionnova: ~$160K-$165K/year (preliminary)
- 3 unknown tables need resolution
- Shipments cost discrepancy needs validation

**Step 3: Get Data Engineering input:**
- Use questions in "QUESTIONS FOR DATA ENGINEERING TEAM" section above
- Validate shipments cost ($467K vs $201K)
- Resolve unknown tables (orders, benchmarks)

**Step 4: Complete analysis:**
- Update all cost estimates with validated figures
- Recalculate fashionnova with complete costs
- Scale to all 284 retailers
- Finalize pricing recommendations

### For Human Collaborator

**Immediate actions:**
1. Contact Eric/Data Engineering with questions from this document
2. Review `monitor_production_costs/` folder - 9 detailed table analyses
3. Decide on shipments cost figure to use ($467K or $201K)
4. Provide missing view definitions (v_orders, v_order_items, v_benchmark_tnt, v_benchmark_ft)

---

## 📊 DATA SOURCES & METHODOLOGY

### Time Periods Used

**Peak_2024_2025:**
- Start: November 1, 2024
- End: January 31, 2025
- Duration: 3 months

**Baseline_2025_Sep_Oct:**
- Start: September 1, 2025
- End: October 31, 2025
- Duration: 2 months

**Total:** 5 months  
**Annualization:** × (12 ÷ 5) = × 2.4

### Audit Log Query

**Table:** `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`

**Search for:**
- Operations: INSERT, MERGE, CREATE_TABLE_AS_SELECT, UPDATE
- Destination tables: 7 Monitor base tables
- Time periods: Peak + Baseline (5 months)
- Exclusions: QA, test, tmp environments

**Cost Calculation:**
```
For each ETL job:
  If RESERVED: Cost = (total_slot_ms ÷ 3,600,000) × $0.0494
  If ON_DEMAND: Cost = (total_billed_bytes ÷ 1024^4) × $6.25

Annualize: 5-month cost × 2.4
```

---

## 💡 ATTRIBUTION MODEL

### Cost-Component Aligned (50/30/20) - RECOMMENDED

```
Retailer's Share = 
  50% × (retailer_slot_hours / total_slot_hours) +     [Compute: 79% of costs]
  30% × (retailer_queries / total_queries) +           [Messaging: ~13%]
  20% × (retailer_TB_scanned / total_TB_scanned)       [Storage: ~12%]
```

**For fashionnova (preliminary):**
- Slot-hours: 54.5% of platform
- Queries: 2.9% of platform
- TB scanned: ~55% estimated
- **Weighted attribution: ~38-40%**
- **Applied to $591,930 production: ~$224,000**
- **Plus consumption: $1,616**
- **Total: ~$226,000/year**

**Note:** Need to validate and refine with complete data

---

## 🎯 SUCCESS CRITERIA

**To complete this analysis:**

1. ✅ All 7 base table production costs known (currently 4 of 7)
2. ✅ Shipments cost validated ($467K or $201K decision made)
3. ✅ fashionnova total cost calculated with complete data
4. ✅ Attribution model finalized and validated
5. ✅ Scaled to all 284 retailers
6. ✅ Pricing recommendations presented to Product team with confidence

---

## 📧 SUGGESTED EMAIL TO DATA ENGINEERING

```
Subject: Monitor Pricing - Production Cost Validation Needed

Hi Eric and team,

We're completing the Monitor production cost analysis to support pricing strategy.
We've found most costs but need your help validating and resolving some items:

CRITICAL:
1. Shipments cost discrepancy:
   - Old analysis (Sep-Oct 2024): $200,957/year
   - New analysis (Peak 2024 + Baseline 2025): $467,922/year
   - Which is more accurate for 2025 annual planning?

2. Orders table verification:
   - Does monitor-base-us-prod.monitor_base.orders exist as a base TABLE?
   - Or do v_orders/v_order_items query shipments directly?
   - If it exists, how is it populated and what's the cost?

3. Benchmark tables:
   - Do tnt_benchmarks_latest and ft_benchmarks_latest exist?
   - Are they tables or views?
   - Production costs?

NICE TO HAVE:
4. View definitions for: v_orders, v_order_items, v_benchmark_tnt, v_benchmark_ft
5. Airflow DAG names for shipments and return_item_details MERGE operations
6. Any optimization opportunities for the high-frequency MERGEs?

Analysis summary: monitor_production_costs/COMPLETE_PRODUCTION_COST_SUMMARY.md

Thanks!
```

---

## 📈 PROVISIONAL PRICING STRATEGY

**Pending cost validation, preliminary recommendations:**

### Model: Tiered Pricing (Simplicity wins adoption)

**Rationale:**
- Predictable monthly costs
- Industry standard (high acceptance)
- Can be refined based on actual usage data
- Massive profit potential allows for competitive pricing

### Margin Strategy: 20% (Sustainable)

**Rationale:**
- Industry standard for B2B SaaS
- Provides sustainability buffer
- Room for discounts and negotiations
- Funds platform improvements

### Customer Segmentation: Usage-based tiers

**Rationale:**
- Light tier subsidized (acquire small retailers)
- Enterprise tier custom (negotiate with high-cost retailers like fashionnova)
- Cross-subsidization acceptable (small retailers pay 2x cost, large pay 0.8x cost)

---

## ✅ WHAT'S READY NOW

**Can share with Product team (with caveats):**
- Executive summary (note: uses conservative $207K - will update)
- Pricing strategy options (comprehensive analysis)
- fashionnova case study (preliminary, pending complete costs)

**Can't share yet (needs validation):**
- Final platform cost ($598K pending validation)
- Final pricing tier prices (depend on validated costs)
- fashionnova total cost ($160K-$226K range, needs refinement)

---

## 💼 BUSINESS CASE SNAPSHOT (Provisional)

**If platform costs are $598K/year:**

| Pricing Model | Annual Revenue | Cost | Net Profit | Margin |
|---------------|----------------|------|------------|--------|
| Tiered (conservative) | $3,200,000 | $598,348 | $2,601,652 | 435% |
| Usage-based (20% margin) | $718,018 | $598,348 | $119,670 | 20% |
| Cost-plus (50% margin) | $897,522 | $598,348 | $299,174 | 50% |

**Key takeaway:** Even at $598K costs (3x initial estimate), tiered pricing generates massive profit.

**Strategic decision:** Invest excess profit in platform optimization vs extract as margin?

---

## 📁 ALL DELIVERABLES CREATED (30+ Files)

**Production Cost Analysis:** 9 files in `monitor_production_costs/`  
**Pricing Strategy:** 8 files in `docs/monitor_total_cost/`  
**Executive Summaries:** 6 files in root  
**SQL Queries:** 6 files in `queries/monitor_total_cost/`  
**Scripts:** 5 files in `scripts/`  
**Results:** 5 CSV files in `results/monitor_total_cost/`

**Total:** 33+ files, 12,000+ lines of analysis

---

## 🎯 RECOMMENDED NEXT SESSION AGENDA

1. **Start:** Read this file (MONITOR_PRICING_NEXT_SESSION.md)
2. **Review:** Production cost summaries in `monitor_production_costs/`
3. **Contact:** Data Engineering team with validation questions
4. **Resolve:** Shipments cost discrepancy + unknown tables
5. **Calculate:** Complete fashionnova and platform totals
6. **Scale:** Extend to all 284 retailers
7. **Finalize:** Pricing recommendations
8. **Present:** To Product team with confidence

**Timeline:** 1-2 days after getting Data Engineering input

---

**Status:** ⏸️ PAUSED FOR VALIDATION  
**Progress:** ~75% complete (costs found, attribution model ready, pricing framework designed)  
**Remaining:** ~25% (validation, scaling, finalization)  
**Critical Path:** Data Engineering input → Final costs → Scale to 284 → Present to Product

---

**Prepared by:** AI Assistant (Claude Sonnet 4.5)  
**Last Session:** November 14, 2025  
**Next Session:** Continue after Data Engineering validation  
**Priority:** URGENT - Pricing strategy decision pending

---

*For complete context, see: AI_SESSION_CONTEXT.md, MONITOR_2025_ANALYSIS_REPORT.md, and all files in monitor_production_costs/ folder*

