#!/usr/bin/env python3
"""
Generate accurate cost distribution histogram from combined_cost_attribution.csv
"""

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

# Read the CSV data
results_dir = Path(__file__).parent.parent / 'results'
csv_path = results_dir / 'combined_cost_attribution.csv'
output_path = Path(__file__).parent.parent.parent / 'DELIVERABLES' / 'cost_distribution_histogram.png'

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
    print(f"{label}: {count} retailers")

# Create the histogram
fig, ax = plt.subplots(figsize=(12, 7))

# Create bar chart
x_pos = np.arange(len(labels))
bars = ax.bar(x_pos, bucket_counts.values, color='#2E86AB', alpha=0.85, edgecolor='black', linewidth=0.5)

# Customize the plot
ax.set_xlabel('Total Cost (USD, Logarithmic Scale)', fontsize=14, fontweight='bold')
ax.set_ylabel('Number of Retailers', fontsize=14, fontweight='bold')
ax.set_title('Retailer Cost Distribution (Production + Consumption)\nTop 100 Retailers by Total Cost', 
             fontsize=16, fontweight='bold', pad=20)
ax.set_xticks(x_pos)
ax.set_xticklabels(labels, rotation=0, ha='center', fontsize=11)
ax.tick_params(axis='y', labelsize=11)

# Add value labels on top of bars
for i, (bar, count) in enumerate(zip(bars, bucket_counts.values)):
    if count > 0:
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{int(count)}',
                ha='center', va='bottom', fontsize=11, fontweight='bold')

# Add grid for readability
ax.grid(axis='y', alpha=0.3, linestyle='--', linewidth=0.5)
ax.set_axisbelow(True)

# Add data quality note
note_text = (
    f"Data Source: combined_cost_attribution.csv | Top 100 retailers analyzed\n"
    f"Period: Shipments (all-time), Orders (2024), Returns (90 days), Consumption (Nov 2024-Jan 2025)"
)
fig.text(0.5, 0.02, note_text, ha='center', fontsize=9, style='italic', color='#555555')

# Adjust layout to prevent label cutoff
plt.tight_layout(rect=[0, 0.04, 1, 0.96])

# Save the figure
plt.savefig(output_path, dpi=150, bbox_inches='tight', facecolor='white')
print(f"\n✅ Histogram saved to: {output_path}")

# Display summary statistics
print(f"\n=== Summary Statistics ===")
print(f"Total retailers: {len(df)}")
print(f"Min cost: ${df['total_cost_usd'].min():.2f}")
print(f"Max cost: ${df['total_cost_usd'].max():.2f}")
print(f"Mean cost: ${df['total_cost_usd'].mean():.2f}")
print(f"Median cost: ${df['total_cost_usd'].median():.2f}")
print(f"\nTop 5 retailers:")
for idx, row in df.nlargest(5, 'total_cost_usd').iterrows():
    print(f"  {row['retailer_moniker']}: ${row['total_cost_usd']:.2f}")

plt.close()

