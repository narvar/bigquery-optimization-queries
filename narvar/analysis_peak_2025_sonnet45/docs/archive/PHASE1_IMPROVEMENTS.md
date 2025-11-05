# Phase 1 Classification - Improvements Applied

**Date**: November 5, 2025  
**Status**: Ready for Re-validation Testing

---

## 🎯 Issues Identified & Fixed

### Issue #1: Incorrect Cost Calculation ✅ FIXED
**Problem**: Queries used on-demand pricing ($5/TB) instead of slot-based pricing  
**Impact**: Costs were overstated by ~6-7x  
**Solution**: Updated to slot-based pricing with blended rate

**Changes**:
- Changed from: `bytes / 1TB * $5` 
- Changed to: `slot_hours * $0.0494`
- Blended rate calculation: `(500×$0.048 + 500×$0.036 + 700×$0.06) / 1700 = $0.0494/slot-hour`

**Corrected Costs (Oct-Nov 2024)**:
- AUTOMATED: ~$67,189 (was $390K)
- EXTERNAL: ~$32,935 (was $76K)
- INTERNAL: ~$14,676 (was $140K)
- **Total: ~$115K for 2 months**

**Files Updated**:
- `vw_traffic_classification.sql`
- `external_consumer_classification.sql`
- `automated_process_classification.sql`
- `internal_user_classification.sql`

---

### Issue #2: Monitor Project Retailer Matching Failed (0% success rate) ✅ FIXED
**Problem**: Using token-based regex matching against `manual_retailer_categories` - 0% success rate  
**Impact**: 407,640 jobs (70% of external traffic) had no retailer attribution  
**Root Cause**: Monitor projects use MD5-hashed naming: `monitor-{MD5_HASH}-us-{env}`

**Diagnostic Results**:
```
Top unmatched projects:
- monitor-base-us-prod: 146K jobs (35.95%)
- monitor-base-us-qa: 23K jobs (5.74%)
- Various monitor-{hash}-us-{env} projects
```

**Solution**: Changed to MD5-based matching using `t_return_details`
```sql
-- Old (token-based, 0% match):
REGEXP_CONTAINS(project_id, retailer_token)

-- New (MD5-based, expects ~95%+ match):
CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-{env}')
```

**Expected Result**: 95%+ of monitor projects should now match to retailers  
**Remaining unmatched**: Only `monitor-base-*` projects (shared/test environments)

**Files Updated**:
- `vw_traffic_classification.sql`
- `external_consumer_classification.sql`

---

### Issue #3: Missing Service Account Classifications ✅ FIXED
**Problem**: 281,116 jobs (7.4%) classified as `SERVICE_ACCOUNT_OTHER`  
**Impact**: Cannot properly allocate slots without knowing if they're AUTOMATED or INTERNAL

**Top Unclassified Accounts**:
1. **messaging@narvar-data-lake** - 188K jobs (67% of unclassified!)
2. **service-qa-automation-bigquery** - 71K jobs
3. **shopify-zero-runner** - 14K jobs
4. **ipaas-integration-bq** - 2K jobs
5. **growthbook**, **metric-layer**, **retool**, **doit-cmp**, etc.

**Solution**: Added 12+ new regex patterns for automated service accounts

**New Patterns Added**:
```sql
-- Messaging service (BIG ONE - 67% of unclassified)
r'^messaging@'

-- Integrations
r'shopify.*runner'
r'ipaas-integration'

-- Internal platforms
r'growthbook'
r'metric-layer'
r'retool'

-- Monitoring/infrastructure
r'doit-cmp'
r'gcp-sa-bigquerydatatransfer'
r'gcp-sa-aiplatform'

-- Domain services
r'(nub-tenant|carrierstest|service-samoa)@'
```

**Expected Result**: UNCLASSIFIED should drop from 7.4% to <2%

**Files Updated**:
- `vw_traffic_classification.sql`

---

### Issue #4: Human Users Misclassified as AUTOMATED ✅ FIXED
**Problem**: 5,352 jobs from 21 human users (@narvar.com) classified as AUTOMATED  
**Impact**: Internal employee queries counted as automated processes  
**Root Cause**: Classification checked project patterns (CDP/ML) BEFORE email patterns

**Examples of Misclassified Users**:
- prasanth.vamsi@narvar.com in narvar-cdp-us-prod: 1,296 jobs
- ankur.marchattiwar@narvar.com in narvar-ml-prod: 1,182 jobs
- kunal.arneja@narvar.com in narvar-ml-prod: 1,098 jobs

**Solution**: 
1. Moved `@narvar.com` check BEFORE project pattern checks
2. Removed project-based classification for CDP/ML (only check principal email)

**Classification Priority (Fixed)**:
```
1. Service account patterns (airflow, composer, gke, etc.)
2. @narvar.com employees → INTERNAL
3. Project patterns no longer override email patterns
```

**Expected Result**: All 5,352 jobs should now be INTERNAL → ADHOC_USER

**Files Updated**:
- `vw_traffic_classification.sql`

---

## 📊 Expected Improved Results

### Classification Coverage (Target):
- **EXTERNAL**: ~13% (should stay similar, but 95%+ should have retailer attribution)
- **AUTOMATED**: ~76% (was 71%, adding messaging + others)
- **INTERNAL**: ~10% (was 9%, adding back the 5K misclassified users)
- **UNCLASSIFIED**: <2% (down from 7.4%)

### Retailer Attribution (Target):
- **MONITOR (matched)**: ~95% of monitor projects
- **MONITOR_UNMATCHED**: ~5% (only monitor-base and edge cases)

### Cost Accuracy:
- All costs now calculated using slot-hours × $0.0494
- Expected total: ~$115K for 2 months (Oct-Nov 2024)

---

## 🚀 Next Steps

### 1. Re-run Classification Query
Run updated `vw_traffic_classification.sql` to validate improvements

**Expected Improvements**:
- ✅ UNCLASSIFIED: 7.4% → <2%
- ✅ MONITOR with retailer: 0% → 95%+
- ✅ Costs: Realistic ($115K vs $600K)
- ✅ Human users: AUTOMATED → INTERNAL

### 2. Validate Results
Check the summary statistics:
```sql
SELECT
  consumer_category,
  consumer_subcategory,
  COUNT(*) AS jobs,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 2) AS pct,
  COUNT(DISTINCT retailer_moniker) AS unique_retailers
FROM traffic_classified
GROUP BY consumer_category, consumer_subcategory
ORDER BY jobs DESC;
```

### 3. Proceed to Phase 2
Once classification is validated (<5% unclassified), move to historical analysis!

---

## 📝 Technical Notes

### Retailer Matching Logic
Monitor projects follow naming convention:
```
monitor-{7_char_md5_hash}-us-{environment}

Example:
retailer: "fashionnova"
MD5: TO_HEX(MD5("fashionnova")) = "0006f9c..."
Project: "monitor-0006f9c-us-prod"
```

### Service Account Patterns
Now covers:
- Airflow/Composer orchestration
- GKE/Compute workloads
- ML/AI inference (eddmodel)
- Analytics API, CDP
- Messaging (high volume!)
- Integration platforms (Shopify, iPaaS)
- Internal tools (GrowthBook, Retool, Metric Layer)
- Google managed services (Data Transfer, AI Platform)

### Classification Priority Order
1. Monitor projects (by project ID) → EXTERNAL
2. Hub services (Looker) → EXTERNAL
3. Service account patterns → AUTOMATED
4. @narvar.com emails → INTERNAL (this was moved UP)
5. Metabase, n8n → INTERNAL
6. Everything else → UNCLASSIFIED

---

**Last Updated**: November 5, 2025  
**Next Validation**: Re-run vw_traffic_classification.sql with improvements

