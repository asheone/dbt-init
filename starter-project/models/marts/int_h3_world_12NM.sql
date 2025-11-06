{{
    config(
        materialized='table'
    )
}}

-- Intermediate model for territorial waters (12 nautical miles)
-- Maps H3 hexagons to territories, countries, and ISO codes
-- This should be connected to your actual source data

SELECT
    h3_index,
    geoname,
    territory,
    iso3
FROM {{ source('territorial', 'h3_world_12nm') }}
WHERE h3_index IS NOT NULL
