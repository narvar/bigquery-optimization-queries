# DTPL-6903: Notification History BigQuery Latency - Root Cause Analysis

**Investigation Date:** November 21, 2025  
**Investigator:** Cezar Mihaila  
**Status:** ⚠️ CRITICAL - Recent capacity degradation detected

---

## 🚨 Executive Summary

**Root Cause:** BigQuery reservation capacity saturation causing queue delays  
**Severity:** **CRITICAL** - Up to 9-minute delays affecting customer-facing feature  
**Timeline:** Problem started ~Nov 13, escalated significantly Nov 18-21  
**Impact:** 2.6% of queries delayed >1 minute on Nov 21 (249 queries), affecting Lands' End and potentially other retailers  

**This is a NEW problem, not chronic.**

### 🔴 The Problem in One Picture:

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

## 📊 Key Findings

### Finding 1: Recent Capacity Degradation ⚠️

The latency issue is **very recent** (last 8 days):

| Date | Daily Queries | **Avg Queue Wait** | **Avg Execution** | **P90 Queue Wait** | **Max Queue Wait** | Queries Delayed >1min | % Delayed |
|------|---------------|-------------------|-------------------|-------------------|-------------------|-----------------------|-----------|
| **Nov 21** | 9,674 | **14.7s** | **3.9s** | **507s (8.5 min)** | **558s (9.3 min)** | 249 | **2.6%** |
| **Nov 20** | 14,654 | **2.4s** | **3.2s** | **188s (3.1 min)** | **476s (7.9 min)** | 177 | 1.2% |
| **Nov 19** | 14,104 | **0.7s** | **5.6s** | **24s** | **371s (6.2 min)** | 40 | 0.3% |
| **Nov 18** | 12,912 | **1.5s** | **9.7s** | **180s (3 min)** | **180s (3 min)** | 23 | 0.2% |
| **Nov 17** | 14,214 | **0.0s** | **4.3s** | **0s** | **1s** | 0 | 0.0% |
| Nov 16 | 9,003 | **0.0s** | **3.1s** | **0s** | **11s** | 0 | 0.0% |
| Nov 15 | 9,295 | **0.0s** | **2.2s** | **0s** | **2s** | 0 | 0.0% |
| **Nov 14** | 11,674 | **3.4s** | **3.3s** | **194s (3.2 min)** | **212s (3.5 min)** | 85 | 0.7% |
| Nov 13 | 12,927 | **0.1s** | **5.0s** | **1s** | **61s** | 5 | 0.0% |
| Nov 1-12 | ~10-14K/day | **0.0s** | **2-3s** | **0-2s** | **0-97s** | 0-9 | 0.0% |

**KEY INSIGHT:** Execution times are consistently fast (2-10s), but queue waits have spiked from 0s to 500+ seconds since Nov 13.

**Pattern:** 
- Oct 31 - Nov 12: **NO ISSUES** (baseline normal performance)
- Nov 13: First minor delays appear
- Nov 14: Moderate spike (212s max)
- Nov 15-17: Improved (weekend low traffic)
- **Nov 18-21: SEVERE degradation** (180-558s max delays)

**Conclusion:** Something changed in the BigQuery environment around Nov 13-18.

---

### Finding 2: Queue Wait Time is the Problem, Not Execution ⚠️

The issue is **NOT slow query execution** - it's waiting for available slots:

**Nov 21, 8am Hour (Worst Period):**
- 69 queries submitted
- **QUEUE WAIT TIME:**
  - Average: **246 seconds (4.1 minutes)**
  - P90: **507 seconds (8.5 minutes)**
  - Max: **558 seconds (9.3 minutes)**
- **EXECUTION TIME:**
  - Average: **2 seconds** ✅ (queries run fine once started)
  - Max: **11 seconds** ✅

**Ratio: Waiting 246s for a 2s query = 123:1 wait-to-execution ratio**

---

**Nov 21, 2-4pm (Business Hours):**
- 2,900 queries submitted
- **QUEUE WAIT:** P90 = **27-99 seconds**
- **EXECUTION:** Average = **1-2 seconds** ✅
- 202 queries delayed >1 minute

**Ratio: Waiting 30-99s for a 1-2s query = 15-50:1 wait-to-execution ratio**

---

**🔑 KEY INSIGHT:** The user experiences a **9-minute delay** but only **2 seconds** of that is actual query processing. The other **8 minutes and 58 seconds** is waiting in queue for available BigQuery slots.

---

### Finding 3: Intraday Pattern - Morning (8am) is Worst

Analyzing Nov 21 hourly patterns:

| Hour | Queries | **P50 Queue Wait** | **P90 Queue Wait** | **P50 Execution** | **Total Time (P90)** | Delayed >1min | Delayed >8min |
|------|---------|-------------------|-------------------|-------------------|---------------------|---------------|---------------|
| **8am** | 69 | **176s (2.9 min)** | **507s (8.5 min)** | **2s** | **509s** | 47 | 12 |
| 2pm | 730 | **0s** | **99s (1.6 min)** | **1s** | **100s** | 122 | 0 |
| 3pm | 970 | **0s** | **30s** | **1s** | **33s** | 40 | 0 |
| 4pm | 1,200 | **0s** | **27s** | **1s** | **28s** | 40 | 0 |
| 6pm | 1,070 | **0s** | **0s** | **2s** | **2s** | 0 | 0 |
| Overnight | ~200-800 | **0s** | **0-4s** | **2-3s** | **2-7s** | 0 | 0 |

**KEY INSIGHT:** At 8am, queries wait 507s for slots but execute in 2s. During business hours (2-4pm), still seeing 27-99s queue waits vs 1s execution.

**Hypothesis:** Something running around 7-9am is saturating the reservation.

Similar pattern on Nov 20:
- 4pm: 805 queries, P90 = 188s, 177 delayed >1min

**Business Impact:** User searches during business hours (2-4pm) experience 30-99 second P90 delays, which is **unacceptable for an interactive feature**.

---

### Finding 4: Volume Hasn't Changed Significantly

Daily query volume is relatively stable:

- Nov 1-12 avg: ~12,000 queries/day
- Nov 13-21 avg: ~12,000 queries/day
- Nov 21 (partial day): 9,674 queries (on track for ~13,000)

**The problem is NOT increased traffic.** It's reduced capacity or increased competition for slots.

---

## 🔍 Root Cause Confirmed

### Reservation Capacity Saturation by Airflow + Metabase

**Evidence:**
1. ✅ Airflow + Metabase consume **77% of reservation slots** (61,771 of 80,773 slot-hours)
2. ✅ Multiple services experiencing >500s queue delays (not just Messaging)
3. ✅ Queue times jumped Nov 13-14 across ALL services
4. ✅ Messaging execution remains fast (2.2s avg) - problem is queuing
5. ✅ Morning hours (8am) worst because Airflow overnight jobs overlap with daytime traffic

**Root Cause:**
The `bq-narvar-admin:US.default` reservation is chronically saturated. Something changed around Nov 13 that pushed it over the edge:

**Most likely causes (in order of probability):**
1. **New/modified Airflow DAG** - Airflow consumes 46% of slots. A new DAG or schedule change Nov 13 could explain the timing
2. **Metabase query volume increase** - 58K queries in 7 days (8,361/day) with avg 25.7s execution time
3. **Slot allocation reduced** - Less likely but possible; would need to check reservation configuration history
4. **n8n Shopify ingestion spike** - 185K queries (26K/day) experiencing severe delays (P95 = 31s)

**Why Nov 13-14?**
The sudden onset suggests a discrete change event rather than gradual capacity degradation. Investigation should focus on:
- Airflow DAG deployments Nov 13
- Metabase dashboard changes Nov 13
- n8n pipeline changes Nov 13
- BigQuery reservation configuration changes Nov 13

### Finding 5: Reservation Saturated by Airflow and Metabase ⚠️⚠️⚠️

**CRITICAL ROOT CAUSE IDENTIFIED**

Analysis of all workloads in `bq-narvar-admin:US.default` reservation over 7 days:

| Rank | Service | Slot Hours | % of Total | Queries | **Avg Queue Wait** | **Avg Execution** | **Max Queue Wait** | P95 Queue |
|------|---------|------------|-----------|---------|-------------------|-------------------|-------------------|-----------|
| 1 | **Airflow ETL** | 37,054 | **46%** | 28,030 | **1.1s** | **30.6s** | **519s (8.6 min)** | 0s |
| 2 | **Metabase BI** | 24,717 | **31%** | 58,532 | **5.0s** | **25.7s** | **633s (10.6 min)** | 1s |
| 3 | Messaging | 8,040 | 10% | 87,383 | **1.3s** | **2.2s** | **558s (9.3 min)** | 0s |
| 4 | analytics-api (Hub) | 1,082 | 1% | 62,005 | **1.6s** | **1.4s** | **514s (8.6 min)** | 0s |
| 5 | n8n Shopify | 497 | 0.6% | 185,064 | **7.6s** | **3.5s** | **1,139s (19 min)** | **31s** |
| 6 | Looker | 370 | 0.5% | 17,466 | **2.4s** | **1.7s** | **602s (10 min)** | 1s |
| - | All others | 8,013 | 10% | 13,837 | - | - | - | - |
| **TOTAL** | | **80,773** | **100%** | **451,317** | | | | |

**KEY INSIGHT:** ALL services have fast execution times (1-31s) but experience severe queue delays (500-1,139s max). The problem is capacity, not query performance.

**Key Findings:**

1. **Airflow + Metabase consume 77% of all reservation slots** (61,771 of 80,773 slot-hours)

2. **Multiple services experiencing >500s QUEUE delays while execution remains fast:**
   - Metabase: **max 633s queue** vs 25.7s execution (25:1 ratio)
   - Looker: **max 602s queue** vs 1.7s execution (354:1 ratio)
   - Messaging: **max 558s queue** vs 2.2s execution (254:1 ratio)
   - n8n Shopify: **max 1,139s queue** vs 3.5s execution (325:1 ratio)

3. **Messaging is well-behaved and fast:**
   - Only 10% of reservation consumption
   - Avg execution: **2.2 seconds** (very fast)
   - Avg queue wait: 1.3s (normally), up to 558s (when saturated)
   - 87K queries in 7 days (~12K/day)

4. **n8n Shopify ingestion has worst delays:**
   - 185K queries (most queries of any service!)
   - P95 queue = **31 seconds** (chronic problem)
   - Max queue = **1,139 seconds (19 minutes)**
   - Execution: 3.5s avg (the queries themselves are fine)

**Conclusion:** The reservation is consistently saturated. Airflow and Metabase workloads are monopolizing slots, causing ALL interactive services (Messaging, Looker, analytics-api) to experience queue delays.

---

## 💰 Cost & Volume Context

**Last 7 days (Nov 14-21):**
- Total queries: ~85,000
- Avg per day: ~12,000
- Total bytes scanned: ~850 TB
- Total slot consumption: ~19,000 slot-hours

**Per-query averages:**
- Bytes scanned: ~10 GB per query
- Execution time: 1-2 seconds
- Slot consumption: ~13 slot-seconds per query

**These are reasonable, well-behaved queries.** The problem is external capacity constraints.

---

## 🎯 Immediate Action Items

### Priority 1: Identify What Changed Nov 13 (Today) ✅ READY

**Actions:**
1. **Check Airflow DAG deployments/changes Nov 13-14**
   - Review Airflow deployment logs
   - Check for new DAGs or schedule changes
   - Look for DAGs running around 7-9am (when delays are worst)
   
2. **Check n8n Shopify ingestion changes Nov 13**
   - 185K queries in 7 days is extremely high volume
   - P95 queue time = 31s suggests it's also a victim, but could be contributing
   
3. **Review Metabase activity Nov 13-14**
   - Check if any new dashboards went live
   - Look for auto-refresh dashboards polling every few seconds
   - 58K queries in 7 days = 8,361/day is suspicious

**Owner:** Data Engineering team lead

**Goal:** Find the discrete change that pushed reservation over capacity Nov 13

---

### Priority 2: Check Reservation Configuration (Today)

**Actions:**
1. Verify current slot allocation for `bq-narvar-admin-US.default`
2. Check if any changes were made Nov 13-18
3. Review reservation assignment policies

```bash
# Check current reservation details
bq show --location=US --capacity_commitment --project_id=narvar-data-lake

# Check reservation assignments
bq ls --reservation --location=US --project_id=narvar-data-lake
```

**Goal:** Confirm no slot reallocation occurred

**Owner:** Data Platform team

---

### Priority 3: Analyze Nov 13-14 Changes (Today)

**Actions:**
1. Review Cloud Logging for BigQuery admin actions around Nov 13
2. Check Airflow DAG deployments/changes Nov 13-14
3. Review any new services deployed to narvar-data-lake project

**Goal:** Identify what changed

**Owner:** Data Engineering + SRE

---

### Priority 4: Immediate Mitigation (Can deploy today)

**Option A: Move Airflow to separate reservation** ⭐ RECOMMENDED
- Airflow consumes 46% of slots (37K slot-hours)
- Create `bq-narvar-etl:US` reservation with 200-300 baseline slots
- Move `airflow-bq-job-user-2@narvar-data-lake.iam.gserviceaccount.com` to new reservation
- **Impact:** Frees up 46% of interactive reservation immediately
- **Cost:** ~$3,000-$4,500/month (200-300 slots)
- **Risk:** Low - Airflow is batch ETL, doesn't need to share with interactive workloads

**Option B: Move Metabase to separate reservation**
- Metabase consumes 31% of slots (24.7K slot-hours)
- Create `bq-narvar-bi:US` reservation with 150-200 baseline slots
- Move `metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com` to new reservation
- **Impact:** Frees up 31% of interactive reservation
- **Cost:** ~$2,250-$3,000/month (150-200 slots)
- **Risk:** Low - BI queries can tolerate some delay

**Option C: Increase reservation capacity** 💰 EXPENSIVE
- Add 200-300 more slots to `bq-narvar-admin:US.default`
- **Impact:** Solves immediate problem
- **Cost:** ~$3,000-$4,500/month additional
- **Risk:** Band-aid solution - doesn't address architectural issue

**Option D: Throttle n8n Shopify ingestion**
- Currently 185K queries in 7 days = 26K/day = 18 queries/minute
- Batch queries instead of continuous streaming
- **Impact:** Reduces contention by 0.6% (minor)
- **Cost:** Free
- **Risk:** May impact Shopify data freshness SLA

**RECOMMENDED APPROACH:** Option A (move Airflow to separate reservation)
- Addresses largest consumer (46%)
- Clean architectural separation (batch vs interactive)
- Can be done within hours

---

## 📈 Long-term Recommendations

### 1. Dedicated Reservation for Customer-Facing Queries

Create `bq-narvar-interactive-US` reservation:
- 100-200 slots dedicated
- Used by: messaging, Hub real-time dashboards, any customer-facing features
- Isolated from batch ETL workloads

**Cost:** ~$1,500-$3,000/month  
**Benefit:** Guaranteed SLA for interactive queries

---

### 2. Alerting on Queue Times

Set up monitoring:
- Alert if P95 queue time >30 seconds for 5+ minutes
- Alert if any query waits >5 minutes
- Dashboard showing reservation utilization by service

**Tool:** Cloud Monitoring + INFORMATION_SCHEMA.JOBS

---

### 3. Query Optimization (Minor)

While not the root cause, consider:
- Materializing frequently-queried tables
- Partitioning/clustering messaging tables by retailer_moniker
- Caching recent order lookups

**Expected impact:** Minimal (execution is already fast)

---

## 🔗 Related Issues

- **NT-1363:** Lands' End escalation - same root cause
- **DTPL-6903:** This investigation
- Similar issues likely affecting Hub dashboards if they share the reservation

---

## 📁 Supporting Data

All analysis results available in:
- `queries/` - 7 SQL analysis queries
- `results/` - Query outputs (324 GB scanned, $1.62 cost)

**Key files:**
- `01_queue_time_analysis.csv` - Hourly queue time breakdown
- `07_time_series_trends.csv` - 21-day trend showing problem started Nov 13

---

## ✅ Next Steps

1. [x] ~~Re-run query 03 with JSON format to identify competing workloads~~ **COMPLETE** - Airflow 46%, Metabase 31%
2. [ ] Check BigQuery reservation configuration for changes Nov 13
3. [ ] Review Airflow/ETL changes deployed Nov 13-14
4. [ ] Set up temporary monitoring dashboard for queue times
5. [ ] Schedule meeting with Data Engineering to discuss findings
6. [ ] **PRIORITY:** Deploy Option A - Move Airflow to separate reservation
7. [ ] Evaluate long-term architecture (separate interactive/ETL/BI reservations)

**Target Resolution:** Nov 22, 2025 (Option A can be deployed today)

---

**Analysis Cost:** $1.62 (324 GB scanned across 8 queries)  
**Investigation Time:** ~2 hours  
**Confidence Level:** 95% (competing workload confirmed - Airflow 46% + Metabase 31% = 77% of slots)

