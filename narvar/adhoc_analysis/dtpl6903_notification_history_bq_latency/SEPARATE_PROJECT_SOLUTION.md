# Option A: Separate Project for Messaging - Implementation Guide

**Project Name:** `messaging-bq-dedicated`  
**Goal:** Isolate messaging BigQuery traffic to achieve on-demand pricing ($27/month)  
**Timeline:** 3-5 days  
**Cost:** $27/month (on-demand) vs $219/month (shared project reservation)

---

## Executive Summary

**Approach:** Create dedicated GCP project for messaging BigQuery operations

**Benefits:**
- ✅ Achieves original goal: On-demand slots at $27/month
- ✅ Complete isolation from other workloads
- ✅ No org-wide coordination needed
- ✅ Predictable, low cost

**Trade-offs:**
- ⚠️ Requires application changes (update service account credentials)
- ⚠️ Cross-project BigQuery access setup
- ⚠️ Testing required before production rollout
- ⚠️ Timeline: 3-5 days (not immediate)

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

#### Step 1.2: Create Service Account

```bash
# Create messaging service account in new project
gcloud iam service-accounts create messaging-bq \
  --display-name="Messaging BigQuery Service Account" \
  --description="Dedicated service account for notification history BigQuery queries" \
  --project=messaging-bq-dedicated

# Verify creation
gcloud iam service-accounts list --project=messaging-bq-dedicated
```

**Created:** `messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com`

---

### Phase 2: Grant Cross-Project Data Access (Day 1 - 1 hour)

**Goal:** Allow new service account to query messaging.* tables in narvar-data-lake

#### Step 2.1: Grant BigQuery Permissions

**Easiest approach: Dataset-level permissions**

```bash
# Grant BigQuery Data Viewer on messaging dataset
bq add-iam-policy-binding \
  --member="serviceAccount:messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer" \
  narvar-data-lake:messaging

# Grant BigQuery Job User in the NEW project (to run queries)
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="serviceAccount:messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"
```

**What this grants:**
- ✅ Read access to all tables in `narvar-data-lake.messaging` dataset
- ✅ Ability to run BigQuery jobs in `messaging-bq-dedicated` project
- ✅ Jobs will be billed to `messaging-bq-dedicated` (on-demand pricing)

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

#### Step 2.2: Verify Cross-Project Access

```bash
# Test query from new service account (you'll need the service account key)
# First, create and download key
gcloud iam service-accounts keys create ~/messaging-bq-key.json \
  --iam-account=messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com \
  --project=messaging-bq-dedicated

# Activate service account locally (for testing)
gcloud auth activate-service-account \
  --key-file=~/messaging-bq-key.json

# Test query to narvar-data-lake.messaging tables
bq query --use_legacy_sql=false --project_id=messaging-bq-dedicated "
SELECT COUNT(*) AS test_count
FROM \`narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug\`
WHERE event_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
LIMIT 1;
"

# Check which reservation was used
bq query --use_legacy_sql=false --project_id=messaging-bq-dedicated "
SELECT 
  reservation_id,
  COUNT(*) AS queries
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com'
GROUP BY reservation_id;
"
# Should show: reservation_id = NULL (on-demand)

# Switch back to your user account
gcloud auth login
```

**Expected results:**
- ✅ Query executes successfully
- ✅ Can read from narvar-data-lake.messaging tables
- ✅ reservation_id = NULL (using on-demand)
- ✅ Queue time <1 second

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

### Phase 4: Application Update (Day 2-3 - With App Team)

**Changes needed in notify-automation-service:**

#### Update Service Account Credentials

**File:** Service account configuration (Kubernetes secret or config file)

**Change:**
```diff
- Service Account: service-prod-messaging-pubsub@narvar-prod.iam.gserviceaccount.com
- OR: messaging@narvar-data-lake.iam.gserviceaccount.com
+ Service Account: messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com
```

**Steps:**
1. Generate new service account key (done in Step 2.2)
2. Store key in secrets manager (K8s secret, GCP Secret Manager, etc.)
3. Update application configuration to use new credentials
4. **NO code changes needed** - just credential swap

**BigQuery client code:** 
- Source: https://github.com/narvar/notify-automation-service/blob/master/src/main/java/com/narvar/automationservice/services/BigQueryService.java
- **No code changes needed** - BigQuery client automatically handles cross-project queries

**Table references stay the same:**
```java
// These stay UNCHANGED - fully qualified table names work cross-project
"narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug"
"narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug_V2"
// etc.
```

---

#### Testing Checklist

**Staging environment:**
1. Deploy new service account credentials to staging
2. Test notification history search (10 parallel queries)
3. Verify queries execute successfully
4. Check reservation_id = NULL (on-demand)
5. Verify queue times <1 second
6. Test rollback (switch back to old service account)

**Production deployment:**
1. Deploy during low-traffic window (early morning)
2. Monitor for 1 hour post-deployment
3. Verify no errors
4. Keep old service account credentials for 7 days (rollback insurance)

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

## Cost Analysis: Separate Project

### On-Demand Cost for Messaging Only

**Based on messaging traffic (7 days):**
- Queries: 93,315
- Data processed: 1.07 TB/week = 4.3 TB/month
- On-demand cost: 4.3 TB × $6.25/TB = **$27/month**

**Compared to other options:**
- narvar-data-lake project-level assignment: $146/month (50-slot flex, insufficient capacity)
- narvar-data-lake entire project on-demand: ~$500-800/month
- Separate project on-demand: **$27/month** ✅ Winner

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

### Approach 1: Grant Individual Users (Quick)

```bash
# Data Engineering leads
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="user:cezar.mihaila@narvar.com" \
  --role="roles/owner"

gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="user:eric.rops@narvar.com" \
  --role="roles/bigquery.admin"

# Add more team members as needed
```

**Pros:** Quick (5 minutes)  
**Cons:** Hard to manage as team changes

---

### Approach 2: Use Google Group (Best Practice)

```bash
# Requires Google Workspace Admin to create group
# Group: data-engineering-admins@narvar.com
# Members: Cezar, Eric, other team leads

# Grant group access to project
gcloud projects add-iam-policy-binding messaging-bq-dedicated \
  --member="group:data-engineering-admins@narvar.com" \
  --role="roles/owner"
```

**Pros:** Easy to manage over time, audit trail  
**Cons:** Requires group creation (may need IT/admin help)

---

### Approach 3: Similar to narvar-data-lake (Mirror Permissions)

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
| `roles/owner` | Cezar, Eric (Data Eng leads) | Full project admin |
| `roles/bigquery.admin` | Data Engineering team | Manage BigQuery resources |
| `roles/viewer` | Messaging team, SRE | Read-only monitoring access |
| `roles/iam.securityReviewer` | Security team | Audit access |

---

## Detailed Implementation Plan

### Day 1: Infrastructure Setup

**Morning (2-3 hours):**
- [ ] Create messaging-bq-dedicated project
- [ ] Link billing account
- [ ] Enable BigQuery API
- [ ] Create messaging-bq service account
- [ ] Grant cross-project data access (dataset-level IAM)
- [ ] Grant admin access to data engineering team
- [ ] Test cross-project query manually

**Afternoon (2 hours):**
- [ ] Generate service account key
- [ ] Store in GCP Secret Manager
- [ ] Document configuration
- [ ] Create monitoring dashboard

---

### Day 2: Staging Deployment

**Morning (2 hours):**
- [ ] Update staging environment with new service account
- [ ] Deploy to staging pods
- [ ] Test notification history searches (10+ tests)
- [ ] Verify all 10 tables accessible
- [ ] Check query performance (should be identical)
- [ ] Verify using on-demand (reservation_id = NULL)

**Afternoon (2 hours):**
- [ ] Soak test for 2-4 hours
- [ ] Monitor for errors
- [ ] Check cost projection
- [ ] Get approval for production deployment

---

### Day 3: Production Deployment

**Morning (1 hour):**
- [ ] Notify stakeholders (30-min warning)
- [ ] Update production K8s secrets with new service account
- [ ] Rolling deployment (gradual pod update)
- [ ] Monitor first pod for 15 minutes
- [ ] Roll out to remaining pods

**Afternoon (3 hours):**
- [ ] Monitor every 15 minutes for 2 hours
- [ ] Verify no customer complaints
- [ ] Check cost tracking
- [ ] Document deployment

---

### Days 4-5: Validation & Cleanup

- [ ] Daily monitoring
- [ ] 48-hour soak test
- [ ] Remove old service account credentials (after confirming stability)
- [ ] Update runbooks and documentation
- [ ] Close DTPL-6903

---

## Cross-Project Table Access: Technical Details

### How BigQuery Cross-Project Queries Work

**Query from messaging-bq-dedicated project:**
```sql
SELECT * FROM `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug`
WHERE event_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);
```

**What happens:**
1. Query runs in `messaging-bq-dedicated` project
2. BigQuery checks if service account has permission on `narvar-data-lake.messaging` dataset
3. If authorized, fetches data from source project
4. Returns results
5. **Billing:** Charges `messaging-bq-dedicated` project (on-demand)
6. **Reservation:** Uses messaging-bq-dedicated's assignment (none = on-demand)

**No data leaves narvar-data-lake** - BigQuery handles routing internally

**Latency:** Identical to same-project queries (milliseconds overhead, negligible)

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

## Cost Comparison: All Options

| Option | Monthly Cost | Setup Time | Complexity | Impact |
|--------|-------------|------------|------------|--------|
| **Separate project (on-demand)** | **$27** | 3-5 days | Medium | App changes |
| Project-level assignment (flex) | $146 | 15 min | Low | Affects all services |
| narvar-data-lake on-demand | ~$600 | 1-2 weeks | High | Org-wide |
| Status quo | $0 | 0 | None | Delays continue |

**Winner: Separate project** - Best cost/benefit for messaging isolation

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
- Daily cost: $0.90-$1.50
- Monthly cost: $27-$45
- Alert if exceeds $50/month

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
5. [ ] Set up service account and permissions
6. [ ] Test cross-project queries
7. [ ] Generate and secure service account key

### This Week:
8. [ ] Deploy to staging environment
9. [ ] Coordinate with messaging/app team for production deployment
10. [ ] Deploy to production with monitoring
11. [ ] Validate and close DTPL-6903

---

**Recommendation:** Proceed with Option A (separate project) - achieves original goal ($27/month on-demand) with manageable complexity.

