# BQ Monitor Merge Cost Analysis

**Purpose**: Calculate the annual cost of BQ Monitor merge operations to determine the cost that would need to be offset by any alternative solution.

**Date**: 2025-11-06

---

## Quick Answer (Preliminary)

Based on the DoIT CSV data analysis:

### Fixed Costs (Already Calculated):
- **Total BigQuery Reservation API**: $619,598.41/year
- **Storage (monitor-base-us-prod)**: $24,899.45/year
- **Pub/Sub (monitor-base-us-prod)**: $26,226.46/year

### Variable Cost (Requires BigQuery Query):
- **Monitor Merge Reservation Portion**: $619,598.41 × (monitor_merge_slot_pct / 100)

**Total Annual Cost Formula**:
```
Total = Monitor Merge Reservation Cost + Storage + Pub/Sub
      = (619,598.41 × monitor_merge_slot_pct / 100) + 24,899.45 + 26,226.46
```

---

## Three Ways to Complete the Analysis

### Option 1: Run the Jupyter Notebook (Recommended)

**File**: `monitor_merge_cost_analysis.ipynb`

**Steps**:
1. Open the notebook in Jupyter or VS Code
2. Run all cells in sequence
3. The notebook will:
   - Calculate costs from DoIT CSV
   - Query BigQuery for merge percentage
   - Calculate final annual cost
   - Export summary to CSV

**Requirements**:
- Python with `pandas`, `google-cloud-bigquery`
- BigQuery authentication configured
- Access to `narvar-data-lake.query_opt.traffic_classification` table

---

### Option 2: SQL Query + Python Calculator

**Step 1**: Run the SQL query in BigQuery console

**File**: `monitor_merge_analysis.sql`

This query will:
- Analyze AUTOMATED category merge jobs writing to monitor projects
- Calculate `monitor_merge_slot_pct` (the key metric)
- Show sample queries for validation
- Break down by subcategory

**Expected Output**: A percentage value (e.g., 5.23%)

**Step 2**: Use the Python calculator

**File**: `calculate_monitor_merge_cost.py`

```bash
python3 calculate_monitor_merge_cost.py
```

Enter the `monitor_merge_slot_pct` from Step 1, and the script will:
- Calculate the annual cost breakdown
- Show the total cost to offset
- Optionally save to CSV

---

### Option 3: Manual Calculation

If you already know the merge percentage from previous analysis:

```
Monitor Merge Reservation Cost = $619,598.41 × (merge_slot_pct / 100)
Storage Cost = $24,899.45
Pub/Sub Cost = $26,226.46

Total Annual Cost = Monitor Merge Reservation + Storage + Pub/Sub
```

**Example**: If merge operations consume 8% of AUTOMATED slots:
```
Monitor Merge Reservation = $619,598.41 × 0.08 = $49,567.87
Total Annual Cost = $49,567.87 + $24,899.45 + $26,226.46 = $100,693.78
```

---

## Methodology Details

### Scope Definition

1. **Consumer Category**: AUTOMATED only
   - Excludes EXTERNAL (Monitor projects, Hub)
   - Excludes INTERNAL (Metabase, ad-hoc queries)

2. **Operation Type**: MERGE INTO operations
   - Detected via query text pattern: `MERGE INTO monitor-*`
   - Specifically writing to monitor projects

3. **Time Period**: Sep-Oct 2024 (2 months baseline)
   - Extrapolated to annual costs (12 months)
   - Uses actual billing data from DoIT CSV

4. **Cost Components**:
   - **Compute**: Proportional share of BigQuery Reservation API based on slot consumption
   - **Storage**: All storage SKUs for monitor-base-us-prod
   - **Pub/Sub**: All Pub/Sub operations for monitor-base-us-prod

### Data Sources

1. **DoIT CSV** (`BQ Detailed 01 monthly.csv`):
   - BigQuery Reservation API costs (3 commitment types)
   - Storage costs by project and SKU
   - Pub/Sub costs by project and SKU
   - Actual billing data for 12 months

2. **BigQuery Traffic Classification** (`narvar-data-lake.query_opt.traffic_classification`):
   - Job-level slot consumption
   - Query text for pattern matching
   - Consumer category classification
   - Cost estimates based on slot-hours

### Key Assumptions

1. **Merge Detection**: Regex pattern `MERGE\s+INTO\s+[`\[]?monitor-[a-z0-9]+-us-[a-z]+` 
   accurately identifies merge operations to monitor projects

2. **Proportional Cost**: Merge operations consume reservation capacity proportionally
   to their slot consumption percentage

3. **Baseline Representativeness**: Sep-Oct 2024 is representative of typical workload
   (adjust if this period had anomalies)

4. **Storage Attribution**: All monitor-base-us-prod storage is attributed to merge
   operations (reasonable since this project is specifically for monitor data)

5. **Pub/Sub Attribution**: All Pub/Sub for monitor-base-us-prod is attributed to merge
   operations (this project is the messaging hub for monitor data)

---

## Cost Breakdown by SKU

### BigQuery Reservation API (bq-narvar-admin)
| SKU | Annual Cost | Notes |
|-----|-------------|-------|
| Enterprise Edition (US multi-region) | $435,906.71 | On-demand |
| Enterprise Edition 1 Year (US multi-region) | $104,957.84 | 1-year commitment |
| Enterprise Edition 3 Years (US multi-region) | $78,733.87 | 3-year commitment |
| **Total** | **$619,598.41** | All commitment types |

### Storage (monitor-base-us-prod)
| SKU | Annual Cost | Notes |
|-----|-------------|-------|
| Active Logical Storage | $17,996.28 | Frequently accessed tables |
| Long Term Logical Storage | $5,801.23 | Tables not modified for 90+ days |
| Long-Term Physical Storage (US) | $948.01 | Physical storage for long-term data |
| Active Physical Storage (US) | $153.94 | Physical storage for active data |
| **Total** | **$24,899.45** | All storage types |

### Cloud Pub/Sub (monitor-base-us-prod)
| SKU | Annual Cost | Notes |
|-----|-------------|-------|
| Message Delivery Basic | $26,226.46 | Pub/Sub message delivery |
| **Total** | **$26,226.46** | All Pub/Sub operations |

---

## Next Steps

1. **Run the Analysis**:
   - Choose one of the three options above
   - Get the `monitor_merge_slot_pct` value
   - Calculate the final annual cost

2. **Validate Results**:
   - Check if the merge percentage seems reasonable (typically 2-15%)
   - Review sample queries to ensure regex pattern is working
   - Consider seasonal variations if baseline period was unusual

3. **Document Findings**:
   - Record the final annual cost
   - Note any assumptions or caveats
   - Share with stakeholders

4. **Use for Decision Making**:
   - This is the cost that any alternative solution would need to offset
   - Consider ROI of alternative approaches
   - Factor in migration costs and risks

---

## Questions or Issues?

If you encounter any issues:

1. **Regex pattern not matching**: Check sample queries output
2. **Unexpected percentage**: Validate against known workload patterns
3. **Query timeout**: Consider reducing date range or adding filters
4. **Authentication errors**: Ensure BigQuery credentials are configured

---

## Files in This Analysis

- `monitor_merge_cost_analysis.ipynb` - Full Jupyter notebook analysis
- `monitor_merge_analysis.sql` - SQL query to run in BigQuery console
- `calculate_monitor_merge_cost.py` - Python calculator script
- `MONITOR_MERGE_COST_README.md` - This file (documentation)
- `BQ Detailed 01 monthly.csv` - Source data (DoIT billing CSV)

---

**Last Updated**: 2025-11-06

