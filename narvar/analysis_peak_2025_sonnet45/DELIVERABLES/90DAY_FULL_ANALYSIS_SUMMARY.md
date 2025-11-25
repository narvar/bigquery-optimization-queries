# Monitor Platform - Retailer Cost Analysis (90-Day Window)

**Analysis Date:** November 25, 2025  
**Period:** Last 90 days (rolling window)  
**Coverage:** ALL 1,724 retailers in Monitor platform  
**Purpose:** Executive brief on retailer costs and usage patterns

> 📋 **For complete platform cost breakdown (7 tables + infrastructure)**, see [`MONITOR_COST_EXECUTIVE_SUMMARY.md`](MONITOR_COST_EXECUTIVE_SUMMARY.md)

---

## 🎯 Executive Summary

The Monitor platform serves **1,724 retailers** with a **massive zombie data problem**:

- **1,518 retailers (88%) have ZERO consumption** - zombie data
- **$109K/year wasted** on retailers who never query their data (45% of platform costs)
- **94% of retailers cost <$100 per 90 days** (<$400/year) - extreme long tail
- **Only 206 retailers (12%) actively use Monitor**
- **Top 106 retailers account for 73% of costs** - focus monetization here

---

## 📊 Cost Distribution (90-Day Period)

![Cost Distribution - All Retailers](cost_distribution_histogram_ALL_RETAILERS.png)

**Pro-Rated Platform Costs (90 days):**
- Shipments: $43,449 (from $176,556 annual)
- Orders: $11,157 (from $45,302 annual)
- Returns: $2,923 (from $11,871 annual)
- **Total Production (90d):** $57,529

| Cost Range (90 days) | Retailers | % of Total | Annualized Range |
|---------------------|-----------|------------|------------------|
| **$2,500-$5,000** | 2 | 0.1% | $10K-$20K/year |
| **$1,000-$2,500** | 9 | 0.5% | $4K-$10K/year |
| **$500-$1,000** | 13 | 0.8% | $2K-$4K/year |
| **$100-$500** | 82 | 4.8% | $400-$2K/year |
| **$0-$100** | **1,618** | **93.9%** | **<$400/year** |

**Key Statistics:**
- **Average:** $34/90 days = **$138/year**
- **Median:** $2.21/90 days = **$9/year**
- **Top 106 retailers** (>$100/90d) = **73% of platform costs**
- **Bottom 1,618 retailers** (<$100/90d) = **27% of platform costs**

---

## 🔍 Production vs Consumption Analysis

![Production vs Consumption Treemap](cost_treemap_production_vs_consumption.png)

**How to Read the Treemap:**
- **Rectangle SIZE** = Production cost (ETL + storage) - bigger = more expensive to produce
- **Rectangle COLOR** = Consumption intensity (query usage)
  - 🟦 Light blue/white = Zombie (0% consumption)
  - 🟦 Blue = Low consumption (<1%)
  - 🟦 Darker blue = Normal (1-5%)
  - 🟧 Orange = Elevated (5-20%)
  - 🟥 Red = Heavy (>20%)

**Visual Insights:**
- **53 of top 100 retailers are light blue** = zombies with expensive production but zero queries
- **Large light blue rectangles** = high-value audit targets (Gap, Kohls, Fanatics, etc.)
- **Small red rectangle** = 511Tactical anomaly (26x over-consumption)
- **Large orange rectangle** = FashionNova heavy user (expected)

---

## 🎯 Top 20 Retailers (90-Day Costs)

| Rank | Retailer | Production | Consumption | Total | Queries | Active Days | Avg/Day | Status |
|------|----------|------------|-------------|-------|---------|-------------|---------|--------|
| 1 | **Gap** | $2,962 | $0.00 | **$2,962** | 0 | - | 0 | 🔴 Zombie |
| 2 | **QVC** | $2,617 | $0.07 | **$2,617** | 2 | 1 | 2.0 | ✅ Minimal |
| 3 | **Kohls** | $2,479 | $0.00 | **$2,479** | 0 | - | 0 | 🔴 Zombie |
| 4 | **FashionNova** | $1,497 | **$581** | **$2,079** | 4,189 | **61** | 68.7 | 🟠 Heavy |
| 5 | **Fanatics** | $1,367 | $0.00 | **$1,367** | 0 | - | 0 | 🔴 Zombie |
| 6 | **Sephora** | $1,323 | $17 | **$1,339** | 864 | **61** | 14.2 | ✅ Active |
| 7 | **Centerwell** | $1,245 | $2 | **$1,247** | 1,995 | **61** | 32.7 | ✅ Active |
| 8 | **AE** | $1,219 | $0.15 | **$1,219** | 17 | 1 | 17.0 | ✅ Light |
| 9 | **Nike** | $1,157 | $4 | **$1,160** | 167 | 52 | 3.2 | ✅ Active |
| 10 | **Medline** | $1,057 | $0.00 | **$1,057** | 0 | - | 0 | 🔴 Zombie |
| 11 | **Lululemon** | $1,021 | $3 | **$1,024** | 1,219 | 58 | 21.0 | ✅ Active |
| 12 | **Ulta** | $915 | $0.67 | **$915** | 97 | 15 | 6.5 | ✅ Light |
| 13 | **511Tactical** | $33 | **$859** | **$891** | 707 | 59 | 12.0 | 🚨 Anomaly |
| 14 | **Shutterfly** | $825 | $0.00 | **$825** | 0 | - | 0 | 🔴 Zombie |
| 15 | **Dick's** | $738 | $0.00 | **$738** | 0 | - | 0 | 🔴 Zombie |
| 16 | **Victoria's Secret** | $689 | $0.00 | **$689** | 0 | - | 0 | 🔴 Zombie |
| 17 | **Bath & Body Works** | $640 | $0.00 | **$640** | 0 | - | 0 | 🔴 Zombie |
| 18 | **Dell** | $626 | $0.00 | **$626** | 0 | - | 0 | 🔴 Zombie |
| 19 | **Urban Outfitters** | $592 | $0.00 | **$592** | 0 | - | 0 | 🔴 Zombie |
| 20 | **JCPenney** | $573 | $3 | **$576** | 122 | 61 | 2.0 | ✅ Light |

**Note:** "Active Days" = days with at least one query in the 90-day window. Zombies show "-" (no query activity).

**Annualized Top 3:**
1. Gap: **$12,008/year** (100% zombie - 0 queries)
2. QVC: **$10,608/year** (nearly zombie - 2 queries on 1 day)
3. Kohls: **$10,050/year** (100% zombie - 0 queries)

---

## 💰 The Zombie Data Problem

### Definition
Retailers with production costs (data ingestion + storage) but **ZERO query consumption**.

### High-Value Zombies (Top 10)

These retailers cost **$51K/year** but NO ONE queries their data:

| Retailer | 90-Day Cost | Annualized | Status |
|----------|-------------|------------|--------|
| Gap | $2,962 | **$12,008** | 🔴 No queries |
| Kohls | $2,479 | **$10,050** | 🔴 No queries |
| Fanatics | $1,367 | **$5,542** | 🔴 No queries |
| Medline | $1,057 | **$4,286** | 🔴 No queries |
| Shutterfly | $825 | **$3,345** | 🔴 No queries |
| Dick's Sporting Goods | $738 | **$2,993** | 🔴 No queries |
| Victoria's Secret | $689 | **$2,794** | 🔴 No queries |
| Bath & Body Works | $640 | **$2,595** | 🔴 No queries |
| Dell | $626 | **$2,539** | 🔴 No queries |
| Urban Outfitters | $592 | **$2,400** | 🔴 No queries |

**These are actively ingesting millions of shipments and orders but NO ONE is querying the data!**

### Small Retailers (<$100 per 90 days)

**Segment Size:** 1,618 retailers (93.9% of platform)

**Cost Breakdown:**
- Total cost: $15,744 (90 days) = **~$64K/year**
- Production cost: $15,716 (99.8%)
- Consumption cost: $29 (0.2%)
- **Average per retailer: $9.73 / 90 days = $39/year**

**Activity Level:**
- Active (with queries): 161 retailers (10.0%)
- Zombie (no queries): 1,457 retailers (90.0%)

### Total Zombie Impact

| Segment | Retailers | Annual Cost | % of Platform |
|---------|-----------|-------------|---------------|
| **High-value zombies** (>$500/year) | ~10 | $51K | 21% |
| **Small zombies** (<$400/year) | ~1,457 | $58K | 24% |
| **Total zombie cost** | **1,518 (88%)** | **~$109K** | **45%** |

**This represents a crisis-level waste of platform resources.**

---

## 🔍 Outliers

### 1. 511Tactical - Super Consumer 🚨

| Metric | Value |
|--------|-------|
| Production cost | $33 (90 days) |
| Consumption cost | **$859** (90 days) |
| Total cost | $891 (90 days) = $3,613/year |
| Query count | 707 queries (12/day) |
| Consumption ratio | **2,634%** (26x production!) |

**This is the ONLY retailer consuming 26x more than they produce.**

**Action Required:** Immediate investigation into query patterns - potential bug, misconfiguration, or abuse.

### 2. FashionNova - Heavy User 🟠

| Metric | Value |
|--------|-------|
| Production cost | $1,497 (90 days) |
| Consumption cost | $581 (90 days) |
| Total cost | $2,079 (90 days) = $8,428/year |
| Query count | 4,189 queries (69/day) |
| Consumption ratio | **39%** |

**This is expected behavior for a power user** with heavy query activity.

**Action Required:** Usage-based pricing tier with overage fees for consumption >10% of production.

---

## 📊 Pricing Strategy Implications

### Current Situation

- **Platform cost:** ~$240K/year
- **Total retailers:** 1,724
- **Average per retailer:** $138/year
- **BUT:** 94% cost <$400/year, 88% have zero consumption

### Recommended Tiered Approach

#### Tier 1: Enterprise (11 retailers, >$1,000/90d)
- **Cost range:** $4K-$12K/year
- **Platform cost:** ~$67K/year (28%)
- **Suggested pricing:** $10K-$15K/year each
- **Revenue potential:** $110K-$165K/year
- **Note:** Many are zombies - audit before pricing!

#### Tier 2: Mid-Market (95 retailers, $100-$1,000/90d)
- **Cost range:** $400-$4K/year
- **Platform cost:** ~$101K/year (42%)
- **Suggested pricing:** $2K-$5K/year each
- **Revenue potential:** $190K-$475K/year

#### Tier 3: Light/Free (1,618 retailers, <$100/90d)
- **Cost range:** <$400/year
- **Platform cost:** ~$64K/year (27%)
- **Problem:** 1,457 are zombies (90% of segment)
- **Suggested pricing:** $0-$500/year (or free with limits)
- **Challenge:** Hard to monetize inactive users

### Zombie Cleanup Strategy

- **90 days no queries** → Warning notification
- **180 days no queries** → Move to archive/cold storage
- **360 days no queries** → Sunset integration
- **Potential savings:** ~$109K/year (45% of platform costs)

---

## 🎯 Immediate Recommendations

### 1. Audit Top 10 Zombie Retailers ($51K/year)
- Confirm if still active customers
- Understand why ingesting but not querying
- Sunset or charge premium pricing

### 2. Investigate 511Tactical Anomaly
- 26x over-consumption is anomalous
- Query pattern analysis needed
- Potential bug or misconfiguration

### 3. Focus Pricing on Top 106 Retailers
- These are 6% of retailers but 73% of costs
- More likely to be active users
- Easier to justify pricing

### 4. Clean Up Test/Staging Data
- Multiple test retailers found (returnse2etest-feerules, vuoriclothing-staging, etc.)
- Exclude from production cost analysis

---

## 🔧 Methodology & Data Quality

### Time Period (Consistent Across All Sources)

All data uses same 90-day lookback window:
- **Shipments:** atlas_created_ts >= 90 days ago
- **Orders:** order_date >= 90 days ago
- **Returns:** return_created_date >= 90 days ago
- **Consumption:** start_time >= 90 days ago

### Cost Pro-Rating

Annual costs × (90/365) = 90-day costs:
- Shipments: $176,556 → $43,449
- Orders: $45,302 → $11,157
- Returns: $11,871 → $2,923

### Known Limitations

1. Test/staging retailers should be filtered out
2. Some retailers may be internal/non-production
3. 90-day window may not capture seasonal patterns

---

## 📁 Data Sources

**SQL Query:**
- [`combined_cost_attribution_90days.sql`](../peak_capacity_analysis/queries/phase2_consumer_analysis/combined_cost_attribution_90days.sql)

**Results:**
- [`combined_cost_attribution_90days_ALL.csv`](../peak_capacity_analysis/results/combined_cost_attribution_90days_ALL.csv) - 1,724 retailers

**Visualizations:**
- `cost_distribution_histogram_ALL_RETAILERS.png` - Distribution chart
- `cost_treemap_production_vs_consumption.png` - Production vs consumption analysis

---

## 🚀 Next Steps

1. **Review findings** with product and finance teams
2. **Audit top 10 zombie retailers** ($51K/year opportunity)
3. **Investigate 511Tactical** (26x over-consumption)
4. **Schedule pricing strategy workshop** to determine:
   - Tier structure and pricing
   - Zombie data sunset policy
   - Usage-based overage fees
5. **Implement zombie cleanup policy** (~$109K/year savings potential)

---

**For detailed platform cost breakdown, optimization opportunities, and technical analysis, see:**  
[`MONITOR_COST_EXECUTIVE_SUMMARY.md`](MONITOR_COST_EXECUTIVE_SUMMARY.md)
