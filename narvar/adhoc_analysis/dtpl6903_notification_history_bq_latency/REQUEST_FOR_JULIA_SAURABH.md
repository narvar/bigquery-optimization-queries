# Request for Julia / Saurabh - messaging-hub-bq-dedicated Project Creation

**From:** Cezar Mihaila  
**Date:** November 24, 2025  
**Purpose:** Need help creating messaging-hub-bq-dedicated GCP project for DTPL-6903 resolution

---

## Context (Brief)

We're creating a separate GCP project to isolate messaging BigQuery traffic and resolve the Notification History latency issue (DTPL-6903). I don't have `resourcemanager.projects.create` permission at the organization level.

---

## Option A: Create the Project for Me (QUICKEST - 5 minutes)

**Please run these commands:**

```bash
# Step 1: Create project
gcloud projects create messaging-hub-bq-dedicated \
  --name="Messaging BigQuery Dedicated" \
  --organization=770066481180 \
  --labels=purpose=bigquery-isolation,team=messaging

# Step 2: Grant Cezar owner access (so he can continue setup)
gcloud projects add-iam-policy-binding messaging-hub-bq-dedicated \
  --member="user:cezar.mihaila@narvar.com" \
  --role="roles/owner"

# Step 3: Verify project created
gcloud projects describe messaging-hub-bq-dedicated
```

**Expected output for Step 1:**
```
Create in progress for [https://cloudresourcemanager.googleapis.com/v1/projects/messaging-hub-bq-dedicated].
Waiting for [operations/cp...] to finish...done.
```

**Expected output for Step 2:**
```
Updated IAM policy for project [messaging-hub-bq-dedicated].
```

**That's it!** Once done, I can continue with the remaining setup steps.

---

## Option B: Grant Me Permission to Create Projects (LONG-TERM - 2 minutes)

**If you prefer I do this myself in the future:**

```bash
# Grant Cezar project creator role at organization level
gcloud organizations add-iam-policy-binding 770066481180 \
  --member="user:cezar.mihaila@narvar.com" \
  --role="roles/resourcemanager.projectCreator"

# Verify permission granted
gcloud organizations get-iam-policy 770066481180 \
  --flatten="bindings[].members" \
  --filter="bindings.members:cezar.mihaila" \
  --format="table(bindings.role)"
```

**Expected output:**
```
Updated IAM policy for organization [770066481180].
```

**Then I can create projects myself going forward.**

---

## Recommendation

**I suggest Option A** (create the project for me):
- ✅ Faster (5 minutes)
- ✅ Scoped permission (just this one project)
- ✅ Less security risk
- ✅ I can complete all other setup steps myself

**Option B is better if:**
- I'll be creating multiple projects regularly
- You want to delegate project creation to data engineering team

---

## What Happens After Project is Created

**I will complete these steps (no further help needed):**
1. Link billing account
2. Enable BigQuery API
3. Assign project to messaging-dedicated reservation
4. Grant service account permissions
5. Grant admin access to: Saurabh, Julia, Cezar, Eric + data-eng@narvar.com group
6. Test cross-project queries
7. Coordinate with messaging team for application deployment

**Total time:** ~2 hours for remaining setup

---

## Full Context

**Issue:** DTPL-6903 - Notification History 8-minute delays  
**Solution:** Separate project with dedicated 50-slot reservation (+ autoscale to 100)  
**Cost:** ~$219/month  
**Timeline:** 3-4 days total (Day 1: project setup, Days 2-3: app deployment)

**Documentation:** https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/SEPARATE_PROJECT_SOLUTION.md

---

**Please let me know which option you'd like to use, or if you have questions!**

Thanks,  
Cezar

