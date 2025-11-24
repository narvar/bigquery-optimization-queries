# Archive - Superseded Deployment Documents

**Date:** November 24, 2025  
**Reason:** These documents represent intermediate analysis and deployment planning that were superseded by the final deployment approach.

---

## What's in This Archive

### Superseded Deployment Plans:

1. **DEPLOYMENT_RUNBOOK.md** - Original deployment runbook
   - Assumed we could remove service account from reservation
   - Based on on-demand approach ($27/month)
   - Superseded by: `DEPLOYMENT_RUNBOOK_FINAL.md` (autoscale approach)

2. **ON_DEMAND_DEPLOYMENT_PLAN.md** - On-demand capacity planning
   - Detailed plan for on-demand deployment
   - Not viable due to org-level assignment discovery
   - Would require org-wide refactoring (future project)

3. **CLI_DEPLOYMENT_GUIDE.md** - REST API command reference
   - BigQuery Reservation API examples
   - Incorporated into DEPLOYMENT_RUNBOOK_FINAL.md

4. **ORG_LEVEL_ASSIGNMENT_SOLUTION.md** - Org-level assignment discovery
   - Documents why on-demand isn't achievable
   - Explains assignment hierarchy
   - Key findings incorporated into final runbook

5. **CREDENTIAL_CHECK.md** - Permission verification
   - Tested gcloud commands and Console access
   - Identified that gcloud alpha commands not available
   - Resolution incorporated into deployment approach

6. **TEAM_NOTIFICATION.md** - Communication templates
   - Email, Slack, Jira templates for deployment announcement
   - One-time use (can be referenced if needed again)

7. **check_override_option.md** - Solution options analysis
   - Early analysis of how to override org-level assignment
   - Incorporated into ORG_LEVEL_ASSIGNMENT_SOLUTION.md

---

## Why These Were Superseded

### Original Approach (Nov 21-23):
- Remove messaging from reservation → use on-demand
- Cost: $27/month
- Simple deployment (single command)

### Discovery (Nov 24):
- **Org-level assignment:** Entire narvar.com organization → default reservation
- Cannot simply remove messaging (inherits from org)
- Must create service-account-specific assignment

### Final Approach (Nov 24):
- Create dedicated reservation: 50 baseline + autoscale 50
- Assign messaging service account (overrides org-level)
- Cost: ~$219/month
- Handles 9pm peak of 186-386 slots

---

## Current Documents (Use These Instead)

**For deployment:**
- `../DEPLOYMENT_RUNBOOK_FINAL.md` - Complete guide with autoscale
- `../PRE_DEPLOYMENT_CHECKLIST.md` - Step-by-step checklist
- `../QUICK_DEPLOY.sh` - Automated script

**For analysis:**
- `../CAPACITY_ANALYSIS_SUMMARY.md` - Peak capacity justification
- `../EXECUTIVE_SUMMARY.md` - Stakeholder summary
- `../FINDINGS.md` - Root cause analysis

**For reference:**
- `../README.md` - Investigation overview

---

**These archived documents are kept for historical reference and audit trail.**

