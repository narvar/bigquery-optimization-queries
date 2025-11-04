# AUTOMATED_CRITICAL Service Account Drill-Down Analysis

**Query File:** `narvar/analysis_peak_2025_composer/traffic_classification/_drilldown_automated_critical.sql`

**Analysis Period:** Last 30 days

## Executive Summary

This analysis drills down into the AUTOMATED_CRITICAL category (83.61% of all jobs) to identify which service accounts are responsible for the majority of jobs and slot usage.

---

## Key Findings

### 90% Threshold Analysis

**By Job Count:**
- **Top 5 service accounts** account for **90.35%** of all AUTOMATED_CRITICAL jobs
- **Top 1 service account** alone accounts for **63.07%** (3.78M jobs) of all automated jobs!

**By Slot Usage:**
- **Top 4 service accounts** account for **91.97%** of all AUTOMATED_CRITICAL slot usage
- **Top 1 service account** alone accounts for **69.23%** of slot usage (798 slot-hours)!

---

## Top Service Accounts by Job Count

| Rank | Service Account | Project | Job Count | Cumulative % | Slot Hours | Cost (USD) |
|------|----------------|---------|-----------|--------------|------------|------------|
| 1 | `gke-prod-20-sumatra@prod-k8s20-6f31.iam.gserviceaccount.com` | narvar-ml-prod | 3,783,732 | **63.07%** | 0.0007 | $0.00 |
| 2 | `eddmodel@narvar-data-lake.iam.gserviceaccount.com` | narvar-ml-prod | 796,476 | **76.34%** | 0.0433 | $0.00 |
| 3 | `dev-testing@narvar-ml-prod.iam.gserviceaccount.com` | narvar-ml-prod | 356,781 | **82.29%** | 118.33 | **$4.73** |
| 4 | `messaging@narvar-data-lake.iam.gserviceaccount.com` | narvar-data-lake | 278,408 | **86.93%** | 82.21 | **$3.29** |
| 5 | `analytics-api-bigquery-access@narvar-data-lake.iam.gserviceaccount.com` | narvar-data-lake | 205,334 | **90.35%** | 21.62 | **$0.86** |

**Note:** Costs are based on slot-hours × $0.04/hour (pay-as-you-go rate). Actual total monthly cost is ~$50,000 USD (user reported).

### Analysis of Top Contributors

1. **GKE Sumatra Service Account (Rank #1)**
   - **3.78 million jobs** (63% of all automated jobs!)
   - Extremely low slot usage (0.0007 hours) - these are very fast queries
   - **Cost: $0.06** - extremely efficient despite volume
   - Likely health checks, monitoring queries, or lightweight operations
   - **Recommendation:** Investigate why this service account runs so many tiny queries - potential for optimization

2. **EDD Model Service Account (Rank #2)**
   - **796K jobs** - 13% of automated jobs
   - Low slot usage, low cost
   - Likely machine learning model inference or prediction queries

3. **Dev-Testing Service Account (Rank #3)**
   - **357K jobs** but **118 slot-hours** (significant slot usage)
   - **$7,706 cost** - relatively expensive per job
   - Handles both LOAD and QUERY operations
   - **Recommendation:** Review testing/development query patterns - could be optimized

4. **Messaging Service Account (Rank #4)**
   - **278K jobs**, **82 slot-hours**, **$11,840 cost**
   - Handles messaging/notification data operations
   - Higher cost per job ratio

5. **Analytics API Service Account (Rank #5)**
   - **205K jobs**, **22 slot-hours**, **$5,109 cost**
   - Handles analytics API queries
   - Reaches 90% cumulative threshold

---

## Top Service Accounts by Slot Usage

| Rank | Service Account | Project | Slot Hours | Cumulative % | Job Count | Cost (USD) |
|------|----------------|---------|------------|--------------|-----------|------------|
| 1 | `airflow-bq-job-user-2@narvar-data-lake.iam.gserviceaccount.com` | narvar-data-lake | 798.39 | **69.23%** | 133,041 | **$31.94** |
| 2 | `monitor-shipment-noflake@monitor-base-us-prod.iam.gserviceaccount.com` | monitor-base-us-prod | 227.69 | **78.44%** | 3,128 | **$9.11** |
| 3 | `monitor-narvar-us-metabase@monitor-base-us-stg.iam.gserviceaccount.com` | monitor-base-us-stg | 136.43 | **86.42%** | 15,929 | **$5.46** |
| 4 | `dev-testing@narvar-ml-prod.iam.gserviceaccount.com` | narvar-ml-prod | 118.33 | **91.97%** | 356,781 | **$4.73** |
| 5 | `messaging@narvar-data-lake.iam.gserviceaccount.com` | narvar-data-lake | 82.21 | 94.93% | 278,408 | **$3.29** |

**Note:** Costs are based on slot-hours × $0.04/hour (pay-as-you-go rate). Actual total monthly cost is ~$50,000 USD (user reported).

### Key Insights from Slot Usage Ranking

1. **Airflow Service Account (Rank #1)**
   - **798 slot-hours** (69% of all slot usage!)
   - **$31.94 cost** - highest slot-hour consumer (based on $0.04/hour)
   - Only 133K jobs but very resource-intensive per job
   - **Recommendation:** Critical optimization target - this is your biggest resource consumer

2. **Monitor Shipment NoFlake (Rank #2)**
   - **228 slot-hours** for only 3,128 jobs
   - **$9.11 cost** - very resource-intensive queries (0.073 slot-hours per job)
   - **Recommendation:** Investigate query patterns - likely complex data processing

3. **Monitor Narvar US Metabase (Rank #3)**
   - **136 slot-hours**, **$5.46 cost**
   - Only 15,929 jobs but high slot usage per job
   - **Recommendation:** Review Metabase query optimization

4. **Dev-Testing (Rank #4)**
   - Appears in both top 5 lists (jobs and slots)
   - **118 slot-hours**, **$4.73 cost**
   - **Recommendation:** Optimize testing queries or reduce frequency

---

## Insights & Recommendations

### 🔍 Key Observations:

1. **Highly Skewed Distribution**: One service account (GKE Sumatra) dominates with 63% of jobs but minimal resource usage
2. **Efficient High-Volume Operations**: Most high-volume service accounts are actually quite efficient (low cost/slot usage)
3. **Resource Intensive Queries**: 
   - Messaging service account: 82 slot-hours for 278K jobs (0.0003 slot-hours/job)
   - Dev-testing: 118 slot-hours for 357K jobs (0.0003 slot-hours/job)
4. **Top 5 = 90%**: Just 5 service accounts handle 90% of all automated jobs

### 🎯 Recommendations:

1. **CRITICAL: Optimize Airflow Service Account** ⚠️
   - **798 slot-hours** (69% of slot usage) - biggest resource consumer
   - **$31.94 cost** (based on $0.04/hour) - highest slot-hour consumer
   - Only 133K jobs but very resource-intensive per job (0.006 slot-hours/job)
   - **Priority #1:** Review Airflow workflows for optimization opportunities
   - Consider query batching, caching, or optimizing data pipelines

2. **Investigate GKE Sumatra Service Account**
   - 3.78M jobs (63% of job count) but minimal resource usage (0.0007 slot-hours)
   - Are these necessary or could they be batched/optimized?
   - Potential for reducing job count without impact on slot resources

3. **Optimize Monitor Shipment NoFlake**
   - **228 slot-hours** for only 3,128 jobs - very resource-intensive per job (0.073 slot-hours/job)
   - **$9.11 cost** - investigate query complexity
   - Likely complex data processing that could be optimized

4. **Review Monitor Narvar Metabase**
   - **136 slot-hours**, **$5.46 cost**
   - Review Metabase query patterns and optimize

5. **Optimize Dev-Testing Queries**
   - Appears in both top lists (jobs #3, slots #4)
   - High slot usage suggests resource-intensive queries
   - Review if testing can be optimized or run less frequently

6. **Monitor Top Service Accounts**
   - Top 5 by jobs = 90% of job volume
   - Top 4 by slots = 92% of slot usage
   - Set up alerts for unusual spikes in these accounts

---

## Summary

**Key Takeaway:** The AUTOMATED_CRITICAL workload is highly concentrated:
- **5 service accounts** = 90% of jobs
- **4 service accounts** = 92% of slot usage
- **1 service account (Airflow)** = 69% of slot usage (798 slot-hours)

**Optimization Priority:**
1. **Airflow service account** - Highest impact target (69% of slots, 798 slot-hours)
2. **Monitor Shipment** - Very resource-intensive per job (0.073 slot-hours/job)
3. **GKE Sumatra** - High volume but low resource (could reduce job count)
4. **Dev-Testing & Messaging** - Moderate optimization opportunities

**Note:** All costs shown are based on slot-hours × $0.04/hour (pay-as-you-go rate). Actual total monthly cost is ~$50,000 USD (user reported). Fixed vs. variable cost breakdown requires actual billing data.

## Next Steps

1. **CRITICAL:** Deep dive into Airflow service account queries - this is your #1 optimization target (798 slot-hours)
2. Investigate Monitor Shipment queries - understand why they're so resource-intensive (0.073 slot-hours/job)
3. Review GKE Sumatra - determine if 3.78M jobs/day is necessary or can be batched
4. Set up monitoring/alerts for top 5 service accounts
5. Consider query batching, caching, or workflow optimization for top contributors

**Cost Calculation Notes:**
- All costs calculated as: slot-hours × $0.04/hour
- Actual total monthly cost: ~$50,000 USD (user reported)
- Fixed vs. variable cost breakdown requires actual billing data
- The $0.04/hour rate used in queries is for analysis/estimation purposes

