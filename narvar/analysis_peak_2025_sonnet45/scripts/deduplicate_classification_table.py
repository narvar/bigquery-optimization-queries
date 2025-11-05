#!/usr/bin/env python3
"""
Deduplicate Traffic Classification Table

Purpose: Remove older classification versions, keeping only the latest version for each job_id
Strategy: Recreate table with latest version only (based on classification_version and classification_date)

Usage:
    python deduplicate_classification_table.py --dry-run    # Check what will be kept
    python deduplicate_classification_table.py --execute    # Actually deduplicate
"""

import argparse
from google.cloud import bigquery


PROJECT_ID = "narvar-data-lake"
DATASET_ID = "query_opt"
TABLE_ID = "traffic_classification"
BACKUP_TABLE_ID = "traffic_classification_backup"


# ============================================================================
# DEDUPLICATION QUERY
# ============================================================================

DEDUP_QUERY = f"""
-- Deduplicate traffic_classification table - keep latest version only
-- Strategy: For each job_id, keep the row with highest classification_version and latest classification_date

CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}_deduped`
PARTITION BY DATE(start_time)
CLUSTER BY consumer_category, classification_date
AS

WITH ranked_classifications AS (
  SELECT
    *,
    ROW_NUMBER() OVER(
      PARTITION BY job_id, analysis_period_label
      ORDER BY 
        classification_version DESC,  -- v1.2 > v1.1 > v1.0
        classification_date DESC       -- Latest date wins if same version
    ) AS version_rank
  FROM `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}`
)

SELECT * EXCEPT(version_rank)
FROM ranked_classifications
WHERE version_rank = 1;
"""


STATS_BEFORE_QUERY = f"""
SELECT
  'Before Deduplication' AS status,
  COUNT(*) AS total_rows,
  COUNT(DISTINCT job_id) AS unique_jobs,
  COUNT(*) - COUNT(DISTINCT job_id) AS duplicate_rows,
  ROUND((COUNT(*) - COUNT(DISTINCT job_id)) / COUNT(*) * 100, 2) AS duplicate_pct,
  COUNT(DISTINCT classification_version) AS unique_versions,
  COUNT(DISTINCT analysis_period_label) AS unique_periods
FROM `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}`;
"""


STATS_AFTER_QUERY = f"""
SELECT
  'After Deduplication' AS status,
  COUNT(*) AS total_rows,
  COUNT(DISTINCT job_id) AS unique_jobs,
  COUNT(*) - COUNT(DISTINCT job_id) AS duplicate_rows,
  ROUND((COUNT(*) - COUNT(DISTINCT job_id)) / COUNT(*) * 100, 2) AS duplicate_pct,
  COUNT(DISTINCT classification_version) AS unique_versions,
  COUNT(DISTINCT analysis_period_label) AS unique_periods
FROM `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}_deduped`;
"""


VERSION_SUMMARY_QUERY = f"""
SELECT
  analysis_period_label,
  classification_version,
  COUNT(*) AS row_count,
  COUNT(DISTINCT job_id) AS unique_jobs,
  ROUND(SUM(slot_hours), 0) AS total_slot_hours
FROM `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}`
GROUP BY analysis_period_label, classification_version
ORDER BY analysis_period_label, classification_version;
"""


BACKUP_QUERY = f"""
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET_ID}.{BACKUP_TABLE_ID}`
PARTITION BY DATE(start_time)
CLUSTER BY consumer_category, classification_date
AS
SELECT * FROM `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}`;
"""


REPLACE_QUERY = f"""
-- Replace original table with deduplicated version
DROP TABLE `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}`;

CREATE TABLE `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}`
PARTITION BY DATE(start_time)
CLUSTER BY consumer_category, classification_date
AS
SELECT * FROM `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}_deduped`;

DROP TABLE `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}_deduped`;
"""


# ============================================================================
# EXECUTION FUNCTIONS
# ============================================================================

def print_stats(client: bigquery.Client, query: str, title: str):
    """Print statistics table."""
    print(f"\n{title}")
    print("=" * 100)
    
    result = client.query(query).result()
    row = next(result)
    
    print(f"Total rows:       {row['total_rows']:>12,}")
    print(f"Unique jobs:      {row['unique_jobs']:>12,}")
    print(f"Duplicate rows:   {row['duplicate_rows']:>12,} ({row['duplicate_pct']:.1f}%)")
    print(f"Unique versions:  {row['unique_versions']:>12}")
    print(f"Unique periods:   {row['unique_periods']:>12}")
    print("=" * 100)


def print_version_breakdown(client: bigquery.Client):
    """Print breakdown by period and version."""
    print("\n📊 Current Table: Breakdown by Period and Version")
    print("=" * 120)
    print(f"{'Period':<25} {'Version':<10} {'Rows':>12} {'Unique Jobs':>12} {'Slot Hours':>15}")
    print("-" * 120)
    
    result = client.query(VERSION_SUMMARY_QUERY).result()
    
    for row in result:
        print(f"{row['analysis_period_label']:<25} {row['classification_version']:<10} "
              f"{row['row_count']:>12,} {row['unique_jobs']:>12,} {row['total_slot_hours']:>15,.0f}")
    
    print("=" * 120)


def deduplicate_table(client: bigquery.Client, dry_run: bool = True):
    """Deduplicate the classification table."""
    
    print("\n" + "=" * 100)
    print("🔧 TRAFFIC CLASSIFICATION TABLE DEDUPLICATION")
    print("=" * 100)
    print(f"Project: {PROJECT_ID}")
    print(f"Dataset: {DATASET_ID}")
    print(f"Table: {TABLE_ID}")
    print(f"Mode: {'DRY-RUN (no changes)' if dry_run else 'EXECUTE (will make changes)'}")
    print("=" * 100)
    
    # Show current stats
    print_stats(client, STATS_BEFORE_QUERY, "📊 Current Table Statistics")
    print_version_breakdown(client)
    
    if dry_run:
        print("\n" + "=" * 100)
        print("🔍 DRY-RUN MODE: No changes will be made")
        print("=" * 100)
        print("\nStrategy:")
        print("  1. Keep latest classification_version for each job_id + analysis_period_label")
        print("  2. If same version appears multiple times, keep latest classification_date")
        print("  3. Create deduplicated table: traffic_classification_deduped")
        print("\nTo execute for real, run with: --execute")
        return
    
    # Execute deduplication
    print("\n" + "=" * 100)
    print("⚙️  EXECUTING DEDUPLICATION")
    print("=" * 100)
    
    # Step 1: Create backup
    print("\n1️⃣  Creating backup table...")
    try:
        client.query(BACKUP_QUERY).result()
        print(f"   ✅ Backup created: {BACKUP_TABLE_ID}")
    except Exception as e:
        print(f"   ❌ Backup failed: {e}")
        print("   Aborting to prevent data loss.")
        return
    
    # Step 2: Create deduplicated version
    print("\n2️⃣  Creating deduplicated table...")
    try:
        job = client.query(DEDUP_QUERY)
        result = job.result()
        print(f"   ✅ Deduplicated table created: {TABLE_ID}_deduped")
        print(f"   📊 Bytes processed: {job.total_bytes_processed / 1e9:.2f} GB")
    except Exception as e:
        print(f"   ❌ Deduplication failed: {e}")
        print("   Original table is safe (no changes made)")
        return
    
    # Step 3: Show stats of deduplicated table
    print_stats(client, STATS_AFTER_QUERY, "\n📊 Deduplicated Table Statistics")
    
    # Step 4: Confirm replacement
    print("\n" + "=" * 100)
    print("⚠️  READY TO REPLACE ORIGINAL TABLE")
    print("=" * 100)
    print(f"Backup exists at: {PROJECT_ID}.{DATASET_ID}.{BACKUP_TABLE_ID}")
    print(f"\nThis will:")
    print(f"  1. DROP {TABLE_ID}")
    print(f"  2. RENAME {TABLE_ID}_deduped → {TABLE_ID}")
    print(f"  3. DROP {TABLE_ID}_deduped")
    
    response = input("\nProceed with replacement? [yes/NO]: ")
    if response.lower() != 'yes':
        print("\n❌ Cancelled. Deduplicated table saved as: {TABLE_ID}_deduped")
        print("   You can manually inspect and replace if desired.")
        return
    
    # Step 5: Replace original table
    print("\n3️⃣  Replacing original table with deduplicated version...")
    try:
        client.query(REPLACE_QUERY).result()
        print(f"   ✅ Table replaced successfully!")
        print(f"   ✅ Backup available at: {BACKUP_TABLE_ID}")
    except Exception as e:
        print(f"   ❌ Replacement failed: {e}")
        print(f"   ⚠️  Original table may be in inconsistent state!")
        print(f"   ⚠️  Restore from backup: {BACKUP_TABLE_ID}")
        return
    
    # Final stats
    print_stats(client, STATS_BEFORE_QUERY, "\n✅ Final Table Statistics")
    
    print("\n" + "=" * 100)
    print("✅ DEDUPLICATION COMPLETE!")
    print("=" * 100)
    print(f"✅ Duplicates removed")
    print(f"✅ Latest versions retained")
    print(f"✅ Backup available: {BACKUP_TABLE_ID}")
    print("=" * 100)


# ============================================================================
# MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='Deduplicate traffic classification table')
    parser.add_argument('--mode', 
                        choices=['dry-run', 'execute'],
                        default='dry-run',
                        help='Execution mode')
    
    # Legacy compatibility
    parser.add_argument('--dry-run', action='store_true', help='Dry run mode (same as --mode dry-run)')
    parser.add_argument('--execute', action='store_true', help='Execute mode (same as --mode execute)')
    
    args = parser.parse_args()
    
    # Determine mode
    if args.execute:
        mode = 'execute'
    elif args.dry_run or args.mode == 'dry-run':
        mode = 'dry-run'
    else:
        mode = args.mode
    
    is_dry_run = (mode == 'dry-run')
    
    # Initialize client
    try:
        client = bigquery.Client(project=PROJECT_ID)
        print(f"\n✅ Connected to BigQuery project: {PROJECT_ID}")
    except Exception as e:
        print(f"\n❌ Failed to connect: {e}")
        return
    
    # Run deduplication
    deduplicate_table(client, dry_run=is_dry_run)


if __name__ == "__main__":
    main()

