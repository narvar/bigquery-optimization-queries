# AI Session Context - BigQuery Peak Capacity Planning

**Last Updated**: November 5, 2025  
**Current Phase**: Phase 1 Complete ✅ | Phase 2 Ready to Start 🚀  
**For**: Future AI assistants and collaborators

---

## 🎯 Project Goal

Optimize BigQuery slot allocation (currently 1,700 slots) for Nov 2025 - Jan 2026 peak period based on 3 years of historical traffic analysis for 2,600+ BigQuery projects.

---

## ✅ Phase 1: Traffic Classification - COMPLETE

### **What Was Accomplished**:
- **43.8M jobs classified** across 9 periods (Sep 2022 - Oct 2025)
- **Classification quality**: 0-4% unclassified (excellent!)
- **Physical table created**: `narvar-data-lake.query_opt.traffic_classification`
- **Automation scripts**: Python scripts for multi-period classification

### **Physical Table Details**:

**Table**: `narvar-data-lake.query_opt.traffic_classification`

**Schema**:
```sql
-- Metadata
classification_date DATE
analysis_start_date DATE  
analysis_end_date DATE
analysis_period_label STRING
classification_version STRING

-- Classification
consumer_category STRING       -- EXTERNAL, AUTOMATED, INTERNAL, UNCLASSIFIED
consumer_subcategory STRING    -- MONITOR, MONITOR_BASE, AIRFLOW_COMPOSER, METABASE, etc.
priority_level INT64          -- 1=P0 External, 2=P0 Automated, 3=P1 Internal

-- Attribution
retailer_moniker STRING       -- For monitor projects (207-565 per period)
metabase_user_id STRING       -- For Metabase queries

-- Metrics
job_id, project_id, principal_email, location
start_time, end_time, execution_time_seconds
total_slot_ms, approximate_slot_count, slot_hours
total_billed_bytes, estimated_slot_cost_usd
qos_status, is_qos_violation, qos_violation_seconds

-- Partitioned by: DATE(start_time)
-- Clustered by: consumer_category, classification_date
```

**How to Query Latest Classifications**:
```sql
-- Get latest classification for each period
SELECT *
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE (analysis_period_label, classification_version) IN (
  SELECT analysis_period_label, MAX(classification_version)
  FROM `narvar-data-lake.query_opt.traffic_classification`
  GROUP BY analysis_period_label
)
```

### **Periods Available** (9 periods, 21 months):

**2025**:
- Baseline_2025_Sep_Oct (v1.3) - 4.47M jobs, 0.04% unclassified ⭐ Most recent!

**2024**:
- Baseline_2024_Sep_Oct (v1.0) - 3.79M jobs, 4.0% unclassified
- Peak_2024_2025 (v1.0) - 4.72M jobs, 2.7% unclassified
- NonPeak_2024_Feb_Mar (v1.0) - 1.86M jobs, 1.2% unclassified

**2023**:
- Peak_2023_2024 (v1.0) - 3.29M jobs, 0.07% unclassified
- NonPeak_2023_Sep_Oct (v1.0) - 1.88M jobs, 0.02% unclassified  
- NonPeak_2023_Feb_Mar (v1.2) - 5.02M jobs, 0.00% unclassified

**2022**:
- Peak_2022_2023 (v1.2) - 11.34M jobs, 0.00% unclassified
- NonPeak_2022_Sep_Oct (v1.2) - 7.46M jobs, 0.00% unclassified

---

## 🚨 Critical Findings from Phase 1

### **1. MONITOR_BASE Dominates Capacity** (Single Largest Consumer!)
- **8.74M slot-hours** (85.85% of ALL external capacity)
- Shared infrastructure serving all retailers
- Correctly classified as EXTERNAL (P0) but should be tracked separately
- Optimization opportunity: batch scheduling, off-peak execution

### **2. Peak Multipliers by Category**:
```
EXTERNAL:  1.97x (peak is nearly 2x non-peak)
AUTOMATED: 1.63x (more stable)
INTERNAL:  1.67x (moderate growth)
```
**Implication**: External capacity needs ~2x buffer for peak periods

### **3. External Traffic is Slot-Intensive**:
- Only 20-30% of jobs but 40% of slot consumption
- Average: 1.2-1.5 slot-hours per job (vs 0.2-0.3 for automated)
- Category mix matters more than job volume for capacity planning!

### **4. 2022 Data Anomaly** ⚠️:
- 2022 periods show 3-11x higher job counts than 2023-2024
- Likely: data collection changes, classification differences, or noflake retirement
- **Action**: Phase 2 must investigate before using 2022 for projections
- **Reliable growth**: Use 2023-2024 → 2024-2025 trends (+46-125%)

### **5. Classification Pattern Evolution**:
- **v1.0**: Current services (2023-2024 periods) - messaging, airflow, metabase, etc.
- **v1.2**: Added retired services (2022-2023 periods) - noflake, salesforce, fivetran
- **v1.3**: Added 2025 ML services - dev-testing@narvar-ml (679K jobs!), vertex-pipeline, promise-ai

**Total**: 35+ service account patterns spanning 2022-2025

---

## 🔧 How to Classify New Periods

### **Using Automation Script**:

**Location**: `scripts/run_classification_all_periods.py`

**Add New Period**:
```python
{
    "label": "Peak_2025_2026",  # Or any label
    "start_date": "2025-11-01",
    "end_date": "2026-01-31",
    "type": "peak",
    "priority": 1,
    "skip": False,
    "description": "Current peak - target planning period"
}
```

**Run**:
```bash
cd scripts/
python run_classification_all_periods.py --mode all
```

**Deduplication** (if needed):
```bash
python deduplicate_classification_table.py --execute
```

---

## 📊 Traffic Classification Categories

### **EXTERNAL (P0)** - Customer-facing:
- **MONITOR**: Individual retailer projects (207-565 retailers per period)
- **MONITOR_BASE**: Shared infrastructure (85% of external capacity!) 🚨
- **MONITOR_UNMATCHED**: Retailer data missing in t_return_details (~34% of monitor projects)
- **HUB**: Looker dashboards

### **AUTOMATED (P0)** - Scheduled processes:
- **AIRFLOW_COMPOSER**: Data pipelines (slot-intensive)
- **GKE_WORKLOAD**: Kubernetes workloads (high volume)
- **COMPUTE_ENGINE**: GCE service accounts (highest job count)
- **MESSAGING**: Internal messaging service (157K jobs/period)
- **ANALYTICS_API**: Backend API service
- **ML_INFERENCE**, **CDP**, **ETL_DATAFLOW**, etc.
- **Historical**: NOFLAKE_RETIRED (2022-2023 only)
- **2025 New**: ML_DEV_TESTING, VERTEX_PIPELINE, PROMISE_AI

### **INTERNAL (P1)** - Employee analytics:
- **METABASE**: Business intelligence (92% of internal)
- **ADHOC_USER**: Employee ad-hoc queries (@narvar.com)
- **N8N_WORKFLOW**: Internal automation

---

## 🎯 QoS Thresholds

```
EXTERNAL:  60 seconds (1 minute) - customer-facing SLA
INTERNAL:  480 seconds (8 minutes) - internal analytics
AUTOMATED: Requires schedule data (not currently available)
```

**Current QoS Performance** (Excellent):
- EXTERNAL: 97%+ meeting SLAs
- INTERNAL: 98%+ meeting SLAs

---

## 💰 Cost Model

**Slot-based pricing** (reserved capacity):
- 500 slots @ 1-year commitment: $0.048/slot-hour
- 500 slots @ 3-year commitment: $0.036/slot-hour
- 700 slots @ on-demand enterprise: $0.060/slot-hour
- **Blended rate**: $0.0494/slot-hour

**Historical costs**:
- Average: ~$41K/month
- Peak months: ~$46K/month
- Non-peak months: ~$36K/month

---

## 🔍 Known Data Quality Issues

### **1. Null Slot Jobs** (Handled):
- 46% of query jobs have null totalSlotMs
- Only 6% of execution time (minimal impact)
- **Solution**: Filter `WHERE totalSlotMs IS NOT NULL`
- Captures 94% of execution time and 99.94% of bytes processed

### **2. Monitor Retailer Matching** (Accepted Limitation):
- Uses MD5-based matching: `monitor-{MD5_7char}-us-{env}`
- Match rate: ~34% excluding monitor-base (limited by t_return_details data availability)
- 207-565 retailers matched per period (sufficient for analysis)
- **monitor-base projects**: Cannot match (shared infrastructure)

### **3. 2022 Data Volume Anomaly** (Needs Investigation in Phase 2):
- 2022 periods show 3-11x higher job counts than 2023-2024
- Possibly: noflake services (retired in 2023), data collection changes, or actual traffic
- **Use 2023-2024 → 2024-2025 growth for reliable projections**

---

## 📁 File Structure Reference

### **SQL Queries**:
```
queries/
├── phase1_classification/
│   ├── vw_traffic_classification_to_table.sql  ← MAIN PRODUCTION QUERY
│   ├── external_consumer_classification.sql
│   ├── automated_process_classification.sql
│   └── internal_user_classification.sql
├── phase2_historical/
│   ├── peak_vs_nonpeak_analysis.sql  ← NEEDS UPDATE for physical table
│   ├── qos_violations_historical.sql  ← NEEDS UPDATE
│   ├── slot_heatmap_analysis.sql      ← NEEDS UPDATE
│   └── yoy_growth_analysis.sql        ← NEEDS UPDATE
└── utils/
    ├── validate_audit_log_completeness.sql
    └── classification_diagnostics.sql
```

### **Python Scripts**:
```
scripts/
├── run_classification_all_periods.py       ← Multi-period automation
├── deduplicate_classification_table.py     ← Remove duplicate versions
└── requirements.txt                         ← google-cloud-bigquery>=3.10.0
```

### **Documentation**:
```
├── README.md                        ← Project overview
├── PHASE1_FINAL_REPORT.md          ← Complete Phase 1 results ⭐
├── AI_SESSION_CONTEXT.md           ← THIS FILE (for AI assistants)
└── docs/
    ├── CLASSIFICATION_STRATEGY.md  ← Temporal variability strategy
    └── IMPLEMENTATION_STATUS.md     ← Implementation checklist
```

---

## 🚀 Phase 2: Next Steps

### **What Needs to Be Done**:

**1. Update Phase 2 Queries** to use `traffic_classification` table instead of inline classification:
- Replace inline WITH clauses with: `FROM \`narvar-data-lake.query_opt.traffic_classification\``
- Add period filtering: `WHERE analysis_period_label IN ('Peak_2024_2025', ...)`
- Use latest versions only

**2. Run Phase 2 Analysis**:
- Peak vs. non-peak comparison
- QoS violations analysis  
- Slot utilization heatmaps
- Year-over-year growth (investigate 2022 anomaly)

**3. Investigate Critical Findings**:
- monitor-base optimization opportunities
- 2022 data quality issue
- Category-specific capacity patterns

### **Phase 2 Query Pattern** (Example):
```sql
-- Old approach: Inline classification (slow, expensive)
WITH audit_data AS (
  SELECT ... FROM cloudaudit_googleapis_com_data_access
  -- Complex classification logic repeated
)

-- New approach: Use pre-classified table (fast, cheap)
SELECT
  analysis_period_label,
  consumer_category,
  COUNT(*) as jobs,
  SUM(slot_hours) as slot_hours
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE analysis_period_label LIKE 'Peak%'
GROUP BY analysis_period_label, consumer_category;
```

---

## 🎓 Key Design Decisions (For Context)

### **Why Physical Table Instead of Views?**
- 9 periods × 8-15 min each = expensive to recreate
- Phase 2-4 queries need same classification multiple times
- Cost savings: $0.01-0.10 per query vs $3-5 for reclassification

### **Why Multiple Versions (v1.0, v1.2, v1.3)?**
- Services retire over time (noflake 2022-2023)
- Services launch over time (dev-testing@narvar-ml in 2025)
- Version tracking allows pattern improvement without losing history
- Each period uses best available version

### **Why Regex Patterns Instead of Service Account Arrays?**
- No manual configuration needed
- Patterns discovered from actual data
- Easy to extend (just add pattern)
- Achieved 0-4% unclassified with 35+ patterns

### **Why MD5 Matching for Monitor Projects?**
- Actual naming convention: `monitor-{MD5_7char}-us-{env}`
- Token matching achieved 0% success
- MD5 matching achieves ~34% success (limited by t_return_details completeness)

### **Why Null-Tolerant (totalSlotMs IS NOT NULL)?**
- 46% of query jobs have null slots
- But only 6% of execution time (cache hits, metadata queries)
- Including nulls would distort capacity planning
- Decision: Focus on measurable capacity consumption

---

## 📊 Quick Stats (For Reference)

**Table Size**: 43.8M rows, 20-22 GB  
**Coverage**: 21 months (Sep 2022 - Oct 2025)  
**Periods**: 9 (3 peak, 6 non-peak)  
**Cost**: $866K historical (21 months)  
**Avg Monthly Cost**: ~$41K  

**Category Distribution**:
- EXTERNAL: 20-30% jobs, 40% slots (slot-intensive!)
- AUTOMATED: 55-75% jobs, 45% slots
- INTERNAL: 10-15% jobs, 15% slots

**Peak Multipliers**:
- EXTERNAL: 1.97x
- AUTOMATED: 1.63x
- INTERNAL: 1.67x

**Critical Consumer**: MONITOR_BASE (85% of external capacity!)

---

## ⚠️ Critical Issues to Address in Phase 2

1. **2022 Data Anomaly**: 3-11x higher volumes than 2023-2024 (investigate before using for projections)
2. **MONITOR_BASE Optimization**: 8.74M slot-hours - single largest consumer (batch scheduling opportunity?)
3. **Reliable Growth Trend**: Use 2023-2024 → 2024-2025 (+46-125% slot growth)
4. **2025 Baseline**: Sep-Oct 2025 is freshest data for upcoming peak planning

---

## 🔧 Common Queries for Future Work

### **Peak vs. Non-Peak by Category**:
```sql
SELECT
  CASE WHEN analysis_period_label LIKE 'Peak%' THEN 'PEAK' ELSE 'NON_PEAK' END AS type,
  consumer_category,
  AVG(slot_hours) as avg_slot_hours
FROM `narvar-data-lake.query_opt.traffic_classification`
GROUP BY type, consumer_category;
```

### **Year-over-Year Growth**:
```sql
SELECT
  EXTRACT(YEAR FROM analysis_start_date) AS year,
  consumer_category,
  SUM(slot_hours) as slot_hours
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE analysis_period_label LIKE 'Peak%'
GROUP BY year, consumer_category;
```

### **Top Slot Consumers**:
```sql
SELECT
  consumer_subcategory,
  SUM(slot_hours) as total_slot_hours,
  COUNT(*) as jobs,
  AVG(slot_hours) as avg_slot_hours_per_job
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE analysis_period_label = 'Peak_2024_2025'
GROUP BY consumer_subcategory
ORDER BY total_slot_hours DESC;
```

---

## 🎯 Phase 2-4 Roadmap

### **Phase 2: Historical Analysis** (Next)
**Goal**: Understand historical patterns to inform predictions

**Queries to Update** (4 queries need modification to use physical table):
1. `peak_vs_nonpeak_analysis.sql` - Peak multipliers, patterns
2. `qos_violations_historical.sql` - QoS issues, slot starvation
3. `slot_heatmap_analysis.sql` - Hour-by-hour demand patterns
4. `yoy_growth_analysis.sql` - Growth rates, CAGR

**Expected Runtime**: 1-2 days (queries are fast with pre-classified table)

### **Phase 3: Prediction** (Not Started)
**Goal**: Forecast Nov 2025 - Jan 2026 peak demand

**Approach**:
- Apply growth rates from 2023-2024 → 2024-2025
- Use 2025 baseline as starting point
- Calculate expected slot demand by hour/category
- Predict QoS violations under current 1,700-slot capacity

### **Phase 4: Simulation** (Not Started)
**Goal**: Test slot allocation strategies

**Scenarios**:
- A: Separate reservations by category (3 reservations)
- B: Priority-based single reservation (1 reservation with priorities)
- C: Hybrid (dedicated for external + shared for others)
- D: Capacity increase (evaluate 500/1000/1500 additional slots)

---

## 📖 Additional Documentation

**Comprehensive Reports**:
- `PHASE1_FINAL_REPORT.md` - Complete Phase 1 results and findings
- `docs/CLASSIFICATION_STRATEGY.md` - Temporal variability handling

**Archived Docs** (Historical Reference):
- `docs/archive/PERIOD_COVERAGE_PLAN.md` - Original planning doc
- `docs/archive/PHASE1_COMPLETION_SUMMARY.md` - Interim summary
- `docs/archive/PHASE1_IMPROVEMENTS.md` - Issue fixes applied

---

## 🔑 Key Takeaways for Future Sessions

1. **Use the physical table** - Don't reclassify, query `traffic_classification`
2. **Latest baseline is Sep-Oct 2025** - Use for 2025-2026 peak planning
3. **monitor-base is critical** - 85% of external capacity, track separately
4. **Don't use 2022 data alone** - Investigate anomaly first
5. **External ~2x peak multiplier** - Capacity planning needs this buffer
6. **Pattern library is comprehensive** - 35+ patterns, covers 2022-2025

---

**For detailed Phase 1 results, see**: `PHASE1_FINAL_REPORT.md`

**For classification strategy and temporal handling, see**: `docs/CLASSIFICATION_STRATEGY.md`

