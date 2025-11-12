# BigQuery Audit Log Analysis Queries - Summary

**Purpose**: This collection of queries analyzes BigQuery audit logs to support capacity planning and traffic analysis for the peak period November 2025 - January 2026.

**Data Source**: `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`

**Last Updated**: October 30, 2025

---

## Table of Contents
- [Job Information Queries](#job-information-queries)
- [Cost Analysis Queries](#cost-analysis-queries)
- [Slot Usage Queries](#slot-usage-queries)
- [Concurrency Analysis Queries](#concurrency-analysis-queries)
- [Performance Analysis Queries](#performance-analysis-queries)
- [User and Project Analysis Queries](#user-and-project-analysis-queries)
- [Specialized Analysis Queries](#specialized-analysis-queries)

---

## Job Information Queries

### general_job_information.sql / general_job_information_general.sql
**Purpose**: Provides comprehensive information about all jobs (query, load, extract, table copy) executed over a specified time interval.

**Key Metrics**:
- Job execution details (start time, end time, duration)
- Billing information (bytes billed, on-demand cost)
- Slot usage (totalSlotMs, approximate slot count)
- Job type categorization

**Use Cases**: 
- Overall system activity monitoring
- Job performance baseline establishment
- Capacity planning foundation data

---

### query_job_information.sql / query_job_information_general.sql
**Purpose**: Focuses specifically on query jobs, providing detailed execution statistics and performance metrics.

**Key Metrics**:
- Query-specific execution details
- Resource consumption per query
- Query configuration details

**Use Cases**:
- Query performance optimization
- Query workload analysis
- Query cost attribution

---

### load_job_information.sql / load_job_information_general.sql
**Purpose**: Analyzes data loading jobs including their execution characteristics and resource consumption.

**Key Metrics**:
- Load job execution time
- Data volume loaded
- Resource utilization for load operations

**Use Cases**:
- Data ingestion pipeline monitoring
- Load job optimization
- ETL capacity planning

---

### looker_job_information.sql / looker_job_information_general.sql
**Purpose**: Specifically tracks jobs initiated by Looker service accounts, helping understand BI tool impact on BigQuery resources.

**Key Metrics**:
- Looker-generated job statistics
- BI workload patterns
- Looker service account activity

**Use Cases**:
- BI tool resource consumption analysis
- Looker workload optimization
- Separation of BI vs. ad-hoc query loads

---

## Cost Analysis Queries

### top_billed_queries.sql / top_billed_queries_general.sql
**Purpose**: Identifies the highest cost queries based on bytes billed, with multiple unit conversions for easy analysis.

**Key Metrics**:
- Total bytes billed (in bytes, MB, GB, TB)
- Estimated on-demand cost ($5 per TB)
- Query text and execution details

**Use Cases**:
- Cost optimization opportunities identification
- Most expensive query tracking
- Budget allocation and forecasting

---

### top_billed_queries_deduplicated.sql / top_billed_queries_deduplicated_general.sql
**Purpose**: Similar to top_billed_queries but with deduplication logic to avoid counting the same query multiple times.

**Key Metrics**:
- Deduplicated query costs
- Unique query patterns
- Total billing by distinct queries

**Use Cases**:
- Accurate cost attribution
- Repeated query identification
- Query optimization prioritization

---

### top_costly_queries.sql / top_costly_queries_general.sql
**Purpose**: Ranks queries by their operational cost, considering both billing and resource consumption.

**Key Metrics**:
- Comprehensive cost metrics
- Slot milliseconds consumed
- Cost per execution

**Use Cases**:
- Query optimization target identification
- Cost-benefit analysis
- Resource allocation decisions

---

### top_billed_labels.sql / top_billed_labels_general.sql
**Purpose**: Analyzes costs by job labels, enabling cost tracking by team, project, or application.

**Key Metrics**:
- Cost aggregated by labels
- Label usage patterns
- Cost allocation by tags

**Use Cases**:
- Cost allocation by team/project
- Chargeback reporting
- Label-based cost optimization

---

### top_cost_users.sql / top_cost_users_general.sql
**Purpose**: Identifies users generating the highest BigQuery costs.

**Key Metrics**:
- On-demand cost per user
- User billing patterns
- Cost ranking by principal email

**Use Cases**:
- User-level cost attribution
- Training needs identification
- Cost awareness and accountability

---

### top_cost_user_by_region_and_project.sql
**Purpose**: Breaks down costs by user, region, and project combination for granular cost analysis.

**Key Metrics**:
- Multi-dimensional cost breakdown
- Regional cost patterns
- Project-specific user costs

**Use Cases**:
- Regional cost analysis
- Project-level cost allocation
- Cross-region cost comparison

---

### billing_recommendations_per_query.sql / billing_recommendations_per_query_general.sql
**Purpose**: Provides intelligent recommendations on whether queries should use on-demand or flat-rate billing.

**Key Metrics**:
- On-demand vs. flat-rate scoring
- Recommended billing mode
- Cost efficiency ratios
- Query frequency impact

**Use Cases**:
- Billing model optimization
- Flat-rate vs. on-demand decision making
- Cost optimization strategies

---

## Slot Usage Queries

### slots_by_second.sql / slots_by_second_general.sql
**Purpose**: Tracks slot consumption at a per-second granularity for detailed capacity planning.

**Key Metrics**:
- Slot count per second
- Job type breakdown (query, load, extract, copy)
- Time-series slot utilization

**Use Cases**:
- Real-time capacity monitoring
- Peak usage identification
- Second-level capacity planning

---

### slots_by_minute.sql / slots_by_minute_general.sql
**Purpose**: Aggregates slot usage at the minute level for medium-granularity analysis.

**Key Metrics**:
- Slot count per minute
- Job type distribution
- Minute-by-minute utilization patterns

**Use Cases**:
- Standard capacity monitoring
- Minute-level traffic patterns
- Reservation sizing

---

### slots_by_hour.sql / slots_by_hour_general.sql
**Purpose**: Provides hourly slot consumption patterns for daily planning cycles.

**Key Metrics**:
- Hourly slot aggregations
- Daily usage patterns
- Hour-of-day utilization trends

**Use Cases**:
- Daily capacity planning
- Business hours vs. off-hours analysis
- Hourly reservation optimization

---

### slots_by_day.sql / slots_by_day_general.sql
**Purpose**: Summarizes slot usage at the daily level for long-term trend analysis.

**Key Metrics**:
- Daily slot consumption
- Day-over-day trends
- Weekly patterns

**Use Cases**:
- Long-term capacity planning
- Weekly/monthly trend analysis
- Seasonal pattern identification

---

### slots_by_minute_and_user.sql / slots_by_minute_and_user_general.sql
**Purpose**: Combines minute-level slot usage with user attribution for detailed accountability.

**Key Metrics**:
- Per-user slot consumption per minute
- User activity patterns
- Time-based user resource usage

**Use Cases**:
- User-level capacity attribution
- Heavy user identification
- Time-based user behavior analysis

---

### query_slots_per_minute.sql / query_slots_per_minute_general.sql
**Purpose**: Focuses specifically on query job slot consumption at minute-level granularity.

**Key Metrics**:
- Query-only slot usage per minute
- Query workload patterns
- Query capacity requirements

**Use Cases**:
- Query workload capacity planning
- Query-specific reservation sizing
- Query pattern analysis

---

### query_slots_per_second.sql / query_slots_per_second_general.sql
**Purpose**: Tracks query job slot consumption at second-level granularity for detailed analysis.

**Key Metrics**:
- Per-second query slot consumption
- Second-level query peaks
- Real-time query capacity needs

**Use Cases**:
- Real-time query monitoring
- Query burst capacity planning
- Second-level query patterns

---

### load_slots_per_minute.sql / load_slots_per_minute_general.sql
**Purpose**: Analyzes slot usage for data loading jobs at minute-level resolution.

**Key Metrics**:
- Load job slot consumption per minute
- Data loading patterns
- ETL capacity requirements

**Use Cases**:
- ETL capacity planning
- Load job scheduling optimization
- Data pipeline resource allocation

---

### load_slots_per_second.sql / load_slots_per_second_general.sql
**Purpose**: Provides second-level granularity for load job slot consumption analysis.

**Key Metrics**:
- Per-second load job slot usage
- Load job burst patterns
- Real-time ingestion capacity

**Use Cases**:
- Real-time ingestion monitoring
- Load burst capacity planning
- Second-level load patterns

---

### slot_usage_by_billing_project_and_project.sql
**Purpose**: Breaks down slot usage by billing project and resource project combinations.

**Key Metrics**:
- Cross-project slot attribution
- Billing vs. resource project mapping
- Multi-project capacity allocation

**Use Cases**:
- Cross-project cost allocation
- Multi-project capacity planning
- Billing project chargeback

---

## Concurrency Analysis Queries

### concurrent_queries_by_minute.sql / concurrent_queries_by_minute_general.sql
**Purpose**: Measures the number of queries running concurrently at each minute to identify concurrency patterns.

**Key Metrics**:
- Concurrent job count per minute
- Peak concurrency periods
- Minute-by-minute concurrency trends

**Use Cases**:
- Concurrency limit planning
- Peak period identification
- Reservation sizing for concurrent workloads

---

### concurrent_queries_by_second.sql / concurrent_queries_by_second_general.sql
**Purpose**: Provides second-level granularity for concurrent query analysis.

**Key Metrics**:
- Concurrent job count per second
- Second-level concurrency peaks
- Real-time concurrency patterns

**Use Cases**:
- Real-time concurrency monitoring
- Burst concurrency analysis
- Fine-grained capacity planning

---

## Performance Analysis Queries

### longest_running_queries.sql / longest_running_queries_general.sql
**Purpose**: Identifies queries with the longest execution times for performance optimization.

**Key Metrics**:
- Query execution duration (seconds)
- Runtime to bytes billed ratio
- Approximate slot count
- Query text for analysis

**Use Cases**:
- Performance optimization targeting
- Long-running query identification
- Query efficiency analysis

---

### top_complex_queries.sql / top_complex_queries_general.sql
**Purpose**: Ranks queries by complexity (approximate slot count) to identify resource-intensive operations.

**Key Metrics**:
- Slot count as complexity metric
- Total slot milliseconds
- Execution time vs. slot usage

**Use Cases**:
- Complex query identification
- Query optimization prioritization
- Resource-intensive operation analysis

---

### query_counts.sql / query_counts_general.sql
**Purpose**: Counts query executions to identify frequently run queries and patterns.

**Key Metrics**:
- Query execution frequency
- Most-run query patterns
- Query repetition analysis

**Use Cases**:
- Query caching opportunities
- Frequent query optimization
- Materialized view candidates identification

---

## User and Project Analysis Queries

### table_query_counts.sql / table_query_counts_general.sql
**Purpose**: Analyzes which tables are queried most frequently and their access patterns.

**Key Metrics**:
- Table access frequency
- Table reference patterns
- Most-queried datasets

**Use Cases**:
- Table popularity analysis
- Caching strategy development
- Hot table identification

---

### jobs_in_regions.sql
**Purpose**: Tracks job distribution across different geographic regions and identifies unexpected regional activity.

**Key Metrics**:
- Jobs by region and project
- Job type distribution by location
- Regional activity patterns

**Use Cases**:
- Regional capacity planning
- Multi-region workload distribution
- Unexpected regional activity detection

---

## File Naming Conventions

- **Standard queries**: Named by functionality (e.g., `top_billed_queries.sql`)
- **"_general" suffix**: Optimized or alternate version with potentially different filtering or aggregation logic
- **Test files** (prefixed with `_test_`): Limited result sets for query validation

---

## Query Parameters

Most queries include a configurable parameter:
```sql
DECLARE interval_in_days INT64 DEFAULT 7;
```

This allows you to adjust the time window for analysis:
- **1 day**: Real-time/recent analysis
- **7 days**: Weekly patterns (default for most queries)
- **30 days**: Monthly trends
- **90+ days**: Seasonal patterns and long-term planning

For peak period capacity planning (Nov 2025 - Jan 2026), consider:
- Using 365 days for year-over-year comparison
- Using 90 days for recent trend analysis
- Using 7 days for current baseline establishment

---

## Peak Period Analysis Recommendations

For November 2025 - January 2026 capacity planning:

1. **Baseline Establishment**: Run `general_job_information_general.sql` with 90-day interval
2. **Cost Baseline**: Use `top_billed_queries_general.sql` to identify current top cost drivers
3. **Slot Baseline**: Analyze `slots_by_hour_general.sql` and `slots_by_day_general.sql` for hourly and daily patterns
4. **Concurrency Baseline**: Use `concurrent_queries_by_minute_general.sql` to understand current concurrency needs
5. **Peak Identification**: Run `slots_by_minute_general.sql` to identify specific peak minutes
6. **User Impact**: Analyze `top_cost_users_general.sql` and `slots_by_minute_and_user_general.sql` for user-level patterns

### Recommended Analysis Workflow:
1. Historical pattern analysis (compare Nov-Jan from previous years if available)
2. Current baseline establishment (last 7-30 days)
3. Growth projection (compare YoY trends)
4. Peak period simulation (add expected growth to current baseline)
5. Reservation sizing (based on projected peak + buffer)

---

## Notes

- All queries filter out BigQuery script child jobs (`script_job_%`)
- All queries exclude dry run executions
- Slot calculations use `SAFE_DIVIDE` to handle division by zero
- Cost calculations assume $5 per TB of data processed (on-demand pricing)
- Timestamps are in the timezone of the BigQuery audit log entries
- Deduplication logic (where present) uses `ROW_NUMBER()` partitioned by job ID

---

## Support for Capacity Planning

These queries support multiple capacity planning scenarios:

1. **Reservation Sizing**: Use slot usage queries to determine appropriate reservation sizes
2. **Billing Mode Selection**: Use billing recommendation queries to optimize cost structure
3. **User Education**: Use top cost/user queries to identify training opportunities
4. **Query Optimization**: Use performance queries to prioritize optimization efforts
5. **Regional Planning**: Use jobs_in_regions to plan multi-region deployments
6. **Concurrency Planning**: Use concurrent query analysis to plan for parallel workloads

---

## Version History

- **v1.0** (Oct 30, 2025): Initial query summary for Nov 2025 - Jan 2026 capacity planning
  - Updated all queries to use `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  - Created test queries for validation
  - Documented all 53 query files

---

## Contact

For questions about these queries or capacity planning assistance, please contact the DoiT International Cloud Management Platform team.











