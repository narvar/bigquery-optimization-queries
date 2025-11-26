#!/usr/bin/env python3
"""
Combine audit log consumption data with retailer mapping
Handles both literal names and MD5 hashes
"""

import pandas as pd
from pathlib import Path

# Paths
results_dir = Path(__file__).parent.parent / 'results'
audit_csv = results_dir / 'monitor_consumption_audit_logs_90days_clean.csv'
mapping_csv = results_dir / 'retailer_project_mapping.csv'
output_csv = results_dir / 'monitor_consumption_mapped_90days.csv'

print(f"Loading data...")
print(f"  Audit logs: {audit_csv}")
print(f"  Mapping: {mapping_csv}")

# Load data
audit_df = pd.read_csv(audit_csv)
mapping_df = pd.read_csv(mapping_csv)

print(f"\nAudit logs loaded: {len(audit_df)} entries")
print(f"Mapping loaded: {len(mapping_df)} retailers")

# Create hash → retailer lookup
hash_to_retailer = dict(zip(mapping_df['md5_hash'], mapping_df['retailer_moniker']))

print(f"\n=== Mapping MD5 hashes to retailer names ===")

# Map hashes to retailer names
def map_to_retailer(retailer):
    # If it's a 7-character hash, map it
    if pd.notna(retailer) and len(str(retailer)) == 7 and str(retailer) in hash_to_retailer:
        mapped = hash_to_retailer[str(retailer)]
        print(f"  Mapped: {retailer} → {mapped}")
        return mapped
    
    # Otherwise keep as-is (already a retailer name)
    return retailer

audit_df['retailer_mapped'] = audit_df['retailer_moniker'].apply(map_to_retailer)

# Combine rows for same retailer (literal name + hash queries)
print(f"\n=== Combining duplicate retailers ===")

combined_df = audit_df.groupby('retailer_mapped').agg({
    'query_count': 'sum',
    'total_slot_hours': 'sum',
    'estimated_cost_usd': 'sum',
    'first_query_date': 'min',
    'last_query_date': 'max',
    'active_days': 'max',  # Take max since they might query on different days via different paths
    'avg_execution_seconds': 'mean',
    'max_execution_seconds': 'max'
}).reset_index()

# Rename column
combined_df.rename(columns={'retailer_mapped': 'retailer_moniker'}, inplace=True)

# Recalculate avg_queries_per_day based on combined data
combined_df['avg_queries_per_day'] = combined_df['query_count'] / combined_df['active_days'].replace(0, 1)

# Round numeric columns
combined_df['total_slot_hours'] = combined_df['total_slot_hours'].round(2)
combined_df['estimated_cost_usd'] = combined_df['estimated_cost_usd'].round(2)
combined_df['avg_queries_per_day'] = combined_df['avg_queries_per_day'].round(2)
combined_df['avg_execution_seconds'] = combined_df['avg_execution_seconds'].round(2)

# Sort by cost descending
combined_df = combined_df.sort_values('estimated_cost_usd', ascending=False)

# Save
combined_df.to_csv(output_csv, index=False)

print(f"\n✅ Combined consumption data saved to: {output_csv}")
print(f"   Total retailers: {len(combined_df)}")

# Show top 20
print(f"\n=== TOP 20 RETAILERS (Audit Logs, Last 90 Days) ===")
for idx, row in combined_df.head(20).iterrows():
    print(f"{row.name+1:2d}. {row['retailer_moniker']:25s} {row['query_count']:6.0f} queries, ${row['estimated_cost_usd']:8.2f}, {row['active_days']:2.0f} days, {row['avg_queries_per_day']:5.1f} q/day")

# Check Gap and Kohls specifically
print(f"\n=== GAP AND KOHLS VERIFICATION ===")
for retailer in ['gap', 'kohls']:
    retailer_data = combined_df[combined_df['retailer_moniker'] == retailer]
    if len(retailer_data) > 0:
        row = retailer_data.iloc[0]
        print(f"\n{retailer.upper()}:")
        print(f"  Queries: {row['query_count']:.0f}")
        print(f"  Cost: ${row['estimated_cost_usd']:.2f} (90 days)")
        print(f"  Annualized: ${row['estimated_cost_usd'] * 4.056:.2f}")
        print(f"  Active days: {row['active_days']:.0f}")
        print(f"  Avg queries/day: {row['avg_queries_per_day']:.1f}")
    else:
        print(f"{retailer.upper()}: NOT FOUND")

# Stats
print(f"\n=== SUMMARY STATISTICS ===")
print(f"Total retailers: {len(combined_df)}")
print(f"Total queries: {combined_df['query_count'].sum():.0f}")
print(f"Total cost (90d): ${combined_df['estimated_cost_usd'].sum():.2f}")
print(f"Annualized: ${combined_df['estimated_cost_usd'].sum() * 4.056:.2f}")
print(f"Retailers with queries: {len(combined_df[combined_df['query_count'] > 0])}")

