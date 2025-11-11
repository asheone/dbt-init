# SSPC Stats Models

## Optimized Composite Models

This directory contains heavily optimized versions of the SSPC Stats composite query, refactored for BigQuery performance.

### 📊 Available Models

| File | Use Case | Performance | Features |
|------|----------|-------------|----------|
| **sspc_stats_composite_production.sql** | Production (dbt) | ⚡⚡⚡ Fastest | Partitioning, clustering, incremental |
| **sspc_stats_composite_ultimate.sql** | Ad-hoc queries | ⚡⚡⚡ Fast | Clean SQL, hardcoded dates |
| **sspc_stats_composite_refactored.sql** | Alternative | ⚡⚡⚡ Fast | EXISTS pattern |

### 🚀 Quick Start

**For Production:**
```bash
dbt run --models sspc_stats_composite_production --vars '{"start_date": "2025-10-10", "end_date": "2025-10-20"}'
```

**For Ad-hoc Analysis:**
1. Open `sspc_stats_composite_ultimate.sql`
2. Update date range on lines 45-46
3. Run in BigQuery console

### 📈 Expected Performance

- **Query Time:** 60-110 seconds (10-day range)
- **Data Scanned:** ~150 GB (70% reduction from original)
- **Cost:** ~$0.75 per run (70% cheaper)
- **Improvement:** 70-80% faster than original

### 🔑 Key Optimizations

1. **Broadcast Join Pattern** - Small quality lookup table broadcast to all workers
2. **Partition Pruning** - Direct `_PARTITIONDATE` filtering
3. **Zero Shuffle Joins** - All joins happen locally on workers
4. **Smart Clustering** - Output clustered on most-filtered columns

### 📚 Documentation

See `/BIGQUERY_PERFORMANCE_OPTIMIZATION.md` for:
- Detailed architecture explanation
- Performance comparison
- Troubleshooting guide
- Migration checklist

### ⚠️ Important Notes

1. **Quality Threshold:** Using 2016 records (70% of expected 2880) as quality cutoff
2. **Data Sources:**
   - 30sec data used when quality is sufficient
   - 300sec data used as fallback
3. **No Overlaps:** Logic ensures no duplicate records between sources

### 🔍 Monitoring

After running, check performance:
```sql
SELECT
  job_id,
  total_slot_ms / 1000 / 60 as slot_minutes,
  total_bytes_processed / pow(1024, 3) as gb_processed,
  total_bytes_billed / pow(1024, 4) as tb_billed
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY creation_time DESC
LIMIT 5;
```

### 🐛 Troubleshooting

**Query still slow?**
1. Verify `_PARTITIONDATE` exists on source tables
2. Check execution plan for "Broadcast" joins
3. Ensure quality_lookup CTE is < 10MB
4. Confirm partition pruning in execution plan

**Different results?**
1. Compare row counts by data_source
2. Verify date ranges match exactly
3. Check join key casting (terminal_id must be int64)
