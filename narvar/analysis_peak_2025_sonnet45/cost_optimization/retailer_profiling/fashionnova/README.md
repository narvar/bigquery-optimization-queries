# fashionnova Usage Analysis

**Retailer:** fashionnova  
**Priority:** HIGHEST (74.89% of platform compute, $99,718/year cost)  
**Status:** Not started  
**Timeline:** Week 1-2 of Phase 1

---

## 🎯 Why fashionnova is Critical

**Cost Impact:**
- Annual cost: $99,718 (37.8% of $263K platform cost)
- Slot-hour consumption: 74.89% of all Monitor queries
- 107.7x more expensive than average retailer ($926)
- Only 6.83% of query count but 74.89% of compute

**Strategic Impact:**
- Most customized integration
- Highest traffic volume
- **Their requirements likely define platform constraints**
- If fashionnova can accept delays/shorter retention → most retailers can
- If fashionnova needs real-time/long retention → tiered SLA model required

---

## 📋 Analysis Objectives

### 1. Latency Requirements
**Question:** How fresh does fashionnova's data need to be?

**Analysis:**
- Extract query execution times
- Extract date filters from queries (ship_date, order_date, etc.)
- Calculate: query_time - MAX(data_date_filtered)
- **Result:** Distribution showing "age of data when queried"

**Output:**
- X% of queries use data <1 hour old (need real-time)
- Y% of queries use data <6 hours old (need near-time)
- Z% of queries use data <24 hours old (same-day acceptable)
- Remaining queries use historical data (batch acceptable)

**Decision criteria:**
- If >80% query data >6 hours old → 6-hour batching is safe
- If >90% query data >24 hours old → daily batching is safe
- Else → fashionnova needs real-time, explore tiered SLA

---

### 2. Retention Requirements
**Question:** How far back does fashionnova query?

**Analysis:**
- Extract date range filters from queries
- Calculate: MAX(query_date - MIN(data_date_filtered))
- **Result:** Distribution showing "maximum lookback period"

**Output:**
- X% of queries look back <3 months
- Y% of queries look back <6 months
- Z% of queries look back <1 year
- Remaining queries need >1 year historical

**Decision criteria:**
- If >90% look back <6 months → 1-year retention is safe
- If >95% look back <1 year → 2-year retention is safe
- Else → Need long retention or archive strategy

---

### 3. Cost Breakdown
**Question:** Where does fashionnova's $99,718 cost come from?

**Analysis:**
- Break down by table (shipments, orders, returns, benchmarks)
- Break down by operation type (ETL vs consumption)
- Break down by query complexity (slot-hours per query)
- Validate v_orders usage

**Output:**
- Cost by table
- ETL cost vs consumption cost
- Inefficiency opportunities (query optimization)

---

### 4. Query Pattern Classification
**Question:** What types of queries does fashionnova run?

**Analysis:**
- Classify by dashboard type (operations, analytics, executive)
- Identify time-sensitive queries (filtering for "today" or "last hour")
- Identify historical queries (filtering for date ranges >30 days ago)
- Frequency patterns (hourly, daily, weekly, ad-hoc)

**Output:**
- Dashboard usage breakdown
- Time-sensitive use cases
- Candidates for optimization

---

## 📂 File Organization

### **queries/**
- `fashionnova_latency_analysis.sql` - Data freshness requirements
- `fashionnova_retention_analysis.sql` - Historical data lookback
- `fashionnova_cost_breakdown.sql` - Cost by table and operation
- `fashionnova_query_patterns.sql` - Query classification and patterns

### **results/**
- `latency_requirements.csv` - Distribution of data freshness needs
- `retention_requirements.csv` - Distribution of lookback periods
- `cost_breakdown.csv` - Detailed cost attribution
- `query_patterns.csv` - Query classification results

### **Analysis Document:**
- `FASHIONNOVA_USAGE_ANALYSIS.md` - Consolidated findings and recommendations

---

## 🔬 Methodology

### Data Source
`narvar-data-lake.query_opt.traffic_classification`

### Filters
```sql
WHERE retailer_moniker = 'fashionnova'
  AND consumer_subcategory = 'MONITOR'
  AND DATE(start_time) BETWEEN '2024-09-01' AND '2024-10-31'  -- 2-month baseline
```

### Challenges

1. **Query text truncation:** Only 500 characters available
   - May miss date filters in complex queries
   - Need to analyze sample coverage

2. **Date filter extraction:** Multiple formats
   - Explicit dates: `WHERE ship_date = '2024-10-15'`
   - Relative dates: `WHERE ship_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)`
   - Dynamic ranges: `WHERE ship_date BETWEEN X AND Y`
   - Need robust regex patterns

3. **Attribution complexity:** Queries join multiple tables
   - Need to determine primary table being queried
   - May need to weight by bytes scanned per table

---

## 🎯 Success Criteria

**Phase 1 is successful if we can answer:**

1. ✅ Can fashionnova tolerate 6-hour data delays? (Y/N with confidence %)
2. ✅ Can fashionnova accept 1-year retention? (Y/N with confidence %)
3. ✅ What % of fashionnova's cost is ETL vs consumption?
4. ✅ Which dashboard types drive real-time requirements?
5. ✅ What's the business impact of optimization scenarios?

**If answers are unclear:** Need to survey fashionnova directly or extend analysis period

---

## 🚀 Next Steps

1. Create fashionnova latency analysis query
2. Run query and analyze results
3. Create fashionnova retention analysis query
4. Run query and analyze results
5. Document findings in FASHIONNOVA_USAGE_ANALYSIS.md
6. Use findings to validate optimization scenarios

**Start:** Create latency analysis query  
**Owner:** Data Engineering + AI

---

**Last Updated:** November 19, 2025  
**Status:** Ready to begin

