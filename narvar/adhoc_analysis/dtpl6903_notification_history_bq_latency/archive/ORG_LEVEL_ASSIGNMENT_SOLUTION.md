# Organization-Level Assignment - Solution for Messaging On-Demand

**Date:** November 24, 2025  
**Discovery:** Messaging service account inherits reservation from org-level assignment  
**Organization:** narvar.com (ID: 770066481180)

---

## 🔍 Current Situation

**What we discovered:**
- The `bq-narvar-admin:US.default` reservation has **only 1 assignment**
- Assignment is at: **organizations/770066481180** (entire narvar.com organization)
- **All projects** in narvar.com organization inherit this reservation
- **Including:** messaging@narvar-data-lake.iam.gserviceaccount.com

**Why this matters:**
- We cannot "remove" messaging from the reservation (it's not directly assigned)
- It inherits the reservation from the organization-level assignment
- To enable on-demand, we need to override the org-level assignment

---

## ✅ Solution: Create Dedicated Flex Reservation for Messaging

**Strategy:** Create a service-account-specific assignment that overrides the org-level default.

**BigQuery assignment hierarchy:**
```
Organization assignment (lowest priority)
    ↓
Project assignment (medium priority)
    ↓
Service Account assignment (HIGHEST priority - overrides above)
```

**Implementation:**
1. Create small flex reservation for messaging (50-100 slots)
2. Create service-account-specific assignment
3. This overrides the org-level assignment
4. Messaging uses dedicated capacity, isolated from Airflow/Metabase

---

## 📋 Deployment Steps (CLI)

### Step 1: Create Messaging Flex Reservation (5 minutes)

```bash
# Create 50-slot flex reservation
# Note: We're using flex ($146/month) not on-demand because we can't assign to "null"
bq mk \
  --location=US \
  --project_id=bq-narvar-admin \
  --reservation \
  --slots=50 \
  --ignore_idle_slots=false \
  --edition=STANDARD \
  messaging-dedicated
```

**Expected output:**
```
Reservation 'bq-narvar-admin:US.messaging-dedicated' successfully created.
```

**Cost:** $146/month (50 slots) - More than on-demand ($27), but necessary given org-level assignment

---

### Step 2: Assign Messaging Service Account to New Reservation

**Using API (since gcloud command not available):**

```bash
# Get token
TOKEN=$(gcloud auth print-access-token)

# Create service account assignment
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "assignee": "projects/narvar-data-lake/serviceAccounts/messaging@narvar-data-lake.iam.gserviceaccount.com",
    "jobType": "QUERY"
  }' \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments"
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

---

### Step 3: Wait and Verify

```bash
# Wait 60 seconds for propagation
echo "Waiting 60 seconds..."
sleep 60

# Verify messaging now uses the new reservation
bq query --use_legacy_sql=false "
SELECT
  job_id,
  creation_time,
  reservation_id,
  TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
ORDER BY creation_time DESC
LIMIT 5;
"
```

**Expected result:**
- `reservation_id` = `bq-narvar-admin:US.messaging-dedicated`
- `queue_sec` = 0-1 seconds (no contention with Airflow/Metabase)

---

## Alternative: Request narvar-data-lake Project Assignment

**If you want to use on-demand ($27/month) instead of flex ($146/month):**

**You need to:**
1. **Remove the org-level assignment** (organizations/770066481180)
2. **Create project-level assignments** for each project that needs the reservation
3. **Exclude narvar-data-lake** project (it will default to on-demand)

**Issue:** This affects the ENTIRE organization - requires:
- Approval from Data Platform team
- Coordinated rollout across all projects
- Risk of disrupting other services

**This is a larger initiative** - not suitable for quick deployment today.

---

## Cost Implications

### Comparison:

| Approach | Monthly Cost | Complexity | Timeline | Risk |
|----------|-------------|------------|----------|------|
| **Dedicated 50-slot Flex** | **$146** | Low | Today | Low |
| **On-demand (requires org change)** | $27 | High | 1-2 weeks | Medium-High |
| **Dedicated 100-slot Flex** | $292 | Low | Today | Low |

**Given the org-level assignment:**
- **On-demand ($27/month) is NOT achievable** without org-wide changes
- **Minimum cost is $146/month** (50-slot flex)
- This is still better than status quo (delays + shared contention)

---

## 🎯 Recommended Approach for Today

### Deploy 50-Slot Flex Reservation

**Steps:**
1. Create messaging-dedicated reservation (50 slots)
2. Assign messaging service account
3. Monitor performance
4. Right-size to 30-100 slots based on actual usage

**Timeline:** 15 minutes

**Cost:** $146/month (vs current $0 but with 558s delays)

**Benefit:**
- Isolated capacity (no Airflow/Metabase contention)
- Queue times <1 second
- Can deploy today
- No org-wide coordination needed

---

### Future: Pursue On-Demand ($27/month)

**Requires:**
1. Data Platform team meeting
2. Remove org-level assignment
3. Create project-specific assignments for all other projects
4. Exclude narvar-data-lake (goes to on-demand)

**Timeline:** 1-2 weeks (coordination across teams)

**Benefit:** Save $119/month ($146 flex - $27 on-demand)

---

## 📝 Updated Recommendation

**Today (Quick Fix):**
- Create 50-slot flex reservation for messaging ($146/month)
- Eliminates queue delays immediately
- No org-wide impact

**Next Month (Cost Optimization):**
- Work with Data Platform team on org-level assignment refactoring
- Switch to on-demand ($27/month)
- Saves $119/month

---

Would you like me to:
1. **Create the deployment script for 50-slot flex** (ready to execute today)?
2. **Document the org-level assignment refactoring plan** (for future cost optimization)?
3. **Both**?

The flex reservation solves the immediate problem (queue delays) but costs more than on-demand. The cost optimization is a follow-up project.
