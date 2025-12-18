{% macro scd_type2(
    source_name,
    source_table,
    business_key,
    timestamp_column='_ab_source_file_last_modified',
    exclude_columns=[],
    effective_start_date_column='effective_start_date',
    effective_end_date_column='effective_end_date',
    current_record_column='is_current_record',
    version_column='version_number'
) %}

{#- Airbyte metadata columns to always exclude -#}
{%- set airbyte_columns = [
    '_ab_source_file_last_modified',
    '_airbyte_raw_id',
    '_airbyte_extracted_at',
    '_airbyte_meta',
    '_airbyte_generation_id'
] -%}

{#- SCD tracking columns to exclude from source column detection -#}
{%- set tracking_columns = [
    effective_start_date_column,
    effective_end_date_column,
    current_record_column,
    version_column
] -%}

{#- Build complete exclusion list -#}
{%- set all_excluded_columns = airbyte_columns + tracking_columns + exclude_columns -%}

{#- Get source relation and columns from schema -#}
{%- set source_relation = source(source_name, source_table) -%}
{%- set source_columns = adapter.get_columns_in_relation(source_relation) -%}
{%- set column_names = source_columns | map(attribute='name') | list -%}

{#- Filter to business columns only -#}
{%- set business_columns = column_names | reject('in', all_excluded_columns) | list -%}

{#- Hash columns are business columns minus the business key -#}
{%- set hash_columns = business_columns | reject('equalto', business_key) | list -%}

WITH source_data AS (
    SELECT
        {{ business_key }},
        {%- for col in hash_columns %}
        {{ col }},
        {%- endfor %}
        {{ dbt_utils.generate_surrogate_key(hash_columns) }} AS _row_hash,
        TIMESTAMP({{ timestamp_column }}) AS _loaded_at
    FROM {{ source_relation }}
),

{#- Deduplicate to get first occurrence of each unique version per business key -#}
unique_versions AS (
    SELECT
        {{ business_key }},
        {%- for col in hash_columns %}
        {{ col }},
        {%- endfor %}
        _row_hash,
        MIN(_loaded_at) AS _first_seen_at
    FROM source_data
    GROUP BY
        {{ business_key }},
        {%- for col in hash_columns %}
        {{ col }},
        {%- endfor %}
        _row_hash
),

{#- Order versions chronologically and calculate SCD metadata -#}
versioned AS (
    SELECT
        {{ business_key }},
        {%- for col in hash_columns %}
        {{ col }},
        {%- endfor %}
        _row_hash,
        _first_seen_at,
        ROW_NUMBER() OVER (
            PARTITION BY {{ business_key }}
            ORDER BY _first_seen_at ASC
        ) AS _version_num,
        LEAD(_first_seen_at) OVER (
            PARTITION BY {{ business_key }}
            ORDER BY _first_seen_at ASC
        ) AS _next_version_at
    FROM unique_versions
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key([business_key, '_version_num']) }} AS surrogate_key,
        {{ business_key }},
        {%- for col in hash_columns %}
        {{ col }},
        {%- endfor %}
        _first_seen_at AS {{ effective_start_date_column }},
        COALESCE(
            TIMESTAMP_SUB(_next_version_at, INTERVAL 1 MILLISECOND),
            TIMESTAMP('9999-12-31 23:59:59')
        ) AS {{ effective_end_date_column }},
        _next_version_at IS NULL AS {{ current_record_column }},
        _version_num AS {{ version_column }}
    FROM versioned
)

SELECT * FROM final

{% endmacro %}
