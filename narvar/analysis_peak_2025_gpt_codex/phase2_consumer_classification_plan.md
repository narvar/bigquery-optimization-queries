# Phase 2 — Consumer Classification Framework

_Last updated: 2025-11-01_

## 1. Objective
Create reusable dimensions that map every BigQuery job principal to a business-facing consumer segment (retailer, hub service, automated workflow, internal user). Output should support slot/cost analyses, QoS monitoring, and executive rollups without re-running heavy joins in each query.

## 2. Current Signals & Datasets

| Signal | Dataset / Query | Notes | Status |
| --- | --- | --- | --- |
| Principal email, project, reservation usage | `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` | Primary fact source (audit logs). | Confirmed. Sampled last 7 days (scan 1.23 GB) → top principals dominated by service accounts (`gke-prod-20-sumatra@...`, `metabase-prod-access@...`, etc.). |
| Retailer list | `reporting.all_retailers` | Contains `retailer_moniker` list (2,286 rows). | Available; schema inspected. |
| Retailer ↔ category overrides | `reporting.manual_retailer_categories` | (`retailer`, `category`, `modified_ts`). Candidate for enrichment. | Available; 2,129 rows. |
| Cost attribution history | `analytics.noflake_query_costs` | Likely used for historical cost by user/project; schema not yet inspected. | TBD. |
| Service account registry | GCP IAM export (not in BigQuery) | Not discoverable in BQ; may require export or static config. | Missing. |
| Workflow metadata | Composer / Airflow DAG metadata (mentioned Phase 0 dependency) | Needs access to Composer repo. | Pending dependency. |

## 3. Classification Approach

### 3.1 Dimension Table Schema (proposal)
`analytics.consumer_classification` (materialized/managed via scheduled query)

| Column | Type | Source | Description |
| --- | --- | --- | --- |
| `principal_email` | STRING | Audit logs | Unique identifier (service account, user).
| `billing_project_id` | STRING | Audit logs | Owning billing project.
| `job_project_id` | STRING | Audit logs | Target project (where tables reside).
| `classification_type` | STRING | Derived | ENUM: `RETAILER`, `HUB_SERVICE`, `AUTOMATION`, `INTERNAL_USER`, `UNKNOWN`.
| `classification_subtype` | STRING | Derived | Retailer moniker, application name, environment (prod/qa), etc.
| `retailer_moniker` | STRING | Derived | Map when classification type is `RETAILER` or job project tied to retailer dataset.
| `source_confidence` | STRING | Derived | `AUTO`, `MANUAL_OVERRIDE`, `HEURISTIC`.
| `first_seen`, `last_seen` | TIMESTAMP | Aggregated from audit logs | Track freshness.
| `notes` | STRING | Manual annotations for exceptions.

### 3.2 Pipeline Steps
1. **Daily refresh job** (scheduled query or Dataform/DBT):
   - Ingest last 7 days of audit principals, union with historical dimension.
   - Update `last_seen` and create new rows for unseen principals.
2. **Classification logic layered as CTEs**:
   - **Manual overrides**: join to curated table (`analytics.consumer_classification_overrides`) maintained by Analytics Eng.
   - **Retailer detection**:
     - Map when principal email follows pattern `<retailer>-*@(narvar|external)` or job project matches retailer-specific project/dataset names (need curated crosswalk, e.g., from `reporting.manual_retailer_categories`).
   - **Hub services**:
     - Regex match on known services (`looker`, `metabase`, `monitor`, `messaging`, `analytics-api`, `airflow`, `gke`).
     - Associate to business owner + environment.
   - **Automation / Infrastructure**:
     - Domain `iam.gserviceaccount.com` with project prefixes (e.g., `narvar-ml-prod`, `dtpl-mgmt-prod`).
   - **Internal users**:
     - Emails ending in `@narvar.com` not already mapped to service categories.
3. **Exception surfacing**: produce daily diff of `UNKNOWN` principals for manual triage.

### 3.3 Supporting Assets
- `analytics.consumer_classification_overrides` (manual table with columns: `principal_email`, `classification_type`, `classification_subtype`, `retailer_moniker`, `notes`, `owner`, `updated_at`).
- `analytics.project_retailer_map` (derived from `reporting.manual_retailer_categories`, `reporting.all_retailers`, plus additional heuristics for dataset naming).
- Dashboard/notebook to monitor top `UNKNOWN` principals and volume by class.

## 4. Immediate To-Dos

1. **Schema Verification** (complete for key base tables; pending others like `analytics.noflake_query_costs`).
2. **Draft Classification SQL Skeleton**
   - `new_audit_sql/consumer_classification_staging.sql` now produces 7-day aggregates with heuristic labels, retaining a manual override hook.
3. **Manual Override Table Design & Seeding**
   - `analytics.consumer_classification_overrides` table created (BigQuery) with columns for manual classifications, owner, notes, and timestamp.
   - Seeded with top service accounts/users so overrides take effect immediately; governance owner set to `analytics_eng` (adjust as needed).
4. **Unknown Principal Alerting**
   - `new_audit_sql/consumer_classification_unknown_alert.sql` surfaces highest-volume `UNKNOWN` / `UNMAPPED` principals (default 7-day window, top 50).
   - Current coverage (7-day sample): ~3.6% of slot ms remains `UNKNOWN`; acceptable for Phase 3 kickoff.
5. **Documentation**
   - Add classification logic explanation to PRD (`prd_requirements.md`).

## 5. Open Questions / Dependencies

| Item | Status | Owner? |
| --- | --- | --- |
| Access to Composer/Airflow metadata for automation tagging | Pending | Data Infra |
| Confirmation of retailer project naming conventions | Needed | Product Analytics |
| Source of canonical service account registry (outside BQ) | Needed | Security / Platform |
| Stakeholder alignment on classification ENUMs | Needed | Analytics Eng + stakeholders |
| Override governance (who approves/updates) | Needed | TBD |
| Automation for weekly unknown review + override refresh | Needed | Analytics Eng |

## 6. Deferred Improvements

- Finalize governance for `consumer_classification_overrides` (approval workflow, change log).
- Automate ingestion of Composer/Airflow metadata to strengthen automation tagging.
- Expand retailer detection beyond email heuristics (project/dataset crosswalk, manual retailer categories).
- Schedule unknown-alert query + overrides merge as part of a weekly triage job.
- Backfill historical classification coverage to confirm unknown share remains <5% across peak seasons.

## 7. Cost Considerations

- 7-day principal aggregation scanned ~1.23 GB; safe for iterative development.
- Full backfill across 3.5 years would exceed 0.5 TB; plan incremental approach (e.g., monthly backfill batches) or leverage existing cost tables if available.
- Continue using `--dry_run` to gate queries; call out anything projected >10 GB before execution.

---
Prepared by GPT Codex — 2025-11-01.
