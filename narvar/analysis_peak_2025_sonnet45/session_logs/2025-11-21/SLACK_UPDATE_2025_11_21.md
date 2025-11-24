# Slack Update - Julia Le Feedback Addressed

**Date:** November 21, 2025

---

## Update: Platform Cost Finalized + Cost Optimization Strategy Refined

**✅ Julia Le Feedback - All Three Points Addressed:**

1. **Core returns analyzed:** $1,917/year (returns_etl pipeline to reporting.*) 
2. **Cold storage strategy:** Orders archive saves $7K-$10K/year, supports ML training
3. **Tiered batching:** Analyzed feasibility - recommend uniform 6-hr pilot first, add tiering if needed

**📊 Platform Cost Finalized:** **$261,591/year** (refined from $263,084)
- Returns breakdown: Shopify $8,461 + Core $1,917 = $10,378 total
- Cost per retailer: $921/year

**💡 Cost Optimization (Updated):**
- Cold storage (orders table): $7K-$10K/year ✅ Can start now
- Uniform batching: $10K-$15K/year ⏸️ Pilot first
- Tiered batching (Julia's proposal): $8K-$18K/year ⏸️ Requires Prasanth validation
- Document cleanup before Scott review (remove old estimates)
- **Conservative total: $17K-$25K/year**

**Documents:**
- [Executive Summary (Updated)](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/DELIVERABLES/MONITOR_COST_EXECUTIVE_SUMMARY.md) - Julia feedback incorporated
- [Julia Feedback Response](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/JULIA_FEEDBACK_RESPONSE_NOV21.md) - Detailed analysis

---

## 🔴 Ad Hoc: DTPL-6903 Notification History Latency (CRITICAL)

**Issue WIP:** Notification History experiencing 8-minute delays (jdsports-emea escalation)

**Root Cause:** BigQuery reservation saturated (1,700 slots maxed out). Queries execute in 2 seconds but wait 8 minutes in queue - n8n Shopify ingestion causes 88% of worst delays.

**Solution:** Deploy on-demand slots for messaging (~$27/month, 3-5 day implementation)

**📄 Documents:**
- [Executive Summary](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/EXECUTIVE_SUMMARY.md) - Ready for Jira ticket
- [Implementation TRD](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/MESSAGING_CAPACITY_PLANNING.md) - Complete deployment guide
- [All Analysis](https://github.com/narvar/bigquery-optimization-queries/tree/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency)

## 🚀 NEXT (Monday Nov 24):
0. **EXECUTE PLAN FOR DTPL-6903 Notification History Latency (CRITICAL) ?**
1. Data retention analysis (Priority 1 - lower LOE, similar $ impact)
2. Fashion Nova data volume analysis (validate cost attribution)
3. Retailer merge cost breakdown (allocate $176K by retailer)


