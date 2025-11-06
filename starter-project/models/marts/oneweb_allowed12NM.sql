{{
    config(
        materialized='table'
    )
}}

-- OneWeb allowed territories across multiple H3 resolutions (1, 3, 5, 7)
-- Filters territorial waters to only include allowed regions

WITH territorial_h3 AS (
    SELECT *
    FROM {{ ref('int_h3_world_12NM') }}
),

oneweb_allowed AS (
    SELECT *
    FROM {{ source('oneweb', 'allowed_territories') }}
),

-- Resolution 5: Base resolution from territorial data
oneweb_allowed_res5 AS (
    SELECT
        territorial_h3.h3_index,
        5 AS h3_resolution,
        territorial_h3.geoname,
        territorial_h3.territory,
        territorial_h3.iso3
    FROM territorial_h3
        LEFT JOIN oneweb_allowed
            ON territorial_h3.geoname = oneweb_allowed.geoname
    WHERE oneweb_allowed.geoname IS NOT NULL
),

-- Resolution 7: Expand res5 to children cells
oneweb_allowed_res7 AS (
    SELECT
        h3_index,
        7 AS h3_resolution,
        geoname,
        territory,
        iso3
    FROM oneweb_allowed_res5, UNNEST(h3.celltoChildren(oneweb_allowed_res5.h3_index, 7)) AS h3_index
),

-- Resolution 3: Aggregate res5 to parent cells
oneweb_allowed_res3_raw AS (
    SELECT
        h3.celltoParent(h3_index, 3) AS h3_index,
        3 AS h3_resolution,
        geoname,
        territory,
        iso3
    FROM oneweb_allowed_res5
),

oneweb_allowed_res3 AS (
    SELECT DISTINCT
        h3_index,
        h3_resolution,
        geoname,
        territory,
        iso3
    FROM oneweb_allowed_res3_raw
),

-- Resolution 1: Aggregate res5 to parent cells
oneweb_allowed_res1_raw AS (
    SELECT
        h3.celltoParent(h3_index, 1) AS h3_index,
        1 AS h3_resolution,
        geoname,
        territory,
        iso3
    FROM oneweb_allowed_res5
),

oneweb_allowed_res1 AS (
    SELECT DISTINCT
        h3_index,
        h3_resolution,
        geoname,
        territory,
        iso3
    FROM oneweb_allowed_res1_raw
)

-- Combine all resolutions
SELECT
    h3_index,
    h3_resolution,
    geoname,
    territory,
    iso3
FROM oneweb_allowed_res1

UNION ALL

SELECT
    h3_index,
    h3_resolution,
    geoname,
    territory,
    iso3
FROM oneweb_allowed_res3

UNION ALL

SELECT
    h3_index,
    h3_resolution,
    geoname,
    territory,
    iso3
FROM oneweb_allowed_res5

UNION ALL

SELECT
    h3_index,
    h3_resolution,
    geoname,
    territory,
    iso3
FROM oneweb_allowed_res7
