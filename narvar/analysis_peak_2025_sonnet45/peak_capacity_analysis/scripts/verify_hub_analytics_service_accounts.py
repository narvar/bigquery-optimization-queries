#!/usr/bin/env python3
"""
Verify that BOTH analytics-api-bigquery-access service accounts are captured.
Checks classification table for ANALYTICS_API queries.
"""

import os
from google.cloud import bigquery
import pandas as pd

def verify_service_accounts():
    """Check which analytics-api service accounts are captured."""
    
    client = bigquery.Client()
    
    query = """
    SELECT
      principal_email,
      COUNT(*) as query_count,
      MIN(start_time) as first_seen,
      MAX(start_time) as last_seen,
      ROUND(SUM(slot_hours), 2) as total_slot_hours,
      ROUND(SUM(estimated_slot_cost_usd), 2) as total_cost,
      COUNT(DISTINCT analysis_period_label) as periods_present
    FROM `narvar-data-lake.query_opt.traffic_classification`
    WHERE consumer_subcategory = 'ANALYTICS_API'
      AND analysis_period_label IN ('Peak_2024_2025', 'Baseline_2025_Sep_Oct')
    GROUP BY principal_email
    ORDER BY query_count DESC
    """
    
    print(f"\n🔍 Checking ANALYTICS_API service accounts...\n")
    
    df = client.query(query).to_dataframe()
    
    print("="*80)
    print("ANALYTICS_API SERVICE ACCOUNTS")
    print("="*80)
    
    print(f"\n📊 Total unique service accounts: {len(df)}\n")
    
    for idx, row in df.iterrows():
        print(f"{idx+1}. {row['principal_email']}")
        print(f"   Queries: {row['query_count']:,}")
        print(f"   Slot-hours: {row['total_slot_hours']:,.2f}")
        print(f"   Cost: ${row['total_cost']:,.2f}")
        print(f"   First seen: {row['first_seen']}")
        print(f"   Last seen: {row['last_seen']}")
        print(f"   Periods: {row['periods_present']}")
        print()
    
    # Check for both expected accounts
    print("="*80)
    print("VERIFICATION")
    print("="*80)
    
    emails = df['principal_email'].tolist()
    
    account1_found = any('analytics-api-bigquery-access@' in email and 'access2' not in email for email in emails)
    account2_found = any('analytics-api-bigquery-access2@' in email for email in emails)
    
    print(f"\n✓ Expected Accounts:")
    print(f"   analytics-api-bigquery-access: {'✅ FOUND' if account1_found else '❌ NOT FOUND'}")
    print(f"   analytics-api-bigquery-access2: {'✅ FOUND' if account2_found else '❌ NOT FOUND'}")
    
    if len(emails) > 0:
        print(f"\n📋 All service accounts captured:")
        for email in emails:
            if 'analytics-api' in email.lower():
                print(f"   ✅ {email}")
            else:
                print(f"   ⚠️  {email} (unexpected - doesn't match 'analytics-api')")
    
    total_queries = df['query_count'].sum()
    total_cost = df['total_cost'].sum()
    
    print(f"\n💰 Combined Totals:")
    print(f"   Total queries: {total_queries:,}")
    print(f"   Total cost: ${total_cost:,.2f}")
    
    if len(df) == 2 and account1_found and account2_found:
        print(f"\n✅ CONFIRMED: Both analytics-api-bigquery-access accounts are captured!")
        
        # Show distribution
        print(f"\n📊 Distribution:")
        for _, row in df.iterrows():
            pct = row['query_count'] / total_queries * 100
            print(f"   {row['principal_email']}: {row['query_count']:,} ({pct:.1f}%)")
    elif not account2_found:
        print(f"\n⚠️  WARNING: analytics-api-bigquery-access2 NOT FOUND!")
        print(f"   Only {len(df)} service account(s) captured")
        print(f"   Pattern may need to be updated to explicitly include '2' suffix")
    
    return df

if __name__ == "__main__":
    os.chdir('/Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/analysis_peak_2025_sonnet45')
    
    df = verify_service_accounts()



