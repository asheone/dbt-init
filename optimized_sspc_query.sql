-- OPTIMIZED BigQuery SSPC Stats Query
-- Key optimizations:
-- 1. Single scan of 30-second table with pre-cast terminal_id
-- 2. Proper partition pruning using timestamp directly
-- 3. Fixed anti-join using NOT EXISTS (more efficient than LEFT JOIN + IS NULL)
-- 4. Window function to compute quality metrics in single pass

WITH

-- Single scan of 30-second data with all necessary computations
sspc_30s_prepared AS (
    SELECT
        timestamp,
        sspc_name,
        sspc_id,
        CAST(terminal_id AS INT64) AS terminal_id,  -- Cast once, not in joins
        terminal_name,

        -- Downstream metrics
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

        -- Upstream metrics
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

        -- Compute quality metrics in single pass using window function
        COUNT(*) OVER (
            PARTITION BY DATE(timestamp), sspc_id, CAST(terminal_id AS INT64)
        ) AS record_count

    FROM `inm-data-led-sales-dev`.`pdl_dal_30_seconds`.`sspc_stats`
    -- Use timestamp directly if table is partitioned on timestamp
    -- If using _PARTITIONTIME pseudo-column, replace with: WHERE _PARTITIONTIME BETWEEN...
    WHERE timestamp BETWEEN TIMESTAMP('2025-10-10') AND TIMESTAMP('2025-10-20 23:59:59')
),

-- High quality data (>= 70% of expected records)
high_quality_data AS (
    SELECT
        timestamp,
        sspc_name,
        sspc_id AS sspc_obj_id,
        terminal_id AS terminal_obj_id,
        terminal_name,
        'gx_dal_sspc_stats_30_seconds' AS type,

        -- Downstream metrics
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

        -- Upstream metrics
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

    FROM sspc_30s_prepared
    WHERE record_count >= 2016  -- Quality threshold filter
),

-- Create a lookup set of high-quality keys for efficient anti-join
high_quality_keys AS (
    SELECT DISTINCT
        partition_date,
        sspc_obj_id,
        terminal_obj_id
    FROM high_quality_data
),

-- Fallback data (only records NOT in high-quality set)
fallback_data AS (
    SELECT
        d.timestamp,
        d.sspc_name,
        d.sspc_id AS sspc_obj_id,
        CAST(d.terminal_id AS INT64) AS terminal_obj_id,
        d.terminal_name,
        'gx_dal_sspc_stats' AS type,

        -- Downstream metrics
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

        -- Upstream metrics
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
    WHERE
        -- Partition filter first
        d.timestamp BETWEEN TIMESTAMP('2025-10-10') AND TIMESTAMP('2025-10-20 23:59:59')
        -- Anti-join: exclude records that exist in high_quality_keys
        AND NOT EXISTS (
            SELECT 1
            FROM high_quality_keys hq
            WHERE hq.partition_date = DATE(d.timestamp)
                AND hq.sspc_obj_id = d.sspc_id
                AND hq.terminal_obj_id = CAST(d.terminal_id AS INT64)
        )
)

-- Final union (no overlap due to proper anti-join)
SELECT * FROM high_quality_data
UNION ALL
SELECT * FROM fallback_data;
