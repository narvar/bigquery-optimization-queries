# BQ Monitor Merge Cost Analysis - FINAL RESULTS

**Analysis Date**: November 6, 2025  
**Question**: "What is the BQ Monitor merge costing us today annually, that would need to be offset?"

---

## 🎯 EXECUTIVE SUMMARY

### **Annual Cost: $200,957.67**

This is the cost that would need to be offset by any alternative solution to the current BQ Monitor merge operations.

### **Cost Calculation Formula**

```
Total Annual Cost = Monitor Merge Reservation Cost + Storage + Pub/Sub

Where:
  Monitor Merge Reservation Cost = Total BQ Reservation × Monitor Merge %
                                  = $619,598.41 × 24.18%
                                  = $149,831.76

  Storage Cost (monitor-base-us-prod)     = $24,899.45
  Cloud Pub/Sub Cost (monitor-base-us-prod) = $26,226.46

Therefore:
  Total Annual Cost = $149,831.76 + $24,899.45 + $26,226.46
                    = $200,957.67
```

### **Baseline Period & Extrapolation**

**Important**: This cost is extrapolated from actual 2-month traffic data:
- **Baseline Period**: September - October 2024
- **2-Month Actual Cost**: $24,971.96 (compute only)
- **Extrapolation Method**: 
  - Calculated percentage of total BQ Reservation: 24.18%
  - Applied this percentage to annual BQ Reservation costs
  - Added annual storage and Pub/Sub costs for monitor-base-us-prod
- **Extrapolation Factor**: 6x (12 months ÷ 2 months)

---

## 📊 KEY FINDINGS

### Service Account Identified
**`monitor-base-us-prod@appspot.gserviceaccount.com`**
- Performs MERGE operations containing "shipments"
- EXTERNAL category (Monitor-base project)
- 99.5% of all MERGE+SHIPMENTS operations

### Resource Consumption (Sep-Oct 2024 Baseline)
| Metric | Value |
|--------|-------|
| **Jobs** | 6,256 |
| **Slot Hours** | 505,505.37 |
| **2-Month Cost** | $24,971.96 |
| **% of BQ Reservation** | **24.18%** |

---

## 💰 ANNUAL COST BREAKDOWN

| Component | Annual Cost | % of Total |
|-----------|-------------|------------|
| **Compute (Merge Slots)** | **$149,831.76** | **74.6%** |
| Storage (monitor-base-us-prod) | $24,899.45 | 12.4% |
| Cloud Pub/Sub (monitor-base-us-prod) | $26,226.46 | 13.1% |
| **TOTAL** | **$200,957.67** | **100.0%** |

### Compute Cost Calculation
```
Total BigQuery Reservation API (Annual):  $619,598.41
Monitor Merge Percentage:                 24.18%
Monitor Merge Reservation Cost:           $149,831.76
```

### Storage Costs (monitor-base-us-prod)
- Active Logical Storage: $17,996.28
- Long Term Logical Storage: $5,801.23
- Long-Term Physical Storage (US): $948.01
- Active Physical Storage (US): $153.94
- **Total**: $24,899.45

### Pub/Sub Costs (monitor-base-us-prod)
- Message Delivery Basic: $26,226.46
- **Total**: $26,226.46

---

## 📈 ANALYSIS METHODOLOGY

### Data Sources
1. **DoIT CSV** (`BQ Detailed 01 monthly.csv`)
   - 12 months of actual billing data
   - BigQuery Reservation API costs
   - Storage and Pub/Sub costs by project

2. **BigQuery Traffic Classification** (`narvar-data-lake.query_opt.traffic_classification`)
   - Job-level slot consumption
   - Query text for pattern matching
   - Consumer category classification
   - Sep-Oct 2024 baseline period

### Query Pattern
```sql
WHERE UPPER(query_text_sample) LIKE '%MERGE%'
  AND UPPER(query_text_sample) LIKE '%SHIPMENTS%'
  AND principal_email = 'monitor-base-us-prod@appspot.gserviceaccount.com'
```

### Calculation Method
1. Analyzed 2-month baseline (Sep-Oct 2024)
2. Found monitor merge operations consumed $24,971.96 in 2 months
3. Calculated percentage: $24,971.96 / $103,266.40 (2-month BQ reservation) = 24.18%
4. Applied percentage to annual BQ reservation: $619,598.41 × 24.18% = $149,831.76
5. Added storage and Pub/Sub costs for monitor-base-us-prod

---

## 🔍 DETAILED FINDINGS

### Top Service Accounts with MERGE+SHIPMENTS (Sep-Oct 2024)

| Rank | Service Account | Jobs | Slot Hours | Cost |
|------|----------------|------|------------|------|
| **#1** | **monitor-base-us-prod@appspot.gserviceaccount.com** | **6,256** | **505,505.37** | **$24,971.96** |
| #2 | monitor-analytics-us-airflow@... | 122 | 1,923.04 | $95.00 |
| #3 | monitor-shipment-noflake@... | 20 | 621.29 | $30.69 |
| #4 | monitor-base-us-qa@appspot.gserviceaccount.com | 7,895 | 106.06 | $5.24 |

**Total Across All Accounts**: 14,365 jobs, 508,261 slot-hours, $25,108.11

---

## 📋 KEY ASSUMPTIONS

1. **Baseline Period**: Sep-Oct 2024 is representative of typical workload
2. **Scope**: Only MERGE operations containing "shipments" keyword
3. **Service Account**: monitor-base-us-prod@appspot.gserviceaccount.com is the primary account
4. **Storage Attribution**: All monitor-base-us-prod storage is attributed to merge operations
5. **Pub/Sub Attribution**: All monitor-base-us-prod Pub/Sub is attributed to merge operations
6. **Proportional Cost**: Merge operations consume 24.18% of total BQ Reservation capacity

---

## 📁 FILES GENERATED

1. **`monitor_merge_cost_summary_FINAL.csv`** - Summary cost breakdown
2. **`monitor_merge_cost_breakdown_FINAL.csv`** - Detailed metrics
3. **`calculate_monitor_merge_cost.py`** - Updated calculator script (24.18%)
4. **`MONITOR_MERGE_COST_FINAL_RESULTS.md`** - This document

---

## 🎯 ANSWER TO BUSINESS QUESTION

> **"What is the BQ Monitor merge costing us today annually, that would need to be offset?"**

**Answer**: **$200,957.67 per year**

This cost consists of:
- **74.6%** ($149,831.76) in compute costs for MERGE operations
- **12.4%** ($24,899.45) in storage costs
- **13.1%** ($26,226.46) in Pub/Sub costs

The monitor merge operations consume **24.18%** of total BigQuery Reservation capacity, making this a significant workload that would need to be carefully planned for in any alternative solution.

---

## 💡 IMPLICATIONS FOR ALTERNATIVE SOLUTIONS

Any alternative to the current BQ Monitor merge approach must account for:

1. **Compute Capacity**: 24.18% of current BQ Reservation ($149,831.76/year)
   - 505,505 slot-hours per 2 months
   - ~6,256 merge jobs per 2 months

2. **Storage Requirements**: $24,899.45/year
   - Active and long-term storage
   - Both logical and physical storage

3. **Messaging Infrastructure**: $26,226.46/year
   - Pub/Sub message delivery
   - Integration with downstream systems

4. **Performance Requirements**:
   - Processing ~3,128 jobs/month
   - Handling shipments data merges
   - Maintaining current SLAs

---

## 📞 NEXT STEPS

1. **Validate Results**: Review the service account and query patterns to confirm scope
2. **Seasonal Analysis**: Check if Sep-Oct 2024 workload is typical or seasonal
3. **Alternative Evaluation**: Use $200,957.67 as the baseline for ROI calculations
4. **Cost-Benefit Analysis**: Compare alternative solutions against this baseline

---

## 📝 REVISION HISTORY

| Date | Version | Changes |
|------|---------|---------|
| 2025-11-06 | 1.0 | Initial analysis - AUTOMATED category only (0 results) |
| 2025-11-06 | 2.0 | Corrected - Found EXTERNAL category operations (negligible) |
| 2025-11-06 | 3.0 | **FINAL** - Identified MERGE+SHIPMENTS pattern, 24.18% |

---

**Prepared by**: AI Analysis  
**Reviewed by**: [Pending]  
**Approved by**: [Pending]

---

*For questions or clarifications, please refer to the detailed CSV files or re-run the analysis using the updated `calculate_monitor_merge_cost.py` script with the value 24.18%.*

