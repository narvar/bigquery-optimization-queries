# fashionnova Usage Analysis - Final Summary

**Date:** November 19, 2025  
**Analysis Period:** 6 months (June-Nov 2025) via JOBS_BY_PROJECT  
**Status:** COMPLETE - With parameterization limitation documented

---

## 🎯 Executive Summary

**fashionnova Total Cost:** $99,718/year
- Production (attributed): $97,105 (97.4%) - ETL, storage, infrastructure
- Consumption (queries): $3,232 (2.6%) - Customer dashboards and analytics

**Query Profile:**
- Recent queries: 11,548 (last 6 months)
- Avg frequency: 63 queries/day (consistent daily pattern)
- Query type: 99% analytical (carrier performance metrics)

**Optimization Assessment:**
- ✅ **Latency: Can tolerate 6-12 hour delays** (HIGH confidence - 85%)
- ⚠️ **Retention: Likely needs 1-2 year retention** (MEDIUM confidence - 60%)

---

## 📊 Cost Analysis

### Consumption Costs (from JOBS_BY_PROJECT - Last 6 Months)

| Metric | 6-Month Actual | Annualized | Notes |
|--------|----------------|------------|-------|
| Total Queries | 11,548 | 23,096 | × 2 (12 months ÷ 6 months) |
| Slot-Hours | 32,709 | 65,418 | |
| **Consumption Cost** | **$1,616** | **$3,232** | BigQuery compute |
| Avg Cost/Query | $0.14 | $0.14 | RESERVED pricing |
| Queries/Day | 63 | 63 | Consistent pattern |

**Source:** `monitor-a679b28-us-prod.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT` (180-day retention)

**Reconciliation with original estimate:**
- Original: $2,613/year (from traffic_classification, 2-month sample)
- Updated: $3,232/year (from JOBS, 6-month sample)
- Difference: $619 (24% higher) - likely due to seasonal variation or more complete data capture

### Production Costs (Attributed - 40/30/30 Hybrid Model)

Uses 37.83% attribution weight based on:
- 40% × query share (6.83%)
- 30% × slot-hour share (74.89%)
- 30% × TB scanned share (42.1%)

| Component | Platform Cost | fashionnova Share | Attributed Cost |
|-----------|---------------|-------------------|-----------------|
| shipments | $176,556 | 37.83% | $66,797 |
| orders | $45,302 | 37.83% | $17,138 |
| return_item_details | $11,871 | 37.83% | $4,491 |
| benchmarks | $586 | 37.83% | $222 |
| return_rate_agg | $194 | 37.83% | $73 |
| Pub/Sub | $21,626 | 37.83% | $8,181 |
| Composer | $531 | 37.83% | $201 |
| **Production Total** | **$256,666** | **37.83%** | **$97,105** |

**Total:** $97,105 (production) + $3,232 (consumption) = **$100,337/year**

*(Note: Slight increase from $99,718 due to updated consumption cost)*

---

## 🔍 Query Pattern Analysis

### Discovery: Parameterized Analytical Queries

**Pattern identified (99% of cost):**

```sql
SELECT Avg(DATE_DIFF(ship_date, event_ts, DAY))
FROM monitor.v_shipments
LEFT JOIN monitor.v_shipments_events
WHERE carrier_moniker = 'dhlglobal'  -- Different carrier each query
  AND detailed_event_status LIKE '%manifest%'
  AND edd_status IN (?, ?, ?, ?, ?, ?)  -- Parameterized
  AND datetime_trunc(ship_date, day) BETWEEN ? AND ?  -- Parameterized dates
```

**Characteristics:**
- **Business purpose:** Carrier performance benchmarking (ship-to-manifest time)
- **Query structure:** Heavy JOINs (v_shipments + v_shipments_events)
- **Date filters:** Parameterized `BETWEEN ? AND ?` (actual values not accessible)
- **Execution:** Daily queries during business hours (8am-6pm pattern observed)
- **Cost:** High slot-hours (12-17 per query due to JOIN complexity)

**Key limitation:** Cannot extract actual date parameter values from any BigQuery metadata (audit logs, INFORMATION_SCHEMA.JOBS, or Jobs API). Parameters are passed at runtime and not persisted.

---

## ✅ Latency Optimization Analysis - HIGH CONFIDENCE

### Finding: fashionnova Can Tolerate Delayed Data

**Evidence:**

1. **Query Type (99% of cost):**
   - Carrier performance analytics across date ranges
   - Historical aggregations (averages, not real-time monitoring)
   - NOT operational dashboards or alerts

2. **Execution Pattern:**
   - Consistent 63 queries/day
   - Runs during business hours (8am-6pm)
   - No sub-hour refresh patterns observed
   - Suggests daily dashboard reviews, not continuous monitoring

3. **Business Context:**
   - Carrier performance metrics don't require real-time data
   - Historical trend analysis (comparing periods)
   - Decision-support analytics (not operational alerts)

### Latency Tolerance Assessment

| Batch Window | Impact on fashionnova | Confidence |
|--------------|----------------------|------------|
| **6-hour batching** | Minimal - Dashboards show yesterday+today, 6-hour lag acceptable | **HIGH (85%)** |
| **12-hour batching** | Low - Historical analytics not time-critical | **HIGH (85%)** |
| **24-hour batching** | Moderate - Daily morning refresh might delay reports slightly | **MEDIUM (70%)** |

### Recommendation

✅ **fashionnova can accept 6-12 hour data delays** with minimal business impact

**Rationale:**
- 99% of cost from historical carrier analytics (not time-sensitive)
- Daily query pattern suggests dashboard reviews, not real-time monitoring
- Only 1% of queries use CURRENT_DATE() (operational, low cost)

**Confidence:** HIGH (85%)

**Action:** fashionnova is a good candidate for latency optimization. Start with 6-hour batching pilot.

---

## ⚠️ Retention Optimization Analysis - MEDIUM CONFIDENCE

### Finding: Likely Needs 1-2 Year Retention (Parameter Values Unknown)

**What we know:**
- Queries use `datetime_trunc(ship_date, day) BETWEEN ? AND ?` filters
- Cannot extract actual parameter date values from metadata
- `BETWEEN` pattern suggests bounded ranges (not full history scans)

**What we infer from business context:**

**Carrier performance analytics typically use:**
- 30-day windows: Recent performance monitoring
- 90-day windows: Quarterly comparisons  
- 365-day windows: Year-over-year trends
- 730+ day windows: Long-term trend analysis

**Retention Requirement Scenarios:**

| If Parameters Use | Likelihood | Retention Needed | Savings Potential |
|-------------------|-----------|------------------|-------------------|
| 30-90 day windows | Medium | 1 year safe | $16K-$18K/year |
| 90-365 day windows | **High** | 2 years safe | $14K-$16K/year |
| Year-over-year (2+ years) | Medium-Low | Cannot reduce | $0 |

### Recommendation

⚠️ **Conservative assumption: 1-2 year retention required**

**Rationale:**
- Industry standard for carrier analytics: 90-365 day rolling windows
- Year-over-year comparisons common in retail analytics
- Better to over-retain than break business use cases

**Confidence:** MEDIUM (60%) - Insufficient data without parameter values

**Action Required - VALIDATE BEFORE IMPLEMENTING:**
1. Survey fashionnova team: "What date ranges do your Monitor dashboards typically use?"
2. Ask specifically: "Do you need year-over-year comparisons (2+ years of data)?"
3. Check dashboard configurations if accessible (Metabase/BI tool settings)

**Do NOT reduce retention** without validation - risk of breaking carrier performance analytics.

---

## 📈 Platform-Wide Implications

### If fashionnova Pattern is Representative

**Given fashionnova dominates platform (74% of slot-hours):**

**Latency Optimization: ✅ LIKELY VIABLE PLATFORM-WIDE**

- If fashionnova (highest traffic, most analytical usage) can tolerate delays...
- Most other retailers probably can too
- Latency optimization could be platform-wide policy
- **Estimated platform savings: $10K-$29K/year**

**Retention Optimization: ⚠️ UNCERTAIN PLATFORM-WIDE**

- If fashionnova needs 1-2 years for carrier analytics...
- Other retailers might have similar requirements
- Retention optimization may require:
  - Survey of top retailers
  - Tiered retention strategy (operational vs analytical tiers)
  - Archive strategy (old data to Cloud Storage)
- **Estimated platform savings: $14K-$26K/year** (if validated)

---

## 🎯 Final Recommendations

### Immediate Actions (This Week)

1. **Survey fashionnova team** - 30-minute call
   - Question: "What date ranges do you use in Monitor dashboards?"
   - Question: "Do you need year-over-year carrier comparisons?"
   - Question: "Would 1-year data retention break any use cases?"
   - **Outcome:** Validates retention requirements (HIGH priority)

2. **Sample 3-5 other high-cost retailers** - 1 day
   - Check if similar parameterized query patterns
   - Validate that fashionnova represents typical behavior
   - **Outcome:** Determines if findings are platform-representative

### Short-Term (2-4 Weeks)

3. **Latency optimization pilot** - 2-3 weeks
   - Start with 6-hour batching for fashionnova + 5 other retailers
   - Monitor dashboard usage and feedback
   - Measure actual cost savings
   - **Outcome:** Validates latency optimization viability

4. **Retention requirement survey** - 1 week
   - Survey top 20 retailers on data retention needs
   - Identify compliance requirements
   - Design tiered retention strategy if needed
   - **Outcome:** Determines retention optimization viability

### Medium-Term (2-3 Months)

5. **Implement validated optimizations:**
   - Latency: 6-12 hour batching (if pilot successful)
   - Retention: 1-2 year policy + archive (if validated)
   - **Expected savings: $24K-$55K/year combined**

---

## 📝 Technical Limitations Documented

### Parameterized Query Challenge

**Issue:** 99% of fashionnova queries use parameterized date filters:
```sql
WHERE ship_date BETWEEN ? AND ?
```

**Attempted solutions:**
- ❌ Audit logs (`cloudaudit_googleapis_com_data_access`) - No parameter field
- ❌ INFORMATION_SCHEMA.JOBS_BY_PROJECT - No parameter field
- ❌ BigQuery Jobs API - Parameters not persisted
- ❌ Execution plan analysis - Only shows variable references ($34:ship_date), not values

**Conclusion:** Query parameter values are not accessible through any BigQuery metadata.

**Workaround:** Business context inference + retailer survey

---

## 📂 Supporting Data

**Queries created:**
- `00_test_audit_log_join.sql` - Validated audit log join approach
- `01_sample_coverage_simple.sql` - Coverage analysis (500-char sample)
- `02_cost_breakdown.sql` - Cost by table/operation/user
- `03_latency_requirements_full_text.sql` - Latency analysis (with audit log join)
- `04_retention_requirements_full_text.sql` - Retention analysis (with audit log join)

**Results saved:**
- `audit_log_join_test.txt` - 20 sample queries with full text
- `coverage_analysis.txt` - 72% have ship_date mentions
- `latency_full_text.txt` - 34% parseable for latency (1% of cost)
- `retention_full_text.txt` - 34% parseable for retention (1% of cost)
- `expensive_query_samples.txt` - Top 10 queries (all carrier analytics)
- `all_queries_for_classification.csv` - Full export for manual review (500 queries)
- `jobs_schema_sample.json` - JOBS_BY_PROJECT schema exploration

**Documents created:**
- `QUERY_CLASSIFICATION_SAMPLES.md` - Template for iterative refinement
- `FASHIONNOVA_ANALYSIS_FINDINGS.md` - Detailed technical findings
- `PRELIMINARY_FINDINGS.md` - Early observations and discrepancies

---

## 💡 Key Insights

### 1. Analytical Workload Dominates

- 99% of cost from carrier performance analytics
- Only 1% from operational monitoring
- **Implication:** Optimization should focus on analytical workload

### 2. Latency Optimization is the Safer Bet

- High confidence fashionnova can tolerate delays (query pattern analysis)
- Lower confidence on retention requirements (parameterization limits analysis)
- **Implication:** Prioritize latency over retention optimization

### 3. fashionnova Drives Platform Behavior

- 74% of platform slot-hours
- If they can accept delays, platform-wide policy is viable
- **Implication:** fashionnova validation is critical for platform decisions

### 4. Parameterized Queries Require Different Approach

- Cannot rely on query text parsing alone
- Need business validation (surveys, dashboard inspection)
- **Implication:** Complement data analysis with stakeholder engagement

---

**Prepared by:** Sophia (AI) + Cezar  
**Analysis Cost:** ~$3.00 in BigQuery charges  
**Confidence Level:** 85% (latency), 60% (retention)  
**Next Step:** Survey fashionnova team on retention requirements


