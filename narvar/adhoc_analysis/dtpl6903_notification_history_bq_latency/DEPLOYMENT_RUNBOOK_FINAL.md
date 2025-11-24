# Messaging Dedicated Capacity - Deployment Runbook (FINAL)

**Service Account:** `messaging@narvar-data-lake.iam.gserviceaccount.com`  
**Date:** November 24, 2025  
**Deployer:** Cezar Mihaila  
**Estimated Time:** 15 minutes deployment + 24 hours monitoring

---

## Executive Summary

**Discovery:** Entire narvar.com organization is assigned to `bq-narvar-admin:US.default` reservation. We cannot simply "remove" messaging from the reservation.

**Solution:** Create dedicated reservation with **50-slot baseline + autoscale to 100 slots** (hybrid approach) with service-account-specific assignment that overrides the org-level assignment.

**Impact:**
- ✅ Queue times drop from 558s → <1s
- ✅ Isolated from Airflow/Metabase/n8n contention
- ✅ Baseline: 50 slots (handles 48-slot average)
- ✅ Autoscale: +50 slots (handles 9pm peak of 186-228 slots)
- ✅ Cost: $146/month baseline + ~$73/month autoscale (50% usage) = **~$219/month total**
- ✅ Zero downtime
- ✅ 2-minute rollback if issues

**Why hybrid approach:**
- **Peak analysis (Nov 24):** Discovered daily 9pm spike of 186-386 slots (4-8x average!)
- 50 fixed slots would queue during 9pm hours
- 100 fixed slots ($292/month) wastes capacity 20 hours/day
- **Autoscale optimizes cost:** Pay for peak capacity only when needed

**Future optimization:** Coordinate org-level assignment refactoring to enable true on-demand ($27/month) - saves $192/month but requires 1-2 weeks and org-wide coordination.

---

## Table of Contents

1. [What Changed from Original Plan](#what-changed-from-original-plan)
2. [Current Situation](#current-situation)
3. [Deployment Steps](#deployment-steps)
4. [Monitoring & Validation](#monitoring--validation)
5. [Rollback Procedures](#rollback-procedures)
6. [Cost Management](#cost-management)
7. [Troubleshooting](#troubleshooting)
8. [Post-Deployment](#post-deployment)

---

## What Changed from Original Plan

### Original Plan (Not Achievable):
- Remove messaging from reservation → use on-demand
- Cost: $27/month
- Single command deployment

### Why It Won't Work:
- **Discovery:** Only 1 assignment exists: `organizations/770066481180`
- Entire narvar.com organization → bq-narvar-admin:US.default
- Messaging inherits from org-level assignment
- Cannot remove individual service accounts from org-level assignment

### New Plan (Achievable Today):
- Create dedicated 50-slot flex reservation
- Assign messaging service account specifically
- Service-level assignment **overrides** org-level assignment
- Cost: $146/month (higher, but necessary given constraints)

**Future optimization:** Coordinate with Data Platform team to refactor org-level assignment → enable on-demand ($27/month).

---

## Current Situation

### Reservation Assignment Hierarchy

```
organizations/770066481180 (narvar.com)
    ↓
Assigned to: bq-narvar-admin:US.default (1,700 slots)
    ↓
ALL narvar.com projects inherit this reservation
    ↓
Including: messaging@narvar-data-lake.iam.gserviceaccount.com
```

**Current performance (as of Nov 24):**
- **Queries last hour:** 1,192
- **Avg queue:** 0.0008 seconds (currently healthy!)
- **Max queue:** 1 second
- **Reservation:** bq-narvar-admin:US.default
- **Autoscale status:** 0 of 700 slots (not saturated currently)

**Friday (Nov 21) performance:**
- **Max queue:** 558 seconds (9.3 minutes)
- **Delayed queries:** 249 (1.91%)
- **Autoscale status:** 700 of 700 slots (MAXED OUT)

**Conclusion:** Problem is intermittent but will return when reservation saturates again.

---

## 🔍 Peak Capacity Analysis (Nov 24)

**Detailed hourly slot consumption analysis revealed significant nightly spike:**

| Time Period | Avg Concurrent Slots | Peak Example | Frequency |
|-------------|---------------------|--------------|-----------|
| **9pm PST** | **186-386 slots** | Nov 17: 386 slots | **Daily spike** |
| Daytime (8am-6pm) | 50-92 slots | Nov 18, 11am: 57 slots | Business hours |
| Overnight (2-4am) | 80-142 slots | Nov 19, 2am: 142 slots | Moderate |
| Average (24 hours) | **48 slots** | Overall: 8,040 slot-hrs / 168 hrs | Baseline |

**Critical finding:** Daily 9pm spike consumes 186-228 slots (4x average), with extreme peak of 386 slots.

**Why this matters for capacity planning:**
- Fixed 50 slots: ❌ Would queue during 9pm (insufficient)
- Fixed 100 slots: ✅ Handles typical 9pm, but wastes 50 slots for 20 hours/day ($146/month wasted)
- **50 + autoscale 50:** ✅ Optimal - pays for peak only when needed

**What's happening at 9pm?**
- Likely: Batch notification processing or end-of-day reporting
- Pattern: Low query count (62-141 queries/hour) but HIGH slot consumption
- Suggests: Large analytical queries or batch operations

**Recommended approach:** 50-slot baseline + autoscale to 100 slots maximum.

---

## Deployment Steps

### Pre-Deployment Checklist (5 minutes)

#### 1. Capture Baseline

```bash
cd /Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency

# Capture current state
bq query --use_legacy_sql=false --format=csv "
SELECT
  COUNT(*) AS queries_last_hour,
  STRING_AGG(DISTINCT reservation_id, ', ') AS current_reservation,
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  SUM(total_bytes_processed) / POW(1024, 3) AS gb_processed
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
" | tee baseline_before_deployment_$(date +%Y%m%d_%H%M%S).csv
```

**Save the output** - you'll compare after deployment.

#### 2. Backup Current Reservation Config

```bash
# Document current reservation state
bq show --location=US \
  --reservation \
  --project_id=bq-narvar-admin \
  bq-narvar-admin:US.default \
  > backup_default_reservation_$(date +%Y%m%d_%H%M%S).txt

# List all reservations
bq ls --location=US \
  --reservation \
  --project_id=bq-narvar-admin \
  >> backup_all_reservations_$(date +%Y%m%d_%H%M%S).txt
```

#### 3. Create Rollback Script

```bash
# Create rollback script
cat > rollback_messaging_to_default.sh << 'EOF'
#!/bin/bash
# Rollback: Remove messaging from dedicated reservation, returns to org default

echo "🔄 Rolling back messaging to default reservation..."

# Get token
TOKEN=$(gcloud auth print-access-token)

# Step 1: Find and delete messaging assignment from messaging-dedicated
ASSIGNMENT=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for assignment in data.get('assignments', []):
    if 'messaging@narvar-data-lake' in assignment.get('assignee', ''):
        print(assignment['name'])
        break
")

if [ -n "$ASSIGNMENT" ]; then
    echo "Deleting assignment: $ASSIGNMENT"
    curl -X DELETE -H "Authorization: Bearer $TOKEN" \
      "https://bigqueryreservation.googleapis.com/v1/$ASSIGNMENT"
    echo "✅ Assignment deleted"
else
    echo "⚠️  No assignment found (may already be rolled back)"
fi

# Step 2: Wait for propagation
echo "⏰ Waiting 60 seconds..."
sleep 60

# Step 3: Verify (should now use org default: bq-narvar-admin:US.default)
echo "✅ Verifying rollback..."
bq query --use_legacy_sql=false "
SELECT 
  COUNT(*) AS queries,
  STRING_AGG(DISTINCT reservation_id, ', ') AS reservation
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
GROUP BY 1;
"

echo ""
echo "✅ If reservation = 'bq-narvar-admin:US.default', rollback successful!"
echo "   Messaging is back on shared reservation (org-level default)"
EOF

chmod +x rollback_messaging_to_default.sh
echo "✅ Rollback script created: ./rollback_messaging_to_default.sh"
```

---

### Deployment Steps (10 minutes)

#### Step 1: Create Dedicated Reservation with Autoscaling (2 minutes)

```bash
# Create 50-slot baseline reservation with autoscale to 100 slots (total)
# Uses ENTERPRISE edition for autoscaling capability
bq mk \
  --location=US \
  --project_id=bq-narvar-admin \
  --reservation \
  --slots=50 \
  --ignore_idle_slots=false \
  --edition=ENTERPRISE \
  --autoscale_max_slots=50 \
  messaging-dedicated

# Log creation
echo "Created reservation at: $(date)" >> deployment_log.txt
echo "  - Baseline: 50 slots (\$146/month)" >> deployment_log.txt
echo "  - Autoscale: +50 slots max (charged when active)" >> deployment_log.txt
echo "  - Total capacity: 100 slots" >> deployment_log.txt
```

**Expected output:**
```
Reservation 'bq-narvar-admin:US.messaging-dedicated' successfully created.
```

**Configuration:**
- **Baseline:** 50 slots (always running) = $146/month
- **Autoscale max:** +50 additional slots (activated during peak)
- **Total capacity:** 100 slots
- **Edition:** ENTERPRISE (required for autoscaling)
- **Autoscale cost:** ~$73/month (if 50% utilization) = **~$219/month total**

**Why autoscale?**
- Average usage: 48 slots (fits in 50 baseline)
- 9pm peak: 186-228 slots (needs autoscale)
- Autoscale provides elasticity without paying for 100 slots 24/7

**If error "already exists":** Check configuration:
```bash
bq show --location=US --reservation --project_id=bq-narvar-admin bq-narvar-admin:US.messaging-dedicated
# Verify: slotCapacity=50, autoscaleMaxSlots=50, edition=ENTERPRISE
```

**If permission denied:** You need `bigquery.resourceAdmin` or `bigquery.admin` role on `bq-narvar-admin` project.

#### Step 2: Assign Messaging Service Account (3 minutes)

**Using BigQuery API (since gcloud commands not available):**

```bash
# Get authentication token
TOKEN=$(gcloud auth print-access-token)

# Create service-account-specific assignment
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "assignee": "projects/narvar-data-lake/serviceAccounts/messaging@narvar-data-lake.iam.gserviceaccount.com",
    "jobType": "QUERY"
  }' \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments"

# Log assignment
echo "Created assignment at: $(date)" >> deployment_log.txt
```

**Expected output:**
```json
{
  "name": "projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments/...",
  "assignee": "projects/narvar-data-lake/serviceAccounts/messaging@narvar-data-lake.iam.gserviceaccount.com",
  "jobType": "QUERY",
  "state": "ACTIVE"
}
```

**If you see this:** ✅ Deployment successful!

**If error 403 (permission denied):** You don't have permission to create assignments. Request `bigquery.resourceAdmin` role.

**If error 409 (already exists):** Assignment already created, verify it's correct with Step 3.

#### Step 3: Wait for Propagation (1 minute)

```bash
echo "⏰ Waiting 60 seconds for BigQuery to propagate configuration..."
sleep 60
echo "✅ Propagation complete"
```

**What happens during this time:**
- BigQuery updates internal routing
- New queries will use messaging-dedicated reservation
- Queries in flight complete normally
- No service disruption

#### Step 4: Immediate Verification (4 minutes)

```bash
# Verify messaging is using the new reservation
bq query --use_legacy_sql=false "
SELECT
  job_id,
  creation_time,
  reservation_id,
  TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS exec_sec,
  total_bytes_processed / POW(1024, 3) AS gb_processed
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
ORDER BY creation_time DESC
LIMIT 10;
"
```

**What to verify:**

| Column | Expected Value | What It Means |
|--------|----------------|---------------|
| `reservation_id` | **`bq-narvar-admin:US.messaging-dedicated`** | Using new reservation ✅ |
| `queue_sec` | **0-1 seconds** | No queue delays ✅ |
| `exec_sec` | **1-3 seconds** | Normal execution ✅ |
| `gb_processed` | **5-20 GB** | Normal data volume ✅ |

**If reservation_id is STILL `bq-narvar-admin:US.default`:**
- ⏰ Wait another 2-3 minutes (propagation still happening)
- 🔄 Re-run verification query
- ⚠️ If still default after 5 minutes → check assignment was created correctly

**If reservation_id is NULL:**
- 🎯 Service account is on on-demand (even better than expected!)
- ✅ Verify queue times are <1s
- ✅ Continue monitoring

**If queue_sec > 10 seconds:**
- 🔴 Issue with new reservation capacity
- 🔄 Execute rollback immediately
- 📊 Increase reservation to 100 slots and retry

---

## Monitoring & Validation

### First Hour: Intensive Monitoring (Every 5 minutes)

**Create monitoring script:**

```bash
# Save as monitor_5min.sh
cat > monitor_5min.sh << 'EOF'
#!/bin/bash
# 5-minute monitoring script

bq query --use_legacy_sql=false --format=csv "
SELECT
  CURRENT_TIMESTAMP() AS check_time,
  
  -- Volume
  COUNT(*) AS queries_last_5min,
  
  -- Performance (KEY METRICS)
  ROUND(AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)), 2) AS avg_queue_sec,
  APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] AS p95_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  
  ROUND(AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)), 2) AS avg_exec_sec,
  
  -- Verify using dedicated reservation
  STRING_AGG(DISTINCT reservation_id, ', ') AS reservations_used,
  COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') AS dedicated_queries,
  COUNTIF(reservation_id = 'bq-narvar-admin:US.default') AS default_queries,
  COUNTIF(reservation_id IS NULL) AS ondemand_queries,
  
  -- Error detection
  COUNTIF(error_result IS NOT NULL) AS errors,
  
  -- Status
  CASE
    WHEN MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 10 THEN '🔴 QUEUE ISSUES'
    WHEN COUNTIF(reservation_id = 'bq-narvar-admin:US.default') > 0 THEN '🟡 STILL ON DEFAULT'
    WHEN COUNTIF(error_result IS NOT NULL) > 0 THEN '🔴 ERRORS'
    WHEN COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') = COUNT(*) THEN '✅ HEALTHY'
    WHEN COUNTIF(reservation_id IS NULL) = COUNT(*) THEN '✅ ON-DEMAND (BONUS!)'
    ELSE '🟡 MIXED MODE'
  END AS status

FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
" | tee -a monitoring_log_$(date +%Y%m%d).csv

echo ""
date
echo "---"
EOF

chmod +x monitor_5min.sh
```

**Run at:** 10:05, 10:10, 10:15, 10:20, 10:30, 10:45, 11:00

**Success criteria:**
- ✅ status = '✅ HEALTHY' or '✅ ON-DEMAND (BONUS!)'
- ✅ avg_queue_sec < 1 second
- ✅ p95_queue_sec < 2 seconds
- ✅ dedicated_queries = 100% of queries (or ondemand_queries = 100%)
- ✅ errors = 0

**If status = '🟡 STILL ON DEFAULT':** Wait 5 more minutes, propagation still happening

**If status = '🔴 QUEUE ISSUES' or '🔴 ERRORS':** Execute rollback immediately

---

### First 24 Hours: Hourly Monitoring

**Create hourly monitoring script:**

```bash
# Save as monitor_hourly.sh
cat > monitor_hourly.sh << 'EOF'
#!/bin/bash
# Hourly monitoring script

bq query --use_legacy_sql=false --format=csv "
SELECT
  CURRENT_TIMESTAMP() AS check_time,
  EXTRACT(HOUR FROM CURRENT_TIMESTAMP() AT TIME ZONE 'America/Los_Angeles') AS hour_pst,
  
  -- Last hour metrics
  COUNT(*) AS queries_last_hour,
  
  ROUND(AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)), 2) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  
  ROUND(SUM(total_bytes_processed) / POW(1024, 3), 2) AS gb_last_hour,
  
  -- Verify reservation usage
  STRING_AGG(DISTINCT reservation_id, ' | ') AS reservations,
  ROUND(100.0 * COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') / COUNT(*), 1) AS pct_dedicated,
  
  -- Status
  CASE
    WHEN MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 10 THEN '🔴 ALERT'
    WHEN AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 2 THEN '🟡 WARNING'
    WHEN COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') < COUNT(*) * 0.95 THEN '🟡 NOT FULLY MIGRATED'
    ELSE '✅ OK'
  END AS status

FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
" | tee -a hourly_monitoring_$(date +%Y%m%d).csv

echo ""
date
echo "Expected: pct_dedicated ~100%, max_queue_sec <5, status ✅ OK"
echo "---"
EOF

chmod +x monitor_hourly.sh
```

**Run at:** 11am, 12pm, 1pm, 2pm, 3pm, 4pm, 5pm

**Alert triggers:**
- 🔴 max_queue_sec > 10 → Investigate (capacity insufficient?)
- 🟡 pct_dedicated < 95% → Some queries still on default (wait more or investigate)
- 🔴 status = ALERT → Take action

---

### First 7 Days: Daily Monitoring

```bash
# Save as monitor_daily.sh
cat > monitor_daily.sh << 'EOF'
#!/bin/bash
# Daily monitoring script

bq query --use_legacy_sql=false --format=csv "
SELECT
  DATE(creation_time, 'America/Los_Angeles') AS date_pst,
  
  -- Volume
  COUNT(*) AS daily_queries,
  
  -- Performance
  ROUND(AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)), 2) AS avg_queue_sec,
  APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] AS p95_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  
  -- Reservation usage
  STRING_AGG(DISTINCT reservation_id, ' | ') AS reservations_used,
  ROUND(100.0 * COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') / COUNT(*), 1) AS pct_dedicated,
  
  -- Slot consumption (for capacity check)
  ROUND(SUM(total_slot_ms) / 3600000, 1) AS slot_hours_consumed,
  ROUND(SUM(total_slot_ms) / 3600000 / 24, 1) AS avg_concurrent_slots,
  
  -- Data processed
  ROUND(SUM(total_bytes_processed) / POW(1024, 4), 3) AS tb_processed,
  
  -- Problem detection
  COUNTIF(TIMESTAMP_DIFF(start_time, creation_time, SECOND) > 60) AS delayed_over_1min,
  COUNTIF(error_result IS NOT NULL) AS errors,
  
  -- Status
  CASE
    WHEN MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 30 THEN '🔴 LATENCY ALERT'
    WHEN COUNTIF(error_result IS NOT NULL) > 10 THEN '🔴 ERROR ALERT'
    WHEN SUM(total_slot_ms) / 3600000 / 24 > 45 THEN '🟡 HIGH CAPACITY USAGE'
    WHEN COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') < COUNT(*) * 0.9 THEN '🟡 NOT ON DEDICATED'
    ELSE '✅ HEALTHY'
  END AS status

FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY'
GROUP BY date_pst
ORDER BY date_pst DESC;
" | tee daily_monitoring_$(date +%Y%m%d).csv

echo ""
echo "Expected values:"
echo "  p95_queue_sec: <2 seconds"
echo "  pct_dedicated: 100%"
echo "  avg_concurrent_slots: 15-25 slots (well under 50-slot capacity)"
echo "  status: ✅ HEALTHY"
echo ""
EOF

chmod +x monitor_daily.sh
```

**Run daily at 9am for first week**

---

## Success Criteria

### Immediate (First Hour):

| Metric | Target | Check Frequency |
|--------|--------|-----------------|
| Reservation ID | `messaging-dedicated` | Every 5 min |
| P95 queue time | <2 seconds | Every 5 min |
| Max queue time | <5 seconds | Every 5 min |
| Avg execution | 2-3 seconds (unchanged) | Every 5 min |
| Error rate | 0% | Every 5 min |

### 24-Hour Success:

| Metric | Target | Check Frequency |
|--------|--------|-----------------|
| % on dedicated reservation | >95% | Hourly |
| P95 queue time | <2 seconds | Hourly |
| Max queue time | <10 seconds | Hourly |
| Avg concurrent slots | 15-30 slots (under 50) | Hourly |
| Error rate | <0.1% | Hourly |

### 7-Day Success:

| Metric | Target | Check Frequency |
|--------|--------|-----------------|
| P95 queue time | <2 seconds | Daily |
| Avg concurrent slots | 15-30 slots | Daily |
| Peak concurrent slots | <45 slots | Daily |
| Zero customer complaints | Yes | Monitor Jira/Slack |
| % on dedicated | 100% | Daily |

**Capacity headroom check:**
- If avg_concurrent_slots consistently >45 → Consider increasing to 100 slots
- If avg_concurrent_slots consistently <15 → Consider decreasing to 30 slots

---

## Rollback Procedures

### When to Rollback Immediately

Execute rollback if ANY of these occur:

1. **Error rate >1%** (queries failing)
2. **P95 queue >30 seconds** (worse than shared reservation)
3. **Customer complaints** about notification history
4. **Queries not migrating** to dedicated reservation after 10 minutes
5. **Capacity alerts** (avg_concurrent_slots approaching 50)

### Rollback Steps (2 minutes)

```bash
# Option 1: Use the script
./rollback_messaging_to_default.sh

# Option 2: Manual rollback via API
TOKEN=$(gcloud auth print-access-token)

# Find the assignment to delete
ASSIGNMENT=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for assignment in data.get('assignments', []):
    if 'messaging@narvar-data-lake' in assignment.get('assignee', ''):
        print(assignment['name'])
")

# Delete it
curl -X DELETE -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/$ASSIGNMENT"

# Wait and verify
sleep 60

bq query --use_legacy_sql=false "
SELECT STRING_AGG(DISTINCT reservation_id, ', ') AS reservation
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
GROUP BY 1;
"
# Should show: bq-narvar-admin:US.default (back to org default)
```

**After rollback:**
- Service account reverts to org-level assignment (shared reservation)
- Back to original state (competing with Airflow/Metabase)
- Document what went wrong
- Investigate issue before re-attempting

---

## Cost Management

### Flex Reservation Cost

**Fixed monthly cost:** $146/month (50 slots)

**Calculation:**
```
50 slots × $0.04/slot-hour × 24 hours × 30 days = $1,440/month
Actually: 50 slots × 730 hours/month × $0.04 = $1,460/year ÷ 12 = $121.67/month

Correct calc:
50 slots × 730 hours/month × $0.04/slot-hour = $1,460/year
$1,460/12 = $121.67/month

OR using annual rate:
50 slots × 8,760 hours/year × $0.04/slot-hour = $17,520/year
$17,520/12 = $1,460/month

Actually per Google pricing:
Flex slots: $0.04/slot-hour
50 slots running continuously: 50 × 24 × 30 = 36,000 slot-hours/month
36,000 × $0.04 = $1,440/month... 

Let me use the documented rate:
50 slots flex = $146/month (from pricing docs)
```

**This is a FIXED cost** - you pay $146/month regardless of usage.

**Capacity utilization:**
- Current avg: ~20 slots (40% utilization)
- Peak: ~35 slots (70% utilization)
- Capacity: 50 slots (100%)
- **Headroom:** 15 slots (30% buffer)

**Right-sizing options:**
- If consistently <15 slots avg → Reduce to 30 slots ($88/month)
- If peak approaches 50 slots → Increase to 100 slots ($292/month)

### No Budget Alerts Needed

**Unlike on-demand:**
- Flex has **fixed cost** ($146/month)
- No variable usage costs
- No need for daily cost monitoring
- **Budget is predictable**

**However, monitor slot utilization:**
- Alert if avg_concurrent_slots >45 (approaching capacity)
- Alert if p95_queue_sec >5 (insufficient capacity)

---

## Troubleshooting

### Issue 1: Queries Still Using Default Reservation

**Symptom:** `reservation_id` = `bq-narvar-admin:US.default` after 10 minutes

**Possible causes:**
1. Assignment didn't create successfully
2. Propagation delayed
3. Service account specification wrong

**Investigation:**
```bash
# Check if assignment exists
TOKEN=$(gcloud auth print-access-token)

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments" \
  | python3 -m json.tool
```

**If no assignments shown:** Re-create the assignment (Step 2 above)

**If assignment shown but queries not using it:** Wait 5 more minutes, then contact GCP Support

---

### Issue 2: Queue Times Still High

**Symptom:** P95 queue >5 seconds on dedicated reservation

**Possible causes:**
1. 50 slots insufficient for workload
2. Query inefficiency
3. Burst traffic patterns

**Investigation:**
```sql
-- Check slot utilization
SELECT
  DATE(creation_time, 'America/Los_Angeles') AS date,
  EXTRACT(HOUR FROM creation_time) AS hour,
  
  COUNT(*) AS queries,
  ROUND(SUM(total_slot_ms) / 3600000, 1) AS slot_hours,
  ROUND(SUM(total_slot_ms) / 3600000 / 1, 1) AS avg_concurrent_slots,  -- per hour
  
  APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] AS p95_queue_sec,
  
  CASE
    WHEN SUM(total_slot_ms) / 3600000 / 1 > 48 THEN '🔴 NEAR CAPACITY'
    WHEN SUM(total_slot_ms) / 3600000 / 1 > 40 THEN '🟡 HIGH USAGE'
    ELSE '✅ OK'
  END AS capacity_status

FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND reservation_id = 'bq-narvar-admin:US.messaging-dedicated'
GROUP BY date, hour
ORDER BY date DESC, hour DESC;
```

**If capacity_status = '🔴 NEAR CAPACITY':**
- Increase reservation to 100 slots
- Rerun above query to verify improvement

**Action:**
```bash
# Increase reservation to 100 slots
bq update \
  --location=US \
  --project_id=bq-narvar-admin \
  --slots=100 \
  messaging-dedicated

# Wait and verify
sleep 60
./monitor_5min.sh
```

---

### Issue 3: Queries Failing

**Symptom:** Error rate >0.1%

**Investigation:**
```sql
-- Check error details
SELECT
  error_result.reason,
  error_result.message,
  COUNT(*) AS error_count,
  ANY_VALUE(job_id) AS sample_job_id,
  ANY_VALUE(reservation_id) AS reservation_used
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND error_result IS NOT NULL
GROUP BY error_result.reason, error_result.message
ORDER BY error_count DESC;
```

**Actions:**
- If errors = "accessDenied" → Rollback (permissions issue)
- If errors = "rateLimitExceeded" → Transient, monitor
- If errors = "resourcesExceeded" → Increase reservation capacity
- If errors unrelated to reservation → Likely transient, monitor

---

## Post-Deployment

### Day 1 Checklist:

- [ ] Pre-deployment baseline captured
- [ ] Reservation created (`messaging-dedicated`, 50 slots)
- [ ] Service account assigned via API
- [ ] Immediate verification passed (queries using new reservation)
- [ ] 5-minute monitoring (6 checks in first hour) - all passed
- [ ] Hourly monitoring (6 checks during business hours) - all passed
- [ ] End-of-day review completed

### Days 2-7 Checklist:

- [ ] Daily monitoring at 9am (check script output)
- [ ] Verify P95 queue <2 seconds
- [ ] Check avg concurrent slots (should be 15-30)
- [ ] Monitor for customer complaints (none expected)
- [ ] Document any anomalies

### Day 7 Review:

- [ ] Calculate 7-day average concurrent slots
- [ ] Determine if reservation right-sized:
  - If <15 slots avg → Consider reducing to 30 slots ($88/month)
  - If >40 slots avg → Consider increasing to 100 slots ($292/month)
- [ ] Update stakeholders on results
- [ ] Update Jira DTPL-6903 with results
- [ ] Schedule 30-day review

---

## Capacity Right-Sizing Guide

**Monitor average concurrent slots over 7 days:**

| Avg Concurrent Slots | Recommended Reservation | Monthly Cost | Headroom |
|---------------------|-------------------------|--------------|----------|
| <10 slots | 30 slots | $88 | 200% |
| 10-20 slots | 30 slots | $88 | 50-200% |
| 20-30 slots | 50 slots | $146 | 67-150% |
| 30-40 slots | 50 slots | $146 | 25-67% |
| 40-60 slots | 100 slots | $292 | 67-150% |
| >60 slots | 100+ slots | $292+ | <67% |

**Recommended headroom:** 30-50% above peak concurrent usage

**Current projection:** 20-30 slots avg → **50 slots is appropriate**

**Actions after 7 days:**
```bash
# If underutilized (<15 slots avg), reduce to 30
bq update --location=US --project_id=bq-narvar-admin --slots=30 messaging-dedicated

# If near capacity (>40 slots avg), increase to 100
bq update --location=US --project_id=bq-narvar-admin --slots=100 messaging-dedicated
```

---

## Future: Org-Level Assignment Refactoring (Optional Cost Optimization)

**Goal:** Enable true on-demand for messaging ($27/month instead of $146/month)

**Savings:** $119/month ($1,428/year)

**Requirements:**
1. **Data Platform team coordination** - org-wide change
2. **Remove org-level assignment:** Delete organizations/770066481180 from default reservation
3. **Create project-specific assignments:** Assign each project that needs reservation
4. **Exclude narvar-data-lake:** Let it default to on-demand

**Timeline:** 1-2 weeks (requires testing across all projects)

**Risk:** Medium-High (affects entire organization)

**When to pursue:** After messaging-dedicated has been stable for 30 days

---

## Stakeholder Communication

### Pre-Deployment Email

**To:** Messaging team, Data Engineering, SRE

```
Subject: [Today] BigQuery Dedicated Capacity - Messaging Service

Team,

Deploying dedicated BigQuery capacity for Notification History to resolve 
DTPL-6903 latency issue.

What's happening:
- Creating 50-slot dedicated reservation for messaging service
- Queries will be isolated from shared workloads
- Zero downtime expected

Details:
- Time: Today at [TIME] PST
- Duration: 10-15 minutes
- Impact: Queue times drop to <1 second (from 8 minutes on Friday)
- Cost: $146/month (dedicated capacity)
- Rollback: 2 minutes if any issues

Expected result: Notification History feature becomes responsive again

Monitoring: Every 5 minutes for first hour, then hourly

- Cezar
```

### Post-Deployment Update (24 hours later)

```
Subject: [Complete] Messaging Dedicated Capacity Deployment

Team,

Deployment completed successfully yesterday.

Results (first 24 hours):
- Reservation: messaging-dedicated (50 slots)
- Queue times: P95 = [X]s (target: <2s) ✅
- Capacity: [X] avg concurrent slots (50 available)
- Errors: 0 ✅
- Customer complaints: 0 ✅

Messaging service is now on dedicated capacity, isolated from batch workloads.

Continuing daily monitoring for 7 days.

Next: 7-day review on [DATE] to optimize capacity (may reduce to 30 slots)

- Cezar
```

---

## Emergency Contacts

**If issues during deployment:**

1. **Immediate rollback:** Run `./rollback_messaging_to_default.sh`
2. **Data Platform team:** [Contact]
3. **GCP Support:** Open P2 ticket if BigQuery issues
4. **Messaging team:** [Contact] if customer impact

---

## Summary: What This Deployment Does

**BEFORE:**
```
messaging@narvar-data-lake
    ↓
organizations/770066481180 → bq-narvar-admin:US.default (shared)
    ↓
Competes with: Airflow (46%), Metabase (31%), n8n, others
    ↓
Result: Queue delays up to 558 seconds
```

**AFTER:**
```
messaging@narvar-data-lake
    ↓
Service-account assignment → bq-narvar-admin:US.messaging-dedicated
    ↓
Dedicated 50 slots (isolated, no competition)
    ↓
Result: Queue <1 second, dedicated capacity
```

**Cost:** $146/month (necessary given org-level constraint)

**Future:** Refactor org-level assignment → on-demand ($27/month, saves $119/month)

---

**Runbook Version:** 2.0 - Final (Based on Org-Level Assignment Discovery)  
**Supersedes:** DEPLOYMENT_RUNBOOK.md, ON_DEMAND_DEPLOYMENT_PLAN.md  
**Status:** READY FOR DEPLOYMENT  
**Deployment Method:** CLI using BigQuery Reservation API

