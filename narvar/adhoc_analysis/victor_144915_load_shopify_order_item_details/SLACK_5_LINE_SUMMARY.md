# VICTOR-144915: 5-Line Slack Summary

Investigated `load_shopify_order_item_details` DAG timeout (6 hours). Root cause: **continuous data backfill** in `v_order_items_atlas` table—old orders (Oct 15-17) are being re-ingested with Nov 25 timestamps, legitimately passing the 48-hour `ingestion_timestamp` filter but creating 183 distinct dates in aggregations instead of 2-3. The issue is concentrated in **nicandzoe (342K old orders, 94% of problem)** plus 4 other retailers. The `ingestion_timestamp` filter IS working correctly; upstream ETL is the issue. **Fix ready**: Add explicit `order_date` filter to DAG (5 min deployment, exact instructions in [EXACT_CODE_CHANGE.md](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/victor_144915_load_shopify_order_item_details/EXACT_CODE_CHANGE.md)) + coordinate with team owning `v_order_items_atlas` to stop unnecessary backfill.

---

**Files**: 13 docs, 13 queries, 10 results | **Cost**: $1.77 | **GitHub**: [victor_144915_load_shopify_order_item_details](https://github.com/narvar/bigquery-optimization-queries/tree/main/narvar/adhoc_analysis/victor_144915_load_shopify_order_item_details)

