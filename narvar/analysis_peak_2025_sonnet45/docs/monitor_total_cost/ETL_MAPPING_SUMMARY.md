# ETL Mapping Summary - fashionnova Tables

## Primary Production Source

**Table:** `monitor-base-us-prod.monitor_base.shipments`

**ETL Source:** Monitor Base Merge Pipeline
**Service Account:** `monitor-base-us-prod@appspot.gserviceaccount.com`
**Operation Type:** MERGE (continuous + periodic batch)

## Production Costs (from MONITOR_MERGE_COST_FINAL_RESULTS.md)

### Annual Costs
- **Compute (merge operations):** $149,832 (74.6%)
- **Storage:** $24,899 (12.4%)
- **Pub/Sub (ingestion):** $26,226 (13.1%)
- **TOTAL:** $200,957/year

### Resource Consumption (Sep-Oct 2024 baseline, extrapolated)
- **Jobs:** ~6,256 per 2 months = ~37,536/year
- **Slot-hours:** 505,505 per 2 months = ~3,033,030/year
- **% of BQ Reservation:** 24.18%

## Cost Drivers

1. **Merge Operations** (Compute)
   - Pattern: `MERGE INTO monitor_base.shipments`
   - Continuous data ingestion from all retailers
   - High slot consumption due to:
     - Table size (billions of rows)
     - Matching logic (order lookups)
     - Update/insert operations

2. **Storage**
   - Active logical storage: $17,996/year
   - Long-term logical storage: $5,801/year
   - Physical storage: $1,102/year

3. **Pub/Sub**
   - Message delivery for real-time updates
   - $26,226/year

## fashionnova's Usage Pattern

Based on Phase 1 findings:
- Queries reference views built on monitor_base.shipments
- Primary views: v_shipments, v_shipments_events
- Query volume: 12,222 distinct references
- Slot-hours attributed: 50,531 (includes double-counting across views)

## ETL Workflow (Conceptual)

```
Retailer Systems
    ↓
Pub/Sub Messages → monitor-base-us-prod service account
    ↓
MERGE operations → monitor_base.shipments table
    ↓
Views (per retailer) → v_shipments, v_shipments_events, etc.
    ↓
Retailer Queries → Monitor API
```

## Cost Attribution Approach

Since fashionnova queries heavily use views based on monitor_base.shipments:
1. Calculate fashionnova's share of Monitor platform usage (queries, slot-hours, data scanned)
2. Apply hybrid attribution model (40% queries, 30% slot-hours, 30% data volume)
3. Multiply by $200,957 annual production cost
4. Result = fashionnova's attributed production cost

## Limitations

- Unable to trace DAG definitions in Composer repos (requires manual access)
- Actual Dataflow/GCS costs not separately measured (likely included in merge compute)
- Storage cost attribution simplified (proportional to query usage, not actual data footprint)

