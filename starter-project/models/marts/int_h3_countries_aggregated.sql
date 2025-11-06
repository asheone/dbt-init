{{
    config(
        materialized='table'
    )
}}

-- Aggregates country data across multiple H3 resolutions (1, 3, 5, 7)
-- Uses mode (most frequent country) to determine country assignment at coarser resolutions

-- Base res7 country data
WITH countries_res7_base AS (
    SELECT
        h3_index,
        name AS country_name,
        CAST(is_country_border_hexagon AS BOOLEAN) AS is_country_border
    FROM {{ ref('stg_global_poi_countries_res7') }}
    WHERE h3_index IS NOT NULL
),

-- Aggregate res7 to res5 - take mode (most frequent country)
countries_res5_counts AS (
    SELECT
        h3_index,
        name AS country_name,
        CAST(is_country_border_hexagon AS BOOLEAN) AS is_country_border,
        COUNT(*) AS country_count
    FROM {{ ref('stg_global_poi_countries_res5') }}
    GROUP BY 1,2,3
),

countries_res5_aggregated AS (
    SELECT
        h3_index,
        country_name,
        ROUND(country_count * 100.0 / SUM(country_count) OVER (PARTITION BY h3_index), 2) AS country_confidence_pct,
        is_country_border,
        COUNT(*) OVER (PARTITION BY h3_index) AS num_countries
    FROM (
        SELECT
            h3_index,
            country_name,
            is_country_border,
            country_count,
            ROW_NUMBER() OVER (PARTITION BY h3_index ORDER BY country_count DESC) AS rn
        FROM countries_res5_counts
    )
    WHERE rn = 1
),

-- Aggregate res7 to res3 - take mode
countries_res3_counts AS (
    SELECT
        h3.celltoParent(h3_index, 3) AS h3_index,
        country_name,
        COUNT(*) AS country_count
    FROM countries_res7_base
    GROUP BY h3.celltoParent(h3_index, 3), country_name
),

countries_res3_aggregated AS (
    SELECT
        h3_index,
        country_name,
        ROUND(country_count * 100.0 / SUM(country_count) OVER (PARTITION BY h3_index), 2) AS country_confidence_pct,
        COUNT(*) OVER (PARTITION BY h3_index) > 1 AS is_country_border,
        COUNT(*) OVER (PARTITION BY h3_index) AS num_countries
    FROM (
        SELECT
            h3_index,
            country_name,
            country_count,
            ROW_NUMBER() OVER (PARTITION BY h3_index ORDER BY country_count DESC) AS rn
        FROM countries_res3_counts
    )
    WHERE rn = 1
),

-- Aggregate res7 to res1 - take mode
countries_res1_counts AS (
    SELECT
        h3.celltoParent(h3_index, 1) AS h3_index,
        country_name,
        COUNT(*) AS country_count
    FROM countries_res7_base
    GROUP BY h3.celltoParent(h3_index, 1), country_name
),

countries_res1_aggregated AS (
    SELECT
        h3_index,
        country_name,
        ROUND(country_count * 100.0 / SUM(country_count) OVER (PARTITION BY h3_index), 2) AS country_confidence_pct,
        COUNT(*) OVER (PARTITION BY h3_index) > 1 AS is_country_border,
        COUNT(*) OVER (PARTITION BY h3_index) AS num_countries
    FROM (
        SELECT
            h3_index,
            country_name,
            country_count,
            ROW_NUMBER() OVER (PARTITION BY h3_index ORDER BY country_count DESC) AS rn
        FROM countries_res1_counts
    )
    WHERE rn = 1
)

-- Combine all resolutions into long format
SELECT
    h3_index,
    1 AS h3_resolution,
    country_name,
    is_country_border,
    num_countries,
    country_confidence_pct
FROM countries_res1_aggregated

UNION ALL

SELECT
    h3_index,
    3 AS h3_resolution,
    country_name,
    is_country_border,
    num_countries,
    country_confidence_pct
FROM countries_res3_aggregated

UNION ALL

SELECT
    h3_index,
    5 AS h3_resolution,
    country_name,
    is_country_border,
    num_countries,
    country_confidence_pct
FROM countries_res5_aggregated

UNION ALL

SELECT
    h3_index,
    7 AS h3_resolution,
    country_name,
    is_country_border,
    1 AS num_countries,
    100.0 AS country_confidence_pct
FROM countries_res7_base
