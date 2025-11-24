#!/bin/bash
# Quick Deployment Script - Messaging Dedicated Capacity
# Date: November 24, 2025
# Service: messaging@narvar-data-lake.iam.gserviceaccount.com

set -e  # Exit on error

echo "🚀 MESSAGING DEDICATED CAPACITY DEPLOYMENT"
echo "=========================================="
echo ""
echo "Service Account: messaging@narvar-data-lake.iam.gserviceaccount.com"
echo "Target: 50-slot baseline + autoscale to 100 slots"
echo "Cost: \$146/month baseline + ~\$73/month autoscale = ~\$219/month"
echo ""

# Confirm before proceeding
read -p "Proceed with deployment? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

echo ""
echo "Step 1/4: Creating messaging-dedicated reservation..."
echo "  - Baseline: 50 slots (\$146/month)"
echo "  - Autoscale: +50 slots max (total 100)"
echo "  - Edition: ENTERPRISE (for autoscale capability)"
echo "================================================================"

bq mk \
  --location=US \
  --project_id=bq-narvar-admin \
  --reservation \
  --slots=50 \
  --ignore_idle_slots=false \
  --edition=ENTERPRISE \
  --autoscale_max_slots=50 \
  messaging-dedicated

if [ $? -eq 0 ]; then
    echo "✅ Reservation created successfully"
    echo "Created at: $(date)" >> deployment_log.txt
    echo "  - Baseline: 50 slots" >> deployment_log.txt
    echo "  - Autoscale: +50 slots (total 100)" >> deployment_log.txt
else
    echo "⚠️  Note: If 'already exists', that's OK - proceeding to assignment"
fi

echo ""
echo "Step 2/4: Assigning messaging service account..."
echo "================================================"

TOKEN=$(gcloud auth print-access-token)

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "assignee": "projects/narvar-data-lake/serviceAccounts/messaging@narvar-data-lake.iam.gserviceaccount.com",
    "jobType": "QUERY"
  }' \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

echo "Response:"
echo "$BODY" | python3 -m json.tool

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo "✅ Assignment created successfully"
    echo "Assigned at: $(date)" >> deployment_log.txt
elif [ "$HTTP_CODE" = "409" ]; then
    echo "⚠️  Assignment already exists - verifying it's correct..."
else
    echo "❌ ERROR: HTTP $HTTP_CODE"
    echo "Check response above for details"
    exit 1
fi

echo ""
echo "Step 3/4: Waiting for propagation (60 seconds)..."
echo "================================================"
sleep 60
echo "✅ Propagation complete"

echo ""
echo "Step 4/4: Verifying deployment..."
echo "================================="

bq query --use_legacy_sql=false --format=csv "
SELECT
  COUNT(*) AS queries_last_5min,
  STRING_AGG(DISTINCT reservation_id, ' | ') AS reservations_used,
  ROUND(AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)), 2) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') AS dedicated_count,
  COUNTIF(error_result IS NOT NULL) AS errors,
  CASE
    WHEN COUNTIF(reservation_id = 'bq-narvar-admin:US.messaging-dedicated') = COUNT(*) THEN 'SUCCESS'
    WHEN COUNTIF(reservation_id = 'bq-narvar-admin:US.default') > 0 THEN 'STILL_ON_DEFAULT'
    ELSE 'MIXED'
  END AS status
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
"

echo ""
echo "🎯 EXPECTED RESULTS:"
echo "  - reservations_used: bq-narvar-admin:US.messaging-dedicated"
echo "  - avg_queue_sec: <1 second"
echo "  - max_queue_sec: <5 seconds"
echo "  - dedicated_count: 100% of queries"
echo "  - errors: 0"
echo "  - status: SUCCESS"
echo ""

read -p "Does the output match expected results? (yes/no): " SUCCESS

if [ "$SUCCESS" = "yes" ]; then
    echo ""
    echo "✅ ==============================================="
    echo "✅ DEPLOYMENT SUCCESSFUL!"
    echo "✅ ==============================================="
    echo ""
    echo "Next steps:"
    echo "  1. Run ./monitor_5min.sh every 5-10 minutes for the next hour"
    echo "  2. Run ./monitor_hourly.sh at 11am, 12pm, 1pm, 2pm, 3pm, 4pm, 5pm"
    echo "  3. Check for customer complaints (should be none)"
    echo "  4. Tomorrow: Update Jira DTPL-6903 with deployment results"
    echo ""
    echo "Deployment completed at: $(date)" >> deployment_log.txt
else
    echo ""
    echo "⚠️  DEPLOYMENT NEEDS ATTENTION"
    echo ""
    read -p "Do you want to rollback? (yes/no): " ROLLBACK
    
    if [ "$ROLLBACK" = "yes" ]; then
        echo "Executing rollback..."
        ./rollback_messaging_to_default.sh
    else
        echo "Continuing to monitor. Check DEPLOYMENT_RUNBOOK_FINAL.md for troubleshooting."
    fi
fi

