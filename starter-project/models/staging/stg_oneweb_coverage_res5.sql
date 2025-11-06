{{
    config(
        materialized='view'
    )
}}

-- Staging model for OneWeb physical coverage at H3 resolution 5
-- This should be connected to your actual source data

SELECT
    h3_index,
    CAST(has_coverage AS BOOLEAN) AS has_coverage
FROM {{ source('oneweb', 'coverage_res5') }}
WHERE h3_index IS NOT NULL
