# Orders Table Cost Assessment Plan

**Date:** November 14, 2025  
**Table:** `monitor-base-us-prod.monitor_base.orders`  
**Technology:** Apache Beam on Google Cloud Dataflow  
**Type:** Streaming pipeline (PubSub → Dataflow → BigQuery)

---

## 🎯 KEY FINDING

**Orders table is NOT a BigQuery MERGE operation!**

**Technology Stack:**
- **Input:** Pub/Sub subscription (Avro messages)
- **Processing:** Apache Beam pipeline on Dataflow
- **Output:** BigQuery streaming inserts

**This explains why we found 0 ETL operations in BigQuery audit logs!**

---

## 💰 COST COMPONENTS FOR DATAFLOW PIPELINE

### 1. **Dataflow Compute** (Workers)

**What to look for in DoIT billing:**
- Service: `Cloud Dataflow`
- SKU Description: Contains "Dataflow" or "Worker"
- Project: `monitor-base-us-prod` or related

**Query DoIT billing table:**
```sql
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m', invoice_month)) AS year_month,
  service_description,
  sku_description,
  SUM(cost) AS monthly_cost
FROM `narvar-data-lake.doitintl_cmp_bq.*`  -- Or actual billing table
WHERE service_description LIKE '%Dataflow%'
  AND (project_id = 'monitor-base-us-prod' OR project_name LIKE '%monitor%')
  AND PARSE_DATE('%Y%m', invoice_month) >= '2024-06-01'
GROUP BY year_month, service_description, sku_description
ORDER BY year_month, monthly_cost DESC;
```

**Expected costs:**
- Workers: n1-standard-2 × hours running
- Based on README: 1-2 workers typical
- **Estimate:** $500-$2,000/month depending on usage

---

### 2. **Pub/Sub** (Message Delivery)

**What to look for:**
- Service: `Cloud Pub/Sub`
- Topic: `monitor-order-*` (production topic)
- Subscription: `monitor-order-sub`

**Query DoIT billing table:**
```sql
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m', invoice_month)) AS year_month,
  sku_description,
  SUM(cost) AS monthly_cost
FROM `narvar-data-lake.doitintl_cmp_bq.*`
WHERE service_description = 'Cloud Pub/Sub'
  AND (project_id = 'monitor-base-us-prod' OR sku_description LIKE '%monitor%order%')
  AND PARSE_DATE('%Y%m', invoice_month) >= '2024-06-01'
GROUP BY year_month, sku_description
ORDER BY year_month, monthly_cost DESC;
```

**Note:** Pub/Sub for monitor-base-us-prod ($26,226/year) might already include this!

---

### 3. **BigQuery Streaming Inserts**

**What to look for:**
- Service: `BigQuery`
- SKU: `Streaming Insert` or `Insert Rows`
- Destination: `monitor_base.orders`

**Query DoIT billing table:**
```sql
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m', invoice_month)) AS year_month,
  sku_description,
  SUM(usage_amount) AS rows_inserted,
  SUM(cost) AS monthly_cost
FROM `narvar-data-lake.doitintl_cmp_bq.*`
WHERE service_description = 'BigQuery'
  AND sku_description LIKE '%Streaming%Insert%'
  AND project_id = 'monitor-base-us-prod'
  AND PARSE_DATE('%Y%m', invoice_month) >= '2024-06-01'
GROUP BY year_month, sku_description
ORDER BY year_month;
```

**Pricing:**
- $0.01 per 200 MB of streamed data
- Free up to 2 TB/month
- **Likely cost:** Negligible (under free tier)

---

### 4. **Storage** (BigQuery Table)

**Already captured in monitor-base-us-prod storage costs ($24,899/year)**

**To verify orders table size:**
```sql
SELECT
  table_name,
  row_count,
  size_bytes / POW(1024, 3) AS size_gb,
  size_bytes / POW(1024, 3) * 0.02 AS monthly_storage_cost_active,
  size_bytes / POW(1024, 3) * 0.01 AS monthly_storage_cost_longterm
FROM `monitor-base-us-prod.monitor_base.__TABLES__`
WHERE table_id = 'orders';
```

---

### 5. **Cloud Storage** (Staging/Temp)

**What to look for:**
- Service: `Cloud Storage`
- Location: `gs://narvar-*-pubsub-to-bq*/` or similar
- Usage: Staging and temporary files

**Query DoIT billing table:**
```sql
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m', invoice_month)) AS year_month,
  sku_description,
  SUM(cost) AS monthly_cost
FROM `narvar-data-lake.doitintl_cmp_bq.*`
WHERE service_description = 'Cloud Storage'
  AND project_id = 'monitor-base-us-prod'
  AND PARSE_DATE('%Y%m', invoice_month) >= '2024-06-01'
GROUP BY year_month, sku_description
ORDER BY year_month;
```

**Expected:** $10-$100/month (small staging files)

---

## 🔍 ALTERNATIVE: Use GCP Console

If DoIT billing table is not accessible, use GCP Console:

### Navigation
1. Go to: https://console.cloud.google.com/billing
2. Select billing account
3. Go to "Reports"
4. Filter by:
   - Project: `monitor-base-us-prod`
   - Service: Dataflow, Pub/Sub, Cloud Storage
   - Time range: Last 12 months

### Export Data
- Click "Download CSV"
- Get monthly breakdown by service
- Look for patterns and trends

---

## 🔬 DATAFLOW-SPECIFIC COST QUERIES

### Query 1: Check if Dataflow Jobs Exist

```sql
-- Check Dataflow job metadata (if available)
SELECT
  job_name,
  job_id,
  create_time,
  state,
  current_state_time
FROM `monitor-base-us-prod.region-us-west1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE job_type = 'DATAFLOW'
  AND job_name LIKE '%order%'
  AND creation_time >= '2024-06-01'
ORDER BY create_time DESC
LIMIT 100;
```

**Note:** This schema might not exist or have different structure

---

### Query 2: Estimate via Row Counts

```sql
-- Count orders table inserts to estimate message volume
SELECT
  DATE_TRUNC(DATE(_PARTITIONTIME), MONTH) AS month,
  COUNT(*) AS rows_inserted,
  COUNT(*) * 0.000005 AS estimated_streaming_cost,  -- $0.01 per 200MB ~ $0.000005 per row
  '~$0.01 per 200MB streamed' AS pricing_note
FROM `monitor-base-us-prod.monitor_base.orders`
WHERE _PARTITIONTIME >= '2024-06-01'
GROUP BY month
ORDER BY month;
```

**Limitations:**
- Only works if table is partitioned by insertion time
- Doesn't show Dataflow worker costs

---

## 📊 EXPECTED COST BREAKDOWN

### Scenario A: Continuous Streaming (24/7)

| Component | Calculation | Monthly Cost | Annual Cost |
|-----------|-------------|--------------|-------------|
| Dataflow Workers | 2× n1-standard-2 × 730 hrs × ~$0.10/hr | ~$150 | ~$1,800 |
| Pub/Sub Messages | Included in monitor-base | $0 | $0 |
| BQ Streaming Inserts | Free tier | $0 | $0 |
| Cloud Storage | Staging files | ~$10 | ~$120 |
| **TOTAL** | | **~$160/mo** | **~$1,920/yr** |

---

### Scenario B: Scheduled/Batch (e.g., hourly)

| Component | Calculation | Monthly Cost | Annual Cost |
|-----------|-------------|--------------|-------------|
| Dataflow Workers | 2 workers × 1hr/day × 30 days × ~$0.10 | ~$6 | ~$72 |
| Pub/Sub Messages | Included | $0 | $0 |
| BQ Streaming Inserts | Free tier | $0 | $0 |
| Cloud Storage | Minimal | ~$5 | ~$60 |
| **TOTAL** | | **~$11/mo** | **~$132/yr** |

---

### Scenario C: Pipeline Not Running (Table Not Used)

**Cost:** $0

**Evidence:**
- No Dataflow costs in billing
- No recent data in orders table
- v_orders/v_order_items might query shipments directly

---

## 🎯 RECOMMENDATION

### Step 1: Check DoIT Billing (HIGHEST PRIORITY)

Run this query to see if Dataflow costs exist:

```sql
SELECT
  service_description,
  sku_description,
  SUM(cost) AS total_cost_18_months
FROM `narvar-data-lake.doitintl_cmp_bq.*`  -- Replace with actual table pattern
WHERE (project_id = 'monitor-base-us-prod' OR project_name LIKE '%monitor-base%')
  AND service_description IN ('Dataflow', 'Cloud Dataflow', 'Pub/Sub')
  AND PARSE_DATE('%Y%m', invoice_month) >= '2024-06-01'
GROUP BY service_description, sku_description
ORDER BY total_cost_18_months DESC;
```

**Interpretation:**
- If Dataflow costs = $0: Pipeline not running, orders table not populated
- If Dataflow costs = $100-$1,000: Batch/scheduled pipeline
- If Dataflow costs = $1,000-$5,000: Continuous streaming pipeline

---

### Step 2: Verify Orders Table Usage

```sql
-- Check if orders table exists and has recent data
SELECT
  table_name,
  row_count,
  size_bytes / POW(1024, 3) AS size_gb,
  TIMESTAMP_MILLIS(creation_time) AS created,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified
FROM `monitor-base-us-prod.monitor_base.__TABLES__`
WHERE table_id = 'orders';
```

**If table doesn't exist or is empty:**
- No production cost
- v_orders likely queries shipments table directly

---

### Step 3: Check Retailer Usage

```sql
-- See if any retailers actually query v_orders or v_order_items
SELECT
  retailer_moniker,
  referenced_tables,
  COUNT(*) AS query_count
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE DATE(creation_time) BETWEEN '2024-09-01' AND '2024-10-31'
  AND consumer_subcategory = 'MONITOR'
  AND (referenced_tables LIKE '%v_orders%' OR referenced_tables LIKE '%v_order_items%')
GROUP BY retailer_moniker, referenced_tables
ORDER BY query_count DESC;
```

**If zero results:**
- Views not used
- No need to maintain orders table
- Cost = $0

---

## 📋 INFORMATION NEEDED FROM YOU

To complete Priority 3 assessment, I need:

### Critical:
1. **DoIT billing data for Dataflow**
   - Is there ANY Dataflow cost for monitor-base-us-prod?
   - What's the monthly pattern?

2. **Verify orders table exists**
   - Run: `SELECT COUNT(*) FROM monitor-base-us-prod.monitor_base.orders`
   - Does it return data or error?

3. **Check if v_orders is used**
   - Do any retailers actually query v_orders/v_order_items?
   - Or do they just use v_shipments?

### Nice to Have:
4. **Dataflow pipeline code** (from GitHub)
   - Main Java class: `OrderToBigQuery.java`
   - Would help understand processing logic
   - But not critical for cost assessment

---

## 💡 MY HYPOTHESIS

**Most likely scenario:**

1. **Orders table might not be actively used**
   - Dataflow pipeline may have been experimental/deprecated
   - Modern approach: Query shipments table directly via views
   - **Cost: $0 (pipeline not running)**

2. **Or very low-cost batch operation**
   - Small scheduled job
   - Minimal worker hours
   - **Cost: $100-$500/year**

**Why I think this:**
- No MERGE operations found in audit logs (Dataflow uses streaming inserts)
- fashionnova doesn't query v_orders (based on earlier analysis)
- Pub/Sub costs already captured in monitor-base-us-prod total

---

## 🚀 RECOMMENDED APPROACH

### Instead of analyzing GitHub code, let's:

**1. Query DoIT billing for Dataflow costs** (2 minutes)
   - Answers 90% of the question
   - Shows if pipeline is even running

**2. Check if orders table exists** (30 seconds)
   - Single SQL query
   - Confirms table status

**3. Check retailer usage** (1 minute)
   - See if anyone uses v_orders
   - Determines if cost matters

**Total time:** ~5 minutes to get definitive answer

**vs analyzing GitHub code:** Hours of work, still wouldn't show costs

---

## 📊 SUGGESTED SQL QUERY PACKAGE

**Run these 3 queries and we'll have our answer:**

### Query A: Dataflow Costs
```sql
-- Get all Dataflow-related costs for monitor project
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m', invoice_month)) AS year_month,
  service_description,
  sku_description,
  SUM(cost) AS monthly_cost,
  SUM(usage_amount) AS usage_amount,
  usage_unit
FROM `narvar-data-lake.doitintl_cmp_bq.gcp_billing_export_*`
WHERE (project_id LIKE '%monitor%' OR project_name LIKE '%monitor%')
  AND service_description LIKE '%Dataflow%'
  AND _TABLE_SUFFIX >= '20240601'
GROUP BY year_month, service_description, sku_description, usage_unit
ORDER BY year_month, monthly_cost DESC;
```

### Query B: Orders Table Status
```sql
-- Check if orders table exists and is populated
SELECT
  'orders' AS table_name,
  COUNT(*) AS row_count,
  COUNT(*) / 1000000.0 AS millions_of_rows,
  MIN(order_date) AS earliest_order,
  MAX(order_date) AS latest_order,
  DATE_DIFF(CURRENT_DATE(), MAX(DATE(order_date)), DAY) AS days_since_last_insert
FROM `monitor-base-us-prod.monitor_base.orders`
WHERE order_date >= '2024-01-01';
```

### Query C: View Usage Check
```sql
-- See if v_orders/v_order_items are actually queried
SELECT
  COUNT(DISTINCT job_id) AS queries_using_orders_views,
  COUNT(DISTINCT retailer_moniker) AS retailers_using_orders,
  STRING_AGG(DISTINCT retailer_moniker ORDER BY retailer_moniker LIMIT 10) AS sample_retailers
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE DATE(creation_time) BETWEEN '2024-09-01' AND '2024-10-31'
  AND consumer_subcategory = 'MONITOR'
  AND (
    referenced_tables LIKE '%v_orders%' OR 
    referenced_tables LIKE '%v_order_items%' OR
    query_text_sample LIKE '%monitor_base.orders%'
  );
```

---

## 🎯 DECISION TREE

```
Does Dataflow cost exist in billing?
├─ NO → Cost = $0, pipeline not running, mark as negligible
└─ YES → Is it > $1,000/year?
    ├─ NO → Cost = $100-$1,000/year, mark as negligible
    └─ YES → Significant cost, include in platform total
```

**Based on the answer, we either:**
- Add $0-$2,000/year to platform cost
- Confirm orders table is not actively used
- Merge the two redundant markdown files

---

## 📝 FILES TO MERGE (After Cost Determined)

**Current files:**
1. `ORDERS_PRODUCTION_COST.md` (79 lines)
2. `ORDERS_TABLE_PRODUCTION_COST.md` (114 lines)

**Both say:** "NOT FOUND - Investigation needed"

**After we get Dataflow costs:**
- Merge into single `ORDERS_PRODUCTION_COST_FINAL.md`
- Document Dataflow pipeline approach
- Include actual costs from billing
- Close out the investigation

---

## 💡 BOTTOM LINE

**To assess orders table cost, I need you to:**

1. ✅ **Run Query A** (Dataflow costs from DoIT billing)
2. ✅ **Run Query B** (Check if orders table exists/is populated)  
3. ✅ **Run Query C** (See if anyone uses v_orders)

**Don't need:**
- ❌ GitHub code (helpful but not critical for cost)
- ❌ Dataflow pipeline details (billing tells us cost)
- ❌ Complex analysis (3 simple queries answer everything)

**Expected result:** Orders table costs $0-$2,000/year (likely negligible)

---

**Can you run these 3 queries and share results?** That will let me complete Priority 3 assessment in minutes! 🎯

---

**Status:** 📋 AWAITING BILLING QUERIES  
**Priority:** MEDIUM (likely negligible cost)  
**Estimated Time:** 5 minutes after query results

