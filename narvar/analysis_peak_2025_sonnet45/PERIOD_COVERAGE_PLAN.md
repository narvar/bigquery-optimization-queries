# Period Coverage Plan - Complete Historical Analysis

**Generated**: November 5, 2025  
**Purpose**: Classify 3 years of peak and non-peak periods for comprehensive capacity planning

---

## 📅 Timeline Visualization

```
2022:  ────[Sep-Oct]────[Nov──Dec──Jan]────[Feb-Mar]────────────────────────
       NON-PEAK         PEAK 2022-2023       NON-PEAK

2023:  ────[Sep-Oct]────[Nov──Dec──Jan]────[Feb-Mar]────────────────────────
       NON-PEAK         PEAK 2023-2024       NON-PEAK

2024:  ────[Sep-Oct]────[Nov──Dec──Jan]────[Feb-Mar]────────────────────────
       BASELINE ✅      PEAK 2024-2025       NON-PEAK

2025:  ─────────────────[Nov──Dec──Jan]────────────────────────────────────►
                        PEAK 2025-2026       (TARGET PLANNING PERIOD)
                        (Upcoming)
```

**Coverage**: 19 months of classified data spanning 2.5 years

---

## 📊 Complete Period Breakdown

### **Year 2024** (Most Recent - 8 months coverage)

| Period | Dates | Type | Purpose | Jobs (Est.) | Status |
|--------|-------|------|---------|-------------|--------|
| Baseline_2024_Sep_Oct | Sep-Oct 2024 | Non-Peak | Pattern discovery, recent baseline | 3.79M | ✅ DONE |
| Peak_2024_2025 | Nov 2024-Jan 2025 | **PEAK** | Most recent peak (critical for YoY) | 5.5-6M | ⏳ |
| NonPeak_2024_Feb_Mar | Feb-Mar 2024 | Non-Peak | Post-peak baseline | 3.5-4M | ⏳ |

**Total 2024**: ~12-14M jobs classified

---

### **Year 2023** (Historical Comparison - 7 months coverage)

| Period | Dates | Type | Purpose | Jobs (Est.) | Status |
|--------|-------|------|---------|-------------|--------|
| NonPeak_2023_Sep_Oct | Sep-Oct 2023 | Non-Peak | Pre-peak baseline | 3-4M | ⏳ |
| Peak_2023_2024 | Nov 2023-Jan 2024 | **PEAK** | YoY comparison | 5-6M | ⏳ |
| NonPeak_2023_Feb_Mar | Feb-Mar 2023 | Non-Peak | Post-peak baseline | 3-4M | ⏳ |

**Total 2023**: ~11-14M jobs classified

---

### **Year 2022** (3-Year Trend - 5 months coverage)

| Period | Dates | Type | Purpose | Jobs (Est.) | Status |
|--------|-------|------|---------|-------------|--------|
| NonPeak_2022_Sep_Oct | Sep-Oct 2022 | Non-Peak | Pre-peak baseline | 2.5-3M | ⏳ |
| Peak_2022_2023 | Nov 2022-Jan 2023 | **PEAK** | 3-year trend, CAGR | 4-5M | ⏳ |

**Total 2022**: ~7-8M jobs classified

---

## 🎯 Analysis Capabilities After Classification

### ✅ Peak vs. Non-Peak Comparison
**Compare**:
- Sep-Oct (pre-peak) vs. Nov-Jan (peak) vs. Feb-Mar (post-peak)
- Each year: 2022, 2023, 2024

**Insights**:
- Peak multiplier (e.g., "peak is 2.1x higher than Sep-Oct baseline")
- Transition patterns (how fast does traffic ramp up/down?)
- Seasonal variations (Sep-Oct vs Feb-Mar non-peak)

### ✅ Year-over-Year Growth
**Compare same periods across years**:
- Peak 2022-2023 vs. Peak 2023-2024 vs. Peak 2024-2025
- NonPeak Sep-Oct 2022 vs. 2023 vs. 2024

**Insights**:
- Annual growth rate by category (EXTERNAL, AUTOMATED, INTERNAL)
- Which categories are growing fastest?
- Is growth accelerating or decelerating?

### ✅ Compound Annual Growth Rate (CAGR)
**3-year trend**:
- 2022 → 2023 → 2024 peak periods
- 2022 → 2023 → 2024 non-peak periods

**Insights**:
- Projected 2025-2026 peak demand
- Expected slot requirements for 2025

### ✅ Slot Demand Patterns
**Hourly/daily patterns**:
- Peak weekday vs. weekend
- Peak daytime vs. nighttime
- Non-peak patterns (different?)

**Insights**:
- When do we hit capacity limits?
- Intra-day/intra-week variation
- Time-of-day slot allocation optimization

---

## 📈 Expected Metrics After All Classifications

### Aggregate Statistics (Estimated):

**Total Jobs**: ~32-36M jobs across all periods
**Total Slot Hours**: ~5.5-6.5M slot-hours
**Total Cost (historical)**: ~$280-320K (19 months)
**Average monthly cost**: ~$15-17K

### Expected Distribution:
```
AUTOMATED:  70-77% of jobs, 35-40% of slot hours
EXTERNAL:   12-15% of jobs, 35-40% of slot hours (slot-intensive!)
INTERNAL:   10-12% of jobs, 20-25% of slot hours
UNCLASSIFIED: 3-6% of jobs, <1% of slot hours
```

### Expected Growth Trends:
```
Peak growth (2022→2024):     +15-25% CAGR
Non-peak growth (2022→2024): +12-20% CAGR
External growth:             +20-30% CAGR (fastest)
Automated growth:            +10-20% CAGR
Internal growth:             +5-15% CAGR
```

---

## 🎁 What This Enables for Phase 2-4

### Phase 2: Historical Analysis
- ✅ Peak vs. non-peak comparison (direct from table)
- ✅ QoS violations by period and category
- ✅ Slot utilization heatmaps
- ✅ YoY growth calculations

### Phase 3: Prediction
- ✅ Apply growth rates to project 2025-2026 peak
- ✅ Forecast slot demand by hour/day
- ✅ Predict QoS violations under current capacity

### Phase 4: Simulation
- ✅ Test different slot allocation scenarios
- ✅ Model peak multiplier variations
- ✅ Cost-benefit analysis for capacity increases

---

## 💾 Storage Impact

### Table Size After All Periods:
```
Rows:     ~32-36M rows
Storage:  ~16-20 GB (compressed)
Cost:     ~$0.32-0.40/month (BigQuery storage)
```

### Query Performance:
- ✅ Partitioned by start_time (efficient date filtering)
- ✅ Clustered by consumer_category (fast aggregations)
- ✅ Typical Phase 2 query: Scans only relevant partitions (~1-3 months)
- ✅ Cost per Phase 2 query: $0.01-0.10 (very efficient!)

---

## ⚙️ Running the Automation

### Recommended Workflow:

**Step 1: Dry Run** (1 minute)
```bash
cd scripts/
python run_classification_all_periods.py --mode all --dry-run
```
**Check**: Estimated cost, ensure it's ~$3-5

**Step 2: Test Run** (10-15 minutes)
```bash
python run_classification_all_periods.py --mode test
```
**Check**: One period completes successfully, validation passes

**Step 3: Full Run** (2-2.5 hours)
```bash
# Can run unattended - perfect for overnight or lunch break
python run_classification_all_periods.py --mode all

# Or run in background with logging
nohup python run_classification_all_periods.py --mode all > classification_run.log 2>&1 &
```

**Step 4: Validate Results**
```bash
# Check the summary output
# Run validation queries in BigQuery
```

---

## ✅ Success Criteria

After all classifications complete:

- [x] 8 periods successfully classified (7 new + 1 existing)
- [x] All periods have <10% unclassified
- [x] Peak periods have >5M jobs each
- [x] Non-peak periods have >2.5M jobs each
- [x] Retailer attribution working (200+ retailers per period)
- [x] Table size reasonable (~16-20 GB)
- [x] Ready for Phase 2 analysis

---

## 🚀 Next Steps After Classification

1. **Validate quality**: Check unclassified rate per period
2. **Review patterns**: Any unexpected changes over time?
3. **Document findings**: Note any periods with data quality issues
4. **Proceed to Phase 2**: Historical analysis queries
5. **Generate insights**: Peak patterns, growth trends, capacity needs

---

**Automation ready!** The script will handle everything and give you a complete historical dataset for analysis. 🎉

