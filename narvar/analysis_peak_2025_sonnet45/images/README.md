# Phase 2 Visualizations

This directory contains all visualizations generated from Phase 2 historical capacity analysis.

## 📊 Generated Visualizations

When you run the Phase 2 notebook (`notebooks/phase2_analysis.ipynb`), the following visualizations will be automatically saved here:

### Stress Analysis
- **`stress_state_distribution.png`** - Stacked bar chart showing % of time in each stress state (NORMAL/INFO/WARNING/CRITICAL) by period
- **`stress_timeline_Peak_2024_2025.html`** - Interactive Plotly timeline showing stress states over time with hover details
- **`stress_heatmap_hour_day.png`** - Heatmap of stress occurrences by hour of day and day of week

### Customer QoS Analysis
- **`customer_qos_by_stress_state.png`** - Dual plot showing:
  - QoS violation rates by stress state
  - P95 execution times with 60-second threshold line
- **`execution_time_distribution.html`** - Interactive box plot of P95 execution times by stress state

### Monitor-Base Causation
- **`monitor_base_causation.png`** - Bar chart comparing customer violation rates when monitor-base activity is HIGH vs LOW

## 🎨 Visualization Details

### Color Scheme

**Stress States**:
- 🟢 NORMAL: Green (#2ecc71)
- 🔵 INFO: Blue (#3498db)
- 🟠 WARNING: Orange (#f39c12)
- 🔴 CRITICAL: Red (#e74c3c)

**Categories**:
- 🔴 EXTERNAL: Red (#e74c3c) - P0 customer-facing
- 🔵 AUTOMATED: Blue (#3498db) - P0 scheduled processes
- ⚪ INTERNAL: Gray (#95a5a6) - P1 internal analytics

### Image Specifications

- **Format**: PNG for static images, HTML for interactive plots
- **DPI**: 300 (publication quality)
- **Size**: 
  - Wide plots: 16" × 6"
  - Tall plots: 12" × 8"
  - Square plots: 10" × 10"

## 🔄 Regenerating Visualizations

To regenerate visualizations:

1. Ensure Phase 2 query results are loaded in BigQuery
2. Open `notebooks/phase2_analysis.ipynb`
3. Run all cells (Cell → Run All)
4. Visualizations will be saved to this directory

## 📁 Directory Structure

```
images/
├── README.md (this file)
├── stress_state_distribution.png
├── stress_timeline_Peak_2024_2025.html
├── stress_heatmap_hour_day.png
├── customer_qos_by_stress_state.png
├── execution_time_distribution.html
└── monitor_base_causation.png
```

## 💡 Usage in Reports

These visualizations are designed for:
- Executive presentations
- Technical documentation
- Capacity planning reports
- Stakeholder reviews

All images are high-resolution and suitable for print or presentation.

---

**Note**: This directory is created automatically by the notebook. Visualizations are generated during notebook execution.


