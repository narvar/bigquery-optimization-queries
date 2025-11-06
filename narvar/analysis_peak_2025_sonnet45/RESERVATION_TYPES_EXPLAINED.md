# Three Reservation Types - Complete Explanation

**Date**: November 6, 2025  
**Source**: DoIT CMP BigQuery billing data + GCP Console

---

## ✅ ANSWER TO QUESTION 1: Where Are These Managed?

### 1. RESERVED_SHARED_POOL (`bq-narvar-admin:US.default`)

**Managed:** GCP Console → BigQuery → Capacity Management (as shown in screenshot)

**Configuration (from screenshot):**
- **Edition:** Enterprise
- **Max Slots:** 1,700
- **Baseline Slots:** 1,000
- **Committed Slots:** 1,000
- **Commitment:** 100% of baseline
- **Concurrency:** AUTO
- **Additional:** Autoscale + idle slots

**Cost Structure (from DoIT capacity_commitments_history):**
```
Tier 1: 500 slots @ $0.048/hr = $24.00/hr
Tier 2: 500 slots @ $0.036/hr = $18.00/hr  
(Missing: 700 slots @ $0.06/hr from calculation)
Total visible: 1,000 committed + 700 autoscale = 1,700 max
```

**Actual Costs (Baseline_2025_Sep_Oct from DoIT):**
- Jobs: 2,212,941
- Cost: **$57,352**
- Avg cost/job: $0.026

---

### 2. RESERVED_PIPELINE (`default-pipeline`)

**Managed:** ❓ **NOT visible in GCP Console Capacity Management**

**Configuration:** Unknown - Need to investigate:
```bash
# Check in GCP Console:
# BigQuery → Admin → Reservations → Look for "default-pipeline"
# OR
# May be managed via Terraform/API, not UI
```

**From DoIT Data:**
- **Exists in costs table:** Yes ✅
- **Exists in capacity_commitments:** No ❌
- **Jobs:** 1,386,716 (Baseline_2025)
- **Cost:** **$898** (very low!)
- **Avg cost/job:** $0.0006 (almost free!)

**Hypothesis:**
- Legacy reservation OR
- Auto-created by BigQuery for specific workload types OR
- Managed outside normal reservation UI

**⚠️ ACTION REQUIRED:** Check GCP Console or ask GCP admin where this is configured

---

### 3. ON_DEMAND (`unreserved`)

**Managed:** No reservation - pay-per-query billing

**Pricing Model:**
- **NOT slot-based** - billed by data processed
- **Rate:** $6.25 per TB processed (US multi-region)
- No pre-commitment, no slot limits

**Actual Costs (Baseline_2025_Sep_Oct from DoIT):**
- Jobs: 848,681
- Cost: **$245,386** ✅ CONFIRMED
- Avg cost/job: $0.289

---

## ✅ ANSWER TO QUESTION 2: Adding Billed TB to Analysis

Let me create enhanced query with TB processed:

<function_calls>
<invoke name="run_terminal_cmd">
<parameter name="command">bq query --use_legacy_sql=false --format=csv "
SELECT
  CASE
    WHEN reservation_name = 'bq-narvar-admin:US.default' THEN 'RESERVED_SHARED_POOL'
    WHEN reservation_name = 'default-pipeline' THEN 'RESERVED_PIPELINE'
    WHEN reservation_name = 'unreserved' THEN 'ON_DEMAND'
  END as reservation_type,
  consumer_category,
  
  COUNT(*) as total_jobs,
  ROUND(SUM(slot_hours), 0) as total_slot_hours,
  ROUND(SUM(slot_hours) / SUM(SUM(slot_hours)) OVER() * 100, 2) as pct_of_total_slots,
  
  -- Billed data volume
  ROUND(SUM(total_billed_gb) / 1024, 2) as total_billed_tb,
  ROUND(AVG(total_billed_gb), 2) as avg_billed_gb_per_job,
  
  -- QoS
  ROUND(COUNTIF(is_qos_violation) / NULLIF(COUNTIF(is_qos_violation IS NOT NULL), 0) * 100, 2) as qos_violation_pct,
  
  -- Cost (internal allocation)
  ROUND(SUM(estimated_slot_cost_usd), 0) as internal_cost_allocation
  
FROM \`narvar-data-lake.query_opt.traffic_classification\`
WHERE analysis_period_label = 'Baseline_2025_Sep_Oct'
  AND reservation_name IN ('bq-narvar-admin:US.default', 'default-pipeline', 'unreserved')
GROUP BY reservation_type, consumer_category
ORDER BY total_slot_hours DESC
" > /tmp/reservation_with_tb.csv && cat /tmp/reservation_with_tb.csv
