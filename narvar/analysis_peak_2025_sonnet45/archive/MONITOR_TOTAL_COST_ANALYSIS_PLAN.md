# Monitor Platform Total Cost Analysis - Comprehensive Planning Document

**Project:** BigQuery Peak Capacity Planning 2025-2026  
**Sub-Project:** Monitor Total Cost of Ownership (Consumption + Production)  
**Created:** November 14, 2025  
**Status:** Planning Phase  
**For:** Future AI agents and team collaboration

---

## 📋 Table of Contents

1. [Executive Summary](#executive-summary)
2. [Background & Motivation](#background--motivation)
3. [Project Objectives](#project-objectives)
4. [Scope & Boundaries](#scope--boundaries)
5. [Technical Approach](#technical-approach)
6. [Phase-by-Phase Execution Plan](#phase-by-phase-execution-plan)
7. [Cost Attribution Methodology](#cost-attribution-methodology)
8. [Data Sources & Infrastructure](#data-sources--infrastructure)
9. [Expected Deliverables](#expected-deliverables)
10. [Timeline & Dependencies](#timeline--dependencies)
11. [Cost & Risk Assessment](#cost--risk-assessment)
12. [Success Criteria](#success-criteria)
13. [Future Extensions](#future-extensions)
14. [References](#references)
15. [Appendix](#appendix)

---

## 🎯 Executive Summary

### Problem Statement

The existing Monitor platform analysis (documented in `MONITOR_2025_ANALYSIS_REPORT.md`) provides comprehensive **data consumption cost analysis** - the cost retailers incur when querying data through Monitor APIs. However, this represents only **part of the total cost picture**. 

We also need to understand the **data production costs** - the cost of ETL processes, data pipelines, storage, and infrastructure that create and maintain the data being queried. These production costs must be fairly attributed to retailers based on their usage patterns.

### Goal

Develop a **Total Cost of Ownership (TCO) model** for the Monitor platform that includes:
- **Consumption Costs:** BigQuery query execution costs ($2,674 for analyzed periods)
- **Production Costs:** ETL, storage, and infrastructure costs for data creation/maintenance
- **Fair Attribution:** Distribute production costs across 284 retailers based on their usage patterns

### Strategic Value

1. **Complete Cost Visibility:** Understand true per-retailer costs for Monitor platform
2. **Informed Pricing Decisions:** Data-driven basis for customer pricing models
3. **Optimization Priorities:** Identify where to focus cost reduction efforts (consumption vs production)
4. **Platform Comparison:** Enable apples-to-apples comparison with other platforms (Hub, Looker, Metabase)
5. **Retailer Engagement:** Provide retailers with transparency on their total platform costs

### Approach Overview

**Three-Phase Strategy:**

1. **Phase 1-4: Proof-of-Concept (fashionnova)**
   - Focus on single high-cost retailer ($673 consumption cost, 24.8% QoS violations)
   - Validate methodology and attribution model
   - Estimated time: 1 day, Cost: $0.50-$2.00

2. **Phase 5: Scale to All Retailers**
   - Apply validated model to all 284 retailers
   - Generate comprehensive total cost analysis
   - Estimated time: 4-6 hours, Cost: $1.00-$5.00

3. **Phase 6: Integration & Recommendations**
   - Update existing Monitor analysis report
   - Create optimization playbook
   - Estimated time: 3-4 hours

**Total Timeline:** 1-2 days  
**Total Estimated Cost:** $1.50-$7.00 in BigQuery query costs

---

## 📖 Background & Motivation

### Existing Work

The project builds on comprehensive Monitor platform analysis completed in November 2025:

**MONITOR_2025_ANALYSIS_REPORT.md** - Key Findings:
- **205,483 queries** across **284 retailers** analyzed
- **$2,674 total consumption cost** (2 periods: Peak_2024_2025, Baseline_2025_Sep_Oct)
- **97.8% QoS compliance** overall, but significant retailer variability
- **Extreme cost concentration:** Top 20 retailers = 94% of consumption costs
- **fashionnova crisis:** Single retailer = 25% of costs, 47% of QoS violations

**MONITOR_MERGE_COST_FINAL_RESULTS.md** - Key Data Point:
- **$200,957 annual cost** for `monitor-base-us-prod.monitor_base.shipments` production
  - Compute (merge operations): $149,832 (74.6%)
  - Storage: $24,899 (12.4%)
  - Pub/Sub: $26,226 (13.1%)
- This is a **shared resource** serving all retailers
- Represents **24.18%** of total BigQuery reservation capacity

### The Gap

Current analysis answers: **"How much does each retailer cost us when they query data?"**

Missing analysis: **"How much does it cost us to produce and maintain the data they query?"**

### Why This Matters

**Example Scenario: fashionnova**
- **Current Known Cost:** $673/year in query execution
- **Unknown Cost:** Portion of $200,957 monitor_base.shipments production + other table production costs
- **Estimated Total:** Could be $1,500-$3,000/year (2-4x current known cost!)

**Business Impact:**
- **Pricing Decisions:** Are we pricing Monitor services correctly?
- **Optimization ROI:** Which optimizations give best return (query optimization vs ETL optimization)?
- **Platform Viability:** Is Monitor profitable at current scale?
- **Resource Allocation:** Where should engineering effort focus?

### Strategic Alignment

This analysis aligns with:
- **Parent Project:** BigQuery Peak Capacity Planning (Nov 2025 - Jan 2026)
- **Organization Goals:** Cost optimization, platform efficiency, customer value
- **Technical Debt Reduction:** Better understanding of infrastructure costs
- **Future Expansion:** Framework applicable to Hub, Looker, Metabase platforms

---

## 🎯 Project Objectives

### Primary Objectives

1. **Identify Data Dependencies**
   - Catalog all tables and views used by Monitor queries
   - Resolve view hierarchies to find base tables
   - Quantify usage patterns (query count, slot-hours, data volume)

2. **Map Production Workflows**
   - Identify ETL jobs that produce/maintain each table
   - Link tables to Airflow DAGs, service accounts, and workflows
   - Estimate production costs per table (BigQuery, Dataflow, GCS, Pub/Sub)

3. **Develop Attribution Model**
   - Create fair methodology to distribute production costs across retailers
   - Balance multiple factors: query count, slot-hours, data volume
   - Validate model with sanity checks and stakeholder review

4. **Calculate Total Costs**
   - Combine consumption + production costs per retailer
   - Identify cost drivers (which tables drive production costs?)
   - Analyze production/consumption ratios

5. **Generate Actionable Insights**
   - Update existing Monitor analysis with total cost perspective
   - Create optimization recommendations (consumption + production)
   - Provide framework for other platforms (Hub, Looker, etc.)

### Success Metrics

- ✅ **Coverage:** Map 90%+ of tables used by Monitor queries to their ETL sources
- ✅ **Accuracy:** Attribution model sums to 100% within 5% rounding error
- ✅ **Actionability:** Generate 5+ specific optimization recommendations with ROI estimates
- ✅ **Scalability:** Framework works for all 284 retailers with reasonable BigQuery costs (<$10)
- ✅ **Validation:** fashionnova PoC reviewed and approved before scaling
- ✅ **Documentation:** Comprehensive report usable by business stakeholders

---

## 🔍 Scope & Boundaries

### In Scope

**Platforms:**
- ✅ Monitor platform (direct retailer API queries)
- ✅ monitor-base infrastructure (shared resource)

**Cost Components:**
- ✅ BigQuery query execution costs (consumption)
- ✅ BigQuery ETL/merge costs (production compute)
- ✅ BigQuery storage costs (active and long-term)
- ✅ Pub/Sub messaging costs (data ingestion)
- ✅ Known infrastructure costs (where data available)

**Analysis Periods:**
- ✅ Peak_2024_2025 (Nov 2024 - Jan 2025)
- ✅ Baseline_2025_Sep_Oct (Sep-Oct 2025)
- ✅ Extrapolate to annual costs where appropriate

**Retailers:**
- ✅ All 284 retailers with Monitor traffic
- ✅ Start with fashionnova PoC, then scale

### Out of Scope (Phase 1)

**Platforms:**
- ❌ Hub (Looker dashboards) - separate analysis
- ❌ Looker - separate analysis  
- ❌ Metabase - separate analysis
- ❌ Analytics API - separate analysis
- 📝 **Note:** Framework designed for future extension to these platforms

**Cost Components:**
- ❌ Dataflow costs (unless easily attributable)
- ❌ GCS storage costs (unless easily attributable)
- ❌ GKE/Compute Engine costs (infrastructure overhead)
- ❌ Human labor costs (data engineering, support)
- ❌ Network egress costs (minimal for BigQuery)

**Analysis Scope:**
- ❌ Real-time cost tracking (point-in-time analysis only)
- ❌ Cost forecasting (descriptive analysis, not predictive)
- ❌ Cross-platform cost comparison (Monitor only)
- ❌ Chargeback system implementation (analysis only, not billing)

### Boundaries & Assumptions

**Key Assumptions:**

1. **Historical Data Representativeness**
   - Sep-Oct 2025 baseline and Nov 2024-Jan 2025 peak periods represent typical usage
   - Extrapolation to annual costs is reasonable with seasonal adjustments

2. **Cost Model Accuracy**
   - BigQuery slot-hour rate: $0.0494 (blended rate for 1,700-slot reservation)
   - ON_DEMAND rate: $6.25/TB (US multi-region)
   - monitor_base.shipments annual cost: $200,957 (from prior analysis)

3. **Attribution Fairness**
   - Hybrid model (40% query count, 30% slot-hours, 30% TB scanned) is "fair enough"
   - No single perfect attribution model exists
   - Stakeholders will accept documented methodology

4. **Data Completeness**
   - Audit logs contain sufficient information for ETL mapping
   - Referenced tables can be extracted from INFORMATION_SCHEMA or query text
   - View definitions are accessible and parseable

5. **Shared Resource Handling**
   - monitor_base.shipments serves all retailers proportionally
   - Attribution by usage metrics is appropriate
   - No retailer has special access or priority

**Known Limitations:**

1. **Incomplete ETL Mapping:** Some tables may be populated by streaming inserts or external sources without audit log evidence
2. **View Resolution Depth:** Complex nested views (4+ levels) may not fully resolve
3. **Cost Granularity:** Some costs (storage, Pub/Sub) allocated at project level, not table level
4. **Time Lag:** Production costs incurred when data created, consumption when data queried (temporal mismatch)
5. **Incremental vs Full Costs:** Attribution model uses total production cost, not marginal cost per retailer

---

## 🔧 Technical Approach

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     INPUT DATA SOURCES                          │
├─────────────────────────────────────────────────────────────────┤
│ 1. narvar-data-lake.query_opt.traffic_classification           │
│    - 205,483 Monitor queries with retailer attribution         │
│    - Consumption costs, slot-hours, QoS metrics                │
│    - Query text samples (500 chars)                            │
│                                                                 │
│ 2. narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis...   │
│    - Full query text for all job_ids                           │
│    - Table references, service accounts, operations            │
│    - Historical ETL job execution data                         │
│                                                                 │
│ 3. INFORMATION_SCHEMA (BigQuery metadata)                      │
│    - JOBS_BY_PROJECT: referenced_tables field                  │
│    - VIEWS: view definitions for dependency resolution         │
│    - TABLES: table metadata, storage costs                     │
│                                                                 │
│ 4. MONITOR_MERGE_COST_FINAL_RESULTS.md (existing analysis)     │
│    - monitor_base.shipments production cost: $200,957/year     │
│    - Cost breakdown: compute, storage, Pub/Sub                 │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PROCESSING PIPELINE                          │
├─────────────────────────────────────────────────────────────────┤
│ PHASE 1: Table & View Dependency Discovery                     │
│   ├─ Extract referenced tables from query text                 │
│   ├─ Resolve view dependencies (recursive, 3 levels)           │
│   └─ Build table usage matrix (retailer × table)               │
│                                                                 │
│ PHASE 2: ETL Source Discovery                                  │
│   ├─ Search audit logs for INSERT/MERGE operations            │
│   ├─ Map tables to service accounts & ETL jobs                 │
│   ├─ Calculate production costs per table                      │
│   └─ Cross-reference with known costs (monitor_base.shipments) │
│                                                                 │
│ PHASE 3: Cost Attribution Model                                │
│   ├─ Calculate retailer usage metrics per table                │
│   ├─ Apply hybrid attribution formula (40/30/30 weights)       │
│   ├─ Distribute production costs to retailers                  │
│   └─ Validate: sum to 100%, check outliers                     │
│                                                                 │
│ PHASE 4: Total Cost Aggregation                                │
│   ├─ Consumption cost (from existing analysis)                 │
│   ├─ Production cost (from attribution model)                  │
│   ├─ Total cost = consumption + production                     │
│   └─ Calculate cost efficiency metrics                         │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      OUTPUT DELIVERABLES                        │
├─────────────────────────────────────────────────────────────────┤
│ 1. Per-Retailer Total Cost Analysis                            │
│    - fashionnova PoC report (detailed)                         │
│    - All 284 retailers comprehensive report                    │
│                                                                 │
│ 2. Cost Attribution Model Documentation                        │
│    - Methodology explanation                                   │
│    - Validation results                                        │
│    - Sensitivity analysis                                      │
│                                                                 │
│ 3. Optimization Recommendations                                │
│    - Consumption optimization (query efficiency)               │
│    - Production optimization (ETL efficiency)                  │
│    - Combined strategies with ROI estimates                    │
│                                                                 │
│ 4. Updated Monitor Analysis Report                             │
│    - Integrate total cost sections                             │
│    - Update cost rankings and metrics                          │
│    - Add production cost context                               │
└─────────────────────────────────────────────────────────────────┘
```

### Key Technical Decisions

**Decision 1: Table Reference Extraction Method**

**Chosen Approach:** Use `INFORMATION_SCHEMA.JOBS_BY_PROJECT` with `referenced_tables` field
- ✅ **Pros:** Native BigQuery feature, accurate, no parsing needed
- ✅ **Pros:** Handles complex queries, views resolved automatically
- ❌ **Cons:** Requires job_id join with audit logs

**Alternative Rejected:** Regex parsing of query text
- ❌ Too error-prone for complex SQL
- ❌ Misses dynamically constructed table names
- 📝 Keep as fallback for validation

**Decision 2: View Resolution Strategy**

**Chosen Approach:** Recursive SQL query with 3-level depth limit
- ✅ Handles most real-world scenarios (views → views → tables)
- ✅ Prevents infinite loops and query timeouts
- ❌ May miss deeply nested views (document as limitation)

**Implementation:**
```sql
WITH RECURSIVE view_dependencies AS (
  -- Base: Direct view references
  SELECT view_name, table_reference, 1 as depth
  FROM INFORMATION_SCHEMA.VIEWS
  CROSS JOIN UNNEST(extracted_table_refs) AS table_reference
  
  UNION ALL
  
  -- Recursive: Views that reference other views
  SELECT vd.view_name, v.table_reference, vd.depth + 1
  FROM view_dependencies vd
  JOIN INFORMATION_SCHEMA.VIEWS v ON vd.table_reference = v.table_catalog || '.' || v.table_schema || '.' || v.table_name
  CROSS JOIN UNNEST(extract_table_refs(v.view_definition)) AS table_reference
  WHERE vd.depth < 3  -- Limit recursion depth
)
SELECT * FROM view_dependencies
```

**Decision 3: Cost Attribution Model**

**Chosen Approach:** Hybrid multi-factor model (40% query count, 30% slot-hours, 30% TB scanned)

**Rationale:**
- **Query Count (40%):** Reflects API call frequency and basic usage
- **Slot-Hours (30%):** Reflects computational intensity and query complexity
- **TB Scanned (30%):** Reflects data footprint and storage impact

**Alternative Models Considered:**
1. **Simple Query Count:** Too crude, ignores complexity differences
2. **Slot-Hours Only:** Biases toward complex queries, ignores high-frequency simple queries
3. **Equal Weights:** No justification for equal importance

**Validation:**
- Compare to consumption-only attribution (should correlate but not be identical)
- Sensitivity analysis: ±10% weight changes should not drastically alter rankings
- Stakeholder review and adjustment if needed

**Decision 4: ETL Source Mapping Strategy**

**Chosen Approach:** BigQuery audit log search for INSERT/MERGE/CREATE operations

**Query Pattern:**
```sql
SELECT
  destination_table.project_id,
  destination_table.dataset_id,
  destination_table.table_id,
  principal_email,
  COUNT(*) as etl_job_count,
  SUM(total_slot_ms) / 3600000 as total_slot_hours,
  SUM(total_slot_ms) / 3600000 * 0.0494 as estimated_cost_usd
FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
WHERE statement_type IN ('INSERT', 'MERGE', 'CREATE_TABLE_AS_SELECT')
  AND destination_table IS NOT NULL
  AND DATE(creation_time) BETWEEN '2024-09-01' AND '2025-10-31'
GROUP BY 1,2,3,4
```

**Fallbacks:**
- Cross-reference with Composer/Airflow DAG definitions (manual)
- Check GCS bucket uploads (if available)
- Document tables with unknown sources

---

## 📊 Phase-by-Phase Execution Plan

### PHASE 1: Table & View Dependency Discovery (PoC: fashionnova)

**Objective:** Identify all tables and views used by fashionnova queries and resolve to base tables.

**Estimated Time:** 2-3 hours  
**Estimated Cost:** $0.10 - $0.50

---

#### Step 1.1: Extract Referenced Tables from Query Metadata

**Goal:** Get list of all tables referenced in fashionnova queries using BigQuery metadata.

**SQL Query:** `queries/monitor_total_cost/01_extract_referenced_tables.sql`

**Approach:**
```sql
-- ============================================================================
-- Extract Referenced Tables for fashionnova Monitor Queries
-- ============================================================================
-- Uses INFORMATION_SCHEMA.JOBS_BY_PROJECT for accurate table references
-- Avoids complex query text parsing
-- ============================================================================

DECLARE target_retailer STRING DEFAULT 'fashionnova';
DECLARE target_periods ARRAY<STRING> DEFAULT ['Peak_2024_2025', 'Baseline_2025_Sep_Oct'];

WITH fashionnova_jobs AS (
  -- Get all fashionnova job_ids from classification table
  SELECT 
    job_id,
    retailer_moniker,
    analysis_period_label,
    total_slot_ms,
    slot_hours,
    estimated_slot_cost_usd,
    total_billed_bytes,
    execution_time_seconds
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE retailer_moniker = target_retailer
    AND consumer_subcategory = 'MONITOR'
    AND analysis_period_label IN UNNEST(target_periods)
    AND total_slot_ms IS NOT NULL
),

-- Join with INFORMATION_SCHEMA to get referenced tables
job_table_references AS (
  SELECT
    fj.job_id,
    fj.retailer_moniker,
    fj.analysis_period_label,
    fj.slot_hours,
    fj.estimated_slot_cost_usd,
    fj.total_billed_bytes,
    ref_table.project_id,
    ref_table.dataset_id,
    ref_table.table_id,
    CONCAT(ref_table.project_id, '.', ref_table.dataset_id, '.', ref_table.table_id) AS table_reference
  FROM fashionnova_jobs fj
  CROSS JOIN UNNEST(
    (SELECT referenced_tables 
     FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT 
     WHERE job_id = fj.job_id)
  ) AS ref_table
  WHERE ref_table.table_id IS NOT NULL  -- Exclude NULL references
)

-- Aggregate by table reference
SELECT
  table_reference,
  COUNT(DISTINCT job_id) AS reference_count,
  SUM(slot_hours) AS total_slot_hours,
  SUM(estimated_slot_cost_usd) AS total_cost_usd,
  SUM(total_billed_bytes) / POW(1024, 4) AS total_tb_scanned,
  MIN(analysis_period_label) AS first_seen_period,
  MAX(analysis_period_label) AS last_seen_period
FROM job_table_references
GROUP BY table_reference
ORDER BY total_slot_hours DESC;
```

**Expected Output:** `results/fashionnova_referenced_tables.csv`

Sample rows:
```
table_reference                                    | reference_count | total_slot_hours | total_cost_usd | total_tb_scanned
--------------------------------------------------+----------------+------------------+---------------+-----------------
monitor-base-us-prod.monitor_base.shipments       | 4,823          | 8,456.32        | 417.89        | 234.56
narvar-data-lake.reporting.t_return_details       | 1,234          | 1,234.56        | 60.95         | 45.67
monitor-base-us-prod.monitor_base.orders          | 891            | 678.90          | 33.54         | 23.45
...
```

**Validation Checks:**
- Total slot_hours should approximately match fashionnova's total from MONITOR_2025_ANALYSIS_REPORT (13,628 slot-hours)
- Should find 10-50 unique tables (reasonable for Monitor queries)
- monitor-base-us-prod.monitor_base.shipments should be top reference

---

#### Step 1.2: Identify Views and Extract Base Tables

**Goal:** For each table reference, determine if it's a view and recursively resolve to base tables.

**SQL Query:** `queries/monitor_total_cost/02_resolve_view_dependencies.sql`

**Approach:**
```sql
-- ============================================================================
-- Resolve View Dependencies Recursively
-- ============================================================================
-- For each table referenced by fashionnova, check if it's a view
-- If view, extract base tables from view definition (up to 3 levels deep)
-- ============================================================================

WITH fashionnova_tables AS (
  -- Import results from Step 1.1
  SELECT table_reference
  FROM `results.fashionnova_referenced_tables`  -- Temp table or CSV import
),

-- Check which references are views
table_types AS (
  SELECT
    ft.table_reference,
    CASE 
      WHEN v.table_name IS NOT NULL THEN 'VIEW'
      WHEN t.table_name IS NOT NULL THEN 'TABLE'
      ELSE 'UNKNOWN'
    END AS table_type,
    v.view_definition
  FROM fashionnova_tables ft
  LEFT JOIN `region-us`.INFORMATION_SCHEMA.VIEWS v 
    ON ft.table_reference = CONCAT(v.table_catalog, '.', v.table_schema, '.', v.table_name)
  LEFT JOIN `region-us`.INFORMATION_SCHEMA.TABLES t
    ON ft.table_reference = CONCAT(t.table_catalog, '.', t.table_schema, '.', t.table_name)
),

-- Extract base tables from view definitions (simplified regex approach)
-- Note: This is approximate - complex views may need manual review
view_base_tables AS (
  SELECT
    table_reference AS view_name,
    REGEXP_EXTRACT_ALL(
      view_definition,
      r'(?:FROM|JOIN)\s+`?([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)`?'
    ) AS base_table_array
  FROM table_types
  WHERE table_type = 'VIEW'
),

-- Flatten array to rows
view_dependencies AS (
  SELECT
    view_name,
    base_table,
    1 AS dependency_level
  FROM view_base_tables
  CROSS JOIN UNNEST(base_table_array) AS base_table
)

-- Output view → base table mappings
SELECT
  vd.view_name,
  vd.base_table,
  vd.dependency_level,
  tt.table_type AS base_table_type,
  CASE 
    WHEN tt.table_type = 'VIEW' THEN 'NEEDS_FURTHER_RESOLUTION'
    WHEN tt.table_type = 'TABLE' THEN 'RESOLVED'
    ELSE 'UNKNOWN'
  END AS resolution_status
FROM view_dependencies vd
LEFT JOIN table_types tt ON vd.base_table = tt.table_reference
ORDER BY vd.view_name, vd.base_table;
```

**Expected Output:** `results/fashionnova_view_dependencies.csv`

Sample rows:
```
view_name                                  | base_table                                     | dependency_level | resolution_status
------------------------------------------+-----------------------------------------------+-----------------+------------------
monitor-base-us-prod.views.shipment_summary | monitor-base-us-prod.monitor_base.shipments  | 1               | RESOLVED
monitor-base-us-prod.views.shipment_summary | narvar-data-lake.reporting.t_return_details  | 1               | RESOLVED
...
```

**Manual Review Task:**
- For views marked 'NEEDS_FURTHER_RESOLUTION', manually inspect and document
- Limit recursion to 3 levels (document deeper nesting as limitation)

---

#### Step 1.3: Flag monitor_base.shipments Usage

**Goal:** Special handling for the shared infrastructure table with known production cost.

**SQL Query:** Add to `01_extract_referenced_tables.sql` output

```sql
-- Add flag for queries using monitor_base.shipments
-- (either directly or through views)
ALTER TABLE results.fashionnova_referenced_tables
ADD COLUMN uses_monitor_base_shipments BOOL;

UPDATE results.fashionnova_referenced_tables
SET uses_monitor_base_shipments = TRUE
WHERE table_reference = 'monitor-base-us-prod.monitor_base.shipments'
   OR table_reference IN (
     SELECT view_name 
     FROM results.fashionnova_view_dependencies
     WHERE base_table = 'monitor-base-us-prod.monitor_base.shipments'
   );
```

**Validation:**
- Count queries using monitor_base.shipments: expect >50% of fashionnova queries
- Calculate fashionnova's share: 5,911 queries / 205,483 total = 2.88%

---

### PHASE 2: ETL Source Discovery & Cost Estimation

**Objective:** Map each identified table to its ETL production workflow and estimate costs.

**Estimated Time:** 3-4 hours  
**Estimated Cost:** $0.20 - $1.00

---

#### Step 2.1: Search Audit Logs for ETL Jobs

**Goal:** Find all INSERT/MERGE operations that populate tables used by fashionnova.

**SQL Query:** `queries/monitor_total_cost/03_map_tables_to_etl_jobs.sql`

**Approach:**
```sql
-- ============================================================================
-- Map Tables to ETL Production Jobs
-- ============================================================================
-- Search audit logs for jobs that write to fashionnova's referenced tables
-- Focus on same time periods as consumption analysis for consistency
-- ============================================================================

DECLARE analysis_start_date DATE DEFAULT '2024-09-01';
DECLARE analysis_end_date DATE DEFAULT '2025-10-31';

WITH fashionnova_tables AS (
  SELECT DISTINCT table_reference
  FROM `results.fashionnova_referenced_tables`
),

-- Search audit logs for ETL operations on these tables
etl_operations AS (
  SELECT
    job_id,
    creation_time,
    CONCAT(
      destination_table.project_id, '.', 
      destination_table.dataset_id, '.', 
      destination_table.table_id
    ) AS destination_table_ref,
    principal_email,
    statement_type,
    total_slot_ms,
    total_slot_ms / 3600000 AS slot_hours,
    (total_slot_ms / 3600000) * 0.0494 AS estimated_cost_usd,
    total_billed_bytes
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(creation_time) BETWEEN analysis_start_date AND analysis_end_date
    AND statement_type IN ('INSERT', 'MERGE', 'CREATE_TABLE_AS_SELECT', 'UPDATE')
    AND destination_table IS NOT NULL
    AND CONCAT(
          destination_table.project_id, '.', 
          destination_table.dataset_id, '.', 
          destination_table.table_id
        ) IN (SELECT table_reference FROM fashionnova_tables)
    AND total_slot_ms IS NOT NULL
),

-- Classify ETL jobs by service account pattern
etl_classification AS (
  SELECT
    *,
    CASE
      WHEN principal_email LIKE '%airflow%' OR principal_email LIKE '%composer%' THEN 'AIRFLOW'
      WHEN principal_email LIKE '%gke%' THEN 'GKE'
      WHEN principal_email LIKE '%appspot%' THEN 'APP_ENGINE'
      WHEN principal_email LIKE '%compute%' THEN 'COMPUTE_ENGINE'
      WHEN principal_email LIKE '%dataflow%' THEN 'DATAFLOW'
      ELSE 'OTHER'
    END AS etl_source_type
  FROM etl_operations
)

-- Aggregate by table and ETL source
SELECT
  destination_table_ref,
  etl_source_type,
  principal_email,
  COUNT(*) AS etl_job_count,
  SUM(slot_hours) AS total_slot_hours,
  SUM(estimated_cost_usd) AS estimated_production_cost_usd,
  AVG(slot_hours) AS avg_slot_hours_per_job,
  COUNT(*) / DATE_DIFF(analysis_end_date, analysis_start_date, DAY) AS avg_jobs_per_day,
  MIN(creation_time) AS first_seen,
  MAX(creation_time) AS last_seen
FROM etl_classification
GROUP BY destination_table_ref, etl_source_type, principal_email
ORDER BY destination_table_ref, total_slot_hours DESC;
```

**Expected Output:** `results/fashionnova_table_etl_mapping.csv`

Sample rows:
```
destination_table_ref                         | etl_source_type | principal_email                       | etl_job_count | total_slot_hours | estimated_production_cost_usd | avg_jobs_per_day
---------------------------------------------+----------------+---------------------------------------+--------------+------------------+-----------------------------+-----------------
monitor-base-us-prod.monitor_base.shipments  | APP_ENGINE     | monitor-base-us-prod@appspot.gsa...  | 6,256        | 505,505.37      | 24,971.96                   | 147.2
narvar-data-lake.reporting.t_return_details  | AIRFLOW        | airflow-prod@narvar-data-lake.iam... | 182          | 2,345.67        | 115.87                      | 4.3
...
```

**Validation:**
- monitor-base-us-prod.monitor_base.shipments production cost should align with MONITOR_MERGE_COST_FINAL_RESULTS.md ($24,971.96 for 2 months = ~$150K annual compute)
- Identify tables with zero ETL jobs (may be streaming inserts or external sources)

---

#### Step 2.2: Handle monitor_base.shipments Special Case

**Goal:** Use known production cost from MONITOR_MERGE_COST_FINAL_RESULTS.md

**Cost Breakdown:**
```
Total Annual Cost: $200,957

Components:
1. Compute (merge operations):       $149,832  (74.6%)
2. Storage (active + long-term):     $ 24,899  (12.4%)
3. Pub/Sub (message delivery):       $ 26,226  (13.1%)

Time Period: Extrapolated from Sep-Oct 2024 baseline (6x factor)
Service Account: monitor-base-us-prod@appspot.gserviceaccount.com
Operations: MERGE statements containing "shipments" keyword
Workload: 24.18% of total BQ Reservation capacity
```

**Attribution Calculation (Preliminary):**

fashionnova usage metrics (from MONITOR_2025_ANALYSIS_REPORT.md):
- Queries: 5,911 / 205,483 total = **2.88%**
- Slot-hours: 13,628 / unknown total = **TBD%**
- TB scanned: unknown / unknown total = **TBD%**

**Action Items:**
1. Calculate total Monitor platform slot-hours across all retailers
2. Calculate total Monitor platform TB scanned across all retailers
3. Apply hybrid formula (see Phase 3)

---

#### Step 2.3: Cross-Reference with Composer DAG Definitions

**Goal:** Manual validation of ETL sources by reviewing Airflow DAG code.

**Process (Manual):**

1. **Extract Unique Service Accounts:**
   ```bash
   # From Step 2.1 output
   cat results/fashionnova_table_etl_mapping.csv | \
     cut -d',' -f3 | sort | uniq > service_accounts.txt
   ```

2. **Search Composer Repositories:**
   ```bash
   cd /Users/cezarmihaila/workspace/composer
   for account in $(cat service_accounts.txt); do
     echo "Searching for: $account"
     grep -r "$account" . --include="*.py" | head -5
   done
   
   cd /Users/cezarmihaila/workspace/composer2
   # Repeat search
   ```

3. **Document Findings:**
   - Create `docs/monitor_total_cost/fashionnova_etl_sources.md`
   - For each major table, document:
     - DAG name and file path
     - Refresh schedule (daily, hourly, etc.)
     - Purpose and dependencies
     - Estimated non-BigQuery costs (Dataflow, GCS, etc.)

**Example Documentation:**

```markdown
### monitor-base-us-prod.monitor_base.shipments

**ETL Source:** Monitor Base Merge Pipeline

**Service Account:** `monitor-base-us-prod@appspot.gserviceaccount.com`

**DAG Location:** `composer2/dags/monitor_base_merge.py` (example)

**Schedule:** Continuous (streaming + periodic batch merges)

**Purpose:** Consolidates shipment data from all retailers into shared infrastructure table

**Production Costs:**
- BigQuery Compute: $149,832/year (merge operations)
- BigQuery Storage: $24,899/year (active + long-term)
- Pub/Sub: $26,226/year (data ingestion)
- Dataflow: Unknown (may be included in compute)
- GCS: Minimal (transient staging)

**Total Annual Cost:** $200,957

**Attribution Model:** Hybrid (40% queries, 30% slot-hours, 30% TB scanned)
```

---

### PHASE 3: Cost Attribution Model Development

**Objective:** Create and validate fair methodology to distribute production costs across retailers.

**Estimated Time:** 2-3 hours  
**Estimated Cost:** $0.05 - $0.20

---

#### Step 3.1: Calculate Total Platform Metrics

**Goal:** Get denominators for attribution formulas.

**SQL Query:** Add to `queries/monitor_total_cost/04_calculate_production_cost_attribution.sql`

```sql
-- ============================================================================
-- Calculate Total Monitor Platform Metrics
-- ============================================================================
-- Get totals across ALL Monitor retailers for attribution denominators
-- ============================================================================

DECLARE target_periods ARRAY<STRING> DEFAULT ['Peak_2024_2025', 'Baseline_2025_Sep_Oct'];

WITH all_monitor_retailers AS (
  SELECT
    retailer_moniker,
    COUNT(*) AS total_queries,
    SUM(slot_hours) AS total_slot_hours,
    SUM(total_billed_bytes) / POW(1024, 4) AS total_tb_scanned
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE consumer_subcategory = 'MONITOR'
    AND analysis_period_label IN UNNEST(target_periods)
    AND total_slot_ms IS NOT NULL
    AND retailer_moniker IS NOT NULL
  GROUP BY retailer_moniker
)

SELECT
  -- Platform totals
  SUM(total_queries) AS platform_total_queries,
  SUM(total_slot_hours) AS platform_total_slot_hours,
  SUM(total_tb_scanned) AS platform_total_tb_scanned,
  
  -- fashionnova metrics
  SUM(IF(retailer_moniker = 'fashionnova', total_queries, 0)) AS fashionnova_queries,
  SUM(IF(retailer_moniker = 'fashionnova', total_slot_hours, 0)) AS fashionnova_slot_hours,
  SUM(IF(retailer_moniker = 'fashionnova', total_tb_scanned, 0)) AS fashionnova_tb_scanned,
  
  -- fashionnova percentages
  ROUND(SUM(IF(retailer_moniker = 'fashionnova', total_queries, 0)) / SUM(total_queries) * 100, 2) AS fashionnova_query_pct,
  ROUND(SUM(IF(retailer_moniker = 'fashionnova', total_slot_hours, 0)) / SUM(total_slot_hours) * 100, 2) AS fashionnova_slot_pct,
  ROUND(SUM(IF(retailer_moniker = 'fashionnova', total_tb_scanned, 0)) / SUM(total_tb_scanned) * 100, 2) AS fashionnova_tb_pct

FROM all_monitor_retailers;
```

**Expected Output:**
```
platform_total_queries: 205,483
platform_total_slot_hours: ~25,000 (calculated)
platform_total_tb_scanned: ~500 TB (estimated)

fashionnova_queries: 5,911 (2.88%)
fashionnova_slot_hours: 13,628 (54.5% - likely!)
fashionnova_tb_scanned: ~275 TB (55% - estimated)
```

**Key Insight:** fashionnova likely consumes disproportionately high slot-hours and data volume relative to query count!

---

#### Step 3.2: Apply Hybrid Attribution Formula

**Goal:** Calculate fashionnova's fair share of production costs using weighted model.

**Formula:**
```
fashionnova_attribution_weight = 
  0.40 × (fashionnova_queries / platform_total_queries) +
  0.30 × (fashionnova_slot_hours / platform_total_slot_hours) +
  0.30 × (fashionnova_tb_scanned / platform_total_tb_scanned)
```

**Example Calculation for monitor_base.shipments:**

Assumptions:
- fashionnova queries: 2.88% of total
- fashionnova slot-hours: 54.5% of total (high!)
- fashionnova TB scanned: 55% of total (high!)

```
fashionnova_weight = 
  0.40 × 0.0288 +
  0.30 × 0.545 +
  0.30 × 0.55
  = 0.01152 + 0.1635 + 0.165
  = 0.34002 (34.0%)

fashionnova_production_cost = $200,957 × 0.34 = $68,325/year
```

**Wow!** fashionnova's production cost could be **$68K/year** - compare to $673 consumption cost!

**SQL Implementation:**
```sql
-- For each table, calculate fashionnova's attributed production cost
WITH attribution_weights AS (
  SELECT
    table_reference,
    
    -- Usage metrics per table (from Phase 1)
    fashionnova_queries / platform_total_queries AS query_weight,
    fashionnova_slot_hours / platform_total_slot_hours AS slot_weight,
    fashionnova_tb_scanned / platform_total_tb_scanned AS tb_weight,
    
    -- Hybrid formula
    (0.40 × fashionnova_queries / platform_total_queries +
     0.30 × fashionnova_slot_hours / platform_total_slot_hours +
     0.30 × fashionnova_tb_scanned / platform_total_tb_scanned) AS attribution_weight,
    
    -- Production cost from Phase 2
    table_annual_production_cost
    
  FROM table_usage_metrics  -- Joined from Phase 1 & 2 outputs
)

SELECT
  table_reference,
  table_annual_production_cost,
  attribution_weight,
  table_annual_production_cost × attribution_weight AS fashionnova_attributed_cost,
  'HYBRID_40_30_30' AS attribution_method
FROM attribution_weights
ORDER BY fashionnova_attributed_cost DESC;
```

**Expected Output:** `results/fashionnova_production_cost_breakdown.csv`

```
table_reference                              | table_annual_production_cost | attribution_weight | fashionnova_attributed_cost
--------------------------------------------+-----------------------------+-------------------+---------------------------
monitor-base-us-prod.monitor_base.shipments | $200,957                    | 0.340             | $68,325
narvar-data-lake.reporting.t_return_details | $5,000                      | 0.120             | $600
... (other tables)                          | ...                         | ...               | ...
TOTAL                                       | $220,000 (estimated)        | N/A               | $72,000 (estimated)
```

---

#### Step 3.3: Validate Attribution Model

**Goal:** Sanity checks and sensitivity analysis.

**SQL Query:** `queries/monitor_total_cost/05_validate_attribution_model.sql`

**Validation Checks:**

1. **Sum to 100% Check:**
   ```sql
   -- Aggregate all retailer attributions for a given table
   -- Should sum to 1.0 (within 5% rounding error)
   SELECT
     table_reference,
     SUM(attribution_weight) AS total_attribution,
     ABS(SUM(attribution_weight) - 1.0) AS error_magnitude
   FROM all_retailer_attributions  -- Full 284-retailer version
   GROUP BY table_reference
   HAVING error_magnitude > 0.05;  -- Flag errors >5%
   ```

2. **Correlation Check:**
   ```sql
   -- Compare production cost attribution to consumption cost
   -- Should be correlated but not identical
   SELECT
     retailer_moniker,
     consumption_cost_usd,
     production_cost_usd,
     production_cost_usd / consumption_cost_usd AS production_to_consumption_ratio
   FROM retailer_total_costs
   ORDER BY production_to_consumption_ratio DESC;
   
   -- Expected: Most retailers have ratio between 0.5 and 5.0
   -- Outliers need investigation
   ```

3. **Top Retailer Check:**
   ```sql
   -- Top 20 retailers should have majority of production costs
   -- (similar to consumption concentration)
   SELECT
     SUM(IF(cost_rank <= 20, production_cost_usd, 0)) / SUM(production_cost_usd) AS top20_production_share,
     SUM(IF(cost_rank <= 20, consumption_cost_usd, 0)) / SUM(consumption_cost_usd) AS top20_consumption_share
   FROM retailer_total_costs;
   
   -- Expected: Both >80% (high concentration)
   ```

4. **Sensitivity Analysis:**
   ```sql
   -- Test alternative weight combinations
   WITH weight_scenarios AS (
     SELECT retailer_moniker,
       
       -- Scenario 1: Equal weights
       (0.33 × query_weight + 0.33 × slot_weight + 0.34 × tb_weight) AS equal_weights,
       
       -- Scenario 2: Query-heavy
       (0.60 × query_weight + 0.20 × slot_weight + 0.20 × tb_weight) AS query_heavy,
       
       -- Scenario 3: Slot-heavy
       (0.20 × query_weight + 0.60 × slot_weight + 0.20 × tb_weight) AS slot_heavy,
       
       -- Scenario 4: Our hybrid (baseline)
       (0.40 × query_weight + 0.30 × slot_weight + 0.30 × tb_weight) AS hybrid_baseline
       
     FROM retailer_metrics
   )
   
   -- Check if retailer rankings change significantly
   SELECT
     retailer_moniker,
     RANK() OVER (ORDER BY equal_weights DESC) AS rank_equal,
     RANK() OVER (ORDER BY query_heavy DESC) AS rank_query,
     RANK() OVER (ORDER BY slot_heavy DESC) AS rank_slot,
     RANK() OVER (ORDER BY hybrid_baseline DESC) AS rank_hybrid
   FROM weight_scenarios
   WHERE retailer_moniker = 'fashionnova';
   ```

**Validation Report:** `docs/monitor_total_cost/ATTRIBUTION_MODEL_VALIDATION.md`

Document:
- All validation check results
- Outliers and explanations
- Sensitivity analysis findings
- Stakeholder review and approval

---

### PHASE 4: Total Cost Aggregation (fashionnova PoC)

**Objective:** Combine consumption + production costs into single Total Cost report.

**Estimated Time:** 2-3 hours  
**Estimated Cost:** $0.05 (mostly analysis, minimal queries)

---

#### Step 4.1: Aggregate Total Costs

**SQL Query:** `queries/monitor_total_cost/06_fashionnova_total_cost_summary.sql`

```sql
-- ============================================================================
-- fashionnova Total Cost Summary
-- ============================================================================
-- Combine consumption and production costs
-- ============================================================================

WITH consumption_costs AS (
  -- From MONITOR_2025_ANALYSIS_REPORT.md
  SELECT
    'fashionnova' AS retailer_moniker,
    5911 AS total_queries,
    13628.21 AS total_slot_hours,
    673.32 AS consumption_cost_usd,
    'Peak_2024_2025 + Baseline_2025_Sep_Oct' AS time_period,
    -- Extrapolate to annual (5 months → 12 months)
    673.32 * (12.0 / 5.0) AS annual_consumption_cost_usd
),

production_costs AS (
  -- From Phase 3 attribution
  SELECT
    'fashionnova' AS retailer_moniker,
    SUM(fashionnova_attributed_cost) AS production_cost_usd
  FROM `results.fashionnova_production_cost_breakdown`
)

SELECT
  c.retailer_moniker,
  c.total_queries,
  c.total_slot_hours,
  
  -- Costs
  c.annual_consumption_cost_usd,
  p.production_cost_usd AS annual_production_cost_usd,
  c.annual_consumption_cost_usd + p.production_cost_usd AS total_annual_cost_usd,
  
  -- Cost breakdown percentages
  ROUND(c.annual_consumption_cost_usd / (c.annual_consumption_cost_usd + p.production_cost_usd) * 100, 1) AS consumption_pct,
  ROUND(p.production_cost_usd / (c.annual_consumption_cost_usd + p.production_cost_usd) * 100, 1) AS production_pct,
  
  -- Cost per query (including production overhead)
  ROUND((c.annual_consumption_cost_usd + p.production_cost_usd) / (c.total_queries * 12.0 / 5.0), 4) AS cost_per_query_usd,
  
  -- Production/Consumption ratio
  ROUND(p.production_cost_usd / c.annual_consumption_cost_usd, 2) AS production_to_consumption_ratio

FROM consumption_costs c
CROSS JOIN production_costs p;
```

**Expected Output:**

```
retailer_moniker: fashionnova
total_queries: 5,911 (5 months) → 14,186 (12 months)
total_slot_hours: 13,628

annual_consumption_cost_usd: $1,616
annual_production_cost_usd: $72,000
total_annual_cost_usd: $73,616

consumption_pct: 2.2%
production_pct: 97.8%

cost_per_query_usd: $5.19 (vs $0.11 consumption-only!)
production_to_consumption_ratio: 44.6x
```

**Key Insight:** Production costs **massively dominate** total costs for Monitor platform!

---

#### Step 4.2: Generate fashionnova Total Cost Report

**Deliverable:** `docs/monitor_total_cost/FASHIONNOVA_TOTAL_COST_ANALYSIS.md`

**Report Structure:**

```markdown
# fashionnova Total Cost of Ownership Analysis - Monitor Platform

**Date:** November 2025
**Retailer:** fashionnova
**Analysis Period:** Peak_2024_2025 + Baseline_2025_Sep_Oct (extrapolated to annual)

---

## Executive Summary

fashionnova's **Total Annual Cost** for Monitor platform: **$73,616**

**Cost Breakdown:**
- **Query Execution (Consumption):** $1,616 (2.2%)
- **Data Production (ETL + Storage + Infrastructure):** $72,000 (97.8%)

**Key Findings:**
- fashionnova pays **44.6x more** for data production than data consumption
- Primary cost driver: `monitor-base-us-prod.monitor_base.shipments` (93% of production cost)
- fashionnova is **disproportionately expensive** due to high slot-hours consumption (54.5% of platform total)
- Cost per query: **$5.19** (including production overhead) vs $0.11 (consumption only)

**Immediate Actions:**
1. **Query Optimization (HIGH):** Reduce fashionnova's 54.5% slot-hour consumption
   - Expected savings: $10K-$20K/year in production attribution
   - Also reduces consumption cost and QoS violations (24.8% → <5%)

2. **Production Efficiency (MEDIUM):** Optimize monitor_base.shipments merge operations
   - Expected savings: $20K-$40K/year platform-wide
   - Benefits all retailers proportionally

3. **Cost Recovery (STRATEGIC):** Evaluate pricing model for fashionnova
   - Current cost: $73,616/year
   - Current pricing: Unknown (business decision)

---

## Detailed Cost Analysis

### Consumption Costs (Query Execution)

**From MONITOR_2025_ANALYSIS_REPORT.md:**

| Metric | 5-Month Value | Annual Estimate |
|--------|---------------|-----------------|
| Total Queries | 5,911 | 14,186 |
| Slot-Hours Consumed | 13,628 | 32,707 |
| BigQuery Execution Cost | $673 | $1,616 |
| Avg Cost per Query | $0.114 | $0.114 |
| QoS Violation Rate | 24.8% | 24.8% |

**Breakdown by Reservation Type:**
- RESERVED_SHARED_POOL: $673 (100% - fashionnova uses only RESERVED)
- ON_DEMAND: $0 (0%)

### Production Costs (Data Creation & Maintenance)

**Attribution Methodology:** Hybrid multi-factor model
- 40% by Query Count
- 30% by Slot-Hours Consumed
- 30% by Data Volume Scanned

**fashionnova Usage Metrics:**
- Query Count: 2.88% of platform total (5,911 / 205,483)
- Slot-Hours: 54.5% of platform total (13,628 / 25,000 est.)
- TB Scanned: 55% of platform total (275 TB / 500 TB est.)
- **Weighted Attribution:** 34.0%

**Table-by-Table Production Cost Attribution:**

| Table Reference | Annual Production Cost | fashionnova Attribution % | Attributed Cost |
|-----------------|------------------------|---------------------------|-----------------|
| monitor-base-us-prod.monitor_base.shipments | $200,957 | 34.0% | $68,325 |
| narvar-data-lake.reporting.t_return_details | $5,000 | 12.0% | $600 |
| [Other tables] | $15,000 | [Various] | $3,075 |
| **TOTAL** | **$220,957** | **32.6% avg** | **$72,000** |

**Major Production Cost Components:**
- BigQuery Compute (merge operations): $54,000 (75%)
- BigQuery Storage (active + long-term): $9,000 (12.5%)
- Pub/Sub (message delivery): $9,000 (12.5%)

---

## Cost Drivers Analysis

### Top 5 Tables by fashionnova Production Cost

1. **monitor-base-us-prod.monitor_base.shipments** - $68,325/year (95%)
   - Shared infrastructure table serving all retailers
   - fashionnova uses 34% of production capacity
   - Optimization: Reduce query frequency, implement caching

2. **narvar-data-lake.reporting.t_return_details** - $600/year (0.8%)
   - Returns/refunds data
   - Relatively efficient usage

3. [Other tables with minimal costs]

**Key Insight:** 95% of production cost comes from single table (monitor_base.shipments)

---

## Optimization Recommendations

### Priority 1: Query Optimization (HIGH IMPACT)

**Target:** Reduce fashionnova's slot-hour consumption from 54.5% to <20% of platform

**Strategies:**
1. Partition pruning: Add date filters to reduce data scanned
2. Query caching: Implement result caching for repeated queries
3. Denormalization: Create fashionnova-specific materialized views
4. Query complexity reduction: Simplify joins and aggregations

**Expected Impact:**
- Consumption cost reduction: $673 → $300 (-$373/year)
- Production cost reduction: $72,000 → $30,000 (-$42,000/year)
- QoS improvement: 24.8% violations → <5% (-20 percentage points)
- **Total Annual Savings: $42,373**

**ROI:** High - query optimization benefits both consumption and production costs

---

### Priority 2: Production Efficiency (MEDIUM IMPACT)

**Target:** Optimize monitor_base.shipments merge operations platform-wide

**Strategies:**
1. Batch optimization: Consolidate small frequent merges
2. Incremental processing: Reduce full-table scans
3. Partition strategy: Implement partition pruning in merge logic
4. Resource scheduling: Run merges during off-peak hours

**Expected Impact:**
- Platform-wide production cost: $200,957 → $150,000 (-$50,957/year)
- fashionnova attribution (34%): $68,325 → $51,000 (-$17,325/year)

**ROI:** Medium - requires engineering effort, benefits all retailers

---

### Priority 3: Cost Recovery (STRATEGIC)

**Analysis:**
- fashionnova's total annual cost: $73,616
- fashionnova's revenue to Narvar: Unknown (business decision)
- Cost recovery ratio: Unknown

**Recommendations:**
1. Review pricing model: Is fashionnova priced appropriately for usage?
2. Implement usage-based pricing: Charge for high slot-hour consumption
3. Set usage quotas: Limit queries or encourage optimization
4. Transparent cost sharing: Show fashionnova their cost impact

---

## Comparison to Other Retailers

**fashionnova vs Platform Average:**

| Metric | fashionnova | Platform Avg | Ratio |
|--------|-------------|--------------|-------|
| Queries/Year | 14,186 | 8,723 | 1.6x |
| Slot-Hours/Year | 32,707 | 1,054 | 31.0x |
| Consumption Cost/Year | $1,616 | $107 | 15.1x |
| Production Cost/Year | $72,000 | $778 | 92.6x |
| **Total Cost/Year** | **$73,616** | **$885** | **83.2x** |
| Cost per Query | $5.19 | $0.10 | 51.9x |

**Key Insight:** fashionnova is **83x more expensive** than average Monitor retailer!

---

## Validation & Limitations

### Model Validation

✅ **Sum to 100% Check:** All retailer attributions sum to 99.8% (within acceptable range)
✅ **Correlation Check:** Production costs correlate with consumption costs (R² = 0.85)
✅ **Top Retailer Check:** Top 20 retailers = 89% of production costs (expected concentration)
✅ **Sensitivity Analysis:** ±10% weight changes do not alter top retailer rankings significantly

### Limitations

❌ **Attribution Model:** No single "perfect" fair allocation model exists
❌ **Time Lag:** Production costs incurred when data created, consumption when queried (temporal mismatch)
❌ **Shared Infrastructure:** monitor_base.shipments serves all retailers; marginal cost per retailer may be lower than average cost
❌ **Incomplete Mapping:** Some table production costs estimated (missing Dataflow/GCS costs)

---

## Appendix

### Data Sources
- `narvar-data-lake.query_opt.traffic_classification` (consumption metrics)
- `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` (ETL job costs)
- `MONITOR_2025_ANALYSIS_REPORT.md` (existing consumption analysis)
- `MONITOR_MERGE_COST_FINAL_RESULTS.md` (monitor_base.shipments production cost)

### SQL Queries
- `queries/monitor_total_cost/01_extract_referenced_tables.sql`
- `queries/monitor_total_cost/02_resolve_view_dependencies.sql`
- `queries/monitor_total_cost/03_map_tables_to_etl_jobs.sql`
- `queries/monitor_total_cost/04_calculate_production_cost_attribution.sql`
- `queries/monitor_total_cost/05_validate_attribution_model.sql`
- `queries/monitor_total_cost/06_fashionnova_total_cost_summary.sql`

### Analysis Cost
- BigQuery query execution: $0.50
- Human analysis time: 8 hours
- Total project cost: $0.50 (BQ) + minimal compute

---

**Report Status:** ✅ COMPLETE - Ready for stakeholder review
**Next Steps:** Validate findings, optimize queries, scale to all 284 retailers
```

---

### PHASE 5: Scale to All Retailers

**Objective:** Apply validated model to all 284 retailers.

**Estimated Time:** 4-6 hours  
**Estimated Cost:** $1.00 - $5.00

---

#### Step 5.1: Batch Process All Retailers

**Modified SQL:** Extend Phase 1-4 queries to all retailers

Key changes:
```sql
-- Instead of:
WHERE retailer_moniker = 'fashionnova'

-- Use:
WHERE retailer_moniker IN (
  SELECT DISTINCT retailer_moniker
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE consumer_subcategory = 'MONITOR'
    AND analysis_period_label IN UNNEST(target_periods)
    AND retailer_moniker IS NOT NULL
)
```

**Execution Strategy:**
1. Run table extraction for all retailers (Step 1.1 modified)
2. Resolve views once (Step 1.2 - views same for all retailers)
3. Calculate attribution for each retailer (Step 3.2 modified)
4. Generate summary for all 284 retailers (Step 4.1 modified)

**Optimization:**
- Use clustering on `retailer_moniker` for performance
- Consider breaking into batches of 50 retailers if single query times out
- Cache intermediate results to avoid reprocessing

---

#### Step 5.2: Generate Comprehensive Total Cost Report

**Deliverable:** `MONITOR_2025_TOTAL_COST_ANALYSIS_REPORT.md`

**New Sections to Add:**

1. **Total Cost Rankings** (replace/augment existing consumption-only rankings)
   - Top 20 retailers by total cost (consumption + production)
   - Compare to consumption-only rankings (how much does ranking change?)

2. **Production Cost Concentration Analysis**
   - Top 20 retailers' share of production costs
   - Compare to consumption cost concentration

3. **Cost Efficiency Metrics**
   - Cost per query (including production overhead)
   - Production/Consumption ratio by retailer
   - Identify most/least efficient retailers

4. **Retailer Tiers by Total Cost**
   - High-cost (>$10K/year): X retailers
   - Medium-cost ($1K-$10K/year): Y retailers
   - Low-cost (<$1K/year): Z retailers

5. **Production/Consumption Ratio Analysis**
   - Distribution plot of production/consumption ratios
   - Identify outliers (high production vs consumption or vice versa)
   - Explain patterns (e.g., high-frequency simple queries vs low-frequency complex queries)

---

#### Step 5.3: Create Cost Attribution Dashboard

**Jupyter Notebook:** `notebooks/monitor_total_cost_analysis.ipynb`

**Visualizations:**

1. **Stacked Bar Chart: Consumption vs Production by Retailer**
   ```python
   import pandas as pd
   import matplotlib.pyplot as plt
   
   # Load data
   df = pd.read_csv('results/all_retailers_total_cost.csv')
   df = df.sort_values('total_annual_cost_usd', ascending=False).head(30)
   
   # Create stacked bar chart
   fig, ax = plt.subplots(figsize=(14, 8))
   ax.bar(df['retailer_moniker'], df['annual_consumption_cost_usd'], 
          label='Consumption', color='#3498db')
   ax.bar(df['retailer_moniker'], df['annual_production_cost_usd'], 
          bottom=df['annual_consumption_cost_usd'],
          label='Production', color='#e74c3c')
   
   ax.set_xlabel('Retailer')
   ax.set_ylabel('Annual Cost (USD)')
   ax.set_title('Monitor Platform Total Cost by Retailer (Top 30)')
   ax.legend()
   plt.xticks(rotation=90)
   plt.tight_layout()
   plt.savefig('../images/monitor_total_cost_by_retailer.png', dpi=300)
   ```

2. **Scatter Plot: Production vs Consumption Cost**
   ```python
   # Identify outliers
   fig, ax = plt.subplots(figsize=(12, 10))
   scatter = ax.scatter(
       df['annual_consumption_cost_usd'],
       df['annual_production_cost_usd'],
       s=df['total_queries'] / 10,  # Size by query count
       alpha=0.6,
       c=df['production_to_consumption_ratio'],
       cmap='viridis'
   )
   
   # Add diagonal line (equal production/consumption)
   max_val = max(df['annual_consumption_cost_usd'].max(), 
                  df['annual_production_cost_usd'].max())
   ax.plot([0, max_val], [0, max_val], 'k--', alpha=0.3, label='Equal costs')
   
   # Label high-cost retailers
   for idx, row in df.head(10).iterrows():
       ax.annotate(row['retailer_moniker'], 
                   (row['annual_consumption_cost_usd'], 
                    row['annual_production_cost_usd']),
                   fontsize=8)
   
   ax.set_xlabel('Annual Consumption Cost (USD)')
   ax.set_ylabel('Annual Production Cost (USD)')
   ax.set_title('Production vs Consumption Cost by Retailer')
   ax.set_xscale('log')
   ax.set_yscale('log')
   plt.colorbar(scatter, label='Production/Consumption Ratio')
   plt.legend()
   plt.tight_layout()
   plt.savefig('../images/monitor_production_vs_consumption_scatter.png', dpi=300)
   ```

3. **Heatmap: Table Usage by Retailer**
   ```python
   import seaborn as sns
   
   # Load table usage matrix
   usage_matrix = pd.read_csv('results/retailer_table_usage_matrix.csv')
   usage_pivot = usage_matrix.pivot(index='retailer_moniker', 
                                     columns='table_reference', 
                                     values='reference_count')
   
   # Top 50 retailers × top 50 tables
   usage_pivot = usage_pivot.iloc[:50, :50]
   
   # Create heatmap
   fig, ax = plt.subplots(figsize=(20, 16))
   sns.heatmap(usage_pivot, cmap='YlOrRd', ax=ax, cbar_kws={'label': 'Query Count'})
   ax.set_title('Table Usage Heatmap (Top 50 Retailers × Top 50 Tables)')
   ax.set_xlabel('Table Reference')
   ax.set_ylabel('Retailer')
   plt.tight_layout()
   plt.savefig('../images/monitor_table_usage_heatmap.png', dpi=300)
   ```

4. **Pie Chart: Total Cost Distribution**
   ```python
   # Top 20 vs Long Tail
   top20_cost = df.head(20)['total_annual_cost_usd'].sum()
   total_cost = df['total_annual_cost_usd'].sum()
   longtail_cost = total_cost - top20_cost
   
   fig, ax = plt.subplots(figsize=(10, 10))
   ax.pie([top20_cost, longtail_cost], 
          labels=['Top 20 Retailers', 'Remaining 264 Retailers'],
          autopct='%1.1f%%',
          colors=['#e74c3c', '#95a5a6'],
          startangle=90)
   ax.set_title(f'Total Cost Distribution\n(Total: ${total_cost:,.0f}/year)')
   plt.tight_layout()
   plt.savefig('../images/monitor_cost_concentration_pie.png', dpi=300)
   ```

**Export all charts to:** `images/monitor_total_cost_*.png`

---

### PHASE 6: Integration & Recommendations

**Objective:** Integrate findings with existing analysis and provide actionable recommendations.

**Estimated Time:** 3-4 hours  
**Estimated Cost:** $0 (documentation only)

---

#### Step 6.1: Update MONITOR_2025_ANALYSIS_REPORT.md

**New Sections to Add:**

1. **After "💰 Cost Analysis" section, add:**

```markdown
## 💰 Total Cost Analysis (Consumption + Production)

### **Total Monitor Platform Cost: $XXX,XXX/year**

| Cost Component | Annual Cost | % of Total |
|----------------|-------------|------------|
| **Data Consumption (Query Execution)** | $X,XXX | X% |
| **Data Production (ETL + Storage + Infrastructure)** | $XXX,XXX | XX% |
| **TOTAL** | **$XXX,XXX** | **100%** |

**Critical Finding:** Production costs are **XXx higher** than consumption costs. Simply analyzing query execution costs misses XX% of total Monitor platform costs!

### **Production Cost Drivers**

Top 5 tables by production cost:

1. **monitor-base-us-prod.monitor_base.shipments** - $200,957/year (XX% of production)
   - Shared infrastructure serving all 284 retailers
   - Merge operations: $149,832, Storage: $24,899, Pub/Sub: $26,226

2. [Other tables...]

### **Total Cost Rankings** (Replaces or augments existing cost rankings)

**Top 20 Retailers by Total Cost (Consumption + Production):**

| Rank | Retailer | Consumption | Production | Total | % of Platform |
|------|----------|-------------|-----------|-------|---------------|
| 1 | fashionnova | $1,616 | $72,000 | $73,616 | 25% |
| 2 | [retailer 2] | ... | ... | ... | ...% |
...

**Key Changes from Consumption-Only Rankings:**
- fashionnova moves from #1 to #1 (remains highest)
- High-volume simple query retailers move down (low production attribution)
- Complex query retailers move up (high production attribution)

### **Production/Consumption Ratio Analysis**

| Retailer Segment | Avg Ratio | Interpretation |
|------------------|-----------|----------------|
| **High-complexity queries** | 30-50x | Disproportionately expensive production costs |
| **High-frequency simple queries** | 1-5x | Efficient usage |
| **Platform Average** | 15x | Production costs dominate |

**fashionnova:** 44.6x ratio - highest in platform!
```

2. **Update "Critical Issues & Optimization Targets" section:**

Add production cost context to each optimization:
- fashionnova optimization: $42K/year savings (combined consumption + production)
- Shared infrastructure optimization: Platform-wide benefits

3. **Update "Next Steps" section:**

Add production cost optimization actions:
- Optimize monitor_base.shipments merge operations
- Implement query result caching to reduce ETL pressure
- Evaluate materialized views for high-cost retailers

---

#### Step 6.2: Create Optimization Playbook

**Deliverable:** `docs/monitor_total_cost/OPTIMIZATION_PLAYBOOK.md`

**Structure:**

```markdown
# Monitor Platform Optimization Playbook
**Total Cost Reduction Strategies (Consumption + Production)**

---

## Strategy 1: Query Optimization (HIGH IMPACT)

**Target:** Reduce query complexity and slot-hour consumption

**Benefits:**
- ✅ Reduces consumption costs (query execution)
- ✅ Reduces production costs (lower data access attribution)
- ✅ Improves QoS (faster queries)
- ✅ Reduces capacity stress (lower slot usage)

**Tactics:**

### Tactic 1.1: Partition Pruning
**What:** Add date/timestamp filters to all queries
**Target:** Queries scanning full tables without filters
**Expected Savings:** 30-50% slot-hour reduction per query
**Implementation:**
```sql
-- Before (bad)
SELECT * FROM monitor_base.shipments WHERE order_id = 'ABC123';

-- After (good)
SELECT * FROM monitor_base.shipments 
WHERE order_id = 'ABC123' 
  AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY);
```

### Tactic 1.2: Query Result Caching
**What:** Cache frequently-run identical queries
**Target:** Repeated queries within 24-hour window
**Expected Savings:** Eliminates 20-40% of redundant queries
**Implementation:** Enable BigQuery query result caching (ON by default)

### Tactic 1.3: Materialized Views
**What:** Pre-compute expensive aggregations
**Target:** Complex queries with GROUP BY, window functions
**Expected Savings:** 50-80% slot-hour reduction for cached aggregations
**Implementation:**
```sql
CREATE MATERIALIZED VIEW monitor_base.daily_shipment_summary AS
SELECT 
  DATE(created_at) as shipment_date,
  retailer_moniker,
  COUNT(*) as shipment_count,
  AVG(processing_time_seconds) as avg_processing_time
FROM monitor_base.shipments
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
GROUP BY 1, 2;
```

---

## Strategy 2: Production Efficiency (MEDIUM IMPACT)

**Target:** Optimize ETL jobs and merge operations

**Benefits:**
- ✅ Reduces production costs platform-wide
- ✅ Benefits all retailers proportionally
- ✅ Reduces BigQuery capacity stress
- ❌ Does not reduce consumption costs

**Tactics:**

### Tactic 2.1: Batch Merge Optimization
**What:** Consolidate frequent small merges into larger batches
**Target:** monitor_base.shipments merge operations
**Expected Savings:** $30K-$50K/year platform-wide
**Implementation:** Adjust Airflow DAG schedule from continuous to hourly batches

### Tactic 2.2: Incremental Processing
**What:** Process only changed data, not full table scans
**Target:** ETL jobs with full table refresh
**Expected Savings:** 40-60% slot-hour reduction in ETL
**Implementation:** Use `_PARTITIONTIME` or timestamp columns for incremental logic

### Tactic 2.3: Off-Peak Scheduling
**What:** Run ETL jobs during low-traffic hours (2-6 AM)
**Target:** Large batch jobs and merges
**Expected Savings:** Reduces peak capacity stress, improves QoS for queries
**Implementation:** Adjust Airflow DAG schedules

---

## Strategy 3: Retailer Engagement (STRATEGIC)

**Target:** Work with high-cost retailers to optimize usage patterns

**Benefits:**
- ✅ Targeted optimization with highest ROI
- ✅ Educates retailers on cost-efficient practices
- ✅ Improves retailer satisfaction (better QoS)
- ✅ Enables data-driven pricing discussions

**Tactics:**

### Tactic 3.1: Cost Transparency Reports
**What:** Provide retailers with monthly cost reports
**Target:** All retailers, focus on top 20
**Expected Impact:** 10-30% voluntary usage reduction
**Implementation:** Generate monthly reports from total cost analysis

### Tactic 3.2: Best Practices Training
**What:** Educate retailers on efficient query patterns
**Target:** High-cost retailers (fashionnova, etc.)
**Expected Impact:** 20-40% query optimization
**Implementation:** Webinars, documentation, one-on-one consultations

### Tactic 3.3: Usage-Based Pricing
**What:** Charge retailers based on total cost (not flat rate)
**Target:** High-cost retailers exceeding thresholds
**Expected Impact:** Cost recovery and usage reduction incentives
**Implementation:** Business decision (requires contract changes)

---

## Priority Matrix

| Strategy | Impact | Effort | ROI | Priority |
|----------|--------|--------|-----|----------|
| Query Optimization (fashionnova) | $42K/year | Medium | Very High | **P0** |
| Production Efficiency (merge ops) | $50K/year | High | High | **P1** |
| Materialized Views | $20K/year | Medium | High | **P1** |
| Off-Peak Scheduling | QoS improvement | Low | High | **P2** |
| Retailer Engagement | Variable | Ongoing | Medium | **P2** |

---

## Success Metrics

Track monthly:
1. Total platform cost (consumption + production)
2. Per-retailer total cost
3. Production/Consumption ratio
4. Top 20 cost concentration percentage
5. Query optimization adoption rate
6. QoS violation rate

Target: 30% total cost reduction within 12 months
```

---

## 📅 Timeline & Dependencies

### Critical Path

```
Phase 1: Table Discovery (fashionnova PoC)
  ├─ Step 1.1: Extract referenced tables [2 hrs]
  ├─ Step 1.2: Resolve view dependencies [1 hr]
  └─ Step 1.3: Flag monitor_base.shipments [0.5 hr]
  TOTAL: 3.5 hours

Phase 2: ETL Source Discovery
  ├─ Step 2.1: Search audit logs for ETL [2 hrs]
  ├─ Step 2.2: Handle monitor_base.shipments [0.5 hr]
  └─ Step 2.3: Cross-reference Composer DAGs [1 hr, manual]
  TOTAL: 3.5 hours

Phase 3: Cost Attribution Model
  ├─ Step 3.1: Calculate platform totals [0.5 hr]
  ├─ Step 3.2: Apply attribution formula [1 hr]
  └─ Step 3.3: Validate model [1 hr]
  TOTAL: 2.5 hours

Phase 4: Total Cost Aggregation (fashionnova PoC)
  ├─ Step 4.1: Aggregate total costs [0.5 hr]
  └─ Step 4.2: Generate fashionnova report [2 hrs]
  TOTAL: 2.5 hours

CHECKPOINT: Review fashionnova PoC with stakeholders [1 hr]

Phase 5: Scale to All Retailers
  ├─ Step 5.1: Batch process all retailers [2 hrs]
  ├─ Step 5.2: Generate comprehensive report [2 hrs]
  └─ Step 5.3: Create Jupyter notebook visualizations [2 hrs]
  TOTAL: 6 hours

Phase 6: Integration & Recommendations
  ├─ Step 6.1: Update MONITOR_2025_ANALYSIS_REPORT.md [2 hrs]
  └─ Step 6.2: Create optimization playbook [2 hrs]
  TOTAL: 4 hours

TOTAL PROJECT TIME: 22 hours (~3 days)
```

### Parallel Work Opportunities

- Phase 2.3 (Composer DAG review) can run parallel to Phase 3 (attribution model)
- Phase 5.3 (visualizations) can run parallel to Phase 6.1 (report updates)

### Dependencies

**Phase 1 → Phase 2:** Must know which tables to search for in audit logs  
**Phase 2 → Phase 3:** Need production costs before attribution  
**Phase 3 → Phase 4:** Need attribution before aggregation  
**Phase 4 → Phase 5:** Must validate PoC before scaling  
**Phase 5 → Phase 6:** Need full results before integration

**External Dependencies:**
- Access to `cloudaudit_googleapis_com_data_access` audit logs
- Access to Composer repositories (manual review)
- Stakeholder availability for PoC review

---

## 💰 Cost & Risk Assessment

### BigQuery Query Costs

| Phase | Query Type | Estimated Scan | Estimated Cost |
|-------|-----------|----------------|----------------|
| Phase 1 | INFORMATION_SCHEMA.JOBS_BY_PROJECT | ~10 GB | $0.10 |
| Phase 2 | Audit log historical scan | ~50-100 GB | $0.50-$1.00 |
| Phase 3 | Calculations only | ~5 GB | $0.05 |
| Phase 4 | Aggregations | ~5 GB | $0.05 |
| Phase 5 | Scale to 284 retailers | ~100-200 GB | $1.00-$2.00 |
| **TOTAL** | | **~200-350 GB** | **$2.00-$3.50** |

**Plus contingency for iterations/debugging:** +$0.50-$2.00  
**Total Estimated Cost:** $2.50-$5.50 (well within budget)

### Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| **Query text parsing fails** | Low | Medium | Use INFORMATION_SCHEMA.referenced_tables (done) |
| **View recursion too deep** | Medium | Low | Limit to 3 levels, document limitation |
| **Incomplete ETL mapping** | Medium | Medium | Focus on BigQuery evidence, document unknowns |
| **Attribution model disputed** | Low | High | Validation + stakeholder review + sensitivity analysis |
| **BigQuery costs exceed budget** | Low | Low | Dry-run queries, monitor costs, stop if >$10 |
| **fashionnova PoC finds major issues** | Medium | High | Fix before scaling (that's why we do PoC!) |
| **Stakeholder rejects findings** | Low | High | Transparent methodology, multiple validation checks |

### Risk Mitigation Strategies

1. **Incremental Approach:** fashionnova PoC before full-scale (built into plan)
2. **Cost Monitoring:** Dry-run all expensive queries before execution
3. **Transparent Documentation:** Detailed methodology and validation
4. **Stakeholder Engagement:** Early review of PoC findings
5. **Fallback Plans:** Alternative attribution models if primary disputed

---

## ✅ Success Criteria

### Must-Have Success Criteria

1. ✅ **Coverage:** Map 90%+ of tables used by Monitor queries to production sources
2. ✅ **Accuracy:** Attribution model sums to 100% within 5% rounding error
3. ✅ **Validation:** fashionnova PoC reviewed and approved before scaling
4. ✅ **Scalability:** All 284 retailers analyzed within budget (<$10 BigQuery)
5. ✅ **Actionability:** Generate 5+ specific optimization recommendations with ROI
6. ✅ **Documentation:** Comprehensive reports usable by business stakeholders

### Nice-to-Have Success Criteria

1. 🎯 **Automation:** SQL queries reusable for future periods
2. 🎯 **Visualization:** Professional charts for executive presentations
3. 🎯 **Framework:** Methodology extensible to Hub, Looker, Metabase
4. 🎯 **Integration:** Seamless integration with existing Monitor analysis
5. 🎯 **Business Impact:** Inform pricing/contract decisions

### Failure Criteria (Stop/Rethink)

❌ **Attribution model validation fails** (doesn't sum to 100%, major outliers unexplained)  
❌ **BigQuery costs exceed $10** (query optimization needed)  
❌ **Major tables unmapped** (<80% coverage)  
❌ **Stakeholder rejects methodology** (need alternative approach)

---

## 🚀 Future Extensions

### Phase 7: Other Platforms (Future Work)

**Apply same methodology to:**
- **Hub (Looker dashboards):** Already high QoS violations (39.4% during peak)
- **Looker:** Business intelligence platform
- **Metabase:** Internal analytics
- **Analytics API:** Backend API queries

**Estimated Effort:** 1-2 days per platform (faster with framework in place)

### Phase 8: Real-Time Cost Tracking (Future)

**Goal:** Automate daily cost attribution updates

**Approach:**
- Scheduled BigQuery scripts (daily/weekly)
- Looker dashboard for real-time cost visibility
- Alerts for cost threshold breaches

**Benefits:**
- Proactive cost management
- Detect anomalies quickly
- Enable self-service cost reporting

### Phase 9: Cost Forecasting (Future)

**Goal:** Predict future costs based on growth trends

**Approach:**
- Time-series analysis of historical costs
- Retailer growth projections
- Scenario modeling (new retailers, usage growth)

**Benefits:**
- Budget planning
- Capacity planning
- Pricing model optimization

### Phase 10: Chargeback System (Future)

**Goal:** Implement internal cost allocation system

**Approach:**
- Monthly retailer invoices (internal or external)
- Usage-based pricing tiers
- Cost transparency portal for retailers

**Benefits:**
- Cost recovery
- Incentivize efficient usage
- Fair resource allocation

---

## 📚 References

### Related Documents

**Existing Analyses:**
- `MONITOR_2025_ANALYSIS_REPORT.md` - Consumption cost analysis (baseline)
- `MONITOR_MERGE_COST_FINAL_RESULTS.md` - monitor_base.shipments production cost ($200,957/year)
- `AI_SESSION_CONTEXT.md` - Overall project context
- `PHASE1_FINAL_REPORT.md` - Traffic classification results (43.8M jobs)

**Supporting Documents:**
- `PEAK_2025_2026_STRATEGY_EXEC_REPORT.md` - Strategic recommendation
- `ROOT_CAUSE_ANALYSIS_FINDINGS.md` - Capacity stress root causes
- `INV6_HUB_QOS_RESULTS.md` - Hub QoS crisis (39.4% violations)

### Data Sources

**Primary:**
- `narvar-data-lake.query_opt.traffic_classification` - 205,483 Monitor queries classified
- `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` - Full query text, audit logs

**Secondary:**
- `region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT` - Referenced tables metadata
- `region-us.INFORMATION_SCHEMA.VIEWS` - View definitions
- `region-us.INFORMATION_SCHEMA.TABLES` - Table metadata

**External:**
- `/Users/cezarmihaila/workspace/composer/` - Airflow DAG definitions
- `/Users/cezarmihaila/workspace/composer2/` - Airflow DAG definitions (newer)

### SQL Query Locations

All queries stored in:
`queries/monitor_total_cost/`

1. `01_extract_referenced_tables.sql`
2. `02_resolve_view_dependencies.sql`
3. `03_map_tables_to_etl_jobs.sql`
4. `04_calculate_production_cost_attribution.sql`
5. `05_validate_attribution_model.sql`
6. `06_fashionnova_total_cost_summary.sql`
7. `07_all_retailers_total_cost.sql` (Phase 5)

---

## 📝 Appendix

### Cost Attribution Formula Details

**Hybrid Multi-Factor Model:**

```
For each retailer R and table T:

usage_metrics = {
  query_count_R_T: # of queries by R accessing T
  slot_hours_R_T: slot-hours consumed by R on queries accessing T
  tb_scanned_R_T: TB scanned by R on queries accessing T
}

platform_totals = {
  total_query_count_T: sum of query_count_R_T across all retailers
  total_slot_hours_T: sum of slot_hours_R_T across all retailers
  total_tb_scanned_T: sum of tb_scanned_R_T across all retailers
}

weights = {
  w_queries: 0.40 (40%)
  w_slots: 0.30 (30%)
  w_tb: 0.30 (30%)
}

attribution_R_T = 
  w_queries × (query_count_R_T / total_query_count_T) +
  w_slots × (slot_hours_R_T / total_slot_hours_T) +
  w_tb × (tb_scanned_R_T / total_tb_scanned_T)

attributed_cost_R_T = production_cost_T × attribution_R_T

total_production_cost_R = sum(attributed_cost_R_T) across all tables T
```

**Example:**

fashionnova accessing monitor_base.shipments:
- query_count: 5,911 / 205,483 = 0.0288 (2.88%)
- slot_hours: 13,628 / 25,000 = 0.545 (54.5%)
- tb_scanned: 275 / 500 = 0.55 (55%)

attribution = 0.40 × 0.0288 + 0.30 × 0.545 + 0.30 × 0.55 = 0.340 (34%)

attributed_cost = $200,957 × 0.34 = $68,325

### Validation Formulas

**Sum to 100% Check:**
```
For each table T:
  sum(attribution_R_T) across all retailers R should equal 1.0 ± 0.05
```

**Correlation Check:**
```
Pearson correlation coefficient between:
  X = consumption_cost_R (per retailer)
  Y = production_cost_R (per retailer)

Expected: r > 0.7 (strong positive correlation)
```

**Concentration Check:**
```
top20_share = sum(total_cost_R for R in top 20) / sum(total_cost_R for all R)

Expected: top20_share > 0.80 (high concentration similar to consumption)
```

### Glossary

**Consumption Cost:** Cost incurred when queries execute (BigQuery slot-hours × rate)

**Production Cost:** Cost incurred to create and maintain data (ETL, storage, infrastructure)

**Attribution:** Process of distributing shared production costs to individual retailers

**Hybrid Model:** Attribution model using multiple weighted factors (not single metric)

**monitor_base.shipments:** Shared infrastructure table serving all Monitor retailers

**Slot-Hours:** BigQuery compute capacity measure (concurrent slots × time)

**QoS (Quality of Service):** Measure of query performance (SLA: <60 seconds)

**PoC (Proof-of-Concept):** Initial validation using single retailer (fashionnova) before full-scale

---

## 📧 Contact & Collaboration

### Project Team

**Lead Analyst:** AI Assistant (Claude Sonnet 4.5)  
**Data Owner:** Cezar Mihaila  
**Stakeholders:** Data Engineering, Platform Engineering, Finance, Customer Success

### Questions & Feedback

For questions about this plan:
1. Review existing related documents (see References section)
2. Check AI_SESSION_CONTEXT.md for overall project context
3. Consult with project team

### Version History

- **v1.0 (2025-11-14):** Initial comprehensive planning document created
- **Future versions:** Track major changes and stakeholder feedback

---

**Document Status:** ✅ READY FOR EXECUTION  
**Next Step:** Begin Phase 1 (fashionnova PoC) with stakeholder approval

---

*End of Planning Document*

