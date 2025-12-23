# SCD Type 2 Macro

A dbt macro for BigQuery that implements Slowly Changing Dimension Type 2 using an **all-columns change detection strategy** with **incremental support**.

## Overview

This macro automatically tracks historical changes to dimension records by:
- Detecting changes via content hashing of all business columns
- Creating versioned records with effective date ranges
- Maintaining a current record flag for easy querying
- Supporting both `source()` and `ref()` inputs
- Supporting incremental materialization for efficient updates

## Quick Start

### Table Materialization (Full Rebuild)

```sql
{{ config(materialized='table') }}

{{ scd_type2("accounts", "id", source_name="singleops") }}
```

### Incremental Materialization (Recommended)

```sql
{{ config(
    materialized='incremental',
    unique_key='surrogate_key',
    on_schema_change='sync_all_columns',
    post_hook="{{ scd_type2_close_records('id') }}"
) }}

{{ scd_type2("accounts", "id", source_name="singleops") }}
```

## Parameters

### scd_type2

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `table_name` | Yes | - | Source table or model name |
| `business_key` | Yes | - | Primary/unique key column for the entity |
| `source_name` | No | `none` | Source schema name. If provided, uses `source()`. If omitted, uses `ref()` |
| `timestamp_column` | No | `_ab_source_file_last_modified` | Column used to order record versions |
| `exclude_columns` | No | `[]` | Additional columns to exclude from change detection |
| `effective_start_date_column` | No | `effective_start_date` | Output column name for version start |
| `effective_end_date_column` | No | `effective_end_date` | Output column name for version end |
| `current_record_column` | No | `is_current_record` | Output column name for current flag |
| `version_column` | No | `version_number` | Output column name for version number |

### scd_type2_close_records (Post-Hook)

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `business_key` | Yes | - | Primary/unique key column (must match main macro) |
| `effective_start_date_column` | No | `effective_start_date` | Must match main macro |
| `effective_end_date_column` | No | `effective_end_date` | Must match main macro |
| `current_record_column` | No | `is_current_record` | Must match main macro |

## Output Columns

| Column | Type | Description |
|--------|------|-------------|
| `surrogate_key` | STRING | Unique key for each version (hash of business_key + version) |
| `{business_key}` | - | The business key column from source |
| `{business_columns}` | - | All tracked business columns |
| `_row_hash` | STRING | Hash of all business columns (used for change detection) |
| `effective_start_date` | TIMESTAMP | When this version became active |
| `effective_end_date` | TIMESTAMP | When this version was superseded (`9999-12-31` if current) |
| `is_current_record` | BOOLEAN | `TRUE` for the latest version |
| `version_number` | INT64 | Sequential version number starting at 1 |

## Excluded Columns

The following Airbyte metadata columns are **automatically excluded** from change detection:

- `_ab_source_file_last_modified`
- `_airbyte_raw_id`
- `_airbyte_extracted_at`
- `_airbyte_meta`
- `_airbyte_generation_id`

## How Incremental Mode Works

### First Run (Full Refresh)
1. Reads all records from source
2. Deduplicates by business_key + content hash
3. Assigns version numbers chronologically
4. Calculates effective dates for all versions

### Subsequent Runs (Incremental)
1. Compares source records against existing current records using `_row_hash`
2. Identifies new business keys and changed records
3. Inserts new versions with `is_current_record = TRUE`
4. Post-hook updates superseded records:
   - Sets `is_current_record = FALSE`
   - Sets `effective_end_date` to new version's start date minus 1ms

## Examples

### Basic Incremental (Source)

```sql
{{ config(
    materialized='incremental',
    unique_key='surrogate_key',
    on_schema_change='sync_all_columns',
    post_hook="{{ scd_type2_close_records('customer_id') }}"
) }}

{{ scd_type2("customers", "customer_id", source_name="crm") }}
```

### Incremental from Model (ref)

```sql
{{ config(
    materialized='incremental',
    unique_key='surrogate_key',
    on_schema_change='sync_all_columns',
    post_hook="{{ scd_type2_close_records('customer_id') }}"
) }}

{{ scd_type2("stg_customers", "customer_id") }}
```

### With Custom Column Names

```sql
{{ config(
    materialized='incremental',
    unique_key='surrogate_key',
    on_schema_change='sync_all_columns',
    post_hook="{{ scd_type2_close_records('id', 'valid_from', 'valid_to', 'is_active') }}"
) }}

{{ scd_type2(
    table_name="customers",
    business_key="id",
    source_name="crm",
    effective_start_date_column="valid_from",
    effective_end_date_column="valid_to",
    current_record_column="is_active",
    version_column="revision"
) }}
```

### Excluding Additional Columns

```sql
{{ config(
    materialized='incremental',
    unique_key='surrogate_key',
    on_schema_change='sync_all_columns',
    post_hook="{{ scd_type2_close_records('id') }}"
) }}

{{ scd_type2(
    table_name="customers",
    business_key="id",
    source_name="crm",
    exclude_columns=['internal_notes', 'sync_status', 'temp_field']
) }}
```

### Full Rebuild (No Incremental)

```sql
{{ config(materialized='table') }}

{{ scd_type2("customers", "customer_id", source_name="crm") }}
```

## Querying the Output

**Get current records only:**
```sql
SELECT * FROM {{ ref('dim_customers') }}
WHERE is_current_record = TRUE
```

**Get record as of a specific date:**
```sql
SELECT * FROM {{ ref('dim_customers') }}
WHERE effective_start_date <= TIMESTAMP('2024-06-15')
  AND effective_end_date > TIMESTAMP('2024-06-15')
```

**Get full history for a specific entity:**
```sql
SELECT * FROM {{ ref('dim_customers') }}
WHERE customer_id = '12345'
ORDER BY version_number
```

**Get records that changed in the last 7 days:**
```sql
SELECT * FROM {{ ref('dim_customers') }}
WHERE effective_start_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
```

## Requirements

- **dbt-utils package** - Uses `dbt_utils.generate_surrogate_key()`
- **BigQuery adapter** - Uses BigQuery-specific functions

Add to `packages.yml`:
```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
```

## Full Refresh

To force a full rebuild of the dimension table:

```bash
dbt run --select dim_customers --full-refresh
```

## Architecture

```
┌─────────────────┐
│  Source Table   │
│  (raw data)     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  scd_type2 macro                            │
│  ┌─────────────────────────────────────┐    │
│  │ Full Refresh:                       │    │
│  │ - Hash all columns                  │    │
│  │ - Dedupe by key + hash              │    │
│  │ - Assign versions chronologically   │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │ Incremental:                        │    │
│  │ - Compare hashes vs existing        │    │
│  │ - Insert new/changed records        │    │
│  └─────────────────────────────────────┘    │
└────────┬────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  scd_type2_close_records (post-hook)        │
│  - Update superseded records                │
│  - Set is_current = FALSE                   │
│  - Set effective_end_date                   │
└────────┬────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│  Dimension Table│
│  (SCD Type 2)   │
└─────────────────┘
```
