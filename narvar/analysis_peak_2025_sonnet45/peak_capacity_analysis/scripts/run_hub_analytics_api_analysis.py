#!/usr/bin/env python3
"""
Run Hub Analytics API performance analysis.
Analyzes REAL Hub analytics dashboards (analytics-api-bigquery-access service account).
Cost: ~$0.018 (3.74 GB scan)
"""

import os
from google.cloud import bigquery
from datetime import datetime
import pandas as pd

def run_hub_analytics_analysis():
    """Execute Hub Analytics API performance analysis."""
    
    # Initialize BigQuery client
    client = bigquery.Client()
    
    # Read query from file
    query_file = 'queries/phase2_consumer_analysis/hub_analytics_api_performance.sql'
    print(f"\n📂 Reading query from: {query_file}")
    
    with open(query_file, 'r') as f:
        query = f.read()
    
    print(f"\n🚀 Executing Hub Analytics API analysis...")
    print(f"💰 Estimated cost: ~$0.018 (3.74 GB scan)")
    print(f"📊 Analyzing ANALYTICS_API consumer subcategory (real Hub analytics)")
    print(f"⏱️  This should complete in 30-60 seconds...\n")
    
    # Run query
    try:
        start_time = datetime.now()
        df = client.query(query).to_dataframe()
        duration = (datetime.now() - start_time).total_seconds()
        
        print(f"✅ Query completed successfully in {duration:.1f} seconds!")
        print(f"📊 Results: {len(df)} period(s) analyzed\n")
        
        # Save to CSV
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = f'results/hub_analytics_api_performance_{timestamp}.csv'
        
        df.to_csv(output_file, index=False)
        print(f"💾 Results saved to: {output_file}")
        
        # Print comprehensive summary
        print(f"\n" + "="*80)
        print(f"HUB ANALYTICS API (REAL HUB) - PERFORMANCE SUMMARY")
        print(f"="*80)
        
        # Overall statistics
        total_queries = df['total_queries'].sum()
        print(f"\n📈 Dataset Overview:")
        print(f"   Total Hub Analytics queries: {total_queries:,}")
        print(f"   Unique users: {df['unique_users'].sum()}")
        print(f"   Unique projects: {df['unique_projects'].sum()}")
        
        # By period
        print(f"\n📅 By Period:")
        for _, row in df.iterrows():
            print(f"   {row['analysis_period_label']}:")
            print(f"      Queries: {row['total_queries']:,}")
            print(f"      Avg per day: {row['total_queries']/row['days_in_period']:.0f}")
            print(f"      Cost: ${row['total_cost_usd']:,.2f}")
            print(f"      QoS violations: {row['qos_violations']:,} ({row['violation_pct']:.1f}%)")
        
        # Cost breakdown
        print(f"\n💰 Cost Metrics:")
        total_cost = df['total_cost_usd'].sum()
        reserved_cost = df['cost_reserved_shared'].sum()
        on_demand_cost = df['cost_on_demand'].sum()
        
        print(f"   Total Cost: ${total_cost:,.2f}")
        print(f"   RESERVED: ${reserved_cost:,.2f} ({reserved_cost/total_cost*100:.1f}%)")
        print(f"   ON_DEMAND: ${on_demand_cost:,.2f} ({on_demand_cost/total_cost*100:.1f}%)")
        print(f"   Avg Cost per Query: ${df['avg_cost_per_query_usd'].mean():.6f}")
        print(f"   Monthly Average: ${total_cost/12:.2f}")
        
        # Reservation breakdown
        print(f"\n🏢 Reservation Usage:")
        total_reserved = df['queries_reserved_shared'].sum()
        total_on_demand = df['queries_on_demand'].sum()
        total_pipeline = df['queries_reserved_pipeline'].sum()
        
        if total_reserved > 0:
            print(f"   RESERVED_SHARED_POOL: {total_reserved:,} queries ({total_reserved/total_queries*100:.1f}%)")
        if total_on_demand > 0:
            print(f"   ON_DEMAND: {total_on_demand:,} queries ({total_on_demand/total_queries*100:.1f}%)")
        if total_pipeline > 0:
            print(f"   RESERVED_PIPELINE: {total_pipeline:,} queries ({total_pipeline/total_queries*100:.1f}%)")
        
        # QoS Analysis
        print(f"\n⚠️  Quality of Service Metrics:")
        total_violations = df['qos_violations'].sum()
        overall_violation_rate = total_violations / total_queries * 100
        print(f"   Total QoS Violations: {total_violations:,} ({overall_violation_rate:.2f}%)")
        print(f"   Avg Execution Time: {df['avg_execution_seconds'].mean():.2f}s")
        print(f"   Avg P95 Execution: {df['p95_execution_seconds'].mean():.2f}s")
        print(f"   Avg P99 Execution: {df['p99_execution_seconds'].mean():.2f}s")
        
        # QoS by reservation
        if not df['violation_pct_reserved'].isna().all():
            avg_reserved_viol = df['violation_pct_reserved'].mean()
            print(f"\n📊 QoS by Reservation Type:")
            print(f"   RESERVED: {avg_reserved_viol:.2f}% violations")
            if not df['violation_pct_on_demand'].isna().all():
                avg_on_demand_viol = df['violation_pct_on_demand'].mean()
                print(f"   ON_DEMAND: {avg_on_demand_viol:.2f}% violations")
        
        # Query complexity
        print(f"\n🔧 Query Complexity:")
        total_joins = df['queries_with_joins'].sum()
        total_group_by = df['queries_with_group_by'].sum()
        total_cte = df['queries_with_cte'].sum()
        total_window = df['queries_with_window_functions'].sum()
        
        print(f"   Has JOINs: {total_joins:,} ({total_joins/total_queries*100:.1f}%)")
        print(f"   Has GROUP BY: {total_group_by:,} ({total_group_by/total_queries*100:.1f}%)")
        print(f"   Has CTEs: {total_cte:,} ({total_cte/total_queries*100:.1f}%)")
        print(f"   Has Window Functions: {total_window:,} ({total_window/total_queries*100:.1f}%)")
        print(f"   Avg Query Length: {df['avg_query_length'].mean():.0f} characters")
        
        # Resource consumption
        print(f"\n⚙️  Resource Consumption:")
        total_slot_hours = df['total_slot_hours'].sum()
        total_tb = df['total_tb_scanned'].sum()
        print(f"   Total Slot-Hours: {total_slot_hours:,.2f}")
        print(f"   Total TB Scanned: {total_tb:,.2f}")
        print(f"   Avg GB per Query: {df['avg_gb_per_query'].mean():.2f}")
        print(f"   Avg Concurrent Slots: {df['avg_concurrent_slots'].mean():.1f}")
        
        print(f"\n" + "="*80)
        print(f"\n✅ Hub Analytics API analysis complete!")
        print(f"📁 Detailed results in: {output_file}")
        
        print(f"\n📊 Comparison to Looker (consumer_subcategory='HUB'):")
        print(f"   Looker: 235,977 queries, $148/month")
        print(f"   Hub Analytics API: {total_queries:,} queries, ${total_cost/12:.2f}/month")
        
        print(f"\n🎯 Next Steps:")
        print(f"   1. Compare Hub Analytics API vs Looker costs and usage")
        print(f"   2. Identify optimization opportunities for Hub Analytics")
        print(f"   3. Review reservation assignment (RESERVED vs ON_DEMAND)")
        print(f"   4. Create comprehensive Hub Analytics report")
        
        return df, output_file
        
    except Exception as e:
        print(f"\n❌ Query failed: {str(e)}")
        import traceback
        traceback.print_exc()
        return None, None

if __name__ == "__main__":
    # Change to project directory
    os.chdir('/Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/analysis_peak_2025_sonnet45')
    
    df, output_file = run_hub_analytics_analysis()
    
    if df is not None:
        print(f"\n✨ Analysis complete! Ready for comparison with Looker.")
    else:
        print(f"\n⚠️  Check error message above.")

