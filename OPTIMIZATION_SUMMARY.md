# BigQuery SSPC Query Optimization Summary

## 🚨 Critical Issues Found in Original Query

### Execution Stats
- **Records Read**: 6,836,477,808 (6.8+ BILLION)
- **Duration**: 10 minutes 52 seconds
- **Slot Time**: 9+ hours
- **Records Written**: 3.5+ billion

---

## 🔴 Issue #1: BROKEN ANTI-JOIN (MOST CRITICAL!)

### Problem
```sql
left join quality_lookup q
    on cast(d.terminal_id as int64) = q.terminal_id
    and d.sspc_id = q.sspc_id
    and date(d.timestamp) = q.partition_date
where date(d.timestamp) between '2025-10-10' and '2025-10-20'
    -- and q.partition_date is null  -- ❌ THIS IS COMMENTED OUT!
```

**Impact**: Without the `q.partition_date IS NULL` condition, you're getting **ALL records** from `gx_dal_sspc_stats`, not just fallback records. This means:
- No exclusion of high-quality records
- Massive duplicate data (all records appear in BOTH high_quality_data AND fallback_data)
- 3.5 billion records written instead of maybe a few million

### Solution
Use proper anti-join:
```sql
-- Option 1: NOT EXISTS (usually fastest)
WHERE NOT EXISTS (
    SELECT 1 FROM high_quality_keys hq
    WHERE hq.partition_date = DATE(d.timestamp)
        AND hq.sspc_obj_id = d.sspc_id
        AND hq.terminal_obj_id = CAST(d.terminal_id AS INT64)
)

-- Option 2: EXCEPT DISTINCT (also very efficient in BigQuery)
SELECT keys FROM all_daily_data
EXCEPT DISTINCT
SELECT keys FROM high_quality_data
```

---

## 🔴 Issue #2: DOUBLE TABLE SCAN

### Problem
The `pdl_dal_30_seconds.sspc_stats` table is scanned **TWICE**:
1. Once in `quality_lookup` CTE
2. Again in `high_quality_data` CTE

With 6.8 billion records, this is extremely expensive.

### Solution
Use a **window function** to compute quality metrics in a single pass:

```sql
WITH sspc_30s_with_quality AS (
    SELECT
        *,
        COUNT(*) OVER (
            PARTITION BY DATE(timestamp), sspc_id, CAST(terminal_id AS INT64)
        ) AS record_count
    FROM `inm-data-led-sales-dev`.`pdl_dal_30_seconds`.`sspc_stats`
    WHERE timestamp BETWEEN TIMESTAMP('2025-10-10') AND TIMESTAMP('2025-10-20 23:59:59')
)
-- Now just filter: WHERE record_count >= 2016
```

**Impact**: Reduces table scans from 2 to 1 = **~50% reduction in I/O**

---

## 🔴 Issue #3: PARTITION PRUNING FAILURE

### Problem
```sql
WHERE date(timestamp) between '2025-10-10' and '2025-10-20'
```

Using a **function** on the partition column prevents BigQuery from efficiently pruning partitions.

### Solution
Use direct timestamp comparison:
```sql
WHERE timestamp BETWEEN TIMESTAMP('2025-10-10') AND TIMESTAMP('2025-10-20 23:59:59')
```

Or if table uses `_PARTITIONTIME` pseudo-column:
```sql
WHERE _PARTITIONTIME BETWEEN TIMESTAMP('2025-10-10') AND TIMESTAMP('2025-10-20')
```

**Impact**: Enables partition pruning, potentially reducing scan from entire table to just 11 days of data.

---

## 🔴 Issue #4: EXPENSIVE CASTS IN JOIN CONDITIONS

### Problem
```sql
on cast(d.terminal_id as int64) = q.terminal_id  -- ❌ Cast executed billions of times
```

### Solution
Cast **once** in the CTE:
```sql
WITH prepared_data AS (
    SELECT
        CAST(terminal_id AS INT64) AS terminal_id,  -- ✅ Cast once
        ...
    FROM table
)
-- Now joins use pre-cast column
```

**Impact**: Eliminates billions of redundant cast operations.

---

## 📊 Optimization Comparison

| Metric | Original | Optimized (Est.) | Improvement |
|--------|----------|------------------|-------------|
| Table Scans (30s) | 2 | 1 | 50% reduction |
| Anti-join | Broken | Fixed | Correctness |
| Partition Pruning | No | Yes | 90%+ scan reduction |
| Cast Operations | Billions | Thousands | 99.9%+ reduction |
| Expected Runtime | 10+ min | <1 min | 90%+ faster |
| Slot Time | 9+ hours | <30 min | 95%+ reduction |

---

## 🎯 Recommended Optimizations (Priority Order)

### 1. **FIX THE ANTI-JOIN IMMEDIATELY** ⚠️
Your query is currently returning incorrect results (duplicates). This is a data correctness issue.

### 2. **Use Timestamp Filter for Partition Pruning**
Change `date(timestamp)` to direct timestamp comparison.

### 3. **Eliminate Double Scan with Window Function**
Compute quality metrics in a single pass.

### 4. **Pre-cast Terminal IDs**
Do it once in CTEs, not in every join.

---

## 📁 Provided Solutions

### `optimized_sspc_query.sql`
- Uses **NOT EXISTS** for anti-join
- Single table scan with window function
- Proper partition filtering
- Pre-cast terminal_id

### `optimized_sspc_query_v2_except.sql`
- Uses **EXCEPT DISTINCT** for anti-join (alternative approach)
- May be faster for certain data distributions
- Same other optimizations

---

## 🧪 Testing Recommendations

1. **Test with EXPLAIN/QUERY PLAN first**
   ```sql
   -- Dry run to see execution plan
   -- Add to beginning of query in BigQuery UI
   ```

2. **Test with smaller date range first**
   ```sql
   WHERE timestamp BETWEEN TIMESTAMP('2025-10-10') AND TIMESTAMP('2025-10-11')
   ```

3. **Verify row counts match expected values**
   - high_quality_data should have records with count >= 2016
   - fallback_data should have NO overlap with high_quality
   - Total should equal unique records in both source tables

4. **Monitor these metrics**:
   - Bytes scanned (should be <10% of original)
   - Slot time (should be <10% of original)
   - Records written (should match actual unique records, not 3.5B!)

---

## 💡 Additional Optimization Ideas

### If Tables Support It:
1. **Use _PARTITIONTIME** if tables are partitioned:
   ```sql
   WHERE _PARTITIONTIME BETWEEN ...
   ```

2. **Check table clustering**: If tables are clustered by `sspc_id` or `terminal_id`, ensure queries leverage that.

3. **Consider materialization**: If this is run frequently, materialize intermediate results:
   ```sql
   CREATE TEMP TABLE quality_keys AS ...
   ```

### Query Structure:
4. **Filter early, join late**: Apply all filters before joins

5. **Reduce SELECT columns**: Only select columns you actually need

---

## 🎓 Key BigQuery Best Practices Applied

✅ Avoid functions on partition columns
✅ Use window functions instead of multiple scans
✅ Pre-compute expensive operations (CAST)
✅ Use NOT EXISTS or EXCEPT for anti-joins, not LEFT JOIN with IS NULL
✅ Filter on timestamp directly for partition pruning
✅ Use explicit timestamp ranges

---

## Summary

The original query has **critical bugs** (broken anti-join) and **severe performance issues** (multiple scans, no partition pruning). The optimized versions should:

- **Return correct results** (no duplicates)
- **Run 10-20x faster** (seconds to minutes instead of 10+ minutes)
- **Use 90%+ less compute** (reduce slot time from 9 hours to <30 minutes)
- **Scan 90%+ less data** (hundreds of millions instead of billions)

**Start with the optimized version and test with a small date range first!**
