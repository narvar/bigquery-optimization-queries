#!/usr/bin/env python3
"""
Run Hub Analytics API pattern discovery to find retailer attribution patterns.
Cost: ~$0.19 (38 GB scan)
"""

import os
from google.cloud import bigquery
from datetime import datetime
import pandas as pd

def run_pattern_discovery():
    """Execute Hub Analytics API pattern discovery query."""
    
    # Initialize BigQuery client
    client = bigquery.Client()
    
    # Read query from file
    query_file = 'queries/phase2_consumer_analysis/hub_analytics_api_pattern_discovery.sql'
    print(f"\n📂 Reading query from: {query_file}")
    
    with open(query_file, 'r') as f:
        query = f.read()
    
    print(f"\n🚀 Executing Hub Analytics API pattern discovery...")
    print(f"⚠️  Estimated cost: ~$0.19 (38 GB scan)")
    print(f"⏱️  This may take 1-2 minutes...\n")
    
    # Run query
    try:
        df = client.query(query).to_dataframe()
        
        print(f"✅ Query completed successfully!")
        print(f"📊 Results: {len(df)} queries sampled\n")
        
        # Save to CSV
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = f'results/hub_analytics_api_pattern_discovery_{timestamp}.csv'
        
        df.to_csv(output_file, index=False)
        print(f"💾 Results saved to: {output_file}")
        
        # Print summary statistics
        print(f"\n" + "="*80)
        print(f"HUB ANALYTICS API PATTERN DISCOVERY SUMMARY")
        print(f"="*80)
        
        if len(df) > 0:
            print(f"\n📈 Sample Size:")
            print(f"   Total queries: {len(df)}")
            print(f"   By period:")
            for period, count in df['analysis_period_label'].value_counts().items():
                print(f"      {period}: {count}")
            
            print(f"\n🎯 Retailer Extraction Success Rates:")
            if 'retailer_extraction_success' in df.columns:
                success_rate = df['retailer_extraction_success'].sum() / len(df) * 100
                print(f"   Overall: {success_rate:.1f}%")
                
                patterns = {
                    'pattern_1_retailer_equals': 'WHERE retailer_moniker = X',
                    'pattern_2_retailer_in': 'WHERE retailer_moniker IN (...)',
                    'pattern_3_join_retailer': 'JOIN ... retailer',
                    'pattern_4_comment_retailer': '-- retailer: X',
                    'pattern_5_json_retailer': '{"retailer": "X"}',
                    'pattern_6_url_retailer': '?retailer=X'
                }
                
                for col, desc in patterns.items():
                    if col in df.columns:
                        count = df[col].notna().sum()
                        pct = count / len(df) * 100
                        if count > 0:
                            print(f"   {desc}: {count} ({pct:.1f}%)")
            
            print(f"\n🔍 Field Presence:")
            if 'has_retailer_moniker_field' in df.columns:
                count = df['has_retailer_moniker_field'].sum()
                pct = count / len(df) * 100
                print(f"   Has retailer_moniker field: {count} ({pct:.1f}%)")
            if 'has_retailer_word' in df.columns:
                count = df['has_retailer_word'].sum()
                pct = count / len(df) * 100
                print(f"   Has 'retailer' word: {count} ({pct:.1f}%)")
            
            print(f"\n🔧 Query Characteristics:")
            for col in ['has_joins', 'has_group_by', 'has_cte', 'has_window_functions', 'has_partition_filter']:
                if col in df.columns:
                    count = df[col].sum()
                    pct = count / len(df) * 100
                    print(f"   {col}: {count} ({pct:.1f}%)")
            
            print(f"\n⚠️  QoS Metrics:")
            violations = df['is_qos_violation'].sum()
            violation_pct = violations / len(df) * 100
            print(f"   QoS violations: {violations} ({violation_pct:.1f}%)")
            print(f"   Avg execution: {df['execution_time_seconds'].mean():.1f}s")
            if len(df) > 1:
                print(f"   P95 execution: {df['execution_time_seconds'].quantile(0.95):.1f}s")
            
            print(f"\n💰 Cost Metrics:")
            print(f"   Total slot-hours: {df['slot_hours'].sum():.2f}")
            print(f"   Total cost: ${df['estimated_slot_cost_usd'].sum():.2f}")
            print(f"   Avg cost per query: ${df['estimated_slot_cost_usd'].mean():.4f}")
            
            print(f"\n📝 Query Size:")
            print(f"   Avg full query length: {df['full_query_length'].mean():.0f} chars")
            print(f"   Avg partial query length: {df['partial_query_length'].mean():.0f} chars")
            if 'pct_captured_in_sample' in df.columns:
                print(f"   Avg % captured in sample: {df['pct_captured_in_sample'].mean():.1f}%")
            
            # Show successful retailer extractions
            if 'best_retailer_match' in df.columns:
                retailers_found = df[df['retailer_extraction_success'] == True]['best_retailer_match'].value_counts().head(10)
                if len(retailers_found) > 0:
                    print(f"\n✅ SUCCESSFUL RETAILER EXTRACTIONS (Top 10):")
                    for retailer, count in retailers_found.items():
                        print(f"   {retailer}: {count} queries")
                else:
                    print(f"\n❌ NO SUCCESSFUL RETAILER EXTRACTIONS")
                    print(f"   Hub Analytics API may use centralized queries without retailer filters")
        
        print(f"\n" + "="*80)
        print(f"\n✅ Pattern discovery complete!")
        print(f"📁 Review results in: {output_file}")
        print(f"\n💡 Next steps:")
        print(f"   1. Review pattern extraction success rates")
        print(f"   2. Examine query_preview_1000 for manual pattern identification")
        print(f"   3. Determine if Hub Analytics API has retailer attribution")
        print(f"   4. If successful, create full analysis query with retailer breakdown")
        
        return df, output_file
        
    except Exception as e:
        print(f"\n❌ Query failed: {str(e)}")
        import traceback
        traceback.print_exc()
        return None, None

if __name__ == "__main__":
    # Change to project directory
    os.chdir('/Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/analysis_peak_2025_sonnet45')
    
    df, output_file = run_pattern_discovery()
    
    if df is not None:
        print(f"\n✨ Success! Data ready for analysis.")
    else:
        print(f"\n⚠️  Check error message above.")

