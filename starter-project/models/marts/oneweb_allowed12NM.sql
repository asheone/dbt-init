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
oneweb_allowed_res5_base AS (
    SELECT
        territorial_h3.h3_index,
        territorial_h3.geoname,
        territorial_h3.territory,
        territorial_h3.iso3
    FROM territorial_h3
        LEFT JOIN oneweb_allowed
            ON territorial_h3.geoname = oneweb_allowed.geoname
    WHERE oneweb_allowed.geoname IS NOT NULL
),

oneweb_allowed_res5 AS (
    SELECT
        h3_index,
        5 AS h3_resolution,
        geoname,
        territory,
        iso3,
        1 AS num_territories,
        100.0 AS territory_confidence_pct
    FROM oneweb_allowed_res5_base
),

-- Resolution 7: Expand res5 to children cells
oneweb_allowed_res7 AS (
    SELECT
        h3_index,
        7 AS h3_resolution,
        geoname,
        territory,
        iso3,
        1 AS num_territories,
        100.0 AS territory_confidence_pct
    FROM oneweb_allowed_res5_base, UNNEST(h3.celltoChildren(oneweb_allowed_res5_base.h3_index, 7)) AS h3_index
),

-- Resolution 3: Aggregate res5 to parent cells - take mode (most frequent territory)
oneweb_allowed_res3_counts AS (
    SELECT
        h3.celltoParent(h3_index, 3) AS h3_index,
        geoname,
        territory,
        iso3,
        COUNT(*) AS territory_count
    FROM oneweb_allowed_res5_base
    GROUP BY h3.celltoParent(h3_index, 3), geoname, territory, iso3
),

oneweb_allowed_res3 AS (
    SELECT
        h3_index,
        3 AS h3_resolution,
        geoname,
        territory,
        iso3,
        ROUND(territory_count * 100.0 / SUM(territory_count) OVER (PARTITION BY h3_index), 2) AS territory_confidence_pct,
        COUNT(*) OVER (PARTITION BY h3_index) AS num_territories
    FROM (
        SELECT
            h3_index,
            geoname,
            territory,
            iso3,
            territory_count,
            ROW_NUMBER() OVER (PARTITION BY h3_index ORDER BY territory_count DESC) AS rn
        FROM oneweb_allowed_res3_counts
    )
    WHERE rn = 1
),

-- Resolution 1: Aggregate res5 to parent cells - take mode (most frequent territory)
oneweb_allowed_res1_counts AS (
    SELECT
        h3.celltoParent(h3_index, 1) AS h3_index,
        geoname,
        territory,
        iso3,
        COUNT(*) AS territory_count
    FROM oneweb_allowed_res5_base
    GROUP BY h3.celltoParent(h3_index, 1), geoname, territory, iso3
),

oneweb_allowed_res1 AS (
    SELECT
        h3_index,
        1 AS h3_resolution,
        geoname,
        territory,
        iso3,
        ROUND(territory_count * 100.0 / SUM(territory_count) OVER (PARTITION BY h3_index), 2) AS territory_confidence_pct,
        COUNT(*) OVER (PARTITION BY h3_index) AS num_territories
    FROM (
        SELECT
            h3_index,
            geoname,
            territory,
            iso3,
            territory_count,
            ROW_NUMBER() OVER (PARTITION BY h3_index ORDER BY territory_count DESC) AS rn
        FROM oneweb_allowed_res1_counts
    )
    WHERE rn = 1
)

-- Combine all resolutions
SELECT
    h3_index,
    h3_resolution,
    geoname,
    territory,
    iso3,
    num_territories,
    territory_confidence_pct
FROM oneweb_allowed_res1

UNION ALL

SELECT
    h3_index,
    h3_resolution,
    geoname,
    territory,
    iso3,
    num_territories,
    territory_confidence_pct
FROM oneweb_allowed_res3

UNION ALL

SELECT
    h3_index,
    h3_resolution,
    geoname,
    territory,
    iso3,
    num_territories,
    territory_confidence_pct
FROM oneweb_allowed_res5

UNION ALL

SELECT
    h3_index,
    h3_resolution,
    geoname,
    territory,
    iso3,
    num_territories,
    territory_confidence_pct
FROM oneweb_allowed_res7
