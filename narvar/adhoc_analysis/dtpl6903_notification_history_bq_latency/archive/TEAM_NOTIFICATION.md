# Team Notification - Messaging BigQuery Capacity Deployment

**Send to:** Messaging team, Data Engineering, SRE, Data Platform team  
**Timing:** Send 15-30 minutes before deployment  

---

## Email Template

**Subject:** [Today] BigQuery Dedicated Capacity Deployment - Messaging Service

---

Team,

We are deploying dedicated BigQuery capacity for the Notification History feature to resolve the latency issue reported in DTPL-6903 and escalated by JD Sports EMEA (and previously by Lands' End).

### What's Happening

**Change:** Creating dedicated 50-slot BigQuery reservation for messaging service  
**Service Account:** `messaging@narvar-data-lake.iam.gserviceaccount.com`  
**Timing:** Today at **[INSERT TIME]** PST  
**Duration:** 15 minutes (deployment + verification)  
**Downtime:** ZERO - no service interruption expected

### Why This Change

**Problem:** Notification History queries experiencing up to 8-minute delays (Friday Nov 21)
- Queries execute in 2 seconds but wait 8 minutes for available BigQuery capacity
- Caused by competing with batch workloads (Airflow, Metabase, n8n) on shared reservation

**Solution:** Dedicated 50-slot reservation isolates messaging from batch workloads
- Queue times will drop from 8 minutes → <1 second
- Messaging gets guaranteed capacity, no competition
- Cost: $146/month for dedicated capacity

### Technical Details

**What we're doing:**
1. Create new BigQuery reservation: `messaging-dedicated` (50 slots)
2. Assign messaging service account to dedicated reservation
3. Messaging queries automatically use dedicated capacity
4. No application code changes required

**Impact on your services:**
- Notification History: Significantly faster (8 min → <1 sec)
- No impact on other services
- No API changes, no connection changes
- Transparent to end users

**Rollback:** If any issues, 2-minute rollback to previous configuration

### Monitoring Plan

**First hour:** Check every 5 minutes  
**First day:** Check every hour during business hours  
**First week:** Daily monitoring at 9am

**Success metrics:**
- Queue times <1 second
- 100% of queries using dedicated reservation
- Zero errors
- Zero customer complaints

### What You Need to Do

**Before deployment:** Nothing - this is informational

**During deployment (15 minutes):** 
- No action required
- Service continues normally
- You may notice queries become faster

**After deployment:**
- Monitor for any customer complaints (none expected)
- Report any issues to: cezar.mihaila@narvar.com
- If you notice ANY issues with Notification History, let me know immediately

### Rollback Plan

If any issues occur:
- 2-minute rollback available
- Returns to previous configuration (shared reservation)
- No data loss, no query failures

### Background

**Investigation summary:** 
- Complete root cause analysis: https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/FINDINGS.md
- Deployment guide: https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/DEPLOYMENT_RUNBOOK_FINAL.md

**Questions?** Reply to this email or ping me on Slack.

---

Best regards,  
Cezar Mihaila  
Data Engineering

---

## Slack Message Template (Shorter Version)

**Channel:** #data-engineering, #messaging-team

---

🚀 **Deploying BigQuery dedicated capacity for Notification History today at [TIME] PST**

**What:** Creating 50-slot dedicated reservation for messaging service  
**Why:** Resolves 8-minute delays reported in DTPL-6903  
**Impact:** Zero downtime, queries become significantly faster (<1 sec vs 8 min)  
**Duration:** 15 minutes deployment + monitoring  
**Cost:** $146/month for dedicated capacity  

**Your action:** None required - this is informational

**Rollback:** 2 minutes if any issues

📄 Details: https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/EXECUTIVE_SUMMARY.md

Questions? DM me

---

## Jira Ticket Update Template

**For:** DTPL-6903

---

**Status Update - November 24, 2025**

**Investigation Complete:** Root cause identified as BigQuery reservation capacity saturation. Entire narvar.com organization shares a 1,700-slot reservation that was maxed out on Friday (Nov 21), causing 8-minute queue delays.

**Root Cause:**
- Queries execute in 2 seconds but wait 8 minutes for available BigQuery slots
- Competing with Airflow (46%), Metabase (31%), n8n Shopify for shared capacity
- Organization-level reservation assignment prevents simple on-demand solution

**Solution Deploying Today:**
- Creating dedicated 50-slot flex reservation for messaging service
- Isolates Notification History from batch workloads
- Expected result: Queue times <1 second (99.8% improvement)
- Cost: $146/month for guaranteed capacity
- Timeline: 15-minute deployment, zero downtime

**Deployment Time:** [INSERT TIME] PST

**Monitoring:** Intensive for 24 hours, then daily for 7 days

**Expected Resolution:** Queue delays eliminated, feature becomes responsive

**Documentation:**
- Root cause analysis: [FINDINGS.md](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/FINDINGS.md)
- Deployment guide: [DEPLOYMENT_RUNBOOK_FINAL.md](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency/DEPLOYMENT_RUNBOOK_FINAL.md)

Will update this ticket post-deployment with results.

---

## Calendar Invite Template (Optional)

**Title:** BigQuery Deployment - Messaging Dedicated Capacity

**Time:** [INSERT TIME] (15 minutes)

**Attendees:** Messaging team (optional), Data Engineering (optional)

**Description:**

Deploying dedicated BigQuery capacity for Notification History feature.

**Actions during meeting:**
- Execute deployment (2 commands)
- Monitor for 5-10 minutes
- Verify success

**No attendance required** - this is informational. You're welcome to join if interested in seeing the deployment process.

**Dial-in:** [Optional]

---


