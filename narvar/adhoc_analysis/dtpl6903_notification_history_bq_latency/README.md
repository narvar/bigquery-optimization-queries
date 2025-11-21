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

## Investigation Plan

### Phase 1: Queue Time Analysis (Priority 1)
**Goal**: Understand when and why queries are getting queued

1. `01_messaging_queue_time_analysis.sql` - Analyze wait times over last 7 days
2. `02_reservation_utilization_during_delays.sql` - Check slot utilization when delays occur
3. `03_concurrent_workload_analysis.sql` - Identify competing workloads

### Phase 2: Query Profiling
**Goal**: Characterize the messaging workload

4. `04_query_pattern_classification.sql` - Classify query types
5. `05_retailer_breakdown.sql` - Breakdown by retailer
6. `06_resource_consumption.sql` - Analyze bytes/slots per query
7. `07_time_series_analysis.sql` - Trend analysis over 3 weeks

### Phase 3: Recommendations
Based on findings, determine if issue is:
- **Capacity**: Need more slots in reservation
- **Priority**: Need higher priority for interactive queries
- **Architecture**: 10 parallel queries is too aggressive
- **Optimization**: Queries need indexes/optimization

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

- `README.md` - This file
- `f75bba68-ddac-4744-af30-834be6b149d9.png` - Screenshot showing 8-minute delay
- `queries/` - SQL analysis queries (9 queries total)
- `results/` - Query results and findings
- **`FINDINGS.md`** - ⭐ Comprehensive root cause analysis (Airflow 46% + Metabase 31%)
- **`EXECUTIVE_SUMMARY.md`** - One-page summary for stakeholders
- **`CHOKE_POINTS_ANALYSIS.md`** - ⭐ NEW: 10-minute period analysis showing n8n Shopify as primary culprit

