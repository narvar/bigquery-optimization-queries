#!/usr/bin/env python3
"""
Run full 2025 Hub analysis with improved retailer extraction.
Cost: ~$0.85 (173.75 GB scan)
"""

import os
from google.cloud import bigquery
from datetime import datetime
import pandas as pd

def run_full_hub_analysis():
    """Execute full Hub analysis and save results."""
    
    # Initialize BigQuery client
    client = bigquery.Client()
    
    # Read query from file
    query_file = 'queries/phase2_consumer_analysis/hub_full_2025_analysis.sql'
    print(f"\n📂 Reading query from: {query_file}")
    
    with open(query_file, 'r') as f:
        query = f.read()
    
    print(f"\n🚀 Executing full 2025 Hub analysis...")
    print(f"⚠️  Estimated cost: ~$0.85 (173.75 GB scan)")
    print(f"⏱️  This may take 2-3 minutes...\n")
    
    # Run query
    try:
        start_time = datetime.now()
        df = client.query(query).to_dataframe()
        duration = (datetime.now() - start_time).total_seconds()
        
        print(f"✅ Query completed successfully in {duration:.1f} seconds!")
        print(f"📊 Results: {len(df)} Hub queries analyzed\n")
        
        # Save to CSV
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = f'results/hub_full_2025_analysis_{timestamp}.csv'
        
        df.to_csv(output_file, index=False)
        print(f"💾 Results saved to: {output_file}")
        
        # Print comprehensive summary
        print(f"\n" + "="*80)
        print(f"FULL 2025 HUB ANALYSIS SUMMARY")
        print(f"="*80)
        
        # Overall statistics
        print(f"\n📈 Dataset Overview:")
        print(f"   Total Hub queries: {len(df):,}")
        print(f"   Date range: {df['start_time'].min()} to {df['start_time'].max()}")
        
        # By period
        print(f"\n📅 By Period:")
        for period, count in df['analysis_period_label'].value_counts().sort_index().items():
            print(f"   {period}: {count:,} queries")
        
        # Retailer attribution success
        print(f"\n🎯 Retailer Attribution Results:")
        total = len(df)
        
        quality_dist = df['attribution_quality'].value_counts()
        for quality, count in quality_dist.items():
            pct = count / total * 100
            print(f"   {quality}: {count:,} ({pct:.1f}%)")
        
        # Calculate overall success rate
        successful = df['attribution_quality'].isin(['HIGH', 'MEDIUM']).sum()
        success_rate = successful / total * 100
        print(f"\n   ✅ Overall Success Rate: {success_rate:.1f}%")
        print(f"   🎲 Aggregate Dashboards: {(df['attribution_quality'] == 'AGGREGATE').sum():,}")
        print(f"   ❌ Failed Extractions: {(df['attribution_quality'] == 'FAILED').sum():,}")
        
        # Extraction methods
        print(f"\n🔍 Extraction Methods Used:")
        for method, count in df['extraction_method'].value_counts().items():
            pct = count / total * 100
            print(f"   {method}: {count:,} ({pct:.1f}%)")
        
        # Top retailers
        print(f"\n👥 Top 20 Retailers (by query volume):")
        top_retailers = df[df['attribution_quality'].isin(['HIGH', 'MEDIUM'])]['retailer_attribution'].value_counts().head(20)
        for idx, (retailer, count) in enumerate(top_retailers.items(), 1):
            print(f"   {idx:2d}. {retailer}: {count} queries")
        
        # QoS Analysis
        print(f"\n⚠️  Quality of Service Metrics:")
        violations = df['is_qos_violation'].sum()
        violation_rate = violations / total * 100
        print(f"   QoS Violations: {violations:,} ({violation_rate:.1f}%)")
        print(f"   Avg Execution Time: {df['execution_time_seconds'].mean():.1f}s")
        print(f"   P50 Execution Time: {df['execution_time_seconds'].median():.1f}s")
        print(f"   P95 Execution Time: {df['execution_time_seconds'].quantile(0.95):.1f}s")
        print(f"   P99 Execution Time: {df['execution_time_seconds'].quantile(0.99):.1f}s")
        print(f"   Max Execution Time: {df['execution_time_seconds'].max():.1f}s")
        
        # QoS by period
        print(f"\n📊 QoS Violation Rate by Period:")
        for period in df['analysis_period_label'].unique():
            period_df = df[df['analysis_period_label'] == period]
            viols = period_df['is_qos_violation'].sum()
            total_period = len(period_df)
            rate = viols / total_period * 100
            print(f"   {period}: {viols}/{total_period} ({rate:.1f}%)")
        
        # Cost Analysis
        print(f"\n💰 Cost Metrics:")
        total_cost = df['estimated_slot_cost_usd'].sum()
        total_slot_hours = df['slot_hours'].sum()
        total_gb = df['gb_scanned'].sum()
        print(f"   Total Cost: ${total_cost:,.2f}")
        print(f"   Total Slot-Hours: {total_slot_hours:,.2f}")
        print(f"   Total GB Scanned: {total_gb:,.2f}")
        print(f"   Avg Cost per Query: ${df['estimated_slot_cost_usd'].mean():.4f}")
        print(f"   Avg Slot-Hours per Query: {df['slot_hours'].mean():.4f}")
        
        # Top 10 most expensive queries
        print(f"\n💸 Top 10 Most Expensive Queries:")
        expensive = df.nlargest(10, 'estimated_slot_cost_usd')[['job_id', 'retailer_attribution', 'estimated_slot_cost_usd', 'execution_time_seconds', 'is_qos_violation']]
        for idx, row in expensive.iterrows():
            qos_flag = "🚨" if row['is_qos_violation'] else "✅"
            print(f"   {qos_flag} ${row['estimated_slot_cost_usd']:.4f} | {row['execution_time_seconds']:.0f}s | {row['retailer_attribution']}")
        
        # Query characteristics
        print(f"\n🔧 Query Complexity:")
        print(f"   Has JOINs: {df['has_joins'].sum()} ({df['has_joins'].sum()/total*100:.1f}%)")
        print(f"   Has GROUP BY: {df['has_group_by'].sum()} ({df['has_group_by'].sum()/total*100:.1f}%)")
        print(f"   Has CTEs: {df['has_cte'].sum()} ({df['has_cte'].sum()/total*100:.1f}%)")
        print(f"   Has Window Functions: {df['has_window_functions'].sum()} ({df['has_window_functions'].sum()/total*100:.1f}%)")
        print(f"   Avg Query Length: {df['query_length'].mean():.0f} characters")
        
        # Temporal patterns
        print(f"\n⏰ Usage Patterns:")
        print(f"   Peak Hour: {df['hour_of_day'].mode().values[0]}:00")
        print(f"   Peak Day: {df['day_name'].mode().values[0]}")
        
        print(f"\n" + "="*80)
        print(f"\n✅ Full Hub analysis complete!")
        print(f"📁 Detailed results in: {output_file}")
        
        # Generate summary by retailer
        print(f"\n📊 Generating retailer-level summary...")
        retailer_summary = df[df['attribution_quality'].isin(['HIGH', 'MEDIUM'])].groupby(['analysis_period_label', 'retailer_attribution']).agg({
            'job_id': 'count',
            'execution_time_seconds': ['mean', 'median', lambda x: x.quantile(0.95)],
            'slot_hours': 'sum',
            'estimated_slot_cost_usd': 'sum',
            'is_qos_violation': ['sum', lambda x: x.sum()/len(x)*100]
        }).round(2)
        
        retailer_summary.columns = ['_'.join(col).strip('_') for col in retailer_summary.columns.values]
        retailer_summary.rename(columns={
            'job_id_count': 'queries',
            'execution_time_seconds_mean': 'avg_exec_s',
            'execution_time_seconds_median': 'median_exec_s',
            'execution_time_seconds_<lambda>': 'p95_exec_s',
            'slot_hours_sum': 'total_slot_hours',
            'estimated_slot_cost_usd_sum': 'total_cost_usd',
            'is_qos_violation_sum': 'qos_violations',
            'is_qos_violation_<lambda>': 'violation_rate_pct'
        }, inplace=True)
        
        retailer_file = f'results/hub_retailer_summary_{timestamp}.csv'
        retailer_summary.to_csv(retailer_file)
        print(f"💾 Retailer summary saved to: {retailer_file}")
        
        print(f"\n🎯 Next Steps:")
        print(f"   1. Review retailer-level metrics for optimization targets")
        print(f"   2. Identify top QoS violators (retailers + queries)")
        print(f"   3. Analyze cost outliers")
        print(f"   4. Create visualization notebook")
        print(f"   5. Generate executive summary report")
        
        return df, output_file
        
    except Exception as e:
        print(f"\n❌ Query failed: {str(e)}")
        import traceback
        traceback.print_exc()
        return None, None

if __name__ == "__main__":
    # Change to project directory
    os.chdir('/Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/analysis_peak_2025_sonnet45')
    
    df, output_file = run_full_hub_analysis()
    
    if df is not None:
        print(f"\n✨ Analysis complete! Ready for visualization and reporting.")
    else:
        print(f"\n⚠️  Check error message above.")

