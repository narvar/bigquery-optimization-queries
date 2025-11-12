#!/usr/bin/env python3
"""
Check estimated BigQuery query cost via dry run.
Usage: python check_query_cost.py <query_file.sql>
"""

import sys
from google.cloud import bigquery

def check_query_cost(query_file_path):
    """Perform dry run to estimate query cost."""
    
    # Read query from file
    with open(query_file_path, 'r') as f:
        query = f.read()
    
    # Initialize BigQuery client
    client = bigquery.Client()
    
    # Configure dry run
    job_config = bigquery.QueryJobConfig(dry_run=True, use_query_cache=False)
    
    # Run dry run
    print(f"\n🔍 Checking query cost for: {query_file_path}\n")
    print("Running dry run...")
    
    try:
        query_job = client.query(query, job_config=job_config)
        
        # Get bytes processed
        bytes_processed = query_job.total_bytes_processed
        gb_processed = bytes_processed / (1024**3)
        tb_processed = bytes_processed / (1024**4)
        
        # Estimate cost (BigQuery on-demand: $5 per TB for analysis queries)
        estimated_cost = tb_processed * 5.0
        
        # Display results
        print(f"✅ Dry run successful!\n")
        print(f"📊 Estimated scan:")
        print(f"   - Bytes:      {bytes_processed:,}")
        print(f"   - Gigabytes:  {gb_processed:,.2f} GB")
        print(f"   - Terabytes:  {tb_processed:,.4f} TB")
        print(f"\n💰 Estimated cost:")
        print(f"   - ${estimated_cost:.4f} (on-demand pricing: $5/TB)")
        
        # Warning if over 10GB
        if gb_processed > 10:
            print(f"\n⚠️  WARNING: Query will scan {gb_processed:.2f} GB (>10GB threshold)")
        else:
            print(f"\n✅ Query scans {gb_processed:.2f} GB (within acceptable range)")
        
        return bytes_processed, estimated_cost
        
    except Exception as e:
        print(f"❌ Dry run failed: {str(e)}")
        return None, None

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python check_query_cost.py <query_file.sql>")
        sys.exit(1)
    
    query_file = sys.argv[1]
    check_query_cost(query_file)

