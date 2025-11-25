#!/usr/bin/env python3
"""
Generate treemap visualization:
- Rectangle SIZE = Production cost (bigger = more expensive to produce)
- Rectangle COLOR = Consumption intensity (darker red = heavier consumption)
- Shows top 100 retailers by total cost
"""

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import squarify
from pathlib import Path

# Read the CSV data
results_dir = Path(__file__).parent.parent / 'results'
csv_path = results_dir / 'combined_cost_attribution_90days_ALL.csv'
output_path = Path(__file__).parent.parent.parent / 'DELIVERABLES' / 'cost_treemap_production_vs_consumption.png'

# Load data
df = pd.read_csv(csv_path)
print(f"Loaded {len(df)} retailers from {csv_path}")

# Get top 100 by total cost
df_top100 = df.nlargest(100, 'total_cost_usd').copy()
print(f"\nAnalyzing top {len(df_top100)} retailers")

# Calculate consumption ratio (for color intensity)
# Using log scale for better visualization since 511tactical is 26x outlier
df_top100['consumption_ratio'] = df_top100['consumption_cost_usd'] / df_top100['total_production_cost_usd'].replace(0, 1)
df_top100['consumption_ratio'] = df_top100['consumption_ratio'].fillna(0)

# Create labels (retailer name + cost)
df_top100['label'] = df_top100.apply(
    lambda x: f"{x['retailer_moniker']}\n${x['total_production_cost_usd']:.0f}\n({x['consumption_ratio']*100:.1f}%)" 
    if x['total_production_cost_usd'] > 200 else "",  # Only show labels for large rectangles
    axis=1
)

# Prepare data for treemap
sizes = df_top100['total_production_cost_usd'].values
labels = df_top100['label'].values
consumption_ratios = df_top100['consumption_ratio'].values

# Create color map based on consumption ratio
# Use log scale for better visualization
import numpy as np
consumption_log = np.log1p(consumption_ratios * 100)  # log(1 + ratio%)
norm_consumption = (consumption_log - consumption_log.min()) / (consumption_log.max() - consumption_log.min() + 0.001)

# Color scheme: 
# - White/Light Blue = No consumption (zombie)
# - Blue = Low consumption
# - Yellow/Orange = Medium consumption  
# - Red = High consumption
colors = []
for val in norm_consumption:
    if val < 0.1:  # Nearly zero consumption
        colors.append('#E8F4F8')  # Very light blue (zombie)
    elif val < 0.3:
        colors.append('#6FB1D2')  # Light blue (low consumption)
    elif val < 0.5:
        colors.append('#2E86AB')  # Medium blue (normal)
    elif val < 0.7:
        colors.append('#F77F00')  # Orange (elevated)
    else:
        colors.append('#D62828')  # Red (heavy consumption)

# Create the treemap
fig, ax = plt.subplots(figsize=(20, 12))

squarify.plot(
    sizes=sizes,
    label=labels,
    color=colors,
    alpha=0.8,
    edgecolor='white',
    linewidth=2,
    text_kwargs={'fontsize': 8, 'weight': 'bold'},
    ax=ax
)

# Remove axes
ax.axis('off')

# Add title
plt.title(
    'Monitor Platform: Production Cost vs Consumption\n'
    'Top 100 Retailers by Total Cost (90-Day Analysis)',
    fontsize=18, fontweight='bold', pad=20
)

# Create legend
legend_elements = [
    mpatches.Patch(facecolor='#E8F4F8', edgecolor='black', label='Zombie (0% consumption)'),
    mpatches.Patch(facecolor='#6FB1D2', edgecolor='black', label='Low (<1% consumption)'),
    mpatches.Patch(facecolor='#2E86AB', edgecolor='black', label='Normal (1-5% consumption)'),
    mpatches.Patch(facecolor='#F77F00', edgecolor='black', label='Elevated (5-20% consumption)'),
    mpatches.Patch(facecolor='#D62828', edgecolor='black', label='Heavy (>20% consumption)'),
]

ax.legend(
    handles=legend_elements,
    loc='upper left',
    bbox_to_anchor=(0.01, 0.99),
    fontsize=11,
    framealpha=0.95,
    title='Consumption Level',
    title_fontsize=12
)

# Add explanation box
explanation_text = (
    "📊 How to Read This Chart:\n"
    "• Rectangle SIZE = Production cost (ETL, storage)\n"
    "• Rectangle COLOR = Consumption intensity (queries)\n"
    "• Larger rectangles = More expensive to produce\n"
    "• Redder color = Heavier query usage"
)
props = dict(boxstyle='round', facecolor='wheat', alpha=0.9)
ax.text(
    0.99, 0.01, explanation_text,
    transform=ax.transAxes,
    fontsize=10,
    verticalalignment='bottom',
    horizontalalignment='right',
    bbox=props
)

# Add data quality note at bottom
fig.text(
    0.5, 0.01,
    'Data: Last 90 days | Production: Shipments, Orders, Returns | Consumption: Monitor queries',
    ha='center', fontsize=9, style='italic', color='#555555'
)

plt.tight_layout()

# Save the figure
plt.savefig(output_path, dpi=150, bbox_inches='tight', facecolor='white')
print(f"\n✅ Treemap saved to: {output_path}")

# Print statistics
print(f"\n=== Treemap Statistics ===")
print(f"Total retailers shown: {len(df_top100)}")
print(f"Total production cost: ${df_top100['total_production_cost_usd'].sum():.2f}")
print(f"Total consumption cost: ${df_top100['consumption_cost_usd'].sum():.2f}")
print(f"\nTop 5 by production cost:")
for idx, row in df_top100.nlargest(5, 'total_production_cost_usd').iterrows():
    print(f"  {row['retailer_moniker']}: ${row['total_production_cost_usd']:.2f} (consumption: {row['consumption_ratio']*100:.1f}%)")

print(f"\nTop 5 by consumption ratio:")
for idx, row in df_top100.nlargest(5, 'consumption_ratio').iterrows():
    print(f"  {row['retailer_moniker']}: {row['consumption_ratio']*100:.1f}% (${row['consumption_cost_usd']:.2f} / ${row['total_production_cost_usd']:.2f})")

print(f"\nZombie retailers (0 consumption) in top 100:")
zombies = df_top100[df_top100['query_count'] == 0]
print(f"  Count: {len(zombies)}")
print(f"  Total cost: ${zombies['total_production_cost_usd'].sum():.2f}")

plt.close()

