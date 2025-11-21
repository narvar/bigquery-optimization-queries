# DTPL-6903: Notification History Latency - Executive Summary

**Date:** November 21, 2025  
**Status:** 🔴 CRITICAL - Root cause identified, mitigation options ready  
**Impact:** Customer-facing notification history feature experiencing 8-minute delays

---

## Problem

Notification History feature (used by Lands' End and other retailers via Hub) experiencing severe delays:
- **8-minute wait times** before queries execute
- Started Nov 13, escalated Nov 18-21
- Affecting retailer experience (NT-1363 escalation from Lands' End)

---

## Root Cause ✅ CONFIRMED

**BigQuery reservation `bq-narvar-admin:US.default` is saturated.**

### Capacity Breakdown (Last 7 days):

| Service | Slot Consumption | Queries | Impact |
|---------|------------------|---------|--------|
| **Airflow ETL** | **46%** | 28,030 | Batch jobs monopolizing slots |
| **Metabase BI** | **31%** | 58,532 | Heavy BI load |
| Messaging (Notification History) | 10% | 87,383 | **Victim - experiencing delays** |
| analytics-api (Hub) | 1% | 62,005 | Also experiencing delays |
| n8n Shopify | 0.6% | 185,064 | Worst delays (19 min max) |
| All others | 11% | ~190,000 | Various services |

**Key Finding:** Airflow + Metabase consume 77% of all slots, starving interactive customer-facing services.

---

## Why Now? (Nov 13-14 onset)

Something changed around Nov 13 that pushed the reservation over capacity. Most likely:
1. New or modified Airflow DAG deployed
2. Metabase dashboard changes (58K queries/week is high)
3. n8n Shopify ingestion spike (185K queries/week)

**Action needed:** Review deployments/changes from Nov 13-14.

---

## Impact Scope

Not just Messaging - **all interactive services affected:**
- Messaging: max 558s (9 min) queue wait
- Metabase: max 633s (10 min) queue wait
- Looker: max 602s (10 min) queue wait
- n8n Shopify: max 1,139s (19 min) queue wait

**This is a platform-wide capacity crisis.**

---

## Immediate Mitigation Options

### Option A: Move Airflow to Separate Reservation ⭐ RECOMMENDED
- **Impact:** Frees up 46% of interactive capacity immediately
- **Timeline:** Can deploy today
- **Cost:** ~$3,000-$4,500/month
- **Risk:** Low - clean architectural separation

### Option B: Move Metabase to Separate Reservation
- **Impact:** Frees up 31% of interactive capacity
- **Timeline:** Can deploy today
- **Cost:** ~$2,250-$3,000/month
- **Risk:** Low

### Option C: Increase Current Reservation Capacity
- **Impact:** Band-aid solution
- **Timeline:** Can deploy today
- **Cost:** ~$3,000-$4,500/month additional
- **Risk:** Doesn't address root architectural issue

---

## Recommended Immediate Actions

### Today (Nov 21):
1. ✅ **Investigation complete** - Root cause confirmed (reservation saturation)
2. **Investigate Nov 13 changes** - What Airflow/Metabase/n8n changes occurred?
3. **Deploy Option A** - Move Airflow to separate ETL reservation
4. **Set up monitoring** - Alert on P95 queue times >30s

### Next Week:
5. Review Metabase query patterns (58K queries/week seems high)
6. Consider moving Metabase to separate BI reservation (Option B)
7. Implement permanent monitoring dashboard

---

## Long-term Architecture Recommendation

**Separate reservations by workload type:**

1. **Interactive** (`bq-narvar-interactive:US`) - 200 slots
   - Messaging (notification history)
   - analytics-api (Hub real-time queries)
   - Human ad-hoc queries
   - **SLA:** P95 <5 seconds

2. **ETL/Batch** (`bq-narvar-etl:US`) - 300 slots
   - Airflow DAGs
   - Scheduled data pipelines
   - **SLA:** Best effort

3. **BI/Analytics** (`bq-narvar-bi:US`) - 150 slots
   - Metabase dashboards
   - Looker reports
   - **SLA:** P95 <30 seconds

**Total Cost:** ~$9,750/month (650 slots)  
**Benefit:** Guaranteed SLAs for each workload type, no cross-contamination

---

## Business Impact

- **Current:** Retailers experiencing 8-minute delays for notification history lookups
- **Post-Option A:** Delays reduced to <5 seconds P95
- **Revenue impact:** Customer satisfaction issue, potential churn risk

---

## Questions?

Contact: Cezar Mihaila (Data Engineering)  
Investigation details: `FINDINGS.md`  
SQL queries: `queries/` folder (7 analysis queries, $1.62 cost)

---

**Next Update:** After Nov 13 change investigation complete

