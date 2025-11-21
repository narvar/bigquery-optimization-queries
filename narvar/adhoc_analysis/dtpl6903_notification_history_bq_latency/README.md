# DTPL-6903: Notification History BigQuery Latency Investigation

**Jira Issue**: https://narvar.atlassian.net/browse/DTPL-6903  
**Related Ticket**: https://narvar.atlassian.net/browse/NT-1363 (Lands' End escalation)  
**Date**: November 21, 2025  
**Investigator**: Cezar Mihaila

## Problem Statement

Notification History feature experiencing significant BigQuery latency issues:
- **Symptom**: 8-minute delay between query job creation and execution start
- **Impact**: Retailer-facing feature (Hub UI) becomes unusable
- **Pattern**: Each user search triggers 10 parallel queries to BigQuery
- **Service Account**: `messaging@narvar-data-lake.iam.gserviceaccount.com`
- **Reservation**: `bq-narvar-admin-US.default`

## Key Observation from Sample Query

**Job ID**: `job_x_RnGlaGvFGBYyzjA2b1ywgoDSz`
- Creation time: 2025-11-21 13:48:35 PST
- Start time: 2025-11-21 13:56:07 PST  
- End time: 2025-11-21 13:56:08 PST
- **Queue wait**: ~8 minutes
- **Actual execution**: 1 second
- Bytes scanned: 4.21 GB
- Slot milliseconds: 13,224

**Root cause hypothesis**: Queue wait time (not execution time) is the problem.

## Investigation Status: ✅ COMPLETE

### Root Cause Identified:
- **Primary:** BigQuery reservation `bq-narvar-admin:US.default` saturated at maximum autoscale (1,700 slots)
- **Secondary:** n8n Shopify ingestion causes 88% of worst notification history delay periods
- **Impact:** Queue wait times 8-9 minutes vs 2-second execution times (279:1 ratio)

### Solution Recommended:
- **Immediate:** Configure messaging to use on-demand slots (~$27/month, 5-minute deployment)
- **Alternative:** Move Airflow to separate reservation (frees 46% capacity, $3,000-4,500/month)
- **Investigation:** n8n Shopify query efficiency (consuming 6,631 slot-minutes/minute overnight)

## Document Guide

### 📖 Start Here:
1. **EXECUTIVE_SUMMARY.md** - Read first for high-level overview and non-technical summary for Jira ticket
2. **MESSAGING_CAPACITY_PLANNING.md** - Read second for complete implementation plan

### 📊 Deep Dives:
3. **FINDINGS.md** - Detailed technical analysis and data tables
4. **CHOKE_POINTS_ANALYSIS.md** - Specific time periods and competing workload analysis

### 🔧 Implementation:
5. **MESSAGING_CAPACITY_PLANNING.md** - TRD with deployment commands, monitoring, and risk mitigation

## Service Account Details

- **Email**: `messaging@narvar-data-lake.iam.gserviceaccount.com`
- **Project**: `narvar-data-lake` (billing project)
- **Service**: notify-automation-service (Java backend)
- **Reservation**: `bq-narvar-admin-US.default`

## Tables Queried by Notification History

Per [NoFlakeQueryService.java](https://github.com/narvar/notify-automation-service/blob/d5019d7bdcd36e80b03befff899978f28a39b2de/src/main/java/com/narvar/automationservice/services/notificationreports/NoFlakeQueryService.java#L34):

1. `messaging.pubsub_rules_engine_pulsar_debug`
2. `messaging.pubsub_rules_engine_pulsar_debug_V2`
3. `messaging.pubsub_rules_engine_kafka`
4. (7 additional tables)

Each search = 10 parallel queries across these tables.

## Files in This Investigation

### Overview & Navigation:
- `README.md` - This file
- `f75bba68-ddac-4744-af30-834be6b149d9.png` - Screenshot showing 8-minute delay

### Analysis Documents:
- **`EXECUTIVE_SUMMARY.md`** ⭐ - One-page summary for stakeholders (ready for Jira ticket)
- **`FINDINGS.md`** - Comprehensive root cause analysis showing reservation saturation
  - Airflow (46%) + Metabase (31%) = 77% of capacity
  - Queue wait vs execution time breakdown
  - Reservation running at max autoscale (1,700 slots)
- **`CHOKE_POINTS_ANALYSIS.md`** - 10-minute period analysis
  - n8n Shopify identified as primary culprit (88% of worst delays)
  - Overnight periods with 6,631 slot-minutes/minute consumption
  - Time-of-day patterns and recommendations

### Implementation Planning:
- **`MESSAGING_CAPACITY_PLANNING.md`** ⭐ **Technical Requirements Document (TRD)**
  - **Purpose:** Complete implementation guide for deploying dedicated BigQuery capacity
  - **Capacity Requirements:** 50-100 slots minimum (based on peak concurrency analysis)
  - **Pricing Options:**
    - On-demand: $27/month (recommended for Phase 1)
    - Flex slots: $146/month (if usage exceeds 24 TB/month)
    - Annual commitment: $200/month (if usage exceeds 35 TB/month)
  - **Implementation Timeline:** 3-5 days
    - Days 1-2: Specification & approval (baseline measurement query included)
    - Day 2: Pilot deployment (5-minute change to remove reservation assignment)
    - Days 2-5: Monitoring & validation
  - **Architecture:** Service account uses on-demand slots (no reservation)
  - **Risk Analysis:** 5 major risks identified with mitigation strategies
  - **Deployment Commands:** Complete bash/SQL scripts for implementation and rollback
  - **Monitoring:** Daily dashboard query and alert thresholds
  - **Success Metrics:** P95 queue <1s, cost <$150/month
  - **Current Reservation Status:** bq-narvar-admin:US.default at 1,700 slots (maxed out)

### Supporting Data:
- `queries/` - 9 SQL analysis queries (all validated and executed, $1.85 total cost)
- `results/` - Query outputs (CSV and JSON formats)

