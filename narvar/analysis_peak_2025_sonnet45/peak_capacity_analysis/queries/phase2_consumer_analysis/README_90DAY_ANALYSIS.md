# 90-Day Cost Attribution Analysis

**Date:** November 25, 2025  
**Purpose:** Consistent time-period analysis for accurate retailer cost attribution  
**Query:** `combined_cost_attribution_90days.sql`

---

## 🎯 Key Changes from Original Analysis

### ❌ Problem with Original Query (`combined_cost_attribution.sql`)

The original query had **inconsistent time periods**:

| Data Source | Time Period | Issue |
|------------|-------------|-------|
| **Shipments** | All-time (no date filter) | ⚠️ Includes historical data |
| **Orders** | Jan 1, 2024 onwards (12 months) | ⚠️ Different window |
| **Returns** | Last 90 days | ✓ Short window |
| **Consumption** | Peak_2024_2025 (Nov 2024-Jan 2025, 3 months) | ⚠️ Different window |

**Result:** Costs were **not comparable** across retailers because each table covered different time periods.

---

## ✅ Solution: 90-Day Consistent Window

All data sources now use the **same 90-day lookback window**:

```sql
WHERE DATE(timestamp_column) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
```

### Pro-Rated Costs

Annual costs are **pro-rated for 90 days**:

| Table | Annual Cost | 90-Day Cost | Calculation |
|-------|-------------|-------------|-------------|
| **Shipments** | $176,556 | **$43,449** | $176,556 × (90/365) |
| **Orders** | $45,302 | **$11,157** | $45,302 × (90/365) |
| **Returns** | $11,871 | **$2,923** | $11,871 × (90/365) |
| **Total Production** | $233,729 | **$57,529** | Sum of 90-day costs |

---

## 📊 New Output Columns

The updated query includes:

### Production Metrics (by retailer)
- `shipment_count` - Shipments in last 90 days
- `order_count` - Orders in last 90 days
- `return_count` - Returns in last 90 days
- `shipments_production_cost_usd` - Pro-rated cost
- `orders_production_cost_usd` - Pro-rated cost
- `returns_production_cost_usd` - Pro-rated cost
- `total_production_cost_usd` - Sum of all production costs

### Consumption Metrics (by retailer)
- `consumption_cost_usd` - Query costs (last 90 days)
- `consumption_slot_hours` - Slot-hours consumed
- `query_count` - **NEW:** Total queries in period
- `first_query_date` - **NEW:** First query in 90-day window
- `last_query_date` - **NEW:** Last query in 90-day window
- `query_days_active` - **NEW:** Days with query activity
- `avg_queries_per_day` - **NEW:** Queries ÷ active days

### Combined Metrics
- `total_cost_usd` - Production + Consumption
- `consumption_to_production_ratio` - Consumption ÷ Production
- `consumption_pct_of_total` - Consumption ÷ Total Cost

---

## ⚠️ Important Notes

### 1. Shipments Table Timestamp Column
The query uses `created_at` as the timestamp column. **You must verify this is correct:**

```sql
-- Check the schema:
SELECT column_name, data_type 
FROM `monitor-base-us-prod.monitor_base.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'shipments'
  AND column_name LIKE '%time%' OR column_name LIKE '%date%';
```

Possible column names:
- `created_at`
- `updated_at`
- `ingestion_timestamp`
- `event_timestamp`

**Update line 18** of the query if needed.

### 2. Consumption Data Availability
The `traffic_classification` table may not have 90 days of data for all periods. Check coverage:

```sql
SELECT 
  analysis_period_label,
  MIN(DATE(start_time)) as start_date,
  MAX(DATE(start_time)) as end_date,
  DATE_DIFF(MAX(DATE(start_time)), MIN(DATE(start_time)), DAY) + 1 as days_covered
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE consumer_subcategory = 'MONITOR'
GROUP BY analysis_period_label
ORDER BY start_date DESC;
```

### 3. Cost Interpretation
These are **pro-rated costs for the 90-day window only**. To annualize:

```
Annual Cost = 90-day cost × (365/90) = 90-day cost × 4.056
```

---

## 🚀 How to Run

### Step 1: Verify shipments timestamp column
```sql
-- Run this first to check the column name:
SELECT * FROM `monitor-base-us-prod.monitor_base.shipments` LIMIT 1;
```

### Step 2: Run dry-run to check costs
```bash
bq query --dry_run --use_legacy_sql=false < combined_cost_attribution_90days.sql
```

**Expected bytes processed:** ~5-20 GB (much less than all-time query)

### Step 3: Execute and save results
```bash
bq query \
  --use_legacy_sql=false \
  --format=csv \
  --max_rows=100 \
  < combined_cost_attribution_90days.sql \
  > ../results/combined_cost_attribution_90days.csv
```

### Step 4: Generate updated histogram
```bash
cd ../../scripts
python3 generate_cost_histogram_90days.py
```

---

## 📈 Expected Impact on Results

### Distribution will be MORE concentrated
- Fewer retailers will show up (only those active in last 90 days)
- Cost per retailer will be **4x lower** (90 days vs annual)
- Consumption ratio will be **more accurate** (matching time periods)

### Zombie data retailers
Retailers with **zero consumption** in the 90-day window may still have production costs if they're still ingesting data but not querying it.

---

## 🔄 Next Steps

1. ✅ Verify shipments timestamp column (REQUIRED before running)
2. ✅ Run query with `--dry_run` to check costs
3. ✅ Execute query and save to CSV
4. ✅ Generate new histogram from 90-day data
5. ✅ Update MONITOR_COST_EXECUTIVE_SUMMARY.md with corrected:
   - Distribution counts
   - Nike classification
   - Time period notes
   - Queries per day metrics

---

## 📞 Questions?

If the shipments table doesn't have a suitable timestamp column for 90-day filtering, we have two options:

**Option A:** Use partition column if available (fastest)
**Option B:** Remove date filter for shipments and adjust cost interpretation accordingly

Contact the data team to confirm the shipments table schema.


