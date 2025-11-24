# DTPL-6903: Notification History Latency - Executive Summary

**Date:** November 21, 2025 (Updated: November 24, 2025)  
**Status:** 🔴 CRITICAL - Root cause identified, deployment ready  
**Impact:** Customer-facing notification history feature experiencing 8-minute delays

> 📋 **Deployment Guide:** See [`DEPLOYMENT_RUNBOOK_FINAL.md`](DEPLOYMENT_RUNBOOK_FINAL.md) for complete deployment steps (updated with org-level assignment solution)

> ⚠️ **Update (Nov 24):** Discovery of org-level assignment changes cost from $27/month (on-demand) to $146/month (50-slot flex). On-demand requires org-wide refactoring (future project).

---

## Executive Summary (For Internal & External Communication)

**Problem:** The Notification History feature, used by retailers including Lands' End to search notification details by order number, is experiencing significant delays of up to 8-9 minutes. Investigation confirms the queries themselves are well-optimized and execute in 1-2 seconds, but are waiting 8+ minutes for database processing capacity due to shared infrastructure saturation. This issue started November 13th and has escalated, with peak delays occurring during overnight and morning hours (midnight-9am PST). The delays are caused by competing batch data processing and analytics workloads monopolizing shared database resources, leaving insufficient capacity for customer-facing interactive features.

**Solution:** We are implementing a dedicated database capacity solution specifically for the Notification History feature to guarantee immediate resource availability and sub-second response times. This involves configuring the messaging service to use dedicated on-demand database capacity (~$30-60/month estimated cost) or a small reserved capacity allocation, completely isolated from batch processing workloads. Implementation timeline is 15 days: 5 days for specification and cost analysis, 5 days for pilot testing, and 5 days for production validation. As an interim measure, we are also separating batch data processing to different infrastructure to free up 46% of current shared capacity. This will restore the Notification History feature to its expected performance level of <5 seconds end-to-end response time.

---

## Table of Contents

1. [Problem](#problem)
2. [The Issue in One Picture](#the-issue-in-one-picture)
3. [Example: Real Query with 8-Minute Delay](#example-real-query-with-8-minute-delay)
4. [Root Cause](#root-cause-confirmed)
5. [Why Now?](#why-now-nov-13-14-onset)
6. [Impact Scope](#impact-scope)
7. [Immediate Mitigation Options](#immediate-mitigation-options)
8. [Recommended Immediate Actions](#recommended-immediate-actions)
9. [Long-term Solution](#long-term-solution-on-demand-slots-for-interactive-workloads)
10. [Business Impact](#business-impact)

---

## Problem

Notification History feature (used by Lands' End and other retailers via Hub) experiencing severe delays:
- **8-minute wait times** before queries execute
- Started Nov 13, escalated Nov 18-21
- Affecting retailer experience (NT-1363 escalation from Lands' End)

---

## The Issue in One Picture

```
User Experience (Nov 21, 8am):
┌──────────────────────────────────────────────────────────────────┐
│ TOTAL DELAY: 9 minutes 3 seconds (558s)                         │
│                                                                  │
│ ████████████████████████████████████████████████████ ■          │
│ ↑                                                     ↑          │
│ Queue Wait: 8 min 58 sec (99.6%)               Execution: 2s    │
│                                                     (0.4%)       │
└──────────────────────────────────────────────────────────────────┘
```

**The queries are fast (2s). The problem is waiting for available slots (558s).**

---

## Example: Real Query with 8-Minute Delay

**Job ID:** `job_x_RnGlaGvFGBYyzjA2b1ywgoDSz`

**Timing:**
- Creation time: 2025-11-21 13:48:35 PST
- Start time: 2025-11-21 13:56:07 PST  
- End time: 2025-11-21 13:56:08 PST
- **Queue wait:** ~8 minutes ⚠️
- **Actual execution:** 1 second ✅

**Resources:**
- Bytes scanned: 4.21 GB
- Slot milliseconds: 13,224
- Service account: `messaging@narvar-data-lake.iam.gserviceaccount.com`
- Reservation: `bq-narvar-admin:US.default`

**Query:**
```sql
SELECT metric_name, order_number, tracking_number,
  narvar_tracer_id, carrier_moniker, notification_event_type,
  event_ts, notification.channel, request_failure_code,
  request_failure_reason, '' as status_code, dedupe_key,
  estimated_delivery_date, '' as data_available_date_time 
FROM messaging.pubsub_rules_engine_pulsar_debug 
WHERE event_ts BETWEEN TIMESTAMP '2025-11-20T05:25:43' 
  AND TIMESTAMP '2025-11-22T00:10:35.448412' 
  AND retailer_moniker = 'jdsports-emea' 
  AND metric_name = 'NOTIFICATION_EVENT_NOT_TRIGGERED' 
  AND request_failure_code NOT IN ('103', '112') 
  AND upper(order_number) = '188072755'
```

**Analysis:** This is a well-optimized, focused query scanning only 4.21 GB. The problem is NOT the query - it's waiting 480 seconds (8 minutes) to get BigQuery slots.

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

### Friday Nov 21:
1. ✅ **Investigation complete** - Root cause confirmed (reservation saturation)
2. ✅ **Choke points identified** - n8n Shopify causes 88% of notification history delays
3. ✅ **Planning complete** - TRD created with deployment guide

### Monday Nov 24:
4. ✅ **Org-level assignment discovered** - Entire narvar.com org uses default reservation
5. ✅ **Solution updated** - 50-slot flex reservation (on-demand not achievable)
6. ✅ **Deployment runbook finalized** - Ready to deploy via API
7. **🔴 DEPLOY TODAY:** Create messaging-dedicated reservation ($146/month)

### Implementation Steps (Today - 15 minutes):
1. Pre-deployment: Capture baseline, backup config (5 min)
2. Create `messaging-dedicated` reservation (50 slots) - `bq mk` command (2 min)
3. Assign messaging service account via API (3 min)
4. Verify queries using new reservation (5 min)
5. Monitor every 5 minutes for first hour
6. Continue hourly monitoring for 24 hours

**Complete guide:** `DEPLOYMENT_RUNBOOK_FINAL.md`

### Future Optimization (Next Month):
8. **Coordinate org-level assignment refactoring**
   - Remove org-level assignment, create project-specific assignments
   - Enable true on-demand for messaging
   - **Savings:** $119/month ($146 flex → $27 on-demand)
   - **Timeline:** 1-2 weeks (requires Data Platform team coordination)

9. **Investigate n8n Shopify efficiency** - 6,631 slot-min/min overnight is extreme

10. Review Metabase query patterns (58K queries/week)

---

## Deployment Solution: Dedicated Flex Reservation

**⚠️ Updated Approach (Nov 24):** Due to org-level reservation assignment, using dedicated 50-slot flex reservation instead of on-demand.

> 📋 **For complete deployment steps, see:** [`DEPLOYMENT_RUNBOOK_FINAL.md`](DEPLOYMENT_RUNBOOK_FINAL.md)  
> Includes: pre-deployment backup, API deployment commands, monitoring scripts (5-min/hourly/daily), rollback procedures, and capacity right-sizing guide.

### Why Flex Reservation (Not On-Demand)?

**Discovery:** Entire narvar.com organization is assigned to `bq-narvar-admin:US.default` reservation.
- Cannot simply remove messaging from reservation (org-level inheritance)
- Must create service-account-specific assignment that overrides org-level
- Service-account assignments require a target reservation (cannot assign to "on-demand")
- **Solution:** Create dedicated 50-slot flex reservation

### Benefits of Dedicated Flex Reservation:

**Benefits:**
1. **Isolated capacity** - No competing with Airflow/Metabase/n8n
2. **Guaranteed slots** - 50 dedicated slots always available  
3. **Predictable cost** - Fixed $146/month (no usage variance)
4. **Eliminates queue delays** - <1 second P95 queue time
5. **Scalable** - Can adjust 30-100 slots based on actual usage

**Cost Analysis:**
- **Current cost:** $0 (included in shared org reservation, but experiencing 8-min delays)
- **50-slot Flex cost:** $146/month (fixed)
- **Actual capacity usage:** ~20-30 slots average (40-60% utilization)
- **Capacity headroom:** 30% buffer above peak usage
- **Future optimization:** Org-level refactoring → on-demand ($27/month, saves $119/month)

### Implementation Plan (UPDATED - Nov 24)

**Deployment Approach:** Create dedicated 50-slot flex reservation with service-account assignment

**Timeline:** 15 minutes deployment + 24 hours monitoring

**Steps:**
1. **Pre-deployment (5 min):** Capture baseline, backup config, create rollback script
2. **Create reservation (2 min):** `bq mk` command for 50-slot flex
3. **Assign service account (3 min):** API call to create service-account assignment
4. **Verify (5 min):** Confirm queries using new reservation, queue times <1s

**Complete deployment guide:** See `DEPLOYMENT_RUNBOOK_FINAL.md`

**Why Not On-Demand ($27/month)?**
- Discovery: Entire narvar.com organization assigned to default reservation
- Cannot remove individual service accounts from org-level assignment
- Must create service-account-specific assignment (requires target reservation)
- **Minimum achievable cost:** $146/month (50-slot flex)

**Future Optimization:**
- Coordinate with Data Platform team to refactor org-level assignment
- Enable true on-demand for messaging
- **Savings:** $119/month ($146 flex - $27 on-demand)
- **Timeline:** 1-2 weeks (org-wide coordination required)

**Key Planning Outcomes:**
- **Minimum capacity needed:** 50 slots (based on 20-30 avg, 35 peak)
- **Actual deployment cost:** $146/month (flex reservation)
- **Deployment complexity:** Low (API commands, 15 minutes)
- **Timeline:** 15 minutes deployment, 24 hours validation
- **Risk level:** Very low (isolated capacity, 2-minute rollback)

---

## Business Impact

- **Current:** Retailers experiencing 8-minute delays for notification history lookups
- **Post-Deployment:** Delays reduced to <1 second (dedicated 50-slot capacity)
- **Cost impact:** $146/month new cost (dedicated flex reservation)
- **Alternative considered:** On-demand ($27/month) requires org-wide refactoring (1-2 week project, $119/month savings)
- **Revenue impact:** Customer satisfaction issue resolved, eliminates churn risk from poor UX
- **SLA improvement:** 99.6% reduction in queue wait time (558s → <2s)

---

## Questions?

Contact: Cezar Mihaila (Data Engineering)  
Investigation details: `FINDINGS.md`, `CHOKE_POINTS_ANALYSIS.md`  
SQL queries: `queries/` folder (9 analysis queries, $1.85 cost)

---

## Related Documents

### Analysis & Root Cause:
- **FINDINGS.md** - Comprehensive root cause analysis with detailed data
- **CHOKE_POINTS_ANALYSIS.md** - 10-minute period analysis identifying n8n Shopify as primary culprit during delays
- **README.md** - Investigation overview and file structure

### Implementation Planning:
- **DEPLOYMENT_RUNBOOK_FINAL.md** ⭐ **CURRENT - Complete Deployment Guide (Nov 24)**
  - **Based on:** Org-level assignment discovery
  - **Solution:** 50-slot flex reservation ($146/month)
  - **Timeline:** 15 minutes deployment + 24 hours monitoring
  - **Deployment:** API commands (curl) with pre-deployment backup
  - **Monitoring:** 5-min/hourly/daily scripts included
  - **Rollback:** 2-minute procedure via API
  - **Capacity optimization:** Right-sizing guide (30-100 slots)
  
- **ORG_LEVEL_ASSIGNMENT_SOLUTION.md** - Discovery and Analysis
  - Why on-demand not achievable (org-level inheritance)
  - Service-account assignment hierarchy
  - Future path to $27/month on-demand (org-wide refactoring)

- **MESSAGING_CAPACITY_PLANNING.md** - Original TRD (Reference)
  - Capacity calculations and analysis (still valid)
  - Updated with org-level discovery note
  - Pricing comparison (updated: flex $146/month is minimum)
  
- **CLI_DEPLOYMENT_GUIDE.md** - API Command Reference
  - BigQuery Reservation API via curl
  - Used due to gcloud alpha commands unavailable

- **CREDENTIAL_CHECK.md** - Permission Verification
  - Confirmed: Can use Console and API
  - Resolution: Use API for deployment

### Supporting Data:
- **queries/** - All SQL analysis queries (validated and executed)
- **results/** - Query output data (CSV and JSON formats)

---

**Next Update:** After on-demand slot architecture is specified and approved

