# Scaling Framework: All 284 Retailers Total Cost Analysis

## Overview

This document provides the framework for scaling the fashionnova PoC to all 284 Monitor retailers.

## Approach

### Phase 5.1: Batch Process All Retailers

**Modified Query:** `queries/monitor_total_cost/03_all_retailers_table_extraction.sql`

**Key Changes from PoC:**
```sql
-- Instead of:
WHERE retailer_moniker = 'fashionnova'

-- Use:
WHERE retailer_moniker IS NOT NULL
  AND consumer_subcategory = 'MONITOR'
```

**Expected Output:**
- `results/monitor_total_cost/all_retailers_referenced_tables.csv`
- ~50-200 unique tables across all retailers
- Cost: $0.50-$1.00

### Phase 5.2: Calculate Platform-Wide Metrics

**Query:** `queries/monitor_total_cost/04_platform_totals.sql`

```sql
-- Calculate exact totals for attribution denominators
SELECT
  COUNT(DISTINCT job_id) AS total_queries,
  SUM(slot_hours) AS total_slot_hours,
  SUM(total_billed_bytes) / POW(1024, 4) AS total_tb_scanned,
  SUM(estimated_slot_cost_usd) AS total_consumption_cost
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE consumer_subcategory = 'MONITOR'
  AND analysis_period_label IN ('Peak_2024_2025', 'Baseline_2025_Sep_Oct')
  AND total_slot_ms IS NOT NULL;
```

**Expected Results:**
- Total queries: 205,483 (known)
- Total slot-hours: ~25,000-30,000 (to be calculated)
- Total TB scanned: ~500-1,000 TB (to be calculated)

### Phase 5.3: Apply Attribution Model to All Retailers

**Query:** `queries/monitor_total_cost/05_all_retailers_attribution.sql`

**Logic:**
```sql
WITH retailer_metrics AS (
  SELECT
    retailer_moniker,
    COUNT(*) AS queries,
    SUM(slot_hours) AS slot_hours,
    SUM(total_billed_bytes) / POW(1024, 4) AS tb_scanned,
    SUM(estimated_slot_cost_usd) AS consumption_cost
  FROM traffic_classification
  WHERE consumer_subcategory = 'MONITOR'
  GROUP BY retailer_moniker
),

attribution_weights AS (
  SELECT
    retailer_moniker,
    -- Hybrid model (40/30/30)
    (0.40 * queries / SUM(queries) OVER() +
     0.30 * slot_hours / SUM(slot_hours) OVER() +
     0.30 * tb_scanned / SUM(tb_scanned) OVER()) AS production_share,
    queries,
    slot_hours,
    tb_scanned,
    consumption_cost
  FROM retailer_metrics
)

SELECT
  retailer_moniker,
  queries,
  slot_hours,
  tb_scanned,
  consumption_cost * (12.0 / 5.0) AS annual_consumption_cost,
  production_share * 200957 AS annual_production_cost,
  (consumption_cost * (12.0 / 5.0)) + (production_share * 200957) AS total_annual_cost,
  production_share
FROM attribution_weights
ORDER BY total_annual_cost DESC;
```

**Expected Output:**
- `results/monitor_total_cost/all_retailers_total_cost.csv`
- 284 rows (one per retailer)
- Cost: $0.20-$0.50

### Phase 5.4: Generate Rankings and Statistics

**Top 20 by Total Cost:**
- fashionnova expected #1 (~$70K)
- Top 20 likely account for 90%+ of total costs
- Long tail (260+ retailers) <10% of costs

**Key Metrics to Calculate:**
- Concentration (Top 20 share)
- Production/Consumption ratios
- Cost per query distributions
- Outlier identification

## Expected Findings

### Cost Distribution

**Projection based on fashionnova PoC:**

| Retailer Tier | Count | Estimated Total Cost | % of Platform |
|---------------|-------|----------------------|---------------|
| High-cost (>$10K/year) | 20-30 | $400K-$600K | 80-90% |
| Medium-cost ($1K-$10K) | 40-60 | $80K-$120K | 10-15% |
| Low-cost (<$1K) | 180-220 | $20K-$40K | 3-5% |
| **TOTAL** | **284** | **$500K-$760K** | **100%** |

### Platform Totals

**Consumption (known):** $2,674 (2 periods) → $6,418/year  
**Production (known):** $200,957/year  
**TOTAL PLATFORM COST:** ~$207,375/year

**Average per Retailer:** $730/year  
**Median per Retailer:** <$500/year (expected, due to concentration)

### Key Insights (Expected)

1. **Extreme concentration:** Top 20 retailers = 85-90% of costs
2. **Production dominance:** 97% production, 3% consumption (platform-wide)
3. **Efficiency variance:** 50-100x cost difference between most/least efficient
4. **Optimization potential:** $100K-$200K/year from top 20 optimizations

## Deliverables

### 1. Comprehensive Report

**File:** `MONITOR_2025_TOTAL_COST_ANALYSIS_REPORT.md`

**Contents:**
- Executive summary (platform totals)
- Top 20 retailers by total cost
- Cost distribution analysis
- Production/consumption breakdown
- Retailer tier analysis
- Optimization recommendations
- Comparison to consumption-only analysis

### 2. Cost Dashboard (Jupyter Notebook)

**File:** `notebooks/monitor_total_cost_analysis.ipynb`

**Visualizations:**
- Stacked bar chart: Top 30 retailers (consumption vs production)
- Scatter plot: Production vs consumption (identify outliers)
- Pie chart: Cost concentration (Top 20 vs rest)
- Histogram: Cost per query distribution
- Heatmap: Retailer cost trends over time (if historical data available)

### 3. Updated Monitor Report

**File:** Updates to `MONITOR_2025_ANALYSIS_REPORT.md`

**New Sections:**
- Total Cost Analysis (replaces/augments cost section)
- Production Cost Drivers
- Total Cost Rankings (with production included)
- Revised recommendations (consumption + production optimization)

## Timeline & Resources

**Estimated Time:** 4-6 hours
**Estimated Cost:** $1.50-$3.00 in BigQuery
**Prerequisites:** fashionnova PoC validated and approved

## Next Steps

1. **Validate fashionnova PoC** with stakeholders
2. **Calculate exact platform totals** (slot-hours, TB scanned)
3. **Execute Phase 5 queries** (all retailers)
4. **Generate comprehensive report** and visualizations
5. **Present findings** to leadership
6. **Begin optimization initiatives** for top cost retailers

---

**Status:** 📋 FRAMEWORK DOCUMENTED - Ready for execution after PoC validation  
**Owner:** Data Engineering + Analytics  
**Expected Completion:** 1-2 days post-validation

