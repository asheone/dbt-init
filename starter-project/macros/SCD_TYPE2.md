# SCD Type 2 Macro

A dbt macro for BigQuery that implements Slowly Changing Dimension Type 2 using an **all-columns change detection strategy**.

## Overview

This macro automatically tracks historical changes to dimension records by:
- Detecting changes via content hashing of all business columns
- Creating versioned records with effective date ranges
- Maintaining a current record flag for easy querying
- Supporting both `source()` and `ref()` inputs

## Quick Start

**Using a source table:**
```sql
{{ config(materialized='table') }}

{{ scd_type2("accounts", "id", source_name="singleops") }}
```

**Using a ref (model):**
```sql
{{ config(materialized='table') }}

{{ scd_type2("stg_accounts", "id") }}
```

## Parameters

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

## Output Columns

The macro generates these columns in addition to your business columns:

| Column | Type | Description |
|--------|------|-------------|
| `surrogate_key` | STRING | Unique key for each version (hash of business_key + version) |
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

## Examples

### From Source Table
```sql
{{ config(materialized='table') }}

{{ scd_type2("customers", "customer_id", source_name="crm") }}
```

### From Model (ref)
```sql
{{ config(materialized='table') }}

{{ scd_type2("stg_customers", "customer_id") }}
```

### With Custom Timestamp Column
```sql
{{ config(materialized='table') }}

{{ scd_type2(
    table_name="customers",
    business_key="customer_id",
    source_name="crm",
    timestamp_column="updated_at"
) }}
```

### Excluding Additional Columns
```sql
{{ config(materialized='table') }}

{{ scd_type2(
    table_name="customers",
    business_key="customer_id",
    source_name="crm",
    exclude_columns=['internal_notes', 'sync_status']
) }}
```

### Custom Output Column Names
```sql
{{ config(materialized='table') }}

{{ scd_type2(
    table_name="customers",
    business_key="customer_id",
    source_name="crm",
    effective_start_date_column="valid_from",
    effective_end_date_column="valid_to",
    current_record_column="is_active",
    version_column="revision"
) }}
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

## Requirements

- **dbt-utils package** - Uses `dbt_utils.generate_surrogate_key()`
- **BigQuery adapter** - Uses BigQuery-specific functions (`TIMESTAMP_SUB`, `TIMESTAMP()`)

Add to `packages.yml`:
```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
```

## How It Works

1. **Source Resolution** - Uses `source()` if `source_name` provided, otherwise `ref()`
2. **Column Detection** - Reads all columns from schema, excluding metadata
3. **Hash Generation** - Creates a content hash of all business columns (except business key)
4. **Deduplication** - Groups by business key + hash, keeping the earliest occurrence
5. **Versioning** - Orders unique versions chronologically and assigns version numbers
6. **SCD Metadata** - Calculates effective dates and current record flags
