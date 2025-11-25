# Job IDs for Execution Plan Comparison

## Failed Jobs (Problematic - 6 hour timeouts)

### Nov 19, 2025 - Failed Attempts (update_product_insights task)

1. **First Attempt** (00:17:57 - 06:18:17)
   - Job ID: `job_Wi2G9fWfLVPbs-EpgkjU7AfugSoG`
   - Script Job: `script_job_53e88c3726bd7bc2c171d2bdecfa2be9_0`
   - Duration: 6 hours (timeout)
   - Slot-hours: 80.55
   - Status: DONE (timeout)

2. **Second Attempt** (06:23:57 - 12:23:58)
   - Job ID: `job_uGCk9mLHF5NP2TNo2GtVxlBZluXj`
   - Script Job: `script_job_9c599ce1b62c4987f8abd6d264f43d3b_0`
   - Duration: 6 hours (timeout)
   - Slot-hours: 80.34
   - Status: DONE (timeout)

3. **Third Attempt** (12:34:48 - 18:34:49)
   - Job ID: `job_KaXz5GqUT4AoJhwDFg8RMm1XUQPY`
   - Script Job: `script_job_f497b114b28bd34fd8f808e424d13900_0`
   - Duration: 6 hours (timeout)
   - Slot-hours: 79.77
   - Status: DONE (timeout)

4. **Fourth Attempt** (18:40:14 - 00:40:16)
   - Job ID: `job_s6sJ9_blGH6ZgNFFS2zMO6j4mATV`
   - Script Job: `script_job_1fff0eae5eb7517c16e88621344b0866_0`
   - Duration: 6 hours (timeout)
   - Slot-hours: 89.98
   - Status: DONE (timeout)

### Nov 20, 2025 - Failed Attempts (update_product_insights task)

5. **First Attempt** (00:32:43 - 06:32:46)
   - Job ID: `job_RJqlqB05dKtu4tpLG6e5Xae1ykJ0`
   - Script Job: `script_job_6daf76d91047484b19e5e1311911240e_0`
   - Duration: 6 hours (timeout)
   - Slot-hours: 64.98
   - Status: DONE (timeout)

6. **Second Attempt** (06:38:30 - 12:38:30)
   - Job ID: `job_GfBO-8zBmqLqbOcAErnuRkaa0LQO`
   - Script Job: `script_job_39dbaa9ec3c4e9362f13d9774bb0151e_0`
   - Duration: 6 hours (timeout)
   - Slot-hours: 85.86
   - Status: DONE (timeout)
   - **This is the job ID from the VictorOps alert!**

---

## Successful Jobs (Normal Behavior)

### Nov 18, 2025 - Slow but Successful (update_product_insights task)

7. **Successful but Slow** (00:20:57 - 02:14:30)
   - Job ID: `job_cgyA-u-wp9uqeDCYv5UcTgTwTHJZ`
   - Script Job: `script_job_8285f5268083a9d46c1194b0ee7a84b2_0`
   - Duration: 113 minutes (slow!)
   - Slot-hours: 29.29
   - Status: DONE (success)
   - Bytes processed: 47.15 GB

### Nov 24, 2025 - Normal Performance (update_product_insights task)

8. **Normal Performance** (17:12:47 - 17:18:10)
   - Job ID: `job_b2654d592228ccb1e1d6ebe7619a1c74_0` (child job)
   - Parent Script: `job_1zkKHJkoV9X2I-EreeiClsHpn2ix`
   - Script Job: `script_job_b2654d592228ccb1e1d6ebe7619a1c74_0`
   - Duration: 5.4 minutes (normal!)
   - Slot-hours: 11.34
   - Status: DONE (success)
   - Bytes processed: 69.53 GB

---

## CREATE temp_order_item_details Jobs (for context)

### Nov 19, 2025 - CREATE tmp_order_item_details (preceding task)
- Job ID: `job_kLfJHPL6z_hehdspnRVbz6asIuqk`
- Script Job: `script_job_2eb9ba54166dbb786418eff15be0b353_0`
- Duration: 5 minutes
- Slot-hours: 40.23
- Bytes processed: 3,840 GB
- Status: SUCCESS
- **This task succeeded - creates the 4.2M row temp table with 183 dates**

### Nov 20, 2025 - CREATE tmp_order_item_details (preceding task)
- Job ID: `job_D_maavURf4eg45E8qQmLaloB6eei`
- Script Job: `script_job_391410bb1ddee48f15268bef20533423_0`
- Duration: 14 minutes
- Slot-hours: 37.34
- Bytes processed: 3,847 GB
- Status: SUCCESS
- **This task also succeeded - creates the problematic temp table**

### Nov 24, 2025 - CREATE tmp_order_item_details (preceding task)
- Duration: Normal (data not captured in our query)
- Status: SUCCESS
- **Normal execution with properly filtered data**

---

## How to Compare in BigQuery Console

### Option 1: BigQuery Console Job History

1. Go to: https://console.cloud.google.com/bigquery?project=narvar-data-lake
2. Click "Job history" in left sidebar
3. Search for job IDs (remove the `job_` prefix in the search box)
4. Click on job to see execution details and plan

### Option 2: Direct Links (if you have access)

**Failed Nov 20 (VictorOps alert):**
```
https://console.cloud.google.com/bigquery?project=narvar-data-lake&j=bq:US:job_GfBO-8zBmqLqbOcAErnuRkaa0LQO&page=queryresults
```

**Successful Nov 24:**
```
https://console.cloud.google.com/bigquery?project=narvar-data-lake&j=bq:US:script_job_b2654d592228ccb1e1d6ebe7619a1c74_0&page=queryresults
```

### Option 3: Using bq CLI

```bash
# Get detailed execution stats for failed job
bq show -j --format=prettyjson job_GfBO-8zBmqLqbOcAErnuRkaa0LQO > failed_job_plan.json

# Get detailed execution stats for successful job
bq show -j --format=prettyjson script_job_b2654d592228ccb1e1d6ebe7619a1c74_0 > success_job_plan.json

# Compare the two files
diff failed_job_plan.json success_job_plan.json
```

---

## Key Metrics to Compare

When looking at execution plans in BigQuery Console, focus on:

1. **Timeline tab**:
   - Wait time vs execution time ratio
   - Number of stages
   - Time spent in each stage

2. **Execution Details tab**:
   - Bytes shuffled (indicator of large joins)
   - Bytes spilled to disk (indicator of memory pressure)
   - Number of rows processed per stage

3. **Query Plan tab** (if available):
   - Look for stages with high input/output ratios
   - Identify JOIN operations
   - Check for AGGREGATE operations with large input

4. **Expected Differences**:
   - **Failed jobs**: Large shuffle bytes, many GB spilled to disk, long-running aggregate stages
   - **Successful jobs**: Minimal shuffle, no spill, fast aggregates

---

## What to Look For

### In Failed Jobs (Nov 19-20):
- ❌ Stage with 4.2M rows from temp table joining 236M rows from order_item_details
- ❌ Aggregation across 183 distinct dates
- ❌ Large shuffle output (>100GB)
- ❌ Bytes spilled to disk
- ❌ Long-running aggregate stage (hours)

### In Successful Jobs (Nov 24):
- ✅ Small input from temp table (~500K rows)
- ✅ Filtered join on 2-3 dates only
- ✅ Small shuffle output (<10GB)
- ✅ No spill to disk
- ✅ Fast aggregate stage (minutes)

---

## Next Step: Detailed Execution Plan Analysis

Run the query `07_get_execution_plans.sql` to extract detailed stage-level execution statistics.

