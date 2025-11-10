{{
  config(
    materialized = 'view',
    tags = ['monitoring', 'data_quality']
  )
}}

/*
  Data Quality Monitoring for Composite SSPC Stats

  Purpose:
  - Track which data source (30sec vs 300sec) is being used
  - Identify patterns in data quality issues
  - Alert on chronic data quality problems

  Usage:
    SELECT * FROM monitor_sspc_data_quality
    WHERE partition_date >= CURRENT_DATE - 7
    AND fallback_rate > 0.2  -- More than 20% fallback
*/

with composite_data as (
    select
        partition_date,
        sspc_obj_id,
        sspc_name,
        terminal_obj_id,
        terminal_name,
        data_source,
        data_quality_score,
        count(*) as record_count
    from {{ ref('stg_pdl_dal__gx_sspc_stats_composite') }}
    group by
        partition_date,
        sspc_obj_id,
        sspc_name,
        terminal_obj_id,
        terminal_name,
        data_source,
        data_quality_score
),

daily_summary as (
    select
        partition_date,
        sspc_obj_id,
        sspc_name,
        terminal_obj_id,
        terminal_name,
        max(data_source) as data_source,
        max(data_quality_score) as data_quality_score_30sec,
        sum(record_count) as total_records,
        -- Expected records based on source
        case
            when max(data_source) = '30sec' then 2880
            when max(data_source) = '300sec' then 288
        end as expected_records
    from composite_data
    group by
        partition_date,
        sspc_obj_id,
        sspc_name,
        terminal_obj_id,
        terminal_name
),

enriched_summary as (
    select
        partition_date,
        sspc_obj_id,
        sspc_name,
        terminal_obj_id,
        terminal_name,
        data_source,
        data_quality_score_30sec,
        total_records,
        expected_records,
        round(total_records / nullif(expected_records, 0), 3) as completeness_ratio,
        case
            when data_source = '300sec' then true
            else false
        end as is_fallback,
        -- Calculate 7-day rolling averages
        avg(case when data_source = '300sec' then 1.0 else 0.0 end)
            over (
                partition by sspc_obj_id, terminal_obj_id
                order by partition_date
                rows between 6 preceding and current row
            ) as fallback_rate_7day,
        avg(data_quality_score_30sec)
            over (
                partition by sspc_obj_id, terminal_obj_id
                order by partition_date
                rows between 6 preceding and current row
            ) as avg_quality_score_7day
    from daily_summary
)

select
    partition_date,
    sspc_obj_id,
    sspc_name,
    terminal_obj_id,
    terminal_name,
    data_source,
    data_quality_score_30sec,
    total_records,
    expected_records,
    completeness_ratio,
    is_fallback,
    round(fallback_rate_7day, 3) as fallback_rate_7day,
    round(avg_quality_score_7day, 3) as avg_quality_score_7day,
    -- Flag chronic issues
    case
        when fallback_rate_7day > 0.3 then 'HIGH'
        when fallback_rate_7day > 0.15 then 'MEDIUM'
        when fallback_rate_7day > 0 then 'LOW'
        else 'NONE'
    end as data_quality_alert_level,
    -- Provide actionable message
    case
        when fallback_rate_7day > 0.3 then 'CRITICAL: 30sec data has chronic quality issues (>30% fallback)'
        when fallback_rate_7day > 0.15 then 'WARNING: 30sec data quality degraded (>15% fallback)'
        when fallback_rate_7day > 0 then 'INFO: Occasional fallback to 300sec data'
        else 'OK: Using 30sec data consistently'
    end as data_quality_message
from enriched_summary
order by
    partition_date desc,
    fallback_rate_7day desc,
    sspc_obj_id,
    terminal_obj_id
