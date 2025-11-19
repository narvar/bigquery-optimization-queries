#!/usr/bin/env python3
"""
Execute recursive view resolution query and analyze results
"""

import sys
from pathlib import Path
from google.cloud import bigquery
import pandas as pd

def main():
    print("="*80)
    print("Recursive View Resolution - All 9 Monitor Views")
    print("="*80)
    print()
    
    # Initialize client
    client = bigquery.Client(project='narvar-data-lake')
    
    # Read query
    query_file = Path('../queries/monitor_total_cost/04_recursive_view_resolution_all_views.sql')
    with open(query_file, 'r') as f:
        query = f.read()
    
    print("Executing query...")
    print("This will trace all 9 views to their root base tables...")
    print()
    
    # Execute
    query_job = client.query(query)
    results = query_job.result()
    
    # Stats
    print(f"Bytes processed: {query_job.total_bytes_processed:,} ({query_job.total_bytes_processed/1024**3:.2f} GB)")
    print(f"Estimated cost: ${(query_job.total_bytes_billed/1024**4)*6.25:.4f}")
    print(f"Total rows: {results.total_rows:,}")
    print()
    
    # Convert to DataFrame
    df = results.to_dataframe()
    
    # Save
    output_file = Path('../results/monitor_total_cost/complete_view_dependency_tree.csv')
    df.to_csv(output_file, index=False)
    print(f"✅ Results saved to: {output_file}")
    print()
    
    # Analysis
    print("="*80)
    print("ANALYSIS RESULTS")
    print("="*80)
    print()
    
    # Base tables found
    base_tables = df[df['object_type'] == 'TABLE']['referenced_table'].unique()
    print(f"📊 BASE TABLES FOUND: {len(base_tables)}")
    print()
    for table in sorted(base_tables):
        views_using = df[(df['referenced_table'] == table) & (df['object_type'] == 'TABLE')]['original_view_name'].unique()
        print(f"  ✅ {table}")
        print(f"     Used by: {', '.join(sorted(views_using))}")
        print()
    
    # Views still unresolved
    unresolved_views = df[df['object_type'] == 'VIEW']['referenced_table'].unique()
    if len(unresolved_views) > 0:
        print(f"⚠️  VIEWS NOT FULLY RESOLVED: {len(unresolved_views)}")
        for view in sorted(unresolved_views)[:10]:
            print(f"  - {view}")
        print()
    
    # Resolution level distribution
    print("📈 RESOLUTION DEPTH:")
    level_dist = df.groupby('resolution_level').size()
    for level, count in level_dist.items():
        print(f"  Level {level}: {count} references")
    print()
    
    # Coverage by original view
    print("📋 COVERAGE BY ORIGINAL VIEW:")
    for view in sorted(df['original_view_name'].unique()):
        view_df = df[df['original_view_name'] == view]
        n_tables = len(view_df[view_df['object_type'] == 'TABLE'])
        n_views = len(view_df[view_df['object_type'] == 'VIEW'])
        print(f"  {view}: {n_tables} base tables, {n_views} intermediate views")
    print()
    
    print("="*80)
    print("✅ COMPLETE")
    print("="*80)
    print()
    print("Next step: Search audit logs for production costs of base tables")
    
    return df

if __name__ == '__main__':
    try:
        df = main()
    except Exception as e:
        print(f"❌ ERROR: {e}")
        sys.exit(1)

