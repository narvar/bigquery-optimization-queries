# BigQuery Peak Period Capacity Planning - Nov 2025 - Jan 2026

## Overview

This analysis project aims to optimize BigQuery slot allocation and ensure Quality of Service (QoS) for 2,600+ BigQuery projects during the Nov 2025-Jan 2026 peak period. The analysis is based on 3 years of historical audit log data (2022-2025).

**Project Status**: Phase 1 Complete ✅ | Phase 2 Ready to Start 🚀

**Phase 1 Results**: 39.4M jobs classified across 8 periods (96-100% coverage)

## Quick Start

### **Phase 1 Complete** ✅ - Classification Table Ready!

**Physical Table**: `narvar-data-lake.query_opt.traffic_classification`
- **43.8M jobs classified** across 9 periods (Sep 2022 - Oct 2025)
- **0-4% unclassified** (excellent quality)
- **35+ service account patterns** identified
- **Latest baseline**: Sep-Oct 2025 (freshest data!)

**For complete Phase 1 results**: See `PHASE1_FINAL_REPORT.md`  
**For AI assistants/future sessions**: See `AI_SESSION_CONTEXT.md`

---

### Using the Classification Table

**Query the table directly** (no need to reclassify):

```sql
-- Example: Get category breakdown for latest peak
SELECT
  consumer_category,
  consumer_subcategory,
  COUNT(*) as jobs,
  SUM(slot_hours) as slot_hours,
  COUNT(DISTINCT retailer_moniker) as retailers
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE analysis_period_label = 'Peak_2024_2025'
GROUP BY consumer_category, consumer_subcategory
ORDER BY slot_hours DESC;
```

### Classify New Periods (Automation)

**For future periods** (e.g., Nov 2025 - Jan 2026 peak):

```bash
cd scripts/
# Edit run_classification_all_periods.py to add new period
python run_classification_all_periods.py --mode all
```

See `scripts/CLASSIFICATION_AUTOMATION_GUIDE.md` for details.

### Phase 2: Analyze Historical Patterns (Next Step)

**Status**: Queries exist but need updates to use physical `traffic_classification` table

**Phase 2 Queries** (will be updated):
```sql
-- Compare peak periods across years
queries/phase2_historical/peak_vs_nonpeak_analysis.sql  ← Needs update

-- Identify QoS violations  
queries/phase2_historical/qos_violations_historical.sql  ← Needs update

-- Generate slot utilization heatmaps
queries/phase2_historical/slot_heatmap_analysis.sql      ← Needs update

-- Calculate year-over-year growth
queries/phase2_historical/yoy_growth_analysis.sql        ← Needs update
```

**These queries will be much faster now** - they'll query the pre-classified table instead of reclassifying 43M jobs each time!

### 4. Predict 2025 Peak Load

Forecast expected demand for upcoming peak period:

```sql
-- Project traffic based on historical trends
queries/phase3_prediction/traffic_projection_2025.sql

-- Predict QoS impact
queries/phase3_prediction/predicted_qos_impact_2025.sql

-- Identify bottlenecks
queries/phase3_prediction/bottleneck_identification_2025.sql
```

### 5. Run Slot Allocation Simulations

Evaluate different slot allocation strategies:

```sql
-- Run simulations for various scenarios
queries/phase4_simulation/slot_allocation_simulator.sql

-- Analyze costs vs. benefits
queries/phase4_simulation/cost_benefit_analysis.sql

-- Compare simulation results
queries/phase4_simulation/simulation_results_summary.sql
```

## Project Structure

```
analysis_peak_2025_sonnet45/
├── README.md (this file)
├── docs/
│   ├── PRD_BQ_Peak_Capacity_2025.md (Product Requirements Document)
│   ├── IMPLEMENTATION_GUIDE.md (Technical implementation guide)
│   └── SIMULATION_METHODOLOGY.md (Slot simulation methodology)
├── queries/
│   ├── phase1_classification/ (Traffic taxonomy & classification)
│   ├── phase2_historical/ (3-year peak analysis)
│   ├── phase3_prediction/ (2025 peak forecasting)
│   ├── phase4_simulation/ (Slot allocation scenarios)
│   └── utils/ (Data validation & helper queries)
├── notebooks/ (Python/Jupyter for visualization)
└── results/ (Query outputs, charts, analysis results)
```

## Consumer Categories

### 1. CRITICAL External Consumers (P0)
- **Primary**: Monitor projects (`monitor-{hash}-us-prod`)
- **Secondary**: Hub traffic (Looker-based)
- **QoS Target**: Query response time < 1 minute
- **Business Impact**: Direct customer-facing APIs

### 2. CRITICAL Automated Processes (P0)
- **Primary**: Airflow/Composer scheduled jobs
- **Secondary**: CDP and other automated pipelines
- **QoS Target**: Complete before next scheduled run
- **Business Impact**: Data pipeline SLAs, downstream dependencies

### 3. INTERNAL Users (P1)
- **Primary**: Metabase queries
- **Secondary**: Ad-hoc analysis queries
- **QoS Target**: Query response time < 5-10 minutes
- **Business Impact**: Internal analytics, reporting

## Current Slot Allocation

**Total Capacity**: 1,700 slots (Enterprise reservation)
- 500 slots: 1-year commitment
- 500 slots: 3-year commitment
- 700 slots: Pay-as-you-go
- **Managed in**: `bq-narvar-admin` project

## Data Sources

### Primary Data Source
- **Table**: `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
- **Coverage**: April 19, 2022 - Present
- **Update Frequency**: Real-time (streaming)
- **Key Fields**: job metadata, slot usage, execution times, user attribution

### Supporting Data Sources
- `reporting.t_return_details`: Retailer moniker mapping for monitor projects
- Metabase DB (linked resource): User email mapping for Metabase queries
- Composer/Airflow metadata: DAG schedules and SLAs (to be provided)

## Peak Period Definitions

| Period | Start Date | End Date | Status |
|--------|-----------|----------|--------|
| Peak 2022-2023 | 2022-11-01 | 2023-01-31 | Historical |
| Peak 2023-2024 | 2023-11-01 | 2024-01-31 | Historical |
| Peak 2024-2025 | 2024-11-01 | 2025-01-31 | Historical |
| **Peak 2025-2026** | **2025-11-01** | **2026-01-31** | **Target** |

## Query Standards

All queries in this project follow these standards:

### Parameterization
```sql
-- All queries use DECLARE for configurable parameters
DECLARE start_date DATE DEFAULT '2022-11-01';
DECLARE end_date DATE DEFAULT '2023-01-31';
DECLARE peak_period STRING DEFAULT '2022-2023';
```

### Cost Control
- Include comments with estimated bytes processed
- Warn about queries scanning >10GB
- Recommend dry-run validation before execution

### Consistency
- Follow existing audit_log query patterns
- Use standard field names and calculations
- Filter out script child jobs and dry runs
- Deduplicate using ROW_NUMBER() on jobId

### Performance
- Leverage date partition pruning
- Use clustering on timestamp fields
- Apply SAFE_DIVIDE for division operations
- Minimize query complexity where possible

## Quality of Service (QoS) Definitions

### External Consumers
```sql
CASE 
  WHEN execution_time_seconds > 60 THEN 'QoS_VIOLATION' 
  ELSE 'QoS_MET' 
END
```

### Automated Processes
```sql
CASE 
  WHEN actual_end_time > next_scheduled_run THEN 'QoS_VIOLATION' 
  ELSE 'QoS_MET' 
END
```

### Internal Users
```sql
CASE 
  WHEN execution_time_seconds > 480 THEN 'QoS_VIOLATION' 
  ELSE 'QoS_MET' 
END
```

## Simulation Scenarios

### Scenario A: Separate Reservations by Category
- Reservation 1: External Consumers (monitor + hub)
- Reservation 2: Automated Processes (Airflow/CDP)
- Reservation 3: Internal Users (Metabase + ad-hoc)
- Total: 1,700 slots distributed based on historical patterns

### Scenario B: Priority-Based Single Reservation
- Single 1,700-slot reservation
- Priority levels: External (highest) > Automated > Internal
- Leverage BigQuery's slot preemption

### Scenario C: Hybrid Approach
- Dedicated reservation for External (baseline)
- Shared reservation for Automated + Internal (with priorities)
- Autoscaling for peak overflow

### Scenario D: Capacity Increase
- Evaluate adding 500, 1000, 1500 additional slots
- Calculate QoS improvement vs. incremental cost
- Recommend minimum additional capacity

## Prerequisites & Dependencies

### Data Access Required
- [x] `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
- [x] `reporting.t_return_details`
- [ ] Metabase DB linked resource connection details
- [ ] Composer/Airflow metadata access

### User Input Required
- [ ] Airflow/Composer service account list
- [ ] Hub traffic attribution methodology
- [ ] Composer DAG schedules and SLAs
- [ ] Metabase query comment format validation
- [ ] Known business changes for 2025 peak period

### BigQuery Permissions
- [x] Read access to audit logs
- [x] Read access to reporting dataset
- [ ] Access to reservation/commitment billing details
- [ ] Query execution permissions

## Success Criteria

1. **Traffic Classification**: 95%+ of audit log traffic categorized
2. **Historical Analysis**: Clear identification of peak patterns from 3 years
3. **Prediction Accuracy**: Projections within 15% of actual
4. **Simulation Completeness**: 4+ scenarios with QoS and cost metrics
5. **Actionable Recommendations**: Clear slot allocation strategy
6. **Reusability**: Framework for future peak planning

## Timeline

- **Phase 1** (Classification): 2-3 days
- **Phase 2** (Historical Analysis): 3-4 days
- **Phase 3** (Prediction): 2-3 days
- **Phase 4** (Simulation): 4-5 days
- **Phase 5** (Documentation): 2-3 days
- **Total**: 13-18 working days

## Key Contacts & Resources

- **DoIt International CMP Team**: Cloud audit log data source
- **Airflow/Composer Team**: Service accounts and DAG schedules
- **Metabase Team**: User mapping and query format
- **BQ Admin Team**: Reservation configuration and billing

## Next Steps

1. ✅ Create project structure
2. ✅ Create data validation query
3. ✅ Run data completeness validation
4. ✅ Gather user inputs (service accounts, Hub logic, etc.)
5. ✅ Build traffic classification queries
6. ✅ Execute Phase 1: Traffic Classification (39.4M jobs across 8 periods)
7. 🎯 **CURRENT**: Update Phase 2 queries to use physical classification table
8. ⏳ Execute Phase 2: Historical Analysis (peak vs. non-peak, QoS, growth)
9. ⏳ Execute Phase 3: 2025-2026 Peak Prediction
10. ⏳ Execute Phase 4: Slot Allocation Simulation
11. ⏳ Execute Phase 5: Final Documentation and Recommendations

## Notes

- All queries are designed to be reusable for future peak planning
- Date ranges and thresholds are parameterized for easy customization
- Cost estimates are included in query comments
- Dry-run validation is recommended before executing large queries
- Results should be exported to `results/` folder for documentation

---

## 📚 Documentation

**Primary Docs**:
- `PHASE1_FINAL_REPORT.md` - Complete Phase 1 results and findings
- `AI_SESSION_CONTEXT.md` - Quick context for AI assistants/future sessions
- `README.md` - This file (project overview)

**Strategy & Implementation**:
- `docs/CLASSIFICATION_STRATEGY.md` - Temporal variability handling
- `docs/IMPLEMENTATION_STATUS.md` - Implementation checklist

**Archived Docs** (Historical Reference):
- `docs/archive/` - Interim documentation from Phase 1 development

---

**Last Updated**: November 5, 2025  
**Version**: 1.0.0 (Phase 1 Complete)  
**Maintained by**: Peak Capacity Planning Team




