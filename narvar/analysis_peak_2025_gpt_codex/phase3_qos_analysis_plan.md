# Phase 3 — Seasonal Traffic & QoS Analysis

_Last updated: 2025-11-03_

## 1. Target Analysis Windows

| Window | Dates (UTC) | Purpose | Notes |
| --- | --- | --- | --- |
| Historical Peak FY22 | 2021-11-01 – 2022-01-15 | Baseline for first pandemic-era peak | Extend to Jan 15 to capture return surge. |
| Baseline FY22 | 2021-08-01 – 2021-10-31 | Preceding steady state | Establish pre-peak regression inputs for FY22. |
| Historical Peak FY23 | 2022-11-01 – 2023-01-15 | YOY comparison | Align with FY22 range for clean YOY deltas. |
| Baseline FY23 | 2022-08-01 – 2022-10-31 | Preceding steady state | Baseline for FY23 regression. |
| Historical Peak FY24 | 2023-11-01 – 2024-01-15 | Most recent completed peak | Use for latency + reservation decisions. |
| Baseline FY24 | 2023-08-01 – 2023-10-31 | Pre-peak traffic | Baseline for FY24 regression. |
| Current Baseline FY25 | 2025-08-01 – 2025-10-31 | Pre-peak traffic | Guides expected slot needs entering peak. |
| Rolling 90-day | CURRENT_DATE() - 90 -> today | Detect longer-term trends | Parameterizable for dashboards. |
| Rolling 28-day | CURRENT_DATE() - 28 -> today | Monthly variance | Use in alerting. |
| Rolling 7-day | CURRENT_DATE() - 7 -> today | Weekly incident detection | Primary for near-real-time QoS. |

### Window configuration (BigQuery pseudo-code)
```sql
CREATE TEMP TABLE qos_windows AS
SELECT 'peak_fy22' AS window_id,
       TIMESTAMP('2021-11-01') AS start_ts,
       TIMESTAMP('2022-01-15') AS end_ts UNION ALL
SELECT 'peak_fy23', TIMESTAMP('2022-11-01'), TIMESTAMP('2023-01-15') UNION ALL
SELECT 'peak_fy24', TIMESTAMP('2023-11-01'), TIMESTAMP('2024-01-15') UNION ALL
SELECT 'baseline_fy25', TIMESTAMP('2025-08-01'), TIMESTAMP('2025-10-31') UNION ALL
SELECT 'rolling_90d', TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY), CURRENT_TIMESTAMP() UNION ALL
SELECT 'rolling_28d', TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 28 DAY), CURRENT_TIMESTAMP() UNION ALL
SELECT 'rolling_07d', TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY), CURRENT_TIMESTAMP();
```

## 2. Datasets & Filters

| Dataset | Usage | Filters |
| --- | --- | --- |
| `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` | Primary job facts | Reuse Phase 2 filters (non-null principals, exclude dry runs, script job child ids, include `include_child_jobs` hook for future). |
| `narvar-data-lake.analytics.consumer_classification_overrides` | Consumer labels | Join on `principal_email` to resolve overrides. |
| `narvar-data-lake.analytics.consumer_classification_staging` *(future table)* | Optional materialized view from Phase 2 staging | If materialized, reduces repeated heavy scans. |
| `narvar-data-lake.INFORMATION_SCHEMA.JOBS_BY_PROJECT` *(optional)* | Queue times, slot reservation info | Required for wait time: `reservation_id`, `parent_job_id`, `total_slot_ms`, `start_time`, `end_time`, `creation_time`. |
| Reservation metadata (`bq-narvar-admin` project) | Reservation capacity | Pull `capacity_commitments`, `reservations`, `assignments` to compare concurrency vs. slot allocation. |
| Change calendar source | Annotate incidents | Need pointer to release schedule or incident log (to be provided by stakeholders). |

## 3. Next Steps

1. Materialize `qos_windows` helper view (or parameter set) for reuse in SQL.
2. Build 10-minute slot usage aggregates per window:
   - `new_audit_sql/phase3_qos_slot_usage_10min.sql` (classification + slot metrics per 10-minute bucket; scoped to configurable window list).
   - Store results in staging tables for each window (peak & baseline) to avoid repeated long scans.
3. Spike detection pipeline:
   - Compute rolling baseline (median + MAD) per classification and flag buckets > baseline + k*MAD.
   - Collapse adjacent spike buckets into events, capturing duration, max/avg slot usage, queue times, and classification mix.
   - Output tables `qos_spikes_<window>` and `qos_spike_mix_<window>`.
4. Extend notebook visualizations: time-series with spike overlays, classification mix bars, KPI summary (spikes per week, % slot hours in spikes, etc.).
5. Annotate incidents by joining metrics to change calendar and reservation assignment events.

## 4. TODO Tracking

- [ ] Implement SQL macros/views using `qos_windows` (or an equivalent table) to simplify repeated window filters.
- [ ] Confirm availability of INFORMATION_SCHEMA fields for queue latency/ reservation usage.
- [ ] Ingest reservation capacity snapshots for FY22–FY25 peaks.
- [ ] Design spike detection thresholds (baseline + MAD vs percentile) per classification.
- [ ] Schedule staging-table refresh cadence (monthly for historical, daily for rolling windows).

---
Prepared by GPT Codex.
