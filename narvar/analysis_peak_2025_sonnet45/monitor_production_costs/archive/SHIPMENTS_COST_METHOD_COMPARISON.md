# Shipments Production Cost - Method Comparison Analysis

**Analysis Date:** November 14, 2025  
**Purpose:** Resolve $467,922 vs $200,957 discrepancy  
**Status:** 🔍 ANALYSIS IN PROGRESS

---

## 🎯 THE DISCREPANCY

**Two different methods, two very different results:**

| Method | Annual Cost | Difference |
|--------|-------------|------------|
| **Method A** (DoIT Billing + Traffic Class) | **$200,957** | Baseline |
| **Method B** (Direct Audit Log Analysis) | **$467,922** | **+$266,965 (+133%)** |

**This is a 2.3x difference that fundamentally impacts our pricing strategy!**

---

## 📋 METHOD A: DoIT Billing + Traffic Classification

**File:** `MONITOR_MERGE_COST_FINAL_RESULTS.md`  
**Date:** November 6, 2025  
**Result:** **$200,957/year**

### Plain English Explanation

**The Logic (Step-by-Step):**

1. **Pick a Baseline Period**
   - Used: September - October 2024 (2 months)
   - Why: Assumed to be a "typical" non-peak period

2. **Find Monitor's Percentage of Total BigQuery Usage**
   - Query the traffic classification table to find ALL jobs that:
     * Have "MERGE" in the query text
     * Have "SHIPMENTS" in the query text  
     * Are run by `monitor-base-us-prod@appspot.gserviceaccount.com`
   - Count their slot consumption during those 2 months
   - **Found:** 505,505 slot-hours consumed $24,972 in 2 months
   
3. **Calculate Monitor's Percentage of BQ Reservation**
   - Total BQ Reservation cost for those 2 months: $103,266
   - Monitor's share: $24,972 / $103,266 = **24.18%**
   
4. **Apply Percentage to Annual Reservation**
   - Get total annual BQ Reservation cost from DoIT billing: $619,598
   - Monitor's annual compute: $619,598 × 24.18% = **$149,832**
   
5. **Add Fixed Infrastructure Costs**
   - Storage (monitor-base-us-prod): $24,899/year (from billing)
   - Pub/Sub (monitor-base-us-prod): $26,226/year (from billing)
   
6. **Total**
   ```
   $149,832 (compute) + $24,899 (storage) + $26,226 (Pub/Sub) = $200,957/year
   ```

### Key Assumptions

✅ **Pros:**
- Uses actual billing data (DoIT)
- Includes infrastructure costs (Storage, Pub/Sub)
- Based on clean 2-month baseline

❌ **Cons:**
- Assumes Sep-Oct 2024 is representative of entire year
- Doesn't account for seasonal variations
- Percentage might change month-to-month
- Growth from 2024 to 2025 not captured

---

## 📋 METHOD B: Direct Audit Log Analysis

**File:** `SHIPMENTS_PRODUCTION_COST_UPDATED.md`  
**Date:** November 14, 2025  
**Result:** **$467,922/year**

### Plain English Explanation

**The Logic (Step-by-Step):**

1. **Pick TWO Time Periods (Peak + Baseline)**
   - Peak_2024_2025: November 2024 - January 2025 (3 months)
   - Baseline_2025_Sep_Oct: September - October 2025 (2 months)
   - **Total:** 5 months of actual data

2. **Search Audit Logs Directly**
   - Query `cloudaudit_googleapis_com_data_access` table
   - Find ALL jobs that:
     * Have destination table = `monitor_base.shipments`
     * Have statement type IN ('INSERT', 'MERGE', 'CREATE_TABLE_AS_SELECT', 'UPDATE')
     * Happened during our 5-month window
   - **Found:** 13,576 jobs consuming 1,445,535 slot-hours

3. **Calculate Cost Using BigQuery Pricing**
   - For RESERVED jobs: (slot-hours) × $0.0494 per slot-hour
   - Total 5-month cost: 1,445,535 × $0.0494 = **$71,409**

4. **Annualize (Scale to 12 Months)**
   ```
   Annual Cost = $71,409 × (12 months / 5 months) = $467,922/year
   ```

5. **No Infrastructure Costs**
   - This method only counts compute (MERGE operations)
   - Does NOT include Storage or Pub/Sub
   - Pure production cost for table creation/updates

### Key Assumptions

✅ **Pros:**
- Direct measurement (not extrapolation)
- Includes both peak (Nov-Jan) and baseline (Sep-Oct) periods
- Uses 2025 data (more recent)
- Matches consumption analysis periods

❌ **Cons:**
- Doesn't include Storage or Pub/Sub costs
- 5-month period might not represent full year
- Assumes linear annualization is valid
- No validation against billing data

---

## 🔍 ROOT CAUSES OF DISCREPANCY

### Factor 1: **Time Periods Analyzed**

| Factor | Method A | Method B |
|--------|----------|----------|
| **When** | Sep-Oct 2024 | Nov 2024-Jan 2025 + Sep-Oct 2025 |
| **Growth** | 2024 baseline | 2025 workload |
| **Seasonality** | Off-peak only | Includes peak (Nov-Jan) |

**Impact:** Peak months likely have 50-100% more traffic than off-peak months.

### Factor 2: **What's Included**

| Component | Method A | Method B |
|-----------|----------|----------|
| Compute (MERGE ops) | $149,832 | $467,922 |
| Storage | $24,899 | $0 (not included) |
| Pub/Sub | $26,226 | $0 (not included) |
| **TOTAL** | **$200,957** | **$467,922** |

**Impact:** Method B's compute-only cost ($467,922) is **3.1x** Method A's compute cost ($149,832)!

### Factor 3: **Calculation Method**

**Method A:**
```
Sep-Oct 2024 actual → Percentage → Apply to annual total
(Indirect measurement via percentage)
```

**Method B:**
```
5 months actual → Count every job → Annualize directly  
(Direct measurement via audit logs)
```

**Impact:** Direct counting may capture jobs that percentage method misses.

---

## 🧮 APPLES-TO-APPLES COMPARISON

To compare fairly, let's add infrastructure to Method B:

| Component | Method A | Method B (Adjusted) |
|-----------|----------|---------------------|
| Compute | $149,832 | $467,922 |
| Storage | $24,899 | $24,899 (same) |
| Pub/Sub | $26,226 | $26,226 (same) |
| **TOTAL** | **$200,957** | **$519,047** |

**Even adjusted, Method B is 2.6x higher!**

**The $266,090 compute difference is the real mystery.**

---

## 🔬 HYPOTHESIS: Why Such a Large Difference?

### Hypothesis 1: **Seasonal Growth (Most Likely)**

**Theory:** Nov-Jan 2024 (peak) had significantly more traffic than Sep-Oct 2024 (baseline)

**Evidence Needed:**
- Compare Sep-Oct 2024 vs Sep-Oct 2025 job counts
- Compare Sep-Oct 2024 vs Nov-Jan 2024 job counts  
- If Nov-Jan peak is 2-3x higher, this explains difference

**Test:** Query audit logs for Sep-Oct 2024 using Method B approach

---

### Hypothesis 2: **Year-over-Year Growth**

**Theory:** 2025 workload is genuinely higher than 2024

**Evidence:**
- Method A uses 2024 data
- Method B uses 2024-2025 data
- If platform grew 100%+ in one year, this explains difference

**Test:** Compare Sep-Oct 2024 vs Sep-Oct 2025 month-by-month

---

### Hypothesis 3: **Different Scope of Jobs**

**Theory:** Method A's text search misses some jobs

**Method A Query:**
```sql
WHERE UPPER(query_text_sample) LIKE '%MERGE%'
  AND UPPER(query_text_sample) LIKE '%SHIPMENTS%'
```

**Method B Query:**
```sql
WHERE destination_table.tableId = 'shipments'
  AND statement_type IN ('INSERT', 'MERGE', ...)
```

**Difference:** Method B catches ALL writes to shipments table, not just those with "SHIPMENTS" in query text.

**Test:** Run both queries for same time period

---

## 📊 NEXT STEPS: Monthly Analysis (18 Months)

To resolve this, we need to:

1. **Run Method B for Sep-Oct 2024** (Method A's baseline period)
   - Direct audit log count
   - Compare to Method A's 6,256 jobs / 505,505 slot-hours
   
2. **Run Both Methods Monthly for 18 Months**
   - June 2024 - November 2025
   - See seasonal patterns
   - Calculate average, median, peak vs baseline

3. **Validate Against Billing**
   - Get actual DoIT monthly costs
   - See which method tracks actual bills better

---

## 💡 RECOMMENDATION FOR PRICING STRATEGY

**While we resolve this:**

### Conservative Approach (Method A)
- Use: **$201K/year**
- Pro: Lower, safer estimate
- Con: May understate actual 2025 costs

### Aggressive Approach (Method B)  
- Use: **$468K/year** (compute only)
- Pro: Based on recent 2025 data
- Con: May overstate if includes unusual peak

### Hybrid Approach (RECOMMENDED)
- Use: **$350K-$400K/year**
- Rationale: Split the difference until validated
- Document uncertainty range in pricing model
- Re-validate after monthly analysis

---

## 📁 FILES TO CREATE

1. **`shipments_monthly_method_a.sql`** - Method A applied monthly
2. **`shipments_monthly_method_b.sql`** - Method B applied monthly  
3. **`shipments_cost_comparison_results.csv`** - 18 months of data
4. **`shipments_cost_validation.md`** - Findings and recommendation

---

**Next Action:** Create monthly comparison queries and run analysis

---

**Prepared by:** AI Assistant  
**Status:** 🔄 IN PROGRESS - Awaiting monthly analysis results

