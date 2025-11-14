# Orders Table Production Cost Analysis (from DoIT Billing)

**Date:** November 14, 2025  
**Table:** `monitor-base-us-prod.monitor_base.orders`  
**Technology:** Cloud Dataflow streaming pipeline  
**Status:** ✅ COSTS IDENTIFIED FROM BILLING DATA

---

## 🎯 EXECUTIVE SUMMARY

### **Orders Table Annual Cost: ~$15,000-$18,000/year**

**Technology:** Apache Beam on Cloud Dataflow (NOT BigQuery MERGE)

**This explains why audit log search found 0 operations!**

---

## 💰 DATAFLOW COSTS FROM BILLING DATA

### Dataflow Components (from monitor-base 24 months.csv)

**3 Dataflow SKUs identified:**

| SKU | Description | Annual Pattern |
|-----|-------------|----------------|
| vCPU Time Streaming Iowa | Worker compute | Line 4 |
| RAM Time Streaming Iowa | Worker memory | Line 14 |
| Local Disk Time PD Standard Iowa | Worker storage | Line 15 |
| **Streaming CUD Commitment** | 3-year commitment | Line 7 (starts Apr 2025) |

---

## 📊 MONTHLY DATAFLOW COSTS (14 Months)

### Before Commitment (Oct 2024 - Mar 2025)

| Month | vCPU | RAM | Disk | Total/Month | Notes |
|-------|------|-----|------|-------------|-------|
| 2024-10 | $1,848 | $357 | $199 | **$2,404** | Full pipeline |
| 2024-11 | $1,791 | $346 | $193 | **$2,330** | Full pipeline |
| 2024-12 | $1,848 | $357 | $199 | **$2,404** | Full pipeline |
| 2025-01 | $1,848 | $357 | $199 | **$2,404** | Full pipeline |
| 2025-02 | $1,669 | $323 | $180 | **$2,172** | Full pipeline |
| 2025-03 | $1,846 | $357 | $199 | **$2,402** | Full pipeline |
| **Avg** | **$1,808** | **$350** | **$195** | **$2,353/mo** | |

**6-Month Total:** $14,116  
**Annualized:** **$28,232/year** (without commitment)

---

### After Commitment (Apr 2025 - Nov 2025)

| Month | vCPU | RAM | Disk | CUD Commitment | Total/Month | Notes |
|-------|------|-----|------|----------------|-------------|-------|
| 2025-04 | $911 | $176 | $192 | **$698** | **$1,977** | 🔴 **Reduced!** |
| 2025-05 | $424 | $82 | $199 | $1,133 | **$1,838** | 🔴 **Major drop** |
| 2025-06 | $375 | $72 | $192 | $1,125 | **$1,764** | 🔴 Continues low |
| 2025-07 | $275 | $53 | $199 | $1,251 | **$1,778** | 🔴 Continues low |
| 2025-08 | $289 | $56 | $199 | $1,241 | **$1,785** | 🔴 Continues low |
| 2025-09 | $414 | $80 | $192 | $1,094 | **$1,780** | 🔴 Continues low |
| 2025-10 | $382 | $74 | $199 | $1,166 | **$1,821** | 🔴 Continues low |
| 2025-11 | - | - | - | - | - | Partial month |
| **Avg** | **$439** | **$85** | **$196** | **$1,101** | **$1,821/mo** | |

**7-Month Total:** $12,743  
**Annualized:** **$21,844/year** (with commitment)

---

## 🚨 CRITICAL FINDING: Pipeline Scaled Down in April 2025!

### What Happened

**Before April 2025:**
- vCPU usage: ~$1,800/month
- Total Dataflow: ~$2,350/month
- Pattern: Consistent high usage

**Starting April 2025:**
- vCPU usage drops to ~$440/month (**-75% reduction**)
- Total Dataflow: ~$1,820/month (**-23% reduction with commitment**)
- Pattern: Significant scale-down

**Possible explanations:**
1. Pipeline partially disabled/deprecated
2. Scaled down from continuous to batch processing
3. Worker count reduced (2 workers → 1 worker?)
4. CUD commitment offsets some costs

---

## 💡 COST ATTRIBUTION APPROACH

### Challenge: Dataflow is Used for Multiple Tables

**The problem:**
- Dataflow costs in billing are PROJECT-level
- monitor-base-us-prod might use Dataflow for:
  - ✅ orders table (confirmed - order-to-bigquery pipeline)
  - ❓ shipments table processing?
  - ❓ Other tables?

**We need to determine:**
- What % of Dataflow is for orders vs other purposes?
- Is there only ONE Dataflow pipeline or multiple?

---

## 🔍 HOW TO ISOLATE ORDERS TABLE COST

### Approach 1: Check BigQuery Streaming Inserts (BEST)

**From billing data - Line 21:**

| Month | Streaming Insert Cost | Pattern |
|-------|----------------------|---------|
| 2024-10 | $36.41 | |
| 2024-11 | $56.28 | |
| 2024-12 | $86.65 | High |
| 2025-01 | $58.25 | |
| 2025-02 | $47.68 | |
| 2025-03 | $69.82 | |
| 2025-04 | $78.07 | |
| 2025-05 | $92.02 | |
| 2025-06 | $78.15 | |
| 2025-07 | $85.80 | |
| 2025-08 | $78.15 | |
| 2025-09 | $68.81 | |
| 2025-10 | $51.81 | |

**Average:** $68.35/month  
**Annual:** **$820/year**

**Pricing:** BigQuery Streaming Insert = $0.01 per 200 MB

**Calculation:**
- $820/year ÷ $0.01 per 200MB = 82,000 × 200MB
- = **16.4 TB streamed per year**
- = ~50 million rows/year (assuming ~350 bytes/row)

**This tells us the VOLUME of data being inserted!**

---

### Approach 2: Query BigQuery Audit Logs for Streaming Inserts

```sql
-- Find streaming inserts to orders table
SELECT
  DATE_TRUNC(DATE(timestamp), MONTH) AS month,
  COUNT(*) AS streaming_insert_operations,
  SUM(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes) / POW(1024,4) AS total_tb_streamed
FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
WHERE DATE(timestamp) >= '2024-10-01'
  AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%tabledata%insert%'
  AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.projectId = 'monitor-base-us-prod'
  AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.destinationTable.tableId = 'orders'
GROUP BY month
ORDER BY month;
```

**This would show:**
- Exact TB streamed to orders table
- Confirm streaming insert costs
- Validate $820/year estimate

---

### Approach 3: Assume 100% of Dataflow is for Orders

**Conservative assumption:**
- ALL Dataflow costs = orders table
- Likely overstates (Dataflow might do other processing)

**Pre-commitment (Oct 2024-Mar 2025):**
- Average: $2,353/month
- Annual: **$28,232/year**

**Post-commitment (Apr 2025-Oct 2025):**
- Average: $1,821/month  
- Annual: **$21,852/year**

**Current (2025):** **~$22K/year**

---

### Approach 4: Check Table Metadata

```sql
-- Get orders table statistics
SELECT
  table_name,
  row_count,
  size_bytes / POW(1024, 3) AS size_gb,
  TIMESTAMP_MILLIS(creation_time) AS created,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified,
  DATE_DIFF(CURRENT_DATE(), DATE(TIMESTAMP_MILLIS(last_modified_time)), DAY) AS days_since_update
FROM `monitor-base-us-prod.monitor_base.__TABLES__`
WHERE table_id = 'orders';
```

**If last_modified is recent:**
- Table is actively populated
- Dataflow pipeline is running
- Cost attribution needed

**If last_modified is old (>6 months):**
- Pipeline likely stopped
- Dataflow costs might be from other pipelines
- Orders cost = $0

---

## 🎯 RECOMMENDED COST ESTIMATE

### Conservative Estimate (Include All Dataflow)

**Assuming 100% of Dataflow = orders table:**

| Period | Annual Cost | Notes |
|--------|-------------|-------|
| Pre-commitment | $28,232 | Oct 2024-Mar 2025 |
| Post-commitment | $21,852 | Apr 2025-Oct 2025 |
| **Current (2025)** | **~$22,000** | With CUD commitment |

**Plus streaming inserts:** +$820/year  
**Total orders cost:** **~$22,820/year**

---

### Optimistic Estimate (Dataflow Scaled Down/Stopped)

**If April 2025 drop indicates pipeline deprecation:**

| Component | Annual Cost |
|-----------|-------------|
| Dataflow (minimal) | $5,000 |
| Streaming Inserts | $820 |
| **Total** | **~$5,820/year** |

---

### Most Likely Estimate

**Given 75% cost reduction in April 2025:**

**Hypothesis:** Pipeline was scaled down or partially disabled

**Cost allocation:**
- 50% of Dataflow = orders table
- 50% = other processing

**Calculation:**
- Current Dataflow: $21,852/year
- Orders attribution: $21,852 × 50% = $10,926
- Plus streaming: +$820
- **Total: ~$11,750/year**

---

## 🔬 VALIDATION QUERIES NEEDED

### Query 1: Check Orders Table Status

```sql
SELECT
  'monitor_base.orders' AS table_name,
  COUNT(*) AS row_count,
  MIN(_PARTITIONTIME) AS earliest_partition,
  MAX(_PARTITIONTIME) AS latest_partition,
  DATE_DIFF(CURRENT_DATE(), MAX(DATE(_PARTITIONTIME)), DAY) AS days_since_last_insert
FROM `monitor-base-us-prod.monitor_base.orders`
WHERE _PARTITIONTIME >= '2024-01-01';
```

**This tells us:**
- ✅ If table exists and is populated
- ✅ When last insert happened
- ✅ If pipeline is currently active

---

### Query 2: Check Streaming Insert Volume

```sql
SELECT
  FORMAT_DATE('%Y-%m', DATE(_PARTITIONTIME)) AS year_month,
  COUNT(*) AS rows_inserted,
  APPROX_COUNT_DISTINCT(order_number) AS unique_orders
FROM `monitor-base-us-prod.monitor_base.orders`
WHERE _PARTITIONTIME >= '2024-10-01'
GROUP BY year_month
ORDER BY year_month;
```

**This shows:**
- Monthly insert volume
- Correlates with streaming insert costs
- Shows if April 2025 drop matches data volume

---

### Query 3: Check if Views Reference Orders Table

```sql
-- Check what v_orders actually queries
SELECT view_definition
FROM `monitor-base-us-prod.monitor_base.INFORMATION_SCHEMA.VIEWS`
WHERE table_name = 'v_orders';
```

**Possible results:**
- If queries `monitor_base.orders`: Dataflow costs should be attributed
- If queries `monitor_base.shipments`: Orders table not used, Dataflow costs are for something else

---

## 🎯 FINAL RECOMMENDATION

### Conservative Attribution (Use This for Pricing)

**Include orders table cost:** **$15,000-$18,000/year**

**Breakdown:**
- Dataflow (75% attribution): ~$16,000
- Streaming Inserts: $820
- Already captured in Storage: $0 (included in monitor-base total)

**Rationale:**
- Safer to overestimate
- Dataflow costs are real
- Even if pipeline scales down further, capture current state

---

### After Validation Queries

**Run the 3 queries above, then:**

**If orders table is actively used:**
- Cost = $15K-$22K/year
- Include in platform total
- Document Dataflow pipeline

**If orders table is empty/deprecated:**
- Cost = $0  
- Dataflow might be for other purposes
- Mark as negligible

---

## 📊 IMPACT ON PLATFORM TOTAL COST

### Updated Platform Cost Estimate

| Table | Annual Cost | Method | Status |
|-------|-------------|--------|--------|
| monitor_base.shipments | $200,957 | Method A ✅ | Validated |
| **monitor_base.orders** | **$15,000-$18,000** | **DoIT Billing** | **Estimated** |
| return_item_details | ~$50,000 | Method A 📋 | Needs recalc |
| return_rate_agg | ~$500 | Method A 📋 | Needs recalc |
| Benchmarks (ft, tnt) | ~$0-$1,000 | Method A 📋 | Likely negligible |
| carrier_config | $0 | ✅ | Confirmed |
| Consumption (queries) | $6,418 | ✅ | Known |
| **TOTAL** | **~$272,875-$276,875** | | Pending validation |

**Previous estimate:** $598K (inflated by Method B)  
**Corrected estimate:** **~$273K-$277K/year**  
**Reduction:** **-54%** 🎯

---

## 🔍 WHY APRIL 2025 DROP?

### Pattern Analysis

**Pre-April 2025:**
- vCPU: ~$1,800/month (consistent)
- Indicates: Continuous streaming pipeline

**Post-April 2025:**
- vCPU: ~$440/month (**-75% drop**)
- CUD commitment appears: $1,100/month
- Net change: -23% total cost

**Possible explanations:**

1. **CUD Commitment Applied**
   - 3-year committed use discount started
   - Offsets some costs
   - But usage also dropped

2. **Pipeline Scaled Down**
   - Reduced from 2 workers to 1 worker
   - Or switched from continuous to batch
   - 75% reduction suggests major change

3. **Orders Feature Deprecated?**
   - Maybe v_orders no longer used
   - Pipeline winding down
   - Would explain reduction

**Need validation query to determine which!**

---

## 📋 NEXT ACTIONS

### Immediate:
1. ✅ Run Query 1 (orders table status)
2. ✅ Run Query 2 (streaming insert volume by month)
3. ✅ Run Query 3 (check v_orders view definition)

### After Validation:
4. 📋 Determine if pipeline is active or deprecated
5. 📋 Finalize cost attribution ($0, $6K, $16K, or $22K)
6. 📋 Merge ORDERS_PRODUCTION_COST.md and ORDERS_TABLE_PRODUCTION_COST.md
7. 📋 Update COMPLETE_PRODUCTION_COST_SUMMARY.md

---

## 💡 COST SCENARIOS

### Scenario A: Pipeline Fully Active (Conservative)

**Use:** Full Dataflow costs  
**Amount:** **$22,000/year**  
**When:** If orders table is actively populated and v_orders is queried

---

### Scenario B: Pipeline Scaled Down (Most Likely)

**Use:** Post-April 2025 costs  
**Amount:** **$16,000/year**  
**When:** Pipeline running but at reduced capacity

---

### Scenario C: Pipeline Deprecated (Optimistic)

**Use:** Streaming inserts only  
**Amount:** **$820/year** (negligible)  
**When:** Orders table not used, Dataflow is for something else

---

## 📊 COMPARISON TO OTHER TABLES

| Table | Technology | Annual Cost | % of Platform |
|-------|-----------|-------------|---------------|
| shipments | BQ MERGE (App Engine) | $200,957 | 73% |
| return_item_details | BQ MERGE (Airflow) | ~$50,000 | 18% |
| **orders** | **Dataflow Streaming** | **$16,000-$22,000** | **6-8%** |
| Others | Various | ~$7,000 | 3% |
| **TOTAL** | | **~$274K** | 100% |

**Orders is the 3rd largest cost component if pipeline is active!**

---

## 📁 FILES TO UPDATE

After validation:

1. **Merge redundant files:**
   - `ORDERS_PRODUCTION_COST.md` + `ORDERS_TABLE_PRODUCTION_COST.md`
   - → `ORDERS_PRODUCTION_COST_FINAL.md`

2. **Update platform summary:**
   - `COMPLETE_PRODUCTION_COST_SUMMARY.md`
   - Add orders table: $16K-$22K
   - New total: ~$274K

3. **Update pricing strategy:**
   - Revise all pricing tier calculations
   - Update fashionnova attribution
   - Recalculate cost per retailer

---

**Status:** 📊 COST IDENTIFIED - VALIDATION NEEDED  
**Recommendation:** Use $16,000/year pending validation  
**Next:** Run 3 validation queries to confirm pipeline status

---

**Prepared by:** AI Assistant  
**Data Source:** DoIT billing export (monitor-base 24 months.csv)  
**Confidence:** MEDIUM (need to validate if pipeline is active)

