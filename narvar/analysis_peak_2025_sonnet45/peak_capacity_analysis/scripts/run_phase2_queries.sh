#!/bin/bash
# ============================================================================
# PHASE 2 QUERY EXECUTION SCRIPT
# ============================================================================
# Purpose: Execute all 4 Phase 2 historical analysis queries and save results
#          to BigQuery destination tables for notebook analysis
#
# Prerequisites:
# - gcloud authenticated with narvar-data-lake project access
# - bq CLI installed
# - Phase 1 traffic_classification table exists and populated
#
# Estimated runtime: 32-60 minutes total
# Estimated cost: ~$0.13-$0.35 USD (~26-70GB scanned)
#
# Usage:
#   chmod +x run_phase2_queries.sh
#   ./run_phase2_queries.sh
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# Configuration
PROJECT="narvar-data-lake"
DATASET="query_opt"
LOCATION="us"

# Color output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="phase2_execution_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# ============================================================================
# QUERY 1: IDENTIFY CAPACITY STRESS PERIODS
# ============================================================================
# Detects INFO/WARNING/CRITICAL stress states using production monitoring
# thresholds. 10-minute window analysis with concurrent job calculations.
# Most expensive query (15-30 minutes)
# ============================================================================

run_query_1() {
    log "=========================================="
    log "QUERY 1: Capacity Stress Period Detection"
    log "=========================================="
    log "Destination: ${PROJECT}.${DATASET}.phase2_stress_periods"
    log "Estimated: 10-30GB, 15-30 minutes"
    
    local QUERY_FILE="queries/phase2_historical/identify_capacity_stress_periods.sql"
    local DEST_TABLE="${PROJECT}:${DATASET}.phase2_stress_periods"
    
    if [ ! -f "$QUERY_FILE" ]; then
        error "Query file not found: $QUERY_FILE"
        return 1
    fi
    
    log "Starting execution..."
    local START_TIME=$(date +%s)
    
    bq query \
        --use_legacy_sql=false \
        --destination_table="$DEST_TABLE" \
        --replace \
        --location="$LOCATION" \
        --max_rows=0 \
        --format=none \
        < "$QUERY_FILE" 2>&1 | tee -a "$LOG_FILE"
    
    local EXIT_CODE=$?
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    
    if [ $EXIT_CODE -eq 0 ]; then
        success "Query 1 completed in ${DURATION}s"
        
        # Get table stats
        log "Fetching table statistics..."
        bq show --format=prettyjson "${PROJECT}:${DATASET}.phase2_stress_periods" \
            | grep -E "(numRows|numBytes)" || true
    else
        error "Query 1 failed with exit code: $EXIT_CODE"
        return 1
    fi
}

# ============================================================================
# QUERY 2: EXTERNAL CUSTOMER QOS UNDER STRESS
# ============================================================================
# Analyzes how EXTERNAL customer-facing QoS (MONITOR, HUB) degrades during
# capacity stress. Excludes MONITOR_BASE (infrastructure).
# Medium cost (5-10 minutes)
# ============================================================================

run_query_2() {
    log "=========================================="
    log "QUERY 2: External Customer QoS Analysis"
    log "=========================================="
    log "Destination: ${PROJECT}.${DATASET}.phase2_external_qos"
    log "Estimated: 5-15GB, 5-10 minutes"
    
    local QUERY_FILE="queries/phase2_historical/external_qos_under_stress.sql"
    local DEST_TABLE="${PROJECT}:${DATASET}.phase2_external_qos"
    
    if [ ! -f "$QUERY_FILE" ]; then
        error "Query file not found: $QUERY_FILE"
        return 1
    fi
    
    log "Starting execution..."
    local START_TIME=$(date +%s)
    
    bq query \
        --use_legacy_sql=false \
        --destination_table="$DEST_TABLE" \
        --replace \
        --location="$LOCATION" \
        --max_rows=0 \
        --format=none \
        < "$QUERY_FILE" 2>&1 | tee -a "$LOG_FILE"
    
    local EXIT_CODE=$?
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    
    if [ $EXIT_CODE -eq 0 ]; then
        success "Query 2 completed in ${DURATION}s"
        
        # Get table stats
        log "Fetching table statistics..."
        bq show --format=prettyjson "${PROJECT}:${DATASET}.phase2_external_qos" \
            | grep -E "(numRows|numBytes)" || true
    else
        error "Query 2 failed with exit code: $EXIT_CODE"
        return 1
    fi
}

# ============================================================================
# QUERY 3: MONITOR_BASE STRESS ANALYSIS
# ============================================================================
# Two-part analysis: (A) monitor-base QoS tracking (30-min SLA),
# (B) Causation test - does monitor-base cause customer stress?
# Medium cost (10-15 minutes)
# ============================================================================

run_query_3() {
    log "=========================================="
    log "QUERY 3: Monitor-Base Infrastructure Analysis"
    log "=========================================="
    log "Destination: ${PROJECT}.${DATASET}.phase2_monitor_base"
    log "Estimated: 10-20GB, 10-15 minutes"
    
    local QUERY_FILE="queries/phase2_historical/monitor_base_stress_analysis.sql"
    local DEST_TABLE="${PROJECT}:${DATASET}.phase2_monitor_base"
    
    if [ ! -f "$QUERY_FILE" ]; then
        error "Query file not found: $QUERY_FILE"
        return 1
    fi
    
    log "Starting execution..."
    local START_TIME=$(date +%s)
    
    bq query \
        --use_legacy_sql=false \
        --destination_table="$DEST_TABLE" \
        --replace \
        --location="$LOCATION" \
        --max_rows=0 \
        --format=none \
        < "$QUERY_FILE" 2>&1 | tee -a "$LOG_FILE"
    
    local EXIT_CODE=$?
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    
    if [ $EXIT_CODE -eq 0 ]; then
        success "Query 3 completed in ${DURATION}s"
        
        # Get table stats
        log "Fetching table statistics..."
        bq show --format=prettyjson "${PROJECT}:${DATASET}.phase2_monitor_base" \
            | grep -E "(numRows|numBytes)" || true
    else
        error "Query 3 failed with exit code: $EXIT_CODE"
        return 1
    fi
}

# ============================================================================
# QUERY 4: PEAK VS NON-PEAK ANALYSIS (5 OUTPUTS)
# ============================================================================
# Overall traffic patterns analysis with 5 output sections:
#   1. Peak vs Non-Peak Summary by Category
#   2. Peak Multipliers
#   3. Hour-of-Day Patterns
#   4. Day-of-Week Patterns
#   5. Year-over-Year Growth
# Fast query (2-5 minutes) - uses pre-classified table
# ============================================================================

run_query_4() {
    log "=========================================="
    log "QUERY 4: Peak vs Non-Peak Patterns (5 outputs)"
    log "=========================================="
    log "Note: This query has 5 SELECT statements - will create 5 result sets"
    warning "bq CLI will only capture the last SELECT. Consider running in BigQuery Console."
    log "Destination: ${PROJECT}.${DATASET}.phase2_peak_patterns"
    log "Estimated: 1-5GB, 2-5 minutes"
    
    local QUERY_FILE="queries/phase2_historical/peak_vs_nonpeak_analysis_v2.sql"
    local DEST_TABLE="${PROJECT}:${DATASET}.phase2_peak_patterns"
    
    if [ ! -f "$QUERY_FILE" ]; then
        error "Query file not found: $QUERY_FILE"
        return 1
    fi
    
    warning "Query 4 has multiple SELECT statements. Only last output will be saved to table."
    warning "Recommendation: Run this query in BigQuery Console to capture all 5 outputs."
    read -p "Continue with bq CLI (y/n)? " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warning "Skipping Query 4. Please run manually in BigQuery Console."
        return 0
    fi
    
    log "Starting execution..."
    local START_TIME=$(date +%s)
    
    bq query \
        --use_legacy_sql=false \
        --destination_table="$DEST_TABLE" \
        --replace \
        --location="$LOCATION" \
        --max_rows=0 \
        --format=none \
        < "$QUERY_FILE" 2>&1 | tee -a "$LOG_FILE"
    
    local EXIT_CODE=$?
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    
    if [ $EXIT_CODE -eq 0 ]; then
        success "Query 4 completed in ${DURATION}s"
        
        # Get table stats
        log "Fetching table statistics..."
        bq show --format=prettyjson "${PROJECT}:${DATASET}.phase2_peak_patterns" \
            | grep -E "(numRows|numBytes)" || true
    else
        error "Query 4 failed with exit code: $EXIT_CODE"
        return 1
    fi
}

# ============================================================================
# DRY-RUN VALIDATION (Optional)
# ============================================================================

validate_queries() {
    log "=========================================="
    log "DRY-RUN VALIDATION"
    log "=========================================="
    log "Validating all queries and estimating costs..."
    
    local TOTAL_BYTES=0
    
    for i in 1 2 3 4; do
        case $i in
            1) QUERY_FILE="queries/phase2_historical/identify_capacity_stress_periods.sql" ;;
            2) QUERY_FILE="queries/phase2_historical/external_qos_under_stress.sql" ;;
            3) QUERY_FILE="queries/phase2_historical/monitor_base_stress_analysis.sql" ;;
            4) QUERY_FILE="queries/phase2_historical/peak_vs_nonpeak_analysis_v2.sql" ;;
        esac
        
        if [ -f "$QUERY_FILE" ]; then
            log "Validating Query $i..."
            bq query --dry_run --use_legacy_sql=false < "$QUERY_FILE" 2>&1 | grep -i "bytes processed" || warning "Could not estimate Query $i"
        else
            error "Query file not found: $QUERY_FILE"
        fi
    done
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log "=========================================="
    log "PHASE 2 QUERY EXECUTION - START"
    log "=========================================="
    log "Project: $PROJECT"
    log "Dataset: $DATASET"
    log "Log file: $LOG_FILE"
    log ""
    
    # Optional: Validate queries first
    read -p "Run dry-run validation first? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        validate_queries
        echo
        read -p "Proceed with execution? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            warning "Execution cancelled by user."
            exit 0
        fi
    fi
    
    local TOTAL_START=$(date +%s)
    local FAILED_QUERIES=0
    
    # Execute queries sequentially
    run_query_1 || ((FAILED_QUERIES++))
    echo
    
    run_query_2 || ((FAILED_QUERIES++))
    echo
    
    run_query_3 || ((FAILED_QUERIES++))
    echo
    
    run_query_4 || ((FAILED_QUERIES++))
    echo
    
    local TOTAL_END=$(date +%s)
    local TOTAL_DURATION=$((TOTAL_END - TOTAL_START))
    local TOTAL_MINUTES=$((TOTAL_DURATION / 60))
    
    log "=========================================="
    log "PHASE 2 QUERY EXECUTION - COMPLETE"
    log "=========================================="
    log "Total runtime: ${TOTAL_MINUTES} minutes (${TOTAL_DURATION}s)"
    
    if [ $FAILED_QUERIES -eq 0 ]; then
        success "All queries completed successfully! ✅"
        log ""
        log "Next steps:"
        log "1. Open Jupyter notebook: notebooks/phase2_analysis.ipynb"
        log "2. Run notebook cells to import results and generate visualizations"
        log "3. Review findings and prepare Phase 3 inputs"
    else
        error "$FAILED_QUERIES queries failed. Check log: $LOG_FILE"
        return 1
    fi
}

# Run main function
main "$@"


