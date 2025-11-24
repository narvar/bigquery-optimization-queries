# On-Demand Deployment Runbook - Messaging Service Account

**Service Account:** `messaging@narvar-data-lake.iam.gserviceaccount.com`  
**Date:** November 24, 2025  
**Deployer:** Cezar Mihaila  
**Estimated Time:** 10 minutes deployment + 24 hours monitoring

---

## What This Deployment Does

**Removes** the messaging service account from the shared BigQuery reservation `bq-narvar-admin:US.default`

**Result:** Service account automatically uses on-demand slots (Google's default behavior)

**Impact:**
- ✅ Queue times drop from 558s → <1s
- ✅ No competing with Airflow/Metabase/n8n for slots
- ✅ Unlimited capacity (up to 2,000 slots per query)
- ✅ Cost: ~$27/month (based on 4.3 TB/month usage)
- ✅ Zero downtime
- ✅ 30-second rollback if issues

---

## The Actual Deployment

### Single Command (This is all you need):

```bash
gcloud alpha bq reservations assignments delete \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT
```

**Expected output:**
```
Deleted assignment [projects/bq-narvar-admin/locations/US/reservations/default/assignments/...]
```

**If you see this output:** ✅ Deployment successful - service account is now on-demand

**If you see "Not found" or "Assignment does not exist":** ⚠️ Service account may already be on-demand (verify with monitoring query below)

---

## Pre-Deployment Checklist (5 minutes)

Run these commands BEFORE the deployment:

### 1. Verify Current State

```bash
# Check reservation configuration
bq show --location=US \
  --reservation \
  --project_id=bq-narvar-admin \
  bq-narvar-admin:US.default
```

**Expected output:**
- slotCapacity: 1000
- autoscaleMaxSlots: 700
- autoscaleCurrentSlots: 700 (maxed out)

### 2. Document Baseline Performance

```bash
# Capture baseline (last 1 hour)
bq query --use_legacy_sql=false --format=csv "
SELECT
  COUNT(*) AS queries_last_hour,
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  SUM(total_bytes_processed) / POW(1024, 3) AS gb_processed,
  STRING_AGG(DISTINCT reservation_id, ', ') AS current_reservations
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
" > baseline_before_deployment.csv

cat baseline_before_deployment.csv
```

**Save this output** - you'll compare against it after deployment.

### 3. Create Rollback Script

```bash
# Create rollback script (just in case)
cat > rollback_messaging.sh << 'EOF'
#!/bin/bash
# Rollback script - re-assign messaging to reservation

echo "🔄 Rolling back messaging service account to reservation..."

gcloud alpha bq reservations assignments create \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT \
  --priority=100

echo "⏰ Waiting 60 seconds for propagation..."
sleep 60

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

echo "✅ If you see 'bq-narvar-admin:US.default' above, rollback successful!"
EOF

chmod +x rollback_messaging.sh
echo "✅ Rollback script created: ./rollback_messaging.sh"
```

---

## Deployment Steps

### Step 1: Execute Deployment Command (1 minute)

```bash
# THE DEPLOYMENT - Remove from reservation
gcloud alpha bq reservations assignments delete \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT

# Log the deployment
echo "Deployment executed at: $(date)" >> deployment_log.txt
```

### Step 2: Wait for Propagation (1 minute)

```bash
echo "⏰ Waiting 60 seconds for BigQuery to propagate configuration..."
sleep 60
echo "✅ Propagation window complete"
```

**What happens during this time:**
- BigQuery updates internal routing tables
- New queries will use on-demand
- Queries in flight complete normally
- No disruption to service

### Step 3: Immediate Verification (2 minutes)

```bash
# Check that on-demand is active
bq query --use_legacy_sql=false "
SELECT
  job_id,
  creation_time,
  reservation_id,
  TIMESTAMP_DIFF(start_time, creation_time, SECOND) AS queue_sec,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS exec_sec,
  total_bytes_processed / POW(1024, 3) AS gb_processed
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
ORDER BY creation_time DESC
LIMIT 10;
"
```

**What to verify:**

| Column | Expected Value | What It Means |
|--------|----------------|---------------|
| `reservation_id` | **NULL** | Using on-demand ✅ |
| `queue_sec` | **0-1 seconds** | No queue delays ✅ |
| `exec_sec` | **1-3 seconds** | Normal execution ✅ |
| `gb_processed` | **5-20 GB** | Normal data volume ✅ |

**If reservation_id is NOT null:**
- ⏰ Wait another 2-3 minutes (propagation still happening)
- 🔄 Re-run verification query
- ⚠️ If still showing reservation after 5 minutes → investigate

**If queue_sec is >10 seconds:**
- 🔴 Something wrong with on-demand
- 🔄 Execute rollback immediately
- 📞 Contact Google Cloud Support

---

## Post-Deployment Monitoring

### First Hour: Intensive Monitoring (Every 5 minutes)

**Run this query at: 10:15, 10:20, 10:25, 10:30, 10:45, 11:00**

```bash
# Save as monitor_5min.sh
bq query --use_legacy_sql=false --format=csv "
SELECT
  CURRENT_TIMESTAMP() AS check_time,
  
  -- Volume
  COUNT(*) AS queries_last_5min,
  
  -- Performance (KEY METRICS)
  ROUND(AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)), 2) AS avg_queue_sec,
  APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] AS p95_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  
  ROUND(AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)), 2) AS avg_exec_sec,
  
  -- Verify on-demand usage
  COUNTIF(reservation_id IS NULL) AS on_demand_queries,
  COUNTIF(reservation_id IS NOT NULL) AS reservation_queries,
  
  -- Cost tracking
  ROUND(SUM(total_bytes_processed) / POW(1024, 3) * 6.25, 4) AS cost_last_5min,
  ROUND(SUM(total_bytes_processed) / POW(1024, 3) * 6.25 * 12 * 24 * 30, 2) AS projected_monthly,
  
  -- Error detection
  COUNTIF(error_result IS NOT NULL) AS errors,
  
  -- Status
  CASE
    WHEN MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 30 THEN '🔴 QUEUE ISSUES'
    WHEN COUNTIF(reservation_id IS NOT NULL) > 0 THEN '🟡 NOT ON-DEMAND YET'
    WHEN COUNTIF(error_result IS NOT NULL) > 0 THEN '🔴 ERRORS DETECTED'
    ELSE '✅ HEALTHY'
  END AS status

FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
" | tee -a monitoring_log.csv
```

**Success criteria (all must be true):**
- ✅ status = '✅ HEALTHY'
- ✅ avg_queue_sec < 1 second
- ✅ p95_queue_sec < 2 seconds
- ✅ on_demand_queries = 100%
- ✅ projected_monthly < $150
- ✅ errors = 0

**If ANY check fails:** Review the specific issue:
- 🔴 QUEUE ISSUES → Rollback immediately
- 🟡 NOT ON-DEMAND YET → Wait 5 more minutes
- 🔴 ERRORS DETECTED → Rollback immediately

---

### First 24 Hours: Hourly Monitoring

**Run this query every hour (10:00, 11:00, 12:00, etc.):**

```bash
# Save as monitor_hourly.sh
bq query --use_legacy_sql=false --format=csv "
SELECT
  CURRENT_DATE('America/Los_Angeles') AS date,
  EXTRACT(HOUR FROM CURRENT_TIMESTAMP() AT TIME ZONE 'America/Los_Angeles') AS hour_pst,
  
  -- Last hour metrics
  COUNT(*) AS queries_last_hour,
  
  ROUND(AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)), 2) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  
  ROUND(SUM(total_bytes_processed) / POW(1024, 3), 2) AS gb_last_hour,
  ROUND(SUM(total_bytes_processed) / POW(1024, 3) * 6.25, 2) AS cost_last_hour,
  
  -- Verify all on-demand
  ROUND(100.0 * COUNTIF(reservation_id IS NULL) / COUNT(*), 1) AS pct_on_demand,
  
  CASE
    WHEN MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 10 THEN '🔴 ALERT'
    WHEN AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 2 THEN '🟡 WARNING'
    ELSE '✅ OK'
  END AS status

FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
" | tee -a hourly_monitoring.csv
```

**Check at:** 11am, 12pm, 1pm, 2pm, 3pm, 4pm, 5pm (business hours)

**Alert triggers:**
- 🔴 max_queue_sec > 10 seconds → Investigate immediately
- 🔴 cost_last_hour > $2 → Check for inefficient queries
- 🟡 pct_on_demand < 100% → Some queries still on reservation (wait more)

---

### First 7 Days: Daily Monitoring

**Run this query once per day at 9am:**

```bash
# Save as monitor_daily.sh
bq query --use_legacy_sql=false --format=csv "
SELECT
  DATE(creation_time, 'America/Los_Angeles') AS date_pst,
  
  -- Volume
  COUNT(*) AS daily_queries,
  
  -- Performance
  ROUND(AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)), 2) AS avg_queue_sec,
  APPROX_QUANTILES(TIMESTAMP_DIFF(start_time, creation_time, SECOND), 100)[OFFSET(95)] AS p95_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec,
  
  -- Cost (KEY METRIC)
  ROUND(SUM(total_bytes_processed) / POW(1024, 4), 3) AS tb_processed,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4) * 6.25, 2) AS daily_cost_usd,
  
  -- Verify on-demand
  ROUND(100.0 * COUNTIF(reservation_id IS NULL) / COUNT(*), 1) AS pct_on_demand,
  
  -- Problem detection
  COUNTIF(TIMESTAMP_DIFF(start_time, creation_time, SECOND) > 60) AS delayed_over_1min,
  COUNTIF(error_result IS NOT NULL) AS errors,
  
  -- Status
  CASE
    WHEN SUM(total_bytes_processed) / POW(1024, 4) * 6.25 > 10 THEN '🔴 COST ALERT'
    WHEN MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) > 30 THEN '🔴 LATENCY ALERT'
    WHEN COUNTIF(error_result IS NOT NULL) > 10 THEN '🔴 ERROR ALERT'
    WHEN SUM(total_bytes_processed) / POW(1024, 4) * 6.25 > 5 THEN '🟡 COST WARNING'
    ELSE '✅ HEALTHY'
  END AS status

FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY'
GROUP BY date_pst
ORDER BY date_pst DESC;
" | tee daily_monitoring_$(date +%Y%m%d).csv

echo ""
echo "Expected values:"
echo "  daily_cost_usd: $0.90-$2.50 (target: <$5)"
echo "  p95_queue_sec: <2 seconds"
echo "  pct_on_demand: 100%"
echo "  status: ✅ HEALTHY"
```

**Review criteria:**
- ✅ Daily cost: $0.90-$2.50 (projected $27-$75/month)
- ✅ P95 queue: <2 seconds
- ✅ 100% on-demand
- ✅ No errors
- ✅ Status: HEALTHY

**If daily cost >$10:** Investigate what changed (query efficiency, volume spike, data growth)

---

## Success Criteria

### Immediate Success (First hour):

| Metric | Baseline (Reservation) | Target (On-Demand) | Status |
|--------|------------------------|-------------------|--------|
| P50 queue time | 0-176 seconds | <1 second | Check every 5 min |
| P95 queue time | 30-507 seconds | <2 seconds | Check every 5 min |
| Max queue time | 558 seconds | <5 seconds | Check every 5 min |
| Avg execution | 2.2 seconds | ~2 seconds (unchanged) | Should be stable |
| Error rate | 0% | 0% | Must remain 0% |
| Reservation ID | bq-narvar-admin:US.default | NULL | Must be NULL |

### 24-Hour Success (Day 1):

| Metric | Target | Check Frequency |
|--------|--------|-----------------|
| Daily cost | <$5 | End of day |
| Projected monthly | <$150 | End of day |
| P95 queue time | <2 seconds | Hourly during business hours |
| Error rate | <0.1% | Hourly |
| % on-demand | 100% | Hourly |

### 7-Day Success (Week 1):

| Metric | Target | Check Frequency |
|--------|--------|-----------------|
| Average daily cost | <$2.50 | Daily at 9am |
| 7-day total cost | <$17.50 | Day 7 |
| P95 queue time | <2 seconds | Daily |
| Zero customer complaints | Yes | Monitor Jira/Slack |
| Zero incidents | Yes | Monitor alerts |

---

## Rollback Procedures

### When to Rollback Immediately (Do not wait)

Execute rollback if ANY of these occur:

1. **Error rate >1%** (more than 1 in 100 queries failing)
2. **P95 queue time >30 seconds** (worse than reservation was)
3. **Customer complaint** received about notification history
4. **Queries not using on-demand** after 5 minutes (configuration not applying)

### How to Rollback (30 seconds)

```bash
# Option 1: Use the script
./rollback_messaging.sh

# Option 2: Manual command
gcloud alpha bq reservations assignments create \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=default \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT \
  --priority=100

# Wait for propagation
sleep 60

# Verify rollback
bq query --use_legacy_sql=false "
SELECT 
  COUNT(*) AS queries,
  STRING_AGG(DISTINCT reservation_id, ', ') AS reservation
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 MINUTE)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
GROUP BY 1;
"
# Should show: reservation = 'bq-narvar-admin:US.default'
```

**After rollback:**
- Document what went wrong
- Investigate root cause
- Update this runbook with lessons learned

### When to Monitor & Evaluate (Do not rollback yet)

**Evaluate these conditions but don't rollback immediately:**

1. **P95 queue time 2-10 seconds:**
   - Better than reservation (was 30-507s)
   - But not hitting target (<2s)
   - Monitor for 4 hours - may be temporary spike

2. **Daily cost $5-$10:**
   - Higher than expected ($0.90-2.50)
   - But still reasonable
   - Monitor for 3 days - may be anomaly
   - If sustained >$10/day: Consider switching to flex

3. **Some queries still on reservation:**
   - Propagation may take up to 5 minutes
   - Wait and re-check
   - If persists >10 minutes: Investigate configuration

---

## Cost Management Considerations

### Setting Up Budget Alerts

**Option 1: GCP Budget Alerts (Recommended)**

Via GCP Console:
1. Go to: Billing → Budgets & Alerts
2. Create budget for `narvar-data-lake` project
3. Filter: Service = BigQuery
4. Budget amount: $150/month
5. Alert thresholds: 50%, 75%, 90%, 100%
6. Email recipients: [your team distribution list]

**Option 2: Custom Monitoring Script**

```bash
# Create daily cost check (run via cron at 9am daily)
cat > check_daily_cost.sh << 'EOF'
#!/bin/bash

COST=$(bq query --use_legacy_sql=false --format=csv --max_rows=1 "
SELECT
  ROUND(SUM(total_bytes_processed) / POW(1024, 4) * 6.25, 2) AS cost
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= CURRENT_DATE('America/Los_Angeles')
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND job_type = 'QUERY';
" | tail -1)

echo "Today's cost so far: \$$COST"

# Alert if >$10
if (( $(echo "$COST > 10" | bc -l) )); then
  echo "🔴 ALERT: Daily cost exceeds $10!"
  # Add email notification here
fi
EOF

chmod +x check_daily_cost.sh
```

### Automatic Failsafe: Switch to Flex if Cost Spikes

**If daily cost >$10 for 3 consecutive days:**

```bash
# Create 100-slot flex reservation
bq mk --location=US \
  --project_id=bq-narvar-admin \
  --reservation \
  --slots=100 \
  --ignore_idle_slots=false \
  --edition=STANDARD \
  messaging-flex-100

# Move service account to flex reservation
gcloud alpha bq reservations assignments create \
  --project=bq-narvar-admin \
  --location=US \
  --reservation=messaging-flex-100 \
  --assignee=messaging@narvar-data-lake.iam.gserviceaccount.com \
  --assignee-type=SERVICE_ACCOUNT

# Result: Cost locked at $292/month, capacity capped at 100 slots
```

**This protects you from cost runaway while still maintaining isolation.**

---

## What Could Go Wrong (And How to Handle It)

### Issue 1: Cost Higher Than Expected

**Symptom:** Daily cost >$5 (projected >$150/month)

**Possible causes:**
1. Query efficiency degraded (scanning more data)
2. Volume increased (more user searches)
3. New queries added (more tables scanned)

**Investigation:**
```sql
-- Find expensive queries
SELECT
  job_id,
  creation_time,
  total_bytes_processed / POW(1024, 3) AS gb_scanned,
  total_bytes_processed / POW(1024, 3) * 6.25 AS cost_usd,
  SUBSTR(query, 1, 200) AS query_sample
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND total_bytes_processed / POW(1024, 3) > 50  -- Queries scanning >50 GB
ORDER BY total_bytes_processed DESC
LIMIT 20;
```

**Actions:**
- Optimize inefficient queries
- Check if partition pruning working
- Consider switching to flex ($292/month fixed) if sustained high cost

---

### Issue 2: Queue Times Still High

**Symptom:** P95 queue >5 seconds (even on on-demand)

**Possible causes:**
1. Configuration didn't apply (still using reservation)
2. BigQuery on-demand capacity issue (VERY rare)
3. Application-side queueing (not BigQuery)

**Investigation:**
```sql
-- Check if actually using on-demand
SELECT
  reservation_id,
  COUNT(*) AS queries,
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
GROUP BY reservation_id;
```

**Actions:**
- If reservation_id NOT null → Configuration didn't apply, re-run delete command
- If reservation_id is null but still queueing → Contact Google Cloud Support
- Consider switching to dedicated 200-slot flex reservation

---

### Issue 3: Queries Failing

**Symptom:** Error rate >0.1%

**Possible causes:**
1. Permissions issue (unlikely - same service account)
2. BigQuery service disruption
3. Unrelated to on-demand change

**Investigation:**
```sql
-- Check error details
SELECT
  error_result.reason,
  error_result.message,
  COUNT(*) AS error_count,
  ANY_VALUE(job_id) AS sample_job_id
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND user_email = 'messaging@narvar-data-lake.iam.gserviceaccount.com'
  AND error_result IS NOT NULL
GROUP BY error_result.reason, error_result.message
ORDER BY error_count DESC;
```

**Actions:**
- If errors are "rateLimitExceeded" → Normal, transient
- If errors are "accessDenied" → Rollback (permissions issue)
- If errors are unrelated to configuration → Monitor, likely transient

---

## Deployment Decision Matrix

### Should I Use On-Demand or Flex Reservation?

**Current Data (4.3 TB/month):**

| Factor | On-Demand | 100-Slot Flex | Winner |
|--------|-----------|---------------|--------|
| **Monthly Cost** | $27 | $292 | 🏆 On-Demand (10x cheaper) |
| **Setup Time** | 5 minutes | 10 minutes | 🏆 On-Demand |
| **Slot Cap** | No cap (2,000/query) | 100 slots | Flex (if you need cap) |
| **Cost Predictability** | Variable | Fixed | Flex |
| **Flexibility** | Unlimited capacity | Fixed capacity | 🏆 On-Demand |
| **Risk of Queue** | Near zero | Low (if sized right) | 🏆 On-Demand |

**RECOMMENDATION:** **On-demand** unless you specifically need cost ceiling or slot governance.

---

### When to Switch from On-Demand to Flex

**Trigger conditions (any of these):**

1. **Sustained high cost:** Daily cost >$10 for 7 consecutive days (projected >$300/month)
2. **Budget constraint:** Finance requires fixed monthly cost
3. **Governance requirement:** Need hard slot cap for capacity planning
4. **Usage growth:** Monthly usage exceeds 24 TB (break-even point)

**Current projection:** None of these apply - stay on on-demand.

---

## Next Steps After Deployment

### Day 1 (Deployment Day - Today):

- [x] Pre-deployment checks (5 min)
- [ ] Execute deployment command (1 min)
- [ ] Wait 60 seconds propagation
- [ ] Immediate verification (2 min)
- [ ] Monitor every 5 minutes for 1 hour
- [ ] Monitor every hour until 5pm
- [ ] End-of-day review

### Day 2-7 (First Week):

- [ ] Daily monitoring at 9am
- [ ] Check for cost trends
- [ ] Verify queue times remain low
- [ ] Monitor for any customer complaints
- [ ] Document any anomalies

### Day 8-30 (First Month):

- [ ] Weekly cost review (Mondays at 9am)
- [ ] 30-day cost projection after Day 30
- [ ] Evaluate if switch to flex needed
- [ ] Update stakeholders on results
- [ ] Close DTPL-6903 Jira ticket if successful

---

## Stakeholder Communication

### Pre-Deployment Notification

**Send to:** Messaging team, SRE, Data Engineering

**Template:**
```
Subject: [Scheduled] BigQuery Configuration Change - Messaging Service Account

Team,

We are deploying a configuration change to resolve the Notification History 
latency issue (DTPL-6903). 

Change: Remove messaging service account from shared BigQuery reservation
Impact: Queries will use on-demand capacity instead
Timing: Today at 10:00am PST
Duration: 5 minutes (zero downtime expected)
Rollback: 30 seconds if any issues

Expected result: Queue times drop from 8 minutes to <1 second
Cost impact: ~$27/month additional (on-demand pricing)

Monitoring: Intensive for first hour, then hourly for 24 hours

Please let me know if you have concerns.

- Cezar
```

### Post-Deployment Update

**Send 24 hours after deployment:**

```
Subject: [Complete] BigQuery On-Demand Deployment - Messaging Service

Team,

Deployment completed successfully yesterday at 10:00am.

Results (first 24 hours):
- Queue times: P95 = X seconds (target: <2s) ✅/❌
- Queries executed: X,XXX (normal volume) ✅
- Errors: 0 ✅
- Daily cost: $X.XX (target: <$5) ✅/❌
- Status: ✅ HEALTHY

On-demand capacity is working as expected. Continuing to monitor daily.

Next review: 7-day summary on [DATE]

- Cezar
```

---

## Emergency Contacts

**If issues during deployment:**

1. **Immediate rollback:** Execute `./rollback_messaging.sh` (no approval needed)
2. **Data Engineering lead:** [Contact info]
3. **GCP Support:** Open ticket if BigQuery service issues
4. **Messaging team:** [Contact info] - if customer-facing impact

---

## Appendix: Why On-Demand Doesn't Need Slot Caps

**Your workload characteristics:**
- Average: 170 slots
- Peak: ~300 slots (estimated)
- On-demand provides: Up to 2,000 slots per query

**Capacity headroom:** 6-11x more than you need

**Cost protection is via $$ alerts, not slot caps:**
- Budget alert: $150/month
- Daily monitoring: $5/day threshold
- Automatic failsafe: Switch to flex if >$10/day for 7 days

**Why this works:**
- Current usage is stable (4.3 TB/month for weeks)
- Query patterns are consistent (notification history lookups)
- No indication of runaway query risk
- Budget alerts catch cost issues before they become problems

**If you absolutely need slot governance:** Use 100-slot flex reservation ($292/month) instead of on-demand.

---

**Runbook Version:** 1.0  
**Last Updated:** November 24, 2025  
**Owner:** Cezar Mihaila  
**Status:** READY FOR DEPLOYMENT

