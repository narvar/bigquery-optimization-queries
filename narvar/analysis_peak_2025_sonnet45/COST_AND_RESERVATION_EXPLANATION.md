# Cost Calculation & Reservation Type - Detailed Explanation

**Date**: November 6, 2025  
**Analysis Period**: Baseline_2025_Sep_Oct

---

## 1. Cost Derivation (`total_cost_usd`)

### Formula

```
estimated_slot_cost_usd = (total_slot_ms / 3,600,000) * $0.0494
```

Where:
- `total_slot_ms` = Total slot milliseconds consumed by job
- `3,600,000` = Milliseconds in 1 hour (converts to slot hours)
- `$0.0494` = **Blended hourly slot rate**

### Blended Rate Calculation

**Narvar's Reservation Mix:**
```
Reservation Tier       | Slots | Rate/Hour | Cost/Hour
-----------------------|-------|-----------|----------
Tier 1 (commitment)    |   500 | $0.048    | $24.00
Tier 2 (commitment)    |   500 | $0.036    | $18.00
Tier 3 (flex/baseline) |   700 | $0.060    | $42.00
-----------------------|-------|-----------|----------
TOTAL                  | 1,700 |           | $84.00
```

**Blended Rate:**
```
$84.00 / 1,700 slots = $0.0494 per slot-hour
```

### Example Calculation

**Project:** `monitor-26a614b-us-prod` (511tactical)

**Raw Data:**
- Total slot milliseconds: 62,576,658,000 ms
- Total jobs: 707

**Calculation:**
```
Slot hours = 62,576,658,000 / 3,600,000 = 17,382.85 hours
Cost = 17,382.85 * $0.0494 = $858.72
```

### Important Notes

**⚠️ This is RESERVED SLOT cost, not actual billing:**
- Represents resource consumption **within existing reservation**
- **NOT** what you pay BigQuery (reservation is pre-paid)
- Useful for:
  - Internal cost allocation
  - Understanding relative consumption
  - Capacity planning (which projects use most slots)

**Actual BigQuery Billing:**
- Narvar pays for 1,700 committed slots regardless of usage
- On-demand queries (reservation_name='unreserved') billed separately
- This cost model assumes all usage is within reservation

---

## 2. Reservation Type (`slot_type`)

### Field: `reservation_name` in Audit Logs

BigQuery audit logs include `reservation_name` field indicating which reservation (or none) was used.

### Values Found

**In Baseline_2025_Sep_Oct monitor projects:**

| Reservation Name | Slot Type | Projects | Jobs | Slot Hours | % of Total |
|------------------|-----------|----------|------|------------|------------|
| `bq-narvar-admin:US.default` | **RESERVED** | 409 | 200,342 | 35,563 | 97.8% |
| `unreserved` | **ON_DEMAND** | 15 | 5,802 | 801 | 2.2% |

### Reserved Slots (bq-narvar-admin:US.default)

**What it means:**
- Jobs executed using Narvar's 1,700-slot reservation
- **No additional per-query charges** (reservation already paid)
- Subject to reservation limits (1,700 max concurrent slots)
- Most projects use this (97.8% of monitor consumption)

**Examples:**
- fashionnova: 11,768 slot hours (RESERVED)
- 511tactical: 17,383 slot hours (RESERVED)
- nike: 80 slot hours (RESERVED)

### On-Demand Slots (unreserved)

**What it means:**
- Jobs executed **outside** the reservation
- **Billed separately** (on-demand pricing: $6.25/TB in US)
- No slot limits (can burst beyond 1,700 slots)
- Only 15 projects use this (2.2% of monitor consumption)

**Examples:**
- **sephora** (monitor-1e15a40-us-prod): 340 slot hours ON-DEMAND
- **lululemon** (monitor-273c022-us-prod): 57 slot hours ON-DEMAND
- **uniqlo** (monitor-eaf244f-us-prod): 108 slot hours ON-DEMAND

**⚠️ Important:** On-demand usage suggests:
- Project exceeded reservation capacity
- Project configured to use on-demand explicitly
- Potential optimization opportunity (move to reserved if possible)

---

## 3. Why Some Projects Use On-Demand

### Possible Reasons:

**1. Capacity Overflow:**
- All 1,700 reserved slots in use
- Project "spills over" to on-demand
- Happens during peak load

**2. Explicit Configuration:**
- Project settings force on-demand usage
- May be intentional for specific use cases

**3. Geographic/Workload Isolation:**
- Some projects may be configured separately
- Testing or special requirements

### Investigation Needed:

**For Sephora (340 slot hours on-demand):**
- Why is a major retailer using on-demand?
- Is this cost-effective?
- Should they be moved to reserved?

**Cost Comparison:**
```
Reserved: 340 slot hours * $0.0494 = $16.80 (internal allocation)
On-Demand: ~$200-500 actual billing (depends on data processed)

Potential savings: Move to reserved if capacity available
```

---

## 4. Updated Query Output

### New Fields Added:

| Field | Description |
|-------|-------------|
| `slot_type` | RESERVED or ON_DEMAND |
| `first_job_date` | Earliest job date in period |
| `last_job_date` | Latest job date in period |
| `days_span` | Total days between first and last job |

### Cost Field Explanation:

| Field | Formula | Description |
|-------|---------|-------------|
| `total_cost_usd` | `(slot_ms / 3.6M) * $0.0494` | Internal slot consumption cost (reserved rate) |

**Note:** For ON_DEMAND projects, this shows what the cost **would be** if using reserved slots, not actual on-demand billing.

---

## 5. Key Insights for Investigation 2 (Monitor Segmentation)

**This data enables Investigation 2:**

We can now segment monitor projects by:
- **slot_type** = RESERVED vs ON_DEMAND
- Hypothesis: On-demand projects may have different performance characteristics

**Questions to Answer:**
1. Do on-demand projects have better/worse QoS?
2. Are on-demand projects using more/fewer slots per job?
3. Should Narvar consider separate on-demand strategy?

**Next Steps:**
- Investigation 2 will analyze RESERVED vs ON_DEMAND performance
- Compare slot consumption, QoS, execution patterns
- Recommendation for Nov 2025-Jan 2026 peak planning

---

**Updated SQL Query:** `queries/google_sheets/baseline_2025_monitor_projects_detailed.sql`  
**Includes:** Time period, slot type, cost explanation

