# Option A: Separate Project for Messaging - Implementation Guide

**Project Name:** `messaging-bq-dedicated`  
**Goal:** Isolate messaging BigQuery traffic with dedicated reservation for cost control  
**Timeline:** 3-5 days  
**Cost:** ~$219/month (50-slot baseline + autoscale 50) with predictable cost ceiling

---

## Executive Summary

**Approach:** Create dedicated GCP project for messaging BigQuery operations, assign to messaging-dedicated reservation

**Benefits:**
- ✅ Complete isolation from other workloads (Airflow, Metabase, n8n)
- ✅ Dedicated 50-slot baseline + autoscale to 100 slots (handles 9pm peak)
- ✅ **Cost control:** Fixed $146 baseline + predictable autoscale (~$73/month)
- ✅ No org-wide coordination needed
- ✅ Queue times <1 second guaranteed

**Trade-offs:**
- ⚠️ Requires application changes (update service account credentials)
- ⚠️ Cross-project BigQuery access setup
- ⚠️ Testing required before production rollout
- ⚠️ Timeline: 3-5 days (not immediate)
- ⚠️ Higher cost than hoped ($219/month vs $27 on-demand, but provides capacity guarantee)

---

## Implementation Steps

### Phase 1: Create Project & Service Account (Day 1 - 2 hours)

#### Step 1.1: Create GCP Project

```bash
# Create new project
gcloud projects create messaging-bq-dedicated \
  --name="Messaging BigQuery Dedicated" \
  --organization=770066481180 \
  --labels=purpose=bigquery-isolation,team=messaging

# Set billing account (use same as narvar-data-lake)
BILLING_ACCOUNT=$(gcloud billing projects describe narvar-data-lake --format="value(billingAccountName)")

gcloud billing projects link messaging-bq-dedicated \
  --billing-account=$BILLING_ACCOUNT

# Enable BigQuery API
gcloud services enable bigquery.googleapis.com --project=messaging-bq-dedicated
```

**Expected result:**
- Project ID: `messaging-bq-dedicated`
- Billing: Same account as narvar-data-lake
- BigQuery API: Enabled

---

#### Step 1.2: Assign Project to messaging-dedicated Reservation

```bash
# Assign the new project to the messaging-dedicated reservation (already created)
# This gives cost control via reservation (vs unpredictable on-demand)
TOKEN=$(gcloud auth print-access-token)

curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "assignee": "projects/messaging-bq-dedicated",
    "jobType": "QUERY"
  }' \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments"

# Verify assignment
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments" \
  | python3 -m json.tool
```

**Expected output:**
```json
{
  "name": "projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments/...",
  "assignee": "projects/messaging-bq-dedicated",
  "jobType": "QUERY",
  "state": "ACTIVE"
}
```

**Result:**
- messaging-bq-dedicated project → messaging-dedicated reservation (50 + autoscale 50)
- **Cost:** $146 baseline + ~$73 autoscale = ~$219/month (predictable, capped)
- **Capacity:** 100 slots max (sufficient for messaging's 48 avg, 228 peak)
- **vs On-Demand:** Higher cost but provides capacity guarantee and cost ceiling

---

#### Step 1.3: Grant Existing Service Account Access

**Use existing service account:** `messaging@narvar-data-lake.iam.gserviceaccount.com`

**Why reuse instead of creating new:**
- ✅ No credential changes needed in application
- ✅ Simpler deployment (just change project_id parameter)
- ✅ Less risky (no credential swap)
- ✅ Faster implementation

```bash
# Grant existing service account permission to run jobs in new project
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="serviceAccount:messaging@narvar-data-lake.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

# Service account already has access to narvar-data-lake.messaging dataset
# (existing permissions, no changes needed)
```

**Result:**
- Service account can run BigQuery jobs in messaging-bq-dedicated project
- Jobs billed to messaging-bq-dedicated
- Uses messaging-dedicated reservation
- **No new credentials needed!**

---

### Phase 2: Grant Existing Service Account Permissions (Day 1 - 15 minutes)

**Goal:** Allow existing messaging@narvar-data-lake service account to run jobs in new project

#### Step 2.1: Grant BigQuery Job User Permission

**Simple - just grant permission to run jobs in new project:**

```bash
# Grant existing service account permission to run BigQuery jobs in new project
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="serviceAccount:messaging@narvar-data-lake.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"
```

**What this grants:**
- ✅ Ability to run BigQuery jobs in `messaging-bq-dedicated` project
- ✅ Jobs will be billed to `messaging-bq-dedicated` project
- ✅ Jobs will use messaging-dedicated reservation

**What's already granted:**
- ✅ Service account already has access to `narvar-data-lake.messaging` tables (existing permissions)
- ✅ No additional dataset permissions needed

**Alternative: Table-specific permissions (more granular)**

If you want to grant access to specific tables only:

```bash
# List tables messaging service account currently uses
# (From notify-automation-service code: 10 tables)

TABLES=(
  "pubsub_rules_engine_pulsar_debug"
  "pubsub_rules_engine_pulsar_debug_V2"
  "pubsub_rules_engine_kafka"
  # Add other 7 tables from NoFlakeQueryService.java
)

# Grant access to each table
for table in "${TABLES[@]}"; do
  bq add-iam-policy-binding \
    --member="serviceAccount:messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataViewer" \
    narvar-data-lake:messaging.$table
done
```

**Recommendation:** Use **dataset-level permissions** (simpler, covers all tables, easier to maintain)

---

#### Step 2.2: Test Cross-Project Query Access

**Test the actual notification history query pattern from new project:**

```bash
# Verify permissions were granted
gcloud projects get-iam-policy messaging-bq-dedicated \
  --flatten="bindings[].members" \
  --filter="bindings.members:messaging@narvar-data-lake" \
  --format="table(bindings.role)"
# Should show: roles/bigquery.jobUser

# Test cross-project query (impersonate service account for testing)
# This simulates what the application will do
bq query \
  --use_legacy_sql=false \
  --project_id=messaging-bq-dedicated \
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

# Verify which reservation was used
bq query --use_legacy_sql=false --project_id=messaging-bq-dedicated "
SELECT 
  reservation_id,
  user_email,
  TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS exec_sec
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND project_id = 'messaging-bq-dedicated'
ORDER BY creation_time DESC
LIMIT 5;
"
```

**Expected results:**
- ✅ Query executes successfully
- ✅ Returns notification history data (may be empty if order not found)
- ✅ reservation_id = `bq-narvar-admin:US.messaging-dedicated` (using dedicated reservation!)
- ✅ queue_sec = 0-1 seconds (no delays)
- ✅ Cross-project access working

**This test confirms:**
- Service account can run jobs in messaging-bq-dedicated
- Can read narvar-data-lake.messaging tables
- Uses messaging-dedicated reservation (cost controlled)
- Performance is good (<1s queue)

---

### Phase 3: Admin Access Setup (Day 1 - 30 minutes)

**Grant Data Engineering team admin access to new project:**

```bash
# Add data engineering team members as owners
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="user:cezar.mihaila@narvar.com" \
  --role="roles/owner"

gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="user:eric.rops@narvar.com" \
  --role="roles/owner"

# Or add a Google Group (if you have one)
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="group:data-engineering@narvar.com" \
  --role="roles/owner"

# Grant BigQuery admin specifically
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="user:cezar.mihaila@narvar.com" \
  --role="roles/bigquery.admin"
```

**Recommended admin roles:**
- `roles/owner` - Full project admin (for Cezar, Eric, team leads)
- `roles/bigquery.admin` - BigQuery admin (for data engineers)
- `roles/viewer` - Read-only access (for other team members)

**Best practice:** Use Google Groups instead of individual users:
- Create: `data-engineering-admins@narvar.com` group
- Add group as project owner
- Easier to manage access over time

---

### Phase 4: Application Update (Day 2-3 - With Messaging Team)

**Changes needed in notify-automation-service:**

#### Update BigQuery Client Project ID

**File:** BigQueryService.java or configuration file

**Change:**
```diff
// BigQuery client initialization
BigQueryOptions.Builder optionsBuilder = BigQueryOptions.newBuilder()
-   .setProjectId("narvar-data-lake")
+   .setProjectId("messaging-bq-dedicated")
    .setCredentials(credentials);  // UNCHANGED - same service account
```

**OR environment variable:**
```diff
- BIGQUERY_PROJECT_ID=narvar-data-lake
+ BIGQUERY_PROJECT_ID=messaging-bq-dedicated
```

**What stays the same:**
- ✅ Service account: `messaging@narvar-data-lake.iam.gserviceaccount.com` (NO CHANGE)
- ✅ Credentials/secrets (NO CHANGE)
- ✅ Query logic (NO CHANGE)

**What changes:**
- ⚠️ **project_id parameter:** `narvar-data-lake` → `messaging-bq-dedicated`
- ⚠️ **Table references:** Must use fully-qualified names (project.dataset.table)

**IMPORTANT: Table Name Format**

**From (short form - only works in same project):**
```sql
FROM messaging.pubsub_rules_engine_pulsar_debug
```

**To (fully-qualified - required for cross-project):**
```sql
FROM `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug`
```

**All table references in queries must include the project name:**
- `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug`
- `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug_V2`
- `narvar-data-lake.messaging.pubsub_rules_engine_kafka`
- (and all other messaging tables)

**If tables are referenced as just `messaging.table_name`, queries will fail** with "table not found" errors.

**BigQuery client code:** 
- Source: https://github.com/narvar/notify-automation-service/blob/master/src/main/java/com/narvar/automationservice/services/BigQueryService.java
- **Minimal change:** Just update project_id parameter
- BigQuery client automatically handles cross-project queries

---

#### Testing Checklist

**Staging environment:**
1. Update project_id configuration in staging
2. Deploy/restart staging pods
3. Test notification history search (10+ searches, 100 queries total)
4. Verify queries execute successfully
5. Check reservation_id = `bq-narvar-admin:US.messaging-dedicated` (using new reservation)
6. Verify queue times <1 second
7. Test rollback (revert project_id to narvar-data-lake)

**Production deployment:**
1. Deploy during low-traffic window (early morning or late evening)
2. Monitor for 1 hour post-deployment
3. Verify no errors
4. Keep rollback command ready (2-minute revert)

---

### Phase 5: Monitoring & Validation (Day 4-5)

**Same monitoring as original plan:**
- Day 1: Every 5 minutes for 1 hour, then hourly
- Day 2-7: Daily at 9am
- Metrics: Queue time, cost, errors

**Additional metrics for cross-project setup:**
- Verify queries accessing narvar-data-lake tables successfully
- Monitor for any permission errors
- Track cross-project query latency (should be identical to same-project)

---

## Cost Analysis: Separate Project with Reservation

### Dedicated Reservation Cost for Messaging

**Configuration:**
- New project: `messaging-bq-dedicated`
- Assigned to: `messaging-dedicated` reservation (already created)
- Baseline: 50 slots ($146/month)
- Autoscale: +50 slots (~$73/month when active during 9pm peak)
- **Total: ~$219/month**

**Based on messaging traffic (7 days):**
- Queries: 93,315
- Average concurrent: 48 slots (fits in 50 baseline)
- Peak concurrent (9pm): 186-386 slots (needs autoscale)
- Capacity: 50 baseline + 50 autoscale = 100 total

**Why use reservation vs on-demand:**
- ✅ **Cost predictability:** $219/month ceiling (vs unlimited on-demand)
- ✅ **Capacity guarantee:** 100 slots always available  
- ✅ **No cost surprises:** Autoscale is capped at 50 additional slots
- ⚠️ Higher than on-demand ($219 vs $27), but provides budget certainty

**Compared to other options:**
- narvar-data-lake project-level: ❌ Would move 530-slot workload to 100-slot reservation
- Separate project with reservation: **$219/month** ✅ Chosen for cost control
- Status quo: $0 but delays continue

---

## Cross-Project Data Access: Easiest Implementation

### Recommended Approach: Dataset-Level IAM

**Why this is easiest:**

1. **Single grant command:**
```bash
bq add-iam-policy-binding \
  --member="serviceAccount:messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer" \
  narvar-data-lake:messaging
```

2. **No per-table management** - Automatically covers:
   - All existing tables in messaging dataset
   - New tables created in the future
   - All authorized views

3. **No network configuration** - BigQuery handles cross-project routing automatically

4. **No VPC peering** - BigQuery is a managed service, works across projects

5. **No data duplication** - Queries access source tables directly

**Alternative approaches (more complex):**
- ❌ Authorized views (requires creating views in new project - duplication)
- ❌ Table-level permissions (tedious, must update for each new table)
- ❌ Data transfer/replication (expensive, complex, data staleness)

---

## Admin Credentials Setup

### Approach 1: Grant Team Access via Group (RECOMMENDED)

```bash
# Grant data-eng@narvar.com group owner access
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="group:data-eng@narvar.com" \
  --role="roles/owner"

# Grant individual leads as well (for redundancy)
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="user:saurabh.shrivastava@narvar.com" \
  --role="roles/owner"

gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="user:julia.le@narvar.com" \
  --role="roles/owner"

gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="user:cezar.mihaila@narvar.com" \
  --role="roles/owner"

gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="user:eric.rops@narvar.com" \
  --role="roles/owner"
```

**Admins:** 
- **Group:** data-eng@narvar.com (Data Engineering team)
- **Individuals:** Saurabh Shrivastava, Julia Le, Cezar Mihaila, Eric Rops

**Pros:** Group provides easy team management, individual leads for redundancy  
**Cons:** None

---

### Approach 2: Similar to narvar-data-lake (Mirror Permissions)

```bash
# Check current narvar-data-lake admins
gcloud projects get-iam-policy narvar-data-lake \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/owner" \
  --format="value(bindings.members)"

# Copy the same users/groups to new project
# (Replace USER_EMAIL with actual emails from above)
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="user:USER_EMAIL" \
  --role="roles/owner"
```

**Pros:** Consistent with existing project  
**Cons:** May grant more access than needed

---

### Recommended Admin Roles

| Role | Who | Why |
|------|-----|-----|
| `roles/owner` | Saurabh, Julia, Cezar, Eric | Full project admin |
| `roles/owner` | data-eng@narvar.com group | Data Engineering team access |
| `roles/viewer` | Messaging team, SRE | Read-only monitoring access |
| `roles/iam.securityReviewer` | Security team | Audit access |

---

## Detailed Implementation Plan

### Day 1: Infrastructure Setup

**Morning (1-2 hours):**
- [ ] Create messaging-bq-dedicated project
- [ ] Link billing account
- [ ] Enable BigQuery API
- [ ] Assign project to messaging-dedicated reservation (API call)
- [ ] Grant existing service account jobUser permission on new project
- [ ] Grant admin access: Saurabh, Julia, Cezar, Eric + data-eng@narvar.com group
- [ ] Test that service account can run queries in new project

**Afternoon (1 hour):**
- [ ] Document configuration
- [ ] Create monitoring dashboard
- [ ] Coordinate with messaging team for staging deployment

---

### Day 2: Staging Deployment

**Morning (2 hours):**
- [ ] Update staging config: project_id = messaging-bq-dedicated
- [ ] Deploy to staging pods (rolling restart)
- [ ] Test notification history searches (10+ tests, 100+ queries)
- [ ] Verify all 10 tables accessible (cross-project access working)
- [ ] Check query performance (should be identical to production)
- [ ] Verify using messaging-dedicated reservation (not on-demand)
- [ ] Check queue times (<1 second)

**Afternoon (2 hours):**
- [ ] Soak test for 2-4 hours in staging
- [ ] Monitor for errors or permission issues
- [ ] Verify reservation autoscale during any peaks
- [ ] Get approval for production deployment from messaging team lead

---

### Day 3: Production Deployment

**Morning (1 hour):**
- [ ] Notify stakeholders (30-min warning)
- [ ] Update production config: project_id = messaging-bq-dedicated
- [ ] Rolling deployment (gradual pod update - zero downtime)
- [ ] Monitor first pod for 15 minutes
- [ ] Verify first pod queries using messaging-dedicated reservation
- [ ] Roll out to remaining pods

**Afternoon (2 hours):**
- [ ] Monitor every 15 minutes for 2 hours
- [ ] Verify queue times <1 second
- [ ] Check queries using messaging-dedicated reservation (not default)
- [ ] Verify no customer complaints
- [ ] Document deployment success

---

### Days 4-5: Validation & Cleanup

- [ ] Daily monitoring (queue times, reservation usage, costs)
- [ ] 48-hour soak test in production
- [ ] Document final configuration
- [ ] Update runbooks and architecture docs
- [ ] Update Jira DTPL-6903 as resolved
- [ ] Schedule 30-day cost review

---

## Cross-Project Table Access: Technical Details

### How BigQuery Cross-Project Queries Work

**Query from messaging-bq-dedicated project:**
```sql
SELECT * FROM `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug`
WHERE event_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);
```

**What happens:**
1. Query runs in `messaging-bq-dedicated` project (service account has jobUser permission)
2. BigQuery checks if service account has permission on `narvar-data-lake.messaging` dataset (it does - existing permissions)
3. If authorized, fetches data from source project
4. Returns results
5. **Billing:** Charges `messaging-bq-dedicated` project  
6. **Reservation:** Uses messaging-bq-dedicated's assignment (messaging-dedicated reservation)
7. **Slots:** 50 baseline + autoscale to 100

**No data leaves narvar-data-lake** - BigQuery handles routing internally

**Latency:** Identical to same-project queries (milliseconds overhead, negligible)

**Cost:** ~$219/month (reservation charges to messaging-bq-dedicated project billing)

---

### Tables Messaging Service Needs Access To

**From notify-automation-service code** ([NoFlakeQueryService.java](https://github.com/narvar/notify-automation-service/blob/d5019d7bdcd36e80b03befff899978f28a39b2de/src/main/java/com/narvar/automationservice/services/notificationreports/NoFlakeQueryService.java#L34)):

1. `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug`
2. `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug_V2`
3. `narvar-data-lake.messaging.pubsub_rules_engine_kafka`
4. `narvar-data-lake.messaging.pubsub_notification_service`
5. `narvar-data-lake.messaging.pubsub_pulsar_notification_bus`
6. (5 additional tables - need to check code for complete list)

**Grant strategy:** 
- **Dataset-level:** `roles/bigquery.dataViewer` on `narvar-data-lake:messaging` (covers all)
- **Benefit:** Automatically includes future tables

**Verify tables exist:**
```bash
# List all tables in messaging dataset
bq ls narvar-data-lake:messaging

# Verify service account can query each
# (Use test query from Step 2.2)
```

---

## Application Configuration Changes

### What Needs to Update

**Service:** notify-automation-service (Java backend)

**Configuration file/location:** 
- Likely: Kubernetes secret or environment variable
- Contains: Service account credentials JSON

**Change required:**
```diff
- OLD: messaging@narvar-data-lake.iam.gserviceaccount.com credentials
+ NEW: messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com credentials
```

**Code changes:** NONE
- BigQuery client library handles cross-project queries automatically
- Fully qualified table names (`project.dataset.table`) work identically

**Deployment method:**
- Update K8s secret with new service account key
- Rolling restart of pods (zero downtime)
- Monitor during rollout

---

## Rollback Plan

### If Issues During Production Deployment

**Rollback is simple: Switch back to old service account**

```bash
# Revert K8s secret to old service account
kubectl create secret generic bigquery-credentials \
  --from-file=key.json=/path/to/old-service-account-key.json \
  --dry-run=client -o yaml | kubectl apply -f -

# Rolling restart
kubectl rollout restart deployment/notify-automation-service

# Verify rollback
# Queries should resume using old account on default reservation
```

**Time to rollback:** 5 minutes

---

## What Messaging Team Needs to Do

### Summary for Messaging/App Team

**Changes required:** 
1. Update BigQuery client configuration to specify new project_id
2. **Ensure all table references use fully-qualified names** (project.dataset.table format)

**Impact:** 
- ✅ **No credential changes** - reuse existing service account
- ✅ Only BigQuery client project_id parameter + table name format
- ✅ Zero downtime deployment (rolling restart)
- ⚠️ **CRITICAL:** Must use `narvar-data-lake.messaging.table` (not `messaging.table`)

**Change is SIMPLER than credential swap, but requires code review for table references!**

### Step-by-Step for Messaging Team:

#### 1. Update BigQuery Client Configuration

**Location:** notify-automation-service - BigQuery client initialization

**File:** `src/main/java/com/narvar/automationservice/services/BigQueryService.java`

**Change:**
```diff
// When creating BigQuery client
BigQueryOptions.Builder optionsBuilder = BigQueryOptions.newBuilder()
-   .setProjectId("narvar-data-lake")  // OLD: queries billed to narvar-data-lake
+   .setProjectId("messaging-bq-dedicated")  // NEW: queries billed to messaging-bq-dedicated
    .setCredentials(credentials);
```

**OR if using environment variable:**
```diff
- BIGQUERY_PROJECT_ID=narvar-data-lake
+ BIGQUERY_PROJECT_ID=messaging-bq-dedicated
```

**Service account stays the same:**
- ✅ Keep using: `messaging@narvar-data-lake.iam.gserviceaccount.com`
- ✅ Same credentials JSON file
- ✅ No secret updates needed

**Table names stay the same:**
```java
// These remain UNCHANGED
"narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug"
"narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug_V2"
// etc.
```

---

#### 2. Deploy Configuration Change

**Deployment method:**
```bash
# Update config map or environment variable
kubectl set env deployment/notify-automation-service \
  BIGQUERY_PROJECT_ID=messaging-bq-dedicated \
  -n messaging

# Rolling restart automatically happens
# Or trigger manually:
kubectl rollout restart deployment/notify-automation-service -n messaging
```

---

#### 3. Update Table References to Fully-Qualified Names

**CRITICAL:** Queries must use `narvar-data-lake.messaging.table_name` format

**Code location:** notify-automation-service  
**Likely file:** NoFlakeQueryService.java

**Change all table references:**
```diff
- FROM messaging.pubsub_rules_engine_pulsar_debug
+ FROM `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug`

- FROM messaging.pubsub_rules_engine_pulsar_debug_V2
+ FROM `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug_V2`

// ... and all other messaging tables (10 total)
```

**Why required:**
- When project_id = messaging-bq-dedicated, BigQuery looks for tables in that project
- Table reference `messaging.table` becomes `messaging-bq-dedicated.messaging.table` (doesn't exist!)
- Must explicitly specify `narvar-data-lake.messaging.table` for cross-project

**Check all 10 tables** referenced in NoFlakeQueryService.java are updated.

---

#### 4. Verify in Staging First

**Before production - test with actual notification history query:**

```bash
# In staging environment, after deploying project_id change:

# Test the exact query pattern from DTPL-6903
# This should execute via messaging-bq-dedicated project, 
# access narvar-data-lake.messaging tables,
# and use messaging-dedicated reservation

# Example test (run from staging pod or use service account impersonation):
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
FROM `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug`
WHERE event_ts BETWEEN TIMESTAMP '2025-11-20T05:25:43' 
  AND TIMESTAMP '2025-11-22T00:10:35.448412' 
  AND retailer_moniker = 'jdsports-emea' 
  AND metric_name = 'NOTIFICATION_EVENT_NOT_TRIGGERED' 
  AND request_failure_code NOT IN ('103', '112') 
  AND upper(order_number) = '188072755'
LIMIT 10;
```

**Staging validation checklist:**
- [ ] Query executes without errors
- [ ] Returns expected data (notification events for order 188072755)
- [ ] Response time <5 seconds
- [ ] Test all 10 tables (each table should query successfully)
- [ ] No "table not found" errors (confirms fully-qualified names working)
- [ ] Check reservation usage (should be messaging-dedicated)
- [ ] Test 5-10 different orders to ensure pattern works

**Staging validation:** ✅ All tests pass → Proceed to production

---

#### 4. Production Deployment

**Recommended approach:** Rolling deployment (zero downtime)

1. Update production config (project_id = messaging-bq-dedicated)
2. Rolling restart pods (gradual, 1 pod at a time)
3. Monitor first pod for 15 minutes
4. Continue rollout to remaining pods
5. Monitor all pods for 1 hour post-deployment

**Monitoring during deployment:**
- Watch for errors in application logs
- Test notification history searches
- Verify no customer complaints
- Check queries using messaging-dedicated reservation

---

#### 5. Rollback (if needed)

**If any issues - revert project_id change:**
```bash
# Revert to old project_id
kubectl set env deployment/notify-automation-service \
  BIGQUERY_PROJECT_ID=narvar-data-lake \
  -n messaging

# Or update config map and restart
kubectl rollout restart deployment/notify-automation-service -n messaging
```

**Time to rollback:** 2 minutes (simpler than credential swap!)

---

### Testing Checklist for Messaging Team

**Staging tests:**
- [ ] Notification history search by order number works
- [ ] All 10 tables return data correctly
- [ ] Response time <5 seconds
- [ ] No errors in application logs
- [ ] Query results match production (data consistency)

**Production tests (post-deployment):**
- [ ] First pod: Monitor for 15 minutes, no errors
- [ ] All pods: Monitor for 1 hour
- [ ] User acceptance: Test 5-10 real searches
- [ ] No customer complaints
- [ ] Application logs clean

---

### What Does NOT Change

**No changes needed for:**
- ✅ **Service account credentials** (keep using messaging@narvar-data-lake)
- ✅ **Secrets/credentials** (no K8s secret updates)
- ✅ Query logic and WHERE clauses (unchanged)
- ✅ API endpoints (no changes)
- ✅ User-facing features (transparent to end users)

**What MUST change:**
- ⚠️ **BigQuery client project_id:** `narvar-data-lake` → `messaging-bq-dedicated`
- ⚠️ **Table references:** Must use fully-qualified format:
  - ❌ **Wrong:** `FROM messaging.pubsub_rules_engine_pulsar_debug`
  - ✅ **Correct:** `FROM narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug`
  - **All 10 tables** must include `narvar-data-lake.` prefix

---

## Cost Comparison: All Options

| Option | Monthly Cost | Setup Time | Complexity | Impact |
|--------|-------------|------------|------------|--------|
| **Separate project (with reservation)** | **$219** | 3-5 days | Medium | App changes |
| Project-level assignment | ❌ Not viable | - | - | Would move 530-slot workload to 100-slot reservation |
| Status quo | $0 | 0 | None | Delays continue |

**Winner: Separate project with reservation** - Achieves isolation with cost control ($219/month predictable)

---

## Risk Assessment

### Risk 1: Cross-Project Permission Issues

**Probability:** Low  
**Mitigation:** Test thoroughly in staging

### Risk 2: Application Deployment Issues

**Probability:** Low  
**Mitigation:** Rolling deployment, keep old credentials for rollback

### Risk 3: Cost Higher Than Expected

**Probability:** Low  
**Mitigation:** Monitor daily, set budget alerts at $50/month

### Risk 4: Query Latency Change

**Probability:** Very Low  
**Mitigation:** Cross-project queries have negligible overhead (<1ms)

---

## Success Metrics

**Performance:**
- P95 queue time: <1 second
- P95 execution time: <3 seconds (unchanged)
- Cross-project query overhead: <100ms (negligible)

**Cost:**
- Fixed baseline: $146/month (50 slots)
- Autoscale: ~$73/month (when active during 9pm peaks)
- Total: ~$219/month (predictable)
- No daily monitoring needed (fixed cost)

**Reliability:**
- Error rate: <0.1%
- Cross-project access: 100% success rate
- Zero customer complaints

---

## Next Steps

### Today (Nov 24):
1. [ ] Get approval for separate project approach
2. [ ] Decide: Quick (dataset-level IAM) or granular (table-level)
3. [ ] Identify who needs admin access to new project

### Tomorrow (Nov 25):
4. [ ] Create messaging-bq-dedicated project
5. [ ] Assign project to messaging-dedicated reservation (API)
6. [ ] Grant messaging@narvar-data-lake jobUser permission on new project
7. [ ] Grant admin access: Saurabh, Julia, Cezar, Eric + data-eng@narvar.com
8. [ ] Test cross-project queries

### This Week:
9. [ ] Coordinate with messaging team for staging deployment
10. [ ] Messaging team: Update project_id in staging and test
11. [ ] Deploy to production with monitoring
12. [ ] Validate and close DTPL-6903

---

**Recommendation:** Proceed with separate project approach - achieves isolation with cost control (~$219/month via reservation) using existing service account (simpler than originally planned - no credential changes needed!).

