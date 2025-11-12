#!/usr/bin/env python3
"""
Analyze Monitor retailer performance with reservation breakdown.
"""

import pandas as pd
import os

def analyze_reservations():
    """Analyze reservation usage per retailer."""
    
    # Load results
    results_file = 'results/monitor_retailer_performance_20251112_145504.csv'
    print(f"\n📂 Loading results from: {results_file}\n")
    
    df = pd.read_csv(results_file)
    
    print("="*80)
    print("MONITOR RETAILER RESERVATION ANALYSIS")
    print("="*80)
    
    # Overall reservation distribution (Peak period)
    peak_df = df[df['analysis_period_label'] == 'Peak_2024_2025'].copy()
    
    print(f"\n📊 Reservation Distribution (Peak_2024_2025):")
    print(f"   Total retailers: {len(peak_df)}")
    
    # Count retailers by primary reservation
    for res_type in ['RESERVED_SHARED_POOL', 'ON_DEMAND', 'RESERVED_PIPELINE', 'UNKNOWN']:
        count = (peak_df['primary_reservation_type'] == res_type).sum()
        if count > 0:
            pct = count / len(peak_df) * 100
            print(f"   {res_type}: {count} retailers ({pct:.1f}%)")
    
    # Top retailers using ON_DEMAND
    print(f"\n💰 Top Retailers Using ON_DEMAND (Peak_2024_2025):")
    on_demand_retailers = peak_df[peak_df['queries_on_demand'] > 0].nlargest(10, 'cost_on_demand')
    for _, row in on_demand_retailers.iterrows():
        on_demand_pct = row['queries_on_demand'] / row['total_queries'] * 100
        print(f"   {row['retailer_moniker']:30s} | ${row['cost_on_demand']:8.2f} | {row['queries_on_demand']:5,}/{row['total_queries']:6,} ({on_demand_pct:4.1f}%)")
    
    # Top retailers using RESERVED_SHARED_POOL
    print(f"\n🏢 Top Retailers Using RESERVED_SHARED_POOL (Peak_2024_2025):")
    reserved_retailers = peak_df[peak_df['queries_on_reserved_shared'] > 0].nlargest(10, 'cost_reserved_shared')
    for _, row in reserved_retailers.iterrows():
        reserved_pct = row['queries_on_reserved_shared'] / row['total_queries'] * 100
        print(f"   {row['retailer_moniker']:30s} | ${row['cost_reserved_shared']:8.2f} | {row['queries_on_reserved_shared']:5,}/{row['total_queries']:6,} ({reserved_pct:4.1f}%)")
    
    # Cost breakdown summary
    print(f"\n💰 Total Cost Breakdown (Peak_2024_2025):")
    total_cost = peak_df['total_cost_usd'].sum()
    reserved_shared_cost = peak_df['cost_reserved_shared'].sum()
    reserved_pipeline_cost = peak_df['cost_reserved_pipeline'].sum()
    on_demand_cost = peak_df['cost_on_demand'].sum()
    
    print(f"   Total: ${total_cost:,.2f}")
    print(f"   RESERVED_SHARED_POOL: ${reserved_shared_cost:,.2f} ({reserved_shared_cost/total_cost*100:.1f}%)")
    print(f"   RESERVED_PIPELINE: ${reserved_pipeline_cost:,.2f} ({reserved_pipeline_cost/total_cost*100:.1f}%)")
    print(f"   ON_DEMAND: ${on_demand_cost:,.2f} ({on_demand_cost/total_cost*100:.1f}%)")
    
    # QoS by reservation type
    print(f"\n⚠️  QoS Performance by Reservation Type (Peak_2024_2025):")
    
    # Calculate weighted averages
    total_reserved_shared_violations = peak_df['qos_violations'].where(peak_df['queries_on_reserved_shared'] > 0, 0).sum()
    total_reserved_shared_queries = peak_df['queries_on_reserved_shared'].sum()
    
    total_on_demand_violations = peak_df['qos_violations'].where(peak_df['queries_on_demand'] > 0, 0).sum()
    total_on_demand_queries = peak_df['queries_on_demand'].sum()
    
    if total_reserved_shared_queries > 0:
        reserved_viol_rate = (peak_df['violation_pct_reserved_shared'] * peak_df['queries_on_reserved_shared']).sum() / total_reserved_shared_queries
        print(f"   RESERVED_SHARED_POOL: {reserved_viol_rate:.2f}% violation rate")
    
    if total_on_demand_queries > 0:
        on_demand_viol_rate = (peak_df['violation_pct_on_demand'] * peak_df['queries_on_demand']).sum() / total_on_demand_queries
        print(f"   ON_DEMAND: {on_demand_viol_rate:.2f}% violation rate")
    
    # Export reservation breakdown
    print(f"\n💾 Exporting reservation breakdown...")
    reservation_breakdown = peak_df[['retailer_moniker', 'primary_reservation_type', 'total_queries',
                                      'queries_on_reserved_shared', 'queries_on_demand',
                                      'cost_reserved_shared', 'cost_on_demand', 'total_cost_usd',
                                      'violation_pct', 'violation_pct_reserved_shared', 'violation_pct_on_demand']].copy()
    
    reservation_file = 'results/monitor_reservation_breakdown_20251112.csv'
    reservation_breakdown.to_csv(reservation_file, index=False)
    print(f"   Saved to: {reservation_file}")
    
    print(f"\n" + "="*80)
    print(f"\n✅ Reservation analysis complete!")
    
    return df, peak_df

if __name__ == "__main__":
    os.chdir('/Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/analysis_peak_2025_sonnet45')
    
    df, peak_df = analyze_reservations()

