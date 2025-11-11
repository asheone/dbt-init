-- OPTIMIZED BigQuery SSPC Stats Query - Version 2 (Using EXCEPT for Anti-Join)
-- This version uses EXCEPT DISTINCT which may be more efficient than NOT EXISTS in BigQuery
--
-- Key optimizations:
-- 1. Single scan of 30-second table with window function for quality calculation
-- 2. Direct timestamp comparison for partition pruning
-- 3. EXCEPT DISTINCT for anti-join (often faster than NOT EXISTS in BigQuery)
-- 4. Pre-cast terminal_id to avoid repeated casting

WITH

-- Single scan of 30-second data with quality metrics computed via window function
sspc_30s_with_quality AS (
    SELECT
        timestamp,
        sspc_name,
        sspc_id,
        CAST(terminal_id AS INT64) AS terminal_id,
        terminal_name,

        -- All metrics
        sspc_ds_allocated_bw_bytes,
        sspc_ds_allocated_bw_kbps,
        sspc_ds_cir_demand_bytes,
        sspc_ds_cir_fulfillment,
        sspc_ds_cir_fulfillment_ratio,
        sspc_ds_cir_current,
        sspc_ds_mir_current,
        sspc_ds_mir_demand_bytes,
        sspc_ds_mir_demand_kbps,
        sspc_ds_mir_fulfillment,
        sspc_ds_mir_fulfillment_ratio,
        sspc_ds_usage,
        sspc_us_allocated_bw_bytes,
        sspc_us_allocated_bw_kbps,
        sspc_us_cir_demand_bytes,
        sspc_us_cir_fulfillment,
        sspc_us_cir_fulfillment_ratio,
        sspc_us_cir_current,
        sspc_us_mir_current,
        sspc_us_mir_demand_bytes,
        sspc_us_mir_demand_kbps,
        sspc_us_mir_fulfillment,
        sspc_us_mir_fulfillment_ratio,
        sspc_us_usage,

        DATE(timestamp) AS partition_date,

        -- Window function computes count per partition/sspc/terminal
        COUNT(*) OVER (
            PARTITION BY DATE(timestamp), sspc_id, CAST(terminal_id AS INT64)
        ) AS record_count

    FROM `inm-data-led-sales-dev`.`pdl_dal_30_seconds`.`sspc_stats`
    WHERE timestamp BETWEEN TIMESTAMP('2025-10-10') AND TIMESTAMP('2025-10-20 23:59:59')
),

-- High quality data with proper threshold
high_quality_data AS (
    SELECT
        timestamp,
        sspc_name,
        sspc_id AS sspc_obj_id,
        terminal_id AS terminal_obj_id,
        terminal_name,
        'gx_dal_sspc_stats_30_seconds' AS type,

        sspc_ds_allocated_bw_bytes AS sspc_downstream_allocated_bandwidth_in_bytes,
        sspc_ds_allocated_bw_kbps AS sspc_downstream_allocated_bandwidth_in_kbps,
        sspc_ds_cir_demand_bytes AS sspc_downstream_cir_demand_in_bytes,
        sspc_ds_cir_fulfillment AS sspc_downstream_cir_fulfillment,
        sspc_ds_cir_fulfillment_ratio AS sspc_downstream_cir_fulfillment_ratio,
        sspc_ds_cir_current AS sspc_downstream_current_cir,
        sspc_ds_mir_current AS sspc_downstream_current_mir,
        sspc_ds_mir_demand_bytes AS sspc_downstream_mir_demand_in_bytes,
        sspc_ds_mir_demand_kbps AS sspc_downstream_mir_demand_in_kbps,
        sspc_ds_mir_fulfillment AS sspc_downstream_mir_fulfillment,
        sspc_ds_mir_fulfillment_ratio AS sspc_downstream_mir_fulfillment_ratio,
        sspc_ds_usage AS sspc_total_downstream_usage,

        sspc_us_allocated_bw_bytes AS sspc_upstream_allocated_bandwidth_in_bytes,
        sspc_us_allocated_bw_kbps AS sspc_upstream_allocated_bandwidth_in_kbps,
        sspc_us_cir_demand_bytes AS sspc_upstream_cir_demand_in_bytes,
        sspc_us_cir_fulfillment AS sspc_upstream_cir_fulfillment,
        sspc_us_cir_fulfillment_ratio AS sspc_upstream_cir_fulfillment_ratio,
        sspc_us_cir_current AS sspc_upstream_current_cir,
        sspc_us_mir_current AS sspc_upstream_current_mir,
        sspc_us_mir_demand_bytes AS sspc_upstream_mir_demand_in_bytes,
        sspc_us_mir_demand_kbps AS sspc_upstream_mir_demand_in_kbps,
        sspc_us_mir_fulfillment AS sspc_upstream_mir_fulfillment,
        sspc_us_mir_fulfillment_ratio AS sspc_upstream_mir_fulfillment_ratio,
        sspc_us_usage AS sspc_total_upstream_usage,

        partition_date,
        record_count,
        ROUND(record_count / 2880.0, 3) AS quality_score

    FROM sspc_30s_with_quality
    WHERE record_count >= 2016
),

-- All daily data from gx_dal_sspc_stats
all_daily_data AS (
    SELECT
        d.timestamp,
        d.sspc_name,
        d.sspc_id AS sspc_obj_id,
        CAST(d.terminal_id AS INT64) AS terminal_obj_id,
        d.terminal_name,
        'gx_dal_sspc_stats' AS type,

        d.sspc_ds_allocated_bw_bytes AS sspc_downstream_allocated_bandwidth_in_bytes,
        d.sspc_ds_allocated_bw_kbps AS sspc_downstream_allocated_bandwidth_in_kbps,
        d.sspc_ds_cir_demand_bytes AS sspc_downstream_cir_demand_in_bytes,
        d.sspc_ds_cir_fulfillment AS sspc_downstream_cir_fulfillment,
        d.sspc_ds_cir_fulfillment_ratio AS sspc_downstream_cir_fulfillment_ratio,
        d.sspc_ds_cir_current AS sspc_downstream_current_cir,
        d.sspc_ds_mir_current AS sspc_downstream_current_mir,
        d.sspc_ds_mir_demand_bytes AS sspc_downstream_mir_demand_in_bytes,
        d.sspc_ds_mir_demand_kbps AS sspc_downstream_mir_demand_in_kbps,
        d.sspc_ds_mir_fulfillment AS sspc_downstream_mir_fulfillment,
        d.sspc_ds_mir_fulfillment_ratio AS sspc_downstream_mir_fulfillment_ratio,
        d.sspc_ds_usage AS sspc_total_downstream_usage,

        d.sspc_us_allocated_bw_bytes AS sspc_upstream_allocated_bandwidth_in_bytes,
        d.sspc_us_allocated_bw_kbps AS sspc_upstream_allocated_bandwidth_in_kbps,
        d.sspc_us_cir_demand_bytes AS sspc_upstream_cir_demand_in_bytes,
        d.sspc_us_cir_fulfillment AS sspc_upstream_cir_fulfillment,
        d.sspc_us_cir_fulfillment_ratio AS sspc_upstream_cir_fulfillment_ratio,
        d.sspc_us_cir_current AS sspc_upstream_current_cir,
        d.sspc_us_mir_current AS sspc_upstream_current_mir,
        d.sspc_us_mir_demand_bytes AS sspc_upstream_mir_demand_in_bytes,
        d.sspc_us_mir_demand_kbps AS sspc_upstream_mir_demand_in_kbps,
        d.sspc_us_mir_fulfillment AS sspc_upstream_mir_fulfillment,
        d.sspc_us_mir_fulfillment_ratio AS sspc_upstream_mir_fulfillment_ratio,
        d.sspc_us_usage AS sspc_total_upstream_usage,

        DATE(d.timestamp) AS partition_date,
        0 AS record_count,
        0.0 AS quality_score

    FROM `inm-data-led-sales-dev`.`pdl_dal`.`gx_dal_sspc_stats` d
    WHERE d.timestamp BETWEEN TIMESTAMP('2025-10-10') AND TIMESTAMP('2025-10-20 23:59:59')
),

-- Keys that are in high quality dataset
high_quality_keys AS (
    SELECT DISTINCT
        partition_date,
        sspc_obj_id,
        terminal_obj_id
    FROM high_quality_data
),

-- Keys from daily data
all_daily_keys AS (
    SELECT DISTINCT
        partition_date,
        sspc_obj_id,
        terminal_obj_id
    FROM all_daily_data
),

-- Anti-join using EXCEPT DISTINCT (often more efficient in BigQuery)
fallback_keys AS (
    SELECT * FROM all_daily_keys
    EXCEPT DISTINCT
    SELECT * FROM high_quality_keys
),

-- Fallback data joined with excluded keys
fallback_data AS (
    SELECT d.*
    FROM all_daily_data d
    INNER JOIN fallback_keys fk
        ON d.partition_date = fk.partition_date
        AND d.sspc_obj_id = fk.sspc_obj_id
        AND d.terminal_obj_id = fk.terminal_obj_id
)

-- Final union
SELECT * FROM high_quality_data
UNION ALL
SELECT * FROM fallback_data;
