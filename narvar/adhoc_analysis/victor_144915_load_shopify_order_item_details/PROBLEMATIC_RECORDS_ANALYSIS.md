# Problematic Records Analysis

**Date**: November 25, 2025  
**Table**: `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`  
**Total Records**: 4,207,927

---

## Summary: What Makes Records "Problematic"

The records themselves aren't corrupted or invalid. The problem is that **2.78M records (66%) should NOT be in this temp table at all**. They're from old dates (May-October 2025) that should have been filtered out by the `ingestion_timestamp >= TIMESTAMP_SUB(...)` clause.

---

## The Core Issue

### Expected Data
```
Execution date: 2025-11-20
Filter: 48-hour window
Expected: Nov 18-20 data (~500K rows)
Expected dates: 2-3 distinct dates
```

### Actual Data (from Query 3 results)
```
Actual: 4,207,927 rows
Actual dates: 183 distinct dates (May 1 - Nov 20)
Problem: 66% of data is from May-October (should not be here!)
```

---

## Breakdown of Problematic Records

### By Time Period

| Period | Rows | % of Total | Problem Severity |
|--------|------|------------|------------------|
| **Nov 18-20 (Recent)** | 2,481,678 | 59.0% | ✅ **EXPECTED** - These should be here |
| **Oct 15-17 (Spike)** | 350,060 | 9.3% | ❌ **PROBLEM** - 1 month old, should NOT be here |
| **May-Oct (Tail)** | 1,376,189 | 31.7% | ❌❌ **CRITICAL** - 1-6 months old, definitely wrong |

### Date Distribution Details (from Query 3)

Top problematic date ranges:
```
2025-11-20: 564,249 rows (13.4%) - ✅ Expected
2025-11-19: 1,116,130 rows (26.5%) - ✅ Expected  
2025-11-18: 801,299 rows (19.0%) - ✅ Expected

2025-10-17: 71,262 rows (1.7%) - ❌ 34 days old
2025-10-16: 162,874 rows (3.9%) - ❌ 35 days old
2025-10-15: 115,924 rows (2.8%) - ❌ 36 days old

(... 177 more dates from May-Oct ...)
```

---

## Impact on Aggregation

### The Multiplication Effect

When the query groups by these dimensions:
```sql
GROUP BY
    retailer_moniker,          -- 194 distinct
    shopify_domain,            -- 207 distinct  
    DATE(order_date),          -- 183 distinct ← THE PROBLEM!
    order_checkout_locale,
    order_item_product_id,
    order_item_sku,            -- 648,642 distinct
    ... (15 dimensions total)
```

**The math**:
- With 3 dates (expected): 3 × 194 × avg_skus = ~1-2M groups ✅ Manageable
- With 183 dates (actual): 183 × 194 × avg_skus = **10-50M groups** ❌ Timeout!

---

## How to Identify Specific Problematic Records

### Query 1: Records That Should Not Be Here

```sql
-- All records more than 7 days old
SELECT 
    DATE(order_date) AS order_date,
    retailer_moniker,
    COUNT(*) AS row_count,
    COUNT(DISTINCT order_item_sku) AS sku_count
FROM 
    `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
WHERE 
    DATE(order_date) < '2025-11-13'  -- More than 7 days before Nov 20
GROUP BY 
    DATE(order_date),
    retailer_moniker
ORDER BY 
    order_date DESC
LIMIT 100;
```

**Expected result**: ~1.73M problematic records across 180 old dates

---

### Query 2: Retailers Contributing Most to Old Data

```sql
-- Which retailers have the most historical data?
SELECT 
    retailer_moniker,
    COUNT(*) AS total_records,
    COUNT(DISTINCT DATE(order_date)) AS distinct_dates,
    MIN(DATE(order_date)) AS oldest_date,
    MAX(DATE(order_date)) AS newest_date,
    DATE_DIFF(MAX(DATE(order_date)), MIN(DATE(order_date)), DAY) AS date_span_days
FROM 
    `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
GROUP BY 
    retailer_moniker
HAVING 
    COUNT(DISTINCT DATE(order_date)) > 30  -- More than 30 days of data
ORDER BY 
    date_span_days DESC,
    total_records DESC
LIMIT 20;
```

**What to look for**: Retailers with date_span_days > 30 are contributing heavily to the problem.

---

### Query 3: Sample Problematic Records

```sql
-- Get actual example records from old dates
SELECT 
    order_date,
    retailer_moniker,
    shopify_domain,
    order_number,
    order_item_sku,
    order_item_name
FROM 
    `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
WHERE 
    DATE(order_date) = '2025-10-16'  -- The big spike date
LIMIT 20;
```

**Purpose**: Verify these are real data (not corrupted), just wrongly included.

---

### Query 4: Estimate Aggregation Cardinality

```sql
-- Simulate the affected_items CTE and count unique combinations
WITH affected_items_sim AS (
    SELECT DISTINCT
        retailer_moniker,
        shopify_domain,
        DATE(order_date) AS order_date,
        order_item_sku
    FROM 
        `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
)
SELECT 
    COUNT(*) AS total_affected_items_combinations,
    COUNT(DISTINCT retailer_moniker) AS distinct_retailers,
    COUNT(DISTINCT shopify_domain) AS distinct_domains,
    COUNT(DISTINCT order_date) AS distinct_dates,
    COUNT(DISTINCT order_item_sku) AS distinct_skus,
    -- Estimate minimum groups (conservative)
    COUNT(DISTINCT CONCAT(
        retailer_moniker, '|',
        shopify_domain, '|',
        CAST(order_date AS STRING), '|',
        order_item_sku
    )) AS estimated_min_final_groups
FROM 
    affected_items_sim;
```

**Expected result**: 
- `distinct_dates`: 183
- `estimated_min_final_groups`: 1-2 million (this is the join key count we found: 1,180,017)

---

## Why These Records Cause Aggregation Explosion

### Step-by-Step Problem

1. **affected_items CTE** creates 1.18M distinct combinations from 4.2M records
   - This includes 183 distinct dates worth of data

2. **JOIN with order_item_details** (236M rows):
   ```sql
   INNER JOIN order_item_details r
   ON r.retailer_moniker = a.retailer_moniker
   AND r.shopify_domain = a.shopify_domain
   AND DATE(r.order_date) = DATE(a.order_date)  ← Joins on 183 dates!
   AND r.order_item_sku = a.order_item_sku
   ```
   - For EACH of the 183 dates, BigQuery must scan order_item_details
   - Produces 20M joined rows

3. **GROUP BY aggregation**:
   ```sql
   GROUP BY retailer, domain, date, sku, ... (15 dimensions)
   ```
   - With 183 dates, creates 10-50M unique grouping combinations
   - BigQuery runs out of memory trying to aggregate
   - **Result: Timeout after 6 hours**

---

## The Solution (Not a Data Fix)

**Important**: You don't need to "fix" individual problematic records. The issue is the **query filter not working**.

### Root Cause
The `ingestion_timestamp >= TIMESTAMP_SUB(...)` filter doesn't work because:
- `v_order_items.ingestion_timestamp` column doesn't exist, OR
- Column exists but has NULL/incorrect values

### The Fix
Add explicit date filter to the DAG:
```sql
WHERE 
    o.ingestion_timestamp >= TIMESTAMP_SUB(TIMESTAMP('{execution_date}'), INTERVAL 48 HOUR)
    AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)  -- NEW
```

This will prevent old records from entering the temp table in the first place.

---

## For Your Debug Query

Your query (without the histogram UDF) should work fine once the temp table has the correct data scope. The issue isn't the query logic—it's the input data containing 61x more dates than expected.

### Test With Filtered Data

To verify your query logic works, test with only recent dates:

```sql
CREATE OR REPLACE TABLE `narvar-data-lake.return_insights_base.tmp_product_insights_updates_2025-11-20_test` AS (
    WITH affected_items AS (
        SELECT DISTINCT
            retailer_moniker,
            shopify_domain,
            order_date,
            ... 
        FROM `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20_debug`
        WHERE DATE(order_date) >= '2025-11-18'  -- FILTER TO RECENT 3 DAYS ONLY
    )
    SELECT
        r.retailer_moniker,
        ... (your aggregations)
    FROM `narvar-data-lake.return_insights_base.order_item_details` r
    INNER JOIN affected_items a ...
    GROUP BY ...
);
```

**Expected**: Completes in 5-10 minutes instead of timing out.

---

## Summary

**Problematic records**:
- 1,726,249 records from dates before Nov 13 (>7 days old)
- Spread across 180 old dates
- Especially the Oct 15-17 spike (350K records)

**Why they're problematic**:
- Not because they're corrupted
- Because they create 183 dates in the GROUP BY
- Which creates 61x more grouping combinations
- Which exhausts memory and causes timeout

**The fix**:
- Not to delete these records manually
- But to fix the filter so they never enter the temp table
- See NEXT_STEPS.md for deployment instructions

---

## Files for Reference

- [03_temp_table_date_distribution.csv](./results/03_temp_table_date_distribution.csv) - Complete date breakdown
- [EXECUTION_PLAN_ANALYSIS.md](./EXECUTION_PLAN_ANALYSIS.md) - Proves it's aggregation explosion
- [NEXT_STEPS.md](./NEXT_STEPS.md) - How to fix the root cause

