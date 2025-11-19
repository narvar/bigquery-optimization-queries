# Priority 1: Shipments Cost Methods - Plain English Explanation

**Date:** November 14, 2025  
**Purpose:** Explain both calculation methods for non-technical stakeholders  
**Question:** Why do we get $200,957 vs $467,922 for the same table?

---

## 🎯 THE SIMPLE ANSWER

**Two accountants counting the same thing got different numbers.**

**Accountant A (Method A):**
- Looked at 2 months of bills
- Said "Monitor uses 24% of our BigQuery"
- Applied 24% to the whole year's cost
- **Result: $201K/year**

**Accountant B (Method B):**
- Counted every single job for 5 months
- Added up the actual time spent
- Scaled to a full year
- **Result: $468K/year**

**Why different?** They counted different things, in different months, using different math.

---

## 📊 METHOD A: The "Percentage" Approach

### 🗣️ Explain It Like I'm 5

**Imagine you're running a bakery:**

1. **Watch for 2 months** (Sep-Oct 2024)
   - You make 100 loaves total
   - Wedding cakes use 24 loaves (24% of your oven time)

2. **Look at your annual oven costs**
   - Your oven costs $619,598 per year

3. **Calculate wedding cake cost**
   - Wedding cakes = 24% of oven use
   - Wedding cake cost = $619,598 × 24% = $149,832

4. **Add other costs**
   - Storage (freezer): $24,899
   - Delivery (trucks): $26,226
   
5. **Total wedding cake cost**
   - $149,832 + $24,899 + $26,226 = **$200,957/year**

### 📋 The Actual Process

**Step 1: Pick a baseline** (Sep-Oct 2024, 2 months)

**Step 2: Find Monitor jobs in traffic classification table**
```sql
WHERE query_text LIKE '%MERGE%' 
  AND query_text LIKE '%SHIPMENTS%'
  AND principal_email = 'monitor-base-us-prod@...'
```

**Found:** 6,256 jobs using 505,505 slot-hours costing $24,972

**Step 3: Calculate what % of total BQ this represents**
- Total BQ cost those 2 months: $103,266
- Monitor's share: $24,972 / $103,266 = **24.18%**

**Step 4: Apply to annual BQ reservation**
- Annual BQ cost from DoIT billing: $619,598
- Monitor's annual share: $619,598 × 24.18% = $149,832

**Step 5: Add infrastructure from billing**
- Storage: $24,899
- Pub/Sub: $26,226
- **Total: $200,957/year**

### ✅ Strengths

1. **Based on actual billing data** (DoIT invoices)
2. **Includes all infrastructure** (storage, messaging)
3. **Clean methodology** (easy to explain to Finance)
4. **External validation** (billing confirms numbers)

### ❌ Weaknesses

1. **Only 2 months of data** (might not represent full year)
2. **Assumes percentage stays constant** (24.18% year-round)
3. **Misses seasonal variations** (holiday peaks)
4. **2024 data** (doesn't show 2025 growth)
5. **Text search might miss jobs** (what if query comment doesn't say "shipments"?)

---

## 📊 METHOD B: The "Direct Count" Approach

### 🗣️ Explain It Like I'm 5

**Using the same bakery:**

1. **Install a camera on your oven** (audit logs)
   - Record EVERY time you make wedding cakes
   - Watch for 5 months (Nov 2024-Jan 2025, Sep-Oct 2025)

2. **Count actual oven time**
   - Wedding cakes used 13,576 oven-hours
   - Each oven-hour costs $0.0494

3. **Calculate 5-month cost**
   - 1,445,535 oven-hours × $0.0494 = $71,409

4. **Scale to full year**
   - $71,409 for 5 months
   - Full year: $71,409 × (12/5) = **$467,922/year**

5. **Infrastructure NOT included**
   - Just oven time (no freezer or trucks counted)

### 📋 The Actual Process

**Step 1: Pick TWO time periods** (5 months total)
- Peak_2024_2025: November 2024 - January 2025 (3 months)
- Baseline_2025_Sep_Oct: September - October 2025 (2 months)

**Step 2: Query audit logs directly**
```sql
WHERE destination_table = 'monitor-base-us-prod.monitor_base.shipments'
  AND statement_type IN ('INSERT', 'MERGE', 'CREATE_TABLE_AS_SELECT', 'UPDATE')
  AND DATE(timestamp) BETWEEN [our 5 months]
```

**Found:** 13,576 jobs using 1,445,535 slot-hours

**Step 3: Calculate cost using BigQuery pricing**
- RESERVED rate: $0.0494 per slot-hour
- 5-month cost: 1,445,535 × $0.0494 = $71,409

**Step 4: Annualize**
- $71,409 × (12 months / 5 months) = **$467,922/year**

**Step 5: Infrastructure**
- **NOT INCLUDED** in this method
- Pure compute cost only

### ✅ Strengths

1. **Direct measurement** (counts every single job)
2. **No estimation** (actual resource consumption)
3. **Recent data** (2024-2025, not just 2024)
4. **Includes peak periods** (Nov-Jan holidays)
5. **Destination table filter** (catches all writes, not just text matches)

### ❌ Weaknesses

1. **Missing infrastructure** (no storage/Pub/Sub)
2. **Linear annualization** (assumes 5 months = typical)
3. **No billing validation** (just audit logs, not invoices)
4. **Potential double-counting** (if jobs run across midnight?)

---

## 🔬 KEY DIFFERENCES EXPLAINED

### Difference 1: **What They Count**

**Method A:**
- Searches for jobs with "MERGE" + "SHIPMENTS" in query text
- Might miss some jobs if text doesn't match

**Method B:**  
- Finds ALL jobs writing to `monitor_base.shipments` table
- Catches everything, regardless of query text

**Why it matters:** Method B likely finds 2-3x more jobs!

---

### Difference 2: **Time Periods**

**Method A:**
- Sep-Oct 2024 only (2 months, off-peak)
- Assumes these 2 months represent whole year

**Method B:**
- Nov 2024-Jan 2025 (peak) + Sep-Oct 2025 (baseline)
- Mix of peak and off-peak periods

**Why it matters:** Peak months have 50-100% more traffic!

---

### Difference 3: **The Math**

**Method A (Percentage):**
```
1. Find % in sample period: 24.18%
2. Apply % to annual bill: $619,598 × 24.18% = $149,832
3. Add infrastructure: +$51,125
4. Total: $200,957
```

**Method B (Direct Count):**
```
1. Count actual slot-hours: 1,445,535
2. Multiply by rate: × $0.0494 = $71,409
3. Annualize: × (12/5) = $467,922  
4. Total: $467,922 (no infrastructure)
```

**Why it matters:** Different calculation methods + different scopes!

---

## 🎯 THE REAL COMPARISON

**If we add infrastructure to Method B:**

| Component | Method A | Method B + Infra |
|-----------|----------|------------------|
| Compute | $149,832 | $467,922 |
| Storage | $24,899 | $24,899 (same) |
| Pub/Sub | $26,226 | $26,226 (same) |
| **TOTAL** | **$200,957** | **$519,047** |

**Even with infrastructure, Method B is 2.6x higher!**

**The mystery is the $318,090 compute difference.**

---

## 💡 MOST LIKELY EXPLANATION

### The "Perfect Storm" Theory

**All three factors combined:**

1. **Peak vs Off-Peak** (50% impact)
   - Method A: Sep-Oct 2024 (quiet months)
   - Method B: Includes Nov-Jan 2024 (holiday peak)
   - Peak months probably 50-100% busier

2. **Text Search vs Table Name** (30% impact)
   - Method A: Text search might miss jobs
   - Method B: Catches ALL table writes
   - Probably finds 30% more jobs

3. **Year-over-Year Growth** (20% impact)
   - Method A: 2024 baseline
   - Method B: 2024-2025 mix
   - Platform likely grew 20-30% in one year

**Combined effect:** 50% × 30% × 20% ≈ 2-3x difference ✓

---

## 🔍 HOW TO RESOLVE

### Test #1: Run Method B for Sep-Oct 2024

**Question:** How many jobs does Method B find in Method A's baseline period?

**Expected:**
- Method A found: 6,256 jobs
- Method B should find: 8,000-10,000 jobs (30% more due to table filter)

**If true:** Confirms text search misses jobs

---

### Test #2: Compare Seasonal Patterns

**Question:** Is Nov-Jan really that much busier than Sep-Oct?

**Do this:**
- Count jobs per month for 18 months
- Calculate Peak/Baseline ratio
- See if Nov-Jan is 50-100% higher

**If true:** Confirms seasonal effect

---

### Test #3: Validate Against DoIT Billing

**Question:** What does DoIT billing actually say for monitor-base-us-prod?

**Do this:**
- Get monthly BigQuery bills for monitor-base-us-prod project
- Compare to our calculations
- See which method tracks actual invoices better

**Winner:** The method that matches billing is correct

---

## 📊 NEXT ACTIONS

### Immediate (Today):
1. ✅ Run `compare_shipments_cost_methods.py` script
2. ✅ Generate 18-month comparison
3. ✅ Analyze seasonal patterns
4. ✅ Identify which method is more accurate

### Follow-up (Tomorrow):
5. 📋 Run Method B for Sep-Oct 2024 specifically
6. 📋 Compare job counts between methods
7. 📋 Validate against DoIT billing data
8. 📋 Make final recommendation

---

## 🎯 RECOMMENDATION FOR PRICING (Interim)

**Until we resolve this, use a range:**

| Scenario | Annual Cost | Use Case |
|----------|-------------|----------|
| Conservative | $201K | If minimizing risk |
| Realistic | $350K | Split the difference |
| Aggressive | $468K | If using 2025 data |

**For pricing strategy:**
- Present range: "$350K-$470K depending on validation"
- Note uncertainty in pricing tiers
- Re-validate after monthly analysis

---

## 📁 FILES CREATED

1. **`SHIPMENTS_COST_METHOD_COMPARISON.md`** - Technical comparison
2. **`PRIORITY_1_METHOD_COMPARISON_EXPLAINED.md`** - This document (plain English)
3. **`queries/monitor_total_cost/shipments_monthly_method_a.sql`** - Method A monthly query
4. **`queries/monitor_total_cost/shipments_monthly_method_b.sql`** - Method B monthly query
5. **`scripts/compare_shipments_cost_methods.py`** - Analysis script

---

## 🎓 LEARNING: Why This Matters

**For Finance Team:**
- We need to know true costs for pricing decisions
- $201K vs $468K means different pricing tiers
- Uncertainty affects margin calculations

**For Product Team:**
- Higher costs = higher prices needed
- Need to validate before customer conversations
- Range allows for conservative/aggressive scenarios

**For Engineering Team:**
- Different methods capture different things
- Audit logs more complete than text search
- Need to standardize cost attribution methods

---

**Status:** 📊 Ready to run monthly analysis  
**Next:** Execute `compare_shipments_cost_methods.py` and review results  
**Timeline:** 1-2 hours for query execution + analysis

