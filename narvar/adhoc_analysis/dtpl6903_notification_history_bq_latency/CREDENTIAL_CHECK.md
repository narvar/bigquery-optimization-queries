# Credential & Permission Check - Deployment Readiness

**User:** cezar.mihaila@narvar.com  
**Date:** November 24, 2025  
**Purpose:** Verify permissions to deploy on-demand capacity for messaging service

---

## ✅ Credentials Verified

**Active GCP Account:** `cezar.mihaila@narvar.com`

**Test Results:**

| Permission Test | Result | Notes |
|----------------|--------|-------|
| List BigQuery reservations | ✅ PASS | Can view bq-narvar-admin:US.default |
| View reservation details | ✅ PASS | Can see capacity (1,000 + 700 autoscale) |
| Get IAM policy | ❌ FAIL | No getIamPolicy permission on bq-narvar-admin |
| gcloud alpha bq commands | ⚠️ NOT AVAILABLE | Command not found in current gcloud version |

---

## ⚠️ Issue Identified: gcloud alpha bq reservations Commands Not Available

**Problem:** The `gcloud alpha bq reservations` command group doesn't exist in your gcloud installation.

**Commands that DON'T work:**
```bash
# These will fail:
gcloud alpha bq reservations assignments delete ...
gcloud alpha bq reservations assignments create ...
gcloud alpha bq reservations assignments list ...
```

---

## 🔧 Solutions: Alternative Approaches to Manage Reservations

### Option 1: Use GCP Console (Web UI) - RECOMMENDED

**This is the simplest and most reliable approach:**

#### To Remove Reservation Assignment (Enable On-Demand):

1. **Navigate to BigQuery Reservations:**
   - Go to: https://console.cloud.google.com/bigquery/admin/reservations?project=bq-narvar-admin
   - Or: GCP Console → BigQuery → Admin → Reservations

2. **Find the reservation:**
   - Select location: **US**
   - Click on: **default** reservation

3. **View Assignments tab:**
   - Click "Assignments" tab
   - Look for: `messaging@narvar-data-lake.iam.gserviceaccount.com`

4. **Delete the assignment:**
   - Click the ⋮ (three dots) next to the assignment
   - Select "Delete assignment"
   - Confirm

**Result:** Service account now uses on-demand slots

**Time:** 2-3 minutes (vs 1 minute command-line)

---

#### To Rollback (Re-assign to Reservation):

1. Go to: Reservations → default → Assignments tab
2. Click "+ Create Assignment"
3. Fill in:
   - **Assignment type:** Service account
   - **Service account:** `messaging@narvar-data-lake.iam.gserviceaccount.com`
   - **Job type:** Query (or leave default "All")
4. Click "Create"

**Result:** Service account back on reservation

**Time:** 1-2 minutes

---

### Option 2: Install/Update gcloud Components

**If you want command-line access:**

```bash
# Update gcloud components
gcloud components update

# Check if alpha bq reservations is now available
gcloud alpha bq --help 2>&1 | grep -i reservation
```

**However:** This may still not work if the reservation management commands are region-specific or require special alpha access.

**My recommendation:** Use GCP Console instead - it's faster and more reliable.

---

### Option 3: Use BigQuery API via curl (Advanced)

**If you absolutely need command-line:**

```bash
# Get access token
TOKEN=$(gcloud auth print-access-token)

# List assignments for reservation
curl -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments"

# Delete assignment (would need assignment name from above)
# curl -X DELETE -H "Authorization: Bearer $TOKEN" \
#   "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments/{ASSIGNMENT_NAME}"
```

**This is complex** - I recommend GCP Console instead.

---

## ✅ Permissions You DO Have

**Based on successful commands:**

1. **BigQuery Query Execution** ✅
   - Can run queries in narvar-data-lake project
   - Can access INFORMATION_SCHEMA
   - Can analyze job history

2. **BigQuery Reservation Viewing** ✅
   - Can list reservations in bq-narvar-admin
   - Can view reservation details (capacity, autoscale)
   - Can see configuration

**Permissions you might NOT have (to verify):**

3. **Reservation Assignment Management** ❓
   - Delete assignments (needed for deployment)
   - Create assignments (needed for rollback)
   - **Test this via GCP Console before deployment**

---

## 🔍 Permission Verification Steps

### Step 1: Check if You Can Manage Assignments via Console

**Do this NOW before deployment:**

1. Go to: https://console.cloud.google.com/bigquery/admin/reservations?project=bq-narvar-admin
2. Click on **default** reservation
3. Click **Assignments** tab
4. Try to find `messaging@narvar-data-lake.iam.gserviceaccount.com` in the list

**Check:**
- ✅ Can you see the assignments list?
- ✅ Can you see a ⋮ (three dots) menu next to assignments?
- ✅ When you click ⋮, do you see "Delete assignment" option?

**If NO to any of these:** You don't have reservation.admin permission - need to request it.

---

### Step 2: Verify Required IAM Roles

**Roles needed for this deployment:**

| Role | Permission | Why Needed | Have It? |
|------|-----------|------------|----------|
| `bigquery.admin` | Full BigQuery admin | Best option - has everything | ❓ Need to verify |
| `bigquery.resourceAdmin` | Manage reservations | Minimum needed for deployment | ❓ Need to verify |
| `bigquery.user` | Run queries | For monitoring/validation | ✅ YES (you run queries) |
| `resourcemanager.projectIamAdmin` | View IAM | Nice to have, not required | ❌ NO (getIamPolicy failed) |

**Critical role needed:** `bigquery.resourceAdmin` or `bigquery.admin` on project `bq-narvar-admin`

---

### Step 3: Check Your Permissions (Simple Test)

```bash
# Test if you can access reservation details
bq show --location=US \
  --reservation \
  --project_id=bq-narvar-admin \
  bq-narvar-admin:US.default

# If this works (we know it does), you can VIEW
# But can you EDIT? That's the question.
```

**To test EDIT permissions without making changes:**

Go to GCP Console → BigQuery → Reservations and try to:
- Click "Create Assignment" button
- If you see the form → You have edit permissions ✅
- If you see "Permission denied" → You need to request access ❌

---

## 🎯 Deployment Options Based on Your Permissions

### If You HAVE Reservation Admin Permissions:

**Use GCP Console (recommended):**
- Navigate to Reservations
- Delete the assignment
- Monitor using SQL queries
- 5-minute deployment

**Total time:** 10 minutes

---

### If You DON'T HAVE Reservation Admin Permissions:

**You'll need to:**

1. **Request permissions** from whoever manages `bq-narvar-admin` project:
   - Role needed: `bigquery.resourceAdmin`
   - On project: `bq-narvar-admin`
   - Or organization-level: `roles/bigquery.admin`

2. **OR - Ask someone who has permissions** to execute the deployment:
   - Data Platform team lead
   - BigQuery admin
   - Provide them with the deployment command from DEPLOYMENT_RUNBOOK.md

3. **OR - Use a Service Account with permissions:**
   - If there's an admin service account with reservation permissions
   - Authenticate as that account
   - Execute the deployment

---

## 🚦 Pre-Deployment Action Required

**BEFORE attempting deployment, please:**

### Test 1: Try to Access Assignments via Console

```
1. Open: https://console.cloud.google.com/bigquery/admin/reservations?project=bq-narvar-admin
2. Click: "default" reservation
3. Click: "Assignments" tab
4. Screenshot what you see and share with me
```

**Expected scenarios:**

**Scenario A:** You see assignments and can click ⋮ menu
- ✅ You have permissions - proceed with deployment

**Scenario B:** You see "Permission denied" or can't access
- ❌ Need to request `bigquery.resourceAdmin` role

**Scenario C:** You see assignments but no edit buttons
- ⚠️ View-only access - need edit permissions

---

### Test 2: Alternative - Try bq Command (May work even if gcloud doesn't)

```bash
# Check if bq CLI has reservation management
bq help 2>&1 | grep -i "reservation\|assignment"
```

**Note:** The `bq` command may have different capabilities than `gcloud`.

---

## 📋 Next Steps

**Right now, before proceeding:**

1. **Test GCP Console access** (5 minutes)
   - Can you see assignments?
   - Can you delete them?
   - Screenshot and confirm

2. **If you DON'T have access:**
   - Who manages bq-narvar-admin project in your org?
   - Request: `roles/bigquery.resourceAdmin` on `bq-narvar-admin`
   - Or: Ask them to execute the single deployment command

3. **If you DO have access:**
   - ✅ Ready to deploy via GCP Console
   - ✅ Use DEPLOYMENT_RUNBOOK.md steps
   - ✅ All monitoring queries work (you have bigquery.user)

---

## ✅ What We Know You CAN Do

Based on successful commands from Friday:

1. **Run BigQuery queries** ✅
2. **View reservation configuration** ✅
3. **Access INFORMATION_SCHEMA** ✅
4. **Execute monitoring queries** ✅
5. **View reservation capacity** ✅

**What's UNCERTAIN:**

6. **Delete reservation assignments** ❓ (needs testing)
7. **Create reservation assignments** ❓ (for rollback)

---

## 💡 Recommendation

**Test the GCP Console NOW:**

1. Open: https://console.cloud.google.com/bigquery/admin/reservations?project=bq-narvar-admin&location=US
2. Try to access the Assignments tab
3. Report back what you see

**If you have access:** We can deploy in 10 minutes via Console (safer than command-line anyway)

**If you don't have access:** We need to identify who has `bigquery.resourceAdmin` role and get their help (or request the role for you)

---

**Status:** ✅ RESOLVED - Console permissions verified, org-level assignment discovered

---

## ✅ Resolution: Org-Level Assignment Discovered

**Console test completed:** You can access Assignments tab and see assignments.

**Critical discovery:**
- Only **1 assignment** exists: `organizations/770066481180`
- Entire narvar.com organization → bq-narvar-admin:US.default
- messaging@narvar-data-lake inherits from this org-level assignment

**Implication:**
- Cannot simply "remove" messaging (it's not directly assigned)
- Must create service-account-specific assignment that **overrides** org-level
- Solution: Create dedicated 50-slot flex reservation ($146/month)

**See:** `DEPLOYMENT_RUNBOOK_FINAL.md` for complete deployment guide

**Future:** Coordinate org-level assignment refactoring to achieve on-demand ($27/month) - saves $119/month but requires org-wide coordination.

