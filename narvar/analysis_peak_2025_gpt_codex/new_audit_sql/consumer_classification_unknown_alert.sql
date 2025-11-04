-- Alerting slice: highlight principals still classified as UNKNOWN/UNMAPPED
-- after applying manual overrides. Default lookback = 7 days.

DECLARE interval_in_days INT64 DEFAULT 7;

WITH base_jobs AS (
  SELECT
    protopayload_auditlog.authenticationInfo.principalEmail AS principal_email,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS billing_project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.projectId AS job_project_id,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.location AS job_location,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.eventName AS event_name,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs AS total_slot_ms,
    protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes AS total_billed_bytes,
    timestamp
  FROM
    `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
  WHERE
    timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL interval_in_days DAY)
    AND protopayload_auditlog.authenticationInfo.principalEmail IS NOT NULL
    AND protopayload_auditlog.authenticationInfo.principalEmail != ""
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobName.jobId IS NOT NULL
    AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.dryRun IS NULL
),
aggregated AS (
  SELECT
    principal_email,
    billing_project_id,
    job_project_id,
    ANY_VALUE(job_location) AS job_location,
    ARRAY_AGG(DISTINCT event_name IGNORE NULLS ORDER BY event_name) AS event_types,
    COUNT(*) AS job_events,
    SUM(COALESCE(total_slot_ms, 0)) AS total_slot_ms,
    SUM(COALESCE(total_billed_bytes, 0)) AS total_billed_bytes,
    MIN(timestamp) AS first_seen_ts,
    MAX(timestamp) AS last_seen_ts
  FROM
    base_jobs
  GROUP BY
    principal_email,
    billing_project_id,
    job_project_id
),
retailer_hints AS (
  SELECT DISTINCT
    retailer AS retailer_moniker,
    LOWER(REGEXP_REPLACE(retailer, r'[^a-z0-9]', '')) AS retailer_token
  FROM
    `narvar-data-lake.reporting.manual_retailer_categories`
  WHERE
    retailer IS NOT NULL
    AND LENGTH(REGEXP_REPLACE(retailer, r'[^a-z0-9]', '')) >= 3
),
retailer_matches AS (
  SELECT
    a.principal_email,
    a.billing_project_id,
    a.job_project_id,
    h.retailer_moniker,
    ROW_NUMBER() OVER (
      PARTITION BY a.principal_email, a.billing_project_id, a.job_project_id
      ORDER BY LENGTH(h.retailer_token) DESC
    ) AS rnk
  FROM
    aggregated AS a
  JOIN
    retailer_hints AS h
  ON
    REGEXP_CONTAINS(
      LOWER(a.principal_email),
      CONCAT('(^|[._-])', h.retailer_token, '([._-]|@|$)')
    )
),
retailer_selected AS (
  SELECT
    principal_email,
    billing_project_id,
    job_project_id,
    retailer_moniker
  FROM
    retailer_matches
  WHERE
    rnk = 1
),
overrides AS (
  SELECT
    principal_email,
    classification_type,
    classification_subtype,
    retailer_moniker,
    source_confidence,
    notes
  FROM
    `narvar-data-lake.analytics.consumer_classification_overrides`
),
heuristics AS (
  SELECT
    a.principal_email,
    a.billing_project_id,
    a.job_project_id,
    a.job_location,
    a.event_types,
    a.job_events,
    a.total_slot_ms,
    a.total_billed_bytes,
    a.first_seen_ts,
    a.last_seen_ts,
    CASE
      WHEN rs.retailer_moniker IS NOT NULL THEN 'RETAILER'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(looker|metabase|monitor|analytics-api|messaging|n8n)') THEN 'HUB_SERVICE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer|gke|compute@developer|iam\\.gserviceaccount\\.com)') THEN 'AUTOMATION'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'@narvar\\.com$') THEN 'INTERNAL_USER'
      ELSE 'UNKNOWN'
    END AS classification_type,
    CASE
      WHEN rs.retailer_moniker IS NOT NULL THEN rs.retailer_moniker
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'looker') THEN 'LOOKER'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'metabase') THEN 'METABASE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'monitor') THEN 'MONITOR'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'analytics-api') THEN 'ANALYTICS_API'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'messaging') THEN 'MESSAGING'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'n8n') THEN 'N8N'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'airflow') THEN 'AIRFLOW'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'composer') THEN 'COMPOSER'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'gke') THEN 'GKE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'compute@developer') THEN 'COMPUTE_ENGINE'
      WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'iam\\.gserviceaccount\\.com') THEN 'SERVICE_ACCOUNT'
      ELSE 'UNMAPPED'
    END AS classification_subtype,
    rs.retailer_moniker,
    IF(rs.retailer_moniker IS NOT NULL, 'HEURISTIC_RETAILER',
      CASE
        WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(looker|metabase|monitor|analytics-api|messaging|n8n)') THEN 'HEURISTIC_SERVICE'
        WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'(airflow|composer|gke|compute@developer|iam\\.gserviceaccount\\.com)') THEN 'HEURISTIC_AUTOMATION'
        WHEN REGEXP_CONTAINS(LOWER(a.principal_email), r'@narvar\\.com$') THEN 'HEURISTIC_EMPLOYEE'
        ELSE 'UNMAPPED'
      END
    ) AS source_confidence
  FROM
    aggregated AS a
  LEFT JOIN
    retailer_selected AS rs
  USING
    (principal_email, billing_project_id, job_project_id)
),
classified AS (
  SELECT
    h.principal_email,
    h.billing_project_id,
    h.job_project_id,
    h.job_location,
    h.event_types,
    h.job_events,
    h.total_slot_ms,
    h.total_billed_bytes,
    h.first_seen_ts,
    h.last_seen_ts,
    COALESCE(o.classification_type, h.classification_type) AS classification_type,
    COALESCE(o.classification_subtype, h.classification_subtype) AS classification_subtype,
    COALESCE(o.retailer_moniker, h.retailer_moniker) AS retailer_moniker,
    COALESCE(o.source_confidence, h.source_confidence) AS source_confidence,
    o.notes AS override_notes
  FROM
    heuristics AS h
  LEFT JOIN
    overrides AS o
  USING
    (principal_email)
)
SELECT
  principal_email,
  billing_project_id,
  job_project_id,
  job_location,
  event_types,
  job_events,
  total_slot_ms,
  SAFE_DIVIDE(total_slot_ms, NULLIF(job_events, 0)) AS avg_slot_ms,
  total_billed_bytes,
  SAFE_DIVIDE(total_billed_bytes, NULLIF(job_events, 0)) AS avg_billed_bytes,
  first_seen_ts,
  last_seen_ts,
  classification_type,
  classification_subtype,
  retailer_moniker,
  source_confidence,
  override_notes
FROM
  classified
WHERE
  classification_type = 'UNKNOWN'
  OR source_confidence = 'UNMAPPED'
ORDER BY
  job_events DESC
LIMIT
  50;
