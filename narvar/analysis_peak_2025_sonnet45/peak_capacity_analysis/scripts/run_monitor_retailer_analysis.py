#!/usr/bin/env python3
"""
Run Monitor retailer performance profile analysis.
Analyzes direct retailer API queries (Monitor projects) by retailer for 2025 periods.
Cost: ~$0.016 (3.20 GB scan)
"""

import os
from google.cloud import bigquery
from datetime import datetime
import pandas as pd

def run_monitor_analysis():
    """Execute Monitor retailer performance analysis."""
    
    # Initialize BigQuery client
    client = bigquery.Client()
    
    # Read query from file
    query_file = 'queries/phase2_consumer_analysis/monitor_retailer_performance_profile.sql'
    print(f"\n📂 Reading query from: {query_file}")
    
    with open(query_file, 'r') as f:
        query = f.read()
    
    print(f"\n🚀 Executing Monitor retailer performance analysis...")
    print(f"💰 Estimated cost: ~$0.016 (3.20 GB scan)")
    print(f"⏱️  This should complete in 30-60 seconds...\n")
    
    # Run query
    try:
        start_time = datetime.now()
        df = client.query(query).to_dataframe()
        duration = (datetime.now() - start_time).total_seconds()
        
        print(f"✅ Query completed successfully in {duration:.1f} seconds!")
        print(f"📊 Results: {len(df)} retailer-period combinations analyzed\n")
        
        # Save to CSV
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = f'results/monitor_retailer_performance_{timestamp}.csv'
        
        df.to_csv(output_file, index=False)
        print(f"💾 Results saved to: {output_file}")
        
        # Print comprehensive summary
        print(f"\n" + "="*80)
        print(f"MONITOR RETAILER PERFORMANCE SUMMARY")
        print(f"="*80)
        
        # Overall statistics
        print(f"\n📈 Dataset Overview:")
        total_queries = df['total_queries'].sum()
        unique_retailers = df['retailer_moniker'].nunique()
        print(f"   Total Monitor queries: {total_queries:,}")
        print(f"   Unique retailers: {unique_retailers}")
        
        # By period
        print(f"\n📅 By Period:")
        for period in df['analysis_period_label'].unique():
            period_df = df[df['analysis_period_label'] == period]
            period_queries = period_df['total_queries'].sum()
            period_retailers = period_df['retailer_moniker'].nunique()
            print(f"   {period}:")
            print(f"      Queries: {period_queries:,}")
            print(f"      Retailers: {period_retailers}")
        
        # Top 20 retailers by query volume (latest period)
        print(f"\n👥 Top 20 Retailers by Query Volume (Peak_2024_2025):")
        peak_df = df[df['analysis_period_label'] == 'Peak_2024_2025'].copy()
        if len(peak_df) > 0:
            top_20_volume = peak_df.nlargest(20, 'total_queries')[['retailer_moniker', 'total_queries', 'total_slot_hours', 'total_cost_usd', 'violation_pct']]
            for idx, row in top_20_volume.iterrows():
                print(f"   {row['retailer_moniker']:30s} | {row['total_queries']:6,} queries | {row['total_slot_hours']:8.2f} slot-hrs | ${row['total_cost_usd']:7.2f} | {row['violation_pct']:4.1f}% violations")
        
        # Top 20 retailers by slot consumption
        print(f"\n💰 Top 20 Retailers by Slot Consumption (Peak_2024_2025):")
        if len(peak_df) > 0:
            top_20_slots = peak_df.nlargest(20, 'total_slot_hours')[['retailer_moniker', 'total_slot_hours', 'total_cost_usd', 'total_queries', 'avg_execution_seconds']]
            for idx, row in top_20_slots.iterrows():
                print(f"   {row['retailer_moniker']:30s} | {row['total_slot_hours']:8.2f} slot-hrs | ${row['total_cost_usd']:7.2f} | {row['total_queries']:6,} queries | {row['avg_execution_seconds']:6.2f}s avg")
        
        # QoS Analysis
        print(f"\n⚠️  Quality of Service Metrics:")
        total_violations = df['qos_violations'].sum()
        overall_violation_rate = total_violations / total_queries * 100
        print(f"   Total QoS Violations: {total_violations:,} ({overall_violation_rate:.2f}%)")
        print(f"   Avg Execution Time: {df['avg_execution_seconds'].mean():.2f}s")
        print(f"   Avg P95 Execution: {df['p95_execution_seconds'].mean():.2f}s")
        
        # QoS by period
        print(f"\n📊 QoS Violation Rate by Period:")
        for period in df['analysis_period_label'].unique():
            period_df = df[df['analysis_period_label'] == period]
            period_violations = period_df['qos_violations'].sum()
            period_total = period_df['total_queries'].sum()
            period_rate = period_violations / period_total * 100
            print(f"   {period}: {period_violations:,}/{period_total:,} ({period_rate:.2f}%)")
        
        # Top 10 retailers with highest QoS violations
        print(f"\n🚨 Top 10 Retailers by QoS Violation Rate (Peak_2024_2025):")
        if len(peak_df) > 0:
            # Only retailers with significant query volume (>100 queries)
            significant_retailers = peak_df[peak_df['total_queries'] >= 100].copy()
            if len(significant_retailers) > 0:
                top_10_violations = significant_retailers.nlargest(10, 'violation_pct')[['retailer_moniker', 'violation_pct', 'qos_violations', 'total_queries', 'p95_execution_seconds']]
                for idx, row in top_10_violations.iterrows():
                    print(f"   {row['retailer_moniker']:30s} | {row['violation_pct']:5.1f}% | {row['qos_violations']:4,}/{row['total_queries']:6,} | P95: {row['p95_execution_seconds']:6.1f}s")
        
        # Cost Analysis
        print(f"\n💰 Cost Metrics:")
        total_cost = df['total_cost_usd'].sum()
        total_slot_hours = df['total_slot_hours'].sum()
        print(f"   Total Monitor Cost: ${total_cost:,.2f}")
        print(f"   Total Slot-Hours: {total_slot_hours:,.2f}")
        print(f"   Avg Cost per Query: ${df['avg_cost_per_query_usd'].mean():.6f}")
        print(f"   Avg Slot-Hours per Query: {df['avg_slot_hours_per_query'].mean():.6f}")
        
        # Query complexity
        print(f"\n🔧 Query Complexity (Overall):")
        total_with_joins = df['queries_with_joins'].sum()
        total_with_group_by = df['queries_with_group_by'].sum()
        total_with_cte = df['queries_with_cte'].sum()
        total_with_window = df['queries_with_window_functions'].sum()
        
        print(f"   Has JOINs: {total_with_joins:,} ({total_with_joins/total_queries*100:.1f}%)")
        print(f"   Has GROUP BY: {total_with_group_by:,} ({total_with_group_by/total_queries*100:.1f}%)")
        print(f"   Has CTEs: {total_with_cte:,} ({total_with_cte/total_queries*100:.1f}%)")
        print(f"   Has Window Functions: {total_with_window:,} ({total_with_window/total_queries*100:.1f}%)")
        print(f"   Avg Query Length: {df['avg_query_length'].mean():.0f} characters")
        
        # Usage patterns
        print(f"\n⏰ Usage Patterns:")
        print(f"   Avg Queries per Day (per retailer): {df['avg_queries_per_day'].mean():.1f}")
        print(f"   Most Active Retailer: {peak_df.nlargest(1, 'avg_queries_per_day')['retailer_moniker'].values[0] if len(peak_df) > 0 else 'N/A'}")
        
        print(f"\n" + "="*80)
        print(f"\n✅ Monitor retailer analysis complete!")
        print(f"📁 Detailed results in: {output_file}")
        
        print(f"\n🎯 Next Steps:")
        print(f"   1. Review top 20 retailers by volume and cost")
        print(f"   2. Identify retailers with high QoS violation rates")
        print(f"   3. Compare Peak vs Baseline trends")
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
    
    df, output_file = run_monitor_analysis()
    
    if df is not None:
        print(f"\n✨ Analysis complete! Ready for visualization and reporting.")
    else:
        print(f"\n⚠️  Check error message above.")

