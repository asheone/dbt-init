{{
  config(
    materialized = 'view',
    tags = ['source','view', 'composite'],
    event_time = 'timestamp'
  )
}}

/*
  Composite SSPC Stats Model with Intelligent Fallback

  Logic:
  - Primary: Use 30-second data for daily stats when quality is sufficient
  - Fallback: Use 300-second data when 30-second data has coverage issues

  Quality Criteria:
  - 30-second data should have ~2,880 records/day (86,400 sec / 30)
  - Threshold: >= 2,016 records/day (70% of expected)
*/

with data_30sec as (
    select
        timestamp,
        sspc_name,
        sspc_id as sspc_obj_id,
        cast(terminal_id as int64) as terminal_obj_id,  -- Standardize type
        terminal_name,
        'gx_dal_sspc_stats_30_seconds' as type,
        sspc_ds_allocated_bw_bytes as sspc_downstream_allocated_bandwidth_in_bytes,
        sspc_ds_cir_demand_bytes as sspc_downstream_cir_demand_in_bytes,
        sspc_ds_cir_fulfillment as sspc_downstream_cir_fulfillment,
        sspc_ds_cir_current as sspc_downstream_current_cir,
        sspc_ds_mir_current as sspc_downstream_current_mir,
        sspc_ds_mir_demand_bytes as sspc_downstream_mir_demand_in_bytes,
        sspc_ds_usage as sspc_total_downstream_usage,
        sspc_us_usage as sspc_total_upstream_usage,
        sspc_us_allocated_bw_bytes as sspc_upstream_allocated_bandwidth_in_bytes,
        sspc_us_cir_demand_bytes as sspc_upstream_cir_demand_in_bytes,
        sspc_us_cir_fulfillment as sspc_upstream_cir_fulfillment,
        sspc_ds_mir_fulfillment as sspc_downstream_mir_fulfillment,
        sspc_us_mir_fulfillment as sspc_upstream_mir_fulfillment,
        sspc_us_cir_current as sspc_upstream_current_cir,
        sspc_us_mir_current as sspc_upstream_current_mir,
        sspc_us_mir_demand_bytes as sspc_upstream_mir_demand_in_bytes,
        sspc_ds_mir_demand_kbps as sspc_downstream_mir_demand_in_kbps,
        sspc_us_mir_demand_kbps as sspc_upstream_mir_demand_in_kbps,
        sspc_ds_allocated_bw_kbps as sspc_downstream_allocated_bandwidth_in_kbps,
        sspc_us_allocated_bw_kbps as sspc_upstream_allocated_bandwidth_in_kbps,
        sspc_us_cir_fulfillment_ratio as sspc_upstream_cir_fulfillment_ratio,
        sspc_ds_cir_fulfillment_ratio as sspc_downstream_cir_fulfillment_ratio,
        sspc_us_mir_fulfillment_ratio as sspc_upstream_mir_fulfillment_ratio,
        sspc_ds_mir_fulfillment_ratio as sspc_downstream_mir_fulfillment_ratio,
        date(timestamp) as partition_date
    from {{ source('pdl_dal_30_seconds', 'sspc_stats') }}
),

data_300sec as (
    select
        timestamp,
        sspc_name,
        sspc_id as sspc_obj_id,
        cast(terminal_id as int64) as terminal_obj_id,  -- Already cast in original
        terminal_name,
        'gx_dal_sspc_stats' as type,
        sspc_ds_allocated_bw_bytes as sspc_downstream_allocated_bandwidth_in_bytes,
        sspc_ds_cir_demand_bytes as sspc_downstream_cir_demand_in_bytes,
        sspc_ds_cir_fulfillment as sspc_downstream_cir_fulfillment,
        sspc_ds_cir_current as sspc_downstream_current_cir,
        sspc_ds_mir_current as sspc_downstream_current_mir,
        sspc_ds_mir_demand_bytes as sspc_downstream_mir_demand_in_bytes,
        sspc_ds_usage as sspc_total_downstream_usage,
        sspc_us_usage as sspc_total_upstream_usage,
        sspc_us_allocated_bw_bytes as sspc_upstream_allocated_bandwidth_in_bytes,
        sspc_us_cir_demand_bytes as sspc_upstream_cir_demand_in_bytes,
        sspc_us_cir_fulfillment as sspc_upstream_cir_fulfillment,
        sspc_ds_mir_fulfillment as sspc_downstream_mir_fulfillment,
        sspc_us_mir_fulfillment as sspc_upstream_mir_fulfillment,
        sspc_us_cir_current as sspc_upstream_current_cir,
        sspc_us_mir_current as sspc_upstream_current_mir,
        sspc_us_mir_demand_bytes as sspc_upstream_mir_demand_in_bytes,
        sspc_ds_mir_demand_kbps as sspc_downstream_mir_demand_in_kbps,
        sspc_us_mir_demand_kbps as sspc_upstream_mir_demand_in_kbps,
        sspc_ds_allocated_bw_kbps as sspc_downstream_allocated_bandwidth_in_kbps,
        sspc_us_allocated_bw_kbps as sspc_upstream_allocated_bandwidth_in_kbps,
        sspc_us_cir_fulfillment_ratio as sspc_upstream_cir_fulfillment_ratio,
        sspc_ds_cir_fulfillment_ratio as sspc_downstream_cir_fulfillment_ratio,
        sspc_us_mir_fulfillment_ratio as sspc_upstream_mir_fulfillment_ratio,
        sspc_ds_mir_fulfillment_ratio as sspc_downstream_mir_fulfillment_ratio,
        date(timestamp) as partition_date
    from {{ source('pdl_dal', 'gx_dal_sspc_stats') }}
),

-- Calculate data quality metrics for 30-second data at daily granularity
data_quality_30sec as (
    select
        partition_date,
        sspc_obj_id,
        terminal_obj_id,
        count(*) as record_count,
        -- Expected: 2880 records per day for 30sec data
        -- Threshold: 70% = 2016 records (adjust as needed)
        case
            when count(*) >= 2016 then true
            else false
        end as is_quality_sufficient,
        -- Quality score for monitoring
        round(count(*) / 2880.0, 3) as quality_score
    from data_30sec
    group by
        partition_date,
        sspc_obj_id,
        terminal_obj_id
),

-- Determine which source to use per day/sspc/terminal
source_selection as (
    select
        partition_date,
        sspc_obj_id,
        terminal_obj_id,
        case
            when is_quality_sufficient then '30sec'
            else '300sec'
        end as selected_source,
        record_count as records_30sec,
        quality_score
    from data_quality_30sec

    union all

    -- For days/combinations that have NO 30sec data, default to 300sec
    select distinct
        d300.partition_date,
        d300.sspc_obj_id,
        d300.terminal_obj_id,
        '300sec' as selected_source,
        0 as records_30sec,
        0.0 as quality_score
    from data_300sec d300
    left join data_quality_30sec dq30
        on d300.partition_date = dq30.partition_date
        and d300.sspc_obj_id = dq30.sspc_obj_id
        and d300.terminal_obj_id = dq30.terminal_obj_id
    where dq30.partition_date is null
),

-- Deduplicate source_selection (prefer 30sec if both exist)
source_selection_final as (
    select
        partition_date,
        sspc_obj_id,
        terminal_obj_id,
        selected_source,
        records_30sec,
        quality_score
    from source_selection
    qualify row_number() over (
        partition by partition_date, sspc_obj_id, terminal_obj_id
        order by case when selected_source = '30sec' then 1 else 2 end
    ) = 1
),

-- Combine data based on selection
composite_data as (
    -- 30-second data where quality is sufficient
    select
        d30.*,
        ss.selected_source as data_source,
        ss.quality_score as data_quality_score
    from data_30sec d30
    inner join source_selection_final ss
        on d30.partition_date = ss.partition_date
        and d30.sspc_obj_id = ss.sspc_obj_id
        and d30.terminal_obj_id = ss.terminal_obj_id
    where ss.selected_source = '30sec'

    union all

    -- 300-second data where 30-second quality is insufficient
    select
        d300.*,
        ss.selected_source as data_source,
        ss.quality_score as data_quality_score
    from data_300sec d300
    inner join source_selection_final ss
        on d300.partition_date = ss.partition_date
        and d300.sspc_obj_id = ss.sspc_obj_id
        and d300.terminal_obj_id = ss.terminal_obj_id
    where ss.selected_source = '300sec'
)

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
    -- Metadata fields for transparency and monitoring
    data_source,
    data_quality_score
from composite_data
