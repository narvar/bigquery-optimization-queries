#!/usr/bin/env python3
"""
Generate cost distribution histogram from 90-day ALL retailers analysis
"""

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

# Read the CSV data
results_dir = Path(__file__).parent.parent / 'results'
csv_path = results_dir / 'combined_cost_attribution_90days_ALL.csv'
output_path = Path(__file__).parent.parent.parent / 'DELIVERABLES' / 'cost_distribution_histogram_90days.png'

# Load data
df = pd.read_csv(csv_path)
print(f"Loaded {len(df)} retailers from {csv_path}")

# Define cost buckets
bins = [0, 100, 500, 1000, 2500, 5000, 10000, float('inf')]
labels = ['$0-$100', '$100-$500', '$500-$1,000', '$1,000-$2,500', 
          '$2,500-$5,000', '$5,000-$10,000', '$10,000+']

# Categorize retailers by total cost
df['cost_bucket'] = pd.cut(df['total_cost_usd'], bins=bins, labels=labels, right=False)

# Count retailers in each bucket
bucket_counts = df['cost_bucket'].value_counts().reindex(labels, fill_value=0)

print("\n=== Distribution ===")
for label, count in bucket_counts.items():
    pct = (count / len(df)) * 100
    print(f"{label}: {count} retailers ({pct:.1f}%)")

# Create the histogram
fig, ax = plt.subplots(figsize=(14, 8))

# Create bar chart
x_pos = np.arange(len(labels))
colors = ['#E63946' if count > 1000 else '#2E86AB' for count in bucket_counts.values]
bars = ax.bar(x_pos, bucket_counts.values, color=colors, alpha=0.85, edgecolor='black', linewidth=0.5)

# Customize the plot
ax.set_xlabel('Total Cost per 90 Days (USD)', fontsize=15, fontweight='bold')
ax.set_ylabel('Number of Retailers', fontsize=15, fontweight='bold')
ax.set_title('Monitor Platform Cost Distribution - ALL 1,724 Retailers\n90-Day Analysis (Rolling Window)', 
             fontsize=17, fontweight='bold', pad=20)
ax.set_xticks(x_pos)
ax.set_xticklabels(labels, rotation=0, ha='center', fontsize=12)
ax.tick_params(axis='y', labelsize=12)

# Add value labels on top of bars
for i, (bar, count) in enumerate(zip(bars, bucket_counts.values)):
    if count > 0:
        height = bar.get_height()
        label_text = f'{int(count)}\n({(count/len(df))*100:.1f}%)'
        ax.text(bar.get_x() + bar.get_width()/2., height,
                label_text,
                ha='center', va='bottom', fontsize=11, fontweight='bold')

# Add grid for readability
ax.grid(axis='y', alpha=0.3, linestyle='--', linewidth=0.5)
ax.set_axisbelow(True)

# Add key insights box
insights_text = (
    "KEY INSIGHTS:\n"
    f"• 1,724 total retailers analyzed\n"
    f"• 1,618 retailers (93.9%) cost <$100 per 90 days\n"
    f"• 1,518 retailers (88.1%) have ZERO query consumption\n"
    f"• Only 206 retailers (11.9%) actively use Monitor"
)
props = dict(boxstyle='round', facecolor='wheat', alpha=0.8)
ax.text(0.98, 0.97, insights_text, transform=ax.transAxes, fontsize=10,
        verticalalignment='top', horizontalalignment='right', bbox=props)

# Add data quality note
note_text = (
    f"Data Source: combined_cost_attribution_90days_ALL.csv | All {len(df)} retailers\n"
    f"Period: Last 90 days (rolling window) | Production: Shipments, Orders, Returns | Consumption: Monitor queries\n"
    f"Pro-rated costs: Shipments ($43.4K), Orders ($11.2K), Returns ($2.9K) for 90-day period"
)
fig.text(0.5, 0.02, note_text, ha='center', fontsize=9, style='italic', color='#555555')

# Adjust layout to prevent label cutoff
plt.tight_layout(rect=[0, 0.06, 1, 0.96])

# Save the figure
plt.savefig(output_path, dpi=150, bbox_inches='tight', facecolor='white')
print(f"\n✅ Histogram saved to: {output_path}")

# Display summary statistics
print(f"\n=== Summary Statistics (90-Day Period) ===")
print(f"Total retailers: {len(df)}")
print(f"Min cost: ${df['total_cost_usd'].min():.2f}")
print(f"Max cost: ${df['total_cost_usd'].max():.2f}")
print(f"Mean cost: ${df['total_cost_usd'].mean():.2f}")
print(f"Median cost: ${df['total_cost_usd'].median():.2f}")
print(f"\nRetailers with zero consumption: {len(df[df['query_count'] == 0])}")
print(f"Retailers with consumption: {len(df[df['query_count'] > 0])}")

print(f"\nTop 10 retailers:")
for idx, row in df.nlargest(10, 'total_cost_usd').iterrows():
    print(f"  {row['retailer_moniker']}: ${row['total_cost_usd']:.2f} (queries: {row['query_count']:.0f})")

plt.close()

