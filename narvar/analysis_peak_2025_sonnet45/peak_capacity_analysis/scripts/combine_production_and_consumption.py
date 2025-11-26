#!/usr/bin/env python3
"""
Combine production costs with corrected consumption data from audit logs
Updates the existing combined_cost_attribution_90days_ALL.csv file
"""

import pandas as pd
from pathlib import Path

# Paths
results_dir = Path(__file__).parent.parent / 'results'
production_csv = results_dir / 'combined_cost_attribution_90days_ALL.csv'
consumption_csv = results_dir / 'monitor_consumption_mapped_90days.csv'
output_csv = results_dir / 'combined_cost_attribution_90days_ALL.csv'  # Update existing file

print("Loading data...")
production_df = pd.read_csv(production_csv)
consumption_df = pd.read_csv(consumption_csv)

print(f"Production data: {len(production_df)} retailers")
print(f"Consumption data (corrected): {len(consumption_df)} retailers")

# Merge production with corrected consumption
# Drop old consumption columns from production
production_clean = production_df.drop(columns=['consumption_cost_usd', 'consumption_slot_hours', 'query_count', 
                                                'first_query_date', 'last_query_date', 'query_days_active', 
                                                'avg_queries_per_day', 'consumption_to_production_ratio', 
                                                'consumption_pct_of_total', 'total_cost_usd'], errors='ignore')

# Rename consumption columns to match expected names
consumption_rename = consumption_df[['retailer_moniker', 'query_count', 'total_slot_hours', 'estimated_cost_usd', 
                                     'first_query_date', 'last_query_date', 'active_days', 'avg_queries_per_day']].copy()
consumption_rename.rename(columns={
    'total_slot_hours': 'consumption_slot_hours',
    'estimated_cost_usd': 'consumption_cost_usd',
    'active_days': 'query_days_active'
}, inplace=True)

# Merge
merged_df = production_clean.merge(consumption_rename, on='retailer_moniker', how='left')

# Fill NaN values with 0/defaults for retailers with no consumption
merged_df['consumption_cost_usd'] = merged_df['consumption_cost_usd'].fillna(0)
merged_df['consumption_slot_hours'] = merged_df['consumption_slot_hours'].fillna(0)
merged_df['query_count'] = merged_df['query_count'].fillna(0).astype(int)
merged_df['query_days_active'] = merged_df['query_days_active'].fillna(1).astype(int)
merged_df['avg_queries_per_day'] = merged_df['avg_queries_per_day'].fillna(0)

# Recalculate total cost and ratios
merged_df['total_cost_usd'] = merged_df['total_production_cost_usd'] + merged_df['consumption_cost_usd']
merged_df['consumption_to_production_ratio'] = (
    merged_df['consumption_cost_usd'] / merged_df['total_production_cost_usd'].replace(0, 1)
).round(4)
merged_df['consumption_pct_of_total'] = (
    merged_df['consumption_cost_usd'] / merged_df['total_cost_usd'].replace(0, 1)
).round(4)

# Select final columns in correct order
final_df = merged_df[[
    'retailer_moniker', 'shipment_count', 'order_count', 'return_count',
    'shipments_production_cost_usd', 'orders_production_cost_usd', 'returns_production_cost_usd',
    'total_production_cost_usd', 'consumption_cost_usd', 'consumption_slot_hours',
    'query_count', 'first_query_date', 'last_query_date', 'query_days_active',
    'avg_queries_per_day', 'total_cost_usd', 'consumption_to_production_ratio',
    'consumption_pct_of_total'
]].sort_values('total_cost_usd', ascending=False)

# Save
final_df.to_csv(output_csv, index=False)

print(f"\n✅ Updated file: {output_csv}")
print(f"   Total retailers: {len(final_df)}")

# Show changes for Gap and Kohls
print(f"\n=== CORRECTED GAP AND KOHLS DATA ===")
for retailer in ['gap', 'kohls']:
    row = final_df[final_df['retailer_moniker'] == retailer]
    if len(row) > 0:
        row = row.iloc[0]
        rank = final_df[final_df['retailer_moniker'] == retailer].index[0] + 1
        print(f"\n{retailer.upper()} (Rank #{rank}):")
        print(f"  Production: ${row['total_production_cost_usd']:.2f}")
        print(f"  Consumption: ${row['consumption_cost_usd']:.2f} (was $0)")
        print(f"  Total: ${row['total_cost_usd']:.2f}")
        print(f"  Queries: {row['query_count']:.0f} (was 0)")
        print(f"  Active days: {row['query_days_active']:.0f}")
        print(f"  Avg/day: {row['avg_queries_per_day']:.1f}")
        print(f"  Status: ✅ ACTIVE (was ❌ Zombie)")

# Stats on zombie correction
print(f"\n=== ZOMBIE STATISTICS (CORRECTED) ===")
zombies = final_df[final_df['query_count'] == 0]
active = final_df[final_df['query_count'] > 0]
print(f"Zombies (0 queries): {len(zombies)} ({len(zombies)/len(final_df)*100:.1f}%)")
print(f"Active (>0 queries): {len(active)} ({len(active)/len(final_df)*100:.1f}%)")
print(f"Zombie cost: ${zombies['total_production_cost_usd'].sum():.2f} (90d)")
print(f"Zombie cost annualized: ${zombies['total_production_cost_usd'].sum() * 4.056:.2f}")

# Top 20
print(f"\n=== TOP 20 RETAILERS (CORRECTED) ===")
for idx, row in final_df.head(20).iterrows():
    status = "🔴 Zombie" if row['query_count'] == 0 else "✅ Active"
    print(f"{idx+1:2d}. {row['retailer_moniker']:20s} ${row['total_cost_usd']:7.2f} "
          f"(prod: ${row['total_production_cost_usd']:.0f}, cons: ${row['consumption_cost_usd']:.0f}, "
          f"q: {row['query_count']:.0f}) {status}")

