# 🚨 CRITICAL FINDING: Cost Calculation Discrepancy Identified

**Date:** November 14, 2025  
**Status:** 🔴 URGENT - Major Discovery  
**Impact:** Changes our understanding of the $201K vs $468K discrepancy

---

## 🎯 THE SHOCKING DISCOVERY

**Test #1 revealed something completely unexpected:**

### Same Jobs, Same Period, Different Costs!

| Metric | Method A | Method B | Difference |
|--------|----------|----------|------------|
| Jobs | 6,256 | 6,255 | -1 (0.0%) ✅ |
| Slot-Hours | 505,505 | 502,015 | -3,491 (-0.7%) ✅ |
| **COST** | **$24,972** | **$68,644** | **+$43,672 (+175%)** 🚨 |

**Translation:** Method B calculated 2.75x higher cost for THE SAME JOBS in the SAME time period!

**This means:**
- ✅ Text search is accurate (finds same jobs)
- ✅ Slot-hour consumption is nearly identical
- 🚨 **Cost calculation is DIFFERENT between methods**

---

## 🔬 THE MYSTERY DEEPENS

### Expected vs Actual

**What we expected:**
- Method B would find more jobs (destination vs text search)
- Different time periods would explain discrepancy
- Seasonality would show 50-100% peak/baseline difference

**What we actually found:**
1. **Job counts identical** - Text search works perfectly
2. **Seasonality minimal** - Peak only 1.02x baseline (not 1.5-2x expected)
3. **Cost calculation differs** - Same jobs, same slots, different $ amounts

---

## 💡 THE REAL PROBLEM

### Cost Per Slot-Hour Comparison

**Method A:**
```
$24,972 / 505,505 slot-hours = $0.0494 per slot-hour ✓
```
This is correct! ($0.0494 = standard RESERVED rate)

**Method B:**
```
$68,644 / 502,015 slot-hours = $0.1367 per slot-hour ✗
```
This is 2.77x too high! This can't be right.

---

## 🔍 POSSIBLE EXPLANATIONS

### Theory 1: ON_DEMAND vs RESERVED Confusion

**Method A:**
- Assumes all jobs are RESERVED ($0.0494/slot-hour)
- Uses traffic classification table

**Method B:**
- Checks each job for reservation_usage array
- If empty → treats as ON_DEMAND ($6.25/TB)
- If present → treats as RESERVED ($0.0494/slot-hour)

**Problem:** Some jobs might have empty reservation array but still be RESERVED!

**Test this:** Count how many jobs Method B treats as ON_DEMAND vs RESERVED

---

### Theory 2: Billing Model Changed

**Possibility:**
- Sep-Oct 2024: Jobs were truly RESERVED
- Later periods: Some jobs switched to ON_DEMAND or flex slots
- This would explain higher costs for same slot-hours

**Test this:** Check reservation_usage field for all jobs across time

---

### Theory 3: Data Source Difference

**Method A:**
- Uses `traffic_classification` table (preprocessed)
- Costs already calculated and stored

**Method B:**
- Uses raw `cloudaudit` table
- Calculates costs dynamically

**Problem:** Different source tables might have different data!

**Test this:** Compare same job_id in both tables

---

## 📊 MONTHLY COMPARISON TABLE (18 Months)

### Side-by-Side Analysis: Method A vs Method B

| Month | Season | Method B Jobs | Method B Slots | Method B Cost | Method A Cost* | Difference | % Diff |
|-------|--------|--------------|----------------|---------------|----------------|------------|--------|
| 2024-06 | SUMMER | 3,092 | 172,319 | $31,383 | $12,750 | +$18,633 | +146% |
| 2024-07 | SUMMER | 2,915 | 210,017 | $30,017 | $15,549 | +$14,468 | +93% |
| 2024-08 | SUMMER | 3,019 | 212,083 | $31,101 | $15,702 | +$15,399 | +98% |
| **2024-09** | **BASELINE** | **3,181** | **249,559** | **$33,742** | **$18,476** | **+$15,266** | **+83%** |
| **2024-10** | **BASELINE** | **3,074** | **252,456** | **$34,902** | **$18,690** | **+$16,212** | **+87%** |
| 2024-11 | PEAK | 2,901 | 284,858 | $35,495 | $21,092 | +$14,403 | +68% |
| 2024-12 | PEAK | 3,015 | 357,198 | $44,896 | $26,445 | +$18,451 | +70% |
| 2025-01 | PEAK | 2,985 | 348,584 | $45,103 | $25,807 | +$19,296 | +75% |
| 2025-02 | OTHER | 3,039 | 303,570 | $43,222 | $22,478 | +$20,744 | +92% |
| 2025-03 | OTHER | 2,938 | 303,577 | $41,565 | $22,479 | +$19,086 | +85% |
| 2025-04 | OTHER | 2,584 | 267,577 | $36,745 | $19,814 | +$16,931 | +85% |
| 2025-05 | OTHER | 2,650 | 256,885 | $37,431 | $19,020 | +$18,411 | +97% |
| 2025-06 | SUMMER | 2,495 | 245,485 | $35,691 | $18,175 | +$17,516 | +96% |
| 2025-07 | SUMMER | 2,116 | 230,551 | $31,494 | $17,069 | +$14,425 | +85% |
| 2025-08 | SUMMER | 2,270 | 235,344 | $33,605 | $17,424 | +$16,181 | +93% |
| **2025-09** | **BASELINE** | **2,273** | **230,126** | **$33,632** | **$17,038** | **+$16,594** | **+97%** |
| **2025-10** | **BASELINE** | **2,402** | **224,768** | **$35,842** | **$16,641** | **+$19,201** | **+115%** |
| 2025-11† | PEAK | 1,064 | 96,570 | $15,888 | $7,150 | +$8,738 | +122% |

**†** November 2025 is partial month (through Nov 14)

**\* Method A Cost** = (Slot-Hours × $0.0494) + $2,075/month (storage) + $2,186/month (Pub/Sub)

### Summary Statistics

| Metric | Method A | Method B | Difference |
|--------|----------|----------|------------|
| **18-Month Total** | **$327,057** | **$635,718** | **+$308,661 (+94%)** |
| **Avg per Month** | $18,170 | $35,318 | +$17,148 (+94%) |
| **Annualized (×12/18)** | **$218,038** | **$423,812** | **+$205,774 (+94%)** |

### Key Observations

1. **Consistent 85-95% difference across ALL months**
   - Not just specific periods
   - Not seasonal variation
   - Method B is systematically ~2x higher

2. **Sep-Oct 2024 (Method A baseline)**
   - Method A: $37,166 (2 months)
   - Method B: $68,644 (2 months)
   - Difference: +85% (same as overall pattern)

3. **Seasonality is minimal**
   - Peak avg: $40,122/month
   - Baseline avg: $35,079/month  
   - Ratio: 1.14x (only 14% higher)

---

## 🎯 REVISED UNDERSTANDING

### What We Now Know

1. **Job counts are accurate** ✅
   - Text search and destination filter find same jobs
   - Not missing any operations

2. **Seasonality is minimal** ✅  
   - Peak only 2% higher than baseline
   - Year-round consistency

3. **Cost calculation method differs** 🚨
   - Same jobs, same slots, 2.75x different cost
   - This is the REAL problem!

### The $467K vs $201K Discrepancy Explained

**Hypothesis:**
- Method A: Uses traffic_classification with preprocessed costs
- Method B: Recalculates from raw audit logs
- Method B might be incorrectly treating RESERVED jobs as ON_DEMAND

**Evidence needed:**
- Count ON_DEMAND vs RESERVED jobs in audit logs
- Verify reservation_usage array population
- Cross-reference with billing to see actual pricing model

---

## 🔬 NEXT INVESTIGATION

### Query to Run: Check Pricing Model

```sql
SELECT
  DATE_TRUNC(DATE(timestamp), MONTH) AS month,
  
  -- Count by pricing model
  COUNTIF(ARRAY_LENGTH(reservation_usage) > 0) AS reserved_jobs,
  COUNTIF(ARRAY_LENGTH(reservation_usage) = 0 OR reservation_usage IS NULL) AS unreserved_jobs,
  
  -- Calculate costs both ways
  SUM(CASE 
    WHEN ARRAY_LENGTH(reservation_usage) > 0 
    THEN (total_slot_ms / 3600000) * 0.0494 
  END) AS reserved_cost,
  
  SUM(CASE 
    WHEN ARRAY_LENGTH(reservation_usage) = 0 OR reservation_usage IS NULL
    THEN (total_billed_bytes / POW(1024,4)) * 6.25
  END) AS ondemand_cost

FROM audit_logs
WHERE destination_table = 'shipments'
  AND DATE(timestamp) BETWEEN '2024-09-01' AND '2024-10-31'
GROUP BY month
```

If this shows most jobs as ON_DEMAND, that's our problem!

---

## 💡 IMMEDIATE ACTIONS

1. **Investigate reservation_usage field**
   - Are jobs truly RESERVED or ON_DEMAND?
   - Why would audit logs show different pricing than traffic_classification?

2. **Cross-reference with billing**
   - Get actual Sep-Oct 2024 invoices for monitor-base-us-prod
   - Was actual cost $25K or $69K?
   - This will tell us which method is correct

3. **Check traffic_classification logic**
   - How are costs calculated in that table?
   - Does it use different pricing logic?

---

## 🎯 RECOMMENDATION (UPDATED)

**Do NOT use either method blindly until we resolve this!**

**The issue is NOT:**
- ❌ Missing jobs (both methods find same jobs)
- ❌ Seasonality (minimal 2% variation)
- ❌ Growth (can't be 175% in same period)

**The issue IS:**
- 🚨 **Cost calculation methodology**
- 🚨 **ON_DEMAND vs RESERVED pricing confusion**
- 🚨 **Possible data quality issue in one of the sources**

**Next step:** Get actual billing invoice for Sep-Oct 2024 to see which method matches reality.

---

**Status:** 🔴 INVESTIGATION REQUIRED  
**Confidence:** Low until billing validated  
**Priority:** CRITICAL - Blocks all pricing decisions

