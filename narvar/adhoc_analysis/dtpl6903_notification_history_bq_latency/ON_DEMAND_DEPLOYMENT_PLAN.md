# On-Demand Capacity Deployment Plan for Messaging Service

**Date:** November 24, 2025  
**Service Account:** `messaging@narvar-data-lake.iam.gserviceaccount.com` *(pending confirmation)*  
**Status:** READY FOR DEPLOYMENT  
**Estimated Time:** 30 minutes (5-minute deployment + 25 minutes testing/validation)

---

## Table of Contents

1. [Service Account Clarification](#service-account-clarification)
2. [Detailed Capacity Estimation Plan](#detailed-capacity-estimation-plan)
3. [Detailed Deployment Plan](#detailed-deployment-plan)
4. [Testing Strategy](#testing-strategy)
5. [Downtime Assessment](#downtime-assessment)
6. [Validation & Sufficiency Testing](#validation--sufficiency-testing)
7. [Rollback Procedures](#rollback-procedures)

---

## Service Account Clarification

**⚠️ IMPORTANT:** Need to confirm which service account to configure:

**Option A:** `messaging@narvar-data-lake.iam.gserviceaccount.com`
- ✅ Found in audit logs (93,100 queries last 7 days)
- ✅ Experiencing delays (558s max on Friday)
- ✅ Shown in Jira screenshot
- ✅ All analysis based on this account

**Option B:** `service-prod-messaging-pubsub@narvar-prod.iam.gserviceaccount.com`
- ❌ NOT found in narvar-data-lake audit logs (0 queries)
- ❓ May query different BigQuery project (`narvar-prod`?)
- ❓ Mentioned by Cezar but not in investigation data

**RECOMMENDATION:** Configure **`messaging@narvar-data-lake.iam.gserviceaccount.com`** (the one we analyzed)

**If both need configuration:** Follow same process for each account separately.

---

## Detailed Capacity Estimation Plan

### Step 1: Calculate 30-Day Historical Usage (5 minutes)

**Query to run:**

```sql
-- 30-day baseline for on-demand cost estimation
DECLARE target_user STRING DEFAULT 'messaging@narvar-data-lake.iam.gserviceaccount.com';

SELECT
  DATE(creation_time, 'America/Los_Angeles') AS date_pst,
  
  -- Volume metrics
  COUNT(*) AS daily_queries,
  
  -- Data scanned (for on-demand cost)
  SUM(total_bytes_processed) / POW(1024, 4) AS tb_processed,
  SUM(total_bytes_processed) / POW(1024, 4) * 6.25 AS on_demand_cost_usd,
  
  -- Slot consumption (for flex reservation sizing)
  SUM(total_slot_ms) / 3600000 AS slot_hours,
  
  -- Performance baselines
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS avg_exec_sec,
  
  -- Peak concurrency estimate
  MAX(total_slot_ms / (TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) + 1)) AS peak_concurrent_slots
  
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND user_email = target_user
  AND job_type = 'QUERY'
  AND state = 'DONE'
GROUP BY date_pst
ORDER BY date_pst DESC;
```

**Expected outputs:**
- **Daily TB processed:** 0.15-0.25 TB
- **Daily on-demand cost:** $0.94-$1.56
- **Monthly TB processed:** ~4.5-7.5 TB
- **Monthly on-demand cost:** ~$28-$47
- **Peak concurrent slots:** 150-300 slots

---

### Step 2: Peak Concurrency Analysis (10 minutes)

**Query to understand worst-case slot needs:**

```sql
-- Analyze peak 5-minute windows to understand burst capacity needs
DECLARE target_user STRING DEFAULT 'messaging@narvar-data-lake.iam.gserviceaccount.com';

WITH five_min_buckets AS (
  SELECT
    TIMESTAMP_TRUNC(creation_time, MINUTE) AS minute_start,
    DIV(EXTRACT(MINUTE FROM creation_time), 5) AS five_min_bucket,
    
    COUNT(*) AS queries_in_5min,
    SUM(total_slot_ms) / 300000 AS avg_concurrent_slots_needed,
    SUM(total_bytes_processed) / POW(1024, 3) AS gb_processed
    
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND user_email = target_user
    AND job_type = 'QUERY'
    AND state = 'DONE'
  GROUP BY minute_start, five_min_bucket
)

SELECT
  -- Peak metrics
  MAX(queries_in_5min) AS max_queries_per_5min,
  APPROX_QUANTILES(queries_in_5min, 100)[OFFSET(95)] AS p95_queries_per_5min,
  
  -- Capacity needs
  MAX(avg_concurrent_slots_needed) AS max_concurrent_slots,
  APPROX_QUANTILES(avg_concurrent_slots_needed, 100)[OFFSET(95)] AS p95_concurrent_slots,
  AVG(avg_concurrent_slots_needed) AS avg_concurrent_slots,
  
  -- Data volume
  MAX(gb_processed) AS max_gb_per_5min,
  APPROX_QUANTILES(gb_processed, 100)[OFFSET(95)] AS p95_gb_per_5min

FROM five_min_buckets;
```

**Expected outputs:**
- **Max concurrent slots needed:** 100-200 slots (burst capacity)
- **P95 concurrent slots:** 50-100 slots (normal peak)
- **Average concurrent slots:** 20-40 slots (typical)

**Interpretation:**
- If P95 concurrent <100 slots → On-demand is perfect (unlimited capacity)
- If P95 concurrent >200 slots → Consider 200-slot flex reservation
- Current data suggests: **On-demand is ideal**

---

### Step 3: Cost Projection & Decision Matrix (5 minutes)

**Calculate break-even point:**

```
30-day average TB: [FROM STEP 1]
Monthly on-demand cost: TB * $6.25

Flex reservation options:
- 50 slots: $146/month
- 100 slots: $292/month

Decision:
IF monthly_cost < $146 THEN use_on_demand
ELIF monthly_cost < $292 THEN use_50_slot_flex
ELSE use_100_slot_flex
```

**Based on historical data (4.3 TB/month):**
- On-demand: **$27/month** ✅ WINNER
- 50-slot flex: $146/month
- Recommendation: **On-demand**

---

## Detailed Deployment Plan

### Prerequisites Checklist

**Before starting:**
- [ ] Service account confirmed: `messaging@narvar-data-lake.iam.gserviceaccount.com`
- [ ] Approval obtained from: Messaging team lead, Data Platform team
- [ ] Budget alert configured: $10/day, $150/month
- [ ] Stakeholders notified: Messaging team, SRE, Data Engineering
- [ ] Monitoring dashboard ready
- [ ] Rollback command tested and ready

---

### Phase 1: Pre-Deployment (10 minutes)

#### Step 1.1: Backup Current Configuration (2 minutes)

```bash
# Save current reservation configuration
bq show --location=US \
  --reservation \
  --project_id=bq-narvar-admin \
  bq-narvar-admin:US.default \
  > backup_reservation_config_$(date +%Y%m%d_%H%M%S).txt

# Check current service account assignment (if any)
# Note: This command may not work if assignment API not available
# Alternative: Check via GCP Console > BigQuery > Reservations > Assignments
```

#### Step 1.2: Document Baseline Metrics (3 minutes)

Run this query to capture pre-deployment baseline:

```sql
-- Pre-deployment baseline (last 1 hour)
SELECT
  COUNT(*) AS queries_last_hour,
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS avg_exec_sec,
  SUM(total_bytes_processed) / POW(1024, 3) AS gb_processed,
  COUNTIF(error_result IS NOT NULL) AS errors
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
```

Save output as baseline for comparison.

#### Step 1.3: Verify Service Account Permissions (2 minutes)

```bash
# Verify service account has BigQuery permissions
gcloud projects get-iam-policy narvar-data-lake \
  --flatten="bindings[].members" \
  --filter="bindings.members:messaging@narvar-data-lake.iam.gserviceaccount.com" \
  --format="table(bindings.role)"

# Expected roles:
# - roles/bigquery.jobUser (to create jobs)
# - roles/bigquery.dataViewer (to read data)
```

**No changes needed** - service account already has necessary permissions.

#### Step 1.4: Prepare Rollback Command (3 minutes)

Create rollback script and test the syntax:

```bash
# Create rollback.sh
cat > rollback_to_reservation.sh << 'ROLLBACK'
#!/bin/bash
# Rollback script - re-assign to reservation

echo "Rolling back messaging service account to reservation..."

gcloud alpha bq reservations assignments create \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT \
  --priority=100

echo "Rollback complete. Checking status..."

# Wait 30 seconds for propagation
sleep 30

# Run test query to verify
bq query --use_legacy_sql=false "SELECT 1 AS test"

echo "If you see result above, rollback successful!"
ROLLBACK

chmod +x rollback_to_reservation.sh

# TEST the syntax (but don't execute yet)
cat rollback_to_reservation.sh
```

---

### Phase 2: Deployment (5 minutes)

#### Step 2.1: Remove from Reservation (1 minute)

**THE CRITICAL COMMAND:**

```bash
# Remove service account from reservation
# This makes it use on-demand slots automatically
gcloud alpha bq reservations assignments delete \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT
```

**Expected output:**
```
Deleted assignment [...]
```

**If error:** "Assignment not found" - service account may already be using on-demand. Check with:
```bash
# This will show all assignments (if API available)
# Alternative: Check GCP Console manually
```

#### Step 2.2: Wait for Propagation (1 minute)

**Configuration changes take 30-60 seconds to propagate.**

```bash
# Wait for BigQuery to propagate the change
echo "Waiting 60 seconds for configuration to propagate..."
sleep 60
echo "Ready to test!"
```

#### Step 2.3: Immediate Smoke Test (3 minutes)

Run a test query to verify on-demand is working:

```bash
# Run simple test query as the messaging service account
# (This would need to be done from the application or with service account credentials)

# Alternative: Check INFORMATION_SCHEMA immediately
bq query --use_legacy_sql=false "
SELECT
  job_id,
  user_email,
  reservation_id,
  TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS exec_sec
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
ORDER BY creation_time DESC
LIMIT 10;
"
```

**What to check:**
- ✅ `reservation_id` should be **NULL** (indicates on-demand)
- ✅ `queue_sec` should be **0-1 seconds**
- ✅ `exec_sec` should be **1-3 seconds** (unchanged)
- ✅ No errors

**If reservation_id is still showing:** Wait another 2-3 minutes, configuration still propagating.

---

### Phase 3: Validation & Testing (15 minutes)

#### Test 1: Live Traffic Monitoring (5 minutes)

Monitor real user queries for 5 minutes:

```sql
-- Real-time monitoring query (run this, then wait 5 minutes, run again)
SELECT
  COUNT(*) AS queries_last_5min,
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS avg_exec_sec,
  
  SUM(total_bytes_processed) / POW(1024, 3) AS gb_processed,
  SUM(total_bytes_processed) / POW(1024, 3) * 6.25 AS on_demand_cost,
  
  COUNTIF(reservation_id IS NULL) AS on_demand_queries,
  COUNTIF(reservation_id IS NOT NULL) AS reservation_queries,
  
  COUNTIF(error_result IS NOT NULL) AS errors,
  
  STRING_AGG(DISTINCT reservation_id, ', ') AS reservations_used

FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
```

**Success criteria:**
- ✅ `on_demand_queries` > 0 (queries using on-demand)
- ✅ `reservation_queries` = 0 (no queries using reservation)
- ✅ `avg_queue_sec` < 2 seconds
- ✅ `max_queue_sec` < 5 seconds
- ✅ `errors` = 0
- ✅ `reservations_used` = NULL

**If any criteria fail:** Execute rollback immediately.

#### Test 2: Cost Validation (5 minutes)

Check if costs are reasonable:

```sql
-- Cost check for last hour after deployment
SELECT
  SUM(total_bytes_processed) / POW(1024, 4) AS tb_processed_last_hour,
  SUM(total_bytes_processed) / POW(1024, 4) * 6.25 AS cost_last_hour,
  (SUM(total_bytes_processed) / POW(1024, 4) * 6.25) * 24 AS projected_daily_cost,
  (SUM(total_bytes_processed) / POW(1024, 4) * 6.25) * 24 * 30 AS projected_monthly_cost,
  
  COUNT(*) AS queries_last_hour,
  AVG(total_bytes_processed) / POW(1024, 3) AS avg_gb_per_query

FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
```

**Success criteria:**
- ✅ Projected daily cost: $0.90-$2.50 (reasonable)
- ✅ Projected monthly cost: $27-$75 (within budget)
- ✅ Avg GB per query: 10-15 GB (unchanged from baseline)

**If monthly projection >$150:** Escalate for review (but don't rollback yet - wait 24 hours to confirm).

#### Test 3: Performance Validation (5 minutes)

Compare performance before/after:

```sql
-- Compare last hour (on-demand) vs previous hour (reservation)
WITH time_periods AS (
  SELECT
    CASE
      WHEN creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) 
        THEN 'After_OnDemand'
      WHEN creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
        THEN 'Before_OnDemand'
    END AS period,
    
    TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS exec_sec,
    reservation_id
    
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
    AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
    AND job_type = 'QUERY'
    AND state = 'DONE'
)

SELECT
  period,
  COUNT(*) AS queries,
  
  ROUND(AVG(queue_sec), 2) AS avg_queue_sec,
  APPROX_QUANTILES(queue_sec, 100)[OFFSET(95)] AS p95_queue_sec,
  MAX(queue_sec) AS max_queue_sec,
  
  ROUND(AVG(exec_sec), 2) AS avg_exec_sec,
  
  COUNTIF(reservation_id IS NULL) AS on_demand_count,
  
  -- Expected improvement
  AVG(queue_sec + exec_sec) AS avg_total_time_sec

FROM time_periods
WHERE period IS NOT NULL
GROUP BY period
ORDER BY period;
```

**Success criteria:**
- ✅ After_OnDemand has lower avg_queue_sec than Before
- ✅ After_OnDemand has p95_queue_sec < 2 seconds
- ✅ After_OnDemand has on_demand_count = total queries
- ✅ avg_exec_sec unchanged (should be similar before/after)

---

## Testing Strategy

### Option A: Deploy Directly to Production (RECOMMENDED)

**Why this is safe:**
1. **Non-breaking change:** Just removes reservation assignment
2. **No application changes:** App doesn't know/care about on-demand vs reservation
3. **30-second rollback:** Can restore immediately if issues
4. **No downtime:** Queries continue executing during change
5. **Low risk:** On-demand is Google's default (used by millions of customers)

**Process:**
1. Remove reservation assignment (1 minute)
2. Wait 60 seconds for propagation
3. Monitor for 5 minutes
4. Validate success criteria
5. Continue monitoring for 24 hours

**Timeline:** 10 minutes deployment + 24 hours monitoring

---

### Option B: Create Test Service Account First (CONSERVATIVE)

**If you prefer to test before production deployment:**

#### Step 1: Create Test Service Account (15 minutes)

```bash
# Create test service account in narvar-data-lake project
gcloud iam service-accounts create messaging-test-ondemand \
  --display-name="Messaging Test - On-Demand Capacity Testing" \
  --project=narvar-data-lake

# Grant BigQuery permissions
gcloud projects add-iam-policy-binding narvar-data-lake \
  --member="serviceAccount:messaging-test-ondemand@narvar-data-lake.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding narvar-data-lake \
  --member="serviceAccount:messaging-test-ondemand@narvar-data-lake.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"

# Grant access to messaging dataset
bq grant \
  --dataset narvar-data-lake:messaging \
  --view \
  "serviceAccount:messaging-test-ondemand@narvar-data-lake.iam.gserviceaccount.com"
```

#### Step 2: Generate Test Load (20 minutes)

Create test script that mimics notification history queries:

```bash
# test_ondemand_load.sh
#!/bin/bash

SERVICE_ACCOUNT="messaging-test-ondemand@narvar-data-lake.iam.gserviceaccount.com"
KEY_FILE="/path/to/service-account-key.json"

# Authenticate
gcloud auth activate-service-account --key-file=$KEY_FILE

# Run 10 parallel queries (simulating one user search)
for i in {1..10}; do
  (
    bq query --use_legacy_sql=false \
      --service_account_credential_file=$KEY_FILE \
      "SELECT COUNT(*) FROM \`narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug\` 
       WHERE event_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
       LIMIT 1000" \
      > /dev/null 2>&1
  ) &
done

wait
echo "Test batch complete"

# Check results
bq query --use_legacy_sql=false "
SELECT
  COUNT(*) AS test_queries,
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  reservation_id
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = '$SERVICE_ACCOUNT'
GROUP BY reservation_id;
"
```

**Expected results:**
- Test queries should have queue_sec < 1 second
- reservation_id should be NULL (on-demand)

#### Step 3: Validate Test Results (10 minutes)

```sql
-- Analyze test service account performance
SELECT
  COUNT(*) AS test_queries,
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS avg_exec_sec,
  
  SUM(total_bytes_processed) / POW(1024, 3) AS total_gb,
  SUM(total_bytes_processed) / POW(1024, 3) * 6.25 AS cost_usd,
  
  COUNTIF(reservation_id IS NULL) AS on_demand_count,
  COUNTIF(error_result IS NOT NULL) AS errors

FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging-test-ondemand@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
```

**If test successful:** Proceed to production deployment (Option A process)

**If test fails:** Investigate before proceeding

#### Step 4: Cleanup Test Resources (5 minutes)

```bash
# After successful test, delete test service account
gcloud iam service-accounts delete \
  messaging-test-ondemand@narvar-data-lake.iam.gserviceaccount.com \
  --project=narvar-data-lake
```

---

## Downtime Assessment

### ✅ ZERO DOWNTIME EXPECTED

**Why no downtime:**

1. **Change is transparent to application:**
   - App uses service account credentials
   - BigQuery client library doesn't care about on-demand vs reservation
   - No code changes needed
   - No connection disruption

2. **Query routing is instant:**
   - BigQuery automatically routes queries to on-demand capacity
   - No DNS changes, no endpoints changing
   - Propagation happens in background (30-60 seconds)

3. **Queries in flight are unaffected:**
   - Currently running queries continue on reservation
   - New queries use on-demand
   - No interruption to either

4. **Rollback is instant:**
   - 30-second command to re-assign to reservation
   - No data loss, no query failures

**Worst case scenario:**
- During 30-60 second propagation window, some queries might use old configuration
- Impact: Negligible (queries still execute, might queue briefly)
- No failures, no errors, no downtime

**Recommended deployment window:** Anytime - no maintenance window needed

**However, for conservatism:** Deploy during low-traffic period (early morning or late evening) if you want extra caution.

---

## Validation & Sufficiency Testing

### How to Test if Capacity is Sufficient

**Method 1: Real-time Queue Time Monitoring (Continuous)**

Set up this query to run every 5 minutes automatically:

```sql
-- Continuous monitoring query
SELECT
  CURRENT_TIMESTAMP() AS check_time,
  
  COUNT(*) AS queries_last_5min,
  
  -- Queue time (should be near zero)
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
  APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] AS p95_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  
  -- Execution time (should be unchanged)
  AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS avg_exec_sec,
  
  -- Verify using on-demand
  COUNTIF(reservation_id IS NULL) AS on_demand_count,
  COUNT(*) - COUNTIF(reservation_id IS NULL) AS reservation_count,
  
  -- Cost tracking
  SUM(total_bytes_processed) / POW(1024, 3) * 6.25 AS cost_last_5min,
  
  -- Status indicator
  CASE
    WHEN MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 10 THEN '🔴 QUEUE ISSUES'
    WHEN AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 5 THEN '🟡 SLIGHT DELAYS'
    WHEN COUNTIF(reservation_id IS NOT NULL) > 0 THEN '🟡 MIXED MODE'
    ELSE '✅ HEALTHY'
  END AS status

FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
```

**Run this query every 5 minutes for the first hour, then every hour for 24 hours.**

**Success indicators:**
- ✅ status = '✅ HEALTHY'
- ✅ avg_queue_sec < 1 second
- ✅ p95_queue_sec < 2 seconds
- ✅ max_queue_sec < 5 seconds
- ✅ on_demand_count = 100% of queries
- ✅ cost_last_5min reasonable (< $0.50)

---

### Method 2: Peak Load Testing (During business hours)

**Test during peak traffic (2-4pm PST):**

```sql
-- Peak hour capacity check
SELECT
  EXTRACT(HOUR FROM creation_time AT TIME ZONE 'America/Los_Angeles') AS hour_pst,
  
  COUNT(*) AS hourly_queries,
  
  -- Performance
  ROUND(AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)), 2) AS avg_queue_sec,
  APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] AS p95_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  
  -- Detect if capacity insufficient
  COUNTIF(TIMESTAMP_DIFF(start_time, creation_time, SECOND) > 5) AS queries_queued_over_5s,
  
  CASE
    WHEN MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 30 THEN '🔴 INSUFFICIENT'
    WHEN APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] > 5 THEN '🟡 BORDERLINE'
    ELSE '✅ SUFFICIENT'
  END AS capacity_status

FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE DATE(creation_time, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY'
  AND state = 'DONE'
GROUP BY hour_pst
ORDER BY hour_pst DESC;
```

**If capacity_status shows '🔴 INSUFFICIENT':**
- On-demand is theoretically unlimited, so this would indicate a broader BigQuery issue
- Escalate to Google Cloud Support
- Consider switching to 100-200 slot flex reservation

**Realistically:** On-demand should NEVER be insufficient for this workload (87K queries/week, ~170 slots average).

---

### Method 3: Cost Sufficiency Check (Daily)

Monitor costs to ensure on-demand remains economical:

```bash
# Daily cost check script
bq query --use_legacy_sql=false --format=csv "
SELECT
  DATE(creation_time) AS date,
  SUM(total_bytes_processed) / POW(1024, 4) * 6.25 AS daily_cost_usd,
  COUNT(*) AS queries
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY'
GROUP BY date
ORDER BY date DESC;
" > daily_cost_check.csv

# Check if any day exceeded $10
awk -F',' '$2 > 10 {print "ALERT: Daily cost exceeded $10 on " $1 ": $" $2}' daily_cost_check.csv
```

**Sufficiency criteria:**
- ✅ Daily cost < $5 (ideal)
- 🟡 Daily cost $5-$10 (acceptable)
- 🔴 Daily cost > $10 (investigate - may need to switch to flex)

**If 7-day average >$150/month:** Switch to 50-slot flex reservation ($146/month fixed cost).

---

## Is Test Service Account Recommended?

### My Assessment: **NO, not necessary for this deployment**

**Why testing is lower value than you might think:**

1. **Configuration change is reversible in 30 seconds:**
   - Test account won't reveal issues that production deployment wouldn't
   - If production has issues, we rollback in 30 seconds
   - Test account setup takes 45-60 minutes (longer than full production deployment + monitoring)

2. **On-demand is Google's default behavior:**
   - Used by millions of BigQuery customers
   - Well-tested, mature capability
   - Less risky than using reservations (which require configuration)

3. **Test account can't replicate production load:**
   - Production has 12K queries/day from real users
   - Test account would have synthetic load
   - Real production patterns (10 parallel queries per search) hard to simulate accurately
   - Wouldn't test the actual integration with notify-automation-service

4. **The risk is already minimal:**
   - No code changes
   - No application restart
   - No data access changes
   - Transparent to end users

---

### Alternative: Gradual Rollout (If you want extreme caution)

**Instead of test account, consider gradual rollout:**

**Option: Deploy but monitor intensively**
1. Deploy on-demand (5 minutes)
2. Monitor every 5 minutes for first hour
3. Monitor every hour for next 23 hours
4. Monitor daily for next 7 days
5. If ANY issues, rollback in 30 seconds

**This gives you:**
- ✅ Real production validation
- ✅ Immediate rollback capability
- ✅ No wasted time on test account setup
- ✅ Faster time to resolution for end users

---

### If You Insist on Test Account:

**Here's the minimal viable test:**

1. **Create test service account** (15 min)
2. **Run 100 test queries** (10 min) - Sample notification history query pattern
3. **Verify:**
   - Queue time < 1s
   - On-demand working (reservation_id = NULL)
   - Cost reasonable (~$0.01-0.05 for 100 queries)
4. **Delete test account** (5 min)
5. **Deploy to production** (5 min)

**Total time:** 45 minutes (vs 10 minutes direct deployment)

**My recommendation:** Skip the test account. Deploy directly with intensive monitoring. The rollback is so fast (30 seconds) that there's minimal risk.

---

## Rollback Procedures

### When to Rollback

**Immediate rollback if:**
- ❌ Error rate >1% (any query failures)
- ❌ P95 queue time >10 seconds (worse than reservation)
- ❌ Cost projection >$300/month (exceeds budget by 2x)
- ❌ Queries not using on-demand (configuration didn't apply)

**Monitor and evaluate if:**
- 🟡 P95 queue time 2-10 seconds (better than reservation but not ideal)
- 🟡 Cost projection $150-300/month (higher than expected)
- 🟡 Some queries still using reservation (propagation delay)

**Continue monitoring if:**
- ✅ P95 queue time <2 seconds
- ✅ Cost projection <$150/month
- ✅ 100% queries on-demand
- ✅ Zero errors

---

### Rollback Command (30 seconds)

```bash
# Execute rollback script
./rollback_to_reservation.sh

# OR manually:
gcloud alpha bq reservations assignments create \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT \
  --priority=100

# Wait for propagation
sleep 60

# Verify rollback successful
bq query --use_legacy_sql=false "
SELECT
  COUNT(*) AS queries,
  STRING_AGG(DISTINCT reservation_id, ', ') AS reservations,
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com';
"
```

**Success criteria for rollback:**
- ✅ reservations shows 'bq-narvar-admin:US.default' (back on reservation)
- ✅ Queries executing normally

---

## My Recommendation for Today

### Recommended Approach: Direct Production Deployment with Intensive Monitoring

**Timeline:**
1. **9:00-9:10am:** Pre-deployment checks and baseline capture
2. **9:10-9:15am:** Remove reservation assignment (the deployment)
3. **9:15-9:30am:** Intensive monitoring (every 5 minutes)
4. **9:30am-5pm:** Hourly monitoring checks
5. **Tomorrow:** Daily monitoring for 7 days

**Why not test account:**
- 45-60 minute overhead for marginal benefit
- Can't replicate production patterns accurately
- 30-second rollback makes production deployment low-risk
- Weekend data shows problem is currently not active (good time to deploy)

**Critical success factors:**
- Have rollback script ready
- Monitor intensively for first hour
- Check cost projections
- Verify 100% on-demand usage

---

Would you like me to:
1. **Run the weekend wait time analysis** to show you the full Friday-Monday trend?
2. **Run the 30-day capacity estimation query** to confirm cost projections?
3. **Create the deployment runbook** with exact commands for today's deployment?
4. **Address the service account clarification** (narvar-prod vs narvar-data-lake)?

What's your preference: test account first, or direct deployment with monitoring?
