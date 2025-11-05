# Quick Start Guide - BigQuery Peak Capacity Planning

**Goal**: Optimize slot allocation for Nov 2025 - Jan 2026 peak period

**Current Status**: Framework created, ready for data validation and configuration

---

## 🚀 Immediate Next Steps (30 minutes)

### Step 1: Validate Data Availability (5 minutes)

**Action**: Run the data completeness validation query

**Query**: `queries/utils/validate_audit_log_completeness.sql`

**How to Run**:
1. Open BigQuery console
2. Copy query from file
3. Click "Run" (or dry-run first to check cost)

**What to Check**:
- Are there any dates with `is_gap = TRUE`?
- Are there dates with `is_suspiciously_low = TRUE`?
- Is `pct_null_slot` or `pct_null_user` > 10%?
- Do all 3 peak periods have data?

**Expected Result**: Minimal gaps (<5%), null rates <10%, all peak periods covered

**If Issues Found**: Document specific gaps and adjust analysis approach accordingly

---

### Step 2: Identify Automated Service Accounts (15 minutes)

**Action**: Discover Airflow/Composer service accounts automatically

**Query**: `queries/utils/extract_airflow_service_accounts.sql`

**How to Run**:
1. Open BigQuery console
2. Adjust date range if needed (default: last 2 months)
3. Run query

**What to Look For**:
- Accounts with recommendation "✓ INCLUDE in Automated Process list"
- High automation_score (>20) accounts
- Account_classification = 'AIRFLOW_COMPOSER', 'CDP', 'ETL_DATAFLOW'

**Export Results**: Copy the list of service accounts for next step

---

### Step 3: Validate Metabase Format (5 minutes)

**Action**: Check Metabase query comment format

**Query**: `queries/utils/metabase_user_mapping.sql`

**Option A - Pattern Analysis** (Uncomment lines 94-125):
```sql
-- Shows which comment patterns are being used
-- Expected: High pct_with_user_id (>80%)
```

**Option B - Sample Queries** (Run main query):
```sql
-- Shows sample queries with extracted user IDs
-- Verify pattern_matched shows correct format
```

**What to Check**:
- Is `pattern_matched` showing successful extractions?
- Are user IDs being captured correctly?
- What percentage of Metabase queries have user IDs?

---

### Step 4: Configure Service Accounts (5 minutes)

**Action**: Update service account list in queries

**Files to Update** (use search & replace):

1. **Find** this block in each file:
```sql
DECLARE automated_service_accounts ARRAY<STRING> DEFAULT [
  'PLACEHOLDER_ACCOUNT@example.iam.gserviceaccount.com'
];
```

2. **Replace** with your actual service accounts from Step 2:
```sql
DECLARE automated_service_accounts ARRAY<STRING> DEFAULT [
  'airflow-prod@narvar-data-lake.iam.gserviceaccount.com',
  'composer-worker@project-id.iam.gserviceaccount.com',
  'cdp-sync@project-id.iam.gserviceaccount.com'
  -- Add more as needed
];
```

**Files to Update**:
- `queries/phase1_classification/automated_process_classification.sql`
- `queries/phase1_classification/vw_traffic_classification.sql`
- `queries/phase2_historical/peak_vs_nonpeak_analysis.sql`
- `queries/phase2_historical/qos_violations_historical.sql`
- `queries/phase2_historical/slot_heatmap_analysis.sql`
- `queries/phase2_historical/yoy_growth_analysis.sql`

**Pro Tip**: Use find/replace across all files in the `queries/` folder

---

## 🎯 Phase 1: Traffic Classification (1-2 hours)

### Run Classification Queries (Test with 1 Month First)

#### 1. External Consumers
**Query**: `queries/phase1_classification/external_consumer_classification.sql`

**Default Parameters** (lines 20-22):
```sql
DECLARE start_date DATE DEFAULT '2024-10-01';
DECLARE end_date DATE DEFAULT '2024-10-31';
```

**Expected Output**:
- Consumer category: EXTERNAL
- Subcategories: MONITOR, HUB, MONITOR_UNMATCHED
- Retailer attribution for monitor projects
- QoS metrics (60-second threshold)

**Validation Check**:
```sql
-- Run summary statistics (uncomment lines 182-218)
-- Should see breakdown by subcategory and retailer
```

---

#### 2. Automated Processes
**Query**: `queries/phase1_classification/automated_process_classification.sql`

**Prerequisites**: Service accounts configured (Step 4)

**Expected Output**:
- Consumer category: AUTOMATED
- Subcategories: AIRFLOW_COMPOSER, CDP, ETL_DATAFLOW, etc.
- Airflow DAG info (if labels present)
- Execution speed categories

**Validation Check**:
```sql
-- Run summary statistics (uncomment lines 192-229)
-- Should see breakdown by subcategory
-- Check success_rate_pct (should be >90% typically)
```

---

#### 3. Internal Users
**Query**: `queries/phase1_classification/internal_user_classification.sql`

**Expected Output**:
- Consumer category: INTERNAL
- Subcategories: METABASE, ADHOC_USER, INTERNAL_SERVICE_ACCOUNT
- Metabase user IDs (where available)
- QoS metrics (480-second threshold)

**Validation Check**:
```sql
-- Run summary statistics (uncomment lines 200-242)
-- Check qos_violation_pct by subcategory
```

---

#### 4. Unified Classification View (Master Query)
**Query**: `queries/phase1_classification/vw_traffic_classification.sql`

**Prerequisites**: All above queries validated, service accounts configured

**Expected Output**:
- ALL traffic classified into EXTERNAL, AUTOMATED, INTERNAL
- Combined QoS metrics
- Priority levels assigned
- Single source of truth for downstream analysis

**Critical Validation**:
```sql
-- Run summary statistics (uncomment lines 253-281)
-- Check classification coverage:
SELECT 
  consumer_category,
  COUNT(*) as jobs,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 2) as pct
FROM [results]
GROUP BY consumer_category;

-- Target: UNCLASSIFIED < 5%
```

**If UNCLASSIFIED > 5%**:
- Review unclassified records
- Add missing service accounts
- Refine classification logic

---

## 📊 Phase 2: Historical Analysis (2-4 hours)

### Prerequisites
- ✅ Phase 1 complete
- ✅ Classification validated (UNCLASSIFIED < 5%)
- ✅ Service accounts configured

### Run Analysis Queries (Full 3-Year History)

#### 1. Peak vs Non-Peak Comparison
**Query**: `queries/phase2_historical/peak_vs_nonpeak_analysis.sql`

**Parameters** (adjust for full analysis):
```sql
DECLARE analysis_start_date DATE DEFAULT '2022-04-19';
DECLARE analysis_end_date DATE DEFAULT CURRENT_DATE();
```

**Key Metrics to Review**:
- `avg_jobs_per_day` by period and category
- `avg_slot_hours_per_day` - capacity demand
- `qos_violation_pct` - quality issues
- Peak vs non-peak multipliers

**Expected Insights**:
- Peak period is X% higher than non-peak
- External category grows most during peaks
- Specific hour-of-day patterns

---

#### 2. QoS Violations Analysis
**Query**: `queries/phase2_historical/qos_violations_historical.sql`

**Key Metrics to Review**:
- `qos_violation_pct` by category and period
- `violation_severity` breakdown
- `avg_violation_seconds` - how bad are violations
- Slot starvation periods

**Expected Insights**:
- Which categories have most QoS issues
- When violations occur (specific dates/hours)
- Correlation with slot capacity (1,700 limit)

**Optional Analysis** (uncomment sections):
- Worst violation periods by hour
- Slot starvation analysis (demand > 1,700)

---

#### 3. Slot Utilization Heatmaps
**Query**: `queries/phase2_historical/slot_heatmap_analysis.sql`

**Parameters** (start with single peak):
```sql
DECLARE analysis_start_date DATE DEFAULT '2024-11-01';
DECLARE analysis_end_date DATE DEFAULT '2025-01-31';
```

**Output Format**: Ready for heatmap visualization

**Key Columns**:
- `hour_timestamp`, `date`, `hour`, `day_of_week`
- `external_slot_demand`, `automated_slot_demand`, `internal_slot_demand`
- `total_slot_demand`, `slot_deficit`
- `over_capacity` flag

**Visualization Tip**: Export to CSV and create heatmap in:
- Google Sheets (conditional formatting)
- Tableau/Looker
- Python (matplotlib/seaborn)

**Optional Analysis** (uncomment):
- Top 100 busiest minutes
- Concurrency heatmap

---

#### 4. Year-over-Year Growth
**Query**: `queries/phase2_historical/yoy_growth_analysis.sql`

**Key Metrics to Review**:
- `yoy_growth_2022_2023_pct`, `yoy_growth_2023_2024_pct`
- `avg_yoy_growth_pct` - baseline for 2025 projections
- `cagr_2_year_pct` - compound annual growth rate
- `projected_jobs_2025`, `projected_slot_hours_per_day_2025`

**Expected Insights**:
- Consistent growth rate vs volatile
- Which category is growing fastest
- Realistic 2025 peak projections

**Optional Analysis** (uncomment):
- Monthly trend analysis
- Anomaly detection

---

## 🎁 What You Get After Phase 1 & 2

### Deliverables
1. **Traffic Classification**: 95%+ of jobs categorized
2. **Historical Patterns**: 3 years of peak period analysis
3. **Growth Rates**: YoY growth by category for projections
4. **QoS Baseline**: Current quality of service metrics
5. **Capacity Insights**: Slot utilization patterns and bottlenecks

### Key Questions Answered
- ✅ What is the current traffic distribution? (External/Automated/Internal)
- ✅ How much does peak differ from non-peak? (multiplier)
- ✅ Where are QoS violations occurring? (when, which category)
- ✅ What is the growth trend? (for 2025 predictions)
- ✅ When do we hit slot capacity limits? (1,700 slot ceiling)

---

## ⏭️ Next Phases

### Phase 3: Prediction (Not Yet Created)
**Goal**: Forecast Nov 2025-Jan 2026 demand

**Approach**:
- Apply YoY growth rates to latest baseline
- Calculate expected slot demand by hour
- Predict QoS violations under current 1,700-slot capacity

### Phase 4: Simulation (Not Yet Created)
**Goal**: Test slot allocation strategies

**Scenarios to Evaluate**:
- A: Separate reservations by category
- B: Priority-based single reservation
- C: Hybrid approach
- D: Capacity increase options

### Phase 5: Documentation (Not Yet Created)
**Goal**: Create final PRD and implementation guide

**Outputs**:
- Comprehensive PRD with recommendations
- Technical implementation guide
- Simulation methodology documentation

---

## 📋 Checklist

### Data Validation
- [ ] Ran `validate_audit_log_completeness.sql`
- [ ] Confirmed data quality (gaps <5%, nulls <10%)
- [ ] All 3 peak periods have data

### Service Account Configuration
- [ ] Ran `extract_airflow_service_accounts.sql`
- [ ] Identified automated service accounts
- [ ] Updated all queries with service account list

### Metabase Validation
- [ ] Ran `metabase_user_mapping.sql`
- [ ] Confirmed user ID extraction works
- [ ] Documented Metabase comment format

### Phase 1: Classification
- [ ] Ran `external_consumer_classification.sql` (1 month test)
- [ ] Ran `automated_process_classification.sql` (1 month test)
- [ ] Ran `internal_user_classification.sql` (1 month test)
- [ ] Ran `vw_traffic_classification.sql` (1 month test)
- [ ] Validated UNCLASSIFIED < 5%

### Phase 2: Historical Analysis
- [ ] Ran `peak_vs_nonpeak_analysis.sql` (full 3 years)
- [ ] Ran `qos_violations_historical.sql` (full 3 years)
- [ ] Ran `slot_heatmap_analysis.sql` (single peak period)
- [ ] Ran `yoy_growth_analysis.sql` (full 3 years)
- [ ] Documented key insights

---

## 🆘 Troubleshooting

### Query Too Expensive
**Solution**: Use dry-run first, start with smaller date ranges
```sql
-- Test with 1 week first
DECLARE start_date DATE DEFAULT '2024-10-01';
DECLARE end_date DATE DEFAULT '2024-10-07';
```

### High UNCLASSIFIED Percentage
**Solution**: Review unclassified jobs, add missing patterns
```sql
-- Find common unclassified patterns
SELECT principal_email, project_id, COUNT(*) as cnt
FROM [vw_traffic_classification_results]
WHERE consumer_category = 'UNCLASSIFIED'
GROUP BY 1, 2
ORDER BY cnt DESC
LIMIT 20;
```

### Metabase User IDs Not Found
**Solution**: Check different comment patterns
```sql
-- Test all 3 patterns in metabase_user_mapping.sql
-- Adjust REGEXP if format is different
```

---

## 📞 Support

**Questions?**
- Review `README.md` for project overview
- Check `docs/IMPLEMENTATION_STATUS.md` for detailed status
- Consult `narvar/audit_log/QUERY_SUMMARY.md` for audit log patterns

**Need Help?**
- Data validation issues → Review validation query output
- Classification issues → Check service account configuration
- Query errors → Verify DECLARE parameters and date ranges




