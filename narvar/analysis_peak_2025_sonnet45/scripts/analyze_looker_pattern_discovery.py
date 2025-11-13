#!/usr/bin/env python3
"""
Analyze Hub pattern discovery results to identify additional patterns.
Focus on the 40% of queries where retailer extraction failed.
"""

import pandas as pd
import re
from pathlib import Path

def analyze_patterns():
    """Analyze pattern discovery results and identify new patterns."""
    
    # Load results
    results_file = 'results/hub_pattern_discovery_20251112_130121.csv'
    print(f"\n📂 Loading results from: {results_file}\n")
    
    df = pd.read_csv(results_file)
    
    print("="*80)
    print("PATTERN DISCOVERY DEEP DIVE")
    print("="*80)
    
    # Separate successful vs failed extractions
    success = df[df['retailer_extraction_success'] == True]
    failed = df[df['retailer_extraction_success'] == False]
    
    print(f"\n📊 Overall Statistics:")
    print(f"   Total queries: {len(df)}")
    print(f"   ✅ Successful: {len(success)} ({len(success)/len(df)*100:.1f}%)")
    print(f"   ❌ Failed: {len(failed)} ({len(failed)/len(df)*100:.1f}%)")
    
    # Pattern performance breakdown
    print(f"\n🎯 Pattern Performance:")
    print(f"   Pattern 1 (retailer_moniker = 'X'): {df['pattern_1_retailer_equals'].notna().sum()} matches")
    print(f"   Pattern 2 (retailer_moniker IN (...)): {df['pattern_2_retailer_in'].notna().sum()} matches")
    print(f"   Pattern 3 (JOIN ... retailer): {df['pattern_3_join_retailer'].notna().sum()} matches")
    
    # Looker metadata presence
    print(f"\n💡 Looker Metadata:")
    print(f"   Has Looker comments: {df['has_looker_comment'].sum()}")
    print(f"   Has dashboard names: {df['dashboard_name'].notna().sum()}")
    print(f"   Has view names: {df['view_name'].notna().sum()}")
    
    # Show successful retailer extractions
    print(f"\n✅ SUCCESSFUL RETAILER EXTRACTIONS (Sample):")
    print("="*80)
    retailers_found = success['best_retailer_match'].value_counts().head(10)
    for retailer, count in retailers_found.items():
        print(f"   {retailer}: {count} queries")
    
    # Analyze failed queries
    print(f"\n❌ FAILED EXTRACTIONS - MANUAL REVIEW NEEDED:")
    print("="*80)
    print(f"\nShowing {min(10, len(failed))} queries where pattern extraction failed:\n")
    
    for idx, row in failed.head(10).iterrows():
        print(f"\n--- Query {idx+1} ---")
        print(f"Job ID: {row['job_id']}")
        print(f"Period: {row['analysis_period_label']}")
        print(f"Execution: {row['execution_time_seconds']:.1f}s (QoS: {'VIOLATION' if row['is_qos_violation'] else 'OK'})")
        print(f"Cost: ${row['estimated_slot_cost_usd']:.4f}")
        print(f"\nQuery Preview (first 1000 chars):")
        print("-" * 80)
        preview = str(row['query_preview_1000'])
        print(preview[:1000] if pd.notna(preview) else "No preview available")
        print("-" * 80)
        
        # Look for potential patterns in preview
        print("\n🔍 Pattern Analysis:")
        if pd.notna(preview):
            # Check for various retailer-related patterns
            patterns_to_check = {
                'Has retailer_moniker word': 'retailer_moniker' in preview.lower(),
                'Has retailer word': 'retailer' in preview.lower(),
                'Has FROM returns': 'from returns' in preview.lower() or 'FROM returns' in preview,
                'Has FROM shipments': 'from shipments' in preview.lower() or 'FROM shipments' in preview,
                'Has WHERE clause': 'WHERE' in preview or 'where' in preview,
                'Has project_id in query': 'monitor-' in preview,
                'Has table with underscore': bool(re.search(r'FROM\s+\w+\.\w+_', preview, re.IGNORECASE)),
            }
            
            for pattern_name, found in patterns_to_check.items():
                print(f"   {pattern_name}: {'✓' if found else '✗'}")
        
        print("\n" + "="*80)
    
    # Export failed queries for manual review
    failed_export = failed[['job_id', 'analysis_period_label', 'execution_time_seconds', 
                            'is_qos_violation', 'query_preview_1000']].copy()
    
    failed_file = 'results/hub_failed_patterns_for_review.csv'
    failed_export.to_csv(failed_file, index=False)
    print(f"\n💾 Failed patterns exported to: {failed_file}")
    print(f"   ({len(failed)} queries for manual review)")
    
    # Query characteristics comparison
    print(f"\n📈 CHARACTERISTIC COMPARISON:")
    print("="*80)
    print(f"{'Metric':<30} {'Successful':<15} {'Failed':<15}")
    print("-"*80)
    
    metrics = {
        'Avg Query Length': ('full_query_length', 'mean'),
        'Avg Execution Time (s)': ('execution_time_seconds', 'mean'),
        'QoS Violation Rate (%)': ('is_qos_violation', lambda x: x.sum()/len(x)*100),
        'Has JOINs (%)': ('has_joins', lambda x: x.sum()/len(x)*100),
        'Has GROUP BY (%)': ('has_group_by', lambda x: x.sum()/len(x)*100),
        'Has CTEs (%)': ('has_cte', lambda x: x.sum()/len(x)*100),
        'References retailer table (%)': ('references_retailer_table', lambda x: x.sum()/len(x)*100),
    }
    
    for metric_name, (col, agg_func) in metrics.items():
        if col in df.columns:
            if callable(agg_func):
                success_val = agg_func(success[col]) if len(success) > 0 else 0
                failed_val = agg_func(failed[col]) if len(failed) > 0 else 0
            else:
                success_val = success[col].agg(agg_func) if len(success) > 0 else 0
                failed_val = failed[col].agg(agg_func) if len(failed) > 0 else 0
            
            print(f"{metric_name:<30} {success_val:<15.1f} {failed_val:<15.1f}")
    
    # Recommendations
    print(f"\n💡 RECOMMENDATIONS FOR NEW PATTERNS:")
    print("="*80)
    print("""
Based on the analysis, consider adding these patterns:

1. **Project ID Pattern**: Extract retailer from monitor project IDs in query
   - Look for: 'monitor-{hash}-us-prod' in FROM clauses
   - Map back to retailer using MD5 matching

2. **Table Name Patterns**: Some retailers may have dedicated tables
   - Look for: table names containing retailer identifiers
   - Pattern: `FROM dataset.{retailer}_*`

3. **Query Comments**: Check for retailer in SQL comments
   - Pattern: `-- Retailer: {name}`
   - Pattern: `/* Retailer: {name} */`

4. **LIKE Patterns**: Check for partial matches
   - Pattern: `WHERE retailer_moniker LIKE '%{value}%'`

5. **Subquery Patterns**: Retailer might be in nested queries
   - Check CTEs and subqueries for retailer_moniker

6. **Full Query Analysis**: If patterns still insufficient
   - Some queries may be aggregate dashboards (no specific retailer)
   - Consider 'ALL_RETAILERS' or 'MULTI_RETAILER' classification

Next Step: Review failed queries manually and identify common patterns.
Then update the full analysis query with improved regex patterns.
    """)
    
    print("\n✅ Analysis complete!")
    print(f"📁 Review failed queries in: {failed_file}")
    print(f"\n🚀 Ready for manual pattern identification...")
    
    return df, success, failed

if __name__ == "__main__":
    import os
    os.chdir('/Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/analysis_peak_2025_sonnet45')
    
    df, success, failed = analyze_patterns()

