# DTPL-6903: Notification History Latency - Executive Summary

**Date:** November 21, 2025 (Updated: November 25, 2025)  
**Status:** ⏸️ POSTPONED - Awaiting messaging team business justification  
**Impact:** Customer-facing notification history feature experiencing 8-minute delays

> 📋 **Critical Facts & Decision:** See [`CRITICAL_FACTS.md`](CRITICAL_FACTS.md) for verified costs, options comparison, and business justification questions

> 📋 **Live Status Tracking:** See [`IMPLEMENTATION_LOG.md`](IMPLEMENTATION_LOG.md) for current status

> ⏸️ **Decision (Nov 25):** Saurabh postponed deployment until messaging team justifies that ~$1,700/month cost is warranted. Project `messaging-hub-bq-dedicated` created but not configured. On-demand alternative at $27/month available but decision pending.

---

## Executive Summary (For Internal & External Communication)

**Problem:** The Notification History feature, used by retailers including Lands' End to search notification details by order number, is experiencing significant delays of up to 8-9 minutes. Investigation confirms the queries themselves are well-optimized and execute in 1-2 seconds, but are waiting 8+ minutes for database processing capacity due to shared infrastructure saturation. This issue started November 13th and has escalated, with peak delays occurring during overnight and morning hours (midnight-9am PST). The delays are caused by competing batch data processing and analytics workloads (Airflow 46%, Metabase 31%) monopolizing shared database resources, leaving insufficient capacity for customer-facing interactive features.

**Solution (Designed, Pending Approval):** A dedicated BigQuery project (`messaging-hub-bq-dedicated`) has been created to isolate messaging queries from the saturated shared reservation. Two cost options exist: (1) On-demand billing at ~$27/month for current usage with unlimited capacity, or (2) Flex reservation at ~$1,700/month for guaranteed capacity with autoscale. Implementation timeline is 3-4 days with zero downtime deployment. This will restore the Notification History feature to its expected performance level of <3 seconds end-to-end response time, eliminating the 8-minute queue delays.

**Current Status (Nov 25):** Deployment postponed by Saurabh. Messaging team must provide business justification demonstrating that resolving the 8-minute delays is worth the investment (~$1,700/month for flex reservation, or $27/month for on-demand). Decision pending on: (1) quantified business impact (churn risk, revenue), (2) customer escalation severity, (3) cost approval authority, and (4) which cost option ($27/month vs $1,700/month) is appropriate for the business need.

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

## Solution Approach: Separate Project with On-Demand Billing ⭐

### Selected Solution: messaging-hub-bq-dedicated Project (CREATED ✅)

**Approach:** Dedicated GCP project for messaging BigQuery operations using **on-demand billing** (no reservation)

**Cost Analysis:**
- **On-demand:** ~$27/month (4.3 TB × $6.25/TB) ⭐ **RECOMMENDED**
- **Flex reservation:** ~$1,700/month (50 baseline + autoscale 50)
- **Annual commitment:** ~$1,000/month (50 slots, 1-year lock-in)

**Benefits:**
- ✅ **Lowest cost:** $27/month (63x cheaper than alternatives)
- ✅ **Unlimited capacity:** No queue delays, auto-scales infinitely
- ✅ **Complete isolation:** Separate from Airflow/Metabase saturation
- ✅ **No commitment:** Pay only for usage
- ✅ **Simple setup:** No reservation management needed
- ✅ **Reuses existing service account:** No credential changes

**Implementation:**
- ⚠️ Requires application changes (project_id parameter + fully-qualified table names)
- ⚠️ Cross-project BigQuery access setup (simple permission grants)
- ⚠️ Testing required before production rollout
- ⚠️ Timeline: 3-4 days total

**Cost Management:**
- Monitor monthly scanned data volume
- If exceeds 24 TB/month (~$150): Consider switching to flex reservation
- Break-even: Would need 234 TB/month to justify $1,700 flex cost
- Current: 4.3 TB/month = 54x below break-even point

**Reference:** See `CRITICAL_FACTS.md` for detailed cost analysis and `SEPARATE_PROJECT_SOLUTION.md` for implementation guide

---

## Implementation Status

### ✅ Completed (Nov 21-25):
1. ✅ **Investigation complete** - Root cause confirmed (reservation saturation by Airflow 46% + Metabase 31%)
2. ✅ **Choke points identified** - n8n Shopify causes 88% of notification history delays during 8-9am window
3. ✅ **Peak analysis complete** - Daily 9pm spike (186-386 slots) documented
4. ✅ **Solution designed** - Separate project with two cost options (on-demand $27/month or flex $1,700/month)
5. ✅ **Project created** - `messaging-hub-bq-dedicated` (Cezar has owner permissions)
6. ✅ **Cost analysis completed** - Verified pricing, break-even analysis, options comparison

### ⏸️ Postponed (Nov 25):
**Decision by:** Saurabh (Director)  
**Reason:** Messaging team must justify business value vs cost

**Questions requiring answers:**
- What is the business impact of 8-minute delays? (quantified churn risk, revenue impact)
- How critical is the Lands' End escalation (NT-1363)?
- Who has budget authority to approve $27/month (on-demand) or $1,700/month (flex)?
- Is there business case for $20,400/year investment?

**Next step:** Messaging team provides business justification, then Saurabh approves cost option

### 📅 When Approved - Implementation Timeline:

**Day 1 (2 hours):** Infrastructure setup
   - Link billing account
   - Enable BigQuery API
   - Grant service account access
   - Test cross-project query
   - Grant admin access

**Days 2-3:** Messaging team deployment
   - Update project_id configuration
   - Update table references to fully-qualified names
   - Deploy to staging, test, then production

**Day 4:** Validation
   - Monitor queue times (<1 second expected)
   - Verify cost ($27/month on-demand or $1,700/month flex)
   - Close DTPL-6903

**Detailed tracking:** `IMPLEMENTATION_LOG.md`  
**Cost analysis & business questions:** `CRITICAL_FACTS.md`  
**Complete guide:** `SEPARATE_PROJECT_SOLUTION.md`

---

## Deployment Solution: Separate Project with On-Demand Billing ⭐

**✅ Final Approach (Nov 25):** Create separate `messaging-hub-bq-dedicated` project using **on-demand billing** (no reservation)

> 📋 **For detailed cost analysis and options, see:** [`CRITICAL_FACTS.md`](CRITICAL_FACTS.md)  
> Includes: verified pricing calculations, option comparisons, break-even analysis

> 📋 **For implementation steps, see:** [`SEPARATE_PROJECT_SOLUTION.md`](SEPARATE_PROJECT_SOLUTION.md)  
> Includes: project setup, cross-project permissions, application changes, testing checklist

> 📋 **Implementation tracking:** [`IMPLEMENTATION_LOG.md`](IMPLEMENTATION_LOG.md)  
> Real-time status of each deployment step

### Why Separate Project with On-Demand?

**Root cause:** narvar-data-lake project is assigned to saturated `bq-narvar-admin:US.default` reservation (org-level)
- Cannot assign individual service accounts to reservations (API limitation)
- **Solution:** Create dedicated project for messaging, leave it UNASSIGNED to use on-demand billing
- **Result:** Complete isolation at minimal cost

### Architecture Overview

```
messaging-hub-bq-dedicated (new project) ✅ CREATED
├── Billing: Same as narvar-data-lake
├── Reservation: NONE (uses on-demand billing)
│   ├── Cost: $6.25 per TB scanned
│   └── Current: 4.3 TB/month = $27/month
├── Capacity: Unlimited (auto-scales, no queue delays)
├── Service account: messaging@narvar-data-lake (reused, no new credentials)
└── Queries: Cross-project access to narvar-data-lake.messaging tables
```

### Benefits

1. **Lowest cost** - $27/month (vs $1,700 for flex reservation)
2. **Unlimited capacity** - No queue delays, scales automatically
3. **Complete isolation** - Separate from Airflow/Metabase saturation
4. **Simple credential management** - Reuses existing service account
5. **No commitment** - Pay only for usage, can add reservation later if needed

### Implementation Requirements

**Infrastructure (Data Engineering) - 2 hours:**
- ✅ Create GCP project: `messaging-hub-bq-dedicated` (DONE)
- Enable BigQuery API
- Grant existing service account jobUser permission on new project
- Grant data read access to messaging tables in narvar-data-lake
- Test cross-project query
- Grant admin access to Saurabh, Julia, Eric, data-eng team

**Application (Messaging Team) - 1-2 days:**
- Update project_id: `"narvar-data-lake"` → `"messaging-hub-bq-dedicated"`
- Update table references to fully-qualified names:
  - ❌ Wrong: `FROM messaging.pubsub_rules_engine_pulsar_debug`
  - ✅ Correct: ``FROM `narvar-data-lake.messaging.pubsub_rules_engine_pulsar_debug` ``
- No credential changes needed (same service account)
- Deploy to staging → test → production (rolling restart)

### Cost Analysis (CORRECTED)

**On-Demand (Recommended):**
```
Current: 4.3 TB/month × $6.25/TB = $27/month ($324/year)
If grows to 10 TB/month: $63/month
If grows to 24 TB/month: $150/month (still viable)
Break-even vs flex: 234 TB/month
```

**Alternative Options (if needed later):**
- **Flex reservation:** $1,700/month (50 baseline + autoscale 50) - Only if usage exceeds 24 TB/month
- **Annual commitment:** $1,000/month (50 slots, 1-year) - Only for very high stable volume

### Timeline

**Total: 3-4 days**
- ✅ Day 0: Project created (`messaging-hub-bq-dedicated`)
- 🔄 Day 1: Infrastructure setup (2 hours) - IN PROGRESS
- Days 2-3: Messaging team staging + production deployment
- Day 4: Validation and monitoring

**Status:** ✅ Project creation blocker resolved

---

## Business Impact & Justification Required

### Current State (Problem)
- Retailers experiencing 8-minute delays for notification history lookups
- Customer-facing feature degraded during business hours
- Lands' End escalation (NT-1363) - potential churn risk
- Root cause: Airflow (46%) + Metabase (31%) saturating shared reservation

### Expected Post-Deployment (Benefits)
- Queue delays eliminated: 558s → <1s (99.8% reduction)
- Query execution unchanged: ~2.2 seconds (queries are well-optimized)
- Total response time: <3 seconds end-to-end
- Unlimited capacity (no future saturation risk)

### Cost-Benefit Analysis (Nov 25)

**Option 1: On-Demand Billing - $27/month**
- Cost: 4.3 TB/month × $6.25/TB = **$27/month ($324/year)**
- Benefits: Unlimited capacity, complete isolation, no commitment
- Risk: Variable cost if usage spikes significantly (>24 TB/month)
- **Break-even:** Would need 54x usage increase to justify flex

**Option 2: Flex Reservation - $1,700/month**
- Cost: 50 baseline + 50 autoscale = **$1,700/month ($20,400/year)**
- Benefits: Guaranteed capacity, predictable cost ceiling, handles peaks
- Risk: Over-provisioned for current 4.3 TB/month usage (63x more expensive than on-demand)
- **Use case:** Only if need capacity guarantee or usage >24 TB/month

### Decision Required: Business Justification

**Saurabh's question:** Is resolving 8-minute delays worth the investment?

**Messaging team must provide:**

1. **Quantified business impact:**
   - How many retailer searches affected per day?
   - Customer churn risk quantified ($/year)?
   - Revenue impact if unresolved?
   - How many retailers affected beyond Lands' End?

2. **Escalation severity:**
   - NT-1363 (Lands' End) - how critical?
   - Timeline pressure? Contract renewal risk?
   - Impact on customer satisfaction scores?

3. **Cost approval:**
   - Is $27/month (on-demand) acceptable? If yes, approve immediately.
   - Is $1,700/month (flex) justified? Show ROI calculation.
   - Who has budget authority?

4. **Alternatives considered:**
   - Can we optimize further to reduce volume?
   - Can delays be tolerated during off-peak hours only?
   - Can we reduce query frequency?

### Implementation Status
- ⏸️ **Postponed (Nov 25):** Awaiting messaging team business justification
- ✅ **Project ready:** `messaging-hub-bq-dedicated` created, ready to configure
- 📋 **Timeline if approved:** 3-4 days to resolution (zero downtime)

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

