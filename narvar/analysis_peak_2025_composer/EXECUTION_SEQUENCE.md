# Query Execution Sequence for Phase 1 Validation

## Recommended Execution Order

### Phase 1.1: Initial Validation (Start Small - 7 days)
1. `_validation_classification_coverage.sql` (7 days) - Verify all jobs are classified
2. `_validation_classification_accuracy.sql` (7 days) - Check known patterns
3. `_validation_sample_verification.sql` (7 days) - Get samples for review
4. `_validation_classification_summary.sql` (7 days) - Get summary stats

### Phase 1.2: Hub Attribution Pattern Discovery (30-90 days)
5. `hub_traffic_pattern_analysis.sql` (30 days initially) - Discover patterns
6. Review patterns, then run `hub_traffic_attribution_patterns.sql` (30 days) - Apply patterns

### Phase 1.3: Full Classification Validation (30-90 days)
7. `monitor_project_mappings.sql` - Get retailer mappings
8. `unified_traffic_classification.sql` (30 days) - Full classification
9. Re-run validation queries with 30 days - Verify at scale

### Phase 1.4: Create Materialized View for Phase 2
10. `_create_classification_view.sql` - Create view/table for Phase 2 queries

## Notes
- Start with 7-day intervals to validate queries work
- Gradually increase to 30, 90, then 365 days
- Use dry-run first for large queries
- Monitor costs at each step

