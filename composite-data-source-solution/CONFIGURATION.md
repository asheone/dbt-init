# Configuration Guide: Tuning Composite Data Source

## Overview
The composite data source uses configurable thresholds to determine when to use 30-second data vs. falling back to 300-second data. This guide explains how to tune these parameters for your specific needs.

## Key Configuration Parameters

### 1. Quality Threshold (Record Count)

**Location**: `stg_pdl_dal__gx_sspc_stats_composite.sql` (line ~95)

```sql
-- Current configuration
case
    when count(*) >= 2016 then true  -- 70% of expected 2880 records
    else false
end as is_quality_sufficient
```

#### Threshold Options

| Threshold | Records/Day | Use Case | Trade-offs |
|-----------|-------------|----------|------------|
| **50%** | 1,440 | Maximize 30sec usage | May include poor quality data |
| **60%** | 1,728 | Lenient threshold | Good balance for unstable sources |
| **70%** | 2,016 | **Recommended** | Best balance of quality vs coverage |
| **80%** | 2,304 | Strict quality | May fallback unnecessarily |
| **90%** | 2,592 | Very strict | Maximize data quality, more fallbacks |

#### How to Change

```sql
-- Example: Change to 80% threshold
case
    when count(*) >= 2304 then true  -- 80% of expected 2880 records
    else false
end as is_quality_sufficient
```

### 2. Expected Records Per Day

**30-second data**: 2,880 records (86,400 seconds ÷ 30)
**300-second data**: 288 records (86,400 seconds ÷ 300)

These are calculated as:
```
records_per_day = seconds_per_day / granularity_in_seconds
                = 86,400 / 30 = 2,880 (for 30sec)
                = 86,400 / 300 = 288 (for 300sec)
```

**Note**: If your data has different granularities, adjust these values accordingly.

### 3. Granularity Level

**Current**: Daily (partition_date)

Alternative granularities can be implemented:

#### Hourly Granularity
```sql
-- More fine-grained control, but complex
datetime_trunc(timestamp, HOUR) as hourly_partition,
count(*) >= 120  -- 30sec: 3600/30 = 120 records per hour
```

**Pros**: Catch intra-day quality issues
**Cons**: More complex logic, potential for fragmentation

#### Weekly Granularity
```sql
-- Less sensitive to daily variations
date_trunc(timestamp, WEEK) as weekly_partition,
count(*) >= 20160  -- 2880 * 7 days
```

**Pros**: Smooths out daily variations
**Cons**: May miss systematic issues

## Configuration Scenarios

### Scenario 1: Unstable 30-Second Data Source
**Problem**: 30-second data frequently incomplete
**Solution**: Lower threshold to 60%

```sql
case
    when count(*) >= 1728 then true  -- 60% threshold
    else false
end as is_quality_sufficient
```

**Expected Impact**:
- More days use 30-second data
- Trade-off: Some lower quality data included
- Monitor: Check data_quality_score distribution

### Scenario 2: Critical Business Metrics
**Problem**: Need high confidence in data quality
**Solution**: Raise threshold to 80-90%

```sql
case
    when count(*) >= 2304 then true  -- 80% threshold
    else false
end as is_quality_sufficient
```

**Expected Impact**:
- More days fallback to 300-second data
- Higher confidence in 30-second data when used
- Monitor: Ensure acceptable fallback rate (<30%)

### Scenario 3: Different Patterns by Time of Day
**Problem**: 30-second data quality varies by hour
**Solution**: Implement hourly granularity with time-specific thresholds

```sql
with hourly_quality as (
    select
        date(timestamp) as partition_date,
        extract(hour from timestamp) as hour_of_day,
        sspc_obj_id,
        terminal_obj_id,
        count(*) as record_count,
        case
            -- Peak hours: stricter threshold
            when extract(hour from timestamp) between 8 and 18 and count(*) >= 125 then true
            -- Off-peak: lenient threshold
            when count(*) >= 100 then true
            else false
        end as is_quality_sufficient
    from data_30sec
    group by 1, 2, 3, 4
)
```

### Scenario 4: Different Thresholds by SSPC/Terminal
**Problem**: Some terminals have consistently better/worse quality
**Solution**: Implement terminal-specific thresholds

```sql
-- Create a configuration table
create or replace table terminal_quality_config as
select
    terminal_obj_id,
    case
        when terminal_obj_id in (123, 456) then 0.60  -- Known problematic terminals
        when terminal_obj_id in (789, 012) then 0.85  -- High-quality terminals
        else 0.70  -- Default
    end as quality_threshold
;

-- Use in composite logic
case
    when count(*) >= (2880 * cfg.quality_threshold) then true
    else false
end as is_quality_sufficient
```

## Monitoring Configuration Changes

### Before Changing Thresholds

1. **Run sensitivity analysis**
   ```sql
   -- See validation_queries.sql: Query #7
   -- Shows impact of different thresholds
   ```

2. **Review current performance**
   ```sql
   SELECT
       partition_date,
       data_source,
       COUNT(*) as record_count,
       AVG(data_quality_score) as avg_quality
   FROM stg_pdl_dal__gx_sspc_stats_composite
   WHERE partition_date >= CURRENT_DATE - 30
   GROUP BY 1, 2;
   ```

### After Changing Thresholds

1. **Validate source distribution**
   ```sql
   SELECT
       partition_date,
       data_source,
       COUNT(DISTINCT CONCAT(sspc_obj_id, '-', terminal_obj_id)) as combos,
       COUNT(*) as records
   FROM stg_pdl_dal__gx_sspc_stats_composite
   WHERE partition_date >= CURRENT_DATE - 7
   GROUP BY 1, 2;
   ```

2. **Check data quality alerts**
   ```sql
   SELECT *
   FROM monitor_sspc_data_quality
   WHERE partition_date >= CURRENT_DATE - 7
   ORDER BY fallback_rate_7day DESC;
   ```

3. **Compare key metrics**
   ```sql
   -- Before/after comparison
   WITH before AS (
       SELECT AVG(metric) as avg_before
       FROM historical_composite
       WHERE partition_date BETWEEN '2025-10-01' AND '2025-10-31'
   ),
   after AS (
       SELECT AVG(metric) as avg_after
       FROM stg_pdl_dal__gx_sspc_stats_composite
       WHERE partition_date >= CURRENT_DATE - 7
   )
   SELECT
       avg_before,
       avg_after,
       (avg_after - avg_before) / avg_before * 100 as pct_change
   FROM before, after;
   ```

## Advanced Configuration: dbt Variables

For easier configuration management without editing SQL, use dbt variables:

### Define in dbt_project.yml
```yaml
vars:
  sspc_quality_threshold: 0.70  # 70%
  sspc_expected_records_30sec: 2880
  enable_hourly_granularity: false
```

### Use in model
```sql
{%- set quality_threshold = var('sspc_quality_threshold', 0.70) -%}
{%- set expected_records = var('sspc_expected_records_30sec', 2880) -%}

case
    when count(*) >= {{ expected_records * quality_threshold }} then true
    else false
end as is_quality_sufficient
```

### Override at runtime
```bash
dbt run --select stg_pdl_dal__gx_sspc_stats_composite \
    --vars '{"sspc_quality_threshold": 0.80}'
```

## Configuration Best Practices

### 1. Start Conservative
- Begin with 70% threshold
- Monitor for 2-4 weeks
- Adjust based on actual patterns

### 2. Document Changes
```sql
-- Quality threshold history:
-- 2025-11-10: Initial deployment at 70% (2016 records)
-- 2025-11-20: Increased to 75% due to data quality concerns
-- 2025-12-01: Reverted to 70% after source improvements
```

### 3. Test in Development
```bash
# Test different thresholds in dev environment
dbt run --select stg_pdl_dal__gx_sspc_stats_composite \
    --target dev \
    --vars '{"sspc_quality_threshold": 0.80}'
```

### 4. Gradual Changes
- Change threshold by ±5-10% at a time
- Monitor for 1 week before further changes
- Communicate changes to stakeholders

### 5. Automate Alerts
```sql
-- Alert if fallback rate exceeds threshold
CREATE OR REPLACE VIEW data_quality_alerts AS
SELECT
    partition_date,
    sspc_name,
    terminal_name,
    fallback_rate_7day,
    'ALERT: High fallback rate' as alert_message
FROM monitor_sspc_data_quality
WHERE fallback_rate_7day > 0.30  -- Alert threshold: 30%
    AND partition_date = CURRENT_DATE - 1;
```

## Troubleshooting Configuration Issues

### Issue: Too Many Fallbacks
**Symptom**: >30% of data uses 300sec source
**Check**:
```sql
SELECT AVG(data_quality_score)
FROM stg_pdl_dal__gx_sspc_stats_composite
WHERE data_source = '300sec'
AND partition_date >= CURRENT_DATE - 7;
```
**Solution**: Lower threshold if scores are close to threshold

### Issue: Poor Data Quality
**Symptom**: Business metrics show anomalies
**Check**:
```sql
SELECT
    data_source,
    MIN(data_quality_score) as min_quality,
    AVG(data_quality_score) as avg_quality
FROM stg_pdl_dal__gx_sspc_stats_composite
WHERE partition_date >= CURRENT_DATE - 7
GROUP BY data_source;
```
**Solution**: Raise threshold if 30sec quality scores are low

### Issue: Inconsistent Source Selection
**Symptom**: Same terminal switches frequently
**Check**:
```sql
SELECT
    terminal_obj_id,
    partition_date,
    data_source,
    data_quality_score
FROM stg_pdl_dal__gx_sspc_stats_composite
WHERE terminal_obj_id = 123
    AND partition_date >= CURRENT_DATE - 14
ORDER BY partition_date;
```
**Solution**: Implement hysteresis or moving averages

## Configuration Checklist

Before changing thresholds:
- [ ] Run sensitivity analysis
- [ ] Review current performance metrics
- [ ] Document current configuration
- [ ] Test in development environment
- [ ] Communicate changes to team
- [ ] Plan monitoring strategy
- [ ] Prepare rollback procedure

After changing thresholds:
- [ ] Validate source distribution
- [ ] Check data quality alerts
- [ ] Compare key business metrics
- [ ] Monitor for 1 week
- [ ] Document results
- [ ] Update team on outcomes

## Reference Values

### Common Threshold Values
```
Ultra-lenient:  40% = 1,152 records/day
Lenient:        60% = 1,728 records/day
Balanced:       70% = 2,016 records/day (RECOMMENDED)
Strict:         80% = 2,304 records/day
Ultra-strict:   90% = 2,592 records/day
```

### Expected Records by Granularity
```
30-second:  2,880 records/day, 120 records/hour
60-second:  1,440 records/day, 60 records/hour
300-second: 288 records/day, 12 records/hour
600-second: 144 records/day, 6 records/hour
```

### Alert Thresholds (Recommended)
```
Fallback Rate:
  - INFO: 0-10% (occasional fallback)
  - WARNING: 10-30% (frequent fallback)
  - CRITICAL: >30% (systemic issue)

Quality Score:
  - GOOD: >0.80
  - ACCEPTABLE: 0.60-0.80
  - POOR: <0.60
```
