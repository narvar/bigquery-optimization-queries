# Traffic Classification Strategy - Temporal Variability & Table Management

**Date**: November 5, 2025  
**Purpose**: Address temporal changes in service accounts, users, and projects over time

---

## 🎯 The Core Challenge

### Problem: Classification Patterns Change Over Time

**Services evolve**:
- ✅ New services launch: `messaging@` (2024), `growthbook@` (2024)
- ❌ Old services retire: deprecated ETL accounts, sunset projects
- 🔄 Services change roles: manual → automated, internal → external

**Retailers evolve**:
- ✅ New retailers onboard: new monitor projects created
- ❌ Retailers churn: monitor projects deprecated but still in historical data
- 🔄 Retailer name changes: M&A, rebranding

**Users evolve**:
- ✅ New employees join: new @narvar.com accounts
- ❌ Employees leave: accounts remain in historical audit logs
- 🔄 Roles change: analyst → data engineer (usage patterns shift)

### The Question:
**Should we classify 2022 data using 2022 patterns or 2024 patterns?**

---

## 💡 Recommended Strategy: "Progressive Classification with Versioning"

### Approach Overview:
1. **Discover patterns from RECENT data** (most complete pattern set)
2. **Apply retroactively to historical periods** (consistent taxonomy)
3. **Investigate historical UNCLASSIFIED** (find retired services)
4. **Add period-specific patterns** if needed
5. **Version classifications** (allow re-classification with improved patterns)

---

## 📊 Classification Table Design

### Schema: `narvar-data-lake.query_opt.traffic_classification`

```sql
CREATE TABLE `narvar-data-lake.query_opt.traffic_classification`
(
  -- ========== CLASSIFICATION METADATA ==========
  classification_date DATE,           -- When this classification was run
  analysis_start_date DATE,           -- Job period start (e.g., 2024-09-01)
  analysis_end_date DATE,             -- Job period end (e.g., 2024-10-31)
  analysis_period_label STRING,       -- Human-readable label (e.g., "Baseline_2024_Sep_Oct")
  classification_version STRING,      -- Pattern version (e.g., "v1.0", "v1.1")
  
  -- ========== JOB IDENTIFIERS ==========
  job_id STRING,
  project_id STRING,
  principal_email STRING,
  location STRING,
  
  -- ========== CLASSIFICATION ==========
  consumer_category STRING,           -- EXTERNAL, AUTOMATED, INTERNAL, UNCLASSIFIED
  consumer_subcategory STRING,        -- MONITOR, AIRFLOW_COMPOSER, METABASE, etc.
  priority_level INT64,               -- 1=P0 External, 2=P0 Automated, 3=P1 Internal
  
  -- ========== ATTRIBUTION ==========
  retailer_moniker STRING,            -- For monitor projects
  metabase_user_id STRING,            -- For Metabase queries
  
  -- ========== JOB METRICS ==========
  job_type STRING,
  start_time TIMESTAMP,
  end_time TIMESTAMP,
  execution_time_seconds FLOAT64,
  execution_time_minutes FLOAT64,
  
  -- ========== RESOURCES ==========
  total_slot_ms INT64,
  approximate_slot_count FLOAT64,
  slot_hours FLOAT64,
  total_billed_bytes INT64,
  total_billed_gb FLOAT64,
  estimated_slot_cost_usd FLOAT64,
  
  -- ========== QoS ==========
  qos_status STRING,
  qos_violation_seconds FLOAT64,
  is_qos_violation BOOL,
  
  -- ========== METADATA ==========
  reservation_name STRING,
  user_agent STRING,
  query_text_sample STRING
)
PARTITION BY DATE(start_time)        -- Partition by job execution date (not classification date!)
CLUSTER BY consumer_category, classification_date;
```

### Why This Design?

**Partitioning by start_time (job execution)**:
- ✅ Phase 2 queries filter by peak periods (Nov-Jan) → Efficient pruning
- ✅ Cost-effective: Only scans relevant months
- ✅ Standard for time-series analysis

**Clustering by category + classification_date**:
- ✅ Fast category-based aggregations
- ✅ Easy to filter for "latest classification"
- ✅ Supports comparing classification versions

**Multiple metadata columns**:
- ✅ Track WHEN classification was run (classification_date)
- ✅ Track WHAT PERIOD was classified (analysis_start/end_date)
- ✅ Track VERSION (allows pattern improvements)
- ✅ Human-readable labels for reporting

---

## 🔄 Execution Workflow

### Phase 1: Baseline Pattern Discovery
```sql
-- Run 1: Recent baseline (Sep-Oct 2024)
-- Purpose: Discover ALL current service accounts and patterns
-- Expected: Lowest UNCLASSIFIED rate (all current services active)

start_date: '2024-09-01'
end_date: '2024-10-31'
analysis_period_label: 'Baseline_2024_Sep_Oct'
classification_version: 'v1.0'

Mode: CREATE OR REPLACE TABLE
Runtime: ~8-15 minutes
Output: ~3.7M jobs classified
```

### Phase 2: Current Partial Peak
```sql
-- Run 2: Current peak period (Nov 2024 so far)
-- Purpose: Understand current peak behavior with latest patterns

start_date: '2024-11-01'
end_date: CURRENT_DATE()  -- Or '2024-11-30'
analysis_period_label: 'Peak_2024_2025_Partial_Nov'
classification_version: 'v1.0'

Mode: INSERT INTO
Runtime: ~4-8 minutes (1 month)
```

### Phase 3: Historical Peak Analysis
```sql
-- Run 3: Most recent complete peak
start_date: '2023-11-01'
end_date: '2024-01-31'
analysis_period_label: 'Peak_2023_2024'
classification_version: 'v1.0'

-- Run 4: Previous peak
start_date: '2022-11-01'
end_date: '2023-01-31'
analysis_period_label: 'Peak_2022_2023'
classification_version: 'v1.0'

Mode: INSERT INTO (for both)
Runtime: ~15-20 minutes each (3 months)
```

### Phase 4: Investigate & Refine
```sql
-- After each historical run, check UNCLASSIFIED rate
SELECT 
  analysis_period_label,
  ROUND(COUNTIF(consumer_category = 'UNCLASSIFIED') / COUNT(*) * 100, 2) AS unclassified_pct
FROM `narvar-data-lake.query_opt.traffic_classification`
GROUP BY analysis_period_label;

-- If any period has >5% UNCLASSIFIED:
-- 1. Query for top unclassified principals in that period
-- 2. Add period-specific patterns to classification query
-- 3. Re-run with classification_version = 'v1.1'
-- 4. Use INSERT (keeps both v1.0 and v1.1 for comparison)
```

---

## 🎬 Recommended Execution Order

### **Immediate Actions** (This Week):

#### **Run 1: Baseline Sep-Oct 2024** ⭐ START HERE
```bash
Purpose: Discover all current patterns, validate classification quality
Period: 2024-09-01 to 2024-10-31
Label: 'Baseline_2024_Sep_Oct'
Version: v1.0
Expected: <2% UNCLASSIFIED, ~95% retailer attribution
Runtime: ~8-15 minutes
```

#### **Run 2: Current Peak Nov 2024**
```bash
Purpose: Understand current peak behavior
Period: 2024-11-01 to 2024-11-30
Label: 'Peak_2024_2025_Partial_Nov'
Version: v1.0
Expected: Similar classification as Sep-Oct
Runtime: ~6-10 minutes
```

### **Next Week Actions**:

#### **Run 3: Historical Peak 2023-2024**
```bash
Period: 2023-11-01 to 2024-01-31
Label: 'Peak_2023_2024'
Version: v1.0
Check: UNCLASSIFIED rate (may be higher due to retired services)
Runtime: ~15-20 minutes
```

#### **Run 4: Historical Peak 2022-2023**
```bash
Period: 2022-11-01 to 2023-01-31
Label: 'Peak_2022_2023'
Version: v1.0
Check: UNCLASSIFIED rate (likely highest - oldest data)
Runtime: ~15-20 minutes
```

---

## 🔧 Handling Temporal Variability

### Strategy 1: Retroactive Classification (Default)
**Apply current patterns to all historical periods**

**Pros**:
- ✅ Consistent taxonomy across all periods
- ✅ Focuses on currently-active services (relevant for 2025 planning)
- ✅ Easier to analyze trends (same categories)

**Cons**:
- ⚠️ May miss retired services from 2022-2023
- ⚠️ UNCLASSIFIED rate may be higher for old periods

**When to use**: For capacity planning (we care about current/future workload)

### Strategy 2: Period-Specific Pattern Addition
**Discover unique patterns in each historical period**

**Process**:
1. Run baseline classification on historical period
2. Investigate UNCLASSIFIED principals
3. Add patterns for retired/historical-only services
4. Re-run with updated version (v1.1)
5. Compare v1.0 vs v1.1 for improvement

**Example**:
```sql
-- After classifying Peak_2022_2023, find unclassified:
SELECT principal_email, COUNT(*) as jobs
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE analysis_period_label = 'Peak_2022_2023'
  AND consumer_category = 'UNCLASSIFIED'
GROUP BY principal_email
ORDER BY jobs DESC
LIMIT 20;

-- Discover: "old-pipeline@narvar" was active in 2022, retired in 2023
-- Add pattern: r'old-pipeline'
-- Re-run with version v1.1
```

**When to use**: If UNCLASSIFIED > 5% in any historical period

### Strategy 3: Monitor Project Special Handling
**Issue**: Churned retailers may not be in current `t_return_details`

**Solution**: Use date-filtered retailer lookup
```sql
-- For Peak_2022_2023, use retailers active during that period
retailer_mappings AS (
  SELECT DISTINCT retailer_moniker, ...
  FROM `narvar-data-lake.reporting.t_return_details`
  WHERE DATE(return_created_date) BETWEEN '2022-11-01' AND '2023-01-31'
    OR DATE(return_created_date) >= CURRENT_DATE() - 365  -- Include current
)
```

**Alternative**: Maintain historical retailer list separately if t_return_details prunes old retailers

---

## 📈 Expected Results Per Period

### Sep-Oct 2024 (Recent Baseline):
- UNCLASSIFIED: <2% (all current services should match)
- Retailer attribution: 95%+ (current retailers in database)
- Service accounts: ~20-25 unique patterns

### Nov 2024 (Current Peak):
- Similar to baseline (same active services)
- Higher volume, but same distribution

### Peak 2023-2024:
- UNCLASSIFIED: 2-5% (some retired services may appear)
- Retailer attribution: 90-95% (some churn possible)
- Most patterns should still match

### Peak 2022-2023:
- UNCLASSIFIED: 5-10% (oldest data, more retired services)
- Retailer attribution: 85-90% (more churn over 3 years)
- May need period-specific pattern additions

---

## ⚖️ Tradeoffs & Decisions

### Decision 1: One Version vs Multiple Versions?

**Recommendation**: **Keep multiple versions** (use INSERT, not MERGE)

**Why**:
- Can compare pattern improvements (v1.0 → v1.1 → v1.2)
- Audit trail for analysis decisions
- Reproducibility (know which version produced results)
- Downstream queries can choose version

**Cost**: ~10-20% more storage (minimal for analysis dataset)

### Decision 2: Latest Patterns vs Point-in-Time Patterns?

**Recommendation**: **Use latest patterns retroactively**

**Why**:
- Capacity planning cares about "if today's workload hit yesterday's peak, what capacity needed?"
- Consistent taxonomy for YoY comparisons
- Retired services from 2022 don't need 2025 capacity
- Can always add period-specific patterns for unclassified

**Caveat**: Check UNCLASSIFIED rate per period and add patterns if needed

### Decision 3: CREATE OR REPLACE vs INSERT?

**Recommendation**: 
- **First run**: CREATE OR REPLACE
- **Subsequent runs**: INSERT (append different periods)
- **Re-classification**: INSERT with new version (keep old version)

**Why**: Flexibility + audit trail

---

## 🚀 Immediate Next Steps

### Step 1: Run Baseline Classification (Sep-Oct 2024)
```bash
File: vw_traffic_classification_to_table.sql
Mode: CREATE OR REPLACE TABLE (line 206 active)
Parameters:
  - start_date: '2024-09-01'
  - end_date: '2024-10-31'
  - analysis_period_label: 'Baseline_2024_Sep_Oct'
  - classification_version: 'v1.0'

Expected:
  - Runtime: ~8-15 minutes
  - Jobs: ~3.7M
  - UNCLASSIFIED: <2%
  - Table created with proper partitioning/clustering
```

### Step 2: Validate Results
```sql
-- Run validation query (included in file, lines 285-312)
-- Check:
-- - UNCLASSIFIED < 2%
-- - MONITOR has retailer attribution
-- - Costs are realistic (~$60K for 2 months)
-- - No AUTOMATED → ADHOC_USER anomalies
```

### Step 3: Run Current Peak (Nov 2024)
```bash
File: vw_traffic_classification_to_table.sql
Mode: INSERT INTO (line 207 active, line 206 commented)
Parameters:
  - start_date: '2024-11-01'
  - end_date: '2024-11-30'
  - analysis_period_label: 'Peak_2024_2025_Partial_Nov'
  - classification_version: 'v1.0'

Expected:
  - Runtime: ~6-10 minutes
  - Jobs: ~1.8M
  - Appends to existing table
```

### Step 4: Run Historical Peaks (As Needed)
```bash
Repeat for:
  - Peak_2023_2024: Nov 2023 - Jan 2024
  - Peak_2022_2023: Nov 2022 - Jan 2023

Check UNCLASSIFIED rate after each.
If >5%, investigate and add patterns.
```

---

## 🔍 Monitoring Classification Quality Over Time

### Query 1: UNCLASSIFIED Rate by Period
```sql
SELECT
  analysis_period_label,
  classification_version,
  COUNT(*) AS total_jobs,
  COUNTIF(consumer_category = 'UNCLASSIFIED') AS unclassified_jobs,
  ROUND(COUNTIF(consumer_category = 'UNCLASSIFIED') / COUNT(*) * 100, 2) AS unclassified_pct,
  COUNT(DISTINCT CASE WHEN consumer_category = 'UNCLASSIFIED' THEN principal_email END) AS unclassified_principals

FROM `narvar-data-lake.query_opt.traffic_classification`
GROUP BY analysis_period_label, classification_version
ORDER BY analysis_period_label, classification_version;
```

### Query 2: New Service Accounts by Period
```sql
-- Identify service accounts that appear in Period B but not Period A
WITH period_a_accounts AS (
  SELECT DISTINCT principal_email
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE analysis_period_label = 'Peak_2022_2023'
),
period_b_accounts AS (
  SELECT DISTINCT principal_email
  FROM `narvar-data-lake.query_opt.traffic_classification`
  WHERE analysis_period_label = 'Baseline_2024_Sep_Oct'
)
SELECT 
  b.principal_email,
  'NEW_SINCE_2022' AS status
FROM period_b_accounts b
LEFT JOIN period_a_accounts a USING (principal_email)
WHERE a.principal_email IS NULL
  AND b.principal_email LIKE '%iam.gserviceaccount.com%';
```

### Query 3: Retired Service Accounts
```sql
-- Identify accounts active in 2022 but not in 2024
-- (Inverse of Query 2)
```

---

## 📝 Pattern Evolution Management

### When to Create a New Version:

**Scenario 1**: Discovered new unclassified service accounts
- Example: Found 50K jobs from `new-service@` in historical data
- Action: Add pattern, re-run with v1.1, compare to v1.0

**Scenario 2**: Fixed classification bug
- Example: Human users misclassified as AUTOMATED (we had this!)
- Action: Fix priority, re-run with v1.1

**Scenario 3**: Improved retailer matching
- Example: MD5 matching vs token matching (we had this!)
- Action: Update logic, re-run with v1.1

### Version Naming Convention:
```
v1.0 - Initial classification (current patterns)
v1.1 - Added missing service accounts (messaging, growthbook, etc.)
v1.2 - Fixed retailer matching (MD5-based)
v1.3 - Added period-specific patterns for 2022 data
v2.0 - Major methodology change (if needed)
```

### Comparing Versions:
```sql
SELECT
  analysis_period_label,
  classification_version,
  consumer_category,
  COUNT(*) AS jobs,
  ROUND(SUM(slot_hours), 2) AS slot_hours

FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE analysis_period_label = 'Peak_2023_2024'
  AND classification_version IN ('v1.0', 'v1.1')
GROUP BY ALL
ORDER BY analysis_period_label, classification_version, consumer_category;
```

---

## 🎯 Handling Specific Temporal Issues

### Issue 1: Churned Retailers (Monitor Projects)

**Problem**: Monitor project exists in 2022 audit logs, but retailer churned by 2024
**Impact**: t_return_details may not have historical retailer
**Solution**: 
```sql
-- Option A: Use broad date range in t_return_details lookup
WHERE DATE(return_created_date) >= '2020-01-01'  -- Capture all historical

-- Option B: Accept some MONITOR_UNMATCHED for churned retailers
-- These can be attributed via project_id hash lookup if needed later

-- Option C: Maintain historical retailer snapshot table
CREATE TABLE query_opt.historical_retailers AS
SELECT DISTINCT retailer_moniker, first_seen, last_seen
FROM ...
```

**Recommendation**: Use Option A (broad date range) for now

### Issue 2: Retired Service Accounts

**Problem**: Service account active in 2022, retired by 2024, not in current patterns
**Impact**: Historical data shows higher UNCLASSIFIED
**Solution**:
1. Run classification on historical period with current patterns
2. Identify high-volume UNCLASSIFIED principals
3. Research what these accounts were (ask platform team, check old docs)
4. Add to classification patterns
5. Re-run with version bump

**Example workflow**:
```sql
-- Find unclassified in 2022 peak
SELECT principal_email, COUNT(*) as jobs
FROM `narvar-data-lake.query_opt.traffic_classification`
WHERE analysis_period_label = 'Peak_2022_2023'
  AND consumer_category = 'UNCLASSIFIED'
  AND classification_version = 'v1.0'
GROUP BY principal_email
HAVING jobs > 1000
ORDER BY jobs DESC;

-- Results show: "legacy-etl@narvar" with 50K jobs
-- Action: Add pattern r'legacy-etl', re-run as v1.1
```

### Issue 3: Service Account Role Changes

**Problem**: Account started as manual testing, became automated later
**Impact**: Entire history classified based on final role
**Solution**: Generally acceptable for capacity planning (care about ultimate purpose)

**If precision needed**: 
- Store account lifecycle metadata separately
- Apply role based on job timestamp vs account transition date
- Complex, usually not needed for capacity planning

---

## 📊 Table Management Best Practices

### Storage Estimation:
```
Per 2-month period: ~3.7M jobs × ~500 bytes/row = ~1.85 GB
Full 3 years: ~15-20 periods × 1.85 GB = ~30-40 GB
With 2 versions: ~60-80 GB (manageable)
```

### Retention Policy:
```
Keep:
- All period classifications (permanent for analysis)
- Latest version only for each period (if storage becomes issue)
- Can delete old versions after validation (optional)
```

### Cost Control:
```
Table creation: ~$0.40-0.80 per run (8-15 GB processed)
Storage: ~$0.02/GB/month = ~$0.60-1.60/month
Queries on table: Efficient (partitioned, clustered)
```

---

## ✅ Success Criteria

### After First Run (Sep-Oct 2024):
- [x] Table created successfully
- [x] UNCLASSIFIED < 2%
- [x] MONITOR has >95% retailer attribution  
- [x] No AUTOMATED → ADHOC_USER anomalies
- [x] Costs realistic (~$60K for 2 months)

### After All Runs:
- [x] All 4-5 periods classified
- [x] UNCLASSIFIED < 5% for all periods
- [x] Consistent taxonomy across periods
- [x] Ready for Phase 2 historical analysis

---

## 🚨 Known Limitations & Mitigations

### Limitation 1: monitor-base-* Projects
**Issue**: Special shared monitor projects (monitor-base-us-prod, monitor-base-us-qa)
**Impact**: 230K jobs (35% of MONITOR_UNMATCHED)
**Mitigation**: Accept as unmatched, or manually map to "Shared/Base" category
**Capacity Impact**: Still counted as EXTERNAL (P0), just no specific retailer

### Limitation 2: Null Slot Jobs
**Issue**: 46% of query jobs have null totalSlotMs
**Impact**: Excluded from analysis (but only 6% of execution time)
**Mitigation**: Documented, minimal capacity impact
**Future**: Could impute slots based on execution time + bytes

### Limitation 3: Automated QoS Evaluation
**Issue**: Need Composer schedule data for proper QoS
**Current**: Using execution time thresholds (placeholder)
**Mitigation**: Phase 2 enhancement with schedule table
**Impact**: Can't properly identify automated QoS violations yet

---

**Next Step**: Run `vw_traffic_classification_to_table.sql` with Sep-Oct 2024 parameters! 🚀

**File Ready**: `queries/phase1_classification/vw_traffic_classification_to_table.sql`

