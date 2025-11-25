# EXACT Code Change for VICTOR-144915 Fix

**File**: `/Users/cezarmihaila/workspace/composer/dags/shopify/load_shopify_order_item_details.py`  
**Task**: `merge_order_item_details` (starts line 227)  
**WHERE clause**: Lines 335-342

---

## Current Code (Lines 335-342)

```python
            WHERE 
                o.ingestion_timestamp >= TIMESTAMP_SUB(
                    TIMESTAMP('{execution_date}'),
                    INTERVAL 48 HOUR
                )
                AND DATE(o.order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
                AND o.order_date >= '2024-01-01'
        );
```

---

## Modified Code (Add 2 Lines)

```python
            WHERE 
                o.ingestion_timestamp >= TIMESTAMP_SUB(
                    TIMESTAMP('{execution_date}'),
                    INTERVAL 48 HOUR
                )
                AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)  ← ADD THIS LINE
                AND DATE(o.order_date) <= DATE('{execution_date}')  ← ADD THIS LINE
                AND o.order_date >= '2024-01-01'
        );
```

---

## What to Change

### Line to Add After Line 340

**After this line**:
```python
                    INTERVAL 48 HOUR
                )
```

**Add these two lines**:
```python
                AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)
                AND DATE(o.order_date) <= DATE('{execution_date}')
```

**Before this existing line**:
```python
                AND o.order_date >= '2024-01-01'
```

---

## Visual Guide

```python
# Line 335
            WHERE 
# Line 336
                o.ingestion_timestamp >= TIMESTAMP_SUB(
# Line 337
                    TIMESTAMP('{execution_date}'),
# Line 338
                    INTERVAL 48 HOUR
# Line 339
                )
# Line 340 ← INSERT NEW LINES AFTER THIS
                AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)  # NEW LINE 1
                AND DATE(o.order_date) <= DATE('{execution_date}')  # NEW LINE 2
# Line 341 (existing)
                AND DATE(o.order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
# Line 342 (existing)
                AND o.order_date >= '2024-01-01'
# Line 343
        );
```

---

## Why This Works

### Existing Filter (Working)
```python
o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('{execution_date}'), INTERVAL 48 HOUR)
```
**Gets**: Orders ingested in last 48 hours  
**Problem**: Includes old orders that were RE-INGESTED recently

### NEW Filter 1: Lower Bound
```python
AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)
```
**Gets**: Only orders PLACED in last 7 days  
**Fixes**: Blocks old Oct 15 orders even if re-ingested Nov 25

### NEW Filter 2: Upper Bound
```python
AND DATE(o.order_date) <= DATE('{execution_date}')
```
**Gets**: Only orders PLACED on or before execution date  
**Fixes**: Prevents any future-dated orders (safety check)

---

## Example

**Execution date**: 2025-11-20

**OLD (Broken)**:
- Filter: `ingestion_timestamp >= 2025-11-18 00:00` (48 hours before Nov 20)
- Oct 15 order re-ingested Nov 25: `ingestion_timestamp = 2025-11-25` → **PASSES** ❌
- Result: Oct 15 order included (wrong!)

**NEW (Fixed)**:
- Filter 1: `ingestion_timestamp >= 2025-11-18 00:00` → Oct 15 order with Nov 25 ingestion **PASSES** ✅
- Filter 2: `order_date >= 2025-11-13` (7 days before Nov 20) → Oct 15 order **FAILS** ❌
- Filter 3: `order_date <= 2025-11-20` → Oct 15 order **FAILS** ❌
- Result: Oct 15 order excluded (correct!)

---

## Testing Before Deployment

### Option 1: Dry-Run Test

Copy the modified query and test it:

```bash
cd /Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/adhoc_analysis/victor_144915_load_shopify_order_item_details

# Create test query
cat > test_modified_query.sql << 'EOF'
-- Test the modified filter
SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT DATE(o.order_date)) AS distinct_dates,
    MIN(DATE(o.order_date)) AS min_date,
    MAX(DATE(o.order_date)) AS max_date
FROM `narvar-data-lake.return_insights_base.v_order_items` o
WHERE 
    o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('2025-11-20'), INTERVAL 48 HOUR)
    AND DATE(o.order_date) >= DATE_SUB(DATE('2025-11-20'), INTERVAL 7 DAY)  -- NEW
    AND DATE(o.order_date) <= DATE('2025-11-20')  -- NEW
    AND o.order_date >= '2024-01-01';
EOF

# Run dry-run
bq query --dry_run --use_legacy_sql=false < test_modified_query.sql
```

**Expected**: Should scan reasonable amount of data (not TBs)

### Option 2: Actually Run Test

```bash
# Run the test query (will take 30-60 seconds)
bq query --use_legacy_sql=false < test_modified_query.sql
```

**Expected Result**:
```
total_rows: 300,000 - 600,000 (not 4.2M)
distinct_dates: 2-3 (not 183)
min_date: 2025-11-13 to 2025-11-18
max_date: 2025-11-20
```

---

## Deployment Checklist

- [ ] Backup current DAG file
- [ ] Open `/Users/cezarmihaila/workspace/composer/dags/shopify/load_shopify_order_item_details.py`
- [ ] Find line 340 (after `INTERVAL 48 HOUR` closing paren)
- [ ] Add the two new AND conditions
- [ ] Save file
- [ ] Test with dry-run (optional but recommended)
- [ ] Commit to git
- [ ] Push to trigger Composer sync
- [ ] Verify in Airflow UI (check code view)
- [ ] Monitor tonight's DAG run

---

## After Deployment

Watch for these success indicators:
- ✅ DAG completes in 5-10 minutes (not 6 hours)
- ✅ Temp table has 2-3 distinct dates (not 183)
- ✅ Slot consumption ~11-15 slot-hours (not 80-90)
- ✅ No timeout errors

If any issues, rollback using the backup file.

---

## Summary

**File**: `/Users/cezarmihaila/workspace/composer/dags/shopify/load_shopify_order_item_details.py`  
**Line**: Insert after line 340  
**Change**: Add 2 AND conditions for order_date filtering  
**Effort**: 5 minutes  
**Test**: Optional dry-run to verify syntax

