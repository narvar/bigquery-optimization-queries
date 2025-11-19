# Repository Restructuring Proposal

**Date:** November 19, 2025  
**Problem:** 36 top-level markdown files, unclear organization, hard to find current vs historical work  
**Goal:** Clean, navigable structure with clear entry points

---

## Current Issues

1. **Too many top-level files** (36 .md files in root)
2. **Overlapping documents** (multiple session summaries, Slack updates, status files)
3. **Mixed concerns** (Monitor pricing + Peak capacity analysis + Hub QoS in same directory)
4. **No clear entry point** (which file should Product team read?)
5. **Unclear file status** (which are current deliverables vs work-in-progress vs historical?)

---

## Remaining Work to Complete Project

### Phase 1: Retailer Usage Profiling ⭐ **CURRENT PRIORITY**
**Timeline:** 2-4 weeks  
**Deliverables:**
- Per-retailer cost attribution (all 284 retailers)
- fashionnova detailed analysis (latency + retention requirements)
- Retailer segmentation by usage patterns
- Query pattern profiling results

### Phase 2: Pricing Strategy Finalization
**Timeline:** 1 week (after Phase 1)  
**Deliverables:**
- Pricing tier assignments
- Revenue projections
- Product team presentation deck

### Phase 3: Cost Optimization Implementation (Conditional)
**Timeline:** 3-6 months (if approved after Phase 1)  
**Deliverables:**
- Data retention optimization (if validated)
- Latency SLA optimization (if validated)
- Implementation roadmap

### Phase 4: Product Team Workshop
**Timeline:** When Phase 1-2 complete  
**Deliverables:**
- Final recommendations
- Decision matrix
- Rollout plan

---

## Proposed Structure

```
analysis_peak_2025_sonnet45/
│
├── README.md                           ⭐ NEW - Entry point with navigation
│
├── DELIVERABLES/                       ⭐ NEW - What Product team needs
│   ├── README.md                       Navigation guide
│   ├── MONITOR_COST_EXECUTIVE_SUMMARY.md (MOVED from root)
│   ├── MONITOR_PRICING_STRATEGY.md    (MOVED from root)
│   ├── COST_OPTIMIZATION_ANALYSIS.md  ⭐ NEW - Consolidates optimization findings
│   └── QUESTIONS_FOR_PRODUCT.md       ⭐ NEW - All outstanding questions
│
├── monitor_cost_analysis/              ⭐ RENAMED from monitor_production_costs/
│   ├── README.md                       
│   ├── methodology/
│   │   ├── CORRECT_COST_CALCULATION_METHODOLOGY.md
│   │   └── CRITICAL_FINDING_COST_CALCULATION_ERROR.md
│   ├── tables/
│   │   ├── SHIPMENTS_FINAL_COST.md    (consolidate with PRODUCTION_COST)
│   │   ├── ORDERS_FINAL_COST.md
│   │   ├── RETURN_ITEM_DETAILS_FINAL_COST.md
│   │   ├── BENCHMARKS_FINAL_COST.md
│   │   └── RETURN_RATE_AGG_FINAL_COST.md
│   ├── infrastructure/
│   │   ├── COMPOSER_AIRFLOW_COST.md   ⭐ NEW
│   │   └── PUBSUB_COST.md             ⭐ NEW
│   ├── billing_data/
│   │   ├── monitor-base 24 months.csv
│   │   ├── narvar-data-lake-base 24 months.csv
│   │   └── narvar-na01-datalake-base 24 months.csv
│   ├── queries/
│   │   ├── SHIPMENTS_COST_DECOMPOSITION.sql (MOVED from root)
│   │   └── COST_BREAKDOWN_SHIPMENTS_VS_ORDERS.sql (MOVED from root)
│   ├── results/
│   │   ├── shipments_decomposition_results.txt (MOVED from root)
│   │   └── shipments_vs_orders_results.txt (MOVED from root)
│   └── archive/                        (14 superseded files already here)
│
├── cost_optimization/                  ⭐ NEW - Optimization analysis
│   ├── README.md
│   ├── architecture/
│   │   ├── STREAMING_VS_BATCH_COMPARISON.md (MOVED from root)
│   │   └── Monitor+Analytics.doc       (MOVED from root)
│   ├── retailer_profiling/             ⭐ NEW - Phase 1 work goes here
│   │   ├── README.md
│   │   ├── fashionnova/                ⭐ NEW - Subfolder for fashionnova analysis
│   │   │   ├── queries/
│   │   │   ├── results/
│   │   │   └── FASHIONNOVA_ANALYSIS.md
│   │   ├── all_retailers/
│   │   │   ├── queries/
│   │   │   ├── results/
│   │   │   └── RETAILER_SEGMENTATION.md
│   │   └── RETAILER_USAGE_PROFILING_RESULTS.md (consolidated)
│   ├── latency_optimization/
│   │   └── (Phase 3 work, if proceeding)
│   └── retention_optimization/
│       └── (Phase 2 work, if proceeding)
│
├── peak_capacity_analysis/             ⭐ NEW - Separate concern from Monitor pricing
│   ├── README.md
│   ├── phase1/
│   │   └── PHASE1_FINAL_REPORT.md     (MOVED from root)
│   ├── hub_qos/
│   │   ├── INV6_HUB_QOS_RESULTS.md    (MOVED from root)
│   │   ├── HUB_ANALYTICS_API_2025_REPORT.md (MOVED from root)
│   │   └── LOOKER_VS_HUB_ANALYTICS_COMPARISON.md (MOVED from root)
│   ├── monitor/
│   │   └── MONITOR_2025_ANALYSIS_REPORT.md (MOVED from root)
│   ├── root_cause/
│   │   └── ROOT_CAUSE_ANALYSIS_FINDINGS.md (MOVED from root)
│   ├── queries/                        (MOVED from root)
│   ├── results/                        (MOVED from root)
│   ├── scripts/                        (MOVED from root)
│   ├── notebooks/                      (MOVED from root)
│   ├── images/                         (MOVED from root)
│   └── PEAK_2025_2026_STRATEGY_EXEC_REPORT.md (MOVED from root)
│
├── session_logs/                       ⭐ NEW - Historical session context
│   ├── 2025-11-14/
│   │   ├── SESSION_SUMMARY_2025_11_14.md
│   │   ├── SESSION_SUMMARY_2025_11_14_EVENING.md
│   │   ├── SLACK_UPDATE_2025_11_14_EVENING.md
│   │   └── SLACK_UPDATE_2025_11_14_MONITOR_PRICING.md
│   ├── 2025-11-17/
│   │   ├── SESSION_SUMMARY_2025_11_17.md
│   │   ├── SLACK_UPDATE_2025_11_17.md
│   │   └── TODAYS_ACCOMPLISHMENTS_NOV_17_2025.md
│   ├── 2025-11-19/
│   │   └── (today's session notes)
│   └── LETTER_TO_TOMORROW.md           (keep at root or move here)
│
├── archive/                            ⭐ NEW - Deprecated/superseded files
│   ├── MONITOR_TOTAL_COST_ANALYSIS_PLAN.md
│   ├── MONITOR_TOTAL_COST_EXECUTION_SUMMARY.md
│   ├── MONITOR_TOTAL_COST_STATUS.md
│   ├── MONITOR_COST_UPDATE_CRITICAL_FINDINGS.md
│   ├── PRIORITIES_2_TO_5_REQUIREMENTS.md
│   ├── TOMORROW_PRIORITY_OPTIMIZATION_SCENARIOS.md (superseded by new structure)
│   ├── NEXT_SESSION_PROMPT.md
│   ├── MONITOR_PRICING_NEXT_SESSION.md
│   ├── SQL_SEMANTIC_ANALYSIS_*.md (3 files)
│   └── sql_semantic_analysis/          (entire directory)
│
└── docs/                               (keep current structure)
    ├── CLASSIFICATION_STRATEGY.md
    ├── IMPLEMENTATION_STATUS.md
    ├── monitor_total_cost/
    ├── phase2/
    ├── reference/
    └── archive/
```

---

## Essential Files to Keep (DELIVERABLES)

### For Product Team (What they need to make decisions):

1. **DELIVERABLES/README.md** ⭐ NEW
   - Navigation guide
   - What each document contains
   - Reading order recommendation

2. **DELIVERABLES/MONITOR_COST_EXECUTIVE_SUMMARY.md** (moved from root)
   - Complete cost analysis ($263K breakdown)
   - Cost optimization opportunities
   - Retailer profiling plan
   - **THIS IS THE PRIMARY DELIVERABLE**

3. **DELIVERABLES/MONITOR_PRICING_STRATEGY.md** (moved from root)
   - Pricing options (tiered, usage-based, hybrid)
   - Revenue projections
   - Rollout recommendations

4. **DELIVERABLES/COST_OPTIMIZATION_ANALYSIS.md** ⭐ NEW (consolidates multiple docs)
   - Streaming vs batch comparison
   - Partition pruning findings
   - Optimization roadmap
   - Combined from: STREAMING_VS_BATCH_ARCHITECTURE_COMPARISON.md + COST_BREAKDOWN_ANALYSIS_PLAN.md

5. **DELIVERABLES/QUESTIONS_FOR_PRODUCT.md** ⭐ NEW
   - All questions requiring Product Management input
   - Competitive analysis questions
   - SLA contract questions
   - Compliance questions
   - Extracted from various documents

### Supporting Analysis (How we got here):

6. **monitor_cost_analysis/** directory
   - Methodology documents
   - Individual table cost analyses
   - Billing data
   - SQL queries and results
   - Archive of superseded versions

7. **cost_optimization/** directory ⭐ NEW
   - Retailer profiling work (Phase 1)
   - fashionnova subfolder (isolated analysis)
   - Architecture comparisons
   - Optimization scenarios

### Context/Historical (For continuity):

8. **session_logs/** directory ⭐ NEW
   - Organized by date
   - Session summaries, Slack updates, accomplishments
   - Helps future AI understand context
   - Not needed by Product team

9. **LETTER_TO_TOMORROW.md** (keep at root)
   - Critical for AI continuity
   - Contains communication guidelines
   - Historical context

---

## Files to Archive (Superseded/Historical)

**Session Management (move to session_logs/):**
- SESSION_SUMMARY_2025_11_14.md
- SESSION_SUMMARY_2025_11_14_EVENING.md
- SESSION_SUMMARY_2025_11_17.md
- SLACK_UPDATE_2025_11_12.md
- SLACK_UPDATE_2025_11_14_EVENING.md
- SLACK_UPDATE_2025_11_14_MONITOR_PRICING.md
- SLACK_UPDATE_2025_11_17.md
- TODAYS_ACCOMPLISHMENTS_NOV_17_2025.md

**Superseded Planning Docs (move to archive/):**
- MONITOR_TOTAL_COST_ANALYSIS_PLAN.md
- MONITOR_TOTAL_COST_EXECUTION_SUMMARY.md
- MONITOR_TOTAL_COST_STATUS.md
- MONITOR_COST_UPDATE_CRITICAL_FINDINGS.md
- PRIORITIES_2_TO_5_REQUIREMENTS.md
- TOMORROW_PRIORITY_OPTIMIZATION_SCENARIOS.md
- NEXT_SESSION_PROMPT.md
- MONITOR_PRICING_NEXT_SESSION.md
- MONITOR_TOTAL_COST_REVIEW_FOR_PRODUCT_TEAM.md

**SQL Semantic Analysis (move to archive/ - abandoned workstream):**
- SQL_QUERY_SEMANTIC_ANALYSIS_FRAMEWORK.md
- SQL_SEMANTIC_ANALYSIS_NEXT_SESSION.md
- SQL_SEMANTIC_ANALYSIS_PHASE0_PLAN.md
- sql_semantic_analysis/ directory

**Peak Capacity Analysis (move to peak_capacity_analysis/):**
- PEAK_2025_2026_STRATEGY_EXEC_REPORT.md
- PHASE1_FINAL_REPORT.md
- ROOT_CAUSE_ANALYSIS_FINDINGS.md
- INV6_HUB_QOS_RESULTS.md
- HUB_ANALYTICS_API_2025_REPORT.md
- LOOKER_VS_HUB_ANALYTICS_COMPARISON.md
- MONITOR_2025_ANALYSIS_REPORT.md
- LOOKER_2025_ANALYSIS_REPORT.md
- queries/, results/, scripts/, notebooks/, images/

---

## Proposed Top-Level Structure (After Cleanup)

```
analysis_peak_2025_sonnet45/
│
├── README.md                           ⭐ Master navigation document
├── LETTER_TO_TOMORROW.md               AI continuity
│
├── DELIVERABLES/                       ⭐ What Product needs (4-5 files)
├── monitor_cost_analysis/              Supporting cost analysis
├── cost_optimization/                  ⭐ NEW - Phase 1 work here
│   └── retailer_profiling/
│       └── fashionnova/                ⭐ Isolated fashionnova analysis
├── peak_capacity_analysis/             Separate concern (Hub QoS, etc.)
├── session_logs/                       Historical context (9 files)
├── archive/                            Superseded files (12 files)
└── docs/                               Current supporting docs
```

**Top-level file count after restructuring:** ~2-3 files (README + LETTER_TO_TOMORROW)

---

## Answer to Your Questions

### 1. Remaining Steps to Finalize Project

**Immediate (2-4 weeks):**
- ✅ Phase 1: Retailer usage profiling (fashionnova priority)
- ✅ Consolidate findings into clean deliverables
- ✅ Update pricing strategy with profiling results

**Near-term (1-2 months):**
- ✅ Product team workshop and decisions
- ✅ Pricing strategy approval
- ⏸️ Cost optimization Phase 2/3 (conditional on decisions)

**Long-term (3-6 months):**
- ⏸️ Implementation of approved optimization strategies
- ⏸️ Rollout and monitoring

### 2. fashionnova Analysis Subfolder

**Recommended location:**
```
cost_optimization/retailer_profiling/fashionnova/
├── README.md                           Overview and purpose
├── queries/
│   ├── fashionnova_latency_analysis.sql
│   ├── fashionnova_retention_analysis.sql
│   ├── fashionnova_cost_breakdown.sql
│   └── fashionnova_query_patterns.sql
├── results/
│   ├── latency_requirements.csv
│   ├── retention_requirements.csv
│   ├── cost_breakdown.csv
│   └── query_patterns.csv
└── FASHIONNOVA_USAGE_ANALYSIS.md       Consolidated findings
```

**Why this structure:**
- Isolated from other work (easy to find)
- Parallel structure for other retailers if needed
- Clear separation of queries, results, analysis
- Part of cost_optimization workflow (not mixed with cost calculation)

---

## Implementation Plan

### Step 1: Create New Structure (15 mins)
- Create new directories
- Create README files with navigation

### Step 2: Move Files (20 mins)
- Move deliverables to DELIVERABLES/
- Move session logs to session_logs/
- Move peak capacity work to peak_capacity_analysis/
- Move superseded files to archive/

### Step 3: Create Consolidated Documents (30 mins)
- Create DELIVERABLES/README.md with navigation
- Create DELIVERABLES/COST_OPTIMIZATION_ANALYSIS.md (consolidates STREAMING_VS_BATCH + COST_BREAKDOWN_ANALYSIS_PLAN)
- Create DELIVERABLES/QUESTIONS_FOR_PRODUCT.md
- Create root README.md as master entry point

### Step 4: Update Cross-References (15 mins)
- Update links in documents to reflect new paths
- Update LETTER_TO_TOMORROW.md with new structure

### Step 5: Commit Restructuring (5 mins)
- Single commit: "Restructure repository for clarity"
- Clear commit message explaining reorganization

**Total time:** ~1.5 hours

---

## Benefits of This Structure

1. **Clear entry point** - README.md at root tells you where to go
2. **Deliverables isolated** - Product team can find what they need quickly
3. **Work organized by phase** - Current work (retailer profiling) has clear home
4. **Historical context preserved** - Session logs organized by date
5. **Reduced top-level clutter** - From 36 files to 2-3 files
6. **fashionnova isolated** - Easy to find and work on without mixing with other analysis

---

## Essential Files List (What Product Team Needs)

**Must Keep:**
1. MONITOR_COST_EXECUTIVE_SUMMARY.md ($263K cost analysis)
2. MONITOR_PRICING_STRATEGY.md (pricing options)
3. Cost optimization analysis (consolidated)
4. Individual table cost analyses (7 tables)
5. Methodology documentation
6. Billing data CSVs

**Can Archive:**
- All session summaries and Slack updates (historical context only)
- Superseded planning documents
- SQL semantic analysis work (abandoned)
- Multiple status update files

**Separate:**
- Peak capacity analysis (different concern from Monitor pricing)
- Hub QoS analysis (different concern)

---

## Questions for You

1. **Should I proceed with this restructuring?** (1.5 hours of work)
2. **Or start fashionnova analysis in current structure** and restructure later?
3. **Any changes to the proposed structure?**

My recommendation: Do the restructuring now (1.5 hours). It will make the next 2-4 weeks of retailer profiling work much cleaner and easier to navigate.

