# Messaging (Notification History) - Dedicated Capacity Planning & Implementation

**Date:** November 21, 2025  
**Author:** Cezar Mihaila  
**Status:** DRAFT - Technical Requirements Document  
**Purpose:** Plan dedicated BigQuery capacity for messaging service to eliminate queue delays

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Capacity Requirements](#capacity-requirements)
4. [Pricing Options Analysis](#pricing-options-analysis)
5. [Recommended Architecture](#recommended-architecture)
6. [Implementation Plan](#implementation-plan)
7. [Risks & Mitigation](#risks--mitigation)
8. [Cost-Benefit Analysis](#cost-benefit-analysis)
9. [Success Metrics](#success-metrics)

---

## Executive Summary

**Objective:** Provide dedicated, isolated BigQuery capacity for messaging service to guarantee <5 second P95 response times.

**⚠️ UPDATE (Nov 24):** Discovery of org-level reservation assignment changes approach.

**Recommended Solution:** **50-slot Flex Reservation** (only viable option given org-level assignment)

**Minimum Capacity Required:** 50-100 slots (based on peak concurrency analysis)

**Actual Cost:** 
- ~~On-demand: $27/month~~ (NOT achievable - org-level assignment blocks this)
- **50-slot Flex: $146/month** (minimum cost given organizational constraints)
- Future optimization: Org-level refactoring → on-demand ($27/month, saves $119/month)

**Implementation Timeline:** 15 minutes deployment (create reservation + assign service account)

**See:** `DEPLOYMENT_RUNBOOK_FINAL.md` for complete step-by-step guide based on org-level discovery.

---

## Current State Analysis

### Existing Reservation Configuration

**Reservation:** `bq-narvar-admin:US.default`
- **Project:** `bq-narvar-admin` (admin project for BigQuery capacity)
- **Base Slot Capacity:** 1,000 slots (committed)
- **Autoscale Max:** +700 slots (70% additional capacity)
- **Autoscale Current:** 700 slots (currently maxed out)
- **Total Active Capacity:** **1,700 slots** (base + autoscale)
- **Edition:** ENTERPRISE (with autoscaling features)
- **Ignore Idle Slots:** False
- **Created:** April 29, 2022
- **Last Updated:** October 31, 2025

**🚨 Critical Finding:** The reservation is running at **maximum autoscale capacity** (1,700 slots), confirming saturation.

**Analysis:**
```
Committed Base:     1,000 slots (always paid for)
Autoscale Maximum:  +700 slots (70% additional)
Current Autoscale:  +700 slots (MAXED OUT!)
─────────────────────────────────────────────
Total Active:       1,700 slots

Cost Breakdown:
- Base commitment: ~$700-1,000/month (annual enterprise pricing)
- Autoscale active: ~$500-700/month additional (for 700 extra slots)
- Total reservation cost: ~$1,200-1,700/month for all workloads
```

**Why this matters:**
1. The reservation is **constantly autoscaling to maximum** - a sign of chronic under-capacity
2. Even with 70% autoscale buffer, workloads still experience queue delays
3. Removing messaging (170 slots, 10%) will provide **minimal relief** to the shared reservation
4. This confirms on-demand is the right solution - messaging needs **isolated capacity**

### Workload Characteristics (Last 7 Days)

**Volume:**
- Total queries: 87,383
- Average per day: 12,483 queries
- Average per hour: 520 queries
- Average per minute: 8.7 queries

**Resource Consumption:**
- Total slot-hours: 8,040
- Average per query: 0.092 slot-hours (331 slot-seconds)
- Average execution time: 2.2 seconds
- Average bytes scanned per query: 12.2 GB (1.07 TB total / 87,383 queries)
- **Estimated average slots consumed:** ~170 slots (10% of 1,700-slot reservation)

**Query Pattern:**
- Each user search = 10 parallel queries (across 10 messaging tables)
- Average execution per query: 2.2 seconds
- Average queue wait (current): 1.3 seconds (normal), up to 558 seconds (saturated)

**Peak Patterns:**
- Peak hour: ~1,200 queries/hour (business hours 2-4pm)
- Peak minute: ~30 queries/minute
- Peak concurrent user searches: ~3-5 simultaneous searches
- Peak concurrent queries: 30-50 queries executing simultaneously

**Capacity Distribution (of 1,700 active slots):**
- Airflow ETL: ~782 slots (46%)
- Metabase BI: ~527 slots (31%)
- **Messaging: ~170 slots (10%)** ← Our workload
- Others: ~221 slots (13%)

---

## Capacity Requirements

### Minimum Capacity Calculation

#### Method 1: Peak Concurrency Analysis

**Assumptions:**
- Peak concurrent user searches: 5 simultaneous searches
- Queries per search: 10 parallel queries
- Peak concurrent queries: 50 queries
- Average execution time: 2.2 seconds per query
- Target: Queue time <1 second

**Slot calculation:**
```
Peak concurrent queries = 50
Execution time = 2.2 seconds
Slot-seconds per query = 331 (from actual data)
Effective slots per query = 331 / 2.2 = 150 slots

If queries were perfectly parallelized:
  50 queries * 150 slots = 7,500 slots (unrealistic peak)

More realistic (queries arrive over ~10 second window):
  Average concurrent queries = 50 / (10 / 2.2) = ~11 queries
  Required slots = 11 * 150 = 1,650 slots

Conservative estimate accounting for bursts:
  Minimum: 50-100 slots
  Comfortable: 100-200 slots
```

**RECOMMENDATION:** Start with **50-100 slots** and monitor.

#### Method 2: Percentile-Based Analysis

**Current slot consumption:**
- P50: ~50 slot-seconds per query (equivalent to ~23 slots for 2.2s query)
- P90: ~200 slot-seconds per query (equivalent to ~90 slots for 2.2s query)
- P99: ~800 slot-seconds per query (equivalent to ~360 slots for 2.2s query)

**For <1s queue time at P95 load:**
- Need capacity to handle P90 queries
- With 10 parallel queries per search: 90 slots * 10 = 900 slots (if all parallel)
- Realistically (queries staged): 100-200 slots

**RECOMMENDATION:** **50-100 slots minimum**, **100-200 slots for comfort**.

#### Method 3: Cost-Optimized Approach

**On-demand pricing:** $6.25/TB
**Current consumption:** 1.07 TB/week = 4.3 TB/month
**Cost:** $27/month (very cheap!)

**Conclusion:** Start with **on-demand (unlimited slots)**, monitor actual slot usage, then right-size.

---

## Pricing Options Analysis

### Option 1: On-Demand Slots (RECOMMENDED for Phase 1)

**How it works:**
- Pay $6.25 per TB scanned
- Unlimited slot availability (up to 2,000 slots per query)
- No reservation needed
- Instant availability

**Pros:**
- ✅ **Immediate availability** - No queue times ever
- ✅ **Zero upfront commitment** - Pay only for actual usage
- ✅ **Elastic capacity** - Auto-scales to demand
- ✅ **Simplest implementation** - Just change service account config
- ✅ **Very cheap for current volume** - $27-62/month vs $300+/month for reservation
- ✅ **No capacity planning risk** - Always have enough slots

**Cons:**
- ❌ **Cost unpredictable** - Spikes in usage = cost spikes
- ❌ **No cost ceiling** - Could get expensive if usage grows 10x
- ❌ **Pricing penalty** - 25x more expensive per TB than reservation ($6.25 vs $0.25/TB)
- ❌ **No slot guarantees** - Technically subject to availability (rare issue)

**Cost Analysis:**
```
Current: 1.07 TB/week = 4.3 TB/month
Cost: 4.3 TB * $6.25 = $26.88/month

If usage 2x: 8.6 TB * $6.25 = $53.75/month
If usage 5x: 21.5 TB * $6.25 = $134.38/month (still reasonable)
If usage 10x: 43 TB * $6.25 = $268.75/month (cheaper than flat reservation still!)

Break-even point: ~48 TB/month = $300 (50-slot flex reservation cost)
```

**RECOMMENDATION:** **Start here** - Most cost-effective for current volume, zero risk.

---

### Option 2: Flex Slots Reservation

**How it works:**
- Commit to minimum slots for 60 seconds minimum
- Can scale up/down with 60-second commitment
- Pay $0.04 per slot-hour (prorated by second)
- Can cancel anytime after 60 seconds

**Slot options:**
- 50 slots: $1,752/year = **$146/month**
- 100 slots: $3,504/year = **$292/month**
- 200 slots: $7,008/year = **$584/month**

**Pros:**
- ✅ **Predictable cost ceiling** - Known maximum monthly cost
- ✅ **Flexible scaling** - Can adjust capacity every 60 seconds
- ✅ **No long-term commitment** - Can cancel anytime
- ✅ **Better cost per TB** - ~$0.25/TB equivalent (at full utilization)
- ✅ **Guaranteed capacity** - Reserved slots always available

**Cons:**
- ❌ **Higher base cost** - $146-584/month even if unused
- ❌ **Requires capacity planning** - Need to size correctly
- ❌ **Overhead if under-utilized** - Pay for slots even if not fully used
- ❌ **More complex** - Need to manage reservation

**Cost Analysis:**
```
50 slots = $146/month baseline
Break-even vs on-demand: 23.4 TB/month ($146 / $6.25)

Current usage (4.3 TB/month):
  On-demand: $27/month ✅ Winner
  50-slot flex: $146/month
  Savings: $119/month with on-demand

If usage grows to 25 TB/month:
  On-demand: $156/month
  50-slot flex: $146/month ✅ Winner
  Savings: $10/month with flex

If usage grows to 50 TB/month:
  On-demand: $313/month
  50-slot flex: $146/month ✅ Winner
  Savings: $167/month with flex
```

**RECOMMENDATION:** **Phase 2 option** if on-demand costs exceed $150/month.

---

### Option 3: Annual/Monthly Commitment Reservation

**How it works:**
- Commit to slots for 1 year or 1 month
- Pay $0.02736 per slot-hour (1-year) or $0.0336 per slot-hour (1-month)
- Fixed capacity, cannot scale down during commitment

**Slot options (1-year commitment):**
- 50 slots: $1,199/year = **$100/month**
- 100 slots: $2,398/year = **$200/month**
- 200 slots: $4,796/year = **$400/month**

**Pros:**
- ✅ **Lowest cost per slot** - 31% cheaper than flex
- ✅ **Predictable budgeting** - Fixed annual cost
- ✅ **Guaranteed capacity** - Always available
- ✅ **Best for stable workloads** - Ideal if usage predictable

**Cons:**
- ❌ **Long commitment** - Locked in for 1 year
- ❌ **No flexibility** - Can't reduce if over-provisioned
- ❌ **Upfront cost risk** - Pay even if workload changes
- ❌ **Harder to justify** - Requires long-term capacity forecast

**Cost Analysis:**
```
100-slot annual commitment = $200/month
Break-even vs on-demand: 32 TB/month

Current usage (4.3 TB/month):
  On-demand: $27/month ✅ Winner
  100-slot annual: $200/month
  Over-spending: $173/month

Need 8x usage growth (34 TB/month) to justify annual commitment
```

**RECOMMENDATION:** **Not recommended** - Current volume too low to justify.

---

## Recommended Architecture

### Phase 1: On-Demand Slots (Days 1-4)

**Architecture:**

```
┌─────────────────────────────────────────────────────────┐
│ Messaging Service                                       │
│ (notify-automation-service)                             │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ Service Account:                                        │
│ messaging@narvar-data-lake.iam.gserviceaccount.com      │
│                                                         │
│ Configuration:                                          │
│ - Project: narvar-data-lake                            │
│ - Billing: narvar-data-lake (on-demand)               │
│ - Reservation: NONE (use on-demand)                    │
│ - Priority: INTERACTIVE                                │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ BigQuery On-Demand Capacity                             │
│ - Slots: Up to 2,000 per query (unlimited pool)       │
│ - Pricing: $6.25/TB scanned                            │
│ - Queue time: <1 second (effectively zero)             │
│ - Isolation: Complete (not shared with any workload)  │
└─────────────────────────────────────────────────────────┘
```

**Implementation:** Remove reservation assignment from service account.

**Monitoring:**
- Daily cost (expect $1-2/day)
- TB scanned per day
- Query count per day
- P95 response time (should be <5s)

**Success Criteria:**
- P95 queue time <1 second
- P95 total response time <5 seconds
- Daily cost <$5 ($150/month ceiling)

---

### Phase 2: Flex Slots (If needed)

**Trigger:** On-demand costs exceed $150/month for 2+ consecutive months

**Architecture:**

```
┌─────────────────────────────────────────────────────────┐
│ Messaging Service                                       │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ Service Account:                                        │
│ messaging@narvar-data-lake.iam.gserviceaccount.com      │
│                                                         │
│ Configuration:                                          │
│ - Reservation Assignment: messaging-flex-reservation    │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ Flex Slots Reservation                                  │
│ - Name: messaging-flex-reservation                      │
│ - Location: US                                          │
│ - Commitment: 60 seconds minimum                        │
│ - Base capacity: 50-100 slots                          │
│ - Scale: Can increase to 200 slots if needed           │
│ - Cost: $146-292/month base                            │
└─────────────────────────────────────────────────────────┘
```

**Implementation:** Create flex reservation, assign service account.

---

### Alternative: Dedicated Project (NOT RECOMMENDED)

**Architecture:**

```
┌─────────────────────────────────────────────────────────┐
│ NEW Project: messaging-bq-dedicated                     │
│                                                         │
│ Service Account:                                        │
│ messaging-bq@messaging-bq-dedicated.iam.gserviceaccount.com
│                                                         │
│ Billing: messaging-bq-dedicated (separate budget)      │
│ Reservation: messaging-dedicated (50-100 slots)        │
└─────────────────────────────────────────────────────────┘
```

**Why NOT recommended:**
- ❌ **Complexity:** Need to provision new project, service account, IAM
- ❌ **Data access:** Need to grant permissions to all messaging.* tables
- ❌ **Maintenance overhead:** Two projects to manage
- ❌ **No cost benefit:** Same cost as using existing project
- ❌ **Application changes:** Need to update service account in app config
- ❌ **Testing complexity:** Need to test cross-project queries

**When to consider:**
- If need strict cost separation/chargeback
- If security requirements demand project-level isolation
- If want separate billing alerts/budgets

---

## Implementation Plan

### Phase 1: On-Demand Implementation (Days 1-2)

#### Days 1-2: Specification & Approval

**Day 1-2: Baseline Measurement**
```bash
# Query to calculate 30-day baseline
SELECT
  DATE(creation_time) AS date,
  COUNT(*) AS queries,
  SUM(total_bytes_processed) / POW(1024, 4) AS tb_processed,
  SUM(total_bytes_processed) / POW(1024, 4) * 6.25 AS on_demand_cost,
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY'
  AND state = 'DONE'
GROUP BY date
ORDER BY date DESC;
```

**Expected output:**
- Average daily TB: 0.15-0.25 TB
- Average daily cost: $0.94-$1.56
- Average daily queries: 12,000-15,000
- Current queue times: 0-558 seconds

**Day 3: Document Current State**
- Create baseline metrics document
- Document current service account configuration
- Get approval for on-demand approach
- Set budget alert at $10/day ($300/month)

**Day 4-5: Implementation Planning**
- Review service account IAM permissions (no changes needed)
- Plan rollback procedure
- Create monitoring dashboard
- Set up cost alerts

#### Day 2: Pilot Deployment

**Day 1: Remove Reservation Assignment**

```bash
# 1. Check current reservation status
bq show \
  --location=US \
  --reservation \
  --project_id=bq-narvar-admin \
  bq-narvar-admin:US.default

# Expected output:
# - slotCapacity: 1000
# - autoscaleMaxSlots: 700
# - autoscaleCurrentSlots: 700 (maxed out!)

# 2. Remove service account from reservation
# (Done via GCP Console: BigQuery > Reservations > Assignments)
# OR via gcloud:
gcloud alpha bq reservations assignments delete \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT
```

**Implementation Steps:**
1. Announce maintenance window (non-breaking change)
2. Remove reservation assignment from `messaging@narvar-data-lake.iam.gserviceaccount.com`
3. Service account now uses on-demand slots by default
4. Monitor for 5 minutes - queries should start executing immediately
5. Verify queue times drop to <1 second

**Rollback Plan:**
```bash
# If issues, re-assign to reservation (30 seconds)
gcloud alpha bq reservations assignments create \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT \
  --priority=100
```

**Days 2-5: Monitor & Validate**

Monitor these metrics every 6 hours:
- **Cost:** Should be $1-2/day ($0.90-0.94 baseline)
- **Queue time:** Should be <1 second P95
- **Execution time:** Should remain ~2 seconds (unchanged)
- **Error rate:** Should be 0% (no impact expected)
- **Query count:** Should match baseline (12-15K/day)

**Success Criteria:**
- ✅ P95 queue time <1 second (down from 30-507 seconds)
- ✅ P95 total response time <5 seconds
- ✅ Daily cost <$5 ($150/month)
- ✅ Zero errors or failed queries
- ✅ No customer complaints

#### Day 3: Production Validation

**Days 1-3: Extended Monitoring**
- Monitor for 72 hours continuous
- Check weekend vs weekday patterns
- Validate during peak hours (2-4pm)
- Review any cost anomalies

**Day 4: Documentation**
- Update architecture diagrams
- Document new service account configuration
- Create runbook for troubleshooting
- Update cost allocation tracking

**Day 5: Stakeholder Communication**
- Share results with Data Engineering team
- Update Jira ticket DTPL-6903 as resolved
- Notify messaging team of change
- Schedule 30-day cost review

---

### Phase 2: Flex Slots (If Needed)

**Trigger Condition:** On-demand costs >$150/month for 2 consecutive months

**Implementation Steps:**

1. **Create Flex Reservation (15 minutes)**
```bash
# Create 50-slot flex reservation
bq mk \
  --location=US \
  --project_id=bq-narvar-admin \
  --reservation \
  --slots=50 \
  --ignore_idle_slots=false \
  --edition=STANDARD \
  messaging-flex-reservation

# Create assignment
gcloud alpha bq reservations assignments create \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=messaging-flex-reservation \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT \
  --priority=100
```

2. **Monitor for 5 days**
- Verify no queue times
- Confirm cost reduction (should drop to $146/month base)
- Check slot utilization (should be 40-60%)

3. **Right-size if needed**
```bash
# Increase to 100 slots if seeing queue times
bq update \
  --location=US \
  --project_id=bq-narvar-admin \
  --slots=100 \
  messaging-flex-reservation

# Or decrease to 30 slots if over-provisioned
bq update \
  --location=US \
  --project_id=bq-narvar-admin \
  --slots=30 \
  messaging-flex-reservation
```

---

## Risks & Mitigation

### Risk 1: Cost Overrun on On-Demand

**Risk:** Query volume spikes unexpectedly, on-demand costs explode

**Probability:** Medium  
**Impact:** Medium ($500-1,000/month potential)

**Mitigation:**
1. **Set budget alerts:** $10/day, $70/week (7 days), $150/month
2. **Monitor daily:** Review cost dashboard every morning
3. **Automatic failsafe:** If cost >$300/month for 14 days, switch to flex
4. **Query optimization:** Investigate any queries scanning >100 GB

**Detection:**
```sql
-- Alert if daily cost >$10
SELECT
  DATE(creation_time) AS date,
  SUM(total_bytes_processed) / POW(1024, 4) * 6.25 AS cost,
  COUNT(*) AS queries,
  MAX(total_bytes_processed) / POW(1024, 3) AS max_gb_query
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= CURRENT_DATE()
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
GROUP BY date
HAVING cost > 10;
```

---

### Risk 2: Service Account Misconfiguration

**Risk:** Remove wrong service account from reservation, break other services

**Probability:** Low  
**Impact:** High (break other services)

**Mitigation:**
1. **Verify service account:** Triple-check email before removing
2. **Test in dev first:** If possible, test in lower environment
3. **Backup current config:** Document current assignments before change
4. **Rollback ready:** Have rollback command ready to paste (30 seconds to restore)

**Prevention:**
```bash
# BEFORE making changes, document current state
bq show \
  --location=US \
  --reservation \
  --project_id=bq-narvar-admin \
  bq-narvar-admin:US.default \
  > reservation_backup_$(date +%Y%m%d).txt

# Also list all reservations
bq ls \
  --location=US \
  --reservation \
  --project_id=bq-narvar-admin \
  >> reservation_backup_$(date +%Y%m%d).txt
```

---

### Risk 3: On-Demand Slots Unavailable

**Risk:** BigQuery on-demand capacity exhausted (very rare)

**Probability:** Very Low (<0.01%)  
**Impact:** Medium (queries queue until capacity available)

**Mitigation:**
1. **Monitor queue times:** Alert if P95 >5 seconds
2. **Fallback to reservation:** Re-assign to reservation immediately
3. **Google SLA:** On-demand has 99.9% availability SLA

**This is theoretical - on-demand capacity issues are extremely rare in US region.**

---

### Risk 4: Query Pattern Changes

**Risk:** App changes cause 10x increase in query volume or bytes scanned

**Probability:** Low  
**Impact:** High (cost spike)

**Mitigation:**
1. **Code review process:** Review any messaging query changes
2. **Staging testing:** Test query changes in dev environment first
3. **Monitoring:** Alert on query count >20K/day or bytes >10 TB/month
4. **Query optimization:** Ensure partition pruning, clustering used

**Detection:**
```sql
-- Alert if query pattern changes
SELECT
  DATE(creation_time) AS date,
  COUNT(*) AS queries,
  AVG(total_bytes_processed) / POW(1024, 3) AS avg_gb_per_query,
  MAX(total_bytes_processed) / POW(1024, 3) AS max_gb_per_query
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
GROUP BY date
HAVING 
  queries > 20000 
  OR avg_gb_per_query > 50
  OR max_gb_per_query > 500;
```

---

### Risk 5: Billing Project Configuration

**Risk:** Service account accidentally uses wrong billing project

**Probability:** Very Low  
**Impact:** Low (queries still work, but bill wrong project)

**Mitigation:**
1. **Verify billing project:** Check service account uses `narvar-data-lake` project
2. **Cost tracking:** Monitor costs in correct billing project
3. **IAM audit:** Review service account has correct project permissions

---

## Cost-Benefit Analysis

### Option Comparison at Current Volume (4.3 TB/month)

| Option | Monthly Cost | Setup Time | Complexity | Queue Time | Flexibility |
|--------|-------------|------------|------------|------------|-------------|
| **On-Demand** | **$27** | **5 min** | **Very Low** | **<1s** | **High** |
| Flex 50 slots | $146 | 30 min | Low | <1s | Medium |
| Annual 100 slots | $200 | 1 hour | Medium | <1s | Low |
| Current (shared) | $0* | 0 | N/A | 0-558s | N/A |

*Technically free (included in existing reservation) but unusable due to delays

**Winner:** On-demand (5x cheaper, simplest, instant)

---

### Option Comparison if Volume Grows 10x (43 TB/month)

| Option | Monthly Cost | Savings vs On-Demand | Queue Time | Break-even Point |
|--------|-------------|----------------------|------------|------------------|
| On-Demand | $269 | Baseline | <1s | - |
| **Flex 50 slots** | **$146** | **$123/month** | **<1s** | 23 TB/month |
| **Flex 100 slots** | **$292** | Break-even | **<1s** | 47 TB/month |
| Annual 100 slots | $200 | $69/month | <1s | 32 TB/month |

**Winner (at 43 TB/month):** Flex 50 slots (cheapest, still flexible)

---

### Total Cost of Ownership (3-year projection)

**Assumptions:**
- Year 1: 4.3 TB/month average (current)
- Year 2: 10 TB/month (2.3x growth)
- Year 3: 25 TB/month (5.8x growth from year 1)

| Option | Year 1 | Year 2 | Year 3 | **3-Year Total** |
|--------|--------|--------|--------|------------------|
| **On-Demand** | **$324** | **$750** | **$1,875** | **$2,949** |
| **Adaptive*** | **$324** | **$750** | **$1,752** | **$2,826** |
| Flex 50 slots | $1,752 | $1,752 | $1,752 | $5,256 |
| Annual 100 slots | $2,400 | $2,400 | $2,400 | $7,200 |

*Adaptive: Start on-demand Year 1-2, switch to flex Year 3 when usage >23 TB/month

**Winner:** Adaptive approach (saves $2,430 vs flex, $4,374 vs annual)

---

## Success Metrics

### Primary Metrics (Must Achieve)

**Performance:**
- ✅ P50 queue time: <1 second (currently 0-176 seconds)
- ✅ P95 queue time: <1 second (currently 30-507 seconds)
- ✅ P99 queue time: <2 seconds (currently 100-558 seconds)
- ✅ P95 total response time: <5 seconds

**Reliability:**
- ✅ Query success rate: >99.9% (no degradation)
- ✅ Zero customer escalations due to latency
- ✅ Zero incidents related to capacity

**Cost:**
- ✅ Monthly cost <$150 (Phase 1 on-demand)
- ✅ Cost per query <$0.01 (currently ~$0.003)
- ✅ No surprise cost spikes (daily variance <50%)

### Secondary Metrics (Monitor)

**Usage:**
- Daily query count: 12,000-15,000 (track trend)
- TB scanned per day: 0.15-0.25 TB (track trend)
- Queries per user search: 10 (should remain constant)
- Peak concurrent queries: 30-50 (track for capacity planning)

**Efficiency:**
- Average bytes per query: 10-15 GB (optimize if increases)
- Average execution time: 2-3 seconds (should remain stable)
- Slot utilization: N/A for on-demand, 40-60% for flex

### Monitoring Dashboard

**Daily KPIs:**
```sql
-- Daily dashboard query
WITH daily_metrics AS (
  SELECT
    DATE(creation_time) AS date,
    COUNT(*) AS queries,
    SUM(total_bytes_processed) / POW(1024, 4) AS tb_processed,
    SUM(total_bytes_processed) / POW(1024, 4) * 6.25 AS on_demand_cost,
    
    -- Performance
    APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(50)] AS p50_queue_sec,
    APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] AS p95_queue_sec,
    APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(99)] AS p99_queue_sec,
    
    APPROX_QUANTILES(TIMESTAMP_DIFF(end_time, start_time, SECOND), 100)[OFFSET(95)] AS p95_exec_sec,
    
    -- Problems
    COUNTIF(error_result IS NOT NULL) AS errors,
    COUNTIF(TIMESTAMP_DIFF(start_time, creation_time, SECOND) > 5) AS queries_delayed_over_5s
    
  FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
  WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
    AND job_type = 'QUERY'
  GROUP BY date
)
SELECT 
  date,
  queries,
  ROUND(tb_processed, 2) AS tb,
  ROUND(on_demand_cost, 2) AS cost_usd,
  p50_queue_sec,
  p95_queue_sec,
  p99_queue_sec,
  p95_exec_sec,
  errors,
  queries_delayed_over_5s,
  
  -- Alerts
  CASE 
    WHEN on_demand_cost > 10 THEN '🔴 COST ALERT'
    WHEN p95_queue_sec > 5 THEN '🟡 LATENCY WARNING'
    WHEN errors > 0 THEN '🔴 ERROR ALERT'
    ELSE '✅ Healthy'
  END AS status
FROM daily_metrics
ORDER BY date DESC;
```

**Alerts:**
- 🔴 **CRITICAL:** Daily cost >$10 OR P95 queue >10s OR errors >10
- 🟡 **WARNING:** Daily cost >$5 OR P95 queue >5s OR queries delayed >100
- 📊 **INFO:** Weekly summary email with 7-day trend

---

## Decision Matrix

### Should We Use On-Demand or Reservation?

**Use ON-DEMAND if:**
- ✅ Current usage <20 TB/month ($125/month on-demand cost)
- ✅ Usage pattern unpredictable or seasonal
- ✅ Want zero upfront commitment
- ✅ Prioritize simplicity over cost optimization
- ✅ Want to defer capacity planning decisions

**Use FLEX RESERVATION if:**
- ✅ Usage consistently >25 TB/month ($156/month on-demand cost)
- ✅ Usage pattern stable and predictable
- ✅ Want cost ceiling/budget predictability
- ✅ Can commit to monitoring and managing reservation
- ✅ Want to optimize for long-term cost efficiency

**Use ANNUAL RESERVATION if:**
- ✅ Usage consistently >35 TB/month ($219/month on-demand cost)
- ✅ Very stable, mature workload
- ✅ Can commit for 12 months
- ✅ Want absolute lowest cost per TB
- ✅ Have executive approval for multi-year budget

---

## Recommendation Summary

### Phase 1 (Immediate): On-Demand Slots

**Why:** 
- Simplest implementation (5 minutes)
- Cheapest for current volume ($27/month vs $146/month)
- Zero risk (can switch back instantly)
- Eliminates queue times immediately
- No capacity planning needed

**Timeline:** Deploy within 6-10 days

**Success metric:** P95 queue time <1 second at <$150/month cost

---

### Phase 2 (If Needed): Flex Slots

**Trigger:** On-demand costs exceed $150/month for 2 consecutive months (usage >24 TB/month)

**Action:** 
- Create 50-slot flex reservation
- Reassign service account
- Monitor for 5-7 days
- Right-size to 30-100 slots based on actual usage

**Cost:** $146/month (50 slots) with option to scale

---

### Phase 3 (Future): Annual Commitment

**Trigger:** Usage stabilizes >35 TB/month for 6+ months AND growth projections support it

**Action:** 
- Switch from flex to annual
- Commit to 100-200 slot annual reservation
- Lock in $200-400/month cost for 12 months

**Benefit:** Save $50-100/month vs flex

---

## Next Actions

### Days 1:
1. [ ] Review and approve this TRD
2. [ ] Set up budget alerts ($10/day, $150/month)
3. [ ] Create monitoring dashboard (use SQL above)
4. [ ] Schedule deployment window (15 minutes)

### Day 2-5:
5. [ ] Execute Phase 1 deployment (remove reservation assignment)
6. [ ] Monitor for 5 days (check dashboard 2x/day)
7. [ ] Validate success criteria
8. [ ] Document results and update stakeholders

### Day 5-30:
9. [ ] 30-day cost review
10. [ ] Evaluate if Phase 2 (flex) needed
11. [ ] Long-term capacity forecast
12. [ ] Close Jira ticket DTPL-6903

---

## Appendix: Technical Commands

### Verify Current Configuration
```bash
# Check current reservation status and capacity
bq show --location=US \
  --reservation \
  --project_id=bq-narvar-admin \
  bq-narvar-admin:US.default

# Expected output:
# - slotCapacity: 1000
# - autoscaleMaxSlots: 700
# - autoscaleCurrentSlots: 700 (currently maxed out!)
# - edition: ENTERPRISE

# List all reservations
bq ls --location=US \
  --reservation \
  --project_id=bq-narvar-admin

# Check service account has necessary permissions
gcloud projects get-iam-policy narvar-data-lake \
  --flatten="bindings[].members" \
  --filter="bindings.members:messaging@narvar-data-lake.iam.gserviceaccount.com"
```

### Deploy On-Demand (Phase 1)
```bash
# Remove from reservation (makes it on-demand)
# NOTE: Use 'default' as reservation name, not full 'bq-narvar-admin:US.default'
gcloud alpha bq reservations assignments delete \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT

# Verify service account is no longer in reservation
# (Query should show no messaging@narvar-data-lake assignments)
```

### Rollback to Reservation
```bash
# Re-assign to reservation (30-second rollback)
gcloud alpha bq reservations assignments create \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT \
  --priority=100
```

### Create Flex Reservation (Phase 2)
```bash
# Create new flex reservation for messaging
bq mk --location=US \
  --project_id=bq-narvar-admin \
  --reservation \
  --slots=50 \
  --ignore_idle_slots=false \
  --edition=STANDARD \
  messaging-flex-reservation

# Assign messaging service account
gcloud alpha bq reservations assignments create \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=messaging-flex-reservation \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT
```

### Scale Flex Reservation
```bash
# Increase slots to 100
bq update --location=US \
  --project_id=bq-narvar-admin \
  --slots=100 \
  messaging-flex-reservation

# Decrease slots to 30 if over-provisioned
bq update --location=US \
  --project_id=bq-narvar-admin \
  --slots=30 \
  messaging-flex-reservation
```

### Delete Flex Reservation
```bash
# Remove assignment first
gcloud alpha bq reservations assignments delete \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=messaging-flex-reservation \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT

# Delete the reservation
bq rm --location=US \
  --project_id=bq-narvar-admin \
  --reservation \
  messaging-flex-reservation
```

---

**Document Status:** DRAFT for review  
**Next Review:** After approval, update with actual deployment results  
**Owner:** Cezar Mihaila (Data Engineering)  
**Stakeholders:** Messaging team, Data Platform team, Finance

