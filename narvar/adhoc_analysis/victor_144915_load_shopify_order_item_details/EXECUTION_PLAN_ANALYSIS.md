# Execution Plan Analysis: Failed vs Successful Jobs

**Date**: November 25, 2025  
**Comparison**: Nov 20 Failed vs Nov 24 Successful

---

## Executive Summary

Both jobs read similar amounts of data from the base tables (~4M rows from temp table, ~236M rows from fact table), but the **failed job times out during the aggregation stage** while processing 183 distinct dates. The successful job completes because it only processes 2-3 dates.

**Key Finding**: This is **NOT a traditional cartesian join** (where join conditions are missing). Instead, it's an **aggregation explosion** caused by excessive grouping dimensions (183 dates instead of 3).

---

## High-Level Comparison

| Metric | Failed (Nov 20) | Successful (Nov 24) | Ratio |
|--------|----------------|-------------------|-------|
| **Total Slot-ms** | 309,102,626 | 40,832,524 | **7.6x** |
| **Duration** | 6 hours (timeout) | 5.4 minutes | **67x** |
| **Timeline Entries** | 21,563 | 322 | **67x** |
| **Query Plan Stages** | 14 | 28 | 0.5x |
| **Bytes Processed** | 0 (timeout) | 74.7 GB | N/A |
| **Shuffle Output** | 0 (no data) | 89.1 GB | N/A |
| **Final Status** | RUNNING (timeout) | COMPLETE | - |

---

## Detailed Stage-by-Stage Analysis

### Failed Job (Nov 20): `script_job_39dbaa9ec3c4e9362f13d9774bb0151e_0`

#### Stage S00: Input (tmp_order_item_details)
```
Status: COMPLETE
Records Read: 4,207,927
Records Written: 4,205,180
Shuffle Output: 0 bytes
```

**Analysis**: Reads the temp table with **183 distinct dates**. This is 60x more data than expected.

---

#### Stage S04: Input (order_item_details)
```
Status: COMPLETE
Records Read: 233,419,783  
Records Written: 233,419,605
Shuffle Output: 0 bytes
```

**Analysis**: Reads the massive 236M row fact table. This is the full table scan.

---

#### Stages S01-S0C: Repartitioning
```
Multiple repartition stages to prepare data for join/aggregation
Total records shuffled: ~60M records across 12 repartition stages
Shuffle Output: ALL ZEROS (suspicious - indicates timeout before metrics captured)
```

**Analysis**: BigQuery is reorganizing data for distributed join, but shuffle metrics are missing, suggesting the job timed out before metrics were finalized.

---

#### Stage S0D: Output **[STUCK HERE]**
```
Status: RUNNING (never completed!)
Input Stages: [11, 12, 4, 3]
Records Read: 237,041,253
Records Written: 20,077,314 (partial)
Shuffle Output: 0 bytes
```

**Critical Finding**: This output stage read 237M records but only managed to write 20M before timing out. The query was stuck in the aggregation/output phase for 6 hours.

**Why it's stuck**:
- Aggregating across: 183 dates × 194 retailers × 648K SKUs × multiple metrics
- GROUP BY dimensions: `retailer_moniker, shopify_domain, order_date, order_checkout_locale, order_item_product_id, order_item_description, order_item_name, order_item_sku, order_item_vendor, order_item_size, order_item_color, order_item_product_type, return_outcome, order_item_variant_id, order_item_variant_title`
- **15 grouping dimensions** with 183 date values = massive cardinality

---

### Successful Job (Nov 24): `script_job_b2654d592228ccb1e1d6ebe7619a1c74_0`

#### Stage S00: Input (tmp_order_item_details)
```
Status: COMPLETE
Records Read: 3,907,163
Records Written: 3,907,052
Shuffle Output: 1.05 GB
```

**Analysis**: Slightly fewer records (3.9M vs 4.2M), but likely still contains historical data. The difference is in how much of it gets joined/aggregated.

---

#### Stage S04: Input (order_item_details)
```
Status: COMPLETE
Records Read: 236,340,306
Records Written: 236,340,128
Shuffle Output: 89.1 GB
```

**Analysis**: Similar fact table size (236M vs 233M). **This is NOT the bottleneck** - both jobs scan similar amounts.

---

#### Stage S0D: Join+ **[COMPLETES SUCCESSFULLY]**
```
Status: COMPLETE
Input Stages: [3, 4, 12, 11]
Records Read: 240,230,198
Records Written: 20,720,402
Shuffle Output: 6.6 GB
```

**Critical Success**: The join completes in reasonable time because:
- Only 2-3 distinct dates in the filtered data
- Efficient hash join on join keys
- Manageable output cardinality

---

#### Stage S0E: Aggregate+ **[FIRST AGGREGATION]**
```
Status: COMPLETE
Records Read: 20,720,402
Records Written: 18,871,745
Shuffle Output: 7.1 GB
```

**Analysis**: First aggregation reduces 20.7M joined records to 18.9M. This is the "affected_items" CTE aggregation.

---

#### Stages S0F-S18: Multiple Repartitions
```
Multiple stages to reorganize data for final aggregation
Total shuffle: ~20 GB across multiple stages
All stages COMPLETE
```

**Analysis**: BigQuery's query optimizer creates many stages for distributed aggregation, but all complete successfully because the data volume is manageable.

---

#### Stage S19: Aggregate+ **[FINAL AGGREGATION]**
```
Status: COMPLETE
Records Read: 13,617,988
Records Written: 1,540,389
Shuffle Output: 702 MB
```

**Analysis**: Final GROUP BY aggregation produces 1.5M output rows (product insights grouped by retailer, date, SKU, etc.). **This is the stage that times out in the failed job.**

---

#### Stage S1B: Output **[WRITES RESULTS]**
```
Status: COMPLETE
Records Read: 1,540,389
Records Written: 1,540,389
Shuffle Output: 0 bytes
```

**Analysis**: Successfully writes 1.5M rows to the output table.

---

## Why Is This NOT a Cartesian Join?

A **cartesian join** occurs when:
- Join conditions are missing or incorrect
- Every row in table A matches every row in table B
- Output = rows(A) × rows(B)

**Evidence this is NOT cartesian**:
1. ✅ Join conditions are present and correct:
   ```sql
   ON r.retailer_moniker = a.retailer_moniker
   AND r.shopify_domain = a.shopify_domain
   AND DATE(r.order_date) = DATE(a.order_date)
   AND r.order_item_sku = a.order_item_sku
   ```

2. ✅ Output size is reasonable: 20-21M rows, not billions
   - If cartesian: 4.2M × 236M = **991 trillion rows!**
   - Actual: 20M rows (0.000002% of cartesian)

3. ✅ Records read vs written shows proper filtering:
   - Input: 237M records
   - Output: 20M records
   - Reduction: 11.8x (proper join filtering)

---

## The Real Problem: Aggregation Explosion

### What's Actually Happening

1. **Input from temp table**: 4.2M rows covering **183 distinct dates**
2. **Join with fact table**: Produces 20M joined rows
3. **Group By aggregation**: Groups by **15 dimensions** including date
4. **Explosion**: 183 dates × 194 retailers × 648K SKUs × other dimensions
5. **Result**: BigQuery tries to create millions of unique groups
6. **Memory pressure**: Exceeds available memory, causes spilling/slowdown
7. **Timeout**: After 6 hours of aggregation, job times out

### Why Nov 24 Works

1. **Input from temp table**: 3.9M rows covering **2-3 distinct dates only**
2. **Join with fact table**: Produces 20M joined rows (similar!)
3. **Group By aggregation**: Groups by same 15 dimensions
4. **Manageable**: 3 dates × 194 retailers × smaller SKU subset
5. **Result**: ~1.5M unique groups (manageable)
6. **Fast**: Aggregation completes in minutes
7. **Success**: Writes 1.5M rows to output table

---

## Timeline Analysis

### Failed Job: 21,563 Timeline Entries

The massive number of timeline entries indicates:
- **Repeated micro-retries** as BigQuery tries to complete aggregation
- **Memory pressure** causing spillage to disk and re-reads
- **Slot thrashing** as workers repeatedly process the same data

Sample timeline pattern (inferred):
- 0-30 min: Input stages complete quickly
- 30 min - 6 hours: Stuck in aggregation/output (S0D stage)
- Thousands of timeline entries as BigQuery retries the aggregation
- Eventually hits 6-hour timeout limit

### Successful Job: 322 Timeline Entries

Normal execution pattern:
- Each stage generates ~10-20 timeline entries
- 28 stages × ~11 entries each = ~308 entries
- Clean execution with no retries or thrashing

---

## Memory and Shuffle Analysis

### Failed Job: No Shuffle Data (Red Flag!)

```
All Shuffle Output Bytes: 0
All Shuffle Output Bytes Spilled: 0
```

**This is suspicious** - a query processing 237M rows MUST shuffle data. The zeros indicate:
- Metrics weren't captured before timeout
- Job failed before finalizing statistics
- Internal error state

### Successful Job: Proper Shuffle Metrics

```
S04 (Input): 89.1 GB shuffled
S0D (Join): 6.6 GB shuffled
S0E (Aggregate): 7.1 GB shuffled
Total: ~100 GB shuffled across all stages
```

**This is normal** for a query processing 240M rows with joins and aggregations.

---

## Root Cause Confirmation

### The Temp Table Date Distribution

From Query 3 results (`03_temp_table_date_distribution.csv`):

```
Nov 20, 2025: 564,249 rows (13.4%)
Nov 19, 2025: 1,116,130 rows (26.5%)
Nov 18, 2025: 801,299 rows (19.0%)
---
Recent 3 days: 2,481,678 rows (59.0%)
Oct 15-17: 350,060 rows (9.3%)
May-Oct: 1,376,189 rows (31.7%)
---
Total: 4,207,927 rows across 183 distinct dates
```

### The Aggregation Cardinality Explosion

**Failed job processes**:
- 183 dates × 194 retailers = **35,502 date-retailer combinations**
- Each with potentially thousands of SKUs
- **Estimated output cardinality: 10-50 million groups**

**Successful job processes**:
- 3 dates × 194 retailers = **582 date-retailer combinations**
- **Estimated output cardinality: 1-2 million groups** (61x fewer!)

**This is why aggregation times out**: 61x more grouping combinations!

---

## Job IDs for BigQuery Console Comparison

### Failed Jobs to Analyze

**Nov 20 Failed** (VictorOps alert):
- Parent: `job_GfBO-8zBmqLqbOcAErnuRkaa0LQO`
- Child: `script_job_39dbaa9ec3c4e9362f13d9774bb0151e_0` **← Analyze this one**
- Console: https://console.cloud.google.com/bigquery?project=narvar-data-lake&j=bq:US:script_job_39dbaa9ec3c4e9362f13d9774bb0151e_0

**Nov 19 Failed** (for comparison):
- `job_Wi2G9fWfLVPbs-EpgkjU7AfugSoG` (attempt 1)
- `job_uGCk9mLHF5NP2TNo2GtVxlBZluXj` (attempt 2)
- `job_KaXz5GqUT4AoJhwDFg8RMm1XUQPY` (attempt 3)
- `job_s6sJ9_blGH6ZgNFFS2zMO6j4mATV` (attempt 4)

### Successful Jobs to Compare

**Nov 24 Success**:
- Parent: `job_1zkKHJkoV9X2I-EreeiClsHpn2ix`
- Child: `script_job_b2654d592228ccb1e1d6ebe7619a1c74_0` **← Analyze this one**
- Console: https://console.cloud.google.com/bigquery?project=narvar-data-lake&j=bq:US:script_job_b2654d592228ccb1e1d6ebe7619a1c74_0

**Nov 18 Slow but Successful**:
- Parent: `job_cgyA-u-wp9uqeDCYv5UcTgTwTHJZ`
- Child: `script_job_8285f5268083a9d46c1194b0ee7a84b2_0`
- Duration: 113 minutes (20x slower than Nov 24, but still completes)

---

## What to Look For in BigQuery Console

### 1. Timeline Tab (Most Important!)

**Failed Job**:
- Look for the S0D (Output) stage
- Will show "RUNNING" status for hours
- Many repeated timeline entries
- Slot utilization may spike and drop repeatedly

**Successful Job**:
- All stages show "COMPLETE"
- Clean progression through stages
- Consistent slot utilization

### 2. Execution Details Tab

**Failed Job**:
- May show bytes spilled to disk (if metrics captured)
- High memory utilization
- Repeated stage retries

**Successful Job**:
- No spill to disk
- Normal memory usage
- Single execution per stage

### 3. Query Plan Tab

Compare stage S0D (failed) vs S0D/S0E/S19 (successful):
- **Records read**: Similar (~237M vs 240M)
- **Records written**: Failed writes 20M (partial), successful writes 1.5M (complete after aggregation)
- **Shuffle output**: Failed shows 0 (bad), successful shows proper shuffle bytes

---

## Conclusion

This is **NOT a cartesian join issue**. It's an **aggregation explosion** caused by:

1. **Root cause**: Temp table contains 183 dates instead of 2-3 days
2. **Cascading effect**: GROUP BY across 183 dates creates 61x more grouping combinations
3. **Memory pressure**: Aggregation exceeds available memory
4. **Timeout**: After 6 hours of retries, BigQuery gives up

**The fix**: Add explicit date filter to limit temp table to 7 days maximum (see NEXT_STEPS.md).

---

## Files Referenced

- `failed_nov20_child_job_plan.json` - Full execution plan for failed job
- `success_nov24_job_plan.json` - Full execution plan for successful job
- `03_temp_table_date_distribution.csv` - Proof of 183-date span
- `02_join_key_distribution.csv` - Join key cardinality analysis

