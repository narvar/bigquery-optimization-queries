<!-- Peak 2025 PRD requirements authored by GPT Codex -->
# Peak 2025 BigQuery Slot Optimization — PRD Requirements

## 1. Context & Goals
- Portfolio of 2,600+ BigQuery projects shares an enterprise reservation of 1,700 slots (`500 + 500` committed, `700` PAYG) provisioned in `bq-narvar-admin`.
- Slot pricing assumptions (Enterprise edition, `us` multi-region) from [BigQuery pricing](https://cloud.google.com/bigquery/pricing):
  - 3-year CUD: `$0.048/slot-hour`
  - 1-year CUD: `$0.054/slot-hour`
  - On-demand/PAYG: `$0.06/slot-hour`
- Current portfolio mix (500 × 1-year CUD, 500 × 3-year CUD, 700 × PAYG) yields a theoretical all-in cost of ~`$67.9K/month` (assuming 730 hrs/month). Reported spend (~`$60K/month`) implies ~88% utilization or partial on-demand relief; cost modeling must reconcile this gap.
- Three critical consumer segments must be protected during the Nov 2025 – Jan 2026 peak window:
  - `Critical External Consumers` (retailer-facing monitor & hub projects).
  - `Critical Automated Processes` (service-account driven pipelines: Composer, Airflow, CDP, etc.).
  - `Internal Users` (BI, exploratory workloads, primarily Metabase).
- Objective: ensure Quality of Service (QoS) for the first two segments and acceptable service for Internal Users, with no slot cost increase if possible and minimal incremental spend otherwise.

## 2. Success Criteria
- QoS thresholds defined, measured, and met for each segment (see §6).
- Forecasted slot demand for peak 2025 published with 95% confidence intervals and scenario commentary.
- Slot allocation simulations delivered (shared vs. partitioned reservations, on-demand overflow) with quantified cost deltas.
- Actionable reservation configuration recommendations, including required purchasing timeline if additional commitments are needed.
- Reusable analytics framework (parameterized queries, notebooks, dashboards) for future peak planning cycles.

## 3. Scope Definition
### In Scope
- Consumer classification mapping (projects, service accounts, retailer monikers).
- Seasonal workload analysis using historical audit logs (>= Apr 2022).
- QoS baseline and incident review aligned to audit log metrics.
- Forecasting models for slot demand and latency risk during peak.
- Simulation of reservation policies and cost impacts.
- Governance & monitoring recommendations (alerts, dashboards, runbooks).

### Out of Scope
- Non-BigQuery data platforms.
- Real-time orchestration changes (handled by platform teams after recommendations).
- One-off query rewrites; only pattern-level optimization guidance.

## 4. Stakeholders & Roles
- **Program Sponsor:** VP Data & Analytics.
- **Capacity Operations:** Narvar SRE / Data Infra team (owns reservations & Composer configs).
- **Analytics Engineering:** Maintains `narvar/audit_log` queries, develops new parameterized SQL / notebooks.
- **Retailer Success:** Interfaces with external consumers during peak readiness.
- **Finance / Procurement:** Oversees commitment changes.

## 5. Data Sources & Tooling Requirements
- **Primary logs:** `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` (DoIt CMP export). Ensure retention for >= 3 years.
- **Retailer mapping:** `reporting.t_return_details` for monitor project hashing (query snippet supplied by user).
- **Service account inventory:** IAM audit / Composer repos (user to confirm authoritative list).
- **Existing SQL assets:** `narvar/audit_log/*.sql` with `_general` variants for broader filtering.
- **BI usage metadata:** Metabase internal tables or access logs for user attribution (pending validation).
- **Version control:** Work performed in repository branch + `narvar/analysis_peak_2025_gpt_codex` subfolder.
- **Computation environment:** BigQuery (US multi-region). Enforce dry-runs for >=10 GB scans and surface estimated costs.

## 6. Quality of Service Definitions
| Segment | QoS KPI | Threshold | Notes |
| --- | --- | --- | --- |
| Critical External Consumers | Query end-to-end latency | < 60 seconds flagged, < 30 seconds target | Prioritize deterministic SLAs; consider slot pre-allocation & high-priority reservations. |
| Critical Automated Processes | Schedule adherence | Completion before next scheduled run | Align with Composer DAGs / Airflow SLAs; monitor retry counts and backlog. |
| Internal Users | Query latency | < 5–10 minutes acceptable | Encourage workload management and scheduled windows. |

Additional metrics: concurrency saturation (% of slots utilized), queued job counts, on-demand spillover, QUERY_INTERACTIVE vs BATCH mix.

## 7. Existing Asset Audit & Gaps
### Reusable Queries
- `general_job_information_general.sql`, `query_job_information_general.sql`: baseline job inventory & slot usage.
- `slots_by_hour_general.sql`, `slots_by_day_general.sql`, `slots_by_minute_general.sql`: temporal slot trends for peak vs off-peak comparisons.
- `query_slots_per_minute_general.sql`, `query_slots_per_second_general.sql`: high-resolution query slots outputs for QoS diagnostics.
- `concurrent_queries_by_minute_general.sql`: supports contention analysis.
- `top_cost_users_general.sql`, `top_cost_user_by_region_and_project.sql`: user/project cost attribution.
- `top_complex_queries_general.sql`, `longest_running_queries_general.sql`: candidate QoS violators.
- `billing_recommendations_per_query_general.sql`: informs PAYG vs committed trade-offs.

### Identified Gaps
- **Consumer tagging:** Need standardized mapping tables for monitor projects, hub service accounts, Composer DAG ownership, Metabase users (not present in repo).
- **QoS state tracking:** Queries lack explicit latency SLA checks (need derived metrics vs thresholds).
- **Incident cataloguing:** No existing linkage between historical QoS breaches and remediation outcomes.
- **Forecasting artifacts:** No time-series models or reusable Python notebooks in repo.
- **Simulation tooling:** Absent scripts to emulate slot allocation scenarios or reservation adjustments.

## 8. Functional Requirements
1. **Classification Layer**
   - Create canonical lookup tables for project → retailer, service account → process, user → department.
   - Enforce parameterized BigQuery SQL (DECLARE date ranges, category filters) for reproducibility.

2. **Historical Analysis**
   - Support configurable windows: baseline (rolling 28/90 days), past peaks (Nov–Jan 2022/23/24), pre-peak (Aug–Oct 2025), live peak tracking (Nov 2025–Jan 2026).
   - Produce aggregated dashboards (hourly/daily) and anomaly detection (e.g., >90th percentile slot usage spikes).
   - Derive a root-job lens by excluding child script jobs (`parentJobName IS NOT NULL`) to avoid inflated slot/cost tallies; maintain ability to roll child metrics back to parents when necessary.

3. **QoS Monitoring**
   - Derive per-category latency, queue time, slot utilization percentiles.
   - Flag threshold breaches and correlate with reservation utilization and concurrency.
   - Incorporate incident annotations (change freezes, outages).

4. **Forecasting & Scenario Modeling**
   - Fit at least two forecasting approaches (e.g., Holt-Winters/Prophet and ARIMA with exogenous regressors) using 3+ years of slot demand.
   - Model growth drivers (retailer adds, automation, internal adoption) via categorical weights.
   - Generate slot demand projections with P50/P95 bounds for each segment.

5. **Simulation Engine**
   - Evaluate reservations: shared pool vs. segment-specific slot commitments, plus hybrid (critical reserved + internal PAYG).
   - Calculate impact on QoS metrics and cost under scenarios: (a) status quo, (b) internal throttling, (c) additional 200–400 committed slots, (d) temporary PAYG bursts.
   - Incorporate BigQuery reservation APIs / FLEX slots for short-term bursts (if available).

6. **Reporting & Communication**
   - Produce PRD deliverable with recommendations, required investment, and implementation checklist.
   - Provide Metabase / Looker dashboards for near real-time monitoring.
   - Define alerting thresholds for SRE hand-off (Stackdriver metrics, Looker alerts).

## 9. Non-Functional Requirements
- **Parameterization:** All SQL must use `DECLARE` for time windows, project lists, and category filters.
- **Cost Controls:** Execute dry runs when estimated scanned data >10 GB; log cost estimates in analysis notebooks.
- **Reusability:** Modular notebooks and SQL macros to reuse filtering logic across future peak analyses.
- **Observability:** Versioned documentation (Markdown) with change logs.
- **Security:** No credentials or sensitive data embedded; leverage service account roles for data pulls.
- **Performance:** Aggregations should leverage partitioned tables and cached intermediate results to minimize new slot consumption.

## 10. Dependencies & Assumptions
- Access to historical DoIt logs remains intact and queryable at required granularity.
- Retailer moniker → monitor project mapping consistent with hashing convention.
- Composer repositories expose DAG schedules and owners for SLA mapping.
- Metabase auditing enabled to resolve individual analysts; otherwise require product change.
- Reservation management via `gcloud` / BigQuery Reservation API available to capacity team.

## 11. Risks & Mitigations
- **Data Gaps:** Missing audit logs or incomplete service account metadata → mitigate with targeted exports or alternative telemetry (e.g., INFORMATION_SCHEMA.JOBS).
- **Forecast Drift:** Pandemic or macro events altering peak behavior → use scenario-based adjustments and sensitivity analysis.
- **Reservation Change Lead Time:** Procurement cycles for new commitments → define deadlines (e.g., finalize by Sep 2025).
- **Cross-team Alignment:** Coordination across retailers, automation owners → set decision checkpoints and RACI.

## 12. Open Questions
1. Confirmation of authoritative list of hub projects and service accounts.
2. Composer repository locations and DAG schedule metadata sources.
3. Availability of Metabase audit logs linking service account queries to end users.
4. Target decision date for reservation changes vs. finance approval windows.
5. Appetite for adopting FLEX slots or temporary PAYG caps during peak.

---
Document owner: GPT Codex (Oct 31 2025).

