## BigQuery Peak Capacity Planning - Implementation Status

**Last Updated**: 2025-10-31
**Project Phase**: Phase 1 (Traffic Classification & Data Validation)

---

## ✅ Completed Work

### Project Structure
- [x] Created complete folder structure
- [x] README.md with project overview and quick start guide
- [x] This status document

### Phase 1: Traffic Classification Queries

#### Utility Queries (Ready to Run)
1. **`queries/utils/validate_audit_log_completeness.sql`** ✅
   - Validates audit log data availability for 3 peak periods (Nov-Jan 2022/23, 2023/24, 2024/25)
   - Identifies data gaps, quality issues, and coverage metrics
   - **Action Required**: Run this query FIRST to confirm data quality

2. **`queries/utils/extract_airflow_service_accounts.sql`** ✅
   - Identifies potential Airflow/Composer service accounts using pattern analysis
   - Scores accounts by automation likelihood
   - **Action Required**: Run and review results, then update classification queries

3. **`queries/utils/metabase_user_mapping.sql`** ✅
   - Extracts Metabase user IDs from query comments
   - Tests multiple comment format patterns
   - **Action Required**: Run to validate comment format, then configure Metabase DB join

#### Classification Queries (Need Configuration)
4. **`queries/phase1_classification/external_consumer_classification.sql`** ✅
   - Classifies external consumers (monitor projects, Hub traffic)
   - Maps monitor projects to retailers
   - Evaluates QoS (60-second threshold)
   - **Status**: Ready to run after data validation

5. **`queries/phase1_classification/automated_process_classification.sql`** ⚠️
   - Classifies automated processes (Airflow, CDP, ETL)
   - **Needs**: User to populate `automated_service_accounts` array
   - **Action Required**: Update line 30-35 with actual service account list

6. **`queries/phase1_classification/internal_user_classification.sql`** ✅
   - Classifies internal users (Metabase, ad-hoc queries)
   - Extracts Metabase user IDs
   - Evaluates QoS (480-second threshold)
   - **Status**: Ready to run

7. **`queries/phase1_classification/vw_traffic_classification.sql`** ⚠️
   - **MASTER VIEW**: Combines all three classification queries
   - Single source of truth for all downstream analysis
   - **Needs**: `automated_service_accounts` array populated
   - **Action Required**: Update after configuring automated_process_classification.sql

### Phase 2: Historical Analysis Queries

8. **`queries/phase2_historical/peak_vs_nonpeak_analysis.sql`** ✅
   - Compares 3 years of peak vs. non-peak traffic patterns
   - Aggregates by consumer category, hour, day of week
   - Calculates slot usage, costs, and performance metrics
   - **Status**: Ready to run after Phase 1 configuration

9. **`queries/phase2_historical/qos_violations_historical.sql`** ✅
   - Identifies QoS violations across historical peak periods
   - Analyzes violation severity and patterns
   - Includes slot starvation detection logic
   - **Status**: Ready to run after Phase 1 configuration

---

## ⏳ Pending Work

### Phase 2: Historical Analysis (Remaining Queries)
- [ ] `queries/phase2_historical/slot_heatmap_analysis.sql`
- [ ] `queries/phase2_historical/yoy_growth_analysis.sql`

### Phase 3: Prediction Queries
- [ ] `queries/phase3_prediction/traffic_projection_2025.sql`
- [ ] `queries/phase3_prediction/predicted_qos_impact_2025.sql`
- [ ] `queries/phase3_prediction/bottleneck_identification_2025.sql`

### Phase 4: Simulation Queries
- [ ] `queries/phase4_simulation/slot_allocation_simulator.sql`
- [ ] `queries/phase4_simulation/cost_benefit_analysis.sql`
- [ ] `queries/phase4_simulation/simulation_results_summary.sql`

### Phase 5: Documentation
- [ ] `docs/PRD_BQ_Peak_Capacity_2025.md` (comprehensive PRD)
- [ ] `docs/IMPLEMENTATION_GUIDE.md` (technical guide)
- [ ] `docs/SIMULATION_METHODOLOGY.md` (slot simulation approach)

---

## 🔴 Critical User Inputs Required

### Priority 1: Must Have (Blocks Phase 1 Completion)

#### 1. Airflow/Composer Service Accounts
**What**: List of service accounts used by Airflow/Composer for automated jobs

**How to Obtain**:
- Option A: Run `queries/utils/extract_airflow_service_accounts.sql` and review recommendations
- Option B: Consult with Airflow/Composer team for official list
- Option C: Check Composer configuration in `bq-narvar-admin` project

**Where to Update**:
- `queries/phase1_classification/automated_process_classification.sql` (lines 30-35)
- `queries/phase1_classification/vw_traffic_classification.sql` (lines 34-36)
- All Phase 2, 3, 4 queries (DECLARE section)

**Example Format**:
```sql
DECLARE automated_service_accounts ARRAY<STRING> DEFAULT [
  'airflow-prod@narvar-data-lake.iam.gserviceaccount.com',
  'composer-scheduler@narvar-data-lake.iam.gserviceaccount.com',
  'cdp-sync@narvar-data-lake.iam.gserviceaccount.com'
];
```

#### 2. Hub Traffic Attribution Logic
**What**: Method to attribute Hub (Looker) traffic to specific retailers

**Current Assumption**: Using service account `looker-prod@narvar-data-lake.iam.gserviceaccount.com`

**Questions**:
- Can Hub queries be attributed to individual retailers?
- Is there metadata in query text, labels, or other fields?
- Should Hub be classified as External (as currently assumed) or separate category?

**Where to Update**:
- `queries/phase1_classification/external_consumer_classification.sql` (attribution logic)
- All classification queries (if category changes)

#### 3. Metabase Query Comment Format
**What**: Exact format of user ID in Metabase query comments

**How to Validate**:
- Run `queries/utils/metabase_user_mapping.sql` (uncomment PATTERN ANALYSIS section)
- Review sample Metabase queries

**Current Assumptions** (testing 3 patterns):
```sql
-- Pattern 1: -- Metabase:: userID: 123
-- Pattern 2: /* Metabase userID: 123 */
-- Pattern 3: -- metabase_user_id=123
```

**Where to Update**: 
- `queries/utils/metabase_user_mapping.sql` (REGEXP patterns if different)
- `queries/phase1_classification/internal_user_classification.sql` (lines 94-98)
- `queries/phase1_classification/vw_traffic_classification.sql` (lines 84-88)

### Priority 2: Important (Enhances Analysis Quality)

#### 4. Composer DAG Schedules and SLAs
**What**: Airflow/Composer DAG schedules to calculate proper QoS for automated processes

**Current Workaround**: Using 30-minute threshold as placeholder

**Needed**:
- Table or view with: `dag_id`, `schedule_interval`, `expected_execution_time`, `sla_seconds`
- Or: BigQuery connection to Composer metadata DB

**Usage**: Phase 2 QoS analysis, Phase 3 predictions

#### 5. Metabase Database Connection
**What**: Access to Metabase DB to map user IDs to user emails

**Current Workaround**: Using `metabase_user_id` as identifier

**Needed**:
- BigQuery external connection or linked resource to Metabase DB
- Typical schema: `metabase.users` table with columns: `id`, `email`, `first_name`, `last_name`

**Where to Update**:
- `queries/utils/metabase_user_mapping.sql` (uncomment JOIN section)
- `queries/phase1_classification/internal_user_classification.sql` (add JOIN)
- `queries/phase1_classification/vw_traffic_classification.sql` (add JOIN)

### Priority 3: Nice to Have (Improves Analysis)

#### 6. Known Business Changes for 2025 Peak
**What**: Information about expected business changes that could affect traffic patterns

**Examples**:
- New major retailers launching (monitor projects)
- Retired/deprecated services
- New automated pipelines
- Planned infrastructure changes

**Usage**: Phase 3 traffic projection adjustments

#### 7. Historical Incidents or Anomalies
**What**: Known outages, incidents, or unusual events during historical peak periods

**Why**: To exclude anomalous data from trend analysis

**Examples**:
- Specific dates with outages
- Data pipeline failures causing retry storms
- One-time data migrations

---

## 🎯 Recommended Next Steps

### Step 1: Data Validation (15 minutes)
```bash
# Run in BigQuery console
# Query: queries/utils/validate_audit_log_completeness.sql
# Review output for gaps or quality issues
```

**Expected Output**:
- Daily record counts for 2022-2025
- Gap detection (should be minimal)
- Data quality metrics (null rates should be <5%)

**Decision Point**: If data quality is poor, may need to adjust analysis approach

### Step 2: Service Account Discovery (30 minutes)
```bash
# Run in BigQuery console
# Query: queries/utils/extract_airflow_service_accounts.sql
# Review accounts with recommendation "✓ INCLUDE in Automated Process list"
```

**Expected Output**:
- List of service accounts ranked by automation likelihood
- Recommendations for which to include

**Action**: Create final service account list and update queries

### Step 3: Metabase Format Validation (10 minutes)
```bash
# Run in BigQuery console
# Query: queries/utils/metabase_user_mapping.sql
# Check pattern analysis results
```

**Expected Output**:
- Count of queries matching each pattern
- Sample queries with extracted user IDs

**Action**: Confirm pattern works or adjust REGEXP

### Step 4: Update Configuration (30 minutes)
**Files to Update**:
1. `automated_process_classification.sql` - Add service accounts
2. `vw_traffic_classification.sql` - Add service accounts
3. Copy service account DECLARE to all Phase 2+ queries

**Validation**: Run `vw_traffic_classification.sql` on small date range (1 day) to test

### Step 5: Run Phase 1 Classification (1-2 hours)
**Order**:
1. `external_consumer_classification.sql` (baseline: 1 month)
2. `automated_process_classification.sql` (baseline: 1 month)
3. `internal_user_classification.sql` (baseline: 1 month)
4. `vw_traffic_classification.sql` (baseline: 1 month)

**Expected Results**:
- 95%+ of traffic should be classified (not 'UNCLASSIFIED')
- Reasonable distribution across categories
- QoS metrics calculated

**Validation Checks**:
```sql
-- Check classification coverage
SELECT 
  consumer_category,
  COUNT(*) as job_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 2) as pct_of_total
FROM [vw_traffic_classification_results]
GROUP BY consumer_category
ORDER BY job_count DESC;

-- Should see:
-- EXTERNAL: ~20-40%
-- AUTOMATED: ~30-50%
-- INTERNAL: ~20-30%
-- UNCLASSIFIED: <5%
```

### Step 6: Run Phase 2 Historical Analysis (2-4 hours)
Once Phase 1 is validated:
1. `peak_vs_nonpeak_analysis.sql` (full 3-year history)
2. `qos_violations_historical.sql` (full 3-year history)
3. Remaining Phase 2 queries (to be created)

---

## 📊 Expected Analysis Timeline

| Phase | Duration | Prerequisites | Deliverables |
|-------|----------|---------------|--------------|
| **Data Validation** | 0.5 days | None | Data quality report |
| **Phase 1 Configuration** | 1 day | User inputs 1-3 | Service account list, validated patterns |
| **Phase 1 Execution** | 1-2 days | Configuration complete | Traffic classification (95%+ coverage) |
| **Phase 2 Analysis** | 3-4 days | Phase 1 complete | Peak patterns, QoS violations, growth rates |
| **Phase 3 Prediction** | 2-3 days | Phase 2 complete | 2025 peak forecasts |
| **Phase 4 Simulation** | 4-5 days | Phase 3 complete | Slot allocation recommendations |
| **Phase 5 Documentation** | 2-3 days | Phase 4 complete | PRD and implementation guide |
| **Total** | **13-18 days** | All inputs provided | Complete analysis and recommendations |

---

## 🔧 Troubleshooting

### Issue: High percentage of UNCLASSIFIED traffic
**Cause**: Service account list incomplete or classification logic too restrictive

**Solution**:
1. Run `extract_airflow_service_accounts.sql` to find missing accounts
2. Review UNCLASSIFIED queries for patterns
3. Add additional classification rules

### Issue: QoS violation rates seem too high/low
**Cause**: Thresholds may not match actual business requirements

**Solution**:
1. Review sample violations with business stakeholders
2. Adjust thresholds in DECLARE section
3. Re-run analysis with updated thresholds

### Issue: Data gaps in historical analysis
**Cause**: Audit log collection issues or data retention limits

**Solution**:
1. Check `validate_audit_log_completeness.sql` output for specific gaps
2. Exclude gap periods from trend analysis
3. Document data limitations in final report

### Issue: Query costs too high
**Cause**: Large date ranges without proper filtering

**Solution**:
1. Always use DECLARE date parameters
2. Start with 1-month baseline tests
3. Use dry-run for cost estimation before full runs
4. Consider materializing intermediate results as tables

---

## 📝 Notes

- All queries use parameterized dates via DECLARE statements
- Queries follow existing audit_log patterns from `narvar/audit_log/` folder
- Cost control: Include estimated bytes in query comments, warn on >10GB
- Testing: Always run dry_run first for large date ranges
- Reusability: All queries designed for future peak planning (parameterized)

---

## 📞 Support

**Questions or Issues?**
- Review this document first
- Check README.md for query documentation
- Consult `narvar/audit_log/QUERY_SUMMARY.md` for audit log patterns

**Need Help With**:
- Service account identification → `extract_airflow_service_accounts.sql`
- Metabase format → `metabase_user_mapping.sql`
- Data quality → `validate_audit_log_completeness.sql`




