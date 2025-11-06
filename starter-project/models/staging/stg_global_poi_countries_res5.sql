{{
    config(
        materialized='view'
    )
}}

-- Staging model for global POI countries at H3 resolution 5
-- This aggregates from res7 using H3 parent cells
-- Or should be connected to your actual source data if available at res5

SELECT
    h3.celltoParent(h3_index, 5) AS h3_index,
    name,
    is_country_border_hexagon
FROM {{ ref('stg_global_poi_countries_res7') }}
WHERE h3_index IS NOT NULL
