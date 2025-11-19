# Monitor Platform: Streaming vs Batch Architecture Comparison

**Date:** November 18, 2025  
**Purpose:** Evaluate cost optimization through architecture changes (latency SLA reduction)  
**Audience:** Julia Le, Data Engineering, Product Team  
**Status:** Proposal for Review - **MAJOR REVISION AFTER ARCHITECTURE REVIEW**

---

## ⚠️ CRITICAL UPDATE

**Original assumption:** System uses continuous streaming → batch would save $40K-$78K/year (20-40%)

**Actual finding:** System ALREADY uses 5-minute micro-batching with partitioned tables

**Revised estimate:** Larger batch windows would save $10K-$29K/year (5-15%) at most

**Key discovery:** shipments table is partitioned on `retailer_moniker` and clustered, meaning MERGE operations likely use partition pruning and don't scan the full 19.1 TB.

**Recommendation:** Data retention optimization may offer better ROI than latency optimization.

---

## Executive Summary

This document compares the current **5-minute micro-batch** architecture with proposed **larger batch window** architectures (1/6/12/24 hours) for Monitor platform data ingestion. 

**IMPORTANT CORRECTION:** After reviewing the actual architecture documentation, the current system is NOT continuous streaming. It already uses Dataflow micro-batches every 5 minutes with partitioned MERGE operations.

**Key Question:** Would increasing batch windows from 5 minutes to 1/6/12/24 hours reduce costs enough to justify the increased data latency?

**Critical Finding:** The shipments table is already partitioned on `retailer_moniker` and clustered on `order_date`, `carrier_moniker`, `tracking_number`. This means MERGE operations already benefit from partition pruning and may NOT scan the full 19.1 TB table.

**Implication:** Cost savings from larger batch windows are likely **much smaller** than initially estimated ($40K-$78K). The system is already optimized for efficient micro-batch processing.

---

## Current Architecture (5-Minute Micro-Batch)

### Component Overview

```
┌─────────────────┐
│  Shipment/Order │
│     Events      │
│  (from Narvar   │
│   platform)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Pub/Sub      │  Cost: $24,528/year (shipments + orders)
│  Topics:        │  - Continuous message flow
│  - shipments    │  - Message buffering
│  - orders       │  - Load: ~2400 msgs/s
│                 │    (~270M msgs/day)
└────────┬────────┘
         │
         │  Every 5 minutes (micro-batch for shipments)
         │  Continuous streaming (for orders)
         │
         ├─────────────────────┐
         │                     │
         ▼                     ▼
┌──────────────────┐  ┌──────────────────┐
│  Cloud Dataflow  │  │  Cloud Dataflow  │
│  (shipments)     │  │    (orders)      │
│                  │  │                  │
│  - Micro-batch   │  │  - Streaming     │
│    every 5 mins  │  │    continuous    │
│  - Deduplication │  │  - Streaming     │
│  - MERGE to BQ   │  │    inserts       │
│                  │  │                  │
│  Cost: ???       │  │  Cost: $21,852   │
└────────┬─────────┘  └────────┬─────────┘
         │                     │
         ▼                     ▼
┌──────────────────────────────────────────┐
│         BigQuery Tables                   │
│                                          │
│  monitor_base.shipments  (19.1 TB)      │
│    - PARTITIONED on retailer_moniker    │
│    - CLUSTERED on order_date,           │
│      carrier_moniker, tracking_number   │
│    - Updated via MERGE (288x/day)       │
│                                          │
│  monitor_base.orders     (88.7 TB)      │
│    - Updated via streaming inserts      │
│    - Structure TBD                      │
│                                          │
│  Latency: 5 minutes (shipments)         │
│           Real-time (orders)            │
└──────────────────────────────────────────┘

QUESTION: Where does the $149,832 "shipments" cost come from?
- Is it Dataflow infrastructure for shipments pipeline?
- Is it BigQuery MERGE compute (slot-hours)?
- Is it split across multiple cost centers?
```

### Cost Breakdown (Current)

| Component | Annual Cost | Characteristics |
|-----------|-------------|-----------------|
| **Dataflow (shipments micro-batch)** | $149,832* | 288 MERGE operations/day (every 5 mins) |
| **Dataflow (orders streaming)** | $21,852 | Continuous streaming inserts |
| Pub/Sub | $24,528 | Message buffering (~270M msgs/day) |
| **Total Data Ingestion** | **$196,212** | 5-minute micro-batch SLA |

*Note: The $149,832 cost was previously attributed to "App Engine" but the architecture doc shows Dataflow is used for shipments MERGE operations. This needs clarification.

### Technology Details

**shipments (Dataflow Micro-Batch MERGE):**
- **Architecture:** Apache Beam micro-batch pipeline (5-minute windows)
- **Operation:** Dataflow consumes from Pub/Sub every 5 minutes, deduplicates, and MERGEs into BigQuery
- **Deduplication:** Based on `tracking_detail_id` and `ingestion_timestamp`
- **Table Scans:** **CRITICAL - Likely partition-pruned**
  - Table is partitioned on `retailer_moniker`
  - Clustered on `order_date`, `carrier_moniker`, `tracking_number`
  - Each MERGE likely scans only relevant retailer partition(s), not full 19.1 TB
  - **This significantly reduces the cost benefit of larger batch windows**
- **Resource Pattern:** n1-standard-1 machines, Min 2 / Max 5 workers
- **Data Latency:** 5 minutes
- **Load:** ~2400 msgs/s, ~270 million messages/day
- **Reference:** [Dataflow Batch Pipelines](https://cloud.google.com/dataflow/docs/guides/deploying-a-pipeline#batch-pipelines)

**orders (Dataflow Streaming):**
- **Architecture:** Apache Beam streaming pipeline (continuous)
- **Operation:** Continuous data ingestion via BigQuery streaming inserts API
- **Workers:** Persistent worker VMs running 24/7
- **Resource Pattern:** Fixed allocation for streaming
- **Data Latency:** Near-real-time
- **Table Size:** 88.7 TB (23.76 billion rows)
- **Reference:** [Dataflow Streaming Pipelines](https://cloud.google.com/dataflow/docs/concepts/streaming-pipelines)

---

## Proposed Architecture (Larger Batch Windows)

### Component Overview

```
┌─────────────────┐
│  Shipment/Order │
│     Events      │
│  (from Narvar   │
│   platform)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Pub/Sub      │  Cost: $24K-$25K/year (similar)
│  Topics:        │  - Longer message retention
│  - shipments    │  - Accumulates more messages
│  - orders       │  - Same daily volume
└────────┬────────┘
         │
         │  Scheduled execution
         │  (every 1/6/12/24 hours instead of 5 mins/streaming)
         │
         ├─────────────────────┐
         │                     │
         ▼                     ▼
┌──────────────────┐  ┌──────────────────┐
│  Cloud Dataflow  │  │  Cloud Dataflow  │
│  (shipments)     │  │    (orders)      │
│                  │  │                  │
│  - Larger batch  │  │  - Batch mode    │
│    windows       │  │    (vs streaming)│
│  - Deduplication │  │  - FlexRS option │
│  - MERGE to BQ   │  │  - Batch inserts │
│                  │  │                  │
│  Fewer runs/day  │  │  Scheduled runs  │
└────────┬─────────┘  └────────┬─────────┘
         │                     │
         ▼                     ▼
┌──────────────────────────────────────────┐
│         BigQuery Tables                   │
│                                          │
│  monitor_base.shipments  (19.1 TB)      │
│    - PARTITIONED on retailer_moniker    │
│    - CLUSTERED on order_date, ...       │
│    - Same structure (unchanged)         │
│    - Updated via MERGE (1-24x/day)      │
│                                          │
│  monitor_base.orders     (88.7 TB)      │
│    - Updated via batch inserts          │
│    - Structure unchanged                │
│                                          │
│  Latency: 1-24 hours (depending on SLA) │
│  MERGE Frequency: 1-24 times/day        │
└──────────────────────────────────────────┘
```

### Cost Estimates (Proposed - REVISED Conservative)

| Component | Current (5-min) | Proposed (1-24hr) | Savings | Confidence |
|-----------|-----------------|-------------------|---------|------------|
| **shipments (Dataflow)** | $149,832 | $130K-$145K | $5K-$20K | **Very Low** |
| **orders (Dataflow)** | $21,852 | $13K-$17K | $5K-$9K | Medium |
| Pub/Sub | $24,528 | $24K-$26K | $0-$1K | Medium |
| **Total** | **$196,212** | **$167K-$188K** | **$10K-$29K** | **Very Low** |

**Revised Savings Range:** 5-15% reduction in data ingestion costs (down from 20-40%)

**Why Much Lower Savings?**

1. **Partition Pruning Already Works:** Table is partitioned on `retailer_moniker`. Each MERGE likely scans only specific retailer partitions, not the full table. Going from 288 small scans to 24 larger scans doesn't save as much as expected.

2. **Dataflow Already Micro-Batches:** Current system uses batch processing (5-min windows), not continuous streaming. We're comparing "small batches" to "large batches", not "streaming" to "batch".

3. **Worker Allocation:** Dataflow workers (2-5 machines) might not scale down much with larger batch windows. They might just sit idle between batches.

4. **Pub/Sub Costs:** Longer retention has minimal cost impact. Savings here are negligible.

**MAJOR CONCERN:** The $149,832 shipments cost might NOT be primarily from BigQuery compute. If it includes Dataflow infrastructure costs, worker allocation, etc., then batch size changes may have minimal impact.

### Technology Details

**shipments (Batch MERGE via Airflow):**
- **Architecture:** Scheduled batch processing
- **Operation:** Accumulate events, process in bulk every X hours
- **Table Scans:** Hypothesis - one large scan vs many small ones
  - **Your insight:** "One huge table scan per day instead of multiple"
  - **Question:** Does MERGE logic allow for bulk updates, or does it still scan per-row?
  - **Validation needed:** Examine actual MERGE code
- **Resource Pattern:** Periodic compute bursts
- **Data Latency:** 1-24 hours (configurable)
- **Reference:** [BigQuery MERGE Statement](https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#merge_statement)

**orders (Dataflow Batch with FlexRS):**
- **Architecture:** Scheduled batch pipeline with FlexRS
- **Operation:** Process accumulated messages in scheduled windows
- **Workers:** On-demand worker allocation, uses preemptible VMs
- **Resource Pattern:** Intermittent resource usage
- **Cost Savings:** FlexRS offers discount but adds execution delay
- **Data Latency:** 1-24 hours + FlexRS delay (variable)
- **References:** 
  - [Dataflow Batch Pipelines](https://cloud.google.com/dataflow/docs/guides/deploying-a-pipeline#batch-pipelines)
  - [FlexRS Cost Optimization](https://cloud.google.com/dataflow/docs/guides/flexrs)

---

## Key Technical Questions to Resolve

### 1. CRITICAL: What is the $149,832 shipments cost?

**URGENT QUESTION:** The cost analysis shows $149,832 for shipments, but it's unclear what this represents:

**Option A: Mostly BigQuery MERGE compute**
- If this is primarily BigQuery slot-hours for MERGE operations
- Then larger batch windows *might* reduce costs through fewer operations
- But partition pruning already optimizes scans

**Option B: Mostly Dataflow infrastructure**
- If this is Dataflow worker costs (vCPU, memory, disk)
- Then batch window size may not matter much
- Workers might sit idle between larger batches
- Infrastructure costs remain similar

**Option C: Mixed (need breakdown)**
- Some percentage BigQuery compute
- Some percentage Dataflow infrastructure
- Need to understand the ratio to estimate savings potential

**Action Required:** Query DoIT billing or analyze traffic_classification to understand:
- How many slot-hours are used for MERGE operations?
- What's the cost breakdown between BigQuery and Dataflow?
- This determines if latency optimization is even worth pursuing

---

### 2. Dataflow MERGE Logic (shipments)

**Known Facts:**
- Table is partitioned on `retailer_moniker`
- Clustered on `order_date`, `carrier_moniker`, `tracking_number`
- MERGE happens every 5 minutes (288 times/day)
- Deduplicates on `tracking_detail_id` and `ingestion_timestamp`

**Questions to Answer:**
- Does the MERGE use partition pruning?
- How many bytes scanned per MERGE operation?
- Is it scanning full table (19.1 TB) or just relevant partitions (< 100 GB)?
- Would batching reduce bytes scanned, or just reduce operation count?

**Likely Scenario (based on partitioning):**
```sql
-- Current: 288 times per day
MERGE monitor_base.shipments T
USING (SELECT ...) S  -- 5 minutes of events
ON T.shipment_id = S.shipment_id
  AND T.retailer_moniker = S.retailer_moniker  -- partition pruning
WHEN MATCHED THEN UPDATE ...
WHEN NOT MATCHED THEN INSERT ...

-- Cost: Scans only affected retailer partitions
-- Example: If batch has events from 50 retailers,
--          scans 50 partitions, not all 284
-- Total scan: ~2-5 GB, not 19.1 TB

-- Proposed: 24 times per day (hourly)
-- Larger batch, more retailers per batch
-- Still uses partition pruning
-- Saves: Fewer operations, but similar bytes scanned per day
```

**Why savings are lower than expected:**
- Partition pruning means we're NOT scanning 19.1 TB per MERGE
- Going from 288 small batches to 24 large batches reduces overhead
- But doesn't dramatically reduce bytes scanned
- Savings come from: fewer operation initiations, less overhead

**Action:** Validate partition pruning is working and measure actual bytes scanned

---

### 3. Pub/Sub Cost Model

**Current understanding:**
- Pub/Sub pricing = data volume + operations + storage
- Reference: [Pub/Sub Pricing](https://cloud.google.com/pubsub/pricing)

**Question:** Does batching increase costs due to longer message retention?

**Analysis needed:**
- Current: Messages delivered within minutes, minimal retention
- Batch: Messages might sit in Pub/Sub for 1-24 hours
- Pub/Sub storage pricing: $0.27/GB-month for messages
- Do we pay more for longer retention than we save on operations?

**Example calculation:**
```
Daily shipment events: ~100,000 events/day * 5 KB = 500 MB/day

Real-time:
  - Average retention: 5 minutes
  - Storage cost: negligible

24-hour batch:
  - Average retention: 12 hours (half a day)
  - Storage cost: 500 MB * 0.5 days * $0.27/GB-month / 30 days
  - = minimal, probably < $10/month

Conclusion: Retention cost increase likely negligible
```

---

### 4. Dataflow Batch Savings

**Current:** orders streaming mode - $21,852/year

**Proposed:** Batch mode with FlexRS

**Reference:** [Dataflow Pricing](https://cloud.google.com/dataflow/pricing)

**Cost components:**
- vCPU hours
- Memory GB-hours  
- Persistent disk GB-hours
- Streaming Engine (streaming only)

**Savings opportunities:**
1. **Eliminate Streaming Engine costs** (only applies to streaming)
2. **Use FlexRS** for additional 35-40% discount (but adds delay)
3. **Resource efficiency** - batch can scale up/down vs steady-state streaming

**Conservative estimate:** 40-50% savings = $9K-$11K/year

**Aggressive estimate:** 60% savings with FlexRS = $13K/year

**Risk:** FlexRS jobs can be delayed if resources unavailable

---

## Architecture Comparison Table

| Aspect | Streaming (Current) | Batch (Proposed) | Trade-off |
|--------|---------------------|------------------|-----------|
| **Data Latency** | < 5 minutes | 1-24 hours | ⚠️ Business impact unclear |
| **Resource Pattern** | Continuous allocation | Periodic bursts | ✅ Batch more efficient |
| **Cost (estimated)** | $196K/year | $118K-$157K/year | ✅ 20-40% savings |
| **Operational Complexity** | Moderate (always-on) | Higher (scheduling) | ⚠️ More moving parts |
| **Query Performance** | Real-time updates | Delayed updates | ⚠️ Customer experience |
| **Infrastructure** | App Engine + Dataflow | Airflow + Dataflow | ⚠️ Migration effort |
| **Scalability** | Auto-scales | Scheduled capacity | ⚠️ Batch windows can overflow |
| **Risk** | Known/stable | Unknown/needs validation | ⚠️ Requires testing |

---

## Critical Assumptions to Validate

### Before Proceeding with Cost Modeling:

1. **✅ CRITICAL:** Examine shipments MERGE code to validate table scan hypothesis
   - Is it doing full scans or partition-pruned scans?
   - Can batch MERGE reduce scan costs?
   
2. **Medium Priority:** Analyze Pub/Sub retention and storage costs for batching
   - Does 24-hour retention significantly increase costs?
   
3. **Medium Priority:** Validate Dataflow batch vs streaming pricing delta
   - Review DoIT billing to see current Dataflow cost breakdown
   - Check if already using CUDs

4. **Low Priority:** Assess App Engine → Airflow migration effort
   - How complex is the current App Engine logic?
   - Can it be migrated to Airflow without rewrite?

---

## Latency Scenarios (REVISED)

**NOTE:** All estimates are REVISED DOWN based on corrected architecture understanding (micro-batch vs streaming).

### Scenario A: 1-Hour Batching

**Characteristics:**
- Process events every hour
- 24 MERGE operations per day (vs 288 currently)
- Data up to 1 hour stale (vs 5 minutes)
- Minimal customer impact

**Revised Savings:** 3-8% ($6K-$16K/year) - **down from $30K-$49K**

**Why lower?** Partition pruning already optimizes scans. Going from 288 to 24 operations saves overhead but not proportional compute.

---

### Scenario B: 6-Hour Batching  

**Characteristics:**
- Process events every 6 hours (4x per day)
- Data up to 6 hours stale
- Moderate customer impact
- Some cost savings

**Revised Savings:** 5-12% ($10K-$24K/year) - **down from $49K-$69K**

**Why lower?** Same partition pruning issue. Larger batches don't dramatically reduce bytes scanned, just operation count.

---

### Scenario C: 12-Hour Batching

**Characteristics:**
- Process twice daily (morning/evening)
- Data up to 12 hours stale
- Significant customer impact
- Moderate cost savings

**Revised Savings:** 7-15% ($14K-$29K/year) - **down from $59K-$78K**

**Business Risk:** 12-hour delay likely unacceptable for operational dashboards

---

### Scenario D: 24-Hour Batching (Daily)

**Characteristics:**
- Process once daily (overnight)
- Data up to 24 hours stale
- High customer impact
- Maximum cost savings (but still modest)

**Revised Savings:** 10-15% ($20K-$29K/year) - **down from $69K-$88K**

**Risks:** 
- Daily batch windows could become bottlenecks during peak periods
- 24-hour latency likely violates customer expectations
- Minimal savings don't justify business impact

---

## Risks and Concerns

### Technical Risks

1. **Pub/Sub Message Retention Limits**
   - Default: 7 days max
   - 24-hour batching should be fine
   - But spikes or failures could lose data
   - Mitigation: Monitor queue depth, alerting

2. **Batch Window Performance**
   - Large bulk MERGEs might take hours
   - Could delay downstream processes
   - Peak periods could exceed batch window
   - Mitigation: Test with peak volumes

3. **Data Consistency During Batch Window**
   - Data is stale between batch runs
   - Queries might see incomplete data
   - Need to handle partial updates
   - Mitigation: Clear batch timestamps, query guidelines

### Business Risks

4. **Customer Experience Degradation**
   - Retailers accustomed to real-time data
   - 24-hour delay could reduce product value
   - May impact operational dashboards
   - **Mitigation:** Query pattern profiling to understand actual needs

5. **SLA Violations**
   - Some retailers may have contracted latency SLAs
   - We don't have visibility into contracts
   - **Mitigation:** Product team review required

6. **Competitive Positioning**
   - Competitors may offer real-time data
   - Could be differentiator for Monitor
   - **Mitigation:** Survey customer requirements

---

## Recommendations for Next Steps

### Phase 1: Validation (Before Cost Modeling)

1. **✅ HIGH PRIORITY:** Examine shipments MERGE code
   - Validate table scan hypothesis
   - Understand current efficiency
   - Estimate realistic batch savings
   
2. **Query Pattern Profiling** (in parallel)
   - How fresh does data need to be?
   - Which retailers need real-time?
   - Can we offer tiered latency SLAs?

### Phase 2: Conservative Cost Modeling

3. **Model Conservative Scenarios**
   - Use lower-bound savings estimates
   - Factor in migration costs
   - Include operational complexity

### Phase 3: Business Validation

4. **Customer Impact Assessment**
   - Survey top 10 retailers on latency requirements
   - Identify real-time use cases
   - Understand compliance needs

### Phase 4: Pilot

5. **Controlled Test**
   - Select 5-10 low-risk retailers
   - Run batch pipeline in parallel
   - Measure actual cost savings
   - Validate customer acceptance

---

## References

### Google Cloud Documentation

1. **Dataflow:**
   - [Dataflow Streaming Pipelines](https://cloud.google.com/dataflow/docs/concepts/streaming-pipelines)
   - [Dataflow Batch Pipelines](https://cloud.google.com/dataflow/docs/guides/deploying-a-pipeline#batch-pipelines)
   - [FlexRS Cost Optimization](https://cloud.google.com/dataflow/docs/guides/flexrs)
   - [Dataflow Pricing](https://cloud.google.com/dataflow/pricing)
   - [Dataflow Cost Optimization Guide](https://cloud.google.com/dataflow/docs/optimize-costs)

2. **BigQuery:**
   - [MERGE Statement Documentation](https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#merge_statement)
   - [BigQuery Partitioning](https://cloud.google.com/bigquery/docs/partitioned-tables)
   - [BigQuery Clustering](https://cloud.google.com/bigquery/docs/clustered-tables)
   - [BigQuery DML Pricing](https://cloud.google.com/bigquery/pricing#dml-pricing)

3. **Pub/Sub:**
   - [Pub/Sub Pricing](https://cloud.google.com/pubsub/pricing)
   - [Pub/Sub Message Retention](https://cloud.google.com/pubsub/docs/replay-overview)
   - [Pub/Sub Batch Publishing](https://cloud.google.com/pubsub/docs/publisher#batch_publish)

4. **App Engine:**
   - [App Engine Standard Environment](https://cloud.google.com/appengine/docs/standard)
   - [App Engine Pricing](https://cloud.google.com/appengine/pricing)

5. **Cost Optimization:**
   - [Dataflow Committed Use Discounts](https://cloud.google.com/blog/products/data-analytics/save-with-new-dataflow-streaming-committed-use-discounts-cuds)
   - [GCP Cost Optimization Best Practices](https://cloud.google.com/architecture/cost-optimization)

---

## Conclusion

**MAJOR REVISION:** After reviewing the actual architecture documentation, the cost savings potential is **much lower** than initially estimated.

**Key Findings:**

1. **Current system already uses micro-batch processing** (5-minute windows), NOT continuous streaming
2. **Table is already optimized** with partitioning on `retailer_moniker` and clustering
3. **MERGE operations likely use partition pruning**, scanning only relevant partitions
4. **Expected savings: $10K-$29K/year (5-15%)**, not $40K-$78K

**Critical Path Forward:**

1. **URGENT: Clarify the $149,832 shipments cost breakdown**
   - Is this BigQuery compute, Dataflow infrastructure, or both?
   - How much is MERGE cost vs worker allocation cost?
   - This determines if batch size changes matter at all

2. **Analyze actual MERGE query patterns**
   - Confirm partition pruning is working
   - Measure bytes scanned per MERGE operation
   - Validate that larger batches would reduce total bytes scanned

3. **Profile customer latency requirements**
   - Understand business tolerance for delayed data
   - Identify high-value vs low-risk scenarios

4. **Consider alternative optimizations**
   - Data retention reduction may offer better ROI
   - Query optimization for heavy consumers (fashionnova)
   - Materialized views to reduce repeated computations

**My Assessment:**

- **Revised savings estimate:** $10K-$29K/year (5-15%) - **down from $40K-$78K**
- **Very low confidence** until we understand cost breakdown
- **Partition pruning significantly reduces the benefit of larger batch windows**
- **Focus should shift to data retention optimization** as primary cost lever

**Recommendation:** Before investing in latency SLA changes, we should:
1. Understand the actual cost drivers (MERGE vs infrastructure)
2. Validate partition pruning efficiency
3. Compare latency optimization vs retention optimization ROI

The business impact of delayed data may not be worth the relatively modest savings.

---

**Prepared by:** Sophia (AI) + Cezar  
**Date:** November 18, 2025  
**Status:** Draft for Review  
**Next Step:** Examine shipments MERGE code (pending your approval)

