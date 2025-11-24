# DEPLOYMENT BLOCKER - Cannot Assign Individual Service Accounts

**Date:** November 24, 2025, 2:32pm PST  
**Discovery:** BigQuery Reservation API limitation  
**Impact:** Original deployment approach not viable  
**Status:** 🔴 BLOCKED - Reassessing approach

---

## What Happened

### Attempted Deployment (Step 4):

**Goal:** Assign `messaging@narvar-data-lake.iam.gserviceaccount.com` to dedicated reservation

**Command attempted:**
```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -d '{"assignee": "projects/narvar-data-lake/serviceAccounts/messaging@..."}' \
  .../messaging-dedicated/assignments
```

**Result:** ❌ **API Error 400: Invalid Argument**

**Error message:**
```
Assignment.assignee has the wrong format. 
Format should be one of: projects/myproject, folders/123, organizations/456
```

---

## Critical Discovery

**BigQuery Reservation assignments can ONLY be made at:**
1. **Organization level** - `organizations/770066481180`
2. **Folder level** - `folders/folder-id`
3. **Project level** - `projects/project-id`

**Cannot assign:**
- ❌ Individual service accounts
- ❌ Individual users
- ❌ Groups

**This means:**
- To use `messaging-dedicated` reservation, we must assign the **entire narvar-data-lake PROJECT**
- This would move **ALL services** in narvar-data-lake to the 50-slot reservation

---

## Impact Analysis: narvar-data-lake Project Traffic

**Services that would be affected (last 7 days):**

| Service | Queries | Slot-Hours | % of Project |
|---------|---------|------------|--------------|
| **Airflow ETL** | 29,687 | **38,658** | **44%** |
| **Metabase BI** | 57,943 | **28,590** | **32%** |
| **messaging** | 93,315 | **6,650** | **7.5%** |
| analytics-api (Hub) | 64,746 | 1,068 | 1.2% |
| n8n Shopify | 243,564 | 715 | 0.8% |
| Looker | 18,123 | 367 | 0.4% |
| Human users (Cezar, Vijay, Eric, etc.) | ~2,500 | **12,500** | **14%** |
| **TOTAL** | **~512,000** | **~88,650** | **100%** |

**Capacity requirement for narvar-data-lake project:** ~**530 slots average** (88,650 slot-hours / 168 hours)

**Our reservation:** 50 slots (+50 autoscale = 100 max)

**Result:** ❌ **Massively insufficient** - would cause severe queue delays for ALL services

---

## Why Original Plan Failed

### Assumption (Incorrect):
- Individual service accounts can be assigned to reservations
- We can carve out just messaging from narvar-data-lake project

### Reality (Correct):
- Only project/folder/org-level assignments supported
- narvar-data-lake project has 88,650 slot-hours/week (530 concurrent slots)
- Our 100-slot reservation cannot handle this

### Rollback Action Taken:
- ✅ Deleted project assignment immediately
- ✅ Messaging back on `bq-narvar-admin:US.default` (org-level)
- ✅ No impact to production

---

## Next Steps: Three Options

### Option A: Create Separate Project for Messaging (RECOMMENDED)

**Approach:**
1. Create new GCP project: `messaging-bq-dedicated`
2. Create new service account: `messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com`
3. Grant permissions to access messaging.* tables in narvar-data-lake
4. Update notify-automation-service to use new service account
5. New project uses on-demand by default (not assigned to any reservation)

**Cost:** $27/month (on-demand for messaging traffic only)

**Pros:**
- ✅ Achieves original goal (on-demand at $27/month)
- ✅ Complete isolation
- ✅ No impact on other services

**Cons:**
- ❌ Requires application changes (new service account)
- ❌ Cross-project data access setup
- ❌ More complex (new project, IAM, testing)
- ❌ Timeline: 3-5 days (not today)

---

### Option B: Remove narvar-data-lake from Org Assignment

**Approach:**
1. Delete org-level assignment (organizations/770066481180)
2. Create project-specific assignments for ALL other projects
3. Leave narvar-data-lake unassigned (goes to on-demand)
4. All narvar-data-lake traffic (including messaging) uses on-demand

**Cost:** 
- narvar-data-lake on-demand: ~$500-800/month (88,650 slot-hours @ $6.25/TB)
- Need to calculate TB processed for accurate estimate

**Pros:**
- ✅ No application changes
- ✅ Simple for narvar-data-lake (just use on-demand)
- ✅ Entire project gets unlimited capacity

**Cons:**
- ❌ Affects ENTIRE organization
- ❌ High cost ($500-800/month vs $27 for just messaging)
- ❌ Requires coordination across all teams
- ❌ Timeline: 1-2 weeks minimum

---

### Option C: Accept Status Quo

**Approach:**
- Keep messaging on shared reservation
- Monitor for capacity saturation events
- Escalate to increase org reservation capacity when needed

**Cost:** $0 (included in existing reservation)

**Pros:**
- ✅ No changes required
- ✅ No costs
- ✅ Weekend data shows problem is currently dormant

**Cons:**
- ❌ Queue delays will return when saturation happens
- ❌ No guaranteed SLA for customer-facing feature
- ❌ Doesn't solve the root problem

---

## Recommended Path Forward

### Immediate (Today):
1. Document this blocker and findings
2. Delete the messaging-dedicated reservation (clean up)
3. Update team on blocker and options
4. Decision meeting: Which option to pursue?

### Short-term (This Week - if Option A approved):
1. Create messaging-bq-dedicated project
2. Set up cross-project data access
3. Test with new service account in staging
4. Deploy to production with app update

### Medium-term (Next Month - if Option B approved):
1. Audit all projects in narvar.com organization
2. Plan org-level assignment migration
3. Coordinate with all teams
4. Phased rollout

---

**Status:** 🔴 BLOCKED - Awaiting decision on which option to pursue

**Rollback complete:** ✅ System restored to pre-deployment state

**Reservation created:** `messaging-dedicated` (50 slots + autoscale 50) - can be deleted or repurposed

