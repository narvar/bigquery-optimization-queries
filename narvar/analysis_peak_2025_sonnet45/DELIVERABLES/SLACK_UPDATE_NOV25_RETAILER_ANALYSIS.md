# Monitor Platform - Retailer Cost Analysis Complete (CORRECTED)

**Key Finding:** Monitor platform serves **1,724 retailers** with moderate zombie data issue (54%, not 88% as initially calculated):

• **796 retailers (46%) actively use Monitor** - validated via audit logs (Aug 27-Nov 25)  
• **928 retailers (54%) are zombies** - $32K/year waste (13% of platform, not 45%)  
• **94% cost <$100 per 90 days** - extreme long tail, median $9/year  
• **Top retailers:** Gap (1,194 queries, $138 cons), Kohls (2,110 queries, $126 cons), FashionNova (6,459 queries, $843 cons - heaviest user)  
• **Data quality lesson:** Initial analysis used incomplete traffic_classification table (missing Nov 1-25 data). Audit logs are source of truth.

**Action Required:** Focus pricing on top 105 retailers (73% of costs), implement zombie cleanup for bottom 54%

📊 [Executive Summary](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/DELIVERABLES/MONITOR_COST_EXECUTIVE_SUMMARY.md) | [90-Day Analysis](https://github.com/narvar/bigquery-optimization-queries/blob/main/narvar/analysis_peak_2025_sonnet45/DELIVERABLES/90DAY_FULL_ANALYSIS_SUMMARY.md)


