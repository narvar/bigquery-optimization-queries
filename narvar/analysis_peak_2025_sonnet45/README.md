# BigQuery Peak 2025 Analysis - Monitor Platform

**Project:** Monitor Platform Cost Analysis & Optimization  
**Date:** November 2025  
**Status:** Phase 1 (Retailer Profiling) - In Progress

---

## 📍 Start Here

**New to this project?** Read in this order:

1. **[DELIVERABLES/MONITOR_COST_EXECUTIVE_SUMMARY.md](DELIVERABLES/MONITOR_COST_EXECUTIVE_SUMMARY.md)** - Complete cost analysis ($263K/year) and optimization roadmap
2. **[DELIVERABLES/MONITOR_PRICING_STRATEGY.md](DELIVERABLES/MONITOR_PRICING_STRATEGY.md)** - Pricing options and financial scenarios
3. **[LETTER_TO_TOMORROW.md](LETTER_TO_TOMORROW.md)** - Context for AI sessions (communication guidelines, project history)

**Looking for specific information?** See directory guide below.

---

## 📁 Directory Guide

### **DELIVERABLES/** ⭐ **PRODUCT TEAM DELIVERABLES**
**What's here:** Final reports and recommendations for Product Management

- `MONITOR_COST_EXECUTIVE_SUMMARY.md` - Complete cost analysis + optimization opportunities
- `MONITOR_PRICING_STRATEGY.md` - Pricing strategy options
- Future: Cost optimization results, retailer profiling results, questions for Product

**Who needs this:** Product Management, Finance, Executive Leadership

---

### **cost_optimization/** ⭐ **CURRENT WORK - PHASE 1**
**What's here:** Cost optimization analysis and retailer profiling work

**Subdirectories:**
- `architecture/` - Streaming vs batch comparison, architecture docs
- `retailer_profiling/` - **ACTIVE WORK**
  - `fashionnova/` - High-priority case study (74% of platform compute)
  - `all_retailers/` - Full retailer segmentation
- `latency_optimization/` - Phase 3 work (conditional)
- `retention_optimization/` - Phase 2 work (conditional)

**Who needs this:** Data Engineering (active analysis)

---

### **monitor_cost_analysis/**
**What's here:** Supporting cost analysis data and methodology

**Subdirectories:**
- `methodology/` - How costs were calculated (Method A approach)
- `tables/` - Individual table cost analyses (7 tables)
- `infrastructure/` - Pub/Sub, Composer/Airflow cost attribution
- `billing_data/` - DoIT billing CSVs (24 months)
- `queries/` - SQL queries used for analysis
- `results/` - Query result files
- `archive_old/` - Superseded cost documents

**Key Files:**
- `MONITOR_PLATFORM_COMPLETE_COST_ANALYSIS.md` - Comprehensive technical report
- `MONITOR_COST_SUMMARY_TABLE.md` - Quick reference tables

**Who needs this:** Data Engineering (reference material)

---

### **peak_capacity_analysis/**
**What's here:** BigQuery capacity planning for peak periods (separate from Monitor pricing)

**Subdirectories:**
- `phase1/` - Phase 1 analysis reports
- `hub_qos/` - Hub (Looker) QoS investigation results
- `monitor/` - Monitor retailer performance analysis
- `root_cause/` - Root cause analysis findings
- `queries/`, `results/`, `scripts/`, `notebooks/`, `images/`, `logs/`

**Who needs this:** Capacity Planning, SRE, Data Engineering

**Note:** This is a different workstream from Monitor pricing/cost optimization

---

### **session_logs/**
**What's here:** Historical session summaries, Slack updates, daily accomplishments

**Organization:** By date (2025-11-14, 2025-11-17, etc.)

**Who needs this:** AI continuity, project historians

**Note:** Not needed by Product team - contextual information only

---

### **archive/**
**What's here:** Superseded planning documents, abandoned workstreams, historical files

**Who needs this:** Reference only - these documents are no longer current

---

### **docs/**
**What's here:** Supporting documentation (classification strategy, implementation status, reference materials)

**Subdirectories:**
- `monitor_total_cost/` - Detailed pricing analysis, scaling framework
- `phase2/` - Phase 2 historical analysis docs
- `reference/` - Reference materials
- `archive/` - Superseded docs

---

## 🎯 Current Project Status

**Completed:**
- ✅ Complete cost analysis: $263,084/year (all 7 tables + infrastructure validated)
- ✅ Partition pruning validation (MERGE operations scan ~10% of table)
- ✅ Cost optimization roadmap created ($34K-$75K potential savings)
- ✅ Architecture comparison documented (streaming vs batch)

**In Progress:**
- 🔄 **Phase 1: Retailer Usage Profiling** (2-4 weeks)
  - fashionnova query pattern analysis (HIGH PRIORITY)
  - All retailers segmentation
  - Latency and retention requirements profiling

**Next:**
- 📋 Phase 2: Pricing tier assignments (after profiling)
- 📋 Phase 3: Product team decision workshop
- 📋 Phase 4: Implementation (conditional)

---

## 🚀 Quick Links

**I want to understand...**
- **...the total cost:** [DELIVERABLES/MONITOR_COST_EXECUTIVE_SUMMARY.md](DELIVERABLES/MONITOR_COST_EXECUTIVE_SUMMARY.md)
- **...pricing options:** [DELIVERABLES/MONITOR_PRICING_STRATEGY.md](DELIVERABLES/MONITOR_PRICING_STRATEGY.md)
- **...cost optimization:** [cost_optimization/architecture/STREAMING_VS_BATCH_ARCHITECTURE_COMPARISON.md](cost_optimization/architecture/STREAMING_VS_BATCH_ARCHITECTURE_COMPARISON.md)
- **...a specific table cost:** [monitor_cost_analysis/tables/](monitor_cost_analysis/tables/)
- **...how costs were calculated:** [monitor_cost_analysis/methodology/CORRECT_COST_CALCULATION_METHODOLOGY.md](monitor_cost_analysis/methodology/CORRECT_COST_CALCULATION_METHODOLOGY.md)
- **...fashionnova analysis:** [cost_optimization/retailer_profiling/fashionnova/](cost_optimization/retailer_profiling/fashionnova/) (in progress)
- **...Hub QoS issues:** [peak_capacity_analysis/hub_qos/](peak_capacity_analysis/hub_qos/)
- **...peak capacity planning:** [peak_capacity_analysis/PEAK_2025_2026_STRATEGY_EXEC_REPORT.md](peak_capacity_analysis/PEAK_2025_2026_STRATEGY_EXEC_REPORT.md)

---

## 📊 Key Numbers (Quick Reference)

**Platform Cost:** $263,084/year  
**Cost per Retailer (avg):** $926/year  
**Largest Component:** shipments ($176,556, 67.1%)  
**Largest Retailer:** fashionnova ($99,718, 37.8% of platform)  
**Optimization Potential:** $34K-$75K/year (13-29% reduction)

---

## 👥 Contact

**For technical questions:** Data Engineering  
**For strategic questions:** Product Management + Data Engineering  
**For this analysis:** Cezar Mihaila (cezar.mihaila@narvar.com)

---

**Repository:** https://github.com/narvar/bigquery-optimization-queries  
**Last Updated:** November 19, 2025
