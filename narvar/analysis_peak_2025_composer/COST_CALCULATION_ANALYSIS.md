# BigQuery Cost Calculation Analysis

## Issue Identified

**Problem:** All queries were using on-demand pricing ($5 per TB of data scanned) when the enterprise actually has **slot-based capacity** (commitments + pay-as-you-go).

**Current Enterprise Capacity:**
- 500 slots (1-year commitment)
- 500 slots (3-year commitment)  
- 700 slots (Pay-as-you-go)
- **Total: 1,700 slots**

**Actual Cost Usage:** ~$50,000 USD per month (user reported)

---

## Slot Pricing Research

Based on BigQuery Enterprise Edition pricing and simulation configuration:

### Standard BigQuery Slot Pricing (Enterprise Edition)

**On-Demand / Pay-as-you-go:**
- $0.04 - $0.055 per slot-hour (varies by region)
- Typical: **$0.04 per slot-hour** for US region

**Commitment Pricing:**
- **1-year commitment:** ~$2,000/month per slot (effective ~$2.74/hour if used 24/7)
- **3-year commitment:** ~$1,500/month per slot (effective ~$2.05/hour if used 24/7)
- **Important:** Commitments are fixed monthly costs regardless of actual usage

### Cost Calculation Methodology

**For Analysis Queries:**
Since we cannot determine which specific jobs used committed vs. pay-as-you-go slots from audit logs, we use:

**Option 1: Marginal Cost (Recommended for analysis)**
- Use **$0.04 per slot-hour** as the baseline
- This represents the cost of additional slot usage beyond commitments
- Reflects "opportunity cost" of slot usage

**Option 2: Weighted Average (For "all slots used" scenario)**
If all 1,700 slots used 24/7 (730 hours/month = 1,241,000 slot-hours):
- 500 slots (1yr) * $2,000/month = $1,000,000/month
- 500 slots (3yr) * $1,500/month = $750,000/month
- 700 slots (paygo) * 730 hours * $0.04/hour = $20,440/month
- **Total: $1,770,440/month**
- **Cost per slot-hour: $1,770,440 / 1,241,000 = $1.426 per slot-hour**

**However**, this weighted average ($1.43/hour) is misleading because:
1. Commitments are already paid (sunk cost) regardless of usage
2. Pay-as-you-go slots only cost when actually used
3. **NOTE:** Actual total cost is ~$50,000/month (not $1.77M), indicating the simulation config pricing values are incorrect

**Recommended Approach:**
For query analysis, use **$0.04 per slot-hour** as it represents:
- The actual cost paid for slot usage (pay-as-you-go rate)
- The marginal cost of additional capacity
- A reasonable estimate for capacity planning

---

## Corrected Cost Calculation Formula

**Replace:**
```sql
ROUND(SAFE_DIVIDE(totalBilledBytes, POW(1024, 4)) * 5, 2) AS on_demand_cost
```

**With:**
```sql
ROUND(SAFE_DIVIDE(totalSlotMs, 3600000.0) * 0.04, 2) AS slot_cost_usd
```

Where:
- `totalSlotMs / 3600000.0` = slot-hours (convert milliseconds to hours)
- `* 0.04` = $0.04 per slot-hour

---

## Actual Monthly Costs

Based on reported **~$50,000 USD per month** (user reported):

**Important Finding:**
The actual total cost of $50,000/month is **much lower** than the theoretical costs calculated from simulation config values:
- Simulation config suggests: $1,750,000/month (1,000 commitment slots)
- Actual cost: **$50,000/month**

This indicates:
1. The commitment pricing in `simulation_config.sql` ($2,000/month per 1yr slot, $1,500/month per 3yr slot) is **incorrect** or not applicable
2. Actual pricing structure is significantly different
3. The actual cost per slot is approximately: $50,000 / 1,700 slots = **~$29.41 per slot per month**

**Cost Breakdown (estimated based on actual $50k/month):**
- Actual total: **$50,000/month**
- Cannot accurately separate fixed vs. variable without knowing:
  - Actual commitment pricing
  - Actual slot-hour consumption
  - Which slots are commitments vs. pay-as-you-go

**For Cost Calculations in Queries:**
Since actual pricing structure is unknown, we continue to use:
- **$0.04 per slot-hour** for individual job costs (standard pay-as-you-go rate)
- Note: This is an estimate for analysis purposes; actual allocation between fixed/variable costs requires actual billing data

---

## Median Cost Per Slot-Hour

**Important Correction:**
The "median cost" calculation using simulation config values ($1.426/hour) is **incorrect** because:
- Simulation config pricing values ($2k/month per 1yr slot, $1.5k/month per 3yr slot) do not match actual costs
- Actual total monthly cost is **~$50,000 USD**, not $1.77M
- Actual cost per slot (if distributed equally): ~$50,000 / 1,700 slots = **~$29.41 per slot per month**

**For Analysis Purposes:**
- Use **$0.04 per slot-hour** for individual query/job costs (standard pay-as-you-go rate)
- This provides consistent cost estimates for comparing job costs
- Actual total monthly cost: **~$50,000 USD** (user reported)
- Cannot calculate accurate "median cost per slot-hour" without:
  - Actual billing data showing fixed vs. variable costs
  - Actual slot-hour consumption per month
  - Actual pricing structure for commitments

---

## Parent/Child Query Identification

### Current Implementation

All queries correctly filter out script child jobs:
```sql
AND jobId NOT LIKE 'script_job_%'
```

### Script Job Pattern Analysis

From audit log examination:
- **Parent script jobs:** `script_job_{hash}` (e.g., `script_job_c0a92f5cbf50bc38005178b6bec1b7fe`)
- **Child script jobs:** `script_job_{hash}_{number}` (e.g., `script_job_c0a92f5cbf50bc38005178b6bec1b7fe_71`)

**Current filter (`script_job_%`) excludes:**
- ✅ All child jobs (have underscore + number suffix)
- ❌ Does NOT exclude parent script jobs (these are the actual queries submitted)

### Recommendations

**Option 1: Keep current filter** (excludes children only)
- Parent script jobs represent actual user-submitted queries
- This is likely the correct behavior

**Option 2: Also exclude script parent jobs**
```sql
AND NOT (jobId LIKE 'script_job_%' AND jobId NOT LIKE 'script_job_%_%')
```
- This would exclude both parent and child script jobs
- Only useful if you want to analyze only non-script queries

**Current approach (exclude children only) is correct** because:
- Script parent jobs are real queries that users submitted
- Child jobs are internal splits that would double-count

### Other Parent/Child Patterns

**BigQuery Internal Query Splits:**
- BigQuery can internally split large queries into parallel execution units
- These typically appear with the same `jobId` but multiple log entries
- **Already handled** by `ROW_NUMBER() OVER (PARTITION BY jobId)` deduplication

**No other explicit parent/child indicators found** in audit log schema:
- No `parentJobId` fields
- No explicit parent/child relationship indicators
- Current deduplication + script filter approach is sufficient

---

## Action Items

1. ✅ **Replace all $5/TB calculations** with slot-hour based calculations ($0.04/hour)
2. ✅ **Update all markdown files** with corrected cost figures
3. ✅ **Add cost calculation notes** explaining slot vs. on-demand pricing
4. ✅ **Verify parent/child filtering** is correct (current approach is appropriate)
5. ⚠️ **Clarify with user** actual slot pricing if simulation config values are incorrect

