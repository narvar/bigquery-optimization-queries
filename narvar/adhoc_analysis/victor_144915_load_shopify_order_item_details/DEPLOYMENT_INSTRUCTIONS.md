# Deployment Instructions: Add Explicit Date Filter

**Date**: November 25, 2025  
**Fix**: Add safety net date filter to prevent old backfilled orders  
**Effort**: 5 minutes  
**Risk**: Low

---

## What File to Modify

**File**: The Airflow DAG Python file (likely located at):
```
/Users/cezarmihaila/workspace/composer/dags/shopify/load_shopify_order_item_details.py
```

**OR** wherever this DAG is stored in your Airflow/Composer repository.

---

## What Task to Modify

**Task name**: `merge_order_item_details`

This is the BigQueryOperator task that creates `tmp_order_item_details_2025-11-20`.

---

## Exact Location: In the SQL Parameter

Find this section in the `merge_order_item_details` task:

```python
merge_order_item_details = BigQueryOperator(
    task_id='merge_order_item_details',
    dag=dag,
    sql="""
        CREATE OR REPLACE TABLE `{PROJECT_ID}.return_insights_base.tmp_order_item_details_{execution_date}` AS (
            SELECT DISTINCT
                o.store_name as shopify_domain,
                o.retailer_moniker,
                ...
                (many columns)
                ...
            FROM `{PROJECT_ID}.return_insights_base.v_order_items` o 
            LEFT JOIN ...
            LEFT JOIN ...
            WHERE 
                o.ingestion_timestamp >= TIMESTAMP_SUB(
                    TIMESTAMP('{execution_date}'),
                    INTERVAL 48 HOUR
                )
                AND DATE(o.order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
                AND o.order_date >= '2024-01-01'
        );
    """.format(PROJECT_ID=PROJECT_ID, execution_date="{{ ti.xcom_pull(task_ids='init', key='execution_date') }}")
)
```

---

## The Change: Add Two Lines to WHERE Clause

### BEFORE (Current Code)

```python
            WHERE 
                o.ingestion_timestamp >= TIMESTAMP_SUB(
                    TIMESTAMP('{execution_date}'),
                    INTERVAL 48 HOUR
                )
                AND DATE(o.order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
                AND o.order_date >= '2024-01-01'
```

### AFTER (Add These Two Lines)

```python
            WHERE 
                o.ingestion_timestamp >= TIMESTAMP_SUB(
                    TIMESTAMP('{execution_date}'),
                    INTERVAL 48 HOUR
                )
                AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)  -- NEW: Safety net
                AND DATE(o.order_date) <= DATE('{execution_date}')  -- NEW: Upper bound
                AND o.order_date >= '2024-01-01'  -- KEEP: Existing filter
```

**Note**: I also changed the 6-month filter to use `execution_date` instead of `CURRENT_DATE()` for consistency, but the key additions are lines 2 and 3.

---

## Why These Two Lines

### Line 1: Lower Bound
```sql
AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)
```

**Purpose**: Prevent orders older than 7 days from being included  
**How it helps**: Even if Oct 15 orders are re-ingested with Nov 25 `ingestion_timestamp`, they'll be filtered out because `order_date = Oct 15` is more than 7 days before `execution_date = Nov 20`

### Line 2: Upper Bound
```sql
AND DATE(o.order_date) <= DATE('{execution_date}')
```

**Purpose**: Prevent future-dated orders (shouldn't happen but good practice)  
**How it helps**: Ensures we only process orders up to the execution date

---

## Full Modified WHERE Clause

Here's the complete WHERE clause with all filters:

```sql
WHERE 
    -- Existing: Only recently ingested data (last 48 hours)
    o.ingestion_timestamp >= TIMESTAMP_SUB(
        TIMESTAMP('{execution_date}'),
        INTERVAL 48 HOUR
    )
    -- NEW: Only orders from last 7 days (prevents old backfilled orders)
    AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)
    -- NEW: No future orders (safety check)
    AND DATE(o.order_date) <= DATE('{execution_date}')
    -- Existing: Minimum historical date
    AND o.order_date >= '2024-01-01'
```

---

## How to Deploy

### Step 1: Backup Current DAG
```bash
cp /path/to/load_shopify_order_item_details.py /path/to/load_shopify_order_item_details.py.backup
```

### Step 2: Edit the File

Open the DAG file in your editor and modify the `merge_order_item_details` task's SQL parameter WHERE clause as shown above.

### Step 3: Deploy to Airflow/Composer

**If using Git deployment**:
```bash
git add dags/shopify/load_shopify_order_item_details.py
git commit -m "Fix VICTOR-144915: Add explicit date filter to prevent backfilled data"
git push
# Wait for Composer to sync (usually 1-2 minutes)
```

**If using direct upload**:
```bash
gcloud composer environments storage dags import \
    --environment YOUR_COMPOSER_ENV \
    --location YOUR_LOCATION \
    --source load_shopify_order_item_details.py
```

### Step 4: Verify in Airflow UI

1. Go to Airflow UI
2. Find `load_shopify_order_item_details` DAG
3. Click "Code" button to view
4. Verify the WHERE clause shows the new filters

### Step 5: Test (Optional but Recommended)

**Dry-run the modified query**:
```sql
-- Copy the full query from the DAG
-- Replace {execution_date} with '2025-11-25'
-- Replace {PROJECT_ID} with 'narvar-data-lake'
-- Run with --dry_run flag to check syntax and bytes scanned
```

### Step 6: Monitor Tonight's Run

Watch the DAG execution tonight (or trigger manually for testing):
- Should complete in 5-10 minutes
- Temp table should have only 2-3 distinct dates
- Slot consumption should be ~11-15 slot-hours

---

## Alternative: If You Can't Find the DAG File

### Option 1: Check Composer DAG Folder

```bash
# List all Shopify DAGs
ls -la /Users/cezarmihaila/workspace/composer/dags/shopify/

# Search for the file
find /Users/cezarmihaila/workspace/composer -name "load_shopify_order_item_details.py"
```

### Option 2: Check Airflow UI

1. Go to Airflow web UI
2. DAGs → `load_shopify_order_item_details`
3. Click "Code" button
4. Copy the full code
5. Save locally, modify, re-upload

### Option 3: Ask Team

The DAG owner is **Julia Le** (from the DAG code: `'owner': 'Julia Le'`). She can point you to the exact file location.

---

## Verification After Deployment

### Check 1: Tonight's Temp Table

After tonight's DAG run, check:
```sql
SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT DATE(order_date)) AS distinct_dates,
    MIN(DATE(order_date)) AS min_date,
    MAX(DATE(order_date)) AS max_date
FROM 
    `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-25`;
```

**Expected**:
- total_rows: 300K - 600K (not 4.2M)
- distinct_dates: 2-3 (not 183)
- min_date: 2025-11-18 or later
- max_date: 2025-11-25

### Check 2: Job Performance

```sql
SELECT 
    job_id,
    creation_time,
    total_slot_ms,
    ROUND(total_slot_ms / 3600000, 2) AS slot_hours,
    TIMESTAMP_DIFF(end_time, start_time, MINUTE) AS duration_minutes,
    state
FROM 
    `narvar-data-lake.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE 
    creation_time >= TIMESTAMP('2025-11-25 00:00:00')
    AND user_email = 'airflow-bq-job-user-2@narvar-data-lake.iam.gserviceaccount.com'
    AND query LIKE '%tmp_product_insights_updates%'
ORDER BY creation_time DESC
LIMIT 10;
```

**Expected**:
- duration_minutes: 5-10 (not 360)
- slot_hours: 11-15 (not 80-90)
- state: DONE (not timeout)

---

## Rollback Plan (If Needed)

If the fix causes issues:

```bash
# Restore backup
cp /path/to/load_shopify_order_item_details.py.backup /path/to/load_shopify_order_item_details.py

# Redeploy
git add dags/shopify/load_shopify_order_item_details.py
git commit -m "Rollback VICTOR-144915 fix"
git push
```

---

## Summary

**WHERE to add filter**: In the DAG file `load_shopify_order_item_details.py`  
**WHICH task**: `merge_order_item_details` BigQueryOperator  
**WHICH SQL section**: The WHERE clause (before the final `);` closing the SELECT)  
**WHAT to add**: Two AND conditions for date filtering

See the BEFORE/AFTER sections above for exact code changes.

