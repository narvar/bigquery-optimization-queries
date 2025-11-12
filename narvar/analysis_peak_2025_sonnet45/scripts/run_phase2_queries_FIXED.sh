#!/bin/bash
# ============================================================================
# PHASE 2 QUERY EXECUTION SCRIPT - FIXED VERSION
# ============================================================================
# This version uses CREATE OR REPLACE TABLE in SQL instead of --destination_table
# which fixes the issue with DECLARE statements not working with destination tables.
#
# Usage:
#   chmod +x run_phase2_queries_FIXED.sh
#   ./run_phase2_queries_FIXED.sh
# ============================================================================

set -e
set -u

PROJECT="narvar-data-lake"
DATASET="query_opt"
LOCATION="us"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "PHASE 2 QUERY EXECUTION - FIXED VERSION"
echo "==========================================${NC}"
echo "Project: $PROJECT"
echo "Dataset: $DATASET"
echo ""

# ============================================================================
# QUERY 1: Capacity Stress Detection
# ============================================================================

echo -e "${BLUE}[1/4] Running Query 1: Capacity Stress Detection${NC}"
echo "Expected runtime: 15-30 minutes"
echo "Destination: ${PROJECT}.${DATASET}.phase2_stress_periods"
echo ""

START_TIME=$(date +%s)

bq query \
  --use_legacy_sql=false \
  --location="$LOCATION" \
  --format=none \
  < queries/phase2_historical/identify_capacity_stress_periods_table.sql

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo -e "${GREEN}✅ Query 1 completed in ${DURATION}s ($(($DURATION / 60)) min)${NC}"
echo ""

# ============================================================================
# QUERY 2: External Customer QoS
# ============================================================================

echo -e "${BLUE}[2/4] Running Query 2: External Customer QoS Analysis${NC}"
echo "Expected runtime: 5-10 minutes"
echo "Destination: ${PROJECT}.${DATASET}.phase2_external_qos"
echo ""

START_TIME=$(date +%s)

bq query \
  --use_legacy_sql=false \
  --location="$LOCATION" \
  --format=none \
  < queries/phase2_historical/external_qos_under_stress_table.sql

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo -e "${GREEN}✅ Query 2 completed in ${DURATION}s ($(($DURATION / 60)) min)${NC}"
echo ""

# ============================================================================
# QUERY 3: Monitor-Base Analysis
# ============================================================================

echo -e "${BLUE}[3/4] Running Query 3: Monitor-Base Infrastructure Analysis${NC}"
echo "Expected runtime: 10-15 minutes"
echo "Destination: ${PROJECT}.${DATASET}.phase2_monitor_base"
echo ""

START_TIME=$(date +%s)

bq query \
  --use_legacy_sql=false \
  --location="$LOCATION" \
  --format=none \
  < queries/phase2_historical/monitor_base_stress_analysis_table.sql

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo -e "${GREEN}✅ Query 3 completed in ${DURATION}s ($(($DURATION / 60)) min)${NC}"
echo ""

# ============================================================================
# QUERY 4: Peak vs Non-Peak Patterns
# ============================================================================

echo -e "${BLUE}[4/4] Running Query 4: Peak vs Non-Peak Patterns${NC}"
echo "Expected runtime: 2-5 minutes"
echo "Destination: ${PROJECT}.${DATASET}.phase2_peak_patterns"
echo ""

START_TIME=$(date +%s)

bq query \
  --use_legacy_sql=false \
  --location="$LOCATION" \
  --format=none \
  < queries/phase2_historical/peak_vs_nonpeak_analysis_v2_table.sql

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo -e "${GREEN}✅ Query 4 completed in ${DURATION}s ($(($DURATION / 60)) min)${NC}"
echo ""

# ============================================================================
# VERIFICATION
# ============================================================================

echo -e "${BLUE}=========================================="
echo "VERIFICATION"
echo "==========================================${NC}"
echo "Checking if all tables were created..."
echo ""

for table in phase2_stress_periods phase2_external_qos phase2_monitor_base phase2_peak_patterns; do
    if bq show "${PROJECT}:${DATASET}.${table}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ ${table}${NC}"
    else
        echo -e "${YELLOW}⚠️  ${table} - not found${NC}"
    fi
done

echo ""
echo -e "${GREEN}=========================================="
echo "PHASE 2 QUERIES COMPLETE!"
echo "==========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Open Jupyter notebook: notebooks/phase2_analysis.ipynb"
echo "2. Select kernel: jupyter (Python 3.11.3)"
echo "3. Run all cells to generate analysis and visualizations"
echo ""




