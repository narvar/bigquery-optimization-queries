#!/usr/bin/env python3
"""
Complete production cost analysis for all 7 Monitor base tables
Generates individual detailed reports for each table
"""

from pathlib import Path
from google.cloud import bigquery
import pandas as pd
from datetime import datetime

def main():
    print("="*80)
    print("Monitor Production Cost Analysis - All Base Tables")
    print("="*80)
    print()
    print("Analyzing 7 base tables:")
    print("  1. monitor_base.shipments (known: $200,957/year)")
    print("  2. monitor_base.orders (NEW)")
    print("  3. return_insights_base.return_item_details (NEW)")
    print("  4. reporting.return_rate_agg (NEW)")
    print("  5. monitor_base.tnt_benchmarks_latest (NEW)")
    print("  6. monitor_base.ft_benchmarks_latest (NEW)")
    print("  7. monitor_base.carrier_config (NEW)")
    print()
    print("Time Periods: Peak_2024_2025 (3 months) + Baseline_2025_Sep_Oct (2 months)")
    print("Total: 5 months → Annualize by × (12/5) = × 2.4")
    print()
    
    client = bigquery.Client(project='narvar-data-lake')
    
    query_file = Path('../queries/monitor_total_cost/06_all_base_tables_production_analysis.sql')
    with open(query_file, 'r') as f:
        query = f.read()
    
    print("Executing audit log search...")
    query_job = client.query(query)
    results = query_job.result()
    
    print(f"✅ Query complete")
    print(f"Bytes processed: {query_job.total_bytes_processed:,} ({query_job.total_bytes_processed/1024**3:.2f} GB)")
    print(f"Cost: ${(query_job.total_bytes_billed/1024**4)*6.25:.4f}")
    print(f"ETL operations found: {results.total_rows:,}")
    print()
    
    if results.total_rows == 0:
        print("⚠️  NO ETL OPERATIONS FOUND in the specified periods")
        print("Check: Are table names correct? Do we have audit access?")
        return None
    
    # Convert to DataFrame
    df = results.to_dataframe()
    
    # Filter to production only (exclude QA, test, tmp)
    df_prod = df[
        ~df['full_table_name'].str.contains('qa', case=False, na=False) &
        ~df['full_table_name'].str.contains('test', case=False, na=False) &
        ~df['full_table_name'].str.contains('tmp', case=False, na=False)
    ].copy()
    
    print(f"Production operations only: {len(df_prod)} (excluded {len(df) - len(df_prod)} QA/test/tmp)")
    print()
    
    # Save detailed results
    output_file = Path('../results/monitor_total_cost/all_base_tables_production_detailed.csv')
    df_prod.to_csv(output_file, index=False)
    print(f"✅ Detailed results saved to: {output_file}")
    print()
    
    # Aggregate by table
    summary = df_prod.groupby('full_table_name').agg({
        'total_jobs_5_months': 'sum',
        'annual_slot_hours': 'sum',
        'annual_cost_usd': 'sum',
        'avg_jobs_per_day': 'mean',
        'principal_email': lambda x: list(x.unique()),
        'etl_source_type': lambda x: list(x.unique()),
        'statement_type': lambda x: list(x.unique())
    }).reset_index()
    
    summary = summary.sort_values('annual_cost_usd', ascending=False)
    
    # Display summary
    print("="*80)
    print("PRODUCTION COST SUMMARY BY TABLE")
    print("="*80)
    print()
    
    total_production_cost = 0
    
    for idx, row in summary.iterrows():
        print(f"{'='*80}")
        print(f"{idx+1}. {row['full_table_name']}")
        print(f"{'='*80}")
        print(f"  Annual Cost:        ${row['annual_cost_usd']:,.2f}")
        print(f"  Annual Slot-Hours:  {row['annual_slot_hours']:,.0f}")
        print(f"  ETL Jobs (5 months): {row['total_jobs_5_months']:,}")
        print(f"  Avg Jobs/Day:       {row['avg_jobs_per_day']:.1f}")
        print(f"  Statement Types:    {', '.join(row['statement_type'])}")
        print(f"  ETL Sources:        {', '.join(row['etl_source_type'])}")
        print(f"  Service Accounts:   {len(row['principal_email'])} account(s)")
        for sa in row['principal_email'][:3]:
            print(f"    - {sa}")
        if len(row['principal_email']) > 3:
            print(f"    - ... and {len(row['principal_email'])-3} more")
        print()
        
        total_production_cost += row['annual_cost_usd']
    
    # Platform total
    consumption_cost = 6418  # From MONITOR_2025_ANALYSIS_REPORT
    grand_total = total_production_cost + consumption_cost
    
    print("="*80)
    print("PLATFORM TOTAL")
    print("="*80)
    print(f"  Total Production Cost:  ${total_production_cost:,.2f}/year")
    print(f"  Consumption Cost:       ${consumption_cost:,}/year")
    print(f"  {'─'*60}")
    print(f"  GRAND TOTAL:            ${grand_total:,.2f}/year")
    print()
    print(f"  vs Conservative Estimate: $207,375/year")
    print(f"  Multiplier: {grand_total/207375:.2f}x")
    print()
    
    # Save summary
    summary_file = Path('../results/monitor_total_cost/production_cost_summary.csv')
    summary.to_csv(summary_file, index=False)
    print(f"✅ Summary saved to: {summary_file}")
    print()
    
    return df_prod, summary

if __name__ == '__main__':
    try:
        df_prod, summary = main()
        
        print("="*80)
        print("✅ ANALYSIS COMPLETE")
        print("="*80)
        print()
        print("Next: Generate individual detailed reports for each table")
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()

