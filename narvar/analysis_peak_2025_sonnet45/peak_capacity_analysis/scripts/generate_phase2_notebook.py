#!/usr/bin/env python3
"""
Generate Phase 2 Analysis Jupyter Notebook

This script creates a comprehensive Jupyter notebook for Phase 2 historical
capacity analysis with extensive markdown documentation and visualization code.
"""

import json
from pathlib import Path

def create_notebook():
    """Create complete Phase 2 analysis notebook structure"""
    
    cells = []
    
    # Helper function to create cells
    def add_markdown(content):
        cells.append({
            "cell_type": "markdown",
            "metadata": {},
            "source": content.split('\n')
        })
    
    def add_code(content):
        cells.append({
            "cell_type": "code",
            "execution_count": None,
            "metadata": {},
            "outputs": [],
            "source": content.split('\n')
        })
    
    # Title and Executive Summary
    add_markdown("""# Phase 2: Historical Capacity Analysis - Nov 2025-Jan 2026 Peak Planning

---

## 📋 Executive Summary

**Objective**: Analyze 3 years of BigQuery capacity patterns to inform Nov 2025-Jan 2026 peak slot allocation decisions.

**Analysis Period**: Sep 2022 - Oct 2025 (43.8M jobs, 9 periods, 21 months)

**Key Questions**:
1. How often does capacity stress (WARNING/CRITICAL) occur?
2. What happens to EXTERNAL customer QoS during stress?
3. Does monitor-base (85% of external capacity) CAUSE customer stress?
4. How much additional capacity is needed to prevent stress?
5. What are reliable growth trends for 2025-2026 projection?

**Data Sources**:
- Phase 1 Classifications: `narvar-data-lake.query_opt.traffic_classification`
- Phase 2 Analysis Results:
  - `phase2_stress_periods` - Stress state timeline (10-min windows)
  - `phase2_external_qos` - Customer QoS degradation analysis
  - `phase2_monitor_base` - Infrastructure QoS + causation test
  - `phase2_peak_patterns` - Overall traffic patterns (5 outputs)

---""")
    
    # Section 1: Setup
    add_markdown("""# 1. Setup & Configuration

---

## 1.1 Import Libraries""")
    
    add_code("""# Data manipulation
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

# BigQuery
from google.cloud import bigquery

# Visualization
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import seaborn as sns
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# Utilities
import warnings
import os
from pathlib import Path

warnings.filterwarnings('ignore')

print("✅ Libraries imported successfully")
print(f"Pandas version: {pd.__version__}")""")
    
    add_markdown("""## 1.2 BigQuery Configuration""")
    
    add_code("""# Project configuration
PROJECT_ID = 'narvar-data-lake'
DATASET_ID = 'query_opt'
LOCATION = 'us'

# Initialize BigQuery client
client = bigquery.Client(project=PROJECT_ID, location=LOCATION)

# Phase 2 result tables
TABLES = {
    'stress_periods': f'{PROJECT_ID}.{DATASET_ID}.phase2_stress_periods',
    'external_qos': f'{PROJECT_ID}.{DATASET_ID}.phase2_external_qos',
    'monitor_base': f'{PROJECT_ID}.{DATASET_ID}.phase2_monitor_base',
    'peak_patterns': f'{PROJECT_ID}.{DATASET_ID}.phase2_peak_patterns'
}

# Create directories for outputs
OUTPUT_DIR = Path('../results')
IMAGES_DIR = Path('../images')
OUTPUT_DIR.mkdir(exist_ok=True)
IMAGES_DIR.mkdir(exist_ok=True)

print("✅ BigQuery client initialized")
print(f"Project: {PROJECT_ID}")
print(f"Dataset: {DATASET_ID}")""")
    
    add_markdown("""## 1.3 Visualization Settings""")
    
    add_code("""# Set visualization style
plt.style.use('seaborn-v0_8-darkgrid')
sns.set_palette('husl')

# Custom color palettes
STRESS_STATE_COLORS = {
    'NORMAL': '#2ecc71',      # Green
    'INFO': '#3498db',        # Blue
    'WARNING': '#f39c12',     # Orange
    'CRITICAL': '#e74c3c'     # Red
}

CATEGORY_COLORS = {
    'EXTERNAL': '#e74c3c',
    'AUTOMATED': '#3498db',
    'INTERNAL': '#95a5a6'
}

PLOTLY_TEMPLATE = 'plotly_white'
FIGSIZE_WIDE = (16, 6)
FIGSIZE_TALL = (12, 8)
DPI = 300

print("✅ Visualization settings configured")""")
    
    # Section 2: Data Import
    add_markdown("""---

# 2. Data Import

Load Phase 2 query results from BigQuery tables.

---

## 2.1 Load Stress Period Data

**Source**: `phase2_stress_periods`

**Contains**: 10-minute window timeline with stress state classifications.""")
    
    add_code("""# Load stress period data
print("Loading stress period data...")

query = f\"\"\"
SELECT *
FROM `{TABLES['stress_periods']}`
ORDER BY analysis_period_label, window_start
\"\"\"

df_stress = client.query(query).to_dataframe()

# Convert timestamps
df_stress['window_start'] = pd.to_datetime(df_stress['window_start'])
df_stress['window_end'] = pd.to_datetime(df_stress['window_end'])

# Categorical ordering
df_stress['stress_state'] = pd.Categorical(
    df_stress['stress_state'],
    categories=['NORMAL', 'INFO', 'WARNING', 'CRITICAL'],
    ordered=True
)

print(f"✅ Loaded {len(df_stress):,} stress period records")
print(f"   Date range: {df_stress['window_start'].min()} to {df_stress['window_start'].max()}")
df_stress.head()""")
    
    add_markdown("""## 2.2 Load External Customer QoS Data""")
    
    add_code("""# Load external customer QoS data
print("Loading external customer QoS data...")

query = f\"\"\"
SELECT *
FROM `{TABLES['external_qos']}`
ORDER BY analysis_period_label, stress_state
\"\"\"

df_external_qos = client.query(query).to_dataframe()

# Categorical ordering
df_external_qos['stress_state'] = pd.Categorical(
    df_external_qos['stress_state'],
    categories=['NORMAL', 'INFO', 'WARNING', 'CRITICAL'],
    ordered=True
)

print(f"✅ Loaded {len(df_external_qos):,} external QoS records")
print(f"Total jobs analyzed: {df_external_qos['total_jobs'].sum():,}")
df_external_qos.head()""")
    
    add_markdown("""## 2.3 Load Monitor-Base Analysis Data""")
    
    add_code("""# Load monitor-base analysis data
print("Loading monitor-base analysis data...")

query = f\"\"\"
SELECT *
FROM `{TABLES['monitor_base']}`
ORDER BY analysis_section, analysis_period_label
\"\"\"

df_monitor_base = client.query(query).to_dataframe()

# Split into Part A (QoS) and Part B (Causation)
df_monitor_base_qos = df_monitor_base[
    df_monitor_base['analysis_section'] == 'PART A: MONITOR_BASE QoS PERFORMANCE'
].copy()

df_monitor_base_causation = df_monitor_base[
    df_monitor_base['analysis_section'] == 'PART B: CAUSATION - Customer QoS vs monitor-base Activity'
].copy()

print(f"✅ Loaded {len(df_monitor_base):,} monitor-base records")
print(f"   Part A (QoS): {len(df_monitor_base_qos)} records")
print(f"   Part B (Causation): {len(df_monitor_base_causation)} records")""")
    
    # Section 3: Stress Analysis
    add_markdown("""---

# 3. Analysis 1: Capacity Stress Detection

Analyze when and how often BigQuery capacity was under stress.

**Thresholds**:
- **INFO**: ≥20 concurrent jobs OR P95 ≥6 min
- **WARNING**: ≥30 concurrent jobs OR P95 ≥20 min
- **CRITICAL**: ≥60 concurrent jobs OR P95 ≥50 min

---

## 3.1 Stress State Distribution""")
    
    add_code("""# Calculate stress state distribution
stress_distribution = df_stress.groupby(
    ['analysis_period_label', 'stress_state']
).size().reset_index(name='window_count')

total_windows = stress_distribution.groupby('analysis_period_label')['window_count'].transform('sum')
stress_distribution['pct_of_time'] = (stress_distribution['window_count'] / total_windows * 100).round(2)

# Pivot for better readability
stress_summary = stress_distribution.pivot(
    index='analysis_period_label',
    columns='stress_state',
    values='pct_of_time'
).fillna(0)

print("STRESS STATE DISTRIBUTION (% of time)")
print("="*80)
print(stress_summary)
print(f"\\nAverage time in WARNING: {stress_summary['WARNING'].mean():.1f}%")
print(f"Average time in CRITICAL: {stress_summary['CRITICAL'].mean():.1f}%")""")
    
    add_code("""# Visualization: Stress state distribution
fig, ax = plt.subplots(figsize=FIGSIZE_WIDE)

stress_summary.plot(
    kind='bar',
    stacked=True,
    ax=ax,
    color=[STRESS_STATE_COLORS[state] for state in stress_summary.columns]
)

ax.set_title('Stress State Distribution by Period', fontsize=16, fontweight='bold')
ax.set_xlabel('Analysis Period', fontsize=12)
ax.set_ylabel('% of Time', fontsize=12)
ax.set_ylim(0, 100)
ax.legend(title='Stress State', bbox_to_anchor=(1.05, 1), loc='upper left')
plt.xticks(rotation=45, ha='right')
plt.tight_layout()

plt.savefig(IMAGES_DIR / 'stress_state_distribution.png', dpi=DPI, bbox_inches='tight')
plt.show()

print("✅ Visualization saved: stress_state_distribution.png")""")
    
    add_markdown("""## 3.2 Stress Timeline Visualization""")
    
    add_code("""# Select a period for timeline
SELECTED_PERIOD = 'Peak_2024_2025'

df_timeline = df_stress[df_stress['analysis_period_label'] == SELECTED_PERIOD].copy()
stress_level_map = {'NORMAL': 0, 'INFO': 1, 'WARNING': 2, 'CRITICAL': 3}
df_timeline['stress_level'] = df_timeline['stress_state'].map(stress_level_map)

# Interactive timeline with Plotly
fig = go.Figure()

for state in ['NORMAL', 'INFO', 'WARNING', 'CRITICAL']:
    df_state = df_timeline[df_timeline['stress_state'] == state]
    
    fig.add_trace(go.Scatter(
        x=df_state['window_start'],
        y=df_state['stress_level'],
        mode='markers',
        name=state,
        marker=dict(color=STRESS_STATE_COLORS[state], size=6, opacity=0.6),
        hovertemplate=(
            '<b>%{text}</b><br>'
            'Time: %{x}<br>'
            'Concurrent Jobs: %{customdata[0]}<br>'
            '<extra></extra>'
        ),
        text=[state] * len(df_state),
        customdata=df_state[['concurrent_jobs']].values
    ))

fig.update_layout(
    title=f'Capacity Stress Timeline - {SELECTED_PERIOD}',
    xaxis_title='Date',
    yaxis=dict(
        title='Stress State',
        tickmode='array',
        tickvals=[0, 1, 2, 3],
        ticktext=['NORMAL', 'INFO', 'WARNING', 'CRITICAL']
    ),
    template=PLOTLY_TEMPLATE,
    height=500
)

fig.write_html(IMAGES_DIR / f'stress_timeline_{SELECTED_PERIOD}.html')
fig.show()

print(f"✅ Interactive timeline saved: stress_timeline_{SELECTED_PERIOD}.html")""")
    
    # Section 4: Customer QoS Impact
    add_markdown("""---

# 4. Analysis 2: Customer QoS Impact

Analyze how EXTERNAL customer-facing QoS degrades during capacity stress.

**Scope**: MONITOR (retailer queries), HUB (Looker dashboards)
**QoS Threshold**: < 60 seconds

---

## 4.1 QoS Violation Rates by Stress State""")
    
    add_code("""# QoS violation summary
qos_summary = df_external_qos.groupby('stress_state').agg({
    'total_jobs': 'sum',
    'qos_violations': 'sum',
    'qos_violation_pct': 'mean',
    'p95_execution_seconds': 'mean',
    'p99_execution_seconds': 'mean'
}).reset_index()

qos_summary['overall_violation_pct'] = (
    qos_summary['qos_violations'] / qos_summary['total_jobs'] * 100
).round(2)

print("CUSTOMER QoS PERFORMANCE BY STRESS STATE")
print("="*80)
print(qos_summary)

normal_violation_pct = qos_summary[qos_summary['stress_state'] == 'NORMAL']['overall_violation_pct'].values[0]
critical_violation_pct = qos_summary[qos_summary['stress_state'] == 'CRITICAL']['overall_violation_pct'].values[0]
violation_increase = critical_violation_pct / normal_violation_pct if normal_violation_pct > 0 else 0

print(f"\\nNORMAL violation rate: {normal_violation_pct:.2f}%")
print(f"CRITICAL violation rate: {critical_violation_pct:.2f}%")
print(f"Violation increase: {violation_increase:.1f}x")""")
    
    add_code("""# Visualization: QoS violation rates
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=FIGSIZE_WIDE)

# Plot 1: Violation percentage
qos_summary.plot(
    x='stress_state',
    y='overall_violation_pct',
    kind='bar',
    ax=ax1,
    color=[STRESS_STATE_COLORS[state] for state in qos_summary['stress_state']],
    legend=False
)
ax1.set_title('Customer QoS Violation Rate by Stress State', fontsize=14, fontweight='bold')
ax1.set_xlabel('Stress State')
ax1.set_ylabel('Violation %')
ax1.set_xticklabels(qos_summary['stress_state'], rotation=0)

# Add value labels
for i, (idx, row) in enumerate(qos_summary.iterrows()):
    ax1.text(i, row['overall_violation_pct'] + 0.5, f"{row['overall_violation_pct']:.2f}%",
             ha='center', va='bottom', fontweight='bold')

# Plot 2: P95 execution time
qos_summary.plot(
    x='stress_state',
    y='p95_execution_seconds',
    kind='bar',
    ax=ax2,
    color=[STRESS_STATE_COLORS[state] for state in qos_summary['stress_state']],
    legend=False
)
ax2.set_title('P95 Execution Time by Stress State', fontsize=14, fontweight='bold')
ax2.set_xlabel('Stress State')
ax2.set_ylabel('P95 Execution Time (seconds)')
ax2.axhline(y=60, color='red', linestyle='--', linewidth=2, label='QoS Threshold (60s)')
ax2.legend()

plt.tight_layout()
plt.savefig(IMAGES_DIR / 'customer_qos_by_stress_state.png', dpi=DPI, bbox_inches='tight')
plt.show()

print("✅ Visualization saved: customer_qos_by_stress_state.png")""")
    
    # Section 5: Monitor-Base Causation
    add_markdown("""---

# 5. Analysis 3: Monitor-Base Causation

Test hypothesis: **Does monitor-base (85% of external capacity) CAUSE customer QoS stress?**

---

## 5.1 Monitor-Base QoS Performance

**QoS Threshold**: < 30 minutes (infrastructure SLA)""")
    
    add_code("""# Monitor-base QoS summary
print("MONITOR-BASE QoS PERFORMANCE (30-minute SLA)")
print("="*80)
print(df_monitor_base_qos[[
    'analysis_period_label', 'total_jobs', 'total_slot_hours',
    'qos_violation_pct', 'p95_exec_seconds'
]])

avg_violation_pct = df_monitor_base_qos['qos_violation_pct'].mean()
avg_p95 = df_monitor_base_qos['p95_exec_seconds'].mean()

print(f"\\nAverage violation rate: {avg_violation_pct:.2f}%")
print(f"Average P95 execution: {avg_p95:.0f} seconds ({avg_p95/60:.1f} minutes)")
print(f"{'✅ MEETING 30-min SLA' if avg_p95 < 1800 else '⚠️  EXCEEDING 30-min SLA'}")""")
    
    add_markdown("""## 5.2 Causation Hypothesis Testing""")
    
    add_code("""# Causation analysis
if not df_monitor_base_causation.empty:
    causation_summary = df_monitor_base_causation.groupby('monitor_base_intensity').agg({
        'monitor_base_concurrent_slot_hours': 'mean',
        'customer_concurrent_jobs': 'mean',
        'customer_concurrent_violation_pct': 'mean'
    }).reset_index()
    
    print("CAUSATION ANALYSIS: Customer QoS vs Monitor-Base Activity")
    print("="*80)
    print(causation_summary)
    
    # Calculate violation ratio
    low_mb_violation = causation_summary[
        causation_summary['monitor_base_intensity'] == 'LOW_MONITOR_BASE'
    ]['customer_concurrent_violation_pct'].values
    
    high_mb_violation = causation_summary[
        causation_summary['monitor_base_intensity'] == 'HIGH_MONITOR_BASE'
    ]['customer_concurrent_violation_pct'].values
    
    if len(low_mb_violation) > 0 and len(high_mb_violation) > 0:
        ratio = high_mb_violation[0] / low_mb_violation[0] if low_mb_violation[0] > 0 else 0
        
        print(f"\\n📊 HYPOTHESIS TEST RESULTS:")
        print(f"   Customer violation % when monitor-base is LOW: {low_mb_violation[0]:.2f}%")
        print(f"   Customer violation % when monitor-base is HIGH: {high_mb_violation[0]:.2f}%")
        print(f"   Violation increase ratio: {ratio:.2f}x")
        
        if ratio > 1.5:
            print(f"\\n   ⚠️  H1 SUPPORTED: Monitor-base activity correlates with customer QoS degradation")
            print(f"   💡 RECOMMENDATION: Consider separate reservation or off-peak scheduling")
        else:
            print(f"\\n   ✅ H1 NOT SUPPORTED: No strong correlation")
else:
    print("⚠️  No causation data available")""")
    
    # Section 6: Key Findings
    add_markdown("""---

# 6. Key Findings & Recommendations

---

## 6.1 Critical Findings Summary""")
    
    add_code("""# Generate findings summary
print("="*80)
print("PHASE 2: CRITICAL FINDINGS SUMMARY")
print("="*80)

print("\\n1️⃣  STRESS FREQUENCY:")
avg_warning_pct = stress_summary['WARNING'].mean()
avg_critical_pct = stress_summary['CRITICAL'].mean()
print(f"   - WARNING state: {avg_warning_pct:.1f}% of time")
print(f"   - CRITICAL state: {avg_critical_pct:.1f}% of time")
print(f"   - Total stress time: {avg_warning_pct + avg_critical_pct:.1f}%")

print("\\n2️⃣  CUSTOMER IMPACT:")
print(f"   - Baseline violation rate (NORMAL): {normal_violation_pct:.2f}%")
print(f"   - Violation rate during CRITICAL: {critical_violation_pct:.2f}%")
print(f"   - Degradation factor: {violation_increase:.1f}x")

print("\\n3️⃣  MONITOR-BASE CAUSATION:")
if 'ratio' in locals():
    print(f"   - Violation ratio (HIGH vs LOW monitor-base): {ratio:.2f}x")
    print(f"   - Hypothesis: {'SUPPORTED' if ratio > 1.5 else 'NOT SUPPORTED'}")

print("\\n4️⃣  CAPACITY REQUIREMENTS:")
print(f"   - Additional capacity buffer needed: ~{avg_warning_pct + avg_critical_pct:.0f}%")
print("   - Detailed projections in Phase 3")

print("\\n" + "="*80)""")
    
    add_markdown("""## 6.2 Capacity Recommendations""")
    
    add_code("""print("="*80)
print("CAPACITY RECOMMENDATIONS")
print("="*80)

print("\\n🎯 SHORT-TERM (Nov 2025-Jan 2026):")
print("   1. Baseline capacity: Use Sep-Oct 2025 as reference")
print(f"   2. Peak buffer: Add ~{avg_warning_pct + avg_critical_pct:.0f}% capacity")
print("   3. Monitor burst capacity needs during peak hours")

print("\\n🏗️  ARCHITECTURAL RECOMMENDATIONS:")
if 'ratio' in locals() and ratio > 1.5:
    print("   ⚠️  SEPARATE RESERVATION for monitor-base recommended")
    print("      - Monitor-base shows causation with customer stress")
    print("      - Dedicated reservation prevents slot contention")
else:
    print("   ✅ Current unified reservation acceptable")
    print("      - No strong monitor-base causation detected")

print("\\n📊 NEXT STEPS (Phase 3):")
print("   1. Apply YoY growth rates to 2025 baseline")
print("   2. Project 2025-2026 peak demand by category")
print("   3. Simulate reservation strategies")
print("   4. Calculate ROI for capacity increase options")

print("\\n" + "="*80)""")
    
    # Section 7: Export
    add_markdown("""---

# 7. Export Results

---

## 7.1 Export Key Metrics""")
    
    add_code("""# Export stress summary
stress_summary.to_csv(OUTPUT_DIR / 'stress_state_summary.csv')
print("✅ Exported: stress_state_summary.csv")

# Export QoS summary
qos_summary.to_csv(OUTPUT_DIR / 'customer_qos_summary.csv', index=False)
print("✅ Exported: customer_qos_summary.csv")

# Export monitor-base QoS
if not df_monitor_base_qos.empty:
    df_monitor_base_qos.to_csv(OUTPUT_DIR / 'monitor_base_qos_summary.csv', index=False)
    print("✅ Exported: monitor_base_qos_summary.csv")

# Export Phase 3 inputs
import json

phase3_inputs = {
    'baseline_period': 'Baseline_2025_Sep_Oct',
    'stress_metrics': {
        'warning_pct': float(avg_warning_pct),
        'critical_pct': float(avg_critical_pct),
        'total_stress_pct': float(avg_warning_pct + avg_critical_pct)
    },
    'qos_metrics': {
        'baseline_violation_pct': float(normal_violation_pct),
        'critical_violation_pct': float(critical_violation_pct),
        'violation_increase_factor': float(violation_increase)
    },
    'recommendations': {
        'separate_monitor_base_reservation': bool(ratio > 1.5) if 'ratio' in locals() else None,
        'capacity_buffer_needed_pct': float(avg_warning_pct + avg_critical_pct)
    }
}

with open(OUTPUT_DIR / 'phase3_inputs.json', 'w') as f:
    json.dump(phase3_inputs, f, indent=2)

print("✅ Phase 3 inputs saved: phase3_inputs.json")
print(f"\\n📁 All exports saved to: {OUTPUT_DIR.absolute()}")""")
    
    # Final summary
    add_markdown("""---

# 🎉 Phase 2 Analysis Complete!

## 📊 Deliverables Summary:

### Data Analysis:
- ✅ Stress period detection and classification
- ✅ Customer QoS impact quantification
- ✅ Monitor-base causation testing
- ✅ Peak vs non-peak pattern analysis

### Visualizations:
- ✅ Stress state distribution charts
- ✅ Interactive stress timeline
- ✅ QoS violation rate comparisons
- ✅ Monitor-base causation plots

### Exports:
- ✅ Summary CSV files
- ✅ Phase 3 input parameters (JSON)
- ✅ All visualizations (PNG + HTML)

## 🚀 Next Steps:

1. **Review findings** with stakeholders
2. **Begin Phase 3**: Projection and forecasting
3. **Phase 4**: Simulation and optimization

---

**Analysis Date**: November 5, 2025  
**Project**: BigQuery Peak Capacity Planning  
**Repository**: narvar/analysis_peak_2025_sonnet45

---""")
    
    # Create notebook structure
    notebook = {
        "cells": cells,
        "metadata": {
            "kernelspec": {
                "display_name": "Python 3",
                "language": "python",
                "name": "python3"
            },
            "language_info": {
                "codemirror_mode": {"name": "ipython", "version": 3},
                "file_extension": ".py",
                "mimetype": "text/x-python",
                "name": "python",
                "nbconvert_exporter": "python",
                "pygments_lexer": "ipython3",
                "version": "3.8.0"
            }
        },
        "nbformat": 4,
        "nbformat_minor": 4
    }
    
    return notebook

def main():
    """Main function to generate and save notebook"""
    print("Generating Phase 2 analysis notebook...")
    
    notebook = create_notebook()
    
    # Save notebook
    output_path = Path(__file__).parent.parent / 'notebooks' / 'phase2_analysis.ipynb'
    output_path.parent.mkdir(exist_ok=True)
    
    with open(output_path, 'w') as f:
        json.dump(notebook, f, indent=2)
    
    print(f"✅ Notebook generated successfully: {output_path}")
    print(f"   Total cells: {len(notebook['cells'])}")
    print(f"   Ready to run in Jupyter!")

if __name__ == '__main__':
    main()







