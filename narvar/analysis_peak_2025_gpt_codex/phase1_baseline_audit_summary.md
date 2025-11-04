# Phase 1 — Baseline Asset Audit (Progress Summary)

_Last updated: 2025-11-01_

## 1. Audit Log Query Inventory

| Query family | Representative files | Primary analysis need | Outputs | Notes |
| --- | --- | --- | --- | --- |
| Slot consumption (per second / minute / hour / day) | `slots_by_second*.sql`, `slots_by_minute*.sql`, `slots_by_hour*.sql`, `slots_by_day*.sql`, `slots_by_minute _and_user*.sql` | Slot demand profiles across time grains and user dimensions | Slot counts derived from `totalSlotMs` and time-expanded arrays | Copies under `baseline_audit_sql/` now accept `include_child_jobs` flag; default treats every job as root (no parent metadata available). |
| Query-only slot drills | `query_slots_per_second*.sql`, `query_slots_per_minute*.sql` | Slot focus on interactive queries | Query-only slot counts | Same parameterization as above. |
| Load job slot drills | `load_slots_per_second*.sql`, `load_slots_per_minute*.sql` | ETL/load slot footprints | Slot counts for load jobs | |
| Concurrency | `concurrent_queries_by_second*.sql`, `concurrent_queries_by_minute*.sql` | Concurrent query inventory vs. slot commitments | Concurrent job counts per second/minute | Uses `GENERATE_TIMESTAMP_ARRAY` expansion; de-dup by root job as above. |
| Costly queries | `top_costly_queries*.sql` | Identify repeated high-byte queries | Aggregated billed bytes + cost heuristics | Uses `SHA256(query)` grouping; still requires project substitution. |
| Top billed queries / labels / users | `top_billed_queries*.sql`, `top_billed_queries_deduplicated*.sql`, `top_billed_labels*.sql`, `top_cost_users*.sql` | Consumer cost accountability (users, labels, tables) | Totals and counts by selector | Require the same filters; currently missing parent-job handling (future enhancement consistent with slot views). |
| Billing recommendations | `billing_recommendations_per_query*.sql` | Query-level reservation vs. on-demand insights | Slot ms, concurrency, cost heuristics | Large query (~100 lines); still needs review for parent-job duplication risk. |
| Job inventory | `general_job_information*.sql`, `query_job_information*.sql`, `load_job_information*.sql`, `looker_job_information*.sql`, `jobs_in_regions.sql` | Job-level detail for diagnostics | Full job metadata | Prime candidates for parent-child enrichment when available. |
| Load/query counts | `query_counts*.sql`, `table_query_counts*.sql`, `query_slots_per_second_general.sql` | Workload sizing by table, user, or project | Aggregated counts | |
| Slot usage by reservation | `slot_usage_by_billing_project_and_project.sql`, `slots_by_day_general.sql` | Reservation utilization views | Slot ms by billing project and job project | |

## 2. Parameter Patterns & Gaps

- **Common DECLARE parameters**
  - `DECLARE interval_in_days INT64 DEFAULT <value>;` appears in every query.
  - Project-specific files rely on `protopayload_auditlog.servicedata_v1_bigquery.job.jobName.projectId = '<project-name>'` placeholder; general variants omit it.
  - Newly cloned queries introduce `DECLARE include_child_jobs BOOL DEFAULT FALSE;` to toggle parent filtering. Given audit logs lack `parentJobName`, the flag currently has no effect but future-proofs the interface once parent metadata is available.
- **Recurring filters**
  - `authenticationInfo.principalEmail` non-null, `dryRun IS NULL`, `jobId NOT LIKE 'script_job_%'`, time-window predicate on `timestamp` and sometimes on `jobStatistics.startTime`.
- **Missing / inconsistent filters**
  - No shared macro or parameter for billing project, region, or reservation; duplication across files encourages drift.
  - Lack of QoS filters (latency thresholds, queue duration) mentioned in execution plan.
  - No handling for cross-region analysis (`location` only selected, not filtered).
  - Parent-child de-duplication absent outside the slot/concurrency clones (due to missing metadata); cost-focused queries still double-count script fragments.

## 3. Gap Analysis & Proposed Assets

1. **Parent/child reconciliation view**
   - Build scheduled job to ingest `INFORMATION_SCHEMA.JOBS_BY_PROJECT` (contains `parent_job_id`) and blend with audit logs to faithfully identify root jobs.
   - Until then, document that counts may overstate cost/slots for script-heavy workloads.
2. **Parameter template**
   - Introduce shared template (e.g., SQL macro or external params config) to supply `project_id`, `interval_in_days`, `location`, `include_child_jobs` across all queries.
   - Consider storing defaults in a `.env` or parameter table to reduce manual editing.
3. **Classification join scaffolding**
   - Views needed for Phase 2 mapping (retailer, service account, automation). None of the current SQL references classification tables yet.
4. **QoS metric expansion**
   - Extend job information queries with wait time, execution time percentiles, and queued jobs detection to align with Phase 3 requirements.
5. **Materialized aggregates**
   - High-volume rollups (e.g., slot per second) may warrant scheduled materialized views to avoid repeated heavy scans during dashboards.

## 4. Data Retention & Volume Observations

- **Retention window**: `MIN(DATE(timestamp)) = 2022-04-19`, `MAX(DATE(timestamp)) = 2025-11-01`; roughly 3.5 years available. (Query processed ~3.16 GB.)
- **Recent activity** (2025-10-25 – 2025-11-01):
  - Job events per day range from ~0.29M to 9.1M (peak on 2025-10-29).
  - 7-day aggregation scan processed ~137 MB, well below cost guardrails.
- **Cost guidance**:
  - Continue running new diagnostics with `--dry_run`; flag >10 GB estimates before execution.
  - High-volume historical pulls (full retention) should be batched per month or restricted to relevant date ranges.

## 5. Next Actions

- Propagate `include_child_jobs` interface to remaining cost and job-information SQL, clarifying current limitation (no parent data).
- Draft parameter/template strategy (possibly via scripting or dbt) to avoid diverging filters.
- Begin design for parent-job enrichment pipeline using `INFORMATION_SCHEMA` (even if deemed impractical now, estimate effort and data latency).
- Plan QoS metric extensions (queue latency, reservation saturation) in upcoming phases.
- Coordinate with stakeholders on acceptable sampling windows for dashboards (e.g., rolling 28-day slot metrics vs. full retention analyses).
