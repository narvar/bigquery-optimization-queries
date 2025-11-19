# SQL Query Semantic Analysis Framework
**A Reusable System for Understanding Business Intent from SQL Logs**

**Created**: November 12, 2025  
**Context**: BigQuery query log analysis (Hub, Monitor, Metabase, Airflow ETLs)  
**Goal**: Classify queries by business functionality, extract key tables/columns, identify user intent

---

## 🎯 Problem Statement

### What We Want to Understand:
1. **Business Intent**: What business question is each query trying to answer?
   - Examples: "Calculate return rates", "Analyze shipment delays", "Dashboard: Top retailers by revenue"
2. **Data Assets Used**: Which tables, views, and key columns are accessed?
3. **Query Complexity**: Simple lookup vs complex analytical query?
4. **User Patterns**: Which business functions are most important to different user groups?

### Why This Matters:
- **Optimization**: Focus on queries that matter most to business
- **Governance**: Understand which data assets are critical
- **User Support**: Know what users are trying to accomplish when queries fail
- **Capacity Planning**: Predict load based on business cycles (e.g., "return analysis" peaks in January)

---

## 🔍 Critical Analysis of Approaches

### Approach 1: LLM-Based Query Understanding (User's Suggestion)
**Using Cursor Composer, Claude, GPT-4, or similar**

#### **How It Works:**
```
Query SQL → LLM Prompt → Natural Language Description + Classification
```

Example:
```sql
SELECT retailer_moniker, COUNT(*) as return_count, 
       AVG(refund_amount) as avg_refund
FROM returns r
JOIN shipments s ON r.shipment_id = s.id
WHERE return_date >= '2024-01-01'
  AND return_reason = 'damaged'
GROUP BY retailer_moniker
```

LLM Output:
```
Business Function: Return Analysis & Monitoring
Description: "Analyzes damaged item returns by retailer, calculating return counts and average refund amounts for 2024"
Tables Used: returns, shipments
Key Columns: return_reason, refund_amount, return_date
Query Type: Aggregation with temporal filter
```

#### **Pros:**
- ✅ Understands complex SQL semantics
- ✅ Natural language output (human-readable)
- ✅ Flexible - handles edge cases
- ✅ Can infer business intent even from cryptic queries
- ✅ Minimal manual pattern engineering

#### **Cons:**
- ❌ **Cost at scale**: $0.01-0.05 per query with GPT-4 (thousands of queries = $$$$)
- ❌ **Rate limits**: API throttling for batch processing
- ❌ **Consistency**: Same query might get different classifications
- ❌ **Hallucination risk**: May invent table names or misunderstand joins
- ❌ **Token limits**: Long queries (5K+ characters) might get truncated
- ❌ **Latency**: Slow for real-time classification (100-500ms per query)

#### **Cost Estimate:**
- **Hub (2025)**: ~500-1,000 unique query patterns
- **GPT-4o-mini**: $0.15/1M input tokens, $0.60/1M output tokens
- **Estimated**: $5-15 for one-time analysis
- **At scale (all consumers)**: $50-100

**Verdict**: ⚠️ Good for **prototype** but expensive for continuous use

---

### Approach 2: SQL Parsing + Rule-Based Classification
**Using sqlglot, sqlparse, or BigQuery SQL parser**

#### **How It Works:**
1. Parse SQL to Abstract Syntax Tree (AST)
2. Extract structural features:
   - Tables accessed: `['returns', 'shipments']`
   - Columns used: `['retailer_moniker', 'return_date', 'refund_amount']`
   - Operations: `['JOIN', 'WHERE', 'GROUP BY', 'AVG', 'COUNT']`
   - Filters: `{return_date: '>=2024-01-01', return_reason: 'damaged'}`
3. Apply business rules:
   - `IF 'returns' table + 'return_reason' column → "Return Analysis"`
   - `IF 'shipments' + 'delivery_date' filter → "Delivery Performance"`
   - `IF GROUP BY retailer + aggregation → "Retailer-level KPI"`

#### **Pros:**
- ✅ **Free**: No API costs
- ✅ **Fast**: <10ms per query
- ✅ **Deterministic**: Same query = same classification
- ✅ **Scalable**: Can process millions of queries
- ✅ **Accurate extraction**: Precisely identifies tables/columns
- ✅ **No hallucination**: Only extracts what's actually there

#### **Cons:**
- ❌ **Manual rule creation**: Requires domain knowledge upfront
- ❌ **Rigid**: Doesn't understand semantic nuances
- ❌ **Maintenance**: Rules need updates as business evolves
- ❌ **Edge cases**: Complex queries might not match patterns
- ❌ **No natural language**: Output is categories, not descriptions

#### **Implementation Example:**
```python
import sqlglot

# Parse query
parsed = sqlglot.parse_one(query_text, dialect='bigquery')

# Extract tables
tables = [table.name for table in parsed.find_all(sqlglot.exp.Table)]

# Extract columns in WHERE clause
where_columns = [col.name for col in parsed.find(sqlglot.exp.Where).find_all(sqlglot.exp.Column)]

# Classification rules
if 'returns' in tables and 'return_reason' in where_columns:
    category = 'Return Analysis'
elif 'shipments' in tables and 'delivery_date' in where_columns:
    category = 'Delivery Performance'
else:
    category = 'Other'
```

**Verdict**: ✅ Best for **production** - fast, cheap, reliable

---

### Approach 3: Hybrid (Recommended!) 🏆
**SQL Parsing + LLM for Edge Cases**

#### **How It Works:**
1. **Phase 1**: SQL parsing extracts structural features (100% of queries)
2. **Phase 2**: Rule-based classification attempts matching (80-90% success)
3. **Phase 3**: LLM analyzes unclassified queries (10-20% only!)
4. **Phase 4**: LLM-generated classifications become new rules (continuous improvement)

#### **Workflow:**
```
Query → SQL Parser → Extract Features
         ↓
   Rule Matching
         ↓
   Classified? 
    Yes → Done (fast, free)
    No → LLM Analysis (slow, small cost)
         ↓
    Add new rule for future
```

#### **Pros:**
- ✅ **90% cost savings**: Only use LLM for edge cases
- ✅ **Fast for common queries**: <10ms
- ✅ **Handles complexity**: LLM backup for unusual queries
- ✅ **Self-improving**: New patterns become rules
- ✅ **Best of both worlds**: Speed + intelligence

#### **Cons:**
- ⚠️ More complex to implement initially
- ⚠️ Requires orchestration logic

**Verdict**: ⭐ **RECOMMENDED** - Optimal cost/quality tradeoff

---

### Approach 4: Embeddings + Clustering
**Vector embeddings → Cluster similar queries → LLM describes clusters**

#### **How It Works:**
1. Convert each query to embedding vector (OpenAI ada-002, sentence-transformers)
2. Cluster similar queries (K-means, HDBSCAN)
3. LLM describes each cluster (100 clusters, not 1000 queries!)
4. Assign all queries in cluster the same classification

#### **Example:**
- **Cluster 37** (25 queries): All about return rate calculation
  - LLM prompt: "Here are 5 sample queries from this cluster. What business function do they represent?"
  - LLM: "Return rate analysis with retailer breakdowns"
- **Result**: 25 queries classified for the cost of 1 LLM call!

#### **Pros:**
- ✅ **Cost-efficient**: $0.10/1M tokens for embeddings
- ✅ **Discovers patterns**: Finds similar queries automatically
- ✅ **Scalable**: 10K queries → 100 clusters → $5 LLM cost
- ✅ **Good for exploration**: "What are the main query types?"

#### **Cons:**
- ❌ **Cluster quality**: Embeddings might group unrelated queries
- ❌ **Requires tuning**: Optimal cluster count is unknown
- ❌ **Less precise**: Individual query nuances lost

**Verdict**: ✨ **Great for initial exploration**, then switch to Hybrid

---

## 🏗️ Recommended Implementation Architecture

### **Phase 1: Exploration (One-time)**
**Use Embeddings + Clustering to discover business function categories**

```
All Hub queries (500-1K)
  ↓ OpenAI Embeddings ($0.50)
  ↓ Cluster into 20-50 groups
  ↓ LLM describes each cluster ($5)
  ↓ Human reviews and refines categories
= Business function taxonomy ($5.50 total)
```

**Output**: Category list like:
- Return Analysis
- Delivery Performance
- Inventory Tracking
- Retailer Performance Dashboards
- Shipment Tracking
- Customer Analytics
- etc.

---

### **Phase 2: Production System (Reusable)**
**Hybrid: SQL Parsing + Rules + LLM Fallback**

#### **System Components:**

**1. SQL Parser Module** (`sql_parser.py`)
```python
class SQLAnalyzer:
    def parse(self, query_text: str) -> QueryFeatures:
        """Extract structural features from SQL"""
        return QueryFeatures(
            tables=['returns', 'shipments'],
            columns=['retailer_moniker', 'return_date'],
            operations=['JOIN', 'GROUP BY', 'AVG'],
            filters={'return_date': '>=2024-01-01'},
            has_aggregation=True,
            complexity_score=7
        )
```

**2. Rule-Based Classifier** (`classifier.py`)
```python
class BusinessFunctionClassifier:
    def __init__(self, rules_file: str):
        self.rules = load_rules(rules_file)
    
    def classify(self, features: QueryFeatures) -> Classification:
        """Apply business rules to classify query"""
        for rule in self.rules:
            if rule.matches(features):
                return Classification(
                    category=rule.category,
                    confidence=0.95,
                    method='rule-based'
                )
        return None  # Unclassified → send to LLM
```

**3. LLM Fallback** (`llm_classifier.py`)
```python
class LLMClassifier:
    def classify(self, query_text: str, features: QueryFeatures) -> Classification:
        """Use LLM for complex/unclassified queries"""
        prompt = f"""
        Analyze this BigQuery SQL query and describe its business purpose:
        
        Query: {query_text[:2000]}
        
        Tables used: {features.tables}
        Key columns: {features.columns}
        
        Provide:
        1. Business function category (e.g., "Return Analysis")
        2. Plain English description (1 sentence)
        3. Primary business question being answered
        """
        response = call_llm(prompt)
        return parse_llm_response(response)
```

**4. Orchestrator** (`query_analyzer.py`)
```python
class QueryAnalyzer:
    def __init__(self):
        self.parser = SQLAnalyzer()
        self.rule_classifier = BusinessFunctionClassifier('rules.yaml')
        self.llm_classifier = LLMClassifier()
    
    def analyze(self, query_text: str) -> QueryAnalysis:
        # Step 1: Parse
        features = self.parser.parse(query_text)
        
        # Step 2: Try rules
        classification = self.rule_classifier.classify(features)
        
        # Step 3: Fallback to LLM if needed
        if classification is None:
            classification = self.llm_classifier.classify(query_text, features)
            # Save as new rule for future
            self.save_new_rule(features, classification)
        
        return QueryAnalysis(
            features=features,
            classification=classification
        )
```

---

### **Phase 3: Integration with BigQuery Analysis**

**Query Classification Table** (`query_opt.query_classifications`)
```sql
CREATE TABLE narvar-data-lake.query_opt.query_classifications (
  job_id STRING,
  query_hash STRING,  -- MD5 of normalized query
  
  -- Business classification
  business_function STRING,  -- "Return Analysis", "Delivery Performance", etc.
  business_description STRING,  -- Plain English description
  classification_confidence FLOAT64,
  classification_method STRING,  -- 'rule-based' or 'llm'
  
  -- Data assets
  tables_accessed ARRAY<STRING>,
  key_columns ARRAY<STRING>,
  
  -- Query characteristics
  query_type STRING,  -- 'lookup', 'aggregation', 'transformation'
  complexity_score INT64,  -- 1-10
  has_joins BOOL,
  has_window_functions BOOL,
  has_subqueries BOOL,
  
  -- Metadata
  classification_date TIMESTAMP,
  classification_version STRING
)
PARTITION BY DATE(classification_date)
CLUSTER BY business_function, classification_method;
```

**Join with Traffic Classification**:
```sql
SELECT
  tc.consumer_subcategory,
  tc.retailer_moniker,
  qc.business_function,
  COUNT(*) as jobs,
  SUM(tc.slot_hours) as total_slot_hours,
  AVG(tc.execution_time_seconds) as avg_exec_time,
  COUNTIF(tc.is_qos_violation) as qos_violations
FROM `narvar-data-lake.query_opt.traffic_classification` tc
LEFT JOIN `narvar-data-lake.query_opt.query_classifications` qc USING (job_id)
WHERE tc.consumer_subcategory IN ('HUB', 'MONITOR', 'METABASE')
GROUP BY 1, 2, 3
ORDER BY total_slot_hours DESC
```

**Insights Enabled:**
- "Return Analysis queries consume 40% of Hub capacity"
- "Walmart's top business function: Delivery Performance (200 queries/day)"
- "Metabase users focus on Inventory Tracking (high QoS violation rate)"

---

## 🔧 Implementation Tools

### **SQL Parsing Libraries:**

**1. sqlglot** (Recommended! ⭐)
```bash
pip install sqlglot
```
- ✅ Supports BigQuery dialect
- ✅ Fast and actively maintained
- ✅ Excellent AST manipulation
- ✅ Can transpile between SQL dialects

**2. sqlparse**
```bash
pip install sqlparse
```
- ✅ Simple and lightweight
- ⚠️ Limited dialect support
- ⚠️ Basic parsing only

**3. BigQuery Client**
```python
from google.cloud import bigquery
# Use DRY RUN to get query plan
```
- ✅ Native BigQuery understanding
- ⚠️ Requires API calls (cost)

---

### **LLM Options (Ranked by Cost):**

| Model | Cost per Query* | Speed | Quality | Best For |
|-------|----------------|-------|---------|----------|
| Claude 3.5 Haiku | $0.0008 | Fast | Good | Production fallback |
| GPT-4o-mini | $0.001 | Fast | Good | Production fallback |
| Claude 3.5 Sonnet | $0.003 | Medium | Excellent | Complex queries |
| GPT-4o | $0.005 | Medium | Excellent | Initial exploration |
| Llama 3.1 (local) | $0 | Fast | Good | If running locally |

*Estimated for ~1K token query analysis

**Recommendation**: Use **GPT-4o-mini** or **Claude 3.5 Haiku** for fallback

---

### **Embedding Options:**

| Model | Cost per 1K queries | Dimension | Best For |
|-------|---------------------|-----------|----------|
| OpenAI ada-002 | $0.10 | 1536 | Production |
| sentence-transformers (local) | $0 | 384-768 | Budget option |
| Voyage AI | $0.12 | 1024 | High quality |

**Recommendation**: Use **sentence-transformers** locally (free, fast)

---

## 📊 Proof of Concept Plan

### **Week 1: Exploration**
1. Extract 500-1,000 Hub queries (diverse sample)
2. Generate embeddings ($0.50)
3. Cluster into 20-50 groups
4. LLM describes each cluster ($5)
5. Human review and taxonomy creation
**Deliverable**: Business function category list

### **Week 2: Build Parser + Rules**
1. Implement SQL parser (sqlglot)
2. Create initial rule set based on taxonomy
3. Test on Hub sample
4. Measure rule match rate
**Deliverable**: Working rule-based classifier

### **Week 3: Add LLM Fallback**
1. Implement LLM classifier for unmatched queries
2. Test hybrid system
3. Generate new rules from LLM results
4. Re-test with expanded rules
**Deliverable**: Hybrid classification system

### **Week 4: Scale to Production**
1. Process all Hub queries (2025)
2. Create classification table in BigQuery
3. Join with traffic_classification
4. Generate analysis report
**Deliverable**: Full Hub business function analysis

---

## 💰 Cost Estimate

### **One-time Setup (POC):**
- Embeddings (1K queries): $0.10
- LLM clustering (50 clusters): $5
- LLM fallback (10% of queries): $10
- **Total**: ~$15

### **Production Analysis (all 2025 Hub queries):**
- SQL parsing: $0 (local)
- Rule matching: $0 (90% of queries)
- LLM fallback (10%): $10-20
- **Total**: ~$10-20

### **Continuous Use (monthly):**
- New queries only (~1K/month)
- LLM fallback (10%): $1-2
- **Total**: ~$1-2/month

**Verdict**: 💚 **Very affordable!**

---

## 🚀 Alternative: Quick Win Approach

If you want **immediate results** without building infrastructure:

### **Option A: Manual Sampling + LLM (1-2 hours)**
1. Sample 50 Hub queries (stratified by performance)
2. Feed to Claude/GPT-4 with prompt:
   ```
   Classify these 50 queries into business function categories.
   For each query provide:
   - Category name
   - Description
   - Tables used
   - Key columns
   ```
3. Human reviews and creates taxonomy
4. Use taxonomy to manually tag remaining queries

**Cost**: $2-5  
**Time**: 2 hours  
**Coverage**: Good enough for initial analysis

### **Option B: Simple Pattern Matching (30 minutes)**
1. Grep for table names in query text
2. Simple rules:
   - `grep 'returns' → "Return Analysis"`
   - `grep 'shipments.*delivery_date' → "Delivery Performance"`
3. Manual review of unclassified

**Cost**: $0  
**Time**: 30 minutes  
**Coverage**: 60-70% (acceptable for first pass)

---

## 🎯 Recommendation

### **For This Project (Hub Analysis):**
**Start with Option B (Simple Pattern Matching)**, then:
1. Run pattern discovery query (identify retailer extraction patterns)
2. Manually classify 20-30 sample queries by business function
3. Create simple regex rules for common patterns
4. Use for Hub analysis report

**Future Work (Reusable Framework):**
Build **Hybrid System (Approach 3)** as separate sub-project

---

## ❓ Questions for You

Before proceeding, I need your input:

### **1. Scope & Timeline:**
- **Quick win** (simple patterns for current Hub analysis)? ← I recommend this
- **Full framework** (4-week build for reusable system)?
- **Hybrid** (simple now, framework later)?

### **2. LLM Preferences:**
- Comfortable using **OpenAI/Anthropic APIs** (small cost)?
- Prefer **free local models** (Llama, Mistral)?
- **No LLM** (rule-based only)?

### **3. Business Domain Knowledge:**
- Do you know the main **business functions** Hub users care about?
  - Examples: "Return Rate Monitoring", "Delivery SLA Tracking", etc.
- Or should we **discover** them from data?

### **4. Integration:**
- Want this as **standalone tool** (Python scripts)?
- Or **integrated into BigQuery** (SQL + UDFs)?
- Or **Jupyter notebook** workflow?

### **5. Output Format:**
- **Simple categories** (e.g., "Return Analysis")?
- **Detailed descriptions** (e.g., "Calculates return rates by retailer for damaged items in Q1 2024")?
- **Both**?

---

## 📁 Next Steps

Based on your answers, I can:

1. **Immediate**: Add simple pattern classification to current Hub analysis
2. **Short-term**: Build POC with embeddings + clustering
3. **Long-term**: Create separate project for reusable framework

**Your call!** 🚀

---

**Document Version**: 1.0  
**Last Updated**: November 12, 2025  
**Author**: AI Assistant  
**Status**: Proposal - Awaiting User Decision

