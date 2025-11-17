# Monitor Platform Cost Summary - Quick Reference

**Date:** November 17, 2025  
**Total Annual Cost:** **$263,084**  
**Cost per Retailer:** **$926/year** (284 retailers)  
**Status:** ✅ COMPLETE

---

## 💰 Platform Cost Breakdown

| Component | Annual Cost | % of Total | Monthly | Per Retailer/Year |
|-----------|-------------|------------|---------|-------------------|
| **PRODUCTION TABLES** | | | | |
| shipments | $176,556 | 67.1% | $14,713 | $622 |
| orders | $45,302 | 17.2% | $3,775 | $159 |
| return_item_details | $11,871 | 4.5% | $989 | $42 |
| benchmarks (ft + tnt) | $586 | 0.22% | $49 | $2 |
| return_rate_agg | $194 | 0.07% | $16 | $1 |
| carrier_config | $0 | 0% | $0 | $0 |
| **Subtotal Production** | **$234,509** | **89.1%** | **$19,542** | **$826** |
| **INFRASTRUCTURE** | | | | |
| Pub/Sub | $21,626 | 8.2% | $1,802 | $76 |
| Composer/Airflow | $531 | 0.20% | $44 | $2 |
| **Subtotal Infrastructure** | **$22,157** | **8.4%** | **$1,846** | **$78** |
| **CONSUMPTION** | | | | |
| Customer queries | $6,418 | 2.4% | $535 | $23 |
| **TOTAL PLATFORM** | **$263,084** | **100%** | **$21,924** | **$926** |

---

## 📊 Cost by Technology

| Technology | Tables/Services | Annual Cost | % |
|------------|----------------|-------------|---|
| App Engine MERGE | shipments | $176,556 | 67.1% |
| Dataflow Streaming | orders | $45,302 | 17.2% |
| Airflow ETL + CDC | return_item_details | $11,871 | 4.5% |
| Airflow ETL | benchmarks, return_rate_agg | $780 | 0.30% |
| Pub/Sub | Message delivery | $21,626 | 8.2% |
| Composer | Orchestration (5.78% attribution) | $531 | 0.20% |
| Customer Queries | BigQuery execution | $6,418 | 2.4% |

---

## 📊 Cost by Type

| Type | Annual Cost | % | Components |
|------|-------------|---|------------|
| BigQuery Compute | $161,015 | 61.2% | Queries + MERGE operations |
| Storage | $25,260 | 9.6% | 108 TB total |
| Dataflow | $21,852 | 8.3% | Orders streaming pipeline |
| Pub/Sub | $21,626 | 8.2% | Message delivery |
| CDC Datastream | $1,056 | 0.4% | Returns data streaming |
| Composer | $531 | 0.2% | Airflow orchestration |
| Customer Queries | $6,418 | 2.4% | Consumption |
| Other | $25,326 | 9.6% | Infrastructure, streaming API |

---

## 📈 Storage Breakdown

| Table | Size (GB) | % of Storage | Annual Cost |
|-------|-----------|--------------|-------------|
| orders | 88,737 | 82.0% | $20,430 |
| shipments | 19,093 | 17.7% | $4,396 |
| benchmarks (ft + tnt) | 78 | 0.07% | $19 |
| return_item_details | 40 | 0.04% | $10 |
| CDC tables (returns) | 101 | 0.09% | $24 |
| Other | 99 | 0.09% | $24 |
| **TOTAL** | **108,148 GB** | **100%** | **$24,903** |

**Key Insight:** Orders table is 82% of all storage but only 17% of total platform cost!

---

## 🔍 Workload Metrics (Sep-Oct 2024 Baseline)

| Metric | Value |
|--------|-------|
| **Customer Queries** | |
| Total customer queries | ~77,000 queries (2 months) |
| Queries per day | ~1,283 queries/day |
| Total slot-hours (customer) | ~12,000 slot-hours |
| **ETL Operations** | |
| Total ETL operations | ~7,075 operations (2 months) |
| Operations per day | ~118 operations/day |
| Total slot-hours (ETL) | ~16,000 slot-hours |
| **Platform Total** | |
| Total workload | 1,629,060 slot-hours (all consumers) |
| Monitor percentage | 1.74% of platform |

---

## 💡 Key Findings

1. **Production costs dominate:** 97.6% of total (ETL + storage + infrastructure)
2. **Storage is expensive:** $25K/year for 108 TB (orders = 82%!)
3. **Hidden costs exist:** Orders ($45K), Composer ($531), CDC ($1K)
4. **Average cost per retailer:** $926/year
5. **Cost variance is high:** $100 to $70K+ per retailer
6. **Optimization potential:** $20K-$28K/year (8-11%)

---

## 📝 Documentation Reference

**For complete analysis:** [MONITOR_COST_EXECUTIVE_SUMMARY.md](MONITOR_COST_EXECUTIVE_SUMMARY.md)  
**For pricing strategy:** [MONITOR_PRICING_STRATEGY.md](MONITOR_PRICING_STRATEGY.md)  
**For technical details:** [MONITOR_PLATFORM_COMPLETE_COST_ANALYSIS.md](MONITOR_PLATFORM_COMPLETE_COST_ANALYSIS.md)

**Individual table analyses:**
- [SHIPMENTS_PRODUCTION_COST.md](SHIPMENTS_PRODUCTION_COST.md) - $176,556/year
- [ORDERS_TABLE_FINAL_COST.md](ORDERS_TABLE_FINAL_COST.md) - $45,302/year
- [RETURN_ITEM_DETAILS_FINAL_COST.md](RETURN_ITEM_DETAILS_FINAL_COST.md) - $11,871/year
- [BENCHMARKS_FINAL_COST.md](BENCHMARKS_FINAL_COST.md) - $586/year
- [RETURN_RATE_AGG_FINAL_COST.md](RETURN_RATE_AGG_FINAL_COST.md) - $194/year

---

**Analysis Date:** November 17, 2025  
**Confidence Level:** 95%  
**Validation:** All costs traceable to billing data + code + workload analysis

