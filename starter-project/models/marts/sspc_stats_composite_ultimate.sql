/*
  ULTIMATE OPTIMIZED BigQuery SSPC Stats - Hash Join Strategy

  CRITICAL OPTIMIZATIONS:
  1. Materialized quality lookup table (broadcast join candidate)
  2. Direct INNER JOIN with proper join keys and clustering
  3. Parallel scans with push-down predicates
  4. Zero redundant data movement
  5. Optimized for BigQuery's distributed shuffle

  WHY THIS IS FASTER:
  - quality_check is TINY (days × sspc × terminal combos with good quality)
  - BigQuery will broadcast this small table to all workers
  - Main table scans happen in parallel with partition pruning
  - JOIN happens locally on each worker (no shuffle needed)
  - Simple UNION ALL at the end (no dedup, no extra logic)
*/

with
-- STEP 1: Build small lookup table of "good quality" combinations
-- This will be broadcast to all workers (should be < 10MB)
quality_check as (
    select
        date(timestamp) as partition_date,
        sspc_id,
        cast(terminal_id as int64) as terminal_id
    from `inm-data-led-sales-dev`.`pdl_dal_30_seconds`.`sspc_stats`
    where _PARTITIONDATE between '2025-10-10' and '2025-10-20'
    group by 1, 2, 3
    having count(*) >= 2016  -- Only sufficient quality
),

-- STEP 2: Scan 30sec table and INNER JOIN with quality check
-- JOIN will be broadcast (quality_check is small)
-- Partition pruning + early filtering = minimal data scanned
high_quality_30sec as (
    select
        d.timestamp,
        d.sspc_name,
        d.sspc_id as sspc_obj_id,
        cast(d.terminal_id as int64) as terminal_obj_id,
        d.terminal_name,
        d.sspc_ds_allocated_bw_bytes as sspc_downstream_allocated_bandwidth_in_bytes,
        d.sspc_ds_cir_demand_bytes as sspc_downstream_cir_demand_in_bytes,
        d.sspc_ds_cir_fulfillment as sspc_downstream_cir_fulfillment,
        d.sspc_ds_cir_current as sspc_downstream_current_cir,
        d.sspc_ds_mir_current as sspc_downstream_current_mir,
        d.sspc_ds_mir_demand_bytes as sspc_downstream_mir_demand_in_bytes,
        d.sspc_ds_usage as sspc_total_downstream_usage,
        d.sspc_us_usage as sspc_total_upstream_usage,
        d.sspc_us_allocated_bw_bytes as sspc_upstream_allocated_bandwidth_in_bytes,
        d.sspc_us_cir_demand_bytes as sspc_upstream_cir_demand_in_bytes,
        d.sspc_us_cir_fulfillment as sspc_upstream_cir_fulfillment,
        d.sspc_ds_mir_fulfillment as sspc_downstream_mir_fulfillment,
        d.sspc_us_mir_fulfillment as sspc_upstream_mir_fulfillment,
        d.sspc_us_cir_current as sspc_upstream_current_cir,
        d.sspc_us_mir_current as sspc_upstream_current_mir,
        d.sspc_us_mir_demand_bytes as sspc_upstream_mir_demand_in_bytes,
        d.sspc_ds_mir_demand_kbps as sspc_downstream_mir_demand_in_kbps,
        d.sspc_us_mir_demand_kbps as sspc_upstream_mir_demand_in_kbps,
        d.sspc_ds_allocated_bw_kbps as sspc_downstream_allocated_bandwidth_in_kbps,
        d.sspc_us_allocated_bw_kbps as sspc_upstream_allocated_bandwidth_in_kbps,
        d.sspc_us_cir_fulfillment_ratio as sspc_upstream_cir_fulfillment_ratio,
        d.sspc_ds_cir_fulfillment_ratio as sspc_downstream_cir_fulfillment_ratio,
        d.sspc_us_mir_fulfillment_ratio as sspc_upstream_mir_fulfillment_ratio,
        d.sspc_ds_mir_fulfillment_ratio as sspc_downstream_mir_fulfillment_ratio,
        date(d.timestamp) as partition_date
    from `inm-data-led-sales-dev`.`pdl_dal_30_seconds`.`sspc_stats` d
    inner join quality_check q
        on date(d.timestamp) = q.partition_date
        and d.sspc_id = q.sspc_id
        and cast(d.terminal_id as int64) = q.terminal_id
    where d._PARTITIONDATE between '2025-10-10' and '2025-10-20'
),

-- STEP 3: Scan 300sec table and LEFT JOIN with quality check
-- Only take records where quality check is NULL (= no good 30sec data)
fallback_300sec as (
    select
        d.timestamp,
        d.sspc_name,
        d.sspc_id as sspc_obj_id,
        cast(d.terminal_id as int64) as terminal_obj_id,
        d.terminal_name,
        d.sspc_ds_allocated_bw_bytes as sspc_downstream_allocated_bandwidth_in_bytes,
        d.sspc_ds_cir_demand_bytes as sspc_downstream_cir_demand_in_bytes,
        d.sspc_ds_cir_fulfillment as sspc_downstream_cir_fulfillment,
        d.sspc_ds_cir_current as sspc_downstream_current_cir,
        d.sspc_ds_mir_current as sspc_downstream_current_mir,
        d.sspc_ds_mir_demand_bytes as sspc_downstream_mir_demand_in_bytes,
        d.sspc_ds_usage as sspc_total_downstream_usage,
        d.sspc_us_usage as sspc_total_upstream_usage,
        d.sspc_us_allocated_bw_bytes as sspc_upstream_allocated_bandwidth_in_bytes,
        d.sspc_us_cir_demand_bytes as sspc_upstream_cir_demand_in_bytes,
        d.sspc_us_cir_fulfillment as sspc_upstream_cir_fulfillment,
        d.sspc_ds_mir_fulfillment as sspc_downstream_mir_fulfillment,
        d.sspc_us_mir_fulfillment as sspc_upstream_mir_fulfillment,
        d.sspc_us_cir_current as sspc_upstream_current_cir,
        d.sspc_us_mir_current as sspc_upstream_current_mir,
        d.sspc_us_mir_demand_bytes as sspc_upstream_mir_demand_in_bytes,
        d.sspc_ds_mir_demand_kbps as sspc_downstream_mir_demand_in_kbps,
        d.sspc_us_mir_demand_kbps as sspc_upstream_mir_demand_in_kbps,
        d.sspc_ds_allocated_bw_kbps as sspc_downstream_allocated_bandwidth_in_kbps,
        d.sspc_us_allocated_bw_kbps as sspc_upstream_allocated_bandwidth_in_kbps,
        d.sspc_us_cir_fulfillment_ratio as sspc_upstream_cir_fulfillment_ratio,
        d.sspc_ds_cir_fulfillment_ratio as sspc_downstream_cir_fulfillment_ratio,
        d.sspc_us_mir_fulfillment_ratio as sspc_upstream_mir_fulfillment_ratio,
        d.sspc_ds_mir_fulfillment_ratio as sspc_downstream_mir_fulfillment_ratio,
        date(d.timestamp) as partition_date
    from `inm-data-led-sales-dev`.`pdl_dal`.`gx_dal_sspc_stats` d
    left join quality_check q
        on date(d.timestamp) = q.partition_date
        and d.sspc_id = q.sspc_id
        and cast(d.terminal_id as int64) = q.terminal_id
    where d._PARTITIONDATE between '2025-10-10' and '2025-10-20'
        and q.partition_date is null  -- Anti-join: only records NOT in quality_check
)

-- STEP 4: Combine datasets (no overlap, no deduplication needed)
select
    timestamp,
    sspc_name,
    sspc_obj_id,
    terminal_obj_id,
    terminal_name,
    'gx_dal_sspc_stats_30_seconds' as type,
    sspc_downstream_allocated_bandwidth_in_bytes,
    sspc_downstream_cir_demand_in_bytes,
    sspc_downstream_cir_fulfillment,
    sspc_downstream_current_cir,
    sspc_downstream_current_mir,
    sspc_downstream_mir_demand_in_bytes,
    sspc_total_downstream_usage,
    sspc_total_upstream_usage,
    sspc_upstream_allocated_bandwidth_in_bytes,
    sspc_upstream_cir_demand_in_bytes,
    sspc_upstream_cir_fulfillment,
    sspc_downstream_mir_fulfillment,
    sspc_upstream_mir_fulfillment,
    sspc_upstream_current_cir,
    sspc_upstream_current_mir,
    sspc_upstream_mir_demand_in_bytes,
    sspc_downstream_mir_demand_in_kbps,
    sspc_upstream_mir_demand_in_kbps,
    sspc_downstream_allocated_bandwidth_in_kbps,
    sspc_upstream_allocated_bandwidth_in_kbps,
    sspc_upstream_cir_fulfillment_ratio,
    sspc_downstream_cir_fulfillment_ratio,
    sspc_upstream_mir_fulfillment_ratio,
    sspc_downstream_mir_fulfillment_ratio,
    partition_date,
    'gx_dal_sspc_stats_30_seconds' as data_source,
    1.0 as data_quality_score
from high_quality_30sec

union all

select
    timestamp,
    sspc_name,
    sspc_obj_id,
    terminal_obj_id,
    terminal_name,
    'gx_dal_sspc_stats' as type,
    sspc_downstream_allocated_bandwidth_in_bytes,
    sspc_downstream_cir_demand_in_bytes,
    sspc_downstream_cir_fulfillment,
    sspc_downstream_current_cir,
    sspc_downstream_current_mir,
    sspc_downstream_mir_demand_in_bytes,
    sspc_total_downstream_usage,
    sspc_total_upstream_usage,
    sspc_upstream_allocated_bandwidth_in_bytes,
    sspc_upstream_cir_demand_in_bytes,
    sspc_upstream_cir_fulfillment,
    sspc_downstream_mir_fulfillment,
    sspc_upstream_mir_fulfillment,
    sspc_upstream_current_cir,
    sspc_upstream_current_mir,
    sspc_upstream_mir_demand_in_bytes,
    sspc_downstream_mir_demand_in_kbps,
    sspc_upstream_mir_demand_in_kbps,
    sspc_downstream_allocated_bandwidth_in_kbps,
    sspc_upstream_allocated_bandwidth_in_kbps,
    sspc_upstream_cir_fulfillment_ratio,
    sspc_downstream_cir_fulfillment_ratio,
    sspc_upstream_mir_fulfillment_ratio,
    sspc_downstream_mir_fulfillment_ratio,
    partition_date,
    'gx_dal_sspc_stats' as data_source,
    0.0 as data_quality_score
from fallback_300sec
