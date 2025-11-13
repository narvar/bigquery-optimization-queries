# Next Session: SQL Query Semantic Analysis Framework - Sub-Project

**Use this as your starting prompt for the SQL Semantic Analysis sub-project session**

---

```markdown
I'm building a **reusable SQL Query Semantic Analysis Framework** to understand business intent from BigQuery query logs.

**PROJECT CONTEXT**:
- **Parent Project**: BigQuery capacity optimization for Narvar (Peak 2025-2026)
- **Completed (Nov 12, 2025)**: Analyzed **1.25M queries** across **3 platforms**:
  * Hub Analytics API (ANALYTICS_API): 812K queries, 80.3% retailer attribution, 0% violations
  * Looker (HUB): 236K queries, 72.9% retailer attribution, 2.6% violations
  * Monitor (MONITOR): 205K queries, 100% retailer attribution, 2.21% violations
- **Current Need**: Understand which **business functions** are most important to users (e.g., Return Analysis, Delivery Tracking, Order Status)
- **Broader Goal**: Create reusable framework for any SQL log analysis scenario (Metabase, Airflow, etc.)

**WHY THIS MATTERS**:
1. **Optimization Focus**: Prioritize queries that matter most to business
2. **Governance**: Identify critical data assets (tables, columns)
3. **User Support**: Understand user intent when queries fail
4. **Capacity Planning**: Predict load based on business cycles
5. **Cost Attribution**: Attribute costs to business functions, not just users

**SPECIFIC ANALYTICAL DIMENSIONS TO EXTRACT**:
1. **Time Filtering Patterns**:
   - How far back in time are queries looking? (1 day, 7 days, 30 days, 90 days, 1 year, all-time)
   - Are users looking at recent data vs historical trends?
   - Outlier detection: Queries scanning unnecessarily large time ranges
   - Common patterns: `WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL X DAY/MONTH/YEAR)`
   - Distribution: % of queries by lookback period (recent vs historical)

2. **Query Granularity** (Transactional vs Aggregated):
   - **Transactional Lookups**: Specific entity queries (tracking_number, order_number, shipment_id, return_id)
     * Pattern: `WHERE tracking_number = 'ABC123'`
     * Use case: "Find status of specific shipment"
   - **Aggregated Analytics**: Grouped by attributes (carrier, region, locale, country, retailer, product_category)
     * Pattern: `GROUP BY carrier, region`
     * Use case: "Carrier performance by region"
   - **Granularity distribution**: % transactional vs % aggregated queries

3. **Geographic Dimensions**:
   - Locale/Country groupings and filters
   - Regional performance analytics (GROUP BY country, locale)
   - Cross-border analytics (multi-region comparisons)
   - Pattern: Presence of `locale`, `country`, `region` in GROUP BY or WHERE clauses

4. **Business Function Categories** (Based on Merchant Requirements):
   - **Returns Analytics**: Return rates, refund amounts, return reasons, return workflows (CORE requirement)
   - **Delivery/Shipment Analytics**: Carrier performance, delivery SLAs, transit times
   - **Order Analytics**: Order status, order volume, conversion metrics
   - **Campaign Analytics**: Marketing campaign tracking, rollout performance
   - **Usage Analytics**: Feature adoption, agent usage, customer engagement (C&C value)
   - **Data Integration**: Connector usage (Patchworks), scheduled reports, Google Analytics tagging

---

## 📚 BACKGROUND READING

**Priority order** (read before starting):

1. @SQL_QUERY_SEMANTIC_ANALYSIS_FRAMEWORK.md - Complete analysis of approaches, tools, and recommendations
2. @HUB_ANALYTICS_API_2025_REPORT.md - Hub Analytics (812K queries, 0% violations, 80.3% retailer attribution)
3. @LOOKER_2025_ANALYSIS_REPORT.md - Looker dashboards (236K queries, 72.9% retailer attribution)
4. @MONITOR_2025_ANALYSIS_REPORT.md - Monitor APIs (205K queries, 100% retailer attribution)
5. @AI_SESSION_CONTEXT.md - Parent project context (optional background)

---

## 🎯 PROJECT GOAL

Build a system that takes SQL queries and produces:

### **Input:**
```sql
SELECT retailer_moniker, COUNT(*) as return_count, 
       AVG(refund_amount) as avg_refund
FROM returns r
JOIN shipments s ON r.shipment_id = s.id
WHERE return_date >= '2024-01-01'
  AND return_reason = 'damaged'
GROUP BY retailer_moniker
```

### **Output:**
```json
{
  "business_function": "Return Analysis",
  "description": "Analyzes damaged item returns by retailer with average refunds for 2024",
  "business_question": "Which retailers have the most damaged returns and highest refund costs?",
  "tables_used": ["returns", "shipments"],
  "key_columns": ["retailer_moniker", "return_reason", "refund_amount", "return_date"],
  "query_type": "aggregation",
  "complexity_score": 6,
  "has_joins": true,
  "has_temporal_filter": true,
  "time_range_days": 365,
  "lookback_pattern": "1 year (365 days)",
  "query_granularity": "aggregated",
  "aggregation_dimensions": ["retailer_moniker"],
  "filter_dimensions": ["return_reason", "return_date"],
  "geographic_analysis": false,
  "transactional_lookup": false,
  "classification_confidence": 0.95,
  "classification_method": "rule-based"
}
```

---

## 🏗️ RECOMMENDED ARCHITECTURE (from analysis)

**Hybrid Approach**: SQL Parsing + Rules + LLM Fallback

### **Why Hybrid?**
- ✅ **90% cost savings**: Only use LLM for edge cases
- ✅ **Fast**: <10ms for common queries (rule-based)
- ✅ **Handles complexity**: LLM backup for unusual patterns
- ✅ **Self-improving**: New LLM classifications become rules

### **System Flow:**
```
Query → SQL Parser (sqlglot) → Extract Features
         ↓
   Rule-Based Classifier
         ↓
   Classified? 
    Yes → Return Result (fast, free)
    No → LLM Fallback (slow, small cost)
         ↓
    Save as new rule for future
```

---

## ✅ DELIVERABLES

### **Phase 1: Proof of Concept** (Week 1)
**Goal**: Discover business function taxonomy

**Tasks**:
1. Extract 500-1,000 diverse queries from Hub Analytics API, Looker, and/or Monitor
2. Generate embeddings (sentence-transformers or OpenAI)
3. Cluster queries (K-means/HDBSCAN) into 20-50 groups
4. LLM describes each cluster (GPT-4o-mini or Claude Haiku)
5. Human reviews and refines taxonomy

**Deliverables**:
- `results/business_function_taxonomy.json` - Category list
- `docs/taxonomy_discovery_report.md` - Findings and examples
- **Cost estimate**: $5-10

---

### **Phase 2: SQL Parser + Rules** (Week 2)
**Goal**: Build deterministic classifier for common patterns

**Tasks**:
1. Implement SQL parser module (`sql_parser.py` using sqlglot)
2. Create rule engine (`classifier.py` with rules.yaml)
3. Test on POC sample
4. Measure rule match rate

**Deliverables**:
- `src/sql_parser.py` - Feature extraction
- `src/classifier.py` - Rule-based classification
- `config/rules.yaml` - Business function rules
- `tests/test_classifier.py` - Unit tests
- **Target**: 70-80% rule match rate

---

### **Phase 3: LLM Fallback** (Week 3)
**Goal**: Handle edge cases with AI

**Tasks**:
1. Implement LLM classifier (`llm_classifier.py`)
2. Create prompt templates
3. Test hybrid system
4. Auto-generate new rules from LLM results
5. Re-test with expanded rules

**Deliverables**:
- `src/llm_classifier.py` - AI-based classification
- `config/prompts.yaml` - LLM prompt templates
- `src/orchestrator.py` - Hybrid workflow
- **Target**: 95%+ combined match rate

---

### **Phase 4: Production Integration** (Week 4)
**Goal**: Scale to full dataset and integrate with BigQuery

**Tasks**:
1. Process all platform queries (Hub Analytics API, Looker, Monitor - 1.25M total for 2025)
2. Create BigQuery table: `query_opt.query_classifications`
3. Join with `traffic_classification`
4. Generate analysis report
5. Document usage and maintenance

**Deliverables**:
- `scripts/classify_queries.py` - Batch processor
- `queries/create_classification_table.sql` - BigQuery schema
- `notebooks/query_classification_analysis.ipynb` - Analysis
- `docs/USAGE_GUIDE.md` - How to use the framework
- **Analysis Report**: Business function breakdown by consumer type

---

## 🛠️ TECHNICAL STACK

### **Core Libraries**:
```bash
pip install sqlglot          # SQL parsing (BigQuery dialect)
pip install pandas            # Data manipulation
pip install sentence-transformers  # Embeddings (local, free)
pip install scikit-learn      # Clustering
pip install openai            # LLM API (optional, for better quality)
pip install anthropic         # Claude API (alternative)
pip install google-cloud-bigquery  # BigQuery integration
pip install pyyaml            # Config files
```

### **Project Structure**:
```
sql_semantic_analysis/
├── src/
│   ├── __init__.py
│   ├── sql_parser.py          # Extract features from SQL
│   ├── classifier.py          # Rule-based classification
│   ├── llm_classifier.py      # LLM fallback
│   ├── orchestrator.py        # Main workflow
│   └── embeddings.py          # Clustering (Phase 1)
├── config/
│   ├── rules.yaml             # Business function rules
│   ├── prompts.yaml           # LLM prompts
│   └── settings.yaml          # API keys, thresholds
├── tests/
│   ├── test_parser.py
│   ├── test_classifier.py
│   └── test_integration.py
├── scripts/
│   ├── discover_taxonomy.py   # Phase 1: Clustering
│   ├── classify_queries.py    # Phase 4: Batch processing
│   └── generate_rules.py      # Convert LLM results to rules
├── queries/
│   ├── extract_queries.sql    # Get queries from BigQuery
│   └── create_classification_table.sql
├── notebooks/
│   └── analysis.ipynb         # Exploratory analysis
├── docs/
│   ├── ARCHITECTURE.md
│   ├── USAGE_GUIDE.md
│   └── taxonomy_discovery_report.md
├── results/
│   └── business_function_taxonomy.json
├── requirements.txt
└── README.md
```

---

## 💰 BUDGET & COST TRACKING

### **Expected Costs**:
| Phase | Component | Cost | Notes |
|-------|-----------|------|-------|
| Phase 1 | Embeddings (1K queries) | $0-0.10 | Free if using local model |
| Phase 1 | LLM clustering (50 clusters) | $5 | GPT-4o-mini |
| Phase 3 | LLM fallback (10% of queries) | $10-20 | For unclassified |
| **Total POC** | | **$15-25** | One-time |
| **Production** | Monthly (new queries only) | **$1-2** | Ongoing |

### **Cost Optimization Tips**:
- Use **sentence-transformers** (local) instead of OpenAI embeddings: Save $0.10/1K
- Use **Claude 3.5 Haiku** ($0.0008/query) instead of GPT-4o: Save 80%
- Cache LLM responses by query hash: Avoid re-classifying same query

---

## 📊 SUCCESS METRICS

### **Phase 1 (Taxonomy Discovery)**:
- [ ] 20-50 business function categories identified
- [ ] Each category has 3+ example queries
- [ ] Human-reviewed and validated taxonomy
- [ ] Clear category definitions

### **Phase 2 (Rule Engine)**:
- [ ] 70%+ queries classified by rules
- [ ] <10ms average classification time
- [ ] 95%+ precision (rules don't misclassify)
- [ ] Comprehensive test coverage

### **Phase 3 (LLM Fallback)**:
- [ ] 95%+ total classification rate (rules + LLM)
- [ ] <100ms average time (including LLM calls)
- [ ] Auto-rule generation working
- [ ] Rule improvement over time

### **Phase 4 (Production)**:
- [ ] All 2025 platform queries classified (Hub Analytics API, Looker, Monitor)
- [ ] BigQuery table created and populated
- [ ] Analysis report with business insights by platform
- [ ] Documentation for future maintenance

---

## 🚀 DATA SOURCES AVAILABLE

### **1. BigQuery Classification Table** (Primary source):
```sql
-- Table: narvar-data-lake.query_opt.traffic_classification
-- Contains: 43.8M jobs classified across 9 periods
-- Schema: job_id, query_text (500 char sample), all performance metrics
```

**Useful for**: Quick access to partial query text + metrics

### **2. BigQuery Audit Logs** (Full query text):
```sql
-- Table: narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access
-- Contains: FULL query text (no character limit)
-- Join on: job_id + timestamp
```

**Useful for**: Getting complete SQL for complex queries

### **3. Platform Pattern Discovery Results** (Sample data):
```
-- Hub Analytics API: results/hub_analytics_api_pattern_discovery_20251112_211901.csv
--   60 queries, 80% retailer extraction success
-- Looker: results/hub_pattern_discovery_20251112_130121.csv  
--   60 queries, 60% initial success (improved to 72.9% in full analysis)
-- Monitor: Pre-attributed in classification table (100% success via MD5 matching)
```

**Useful for**: Understanding query patterns across all three platforms

---

## ❓ CRITICAL QUESTIONS TO ANSWER

**Before proceeding, please answer these 5 questions:**

---

### **Question 1: Scope & Timeline**

What approach do you prefer:

**Option A**: Quick Win (Simple patterns for current analysis)
- Pattern matching + manual tagging
- Time: 1-2 days
- Coverage: 60-70%
- Cost: $0-5

**Option B**: Full Framework (4-week build, reusable)
- Complete hybrid system
- Time: 4 weeks
- Coverage: 95%+
- Cost: $15-25

**Option C**: Hybrid Timeline (Simple now, framework later)
- Phase 1 + Phase 2 now (2 weeks)
- Phase 3 + Phase 4 later
- Incremental value

**→ Your Answer**: _________________________

---

### **Question 2: LLM Preferences**

Which LLM approach do you prefer:

**Option A**: Commercial APIs (OpenAI/Anthropic)
- ✅ Best quality
- ✅ Fast
- ⚠️ Small cost ($15-25 for POC)
- ⚠️ Requires API keys

**Option B**: Local Models (Llama 3.1, Mistral)
- ✅ Free
- ✅ Private (no data sent externally)
- ⚠️ Lower quality
- ⚠️ Requires local GPU/CPU setup

**Option C**: No LLM (Rule-based only)
- ✅ Free
- ✅ Fast
- ⚠️ Limited coverage (70-80%)
- ⚠️ Requires manual rule creation

**→ Your Answer**: _________________________

---

### **Question 3: Business Domain Knowledge**

Do you know the main business functions users care about?

**Option A**: Yes, I have a list
- Examples: "Return Rate Monitoring", "Delivery SLA Tracking", etc.
- **Action**: Share the list, we'll create rules directly
- **Skip Phase 1** (taxonomy discovery)

**Option B**: Partially - I know some categories
- **Action**: Share what you know, we'll discover the rest
- **Modified Phase 1** (fill gaps)

**Option C**: No, discover from data
- **Action**: Run full Phase 1 (clustering + LLM)
- **Start from scratch**

**→ Your Answer**: _________________________

**If A or B, please list known categories:**
1. _________________________
2. _________________________
3. _________________________
(add more as needed)

---

### **Question 4: Integration Preferences**

How should this framework integrate with your workflow?

**Option A**: Standalone Python Tool
- Command-line scripts
- Input: CSV/JSON
- Output: CSV/JSON
- Easy to run, portable

**Option B**: BigQuery Integration
- SQL UDFs + stored procedures
- Query directly in BigQuery
- Integrated with existing tables

**Option C**: Jupyter Notebook Workflow
- Interactive exploration
- Visualizations
- Step-by-step analysis

**Option D**: All of the above
- Core library + multiple interfaces

**→ Your Answer**: _________________________

---

### **Question 5: Output Detail Level**

What level of detail do you want in the output?

**Option A**: Simple Categories
```json
{
  "business_function": "Return Analysis",
  "tables_used": ["returns", "shipments"],
  "query_type": "aggregation"
}
```

**Option B**: Detailed Descriptions
```json
{
  "business_function": "Return Analysis",
  "description": "Calculates return rates by retailer for damaged items in Q1 2024",
  "business_question": "Which retailers have the most damaged returns?",
  "tables_used": ["returns", "shipments"],
  "key_columns": ["retailer_moniker", "return_reason", "refund_amount"],
  "query_type": "aggregation",
  "complexity_score": 6,
  "time_range_days": 90,
  "lookback_pattern": "Q1 2024 (90 days)",
  "query_granularity": "aggregated",
  "aggregation_dimensions": ["retailer_moniker"],
  "filter_dimensions": ["return_reason", "return_date"],
  "geographic_analysis": false,
  "transactional_lookup": false,
  "optimization_potential": "high"
}
```

**Option C**: Full Analysis with Recommendations
- Everything from Option B, plus:
- Query optimization suggestions
- Cost reduction opportunities
- Alternative query patterns

**→ Your Answer**: _________________________

---

## 📖 USAGE SCENARIOS (After Framework is Built)

Once complete, this framework will support:

### **Scenario 1: Platform Dashboard Analysis** (Current need)
```python
# Classify Hub Analytics API queries
results = analyzer.classify_queries('ANALYTICS_API', period='2025')

# Group by business function
summary = results.groupby('business_function').agg({
    'slot_hours': 'sum',
    'qos_violations': 'sum',
    'cost': 'sum'
})

# Find: "Return Analysis queries consume 40% of Hub Analytics capacity"
# Can apply same approach to Looker (HUB subcategory) or Monitor
```

### **Scenario 2: Metabase User Support**
```python
# When user reports slow query
query_analysis = analyzer.analyze(query_text)

print(f"Business function: {query_analysis.function}")
print(f"Similar fast queries: {query_analysis.alternatives}")
print(f"Optimization tips: {query_analysis.suggestions}")
```

### **Scenario 3: Airflow ETL Documentation**
```python
# Automatically document all Airflow DAG queries
for dag in airflow_dags:
    for task in dag.tasks:
        if task.query:
            doc = analyzer.document_query(task.query)
            # Generates: "This ETL computes daily return rates"
```

### **Scenario 4: Capacity Forecasting**
```python
# Predict load by business cycle
predictions = analyzer.predict_load(
    business_functions=['Return Analysis', 'Delivery Performance'],
    period='Peak_2025_2026'
)
# "Expect 2x Return Analysis load in January"
```

---

## 🎯 IMMEDIATE FIRST STEPS

When starting this sub-project session:

1. **Answer the 5 questions above** ⬆️
2. **Review** `SQL_QUERY_SEMANTIC_ANALYSIS_FRAMEWORK.md` (comprehensive analysis)
3. **Decide**: POC first (Phase 1 only) or full build (all 4 phases)?
4. **Set up environment**:
   ```bash
   pip install sqlglot pandas sentence-transformers scikit-learn
   ```
5. **Extract sample queries** from BigQuery for taxonomy discovery

---

## 📁 RELATED FILES & CONTEXT

**Parent Project Files**:
- `AI_SESSION_CONTEXT.md` - Overall BigQuery optimization project
- `PHASE1_FINAL_REPORT.md` - Traffic classification (43.8M jobs)
- `PEAK_2025_2026_STRATEGY_EXEC_REPORT.md` - Strategic recommendations

**Completed Platform Analyses** (November 12, 2025):
- `HUB_ANALYTICS_API_2025_REPORT.md` - 812K queries, 80.3% retailer attribution, 0% violations
- `LOOKER_2025_ANALYSIS_REPORT.md` - 236K queries, 72.9% retailer attribution, 2.6% violations
- `MONITOR_2025_ANALYSIS_REPORT.md` - 205K queries, 100% retailer attribution, 2.21% violations
- `LOOKER_VS_HUB_ANALYTICS_COMPARISON.md` - Platform comparison summary

**Pattern Discovery Results** (Sample data for framework development):
- `results/hub_analytics_api_pattern_discovery_20251112_211901.csv` - Hub Analytics API (60 queries)
- `results/hub_pattern_discovery_20251112_130121.csv` - Looker (60 queries)
- Monitor queries available in classification table (no pattern discovery needed)

**Sub-Project Files** (to create in new session):
- `sql_semantic_analysis/` - Framework code directory
- `docs/taxonomy_discovery_report.md` - Phase 1 findings
- `results/business_function_taxonomy.json` - Category definitions

**Key BigQuery Tables**:
- `narvar-data-lake.query_opt.traffic_classification` - Classified jobs (43.8M, includes all platforms)
- `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` - Full query text for audit log joins

---

## 💡 TIPS FOR SUCCESS

1. **Start Small**: Phase 1 (taxonomy discovery) is most important - get this right!
2. **Iterate**: Business taxonomies evolve - design for updates
3. **Document Examples**: Each category needs 5+ example queries for rules
4. **Test Coverage**: Aim for diverse query types (simple selects, complex CTEs, etc.)
5. **Cost Tracking**: Monitor LLM usage to stay within budget
6. **Version Control**: Save rules.yaml versions as taxonomy improves

---

## 🚨 IMPORTANT NOTES

### **Data Privacy**:
- Hub Analytics API and Looker queries may contain retailer-specific data
- When using external LLM APIs, consider data sensitivity
- Option: Use local models for sensitive queries

### **Service Account Coverage**:
- Hub Analytics API currently captures 2 service accounts:
  * `analytics-api-bigquery-access@narvar-data-lake.iam.gserviceaccount.com` (98.5% of queries)
  * `analytics-api-bigquery-access@narvar-qa-202121.iam.gserviceaccount.com` (1.5% of queries)
- **Note**: `analytics-api-bigquery-access2` mentioned by Elliott Feng was NOT found in Nov 2024-Oct 2025 data
  * May be in different timeframe or planned for future
  * Regex pattern `r'analytics-api-bigquery-access'` WILL match if it exists (includes any suffix)
  * Verified 812,010 total queries captured from existing accounts

### **Query Sampling Strategy**:
- **Stratified sampling**: Get diverse query types
  - Fast queries (<30s)
  - Medium queries (30-120s)
  - Slow queries (>120s)
  - QoS-compliant vs violating
  - Different periods (baseline, peak)
- **Representative coverage**: Ensure all business functions sampled

### **Maintenance Plan**:
- **Quarterly review**: Update taxonomy as business evolves
- **Rule refinement**: Add new patterns from LLM fallbacks
- **Performance monitoring**: Track classification accuracy over time

---

## ✅ CHECKLIST BEFORE STARTING

- [ ] Read `SQL_QUERY_SEMANTIC_ANALYSIS_FRAMEWORK.md`
- [ ] Answered all 5 critical questions
- [ ] Decided on scope (POC vs Full Build)
- [ ] Set up Python environment
- [ ] Have BigQuery access configured
- [ ] Understand parent project context (optional)
- [ ] Ready to extract sample queries

---

**Let's build something reusable and valuable!** 🚀

**Start Date**: _________________________  
**Expected Completion**: _________________________  
**Assigned To**: _________________________
```

---

## 📋 MERCHANT/RETAILER ANALYTICS REQUIREMENTS (Reference)

**Source**: Retailer feedback and product requirements

### **1. Advanced Business and Product Analytics**

**Returns Analytics (CORE - Highest Priority)**:
- Comprehensive, sophisticated reporting for entire returns workflow
- Core returns metrics and KPIs
- Return rates, refund amounts, return reasons analysis
- Returns workflow optimization insights
- **Framework Should Identify**: Queries focused on returns tables, return-related metrics

**Analytics Improvements - Geographic Grouping**:
- Consolidate and report by locales/countries
- Regional performance visibility (Hub, Monitor, all reporting interfaces)
- Cross-border analytics
- **Framework Should Identify**: Queries with locale/country dimensions, geographic GROUP BY

### **2. Data Access and Integration**

**Data Connectors**:
- Patchworks integration (connect Narvar data with commerce systems)
- Google Analytics tagging support for Narvar recommendations
- **Framework Should Identify**: Integration-related queries, external data joins

**Self-Service Reporting**:
- More data within Narvar Hub
- Brand-scheduled reports (self-service)
- Reduce manual data pulls
- **Framework Should Identify**: Scheduled/recurring queries, automated report generation

### **3. Campaign & Usage Tracking**

**Campaign Analytics**:
- Marketing campaign performance tracking
- Product rollout analysis
- Campaign ROI measurement
- **Framework Should Identify**: Campaign-tagged queries, time-bound promotional analysis

**Usage Analytics (C&C Value)**:
- Feature usage tracking (agents and retailers)
- Instrumentation improvements
- Value quantification metrics
- **Framework Should Identify**: Usage tracking queries, instrumentation data queries

---

### **How Framework Should Address These Requirements**

**Expected Insights After Classification**:
```
Business Function Distribution:
- Returns Analytics: 45% of queries, $800/month cost (VALIDATE: Is this matching merchant needs?)
- Delivery/Shipment Analytics: 30% of queries
- Order Analytics: 15% of queries
- Campaign Analytics: 5% of queries
- Usage Analytics: 5% of queries

Time Range Patterns:
- Recent (1-7 days): 40% of queries (operational monitoring)
- Medium (30-90 days): 35% of queries (trend analysis)
- Historical (>90 days): 25% of queries (year-over-year comparison)

Query Granularity:
- Transactional lookups: 60% (shipment/order status checks)
- Aggregated analytics: 40% (KPIs, dashboards)

Geographic Analysis:
- 25% of queries include locale/country dimensions
- Top dimensions: country, locale, region
```

**Optimization Applications**:
- If Returns Analytics = 45% of cost, prioritize returns query optimization
- If most queries look at recent data (1-7 days), optimize with aggressive partitioning
- If transactional lookups dominate, create indexes on tracking_number, order_number
- If geographic analytics growing, add locale/country clustering to tables

---

**Repository**: https://github.com/narvar/bigquery-optimization-queries/tree/main/narvar/analysis_peak_2025_sonnet45

**Key Documents**:
- Framework Analysis: [SQL_QUERY_SEMANTIC_ANALYSIS_FRAMEWORK.md](./SQL_QUERY_SEMANTIC_ANALYSIS_FRAMEWORK.md)
- Parent Project: [AI_SESSION_CONTEXT.md](./AI_SESSION_CONTEXT.md)
- Hub Analytics API: [HUB_ANALYTICS_API_2025_REPORT.md](./HUB_ANALYTICS_API_2025_REPORT.md)
- Looker: [LOOKER_2025_ANALYSIS_REPORT.md](./LOOKER_2025_ANALYSIS_REPORT.md)
- Monitor: [MONITOR_2025_ANALYSIS_REPORT.md](./MONITOR_2025_ANALYSIS_REPORT.md)

**Start the new session with this prompt!** 🎯

