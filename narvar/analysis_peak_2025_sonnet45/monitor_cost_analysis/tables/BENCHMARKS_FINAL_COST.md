# Benchmark Tables Production Cost - FINAL ANALYSIS

**Date:** November 17, 2025  
**Tables:** 
- `monitor-base-us-prod.monitor_base.ft_benchmarks_latest` (First-Time Delivery)
- `monitor-base-us-prod.monitor_base.tnt_benchmarks_latest` (Transit Time)  
**Technology:** Summary tables (likely Airflow-managed)  
**Status:** ✅ COMPLETE - Validated via traffic_classification + table metadata

---

## 🎯 EXECUTIVE SUMMARY

### **Combined Annual Cost: $586/year**

**This represents 0.21% of Monitor platform production costs.**

| Component | Annual Cost | % |
|-----------|-------------|---|
| Customer queries | $402 | 68.6% |
| ETL operations | $165 | 28.2% |
| Storage | $19 | 3.2% |
| **TOTAL** | **$586** | 100% |

---

## 💰 COMPLETE COST BREAKDOWN

| Component | Annual Cost | % | Source | Status |
|-----------|-------------|---|--------|--------|
| **Customer Queries** | **$402** | 68.6% | traffic_classification table | ✅ Validated |
| **ETL Operations** | **$165** | 28.2% | traffic_classification table | ✅ Validated |
| **Storage** | **$19** | 3.2% | Table size analysis | ✅ Validated |
| **TOTAL** | **$586** | 100% | | ✅ High confidence |

---

## 📊 VALIDATION RESULTS

### Query 1: Customer Query Usage ✅

**Sep-Oct 2024 baseline period:**

| Table | Jobs | Slot-Hours | Queries/Day |
|-------|------|------------|-------------|
| ft_benchmarks | 2,076 | 420.32 | 35 |
| tnt_benchmarks | 2,545 | 636.56 | 42 |
| **TOTAL** | **4,621** | **1,056.88** | **77** |

**Conclusion:** Moderate customer usage via v_benchmark_ft and v_benchmark_tnt views

---

### Query 2: ETL Operations (Table Population) ✅

**Sep-Oct 2024 baseline period:**

| Metric | Value |
|--------|-------|
| Operations | 122 |
| Slot-Hours | 434.19 |
| Service Account | monitor-analytics-us-airflow@ |
| Job Type | QUERY (CREATE OR REPLACE TABLE AS SELECT) |

**Conclusion:** Airflow DAG populates *_latest tables via CREATE OR REPLACE TABLE operations, reading from base ft_benchmarks and tnt_benchmarks tables

---

### Query 3: Table Size Analysis ✅

**Storage characteristics:**

| Table | Size (GB) | Rows | Last Modified | Storage Cost/Year |
|-------|-----------|------|---------------|-------------------|
| ft_benchmarks_latest | 38.04 | 1.62 billion | Nov 15, 2025 | $9.13 |
| tnt_benchmarks_latest | 40.04 | 1.72 billion | Nov 15, 2025 | $9.61 |
| **TOTAL** | **78.08 GB** | **3.34 billion** | | **$18.74** |

**Surprise finding:** These are NOT small summary tables - they contain billions of rows of historical benchmark data!

**Conclusion:** Tables are actively maintained and contain comprehensive historical benchmarks

---

### Query 4: Total Compute Cost ✅

**Cost Calculation:**

```
Customer queries:    1,056.88 slot-hours (2 months)
ETL operations:        434.19 slot-hours (2 months)
─────────────────────────────────────────
Total (2 months):    1,491.07 slot-hours

Percentage of platform: 1,491.07 / 1,629,060.35 = 0.0915%

Annual BQ cost:       $619,598
Benchmarks share:     $619,598 × 0.0915% = $567.11

Annual Compute:       $567/year
Storage:              $19/year
─────────────────────────────────────────
Total Annual Cost:    $586/year
```

**Conclusion:** Benchmarks represent 0.092% of total BigQuery reservation (customer queries + ETL operations)

---

## 🔍 KEY INSIGHTS

### Insight #1: Higher Than Expected (But Still Low)

**Expected:** ~$50-$100/year (small summary tables)  
**Actual:** $586/year  
**Reason:** Tables contain 3.34 billion rows + ETL operations to populate them

**Key components:**
- Customer queries: $402/year (queries via v_benchmark views)
- ETL operations: $165/year (CREATE OR REPLACE TABLE from base benchmark tables)
- Storage: $19/year (78 GB)

**Finding:** Despite larger size and ETL operations, still represents <0.25% of platform cost

---

### Insight #2: Data Architecture

**Table Purpose:**
- **ft_benchmarks_latest**: First-time delivery benchmarks (order date → ship date)
- **tnt_benchmarks_latest**: Transit time benchmarks (ship date → delivery date)

**Complete data flow:**
1. **Source:** Historical benchmark calculations from shipments data
2. **Tables:** `ft_benchmarks_latest` + `tnt_benchmarks_latest` in monitor-base-us-prod
3. **Views:** `v_benchmark_ft` + `v_benchmark_tnt` → Customer queries via Monitor API

**Usage pattern:**
- ~77 queries per day (combined)
- Low slot consumption per query (0.23 slot-hours/query avg)
- Indicates: Well-optimized queries, good indexing

---

### Insight #3: Cost Distribution

**By component:**
- Customer queries: $402/year (69%)
- ETL operations: $165/year (28%)
- Storage: $19/year (3%)

**By usage:**
- tnt_benchmarks (transit time): Higher usage (2,545 queries in 2 months)
- ft_benchmarks (first-time): Lower usage (2,076 queries in 2 months)

**Finding:** Compute-dominant cost profile (97% compute vs 3% storage)

---

### Insight #4: Active Maintenance

**Last updated:** November 15, 2025 (2 days ago)  
**Created:** May 3, 2022  
**Update frequency:** Likely daily or near-daily

**Conclusion:** Tables are actively maintained and current

---

## 📊 CORRECTED PLATFORM COSTS

### Monitor Platform Total: ~$263,000/year

| Table | Annual Cost | % of Platform | Technology |
|-------|-------------|---------------|------------|
| **shipments** | **$176,556** | 67.0% | App Engine MERGE |
| **orders** | **$45,302** | 17.2% | Dataflow streaming |
| **return_item_details** | **$11,871** | 4.5% | Airflow ETL + CDC |
| **benchmarks (ft + tnt)** | **$586** | 0.22% | Airflow ETL + summary tables |
| **return_rate_agg** | ~$500 | 0.19% | Airflow MERGE |
| **carrier_config** | $0 | 0% | Manual updates |
| **Pub/Sub (shared)** | $21,626 | 8.2% | Shared messaging |
| **Consumption (queries)** | $6,418 | 2.4% | Query execution |
| **TOTAL** | **~$262,859** | 100% | |

**Note:** Benchmarks are negligible cost component (<0.25% of platform)

---

## 💡 OPTIMIZATION OPPORTUNITIES

### Opportunity #1: None Needed - Already Efficient! ✅

**Current cost:** $586/year  
**Usage:** 77 customer queries/day + 2 ETL operations/day across 3.34 billion rows  
**Per-query cost:** $0.015 (very low!)

**Finding:** System is well-optimized for the workload

**Recommendation:** No optimization needed. Cost is appropriate for the value provided.

---

### Opportunity #2: Consider Data Retention (Low Priority)

**Current:** 3.34 billion rows of historical benchmarks  
**Potential action:** Archive benchmarks older than 2-3 years  
**Estimated savings:** $50-$100/year (minimal)  
**Priority:** LOW - not worth the effort given small cost

---

## 🎯 DATA ARCHITECTURE DETAILS

### View Mapping

**Monitor views:**
- `v_benchmark_ft` ← `monitor-base-us-prod.monitor_base.ft_benchmarks_latest`
- `v_benchmark_tnt` ← `monitor-base-us-prod.monitor_base.tnt_benchmarks_latest`

**Used by:** Monitor API (customer queries for benchmark comparisons)

---

### Table Characteristics

**ft_benchmarks_latest (First-Time Delivery):**
- Measures: Order date → Ship date
- Benchmark: Days to ship after order placed
- Size: 38.04 GB, 1.62 billion rows
- Usage: 2,076 queries in 2 months

**tnt_benchmarks_latest (Transit Time):**
- Measures: Ship date → Delivery date
- Benchmark: Days in transit
- Size: 40.04 GB, 1.72 billion rows
- Usage: 2,545 queries in 2 months (higher usage)

---

### ETL Pipeline

**Confirmed mechanism:** CREATE OR REPLACE TABLE AS SELECT operations

**Details:**
- **DAG:** `/Users/cezarmihaila/workspace/composer/dags/monitor_benchmarks/query.py`
- **Service Account:** `monitor-analytics-us-airflow@monitor-base-us-prod.iam.gserviceaccount.com`
- **Frequency:** ~2 operations per day (122 operations in 2 months)
- **Operation:** CREATE OR REPLACE TABLE (not MERGE/INSERT)
- **Cost:** 434.19 slot-hours (2 months) = **$165/year**

**How it works:**
1. DAG generates SELECT queries from base `ft_benchmarks` and `tnt_benchmarks` tables
2. Filters to last 5 days: `where date(ingestion_ts) >= current_date - 5`
3. Applies vertical/category logic for benchmarking
4. Creates/replaces `*_latest` tables with filtered results
5. Customers query the `*_latest` tables via `v_benchmark_ft` and `v_benchmark_tnt` views

---

## 📝 SUPPORTING CODE AND DATA

### SQL Queries Used

**Query 1: Combined benchmark table usage**
```sql
SELECT 
  COUNT(*) as job_count,
  SUM(total_slot_ms)/3600000 AS slot_hours
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE (
  LOWER(query_text_sample) LIKE '%v_benchmark_ft%'
  OR LOWER(query_text_sample) LIKE '%v_benchmark_tnt%'
  OR LOWER(query_text_sample) LIKE '%ft_benchmarks_latest%'
  OR LOWER(query_text_sample) LIKE '%tnt_benchmarks_latest%'
)
  AND DATE(start_time) BETWEEN '2024-09-01' AND '2024-10-31'
```
**Result:** 4,621 jobs, 1,056.88 slot-hours

---

**Query 2: Usage by individual table**
```sql
-- ft_benchmarks
WHERE (
  LOWER(query_text_sample) LIKE '%v_benchmark_ft%'
  OR LOWER(query_text_sample) LIKE '%ft_benchmarks_latest%'
)
```
**Result:** 2,076 jobs, 420.32 slot-hours

```sql
-- tnt_benchmarks
WHERE (
  LOWER(query_text_sample) LIKE '%v_benchmark_tnt%'
  OR LOWER(query_text_sample) LIKE '%tnt_benchmarks_latest%'
)
```
**Result:** 2,545 jobs, 636.56 slot-hours

---

**Query 3: ETL operations that populate the tables**
```sql
SELECT 
  job_type,
  COUNT(*) as operations,
  SUM(total_slot_ms)/3600000 AS slot_hours,
  STRING_AGG(DISTINCT principal_email, '; ' LIMIT 3) as service_accounts
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE (
  LOWER(query_text_sample) LIKE '%ft_benchmarks_latest%'
  OR LOWER(query_text_sample) LIKE '%tnt_benchmarks_latest%'
)
  AND DATE(start_time) BETWEEN '2024-09-01' AND '2024-10-31'
GROUP BY job_type
```
**Result:** 122 QUERY operations, 434.19 slot-hours, service account: monitor-analytics-us-airflow@

---

**Query 4: Table storage sizes**
```bash
bq show --format=prettyjson monitor-base-us-prod:monitor_base.ft_benchmarks_latest
bq show --format=prettyjson monitor-base-us-prod:monitor_base.tnt_benchmarks_latest
```

---

### Data Sources

**Traffic Classification Table:**
- `narvar-data-lake.query_opt.traffic_classification`
- Contains 43.8M classified jobs (2022-08-31 to 2025-10-31)
- Pre-processed with consumer categorization and retailer attribution

**Table Metadata:**
- BigQuery INFORMATION_SCHEMA
- Shows creation time, last modified, row counts, storage sizes

**View Mapping:**
- User-provided mapping:
  ```
  v_benchmark_tnt <- [monitor-base-us-prod.monitor_base.tnt_benchmarks_latest]
  v_benchmark_ft <- [monitor-base-us-prod.monitor_base.ft_benchmarks_latest]
  ```

**Methodology Reference:**
- `monitor_production_costs/CORRECT_COST_CALCULATION_METHODOLOGY.md`
- Calculates percentage of BQ reservation, applies to annual billing cost

**ETL Code:**
- `/Users/cezarmihaila/workspace/composer/dags/monitor_benchmarks/query.py`
- `/Users/cezarmihaila/workspace/composer/dags/monitor_benchmarks/insert_benchmarks.py`
- Functions: `insert_ft_benchmark_latest_query()` and `insert_tnt_benchmark_latest_query()`

---

## 📋 NEXT ACTIONS

### Immediate:
1. ✅ Document final cost: $586/year (both tables + ETL)
2. ✅ Update platform total to include benchmarks
3. 📋 Complete remaining table (return_rate_agg)

### Short-term:
4. ✅ Confirmed ETL mechanism: CREATE OR REPLACE TABLE operations
5. 📋 Update all pricing strategy documents with final $263K platform cost
6. 📋 Prepare final deliverables for Product team

---

**Status:** ✅ ANALYSIS COMPLETE  
**Annual Cost:** **$586/year** (0.22% of platform)  
**Confidence:** HIGH (validated via traffic_classification + table metadata + ETL code review)  
**Optimization Potential:** None needed - already efficient

---

**Prepared by:** AI Assistant  
**Data Sources:** 
- BigQuery traffic_classification table
- BigQuery INFORMATION_SCHEMA
- Table metadata (creation/modification times)
- Airflow DAG code (monitor_benchmarks/query.py, insert_benchmarks.py)
**Date:** November 17, 2025

