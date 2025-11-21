# 📊 Data Engineering Update - November 21, 2025

## 🔴 CRITICAL: DTPL-6903 Notification History Latency - WIP

**Issue:** Notification History feature experiencing 8-9 minute delays (Lands' End escalation NT-1363)

**Root Cause Identified:** BigQuery reservation `bq-narvar-admin:US.default` saturated at maximum autoscale capacity (1,700 slots):
- Airflow ETL: 46% of capacity
- Metabase BI: 31% of capacity
- **n8n Shopify ingestion: Primary culprit** - appears in 88% of worst delay periods, consuming 6,631 slot-minutes/minute overnight

**The Problem:** Queries execute in 2 seconds but wait **8 minutes** in queue (279:1 ratio) - this is a capacity issue, not a query optimization issue.

**Solution Ready:** Deploy on-demand slots for messaging service
- Cost: ~$27/month (vs $146/month for dedicated reservation)
- Timeline: 3-5 day implementation
- Impact: Eliminates queue delays (P95 <1 second vs current 500+ seconds)
- Risk: Very low (5-minute deployment, 30-second rollback)

**Deliverables:** Complete investigation with TRD, root cause analysis, and implementation guide
- 📁 `narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/`
- 9 SQL queries, $1.85 analysis cost, 95% confidence

**📄 Key Documents:**
- [Executive Summary](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/EXECUTIVE_SUMMARY.md) - Ready for Jira ticket with non-technical summary
- [Technical Requirements Doc (TRD)](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/MESSAGING_CAPACITY_PLANNING.md) - Complete implementation guide
- [Root Cause Analysis](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/FINDINGS.md) - Detailed technical findings
- [Choke Points Analysis](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/CHOKE_POINTS_ANALYSIS.md) - n8n Shopify impact analysis

**Next Steps:** Schedule deployment with messaging team (recommended: next week)

---

## 📋 Monitor Pricing - Monday Action Items

### Priority 1: Data Retention Analysis (Lower LOE, Similar $ Impact)

Between data retention and merge frequency optimization, **address data retention first**:
- **Lower level of effort** - Just retention policy changes
- **Similar cost impact** - Storage + compute savings comparable to merge optimization
- **Faster to implement** - Can deploy retention policies without application changes

**Action:** Analyze historical data usage patterns and retention requirements by table.

---

### Priority 2: Fashion Nova Data Volume Analysis

**Question:** What % of data volume is Fashion Nova? Is it proportional to the cost of merge operations?

**Context:** 
- Fashion Nova consumes 74% of slot-hours but only 6.83% of queries
- Need to understand if their DATA SIZE is also disproportionate

**Analysis needed:**
```sql
-- Check Fashion Nova data volume vs merge cost
SELECT
  retailer_moniker,
  COUNT(*) AS merge_operations,
  SUM(total_bytes_processed) / POW(1024, 4) AS tb_processed,
  SUM(total_slot_ms) / 3600000 AS slot_hours,
  AVG(total_bytes_processed) / POW(1024, 3) AS avg_gb_per_merge
FROM traffic_classification
WHERE UPPER(query_text_sample) LIKE '%MERGE%'
  AND UPPER(query_text_sample) LIKE '%SHIPMENTS%'
  AND DATE(creation_time) BETWEEN '2024-09-01' AND '2024-10-31'
GROUP BY retailer_moniker
ORDER BY slot_hours DESC;
```

**Goal:** Determine if Fashion Nova's high cost is due to:
1. Data volume (more shipments = more data to process)
2. Query inefficiency (poor filters, missing partitions)
3. Both

---

### Priority 3: Document Cleanup Before Sharing with Scott

**Action:** Clean up MONITOR_COST_EXECUTIVE_SUMMARY.md and remove mentions of previous estimates

**What to remove:**
- References to old $598K estimate (incorrect Method B)
- References to $281K estimate (before core returns analysis)
- Any "was X, now Y" comparisons

**What to keep:**
- Final validated number: **$261,591/year**
- Methodology explanation (Method A via traffic_classification)
- Cost breakdown by table
- Fashion Nova case study

**Goal:** Present clean, professional document showing only current validated findings.

---

### Priority 4: Break Down Merge Cost by Retailer

**Objective:** Allocate shipments table merge costs to specific retailers

**Current state:**
- Total shipments merge cost: $176,556/year
- Fashion Nova attribution: 37.83% via 40/30/30 hybrid model
- Need granular retailer breakdown

**Analysis approach:**
```sql
-- Retailer-specific merge costs for shipments
WITH retailer_merges AS (
  SELECT
    -- Extract retailer from query (multiple patterns)
    COALESCE(
      REGEXP_EXTRACT(query_text_sample, r"retailer_moniker\s*=\s*'([^']+)'"),
      REGEXP_EXTRACT(query_text_sample, r"retailer_moniker\s*IN\s*\('([^']+)'"),
      'UNKNOWN'
    ) AS retailer_moniker,
    
    COUNT(*) AS merge_count,
    SUM(total_slot_ms) / 3600000 AS slot_hours,
    SUM(total_bytes_processed) / POW(1024, 4) AS tb_processed
    
  FROM traffic_classification
  WHERE UPPER(query_text_sample) LIKE '%MERGE%'
    AND UPPER(query_text_sample) LIKE '%SHIPMENTS%'
    AND principal_email LIKE '%airflow%'
    AND DATE(creation_time) BETWEEN '2024-09-01' AND '2024-10-31'
  GROUP BY retailer_moniker
)

SELECT
  retailer_moniker,
  merge_count,
  slot_hours,
  tb_processed,
  
  -- Calculate % of total
  ROUND(100.0 * slot_hours / SUM(slot_hours) OVER (), 2) AS pct_of_merge_cost,
  
  -- Estimate annual cost (based on $176,556 total)
  ROUND(176556 * slot_hours / SUM(slot_hours) OVER (), 0) AS estimated_annual_cost
  
FROM retailer_merges
ORDER BY slot_hours DESC;
```

**Goal:** 
- Identify top 10 retailers by merge cost
- Compare Fashion Nova's merge cost % to their slot-hour % (should align)
- Validate 40/30/30 hybrid model vs direct merge cost attribution

---

## Monday Priorities (Nov 24):

1. ✅ **Data retention analysis** (2-3 hours)
   - Query historical data access patterns
   - Recommend retention policies by table
   - Estimate storage + compute savings

2. ✅ **Fashion Nova data volume analysis** (1 hour)
   - Calculate % of shipments data by retailer
   - Compare to merge cost attribution
   - Validate cost model

3. ✅ **Document cleanup** (1 hour)
   - Remove old estimates from MONITOR_COST_EXECUTIVE_SUMMARY.md
   - Finalize for Scott's review
   - Ensure professional presentation

4. ✅ **Retailer merge cost breakdown** (2 hours)
   - Run analysis query
   - Create retailer cost allocation table
   - Validate against Fashion Nova case study

**Total estimated effort:** 6-7 hours

---

**Investigation Cost Today:** $1.85 (DTPL-6903)  
**Documents Created:** 5 comprehensive analysis documents + TRD  
**Impact:** Platform-wide capacity issue identified, $27/month solution ready to deploy

