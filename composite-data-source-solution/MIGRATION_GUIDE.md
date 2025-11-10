# Migration Guide: Implementing Composite Data Source

## Overview
This guide walks through migrating from separate 30-second and 300-second models to a unified composite data source.

## Current State Architecture

```
┌─────────────────────────────────┐     ┌─────────────────────────────────┐
│ pdl_dal_30_seconds.sspc_stats   │     │ pdl_dal.gx_dal_sspc_stats       │
│ (30-second source)              │     │ (300-second source)             │
└────────────┬────────────────────┘     └────────────┬────────────────────┘
             │                                       │
             ▼                                       ▼
┌──────────────────────────────────┐   ┌──────────────────────────────────┐
│ stg_pdl_dal__gx_sspc_stats_30_sec│   │ stg_pdl_dal__gx_sspc_stats       │
│ (30-second staging)              │   │ (300-second staging)             │
└────────────┬─────────────────────┘   └────────────┬─────────────────────┘
             │                                       │
             ▼                                       ▼
┌──────────────────────────────────┐   ┌──────────────────────────────────┐
│ int_stats_streams_30sec          │   │ int_stats_stream                 │
└────────────┬─────────────────────┘   └────────────┬─────────────────────┘
             │                                       │
             └───────────────┬───────────────────────┘
                             ▼
                   [Downstream Models]
```

## Target State Architecture

```
┌─────────────────────────────────┐     ┌─────────────────────────────────┐
│ pdl_dal_30_seconds.sspc_stats   │     │ pdl_dal.gx_dal_sspc_stats       │
│ (30-second source)              │     │ (300-second source)             │
└────────────┬────────────────────┘     └────────────┬────────────────────┘
             │                                       │
             └───────────────┬───────────────────────┘
                             ▼
             ┌──────────────────────────────────────┐
             │ stg_pdl_dal__gx_sspc_stats_composite │
             │ (Smart composite with fallback)      │
             │ + metadata fields                    │
             └────────────┬─────────────────────────┘
                          │
                          ▼
             ┌──────────────────────────────────────┐
             │ int_stats_streams_composite          │
             └────────────┬─────────────────────────┘
                          │
                          ▼
                [Downstream Models]

             ┌──────────────────────────────────────┐
             │ monitor_sspc_data_quality            │
             │ (Optional monitoring)                │
             └──────────────────────────────────────┘
```

## Migration Steps

### Phase 1: Deploy Composite Models (Parallel)

**Duration**: 1-2 weeks
**Goal**: Run composite alongside existing models

1. **Deploy composite staging model**
   ```bash
   # Place stg_pdl_dal__gx_sspc_stats_composite.sql in models/staging/pdl_dal/
   dbt run --select stg_pdl_dal__gx_sspc_stats_composite
   ```

2. **Deploy composite intermediate model**
   ```bash
   # Place int_stats_streams_composite.sql in models/intermediate/
   dbt run --select int_stats_streams_composite
   ```

3. **Deploy monitoring model** (optional but recommended)
   ```bash
   # Place monitor_sspc_data_quality.sql in models/monitoring/
   dbt run --select monitor_sspc_data_quality
   ```

### Phase 2: Validation & Testing

**Duration**: 1 week
**Goal**: Ensure composite produces accurate results

1. **Run validation queries**
   ```bash
   # Execute queries from validation_queries.sql
   # Focus on:
   # - Data source distribution
   # - Record count comparisons
   # - Metric validation
   ```

2. **Key validation checks**
   - [ ] Composite record counts match selected source
   - [ ] Data quality threshold is appropriate (adjust if needed)
   - [ ] Aggregated metrics are within acceptable range
   - [ ] No unexpected data gaps

3. **Monitor data quality alerts**
   ```sql
   SELECT * FROM monitor_sspc_data_quality
   WHERE data_quality_alert_level IN ('HIGH', 'MEDIUM')
   AND partition_date >= CURRENT_DATE - 7;
   ```

4. **Threshold tuning** (if needed)
   - Run threshold sensitivity analysis
   - Adjust quality threshold in staging model
   - Common thresholds:
     - 60% = 1728 records/day (lenient)
     - 70% = 2016 records/day (recommended)
     - 80% = 2304 records/day (strict)

### Phase 3: Update Downstream Dependencies

**Duration**: 1-2 weeks
**Goal**: Migrate downstream models to use composite

1. **Identify all downstream dependencies**
   ```bash
   # Find models that reference the old int models
   grep -r "ref('int_stats_streams_30sec')" models/
   grep -r "ref('int_stats_stream')" models/
   ```

2. **Update downstream models** (one at a time)
   ```sql
   -- Before
   FROM {{ ref('int_stats_streams_30sec') }}

   -- After
   FROM {{ ref('int_stats_streams_composite') }}
   ```

3. **Test each downstream model**
   ```bash
   dbt run --select <downstream_model>
   dbt test --select <downstream_model>
   ```

4. **Validate business metrics**
   - Compare outputs before/after migration
   - Ensure dashboards show consistent results
   - Check for any unexpected changes in reporting

### Phase 4: Deprecate Old Models

**Duration**: 1 week
**Goal**: Clean up old models after successful migration

1. **Verify all dependencies migrated**
   ```bash
   dbt ls --select +int_stats_streams_30sec  # Should show no downstream models
   dbt ls --select +int_stats_stream         # Should show no downstream models
   ```

2. **Disable old models** (don't delete yet)
   ```yaml
   # models/staging/pdl_dal/schema.yml
   models:
     - name: stg_pdl_dal__gx_sspc_stats_30_sec
       config:
         enabled: false
     - name: stg_pdl_dal__gx_sspc_stats
       config:
         enabled: false
   ```

3. **Monitor for 1-2 weeks**
   - Ensure no issues arise
   - Check for any missed dependencies

4. **Archive old models**
   ```bash
   # Move to archive directory
   mkdir -p models/archived/
   mv models/staging/pdl_dal/stg_pdl_dal__gx_sspc_stats_30_sec.sql models/archived/
   mv models/intermediate/int_stats_streams_30sec.sql models/archived/
   # etc.
   ```

## Rollback Plan

If issues arise during migration:

### Immediate Rollback
```yaml
# Disable composite models
models:
  - name: stg_pdl_dal__gx_sspc_stats_composite
    config:
      enabled: false
  - name: int_stats_streams_composite
    config:
      enabled: false

# Re-enable old models
models:
  - name: stg_pdl_dal__gx_sspc_stats_30_sec
    config:
      enabled: true
  - name: stg_pdl_dal__gx_sspc_stats
    config:
      enabled: true
```

### Partial Rollback
Keep composite for some use cases, revert others:
```sql
-- Use composite for new reports
FROM {{ ref('int_stats_streams_composite') }}

-- Keep old model for critical dashboards temporarily
FROM {{ ref('int_stats_streams_30sec') }}
```

## Common Issues & Solutions

### Issue 1: High Fallback Rate
**Symptoms**: >30% of data uses 300sec fallback

**Solutions**:
1. Lower quality threshold (e.g., 60% instead of 70%)
2. Investigate 30sec data source reliability
3. Consider time-of-day patterns (may need hourly thresholds)

### Issue 2: Metrics Don't Match
**Symptoms**: Composite metrics differ from original models

**Solutions**:
1. Check data type conversions (especially terminal_obj_id)
2. Verify aggregation logic matches original
3. Ensure date ranges align properly
4. Check for duplicate records in union

### Issue 3: Performance Degradation
**Symptoms**: Composite model runs slower than originals

**Solutions**:
1. Add clustering to composite staging model
2. Consider materializing quality check as incremental table
3. Partition by partition_date in BigQuery
4. Index sspc_obj_id and terminal_obj_id

### Issue 4: Unexpected Source Selection
**Symptoms**: 300sec used when 30sec data looks complete

**Solutions**:
1. Review quality threshold logic
2. Check for timezone issues in date calculations
3. Verify record count expectations are correct
4. Look for data gaps within days

## Testing Checklist

Before going live:
- [ ] All validation queries pass
- [ ] Data quality alerts reviewed and addressed
- [ ] Downstream models updated and tested
- [ ] Business stakeholders validated reports
- [ ] Performance benchmarks acceptable
- [ ] Monitoring alerts configured
- [ ] Documentation updated
- [ ] Rollback plan tested
- [ ] Team trained on new architecture

## Post-Migration Monitoring

### Daily Checks (First 2 Weeks)
```sql
-- 1. Source distribution
SELECT partition_date, data_source, COUNT(*)
FROM stg_pdl_dal__gx_sspc_stats_composite
WHERE partition_date = CURRENT_DATE - 1
GROUP BY 1, 2;

-- 2. Data quality alerts
SELECT * FROM monitor_sspc_data_quality
WHERE partition_date = CURRENT_DATE - 1
AND data_quality_alert_level != 'NONE';
```

### Weekly Reviews
- Review fallback patterns
- Assess threshold appropriateness
- Check for new data quality issues
- Validate business metrics

### Monthly Analysis
- Analyze trends in data quality
- Optimize threshold based on patterns
- Review and adjust monitoring alerts
- Document lessons learned

## Success Criteria

Migration is successful when:
1. ✅ All downstream models use composite source
2. ✅ Data quality meets or exceeds previous state
3. ✅ Business metrics consistent with historical values
4. ✅ No increase in data processing failures
5. ✅ Team confident in new architecture
6. ✅ Monitoring and alerting functioning properly

## Support & Escalation

For issues during migration:
1. Check validation queries output
2. Review monitoring model for patterns
3. Consult this migration guide
4. Escalate to data engineering team if unresolved

## Timeline Summary

| Phase | Duration | Status |
|-------|----------|--------|
| Phase 1: Deploy Composite | 1-2 weeks | ⏳ |
| Phase 2: Validation | 1 week | ⏳ |
| Phase 3: Migrate Downstream | 1-2 weeks | ⏳ |
| Phase 4: Deprecate Old Models | 1 week | ⏳ |
| **Total** | **4-6 weeks** | ⏳ |

## Additional Resources

- `README.md` - Solution architecture overview
- `validation_queries.sql` - Comprehensive validation queries
- `CONFIGURATION.md` - Threshold tuning guide
- dbt docs - Generated documentation for all models
