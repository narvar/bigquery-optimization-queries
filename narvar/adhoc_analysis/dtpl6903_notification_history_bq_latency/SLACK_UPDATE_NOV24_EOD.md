# Slack Update - DTPL-6903 End of Day Nov 24

**Channel:** #data-engineering

---

🔴 **DTPL-6903 Update - Deployment Blocker & Path Forward**

**Today's work:**
- ✅ Analyzed messaging traffic: 87K queries/week, 48 avg slots, **186-386 slot 9pm peak** (requires autoscale)
- ✅ Created messaging-dedicated reservation (50 baseline + autoscale 50, total 100 slots)
- ❌ **Blocker:** BigQuery API only allows project-level assignments, not individual service accounts
- ✅ Rolled back safely, no production impact

**Solution:** Create `messaging-hub-bq-dedicated` project, assign to messaging-dedicated reservation (~$219/month)  
**Blocker:** Need org admin to create project (Cezar lacks permission)  
**Tomorrow:** Once project created: setup permissions, test cross-project queries, coordinate with messaging team (3-4 day timeline)  
**Messaging team change:** Update project_id + use fully-qualified table names (`narvar-data-lake.messaging.table`) - no credential swap needed ✅

📄 Docs: https://github.com/narvar/bigquery-optimization-queries/tree/main/narvar/adhoc_analysis/dtpl6903_notification_history_bq_latency

- Cezar

