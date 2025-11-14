# Priorities 2-5: Requirements & Approach

**Date:** November 14, 2025  
**Status:** Ready to proceed - awaiting inputs  
**Method:** Using correct Method A (traffic_classification) [[memory:11214888]]

---

## 📋 PRIORITY 2: return_item_details ETL Analysis

**Table:** `narvar-data-lake.return_insights_base.return_item_details`  
**Current Cost Estimate:** $123,717/year (using incorrect Method B - needs recalculation)  
**DAG:** `/Users/cezarmihaila/workspace/composer/dags/shopify/load_return_item_details.py` ✓

### ✅ What I Can Do Right Now

**1. Explain DAG Logic in Plain English** ✓
- Already have the Python code
- Can explain MERGE pattern
- Runs every 30 minutes
- Processes Shopify returns data

**2. Provide SQL Pattern Examples** ✓
```python
# From DAG:
MERGE `{PROJECT_ID}.return_insights_base.return_item_details` T
USING (
  SELECT * FROM `{PROJECT_ID}.return_insights_base.v_return_item_details`
  WHERE DATE(return_initiation_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 30 DAY)
) S
ON T.shop_id = S.shop_id AND T.return_id = S.return_id AND T.return_items_id = S.return_items_id
WHEN MATCHED AND (conditions...) THEN UPDATE
WHEN NOT MATCHED THEN INSERT
```

**3. Recalculate Cost Using Method A**

**Query traffic_classification:**
```sql
WHERE UPPER(query_text_sample) LIKE '%MERGE%'
  AND UPPER(query_text_sample) LIKE '%return_item_details%'
  AND principal_email LIKE '%airflow%'
  AND DATE(creation_time) BETWEEN '2024-09-01' AND '2024-10-31'
```

**Expected corrected cost:** $50K-$60K/year (not $124K)

---

## 📋 PRIORITY 3: orders Table Assessment

**Table:** `monitor-base-us-prod.monitor_base.orders`  
**Technology:** Dataflow streaming pipeline (PubSub → Beam → BigQuery)  
**Files to merge:** `ORDERS_PRODUCTION_COST.md` + `ORDERS_TABLE_PRODUCTION_COST.md` ✓

### ⚠️ What I Need From You

**Cannot access:**
- ❌ GitHub repository: `monitor-analytics/order-to-bq`
- ❌ Not needed! Billing data is sufficient

**What I need instead:**

**Run 3 simple queries** (see `ORDERS_TABLE_COST_ASSESSMENT_PLAN.md`):

1. **Dataflow costs query** - Check if pipeline is running
2. **Orders table status** - Check if table exists/populated
3. **View usage check** - See if anyone uses v_orders

**Expected result:** $0-$2,000/year (likely negligible or $0)

---

## 📋 PRIORITY 4: ft_benchmarks_latest

**Table:** `monitor-base-us-prod.monitor_base.ft_benchmarks_latest`  
**Current Estimate:** $0 (not found in audit logs)  
**DAG:** `/Users/cezarmihaila/workspace/composer/dags/monitor_benchmarks/query.py` Line 35 ✓

### ✅ What I Can Do Right Now

**1. Explain Logic in Plain English** ✓

From the code I already have:
```python
def monitor_ft_benchmarks_latest_etl_query(monitor_project):
    # Populates ft_benchmarks_latest table
    # Source: monitor_base.ft_benchmarks (historical benchmark data)
    # Logic: Get latest 5 days of ft_benchmarks, filter to most recent
```

**Plain English:**
- Reads from `monitor_base.ft_benchmarks` (historical table)
- Filters to last 5 days
- Takes latest ingestion timestamp
- Writes to `ft_benchmarks_latest` (latest snapshot)
- This is a **derived/summary table**, not primary ETL

**2. Map to BigQuery Query Pattern**

**Search traffic_classification:**
```sql
WHERE (UPPER(query_text_sample) LIKE '%ft_benchmarks_latest%' OR
       UPPER(query_text_sample) LIKE '%ft_benchmark%')
  AND statement_type IN ('INSERT', 'CREATE_TABLE_AS_SELECT')
```

**Expected cost:** $0-$100/year (summary table, infrequent updates)

---

## 📋 PRIORITY 5: tnt_benchmarks_latest

**Table:** `monitor-base-us-prod.monitor_base.tnt_benchmarks_latest`  
**Current Estimate:** $0 (not found in audit logs)  
**DAG:** `/Users/cezarmihaila/workspace/composer/dags/monitor_benchmarks/query.py` Line 27 ✓

### ✅ What I Can Do Right Now

**1. Explain Logic in Plain English** ✓

From the code I already have:
```python
def monitor_tnt_benchmarks_latest_etl_query(monitor_project):
    # Populates tnt_benchmarks_latest table
    # Source: monitor_base.tnt_benchmarks (historical benchmark data)  
    # Logic: Get latest 5 days of tnt_benchmarks, filter to most recent
```

**Plain English:**
- Reads from `monitor_base.tnt_benchmarks` (historical table)
- Filters to last 5 days
- Takes latest ingestion timestamp  
- Writes to `tnt_benchmarks_latest` (latest snapshot)
- This is a **derived/summary table**, not primary ETL

**2. Map to BigQuery Query Pattern**

**Search traffic_classification:**
```sql
WHERE (UPPER(query_text_sample) LIKE '%tnt_benchmarks_latest%' OR
       UPPER(query_text_sample) LIKE '%tnt_benchmark%')
  AND statement_type IN ('INSERT', 'CREATE_TABLE_AS_SELECT')
```

**Expected cost:** $0-$100/year (summary table, infrequent updates)

---

## 🎯 SUMMARY OF WHAT I CAN/CANNOT DO

### ✅ CAN DO WITHOUT ADDITIONAL INPUT

**Priority 2:** 
- Explain DAG logic ✓
- Provide SQL examples ✓
- Recalculate using Method A ✓

**Priority 4:**
- Explain ft_benchmarks logic ✓
- Map to BigQuery patterns ✓
- Estimate cost using Method A ✓

**Priority 5:**
- Explain tnt_benchmarks logic ✓
- Map to BigQuery patterns ✓
- Estimate cost using Method A ✓

### ⚠️ NEED INPUT FROM YOU

**Priority 3:**
- 3 simple SQL queries (DoIT billing + table status + usage)
- OR confirmation that Dataflow pipeline is not running
- OR access to GCP Console billing export

**Benchmark TRD PDF:**
- Not critical for cost assessment
- DAG code is sufficient
- Can skip if needed

---

## 💡 RECOMMENDATIONS

### Option A: Run Billing Queries (FASTEST)

**Time:** 10 minutes  
**What:** Run the 4 queries I provided  
**Result:** Definitive costs for all tables  

**Queries:**
1. Dataflow costs (Priority 3)
2. return_item_details via Method A (Priority 2)
3. ft_benchmarks via Method A (Priority 4)
4. tnt_benchmarks via Method A (Priority 5)

---

### Option B: Let Me Proceed With What I Have

**I can immediately:**
1. Complete Priorities 2, 4, 5 with DAG analysis
2. Use Method A to estimate costs
3. Document logic in plain English
4. Pause Priority 3 until billing data available

**Would you like me to:**
- ✅ Start on Priorities 2, 4, 5 now?
- ⏸️ Wait for you to run billing queries?
- 🎯 Something else?

---

**Ready to proceed when you are!** 🚀

---

**Status:** 📊 ANALYSIS READY  
**Blocked:** Priority 3 needs billing queries  
**Can Start:** Priorities 2, 4, 5 immediately

