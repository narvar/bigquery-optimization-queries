# BigQuery Peak Period 2025 Analysis

This directory contains queries and analysis for optimizing BigQuery slot allocation and cost management during the peak period of November 2025 - January 2026.

## Overview

This analysis supports capacity planning for 2600+ BigQuery projects sharing a 1,700-slot enterprise capacity. The goal is to predict expected load during peak period (Nov 2025 - Jan 2026) and ensure Quality of Service (QoS) for CRITICAL categories while minimizing cost increases.

## Current State

- **Enterprise Capacity:** 1,700 slots
  - 500 slots (1-year commitment)
  - 500 slots (3-year commitment)
  - 700 slots (Pay-as-you-go)
- **Reservation Management:** Managed in `bq-narvar-admin` project
- **Data History:** April 19, 2022 onwards (3+ peak periods available)

## Consumer Categories

1. **CRITICAL External Consumers**
   - Monitor projects (one per retailer/B2B customer)
   - Hub traffic (Looker-based)
   - QoS Requirement: Query response time > 1 minute is harmful

2. **CRITICAL Automated Processes**
   - Service account-based workloads (Airflow, CDP, etc.)
   - QoS Requirement: Must execute within scheduled time windows

3. **INTERNAL Users**
   - Primarily from Metabase
   - QoS Requirement: Query response time > 5-10 minutes is harmful

## Directory Structure

```
analysis_peak_2025/
├── README.md (this file)
├── traffic_classification/     # Phase 1: Identify and classify traffic
├── seasonal_analysis/          # Phase 2: Historical pattern analysis
├── prediction/                 # Phase 3: Predictive modeling
├── simulations/                # Phase 4: Slot allocation simulations
└── recommendations/            # Phase 5: Final recommendations
```

## Usage Guidelines

### Query Parameters

All queries use `DECLARE` statements for configurable parameters:
- Date ranges (analysis periods, peak periods)
- QoS thresholds
- Slot allocations (for simulations)
- Growth scenarios
- Cost assumptions

### Cost Management

**IMPORTANT:** These queries can process large volumes of data (10-200GB+).

- Always check estimated query cost before execution
- Use dry-run validation for large date ranges
- Start with smaller intervals for exploration
- Queries include cost warnings in comments

### Best Practices

1. **Start Small:** Begin with 7-30 day intervals before full year analysis
2. **Use Dry-Run:** Validate query structure and estimate costs
3. **Incremental Analysis:** Build up to full analysis over multiple runs
4. **Validate Results:** Cross-check findings across different queries

## Phase 1: Traffic Classification

Identifies and classifies all BigQuery traffic by consumer category.

**Queries:**
- `monitor_project_mappings.sql` - Maps retailers to monitor projects
- `hub_traffic_analysis.sql` - Analyzes Hub/Looker traffic
- `automated_processes_classification.sql` - Identifies automated processes
- `automated_schedules_inference.sql` - Infers execution schedules
- `internal_users_classification.sql` - Classifies Metabase users
- `unified_traffic_classification.sql` - Comprehensive classification

## Phase 2: Seasonalized Traffic Analysis

Analyzes historical traffic patterns and QoS issues across peak vs. non-peak periods.

**Queries:**
- `seasonal_query_volume_by_category.sql` - Analyzes query execution volume during peak vs. non-peak periods
- `seasonal_slot_patterns_by_category.sql` - Analyzes slot consumption patterns by category during peak/non-peak
- `seasonal_cost_analysis.sql` - Compares costs and cost efficiency metrics by period and category
- `qos_metrics_calculation.sql` - Calculates QoS metrics (P50, P95, P99, etc.) by category
- `peak_nonpeak_qos_comparison.sql` - Compares QoS metrics between peak and non-peak periods
- `historical_qos_issues_analysis.sql` - Identifies past QoS violations and correlates with slot utilization

**Note:** These queries reference a materialized view `narvar-data-lake.analysis_peak_2025.traffic_classification`. 
Create this view using the `unified_traffic_classification.sql` query, or inline the classification logic for smaller date ranges.

## Phase 3: Predictive Modeling

Predicts expected load and QoS during Nov 2025 - Jan 2026.

**Queries:**
- (To be implemented)

## Phase 4: Slot Allocation Simulations

Simulates different slot allocation strategies and evaluates QoS/cost trade-offs.

**Queries:**
- (To be implemented)

## Phase 5: Recommendations

Synthesizes findings into actionable recommendations.

**Deliverables:**
- (To be implemented)

## Data Sources

- **Primary:** `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
- **Retailer Mapping:** `reporting.t_return_details`
- **Reservation Data:** `bq-narvar-admin` project
- **Metabase DB:** BigQuery linked resource (configurable)

## Notes

- All queries follow existing patterns from `narvar/audit_log/`
- Queries filter out BigQuery script child jobs (`script_job_%`)
  - **Parent/Child Identification:** Script child jobs have pattern `script_job_{hash}_{number}`
  - **Current Filter:** Excludes children only; parent script jobs are retained as they represent actual user-submitted queries
  - **Other Splits:** BigQuery internal query splits are handled via `ROW_NUMBER()` deduplication by `jobId`
- Queries exclude dry-run executions
- Job deduplication uses `ROW_NUMBER()` partitioned by job ID
- **Cost Calculations:** Based on slot-hours × $0.04/hour (pay-as-you-go rate)
  - Actual total monthly cost: ~$50,000 USD (user reported)
  - Fixed vs. variable cost breakdown requires actual billing data
  - Simulation config pricing values appear to be incorrect
  - See `COST_CALCULATION_ANALYSIS.md` for detailed explanation

## Support

For questions about this analysis or capacity planning assistance, contact the DoiT International Cloud Management Platform team.

