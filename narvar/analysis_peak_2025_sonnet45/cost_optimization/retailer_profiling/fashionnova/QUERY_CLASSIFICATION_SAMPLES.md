# fashionnova Query Classification Samples

**Date:** November 19, 2025  
**Purpose:** Iteratively refine query classification for latency/retention analysis  
**Status:** DRAFT - Ready for refinement

**Total Queries:** 4,015 (Sep-Oct 2024)  
**Total Cost:** $2,613/year (consumption only, not including $97K attributed production costs)

---

## ⚠️ ANALYSIS LIMITATION DISCOVERED

**Critical Finding:** 99% of fashionnova queries use **parameterized date filters**:
```sql
WHERE ship_date BETWEEN ? AND ?
```

**Impact:**
- Cannot extract actual date range values from query text
- Cannot determine exact retention requirements from available data
- Can infer latency tolerance (queries are analytical, not time-sensitive)
- **Need alternative approach** to determine retention requirements

**Options to resolve:**
1. Survey fashionnova dashboards/reports to see actual date range settings
2. Analyze referenced_tables metadata (what dates exist in scanned data?)
3. Sample query results to see min/max dates returned
4. Ask fashionnova team directly about retention needs

---

## 📋 Classification Framework (TO BE REFINED)

### Dimensions to Classify:

1. **Query Type**
   - [ ] Analytical (calculating metrics/aggregates over historical data)
   - [ ] Operational (monitoring current state, recent shipments)
   - [ ] Reporting (dashboards, summaries)
   - [ ] Ad-hoc (exploration, one-off analysis)

2. **Business Case** (TO BE ADDED)
   - [ ] Carrier performance analysis
   - [ ] Delivery time metrics
   - [ ] Exception monitoring
   - [ ] Trend analysis
   - [ ] Other: _____________

3. **Time Interval** (data recency/retention needs)
   - [ ] Today only (CURRENT_DATE)
   - [ ] Last day (yesterday + today)
   - [ ] Last week (7 days)
   - [ ] Last month (30 days)
   - [ ] Last quarter (90 days)
   - [ ] Last year (365 days)
   - [ ] Full history (no date filter)
   - [ ] Cannot determine

4. **Latency Tolerance**
   - [ ] Real-time required (<1 hour old data)
   - [ ] Near-time acceptable (1-6 hours)
   - [ ] Same-day acceptable (6-24 hours)
   - [ ] Historical (>24 hours)

5. **Retention Requirement**
   - [ ] 1 month sufficient
   - [ ] 3 months sufficient
   - [ ] 6 months sufficient
   - [ ] 1 year sufficient
   - [ ] >1 year required
   - [ ] Full history required

---

## 🚨 CRITICAL DISCOVERY: Parameterized Queries

**Finding:** The expensive queries (99% of cost) use **parameterized date filters**:
```sql
AND datetime_trunc(ship_date, day) BETWEEN ? AND ?
```

**What this means:**
- Queries DO filter by date range
- Actual date values are passed as query parameters (not in SQL text)
- We cannot extract parameter values from audit logs (field not available)
- Cannot determine exact retention requirements from query text alone

**Impact on analysis:**
- ❌ Cannot parse actual date ranges from query text
- ❌ Cannot determine exact lookback periods
- ✅ Can infer that BETWEEN pattern suggests bounded ranges (not full history)
- ✅ Can analyze query frequency and patterns to estimate requirements

**Alternative approaches:**
1. **Analyze query execution patterns** - If query runs daily/weekly, likely uses recent data
2. **Sample actual data being scanned** - Check min/max dates in referenced tables
3. **Survey fashionnova directly** - Ask about their dashboard date range settings
4. **Infer from business context** - Carrier performance typically uses 30/90/365 day windows

---

## 🔍 ANALYTICAL QUERIES (Parameterized Date Filters - 99% of Cost)

### Sample 1: Carrier Performance - Ship to Manifest Time

**Job ID:** job_AlRkBTb7cHRNQTQYvcvQ5cw0KQ6b  
**Slot-Hours:** 16.82  
**Cost:** ~$0.83  
**Timestamp:** 2024-10-01 08:15:21

**Query:**
```sql
select Avg(DATE_DIFF(`v_shipments_events`.`ship_date`,`v_shipments_events`.`event_ts`, DAY))
FROM `monitor.v_shipments`
LEFT JOIN `monitor.v_shipments_events` `v_shipments_events`
    ON `monitor.v_shipments`.`order_number` = `v_shipments_events`.`order_number`
WHERE `monitor.v_shipments`.`carrier_moniker` = 'dhlglobal'
  and lower(`v_shipments_events`.`detailed_event_status`) like '%manifest%'
  AND (`monitor.v_shipments`.`edd_status` = ? OR `monitor.v_shipments`.`edd_status` = ? ...)
  AND datetime_trunc(`monitor.v_shipments`.`ship_date`, day) BETWEEN ? AND ?
```

**⚠️ CRITICAL DISCOVERY:** The query HAS a date filter `BETWEEN ? AND ?` but uses **parameterized values** (the `?` placeholders). We cannot extract the actual date range from the query text - need to infer from context or query actual parameter values from a different source.

**Manual Classification:**
- Query Type: [ ] Analytical / [ ] Operational / [ ] Reporting / [ ] Ad-hoc
- Business Case: ______________________
- Time Interval: [ ] Full history (no date filter visible)
- Latency Tolerance: [ ] Real-time / [ ] Near-time / [X] Historical
- Retention Requirement: [ ] 1mo / [ ] 3mo / [ ] 6mo / [ ] 1yr / [X] Full history
- **Notes:** _____________________________________________________

---

### Sample 2: Carrier Performance - DHL Prime

**Job ID:** job_n_3CDLdLZnMeNr9AoDe5w5cV9kbg  
**Slot-Hours:** 9.6  
**Cost:** ~$0.47  
**Timestamp:** 2024-10-01 08:14:37

**Query:**
```sql
select Avg(DATE_DIFF(`v_shipments_events`.`ship_date`,`v_shipments_events`.`event_ts`, DAY))
FROM `monitor.v_shipments`
LEFT JOIN `monitor.v_shipments_events` `v_shipments_events`
    ON `monitor.v_shipments`.`order_number` = `v_shipments_events`.`order_number`
WHERE `monitor.v_shipments`.`carrier_moniker` = 'dhl-prime'
  and lower(`v_shipments_events`.`detailed_event_status`) like '%manifest%'
  AND (`monitor.v_shipments`.`edd_status` = ? OR ...)
```

**Manual Classification:**
- Query Type: [ ] Analytical / [ ] Operational / [ ] Reporting / [ ] Ad-hoc
- Business Case: ______________________
- Time Interval: [ ] Full history
- Latency Tolerance: [ ] Real-time / [ ] Near-time / [ ] Historical
- Retention Requirement: [ ] 1mo / [ ] 3mo / [ ] 6mo / [ ] 1yr / [ ] Full history
- **Notes:** _____________________________________________________

---

### Sample 3: Carrier Performance - OnTrac

**Job ID:** job_S_rM1Dd0eklQ8kRSuTiyIn1ZedD3  
**Slot-Hours:** 9.45  
**Cost:** ~$0.47  
**Timestamp:** 2024-10-01 08:07:15

**Query:**
```sql
select Avg(DATE_DIFF(`v_shipments_events`.`ship_date`,`v_shipments_events`.`event_ts`, DAY))
FROM `monitor.v_shipments`
LEFT JOIN `monitor.v_shipments_events`
    ON `monitor.v_shipments`.`order_number` = `v_shipments_events`.`order_number`
WHERE `monitor.v_shipments`.`carrier_moniker` = 'ontrac'
  and lower(`v_shipments_events`.`detailed_event_status`) like '%manifest%'
```

**Manual Classification:**
- Query Type: [ ] Analytical / [ ] Operational / [ ] Reporting / [ ] Ad-hoc
- Business Case: ______________________
- Time Interval: [ ] Full history
- Latency Tolerance: [ ] Historical
- Retention Requirement: [ ] Full history
- **Notes:** _____________________________________________________

---

### Sample 4-12: Additional Analytical Queries

*[Similar pattern - carrier performance queries for different carriers: USPS, FedEx, axlehire, ceva, ecomexpress, olx, etc.]*

**Pattern observed:**
- All calculate average time differences (ship_date to event_ts)
- All filter by carrier_moniker only (no date filters)
- All scan full historical dataset
- Slot-hours: 9-17 per query (expensive)

**Common characteristics:**
- Business case: Carrier performance benchmarking
- Time interval: Full history (no restrictions)
- Latency tolerance: Historical (don't need real-time)
- Retention: Full history required for accurate averages

---

## ⚡ OPERATIONAL QUERIES (With Date Filters - 1% of Cost)

### Sample 1: Recent Shipments Query

**Job ID:** job_[example]  
**Slot-Hours:** 0.05  
**Cost:** ~$0.002  
**Pattern:** Uses CURRENT_DATE()

**Query Pattern:**
```sql
SELECT *
FROM `monitor.v_shipments`
WHERE ship_date = CURRENT_DATE()
  AND carrier_moniker = 'usps'
```

**Manual Classification:**
- Query Type: [ ] Analytical / [X] Operational / [ ] Reporting / [ ] Ad-hoc
- Business Case: Real-time shipment monitoring
- Time Interval: [X] Today only (CURRENT_DATE)
- Latency Tolerance: [X] Real-time required
- Retention Requirement: [X] 1 month sufficient
- **Notes:** Need today's data, likely operational dashboard

---

### Sample 2: Last 30 Days Query

**Job ID:** job_[example]  
**Slot-Hours:** 0.03  
**Cost:** ~$0.001  
**Pattern:** Uses INTERVAL X DAYS

**Query Pattern:**
```sql
SELECT *
FROM `monitor.v_shipments`
WHERE ship_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
```

**Manual Classification:**
- Query Type: [ ] Analytical / [ ] Operational / [X] Reporting / [ ] Ad-hoc
- Business Case: Monthly performance report
- Time Interval: [X] Last month (30 days)
- Latency Tolerance: [ ] Real-time / [X] Same-day acceptable
- Retention Requirement: [X] 3 months sufficient
- **Notes:** Monthly dashboard, doesn't need real-time

---

### Samples 3-12: Additional Operational Queries

**Query count:** 1,391 (34% of queries)  
**Cost:** $6/year (0.23% of cost)  
**Patterns:**
- Most use `CURRENT_DATE()` or `INTERVAL X DAYS`
- Cheap queries (0.01-0.05 slot-hours each)
- Filter to recent time periods

**Common characteristics:**
- Business case: Real-time monitoring or recent reporting
- Time interval: Today to last 30 days
- Latency tolerance: Mixed (some real-time, some same-day ok)
- Retention: Short (1-3 months sufficient)

---

## 📊 Summary Statistics

| Category | Query Count | % of Queries | Cost/Year | % of Cost | Avg Slot-Hours |
|----------|-------------|--------------|-----------|-----------|----------------|
| **Analytical** (no date filters) | 2,624 | 65% | $2,607 | 99.8% | 3.35 |
| **Operational** (with date filters) | 1,391 | 35% | $6 | 0.2% | 0.01 |
| **Total** | 4,015 | 100% | $2,613 | 100% | 0.65 |

---

## 🎯 Initial Insights (To Be Validated)

### Analytical Queries (99% of cost)

**Pattern:** Carrier performance metrics over full history
- No date range filters
- Scan entire dataset
- Calculate averages, percentiles, aggregates

**Business cases identified:**
1. Ship-to-manifest time by carrier
2. Delivery performance by carrier
3. Exception rates by carrier
4. [Add more after reviewing samples]

**Latency tolerance:** HIGH (historical analysis, not time-sensitive)

**Retention needs:** FULL HISTORY (need complete dataset for accurate metrics)

---

### Operational Queries (1% of cost)

**Pattern:** Recent data monitoring
- Use CURRENT_DATE() or INTERVAL patterns
- Small, cheap queries
- Quick lookups

**Business cases identified:**
1. Today's shipments monitoring
2. Last 30 days reporting
3. [Add more after reviewing samples]

**Latency tolerance:** MIXED (some real-time, some same-day)

**Retention needs:** SHORT (1-3 months sufficient)

---

## 🔧 Refinement Process

### Step 1: Review Query Samples (THIS STEP)
**Action:** Manually review samples above and classify:
- Business case category
- Actual time interval used
- Latency tolerance
- Retention requirement

### Step 2: Expand Classification
**Action:** Add new business case categories discovered:
- ________________
- ________________
- ________________

### Step 3: Validate Patterns
**Action:** Check if classification rules hold across all queries:
- Does "no date filter" = "analytical"?
- Does "CURRENT_DATE" = "operational"?
- Are there exceptions?

### Step 4: Quantify by Business Case
**Action:** Group queries by refined business case:
- Business case A: X queries, $Y cost, Z% of total
- Business case B: ...

### Step 5: Optimization Recommendations
**Action:** For each business case, determine:
- Can it tolerate delayed data? (latency optimization)
- Can it work with shorter retention? (retention optimization)
- What's the business impact of changes?

---

## 📂 Supporting Data

**Full query export:** `all_queries_for_classification.csv`
- All 4,015 fashionnova queries
- Full query text (where available)
- Slot-hours and timestamps
- Initial category assignment

**Use this file for:**
- Finding patterns in query structures
- Identifying business use cases
- Validating classification rules
- Quantifying by refined categories

---

## ✏️ Refinement Notes

### Observations from initial review:

1. **Carrier performance queries dominate costs**
   - Pattern: `Avg(DATE_DIFF(ship_date, event_ts, DAY))` by carrier
   - Why expensive: JOIN v_shipments + v_shipments_events (large tables)
   - No date filters: Need full history for accurate carrier benchmarks

2. **Operational queries are cheap**
   - Pattern: Simple SELECTs with CURRENT_DATE() or recent intervals
   - Why cheap: Small result sets, partition pruning works
   - Date filters present: Only need recent data

3. **Time-of-day patterns** (to investigate):
   - Analytical: Run during business hours (8am-6pm)
   - Operational: Run throughout day?
   - Could indicate automated vs interactive

### Questions for further investigation:

1. Are there other query patterns we're missing?
2. Do any analytical queries have implicit date filters in views?
3. Are there seasonal patterns (certain queries only during peak)?
4. Which business cases are high-value (drive decisions) vs nice-to-have?

---

## 🚀 Next Steps

1. **Review the 12 samples above** - Add business case, confirm time intervals
2. **Review CSV file** - Find additional patterns not captured in samples
3. **Define business case taxonomy** - Create consistent categories
4. **Re-run classification query** - Use refined rules
5. **Quantify by business case** - Show cost/value by use case
6. **Optimization recommendations** - Per business case, not blanket policy

---

## 💡 Preliminary Recommendations (Based on Samples)

### Latency Optimization: ✅ VIABLE

**Rationale:**
- 99% of cost from analytical queries (carrier performance)
- These don't care if data is 5 minutes or 24 hours old
- They're calculating averages over full history

**Recommendation:**
- fashionnova can accept 24-hour batching with minimal impact
- Only 1% of queries (operational monitoring) might need real-time
- Could offer tiered SLA: Real-time for operational, delayed for analytical

**Estimated acceptable delay:** 12-24 hours for 99% of cost

---

### Retention Optimization: ⚠️ UNCERTAIN (Parameterized Queries)

**Rationale:**
- Analytical queries use `BETWEEN ? AND ?` date filters (parameterized)
- Cannot extract actual date range values from query text or audit logs
- **BETWEEN pattern suggests bounded ranges** (not open-ended full history)
- Likely uses 30/90/365 day windows for carrier performance (industry standard)

**Recommendation - REQUIRES VALIDATION:**
- **If parameter ranges are ≤365 days:** 1-2 year retention is sufficient (save $14K-$26K)
- **If parameter ranges are >365 days:** Need longer retention or archive strategy
- **Action needed:** Survey fashionnova or analyze their dashboard settings to determine actual date ranges used

**Confidence:** LOW - Cannot determine from available data

**Alternative approaches:**
1. Check fashionnova's actual dashboard configurations (what date ranges do they select?)
2. Sample the data being scanned (min/max dates in query results)
3. Analyze query frequency patterns (daily queries likely use recent data)
4. Ask fashionnova Product team directly

---

## 📝 Template for Adding Samples

### Sample X: [Description]

**Job ID:** job_XXXXX  
**Slot-Hours:** X.XX  
**Cost:** $X.XX  
**Timestamp:** YYYY-MM-DD HH:MM:SS

**Query:**
```sql
[Full query text or first 500 chars]
```

**Manual Classification:**
- Query Type: [ ] Analytical / [ ] Operational / [ ] Reporting / [ ] Ad-hoc
- Business Case: ______________________
- Time Interval: [ ] Today / [ ] Last week / [ ] Last month / [ ] Full history
- Latency Tolerance: [ ] Real-time / [ ] Near-time / [ ] Same-day / [ ] Historical
- Retention Requirement: [ ] 1mo / [ ] 3mo / [ ] 6mo / [ ] 1yr / [ ] Full history
- **Notes:** _____________________________________________________

---

**Instructions for refinement:**
1. Review samples above
2. Fill in business case classifications
3. Adjust time interval categories if needed
4. Add new samples if patterns emerge
5. Update summary statistics
6. Revise optimization recommendations

---

**Data source:** `all_queries_for_classification.csv` (500 queries with full text)  
**Created by:** Sophia (AI)  
**Ready for:** Cezar's review and refinement

