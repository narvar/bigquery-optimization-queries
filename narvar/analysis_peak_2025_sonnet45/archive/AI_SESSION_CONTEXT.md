# AI Session Context - BigQuery Peak Capacity Planning

**Last Updated**: November 12, 2025  
**Current Phase**: Phase 1 ✅ | Phase 2 ✅ | Next: Monitor/Hub Deep Dive 🎯  
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

## 📁 File Structure Reference (Updated Nov 12, 2025)

### **Root Folder** (Essential Docs Only - 6 files):
```
├── README.md                                    ← Project overview
├── AI_SESSION_CONTEXT.md                        ← THIS FILE (for AI assistants)
├── PHASE1_FINAL_REPORT.md                       ← Complete Phase 1 results
├── PEAK_2025_2026_STRATEGY_EXEC_REPORT.md      ← Executive recommendation
├── ROOT_CAUSE_ANALYSIS_FINDINGS.md             ← Root cause technical deep dive
└── INV6_HUB_QOS_RESULTS.md                     ← Hub QoS crisis analysis ⭐ NEXT PRIORITY
```

### **SQL Queries**:
```
queries/
├── phase1_classification/
│   ├── vw_traffic_classification_to_table.sql  ← MAIN PRODUCTION QUERY
│   └── (3 other classification queries)
├── phase2_historical/
│   ├── identify_capacity_stress_periods.sql    ← ✅ Stress detection
│   ├── external_qos_under_stress.sql           ← ✅ Customer QoS during stress
│   ├── monitor_base_stress_analysis.sql        ← ✅ Infrastructure analysis
│   └── peak_vs_nonpeak_analysis_v2.sql         ← ✅ Overall patterns
└── utils/
    └── (validation and diagnostic queries)
```

### **Python Scripts**:
```
scripts/
├── run_classification_all_periods.py       ← Multi-period automation
├── deduplicate_classification_table.py     ← Remove duplicate versions
└── requirements.txt
```

### **Documentation**:
```
docs/
├── phase1/archive/          ← Phase 1 interim docs
├── phase2/
│   ├── investigations/      ← INV2, INV3 (reservation, mapping quality)
│   ├── cost_analysis/       ← Cost summaries
│   ├── archive/             ← Phase 2 status/process docs
│   └── PHASE2_SCOPE.md      ← Phase 2 scope definition
├── reference/               ← Cost explanations, reservation guides
└── CLASSIFICATION_STRATEGY.md
```

### **Results & Data**:
```
results/
├── phase3_inputs.json                          ← Prepared for Phase 3
├── stress_state_summary.csv                    ← Stress analysis results
├── customer_qos_summary.csv                    ← QoS metrics
├── monitor_base_qos_summary.csv                ← Infrastructure QoS
├── baseline_2025_monitor_projects_FINAL.csv    ← All monitor projects
└── (root cause analysis results)

images/         ← For visualizations (upcoming)
notebooks/      ← For Jupyter analysis (upcoming)
logs/           ← Execution logs
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

## ✅ Phase 2: Historical Analysis - COMPLETE

### **What Was Accomplished**:
- **Root cause analysis of 129 critical incidents** (2025 data)
- **Stress period identification** using production monitoring thresholds
- **QoS impact assessment** during capacity stress
- **Executive strategic report** created and approved

### **Key Findings**:

**1. Root Cause Distribution** (2025 Data - 129 Critical Incidents):
- **69% AUTOMATED** (inefficient pipelines, not human error!)
- **23% INTERNAL** (growing concern - up from 12% historically)
- **8% EXTERNAL** (minimal customer load issues)

**2. Hub QoS Crisis** 🚨:
- **39.4% violation rate** during Peak_2024_2025 CRITICAL stress
- vs. 8.5% for MONITOR (retailer queries)
- **44x slower execution** (P95: 1,521s vs 34s)
- **Urgent optimization needed before next peak**

**3. Reservation Impact** (Critical Discovery):
- **Three reservation types** found: RESERVED_SHARED_POOL, RESERVED_PIPELINE, ON_DEMAND
- **Shared pool causes QoS degradation**: 49.6% violations vs 1.5% on on-demand during CRITICAL
- **ON_DEMAND dominated Peak_2024_2025**: 56.75% of capacity (massive cost!)

**4. Monitor-base Reclassification**:
- Moved from EXTERNAL → AUTOMATED (correct - it's batch infrastructure)
- **New capacity split**: EXTERNAL 6%, AUTOMATED 79%, INTERNAL 15%

**5. Strategic Decision**:
- **Monitoring-based approach** recommended (not pre-loading capacity)
- **Cost avoidance**: $58K-$173K
- **Focus**: Process optimization + automated controls

### **Deliverables Created**:
- `PEAK_2025_2026_STRATEGY_EXEC_REPORT.md` - Executive recommendation
- `ROOT_CAUSE_ANALYSIS_FINDINGS.md` - Technical deep dive  
- `INV6_HUB_QOS_RESULTS.md` - Hub performance crisis analysis
- `docs/phase2/investigations/` - Supporting investigation files
- `results/phase3_inputs.json` - Data for Phase 3 projections

---

## 🎯 Next Priority: Monitor & Hub Consumer Analysis

### **Objective**:
Understand **individual consumer behavior, costs, and QoS patterns** for:
- **Monitor Projects** (per-retailer performance profiles)
- **Hub** (dashboard-level analysis, identify 39% violation causes)

**NOT a comparative study** - separate deep dives into each consumer type.

### **Analysis 1: Monitor Project Performance Profiles**

**Questions to Answer**:
1. Who does the most work? (top 20 retailers by job volume, slot consumption)
2. Costs per retailer (slot-hours, estimated cost, trends over time)
3. Type of activity (query patterns, execution time distribution, usage frequency)
4. QoS issues per retailer (which retailers have highest violation rates?)

**Deliverable**: Per-retailer performance dashboard with:
- Cost ranking
- QoS compliance scores
- Usage patterns (time-of-day, frequency)
- Optimization targets (expensive + poor QoS retailers)

### **Analysis 2: Hub Dashboard Deep Dive** 🚨

**Critical Issue**: 39.4% violation rate during Peak_2024_2025 CRITICAL stress

**Questions to Answer**:
1. Which specific queries/dashboards violate SLA? (query patterns, dashboard IDs if available)
2. Who is using Hub? (concurrent users, usage frequency, auto-refresh patterns)
3. What drives the costs? (slot consumption by query type, data volume scanned)
4. QoS pattern analysis (when violations occur, correlation with stress, time patterns)
5. **Why 44x slower than Monitor?** (query complexity, joins, aggregations)

**Deliverable**: Hub optimization recommendations:
- Top 10 slowest queries to optimize
- Dashboard governance recommendations
- Potential separate reservation need
- Expected QoS improvement from optimizations

### **Tools Needed**:
- SQL queries for per-consumer analysis
- Jupyter notebook with visualizations
- Images saved to `/images` folder
- Analysis markdown with findings

**Estimated Duration**: 1-2 days

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

## 🎯 Project Roadmap

### **Phase 1: Traffic Classification** ✅ COMPLETE
- 43.8M jobs classified across 9 periods
- 35+ service account patterns
- Production table created

### **Phase 2: Historical Analysis** ✅ COMPLETE
- Root cause analysis (129 incidents)
- Stress period identification
- Executive strategic report
- **Decision**: Monitoring-based approach (not pre-loading capacity)

### **Current: Monitor & Hub Consumer Analysis** 🎯 IN PROGRESS
**Goal**: Deep dive into individual consumer performance

**Focus Areas**:
1. Per-retailer monitor performance profiles
2. Hub dashboard optimization (39% violation rate - critical!)
3. Cost and usage pattern analysis
4. QoS issue identification by consumer

**Estimated Duration**: 1-2 days

### **Phase 3: Prediction & Forecasting** (Future)
**Goal**: Forecast Nov 2025 - Jan 2026 peak demand (if needed)

**Note**: May be deferred based on monitoring-first strategy  
**Inputs**: Already prepared in `results/phase3_inputs.json`

### **Phase 4: Optimization & Governance** (Future)
**Goal**: Implement findings

**Focus**:
- Hub dashboard optimization (critical!)
- Retailer query governance
- Capacity monitoring enhancements

---

## 📖 Key Documentation by Topic

**Strategic & Executive**:
- `PEAK_2025_2026_STRATEGY_EXEC_REPORT.md` - Executive recommendation (monitoring-based approach)
- `ROOT_CAUSE_ANALYSIS_FINDINGS.md` - 129 incidents analyzed (69% automated, 23% internal, 8% external)

**Phase Reports**:
- `PHASE1_FINAL_REPORT.md` - Classification framework (43.8M jobs, 9 periods)
- Phase 2 report incorporated into executive summary above

**Critical Issues**:
- `INV6_HUB_QOS_RESULTS.md` - Hub 39% violation crisis (NEXT PRIORITY)
- `docs/phase2/investigations/INV2_RESERVATION_IMPACT_RESULTS.md` - Shared pool bottleneck
- `docs/phase2/investigations/INV3_MAPPING_QUALITY_RESULTS.md` - Retailer mapping quality

**Reference**:
- `docs/CLASSIFICATION_STRATEGY.md` - Temporal variability approach
- `docs/reference/` - Cost models, reservation types, guides

**Archived**:
- `docs/phase1/archive/` - Phase 1 development docs
- `docs/phase2/archive/` - Phase 2 status/process docs

---

## 🔑 Key Takeaways for Future Sessions

### **Data & Tables**:
1. **Use physical table** - Query `narvar-data-lake.query_opt.traffic_classification`
2. **Latest baseline**: Sep-Oct 2025 (4.47M jobs, most recent data)
3. **Table coverage**: 43.8M jobs, 9 periods (Sep 2022 - Oct 2025)

### **Critical Findings**:
4. **Hub has QoS crisis** - 39% violations during Peak_2024_2025 CRITICAL (44x slower than Monitor)
5. **Root causes**: 69% automated, 23% internal, 8% external (NOT human error!)
6. **Shared pool bottleneck**: 49.6% violations on reserved vs 1.5% on on-demand during stress
7. **monitor-base reclassified**: Now AUTOMATED (was EXTERNAL) - it's infrastructure batch processing

### **Capacity Strategy**:
8. **Monitoring-based approach approved** - Not pre-loading capacity ($58K-$173K avoided)
9. **Peak multipliers**: EXTERNAL 1.97x, AUTOMATED 1.63x, INTERNAL 1.67x
10. **Proactive controls in place**: Metabase termination DAG, Airflow staggering, real-time monitoring

---

**For next session priorities**: See "Next Priority: Monitor & Hub Consumer Analysis" section above

**For complete technical details**: See root folder documentation files

