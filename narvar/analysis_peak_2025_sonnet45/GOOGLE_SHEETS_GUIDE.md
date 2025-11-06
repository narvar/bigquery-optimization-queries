# Google Connected Sheets - Monitor Projects Analysis

**Updated**: November 6, 2025  
**Data Source**: `narvar-data-lake.query_opt.traffic_classification` (v1.4)  
**Period**: Baseline_2025_Sep_Oct

---

## How to Create Connected Sheet

### Step 1: Open Google Sheets
1. Create new Google Sheet
2. Go to **Data** → **Data connectors** → **Connect to BigQuery**

### Step 2: Choose "Custom Query"
1. Select **Custom query** (not table selection)
2. Choose project: `narvar-data-lake`

### Step 3: Paste Query
Copy the SQL from: `queries/google_sheets/baseline_2025_monitor_projects_detailed.sql`

Or use the query below:

```sql
SELECT
  project_id,
  
  -- Environment (PROD/QA/STG)
  CASE
    WHEN project_id LIKE '%-us-prod' THEN 'PROD'
    WHEN project_id LIKE '%-us-qa' THEN 'QA'
    WHEN project_id LIKE '%-us-stg' THEN 'STG'
    ELSE 'UNKNOWN'
  END as environment,
  
  -- Mapping status
  CASE
    WHEN consumer_subcategory = 'MONITOR' THEN 'MATCHED'
    WHEN consumer_subcategory = 'MONITOR_UNMATCHED' THEN 'UNMATCHED'
  END as mapping_status,
  
  retailer_moniker,
  
  COUNT(*) as total_jobs,
  COUNT(DISTINCT DATE(start_time)) as active_days,
  ROUND(SUM(slot_hours), 2) as total_slot_hours,
  ROUND(AVG(slot_hours), 4) as avg_slot_hours_per_job,
  ROUND(AVG(approximate_slot_count), 2) as avg_concurrent_slots,
  ROUND(AVG(execution_time_seconds), 2) as avg_exec_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)], 2) as p50_exec_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(95)], 2) as p95_exec_seconds,
  ROUND(APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(99)], 2) as p99_exec_seconds,
  MAX(execution_time_seconds) as max_exec_seconds,
  COUNTIF(is_qos_violation) as qos_violations,
  ROUND(COUNTIF(is_qos_violation) / COUNT(*) * 100, 2) as qos_violation_pct,
  ROUND(SUM(estimated_slot_cost_usd), 2) as total_cost_usd

FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE analysis_period_label = 'Baseline_2025_Sep_Oct'
  AND consumer_subcategory IN ('MONITOR', 'MONITOR_UNMATCHED')
GROUP BY project_id, consumer_subcategory, retailer_moniker
ORDER BY environment, total_slot_hours DESC;
```

### Step 4: Configure Refresh
- Set refresh schedule (e.g., daily, weekly, manual)
- Click **Connect**

---

## Data Summary (Excluding Monitor-Base)

### Baseline_2025_Sep_Oct - All Monitor Projects

**Total:** 422 unique monitor projects across all environments

| Environment | Mapping Status | Projects | Total Jobs | Slot Hours | Avg QoS Violation % |
|-------------|----------------|----------|------------|------------|---------------------|
| **PROD**    | MATCHED        | 208      | 88,313     | 31,572     | 0.39%               |
| **PROD**    | UNMATCHED      | 188      | 23,493     | 4,637      | 0.68%               |
| **QA**      | MATCHED        | 1        | 5,856      | 0          | 0%                  |
| **QA**      | UNMATCHED      | 12       | 71,736     | 2          | 0.03%               |
| **STG**     | MATCHED        | 4        | 4,995      | 21         | 0.1%                |
| **STG**     | UNMATCHED      | 9        | 11,751     | 130        | 0.01%               |
| **TOTAL**   | **ALL**        | **422**  | **206,144**| **36,362** | **0.42%**           |

---

### Key Insights

**1. PROD Environment (Most Important):**
- **396 unique PROD projects** (208 matched + 188 unmapped)
- **111,806 total jobs**
- **36,209 slot hours** (99.6% of all monitor consumption!)
- **Match rate: 52.5%** by projects, **87.2%** by slot hours

**2. QA Environment (Test):**
- 13 projects
- 77,592 jobs (high volume but negligible slots)
- **2 slot hours total** (almost no resource consumption)

**3. STG Environment (Staging):**
- 13 projects
- 16,746 jobs
- **151 slot hours total**

---

### Top 10 PROD Monitor Projects (Matched)

| Rank | Project ID | Retailer | Jobs | Slot Hours | QoS Violations | Violation % |
|------|------------|----------|------|------------|----------------|-------------|
| 1 | monitor-26a614b-us-prod | 511tactical | 707 | 17,383 | 89 | 12.6% |
| 2 | monitor-a679b28-us-prod | fashionnova | 4,189 | 11,768 | 983 | 23.5% |
| 3 | monitor-5494e1e-us-prod | onrunning | 17,108 | 636 | 129 | 0.8% |
| 4 | monitor-1e15a40-us-prod | sephora | 864 | 340 | 9 | 1.0% |
| 5 | monitor-fdbaa09-us-prod | newbalance | 4,709 | 113 | 7 | 0.2% |
| 6 | monitor-eaf244f-us-prod | uniqlo | 646 | 108 | 13 | 2.0% |
| 7 | monitor-6cb3559-us-prod | altardstate | 1,865 | 91 | 17 | 0.9% |
| 8 | monitor-41fd220-us-prod | nike | 167 | 80 | 0 | 0% |
| 9 | monitor-c50f7c7-us-prod | jcpenney | 122 | 69 | 1 | 0.8% |
| 10 | monitor-894824d-us-prod | huckberry | 2,336 | 60 | 37 | 1.6% |

---

### Top 10 PROD Monitor Projects (Unmatched)

| Rank | Project ID | Jobs | Slot Hours | QoS Violations | Violation % |
|------|------------|------|------------|----------------|-------------|
| 1 | monitor-a3d24b5-us-prod | 4,197 | 2,372 | 336 | 8.0% |
| 2 | monitor-64a7788-us-prod | 1,253 | 1,564 | 342 | **27.3%** |
| 3 | monitor-8bf3d71-us-prod | 103 | 141 | 18 | 17.5% |
| 4 | monitor-20d2462-us-prod | 450 | 99 | 3 | 0.7% |
| 5 | monitor-cfaaee8-us-prod | 1,723 | 70 | 3 | 0.2% |
| 6 | monitor-72a823e-us-prod | 278 | 62 | 30 | 10.8% |
| 7 | monitor-b39691a-us-prod | 86 | 33 | 4 | 4.7% |
| 8 | monitor-f6c6dd2-us-prod | 219 | 33 | 2 | 0.9% |
| 9 | monitor-0bd08b1-us-prod | 614 | 31 | 7 | 1.1% |
| 10 | monitor-e954c9f-us-prod | 229 | 13 | 9 | 3.9% |

**⚠️ Note:** Some unmapped PROD projects have significant QoS issues (monitor-64a7788: 27.3%)

---

## Column Descriptions

| Column | Description |
|--------|-------------|
| `project_id` | BigQuery project identifier |
| `environment` | PROD/QA/STG |
| `slot_type` | **RESERVED** (uses bq-narvar-admin reservation) or **ON_DEMAND** (unreserved, billed separately) |
| `mapping_status` | MATCHED (has retailer_moniker) or UNMATCHED |
| `retailer_moniker` | Retailer name (NULL if unmatched) |
| `first_job_date` | First job date in period (2025-09-01 to 2025-10-31) |
| `last_job_date` | Last job date in period |
| `days_span` | Total days between first and last job |
| `total_jobs` | Total BQ jobs in period |
| `active_days` | Number of days with activity (out of 61) |
| `total_slot_hours` | Total slot consumption |
| `avg_slot_hours_per_job` | Average slots per job |
| `avg_concurrent_slots` | Average concurrent slot usage |
| `avg_exec_seconds` | Average execution time |
| `p50/p95/p99_exec_seconds` | Execution time percentiles |
| `max_exec_seconds` | Longest query |
| `qos_violations` | Count of queries >30s |
| `qos_violation_pct` | % of queries >30s |
| `total_cost_usd` | Internal cost allocation (slot_hours * $0.0494 blended rate) - **NOT actual billing** |

### 💰 Cost Explanation

**`total_cost_usd` represents:**
- Internal resource consumption cost
- Based on blended reserved slot rate: **$0.0494/slot-hour**
- Formula: `(slot_ms / 3.6M) * $0.0494`

**Blended rate calculation:**
```
(500 slots @ $0.048 + 500 @ $0.036 + 700 @ $0.06) / 1,700 = $0.0494/hr
```

**⚠️ NOT actual BigQuery billing:**
- Reserved slots: Pre-paid, no additional charges
- On-demand: Billed separately at $6.25/TB

**See:** `COST_AND_RESERVATION_EXPLANATION.md` for full details

---

### 🎯 Slot Type Insights

**97.8% of monitor traffic uses RESERVED slots**

**15 projects using ON_DEMAND (2.2% of consumption):**
- Sephora: 340 slot hours
- OnRunning: 113 slot hours (also has 522 reserved!)
- Uniqlo: 108 slot hours
- Lululemon: 57 slot hours
- Nike: 80 slot hours

**⚠️ Note:** Some projects (like OnRunning) appear **twice** in the data:
- Once for RESERVED usage
- Once for ON_DEMAND usage
- This is correct - they use both slot types

---

## Recommended Google Sheets Setup

### Tabs to Create:

1. **Raw Data** - Connected sheet with full query results
2. **PROD Summary** - Pivot: environment=PROD, group by mapping_status
3. **Top Retailers** - Filter: MATCHED, sort by slot_hours DESC
4. **Unmapped Analysis** - Filter: UNMATCHED, sort by slot_hours DESC
5. **QoS Issues** - Filter: qos_violation_pct > 10%, all environments

### Useful Filters/Pivots:

**Top Slot Consumers:**
```
Filter: environment = "PROD"
Sort by: total_slot_hours DESC
```

**QoS Problem Projects:**
```
Filter: qos_violation_pct > 10%
Sort by: qos_violations DESC
```

**Matched Retailers Only:**
```
Filter: mapping_status = "MATCHED"
Sort by: total_slot_hours DESC
```

---

## Data Refresh Notes

- Query runs in ~3-5 seconds
- Safe to refresh daily/weekly
- For different periods, change `analysis_period_label` in query
- Data is static (historical period completed)

---

**File Location:** `queries/google_sheets/baseline_2025_monitor_projects_detailed.sql`  
**CSV Export (backup):** `results/baseline_2025_monitor_projects_CLEAN.csv`

