# SQL Semantic Analysis Framework - Phase 0: Discovery & Setup

**Session Start**: November 13, 2025  
**Status**: Phase 0 - Discovery (In Progress)  
**Related Documents**: 
- [Framework Prompt](./SQL_SEMANTIC_ANALYSIS_NEXT_SESSION.md)
- [Detailed Analysis](./SQL_QUERY_SEMANTIC_ANALYSIS_FRAMEWORK.md)

---

## 📝 SESSION SUMMARY

This document captures the critical decisions, approach, and execution plan for building the SQL Query Semantic Analysis Framework for BigQuery capacity optimization.

---

## ✅ CRITICAL DECISIONS MADE

### **1. Scope & Scale**
- **Testing Scope**: Hub Analytics API, Looker, Monitor, Airflow ETL (1.25M + Airflow queries)
- **Production Scale**: Full platform (43.8M queries across all periods)
- **Strategy**: Test first, scale later with validated approach

### **2. Data Sources**
- **Full Query Text**: Available in `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
- **Metrics & Classification**: `narvar-data-lake.query_opt.traffic_classification`
- **JOIN Strategy**: Use job_id + timestamp to get full query text when needed
- **Reference Implementation**: See `automated_process_classification.sql` for pattern

### **3. Sampling Strategy**
**Stratified sampling approach**:
- 65% Hub Analytics API (ANALYTICS_API)
- 19% Looker (HUB)
- 16% Monitor (MONITOR)
- Plus Airflow/Composer (AUTOMATED category)

**Oversample edge cases**:
- QoS violations
- Slow queries (>120s)
- High slot consumption
- Failed queries

**Sample Size**: 10K queries for discovery phase

### **4. LLM Selection & Budget**
**Primary Model**: Gemini 1.5 Flash
- Cost: $0.35/1M tokens input
- Use case: 90% of classifications
- Fast, cost-effective, good quality

**Fallback Models** (if performance inadequate):
1. Claude 3.5 Sonnet (via Vertex AI) - ~$3/1M tokens
2. Gemini 1.5 Pro - $7/1M tokens input

**Budget Approved**: $200-300/month

**Cost Optimization**:
- Cache LLM responses by query hash
- Use rules for 70%+ of queries (free)
- LLM only for edge cases (~30%)

### **5. Taxonomy Approach**

**Hybrid Discovery Method** (4-step process):

**Step 1: Seed Taxonomy** (from merchant requirements)
- Returns Analytics (CORE - highest priority)
- Geographic/Regional Analytics
- Delivery/Shipment Performance
- Order Analytics
- Campaign Analytics
- Usage/Instrumentation Analytics
- Data Integration/Connectors
- Self-Service Reporting
- *10-15 categories total*

**Step 2: Cluster Remaining Queries**
- Extract patterns that don't match seed categories
- Use embeddings + clustering (HDBSCAN or K-means)
- Discover unknown business functions

**Step 3: LLM Categorization**
- Map clusters to seed categories
- OR create new categories for distinct patterns
- Generate category descriptions

**Step 4: Human Validation**
- Review and refine taxonomy
- Align with business strategy
- Document category definitions

### **6. Classification Output Schema**

**Primary Approach**: Primary + Secondary tags
```json
{
  "business_function": "Returns",  // Primary category
  "secondary_functions": ["Delivery", "Order_Status"],  // Optional array
  "classification_confidence": 0.95,
  "classification_method": "rule-based"  // or "llm-based"
}
```

**Backup Option**: Multi-label array (if primary/secondary proves insufficient)
```json
{
  "business_functions": ["Returns", "Delivery"],  // Equal weight
  "function_weights": [0.7, 0.3]  // Optional confidence per function
}
```

**Decision**: Start with primary+secondary, evaluate in Phase 1, pivot if needed

### **7. Schema Integration**

**Approach**: Separate versioned table (Option B)

**Table**: `narvar-data-lake.query_opt.query_semantic_classifications`

**Schema** (draft):
```sql
CREATE TABLE query_opt.query_semantic_classifications (
  -- Identifiers
  job_id STRING NOT NULL,
  period STRING NOT NULL,
  classification_timestamp TIMESTAMP NOT NULL,
  classifier_version STRING NOT NULL,  -- e.g., "v1.0.0", "v1.1.0"
  
  -- Primary Classification
  business_function STRING,  -- Primary category
  secondary_functions ARRAY<STRING>,  -- Secondary categories
  classification_confidence FLOAT64,
  classification_method STRING,  -- "rule-based", "llm-based", "manual"
  
  -- Query Characteristics
  query_type STRING,  -- "aggregation", "transactional_lookup", "etl", "exploratory"
  query_granularity STRING,  -- "transactional", "aggregated", "mixed"
  complexity_score INT64,  -- 1-10 scale
  
  -- Temporal Analysis
  has_temporal_filter BOOL,
  time_range_bucket STRING,  -- "1-7d", "8-30d", "31-90d", "90+d", "none", "current_date_relative"
  time_range_days INT64,  -- Exact days if determinable
  lookback_pattern STRING,  -- Human-readable description
  
  -- Semantic Features
  tables_used ARRAY<STRING>,
  key_columns ARRAY<STRING>,
  aggregation_dimensions ARRAY<STRING>,
  filter_dimensions ARRAY<STRING>,
  has_joins BOOL,
  join_count INT64,
  has_subqueries BOOL,
  has_ctes BOOL,
  
  -- Geographic Analysis
  has_geographic_analysis BOOL,
  geographic_dimensions ARRAY<STRING>,  -- ["country", "locale", "region"]
  
  -- Business Intent
  business_question STRING,  -- LLM-generated description
  description STRING,  -- Detailed explanation
  
  -- Optimization Potential
  optimization_flags ARRAY<STRING>,  -- ["no_time_filter", "full_table_scan", "inefficient_join"]
  optimization_potential STRING,  -- "high", "medium", "low"
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  created_by STRING  -- User or service account that created classification
)
PARTITION BY DATE(classification_timestamp)
CLUSTER BY period, business_function, classification_method;
```

**Versioning Strategy**:
- New taxonomy version = new classifier_version
- Keep historical classifications for comparison
- Can re-classify with new version without deleting old data

### **8. Budget & Cost**

**Approved Budget**: $200-300/month

**Expected Costs**:
- **Phase 0** (Discovery): $0 (no LLM calls)
- **Phase 1** (POC with 1K queries): $5-10
- **Phase 2** (Rules development): $0-5
- **Phase 3** (LLM fallback): $10-20
- **Phase 4** (Full 1.25M classification): $50-100 one-time
- **Ongoing** (new queries monthly): $10-20/month

**Cost Tracking**: Monitor per phase, halt if exceeding budget

### **9. Validation Strategy**

**Challenge**: No ground truth, limited domain expert time, solo validation

**Solution**: 3-Tier Quality System

#### **Tier 1: AUTOMATED (Every query)**
- Cluster coherence score (silhouette score 0-1)
- LLM confidence score
- Rule match indicator (deterministic vs probabilistic)

#### **Tier 2: SPOT CHECKS (Every 1,000 queries)**
- Manual validation of 50 random samples (5% sample rate)
- Quick keyboard shortcuts: 1=✅ Correct | 2=❌ Wrong | 3=⚠️ Ambiguous | 4=Skip
- Track accuracy over time
- Flag categories with <80% accuracy for review

**Efficiency Optimizations**:
- Pre-filter: Only validate high-impact queries (high cost, QoS violations, low confidence)
- Similarity clustering: Validate 1 query per cluster of similar queries (reduces work 80-90%)
- Skip obvious patterns: Simple SELECT *, already validated similar queries

#### **Tier 3: GROUND TRUTH BUILD (Ongoing)**
- Tag 500-1,000 queries manually as gold standard
- Re-test classifier monthly against ground truth
- Use to improve rules and prompts
- **Target**: Build over 3-6 months

### **10. Time Range Extraction**

**Approach**: Bucketed ranges (not exact days)

**Buckets**:
- `"1-7d"` - Recent/Operational (last week)
- `"8-30d"` - Medium-term (last month)
- `"31-90d"` - Quarterly trends
- `"90+d"` - Historical/Year-over-year
- `"none"` - **FLAG: Full table scan, optimization opportunity!**
- `"current_date_relative"` - Uses CURRENT_DATE() or similar (dynamic)

**Extraction Logic**:
- Parse literal dates: `WHERE date >= '2024-01-01'`
- Parse DATE_SUB patterns: `WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)`
- Detect CURRENT_DATE(), CURRENT_TIMESTAMP() usage
- Flag queries with NO date filter in WHERE clause

**Phase 2 complexity** (later):
- Partition decorators: `_PARTITIONTIME`
- Window functions: `DATE_TRUNC(created_at, WEEK)`
- Business calendars: `fiscal_quarter = 'Q1_2024'`

---

## 📊 PERFORMANCE MEASUREMENT STRATEGY

### **Without Ground Truth (Phase 1-2)**

**Method 1: Cluster Coherence Metrics** (Automated)
```python
from sklearn.metrics import silhouette_score, davies_bouldin_score

# Silhouette Score: 0-1 (higher = better separation)
score = silhouette_score(embeddings, cluster_labels)

# Davies-Bouldin Index: Lower = better (cluster compactness)
db_score = davies_bouldin_score(embeddings, cluster_labels)
```

**Method 2: LLM Confidence Scores** (Per-query)
- Extract confidence from LLM response
- Track distribution (aim for 80%+ high confidence >0.8)
- Flag low confidence queries for manual review

**Method 3: Human Validation Sampling** (Quality Check)
- Validate 50 queries per 1,000 classified
- **Validation Accuracy** = Correct / (Correct + Wrong)
- **Target**: >90% validation accuracy

### **With Ground Truth (Phase 3+)**

**Method 4: Precision & Recall** (Standard ML metrics)
```python
from sklearn.metrics import precision_recall_fscore_support, classification_report

# Per-category metrics
precision, recall, f1, support = precision_recall_fscore_support(
    y_true=ground_truth_labels,
    y_pred=predicted_labels,
    average=None  # Per-category scores
)

# Overall metrics
macro_f1 = f1_score(y_true, y_pred, average='macro')  # Equal weight per category
weighted_f1 = f1_score(y_true, y_pred, average='weighted')  # Weight by frequency
```

**Method 5: Confusion Matrix** (Category-level accuracy)
```python
from sklearn.metrics import confusion_matrix
import seaborn as sns

cm = confusion_matrix(y_true, y_pred)
sns.heatmap(cm, annot=True, fmt='d', cmap='Blues')
```

### **Success Criteria by Phase**

**Phase 1 (Taxonomy Discovery)**:
- [ ] Silhouette score >0.3 (reasonable cluster separation)
- [ ] 15-30 business function categories identified
- [ ] Each category has 5+ example queries
- [ ] Human validation: >85% agree with clustering

**Phase 2 (Rule Engine)**:
- [ ] 40-70% queries classified by rules (baseline)
- [ ] <10ms average classification time
- [ ] Validation accuracy: >90% for rule-based classifications
- [ ] Rule coverage improves 5-10% per iteration

**Phase 3 (LLM Fallback)**:
- [ ] 90%+ total classification rate (rules + LLM)
- [ ] <500ms average time (including LLM calls with caching)
- [ ] LLM confidence score: >0.8 for 80% of classifications
- [ ] Validation accuracy: >85% for LLM-based classifications

**Phase 4 (Production)**:
- [ ] All 1.25M test queries classified
- [ ] Classification table created and populated
- [ ] Precision >0.85, Recall >0.80 on ground truth (if available)
- [ ] Cost within budget ($50-100 for full run)

---

## 🚀 PHASE 0: DISCOVERY & SETUP

**Goal**: Understand query diversity and patterns before building framework  
**Time Estimate**: 2-3 hours  
**Cost**: $0 (no LLM calls, BigQuery queries only)  
**Status**: 🟡 In Progress

### **Objectives**
1. Understand query diversity (how many unique patterns?)
2. Analyze query complexity and structure
3. Identify common patterns vs edge cases
4. Validate sampling strategy
5. Extract representative sample for Phase 1

### **Deliverables**
- [ ] `QUERY_DIVERSITY_REPORT.md` - Analysis findings
- [ ] `results/sample_queries_10k.csv` - Stratified sample dataset
- [ ] `results/query_patterns_analysis.csv` - Pattern statistics
- [ ] Decision on Phase 1 approach (informed by findings)

---

## 📋 PHASE 0 EXECUTION PLAN

### **Step 1: Query Length & Truncation Analysis**

**Goal**: Determine if 500-char limit in `traffic_classification` is sufficient

**Query**: `queries/phase0_discovery/query_length_analysis.sql`

**Metrics to extract**:
- Total queries by platform
- % truncated at 500 chars
- Average query length
- P50, P95, P99 query lengths
- Longest queries (top 10)

**Decision point**: 
- If <10% truncated → Use traffic_classification (fast)
- If >20% truncated → Need audit log JOIN (slower but complete)

### **Step 2: Query Pattern Diversity Analysis**

**Goal**: Understand how many unique patterns exist

**Query**: `queries/phase0_discovery/query_pattern_diversity.sql`

**Metrics to extract**:
- Total unique queries (by MD5 hash of query text)
- Duplicate query count (same query run multiple times)
- Query pattern distribution (simple SELECT vs complex CTEs)
- Structural features:
  - % with JOINs
  - % with subqueries
  - % with CTEs (WITH clauses)
  - % with window functions
  - % with UNIONs

**Decision point**:
- If 90%+ duplicates → Focus on top N patterns (simpler)
- If 50%+ unique → Need robust clustering (complex)

### **Step 3: Temporal Filter Analysis**

**Goal**: Understand how queries filter by time

**Query**: `queries/phase0_discovery/temporal_filter_analysis.sql`

**Patterns to detect**:
- Literal dates: `WHERE date >= '2024-01-01'`
- DATE_SUB patterns: `DATE_SUB(CURRENT_DATE(), INTERVAL X DAY/MONTH/YEAR)`
- CURRENT_DATE() / CURRENT_TIMESTAMP() usage
- Partition filters: `_PARTITIONTIME`
- No time filter (full table scans)

**Output**: Distribution by time range bucket

### **Step 4: Platform-Specific Pattern Discovery**

**Goal**: Identify unique patterns per platform

**Query**: `queries/phase0_discovery/platform_pattern_comparison.sql`

**Analysis by platform**:
- Hub Analytics API: 812K queries (what are common patterns?)
- Looker: 236K queries (generated vs custom?)
- Monitor: 205K queries (API-driven patterns?)
- Airflow/Composer: ETL patterns

**Output**: Top 20 patterns per platform

### **Step 5: Stratified Sample Extraction**

**Goal**: Extract 10K representative queries for Phase 1 clustering

**Query**: `queries/phase0_discovery/extract_stratified_sample.sql`

**Sampling strategy**:

**By Platform** (65/19/16 split):
- 6,500 Hub Analytics API
- 1,900 Looker
- 1,600 Monitor

**By Characteristics** (within each platform):
- 60% baseline queries (fast, compliant)
- 20% slow queries (>120s)
- 10% QoS violations
- 10% high slot consumption (top 10%)

**By Query Complexity** (across platforms):
- 40% simple (no joins, single table)
- 40% medium (joins, basic aggregations)
- 20% complex (CTEs, subqueries, window functions)

**Output**: `results/sample_queries_10k.csv` with:
- job_id
- period
- consumer_type
- query_text (full, via JOIN if needed)
- execution_time_seconds
- slot_hours
- qos_violation (boolean)
- sampling_reason (baseline/slow/violation/high_cost)

### **Step 6: Manual Query Review**

**Goal**: You + AI review 30-50 queries to understand business intent

**Process**:
1. AI presents query + metrics
2. You identify:
   - Business function (if obvious)
   - Key tables and columns
   - Time filtering pattern
   - Optimization opportunities
3. AI learns patterns for seed taxonomy refinement

**Output**: 
- Initial intuition about category distribution
- Edge cases to consider
- Seed taxonomy refinement

### **Step 7: Discovery Report**

**Goal**: Synthesize findings and plan Phase 1

**Report**: `QUERY_DIVERSITY_REPORT.md`

**Contents**:
1. Query diversity findings
2. Platform pattern differences
3. Temporal filtering patterns
4. Complexity distribution
5. Sample dataset description
6. Recommended Phase 1 approach
7. Seed taxonomy (refined)
8. Success criteria for clustering

---

## 📂 FILE STRUCTURE (To Create)

```
narvar/analysis_peak_2025_sonnet45/
├── sql_semantic_analysis/              # New framework directory
│   ├── queries/
│   │   ├── phase0_discovery/
│   │   │   ├── query_length_analysis.sql
│   │   │   ├── query_pattern_diversity.sql
│   │   │   ├── temporal_filter_analysis.sql
│   │   │   ├── platform_pattern_comparison.sql
│   │   │   └── extract_stratified_sample.sql
│   │   ├── phase1_clustering/          # Future
│   │   ├── phase2_rules/               # Future
│   │   └── phase4_production/          # Future
│   ├── src/                            # Python code (Phase 1+)
│   ├── config/                         # Configuration files (Phase 2+)
│   ├── tests/                          # Unit tests (Phase 2+)
│   ├── notebooks/                      # Analysis notebooks
│   │   └── phase0_discovery.ipynb
│   ├── results/
│   │   ├── sample_queries_10k.csv
│   │   ├── query_patterns_analysis.csv
│   │   └── phase0_metrics.json
│   └── docs/
│       ├── QUERY_DIVERSITY_REPORT.md   # Phase 0 output
│       ├── TAXONOMY_DISCOVERY.md       # Phase 1 output
│       └── ARCHITECTURE.md             # Future
├── SQL_SEMANTIC_ANALYSIS_NEXT_SESSION.md  # Original prompt
├── SQL_SEMANTIC_ANALYSIS_PHASE0_PLAN.md   # This file
└── SQL_QUERY_SEMANTIC_ANALYSIS_FRAMEWORK.md  # Detailed analysis
```

---

## 🎯 IMMEDIATE NEXT STEPS

### **Now (Next 10 minutes)**
- [x] Document session decisions (this file)
- [ ] Create directory structure
- [ ] Create Phase 0 query: `query_length_analysis.sql`

### **Next Hour**
- [ ] Run query length analysis
- [ ] Run pattern diversity analysis
- [ ] Review results, decide on full text JOIN necessity

### **Next 2-3 Hours**
- [ ] Run temporal filter analysis
- [ ] Run platform pattern comparison
- [ ] Extract 10K stratified sample
- [ ] Manual review 30-50 queries with you
- [ ] Write `QUERY_DIVERSITY_REPORT.md`

### **After Phase 0**
- [ ] Decide: Proceed to Phase 1 or adjust approach
- [ ] Create seed taxonomy (10-15 categories)
- [ ] Set up Python environment for clustering

---

## 🔄 DECISION LOG

| Date | Decision | Rationale | Impact |
|------|----------|-----------|--------|
| 2025-11-13 | Use stratified sampling (10K queries) | Balance diversity and cost | Phase 1 input quality |
| 2025-11-13 | Primary + Secondary classification | Handles ambiguity, easy to report | Schema design |
| 2025-11-13 | Gemini 1.5 Flash primary model | Cost-effective, sufficient quality | Budget optimization |
| 2025-11-13 | Bucketed time ranges | Simpler extraction, sufficient granularity | Feature engineering |
| 2025-11-13 | Separate classification table | Version control, no schema migrations | Schema design |
| 2025-11-13 | Hybrid taxonomy approach | Leverages domain knowledge + discovery | Phase 1 strategy |

---

## 📞 STAKEHOLDER COMMUNICATION

### **Key Messages**

**To: Leadership**
> We're building a reusable framework to understand business intent from SQL queries. This will help us optimize capacity for the most important business functions (like Returns Analytics) and predict load based on business cycles. Phase 0 starts today - discovery and validation.

**To: Domain Experts** (when needed)
> We need 1-2 hours of your time to validate query classifications. We'll prepare 50-100 queries with suggested categories - you just need to mark correct/incorrect. This will ensure our automated system aligns with business reality.

**To: Engineering Teams**
> We're analyzing 1.25M queries from Hub, Looker, and Monitor to understand usage patterns. This will help identify optimization opportunities and support better capacity planning. No action needed from you at this time.

---

## 🚨 RISKS & MITIGATIONS

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Query diversity too high for rules | Medium | High | Focus on LLM-based approach, larger rule library |
| LLM costs exceed budget | Low | Medium | Monitor costs per phase, use cheaper models |
| Classification accuracy too low | Medium | High | Increase ground truth dataset, iterate on prompts |
| Validation bottleneck (solo reviewer) | High | Medium | Use similarity clustering, efficient tools |
| Business taxonomy doesn't match data | Medium | High | Hybrid approach addresses this, iterate with stakeholders |
| Truncated queries insufficient for analysis | Low | High | JOIN with audit logs if needed (verified available) |
| Timeline slips beyond 4 weeks | Medium | Low | Prioritize Phases 1-2, defer Phase 4 if needed |

---

## 📈 SUCCESS DEFINITION

**Phase 0 Success**:
- ✅ Understand query diversity (patterns, complexity, platform differences)
- ✅ Extract representative 10K sample
- ✅ Validate that full query text is accessible
- ✅ Refine seed taxonomy based on actual query patterns
- ✅ Informed decision on Phase 1 approach

**Overall Framework Success** (Phases 1-4):
- ✅ 90%+ of queries classified with >85% accuracy
- ✅ Business insights actionable (e.g., "Returns queries = 45% of cost")
- ✅ Framework reusable for other consumers (Metabase, Airflow documentation)
- ✅ Cost within budget ($200-300/month)
- ✅ Validation process efficient (<2 hours/week)
- ✅ Classification table integrated with existing analysis

---

## 📚 REFERENCES

**Related Documents**:
- [Framework Prompt](./SQL_SEMANTIC_ANALYSIS_NEXT_SESSION.md) - Original session prompt
- [Detailed Analysis](./SQL_QUERY_SEMANTIC_ANALYSIS_FRAMEWORK.md) - Comprehensive approach analysis
- [Parent Project Context](./AI_SESSION_CONTEXT.md) - BigQuery optimization project
- [Hub Analytics Report](./HUB_ANALYTICS_API_2025_REPORT.md) - Platform analysis
- [Looker Report](./LOOKER_2025_ANALYSIS_REPORT.md) - Platform analysis
- [Monitor Report](./MONITOR_2025_ANALYSIS_REPORT.md) - Platform analysis

**Key BigQuery Tables**:
- `narvar-data-lake.query_opt.traffic_classification` - Classified jobs (43.8M)
- `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access` - Full query text

**Code References**:
- `queries/phase1_classification/automated_process_classification.sql` - Pattern for audit log access

---

**Document Status**: Living document, updated as phase progresses  
**Last Updated**: 2025-11-13  
**Next Review**: After Phase 0 completion

