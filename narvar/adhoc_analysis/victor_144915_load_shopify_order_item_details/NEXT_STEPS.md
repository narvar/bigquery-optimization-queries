# VICTOR-144915: Next Steps

**Date**: November 25, 2025  
**Status**: Investigation complete, ready to deploy fix

---

## Immediate Actions (Today - 35 minutes)

### 1. Deploy Safety Net Filter (5 minutes)

**EXACT FILE LOCATION**: `/Users/cezarmihaila/workspace/composer/dags/shopify/load_shopify_order_item_details.py`

**EXACT LINE**: Insert after line 340

**See detailed instructions**: [EXACT_CODE_CHANGE.md](./EXACT_CODE_CHANGE.md) ⭐

**Quick Reference**:

**Current code (lines 335-342)**:
```python
            WHERE 
                o.ingestion_timestamp >= TIMESTAMP_SUB(
                    TIMESTAMP('{execution_date}'),
                    INTERVAL 48 HOUR
                )
                AND DATE(o.order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
                AND o.order_date >= '2024-01-01'
        );
```

**Add these 2 lines after line 340** (after the closing paren):
```python
                AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)
                AND DATE(o.order_date) <= DATE('{execution_date}')
```

**Result**:
```python
            WHERE 
                o.ingestion_timestamp >= TIMESTAMP_SUB(
                    TIMESTAMP('{execution_date}'),
                    INTERVAL 48 HOUR
                )
                AND DATE(o.order_date) >= DATE_SUB(DATE('{execution_date}'), INTERVAL 7 DAY)  -- NEW
                AND DATE(o.order_date) <= DATE('{execution_date}')  -- NEW
                AND o.order_date >= '2024-01-01'
        );
```

**Testing**:
```bash
# Optional: Test the modified filter with dry-run
cd /Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/adhoc_analysis/victor_144915_load_shopify_order_item_details

# Run the test query from EXACT_CODE_CHANGE.md
bq query --dry_run --use_legacy_sql=false < test_modified_query.sql
```

**Deploy**:
```bash
cd /Users/cezarmihaila/workspace/composer
git add dags/shopify/load_shopify_order_item_details.py
git commit -m "Fix VICTOR-144915: Add date filter to prevent backfilled data"
git push
# Wait 1-2 minutes for Composer to sync
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

## This Week Actions (4-8 hours)

### 4. Investigate Continuous Data Backfill ✅ **COMPLETE**

**UPDATE**: Investigation complete via Queries 10-13.

**Findings**:
1. ✅ `ingestion_timestamp` column exists in `v_order_items_atlas`
2. ✅ Filter is working correctly
3. ✅ **ROOT CAUSE**: Continuous re-ingestion of historical orders
4. ✅ **Proof**: Oct 15-17 orders have Nov 25 ingestion timestamps
5. ✅ **Concentration**: nicandzoe (342K), icebreakerapac (5.8K), skims (5.4K), milly (3.6K), stevemadden (3.1K)
6. ✅ **Pattern**: 98% have NO returns - not driven by return activity

**See**: `BACKFILL_ROOT_CAUSE.md` for complete analysis

---

### 5. Identify Backfill Source and Owner

**Questions to answer**:

1. **Who owns `v_order_items_atlas` ingestion?**
   ```sql
   -- Find recent INSERT/MERGE jobs to v_order_items_atlas
   SELECT 
       creation_time,
       user_email,
       job_type,
       destination_table.table_id,
       total_slot_ms,
       total_bytes_processed
   FROM 
       `narvar-data-lake.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
   WHERE 
       creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
       AND destination_table.table_id = 'v_order_items_atlas'
   ORDER BY creation_time DESC
   LIMIT 100;
   ```

2. **Is backfill intentional or a bug?**
   - Check Dataflow job logs
   - Check Airflow DAG schedules
   - Interview team that owns the pipeline

3. **Why these specific retailers?**
   - nicandzoe dominates (342K of 360K very old orders)
   - Is there a data quality issue for these retailers?
   - Recent schema change affecting them?

4. **What's the backfill pattern/schedule?**
   - Query 13 shows ingestion at: 08:00, 09:00, 12:00, 13:00, 15:00, 16:00, 17:00, 18:00, 19:00
   - Continuous? Hourly? Event-driven?

**Effort**: 2-3 hours  
**Risk**: Low (just investigation, no changes)

---

### 6. Fix Root Cause - Stop Unnecessary Backfill

**Action depends on findings from Step 5**:

**If backfill is intentional** (data quality fixes):
- Add `is_backfill` boolean flag to `v_order_items_atlas`
- Update DAG to exclude: `WHERE is_backfill IS NOT TRUE`
- Or use separate table for backfilled data

**If backfill is a bug**:
- Fix upstream ETL/Dataflow pipeline
- Prevent continuous re-ingestion
- Potentially one-time cleanup of historical data

**If backfill is needed**:
- Batch it (daily instead of continuous)
- Process backfill separately from real-time ingestion
- Add explicit backfill tracking

**Effort**: 4-8 hours + coordination time  
**Risk**: Medium (requires upstream team changes)

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

