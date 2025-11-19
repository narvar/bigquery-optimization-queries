# BigQuery Peak Capacity Planning & QoS Analysis

**Purpose:** Capacity planning for Nov 2025 - Jan 2026 peak period  
**Status:** Phase 1 complete, Hub QoS investigation complete  
**Separate from:** Monitor platform pricing/cost optimization

---

## 📍 Overview

This directory contains analysis for BigQuery capacity planning during peak retail periods (Black Friday, Cyber Monday, Holiday season). This is a **separate workstream** from the Monitor platform pricing analysis.

**Key findings:**
- 43.8M jobs classified across 9 time periods
- Hub (Looker) has critical QoS issues: 39.4% violation rate
- Root cause: 69% automated, 23% internal, 8% external incidents
- Strategic decision: Monitoring-based approach (not pre-loading capacity)

---

## 📁 Directory Guide

### **phase1/**
- `PHASE1_FINAL_REPORT.md` - Complete Phase 1 analysis
- **Status:** ✅ Complete

### **hub_qos/**
**What's here:** Hub (Looker dashboards) QoS investigation

- `INV6_HUB_QOS_RESULTS.md` - Hub QoS analysis results
- `HUB_ANALYTICS_API_2025_REPORT.md` - Hub Analytics API analysis
- `LOOKER_VS_HUB_ANALYTICS_COMPARISON.md` - Looker vs Hub comparison
- `LOOKER_2025_ANALYSIS_REPORT.md` - Looker analysis

**Key finding:** Hub has 39.4% QoS violations vs 8.5% for Monitor (44x slower P95 execution time)

### **monitor/**
- `MONITOR_2025_ANALYSIS_REPORT.md` - Monitor retailer performance analysis

### **root_cause/**
- `ROOT_CAUSE_ANALYSIS_FINDINGS.md` - Root cause breakdown

### **Support Directories:**
- `queries/` - SQL queries for capacity analysis (47 files)
- `results/` - Query results and analysis outputs (36 files)
- `scripts/` - Python scripts for analysis (24 files)
- `notebooks/` - Jupyter notebooks for visualization
- `images/` - Charts and diagrams
- `logs/` - Execution logs

---

### **Root File:**
- `PEAK_2025_2026_STRATEGY_EXEC_REPORT.md` - Executive strategy report

---

## 🎯 Key Findings (Summary)

**Traffic Classification:** 43.8M jobs across 9 periods (Peak vs Non-Peak, 2023-2025)

**QoS Issues:**
- Hub (Looker): 39.4% violation rate during critical stress
- Monitor: 8.5% violation rate (much better)
- Hub P95 execution: 1,521 seconds (25 minutes) vs Monitor: 34 seconds

**Strategic Decision:** Monitoring-based capacity management approach

---

## 🔗 Related Work

**Monitor Platform Analysis:** See [../DELIVERABLES/](../DELIVERABLES/) and [../monitor_cost_analysis/](../monitor_cost_analysis/)

**Note:** While both analyses use similar data sources (traffic_classification), they address different questions:
- Peak capacity: How much BigQuery capacity do we need?
- Monitor pricing: What does Monitor platform cost and how should we price it?

---

**Last Updated:** November 19, 2025

