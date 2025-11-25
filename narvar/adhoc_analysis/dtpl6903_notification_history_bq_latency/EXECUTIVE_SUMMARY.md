# DTPL-6903: Notification History Latency - Executive Summary

**Date:** November 21, 2025 (Updated: November 25, 2025)  
**Status:** 🟡 IN PROGRESS - Solution designed, blocked on project creation permission  
**Impact:** Customer-facing notification history feature experiencing 8-minute delays

> 📋 **Implementation Guide:** See [`SEPARATE_PROJECT_SOLUTION.md`](SEPARATE_PROJECT_SOLUTION.md) for complete setup steps

> 📋 **Live Status Tracking:** See [`IMPLEMENTATION_LOG.md`](IMPLEMENTATION_LOG.md) for real-time progress

> ⚠️ **Current Blocker (Nov 25):** Project creation requires `resourcemanager.projects.create` permission. Awaiting Julia or Saurabh to create `messaging-hub-bq-dedicated` project. See [`REQUEST_FOR_JULIA_SAURABH.md`](REQUEST_FOR_JULIA_SAURABH.md) for copy-paste commands.

---

## Executive Summary (For Internal & External Communication)

**Problem:** The Notification History feature, used by retailers including Lands' End to search notification details by order number, is experiencing significant delays of up to 8-9 minutes. Investigation confirms the queries themselves are well-optimized and execute in 1-2 seconds, but are waiting 8+ minutes for database processing capacity due to shared infrastructure saturation. This issue started November 13th and has escalated, with peak delays occurring during overnight and morning hours (midnight-9am PST). The delays are caused by competing batch data processing and analytics workloads monopolizing shared database resources, leaving insufficient capacity for customer-facing interactive features.

**Solution:** We are implementing a dedicated BigQuery project (`messaging-hub-bq-dedicated`) with isolated capacity specifically for the Notification History feature. This approach creates a separate billing project assigned to a dedicated reservation with 50 baseline slots and autoscale capability to 100 slots, handling peak loads that occur daily at 9pm. The solution provides complete isolation from competing workloads while maintaining cost predictability at ~$219/month. Implementation requires creating the GCP project (currently blocked on permissions), configuring cross-project data access, and updating the messaging application to use the new project ID. Timeline is 3-5 days after project creation, with zero downtime deployment via rolling restart. This will restore the Notification History feature to its expected performance level of <3 seconds end-to-end response time, eliminating the 8-minute queue delays.

---

## Table of Contents

1. [Problem](#problem)
2. [The Issue in One Picture](#the-issue-in-one-picture)
3. [Example: Real Query with 8-Minute Delay](#example-real-query-with-8-minute-delay)
4. [Root Cause](#root-cause-confirmed)
5. [Query Pattern Analysis](#query-pattern-analysis-understanding-the-87k-messaging-queries)
6. [Solution Approach](#solution-approach-separate-project-with-dedicated-reservation)
7. [Implementation Status](#implementation-status)
8. [Deployment Solution](#deployment-solution-separate-project-with-dedicated-reservation)
9. [Business Impact](#business-impact)

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

**Key Finding:** Airflow + Metabase consume 77% of all slots, starving interactive customer-facing services. The problem started Nov 13 and affects multiple services (Metabase, Looker, n8n), indicating systemic capacity issues in the shared reservation.

---

## Query Pattern Analysis: Understanding the 87K Messaging Queries

### Are These Queries the Same or Different?

**Answer:** They are **STRUCTURALLY SIMILAR** but with **DIFFERENT PARAMETERS**

### Workload Characteristics

**Volume & Pattern:**
- **87,383 queries** over 7 days (12,483/day consistent)
- Each user search = **10 parallel queries** (one per messaging table)
- Generated by automated service: [NoFlakeQueryService.java](https://github.com/narvar/notify-automation-service/blob/d5019d7bdcd36e80b03befff899978f28a39b2de/src/main/java/com/narvar/automationservice/services/notificationreports/NoFlakeQueryService.java#L34)

**Query Structure (Same Across All Queries):**
- All follow **notification history lookup pattern** by order number
- Tables queried: `pubsub_rules_engine_pulsar_debug`, `pubsub_rules_engine_pulsar_debug_V2`, `pubsub_rules_engine_kafka`, etc.
- WHERE clause pattern: Filter by `event_ts`, `retailer_moniker`, `order_number`, `metric_name`
- Performance: **2.2s average execution**, 12.2 GB average scan (well-optimized)

**Query Parameters (Different Per Search):**
- Different **order numbers** (user-driven searches)
- Different **retailers** (jdsports-emea, landsend, etc.)
- Different **time windows** (event_ts range varies)
- Different **notification types** (metric_name varies)

### Critical Peak Pattern Discovery (Nov 24)

**Initial Analysis (Nov 21):** Average of 48 concurrent slots suggested 50-slot reservation sufficient

**Peak Pattern Discovery (Nov 24):** Hourly analysis revealed daily capacity spikes:

| Time Period | Concurrent Slots | Pattern | Frequency |
|-------------|------------------|---------|-----------|
| Daytime (8am-6pm) | 46-57 slots | Stable | Daily |
| **9pm spike** | **186-386 slots** | **Peak** | **Daily** |
| Overnight (2-4am) | 59-142 slots | Elevated | Daily |
| Average (24h) | 48 slots | Baseline | Constant |

**Key Discovery:** Daily **9pm spike of 186-386 slots** (4-8x average) would cause nightly failures with fixed 50-slot configuration

### Capacity Planning Decision

**For Capacity Planning:**
- **Concurrent execution pattern:** 10 parallel queries per search is the critical factor
- **Peak concurrency:** 5 simultaneous user searches = 50 concurrent queries
- **Query behavior:** Fast execution (2.2s avg), lightweight (12 GB scan avg)
- **Capacity requirement:** 50-100 slots needed

**Configuration Selected:**
- **50 baseline slots:** Handles 100% of daytime traffic (8am-6pm) efficiently
- **Autoscale +50 slots:** Activates during 9pm spike and overnight elevation
- **Total capacity:** 100 slots maximum
- **Coverage:** 99.4% (handles 166 of 168 hours without queuing)

**Rationale:**
- Queries are **similar enough** that capacity planning based on **concurrent execution** (48 avg, 228 peak) is the right approach
- The **50 baseline + autoscale 50** configuration handles the workload efficiently
- Cost-optimized: **~$219/month** ($146 baseline + ~$73 autoscale when active)
- Alternative rejected: Fixed 100 slots ($292/month) wastes 52% capacity during business hours

**Why This Matters for Saurabh:**
- Average-based planning (50 fixed slots) would have resulted in **nightly failures at 9pm**
- Peak pattern analysis prevented deployment of insufficient capacity
- Autoscale configuration provides cost efficiency while handling peak loads

---

## Solution Approach: Separate Project with Dedicated Reservation

### Selected Solution: messaging-hub-bq-dedicated Project

**Approach:** Create dedicated GCP project for messaging BigQuery operations with dedicated reservation

**Benefits:**
- ✅ Complete isolation from other workloads (Airflow, Metabase, n8n)
- ✅ Dedicated 50-slot baseline + autoscale to 100 slots (handles 9pm peak)
- ✅ Cost control: Fixed $146 baseline + predictable autoscale (~$73/month)
- ✅ Queue times <1 second guaranteed
- ✅ Reuses existing service account (simpler deployment)

**Trade-offs:**
- ⚠️ Requires application changes (project_id parameter + fully-qualified table names)
- ⚠️ Cross-project BigQuery access setup
- ⚠️ Testing required before production rollout
- ⚠️ Timeline: 3-5 days (not immediate)
- ⚠️ Cost: ~$219/month (vs $27 on-demand, but provides capacity guarantee)

**Why This Approach:**
- Cannot assign individual service accounts to reservations (API limitation discovered)
- Org-level assignment prevents simple on-demand solution
- Separate project provides clean isolation with cost control
- Application changes are minimal (no credential swap needed)

**Reference:** See `SEPARATE_PROJECT_SOLUTION.md` for complete implementation guide

---

## Implementation Status

### Completed (Nov 21-24):
1. ✅ **Investigation complete** - Root cause confirmed (reservation saturation)
2. ✅ **Choke points identified** - n8n Shopify causes 88% of notification history delays
3. ✅ **Peak analysis complete** - Daily 9pm spike requires autoscale capacity
4. ✅ **Solution designed** - Separate project approach with dedicated reservation
5. ✅ **messaging-dedicated reservation created** - 50 baseline + autoscale 50 slots

### In Progress (Nov 25):
6. 🟡 **Project creation** - Blocked on resourcemanager.projects.create permission
   - **Blocker:** Cezar does not have permission to create projects
   - **Resolution needed:** Julia or Saurabh must either:
     - Option A: Create `messaging-hub-bq-dedicated` project (5 minutes)
     - Option B: Grant Cezar project creator role
   - **See:** `REQUEST_FOR_JULIA_SAURABH.md` for copy-paste commands

### Remaining Steps (3-4 days after project created):
7. **Day 1:** Complete infrastructure setup
   - Link billing account
   - Enable BigQuery API
   - Assign project to messaging-dedicated reservation
   - Grant service account permissions
   - Test cross-project queries

8. **Days 2-3:** Messaging team staging and production deployment
   - Update project_id configuration
   - Update table references to fully-qualified names
   - Deploy to staging and test
   - Production rollout with monitoring

9. **Days 4-5:** Validation and documentation
   - Monitor queue times (<1 second target)
   - Verify cost (~$219/month)
   - Update Jira DTPL-6903 as resolved

**Implementation tracked in:** `IMPLEMENTATION_LOG.md`  
**Complete guide:** `SEPARATE_PROJECT_SOLUTION.md`

---

## Deployment Solution: Separate Project with Dedicated Reservation

**⚠️ Final Approach (Nov 24-25):** Create separate `messaging-hub-bq-dedicated` project assigned to dedicated reservation

> 📋 **For complete implementation guide, see:** [`SEPARATE_PROJECT_SOLUTION.md`](SEPARATE_PROJECT_SOLUTION.md)  
> Includes: project setup, cross-project permissions, application changes, testing checklist, rollback procedures

> 📋 **Implementation tracking:** [`IMPLEMENTATION_LOG.md`](IMPLEMENTATION_LOG.md)  
> Real-time status of each deployment step

### Why Separate Project (Not Service Account Assignment)?

**Discovery:** BigQuery Reservation API only supports project/folder/organization-level assignments
- Cannot assign individual service accounts to reservations (API limitation)
- Org-level assignment prevents clean on-demand solution
- **Solution:** Create dedicated project for messaging, assign entire project to reservation

### Architecture Overview

```
messaging-hub-bq-dedicated (new project)
├── Billing: Same as narvar-data-lake
├── Assigned to: messaging-dedicated reservation
│   ├── Baseline: 50 slots ($146/month)
│   └── Autoscale: +50 slots (~$73/month during peaks)
├── Service account: messaging@narvar-data-lake (reused, no new credentials)
└── Queries: Cross-project access to narvar-data-lake.messaging tables
```

### Benefits

1. **Complete isolation** - Dedicated capacity, no contention
2. **Cost control** - Predictable ~$219/month (capped)
3. **Handles peak loads** - 50 baseline + autoscale 50 = 100 slots total
4. **Simple credential management** - Reuses existing service account
5. **Clean architecture** - Separates billing and capacity from main project

### Implementation Requirements

**Infrastructure (Data Engineering):**
- Create GCP project: `messaging-hub-bq-dedicated`
- Assign to messaging-dedicated reservation (already created)
- Grant existing service account jobUser permission
- Grant admin access to data engineering team

**Application (Messaging Team):**
- Update project_id: `narvar-data-lake` → `messaging-hub-bq-dedicated`
- Update table references to fully-qualified names:
  - ❌ Wrong: `FROM messaging.pubsub_rules_engine_pulsar_debug`
  - ✅ Correct: `FROM narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug`
- No credential changes needed (same service account)

### Cost Analysis

**Monthly cost: ~$219**
- Baseline: $146/month (50 slots, always active)
- Autoscale: ~$73/month (50 slots, active during 9pm peak ~4 hours/day)
- Total capacity: 100 slots (handles 99.4% of traffic)

**vs Alternatives:**
- ❌ On-demand ($27/month): Not achievable due to API limitations
- ❌ Service account assignment: Not supported by BigQuery API
- ✅ Separate project: Achieves isolation with cost control

### Timeline

**Total: 3-5 days** (after project creation)
- Day 1: Infrastructure setup (2 hours)
- Days 2-3: Messaging team staging + production deployment
- Days 4-5: Validation and monitoring

**Current blocker:** Project creation requires `resourcemanager.projects.create` permission
- **Resolution:** Julia or Saurabh must create project (see `REQUEST_FOR_JULIA_SAURABH.md`)

---

## Business Impact

**Current State:**
- Retailers experiencing 8-minute delays for notification history lookups
- Customer-facing feature unusable during business hours
- Lands' End escalation (NT-1363) - potential churn risk

**Post-Deployment:**
- Delays reduced to <1 second (dedicated 100-slot capacity with autoscale)
- Query execution time unchanged: 2.2 seconds (queries are well-optimized)
- Total response time: <3 seconds end-to-end
- 99.6% reduction in queue wait time (558s → <1s)

**Cost Impact:**
- New cost: ~$219/month (dedicated project + reservation)
- Breakdown: $146 baseline + ~$73 autoscale (active ~4 hours/day for 9pm peak)
- Predictable monthly cost with capped maximum
- Isolated billing for messaging workload

**Timeline:**
- Current status: Blocked on project creation permission (Nov 25)
- Estimated completion: 3-5 days after project created
- Zero downtime deployment (rolling restart)

**Alternatives Considered:**
- ❌ On-demand ($27/month): Not achievable due to BigQuery API limitations
- ❌ Service account assignment: API does not support individual service accounts
- ✅ Separate project: Only viable approach for isolated capacity with cost control

**Customer Impact:**
- Eliminates churn risk from poor UX
- Restores Notification History feature to expected performance
- No changes visible to end users (transparent deployment)

---

## Questions?

Contact: Cezar Mihaila (Data Engineering)  
Investigation details: `FINDINGS.md`, `CHOKE_POINTS_ANALYSIS.md`  
SQL queries: `queries/` folder (9 analysis queries, $1.85 cost)

---

## Related Documents

### Analysis & Root Cause:
- **FINDINGS.md** - Comprehensive root cause analysis showing reservation saturation
- **CHOKE_POINTS_ANALYSIS.md** - 10-minute period analysis identifying n8n Shopify impact
- **CAPACITY_ANALYSIS_SUMMARY.md** - Peak pattern discovery (9pm spike) and capacity justification
- **README.md** - Investigation overview and navigation guide

### Implementation Planning:
- **SEPARATE_PROJECT_SOLUTION.md** ⭐ **CURRENT - Complete Implementation Guide (Nov 24-25)**
  - **Solution:** Separate project approach with dedicated reservation
  - **Timeline:** 3-5 days (after project creation)
  - **Cost:** ~$219/month ($146 baseline + ~$73 autoscale)
  - **Infrastructure setup:** Project creation, reservation assignment, permissions
  - **Application changes:** project_id parameter + fully-qualified table names
  - **Testing:** Cross-project query validation, staging deployment checklist
  - **Rollback:** 2-minute procedure (revert project_id)
  
- **IMPLEMENTATION_LOG.md** ⭐ **Real-Time Status Tracking**
  - Step-by-step implementation progress
  - Current status: Blocked on Step 1 (project creation permission)
  - Each step has: commands, expected output, actual result, timestamp
  - Tracks Phase 1 (infrastructure), Phase 2 (staging), Phase 3 (production)

- **REQUEST_FOR_JULIA_SAURABH.md** - Project Creation Request
  - Copy-paste commands for org admins to create project
  - Resolves current blocker (resourcemanager.projects.create permission)

- **MESSAGING_CAPACITY_PLANNING.md** - Capacity Analysis Reference
  - Original capacity calculations (still valid)
  - Workload characteristics (87,383 queries, 8,040 slot-hours)
  - Peak pattern analysis methodology

### Supporting Data:
- **queries/** - 11 SQL analysis queries (validated and executed, $1.85 total cost)
- **results/** - Query output data (CSV and JSON formats including hourly_peak_slots.csv)

---

**Current Status (Nov 25):** Infrastructure setup blocked on project creation permission. Awaiting Julia or Saurabh to create `messaging-hub-bq-dedicated` project. All other steps ready to execute.

