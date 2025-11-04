# BigQuery Consumers Description

**Purpose:** This document describes the scope and purpose of BigQuery consumers at Narvar, providing context for capacity planning, QoS monitoring, and cost optimization efforts.

**Last Updated:** 2025-01-XX

---

## Overview

Narvar's BigQuery infrastructure serves multiple consumer categories with varying QoS requirements and resource consumption patterns. Understanding these consumers is essential for:

- **Capacity Planning:** Predicting slot demand during peak periods (Nov 2025 - Jan 2026)
- **QoS Management:** Ensuring critical workloads meet performance SLAs
- **Cost Optimization:** Identifying high-impact optimization opportunities
- **Traffic Classification:** Categorizing queries for analysis and monitoring

---

## Table of Contents

### Consumer Categories
- [CRITICAL External Consumers](#1-critical-external-consumers)
  - [Monitor Projects](#monitor-projects)
  - [Hub Traffic (Looker)](#hub-traffic-looker)
- [CRITICAL Automated Processes](#2-critical-automated-processes)
  - [Sumatra](#sumatra)
  - [Airflow / Composer](#airflow--composer)
  - [EDD Model](#edd-model)
  - [Messaging Service](#messaging-service)
  - [Analytics API](#analytics-api)
  - [Dev/Testing](#devtesting)
  - [Noflake & TNT Model (Compute Engine)](#noflake--tnt-model-compute-engine)
- [INTERNAL Users](#3-internal-users)
  - [Metabase](#metabase)

### Additional Sections
- [Consumer Classification Framework](#consumer-classification-framework)
- [Resource Consumption Patterns](#resource-consumption-patterns)
- [Optimization Priorities](#optimization-priorities)
- [Monitoring & Alerts](#monitoring--alerts)
- [References](#references)
- [Notes](#notes)

---

## Consumer Categories

### 1. CRITICAL External Consumers

**QoS Requirement:** Query response time > 1 minute is harmful

#### Monitor Projects
- **Description:** Dedicated BigQuery projects (one per retailer/B2B customer) that provide shipment tracking and analytics capabilities
- **Service Accounts:** Pattern `monitor-{name}@monitor-{region}-{env}.iam.gserviceaccount.com`
- **Examples:**
  - `monitor-shipment-noflake@monitor-base-us-prod.iam.gserviceaccount.com`
  - `monitor-narvar-us-metabase@monitor-base-us-stg.iam.gserviceaccount.com`
- **Characteristics:**
  - External-facing (retailer/customer-facing)
  - Requires deterministic SLAs
  - Consider slot pre-allocation & high-priority reservations

#### Hub Traffic (Looker)
- **Description:** Business intelligence and analytics platform serving external stakeholders
- **Service Account:** `looker-prod@narvar-data-lake.iam.gserviceaccount.com`
- **Characteristics:**
  - External-facing dashboards and reports
  - Requires < 60 seconds query latency (target: < 30 seconds)
  - Significant query volume during business hours

---

### 2. CRITICAL Automated Processes

**QoS Requirement:** Must execute within scheduled time windows

These are service account-based workloads that run on automated schedules (Airflow, CDP, GKE, etc.). They are classified as CRITICAL because delays can impact downstream processes and scheduled workflows.

#### Key Automated Services

### Sumatra
- **Service Account:** `gke-prod-20-sumatra@prod-k8s20-6f31.iam.gserviceaccount.com`
- **Project:** `narvar-ml-prod`
- **Classification:** AUTOMATED_CRITICAL
- **Resource Usage:** Extremely high job volume (63% of all automated jobs), but minimal slot usage

**Core Purpose:**
Sumatra is a backend service used primarily for carrier moniker and service code prediction in logistics and shipment tracking workflows at Narvar. It acts as a validation, pre-processing, and post-processing layer for predicting carrier monikers and service codes when tracking numbers are ingested into the system.

**Key Functions:**

1. **Tracking Number Validation:**
   - Validates incoming tracking numbers to filter out junk or invalid entries, which helps maintain model accuracy.

2. **Feature Extraction & Sanitization:**
   - Extracts features from the tracking number and related shipment data (like origin/destination, retailer, etc.).
   - Sanitizes and prepares the payload for prediction.

3. **Model Inference Coordination:**
   - Forwards the processed data to the inference service (called **Ibiza**), which runs a machine learning model (XGBoost-based) to predict the correct carrier moniker or service code.

4. **Business Rule Enforcement:**
   - Checks if the model's top prediction is enabled for the retailer.
   - Applies probability thresholds and mapping rules to ensure only high-confidence, valid predictions are used.
   - Returns errors if predictions are below threshold or if configuration is missing.

5. **Error Handling & Monitoring:**
   - Implements robust logging (Noflake, Stackdriver/Cloud Logging).
   - Monitors health, latency, and functionality via Datadog dashboards and alerts.

**Example Use Cases:**
- **Blank or Invalid Carrier Monikers:** When a retailer submits an order with a blank, junk, or invalid carrier moniker, Sumatra predicts and fills in the correct value using recent tracking data and model inference.
- **Service Code Prediction:** For shipments missing service codes, Sumatra predicts and hydrates this information across the ecosystem.

**System Integration:**
- Works with **Atlas** (sends tracking events to Sumatra) and **Ibiza** (performs ML inference)
- Highly configurable per carrier and retailer
- Autoscaling and resource management to handle high throughput and maintain latency SLAs

**BigQuery Usage Characteristics:**
- **Job Volume:** 3.78M jobs (63% of all AUTOMATED_CRITICAL jobs)
- **Slot Usage:** 0.0007 slot-hours (extremely efficient)
- **Cost:** ~$0.00 (very low cost despite high volume)
- **Query Pattern:** Likely lightweight queries for health checks, monitoring, or small data lookups

**References:**
- [Carrier Moniker Classifier KT Doc](https://narvar.atlassian.net/wiki/search?text=sumatra)
- [TRD: Carrier Service Code Classification](https://narvar.atlassian.net/wiki/search?text=sumatra)
- [Sumatra Runbook](https://narvar.atlassian.net/wiki/search?text=sumatra)
- [Load Test Results 2025](https://narvar.atlassian.net/wiki/search?text=sumatra)

### Airflow / Composer
- **Service Account:** `airflow-bq-job-user-2@narvar-data-lake.iam.gserviceaccount.com`
- **Project:** `narvar-data-lake`
- **Classification:** AUTOMATED_CRITICAL
- **Resource Usage:** Highest slot consumer (69% of AUTOMATED_CRITICAL slot usage, 798 slot-hours)

**Description:** Airflow/Composer orchestrates scheduled data pipelines and ETL workflows.

**BigQuery Usage Characteristics:**
- **Job Volume:** 133K jobs
- **Slot Usage:** 798 slot-hours (69% of AUTOMATED_CRITICAL slots)
- **Cost:** ~$31.94 (highest slot-hour consumer)
- **Query Pattern:** Resource-intensive queries (0.006 slot-hours/job)
- **Optimization Priority:** #1 target - biggest resource consumer

### EDD Model
- **Service Account:** `eddmodel@narvar-data-lake.iam.gserviceaccount.com`
- **Project:** `narvar-data-lake`
- **Classification:** AUTOMATED_CRITICAL
- **Resource Usage:** High job volume (796K jobs, 13% of automated jobs), low slot usage

**Core Purpose:**
The EDD Model service account is used by Narvar's Data Engineering and Data Science teams for Estimated Delivery Date (EDD) modeling workflows. It handles access to EDD model artifacts, data files, and automated data pipeline processes for delivery date predictions.

**Key Functions:**

1. **Model Artifact Access:**
   - Grants read permissions to Google Cloud Storage (GCS) buckets, particularly `gs://narvar-data-lake/tnt/`
   - Accesses EDD model artifacts and data files for inference and processing

2. **Pipeline Automation:**
   - Used in automation scripts and configuration files for EDD model workflows
   - Handles authentication and access control for downstream data pipelines
   - Processes and generates EDD model artifacts (e.g., GO binaries)

3. **Data Processing:**
   - Enables access to model/data artifacts needed for EDD predictions
   - Supports data pipeline operations that consume and process EDD-related data

**System Integration:**
- Works with GCS buckets for model artifact storage (`gs://narvar-data-lake/tnt/`)
- Integrated with data engineering workflows and automation scripts
- Referenced in configuration files (e.g., `tnt.json`, `edd_api_service_account.json`)

**BigQuery Usage Characteristics:**
- **Job Volume:** 796K jobs (13% of AUTOMATED_CRITICAL)
- **Slot Usage:** 0.0433 slot-hours
- **Cost:** Very low
- **Query Pattern:** Efficient operations with minimal resource consumption per job

**Ownership & Contacts:**
- **Primary Owner:** Data Engineering team
- **Contacts:**
  - [Elliott Feng](https://narvar.atlassian.net/people/5c0eae378ce9b546efc4c247)
  - [Cezar Mihaila](https://narvar.atlassian.net/people/642b184f02931fca47bde073)
  - [Saurabh Shrivastava](https://narvar.atlassian.net/people/5ae22d2658742e214dd04bee)

**References:**
- [Steps for creating GO binary](https://narvar.atlassian.net/wiki/spaces/Promise1/pages/3154116727/Steps+for+creating+GO+binary)
- [List of Data Engineering Services, Infra, Projects](https://narvar.atlassian.net/wiki/spaces/DTPL/pages/2015920131/List+of+Data+Engineering+Services+Infra+Projects)

### Messaging Service
- **Service Account:** `messaging@narvar-data-lake.iam.gserviceaccount.com`
- **Project:** `narvar-data-lake`
- **Classification:** AUTOMATED_CRITICAL
- **Resource Usage:** Moderate job volume with higher slot usage

**Description:** Handles messaging and notification data operations.

**BigQuery Usage Characteristics:**
- **Job Volume:** 278K jobs
- **Slot Usage:** 82 slot-hours
- **Cost:** ~$3.29
- **Query Pattern:** Higher cost per job ratio compared to high-volume services

### Analytics API
- **Service Account:** `analytics-api-bigquery-access@narvar-data-lake.iam.gserviceaccount.com`
- **Project:** `narvar-data-lake`
- **Classification:** AUTOMATED_CRITICAL

**Description:** Provides programmatic access to analytics data via API.

**BigQuery Usage Characteristics:**
- **Job Volume:** 205K jobs
- **Slot Usage:** 22 slot-hours
- **Cost:** ~$0.86

### Dev/Testing
- **Service Account:** `dev-testing@narvar-ml-prod.iam.gserviceaccount.com`
- **Project:** `narvar-ml-prod`
- **Classification:** AUTOMATED_CRITICAL
- **Resource Usage:** Appears in both top 5 by jobs and slots

**Description:** Development and testing workloads.

**BigQuery Usage Characteristics:**
- **Job Volume:** 357K jobs
- **Slot Usage:** 118 slot-hours
- **Cost:** ~$4.73
- **Query Pattern:** Resource-intensive (handles both LOAD and QUERY operations)
- **Optimization Opportunity:** Review testing query patterns - could be optimized

### Noflake & TNT Model (Compute Engine)
- **Service Account:** `252778107735-compute@developer.gserviceaccount.com`
- **Projects:** `noflake-schema`, `tnt_model`
- **Classification:** AUTOMATED_CRITICAL
- **Resource Usage:** Varies by workload type (log ingestion pipelines vs. ML training/inference)

**Core Purpose:**
This is a Google Cloud Platform (GCP) Compute Engine default service account used by two critical Narvar systems:

1. **Noflake (`noflake-schema`):** Narvar's unified log ingestion and analytics platform that defines schemas for business and operational logs ingested from various Narvar services into BigQuery. It enables real-time and batch analytics, reporting, debugging, and alerting through a scalable, schema-driven pipeline.

2. **TNT Model (`tnt_model`):** Narvar's machine learning project for predicting **Time in Transit (TNT)**—the estimated shipping duration between origin and destination for various carriers and services. The models are integrated into Narvar's EDD (Estimated Delivery Date) APIs and services.

**Key Functions:**

1. **Noflake - Log Ingestion & Analytics:**
   - Dataflow jobs for ingesting, transforming, and writing log data into BigQuery
   - Schema management and pipeline orchestration
   - Batch processing tasks for log aggregation
   - Supports multiple ingestion methods (HTTP POST, stdout log scraping, direct BigQuery writes)
   - Critical for observability, business intelligence, and operational monitoring

2. **TNT Model - ML Pipeline Operations:**
   - Running ML pipelines (training, evaluation, batch inference) on GCP services like Vertex AI and Dataflow
   - Secure access to training data and feature stores
   - Storing model outputs and artifacts
   - Integration with BigQuery for data access and model deployment
   - Supports regional models (North America, EMEA) and carrier-specific models (UPS, FedEx, USPS, etc.)

**System Integration:**
- **Noflake:** Integrates with various Narvar services (frontend and backend) to ingest logs, routes data to BigQuery tables for downstream analysis
- **TNT Model:** Integrates with EDD APIs, feature stores, and BigQuery for model training data and deployment
- Both use GCP services including BigQuery, Dataflow, Pub/Sub, Vertex AI, and GCS
- Supports automation, scalability, and compliance for data and ML pipelines

**BigQuery Usage Characteristics:**
- **Workload Type:** Mixed (log ingestion writes, ML data reads, and batch processing)
- **Query Pattern:** Varies by use case:
  - Noflake: Primarily LOAD operations for log ingestion, plus QUERY operations for analytics pipelines
  - TNT Model: QUERY operations for feature extraction, training data access, and batch inference
- **Note:** This is a default Compute Engine service account. For production workloads, custom service accounts with least-privilege permissions are recommended.

**References:**

**Noflake:**
- [Noflake Engineering Design Doc](https://narvar.atlassian.net/wiki/spaces/DTPL/pages/339509249)
- [Noflake v2 Design](https://narvar.atlassian.net/wiki/spaces/DTPL/pages/2048098544)
- [How to integrate new events with Noflake](https://narvar.atlassian.net/wiki/spaces/DTPL/pages/2644541466)

**TNT Model:**
- [EDD API - Model Features Management](https://narvar.atlassian.net/wiki/spaces/EN/pages/4325924)
- [TNT Model Accuracy for Peak](https://narvar.atlassian.net/wiki/spaces/EN/pages/1941045387/Time+In+Transit+Model)

---

### 3. INTERNAL Users

**QoS Requirement:** Query response time > 5-10 minutes is harmful

#### Metabase
- **Service Account:** `metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com`
- **Project:** `narvar-data-lake`
- **Classification:** INTERNAL

**Description:** Self-service business intelligence platform for internal Narvar teams. Primarily used for ad-hoc analysis, reporting, and data exploration.

**BigQuery Usage Characteristics:**
- Variable query patterns (ad-hoc)
- Generally lower priority than external consumers
- Can be throttled during peak periods if needed

---

## Consumer Classification Framework

### Classification Types

The consumer classification framework maps BigQuery job principals to business-facing segments:

| Classification Type | Description | Examples |
|-------------------|-------------|----------|
| `RETAILER` | Monitor projects mapped to specific retailers | `monitor-{retailer}@monitor-*.iam.gserviceaccount.com` |
| `HUB_SERVICE` | External-facing analytics services | `looker-prod@narvar-data-lake.iam.gserviceaccount.com` |
| `AUTOMATION` | Automated workflows and scheduled processes | `gke-prod-20-sumatra@*.iam.gserviceaccount.com`, `airflow-bq-job-user-2@*.iam.gserviceaccount.com` |
| `INTERNAL_USER` | Internal analytics and ad-hoc queries | `metabase-prod-access@narvar-data-lake.iam.gserviceaccount.com` |
| `UNKNOWN` | Unclassified principals requiring manual review | Various |

### Classification Sources

1. **Heuristic Rules:** Pattern matching on service account names and email addresses
2. **Retailer Mapping:** Joins to `reporting.manual_retailer_categories` for retailer identification
3. **Manual Overrides:** Curated table `analytics.consumer_classification_overrides` maintained by Analytics Engineering

See `narvar/analysis_peak_2025_gpt_codex/new_audit_sql/consumer_classification_staging.sql` for the implementation.

---

## Resource Consumption Patterns

### Top Consumers Summary

**By Job Count (AUTOMATED_CRITICAL):**
1. **GKE Sumatra:** 3.78M jobs (63.07%) - Extremely low slot usage
2. **EDD Model:** 796K jobs (76.34%)
3. **Dev-Testing:** 357K jobs (82.29%)
4. **Messaging:** 278K jobs (86.93%)
5. **Analytics API:** 205K jobs (90.35%)

**By Slot Usage (AUTOMATED_CRITICAL):**
1. **Airflow:** 798 slot-hours (69.23%) - **CRITICAL optimization target**
2. **Monitor Shipment NoFlake:** 228 slot-hours (78.44%)
3. **Monitor Narvar US Metabase:** 136 slot-hours (86.42%)
4. **Dev-Testing:** 118 slot-hours (91.97%)
5. **Messaging:** 82 slot-hours (94.93%)

### Key Insights

- **Highly Skewed Distribution:** Top 5 service accounts handle 90% of AUTOMATED_CRITICAL jobs
- **Efficient High-Volume Operations:** Most high-volume services (Sumatra, EDD Model) are very efficient with low slot usage
- **Resource-Intensive Queries:** Airflow service account dominates slot usage (69%) despite lower job volume
- **Concentration Risk:** Heavy reliance on a few service accounts creates concentration risk

---

## Optimization Priorities

### Priority #1: Airflow Service Account
- **Impact:** 69% of AUTOMATED_CRITICAL slot usage (798 slot-hours)
- **Actions:**
  - Review Airflow workflows for optimization opportunities
  - Consider query batching, caching, or data pipeline optimization
  - Analyze query patterns to identify bottlenecks

### Priority #2: Monitor Projects
- **Impact:** High resource intensity per job (0.073 slot-hours/job for Monitor Shipment)
- **Actions:**
  - Investigate query complexity
  - Review data access patterns
  - Consider query optimization or materialized views

### Priority #3: GKE Sumatra
- **Impact:** 3.78M jobs (63% of job count) but minimal resource usage
- **Actions:**
  - Investigate if job volume can be reduced through batching
  - Determine if all queries are necessary
  - Potential for reducing job count without impact on slot resources

### Priority #4: Dev-Testing & Messaging
- **Impact:** Moderate optimization opportunities
- **Actions:**
  - Review testing query patterns
  - Optimize messaging data operations
  - Consider reducing frequency where appropriate

---

## Monitoring & Alerts

### Recommended Monitoring

1. **Slot Usage by Consumer:** Track slot consumption trends by consumer category
2. **QoS Metrics:** Monitor query latency by consumer (P50, P95, P99)
3. **Job Volume Trends:** Track job count growth by consumer
4. **Cost Attribution:** Monitor cost per consumer for budget allocation
5. **Anomaly Detection:** Alert on unusual spikes in top service accounts

### Alert Thresholds

- **Airflow:** Alert if slot usage exceeds baseline by 20%
- **Monitor Projects:** Alert if query latency exceeds 60 seconds
- **Sumatra:** Alert if job volume spikes unexpectedly (may indicate issues)
- **Hub/Looker:** Alert if query latency exceeds 30 seconds

---

## References

### Internal Documentation
- `narvar/analysis_peak_2025_composer/README.md` - Peak period analysis overview
- `narvar/analysis_peak_2025_gpt_codex/phase2_consumer_classification_plan.md` - Classification framework design
- `narvar/analysis_peak_2025_composer/AUTOMATED_CRITICAL_DRILLDOWN.md` - Detailed automated consumer analysis
- `narvar/analysis_peak_2025_gpt_codex/new_audit_sql/consumer_classification_staging.sql` - Classification query implementation

### External Links

**Sumatra:**
- [Carrier Moniker Classifier KT Doc](https://narvar.atlassian.net/wiki/spaces/CarriersPlatform/pages/4083384378/Carrier+Moniker+Classifier+KT+Doc)
- [TRD: Carrier Service Code Classification](https://narvar.atlassian.net/wiki/spaces/CarriersPlatform/pages/3942318081/TRD+Carrier+Service+Code+Classification)
- [Sumatra Runbook](https://narvar.atlassian.net/wiki/spaces/CarriersPlatform/pages/4211245086/Sumatra+Runbook)
- [Load Test Results 2025](https://narvar.atlassian.net/wiki/spaces/CarriersPlatform/pages/4251582601/Load+Test+Results+2025)

**EDD Model:**
- [Steps for creating GO binary](https://narvar.atlassian.net/wiki/spaces/Promise1/pages/3154116727/Steps+for+creating+GO+binary)
- [List of Data Engineering Services, Infra, Projects](https://narvar.atlassian.net/wiki/spaces/DTPL/pages/2015920131/List+of+Data+Engineering+Services+Infra+Projects)

**Noflake & TNT Model:**
- [Noflake Engineering Design Doc](https://narvar.atlassian.net/wiki/spaces/DTPL/pages/339509249)
- [Noflake v2 Design](https://narvar.atlassian.net/wiki/spaces/DTPL/pages/2048098544)
- [How to integrate new events with Noflake](https://narvar.atlassian.net/wiki/spaces/DTPL/pages/2644541466)
- [EDD API - Model Features Management](https://narvar.atlassian.net/wiki/spaces/EN/pages/4325924)
- [TNT Model Accuracy for Peak](https://narvar.atlassian.net/wiki/spaces/EN/pages/1941045387/Time+In+Transit+Model)

---

## Notes

- All statistics and metrics are based on analysis of audit logs from `narvar-data-lake.doitintl_cmp_bq.cloudaudit_googleapis_com_data_access`
- Cost calculations use slot-hours × $0.04/hour (pay-as-you-go rate) for analysis purposes
- Actual total monthly BigQuery cost: ~$50,000 USD
- Classification heuristics may require manual review and overrides for edge cases
- This document should be updated as new consumers are identified or existing consumers change their usage patterns

