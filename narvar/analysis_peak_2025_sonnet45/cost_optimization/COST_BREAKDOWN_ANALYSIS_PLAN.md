# Cost Breakdown Analysis Plan

**Date:** November 19, 2025  
**Goal:** Understand the $176,556 shipments cost to evaluate latency optimization potential  
**Status:** Ready to Execute

---

## What We Know

From `SHIPMENTS_PRODUCTION_COST.md`:

**$176,556/year shipments cost breakdown:**
- **BigQuery Compute:** $149,832 (84.8%) - MERGE operations
- **Storage:** $4,396 (2.5%) - 19.1 TB, 18% of monitor-base storage
- **Pub/Sub:** $22,328 (12.7%) - Message delivery

**The $149,832 compute cost is:**
- 505,505 slot-hours over 2 months (Sep-Oct 2024)
- Represents 24.18% of total BQ Reservation ($619,598)
- Service account: `monitor-base-us-prod@appspot.gserviceaccount.com`
- Operation: MERGE operations containing "shipments"

---

## Critical Questions to Answer

### 1. **What is the nature of these MERGE operations?**

**We need to understand:**
- How frequently do MERGEs run? (Expected: every 5 minutes = 288/day)
- How many bytes scanned per MERGE?
- Is partition pruning working? (Table partitioned on `retailer_moniker`)
- What's the job pattern? (continuous micro-batch vs scheduled)

**Why this matters:**
- If partition pruning works: Each MERGE scans only affected retailer partitions (~1-5 GB), not full 19.1 TB
- If scanning full table: Each MERGE scans 19.1 TB → huge optimization potential
- If partition-pruned: Optimization potential is limited to reducing operation overhead

**Query to run:** `SHIPMENTS_COST_DECOMPOSITION.sql`

Expected output:
```
service_type | operation_category | job_count | jobs_per_day | slot_hours | annual_cost | bytes_scanned
------------ | ------------------ | --------- | ------------ | ---------- | ----------- | -------------
Dataflow     | MERGE_SHIPMENTS    | ~17,280   | 288          | 505,505    | $149,832    | ???
```

---

### 2. **What drives the slot-hour consumption?**

**Possible scenarios:**

**Scenario A: Full table scans (BAD)**
- Each MERGE scans 19.1 TB
- 288 MERGEs/day × 19.1 TB = 5.5 PB/day scanned
- Cost is proportional to scan volume
- **Latency optimization HIGH impact:** Going to daily batch saves 287/288 scans

**Scenario B: Partition-pruned scans (LIKELY)**
- Each MERGE scans only affected partitions (~50 retailers × 67 GB/retailer = 3.4 GB)
- 288 MERGEs/day × 3.4 GB = 980 GB/day scanned
- Cost is mostly operation overhead + small scans
- **Latency optimization LOW impact:** Batching saves overhead but not scan volume

**Scenario C: Mixed (UNCERTAIN)**
- Some MERGEs scan full table (misconfigured queries)
- Most MERGEs partition-pruned
- Need to analyze distribution

---

### 3. **How much is operation overhead vs scan cost?**

**BigQuery MERGE cost components:**
1. **Scan cost:** Reading source and target tables
2. **Shuffle cost:** Moving data between workers
3. **Write cost:** Writing updated/new rows
4. **Operation overhead:** Job initialization, metadata updates

If partition pruning works, most cost is likely #4 (operation overhead).

**Impact on latency optimization:**
- **High scan cost:** Batching saves a lot (fewer scans)
- **High overhead cost:** Batching saves some (fewer operations)
- **Mostly overhead:** Limited savings potential (5-15% max)

---

## Queries to Run

### Query 1: MERGE Operation Analysis
**File:** `SHIPMENTS_COST_DECOMPOSITION.sql`

**Purpose:** Break down the 505,505 slot-hours by:
- Service type (Dataflow, Airflow, etc.)
- Operation category (MERGE vs INSERT vs SELECT)
- Frequency (jobs per day)
- Bytes processed per operation

**Expected runtime:** 1-2 minutes  
**Cost:** < $0.10

---

### Query 2: Partition Pruning Validation
**File:** `PARTITION_PRUNING_VALIDATION.sql` (to be created)

**Purpose:** Analyze sample MERGE operations to see:
- Bytes scanned vs table size
- Whether WHERE clauses include partition filters
- Distribution of scan sizes

**SQL approach:**
```sql
-- Sample MERGE operations
SELECT
  job_id,
  query_text_sample,
  total_bytes_processed,
  total_bytes_billed,
  -- Detect partition filter in query
  CASE 
    WHEN query_text_sample LIKE '%retailer_moniker%' THEN 'Has partition filter'
    ELSE 'No partition filter'
  END as partition_filter_present,
  -- Calculate scan efficiency
  total_bytes_processed / (19.1 * POW(1024, 4)) * 100 as pct_of_table_scanned
FROM traffic_classification
WHERE operation matches MERGE on shipments
LIMIT 100
```

---

### Query 3: DoIT Billing Service Breakdown
**File:** `DOIT_BILLING_MONITOR_BREAKDOWN.sql`

**Purpose:** Identify if there are hidden Dataflow infrastructure costs

**Questions:**
- Is there a separate Dataflow line item for shipments pipeline?
- Or is all cost captured in BigQuery slot reservation?
- Are there Cloud Run or Compute Engine costs?

**Note:** Need location of DoIT billing data table/CSV

---

## Execution Plan

**Step 1: Run Decomposition Query (30 mins)**
1. Execute `SHIPMENTS_COST_DECOMPOSITION.sql`
2. Validate total slot-hours ≈ 505,505
3. Identify job frequency pattern
4. Calculate bytes processed per operation

**Step 2: Analyze Partition Pruning (30 mins)**
1. Create and run partition pruning validation query
2. Sample 100 MERGE operations
3. Check if queries include `retailer_moniker` filters
4. Measure average bytes scanned

**Step 3: DoIT Billing Analysis (30 mins)**
1. Locate DoIT billing data
2. Query for monitor-base-us-prod services
3. Identify all cost components
4. Cross-reference with BigQuery compute costs

**Step 4: Document Findings (30 mins)**
1. Create `SHIPMENTS_COST_BREAKDOWN_FINDINGS.md`
2. Quantify optimization potential
3. Update latency scenario estimates
4. Recommend next actions

**Total estimated time:** 2 hours

---

## Success Criteria

At the end of this analysis, we should be able to answer:

1. ✅ **Is the $149,832 pure BigQuery compute or mixed with infrastructure?**
2. ✅ **Does partition pruning work? What % of table is scanned per MERGE?**
3. ✅ **What's the job frequency? (Verify 288/day micro-batch assumption)**
4. ✅ **What's the realistic cost savings from larger batch windows?**
   - Scenario A (full scans): 20-40% savings
   - Scenario B (partition-pruned): 5-15% savings
5. ✅ **Should we prioritize latency or retention optimization?**

---

## Next Steps After Analysis

**If partition pruning works (Scenario B - LIKELY):**
- Latency optimization potential: $10K-$29K/year (5-15%)
- **Recommendation:** Pivot to retention optimization as primary lever
- **Reason:** 88.7 TB orders table offers more concrete savings

**If full table scans (Scenario A - UNLIKELY):**
- Latency optimization potential: $40K-$78K/year (20-40%)
- **Recommendation:** Fix partition pruning first (immediate 70-80% savings)
- Then consider latency optimization

**If mixed/uncertain (Scenario C):**
- Need deeper code analysis
- Review Dataflow MERGE implementation
- Optimize inefficient queries first
- Then reassess latency optimization

---

**Ready to proceed?** 

Please confirm:
1. Should I run `SHIPMENTS_COST_DECOMPOSITION.sql`?
2. Do you have access to DoIT billing data? Where is it located?
3. Any other data sources I should check?

