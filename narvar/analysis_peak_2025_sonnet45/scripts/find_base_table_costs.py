#!/usr/bin/env python3
"""
Search audit logs for base table production costs
"""

from pathlib import Path
from google.cloud import bigquery
import pandas as pd

def main():
    print("="*80)
    print("Base Table Production Cost Analysis")
    print("="*80)
    print()
    print("Searching for ETL operations on 3 known base tables:")
    print("  1. reporting.t_return_details (HIGH PRIORITY - 28M rows)")
    print("  2. return_insights_base.return_item_details")
    print("  3. monitor_base.carrier_config")
    print()
    
    client = bigquery.Client(project='narvar-data-lake')
    
    query_file = Path('../queries/monitor_total_cost/05_base_tables_production_costs.sql')
    with open(query_file, 'r') as f:
        query = f.read()
    
    print("Executing audit log search...")
    query_job = client.query(query)
    results = query_job.result()
    
    print(f"Bytes processed: {query_job.total_bytes_processed:,} ({query_job.total_bytes_processed/1024**3:.2f} GB)")
    print(f"Estimated cost: ${(query_job.total_bytes_billed/1024**4)*6.25:.4f}")
    print(f"ETL operations found: {results.total_rows:,}")
    print()
    
    if results.total_rows == 0:
        print("⚠️  NO ETL OPERATIONS FOUND")
        print()
        print("This could mean:")
        print("  1. Tables are populated via streaming inserts (not batch ETL)")
        print("  2. Tables are in different projects we don't have audit access to")
        print("  3. Table names don't match (check spelling/project)")
        print()
        print("Recommendation: Ask Data Engineering team for:")
        print("  - Which DAGs populate these tables?")
        print("  - Estimated production costs?")
        print("  - Data sources and refresh patterns?")
        return None
    
    # Convert to DataFrame
    df = results.to_dataframe()
    
    # Save
    output_file = Path('../results/monitor_total_cost/base_tables_production_costs.csv')
    df.to_csv(output_file, index=False)
    print(f"✅ Results saved to: {output_file}")
    print()
    
    # Analysis
    print("="*80)
    print("PRODUCTION COST SUMMARY")
    print("="*80)
    print()
    
    # Summary by table
    summary = df.groupby('full_table_name').agg({
        'etl_job_count': 'sum',
        'total_slot_hours': 'sum',
        'annual_cost_usd': 'sum',
        'principal_email': lambda x: ', '.join(x.unique()[:3])
    }).reset_index()
    
    summary = summary.sort_values('annual_cost_usd', ascending=False)
    
    print("📊 ANNUAL PRODUCTION COSTS BY TABLE:")
    print()
    for idx, row in summary.iterrows():
        print(f"  {row['full_table_name']}")
        print(f"    Annual Cost: ${row['annual_cost_usd']:,.2f}")
        print(f"    ETL Jobs: {row['etl_job_count']:,}")
        print(f"    Slot-Hours: {row['total_slot_hours']:,.2f}")
        print(f"    Service Accounts: {row['principal_email']}")
        print()
    
    total_new_costs = summary['annual_cost_usd'].sum()
    print(f"💰 TOTAL NEW PRODUCTION COSTS FOUND: ${total_new_costs:,.2f}/year")
    print()
    
    # Updated platform total
    known_costs = 200957  # monitor_base.shipments
    consumption = 6418
    new_total = known_costs + total_new_costs + consumption
    
    print(f"📈 UPDATED PLATFORM COST ESTIMATE:")
    print(f"  monitor_base.shipments: ${known_costs:,}")
    print(f"  New base tables: ${total_new_costs:,.2f}")
    print(f"  Consumption: ${consumption:,}")
    print(f"  {'─'*50}")
    print(f"  TOTAL: ${new_total:,.2f}/year")
    print()
    
    print("="*80)
    
    return df

if __name__ == '__main__':
    try:
        df = main()
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

