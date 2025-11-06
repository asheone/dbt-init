{{
    config(
        materialized='table',
        tags=['coverage', 'oneweb']
    )
}}

-- OneWeb physical coverage across multiple H3 resolutions (1, 3, 5, 7)
-- Aggregates coverage data with custom logic for resolution 1

WITH
-- Resolution 3: Base coverage data
oneweb_coverage_res3 AS (
    SELECT
        h3_index,
        3 AS h3_resolution,
        has_coverage
    FROM {{ ref('stg_oneweb_coverage_res3') }}
    WHERE h3_index IS NOT NULL
),

-- Resolution 5: Base coverage data
oneweb_coverage_res5 AS (
    SELECT
        h3_index,
        5 AS h3_resolution,
        has_coverage
    FROM {{ ref('stg_oneweb_coverage_res5') }}
    WHERE h3_index IS NOT NULL
),

-- Resolution 7: Base coverage data
oneweb_coverage_res7 AS (
    SELECT
        h3_index,
        7 AS h3_resolution,
        has_coverage
    FROM {{ ref('stg_oneweb_coverage_res7') }}
    WHERE h3_index IS NOT NULL
),

-- Resolution 1: Aggregate from res3 with custom logic
-- Logic: If all res3 cells are TRUE -> TRUE
--        If all res3 cells are FALSE -> FALSE
--        If mixed -> TRUE (default to TRUE)
oneweb_coverage_res1_agg AS (
    SELECT
        h3.celltoParent(h3_index, 1) AS h3_index,
        MIN(CAST(has_coverage AS INT)) AS min_coverage,
        MAX(CAST(has_coverage AS INT)) AS max_coverage,
        COUNT(*) AS num_res3_cells,
        SUM(CAST(has_coverage AS INT)) AS num_covered_cells
    FROM oneweb_coverage_res3
    GROUP BY h3.celltoParent(h3_index, 1)
),

oneweb_coverage_res1 AS (
    SELECT
        h3_index,
        1 AS h3_resolution,
        CASE
            -- All FALSE -> FALSE
            WHEN max_coverage = 0 THEN FALSE
            -- All TRUE or Mixed -> TRUE
            ELSE TRUE
        END AS has_coverage,
        num_res3_cells,
        num_covered_cells,
        ROUND(num_covered_cells * 100.0 / num_res3_cells, 2) AS coverage_pct
    FROM oneweb_coverage_res1_agg
)

-- Combine all resolutions
SELECT
    h3_index,
    h3_resolution,
    has_coverage,
    num_res3_cells,
    num_covered_cells,
    coverage_pct
FROM oneweb_coverage_res1

UNION ALL

SELECT
    h3_index,
    h3_resolution,
    has_coverage,
    NULL AS num_res3_cells,
    NULL AS num_covered_cells,
    NULL AS coverage_pct
FROM oneweb_coverage_res3

UNION ALL

SELECT
    h3_index,
    h3_resolution,
    has_coverage,
    NULL AS num_res3_cells,
    NULL AS num_covered_cells,
    NULL AS coverage_pct
FROM oneweb_coverage_res5

UNION ALL

SELECT
    h3_index,
    h3_resolution,
    has_coverage,
    NULL AS num_res3_cells,
    NULL AS num_covered_cells,
    NULL AS coverage_pct
FROM oneweb_coverage_res7
