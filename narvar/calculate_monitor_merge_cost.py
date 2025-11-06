#!/usr/bin/env python3
"""
BQ Monitor Merge Cost Calculator - FINAL RESULTS

Calculates the annual cost of BQ Monitor merge operations based on actual findings.

FINDINGS:
- Service Account: monitor-base-us-prod@appspot.gserviceaccount.com
- Operations: MERGE queries containing "shipments"
- Percentage: 24.18% of total BigQuery Reservation capacity
- Annual Cost: $200,957.67

Usage:
    python calculate_monitor_merge_cost.py

Date: 2025-11-06 (Updated with actual results)
"""

import pandas as pd


def calculate_costs(monitor_merge_slot_pct):
    """
    Calculate annual BQ Monitor merge costs
    
    Args:
        monitor_merge_slot_pct: Percentage of TOTAL BigQuery Reservation slots 
                                consumed by monitor merge operations (from BigQuery query)
    
    Returns:
        dict: Cost breakdown
    """
    
    # From DoIT CSV (already calculated)
    total_bq_reservation = 619598.41  # Annual BigQuery Reservation API cost
    total_storage = 24899.45          # Annual storage cost (monitor-base-us-prod)
    total_pubsub = 26226.46           # Annual Pub/Sub cost (monitor-base-us-prod)
    
    # Calculate monitor merge reservation cost
    monitor_merge_reservation_cost = total_bq_reservation * (monitor_merge_slot_pct / 100)
    
    # Total annual cost
    total_annual_cost = monitor_merge_reservation_cost + total_storage + total_pubsub
    
    return {
        'total_bq_reservation': total_bq_reservation,
        'monitor_merge_slot_pct': monitor_merge_slot_pct,
        'monitor_merge_reservation_cost': monitor_merge_reservation_cost,
        'total_storage': total_storage,
        'total_pubsub': total_pubsub,
        'total_annual_cost': total_annual_cost
    }


def print_cost_summary(costs):
    """Print formatted cost summary"""
    
    print("=" * 80)
    print("ANNUAL BQ MONITOR MERGE COST CALCULATION")
    print("=" * 80)
    print("\nBASELINE PERIOD: Sep-Oct 2024 (2 months)")
    print("Extrapolation: 12 months / 2 months = 6x")
    
    print("\n1. BigQuery Reservation API Cost (Monitor Merge Portion):")
    print(f"   Total Reservation Cost (Annual):           ${costs['total_bq_reservation']:>15,.2f}")
    print(f"   Monitor Merge Slot % (of TOTAL BQ):        {costs['monitor_merge_slot_pct']:>15.2f}%")
    print(f"   Monitor Merge Reservation Cost (Annual):   ${costs['monitor_merge_reservation_cost']:>15,.2f}")
    
    print("\n2. Storage Costs (monitor-base-us-prod):")
    print(f"   Annual Storage Cost:                       ${costs['total_storage']:>15,.2f}")
    
    print("\n3. Cloud Pub/Sub Costs (monitor-base-us-prod):")
    print(f"   Annual Pub/Sub Cost:                       ${costs['total_pubsub']:>15,.2f}")
    
    print("\n" + "=" * 80)
    print(f"TOTAL ANNUAL BQ MONITOR MERGE COST:           ${costs['total_annual_cost']:>15,.2f}")
    print("=" * 80)
    
    compute_pct = costs['monitor_merge_reservation_cost'] / costs['total_annual_cost'] * 100
    storage_pct = costs['total_storage'] / costs['total_annual_cost'] * 100
    pubsub_pct = costs['total_pubsub'] / costs['total_annual_cost'] * 100
    
    print("\n\nCost Breakdown:")
    print(f"  Compute (Monitor Merge):  ${costs['monitor_merge_reservation_cost']:>12,.2f}  ({compute_pct:>5.1f}%)")
    print(f"  Storage:                  ${costs['total_storage']:>12,.2f}  ({storage_pct:>5.1f}%)")
    print(f"  Pub/Sub:                  ${costs['total_pubsub']:>12,.2f}  ({pubsub_pct:>5.1f}%)")
    print(f"  {'─' * 60}")
    print(f"  TOTAL:                    ${costs['total_annual_cost']:>12,.2f}  (100.0%)")
    
    print("\n\n" + "=" * 80)
    print("ANSWER TO QUESTION:")
    print("=" * 80)
    print(f"\nThe BQ Monitor merge (monitor-base-us-prod@appspot.gserviceaccount.com)")
    print(f"performing MERGE+SHIPMENTS operations is costing us ${costs['total_annual_cost']:,.2f} annually.")
    print(f"\nThis represents {costs['monitor_merge_slot_pct']:.2f}% of total BigQuery Reservation capacity.")
    print(f"\nThis cost would need to be offset by any alternative solution.")
    print("\n" + "=" * 80)


def main():
    """Main function"""
    
    print("BQ Monitor Merge Cost Calculator")
    print("=" * 80)
    print("\nThis calculator requires the monitor_merge_slot_pct from BigQuery.")
    print("Run monitor_merge_analysis.sql first to get this percentage.")
    print("\n" + "=" * 80)
    
    # Get user input
    while True:
        try:
            pct_input = input("\nEnter monitor_merge_slot_pct (e.g., 5.23): ")
            monitor_merge_slot_pct = float(pct_input)
            
            if 0 <= monitor_merge_slot_pct <= 100:
                break
            else:
                print("⚠ Percentage must be between 0 and 100. Please try again.")
        except ValueError:
            print("⚠ Invalid input. Please enter a number (e.g., 5.23)")
    
    # Calculate costs
    costs = calculate_costs(monitor_merge_slot_pct)
    
    # Print summary
    print("\n")
    print_cost_summary(costs)
    
    # Save to CSV
    save_option = input("\nSave summary to CSV? (y/n): ").strip().lower()
    if save_option == 'y':
        summary_data = {
            'Cost Component': [
                'BigQuery Reservation (Monitor Merge)',
                'Storage (monitor-base-us-prod)',
                'Cloud Pub/Sub (monitor-base-us-prod)',
                'TOTAL'
            ],
            'Annual Cost (USD)': [
                costs['monitor_merge_reservation_cost'],
                costs['total_storage'],
                costs['total_pubsub'],
                costs['total_annual_cost']
            ],
            'Percentage': [
                f"{costs['monitor_merge_reservation_cost']/costs['total_annual_cost']*100:.1f}%",
                f"{costs['total_storage']/costs['total_annual_cost']*100:.1f}%",
                f"{costs['total_pubsub']/costs['total_annual_cost']*100:.1f}%",
                "100.0%"
            ],
            'Notes': [
                f"Service: monitor-base-us-prod@appspot.gserviceaccount.com, {monitor_merge_slot_pct:.2f}% of total BQ capacity",
                'All storage SKUs for monitor-base-us-prod',
                'All Pub/Sub operations for monitor-base-us-prod',
                'Total cost to offset'
            ]
        }
        
        df = pd.DataFrame(summary_data)
        output_file = 'monitor_merge_cost_summary.csv'
        df.to_csv(output_file, index=False)
        print(f"\n✓ Summary saved to: {output_file}")


if __name__ == '__main__':
    main()

