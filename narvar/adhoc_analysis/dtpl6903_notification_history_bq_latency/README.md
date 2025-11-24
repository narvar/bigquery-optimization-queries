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

---

## Final Deployment Plan (Nov 24, 2025)

### Configuration:
- **Reservation:** `messaging-dedicated` (new, dedicated to messaging service)
- **Baseline capacity:** 50 slots ($146/month)
- **Autoscale maximum:** +50 slots ($73/month avg when active)
- **Total capacity:** 100 slots
- **Edition:** ENTERPRISE (required for autoscaling)
- **Total cost:** ~$219/month

### Why This Configuration:
1. **Average usage:** 48 concurrent slots (fits in 50 baseline)
2. **9pm daily spike:** 186-386 concurrent slots (needs autoscale)
3. **Cost optimization:** Autoscale saves $73/month vs fixed 100-slot reservation
4. **Handles 95%+ of traffic:** Only extreme peaks (386 slots) might briefly queue

### Deployment Method:
- **Step 1:** Create reservation with `bq mk --autoscale_max_slots=50`
- **Step 2:** Assign service account via BigQuery Reservation API (curl)
- **Step 3:** Monitor intensively (5-min checks for first hour)
- **Rollback:** 2-minute recovery if issues

### Why Not On-Demand ($27/month):
- **Discovery:** Entire narvar.com organization assigned to `bq-narvar-admin:US.default`
- Cannot remove individual service accounts from org-level assignment
- Must create service-account-specific assignment (requires target reservation)
- **Future:** Coordinate org-wide refactoring to enable on-demand (saves $192/month)

## Investigation Status: ✅ COMPLETE | Deployment: 🟡 READY

### Root Cause Identified:
- **Primary:** BigQuery reservation `bq-narvar-admin:US.default` saturated at maximum autoscale (1,700 slots)
- **Organizational constraint:** Entire narvar.com organization assigned to shared reservation (org-level assignment)
- **Secondary:** n8n Shopify ingestion causes 88% of worst notification history delay periods
- **Impact:** Queue wait times 8-9 minutes vs 2-second execution times (279:1 ratio)

### Solution Ready to Deploy:
- **Approach:** Create dedicated reservation with 50-slot baseline + autoscale to 100 slots
- **Cost:** ~$219/month ($146 baseline + ~$73 autoscale when active)
- **Why autoscale:** Daily 9pm spike of 186-386 slots (4-8x average of 48 slots)
- **Timeline:** 15 minutes deployment + 24 hours monitoring
- **Alternative (future):** Org-level assignment refactoring → on-demand ($27/month, saves $192/month, requires 1-2 weeks coordination)

### Peak Capacity Discovery (Nov 24):
- **Average concurrent:** 48 slots
- **Daytime (8am-6pm):** 46-57 slots
- **9pm DAILY spike:** 186-386 slots (requires autoscale)
- **Overnight:** 59-142 slots

## 📖 Document Guide

### 🚀 For Deployment (Read These):
1. **PRE_DEPLOYMENT_CHECKLIST.md** ⭐ Start here - Complete checklist before deployment
2. **QUICK_DEPLOY.sh** - Automated deployment script (or use manual steps from checklist)
3. **DEPLOYMENT_RUNBOOK_FINAL.md** - Complete technical reference with troubleshooting

### 📊 Analysis & Justification (Background):
4. **EXECUTIVE_SUMMARY.md** - High-level overview for stakeholders (ready for Jira ticket)
5. **CAPACITY_ANALYSIS_SUMMARY.md** - Traffic attribution and peak capacity analysis
6. **FINDINGS.md** - Root cause analysis with queue vs execution time breakdown
7. **CHOKE_POINTS_ANALYSIS.md** - 10-minute period analysis (n8n Shopify impact)

### 📁 Supporting Data:
- `queries/` - 11 SQL analysis queries (validated and executed)
- `results/` - Query outputs including hourly_peak_slots.csv (peak analysis)
- `calculate_capacity.py` - Capacity calculation script

### 📚 Archive (Superseded Docs):
- `archive/` - Previous deployment plans and intermediate analysis
  - Original on-demand plan (not viable due to org-level assignment)
  - Credential checks and CLI guides (incorporated into final docs)
  - Org-level assignment discovery docs (incorporated)

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

### 🚀 Deployment Documents (CURRENT - Nov 24):

- **`DEPLOYMENT_RUNBOOK_FINAL.md`** ⭐ **Complete Deployment Guide**
  - **Configuration:** 50-slot baseline + autoscale to 100 slots (ENTERPRISE edition)
  - **Cost:** ~$219/month ($146 baseline + ~$73 autoscale)
  - **Why autoscale:** Daily 9pm spike of 186-386 slots requires elastic capacity
  - **Timeline:** 15 minutes deployment + 24 hours monitoring
  - **Method:** BigQuery Reservation API (curl commands - gcloud not available)
  - **Includes:** Pre-deployment backup, deployment steps, monitoring scripts, rollback procedures
  
- **`PRE_DEPLOYMENT_CHECKLIST.md`** ⭐ **Step-by-Step Checklist**
  - 5 pre-flight checks with commands
  - Copy-paste deployment commands
  - Monitoring schedule (5-min/hourly/daily)
  - Success criteria and rollback decision tree
  
- **`QUICK_DEPLOY.sh`** ⭐ **Automated Deployment Script**
  - Interactive deployment with confirmations
  - Creates reservation with autoscale
  - Assigns service account via API
  - Runs verification automatically
  - Ready to execute: `./QUICK_DEPLOY.sh`
  
- **`CAPACITY_ANALYSIS_SUMMARY.md`** ⭐ **Capacity Justification**
  - Traffic attribution: 87,383 queries, 8,040 slot-hours (10% of reservation)
  - Peak analysis: Daily 9pm spike of 186-386 slots
  - Cost comparison: autoscale vs fixed capacity
  - Why 50 + autoscale 50 is optimal

### 📁 Archived Documents:
- **`archive/`** - Superseded deployment plans
  - `DEPLOYMENT_RUNBOOK.md` - Original (superseded by FINAL)
  - `ON_DEMAND_DEPLOYMENT_PLAN.md` - On-demand approach (not viable due to org-level assignment)
  - `CLI_DEPLOYMENT_GUIDE.md` - API reference (incorporated into FINAL)
  - `ORG_LEVEL_ASSIGNMENT_SOLUTION.md` - Org discovery (incorporated into FINAL)
  - `CREDENTIAL_CHECK.md` - Permission verification (resolved)
  - `TEAM_NOTIFICATION.md` - Communication templates (one-time use)

### Supporting Data:
- `queries/` - 9 SQL analysis queries (all validated and executed, $1.85 total cost)
- `results/` - Query outputs (CSV and JSON formats)

