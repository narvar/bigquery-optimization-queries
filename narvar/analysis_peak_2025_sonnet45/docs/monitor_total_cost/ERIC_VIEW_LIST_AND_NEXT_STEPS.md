# Eric's View List - Monitor Retailer Views and Production Cost Analysis

**Date:** November 14, 2025  
**Source:** Eric (Data Engineering)  
**Context:** Authoritative list of views used by Monitor retailers for cost analysis

---

## 📋 Authoritative View List from Eric

### Project Structure

**Number of Projects:** ~1,800 retailer GCP projects  
**Project Pattern:** `monitor-{7char_hash}-us-prod` (e.g., monitor-06c1cf5-us-prod)  
**Dataset Name:** `monitor` (consistent across all projects)

### View Names (9 views)

1. **v_shipments** - Shipment tracking data
2. **v_shipments_events** - Shipment event history
3. **v_shipments_transposed** - Shipment data in alternative format
4. **v_orders** - Order information
5. **v_order_items** - Order line items
6. **v_return_details** - Return/refund details
7. **v_return_rate_agg** - Return rate aggregations
8. **v_benchmark_tnt** - Time-to-notify benchmarks
9. **v_benchmark_ft** - First-time delivery benchmarks

**Note:** These views are created in each retailer's project and reference shared base tables.

---

## 🎯 Implications for Our Analysis

### What This Means

**Good News:**
- We now have the complete list (9 views vs the 5 we found for fashionnova)
- fashionnova uses 5 of these 9 views (56% coverage)
- Other retailers may use different combinations

**Important Clarifications:**
- **~1,800 projects** but only **284 retailers** analyzed
  - Some retailers have multiple projects (prod, staging, dev)
  - Our analysis correctly focuses on prod projects only
  - fashionnova project: `monitor-a679b28-us-prod` (identified in Phase 1)

### Updated Scope for Tomorrow (Phase 2)

**Instead of recursive view resolution query (complex):**

**Use Eric's list + your provided view definitions:**
1. For each of the 9 views, document the base table chain
2. Identify unique base tables across all 9 views
3. Search audit logs for production costs of those base tables
4. Calculate total Monitor production costs

---

## 📊 View → Base Table Mapping (From Your Provided Definitions)

### View 1 & 2: Shipment Views

**v_shipments, v_shipments_events, v_shipments_transposed**

**Chain:**
```
monitor-{hash}-us-prod.monitor.v_shipments_events
  ↓
monitor_base.v_shipments_events_stg
  ↓
monitor_base.shipments ✅ BASE TABLE (cost known: $200,957/year)
monitor_base.carrier_config ✅ BASE TABLE (need to find cost)
```

**Production Cost:**
- monitor_base.shipments: $200,957/year ✅ KNOWN
- monitor_base.carrier_config: $??? (likely negligible - config table)

---

### View 6 & 7: Return Views

**v_return_details, v_return_rate_agg**

**Chain:**
```
monitor-{hash}-us-prod.monitor.v_return_details
  ↓
monitor_base.v_return_details
  ↓
analytics.v_returns_metrics
  ↓
analytics.v_unified_returns_base
  ↓
reporting.t_return_details ✅ BASE TABLE (28M rows - need to find cost!)
return_insights_base.return_item_details ✅ BASE TABLE (need to find cost!)
```

**Production Cost:**
- reporting.t_return_details: $??? (HIGH PRIORITY - large table!)
- return_insights_base.return_item_details: $??? (need to find)

---

### Views 3, 4, 5, 8, 9: Need to Trace

**v_orders, v_order_items, v_benchmark_tnt**

**Status:** View definitions not yet provided  
**Action:** Need to get definitions to trace to base tables

**Likely base tables (educated guesses):**
- v_orders → probably references monitor_base.shipments or similar
- v_order_items → probably references monitor_base.shipments or order tables
- v_benchmark_tnt → probably references monitor_base.shipments

---

## 🚀 Tomorrow's Execution Plan (Revised)

### Step 1: Document View Definitions for All 9 Views

**Option A (Recommended):** Ask Eric or team for view definitions
- Fastest and most accurate
- Avoids complex INFORMATION_SCHEMA queries across projects
- Can quickly map to base tables

**Option B (Fallback):** Query INFORMATION_SCHEMA
- Create SQL to extract view definitions
- May face cross-project access limitations
- More time-consuming

**Deliverable:** Create `VIEW_TO_BASE_TABLE_MAPPING.md` with complete chain for all 9 views

---

### Step 2: Identify All Unique Base Tables

**From known mappings:**
- ✅ monitor_base.shipments ($200,957/year known)
- ❓ monitor_base.carrier_config (need to find)
- ❓ reporting.t_return_details (HIGH PRIORITY - 28M rows)
- ❓ return_insights_base.return_item_details (need to find)
- ❓ Others from v_orders, v_order_items, v_benchmark_tnt

**Expected:** 5-10 unique base tables total

---

### Step 3: Search Audit Logs for Production Costs

**Query:** `queries/monitor_total_cost/04_all_base_tables_production_costs.sql`

**For each base table:**
- Find INSERT/MERGE/CREATE operations in audit logs
- Calculate slot-hours consumed
- Estimate annual production costs
- Identify service accounts/DAGs

**High Priority Tables:**
1. **reporting.t_return_details** - 28M rows, likely $50K-$150K/year
2. **return_insights_base.return_item_details** - Unknown size, likely significant
3. **monitor_base.carrier_config** - Probably small, <$1K/year

---

### Step 4: Create Questions Document for Data Engineering

**For tables where audit log data is insufficient:**

**Document:** `QUESTIONS_FOR_DATA_ENGINEERING.md`

**Questions per base table:**
1. Which Airflow DAG populates this table?
2. What's the refresh frequency (hourly, daily, batch)?
3. What are the data sources (APIs, databases, files)?
4. Estimated BigQuery compute cost (if known)?
5. Non-BigQuery costs (Dataflow, GCS, etc.)?
6. Any optimization opportunities?

---

### Step 5: Calculate Complete Platform Costs

**Updated cost structure:**

| Component | Current Estimate | After Phase 2 | Status |
|-----------|-----------------|---------------|--------|
| monitor_base.shipments | $200,957 | $200,957 | ✅ Known |
| reporting.t_return_details | $0 | $50K-$150K | 📋 To find |
| return_insights_base.return_item_details | $0 | $10K-$50K | 📋 To find |
| monitor_base.carrier_config | $0 | <$1K | 📋 To find |
| Other base tables | $0 | $10K-$50K | 📋 To find |
| Consumption (queries) | $6,418 | $6,418 | ✅ Known |
| **TOTAL** | **$207,375** | **$280K-$400K** | 📋 To calculate |

---

### Step 6: Revise fashionnova Attribution

**With complete costs:**

**Example scenario:** If total production = $350K (not $201K)

fashionnova attribution (34% weighted):
- Previous: $200,957 × 0.34 = $68,325
- Updated: $350,000 × 0.34 = $119,000
- **New total fashionnova cost: $120,616/year** (not $69,941!)

**Impact on pricing:**
- fashionnova at cost: $10,051/month (not $6,447!)
- fashionnova with 20% margin: $12,062/month (not $7,737!)
- Enterprise tier pricing may need to be $12,000-$15,000/month

---

## 💡 Key Insights from Eric's Information

### Insight 1: 1,800 Projects but 284 Retailers

**Implication:** 
- Average ~6 projects per retailer (prod, staging, dev, regional?)
- Our analysis correctly filters to retailers (not projects)
- Cost attribution should be per retailer (aggregate their projects)

### Insight 2: Consistent View Structure

**All retailer projects have same 9 views:**
- Standardized schema
- Easier to analyze (patterns are consistent)
- Base table production costs are truly shared infrastructure

### Insight 3: Not All Retailers Use All Views

**fashionnova uses 5/9 views:**
- v_shipments ✓
- v_shipments_events ✓
- v_benchmark_ft ✓
- v_return_details ✓
- v_return_rate_agg ✓
- v_shipments_transposed ✗
- v_orders ✗
- v_order_items ✗
- v_benchmark_tnt ✗

**Implication:**
- Different usage patterns per retailer
- Some retailers may only use shipment views (cheaper)
- Some use full suite including returns, orders (more expensive)
- Attribution should account for which views each retailer actually uses

---

## 🎯 Tomorrow's Goals (Concrete)

1. ✅ **Get view definitions for the 4 missing views** (v_orders, v_order_items, v_shipments_transposed, v_benchmark_tnt)
   - Ask Eric/team or query INFORMATION_SCHEMA
   
2. ✅ **Map all 9 views to base tables** - Create complete dependency tree

3. ✅ **Find production costs for all base tables** - Audit log search
   - Priority: reporting.t_return_details (expected: $50K-$150K/year)

4. ✅ **Calculate updated platform total** - $280K-$400K expected

5. ✅ **Revise fashionnova analysis** - With complete costs

6. ✅ **Update pricing recommendations** - Based on real total costs

---

## 📧 Suggested Follow-Up with Eric

**If you want to accelerate tomorrow's work:**

"Hi Eric, thanks for the view list! Very helpful. Quick follow-up questions:

1. Can you share view definitions for these 4 views (or point me to where I can find them)?
   - v_orders
   - v_order_items  
   - v_shipments_transposed
   - v_benchmark_tnt

2. Do you know which base tables these ultimately reference? I'm trying to map production costs.

3. For `reporting.t_return_details` (28M rows) - do you know:
   - Which Airflow DAG populates it?
   - Estimated BigQuery cost to maintain?
   - Any other significant base tables I should be aware of?

Thanks! This will help complete the Monitor pricing cost analysis."

---

**Status:** ✅ Ready for tomorrow's Phase 2 execution with Eric's input  
**Next Session:** Create recursive resolution query OR use Eric's definitions (whichever is faster)

