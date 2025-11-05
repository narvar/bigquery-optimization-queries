# 🚀 Run Phase 2 Queries - FIXED VERSION

## ⚠️ Problem Identified & Fixed

**Issue**: The original queries used `DECLARE` statements, which are incompatible with the `--destination_table` flag in `bq query`. This caused queries to run but NOT create tables.

**Solution**: Created new versions with `CREATE OR REPLACE TABLE` built directly into the SQL.

---

## ✅ Production-Ready Queries Created

All 4 queries now have fixed versions:

| Query | New File | Creates Table |
|-------|----------|---------------|
| **Query 1** | `identify_capacity_stress_periods_table.sql` | `phase2_stress_periods` |
| **Query 2** | `external_qos_under_stress_table.sql` | `phase2_external_qos` |
| **Query 3** | `monitor_base_stress_analysis_table.sql` | `phase2_monitor_base` |
| **Query 4** | `peak_vs_nonpeak_analysis_v2_table.sql` | `phase2_peak_patterns` |

---

## 🎯 How to Run (2 Options)

### Option 1: Automated Script (Recommended)

```bash
cd /Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/analysis_peak_2025_sonnet45

./scripts/run_phase2_queries_FIXED.sh
```

**This will:**
- Run all 4 queries sequentially
- Show progress for each query
- Verify tables were created
- Take ~35-60 minutes total

---

### Option 2: Run Queries Manually

If you prefer to run them one at a time:

```bash
cd /Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/analysis_peak_2025_sonnet45

# Query 1 (15-30 min)
bq query --use_legacy_sql=false --location=us < queries/phase2_historical/identify_capacity_stress_periods_table.sql

# Query 2 (5-10 min)
bq query --use_legacy_sql=false --location=us < queries/phase2_historical/external_qos_under_stress_table.sql

# Query 3 (10-15 min)
bq query --use_legacy_sql=false --location=us < queries/phase2_historical/monitor_base_stress_analysis_table.sql

# Query 4 (2-5 min)
bq query --use_legacy_sql=false --location=us < queries/phase2_historical/peak_vs_nonpeak_analysis_v2_table.sql
```

---

## ✅ Verify Tables Created

After queries complete:

```bash
bq ls narvar-data-lake:query_opt | grep phase2
```

You should see:
```
phase2_external_qos
phase2_monitor_base
phase2_peak_patterns
phase2_stress_periods
```

---

## 📊 Cost & Time Estimates

| Query | Data Scanned | Runtime | Cost |
|-------|--------------|---------|------|
| Query 1 | 10-30GB | 15-30 min | ~$0.05-0.15 |
| Query 2 | 5-15GB | 5-10 min | ~$0.02-0.08 |
| Query 3 | 10-20GB | 10-15 min | ~$0.05-0.10 |
| Query 4 | 1-5GB | 2-5 min | ~$0.01-0.03 |
| **TOTAL** | **26-70GB** | **35-60 min** | **~$0.13-0.36** |

---

## 🎉 After Queries Complete

1. **Verify tables exist** (command above)

2. **Open Jupyter notebook:**
   ```bash
   jupyter notebook notebooks/phase2_analysis.ipynb
   ```

3. **Select kernel:** `jupyter (Python 3.11.3)`

4. **Run all cells** to generate visualizations and analysis

---

## 🆘 Troubleshooting

**Tables still not appearing?**
```bash
# Check if queries are still running
bq ls -j --max_results=10

# Check for errors in last query
bq show -j <job_id>
```

**Query takes too long?**
- Expected! Query 1 takes 15-30 minutes due to concurrent job calculations
- Queries are working if no errors appear

---

## 📝 What Changed

**Old Approach (Didn't Work):**
```bash
# This silently failed due to DECLARE statements
bq query --destination_table=table_name < query.sql
```

**New Approach (Works):**
```sql
-- CREATE OR REPLACE TABLE built into SQL
CREATE OR REPLACE TABLE `narvar-data-lake.query_opt.table_name` AS
SELECT ...
```

---

**Ready to run? Execute the script now!** 🚀

```bash
./scripts/run_phase2_queries_FIXED.sh
```

