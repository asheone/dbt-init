{% macro scd_type2(
    table_name,
    business_key,
    source_name=none,
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
    version_column,
    'surrogate_key',
    '_row_hash'
] -%}

{#- Build complete exclusion list -#}
{%- set all_excluded_columns = airbyte_columns + tracking_columns + exclude_columns -%}

{#- Get source relation: use source() if source_name provided, otherwise use ref() -#}
{%- set source_relation = source(source_name, table_name) if source_name else ref(table_name) -%}
{%- set source_columns = adapter.get_columns_in_relation(source_relation) -%}
{%- set column_names = source_columns | map(attribute='name') | list -%}

{#- Filter to business columns only -#}
{%- set business_columns = column_names | reject('in', all_excluded_columns) | list -%}

{#- Hash columns are business columns minus the business key -#}
{%- set hash_columns = business_columns | reject('equalto', business_key) | list -%}

{% if is_incremental() %}
{#- INCREMENTAL MODE: Only process new/changed records -#}

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

{#- Get latest hash per business key from source -#}
source_latest AS (
    SELECT
        {{ business_key }},
        {%- for col in hash_columns %}
        {{ col }},
        {%- endfor %}
        _row_hash,
        _loaded_at,
        ROW_NUMBER() OVER (
            PARTITION BY {{ business_key }}
            ORDER BY _loaded_at DESC
        ) AS _rn
    FROM source_data
),

source_current AS (
    SELECT
        {{ business_key }},
        {%- for col in hash_columns %}
        {{ col }},
        {%- endfor %}
        _row_hash,
        _loaded_at
    FROM source_latest
    WHERE _rn = 1
),

{#- Get current records from existing dimension -#}
existing_current AS (
    SELECT
        {{ business_key }},
        _row_hash,
        {{ version_column }}
    FROM {{ this }}
    WHERE {{ current_record_column }} = TRUE
),

{#- Find new or changed records -#}
changes AS (
    SELECT
        s.{{ business_key }},
        {%- for col in hash_columns %}
        s.{{ col }},
        {%- endfor %}
        s._row_hash,
        s._loaded_at,
        COALESCE(e.{{ version_column }}, 0) + 1 AS _new_version_num,
        CASE
            WHEN e.{{ business_key }} IS NULL THEN 'new'
            ELSE 'changed'
        END AS _change_type
    FROM source_current s
    LEFT JOIN existing_current e ON s.{{ business_key }} = e.{{ business_key }}
    WHERE e.{{ business_key }} IS NULL
       OR e._row_hash != s._row_hash
)

SELECT
    {{ dbt_utils.generate_surrogate_key([business_key, '_new_version_num']) }} AS surrogate_key,
    {{ business_key }},
    {%- for col in hash_columns %}
    {{ col }},
    {%- endfor %}
    _row_hash,
    _loaded_at AS {{ effective_start_date_column }},
    TIMESTAMP('9999-12-31 23:59:59') AS {{ effective_end_date_column }},
    TRUE AS {{ current_record_column }},
    _new_version_num AS {{ version_column }}
FROM changes

{% else %}
{#- FULL REFRESH MODE: Build complete SCD Type 2 from scratch -#}

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
)

SELECT
    {{ dbt_utils.generate_surrogate_key([business_key, '_version_num']) }} AS surrogate_key,
    {{ business_key }},
    {%- for col in hash_columns %}
    {{ col }},
    {%- endfor %}
    _row_hash,
    _first_seen_at AS {{ effective_start_date_column }},
    COALESCE(
        TIMESTAMP_SUB(_next_version_at, INTERVAL 1 MILLISECOND),
        TIMESTAMP('9999-12-31 23:59:59')
    ) AS {{ effective_end_date_column }},
    _next_version_at IS NULL AS {{ current_record_column }},
    _version_num AS {{ version_column }}
FROM versioned

{% endif %}
{% endmacro %}


{#- Post-hook macro to close out superseded records after incremental insert -#}
{% macro scd_type2_close_records(
    business_key,
    effective_start_date_column='effective_start_date',
    effective_end_date_column='effective_end_date',
    current_record_column='is_current_record'
) %}

UPDATE {{ this }} AS target
SET
    {{ current_record_column }} = FALSE,
    {{ effective_end_date_column }} = TIMESTAMP_SUB(new_records.{{ effective_start_date_column }}, INTERVAL 1 MILLISECOND)
FROM (
    SELECT {{ business_key }}, {{ effective_start_date_column }}
    FROM {{ this }}
    WHERE {{ current_record_column }} = TRUE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY {{ business_key }}
        ORDER BY {{ effective_start_date_column }} DESC
    ) = 1
) AS new_records
WHERE target.{{ business_key }} = new_records.{{ business_key }}
  AND target.{{ current_record_column }} = TRUE
  AND target.{{ effective_start_date_column }} < new_records.{{ effective_start_date_column }}

{% endmacro %}
