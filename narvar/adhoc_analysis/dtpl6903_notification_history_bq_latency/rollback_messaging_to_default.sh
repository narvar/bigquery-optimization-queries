#!/bin/bash
# Rollback: Remove messaging from dedicated reservation, returns to org default

echo "🔄 Rolling back messaging to default reservation..."

# Get token
TOKEN=$(gcloud auth print-access-token)

# Step 1: Find and delete messaging assignment from messaging-dedicated
ASSIGNMENT=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/messaging-dedicated/assignments" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for assignment in data.get('assignments', []):
    if 'messaging@narvar-data-lake' in assignment.get('assignee', ''):
        print(assignment['name'])
        break
")

if [ -n "$ASSIGNMENT" ]; then
    echo "Deleting assignment: $ASSIGNMENT"
    curl -X DELETE -H "Authorization: Bearer $TOKEN" \
      "https://bigqueryreservation.googleapis.com/v1/$ASSIGNMENT"
    echo "✅ Assignment deleted"
else
    echo "⚠️  No assignment found (may already be rolled back)"
fi

# Step 2: Wait for propagation
echo "⏰ Waiting 60 seconds..."
sleep 60

# Step 3: Verify (should now use org default: bq-narvar-admin:US.default)
echo "✅ Verifying rollback..."
bq query --use_legacy_sql=false "
SELECT 
  COUNT(*) AS queries,
  STRING_AGG(DISTINCT reservation_id, ', ') AS reservation
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
GROUP BY 1;
"

echo ""
echo "✅ If reservation = 'bq-narvar-admin:US.default', rollback successful!"
echo "   Messaging is back on shared reservation (org-level default)"
