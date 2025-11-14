# View Resolution Findings - fashionnova

## Summary

fashionnova queries reference 5 views in their monitor project (`monitor-a679b28-us-prod`):

1. **monitor.v_shipments** - 25,378 slot-hours (50% of total)
2. **monitor.v_shipments_events** - 25,150 slot-hours (50% of total)
3. **monitor.v_benchmark_ft** - 1.53 slot-hours
4. **monitor.v_return_details** - 0.07 slot-hours
5. **monitor.v_return_rate_agg** - 0.03 slot-hours

## Key Insight

These views are in retailer-specific projects and their definitions are not accessible via INFORMATION_SCHEMA.VIEWS from the `region-us` dataset.

However, based on naming conventions and the MONITOR_MERGE_COST analysis:
- **v_shipments** and **v_shipments_events** almost certainly reference **monitor-base-us-prod.monitor_base.shipments**
- This is the shared infrastructure table with known production cost: **$200,957/year**

## Assumption for Cost Attribution

**Primary Base Table:** `monitor-base-us-prod.monitor_base.shipments`

**Rationale:**
1. View names (v_shipments, v_shipments_events) strongly indicate shipments data source
2. MONITOR_MERGE_COST_FINAL_RESULTS.md documents monitor_base.shipments as the primary Monitor infrastructure
3. 99.5% of merge operations target this table
4. This table serves all 284 Monitor retailers

## Impact

- fashionnova's 50,531 slot-hours across views translate to usage of monitor_base.shipments
- For cost attribution purposes, we attribute fashionnova's production cost share of monitor_base.shipments
- Other views (benchmark, return_details, return_rate_agg) represent <0.1% of usage and can be considered negligible

## Recommendation

Proceed with cost attribution using:
- **Production cost:** monitor_base.shipments annual cost = $200,957
- **Attribution basis:** fashionnova's share of Monitor platform usage
- **Tables to track:** monitor_base.shipments (primary), others (negligible)

## Limitations

- Unable to resolve view definitions programmatically (cross-project INFORMATION_SCHEMA limitation)
- Assumptions based on naming conventions and prior analysis
- For production system, would need direct access to view definitions or manual documentation

