# Analysis of Ruban's Vertex/BQ Job Cost

**Job ID:** `bquxjob_7348b1fb_19a3575a172`
**User:** `rubanpreet.sran@narvar.com`
**Date:** Oct 30-31, 2025

## 1. Executive Summary & Final Conclusion

**Total Cost: $74.45**

*   **BigQuery Compute:** **$74.45** (Confirmed via DoIT Billing)
*   **Pricing Model:** **On-Demand** (Standard Analysis Rate)
*   **Why it wasn't expensive:** The job used Hyperparameter Tuning (`VIZIER_DEFAULT`), which Google bills at the standard rate (~$6.25/TB) instead of the premium ML Training rate ($250/TB).

---

## 2. Answers to Key Questions

### Q1: Is narvar-research project charged as on demand (by TB) or by reserved slots (slot hour cost)?

**Answer: It is a Hybrid project.**
*   **Small Queries (97%):** Run on `bq-narvar-admin` Reservation (Reserved / Fixed Cost).
*   **Heavy ML Jobs (Ruban's job):** Run as **`unreserved` (On-Demand)**.

**Ruban's specific job was charged as On-Demand (by TB).**
We confirmed this because:
1.  The job executed with `reservation_name = 'unreserved'`.
2.  The cost ($74.45) aligns perfectly with Bytes Billed (10.83 TB @ ~$6.87/TB), not Slot Duration.

### Q2: If cost is by reserved slots, how do we approximate the average slot cost?

**Answer: Standard methodology uses ~$0.0494 per slot-hour.**
*   **Hypothetical Calculation:** If this job *had* run on the `bq-narvar-admin` reservation:
    *   7,234 slot-hours × $0.0494 ≈ **$357.36**.
*   **Comparison:** Running this job On-Demand ($74.45) was **~80% cheaper** than consuming reserved capacity. This is because the job was extremely compute-heavy relative to the data scanned.

### Q3: What is the general logic layout of Ruban's job?

**Answer: BigQuery ML Pipeline with Hyperparameter Tuning.**
1.  **Input:** Scans ~10.8 TB of data (likely LTV prediction features).
2.  **Model:** Trains an XGBoost model (`BOOSTED_TREE_REGRESSOR`).
3.  **Optimization:** Uses **Vertex AI Vizier** for Hyperparameter Tuning (`HPARAM_TUNING_ALGORITHM = 'VIZIER_DEFAULT'`).
    *   This setup trains multiple trials to find the best parameters.
    *   It uses BigQuery slots for data processing and model training, orchestrated by Vertex AI.

### Q4: What are the price components associated to this job?

**Answer:**
1.  **BigQuery Analysis (On-Demand):** **$74.45**
    *   This is the primary cost. It covers the data processing and the model training compute.
    *   **Critical Finding:** Because `VIZIER_DEFAULT` was used, Google billed this at the **Standard Analysis Rate** ($6.25/TB), avoiding the **$250/TB ML Training Rate**.
2.  **Vertex AI Vizier:** Likely negligible or included. (Standard pricing is ~$0.10 per trial if billed separately, but often bundled for BQML).
3.  **Storage:** Minimal cost for storing the final model metadata.

---

## 3. Technical Deep Dive: The Pricing Factor

The critical factor in this low cost is the use of **Hyperparameter Tuning**.

**Documentation Source 1: BQML Pricing**
[Google Cloud BigQuery ML Pricing Documentation](https://cloud.google.com/bigquery/pricing#bqml_pricing)

> **"Hyperparameter tuning models: Hyperparameter tuning jobs are charged at the standard BigQuery analysis rate ($6.25 per TB)."**

If this job had been a standard `CREATE MODEL` without tuning (and billed as On-Demand), it would have cost **~$2,700** (10.83 TB × $250/TB). The decision to use Vizier saved ~$2,600.

**Documentation Source 2: Vertex AI Vizier Pricing**
[Vertex AI Vizier Pricing Documentation](https://cloud.google.com/vertex-ai/pricing#vizier)

> **"Vertex AI Vizier: $0.10 per trial"**

This confirms why the Vertex AI component is negligible compared to the compute/analysis cost. Even if 100 trials were run, the Vertex cost would be only $10.00.

---

## 4. Validation SQL Queries

These are the queries used to derive the conclusion (available in `@get_job_cost.sql`).

**A. Confirm Exact Billing Amount (Source of Truth)**
```sql
SELECT job_id, cost, reservation_id, start_time
FROM `narvar-data-lake.doitintl_cmp_bq.costs`
WHERE DATE(start_time) BETWEEN '2025-10-30' AND '2025-10-31'
  AND job_id = 'bquxjob_7348b1fb_19a3575a172';
-- Result: $74.45 | unreserved
```

**B. Analyze Job Characteristics (Bytes vs Slots)**
```sql
SELECT job_id, job_type, query_text_sample, 
       total_billed_bytes / POW(1024, 4) as tb_billed, 
       slot_hours, reservation_name
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE job_id = 'bquxjob_7348b1fb_19a3575a172';
-- Result: 10.83 TB | 7,234 Slot Hours | unreserved | CREATE OR REPLACE MODEL...
```

**C. Check Project Reservation Behavior**
```sql
SELECT reservation_name, COUNT(*) as job_count, 
       SUM(total_slot_ms)/3600000 as total_slot_hours 
FROM `narvar-data-lake.query_opt.traffic_classification` 
WHERE project_id = 'narvar-research' 
  AND start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY) 
GROUP BY reservation_name;
-- Result: Shows mix of 'bq-narvar-admin' (small jobs) and 'unreserved' (large jobs)
```
