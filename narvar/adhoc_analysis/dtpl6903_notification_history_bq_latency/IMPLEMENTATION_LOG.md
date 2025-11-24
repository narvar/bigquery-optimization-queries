# Implementation Log - messaging-hub-bq-dedicated Project Setup

**Date:** November 24, 2025  
**Implementer:** Cezar Mihaila  
**Goal:** Create separate BigQuery project for messaging with dedicated reservation  
**Reference:** SEPARATE_PROJECT_SOLUTION.md

---

## Implementation Status: 🟡 IN PROGRESS

**Started:** 3:00pm PST, November 24, 2025

---

## Phase 1: Infrastructure Setup (Day 1)

### Step 1: Create GCP Project

**Status:** [x] Attempted

**Command:**
```bash
gcloud projects create messaging-hub-bq-dedicated \
  --name="Messaging BigQuery Dedicated" \
  --organization=770066481180 \
  --labels=purpose=bigquery-isolation,team=messaging
```

**Expected output:** Project created successfully

**Actual result:**
```
ERROR: (gcloud.projects.create) PERMISSION_DENIED: 
Permission 'resourcemanager.projects.create' denied on resource (or it may not exist). 
This command is authenticated as cezar.mihaila@narvar.com
```

**Success criteria:**
- [ ] Project created - ❌ FAILED
- [ ] Project ID: messaging-hub-bq-dedicated - ❌ NOT CREATED

**Timestamp:** 3:05pm PST, November 24, 2025  
**Status:** [x] ❌ FAILED

**Notes:**
- Cezar does not have resourcemanager.projects.create permission
- Need to request this permission OR ask someone who has it (Platform team, Saurabh, Julia)
- **Blocker:** Cannot proceed with remaining steps until project is created

---

### Step 2: Link Billing Account

**Status:** [ ] Not Started

**Commands:**
```bash
# Get billing account from narvar-data-lake
BILLING_ACCOUNT=$(gcloud billing projects describe narvar-data-lake --format="value(billingAccountName)")
echo "Billing account: $BILLING_ACCOUNT"

# Link to new project
gcloud billing projects link messaging-hub-bq-dedicated \
  --billing-account=$BILLING_ACCOUNT
```

**Expected output:** Billing account linked

**Actual result:**
```
[TO BE FILLED]
```

**Success criteria:**
- [ ] Billing account identified
- [ ] Billing linked to messaging-hub-bq-dedicated

**Timestamp:**  
**Status:** [ ] ✅ SUCCESS [ ] ❌ FAILED [ ] ⏸️ PENDING

**Notes:**

---

### Step 3: Enable BigQuery API

**Status:** [ ] Not Started

**Command:**
```bash
gcloud services enable bigquery.googleapis.com --project=messaging-hub-bq-dedicated
```

**Expected output:** Service enabled

**Actual result:**
```
[TO BE FILLED]
```

**Success criteria:**
- [ ] BigQuery API enabled

**Timestamp:**  
**Status:** [ ] ✅ SUCCESS [ ] ❌ FAILED [ ] ⏸️ PENDING

**Notes:**

---

### Step 4: Assign Project to messaging-dedicated Reservation

**Status:** [ ] Not Started

**Commands:**
```bash
# Get auth token
TOKEN=$(gcloud auth print-access-token)

# Assign project to reservation
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "assignee": "projects/messaging-hub-bq-dedicated",
    "jobType": "QUERY"
  }' \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments" \
  | python3 -m json.tool
```

**Expected output:**
```json
{
  "name": "projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments/...",
  "assignee": "projects/messaging-hub-bq-dedicated",
  "jobType": "QUERY",
  "state": "ACTIVE"
}
```

**Actual result:**
```
[TO BE FILLED]
```

**Success criteria:**
- [ ] Assignment created
- [ ] State: ACTIVE
- [ ] Assignee: projects/messaging-hub-bq-dedicated

**Timestamp:**  
**Status:** [ ] ✅ SUCCESS [ ] ❌ FAILED [ ] ⏸️ PENDING

**Notes:**

---

### Step 5: Grant Existing Service Account Permission on New Project

**Status:** [ ] Not Started

**Command:**
```bash
# Grant messaging@narvar-data-lake permission to run jobs in messaging-hub-bq-dedicated
gcloud projects add-iam-policy-binding messaging-hub-bq-dedicated \
  --member="serviceAccount:messaging@narvar-data-lake.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"
```

**Expected output:** Updated IAM policy

**Actual result:**
```
[TO BE FILLED]
```

**Success criteria:**
- [ ] IAM policy updated
- [ ] messaging@narvar-data-lake has bigquery.jobUser

**Timestamp:**  
**Status:** [ ] ✅ SUCCESS [ ] ❌ FAILED [ ] ⏸️ PENDING

**Notes:**

---

### Step 6: Grant Admin Access to Data Engineering Team

**Status:** [ ] Not Started

**Commands:**
```bash
# Grant data-eng@narvar.com group owner access
gcloud projects add-iam-policy-binding messaging-hub-bq-dedicated \
  --member="group:data-eng@narvar.com" \
  --role="roles/owner"

# Grant individual leads
gcloud projects add-iam-policy-binding messaging-hub-bq-dedicated \
  --member="user:saurabh.shrivastava@narvar.com" \
  --role="roles/owner"

gcloud projects add-iam-policy-binding messaging-hub-bq-dedicated \
  --member="user:julia.le@narvar.com" \
  --role="roles/owner"

gcloud projects add-iam-policy-binding messaging-hub-bq-dedicated \
  --member="user:cezar.mihaila@narvar.com" \
  --role="roles/owner"

gcloud projects add-iam-policy-binding messaging-hub-bq-dedicated \
  --member="user:eric.rops@narvar.com" \
  --role="roles/owner"
```

**Expected output:** IAM policies updated for each user/group

**Actual result:**
```
[TO BE FILLED]
```

**Success criteria:**
- [ ] data-eng@narvar.com has owner role
- [ ] Saurabh, Julia, Cezar, Eric have owner roles

**Timestamp:**  
**Status:** [ ] ✅ SUCCESS [ ] ❌ FAILED [ ] ⏸️ PENDING

**Notes:**

---

### Step 7: Test Cross-Project Query

**Status:** [ ] Not Started

**Test Query (from DTPL-6903 - actual notification history query):**
```bash
# Test cross-project access with real query pattern
bq query \
  --use_legacy_sql=false \
  --project_id=messaging-hub-bq-dedicated \
  --impersonate_service_account=messaging@narvar-data-lake.iam.gserviceaccount.com \
  "
SELECT 
  metric_name, 
  order_number, 
  tracking_number,
  narvar_tracer_id, 
  carrier_moniker, 
  notification_event_type,
  event_ts, 
  notification_channel, 
  request_failure_code,
  request_failure_reason, 
  '' as status_code, 
  dedupe_key,
  estimated_delivery_date, 
  '' as data_available_date_time 
FROM \`narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug\`
WHERE event_ts BETWEEN TIMESTAMP '2025-11-20T05:25:43' 
  AND TIMESTAMP '2025-11-22T00:10:35.448412' 
  AND retailer_moniker = 'jdsports-emea' 
  AND metric_name = 'NOTIFICATION_EVENT_NOT_TRIGGERED' 
  AND request_failure_code NOT IN ('103', '112') 
  AND upper(order_number) = '188072755'
LIMIT 10;
"

# Verify reservation usage
bq query --use_legacy_sql=false --project_id=messaging-hub-bq-dedicated "
SELECT 
  job_id,
  reservation_id,
  TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS exec_sec
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND project_id = 'messaging-hub-bq-dedicated'
ORDER BY creation_time DESC
LIMIT 5;
"
```

**Expected results:**
- Test query executes successfully
- Returns notification data (or empty if order not found)
- reservation_id = `bq-narvar-admin:US.messaging-dedicated`
- queue_sec = 0-1 seconds
- No permission errors

**Actual result:**
```
[TO BE FILLED]
```

**Success criteria:**
- [ ] Query executes without errors
- [ ] Can read narvar-data-lake.messaging tables
- [ ] Using messaging-dedicated reservation
- [ ] Queue time <2 seconds

**Timestamp:**  
**Status:** [ ] ✅ SUCCESS [ ] ❌ FAILED [ ] ⏸️ PENDING

**Notes:**

---

## Phase 1 Summary

**Total steps completed:** 0 / 7

**Phase 1 status:** [ ] ✅ COMPLETE [ ] ⚠️ IN PROGRESS [ ] ❌ BLOCKED

**Time spent:**

**Issues encountered:**

**Next phase:** Phase 2 - Messaging Team Staging Deployment

---

## Phase 2: Staging Deployment (Day 2) - Messaging Team

**Status:** [ ] Not Started

**Actions for messaging team:**
1. Update project_id in staging config
2. Update table references to fully-qualified names (all 10 tables)
3. Deploy to staging
4. Test notification history searches
5. Validate cross-project access working

**Will be tracked separately with messaging team**

---

## Phase 3: Production Deployment (Day 3) - Messaging Team

**Status:** [ ] Not Started

**Actions for messaging team:**
1. Update production config (project_id)
2. Rolling deployment
3. Monitor for 1 hour
4. Verify no customer complaints

**Will be tracked separately with messaging team**

---

## Rollback Information

**If any step fails:**
- Reservation: messaging-dedicated (already exists, can keep)
- Project: Can delete messaging-hub-bq-dedicated if needed
- No impact to production (messaging still on default reservation)

**Rollback commands saved in:** `rollback_messaging_to_default.sh`

---

## Final Validation

**After complete implementation:**

**Performance metrics:**
- [ ] P95 queue time <1 second
- [ ] 100% queries using messaging-dedicated reservation
- [ ] Zero errors
- [ ] Zero customer complaints

**Cost metrics:**
- [ ] Billing project: messaging-hub-bq-dedicated
- [ ] Reservation: messaging-dedicated (50 + autoscale 50)
- [ ] Monthly cost: ~$219 (predictable)

**Jira update:**
- [ ] DTPL-6903 marked as resolved
- [ ] Documentation links added

---

**Log Status:** 🟡 ACTIVE - Updating as we proceed  
**Next Update:** After Step 1 completion

