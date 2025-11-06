{{
    config(
        materialized='view'
    )
}}

-- Staging model for global POI countries at H3 resolution 7
-- This should be connected to your actual source data

SELECT
    h3_index,
    name,
    is_country_border_hexagon
FROM {{ source('global_poi', 'countries_res7') }}
WHERE h3_index IS NOT NULL
