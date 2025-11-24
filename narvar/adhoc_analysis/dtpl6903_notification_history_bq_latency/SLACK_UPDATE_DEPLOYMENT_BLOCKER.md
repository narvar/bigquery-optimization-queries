# Slack Update - DTPL-6903 Deployment Blocker

**Date:** November 24, 2025  
**Channel:** #data-engineering

---

## Message:

🔴 **DTPL-6903 Deployment Blocker Discovered**

**Attempted deployment:** Dedicated BigQuery capacity for messaging service to resolve Notification History latency

**Blocker discovered:** BigQuery Reservation API **only supports project/folder/org-level assignments**, not individual service accounts.

**Impact:**
- Cannot isolate just messaging@narvar-data-lake service account
- Assigning narvar-data-lake project would move ALL services (Airflow, Metabase, n8n, Looker, etc.) to 50-slot reservation
- narvar-data-lake project consumes ~530 concurrent slots - our 100-slot reservation is insufficient

**Rollback:** ✅ Assignment deleted, system restored to original state, no production impact

---

**Two viable options:**

**Option A: Create separate project for messaging** ⭐ RECOMMENDED
- New project: `messaging-bq-dedicated` 
- Uses existing `messaging-dedicated` reservation (50 + autoscale 50)
- Cost: ~$219/month (predictable, capped)
- Requires: Cross-project table access (simple) + app config change (credential swap only)
- Timeline: 3-5 days
- **Pros:** Isolation, cost control, handles 9pm peak
- **Cons:** Requires messaging team to update service account credentials

**Option B: Accept status quo**
- Monitor and escalate when saturation returns
- **Pros:** No changes
- **Cons:** Delays will return (problem currently dormant but will recur)

---

**Recommendation:** Option A (Separate Project with Existing Service Account)

**What messaging team needs to do:**
1. **Update BigQuery client:** Change `project_id` from `narvar-data-lake` to `messaging-bq-dedicated`
2. **Update table references:** Use fully-qualified names: `narvar-data-lake.messaging.table_name` (not `messaging.table_name`)
3. Deploy to staging and test (2-4 hours)
4. Deploy to production with rolling restart (zero downtime)

**Good news:**
- ✅ **No credential changes** - reuse existing messaging@narvar-data-lake service account
- ✅ **No secrets updates** - same K8s secrets
- ✅ **Just config + code review** - project_id parameter + table name format

**Timeline:** 3-4 days (Day 1: Data Eng setup, Days 2-3: Messaging team deploy/test)

---

**Next steps:**
1. Done: Document options and trade-offs
2. If Option A: Create messaging-bq-dedicated project and migrate

**Weekend data:** No latency issues Sat-Mon (problem currently dormant, not urgent)

**Full Plan** See full plan: https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/SEPARATE_PROJECT_SOLUTION.md


**Questions?** See full analysis: https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/DEPLOYMENT_BLOCKER_DISCOVERY.md

- Cezar

