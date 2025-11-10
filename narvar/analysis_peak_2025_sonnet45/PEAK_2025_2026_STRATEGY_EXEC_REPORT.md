# BigQuery Peak Capacity Strategy: Nov 2025 - Jan 2026
**Data Engineering Team - Strategic Approach**

---

## Executive Summary

The data team recommends an **ad-hoc reactive capacity management strategy** for the upcoming Nov 2025 - Jan 2026 peak period rather than pre-configuring additional capacity. This decision is driven by cost-benefit analysis showing that pre-loading capacity would cost **$58K-$173K** with uncertain ROI, while **empirical analysis of 129 critical incidents during 2025** reveals that **69% stem from automated processes** (inefficient pipelines), **23% from internal users** (growing Metabase/analytics usage), and only **8% from external customer load spikes**—none of which are resolved by adding capacity.

**Key Evidence**: Peak 2024-2025 was successfully managed at **~$63K/month average cost** using our current 1,700-slot configuration combined with reactive monitoring and incident response.

---

## Current Slot Allocation Structure

### Capacity Configuration

**Total Reserved Capacity**: 1,700 slots (managed in `bq-narvar-admin`)

| Commitment Tier | Slots | Rate | Monthly Cost |
|-----------------|-------|------|--------------|
| 3-year commitment | 500 | $0.036/hr | $12,960 |
| 1-year commitment | 500 | $0.048/hr | $17,280 |
| **Fixed Baseline** | **1,000** | - | **$30,240** |
| Pay-as-you-go autoscale | up to 700 | $0.060/hr | Variable |
| **Maximum Capacity** | **1,700** | - | - |

### Consumer Categories

BigQuery capacity serves three distinct consumer categories:

**EXTERNAL Consumers (~6% of slot capacity)**
- Individual Monitor projects (per-retailer query projects)
- Hub (Looker-based dashboards for retailers)
- **Priority**: P0 - Customer-facing APIs and dashboards
- **Note**: Monitor-base infrastructure (merge process) reclassified to AUTOMATED as it's batch processing, not direct customer queries

**AUTOMATED Processes (~79% of slot capacity)**
- Monitor-base infrastructure (~34% of total - retailer data merge/processing)
- Airflow/Composer ETL pipelines (~100 different scheduled jobs)
- Eric's data processing workflows
- GKE-based automated jobs
- CDP and other data pipelines
- **Priority**: P0 - Data pipeline SLAs and downstream dependencies

**INTERNAL Users (~15% of slot capacity)**
- Metabase queries (internal analytics)
- Ad-hoc analysis and reporting
- **Priority**: P1 - Internal analytics and business intelligence

---

## Cost Analysis: Why Pre-Loading is Unjustifiable

### Pre-Loading Cost Projection

For an 80-day peak period (Nov-Jan), the cost to pre-configure additional slots:

| Additional Slots | Total Peak Cost | Justification |
|------------------|----------------|---------------|
| +500 slots | $57,600 | Minimal buffer |
| +1,000 slots | $115,200 | Moderate expansion |
| +1,500 slots | $172,800 | Aggressive scaling |

**Calculation**: $0.06/slot-hour × 24 hours × 80 days = $115.20 per slot for entire peak

### Historical Performance (Peak 2024-2025)

Actual BigQuery reservation costs during last peak period:

| Month | Actual Cost | Configuration |
|-------|-------------|---------------|
| Nov 2024 | $55,187 | Current 1,700-slot setup |
| Dec 2024 | $65,515 | Current 1,700-slot setup |
| Jan 2025 | $68,323 | Current 1,700-slot setup |
| **Average** | **$63,008/month** | **Successfully managed** |

### Cost-Benefit Analysis

- **Current approach**: Successfully handled 2024-2025 peak at ~$63K/month
- **Pre-loading option**: Would add $58K-$173K for uncertain benefit
- **Root cause reality**: Empirical analysis of 129 critical incidents during 2025 shows **69% caused by automated processes** (inefficient pipelines), **23% by internal users** (growing trend), and **8% by external load spikes**
- **Proactive actions already taken**: Airflow job staggering implemented Oct 9, 2025 to reduce concurrent pipeline execution ([implementation details](https://github.com/narvar/cezar-mihaila-notebooks/blob/master/DTPL_6721_BQ_slot_usage/airflow_staggering_implementation/FINDINGS_NEXT_ACTIONS.md#-implementation-progress-update-october-9-2025))
- **Conclusion**: Pre-loading capacity does not address root cause—process optimization and internal query management are needed, not more slots

---

## Ad-Hoc Strategy for Nov 2025 - Jan 2026

### 1. Proactive Monitoring and Load Control

**Continuous Load Management (Automated)**

**Metabase Query Termination** (Running 24/7)
- **Automated Airflow DAG** runs every 10 minutes (continuous, not reactive)
- Kills Metabase queries running >10 minutes automatically
- **Addresses 23% of critical incidents** proactively (internal user queries)
- Preserves capacity for P0 external and automated workloads
- Operates continuously, tightened thresholds can be applied during peak if needed
- **Reference**: `composer/dags/query_opt_kill_metabase_user_queries/`

**Real-Time Monitoring and Alerting** (Automated DAG Every 10 Minutes)

Monitoring thresholds evaluate BigQuery job queue and execution times:

| Alert Level | Trigger Conditions (ANY met) | Response |
|-------------|------------------------------|----------|
| **INFO** | 20+ jobs (pending+running) OR<br>P95 pending time ≥6 min OR<br>P95 running time ≥6 min | Slack alert to #data-engineering |
| **WARNING** | 30+ jobs (pending+running) OR<br>P95 pending time ≥20 min OR<br>P95 running time ≥20 min | Slack alert to #data-engineering |
| **CRITICAL** | 60+ jobs (pending+running) OR<br>P95 pending time ≥50 min OR<br>P95 running time ≥50 min | Slack alert + VictorOps escalation* |

**VictorOps Escalation** (prevents alert fatigue):
- Triggers only for sustained issues: 2+ consecutive CRITICAL (20+ min) OR 4+ consecutive WARNING/CRITICAL (40+ min)
- 2-hour cooldown between pages during extended incidents
- **Reference**: `composer/dags/query_opt_monitor_bq_load/`

### 2. Reactive Response Toolkit (Incident Response)

**Step 1: Root Cause Identification**
- Follow [established runbook procedures](https://docs.google.com/document/d/1D9Ruy8oln0aFqr39AQ6nt4NwdHMIfxJjcB687whuWSo/edit?tab=t.0#heading=h.juw2omuyhu83)
- **Empirical evidence from 129 incidents in 2025**: 69% automated processes, 23% internal users, 8% external load
- Identify inefficient pipelines or large suboptimal queries flooding the system
- Attribute queries to consumer category (External/Automated/Internal) for targeted response

**Step 2: Temporary Capacity Burst**
- Increase pay-as-you-go slots temporarily ($0.06/slot-hour)
- Duration: Only until incident resolved (typically minutes to hours)
- Cost: Pay only for actual incident duration vs. $58K-$173K pre-commitment

**Step 3: Process and Query Optimization at Source**
- **For AUTOMATED (69% of incidents)**: 
  - Optimize pipeline queries, adjust schedules to off-peak hours
  - **Airflow staggering implemented Oct 9, 2025** to reduce concurrent DAG execution
  - Continue monitoring for further optimization opportunities
- **For INTERNAL (23% of incidents - growing trend)**: Audit Metabase dashboards, restrict auto-refresh, provide query efficiency training
- **For EXTERNAL (8% of incidents)**: Coordinate with customer success if load spike is genuine
- Prevent recurrence through code review, query monitoring, and best practices

### 3. Known Issues and Mitigation Plans

**Hub QoS Performance (Optimization In Progress)**
- Analysis identified 39% QoS violation rate for Hub (Looker dashboards) during Peak 2024-2025 critical stress periods
- Root cause: Dashboard query complexity, not capacity limits
- Mitigation: Dashboard query optimization ongoing, auto-refresh controls during peak

**Internal User Load Growth (Monitoring and Education)**
- Internal users now account for 23% of critical incidents (up from 12% historically)
- Pattern: Clusters during business hours (8am-2pm), end-of-month/year reporting periods
- Notable incidents: Jan 16, 2025 had 64 concurrent high-impact internal queries
- Mitigation: Metabase dashboard optimization, auto-refresh restrictions, query termination during critical periods, user education

---

## Work in Progress: Enhanced Capabilities

### Traffic Classification System (Ongoing Analysis)

Comprehensive categorization of BigQuery consumers across 43M+ historical jobs enables:
- **Faster incident attribution**: Quickly identify which consumer category causing stress
- **Targeted response**: Apply appropriate mitigation by consumer type
- **Better visibility**: Real-time dashboard of capacity consumption by category

### Quality of Service (QoS) Targets by Consumer Type

| Consumer Category | QoS Target | Business Impact |
|-------------------|------------|-----------------|
| EXTERNAL | <30 seconds | Direct customer-facing - retailers experiencing delays |
| AUTOMATED | Complete before next run | Pipeline failures cascade to downstream dependencies |
| INTERNAL | <5-10 minutes | Analytics delays affect internal decision-making |

---

## Risk Assessment

### Acknowledged Risks

**Potential Customer Impact**
- External retailers (Monitor, Hub) could experience query slowdowns during unmanaged incidents
- Duration: Typically resolved within minutes via automated process termination or capacity burst
- Probability: Low - only 8% of 2025 incidents caused by external load spikes; 92% are internal (69% automated + 23% users)

**Mitigation Strategy**
- Real-time monitoring enables rapid detection (<2 minutes)
- Automated response toolkit (query termination) provides immediate relief
- Temporary capacity burst available within minutes if needed
- On-call data engineering team for escalation

**Cost-Risk Trade-off**
- **Risk**: Low probability of customer impact during incidents
- **Certainty**: $58K-$173K cost to pre-load capacity
- **Decision**: Accept manageable risk over certain high cost

---

## Alternative Options Not Pursued

### Option A: Separate Reservations by Consumer Category

**Approach**: Isolate external, automated, and internal workloads into dedicated slot pools

**Decision**: Defer until after peak period
- **Risk**: Complex to implement during peak season
- **Concern**: Potential for resource underutilization across pools
- **Timeline**: Consider for post-peak optimization (Feb 2026+)

### Option B: Pre-Load Additional Capacity (500-1,500 Slots)

**Approach**: Proactively expand reservation before peak season

**Decision**: Not justified by cost-benefit analysis
- **Cost**: $58K-$173K with uncertain ROI
- **Evidence**: Peak 2024-2025 successfully managed at ~$63K/month with current setup
- **Root Cause**: Most incidents not caused by capacity exhaustion
- **Conclusion**: Does not address actual root cause (human query errors)

---

## Conclusion

The data team's ad-hoc capacity strategy for Nov 2025 - Jan 2026 peak balances cost management with operational responsiveness. By investing in monitoring and reactive tools rather than pre-configured capacity, we:

1. **Control costs**: Avoid $58K-$173K uncertain pre-commitment
2. **Address root causes**: Empirical analysis of 129 incidents in 2025 shows 69% stem from automated process inefficiencies and 23% from internal users—optimizing code/schedules and managing internal analytics is more effective than adding capacity
3. **Maintain flexibility**: Pay only for actual incident duration via temporary bursts
4. **Proven approach**: Successfully managed Peak 2024-2025 at ~$63K/month
5. **Accept informed risk**: Only 8% of incidents from external load spikes; 92% are internal (optimizable); low probability customer impact vs. certain high cost

**Recommendation**: Proceed with ad-hoc strategy, monitor closely during peak, and evaluate post-peak whether architectural changes (separate reservations) are warranted for future seasons.

---

## Appendix: Root Cause Analysis Methodology

### Empirical Incident Attribution

To validate the strategic approach, we conducted a rigorous root cause analysis of all critical stress incidents during 2025 (10-minute windows where concurrent demand exceeded thresholds).

**Method**:
1. Identified all jobs running during each critical window
2. Calculated "blame score" based on concurrent slot consumption (>85 slots = high-impact query)
3. Attributed each incident to the consumer category with highest blame score
4. Analyzed 2 periods: Peak_2024_2025 (Nov 2024-Jan 2025) and Baseline_2025_Sep_Oct (Sep-Oct 2025)

**Results** (129 incidents in 2025):

| Root Cause Category | Count | Percentage | Interpretation |
|---------------------|-------|------------|----------------|
| AUTOMATED Processes | 89 | **69%** | Inefficient pipelines, scheduled jobs, merge processes |
| INTERNAL Users | 30 | **23%** | Ad-hoc queries, Metabase dashboards (growing trend) |
| EXTERNAL Load | 10 | **8%** | Genuine customer demand spikes (rare) |

**Key Insights**: 
- **92% of incidents are internal to Narvar** (69% automated + 23% users) and can be optimized through better query design, scheduling adjustments, and resource limits—not by adding capacity
- **INTERNAL usage growing**: Increased from 12% (historical) to 23% (2025), requiring enhanced Metabase governance
- **EXTERNAL remains minimal**: Only 8% from customers, validating low customer risk

**Data Source**: `narvar-data-lake.query_opt.traffic_classification` (43.8M classified jobs)  
**Analysis Query**: Root cause attribution SQL query joining critical stress windows with job execution data to calculate blame scores per consumer category

---

**Prepared by**: Data Engineering Team  
**Date**: November 10, 2025  
**Review Period**: Nov 2025 - Jan 2026  
**Next Review**: February 2026 (post-peak retrospective)

