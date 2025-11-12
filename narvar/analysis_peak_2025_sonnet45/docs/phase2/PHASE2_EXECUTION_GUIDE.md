# Phase 2 Execution Guide

**Date**: November 5, 2025  
**Status**: Ready to Execute  
**Estimated Time**: 4-6 hours total

---

## 📋 Overview

This guide walks you through executing Phase 2 historical capacity analysis, which includes:
1. Running 4 BigQuery analysis queries (~35-60 minutes)
2. Analyzing results in Jupyter notebook (~2-3 hours)
3. Generating visualizations and insights (~1-2 hours)

---

## 🚀 Quick Start

### Prerequisites
- ✅ Phase 1 complete (`traffic_classification` table exists)
- ✅ BigQuery access to `narvar-data-lake` project
- ✅ `bq` CLI installed and authenticated
- ✅ Python 3.8+ with Jupyter
- ✅ Required Python packages: pandas, matplotlib, seaborn, plotly, google-cloud-bigquery

### Installation
```bash
cd narvar/analysis_peak_2025_sonnet45
pip install -r scripts/requirements.txt  # If not already installed
```

---

## 📊 Step 1: Execute Phase 2 Queries

### Option A: Automated Execution (Recommended)

Run all 4 queries sequentially using the provided script:

```bash
cd scripts/
./run_phase2_queries.sh
```

**What this does**:
1. Validates queries with dry-run (optional)
2. Executes all 4 queries sequentially
3. Saves results to BigQuery tables:
   - `narvar-data-lake.query_opt.phase2_stress_periods`
   - `narvar-data-lake.query_opt.phase2_external_qos`
   - `narvar-data-lake.query_opt.phase2_monitor_base`
   - `narvar-data-lake.query_opt.phase2_peak_patterns`
4. Logs execution details to timestamped log file

**Estimated runtime**: 35-60 minutes  
**Estimated cost**: $0.13-$0.35 USD (~26-70GB scanned)

### Option B: Manual Execution

Run queries individually in BigQuery Console for more control:

#### Query 1: Identify Capacity Stress Periods
```bash
bq query --use_legacy_sql=false \
  --destination_table=narvar-data-lake:query_opt.phase2_stress_periods \
  --replace \
  < queries/phase2_historical/identify_capacity_stress_periods.sql
```

**Details**:
- **Purpose**: Detect INFO/WARNING/CRITICAL stress states using 10-minute windows
- **Runtime**: 15-30 minutes
- **Data processed**: 10-30GB
- **Output**: Timeline with stress classifications

#### Query 2: External Customer QoS Under Stress
```bash
bq query --use_legacy_sql=false \
  --destination_table=narvar-data-lake:query_opt.phase2_external_qos \
  --replace \
  < queries/phase2_historical/external_qos_under_stress.sql
```

**Details**:
- **Purpose**: Analyze customer QoS degradation during stress
- **Runtime**: 5-10 minutes
- **Data processed**: 5-15GB
- **Output**: QoS metrics by stress state

#### Query 3: Monitor-Base Stress Analysis
```bash
bq query --use_legacy_sql=false \
  --destination_table=narvar-data-lake:query_opt.phase2_monitor_base \
  --replace \
  < queries/phase2_historical/monitor_base_stress_analysis.sql
```

**Details**:
- **Purpose**: Test if monitor-base CAUSES customer stress
- **Runtime**: 10-15 minutes
- **Data processed**: 10-20GB
- **Output**: Two-part analysis (QoS + causation)

#### Query 4: Peak vs Non-Peak Analysis
⚠️ **Special Note**: This query has 5 SELECT statements. `bq` CLI only captures the last output.

**Recommendation**: Run in BigQuery Console to capture all 5 outputs manually.

```bash
# If using bq CLI (captures only last output):
bq query --use_legacy_sql=false \
  --destination_table=narvar-data-lake:query_opt.phase2_peak_patterns \
  --replace \
  < queries/phase2_historical/peak_vs_nonpeak_analysis_v2.sql
```

**Details**:
- **Purpose**: Overall traffic patterns (peak multipliers, hourly trends, YoY growth)
- **Runtime**: 2-5 minutes
- **Data processed**: 1-5GB
- **Outputs**: 5 result sets (run in Console for complete capture)

---

## 📓 Step 2: Run Jupyter Notebook Analysis

### Launch Notebook

```bash
cd notebooks/
jupyter notebook phase2_analysis.ipynb
```

### Notebook Structure

The notebook has **32 cells** organized into 7 major sections:

#### **Section 1: Setup & Configuration** (Cells 1-5)
- Import libraries
- Configure BigQuery client
- Set visualization themes

#### **Section 2: Data Import** (Cells 6-9)
- Load stress period data
- Load external QoS data
- Load monitor-base analysis data
- Validate data quality

#### **Section 3: Analysis 1 - Capacity Stress Detection** (Cells 10-14)
- Calculate stress state distribution
- Create stress timeline visualizations
- Generate time-of-day heatmaps
- Identify stress events

#### **Section 4: Analysis 2 - Customer QoS Impact** (Cells 15-18)
- QoS violation rates by stress state
- Execution time degradation analysis
- Customer impact quantification

#### **Section 5: Analysis 3 - Monitor-Base Causation** (Cells 19-22)
- Monitor-base QoS performance
- Time-of-day overlap analysis
- Causation hypothesis testing

#### **Section 6: Key Findings & Recommendations** (Cells 23-26)
- Critical findings summary
- Capacity recommendations
- Phase 3 inputs preparation

#### **Section 7: Export Results** (Cells 27-32)
- Save all visualizations
- Export summary metrics to CSV
- Generate Phase 3 input file

### Running the Notebook

**Option A: Run All Cells**
```
Cell → Run All
```

**Option B: Step Through**
- Recommended for first run
- Execute cells sequentially
- Review outputs and visualizations
- Adjust parameters as needed

### Expected Outputs

**Visualizations** (saved to `images/`):
- `stress_state_distribution.png` - Stacked bar chart of stress time %
- `stress_timeline_Peak_2024_2025.html` - Interactive timeline (Plotly)
- `customer_qos_by_stress_state.png` - QoS violation rates and P95 times
- `monitor_base_causation.png` - Causation test results

**Data Exports** (saved to `results/`):
- `stress_state_summary.csv` - % time in each stress state
- `customer_qos_summary.csv` - QoS metrics by stress state
- `monitor_base_qos_summary.csv` - Monitor-base performance
- `phase3_inputs.json` - **Key metrics for Phase 3 projection**

---

## 📈 Step 3: Interpret Key Findings

### Critical Questions Answered

#### 1. How often does capacity stress occur?

Look for:
- **WARNING state %** - Moderate stress frequency
- **CRITICAL state %** - Severe stress frequency
- **Total stress time** - WARNING + CRITICAL combined

**Example**:
```
WARNING: 8.2% of time
CRITICAL: 2.4% of time
Total stress: 10.6% of time
```

**Interpretation**: System under stress ~10% of time. Need buffer to reduce this.

---

#### 2. What happens to customer QoS during stress?

Look for:
- **Baseline violation rate** (NORMAL state)
- **CRITICAL violation rate**
- **Violation increase factor**

**Example**:
```
NORMAL: 2.3% violations
CRITICAL: 18.7% violations
Increase: 8.1x
```

**Interpretation**: Customer QoS degrades 8x during CRITICAL stress. Unacceptable.

---

#### 3. Does monitor-base CAUSE customer stress?

Look for:
- **Violation ratio** (HIGH vs LOW monitor-base activity)
- **Hypothesis test result**

**Example**:
```
Customer violations when monitor-base is LOW: 2.8%
Customer violations when monitor-base is HIGH: 7.4%
Ratio: 2.6x
Result: HYPOTHESIS SUPPORTED
```

**Interpretation**: Monitor-base activity correlates with customer stress. Consider separate reservation.

---

#### 4. How much additional capacity is needed?

Look for:
- **Capacity buffer needed %** (from stress frequency)
- **Peak multipliers** (from Query 4 results)

**Example**:
```
Buffer needed: ~11% to eliminate stress
Peak multiplier: 1.97x (EXTERNAL category)
```

**Interpretation**: Need +11% baseline capacity, +97% during peak periods for EXTERNAL.

---

## 🎯 Step 4: Prepare Phase 3 Inputs

The notebook automatically generates `results/phase3_inputs.json` with:

```json
{
  "baseline_period": "Baseline_2025_Sep_Oct",
  "stress_metrics": {
    "warning_pct": 8.2,
    "critical_pct": 2.4,
    "total_stress_pct": 10.6
  },
  "qos_metrics": {
    "baseline_violation_pct": 2.3,
    "critical_violation_pct": 18.7,
    "violation_increase_factor": 8.1
  },
  "monitor_base_causation": {
    "hypothesis_supported": true,
    "violation_ratio": 2.6
  },
  "recommendations": {
    "separate_monitor_base_reservation": true,
    "capacity_buffer_needed_pct": 10.6
  }
}
```

**Use this file as input for Phase 3 projection modeling.**

---

## 🔍 Troubleshooting

### Query Execution Issues

**Problem**: Query times out
```
Solution: Queries are designed for large datasets. Expected 15-30 min for Query 1.
If timeout persists, check BigQuery quotas.
```

**Problem**: "Table not found" error
```
Solution: Verify Phase 1 traffic_classification table exists:
  bq show narvar-data-lake:query_opt.traffic_classification
```

**Problem**: Query 4 only captures last output
```
Solution: This is expected with bq CLI. Run Query 4 in BigQuery Console
to manually save all 5 outputs to separate tables.
```

### Notebook Issues

**Problem**: "Table not found" when loading data
```
Solution: Ensure all 4 queries completed successfully and destination tables exist:
  bq ls narvar-data-lake:query_opt | grep phase2
```

**Problem**: Import errors (pandas, plotly, etc.)
```
Solution: Install required packages:
  pip install pandas matplotlib seaborn plotly google-cloud-bigquery
```

**Problem**: Empty dataframes in notebook
```
Solution: Check query results have data:
  bq head -n 10 narvar-data-lake:query_opt.phase2_stress_periods
```

---

## 📚 Additional Resources

### Query Documentation
- `queries/phase2_historical/identify_capacity_stress_periods.sql` - Detailed comments
- `PHASE2_SCOPE.md` - Complete analysis approach and methodology

### Phase 1 Reference
- `PHASE1_FINAL_REPORT.md` - Complete Phase 1 results and findings
- `AI_SESSION_CONTEXT.md` - Quick reference for classification details

### Next Phase
- Phase 3 will use `results/phase3_inputs.json` for demand forecasting
- Expected to build upon stress analysis with growth projections

---

## ✅ Success Criteria

Phase 2 is complete when you have:

- [x] All 4 queries executed successfully
- [x] Result tables created in BigQuery
- [x] Notebook analysis run end-to-end
- [x] Visualizations generated and saved
- [x] Summary metrics exported to CSV
- [x] Phase 3 inputs file created
- [x] Key findings documented

---

## 🚀 What's Next?

### Immediate Actions:
1. **Review findings** with stakeholders
2. **Document critical insights** in project docs
3. **Prepare Phase 3 kickoff**

### Phase 3 Preview:
- **Goal**: Forecast Nov 2025-Jan 2026 peak demand
- **Inputs**: Phase 2 stress metrics + growth rates + 2025 baseline
- **Outputs**: Projected capacity requirements by scenario
- **Timeline**: 2-3 days

---

**Questions or issues?** Check:
- Query comments in SQL files
- Notebook markdown cells
- `PHASE2_SCOPE.md` for detailed methodology

**Good luck with your analysis!** 🎉

