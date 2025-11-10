-- ============================================================================
-- VALIDATION QUERIES FOR COMPOSITE DATA SOURCE
-- ============================================================================
-- Use these queries to validate the composite data source implementation
-- and monitor its behavior over time.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DATA SOURCE DISTRIBUTION
-- ----------------------------------------------------------------------------
-- Check what percentage of data comes from each source
SELECT
    partition_date,
    data_source,
    COUNT(DISTINCT CONCAT(sspc_obj_id, '-', terminal_obj_id)) as unique_combinations,
    COUNT(*) as total_records,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY partition_date), 2) as pct_of_daily_records
FROM {{ ref('stg_pdl_dal__gx_sspc_stats_composite') }}
WHERE partition_date >= CURRENT_DATE - 30
GROUP BY partition_date, data_source
ORDER BY partition_date DESC, data_source;

-- ----------------------------------------------------------------------------
-- 2. DATA QUALITY SCORE DISTRIBUTION
-- ----------------------------------------------------------------------------
-- Understand the distribution of quality scores for 30sec data
SELECT
    partition_date,
    data_source,
    MIN(data_quality_score) as min_quality,
    APPROX_QUANTILES(data_quality_score, 100)[OFFSET(25)] as p25_quality,
    APPROX_QUANTILES(data_quality_score, 100)[OFFSET(50)] as median_quality,
    APPROX_QUANTILES(data_quality_score, 100)[OFFSET(75)] as p75_quality,
    MAX(data_quality_score) as max_quality,
    AVG(data_quality_score) as avg_quality
FROM {{ ref('stg_pdl_dal__gx_sspc_stats_composite') }}
WHERE partition_date >= CURRENT_DATE - 30
GROUP BY partition_date, data_source
ORDER BY partition_date DESC, data_source;

-- ----------------------------------------------------------------------------
-- 3. FALLBACK FREQUENCY BY SSPC/TERMINAL
-- ----------------------------------------------------------------------------
-- Identify which SSPC/Terminal combinations frequently fallback to 300sec
WITH daily_sources AS (
    SELECT
        partition_date,
        sspc_obj_id,
        sspc_name,
        terminal_obj_id,
        terminal_name,
        data_source,
        AVG(data_quality_score) as avg_quality_score
    FROM {{ ref('stg_pdl_dal__gx_sspc_stats_composite') }}
    WHERE partition_date >= CURRENT_DATE - 30
    GROUP BY 1, 2, 3, 4, 5, 6
),
fallback_stats AS (
    SELECT
        sspc_obj_id,
        sspc_name,
        terminal_obj_id,
        terminal_name,
        COUNT(DISTINCT partition_date) as total_days,
        SUM(CASE WHEN data_source = '300sec' THEN 1 ELSE 0 END) as days_with_fallback,
        ROUND(AVG(CASE WHEN data_source = '30sec' THEN avg_quality_score END), 3) as avg_30sec_quality,
        ROUND(
            SUM(CASE WHEN data_source = '300sec' THEN 1 ELSE 0 END) * 100.0 /
            COUNT(DISTINCT partition_date),
            2
        ) as fallback_percentage
    FROM daily_sources
    GROUP BY 1, 2, 3, 4
)
SELECT *
FROM fallback_stats
WHERE fallback_percentage > 0  -- Only show combinations with fallback
ORDER BY fallback_percentage DESC, total_days DESC
LIMIT 100;

-- ----------------------------------------------------------------------------
-- 4. COMPARE RECORD COUNTS: COMPOSITE vs ORIGINAL SOURCES
-- ----------------------------------------------------------------------------
-- Validate that composite is selecting data correctly
WITH composite_counts AS (
    SELECT
        partition_date,
        sspc_obj_id,
        terminal_obj_id,
        data_source as composite_source,
        COUNT(*) as composite_records
    FROM {{ ref('stg_pdl_dal__gx_sspc_stats_composite') }}
    WHERE partition_date >= CURRENT_DATE - 7
    GROUP BY 1, 2, 3, 4
),
source_30sec_counts AS (
    SELECT
        DATE(timestamp) as partition_date,
        sspc_id as sspc_obj_id,
        CAST(terminal_id AS INT64) as terminal_obj_id,
        COUNT(*) as records_30sec
    FROM {{ source('pdl_dal_30_seconds', 'sspc_stats') }}
    WHERE DATE(timestamp) >= CURRENT_DATE - 7
    GROUP BY 1, 2, 3
),
source_300sec_counts AS (
    SELECT
        DATE(timestamp) as partition_date,
        sspc_id as sspc_obj_id,
        CAST(terminal_id AS INT64) as terminal_obj_id,
        COUNT(*) as records_300sec
    FROM {{ source('pdl_dal', 'gx_dal_sspc_stats') }}
    WHERE DATE(timestamp) >= CURRENT_DATE - 7
    GROUP BY 1, 2, 3
)
SELECT
    c.partition_date,
    c.sspc_obj_id,
    c.terminal_obj_id,
    c.composite_source,
    c.composite_records,
    COALESCE(s30.records_30sec, 0) as source_30sec_records,
    COALESCE(s300.records_300sec, 0) as source_300sec_records,
    -- Validation: composite should match the selected source
    CASE
        WHEN c.composite_source = '30sec' AND c.composite_records = s30.records_30sec THEN 'PASS'
        WHEN c.composite_source = '300sec' AND c.composite_records = s300.records_300sec THEN 'PASS'
        ELSE 'FAIL'
    END as validation_status
FROM composite_counts c
LEFT JOIN source_30sec_counts s30
    ON c.partition_date = s30.partition_date
    AND c.sspc_obj_id = s30.sspc_obj_id
    AND c.terminal_obj_id = s30.terminal_obj_id
LEFT JOIN source_300sec_counts s300
    ON c.partition_date = s300.partition_date
    AND c.sspc_obj_id = s300.sspc_obj_id
    AND c.terminal_obj_id = s300.terminal_obj_id
WHERE validation_status = 'FAIL'  -- Show only failures
ORDER BY c.partition_date DESC;

-- ----------------------------------------------------------------------------
-- 5. DAILY AGGREGATED METRICS COMPARISON
-- ----------------------------------------------------------------------------
-- Compare key metrics between composite and original 30sec model
WITH composite_metrics AS (
    SELECT
        partition_date,
        COUNT(*) as record_count,
        SUM(sspc_total_downstream_usage) as total_downstream,
        SUM(sspc_total_upstream_usage) as total_upstream,
        AVG(sspc_downstream_cir_fulfillment) as avg_ds_fulfillment
    FROM {{ ref('stg_pdl_dal__gx_sspc_stats_composite') }}
    WHERE partition_date >= CURRENT_DATE - 7
    GROUP BY partition_date
),
original_30sec_metrics AS (
    SELECT
        DATE(timestamp) as partition_date,
        COUNT(*) as record_count,
        SUM(sspc_ds_usage) as total_downstream,
        SUM(sspc_us_usage) as total_upstream,
        AVG(sspc_ds_cir_fulfillment) as avg_ds_fulfillment
    FROM {{ source('pdl_dal_30_seconds', 'sspc_stats') }}
    WHERE DATE(timestamp) >= CURRENT_DATE - 7
    GROUP BY partition_date
)
SELECT
    c.partition_date,
    c.record_count as composite_records,
    o.record_count as original_30sec_records,
    c.total_downstream as composite_downstream,
    o.total_downstream as original_30sec_downstream,
    ROUND(ABS(c.total_downstream - o.total_downstream) * 100.0 / NULLIF(o.total_downstream, 0), 2) as downstream_diff_pct,
    c.avg_ds_fulfillment as composite_fulfillment,
    o.avg_ds_fulfillment as original_fulfillment
FROM composite_metrics c
LEFT JOIN original_30sec_metrics o ON c.partition_date = o.partition_date
ORDER BY c.partition_date DESC;

-- ----------------------------------------------------------------------------
-- 6. DATA QUALITY ALERTS
-- ----------------------------------------------------------------------------
-- Use the monitoring model to identify issues
SELECT
    partition_date,
    sspc_name,
    terminal_name,
    data_quality_alert_level,
    data_quality_message,
    fallback_rate_7day,
    avg_quality_score_7day
FROM {{ ref('monitor_sspc_data_quality') }}
WHERE data_quality_alert_level IN ('HIGH', 'MEDIUM')
    AND partition_date >= CURRENT_DATE - 7
ORDER BY
    CASE data_quality_alert_level
        WHEN 'HIGH' THEN 1
        WHEN 'MEDIUM' THEN 2
        ELSE 3
    END,
    partition_date DESC;

-- ----------------------------------------------------------------------------
-- 7. THRESHOLD SENSITIVITY ANALYSIS
-- ----------------------------------------------------------------------------
-- Analyze impact of different quality thresholds
WITH record_counts AS (
    SELECT
        DATE(timestamp) as partition_date,
        sspc_id as sspc_obj_id,
        CAST(terminal_id AS INT64) as terminal_obj_id,
        COUNT(*) as records_30sec
    FROM {{ source('pdl_dal_30_seconds', 'sspc_stats') }}
    WHERE DATE(timestamp) >= CURRENT_DATE - 30
    GROUP BY 1, 2, 3
),
threshold_analysis AS (
    SELECT
        partition_date,
        COUNT(*) as total_combinations,
        -- Current threshold: 2016 (70%)
        SUM(CASE WHEN records_30sec >= 2016 THEN 1 ELSE 0 END) as pass_70pct,
        -- Alternative thresholds
        SUM(CASE WHEN records_30sec >= 2304 THEN 1 ELSE 0 END) as pass_80pct,
        SUM(CASE WHEN records_30sec >= 1728 THEN 1 ELSE 0 END) as pass_60pct,
        SUM(CASE WHEN records_30sec >= 1440 THEN 1 ELSE 0 END) as pass_50pct
    FROM record_counts
    GROUP BY partition_date
)
SELECT
    partition_date,
    total_combinations,
    pass_70pct,
    ROUND(pass_70pct * 100.0 / total_combinations, 2) as pct_pass_70,
    pass_80pct,
    ROUND(pass_80pct * 100.0 / total_combinations, 2) as pct_pass_80,
    pass_60pct,
    ROUND(pass_60pct * 100.0 / total_combinations, 2) as pct_pass_60,
    pass_50pct,
    ROUND(pass_50pct * 100.0 / total_combinations, 2) as pct_pass_50
FROM threshold_analysis
ORDER BY partition_date DESC;
