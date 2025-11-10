{{
  config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='timestamp',
    begin='2024-01-01',  -- Covers full history (300sec starts from 2024-01-01)
    batch_size='day',
    full_refresh = false,
    tags = ['incremental', 'fx_incremental', 'composite'],
    unique_key = 'sspc_primary_key',
    partition_by = {'field':'partition_date','data_type':'date', 'granularity':'day'},
    on_schema_change = "fail"
  )
}}

/*
  Composite SSPC Stats Streams - Intermediate Model

  Data Source: stg_pdl_dal__gx_sspc_stats_composite
  - Automatically uses 30-second data when quality is sufficient
  - Falls back to 300-second data when necessary

  This model replaces:
  - int_stats_streams_30sec (30-second specific)
  - int_stats_stream (300-second specific)

  Key Features:
  - Single source of truth for SSPC statistics
  - Maintains data_source field for transparency
  - Compatible with existing downstream models
*/

with sspc_stats as (
    select
        timestamp,
        sspc_name,
        sspc_obj_id,
        terminal_obj_id,
        terminal_name,
        type,
        data_source,
        data_quality_score,
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
        sspc_upstream_mir_fulfillment_ratio,
        sspc_downstream_cir_fulfillment_ratio,
        sspc_downstream_mir_fulfillment_ratio
    from {{ ref('stg_pdl_dal__gx_sspc_stats_composite') }}
    where contains_substr(sspc_name, '-DAT-')
),

terminal_status as (
    select
        timestamp,
        safe_cast(terminal_did as integer) as terminal_obj_id,
        terminal_name,
        terminal_type,
        beam as terminal_beam,
        inet as terminal_inet,
        terminal_type as terminal_rftype
    from {{ ref('stg_pdl_dal__gx_terminal_status') }}
),

joining_tables as (
    select
        sspc_stats.timestamp,
        sspc_stats.sspc_name,
        sspc_stats.sspc_obj_id,
        sspc_stats.terminal_obj_id,
        sspc_stats.terminal_name,
        sspc_stats.type,
        sspc_stats.data_source,
        sspc_stats.data_quality_score,
        cast(null as string) as commercial,
        'composite' as location,  -- Changed from 'mrtg' to indicate composite source
        terminal_status.terminal_type,
        terminal_status.terminal_beam,
        terminal_status.terminal_inet,
        terminal_status.terminal_rftype,
        sum(sspc_stats.sspc_total_downstream_usage) as sspc_total_downstream_usage,
        sum(sspc_stats.sspc_total_upstream_usage) as sspc_total_upstream_usage,
        sum(sspc_stats.sspc_upstream_cir_demand_in_bytes) as sspc_upstream_cir_demand_in_bytes,
        sum(sspc_stats.sspc_downstream_mir_demand_in_kbps) as sspc_downstream_mir_demand_in_kbps,
        sum(sspc_stats.sspc_upstream_mir_demand_in_kbps) as sspc_upstream_mir_demand_in_kbps,
        sum(sspc_stats.sspc_downstream_allocated_bandwidth_in_bytes)
            as sspc_downstream_allocated_bandwidth_in_bytes,
        sum(sspc_stats.sspc_downstream_cir_demand_in_bytes) as sspc_downstream_cir_demand_in_bytes,
        avg(sspc_stats.sspc_downstream_cir_fulfillment) as sspc_downstream_cir_fulfillment,
        avg(sspc_stats.sspc_downstream_mir_fulfillment) as sspc_downstream_mir_fulfillment,
        avg(sspc_stats.sspc_upstream_mir_fulfillment) as sspc_upstream_mir_fulfillment,
        avg(sspc_stats.sspc_downstream_current_cir) as sspc_downstream_current_cir,
        avg(sspc_stats.sspc_downstream_current_mir) as sspc_downstream_current_mir,
        avg(sspc_stats.sspc_upstream_current_cir) as sspc_upstream_current_cir,
        avg(sspc_stats.sspc_upstream_current_mir) as sspc_upstream_current_mir,
        sum(sspc_stats.sspc_downstream_mir_demand_in_bytes) as sspc_downstream_mir_demand_in_bytes,
        sum(sspc_stats.sspc_upstream_allocated_bandwidth_in_bytes)
            as sspc_upstream_allocated_bandwidth_in_bytes,
        sum(sspc_stats.sspc_upstream_mir_demand_in_bytes) as sspc_upstream_mir_demand_in_bytes,
        sum(sspc_stats.sspc_downstream_allocated_bandwidth_in_kbps)
            as sspc_downstream_allocated_bandwidth_in_kbps,
        sum(sspc_stats.sspc_upstream_allocated_bandwidth_in_kbps)
            as sspc_upstream_allocated_bandwidth_in_kbps,
        avg(sspc_stats.sspc_upstream_cir_fulfillment) as sspc_upstream_cir_fulfillment,
        avg(sspc_stats.sspc_downstream_mir_fulfillment_ratio) as sspc_downstream_mir_fulfillment_ratio,
        avg(sspc_stats.sspc_upstream_mir_fulfillment_ratio) as sspc_upstream_mir_fulfillment_ratio,
        avg(sspc_stats.sspc_downstream_cir_fulfillment_ratio) as sspc_downstream_cir_fulfillment_ratio,
        avg(sspc_stats.sspc_upstream_cir_fulfillment_ratio) as sspc_upstream_cir_fulfillment_ratio
    from sspc_stats
    left join terminal_status
        on sspc_stats.terminal_obj_id = terminal_status.terminal_obj_id
        and sspc_stats.timestamp = terminal_status.timestamp
    group by all
)

select
    *,
    {{dbt_utils.generate_surrogate_key([
        'timestamp',
        'sspc_name',
        'sspc_obj_id',
        'terminal_obj_id'
    ])}} as sspc_primary_key,
    date(timestamp) as partition_date
from joining_tables
