{{
  config(
    materialized='incremental',
    partition_by={
      "field": "partition_date",
      "data_type": "date",
      "granularity": "day"
    },
    cluster_by=["sspc_obj_id", "terminal_obj_id"],
    incremental_strategy='insert_overwrite',
    on_schema_change='sync_all_columns',
    tags=["daily", "composite", "optimized"]
  )
}}

/*
  Production-Ready Optimized Composite SSPC Stats Model

  FEATURES:
  - Incremental loading with partition overwrite strategy
  - Clustered on join keys for efficient querying
  - Parameterized date ranges for flexibility
  - All BigQuery optimizations applied

  USAGE:
  - Full refresh: dbt run --models sspc_stats_composite_optimized_dbt --full-refresh
  - Incremental: dbt run --models sspc_stats_composite_optimized_dbt --vars '{"start_date": "2025-10-10", "end_date": "2025-10-20"}'
*/

-- Set date range: use vars if provided, otherwise default to last 7 days
{% set start_date = var('start_date', (modules.datetime.date.today() - modules.datetime.timedelta(days=7)).strftime('%Y-%m-%d')) %}
{% set end_date = var('end_date', modules.datetime.date.today().strftime('%Y-%m-%d')) %}

-- Step 1: Calculate quality metrics with minimal column scanning
with quality_metrics as (
    select
        date(timestamp) as partition_date,
        sspc_id as sspc_obj_id,
        cast(terminal_id as int64) as terminal_obj_id,
        count(*) as record_count_30sec,
        count(*) >= 2016 as is_quality_sufficient,
        round(count(*) / 2880.0, 3) as quality_score
    from `inm-data-led-sales-dev`.`pdl_dal_30_seconds`.`sspc_stats`
    where _PARTITIONDATE between '{{ start_date }}' and '{{ end_date }}'
    {% if is_incremental() %}
        and date(timestamp) > (select max(partition_date) from {{ this }})
    {% endif %}
    group by 1, 2, 3
),

-- Step 2: Identify day/sspc/terminal combinations that exist in 300sec but not in 30sec
only_in_300sec as (
    select distinct
        date(timestamp) as partition_date,
        sspc_id as sspc_obj_id,
        cast(terminal_id as int64) as terminal_obj_id
    from `inm-data-led-sales-dev`.`pdl_dal`.`gx_dal_sspc_stats`
    where _PARTITIONDATE between '{{ start_date }}' and '{{ end_date }}'
    {% if is_incremental() %}
        and date(timestamp) > (select max(partition_date) from {{ this }})
    {% endif %}

    except distinct

    select
        partition_date,
        sspc_obj_id,
        terminal_obj_id
    from quality_metrics
),

-- Step 3: Unified source selection
source_selection as (
    -- From 30sec data (with quality check)
    select
        partition_date,
        sspc_obj_id,
        terminal_obj_id,
        case when is_quality_sufficient then '30sec' else '300sec' end as selected_source,
        record_count_30sec,
        quality_score
    from quality_metrics

    union all

    -- Only in 300sec data
    select
        partition_date,
        sspc_obj_id,
        terminal_obj_id,
        '300sec' as selected_source,
        0 as record_count_30sec,
        0.0 as quality_score
    from only_in_300sec
),

-- Step 4: Get 30sec data only when needed (quality sufficient)
data_30sec_filtered as (
    select
        d.timestamp,
        d.sspc_name,
        d.sspc_id as sspc_obj_id,
        cast(d.terminal_id as int64) as terminal_obj_id,
        d.terminal_name,
        'gx_dal_sspc_stats_30_seconds' as type,
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
        date(d.timestamp) as partition_date,
        ss.quality_score
    from `inm-data-led-sales-dev`.`pdl_dal_30_seconds`.`sspc_stats` d
    inner join source_selection ss
        on date(d.timestamp) = ss.partition_date
        and d.sspc_id = ss.sspc_obj_id
        and cast(d.terminal_id as int64) = ss.terminal_obj_id
        and ss.selected_source = '30sec'
    where d._PARTITIONDATE between '{{ start_date }}' and '{{ end_date }}'
    {% if is_incremental() %}
        and date(d.timestamp) > (select max(partition_date) from {{ this }})
    {% endif %}
),

-- Step 5: Get 300sec data only when needed
data_300sec_filtered as (
    select
        d.timestamp,
        d.sspc_name,
        d.sspc_id as sspc_obj_id,
        cast(d.terminal_id as int64) as terminal_obj_id,
        d.terminal_name,
        'gx_dal_sspc_stats' as type,
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
        date(d.timestamp) as partition_date,
        ss.quality_score
    from `inm-data-led-sales-dev`.`pdl_dal`.`gx_dal_sspc_stats` d
    inner join source_selection ss
        on date(d.timestamp) = ss.partition_date
        and d.sspc_id = ss.sspc_obj_id
        and cast(d.terminal_id as int64) = ss.terminal_obj_id
        and ss.selected_source = '300sec'
    where d._PARTITIONDATE between '{{ start_date }}' and '{{ end_date }}'
    {% if is_incremental() %}
        and date(d.timestamp) > (select max(partition_date) from {{ this }})
    {% endif %}
)

-- Step 6: Combine filtered datasets
select
    timestamp,
    sspc_name,
    sspc_obj_id,
    terminal_obj_id,
    terminal_name,
    type,
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
    -- Metadata fields
    type as data_source,
    quality_score as data_quality_score
from data_30sec_filtered

union all

select
    timestamp,
    sspc_name,
    sspc_obj_id,
    terminal_obj_id,
    terminal_name,
    type,
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
    -- Metadata fields
    type as data_source,
    quality_score as data_quality_score
from data_300sec_filtered
