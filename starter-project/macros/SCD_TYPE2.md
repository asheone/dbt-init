# SCD Type 2 Macro

A dbt macro for BigQuery that implements Slowly Changing Dimension Type 2 using an **all-columns change detection strategy**.

## Overview

This macro automatically tracks historical changes to dimension records by:
- Detecting changes via content hashing of all business columns
- Creating versioned records with effective date ranges
- Maintaining a current record flag for easy querying

## Quick Start

```sql
{{ config(materialized='table') }}

{{ scd_type2("source_name", "table_name", "primary_key_column") }}
```

**Example:**
```sql
{{ config(materialized='table') }}

{{ scd_type2("singleops", "accounts", "id") }}
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `source_name` | Yes | - | Name of the source defined in `sources.yml` |
| `source_table` | Yes | - | Name of the source table |
| `business_key` | Yes | - | Primary/unique key column for the entity |
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

### Basic Usage
```sql
{{ config(materialized='table') }}

{{ scd_type2("crm", "customers", "customer_id") }}
```

### With Custom Timestamp Column
```sql
{{ config(materialized='table') }}

{{ scd_type2(
    source_name="crm",
    source_table="customers",
    business_key="customer_id",
    timestamp_column="updated_at"
) }}
```

### Excluding Additional Columns
```sql
{{ config(materialized='table') }}

{{ scd_type2(
    source_name="crm",
    source_table="customers",
    business_key="customer_id",
    exclude_columns=['internal_notes', 'sync_status']
) }}
```

### Custom Output Column Names
```sql
{{ config(materialized='table') }}

{{ scd_type2(
    source_name="crm",
    source_table="customers",
    business_key="customer_id",
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

1. **Source Data** - Reads all columns from the source, excluding metadata
2. **Hash Generation** - Creates a content hash of all business columns (except business key)
3. **Deduplication** - Groups by business key + hash, keeping the earliest occurrence
4. **Versioning** - Orders unique versions chronologically and assigns version numbers
5. **SCD Metadata** - Calculates effective dates and current record flags
