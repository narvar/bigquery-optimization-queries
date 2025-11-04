<!-- Peak 2025 execution roadmap authored by GPT Codex -->
# Peak 2025 BigQuery Slot Optimization — Execution Plan

## Overview
Purpose: Deliver a reusable analytical framework and final PRD that secures QoS for critical workloads during Nov 2025 – Jan 2026 while containing slot costs.

Projected timeline assumes kickoff in Nov 2025 with PRD sign-off by mid-Sep 2025 (two months before peak). Adjust dates based on actual start.

## Phase 0 — Project Setup (Week 0)
- Branch off main repository; place documentation under `narvar/analysis_peak_2025_gpt_codex`.
- Validate access to `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` and supporting datasets.
- Agree on tooling stack (BigQuery, Python notebooks, Metabase/Looker dashboards) and cost guardrails.

## Phase 1 — Baseline Asset Audit (Weeks 1–2)
- Review `narvar/audit_log` SQL suite:
  - Map each query to analysis needs (job inventory, costs, slots, concurrency, users).
  - Document parameter patterns (DECLARE blocks) and identify missing filters (category tags, QoS metrics).
- Add parent/child job assessment: verify presence of `protoPayload.serviceData.jobCompletedEvent.job.jobStatistics.parentJobName` and design reusable root-job filter to prevent duplicate slot counts.
- Gap analysis deliverable summarizing required new assets (classification tables, QoS checks, forecasting models).
- Confirm long-term log retention and data volume for peak windows; schedule dry runs and estimate costs (warn on >10 GB scans).

## Phase 2 — Consumer Classification Framework (Weeks 2–4)
- Build canonical mappings:
  - Monitor projects ↔ retailers (hash-based logic via `reporting.t_return_details`).
  - Hub services (e.g., `looker-prod@narvar-data-lake.iam.gserviceaccount.com`) and other shared accounts.
  - Automated processes (Composer, Airflow, CDP) from repository metadata.
  - Internal users via Metabase access logs; define fallback if user-level detail unavailable.
- Store mappings in parameterized views or temporary tables; ensure repeatable refresh cadence.
- Capture unresolved classifications in shared tracker for stakeholder input.

## Phase 3 — Seasonal Traffic & QoS Analysis (Weeks 4–7)
- Define analysis windows: historical peaks (Nov–Jan 2022/23/24), current year baseline (Aug–Oct 2025), rolling 90/28/7-day views.
- Extend existing SQL to compute QoS metrics:
  - Query latency distributions, queue times, slot utilization percentiles.
  - Concurrency vs. reservation capacity, on-demand overflow detection.
- Annotate incidents (slowdowns, quota exhaustion) by correlating latency spikes with change calendars.
- Produce dashboards/notebooks summarizing per-category QoS, highlighting harmful queries (< thresholds above).

## Phase 4 — Forecasting & Simulation Design (Weeks 7–11)
- **Forecasting:**
  - Prepare time-series datasets (slots/hour, concurrency, queued jobs) segmented by consumer category.
  - Fit multiple models (Prophet with holiday regressors, SARIMAX with retailer onboarding features, Gradient Boosted Trees for leading indicators).
  - Validate using backtesting across prior peaks; report MAE/MAPE and residual diagnostics.
- **Scenario Modeling:**
  - Simulate slot demand under growth assumptions (conservative/base/optimistic) per category.
  - Evaluate reservation strategies:
    - Shared 1,700 slots with priority boosts.
    - Critical segments isolated with dedicated reservations; internal users on PAYG or throttled scheduling.
    - Temporary FLEX or PAYG expansion (use Enterprise edition rates: `$0.06` default, `$0.054` 1-year CUD, `$0.048` 3-year CUD per [BigQuery pricing](https://cloud.google.com/bigquery/pricing)).
  - Quantify QoS impacts (predicted latency vs. thresholds) and cost deltas for each simulation.

## Phase 5 — Recommendation Synthesis & PRD Assembly (Weeks 11–13)
- Consolidate findings into `prd_requirements.md` & PRD narrative:
  - Proposed reservation adjustments (commitment sizes, timeline, ownership).
  - Required process changes (e.g., Metabase query scheduling, retailer SLAs).
  - Monitoring & escalation runbooks.
- Draft implementation backlog (SQL enhancements, dashboards, automation scripts) aligned to responsible teams.
- Prepare exec summary highlighting trade-offs and budget implications.

## Phase 6 — Sign-off & Handoff (Week 14)
- Review PRD with stakeholders (Data Infra, Finance, Retailer Success).
- Capture approval or change requests; iterate as needed.
- Handoff finalized assets: documentation, notebooks, dashboards, simulation outputs, and runbooks.

## Workstreams & Owners
- **Analytics Engineering:** SQL enhancements, notebook development, forecasting.
- **Data Infra / SRE:** Reservation configuration, QoS monitoring integration, alerting.
- **Product Analytics:** Requirements validation, retailer communication.
- **Finance:** Cost modeling validation, commitment procurement.

## Deliverables Checklist
- Updated mapping views/tables for consumer classification.
- Historical QoS analysis reports & dashboards (per category).
- Forecast models with documented methodology and accuracy metrics.
- Slot allocation simulation results (tables + narrative).
- Final PRD and executive summary.
- Operational runbook (alert thresholds, escalation paths).

## Measurement & KPIs
- Forecast accuracy (MAPE ≤ 10% at weekly resolution for critical segments).
- QoS compliance rate during simulated peak ≥ 99% for critical segments, ≥ 95% for internal users.
- Reservation utilization between 60–85% during peak (prevents under/over-provisioning).
- Slot cost variance ≤ ±15% vs. forecast during peak, using `$0.0547` effective blended slot-hour rate derived from current commitment mix; track incremental on-demand spend separately.

## Risk Management
- **Data completeness:** Establish automated checks for missing audit log days; fallback to `INFORMATION_SCHEMA.JOBS_*` where needed.
- **Model drift:** Schedule quarterly forecast refresh; maintain feature store for new regressors.
- **Process adoption:** Run training for Metabase/internal teams on scheduling & throttling policies.
- **Tooling performance:** Monitor cost of analytical queries; cache intermediate results and leverage materialized views.

## Communication Plan
- Weekly working-group sync (Analytics Engineering + Data Infra).
- Bi-weekly stakeholder updates with dashboard snapshots and risk log.
- Decision checkpoints:
  1. End Phase 2 — approve classification completeness.
  2. End Phase 4 — confirm scenario set & cost tolerances.
  3. Prior to Phase 6 — executive approval of reservation changes.

## Open Dependencies
- Composer repository access for DAG metadata.
- Metabase audit logging granularity (per-user vs. shared account).
- Confirmation of retailer onboarding roadmap for 2025 (affects demand growth).
- Finance guidance on commitment budget ceilings and approval lead time.

---
Document owner: GPT Codex (Oct 31 2025).

