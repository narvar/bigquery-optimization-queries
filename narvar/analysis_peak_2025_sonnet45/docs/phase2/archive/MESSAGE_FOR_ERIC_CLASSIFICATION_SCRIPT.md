# Classification Script Overview for Eric

Hi Eric,

Here's a quick overview of the `run_classification_all_periods.py` script I've been using for the BigQuery capacity analysis:

---

## What It Does

Automatically classifies BigQuery audit log jobs into consumer categories (EXTERNAL, AUTOMATED, INTERNAL) for multiple time periods. Uses pattern matching on principal_email, project_id, and user_agent to categorize all BigQuery traffic.

**Current Version:** v1.4
- Monitor-base projects → AUTOMATED (not EXTERNAL)
- QoS threshold: 30s for EXTERNAL (down from 60s)

---

## Input

**Configuration (in script):**
- Period definitions with date ranges (9 periods from Sep 2022 - Oct 2025)
- Classification patterns (regex rules for categorization)
- QoS thresholds by category
- Set `skip: False` for periods you want to run

**Command Line:**
```bash
python run_classification_all_periods.py --mode all          # Run all non-skipped periods
python run_classification_all_periods.py --mode peak-only    # Only peak periods
python run_classification_all_periods.py --mode test         # First period only
python run_classification_all_periods.py --dry-run           # Cost estimation
```

**Data Source:**
- `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` (audit logs)
- `narvar-data-lake.reporting.t_return_details` (retailer mappings)

---

## Output

**BigQuery Table:** `narvar-data-lake.query_opt.traffic_classification`

**Schema Highlights:**
- Job identifiers: job_id, project_id, principal_email
- **Classifications:** consumer_category, consumer_subcategory, priority_level
- Resource metrics: slot_hours, execution_time_seconds, total_billed_gb
- **QoS metrics:** is_qos_violation, qos_violation_seconds
- Attribution: retailer_moniker (for MONITOR), metabase_user_id (for INTERNAL)
- Metadata: classification_date, classification_version, analysis_period_label

**Table Structure:**
- Partitioned by DATE(start_time)
- Clustered by consumer_category, classification_date
- Uses INSERT INTO (appends new versions, keeps history)

---

## Recent Run Results (v1.4 - Nov 6, 2025)

```
Period                    Jobs          Runtime   Unclassified
Baseline_2025_Sep_Oct     4,471,150     0.4 min   0.04%
Peak_2024_2025            4,721,623     0.3 min   0.05%
Peak_2023_2024            3,287,346     0.3 min   0.02%
TOTAL:                   12,480,119     1.0 min
```

**Note:** After classification, run `deduplicate_classification_table.py` to remove old versions and keep only latest.

---

## Key Classifications

**EXTERNAL (P0 - Customer-facing):**
- MONITOR: Retailer-specific monitor projects (monitor-{md5}-us-{env})
- HUB: Looker dashboards (looker service accounts)
- MONITOR_BASE: Infrastructure (NOW → AUTOMATED in v1.4)

**AUTOMATED (P0 - Backend processes):**
- AIRFLOW_COMPOSER, GKE_WORKLOAD, ETL_DATAFLOW, ML_INFERENCE, etc.
- Monitor-base (v1.4+)

**INTERNAL (P1 - Employee analytics):**
- METABASE, ADHOC_USER (@narvar.com), N8N_WORKFLOW

---

## Usage Notes

**Before running:**
1. Update PERIODS config (set skip=True/False)
2. Check/update CLASSIFICATION_VERSION if logic changed
3. Confirm analyze_periods in dependent Phase 2 queries match

**After running:**
1. Run deduplicate script to clean old versions
2. Validate unclassified % (<5% is excellent)
3. Re-run downstream Phase 2 analysis queries

---

Let me know if you have questions!

Cezar

