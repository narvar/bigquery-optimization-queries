# VICTOR-144915: Next Steps

**Date**: November 25, 2025  
**Status**: Investigation complete, ready to deploy fix

---

## Immediate Actions (Today - 35 minutes)

### 1. Deploy Safety Net Filter (5 minutes)

**File to modify**: The Airflow DAG Python file (likely in `/Users/cezarmihaila/workspace/composer/dags/shopify/`)

**Change needed**: In the `merge_order_item_details` task SQL, modify the WHERE clause:

**From:**
```sql
WHERE 
    o.ingestion_timestamp >= TIMESTAMP_SUB(
        TIMESTAMP('{execution_date}'),
        INTERVAL 48 HOUR
    )
    AND DATE(o.order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
    AND o.order_date >= '2024-01-01'
```

**To:**
```sql
WHERE 
    o.ingestion_timestamp >= TIMESTAMP_SUB(
        TIMESTAMP('{execution_date}'),
        INTERVAL 48 HOUR
    )
    AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)  -- NEW: Safety net
    AND DATE(o.order_date) <= DATE('{execution_date}')  -- NEW: Upper bound
```

**Testing**:
```bash
# Deploy to Airflow
# Test with dry-run if possible
# Monitor tonight's DAG run
```

---

### 2. Clean Up Bad Temp Tables (10 minutes)

**Run these BigQuery commands:**

```sql
-- Drop Nov 19 bad temp tables
DROP TABLE IF EXISTS `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-19`;
DROP TABLE IF EXISTS `narvar-data-lake.return_insights_base.tmp_product_insights_updates_2025-11-19`;

-- Drop Nov 20 bad temp tables
DROP TABLE IF EXISTS `narvar-data-lake.return_insights_base.tmp_order_item_details_2025-11-20`;
DROP TABLE IF EXISTS `narvar-data-lake.return_insights_base.tmp_product_insights_updates_2025-11-20`;

-- Kill any running jobs for these dates (if still active)
-- Check: bq ls -j -a -n 50 narvar-data-lake | grep "2025-11-20"
```

---

### 3. Manual Retry for Nov 19-20 (20 minutes)

**Option A**: Trigger Airflow DAG manually for those dates
- In Airflow UI: Trigger DAG with execution_date = 2025-11-19
- Wait for completion (~6 minutes if fix works)
- Repeat for 2025-11-20

**Option B**: Skip backfill if not business-critical
- Nov 21-24 data is already up to date
- Nov 19-20 may not be critical (only 2 days gap)
- Decide based on business impact

---

## This Week Actions (2-4 hours)

### 4. Investigate ingestion_timestamp Column

**Query 1**: Check if column exists
```sql
SELECT column_name, data_type
FROM `narvar-data-lake.return_insights_base.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'v_order_items'
AND column_name LIKE '%ingestion%'
ORDER BY column_name;
```

**Query 2**: If column exists, check values
```sql
SELECT 
    MIN(ingestion_timestamp) AS min_ingestion,
    MAX(ingestion_timestamp) AS max_ingestion,
    COUNT(*) AS total_rows,
    COUNTIF(ingestion_timestamp IS NULL) AS null_count,
    COUNTIF(ingestion_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 48 HOUR)) AS last_48hrs,
    COUNTIF(ingestion_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS last_7days
FROM `narvar-data-lake.return_insights_base.v_order_items`
LIMIT 1;  -- Metadata only, no actual row scan
```

**Query 3**: Get view definition
```sql
SELECT view_definition
FROM `narvar-data-lake.return_insights_base.INFORMATION_SCHEMA.VIEWS`
WHERE table_name = 'v_order_items';
```

**Possible findings**:
- Column doesn't exist → Need to add it to view
- Column exists but is NULL → Need to populate from source table
- Column exists but has wrong values → Need to fix upstream ETL

---

### 5. Fix Root Cause (TBD based on findings)

**If column missing**: Add to view definition  
**If column NULL**: Modify view to populate from source  
**If values wrong**: Fix upstream Dataflow/ETL pipeline

**Effort**: Depends on finding (2 hours - 2 days)

---

### 6. Remove Safety Net Filter (5 minutes)

Once ingestion_timestamp is fixed and validated:
- Remove the explicit date filter added in Step 1
- Return to original design (48-hour ingestion window only)
- Monitor for 1 week to ensure stability

---

## Next Sprint Actions (Optional - 2-3 hours)

### 7. Partition Temp Tables by order_date

**Benefits**:
- Reduces scan size even if temp table has extra data
- Improves performance for all runs (not just problematic ones)
- Future-proofs against filter issues

**Changes needed**:
1. Modify DAG to create partitioned temp table
2. Add partition filter to aggregation CTE
3. Test with backfill

**Effort**: 2-3 hours development + testing

---

## Monitoring

### After deploying fix, monitor:

1. **Tonight's DAG run (Nov 25)**:
   - Should complete in 5-10 minutes
   - Check temp table has only 2-3 days of data
   - Verify slot consumption ~11-15 slot-hours

2. **This week's runs**:
   - All should complete normally
   - No 6-hour timeouts
   - Consistent 5-10 minute runtime

3. **Cost**:
   - Should return to $0.50-$1 per run
   - Down from $24 per failed attempt

### Red flags to watch for:

- ⚠️ Temp table still has >7 days of data
- ⚠️ Runtime >20 minutes
- ⚠️ Slot consumption >30 slot-hours
- ❌ Any timeouts

If any red flag occurs, the ingestion_timestamp filter still isn't working. Proceed with Steps 4-5 urgently.

---

## Open Questions for Team

1. **Business impact**: How critical is it to have Nov 19-20 data in product_insights?
   - Do any dashboards/reports specifically need those 2 days?
   - Or can we skip backfill and move forward?

2. **View ownership**: Who maintains `v_order_items` view?
   - Need to coordinate with them for root cause fix
   - Ensure they understand the ingestion_timestamp requirement

3. **Similar DAGs**: Do other Shopify DAGs have the same pattern?
   - `load_return_item_details` likely has same issue
   - Should we proactively fix those too?

4. **Alerting**: Should we add monitoring for temp table size?
   - Alert if temp table has >7 days of data
   - Prevents future 6-hour timeout surprises

---

## Decision Points for Cezar

**Decision 1**: Deploy fix today or wait until tomorrow?
- **Recommend**: Deploy today (low risk, high benefit)

**Decision 2**: Backfill Nov 19-20 or skip?
- **Recommend**: Check business impact first, then decide

**Decision 3**: Investigate root cause this week or next sprint?
- **Recommend**: This week (prevents recurrence)

**Decision 4**: Deploy long-term partition fix?
- **Recommend**: Next sprint (not urgent, but good improvement)

---

## Files Reference

- [EXECUTIVE_SUMMARY.md](./EXECUTIVE_SUMMARY.md) - For VictorOps ticket
- [FINDINGS.md](./FINDINGS.md) - Complete technical analysis
- [SLACK_UPDATE.md](./SLACK_UPDATE.md) - For team communication
- [README.md](./README.md) - Investigation methodology
- `queries/` - 6 diagnostic SQL queries
- `results/` - 4 result files from investigation

---

## Summary

**Ready to deploy**: ✅ Safety net filter (5 min)  
**Ready to execute**: ✅ Cleanup and retry (30 min)  
**Need investigation**: ⏳ Root cause fix (2-4 hrs this week)  
**Optional improvement**: 🔮 Partition temp tables (next sprint)

**Total time to resolve**: 35 minutes today + 2-4 hours this week

---

*Investigation complete. Awaiting your go-ahead on deployment. -Sophia*

