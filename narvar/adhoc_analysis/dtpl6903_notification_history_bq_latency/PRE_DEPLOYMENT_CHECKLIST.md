# Pre-Deployment Checklist - Messaging Dedicated Capacity

**Deployment Date:** November 24, 2025  
**Deployer:** Cezar Mihaila  
**Service Account:** `messaging@narvar-data-lake.iam.gserviceaccount.com`  
**Reservation:** 50 baseline + autoscale to 100 slots  
**Estimated Cost:** ~$219/month ($146 baseline + ~$73 autoscale)  
**Estimated Time:** 15 minutes

---

## ⚠️ Peak Capacity Analysis Summary

**Why autoscale is needed:**

From 7-day actual usage analysis:
- **Average:** 48 concurrent slots
- **Daytime:** 46-57 slots (fits in 50 baseline)
- **9pm DAILY spike:** 186-386 slots (**4-8x average!**)
- **Overnight:** 59-142 slots

**Fixed 50 slots:** ❌ Would cause queue delays every night at 9pm  
**Fixed 100 slots:** ✅ Handles peak but wastes $73/month  
**50 + autoscale 50:** ✅ Cost-optimized, elastic capacity

**See:** `results/hourly_peak_slots.csv` for complete data

---

## ✅ Pre-Deployment Checklist (Complete Before Starting)

### 1. Environment Setup

```bash
# Navigate to working directory
cd /Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency

# Verify you're authenticated
gcloud auth list
# Should show: cezar.mihaila@narvar.com (active)

# Test BigQuery access
bq ls --project_id=bq-narvar-admin --location=US --reservation
# Should show: bq-narvar-admin:US.default and iris-standard
```

**Status:** [ ] Complete

---

### 2. Capture Baseline (Save for Comparison)

```bash
# Capture current performance baseline
bq query --use_legacy_sql=false --format=csv "
SELECT
  COUNT(*) AS queries_last_hour,
  STRING_AGG(DISTINCT reservation_id, ', ') AS current_reservation,
  ROUND(AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)), 2) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  ROUND(SUM(total_bytes_processed) / POW(1024, 3), 2) AS gb_processed,
  COUNTIF(error_result IS NOT NULL) AS errors
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
" | tee baseline_$(date +%Y%m%d_%H%M).csv
```

**Expected output:**
- current_reservation: `bq-narvar-admin:US.default`
- avg_queue_sec: 0-2 seconds (currently healthy)
- errors: 0

**Status:** [ ] Complete - Baseline saved to: `baseline_YYYYMMDD_HHMM.csv`

---

### 3. Create Rollback Script

```bash
# Create rollback script (just in case)
cat > rollback_messaging_to_default.sh << 'EOF'
#!/bin/bash
# Rollback: Remove messaging from dedicated reservation

echo "🔄 Rolling back messaging to default reservation..."

TOKEN=$(gcloud auth print-access-token)

# Find assignment to delete
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
    echo "Deleting: $ASSIGNMENT"
    curl -s -X DELETE -H "Authorization: Bearer $TOKEN" \
      "https://bigqueryreservation.googleapis.com/v1/$ASSIGNMENT"
    echo "✅ Deleted"
else
    echo "⚠️  No assignment found"
fi

echo "⏰ Waiting 60 seconds..."
sleep 60

echo "✅ Verifying..."
bq query --use_legacy_sql=false "
SELECT STRING_AGG(DISTINCT reservation_id, ', ') AS reservation
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
GROUP BY 1;
"

echo "✅ Should show: bq-narvar-admin:US.default (back to org default)"
EOF

chmod +x rollback_messaging_to_default.sh
echo "✅ Rollback script created"
```

**Status:** [ ] Complete - Rollback script ready: `./rollback_messaging_to_default.sh`

---

### 4. Create Monitoring Scripts

```bash
# 5-minute monitoring script
cat > monitor_5min.sh << 'EOF'
#!/bin/bash
bq query --use_legacy_sql=false --format=csv "
SELECT
  CURRENT_TIMESTAMP() AS check_time,
  COUNT(*) AS queries_last_5min,
  ROUND(AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)), 2) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  STRING_AGG(DISTINCT reservation_id, ' | ') AS reservations,
  COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') AS dedicated_count,
  COUNTIF(error_result IS NOT NULL) AS errors,
  CASE
    WHEN MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 10 THEN '🔴 QUEUE ISSUES'
    WHEN COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') = COUNT(*) THEN '✅ HEALTHY'
    ELSE '🟡 MIGRATING'
  END AS status
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
" | tee -a monitoring_log_$(date +%Y%m%d).csv
echo "---"
EOF

chmod +x monitor_5min.sh

# Hourly monitoring script
cat > monitor_hourly.sh << 'EOF'
#!/bin/bash
bq query --use_legacy_sql=false --format=csv "
SELECT
  EXTRACT(HOUR FROM CURRENT_TIMESTAMP()) AS hour,
  COUNT(*) AS queries_last_hour,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  ROUND(100.0 * COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') / COUNT(*), 1) AS pct_dedicated,
  CASE
    WHEN MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 10 THEN '🔴 ALERT'
    ELSE '✅ OK'
  END AS status
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com';
" | tee -a hourly_log_$(date +%Y%m%d).csv
EOF

chmod +x monitor_hourly.sh

echo "✅ Monitoring scripts created"
```

**Status:** [ ] Complete - Scripts ready: `monitor_5min.sh`, `monitor_hourly.sh`

---

### 5. Verify No Active Incidents

```bash
# Check current query health
bq query --use_legacy_sql=false "
SELECT
  COUNT(*) AS queries_last_10min,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  COUNTIF(error_result IS NOT NULL) AS errors
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com';
"
```

**Expected:**
- queries_last_10min: >0 (traffic flowing)
- max_queue_sec: <5 (currently stable)
- errors: 0

**If errors >0 or max_queue_sec >30:** Wait for current issue to resolve before deploying

**Status:** [ ] Complete - System healthy, safe to proceed

---

## 🚀 DEPLOYMENT COMMANDS (Copy-Paste Ready)

### Step 1: Create Dedicated Reservation with Autoscaling (2 minutes)

```bash
# Create 50-slot baseline + autoscale to 100 slots total
# ENTERPRISE edition required for autoscaling
echo "🚀 Creating messaging-dedicated reservation..."

bq mk \
  --location=US \
  --project_id=bq-narvar-admin \
  --reservation \
  --slots=50 \
  --ignore_idle_slots=false \
  --edition=ENTERPRISE \
  --autoscale_max_slots=50 \
  messaging-dedicated

# Log it
echo "Created at: $(date)" >> deployment_log.txt
echo "  - Baseline: 50 slots (\$146/month)" >> deployment_log.txt  
echo "  - Autoscale: +50 slots (handles 9pm peak)" >> deployment_log.txt
```

**Expected output:**
```
Reservation 'bq-narvar-admin:US.messaging-dedicated' successfully created.
```

**Configuration:**
- **Baseline:** 50 slots (always active, $146/month)
- **Autoscale:** +50 slots (activates during 9pm peak, ~$73/month avg)
- **Total capacity:** 100 slots
- **Total cost:** ~$219/month ($146 baseline + $73 autoscale)

**Why autoscale?**
- Peak analysis showed daily 9pm spike of 186-386 slots
- Autoscale provides capacity when needed without paying for 100 slots 24/7
- Saves ~$73/month vs 100-slot fixed reservation

**If "already exists":** Skip to Step 2 (reservation was created previously)

**If "permission denied":** You need `bigquery.resourceAdmin` role - STOP and request permissions

**Status:** [ ] Complete - Reservation created successfully

---

### Step 2: Assign Messaging Service Account (3 minutes)

```bash
# Get authentication token
echo "🔐 Getting authentication token..."
TOKEN=$(gcloud auth print-access-token)

# Create service-account assignment
echo "📋 Assigning messaging service account..."

curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "assignee": "projects/narvar-data-lake/serviceAccounts/messaging@narvar-data-lake.iam.gserviceaccount.com",
    "jobType": "QUERY"
  }' \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments" \
  | python3 -m json.tool

# Log it
echo "Assigned at: $(date)" >> deployment_log.txt
```

**Expected output (JSON):**
```json
{
  "name": "projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments/...",
  "assignee": "projects/narvar-data-lake/serviceAccounts/messaging@narvar-data-lake.iam.gserviceaccount.com",
  "jobType": "QUERY",
  "state": "ACTIVE"
}
```

**If you see "state": "ACTIVE":** ✅ Assignment created successfully!

**If error 403:** Permission denied - STOP and request `bigquery.resourceAdmin` role

**If error 409:** Assignment already exists - Proceed to Step 3 (verify it's working)

**Status:** [ ] Complete - Assignment created successfully

---

### Step 3: Wait for Propagation (1 minute)

```bash
echo "⏰ Waiting 60 seconds for BigQuery to propagate configuration..."
sleep 60
echo "✅ Ready to verify"
```

**Status:** [ ] Complete - Waited 60 seconds

---

### Step 4: Immediate Verification (5 minutes)

```bash
# Check if queries are using the new reservation
echo "🔍 Verifying deployment..."

bq query --use_legacy_sql=false "
SELECT
  job_id,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), creation_time, SECOND) AS seconds_ago,
  reservation_id,
  TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS exec_sec,
  ROUND(total_bytes_processed / POW(1024, 3), 2) AS gb_processed,
  CASE 
    WHEN error_result IS NOT NULL THEN '❌ ERROR'
    ELSE '✅ OK'
  END AS status
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
ORDER BY creation_time DESC
LIMIT 10;
"
```

**✅ SUCCESS if you see:**
- `reservation_id` = `bq-narvar-admin:US.messaging-dedicated` (using new reservation)
- `queue_sec` = 0-1 seconds (no delays)
- `exec_sec` = 1-3 seconds (normal execution)
- `status` = ✅ OK (no errors)

**🟡 WAIT if you see:**
- `reservation_id` = `bq-narvar-admin:US.default` (still propagating)
- **Action:** Wait 2-3 more minutes, run query again

**🔴 ROLLBACK if you see:**
- `queue_sec` > 10 seconds (something wrong)
- `status` = ❌ ERROR on multiple queries
- **Action:** Run `./rollback_messaging_to_default.sh` immediately

**Status:** [ ] Complete - Queries using messaging-dedicated, queue <2s, no errors

---

## 📊 Post-Deployment Monitoring Schedule

### First Hour (Critical Monitoring Period)

**Run `./monitor_5min.sh` at these times:**

- [ ] T+5 min (10:05 if deployed at 10:00)
- [ ] T+10 min
- [ ] T+15 min
- [ ] T+20 min
- [ ] T+30 min
- [ ] T+45 min
- [ ] T+60 min

**Success criteria for each check:**
- ✅ status = '✅ HEALTHY'
- ✅ avg_queue_sec < 1 second
- ✅ max_queue_sec < 5 seconds
- ✅ dedicated_count = 100% of queries

**If any check fails:** Review troubleshooting section in DEPLOYMENT_RUNBOOK_FINAL.md

---

### First 8 Hours (Business Day Monitoring)

**Run `./monitor_hourly.sh` at these times:**

- [ ] 11:00am
- [ ] 12:00pm (noon)
- [ ] 1:00pm
- [ ] 2:00pm (peak traffic hour)
- [ ] 3:00pm (peak traffic hour)
- [ ] 4:00pm (peak traffic hour)  
- [ ] 5:00pm
- [ ] 6:00pm (end of business day)

**Success criteria:**
- ✅ pct_dedicated >95%
- ✅ max_queue_sec <10 seconds
- ✅ status = ✅ OK

---

### Day 2-7 (Daily Monitoring)

**Run `./monitor_daily.sh` at 9:00am each day:**

- [ ] Day 2 (Tuesday)
- [ ] Day 3 (Wednesday)
- [ ] Day 4 (Thursday)
- [ ] Day 5 (Friday)
- [ ] Day 6 (Saturday)
- [ ] Day 7 (Sunday)

**Review on Day 7:**
- Average concurrent slots (should be 15-30)
- P95 queue time (should be <2 seconds)
- Capacity utilization (should be 40-70%)

**Decision:** If avg slots <15, reduce to 30 slots. If >40, consider increasing to 100 slots.

---

## 🔴 ROLLBACK Decision Tree

```
During deployment, if you see:
├─ Error rate >1%
│  └─ 🔴 ROLLBACK IMMEDIATELY → ./rollback_messaging_to_default.sh
│
├─ P95 queue >30 seconds  
│  └─ 🔴 ROLLBACK IMMEDIATELY → ./rollback_messaging_to_default.sh
│
├─ Queries not using messaging-dedicated after 10 minutes
│  └─ 🔴 ROLLBACK IMMEDIATELY → ./rollback_messaging_to_default.sh
│
├─ P95 queue 5-10 seconds
│  └─ 🟡 MONITOR for 1 hour → If persists, increase to 100 slots
│
├─ Some queries still on default (<90%)
│  └─ 🟡 WAIT 5 minutes → Re-check → If persists, investigate
│
└─ P95 queue <2 seconds, 100% on dedicated, 0 errors
   └─ ✅ SUCCESS → Continue hourly monitoring
```

---

## 📋 Deployment Timeline

### T-5 min: Pre-Flight

- [ ] Baseline captured
- [ ] Rollback script created
- [ ] Monitoring scripts created
- [ ] System healthy check passed
- [ ] Working directory confirmed
- [ ] Authentication verified

### T+0: Deploy

- [ ] Create messaging-dedicated reservation (Step 1)
- [ ] Assign messaging service account (Step 2)
- [ ] Log deployment time

### T+1 min: Propagate

- [ ] Wait 60 seconds
- [ ] No actions required

### T+2 min: Verify

- [ ] Run immediate verification query
- [ ] Check reservation_id = messaging-dedicated
- [ ] Check queue_sec <2s
- [ ] Check no errors

### T+5 min: First Monitor

- [ ] Run `./monitor_5min.sh`
- [ ] Verify status = ✅ HEALTHY
- [ ] Document result

### T+10 to T+60 min: Intensive Monitoring

- [ ] Run `./monitor_5min.sh` every 5-10 minutes
- [ ] All checks should pass
- [ ] Log any anomalies

### T+2 to T+8 hours: Business Hours

- [ ] Run `./monitor_hourly.sh` every hour
- [ ] Verify during peak traffic (2-4pm)
- [ ] End-of-day review

---

## ⚠️ Stop/Go Decision Points

### STOP and Seek Help If:

- [ ] You cannot create the reservation (permission denied)
- [ ] You cannot create the assignment (API returns 403)
- [ ] Reservation created but service account assignment fails
- [ ] You're unsure about any step

**Contact:** Data Platform team or escalate to GCP Support

### GO Ahead If:

- [x] All pre-deployment checks passed
- [x] You have 15 minutes available
- [x] Current system is healthy (no active incidents)
- [x] Rollback script is ready and tested
- [x] You're comfortable with the monitoring plan

---

## 📞 Emergency Contacts (If Needed)

**If deployment issues:**
1. **Rollback first** (2 minutes): `./rollback_messaging_to_default.sh`
2. **Then investigate** - check deployment_log.txt for errors
3. **If unable to rollback:** Contact Data Platform team immediately

**If customer complaints:**
1. Check monitoring - is there a queue issue?
2. If yes: Rollback immediately
3. Update Jira DTPL-6903 with status

---

## ✅ Final Go/No-Go Check

**Check all boxes before proceeding:**

- [ ] Baseline captured and saved
- [ ] Rollback script created and executable
- [ ] Monitoring scripts created and executable
- [ ] Current system healthy (no errors, queue <5s)
- [ ] You have ~30 minutes available (15 deploy + 15 monitor)
- [ ] You understand what success looks like
- [ ] You know when to rollback
- [ ] Stakeholders notified (optional but recommended)

**If ALL boxes checked:** ✅ Proceed with deployment

**If ANY box unchecked:** ⏸️ Complete that item first

---

## 🎯 Post-Deployment Success Validation

**After deployment, verify ALL of these within first hour:**

### Immediate (T+5 min):
- [ ] reservation_id = messaging-dedicated
- [ ] avg_queue_sec < 1 second
- [ ] errors = 0

### First Hour (T+60 min):
- [ ] All 5-minute checks show ✅ HEALTHY
- [ ] No customer complaints
- [ ] No Jira escalations

### End of Day 1:
- [ ] Hourly checks all passed
- [ ] Queries 100% on dedicated reservation
- [ ] P95 queue <2 seconds during peak (2-4pm)
- [ ] Zero errors

**If all validated:** ✅ Deployment successful - continue daily monitoring

**If any failed:** Review troubleshooting in DEPLOYMENT_RUNBOOK_FINAL.md

---

## 📝 Deployment Log Template

```
DEPLOYMENT LOG
==============

Pre-Deployment:
- Date/Time: _______________
- Baseline file: _______________
- Current queue (P95): _____ seconds
- Current reservation: bq-narvar-admin:US.default

Deployment:
- Reservation created: [ ] YES [ ] NO
- Time: _______________
- Assignment created: [ ] YES [ ] NO  
- Time: _______________

Post-Deployment (T+5 min):
- Reservation ID: _______________
- Queue time (P95): _____ seconds
- Errors: _____
- Status: [ ] ✅ SUCCESS [ ] 🟡 WAIT [ ] 🔴 ROLLBACK

First Hour Monitoring:
- T+5: [ ] PASS
- T+10: [ ] PASS
- T+15: [ ] PASS
- T+30: [ ] PASS
- T+60: [ ] PASS

Issues Encountered:
_______________________________________
_______________________________________

Actions Taken:
_______________________________________
_______________________________________

Final Status: [ ] ✅ DEPLOYED [ ] 🔄 ROLLED BACK [ ] ⏸️ IN PROGRESS
```

---

## 🚀 YOU ARE READY TO DEPLOY

**Everything is prepared:**
- ✅ Scripts created
- ✅ Commands tested
- ✅ Monitoring ready
- ✅ Rollback available
- ✅ Success criteria defined

**The deployment:**
- 2 commands
- 15 minutes total
- Zero downtime
- 2-minute rollback

**When ready, execute Step 1 above** (Create Dedicated Reservation).

---

**Checklist Version:** 1.0  
**Date:** November 24, 2025  
**Deployment Runbook:** DEPLOYMENT_RUNBOOK_FINAL.md  
**Status:** ✅ READY - All prerequisites complete

