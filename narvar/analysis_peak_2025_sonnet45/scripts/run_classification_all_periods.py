#!/usr/bin/env python3
"""
Traffic Classification - Multi-Period Automation Script

Purpose: Automatically classify BigQuery traffic for multiple peak and non-peak periods
Output: Populates narvar-data-lake.query_opt.traffic_classification table
Runtime: ~2-3 hours for all periods (can run overnight)

Requirements:
- google-cloud-bigquery
- Proper GCP credentials configured
- Access to narvar-data-lake project

Usage:
    python run_classification_all_periods.py --mode all
    python run_classification_all_periods.py --mode peak-only
    python run_classification_all_periods.py --mode test  # Run one period only
"""

import argparse
import sys
from datetime import datetime, date
from pathlib import Path
from typing import List, Dict, Tuple
import time

from google.cloud import bigquery
from google.cloud.exceptions import GoogleCloudError


# ============================================================================
# CONFIGURATION
# ============================================================================

PROJECT_ID = "narvar-data-lake"
DATASET_ID = "query_opt"
TABLE_ID = "traffic_classification"
CLASSIFICATION_VERSION = "v1.3"  # 2025 ML services (dev-testing, vertex-pipeline, promise-ai, churnzero)

# Period definitions
PERIODS = [
    # ====================
    # NON-PEAK PERIODS (Baselines)
    # ====================
    {
        "label": "Baseline_2025_Sep_Oct",
        "start_date": "2025-09-01",
        "end_date": "2025-10-31",
        "type": "non_peak",
        "priority": 0,  # HIGHEST PRIORITY - Most recent baseline before 2025-2026 peak!
        "skip": False,
        "description": "Most recent baseline (Sep-Oct 2025) - freshest pre-peak data"
    },
    {
        "label": "Baseline_2024_Sep_Oct",
        "start_date": "2024-09-01",
        "end_date": "2024-10-31",
        "type": "non_peak",
        "priority": 1,  # Already done, but included for completeness
        "skip": True,   # Set to False to re-run with improved patterns
        "description": "Recent baseline - pattern discovery"
    },
    {
        "label": "NonPeak_2024_Feb_Mar",
        "start_date": "2024-02-01",
        "end_date": "2024-03-31",
        "type": "non_peak",
        "priority": 4,
        "skip": True,  # v1.0 already done (1.2% unclassified - excellent)
        "description": "Post-peak 2023-2024 baseline"
    },
    {
        "label": "NonPeak_2023_Sep_Oct",
        "start_date": "2023-09-01",
        "end_date": "2023-10-31",
        "type": "non_peak",
        "priority": 5,
        "skip": True,  # v1.0 already done (0.0% unclassified - perfect!)
        "description": "Pre-peak 2023-2024 baseline"
    },
    {
        "label": "NonPeak_2023_Feb_Mar",
        "start_date": "2023-02-01",
        "end_date": "2023-03-31",
        "type": "non_peak",
        "priority": 7,
        "skip": True,  # v1.2 already done (0.00% unclassified - perfect!)
        "description": "Post-peak 2022-2023 baseline"
    },
    {
        "label": "NonPeak_2022_Sep_Oct",
        "start_date": "2022-09-01",
        "end_date": "2022-10-31",
        "type": "non_peak",
        "priority": 8,
        "skip": True,  # v1.2 already done (0.00% unclassified - perfect!)
        "description": "Pre-peak 2022-2023 baseline"
    },
    
    # ====================
    # PEAK PERIODS
    # ====================
    {
        "label": "Peak_2024_2025",
        "start_date": "2024-11-01",
        "end_date": "2025-01-31",
        "type": "peak",
        "priority": 2,
        "skip": True,  # v1.0 already done (2.7% unclassified - excellent)
        "description": "Most recent complete peak"
    },
    {
        "label": "Peak_2023_2024",
        "start_date": "2023-11-01",
        "end_date": "2024-01-31",
        "type": "peak",
        "priority": 3,
        "skip": True,  # v1.0 already done (0.1% unclassified - excellent)
        "description": "Historical peak for YoY comparison"
    },
    {
        "label": "Peak_2022_2023",
        "start_date": "2022-11-01",
        "end_date": "2023-01-31",
        "type": "peak",
        "priority": 6,
        "skip": True,  # v1.2 already done (0.00% unclassified - perfect!)
        "description": "Historical peak for 3-year trend"
    },
]


# ============================================================================
# SQL TEMPLATE
# ============================================================================

SQL_TEMPLATE = """
-- Auto-generated classification query
-- Period: {period_label}
-- Generated: {timestamp}

DECLARE start_date DATE DEFAULT '{start_date}';
DECLARE end_date DATE DEFAULT '{end_date}';
DECLARE analysis_period_label STRING DEFAULT '{period_label}';
DECLARE classification_version STRING DEFAULT '{classification_version}';

-- QoS thresholds
DECLARE external_qos_threshold_seconds INT64 DEFAULT 60;
DECLARE internal_qos_threshold_seconds INT64 DEFAULT 480;
DECLARE automated_qos_threshold_seconds INT64 DEFAULT 1800;

-- Slot cost calculation
DECLARE slot_cost_per_hour FLOAT64 DEFAULT 0.0494;

-- ============================================================================
-- Insert into physical table
-- ============================================================================

INSERT INTO `{project_id}.{dataset_id}.{table_id}`

WITH
-- Get retailer to monitor project mappings using MD5 hash
retailer_mappings AS (
  SELECT DISTINCT 
    retailer_moniker,
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-prod') AS project_id_prod,
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-qa') AS project_id_qa,
    CONCAT('monitor-', SUBSTR(TO_HEX(MD5(retailer_moniker)), 0, 7), '-us-stg') AS project_id_stg
  FROM `narvar-data-lake.reporting.t_return_details`
  WHERE DATE(return_created_date) >= '2022-01-01'
    AND retailer_moniker IS NOT NULL
),

-- Extract and deduplicate audit log data
audit_data AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId AS job_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.location AS location,
    
    CASE protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName
      WHEN 'query_job_completed' THEN 'QUERY'
      WHEN 'load_job_completed' THEN 'LOAD'
      WHEN 'extract_job_completed' THEN 'EXTRACT'
      WHEN 'table_copy_job_completed' THEN 'TABLE_COPY'
    END AS job_type,
    
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime AS start_time,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime AS end_time,
    TIMESTAMP_DIFF(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
      SECOND
    ) AS execution_time_seconds,
    
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes AS total_billed_bytes,
    
    SAFE_DIVIDE(
      protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs,
      TIMESTAMP_DIFF(
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime,
        protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime,
        MILLISECOND
      )
    ) AS approximate_slot_count,
    
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query AS query_text,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.reservation AS reservation_name,
    protopayload_auditlog.requestMetadata.callerSuppliedUserAgent AS user_agent,
    
    ROW_NUMBER() OVER(
      PARTITION BY protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId 
      ORDER BY timestamp DESC
    ) AS row_num
    
  FROM `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE DATE(timestamp) BETWEEN start_date AND end_date
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId NOT LIKE 'script_job_%'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName LIKE '%_job_completed'
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs IS NOT NULL
),

audit_deduplicated AS (
  SELECT * EXCEPT(row_num)
  FROM audit_data
  WHERE row_num = 1
),

retailer_selected AS (
  SELECT
    a.job_id,
    a.project_id,
    rm.retailer_moniker
  FROM audit_deduplicated a
  INNER JOIN retailer_mappings rm
    ON a.project_id IN (rm.project_id_prod, rm.project_id_qa, rm.project_id_stg)
  WHERE STARTS_WITH(LOWER(a.project_id), 'monitor-')
),

traffic_classified AS (
  SELECT
    a.*,
    rs.retailer_moniker,
    
    COALESCE(
      REGEXP_EXTRACT(a.query_text, r'--\\s*Metabase::\\s*userID:\\s*(\\d+)'),
      REGEXP_EXTRACT(a.query_text, r'/\\*\\s*Metabase\\s*userID:\\s*(\\d+)\\s*\\*/'),
      REGEXP_EXTRACT(a.query_text, r'--\\s*metabase_user_id\\s*=\\s*(\\d+)')
    ) AS metabase_user_id,
    
    -- PRIMARY CLASSIFICATION
    CASE
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') THEN 'EXTERNAL'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'looker.*@.*\\.iam\\.gserviceaccount\\.com') THEN 'EXTERNAL'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer)') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gke-prod|gke-[a-z0-9]+-sumatra') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'\\d+-compute@developer\\.gserviceaccount\\.com') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(cdp|customer-data)') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(dataflow|etl)') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(eddmodel|ai-platform)') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'analytics-api-bigquery-access') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'^messaging@') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'shopify.*runner') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'ipaas-integration') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'growthbook') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'metric-layer') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'retool') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(nub-tenant|carrierstest|service-samoa)@') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'doit-cmp') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gcp-sa-bigquerydatatransfer') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gcp-sa-aiplatform') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'qa-automation-bigquery') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'noflake-') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'salesforce-bq-access') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'fivetran-production') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'data-ml-jobs') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'rudderstackbqwriter') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gcp-ship-vertex-ai') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'dev-testing@narvar-ml') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'narvar-ml-prod@appspot') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'vertex-pipeline-sa') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'churnzero-bq-access') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'promise-ai@') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'carriers-ml-service') THEN 'AUTOMATED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'@narvar\\.com$') THEN 'INTERNAL'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'metabase.*@.*\\.iam\\.gserviceaccount\\.com') THEN 'INTERNAL'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'n8n') THEN 'INTERNAL'
      WHEN REGEXP_CONTAINS(LOWER(a.user_agent), r'(tableau|powerbi)') THEN 'INTERNAL'
      ELSE 'UNCLASSIFIED'
    END AS consumer_category,
    
    -- SECONDARY CLASSIFICATION
    CASE
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') AND rs.retailer_moniker IS NOT NULL THEN 'MONITOR'
      WHEN a.project_id IN ('monitor-base-us-prod', 'monitor-base-us-qa', 'monitor-base-us-stg') THEN 'MONITOR_BASE'
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') AND rs.retailer_moniker IS NULL THEN 'MONITOR_UNMATCHED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'looker.*@.*\\.iam\\.gserviceaccount\\.com') THEN 'HUB'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer)') THEN 'AIRFLOW_COMPOSER'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gke-prod|gke-[a-z0-9]+-sumatra') THEN 'GKE_WORKLOAD'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'\\d+-compute@developer\\.gserviceaccount\\.com') THEN 'COMPUTE_ENGINE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(cdp|customer-data)') THEN 'CDP'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(dataflow|etl)') THEN 'ETL_DATAFLOW'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(eddmodel|ai-platform)') THEN 'ML_INFERENCE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'analytics-api-bigquery-access') THEN 'ANALYTICS_API'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'^messaging@') THEN 'MESSAGING'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'shopify.*runner') THEN 'SHOPIFY_INTEGRATION'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'ipaas-integration') THEN 'IPAAS_INTEGRATION'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'growthbook') THEN 'GROWTHBOOK'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'metric-layer') THEN 'METRIC_LAYER'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'retool') THEN 'RETOOL'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'doit-cmp') THEN 'DOIT_CMP'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gcp-sa-bigquerydatatransfer') THEN 'BQ_DATA_TRANSFER'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gcp-sa-aiplatform') THEN 'AI_PLATFORM'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(nub-tenant|carrierstest|service-samoa)@') THEN 'DOMAIN_SERVICE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'qa-automation-bigquery') THEN 'QA_AUTOMATION'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'noflake-') THEN 'NOFLAKE_RETIRED'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'salesforce-bq-access') THEN 'SALESFORCE_INTEGRATION'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'fivetran-production') THEN 'FIVETRAN_ETL'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'data-ml-jobs') THEN 'ML_JOBS'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'rudderstackbqwriter') THEN 'RUDDERSTACK_ETL'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gcp-ship-vertex-ai') THEN 'VERTEX_AI'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'dev-testing@narvar-ml') THEN 'ML_DEV_TESTING'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'narvar-ml-prod@appspot') THEN 'ML_APPSPOT'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'vertex-pipeline-sa') THEN 'VERTEX_PIPELINE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'churnzero-bq-access') THEN 'CHURNZERO_INTEGRATION'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'promise-ai@') THEN 'PROMISE_AI'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'carriers-ml-service') THEN 'CARRIERS_ML'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'iam\\.gserviceaccount\\.com$')
        AND NOT REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer|gke|compute|cdp|dataflow|etl|eddmodel|analytics-api|messaging|shopify|ipaas|growthbook|metric-layer|retool|doit-cmp|bigquerydatatransfer|aiplatform|looker|metabase|n8n|noflake|salesforce|fivetran|data-ml-jobs|rudderstack|vertex|dev-testing|appspot|churnzero|promise-ai|carriers-ml)')
        THEN 'SERVICE_ACCOUNT_OTHER'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'metabase.*@.*\\.iam\\.gserviceaccount\\.com') THEN 'METABASE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'n8n') THEN 'N8N_WORKFLOW'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'@narvar\\.com$') THEN 'ADHOC_USER'
      WHEN REGEXP_CONTAINS(LOWER(a.user_agent), r'(tableau|powerbi)') THEN 'OTHER_BI_TOOL'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'iam\\.gserviceaccount\\.com$') THEN 'INTERNAL_SERVICE_ACCOUNT'
      ELSE 'UNCLASSIFIED'
    END AS consumer_subcategory,
    
    ROUND(SAFE_DIVIDE(a.total_slot_ms, 3600000) * slot_cost_per_hour, 4) AS estimated_slot_cost_usd,
    
    CASE
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') OR REGEXP_CONTAINS(LOWER(a.principal_email), r'looker.*@.*\\.iam\\.gserviceaccount\\.com') THEN
        CASE WHEN a.execution_time_seconds > external_qos_threshold_seconds THEN 'QoS_VIOLATION' ELSE 'QoS_MET' END
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(metabase|@narvar\\.com$)') THEN
        CASE WHEN a.execution_time_seconds > internal_qos_threshold_seconds THEN 'QoS_VIOLATION' ELSE 'QoS_MET' END
      ELSE 'QoS_REQUIRES_SCHEDULE_DATA'
    END AS qos_status,
    
    CASE
      WHEN (STARTS_WITH(LOWER(a.project_id), 'monitor-') OR REGEXP_CONTAINS(LOWER(a.principal_email), r'looker.*@.*\\.iam\\.gserviceaccount\\.com'))
        AND a.execution_time_seconds > external_qos_threshold_seconds 
        THEN a.execution_time_seconds - external_qos_threshold_seconds
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(metabase|@narvar\\.com$)')
        AND a.execution_time_seconds > internal_qos_threshold_seconds 
        THEN a.execution_time_seconds - internal_qos_threshold_seconds
      ELSE 0
    END AS qos_violation_seconds,
    
    CASE
      WHEN STARTS_WITH(LOWER(a.project_id), 'monitor-') OR REGEXP_CONTAINS(LOWER(a.principal_email), r'looker.*@.*\\.iam\\.gserviceaccount\\.com') 
        THEN 1
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer|gke|compute|cdp|dataflow|etl|eddmodel|analytics-api|messaging|shopify|ipaas|growthbook|metric-layer|retool)')
        THEN 2
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(metabase|@narvar\\.com$|n8n)')
        THEN 3
      ELSE 4
    END AS priority_level
    
  FROM audit_deduplicated a
  LEFT JOIN retailer_selected rs USING (job_id, project_id)
)

SELECT
  CURRENT_DATE() AS classification_date,
  start_date AS analysis_start_date,
  end_date AS analysis_end_date,
  analysis_period_label,
  classification_version,
  
  job_id,
  project_id,
  principal_email,
  location,
  
  consumer_category,
  consumer_subcategory,
  priority_level,
  
  retailer_moniker,
  metabase_user_id,
  
  job_type,
  start_time,
  end_time,
  execution_time_seconds,
  ROUND(execution_time_seconds / 60.0, 2) AS execution_time_minutes,
  
  total_slot_ms,
  approximate_slot_count,
  ROUND(total_slot_ms / 3600000, 2) AS slot_hours,
  total_billed_bytes,
  ROUND(total_billed_bytes / POW(1024, 3), 2) AS total_billed_gb,
  estimated_slot_cost_usd,
  
  qos_status,
  qos_violation_seconds,
  CASE 
    WHEN qos_status = 'QoS_VIOLATION' THEN TRUE
    WHEN qos_status = 'QoS_MET' THEN FALSE
    ELSE NULL
  END AS is_qos_violation,
  
  reservation_name,
  user_agent,
  SUBSTR(query_text, 1, 500) AS query_text_sample

FROM traffic_classified;
"""


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def get_periods_to_run(mode: str) -> List[Dict]:
    """Filter periods based on execution mode."""
    periods = sorted([p for p in PERIODS if not p.get('skip', False)], 
                     key=lambda x: x['priority'])
    
    if mode == 'peak-only':
        return [p for p in periods if p['type'] == 'peak']
    elif mode == 'non-peak-only':
        return [p for p in periods if p['type'] == 'non_peak']
    elif mode == 'test':
        return periods[:1]  # Just first period
    else:  # mode == 'all'
        return periods


def create_bigquery_client() -> bigquery.Client:
    """Initialize BigQuery client."""
    try:
        client = bigquery.Client(project=PROJECT_ID)
        print(f"✅ Connected to BigQuery project: {PROJECT_ID}")
        return client
    except Exception as e:
        print(f"❌ Failed to initialize BigQuery client: {e}")
        sys.exit(1)


def run_classification(client: bigquery.Client, period: Dict, dry_run: bool = False) -> Dict:
    """Execute classification query for a single period."""
    
    period_label = period['label']
    start_date = period['start_date']
    end_date = period['end_date']
    description = period['description']
    
    print(f"\n{'='*80}")
    print(f"🔄 Processing: {period_label}")
    print(f"   Description: {description}")
    print(f"   Period: {start_date} to {end_date}")
    print(f"   Type: {period['type'].upper()}")
    print(f"{'='*80}")
    
    # Generate SQL from template
    sql = SQL_TEMPLATE.format(
        period_label=period_label,
        start_date=start_date,
        end_date=end_date,
        classification_version=CLASSIFICATION_VERSION,
        project_id=PROJECT_ID,
        dataset_id=DATASET_ID,
        table_id=TABLE_ID,
        timestamp=datetime.now().isoformat()
    )
    
    # Configure job
    job_config = bigquery.QueryJobConfig()
    if dry_run:
        job_config.dry_run = True
        job_config.use_query_cache = False
    
    try:
        # Execute query
        start_time = time.time()
        query_job = client.query(sql, job_config=job_config)
        
        if dry_run:
            print(f"   💰 Estimated bytes processed: {query_job.total_bytes_processed:,}")
            print(f"   💰 Estimated cost: ${query_job.total_bytes_processed / 1e12 * 5:.2f}")
            return {
                'status': 'dry_run',
                'bytes_processed': query_job.total_bytes_processed,
                'period_label': period_label
            }
        
        # Wait for completion
        print(f"   ⏳ Query job started: {query_job.job_id}")
        print(f"   ⏳ Waiting for completion...", flush=True)
        
        result = query_job.result()  # Wait for job to complete
        
        elapsed_time = time.time() - start_time
        
        print(f"   ✅ Completed in {elapsed_time/60:.1f} minutes")
        print(f"   📊 Bytes processed: {query_job.total_bytes_processed / 1e9:.2f} GB")
        print(f"   📊 Slot milliseconds: {query_job.slot_millis:,}")
        
        # Validate results
        validation_result = validate_period(client, period_label)
        
        return {
            'status': 'success',
            'period_label': period_label,
            'runtime_minutes': elapsed_time / 60,
            'bytes_processed': query_job.total_bytes_processed,
            'slot_ms': query_job.slot_millis,
            'validation': validation_result
        }
        
    except GoogleCloudError as e:
        print(f"   ❌ Query failed: {e}")
        return {
            'status': 'error',
            'period_label': period_label,
            'error': str(e)
        }
    except Exception as e:
        print(f"   ❌ Unexpected error: {e}")
        return {
            'status': 'error',
            'period_label': period_label,
            'error': str(e)
        }


def validate_period(client: bigquery.Client, period_label: str) -> Dict:
    """Validate classification results for a period."""
    
    validation_sql = f"""
    SELECT
      COUNT(*) AS total_jobs,
      COUNTIF(consumer_category = 'UNCLASSIFIED') AS unclassified_jobs,
      ROUND(COUNTIF(consumer_category = 'UNCLASSIFIED') / COUNT(*) * 100, 2) AS unclassified_pct,
      COUNT(DISTINCT consumer_category) AS unique_categories,
      COUNT(DISTINCT consumer_subcategory) AS unique_subcategories,
      ROUND(SUM(slot_hours), 2) AS total_slot_hours,
      ROUND(SUM(estimated_slot_cost_usd), 2) AS total_cost_usd,
      COUNT(DISTINCT retailer_moniker) AS unique_retailers
    FROM `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}`
    WHERE analysis_period_label = '{period_label}'
      AND classification_date = CURRENT_DATE();
    """
    
    try:
        result = client.query(validation_sql).result()
        row = next(result)
        
        validation = {
            'total_jobs': row['total_jobs'],
            'unclassified_pct': row['unclassified_pct'],
            'unique_categories': row['unique_categories'],
            'unique_subcategories': row['unique_subcategories'],
            'total_slot_hours': row['total_slot_hours'],
            'total_cost_usd': row['total_cost_usd'],
            'unique_retailers': row['unique_retailers']
        }
        
        print(f"\n   📊 Validation Results:")
        print(f"      Jobs classified: {validation['total_jobs']:,}")
        print(f"      Unclassified: {validation['unclassified_pct']:.2f}%")
        print(f"      Slot hours: {validation['total_slot_hours']:,.0f}")
        print(f"      Estimated cost: ${validation['total_cost_usd']:,.0f}")
        print(f"      Unique retailers: {validation['unique_retailers']}")
        
        # Check quality
        if validation['unclassified_pct'] > 10:
            print(f"      ⚠️  WARNING: High unclassified rate ({validation['unclassified_pct']:.1f}%)")
        elif validation['unclassified_pct'] > 5:
            print(f"      ⚠️  Acceptable unclassified rate ({validation['unclassified_pct']:.1f}%)")
        else:
            print(f"      ✅ Excellent classification rate!")
        
        return validation
        
    except Exception as e:
        print(f"      ⚠️  Validation failed: {e}")
        return {'error': str(e)}


def print_summary(results: List[Dict]):
    """Print summary of all classification runs."""
    
    print(f"\n\n{'='*80}")
    print("📊 CLASSIFICATION RUN SUMMARY")
    print(f"{'='*80}\n")
    
    successful = [r for r in results if r['status'] == 'success']
    failed = [r for r in results if r['status'] == 'error']
    
    if successful:
        print(f"✅ Successful runs: {len(successful)}")
        print(f"\n{'Period':<30} {'Jobs':<12} {'Unclass %':<12} {'Slot Hours':<15} {'Cost':<12} {'Runtime'}")
        print(f"{'-'*100}")
        
        total_jobs = 0
        total_cost = 0
        total_runtime = 0
        
        for r in successful:
            val = r.get('validation', {})
            jobs = val.get('total_jobs', 0)
            unclass_pct = val.get('unclassified_pct', 0)
            slot_hours = val.get('total_slot_hours', 0)
            cost = val.get('total_cost_usd', 0)
            runtime = r.get('runtime_minutes', 0)
            
            total_jobs += jobs
            total_cost += cost
            total_runtime += runtime
            
            print(f"{r['period_label']:<30} {jobs:>11,} {unclass_pct:>10.1f}% {slot_hours:>14,.0f} ${cost:>10,.0f} {runtime:>7.1f} min")
        
        print(f"{'-'*100}")
        print(f"{'TOTAL':<30} {total_jobs:>11,} {'':>12} {'':>15} ${total_cost:>10,.0f} {total_runtime:>7.1f} min")
    
    if failed:
        print(f"\n❌ Failed runs: {len(failed)}")
        for r in failed:
            print(f"   {r['period_label']}: {r.get('error', 'Unknown error')}")
    
    print(f"\n{'='*80}\n")


# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='Run BigQuery traffic classification for multiple periods')
    parser.add_argument('--mode', 
                        choices=['all', 'peak-only', 'non-peak-only', 'test'],
                        default='all',
                        help='Execution mode: all periods, peaks only, non-peaks only, or test (1 period)')
    parser.add_argument('--dry-run', 
                        action='store_true',
                        help='Estimate cost without executing')
    
    args = parser.parse_args()
    
    print(f"\n{'='*80}")
    print(f"🚀 BigQuery Traffic Classification - Multi-Period Automation")
    print(f"{'='*80}")
    print(f"Mode: {args.mode}")
    print(f"Dry run: {args.dry_run}")
    print(f"Target table: {PROJECT_ID}.{DATASET_ID}.{TABLE_ID}")
    print(f"Classification version: {CLASSIFICATION_VERSION}")
    print(f"{'='*80}\n")
    
    # Get periods to run
    periods_to_run = get_periods_to_run(args.mode)
    
    if not periods_to_run:
        print("⚠️  No periods to run (all marked as skip=True)")
        return
    
    print(f"📅 Periods to classify: {len(periods_to_run)}")
    for i, p in enumerate(periods_to_run, 1):
        print(f"   {i}. {p['label']:<30} ({p['start_date']} to {p['end_date']}) - {p['description']}")
    
    if args.dry_run:
        print(f"\n💰 Running in DRY-RUN mode (cost estimation only)")
    
    # Confirm execution
    if not args.dry_run and args.mode != 'test':
        response = input(f"\n⚠️  Proceed with classification? This will take ~{len(periods_to_run) * 15} minutes. [y/N]: ")
        if response.lower() != 'y':
            print("Cancelled by user.")
            return
    
    # Initialize BigQuery client
    client = create_bigquery_client()
    
    # Run classifications
    results = []
    for i, period in enumerate(periods_to_run, 1):
        print(f"\n\n{'#'*80}")
        print(f"# RUN {i}/{len(periods_to_run)}")
        print(f"{'#'*80}")
        
        result = run_classification(client, period, dry_run=args.dry_run)
        results.append(result)
        
        if result['status'] == 'error' and not args.dry_run:
            response = input(f"\n⚠️  Classification failed. Continue with remaining periods? [y/N]: ")
            if response.lower() != 'y':
                break
    
    # Print summary
    if not args.dry_run:
        print_summary(results)
        
        # Provide next steps
        print("\n🎯 Next Steps:")
        print("   1. Review validation results above")
        print("   2. Check for any periods with >5% unclassified")
        print("   3. If quality is good, proceed to Phase 2 analysis")
        print(f"   4. Query the table: `{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}`")
    else:
        print("\n💰 Dry run summary:")
        total_bytes = sum(r.get('bytes_processed', 0) for r in results)
        print(f"   Total bytes to process: {total_bytes / 1e9:.2f} GB")
        print(f"   Estimated cost: ${total_bytes / 1e12 * 5:.2f}")


if __name__ == "__main__":
    main()

