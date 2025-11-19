#!/usr/bin/env python3
"""
Monitor Total Cost Analysis - Phase 1 Execution
Execute fashionnova table extraction query and save results
"""

import os
import sys
from datetime import datetime
from google.cloud import bigquery
from pathlib import Path

# Add parent directory to path for imports
sys.path.append(str(Path(__file__).parent))

def run_query_and_save(query_file, output_file, project_id='narvar-data-lake'):
    """
    Execute a BigQuery SQL file and save results to CSV
    
    Args:
        query_file: Path to SQL file
        output_file: Path to output CSV file
        project_id: GCP project ID
    """
    print(f"\n{'='*80}")
    print(f"Monitor Total Cost Analysis - Phase 1")
    print(f"{'='*80}\n")
    
    # Initialize BigQuery client
    print(f"Initializing BigQuery client for project: {project_id}")
    client = bigquery.Client(project=project_id)
    
    # Read SQL query
    print(f"\nReading query from: {query_file}")
    with open(query_file, 'r') as f:
        query = f.read()
    
    # Configure query job
    job_config = bigquery.QueryJobConfig(
        use_query_cache=True,
        use_legacy_sql=False
    )
    
    print(f"\n{'='*80}")
    print("EXECUTING QUERY")
    print(f"{'='*80}\n")
    
    # Execute query
    query_job = client.query(query, job_config=job_config)
    
    # Wait for completion and show progress
    print("Query submitted. Waiting for results...")
    print(f"Job ID: {query_job.job_id}")
    
    try:
        # Get results
        results = query_job.result()
        
        # Get job statistics
        total_bytes_processed = query_job.total_bytes_processed
        total_bytes_billed = query_job.total_bytes_billed
        
        print(f"\n{'='*80}")
        print("QUERY COMPLETE")
        print(f"{'='*80}\n")
        print(f"Total bytes processed: {total_bytes_processed:,} ({total_bytes_processed / 1024**3:.2f} GB)")
        print(f"Total bytes billed: {total_bytes_billed:,} ({total_bytes_billed / 1024**3:.2f} GB)")
        print(f"Estimated cost: ${(total_bytes_billed / 1024**4) * 6.25:.4f}")
        print(f"Total rows: {results.total_rows:,}")
        
        # Convert to DataFrame
        import pandas as pd
        df = results.to_dataframe()
        
        # Save to CSV
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        df.to_csv(output_file, index=False)
        print(f"\nResults saved to: {output_file}")
        print(f"Output rows: {len(df):,}")
        print(f"Output columns: {len(df.columns)}")
        
        # Display summary statistics
        print(f"\n{'='*80}")
        print("SUMMARY STATISTICS")
        print(f"{'='*80}\n")
        
        if len(df) > 0:
            # Top 10 tables by slot-hours
            print("\n📊 Top 10 Tables by Slot-Hours:\n")
            top_tables = df.nlargest(10, 'total_slot_hours')[
                ['table_reference', 'reference_count', 'total_slot_hours', 'total_cost_usd', 'table_type']
            ]
            print(top_tables.to_string(index=False))
            
            # Summary metrics
            print(f"\n📈 Overall Metrics:\n")
            print(f"Total unique tables: {len(df)}")
            print(f"Total queries: {df['reference_count'].sum():,}")
            print(f"Total slot-hours: {df['total_slot_hours'].sum():,.2f}")
            print(f"Total cost: ${df['total_cost_usd'].sum():,.2f}")
            print(f"Total TB scanned: {df['total_tb_scanned'].sum():,.2f}")
            
            # Table type breakdown
            print(f"\n🏷️  Table Type Breakdown:\n")
            type_counts = df['table_type'].value_counts()
            for table_type, count in type_counts.items():
                pct = (count / len(df)) * 100
                print(f"  {table_type}: {count} ({pct:.1f}%)")
            
            # monitor_base.shipments check
            monitor_base = df[df['is_monitor_base_shipments'] == True]
            if len(monitor_base) > 0:
                print(f"\n🎯 monitor_base.shipments Usage:\n")
                row = monitor_base.iloc[0]
                print(f"  Reference count: {row['reference_count']:,}")
                print(f"  Slot-hours: {row['total_slot_hours']:,.2f}")
                print(f"  Cost: ${row['total_cost_usd']:,.2f}")
                print(f"  TB scanned: {row['total_tb_scanned']:,.2f}")
        
        print(f"\n{'='*80}")
        print("✅ Phase 1, Step 1 COMPLETE")
        print(f"{'='*80}\n")
        
        return df
        
    except Exception as e:
        print(f"\n❌ ERROR: {str(e)}")
        raise

def main():
    """Main execution"""
    # Get script directory
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    
    # Define paths
    query_file = project_root / 'queries' / 'monitor_total_cost' / '01_extract_referenced_tables.sql'
    output_file = project_root / 'results' / 'monitor_total_cost' / 'fashionnova_referenced_tables.csv'
    
    # Verify query file exists
    if not query_file.exists():
        print(f"❌ ERROR: Query file not found: {query_file}")
        sys.exit(1)
    
    # Execute query
    try:
        df = run_query_and_save(query_file, output_file)
        
        # Validation checks
        print("\n🔍 VALIDATION CHECKS:\n")
        
        total_slot_hours = df['total_slot_hours'].sum()
        expected_slot_hours = 13628  # From MONITOR_2025_ANALYSIS_REPORT
        
        print(f"1. Total slot-hours: {total_slot_hours:,.2f}")
        print(f"   Expected: ~{expected_slot_hours:,}")
        if abs(total_slot_hours - expected_slot_hours) / expected_slot_hours < 0.1:
            print("   ✅ PASS (within 10% of expected)")
        else:
            print(f"   ⚠️  WARNING: {abs(total_slot_hours - expected_slot_hours) / expected_slot_hours * 100:.1f}% deviation")
        
        print(f"\n2. Number of unique tables: {len(df)}")
        if 10 <= len(df) <= 100:
            print("   ✅ PASS (reasonable range: 10-100)")
        else:
            print("   ⚠️  WARNING: Unexpected number of tables")
        
        monitor_base_check = df[df['is_monitor_base_shipments'] == True]
        print(f"\n3. monitor_base.shipments found: {len(monitor_base_check) > 0}")
        if len(monitor_base_check) > 0:
            print("   ✅ PASS")
            if df.iloc[0]['is_monitor_base_shipments']:
                print("   ✅ BONUS: It's the top table by slot-hours!")
        else:
            print("   ⚠️  WARNING: Expected to find monitor_base.shipments")
        
        print(f"\n{'='*80}")
        print("🎉 SUCCESS: Phase 1, Step 1 completed successfully!")
        print(f"{'='*80}\n")
        
    except Exception as e:
        print(f"\n❌ FAILED: {str(e)}")
        sys.exit(1)

if __name__ == '__main__':
    main()

