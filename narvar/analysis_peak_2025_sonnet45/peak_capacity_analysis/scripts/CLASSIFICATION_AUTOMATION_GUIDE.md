# Traffic Classification Automation Guide

**Script**: `run_classification_all_periods.py`  
**Purpose**: Automatically classify 8 periods (3 peak + 5 non-peak) for comprehensive analysis  
**Total Runtime**: ~2-3 hours (can run unattended)

---

## 📅 Periods to Be Classified

### Summary Table:

| # | Period Label | Date Range | Type | Duration | Est. Jobs | Est. Runtime | Status |
|---|-------------|------------|------|----------|-----------|--------------|--------|
| 1 | Baseline_2024_Sep_Oct | Sep-Oct 2024 | Non-Peak | 2 months | 3.79M | ✅ DONE | Already in table |
| 2 | Peak_2024_2025 | Nov 2024-Jan 2025 | Peak | 3 months | 5.5-6M | 25 min | ⏳ To run |
| 3 | NonPeak_2024_Feb_Mar | Feb-Mar 2024 | Non-Peak | 2 months | 3.5-4M | 12 min | ⏳ To run |
| 4 | Peak_2023_2024 | Nov 2023-Jan 2024 | Peak | 3 months | 5-6M | 25 min | ⏳ To run |
| 5 | NonPeak_2023_Sep_Oct | Sep-Oct 2023 | Non-Peak | 2 months | 3-4M | 12 min | ⏳ To run |
| 6 | NonPeak_2023_Feb_Mar | Feb-Mar 2023 | Non-Peak | 2 months | 3-4M | 12 min | ⏳ To run |
| 7 | Peak_2022_2023 | Nov 2022-Jan 2023 | Peak | 3 months | 4-5M | 25 min | ⏳ To run |
| 8 | NonPeak_2022_Sep_Oct | Sep-Oct 2022 | Non-Peak | 2 months | 2.5-3M | 12 min | ⏳ To run |

**Total**: 7 additional periods to classify  
**Estimated Runtime**: ~120-140 minutes (~2-2.5 hours)  
**Estimated Cost**: ~$3-5 (50-100 GB processed)  
**Total Jobs**: ~30-35M jobs across all periods

---

## 🎯 Why These Specific Periods?

### Peak Periods (3 periods = 9 months):
- **Peak_2024_2025**: Most recent complete peak (critical for YoY comparison)
- **Peak_2023_2024**: 1-year historical comparison (YoY growth rate)
- **Peak_2022_2023**: 2-year historical comparison (CAGR calculation)

### Non-Peak Periods (5 periods = 10 months):
- **Pre-Peak Baselines** (Sep-Oct each year):
  - Understand normal capacity before peak ramp-up
  - Calculate peak multiplier (peak vs. baseline ratio)
  - Sep-Oct: Back-to-school season (higher than mid-year but lower than peak)

- **Post-Peak Baselines** (Feb-Mar each year):
  - Post-holiday returns period
  - Understand capacity wind-down after peak
  - Q1 planning activities (moderate load)

### Coverage Strategy:
```
2024: Sep-Oct (✅), Nov-Jan (peak), Feb-Mar
2023: Sep-Oct, Nov-Jan (peak), Feb-Mar
2022: Sep-Oct, Nov-Jan (peak)

Total: 19 months of data spanning 2.5 years
```

This gives us:
- ✅ 3 complete peak periods for trend analysis
- ✅ 5 non-peak periods for baseline comparison
- ✅ Pre/post peak data for transition analysis
- ✅ Balanced dataset for statistical modeling in Phase 3

---

## 🚀 Quick Start

### 1. Install Dependencies
```bash
cd /Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/analysis_peak_2025_sonnet45/scripts
pip install -r requirements.txt
```

### 2. Test with Dry Run (Recommended First!)
```bash
# Estimate cost without running
python run_classification_all_periods.py --mode all --dry-run
```

**Output**: Shows estimated bytes and cost for all periods

### 3. Run All Periods
```bash
# Run all 7 remaining periods (skip already-done baseline)
python run_classification_all_periods.py --mode all
```

**Runtime**: ~2-2.5 hours  
**Will prompt**: Yes/No confirmation before starting

### 4. Alternative Execution Modes

**Run peaks only** (faster, ~75 minutes):
```bash
python run_classification_all_periods.py --mode peak-only
```

**Run non-peaks only** (~60 minutes):
```bash
python run_classification_all_periods.py --mode non-peak-only
```

**Test with one period** (validation):
```bash
python run_classification_all_periods.py --mode test
```

---

## 📊 What the Script Does

### For Each Period:
1. ✅ Generates parameterized SQL from template
2. ✅ Executes INSERT INTO query (appends to existing table)
3. ✅ Tracks progress with timestamps
4. ✅ Waits for completion with status updates
5. ✅ Validates results automatically
6. ✅ Checks unclassified rate
7. ✅ Reports metrics (jobs, slot-hours, cost)

### Error Handling:
- ✅ Catches query failures gracefully
- ✅ Prompts to continue if one period fails
- ✅ Continues with remaining periods
- ✅ Provides detailed error messages

### Output:
- ✅ Real-time progress for each period
- ✅ Validation metrics after each run
- ✅ Summary table at completion
- ✅ Quality warnings if unclassified >5%

---

## 📋 Expected Output

### During Execution:
```
================================================================================
🔄 Processing: Peak_2024_2025
   Description: Most recent complete peak
   Period: 2024-11-01 to 2025-01-31
   Type: PEAK
================================================================================
   ⏳ Query job started: bqjob_r1234...
   ⏳ Waiting for completion...
   ✅ Completed in 24.3 minutes
   📊 Bytes processed: 42.15 GB
   📊 Slot milliseconds: 1,245,678,901

   📊 Validation Results:
      Jobs classified: 5,847,291
      Unclassified: 3.8%
      Slot hours: 1,247,583
      Estimated cost: $61,638
      Unique retailers: 215
      ✅ Excellent classification rate!
```

### Final Summary:
```
================================================================================
📊 CLASSIFICATION RUN SUMMARY
================================================================================

✅ Successful runs: 7

Period                         Jobs         Unclass %    Slot Hours      Cost         Runtime
----------------------------------------------------------------------------------------------------
Peak_2024_2025                5,847,291      3.8%      1,247,583       $61,638      24.3 min
NonPeak_2024_Feb_Mar          3,421,556      4.1%        687,234       $33,945      11.8 min
Peak_2023_2024                5,234,789      4.5%      1,123,456       $55,519      23.7 min
NonPeak_2023_Sep_Oct          3,156,234      4.2%        623,145       $30,783      11.2 min
NonPeak_2023_Feb_Mar          3,089,567      4.8%        598,234       $29,553      11.5 min
Peak_2022_2023                4,567,890      6.2%        945,678       $46,726      22.1 min
NonPeak_2022_Sep_Oct          2,834,123      5.9%        512,345       $25,310      10.9 min
----------------------------------------------------------------------------------------------------
TOTAL                        28,151,450                5,737,675      $283,474     115.5 min

================================================================================
```

---

## 🔧 Customization

### Add More Periods:
Edit `PERIODS` list in the script (lines 24-104):
```python
{
    "label": "NonPeak_2024_Jun_Jul",
    "start_date": "2024-06-01",
    "end_date": "2024-07-31",
    "type": "non_peak",
    "priority": 9,
    "skip": False,
    "description": "Mid-year baseline"
}
```

### Skip Specific Periods:
Set `"skip": True` for any period you don't want to run

### Change Classification Version:
Update `CLASSIFICATION_VERSION = "v1.1"` if you've improved patterns

### Adjust Slot Cost:
Update `DECLARE slot_cost_per_hour` in SQL_TEMPLATE if pricing changes

---

## 🎯 Post-Execution Validation

### Check Overall Quality:
```sql
SELECT
  analysis_period_label,
  COUNT(*) AS jobs,
  ROUND(COUNTIF(consumer_category = 'UNCLASSIFIED') / COUNT(*) * 100, 2) AS unclassified_pct,
  ROUND(SUM(slot_hours), 2) AS slot_hours,
  ROUND(SUM(estimated_slot_cost_usd), 2) AS cost_usd
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE classification_date = CURRENT_DATE()
GROUP BY analysis_period_label
ORDER BY analysis_period_label;
```

### Compare Peak vs Non-Peak:
```sql
SELECT
  CASE 
    WHEN analysis_period_label LIKE 'Peak%' THEN 'PEAK'
    ELSE 'NON_PEAK'
  END AS period_type,
  consumer_category,
  COUNT(*) AS jobs,
  ROUND(AVG(execution_time_seconds), 2) AS avg_exec_sec,
  ROUND(SUM(slot_hours), 2) AS total_slot_hours
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE classification_date = CURRENT_DATE()
GROUP BY period_type, consumer_category
ORDER BY period_type, jobs DESC;
```

---

## ⚠️ Important Notes

### Before Running:

1. **Ensure first period is done**: Baseline_2024_Sep_Oct should already be in the table
2. **Check disk space**: ~40-50 GB will be added to the table
3. **Verify INSERT mode**: Script uses INSERT INTO (appends data)
4. **Schedule appropriately**: ~2 hours runtime - consider running overnight

### Cost Estimate:
- **Per 2-month period**: ~$0.50-0.80 (8-15 GB processed)
- **Per 3-month period**: ~$1.50-2.50 (25-40 GB processed)
- **Total for 7 periods**: ~$3-5

### Table Growth:
- **Current**: ~3.79M rows (1.8 GB)
- **After all periods**: ~32-35M rows (15-18 GB)
- **Storage cost**: ~$0.30-0.40/month

### Performance:
- Queries on the table will be very efficient due to:
  - Partitioning by start_time (date pruning)
  - Clustering by consumer_category (category filtering)
  - Only scans relevant partitions

---

## 🐛 Troubleshooting

### Error: "Table not found"
**Cause**: First run hasn't created the table yet  
**Solution**: Run baseline first manually, or modify script to use CREATE OR REPLACE for first period

### Error: "Duplicate job_id"
**Cause**: Period already classified  
**Solution**: Either skip the period or use different classification_version

### Error: "Quota exceeded"
**Cause**: Too many concurrent queries  
**Solution**: Script runs sequentially (no concurrency issue), but check other running queries

### High Unclassified Rate (>10%)
**Cause**: Historical period has retired service accounts  
**Solution**: 
1. Note which period has high unclassified
2. Query for unclassified principals
3. Add patterns to SQL_TEMPLATE
4. Re-run that period with version v1.1

---

## 📈 After All Periods Complete

You'll have complete coverage for Phase 2 analysis:
- ✅ 3 peak periods (Nov-Jan 2022/23, 2023/24, 2024/25)
- ✅ 5 non-peak periods (Sep-Oct, Feb-Mar for each year)
- ✅ ~32-35M jobs classified
- ✅ Consistent taxonomy across all periods
- ✅ Ready for peak vs. non-peak comparison
- ✅ Ready for YoY growth analysis
- ✅ Ready for slot demand forecasting

### Phase 2 Queries Can Now:
- Compare peak vs. non-peak traffic patterns
- Calculate peak multiplier (e.g., "peak is 2.3x non-peak")
- Identify seasonal trends
- Project 2025-2026 peak demand
- Simulate slot allocation scenarios

---

## 🎯 Recommended Execution

### Option 1: Run Everything Now (Recommended)
```bash
# Full automation - go get coffee/lunch! ☕
python run_classification_all_periods.py --mode all
```

### Option 2: Phased Approach
```bash
# Step 1: Run peaks first (~75 min)
python run_classification_all_periods.py --mode peak-only

# Step 2: Run non-peaks later (~60 min)
python run_classification_all_periods.py --mode non-peak-only
```

### Option 3: Test First
```bash
# Test with one period to validate (~12 min)
python run_classification_all_periods.py --mode test

# If successful, run all
python run_classification_all_periods.py --mode all
```

---

**Ready to automate!** 🚀

The script will handle everything and provide a detailed summary at the end.




