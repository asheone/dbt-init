# Example Usage: Composite Data Source

This document provides concrete examples of how to use the composite data source in different scenarios.

## Basic Usage

### Before: Using Separate Sources

```sql
-- Old way: Had to choose between two models
-- Option 1: Use 30-second data (better granularity, but gaps)
SELECT *
FROM {{ ref('int_stats_streams_30sec') }}
WHERE partition_date >= '2025-11-01'

-- Option 2: Use 300-second data (reliable, but less granular)
SELECT *
FROM {{ ref('int_stats_stream') }}
WHERE partition_date >= '2025-11-01'

-- Problem: Which one should you trust?
```

### After: Using Composite Source

```sql
-- New way: Single source that automatically selects best data
SELECT *
FROM {{ ref('int_stats_streams_composite') }}
WHERE partition_date >= '2025-11-01'

-- Automatically uses 30sec when quality is good, 300sec when needed
-- No manual decision required!
```

## Example 1: Simple Query with Source Transparency

```sql
-- Query composite data with visibility into source selection
SELECT
    partition_date,
    sspc_name,
    terminal_name,
    data_source,  -- NEW: See which source was used
    data_quality_score,  -- NEW: See quality score
    sspc_total_downstream_usage,
    sspc_total_upstream_usage
FROM {{ ref('int_stats_streams_composite') }}
WHERE partition_date >= CURRENT_DATE - 7
ORDER BY partition_date DESC, sspc_name
```

**Sample Output**:
```
partition_date | sspc_name        | terminal_name | data_source | quality_score | downstream_usage
---------------|------------------|---------------|-------------|---------------|------------------
2025-11-09     | SSPC-123-DAT-01 | TERM-001     | 30sec       | 0.92          | 1024000000
2025-11-09     | SSPC-456-DAT-02 | TERM-002     | 300sec      | 0.45          | 2048000000
2025-11-08     | SSPC-123-DAT-01 | TERM-001     | 30sec       | 0.88          | 1023000000
```

## Example 2: Daily Statistics with Quality Filtering

```sql
-- Calculate daily statistics, optionally filtering by data quality
SELECT
    partition_date,
    COUNT(DISTINCT sspc_obj_id) as unique_sspcs,
    SUM(sspc_total_downstream_usage) as total_downstream_gb,
    AVG(sspc_downstream_cir_fulfillment) as avg_cir_fulfillment,
    -- Show data quality metrics
    SUM(CASE WHEN data_source = '30sec' THEN 1 ELSE 0 END) as count_30sec,
    SUM(CASE WHEN data_source = '300sec' THEN 1 ELSE 0 END) as count_300sec,
    AVG(data_quality_score) as avg_quality_score
FROM {{ ref('int_stats_streams_composite') }}
WHERE partition_date >= CURRENT_DATE - 30
    AND data_quality_score >= 0.60  -- Optional: Filter low quality data
GROUP BY partition_date
ORDER BY partition_date DESC
```

## Example 3: Capping Analysis (Original Use Case)

```sql
-- Calculate capping percentage using composite data
-- This was the original use case: "daily statistics such as capping %"
WITH daily_stats AS (
    SELECT
        partition_date,
        sspc_obj_id,
        sspc_name,
        terminal_obj_id,
        data_source,
        data_quality_score,
        -- Calculate actual vs allocated bandwidth
        sspc_total_downstream_usage,
        sspc_downstream_allocated_bandwidth_in_bytes,
        -- Calculate if capped
        CASE
            WHEN sspc_downstream_cir_fulfillment < 1.0 THEN true
            ELSE false
        END as is_capped
    FROM {{ ref('int_stats_streams_composite') }}
    WHERE partition_date >= CURRENT_DATE - 30
),
capping_summary AS (
    SELECT
        partition_date,
        COUNT(*) as total_measurements,
        SUM(CASE WHEN is_capped THEN 1 ELSE 0 END) as capped_measurements,
        ROUND(
            SUM(CASE WHEN is_capped THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
            2
        ) as capping_percentage,
        -- Include data quality context
        ROUND(AVG(data_quality_score), 3) as avg_quality_score,
        SUM(CASE WHEN data_source = '30sec' THEN 1 ELSE 0 END) as using_30sec,
        SUM(CASE WHEN data_source = '300sec' THEN 1 ELSE 0 END) as using_300sec
    FROM daily_stats
    GROUP BY partition_date
)
SELECT
    partition_date,
    capping_percentage,
    total_measurements,
    capped_measurements,
    -- Show confidence level based on data source
    CASE
        WHEN using_30sec > using_300sec THEN 'HIGH (mostly 30sec data)'
        WHEN using_300sec > using_30sec THEN 'MEDIUM (mostly 300sec data)'
        ELSE 'MIXED'
    END as confidence_level,
    avg_quality_score
FROM capping_summary
ORDER BY partition_date DESC
```

## Example 4: Monitoring Data Quality Over Time

```sql
-- Use the built-in monitoring model
SELECT
    partition_date,
    COUNT(*) as sspc_terminal_combinations,
    SUM(CASE WHEN is_fallback THEN 1 ELSE 0 END) as fallback_count,
    ROUND(
        SUM(CASE WHEN is_fallback THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
        2
    ) as fallback_rate,
    AVG(data_quality_score_30sec) as avg_30sec_quality,
    -- Alert level distribution
    SUM(CASE WHEN data_quality_alert_level = 'HIGH' THEN 1 ELSE 0 END) as high_alerts,
    SUM(CASE WHEN data_quality_alert_level = 'MEDIUM' THEN 1 ELSE 0 END) as medium_alerts,
    SUM(CASE WHEN data_quality_alert_level = 'LOW' THEN 1 ELSE 0 END) as low_alerts
FROM {{ ref('monitor_sspc_data_quality') }}
WHERE partition_date >= CURRENT_DATE - 30
GROUP BY partition_date
ORDER BY partition_date DESC
```

## Example 5: Terminal-Level Analysis

```sql
-- Identify terminals with chronic data quality issues
SELECT
    terminal_obj_id,
    terminal_name,
    COUNT(DISTINCT partition_date) as days_analyzed,
    SUM(CASE WHEN data_source = '30sec' THEN 1 ELSE 0 END) as days_using_30sec,
    SUM(CASE WHEN data_source = '300sec' THEN 1 ELSE 0 END) as days_using_300sec,
    ROUND(
        SUM(CASE WHEN data_source = '300sec' THEN 1 ELSE 0 END) * 100.0 /
        COUNT(DISTINCT partition_date),
        2
    ) as fallback_rate_pct,
    ROUND(AVG(data_quality_score), 3) as avg_quality_score,
    -- Flag problematic terminals
    CASE
        WHEN SUM(CASE WHEN data_source = '300sec' THEN 1 ELSE 0 END) * 100.0 /
             COUNT(DISTINCT partition_date) > 30 THEN '🔴 HIGH FALLBACK'
        WHEN SUM(CASE WHEN data_source = '300sec' THEN 1 ELSE 0 END) * 100.0 /
             COUNT(DISTINCT partition_date) > 15 THEN '🟡 MEDIUM FALLBACK'
        ELSE '🟢 GOOD'
    END as status
FROM {{ ref('int_stats_streams_composite') }}
WHERE partition_date >= CURRENT_DATE - 30
GROUP BY terminal_obj_id, terminal_name
HAVING fallback_rate_pct > 0  -- Only show terminals with some fallback
ORDER BY fallback_rate_pct DESC
```

## Example 6: Comparing Before/After Migration

```sql
-- Compare metrics between old and new models
WITH composite_data AS (
    SELECT
        partition_date,
        'composite' as source_type,
        COUNT(*) as record_count,
        SUM(sspc_total_downstream_usage) as total_downstream,
        SUM(sspc_total_upstream_usage) as total_upstream,
        AVG(sspc_downstream_cir_fulfillment) as avg_fulfillment
    FROM {{ ref('int_stats_streams_composite') }}
    WHERE partition_date >= CURRENT_DATE - 7
    GROUP BY partition_date
),
old_30sec_data AS (
    SELECT
        partition_date,
        '30sec_only' as source_type,
        COUNT(*) as record_count,
        SUM(sspc_total_downstream_usage) as total_downstream,
        SUM(sspc_total_upstream_usage) as total_upstream,
        AVG(sspc_downstream_cir_fulfillment) as avg_fulfillment
    FROM {{ ref('int_stats_streams_30sec') }}
    WHERE partition_date >= CURRENT_DATE - 7
    GROUP BY partition_date
),
old_300sec_data AS (
    SELECT
        partition_date,
        '300sec_only' as source_type,
        COUNT(*) as record_count,
        SUM(sspc_total_downstream_usage) as total_downstream,
        SUM(sspc_total_upstream_usage) as total_upstream,
        AVG(sspc_downstream_cir_fulfillment) as avg_fulfillment
    FROM {{ ref('int_stats_stream') }}
    WHERE partition_date >= CURRENT_DATE - 7
    GROUP BY partition_date
),
combined AS (
    SELECT * FROM composite_data
    UNION ALL
    SELECT * FROM old_30sec_data
    UNION ALL
    SELECT * FROM old_300sec_data
)
SELECT
    partition_date,
    source_type,
    record_count,
    total_downstream / 1e9 as total_downstream_gb,
    total_upstream / 1e9 as total_upstream_gb,
    ROUND(avg_fulfillment, 3) as avg_fulfillment
FROM combined
ORDER BY partition_date DESC, source_type
```

## Example 7: Creating a Derived Report

```sql
-- Create a downstream reporting model using composite source
{{ config(
    materialized='table',
    tags=['reporting']
) }}

WITH base_data AS (
    SELECT
        partition_date,
        sspc_name,
        sspc_obj_id,
        terminal_name,
        terminal_obj_id,
        data_source,
        data_quality_score,
        sspc_total_downstream_usage,
        sspc_total_upstream_usage,
        sspc_downstream_cir_fulfillment,
        sspc_upstream_cir_fulfillment
    FROM {{ ref('int_stats_streams_composite') }}
    WHERE partition_date >= CURRENT_DATE - 90
        AND CONTAINS_SUBSTR(sspc_name, '-DAT-')  -- Data terminals only
),
daily_aggregates AS (
    SELECT
        partition_date,
        sspc_name,
        terminal_name,
        -- Traffic metrics
        SUM(sspc_total_downstream_usage) / 1e9 as daily_downstream_gb,
        SUM(sspc_total_upstream_usage) / 1e9 as daily_upstream_gb,
        -- Performance metrics
        AVG(sspc_downstream_cir_fulfillment) as avg_ds_fulfillment,
        AVG(sspc_upstream_cir_fulfillment) as avg_us_fulfillment,
        -- Quality metrics
        MAX(data_source) as primary_data_source,
        AVG(data_quality_score) as avg_quality_score,
        -- Calculate 7-day moving averages
        AVG(SUM(sspc_total_downstream_usage)) OVER (
            PARTITION BY sspc_name
            ORDER BY partition_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) / 1e9 as downstream_7day_avg_gb
    FROM base_data
    GROUP BY partition_date, sspc_name, terminal_name
)
SELECT
    partition_date,
    sspc_name,
    terminal_name,
    daily_downstream_gb,
    daily_upstream_gb,
    downstream_7day_avg_gb,
    avg_ds_fulfillment,
    avg_us_fulfillment,
    primary_data_source,
    avg_quality_score,
    -- Add business classifications
    CASE
        WHEN daily_downstream_gb > 100 THEN 'High Usage'
        WHEN daily_downstream_gb > 50 THEN 'Medium Usage'
        ELSE 'Low Usage'
    END as usage_tier,
    CASE
        WHEN avg_ds_fulfillment < 0.8 THEN 'Frequently Capped'
        WHEN avg_ds_fulfillment < 0.95 THEN 'Occasionally Capped'
        ELSE 'Rarely Capped'
    END as capping_category
FROM daily_aggregates
ORDER BY partition_date DESC, daily_downstream_gb DESC
```

## Example 8: Alert Query for Operations

```sql
-- Daily operational alert query
-- Run this every morning to identify issues
WITH quality_issues AS (
    SELECT
        partition_date,
        sspc_name,
        terminal_name,
        data_quality_alert_level,
        fallback_rate_7day,
        data_quality_message
    FROM {{ ref('monitor_sspc_data_quality') }}
    WHERE partition_date = CURRENT_DATE - 1
        AND data_quality_alert_level IN ('HIGH', 'MEDIUM')
),
usage_anomalies AS (
    SELECT
        partition_date,
        sspc_name,
        terminal_name,
        sspc_total_downstream_usage / 1e9 as downstream_gb,
        AVG(sspc_total_downstream_usage) OVER (
            PARTITION BY sspc_name
            ORDER BY partition_date
            ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
        ) / 1e9 as avg_7day_gb,
        data_source
    FROM {{ ref('int_stats_streams_composite') }}
    WHERE partition_date = CURRENT_DATE - 1
)
-- Combine alerts
SELECT
    'DATA_QUALITY' as alert_type,
    qi.partition_date,
    qi.sspc_name,
    qi.terminal_name,
    qi.data_quality_message as message,
    qi.data_quality_alert_level as severity
FROM quality_issues qi

UNION ALL

SELECT
    'USAGE_ANOMALY' as alert_type,
    ua.partition_date,
    ua.sspc_name,
    ua.terminal_name,
    CONCAT(
        'Usage (', ROUND(ua.downstream_gb, 2), ' GB) differs significantly from 7-day avg (',
        ROUND(ua.avg_7day_gb, 2), ' GB)'
    ) as message,
    CASE
        WHEN ABS(ua.downstream_gb - ua.avg_7day_gb) / ua.avg_7day_gb > 0.5 THEN 'HIGH'
        WHEN ABS(ua.downstream_gb - ua.avg_7day_gb) / ua.avg_7day_gb > 0.3 THEN 'MEDIUM'
        ELSE 'LOW'
    END as severity
FROM usage_anomalies ua
WHERE ABS(ua.downstream_gb - ua.avg_7day_gb) / ua.avg_7day_gb > 0.3

ORDER BY severity DESC, partition_date DESC
```

## Example 9: Quality-Filtered Aggregation

```sql
-- Only use high-quality data for sensitive calculations
SELECT
    partition_date,
    -- Count all records
    COUNT(*) as total_records,
    -- High quality only (30sec with good scores or any 300sec)
    COUNT(CASE
        WHEN data_source = '30sec' AND data_quality_score >= 0.80 THEN 1
        WHEN data_source = '300sec' THEN 1
    END) as high_quality_records,
    -- Calculate metrics using only high-quality data
    AVG(CASE
        WHEN data_source = '30sec' AND data_quality_score >= 0.80 THEN sspc_downstream_cir_fulfillment
        WHEN data_source = '300sec' THEN sspc_downstream_cir_fulfillment
    END) as high_quality_avg_fulfillment,
    -- Compare with all data
    AVG(sspc_downstream_cir_fulfillment) as all_data_avg_fulfillment
FROM {{ ref('int_stats_streams_composite') }}
WHERE partition_date >= CURRENT_DATE - 30
GROUP BY partition_date
ORDER BY partition_date DESC
```

## Tips & Best Practices

### 1. Always Check Data Source
When analyzing critical metrics, check which source was used:
```sql
GROUP BY partition_date, data_source
```

### 2. Filter by Quality When Needed
For sensitive calculations, filter by quality score:
```sql
WHERE data_quality_score >= 0.80 OR data_source = '300sec'
```

### 3. Use Monitoring Model for Health Checks
Don't reinvent the wheel - use the built-in monitoring:
```sql
FROM {{ ref('monitor_sspc_data_quality') }}
```

### 4. Document Source Selection Impact
When creating reports, document how source selection affects results:
```sql
-- Add metadata to reports
SELECT
    ...,
    CONCAT(
        SUM(CASE WHEN data_source = '30sec' THEN 1 ELSE 0 END),
        ' using 30sec, ',
        SUM(CASE WHEN data_source = '300sec' THEN 1 ELSE 0 END),
        ' using 300sec'
    ) as data_source_breakdown
```

### 5. Test with Different Date Ranges
Behavior may vary by date range due to data availability:
```sql
-- Test both recent and historical dates
WHERE partition_date >= '2024-01-01'  -- Historical
WHERE partition_date >= CURRENT_DATE - 7  -- Recent
```

## Next Steps

- Review `README.md` for complete architecture documentation
- Check `validation_queries.sql` for more query examples
- See `MIGRATION_GUIDE.md` for implementation steps
- Consult `CONFIGURATION.md` for threshold tuning
