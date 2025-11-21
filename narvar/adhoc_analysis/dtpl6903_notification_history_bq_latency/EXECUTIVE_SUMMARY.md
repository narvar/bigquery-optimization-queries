# DTPL-6903: Notification History Latency - Executive Summary

**Date:** November 21, 2025  
**Status:** 🔴 CRITICAL - Root cause identified, mitigation options ready  
**Impact:** Customer-facing notification history feature experiencing 8-minute delays

---

## Executive Summary (For Internal & External Communication)

**Problem:** The Notification History feature, used by retailers including Lands' End to search notification details by order number, is experiencing significant delays of up to 8-9 minutes. Investigation confirms the queries themselves are well-optimized and execute in 1-2 seconds, but are waiting 8+ minutes for database processing capacity due to shared infrastructure saturation. This issue started November 13th and has escalated, with peak delays occurring during overnight and morning hours (midnight-9am PST). The delays are caused by competing batch data processing and analytics workloads monopolizing shared database resources, leaving insufficient capacity for customer-facing interactive features.

**Solution:** We are implementing a dedicated database capacity solution specifically for the Notification History feature to guarantee immediate resource availability and sub-second response times. This involves configuring the messaging service to use dedicated on-demand database capacity (~$30-60/month estimated cost) or a small reserved capacity allocation, completely isolated from batch processing workloads. Implementation timeline is 3 weeks: 1 week for specification and cost analysis, 1 week for pilot testing, and 1 week for production rollout. As an interim measure, we are also separating batch data processing to different infrastructure to free up 46% of current shared capacity. This will restore the Notification History feature to its expected performance level of <5 seconds end-to-end response time.

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

### Today (Nov 21):
1. ✅ **Investigation complete** - Root cause confirmed (reservation saturation)
2. ✅ **Choke points identified** - n8n Shopify causes 88% of notification history delays
3. **Investigate Nov 13 changes** - What Airflow/Metabase/n8n changes occurred?
4. **Set up monitoring** - Alert on P95 queue times >30s

### Next Week (Priority Order):
5. **🔴 TOP PRIORITY: Spec on-demand slot solution for messaging**
   - Calculate 30-day historical usage and cost projection
   - Compare on-demand vs dedicated reservation economics
   - Get approval for approach
   - Timeline: 3-week implementation plan

6. **Deploy Option A** - Move Airflow to separate ETL reservation (if on-demand not ready)
   - Impact: Frees up 46% of reservation capacity
   - Cost: ~$3,000-$4,500/month

7. **Investigate n8n Shopify efficiency**
   - Why are queries consuming 6,631 slot-minutes/minute overnight?
   - Potential 50-80% reduction in n8n slot consumption

8. Review Metabase query patterns (58K queries/week seems high)

9. Implement permanent monitoring dashboard

---

## Long-term Solution: On-Demand Slots for Interactive Workloads

**Recommended Architecture:** Configure messaging service account to use **on-demand slots** instead of shared reservation.

### Why On-Demand for Messaging?

**Benefits:**
1. **Immediate availability** - No queue wait times
2. **Pay-per-use** - Only charged for actual slot consumption
3. **Elastic capacity** - Auto-scales with demand
4. **Guaranteed SLA** - Not impacted by other services
5. **No reservation management** - Simpler operational model

**Cost Analysis:**
- **Current cost (via reservation):** Included in $3,000-$4,500/month reservation, but experiencing delays
- **On-demand cost:** $6.25/TB scanned
- **Messaging consumption:** ~1.07 TB/week = ~4.3 TB/month
- **Expected cost:** ~**$27/month** for messaging queries
- **Alternative:** Could purchase dedicated 20-50 slot reservation for $300-$750/month

### Implementation Plan (TOP PRIORITY)

**Phase 1: Assessment & Specification (Week 1)**
1. Calculate exact on-demand cost based on 30-day historical usage
2. Determine capacity requirements:
   - Peak concurrent queries: ~10-15 per user search
   - Peak users: ~5-10 concurrent searches
   - Total slots needed: 50-150 concurrent slots
3. Compare on-demand vs small dedicated reservation costs
4. Document service account configuration changes

**Phase 2: Pilot (Week 2)**
1. Configure `messaging@narvar-data-lake.iam.gserviceaccount.com` to use on-demand slots
2. Monitor performance for 3-5 days:
   - Queue times (should be <1s)
   - Execution times (should remain ~2s)
   - Cost per day
3. Validate SLA achievement (P95 <5s total time)

**Phase 3: Production Rollout (Week 3)**
1. Full migration if pilot successful
2. Set up cost monitoring/alerting
3. Document new architecture
4. Update runbooks

**Decision Point:** On-demand vs dedicated reservation
- If usage <10 TB/month: **On-demand is cheaper** (~$62/month vs $300/month)
- If usage >20 TB/month: **Dedicated reservation is cheaper**

**Status:** ⏳ **Needs specification and approval** - This is a TOP PRIORITY work item

---

## Business Impact

- **Current:** Retailers experiencing 8-minute delays for notification history lookups
- **Post-On-Demand Solution:** Delays reduced to <1 second (immediate slot availability)
- **Post-Option A (Airflow separation):** Delays reduced to <5 seconds P95
- **Cost impact:** On-demand solution ~$27-$62/month vs status quo (included in reservation but poor SLA)
- **Revenue impact:** Customer satisfaction issue, potential churn risk from poor user experience

---

## Questions?

Contact: Cezar Mihaila (Data Engineering)  
Investigation details: `FINDINGS.md`, `CHOKE_POINTS_ANALYSIS.md`  
SQL queries: `queries/` folder (9 analysis queries, $1.85 cost)

---

## Related Documents

- **FINDINGS.md** - Comprehensive root cause analysis with detailed data
- **CHOKE_POINTS_ANALYSIS.md** - 10-minute period analysis identifying n8n Shopify as primary culprit during delays
- **README.md** - Investigation overview and file structure
- **queries/** - All SQL analysis queries (validated and executed)
- **results/** - Query output data (CSV and JSON formats)

---

**Next Update:** After on-demand slot architecture is specified and approved

