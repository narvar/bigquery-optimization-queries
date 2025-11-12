# Phase 2 Quick Start Guide

**⚡ Get started in 5 minutes**

---

## 🎯 Goal

Run 4 BigQuery queries and analyze results to answer:
1. How often does capacity stress occur?
2. What happens to customer QoS during stress?
3. Does monitor-base cause customer stress?
4. How much capacity do we need for Nov 2025-Jan 2026 peak?

---

## 🚀 Quick Start (3 Commands)

```bash
# 1. Navigate to project directory
cd narvar/analysis_peak_2025_sonnet45

# 2. Execute all Phase 2 queries (35-60 minutes)
./scripts/run_phase2_queries.sh

# 3. Open Jupyter notebook for analysis
jupyter notebook notebooks/phase2_analysis.ipynb
```

Then in Jupyter:
- **Cell → Run All**
- Wait ~5-10 minutes for analysis
- Review visualizations and findings

Done! 🎉

---

## 📊 What Gets Created

### Query Results (BigQuery Tables)
- `narvar-data-lake.query_opt.phase2_stress_periods` - When stress occurs
- `narvar-data-lake.query_opt.phase2_external_qos` - Customer QoS impact
- `narvar-data-lake.query_opt.phase2_monitor_base` - Infrastructure causation test
- `narvar-data-lake.query_opt.phase2_peak_patterns` - Overall traffic patterns

### Visualizations (`images/`)
- `stress_state_distribution.png` - Stress frequency chart
- `stress_timeline_Peak_2024_2025.html` - Interactive timeline
- `customer_qos_by_stress_state.png` - QoS degradation
- `monitor_base_causation.png` - Causation test results

### Data Exports (`results/`)
- `stress_state_summary.csv` - Stress metrics
- `customer_qos_summary.csv` - QoS metrics
- `monitor_base_qos_summary.csv` - Infrastructure metrics
- `phase3_inputs.json` - **Key inputs for Phase 3**

---

## ⏱️ Time Estimates

| Step | Duration | Cost |
|------|----------|------|
| Query 1: Stress Detection | 15-30 min | ~$0.05-0.15 |
| Query 2: Customer QoS | 5-10 min | ~$0.02-0.08 |
| Query 3: Monitor-Base | 10-15 min | ~$0.05-0.10 |
| Query 4: Peak Patterns | 2-5 min | ~$0.01-0.03 |
| **Total Query Execution** | **35-60 min** | **~$0.13-0.36** |
| Notebook Analysis | 5-10 min | Free |
| **TOTAL** | **40-70 min** | **~$0.13-0.36** |

---

## 🔑 Key Outputs

### Stress Frequency
```
Example output:
  WARNING: 8.2% of time
  CRITICAL: 2.4% of time
  → System under stress ~11% of time
```

### Customer Impact
```
Example output:
  NORMAL: 2.3% violations
  CRITICAL: 18.7% violations
  → 8.1x degradation during stress
```

### Monitor-Base Causation
```
Example output:
  Violation ratio: 2.6x (HIGH vs LOW monitor-base)
  → HYPOTHESIS SUPPORTED: Separate reservation recommended
```

### Capacity Requirement
```
Example output:
  Capacity buffer needed: ~11%
  Peak multiplier: 1.97x (EXTERNAL)
  → Need +11% baseline, +97% during peaks
```

---

## 🆘 Troubleshooting

**Queries taking too long?**
- Expected! Query 1 takes 15-30 minutes (concurrent job calculations)

**Table not found error?**
- Run Phase 1 first: `python scripts/run_classification_all_periods.py`

**Notebook import errors?**
- Install dependencies: `pip install -r scripts/requirements.txt`

---

## 📚 Detailed Documentation

- **Full guide**: `PHASE2_EXECUTION_GUIDE.md` (comprehensive step-by-step)
- **Methodology**: `PHASE2_SCOPE.md` (analysis approach and QoS definitions)
- **Phase 1 reference**: `PHASE1_FINAL_REPORT.md` (classification details)
- **Context**: `AI_SESSION_CONTEXT.md` (quick reference)

---

## ✅ Success Checklist

- [ ] Executed all 4 queries successfully
- [ ] Result tables visible in BigQuery (`bq ls narvar-data-lake:query_opt | grep phase2`)
- [ ] Notebook runs without errors
- [ ] Visualizations generated in `images/`
- [ ] CSV exports in `results/`
- [ ] `phase3_inputs.json` created

**All checked?** Phase 2 complete! Move to Phase 3 projection. 🚀

---

**Questions?** Check the detailed guides or query comments for help.





