# Monitor Platform Optimization Playbook
## Total Cost Reduction Strategies (Consumption + Production)

**Purpose:** Comprehensive guide for optimizing both consumption and production costs  
**Target:** Monitor platform (applicable to Hub, Looker, Metabase with modifications)  
**Date:** November 14, 2025

---

## 🎯 Executive Summary

### Why This Matters

Traditional BigQuery optimization focuses on **consumption costs** (query execution). However, our analysis reveals:
- **Production costs are 97% of total Monitor platform costs** ($200,957 vs $6,418)
- **Query optimization reduces BOTH** consumption and production costs
- **ROI is 40-50x higher** when production costs are included

### Key Insight

**Reducing query slot-hours by 50% saves:**
- Consumption: ~$800/year (traditional view)
- Production: ~$34,000/year (hidden benefit) 🎯
- **Total: ~$34,800/year (true ROI)**

### Target Retailers

**Highest ROI (Top 5):**
1. **fashionnova:** $41K-$49K/year potential (42x consumption-only ROI)
2. **lululemon, nike, sephora:** $10K-$20K each (currently ON_DEMAND, different strategy)
3. **huckberry, rapha, onrunning:** $5K-$15K each

**Platform-Wide:** $100K-$200K/year from top 20 retailer optimizations

---

## 📊 Cost Model Understanding

### Production vs Consumption Costs

| Aspect | Consumption | Production |
|--------|-------------|------------|
| **What** | Query execution | Data creation & maintenance |
| **Components** | Slot-hours × rate | ETL compute + Storage + Pub/Sub |
| **Billing Model** | Per query execution | Continuous/scheduled operations |
| **Platform Share** | 3% ($6,418/year) | 97% ($200,957/year) |
| **Optimization Leverage** | Direct (1x) | **Indirect (40-50x)** 🚨 |

### Cost Attribution Model

Retailer's production cost share is calculated using hybrid model:
```
Share = 0.40 × (query_count / total) + 
        0.30 × (slot_hours / total) + 
        0.30 × (tb_scanned / total)
```

**Implication:** Reducing slot-hours has **30% direct impact** on production cost attribution, plus indirect effects through lower data access patterns.

---

## 🔧 Strategy 1: Query Optimization (HIGHEST IMPACT)

### 1.1 Partition Pruning

**What:** Add date/timestamp filters to limit data scanned

**Target Queries:** Any query without WHERE clause on partition column

**Example (Before):**
```sql
SELECT COUNT(*) 
FROM `monitor.v_shipments` 
WHERE carrier_moniker = 'ups'
```

**Example (After):**
```sql
SELECT COUNT(*) 
FROM `monitor.v_shipments` 
WHERE carrier_moniker = 'ups'
  AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)  -- 90-day window
```

**Impact:**
- **Slot-hour reduction:** 40-60% (depends on historical data volume)
- **Consumption savings:** $400-$600/year per high-volume retailer
- **Production savings:** $16K-$30K/year per high-volume retailer
- **Total savings:** $16.4K-$30.6K/year per retailer

**Implementation:**
1. Identify queries without partition filters (analyze query_text_sample)
2. Add appropriate date filters based on business requirements
3. Validate results match (important for correctness)
4. Monitor slot-hour reduction

**Effort:** Low (1-2 days per retailer)  
**Risk:** Low (if validated properly)  
**Priority:** 🚨 **CRITICAL - Do first**

---

### 1.2 Query Result Caching

**What:** Cache identical query results for 1-24 hours

**Target:** Repeated queries (e.g., dashboards with auto-refresh)

**Implementation:**
- BigQuery automatically caches for 24 hours (default ON)
- Ensure cache is enabled: Check job configuration
- For custom caching: Use application-level cache (Redis, Memcached)

**Impact:**
- **Query reduction:** 20-40% (typical for dashboard usage)
- **Consumption savings:** $320-$640/year per retailer
- **Production savings:** $13K-$27K/year per retailer
- **Total savings:** $13.3K-$27.6K/year per retailer

**Effort:** Very Low (verify cache enabled)  
**Risk:** Very Low (default BigQuery feature)  
**Priority:** 🚨 **HIGH - Quick win**

---

### 1.3 Materialized Views

**What:** Pre-compute expensive aggregations and JOINs

**Target:** Complex queries with GROUP BY, window functions, or multi-table JOINs

**Example Use Case:**
```sql
-- Instead of running this expensive query repeatedly:
SELECT 
  carrier_moniker,
  DATE(created_at) as date,
  COUNT(*) as shipment_count,
  AVG(delivery_days) as avg_delivery
FROM `monitor.v_shipments`
GROUP BY carrier_moniker, DATE(created_at)

-- Create materialized view:
CREATE MATERIALIZED VIEW `monitor.mv_daily_carrier_stats` AS
SELECT 
  carrier_moniker,
  DATE(created_at) as date,
  COUNT(*) as shipment_count,
  AVG(delivery_days) as avg_delivery
FROM `monitor.v_shipments`
GROUP BY carrier_moniker, DATE(created_at);

-- Then query the MV (much faster):
SELECT * FROM `monitor.mv_daily_carrier_stats`
WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY);
```

**Impact:**
- **Slot-hour reduction:** 60-80% for aggregation queries
- **Consumption savings:** $480-$900/year per retailer
- **Production savings:** $20K-$40K/year per retailer
- **Total savings:** $20.5K-$40.9K/year per retailer
- **Bonus:** Improved query latency (better UX)

**Effort:** Medium (1-2 weeks per retailer, need to identify patterns)  
**Risk:** Medium (MV refresh costs must be considered, usually <10% of query savings)  
**Priority:** ⚠️ **MEDIUM - High impact but requires analysis**

---

### 1.4 Query Simplification

**What:** Remove unnecessary JOINs, CTEs, or subqueries

**Target:** Over-complicated queries that can be rewritten more efficiently

**Example Patterns to Fix:**
1. **Unnecessary JOINs:** Joining tables but not using all columns
2. **Nested subqueries:** Can often be flattened
3. **Redundant CTEs:** Multiple CTEs doing similar work
4. **SELECT *:** Only select needed columns

**Impact:**
- **Variable** - depends on query complexity
- **Typical:** 20-40% slot-hour reduction per optimized query
- **Combined savings:** $10K-$25K/year for high-volume retailers

**Effort:** High (requires SQL expertise, case-by-case analysis)  
**Risk:** Medium (must validate results remain correct)  
**Priority:** ✅ **LOW-MEDIUM - Good long-term investment**

---

## 🏭 Strategy 2: Production Optimization (PLATFORM-WIDE IMPACT)

### 2.1 Optimize monitor_base.shipments Merge Operations

**What:** Improve the primary ETL pipeline efficiency

**Current State:**
- 6,256 merge jobs per 2 months = ~37,536/year
- 505,505 slot-hours per 2 months = ~3M/year
- $149,832/year in compute costs
- 24.18% of total BQ reservation capacity

**Optimization Strategies:**

#### A. Batch Size Optimization
- **Current:** Continuous small merges
- **Proposed:** Larger, less frequent batches
- **Expected:** 20-30% compute reduction ($30K-$45K/year)
- **Risk:** Slight latency increase (acceptable for most use cases)

#### B. Incremental Processing
- **Current:** May be scanning full table for each merge
- **Proposed:** Partition-based incremental merges
- **Expected:** 30-50% compute reduction ($45K-$75K/year)
- **Risk:** Complexity in partition management

#### C. Off-Peak Scheduling
- **Current:** Runs during peak business hours
- **Proposed:** Schedule during low-traffic windows (2-6 AM)
- **Expected:** Reduced contention, better QoS for queries
- **Benefit:** Indirect cost savings through better capacity utilization

**Total Platform Impact:** $50K-$90K/year savings

**Effort:** High (requires Airflow/Composer DAG changes, testing)  
**Risk:** High (affects all retailers, requires careful rollout)  
**Priority:** ⚠️ **MEDIUM - High impact but high risk, needs thorough planning**

---

### 2.2 Storage Optimization

**What:** Reduce storage costs through lifecycle management

**Current Costs:** $24,899/year (storage)

**Strategies:**

#### A. Partition Pruning (Automatic Deletion)
- Delete partitions older than retention requirement (e.g., 2 years)
- **Expected savings:** $5K-$10K/year

#### B. Compression Optimization
- Already using BigQuery default compression
- Review for custom column-level compression if needed

#### C. Archive to Cheaper Storage
- Move historical data (>1 year) to Cloud Storage
- **Expected savings:** $8K-$12K/year
- **Trade-off:** Slower access for historical queries

**Total Platform Impact:** $13K-$22K/year savings

**Effort:** Medium (lifecycle policies, testing)  
**Risk:** Low (with proper backup/retention policies)  
**Priority:** ✅ **MEDIUM - Good long-term savings**

---

## 🎯 Strategy 3: Retailer Engagement & Governance

### 3.1 Cost Transparency Dashboard

**What:** Provide retailers with visibility into their Monitor usage and costs

**Components:**
1. Monthly cost reports (consumption + production attribution)
2. Query performance metrics (QoS, slot-hours, data scanned)
3. Optimization recommendations
4. Benchmarking against peer retailers (anonymized)

**Impact:**
- **Behavioral change:** 10-30% voluntary usage reduction
- **Platform savings:** $20K-$60K/year
- **Benefit:** Improved retailer engagement and partnership

**Effort:** Medium (dashboard development, automation)  
**Risk:** Low  
**Priority:** ⚠️ **MEDIUM - Good for long-term engagement**

---

### 3.2 Usage-Based Pricing Tiers

**What:** Implement tiered pricing based on actual resource consumption

**Current:** Likely flat-rate pricing (assumption - verify with business)

**Proposed Tiers:**
1. **Light:** <100 queries/month, <10 slot-hours → $X/month
2. **Standard:** 100-1,000 queries/month, 10-100 slot-hours → $Y/month
3. **Premium:** 1,000-10,000 queries/month, 100-1,000 slot-hours → $Z/month
4. **Enterprise:** >10,000 queries/month, >1,000 slot-hours → Custom pricing

**Impact:**
- **Cost recovery:** Align pricing with actual costs
- **Incentive:** Encourages efficient usage patterns
- **Revenue:** Potential revenue optimization (business decision)

**Effort:** High (requires business approval, contract changes)  
**Risk:** Medium (customer relationship impact)  
**Priority:** ✅ **STRATEGIC - Long-term consideration**

---

### 3.3 Query Optimization Workshops

**What:** Train retailer technical teams on BigQuery best practices

**Topics:**
1. Partition pruning techniques
2. Understanding slot-hour consumption
3. Query performance debugging
4. Cost-efficient query patterns
5. When to use Monitor API vs custom queries

**Impact:**
- **Knowledge transfer:** Empowers retailers to self-optimize
- **Platform savings:** $15K-$40K/year
- **Benefit:** Reduced support burden

**Effort:** Medium (workshop development, scheduling)  
**Risk:** Low  
**Priority:** ✅ **MEDIUM - Good investment in retailer success**

---

## 📋 Implementation Roadmap

### Phase 1: Quick Wins (Week 1-4)

**Focus:** fashionnova optimization (highest ROI)

**Actions:**
1. ✅ Audit fashionnova's top 20 queries
2. ✅ Implement partition pruning (add date filters)
3. ✅ Verify query result caching enabled
4. ✅ Monitor slot-hour reduction

**Expected Savings:** $20K-$25K/year  
**Effort:** 1-2 engineers, 2-4 weeks

---

### Phase 2: Medium-Term Wins (Month 2-3)

**Focus:** Top 5 retailers + materialized views

**Actions:**
1. ✅ Scale partition pruning to top 5 retailers
2. ✅ Identify common aggregation patterns
3. ✅ Implement 3-5 materialized views
4. ✅ Monitor impact and iterate

**Expected Savings:** $50K-$80K/year (cumulative)  
**Effort:** 2-3 engineers, 2-3 months

---

### Phase 3: Platform Optimization (Month 4-6)

**Focus:** Production infrastructure

**Actions:**
1. ✅ Optimize monitor_base.shipments merges
2. ✅ Implement storage lifecycle policies
3. ✅ Evaluate batch size and scheduling
4. ✅ Gradual rollout with monitoring

**Expected Savings:** $100K-$150K/year (cumulative)  
**Effort:** 3-4 engineers, 3-4 months  
**Risk:** Requires careful testing and rollout

---

### Phase 4: Long-Term Governance (Month 6+)

**Focus:** Sustainable cost management

**Actions:**
1. ✅ Launch cost transparency dashboard
2. ✅ Conduct retailer optimization workshops
3. ✅ Evaluate pricing model changes
4. ✅ Establish ongoing monitoring and alerts

**Expected Savings:** $150K-$200K/year (sustained)  
**Effort:** Ongoing (1-2 engineers for maintenance)

---

## 📊 Success Metrics & Tracking

### Key Performance Indicators

**Cost Metrics:**
- Total platform cost (consumption + production)
- Cost per retailer
- Cost per query (including production)
- Top 20 retailer cost concentration

**Performance Metrics:**
- QoS violation rate (target: <2%)
- P95 query execution time (target: <30s)
- Slot-hour consumption (target: -50% for top retailers)

**Efficiency Metrics:**
- Queries with partition filters (target: >80%)
- Materialized view coverage (target: 30% of query volume)
- Cache hit rate (target: >40%)

### Monitoring Dashboard

**Create:** Real-time dashboard tracking:
1. Daily slot-hour consumption by retailer
2. Production cost attribution (updated monthly)
3. Optimization adoption metrics
4. ROI tracking (savings vs effort)

### Monthly Review Cadence

**Agenda:**
1. Review previous month's savings
2. Identify new high-cost retailers
3. Share success stories
4. Adjust priorities based on data

---

## 🎯 Priority Matrix

| Strategy | ROI | Effort | Risk | Priority |
|----------|-----|--------|------|----------|
| **Partition Pruning (fashionnova)** | Very High | Low | Low | P0 🚨 |
| **Query Caching Verification** | High | Very Low | Very Low | P0 🚨 |
| **Top 5 Partition Pruning** | Very High | Medium | Low | P1 |
| **Materialized Views** | High | Medium | Medium | P1 |
| **Production Merge Optimization** | Very High | High | High | P2 |
| **Storage Lifecycle** | Medium | Medium | Low | P2 |
| **Cost Dashboard** | Medium | Medium | Low | P2 |
| **Retailer Workshops** | Medium | Medium | Low | P3 |
| **Query Simplification** | Medium | High | Medium | P3 |
| **Pricing Model Changes** | High | Very High | High | P4 (Strategic) |

---

## 💡 Key Takeaways

1. **Production costs dominate** (97% of total) - can't be ignored
2. **Query optimization has 40-50x ROI** when production included
3. **Start with fashionnova** - single retailer = $41K-$49K/year potential
4. **Partition pruning is the highest ROI** quick win
5. **Platform optimization has high impact** but requires careful execution
6. **Retailer engagement is key** for sustainable cost management
7. **Total savings potential:** $100K-$200K/year from top 20 retailers

---

## 📚 Supporting Documentation

- `FASHIONNOVA_TOTAL_COST_ANALYSIS.md` - Detailed fashionnova case study
- `FASHIONNOVA_COST_ATTRIBUTION.md` - Attribution methodology
- `SCALING_FRAMEWORK.md` - Framework for all-retailer analysis
- `MONITOR_REPORT_INTEGRATION_SUMMARY.md` - Report integration guide
- `ETL_MAPPING_SUMMARY.md` - Production source documentation

---

**Status:** ✅ PLAYBOOK COMPLETE  
**Next Action:** Begin Phase 1 (fashionnova quick wins)  
**Expected Timeline:** 6 months to full implementation  
**Expected ROI:** $100K-$200K/year sustained savings

---

**Prepared by:** AI Assistant (Claude Sonnet 4.5)  
**Last Updated:** November 14, 2025

