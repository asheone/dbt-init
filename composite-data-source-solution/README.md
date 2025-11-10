# Composite Data Source Solution: 30sec + 300sec Fallback

## Problem Statement
30-second data provides better granularity and is more representative for daily statistics (e.g., capping percentages). However, there are data quality and coverage issues. We need a composite data source that:
- **Primary**: Use 30-second data when record counts are as expected
- **Fallback**: Use 5-minute (300-second) data when 30-second data quality is insufficient
- **Result**: Create a single source of truth for downstream reporting

## Solution Architecture

### 1. Data Quality Metrics
- **30-second data**: Expected ~2,880 records/day per sspc/terminal (86,400 seconds ÷ 30)
- **300-second data**: Expected ~288 records/day per sspc/terminal (86,400 seconds ÷ 300)
- **Quality threshold**: 70% of expected records (configurable)
  - For 30-second: >= 2,016 records/day = sufficient quality

### 2. Composite Logic (Daily Granularity)
For each day + sspc_obj_id + terminal_obj_id combination:
1. Calculate record count from 30-second data
2. If count >= threshold → Use 30-second data for that day
3. If count < threshold → Use 300-second data for that day
4. Track which source was selected for transparency

### 3. Implementation Components

#### A. Composite Staging Model (`stg_pdl_dal__gx_sspc_stats_composite.sql`)
- Combines both data sources
- Implements fallback logic at daily granularity
- Adds metadata fields: `data_source`, `data_quality_score`

#### B. Data Quality Monitor (`monitor_sspc_data_quality.sql`)
- Optional monitoring model
- Tracks source selection patterns
- Helps identify chronic data quality issues

#### C. Updated Downstream Model (`int_stats_streams_composite.sql`)
- Single model replacing separate 30sec and 300sec versions
- Uses composite staging model
- Maintains all existing business logic

## Key Design Decisions

### Why Daily Granularity?
- Task mentions "daily statistics such as capping %"
- Balances data quality assessment with practical implementation
- Avoids over-fragmentation of data sources within a day

### Why 70% Threshold?
- Allows for some natural data loss (network issues, etc.)
- Conservative enough to ensure data quality
- Can be adjusted based on actual data patterns

### Data Type Alignment
- 30sec model: `terminal_id` (string/int variant)
- 300sec model: `cast(terminal_id as int64)`
- Composite: Standardizes as `terminal_obj_id` (int64) for consistency

## Usage Instructions

1. **Deploy the models** in this order:
   ```bash
   dbt run --select stg_pdl_dal__gx_sspc_stats_composite
   dbt run --select int_stats_streams_composite
   dbt run --select monitor_sspc_data_quality  # Optional
   ```

2. **Monitor data quality**:
   ```sql
   SELECT * FROM monitor_sspc_data_quality
   WHERE partition_date >= CURRENT_DATE - 7
   ORDER BY partition_date DESC
   ```

3. **Validate composite logic**:
   ```sql
   -- Check source distribution
   SELECT
     partition_date,
     data_source,
     COUNT(DISTINCT sspc_obj_id) as sspc_count,
     COUNT(*) as record_count
   FROM stg_pdl_dal__gx_sspc_stats_composite
   WHERE partition_date >= CURRENT_DATE - 7
   GROUP BY 1, 2
   ORDER BY 1 DESC, 2
   ```

## Migration Path

### Current State
- `stg_pdl_dal__gx_sspc_stats_30_sec` → `int_stats_streams_30sec`
- `stg_pdl_dal__gx_sspc_stats` → `int_stats_stream`

### Target State
- `stg_pdl_dal__gx_sspc_stats_composite` → `int_stats_streams_composite`

### Migration Steps
1. Deploy composite staging model alongside existing models
2. Deploy composite int model
3. Validate composite model output vs. existing models
4. Update downstream dependencies to use composite model
5. Deprecate old models once validated

## Tuning Parameters

You can adjust these parameters in the composite model:

```sql
-- Quality threshold (records per day)
WHEN COUNT(*) >= 2016 THEN true  -- Adjust this value

-- Alternative: Percentage-based threshold
WHEN COUNT(*) >= (2880 * 0.70) THEN true  -- 70% threshold
```

## Benefits

1. **Automatic failover**: No manual intervention needed for data quality issues
2. **Transparency**: `data_source` field tracks which source was used
3. **Single source of truth**: One model for all downstream consumers
4. **Better data quality**: 30-second granularity when available
5. **Resilience**: Falls back gracefully when 30-second data is incomplete

## Monitoring & Alerting

Recommended alerts:
- Alert when > 20% of days use 300sec fallback for a specific sspc/terminal
- Alert when data quality score drops below 50% for 30sec data
- Daily summary of source distribution

## Future Enhancements

1. **Smart blending**: Mix 30sec and 300sec data within same day
2. **Dynamic thresholds**: Adjust threshold based on historical patterns
3. **Interpolation**: Fill gaps in 30sec data using 300sec data
4. **Real-time monitoring**: Streaming data quality checks
