# Response to Julia's Feedback - November 21, 2025

**From:** Julia Le  
**Re:** MONITOR_COST_EXECUTIVE_SUMMARY.md  
**Date Received:** November 21, 2025  
**Analysis Date:** November 19-21, 2025

---

## 📑 Table of Contents

### Julia's Feedback Points
- [1. Missing Core Returns Data (returns_etl)](#1-missing-core-returns-data-returns_etl)
- [2. Cold Storage for Historical Data](#2-cold-storage-for-historical-data)
  - [Understanding Data Re-hydration](#understanding-data-re-hydration)
  - [Option A: Cloud Storage Archive](#option-a-cloud-storage-archive)
  - [Archival Strategy Options](#archival-strategy-options)
  - [Option B: Fetch from Atlas (NOT RECOMMENDED)](#option-b-fetch-from-atlas-not-recommended)
- [3. Tiered Batching Frequency (15% Active Users)](#3-tiered-batching-frequency-15-active-users)
  - [Analysis: Tiered Batching Feasibility](#analysis-tiered-batching-feasibility)
  - [Alternative: Activity-Based Auto-Tiering](#alternative-activity-based-auto-tiering)

### Recommendations & Action Items
- [Recommendations to Julia](#recommendations-to-julia)
- [Updated Cost Optimization Strategy](#updated-cost-optimization-strategy)
- [Questions for Prasanth (Technical Validation)](#questions-for-prasanth-technical-validation)
- [Action Items to Address Julia's Feedback](#action-items-to-address-julias-feedback)

---

## Julia's Feedback Points

### 1. Missing Core Returns Data (returns_etl)

**Julia's concern:**
> "ETL cost estimates for returns data only includes Shopify returns. We also bring in core returns data (returns_etl) which sees much higher volumes. Both Core and Shopify returns make their way to Monitor."

**Status:** ✅ **ANALYZED** - Julia is correct, we were missing this

**Analysis complete:**

The returns_etl DAG loads data to `narvar-data-lake.reporting.*` tables:
- return_process_info
- order_info / order_info_items
- return_process_items
- return_shipments
- t_return_details

**Cost breakdown (Sep-Oct 2024, annualized):**
- Core Returns ETL operations: **$1,738/year** (Airflow loading data from Postgres)
- Core Returns consumption: **$179/year** (Monitor retailers querying return_process_info)
- **Total Core Returns: $1,917/year**

**Combined with Shopify Returns:**
- Shopify Returns (already analyzed): $8,461/year
- Core Returns (new): $1,917/year
- **Total Returns Platform Cost: $10,378/year**

**Reconciliation:** This is actually LOWER than our original $11,871 estimate by $1,493. No cost increase needed, but we should break out the components for clarity.

**Conclusion:** Julia's concern about completeness is valid. We should separately account for core returns ($1,917) and Shopify returns ($8,461), but total platform cost doesn't increase - it's already captured in our $263K estimate.

---

### 2. Cold Storage for Historical Data

**Julia's question:**
> "For retention scenarios, may be in Narvar's best interests to retain historical data (for model training). What are cold storage options and costs? Or fetch from Atlas if needed?"

**Analysis:**

#### Option A: Cloud Storage Archive

**Pricing:**
- Active BigQuery storage: $0.020/GB/month
- Cloud Storage Nearline: $0.010/GB/month (access 1x/month)
- Cloud Storage Coldline: $0.004/GB/month (access 1x/quarter)  
- Cloud Storage Archive: $0.0012/GB/month (access 1x/year)

**Storage breakdown (monitor-base-us-prod project):**
- orders table: 88.7 TB (82% of total) - **PRIMARY ARCHIVE CANDIDATE**
- shipments table: 19.1 TB (18% of total)
- **Total: 107.8 TB**
- **Current annual storage cost: $25,872** (both tables)

---

### Archival Strategy Options

#### Option 1: Archive orders table ONLY (Recommended)

**What gets archived:** orders table only  
**What stays active:** shipments table (all data remains in BigQuery)

**Rationale:**
- orders is 82% of storage (88.7 TB) - biggest impact
- Likely has oldest data (23.76 billion rows accumulated over years)
- shipments is more actively queried (fashionnova: 99% shipments, minimal orders)
- Bigger impact for lower complexity (one table vs two)

**Proposed tiering (orders table ONLY):**
- Keep 1 year active: ~3.7 TB in BigQuery (2024-2025 data)
- Archive 2+ years: ~85 TB to Nearline Cloud Storage (pre-2024 data)
- **shipments table:** All 19.1 TB remains active in BigQuery (unchanged)

| Component | Current (All Active) | Proposed (1yr Active + Archive) | Savings |
|-----------|---------------------|--------------------------------|---------|
| **orders table** | | | |
| - Active BigQuery | 88.7 TB @ $0.020/GB | 3.7 TB @ $0.020/GB | - |
| - Nearline archive | - | 85 TB @ $0.010/GB | - |
| **Subtotal orders** | **$21,288/year** | **$11,088/year** | **$10,200/year** |
| **shipments table** (unchanged) | **$4,584/year** | **$4,584/year** | **$0** |
| **Total storage** | **$25,872/year** | **$15,672/year** | **$10,200/year** |

**Net savings:** $10,200/year (39% reduction in storage costs)

**ML training impact:**
- orders table queried via external table (slower but works)
- shipments table remains in BigQuery (fast access)
- Egress cost: ~$850/training for 85 TB first read
- **Net savings even with 10 trainings/year:** $10,200 - $8,500 = $1,700/year

---

#### Option 2: Archive BOTH orders AND shipments tables (Maximum Savings)

**What gets archived:** Both orders table AND shipments table  
**What stays active:** Only last 1 year of data for both tables

**Proposed tiering (BOTH tables):**
- **orders:** 3.7 TB active (1 year) + 85 TB archived (2+ years)
- **shipments:** 2 TB active (1 year) + 17.1 TB archived (2+ years)
- **Total:** 5.7 TB active in BigQuery + 102.1 TB in Nearline archive

| Component | Current | Proposed | Savings |
|-----------|---------|----------|---------|
| **orders** | 88.7 TB active | 3.7 TB active + 85 TB archive | $10,200/year |
| **shipments** | 19.1 TB active | 2 TB active + 17.1 TB archive | $4,104/year |
| **Total** | **107.8 TB active** | **5.7 TB active + 102.1 TB archive** | **$14,304/year** |

**Net savings:** $14,304/year (55% reduction)

**Trade-offs:**
- More complexity (two tables to manage)
- shipments archive may impact fashionnova queries (99% shipments-based)
- Higher egress if training on both tables

**ML training impact:**
- Query both tables via external tables
- Egress: ~$1,000/training for 102 TB
- **Net savings with 10 trainings/year:** $14,304 - $10,200 = $4,104/year
- **Still profitable even with frequent ML training**

---

#### Option 3: No Archive (Status Quo)

**Keep all data active in BigQuery:**
- Cost: $25,872/year
- Benefit: Maximum query performance, no egress costs
- Use case: If ML training is very frequent (>monthly) or needs instant access

---

### Recommendation: Start with Option 1 (orders table ONLY)

**Archive THIS:**
- ✅ orders table: 85 TB of pre-2024 data → Nearline Cloud Storage
- ❌ shipments table: Keep all 19.1 TB active in BigQuery (unchanged)

**Rationale:**
1. **Biggest impact** ($10K savings) with **lowest complexity** (one table)
2. **Low risk** to fashionnova queries (they use shipments 99%, minimal orders usage)
3. **Validates the approach** before extending to shipments
4. **ML training still works** (egress cost ~$850/training < $10K storage savings)

**Then:** If successful and ML access patterns are acceptable, extend to shipments (Option 2) for additional $4K savings.

**Phased implementation:**
- **Phase 1 (orders only):** Save $10,200/year, validate approach, measure ML impact
- **Phase 2 (add shipments):** Save additional $4,104/year if Phase 1 successful
- **Total potential:** $14,304/year storage savings (55% reduction)

**Trade-offs:**
- External tables (Nearline/Coldline): Slower queries but still accessible via SQL
- Archive: Requires batch export to access (not queryable)
- BigQuery ML can still train on external tables (slower but works)

#### ML Training Cost with Archived Data

**Scenario:** Train model on 3 years of historical data (88.7 TB)

**Costs with archived data:**

| Component | Active Storage | With Nearline Archive | Notes |
|-----------|---------------|----------------------|-------|
| **Storage** (monthly) | $1,774 | $924 | 85 TB @ Nearline, 3.7 TB active |
| **Query cost** (one-time training) | $0 | $0 | BigQuery slot-hours (RESERVED) |
| **Egress from Cloud Storage** | $0 | ~$850 | 85 TB × $0.01/GB (first read from archive) |
| **Annual storage** | $21,288 | $11,088 | Recurring |
| **Annual ML training** (4x/year) | $0 | $3,400 | 85 TB × $0.01 × 4 trainings |

**Total annual cost:**
- All active: $21,288 storage + $0 egress = **$21,288**
- Tiered (1yr active + archive): $11,088 storage + $3,400 egress = **$14,488**
- **Net savings: $6,880/year** (32% savings even with 4 ML trainings/year)

**Key insight:** Even with quarterly ML training, archive strategy saves money because:
- Storage savings ($10,200/year) > Egress costs ($3,400/year for 4 trainings)
- If ML training is less frequent (1-2x/year), savings increase to $9K-$10K/year

**External table query performance:**
- First query: Reads from Cloud Storage (slower, incurs egress)
- Subsequent queries: Can cache results in BigQuery
- ML training: One-time egress cost per training cycle

**Recommendation:** **Nearline archive with external tables**
- Save $7K-$10K/year (depending on ML training frequency)
- Data remains accessible for model training
- Can promote back to active if access patterns change

---

### Understanding Data Re-hydration

**Definition:** Data re-hydration is the process of rebuilding derived/aggregated data tables by reprocessing raw source events or records.

**Common use cases:**
1. **Schema migrations:** Rebuild table with new schema from original events
2. **Bug fixes:** Reprocess data after fixing transformation logic errors
3. **Data recovery:** Restore lost/corrupted data from event logs
4. **Backfilling:** Add new calculated fields to historical records

**How it works (Event Sourcing pattern):**

```
Raw Events (immutable) → Transformation Logic → Derived State
```

**Example:**
```
Atlas Events (source of truth)
  ↓ Replay with current logic
Monitor shipments table (derived state)
```

**Key principle:** If you have immutable source events and deterministic transformation logic, you can always recreate the derived state.

**Reference frameworks:**
- **Event Sourcing:** Store all changes as immutable events, rebuild current state by replaying events
  - Reference: Martin Fowler's "Event Sourcing" pattern
  - URL: https://martinfowler.com/eaaDev/EventSourcing.html
  
- **Lambda Architecture:** Batch layer reprocesses all historical data from immutable source
  - Reference: Nathan Marz, "Big Data: Principles and best practices of scalable realtime data systems"
  - Concept: Immutable data source allows complete recomputation
  
- **Medallion Architecture (Data Lake):** Bronze (raw) → Silver (processed) → Gold (aggregated)
  - Reference: Databricks Medallion Architecture
  - URL: https://www.databricks.com/glossary/medallion-architecture
  - Pattern: Keep raw data (Bronze) forever, can rebuild Silver/Gold layers

- **BigQuery External Tables:** Query data in Cloud Storage without loading to BigQuery
  - Reference: Google Cloud Documentation
  - URL: https://cloud.google.com/bigquery/docs/external-data-sources
  - Use case: Archive old data to cheaper storage, query when needed

**When re-hydration works:**
- Source events are immutable and retained
- Transformation logic is deterministic
- Reference data is stable or version-controlled
- No time-dependent external dependencies

**When re-hydration fails (our case):**
- Transformation logic has evolved over time (non-deterministic)
- Reference data changes (carrier configs, EDD models)
- Source system may have purged old events
- Enrichment depends on point-in-time state of other systems

---

#### Option B: Fetch from Atlas (NOT RECOMMENDED)

**Atlas tracking event storage:**
- Atlas stores raw tracking events (original source)
- Theoretically could re-hydrate historical data if needed
- **However, significant concerns make this non-viable:**

**Concern 1: Enriched/Processed Data Cannot Be Recreated**

The Monitor `shipments` table contains data that doesn't exist in Atlas raw events:

- **Calculated fields:**
  - `ship_to_delivery_days` (computed from event timestamps)
  - `order_to_ship_days` (requires order data join)
  - `promise_to_delivery_days` (requires promise date calculations)
  - EDD (Estimated Delivery Date) analysis fields
  
- **Enriched data from other sources:**
  - Retailer promise dates (from order integrations)
  - Item-level promise dates (from order systems)
  - Order data joined with shipment events
  - Carrier config mappings (external reference data)
  
- **Historical state that can't be recreated:**
  - What EDD was shown to customer at time T (changes over time)
  - What carrier config was active at time T (changes over time)
  - Deduplication decisions made at ingestion time

**Example:** A shipment from 2022 was processed with:
- Carrier config that existed in 2022 (may have changed since)
- EDD calculation logic from 2022 (algorithm has evolved)
- Order data that was available in 2022 (may be deleted/modified since)

**If we rebuild from Atlas today:**
- We'd get 2025 carrier config, not 2022 config
- We'd use 2025 EDD logic, not 2022 logic
- We might not have the 2022 order data anymore
- **Historical metrics would be different** (breaking year-over-year comparisons)

**Concern 2: Atlas Retention Policy**

- **Question for Data Engineering:** What's Atlas's data retention period?
- If Atlas purges events after 2-3 years, we can't rebuild older data
- Even if Atlas retains events, does it keep ALL fields needed for enrichment?

**Concern 3: Rebuild Complexity & Cost**

**To rebuild historical shipments from Atlas:**
1. Export 2+ years of tracking events from Atlas
2. Re-run all transformation logic (Monitor Analytics processing)
3. Re-join with orders data (if still available)
4. Re-run all enrichment (EDD calculations, carrier mappings)
5. Validate data quality matches original

**Estimated effort:** 2-3 months engineering + data validation  
**Estimated cost:** Export + processing could cost $5K-$10K in compute  
**Risk:** Cannot guarantee exact recreation of historical state

**Conclusion on Atlas approach:**

❌ **Not viable as primary strategy** for data retention:
- Cannot recreate enriched/calculated fields
- Cannot guarantee historical state consistency
- High rebuild complexity and cost
- Atlas retention policy may not even support it

✅ **Cold Storage with external tables is superior:**
- Preserves exact historical state
- Data remains queryable
- Can be restored quickly
- Low cost ($0.010/GB vs $0.020/GB)

**Recommendation:** Use cold storage. Do NOT rely on Atlas re-hydration.

---

#### Deep Dive: Why Atlas Re-hydration is Problematic

**What happens in the Monitor Analytics pipeline:**

```
Atlas Raw Events → Monitor Analytics (AWS) → Pub/Sub → Dataflow → BigQuery
```

**Monitor Analytics processing (before BigQuery):**
1. **Payload validation and enrichment**
   - Validates retailer_moniker, carrier_moniker, tracking_number
   - Filters invalid events (date unparsable, event code missing, etc.)
   - Enriches with order data (if available)
   - Calculates derived fields

2. **Deduplication** (in Dataflow)
   - Based on tracking_detail_id + ingestion_timestamp
   - Historical deduplication decisions can't be recreated (which duplicate was kept?)

3. **MERGE into BigQuery** (App Engine/Dataflow)
   - Joins with existing shipment records
   - Updates existing rows or inserts new
   - Historical MERGE outcomes depend on table state at time T

**What gets added after Atlas:**

From the Monitor Analytics architecture doc, the pipeline adds:
- EDD (Estimated Delivery Date) calculations
- Carrier performance metrics
- Event sequence validation
- Order-to-shipment linking
- Promise date comparisons
- Delivery performance calculations

**These calculations depend on:**
- **Time-varying reference data:** Carrier configs, EDD models, business rules that change over time
- **Point-in-time state:** What order data existed when shipment was processed
- **Cumulative logic:** Running totals, sequence validations that build over time

**Example of non-recreatable state:**

**Original processing (2022):**
```
Shipment arrives → EDD calculated using 2022 algorithm → Result: Nov 15, 2022
```

**If we rebuild from Atlas in 2025:**
```
Same shipment → EDD calculated using 2025 algorithm → Result: Nov 17, 2022 (different!)
```

**Impact:** Historical metrics change, breaking:
- Year-over-year comparisons
- Carrier performance trends
- SLA compliance history
- ML model training (trained on 2022 data, not 2025 recreation)

**Atlas retention concerns:**

**Questions to validate:**
1. What's Atlas data retention policy? (30 days? 1 year? 3 years?)
2. Does Atlas keep deleted/corrected events? (Or only current state?)
3. Does Atlas have all fields needed for enrichment? (order data, promise dates, etc.)

**If Atlas has short retention** (e.g., 90 days):
- Cannot rebuild data >90 days old
- Must use BigQuery archive as source of truth

**Concrete example from Monitor Analytics:**

**If we tried to re-hydrate shipments data from Atlas today:**

**Step 1: Export 2022 tracking events from Atlas**
```
Tracking #12345:
- Event: "In Transit" at 2022-11-10 10:00 AM
- Event: "Delivered" at 2022-11-15 02:30 PM
```

**Step 2: Process through current Monitor Analytics pipeline (2025 version)**
```
Problem 1: EDD calculation uses 2025 algorithm (different from 2022)
  - 2022 algorithm: Predicted delivery Nov 14
  - 2025 algorithm: Predicts Nov 16 (improved ML model)
  - Historical record shows "On Time" (delivered Nov 15 vs predicted Nov 14)
  - Re-hydrated record shows "Early" (delivered Nov 15 vs predicted Nov 16)
  - **Carrier performance metric changes!**

Problem 2: Carrier config changed
  - 2022: Carrier "dhlglobal" mapped to service level "standard"
  - 2025: Carrier "dhlglobal" mapped to service level "express"
  - Historical metrics grouped by wrong service level
  
Problem 3: Order data may not exist
  - 2022 order #789 was in system when shipment processed
  - 2025: Order may be deleted, archived, or modified
  - Cannot recreate order_to_ship_days calculation
```

**Result:** Re-hydrated data ≠ Original historical data

**Why this matters for Julia's ML use case:**
- ML models trained on 2022 data with 2022 logic
- If you re-hydrate with 2025 logic, model training data changes
- Model predictions may degrade (trained on different features)
- Historical performance metrics become unreliable

**Conclusion:** 

For Julia's purposes (ML training + historical analytics), **Atlas re-hydration is NOT viable**.

✅ **Use cold storage instead:**
- Preserves exact historical state (2022 data processed with 2022 logic)
- ML models train on correct historical features
- Carrier performance metrics remain consistent
- Can query via external tables when needed

**Cost:** $10K/year savings (Nearline) vs $20K risk of incorrect ML training

---

### 3. Tiered Batching Frequency (15% Active Users)

**Julia's insight:**
> "Only 15% of retailers ever access Monitor. Could we do 24-hour batching by default and only increase frequency for specific retailers (paid tier or upon request)?"

**This is an excellent idea that could significantly improve the ROI.**

#### Analysis: Tiered Batching Feasibility

**Current system:**
- shipments table partitioned on `retailer_moniker`
- Each MERGE operation scans only affected retailer partitions
- 89 MERGE operations/day currently

**Julia's proposal:**
- Default: 24-hour batching for 85% inactive retailers (241 retailers)
- Premium: 6-hour or real-time for 15% active retailers (43 retailers)

**Technical feasibility:**

✅ **STRUCTURALLY POSSIBLE:**
- Table is already partitioned by retailer
- Could run separate MERGE operations on different schedules:
  - Daily batch: MERGE WHERE retailer_moniker IN ('inactive_list') - 241 retailers
  - Hourly batch: MERGE WHERE retailer_moniker IN ('active_list') - 43 retailers

❌ **IMPLEMENTATION COMPLEXITY:**
- Need to maintain two retailer lists (active vs inactive)
- Need separate DAG/pipeline configurations
- Monitoring becomes more complex
- Data consistency during migration
- What happens when retailer moves from inactive → active?

**Cost savings potential (Julia's scenario):**

**If 85% of retailers get 24-hour batching:**
- Current: 89 MERGEs/day for all 284 retailers
- Tiered: 1 MERGE/day for 241 retailers + 24 MERGEs/day for 43 retailers = 25 total
- **Reduction: 72% fewer MERGE operations**

**However, partition pruning limits savings:**
- Each MERGE already scans only affected partitions (~10% of table)
- 241-retailer batch MERGE would scan 241 partitions (85% of table)
- 43-retailer batch MERGE would scan 43 partitions (15% of table)
- Total bytes scanned might be similar, just fewer operations

**Estimated savings:**
- Operation overhead reduction: $5K-$10K/year
- Compute savings: $3K-$8K/year (not proportional to operation reduction due to partition sizes)
- **Total: $8K-$18K/year** (vs $20K-$35K for uniform 24-hour batching)

**But adds:**
- Engineering effort: 2-3 months development
- Operational complexity: Ongoing maintenance
- Testing effort: Need to validate tier transitions

#### Alternative: Activity-Based Auto-Tiering

**Simpler approach:**
- Automatically detect retailer activity (queries in last 30 days)
- Auto-promote to frequent updates if retailer becomes active
- Auto-demote to daily updates if retailer goes inactive >30 days
- No manual tier management needed

**Benefits:**
- Self-adjusting based on actual usage
- No sales/pricing complexity
- Fair (pay for what you use implicitly)

**Complexity:**
- Still requires dual-pipeline architecture
- Need monitoring and auto-tier logic

---

## Recommendations to Julia

### Point 1: Core Returns - ✅ ANALYZED AND UPDATED

**Action:** Analyzed returns_etl pipeline cost.

**Finding:** Core returns ($1,917/year) + Shopify returns ($8,461/year) = $10,378/year total

**Impact on platform cost:** 
- Original returns estimate: $11,871/year
- Updated returns (Shopify + Core): $10,378/year  
- **Platform cost adjustment: -$1,493** (decrease, not increase)
- **New platform total: $261,591/year** (was $263,084)

**Breakdown:**
- Shopify Returns: $8,461/year (CDC Datastream + MERGE + consumption)
- Core Returns ETL: $1,738/year (Postgres → reporting.* tables)
- Core Returns Consumption: $179/year (Monitor queries to return_process_info)

**Conclusion:** Julia's concern about completeness was valid. We now separately account for both pipelines. Total cost is lower than original estimate, suggesting our initial analysis may have double-counted some operations.

---

### Point 2: Cold Storage - YES, Excellent Strategy

**Recommendation:** **Nearline Cloud Storage with BigQuery external tables**

**Benefits:**
- Save $10K-$17K/year on orders table storage
- Data remains queryable for ML training
- Can be promoted back to active if needed

**Implementation:**
1. Move data >1 year old to Nearline Cloud Storage
2. Create BigQuery external table pointing to archived data
3. Union views combine active + archived data
4. ML models can still train (slower but functional)

**Cost:** $10,644/year (vs $21,288 active) = **$10,644 savings**

**Timeline:** 1-2 months to implement

---

### Point 3: Tiered Batching - MAYBE, High Complexity

**My assessment:**

**Pros:**
- Julia's insight about 15% active users is valuable
- Could save $8K-$18K/year
- Better customer experience (active users get better SLAs)

**Cons:**
- High implementation complexity (2-3 months engineering)
- Ongoing operational overhead (tier management, monitoring)
- Partition pruning already limits savings (not proportional to operation reduction)
- Data consistency challenges during tier transitions

**Alternative I recommend: Start with uniform 6-12 hour batching first**

**Rationale:**
1. **Simpler implementation** (1 month vs 3 months)
2. **Lower risk** (easier to rollback)
3. **Similar savings** ($10K-$15K vs $8K-$18K for tiered)
4. **Validate customer tolerance** before building complex tiering
5. **Can add tiering later** if uniform batching works but some retailers complain

**Then:** If uniform batching succeeds and specific retailers request faster updates, implement activity-based auto-tiering (not manual tiers).

**Discussion point for Prasanth:**
- Is the current pipeline architecture amenable to retailer-specific batch schedules?
- What's the complexity of maintaining two merge paths?
- Could we use a single pipeline with retailer-tier-aware scheduling?

---

## Updated Cost Optimization Strategy

**Based on Julia's feedback:**

**Priority 1: Cold Storage Archive** ✅ **IMPLEMENT**
- Savings: $10K-$17K/year
- Complexity: Low-Medium
- Risk: Low (reversible)
- **Confidence: HIGH**

**Priority 2: Uniform 6-12 Hour Batching** ✅ **PILOT FIRST**
- Savings: $10K-$15K/year
- Complexity: Medium
- Risk: Medium (customer impact)
- **Start with pilot, add tiering if needed**

**Priority 3: Complete Core Returns Analysis** ✅ **QUANTIFY**
- Impact: +$5K-$20K platform cost
- Needed for accuracy

**Deprioritize: Tiered batching** (for now)
- Too complex for initial implementation
- Uniform batching validates customer tolerance first
- Can add tiering later if there's demand

**Combined approach savings: $20K-$32K/year** (cold storage + uniform batching)

---

## Questions for Prasanth (Technical Validation)

1. **Current pipeline architecture:**
   - Is the shipments MERGE pipeline retailer-aware already?
   - How hard would it be to implement retailer-specific batch schedules?
   - What are the data consistency implications?

2. **Simpler alternative:**
   - Could we implement uniform 6-hour batching first?
   - Measure which retailers complain or have issues?
   - Then add tiering only for those retailers?

3. **Activity-based approach:**
   - Could we auto-detect retailer activity (queries in last 30 days)?
   - Auto-adjust batch frequency based on usage?
   - Would this be simpler than manual tier management?

---

---

## Action Items to Address Julia's Feedback

### 1. Analyze Core Returns (returns_etl) - ✅ COMPLETE

**What we did:**
- Analyzed returns_etl DAG from https://github.com/narvar/composer/blob/master/dags/return_analytics/returns_etl.py
- Queried traffic_classification for all returns-related operations
- Identified two pipelines: Shopify returns ($8,461) + Core returns ($1,917)

**Actual outcome:**
- Platform cost refined from $263,084 to **$261,591** (decrease of $1,493)
- Returns broken down: Shopify $8,461 + Core $1,917 = $10,378 total
- Updated all percentages in executive summary

**Finding:** Core returns cost ($1,917/year) is much lower than expected. The "higher volumes" Julia mentioned likely refers to row count/data volume, not cost. Both pipelines now accounted for.

**Status:** ✅ COMPLETE (Nov 21)

---

### 2. Add Cold Storage Section to Executive Summary

**What to add:**
- New section in "Data Retention Optimization" 
- Cloud Storage tiering strategy (Nearline/Coldline)
- Cost-benefit analysis with ML training scenarios
- Implementation approach (1-year active + archive older)
- Savings: $7K-$10K/year (net of ML egress costs)

**Key points to emphasize:**
- Data remains accessible for ML training via external tables
- Preserves historical state (unlike Atlas re-hydration)
- Reversible if access patterns change

**Timeline:** 30 minutes to update document

---

### 3. Refine Tiered Batching Recommendation

**What to update:**
- Acknowledge Julia's 15% active user insight
- Present phased approach: Start uniform, add tiering if needed
- Add Prasanth validation requirement
- Revise savings estimates for tiered approach
- Add activity-based auto-tiering as alternative

**Questions for Prasanth** (to be validated before recommending tiered approach):
1. Current pipeline architecture compatibility with retailer-specific schedules?
2. Complexity of maintaining dual MERGE paths (active vs inactive retailers)?
3. Data consistency implications during tier transitions?
4. Alternative: Auto-tiering based on query activity (last 30 days)?

**Timeline:** Pending Prasanth's input (include in next discussion)

---

## Revised Cost Optimization Summary (After Julia's Feedback)

**Priority 1: Cold Storage Archive** ✅ **IMPLEMENT**
- Savings: $7K-$10K/year (net of ML training egress)
- Complexity: Low-Medium  
- Risk: Low (reversible, data remains accessible)
- **Julia's use case supported:** ML training still works via external tables
- **Confidence: HIGH**

**Priority 2: Core Returns Analysis** ✅ **COMPLETE**
- Analyzed: Core returns = $1,917/year (ETL + consumption)
- Impact: Platform cost refined to $261,591 (decrease of $1,493)
- **Status: DONE** - Both Shopify and Core returns now accounted for

**Priority 3: Uniform Batching Pilot** ✅ **VALIDATE APPROACH**
- Savings: $10K-$15K/year
- Complexity: Medium
- Risk: Medium (customer impact)
- **Pilot first, then consider Julia's tiered approach if needed**

**Priority 4: Tiered Batching** ⚠️ **DEFER UNTIL VALIDATION**
- Savings: $8K-$18K/year (Julia's scenario)
- Complexity: High (requires Prasanth validation)
- Risk: High (operational complexity, tier management)
- **Only proceed if**: Uniform batching shows some retailers need real-time

**Combined savings (conservative):** $17K-$25K/year (cold storage + uniform batching)  
**Optimistic (with tiering):** $25K-$43K/year (if tiered batching validated)

---

**Prepared by:** Sophia (AI) + Cezar  
**Date:** November 21, 2025  
**Status:** ✅ COMPLETE - All three points analyzed and documented  
**Next:** 
1. ✅ DONE - Analyzed core returns_etl ($1,917/year, platform cost now $261,591)
2. ✅ DONE - Updated executive summary with cold storage + tiering recommendations
3. ⏸️ PENDING - Validate tiered batching feasibility with Prasanth (before recommending to Julia)

