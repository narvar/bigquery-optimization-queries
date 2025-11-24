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

**Three options to resolve:**

**Option A: Create separate project for messaging** (my recommendation)
- New project: `messaging-bq-dedicated`
- Uses on-demand ($27/month for messaging only)
- Requires: Cross-project table access + app config change
- Timeline: 3-5 days
- **Pros:** Achieves original goal, isolated, cheap
- **Cons:** Application changes required

**Option B: Remove org-level assignment (entire narvar-data-lake → on-demand)**
- Cost: ~$500-800/month for entire project
- Requires: Org-wide coordination
- Timeline: 1-2 weeks
- **Pros:** No app changes
- **Cons:** Expensive, affects whole org

**Option C: Accept status quo**
- Monitor and escalate when saturation returns
- **Pros:** No changes
- **Cons:** Doesn't solve problem

---

**Next steps:**
1. Today: Document options and trade-offs
2. This week: Decision meeting on which approach to pursue
3. If Option A: Create messaging-bq-dedicated project and migrate

**Weekend data:** No latency issues Sat-Mon (problem currently dormant, not urgent)

**Questions?** See full analysis: https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/DEPLOYMENT_BLOCKER_DISCOVERY.md

- Cezar

