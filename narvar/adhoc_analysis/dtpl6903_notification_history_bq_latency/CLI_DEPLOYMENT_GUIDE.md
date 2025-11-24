# CLI Deployment Guide - Using BigQuery Reservation API

**Date:** November 24, 2025  
**Method:** BigQuery Reservation API via curl  
**Service Account:** `messaging@narvar-data-lake.iam.gserviceaccount.com`

---

## Overview

Since `gcloud alpha bq reservations` commands aren't available, we'll use the **BigQuery Reservation API** directly via curl commands.

**This is a 4-step process:**
1. Get authentication token
2. List current assignments (find the messaging one)
3. Delete the assignment (enables on-demand)
4. Verify it worked

---

## Step-by-Step Deployment

### Step 1: Get Authentication Token

```bash
# Get your access token
TOKEN=$(gcloud auth print-access-token)

# Verify token was created
echo "Token: ${TOKEN:0:50}..." 
# Should show: Token: ya29.c.c0ASRK0Ga... (truncated)
```

---

### Step 2: List All Assignments for the Reservation

```bash
# List all assignments for the default reservation
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments" \
  | jq '.'

# If you don't have jq installed, use python for pretty printing:
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments" \
  | python3 -m json.tool
```

**Expected output format:**
```json
{
  "assignments": [
    {
      "name": "projects/bq-narvar-admin/locations/US/reservations/default/assignments/1234567890",
      "assignee": "organizations/770066481180",
      "jobType": "QUERY",
      "state": "ACTIVE"
    },
    {
      "name": "projects/bq-narvar-admin/locations/US/reservations/default/assignments/9876543210",
      "assignee": "projects/narvar-data-lake/serviceAccounts/messaging@narvar-data-lake.iam.gserviceaccount.com",
      "jobType": "QUERY",
      "state": "ACTIVE"
    }
  ]
}
```

**Look for the entry where:**
- `"assignee"` contains `"messaging@narvar-data-lake.iam.gserviceaccount.com"`
- Copy the full `"name"` value (you'll need this for deletion)

---

### Step 3: Find the Messaging Assignment Name

**Extract just the messaging assignment:**

```bash
# Find messaging assignment and save the name
MESSAGING_ASSIGNMENT=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for assignment in data.get('assignments', []):
    if 'messaging@narvar-data-lake' in assignment.get('assignee', ''):
        print(assignment['name'])
        break
")

# Show what we found
echo "Messaging assignment: $MESSAGING_ASSIGNMENT"

# Should show something like:
# projects/bq-narvar-admin/locations/US/reservations/default/assignments/1774019164364589712
```

**If the output is empty:**
- The messaging service account might not be assigned to this reservation
- It might already be using on-demand
- We can verify this with a query

---

### Step 4: Delete the Assignment (THE DEPLOYMENT)

```bash
# Verify you have the assignment name
echo "About to delete: $MESSAGING_ASSIGNMENT"

# DEPLOYMENT COMMAND - Delete the assignment
curl -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/$MESSAGING_ASSIGNMENT"

# Expected output: {} (empty JSON object = success)
```

**Expected output:**
```json
{}
```

**If successful:** The messaging service account is now using on-demand slots!

**If you get an error:**
```json
{
  "error": {
    "code": 403,
    "message": "Permission denied",
    ...
  }
}
```
This means you don't have permission to delete assignments.

---

### Step 5: Verify Deployment Worked

**Wait 60 seconds for propagation:**

```bash
echo "⏰ Waiting 60 seconds for configuration to propagate..."
sleep 60
echo "✅ Ready to verify"
```

**Check if assignment was deleted:**

```bash
# List assignments again (should not show messaging)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
messaging_found = False
for assignment in data.get('assignments', []):
    if 'messaging@narvar-data-lake' in assignment.get('assignee', ''):
        messaging_found = True
        print('⚠️  WARNING: Messaging assignment still exists!')
        print('Assignment:', assignment['name'])
        break
        
if not messaging_found:
    print('✅ SUCCESS: Messaging assignment deleted!')
"
```

**Check BigQuery job history:**

```bash
# Verify new queries are using on-demand
bq query --use_legacy_sql=false "
SELECT
  job_id,
  creation_time,
  reservation_id,
  TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
ORDER BY creation_time DESC
LIMIT 5;
"
```

**Success indicators:**
- ✅ `reservation_id` = NULL (using on-demand)
- ✅ `queue_sec` = 0-1 seconds
- ✅ Queries executing normally

---

## Complete Deployment Script (Copy-Paste Ready)

Save this as `deploy_ondemand.sh`:

```bash
#!/bin/bash
# On-Demand Deployment Script for Messaging Service Account

set -e  # Exit on any error

echo "🚀 Starting on-demand deployment for messaging service account"
echo "=================================================="
echo ""

# Step 1: Get token
echo "Step 1: Getting authentication token..."
TOKEN=$(gcloud auth print-access-token)
echo "✅ Token obtained"
echo ""

# Step 2: List current assignments
echo "Step 2: Listing current assignments..."
ASSIGNMENTS=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments")

echo "Current assignments:"
echo "$ASSIGNMENTS" | python3 -m json.tool
echo ""

# Step 3: Find messaging assignment
echo "Step 3: Finding messaging service account assignment..."
MESSAGING_ASSIGNMENT=$(echo "$ASSIGNMENTS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for assignment in data.get('assignments', []):
    if 'messaging@narvar-data-lake' in assignment.get('assignee', ''):
        print(assignment['name'])
        break
")

if [ -z "$MESSAGING_ASSIGNMENT" ]; then
    echo "⚠️  WARNING: Messaging assignment not found!"
    echo "Service account may already be on-demand."
    echo "Checking recent queries..."
    
    bq query --use_legacy_sql=false --format=csv "
    SELECT
      STRING_AGG(DISTINCT reservation_id, ', ') AS current_reservation,
      COUNT(*) AS queries_last_hour
    FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
    WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
      AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
    GROUP BY 1;
    "
    
    echo ""
    echo "If current_reservation is NULL, already on-demand!"
    echo "If current_reservation shows a reservation, check Console manually."
    exit 1
fi

echo "✅ Found messaging assignment:"
echo "   $MESSAGING_ASSIGNMENT"
echo ""

# Step 4: Confirm before deletion
echo "⚠️  About to DELETE this assignment (enables on-demand)"
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Deployment cancelled by user"
    exit 0
fi

echo ""
echo "Step 4: Deleting assignment..."

# THE DEPLOYMENT
RESULT=$(curl -s -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/$MESSAGING_ASSIGNMENT")

echo "Delete response: $RESULT"

# Check if successful (empty {} response)
if [ "$RESULT" == "{}" ] || [ -z "$RESULT" ]; then
    echo "✅ Assignment deleted successfully!"
else
    echo "⚠️  Unexpected response. Check if deletion succeeded."
    echo "$RESULT" | python3 -m json.tool
fi

echo ""
echo "Step 5: Waiting 60 seconds for propagation..."
sleep 60

echo ""
echo "Step 6: Verifying on-demand is active..."
bq query --use_legacy_sql=false "
SELECT
  job_id,
  creation_time,
  reservation_id,
  TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS exec_sec
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
ORDER BY creation_time DESC
LIMIT 5;
"

echo ""
echo "✅ DEPLOYMENT COMPLETE!"
echo ""
echo "Expected results:"
echo "  - reservation_id: NULL (on-demand)"
echo "  - queue_sec: 0-1 seconds"
echo "  - exec_sec: 1-3 seconds (unchanged)"
echo ""
echo "If you see NULL for reservation_id, deployment successful!"
echo ""
echo "Monitor for next hour using: ./monitor_5min.sh"
```

---

## Rollback Script (If Needed)

Save this as `rollback_messaging.sh`:

```bash
#!/bin/bash
# Rollback script - re-assign messaging to reservation

set -e

echo "🔄 Rolling back messaging service account to reservation..."

TOKEN=$(gcloud auth print-access-token)

# Create assignment
RESULT=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "assignee": "projects/narvar-data-lake/serviceAccounts/messaging@narvar-data-lake.iam.gserviceaccount.com",
    "jobType": "QUERY"
  }' \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments")

echo "Create response:"
echo "$RESULT" | python3 -m json.tool

echo ""
echo "⏰ Waiting 60 seconds for propagation..."
sleep 60

echo ""
echo "✅ Rollback complete. Verifying..."

bq query --use_legacy_sql=false "
SELECT 
  COUNT(*) AS recent_queries,
  STRING_AGG(DISTINCT reservation_id, ', ') AS reservations
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
GROUP BY 1;
"

echo ""
echo "✅ If you see 'bq-narvar-admin:US.default' above, rollback successful!"
```

---

## Quick Start (Copy-Paste Commands)

**Let's do this step-by-step. First, let's find the messaging assignment:**

```bash
# Step 1: Get token and list assignments
TOKEN=$(gcloud auth print-access-token)

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments" \
  | python3 -m json.tool > current_assignments.json

# Step 2: Look for messaging assignment
cat current_assignments.json | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'Total assignments: {len(data.get(\"assignments\", []))}')
print('')
for i, assignment in enumerate(data.get('assignments', []), 1):
    assignee = assignment.get('assignee', 'Unknown')
    name = assignment.get('name', 'Unknown')
    job_type = assignment.get('jobType', 'Unknown')
    
    print(f'{i}. Assignee: {assignee}')
    print(f'   Job Type: {job_type}')
    print(f'   Name: {name}')
    
    if 'messaging@narvar-data-lake' in assignee:
        print('   👉 THIS IS THE ONE TO DELETE')
    print('')
"
```

**Run these commands and show me the output.** This will list ALL assignments and identify which one is for messaging.

---

## After You Find the Assignment

Once we identify the messaging assignment name, we'll run:

```bash
# Replace ASSIGNMENT_NAME with the actual value from Step 2
MESSAGING_ASSIGNMENT="projects/bq-narvar-admin/locations/US/reservations/default/assignments/XXXXX"

# Delete it
curl -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/$MESSAGING_ASSIGNMENT"

# Wait and verify
sleep 60

# Check if it worked
bq query --use_legacy_sql=false "
SELECT job_id, reservation_id, 
       TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
ORDER BY creation_time DESC LIMIT 5;
"
```

---

## Permission Test First

**Before attempting deployment, let's test if you have API permissions:**

```bash
# Test: Try to list assignments (read-only, safe)
TOKEN=$(gcloud auth print-access-token)

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments" \
  | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'error' in data:
        print('❌ ERROR:', data['error']['message'])
        print('You may not have permission to access assignments.')
    else:
        print('✅ SUCCESS: Can read assignments')
        print(f'Found {len(data.get(\"assignments\", []))} assignments')
except:
    print('❌ Failed to parse response')
    sys.exit(1)
"
```

**Run this command first** and show me the output.

---

## What to Do Right Now

**Copy and paste this into your terminal:**

```bash
cd /Users/cezarmihaila/workspace/do_it_query_optimization_queries/bigquery-optimization-queries/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency

# Get token
TOKEN=$(gcloud auth print-access-token)

# List assignments and search for messaging
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://bigqueryreservation.googleapis.com/v1/projects/bq-narvar-admin/locations/US/reservations/default/assignments" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)

if 'error' in data:
    print('❌ ERROR:', data['error']['message'])
    sys.exit(1)

assignments = data.get('assignments', [])
print(f'✅ Found {len(assignments)} total assignments\n')

messaging_found = False
for i, assignment in enumerate(assignments, 1):
    assignee = assignment.get('assignee', '')
    name = assignment.get('name', '')
    
    print(f'{i}. {assignee}')
    
    if 'messaging@narvar-data-lake' in assignee:
        print(f'   👉 MESSAGING ASSIGNMENT FOUND!')
        print(f'   Name: {name}')
        messaging_found = True
    print('')

if not messaging_found:
    print('⚠️  Messaging assignment NOT found in this reservation.')
    print('It may already be on-demand!')
"
```

**Show me the output and we'll proceed from there!**

