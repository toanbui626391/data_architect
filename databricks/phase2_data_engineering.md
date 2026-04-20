# Phase 2: Data Engineering
*Databricks Data & Solution Architect Track*

***

## 2.1 Medallion Architecture

### What is the Medallion Architecture?

The Medallion Architecture (also called the "lakehouse architecture") is a data design pattern that organizes data into three progressive quality layers: **Bronze**, **Silver**, and **Gold**. Each layer builds on the previous one, increasing data quality, structure, and business value.

```
  Raw Sources
      │
      ▼
  ┌────────┐
  │ BRONZE │  Raw, as-is data
  └───┬────┘
      │ Cleanse & Conform
      ▼
  ┌────────┐
  │ SILVER │  Clean, typed data
  └───┬────┘
      │ Aggregate & Enrich
      ▼
  ┌────────┐
  │  GOLD  │  Business-ready data
  └────────┘
```

### Bronze Layer (Raw Zone)

**Purpose:** Land data exactly as it arrived from the source.

**Characteristics:**
* Data is stored as-is: no transformations, no filtering.
* Schema-on-read: minimal schema enforcement.
* Includes all metadata: source system, ingestion timestamp, filename, etc.
* Append-only: historical data is never deleted.
* Serves as the source of truth for re-processing.

**Common Sources:**
* Kafka / Kinesis event streams.
* Cloud file drops (CSV, JSON, Parquet, Avro).
* Database CDC (Debezium, Qlik, Fivetran).
* API calls and webhooks.

**Best Practices:**
* Always add a `_ingested_at` timestamp column.
* Store the raw source filename as a metadata column.
* Partition by ingestion date (e.g., `year/month/day`) for efficient pruning.
* Use `string` types for all fields when in doubt — enforce types in Silver.

```python
# Example: Bronze ingestion with Auto Loader
(spark.readStream
  .format("cloudFiles")
  .option("cloudFiles.format", "json")
  .option("cloudFiles.schemaLocation", "/schemas/orders_bronze")
  .load("s3://raw-data/orders/")
  .withColumn("_ingested_at", current_timestamp())
  .withColumn("_source_file", col("_metadata.file_path"))
  .writeStream
  .format("delta")
  .option("checkpointLocation", "/checkpoints/orders_bronze")
  .outputMode("append")
  .start("/data/bronze/orders")
)
```

### Silver Layer (Cleansed Zone)

**Purpose:** A single, clean, conformed version of each business entity.

**Characteristics:**
* Data is deduplicated, typed, and validated.
* Null handling and data quality rules applied.
* Relationships between entities are resolvable (foreign keys).
* Still relatively granular (row-level event data).
* Serves as the foundation for data modeling downstream.

**Typical Transformations:**
* Cast string columns to correct types (INT, DATE, BOOLEAN).
* Standardize values (e.g., "US", "U.S.", "usa" → "USA").
* Remove exact duplicates.
* Apply business keys to identify unique records.
* Handle late-arriving data and merge with upserts.

```python
# Example: Silver upsert from Bronze
from delta.tables import DeltaTable

silver = DeltaTable.forPath(spark, "/data/silver/orders")

silver.alias("target").merge(
  source=bronze_df.alias("source"),
  condition="target.order_id = source.order_id"
).whenMatchedUpdateAll() \
 .whenNotMatchedInsertAll() \
 .execute()
```

### Gold Layer (Business Zone)

**Purpose:** Pre-aggregated, business-aligned data ready for consumption.

**Characteristics:**
* Data is joined, aggregated, and enriched.
* Structured around business domains or use cases.
* Designed for BI tools, dashboards, and applications.
* Often denormalized for query performance.
* Lower row count; wider columns.

**Examples:**
* Daily revenue by product category.
* Customer lifetime value per segment.
* 7-day moving average of user activity.
* KPI scorecards for executive dashboards.

### Naming Conventions

Consistent naming prevents confusion across large organizations.

**Recommended Pattern:**
```
<catalog>.<layer>.<domain>_<entity>

Examples:
  prod.bronze.ecommerce_orders_raw
  prod.silver.ecommerce_orders
  prod.gold.ecommerce_revenue_daily
```

**Layer Prefixes:**
* bronze / brz
* silver / slv
* gold / gld

### Data Lifecycle Policies

| Layer | Retention | Format | Partitioning |
|---|---|---|---|
| Bronze | 90–365 days | Delta | By ingestion date |
| Silver | 1–3 years | Delta | By business date |
| Gold | indefinite | Delta | By reporting period |

**Architect Tip:** Bronze acts as a "replayable buffer." If a Silver pipeline has a bug, you can delete and re-derive Silver from Bronze without losing any source data.

***

## 2.2 Modern Data Ingestion

### Auto Loader

Auto Loader is Databricks' native solution for continuous, incremental ingestion of new files from cloud storage into Delta Lake.

**How it Works:**
1. Monitors a cloud storage directory for new files.
2. Uses cloud-native event notifications (S3 Events, Azure Event Grid) for efficiency. Does not scan the entire folder on each run.
3. Tracks which files have been processed using an internal checkpoint.
4. On restart, it only processes new files.

**Key Advantages vs. plain `spark.readStream`:**
* Handles millions of files without listing overhead.
* Automatic schema inference and schema evolution.
* Exactly-once processing guarantee via checkpointing.

**Core Options:**

| Option | Description |
|---|---|
| `cloudFiles.format` | Input file format (json, csv, parquet, avro) |
| `cloudFiles.schemaLocation` | Path to store inferred schema |
| `cloudFiles.useNotifications` | Use event-based notifications (recommended) |
| `cloudFiles.schemaEvolutionMode` | How to handle new columns (rescue, addNewColumns) |

**Schema Evolution with Auto Loader:**
```python
.option("cloudFiles.schemaEvolutionMode", "addNewColumns")
```
* `addNewColumns`: New columns are added to the table schema.
* `rescue`: Unknown columns go into a `_rescued_data` JSON column.
* `failOnNewColumns`: Job fails if new columns are detected (strictest).

### Delta Live Tables (DLT)

Delta Live Tables is a declarative framework for building reliable, maintainable data pipelines on Databricks.

Instead of writing imperative ETL code (`read → transform → write`), you **declare** what tables should contain and let DLT manage the rest.

**Core Concepts:**

**Declaring a Streaming Table (Bronze):**
```python
import dlt
from pyspark.sql.functions import current_timestamp, col

@dlt.table(
  name="orders_raw",
  comment="Raw orders from S3. Append-only.",
  table_properties={"quality": "bronze"}
)
def orders_raw():
  return (
    spark.readStream
      .format("cloudFiles")
      .option("cloudFiles.format", "json")
      .option("cloudFiles.schemaLocation", "/schemas/orders")
      .load("s3://raw/orders/")
      .withColumn("_ingested_at", current_timestamp())
  )
```

**Declaring a Materialized View (Silver):**
```python
@dlt.table(
  name="orders_clean",
  comment="Cleansed and typed orders.",
  table_properties={"quality": "silver"}
)
def orders_clean():
  return (
    dlt.read("orders_raw")
      .filter(col("order_id").isNotNull())
      .withColumn("amount", col("amount").cast("decimal(18,2)"))
  )
```

**DLT Pipeline Execution:**
DLT automatically:
* Infers dependencies between tables.
* Manages checkpoints and restarts.
* Handles schema evolution.
* Provides end-to-end pipeline observability.

### DLT Data Quality Expectations

`@dlt.expect` decorators let you define data quality rules inline with your table definitions.

```python
@dlt.table
@dlt.expect("valid_order_id", "order_id IS NOT NULL")
@dlt.expect_or_drop("positive_amount", "amount > 0")
@dlt.expect_or_fail("valid_status", "status IN ('active', 'closed', 'pending')")
def orders_clean():
  return dlt.read("orders_raw")
```

**Expectation Actions:**

| Decorator | On Violation |
|---|---|
| `@dlt.expect` | Records metric, allows row |
| `@dlt.expect_or_drop` | Silently drops the row |
| `@dlt.expect_or_fail` | Stops the pipeline with an error |

**Architect Tip:** Expectations are the DLT equivalent of database constraints. Use `expect_or_drop` in Silver to keep bad records out. Store dropped records by routing them to a "quarantine" table.

### Structured Streaming

Structured Streaming is Spark's scalable, fault-tolerant stream processing engine. It processes data as an unbounded, continuous DataFrame.

**Core Model:**
* Streaming data is treated as a table with new rows constantly being inserted.
* Spark processes data in micro-batches (or using Continuous Processing mode).

**Trigger Modes:**

| Trigger | Description | Use Case |
|---|---|---|
| `processingTime="0 seconds"` | Runs as fast as possible | Low-latency streaming |
| `processingTime="5 minutes"` | Fixed interval between batches | Near-real-time ETL |
| `once=True` | Runs exactly once, then stops | Scheduled batch on streaming source |
| `availableNow=True` | Processes all pending data, then stops | Efficient scheduled ingestion |

**`availableNow` vs `once`:**
* `once`: Runs a single micro-batch.
* `availableNow`: Runs multiple micro-batches until all pending data is processed. Much more efficient for backfills.

### `foreachBatch`

`foreachBatch` lets you apply arbitrary, non-streaming DataFrame operations to each micro-batch of streaming data.

**Use Case:** Upserts (which are not natively supported in streaming write mode).

```python
from delta.tables import DeltaTable

def upsert_to_silver(batch_df, batch_id):
  silver = DeltaTable.forPath(spark, "/data/silver/orders")
  silver.alias("t").merge(
    batch_df.alias("s"),
    "t.order_id = s.order_id"
  ).whenMatchedUpdateAll() \
   .whenNotMatchedInsertAll() \
   .execute()

(bronze_stream
  .writeStream
  .foreachBatch(upsert_to_silver)
  .option("checkpointLocation", "/checkpoints/silver_orders")
  .trigger(processingTime="2 minutes")
  .start()
)
```

***

## 2.3 Change Data Capture (CDC)

### What is CDC?

Change Data Capture (CDC) is a pattern for tracking row-level changes (inserts, updates, deletes) in a source operational database and propagating them to downstream systems.

**Why CDC Matters:**
* Traditional batch ETL copies entire tables — inefficient at scale.
* CDC only moves what changed, reducing latency and load.
* Critical for building near-real-time data warehouses and lakehouses.

### Common CDC Tools

| Tool | Protocol | Sources |
|---|---|---|
| Debezium | Kafka | MySQL, Postgres, SQL Server, Oracle |
| Qlik Replicate | Proprietary | 40+ databases |
| Fivetran | Managed SaaS | 500+ connectors |
| AWS DMS | AWS-native | RDS, Aurora, Oracle |

### `MERGE INTO` for Upserts

`MERGE INTO` is the SQL command that applies CDC changes to a Delta table.

```sql
MERGE INTO silver.orders AS target
USING bronze.orders_cdc AS source
ON target.order_id = source.order_id

WHEN MATCHED AND source.operation = 'DELETE'
  THEN DELETE

WHEN MATCHED AND source.operation = 'UPDATE'
  THEN UPDATE SET *

WHEN NOT MATCHED AND source.operation = 'INSERT'
  THEN INSERT *;
```

**Performance Tips for MERGE:**
* Filter the target table in the `ON` clause to limit scan size.
* Add `AND target.updated_at < source.updated_at` to avoid reprocessing old events.
* For very high volume, batch changes in micro-batches rather than one row at a time.

### SCD Type 1 (Overwrite)

The simplest approach: just overwrite old values with new ones. No history preserved.

```
Before Update:          After Update:
order_id: 101           order_id: 101
status: "pending"   →   status: "shipped"
```

**Use When:** History is not required. Only the current state matters.

### SCD Type 2 (History Preserved)

A new row is inserted for each change, with validity date ranges to track history.

```
order_id  status    is_current  valid_from  valid_to
101       pending   false       2024-01-01  2024-01-05
101       shipped   true        2024-01-05  9999-12-31
```

**Implementation Pattern:**
1. Mark old row as `is_current = false`, set `valid_to = now()`.
2. Insert new row with `is_current = true`, `valid_from = now()`, `valid_to = 9999-12-31`.

**Use When:** Auditing, regulatory compliance, or when analytics need to answer "What was the state at time T?"

### DLT `APPLY CHANGES INTO`

DLT has a native, built-in command for processing CDC streams without writing manual MERGE logic.

```python
dlt.create_streaming_table("orders_silver")

dlt.apply_changes(
  target="orders_silver",
  source="orders_bronze_cdc",
  keys=["order_id"],
  sequence_by=col("_commit_timestamp"),
  apply_as_deletes=expr("operation = 'DELETE'"),
  except_column_list=["operation", "_commit_timestamp"]
)
```

**How it Works:**
* `keys`: Defines the primary key for matching source to target.
* `sequence_by`: Orders events to handle late arrivals correctly.
* `apply_as_deletes`: Identifies which rows are deletes.
* DLT handles out-of-order events automatically.

**Architect Tip:** Always use `APPLY CHANGES INTO` in DLT pipelines for CDC instead of writing your own `MERGE`. It handles ordering, deduplication, and out-of-order events robustly.

***

## 2.4 Job Orchestration

### Databricks Workflows

Databricks Workflows is the native, fully managed orchestration engine built into the Databricks platform. It replaces the need for external orchestrators (Airflow, dbt Cloud) for many common patterns.

**Key Features:**
* Multi-task pipelines with dependency graphs.
* Multiple task types in the same job.
* Built-in retry logic and alerting.
* Cluster reuse between tasks (reduces startup overhead).
* Git integration for version-controlled notebooks and scripts.

### Task Types

| Task Type | Use Case |
|---|---|
| Notebook | Interactive notebooks (.py, .sql, .r) |
| Python Script | .py files from a Git repo or DBFS |
| DLT Pipeline | Trigger a Delta Live Tables pipeline |
| SQL | Run a SQL statement on a SQL Warehouse |
| dbt | Run dbt project tasks |
| JAR | Run a compiled Scala/Java JAR |

### Dependency Graphs

Tasks are linked by dependencies. Downstream tasks only start after their upstream tasks succeed.

```
  ingest_bronze
        │
        ▼
  transform_silver
     /        \
    ▼           ▼
gold_revenue  gold_users
```

Configure in YAML (asset bundles):
```yaml
tasks:
  - task_key: ingest_bronze
    ...
  - task_key: transform_silver
    depends_on:
      - task_key: ingest_bronze
    ...
```

### Conditional Task Execution

Tasks can be run conditionally based on the outcome of a previous task.

**Run Conditions:**
* `ALL_SUCCESS`: Run only if all upstream tasks succeeded.
* `AT_LEAST_ONE_SUCCESS`: Run if at least one upstream task succeeded.
* `ALL_DONE`: Run regardless of outcome (useful for cleanup tasks).
* `ALL_FAILED`: Run only if all upstream tasks failed (alerting).

### Retry Logic

Configure automatic retries at the task or job level.

```yaml
tasks:
  - task_key: api_call
    max_retries: 3
    min_retry_interval_millis: 30000  # 30 seconds
    retry_on_timeout: true
```

**Best Practice:** Use retries for tasks that call external APIs or depend on transient network conditions. Do not use retries to mask bugs in transformation logic.

### Passing Parameters

**Job-Level Parameters:**
Defined at job creation and passed to all tasks.

```python
# In a notebook task, read parameters:
order_date = dbutils.widgets.get("order_date")
print(f"Processing orders for: {order_date}")
```

**Task Values (passing output between tasks):**
```python
# Task 1: Set a value
dbutils.jobs.taskValues.set(
  key="row_count",
  value=df.count()
)

# Task 2: Read the value from Task 1
row_count = dbutils.jobs.taskValues.get(
  taskKey="ingest_bronze",
  key="row_count"
)
print(f"Rows ingested: {row_count}")
```

### Triggering Workflows

| Method | How |
|---|---|
| Scheduled | CRON expression (e.g., `0 2 * * *`) |
| Continuous | Re-triggers immediately after completion |
| Manual | UI or API |
| File arrival | Via Auto Loader trigger |
| External | REST API `POST /api/2.1/jobs/run-now` |

**REST API Trigger Example:**
```bash
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"job_id": 12345, "notebook_params": {"date": "2024-06-01"}}' \
  https://<workspace>.azuredatabricks.net/api/2.1/jobs/run-now
```

***

## 2.5 Performance Design

### Partition Pruning

Partition pruning is Spark's ability to skip reading entire directories of data when the query filter matches the partition column.

```
/data/silver/orders/
  ├── year=2024/month=01/
  ├── year=2024/month=02/
  └── year=2024/month=03/   ← Only this folder is read

# Query:
SELECT * FROM orders WHERE year=2024 AND month=3;
```

**Rules for Effective Partitioning:**
* Only partition on columns used frequently in `WHERE` clauses.
* Avoid high-cardinality columns (user_id, order_id) — they create too many small directories.
* Target 1–5 partition columns maximum.
* Ideal partition column: low cardinality, high query frequency (date, region, status).

**Architect Note:** For new tables, prefer **Liquid Clustering** (Phase 1) over Hive-style partitioning. It's more flexible and avoids the small-file and over-partitioning pitfalls.

### Bloom Filters

A Bloom filter is a probabilistic data structure that allows Spark to skip reading files that definitely do not contain a value, without scanning the entire file.

```sql
-- Create a Bloom filter index on a column:
CREATE BLOOMFILTER INDEX
ON TABLE silver.orders
FOR COLUMNS (customer_id);
```

**Best Used On:**
* High-cardinality columns (customer_id, transaction_id).
* Columns frequently used in equality filters (`WHERE customer_id = 'abc123'`).

**Do Not Use On:**
* Low-cardinality columns (status, country) — use partitioning instead.
* Range queries (`WHERE age BETWEEN 20 AND 30`) — Bloom filters don't help.

### Caching

**`CACHE TABLE` (SQL / Spark SQL):**
* Caches the entire table into executor memory.
* Survives the session duration.
* Good for repeatedly accessed lookup tables.

```sql
CACHE TABLE silver.dim_products;
```

**`.cache()` / `.persist()` (Python/Scala):**
* Caches a DataFrame in memory (or disk+memory).
* Tied to the SparkContext's lifecycle.
* Call `.unpersist()` when done.

```python
# Cache a frequently joined DataFrame:
dim_customers = spark.table("silver.dim_customers").cache()
dim_customers.count()  # Trigger materialization
```

**Storage Levels for `.persist()`:**

| Level | Description |
|---|---|
| MEMORY_ONLY | Pure memory (fastest, may OOM) |
| MEMORY_AND_DISK | Spills to disk if memory full |
| DISK_ONLY | Stores on disk only (slowest) |

**Architect Tip:** Don't cache everything — it consumes executor memory and can cause OOM errors. Cache only DataFrames that are reused many times in the same job.

### The Small File Problem

**Cause:** Many small writes (streaming micro-batches, many small batch jobs) create thousands of tiny Parquet files. Reading many small files is slow because of metadata overhead and many individual I/O operations.

**Solutions:**

1. **`OPTIMIZE` on a schedule:**
   ```sql
   OPTIMIZE silver.orders;
   ```
   Run as a daily scheduled job. Target: files of ~1 GB each.

2. **Auto Compaction:**
   Databricks automatically runs a small compaction after every streaming write.
   ```python
   .option("delta.autoCompact.enabled", "true")
   ```

3. **Optimized Writes:**
   Before writing, Databricks automatically coalesces the data to minimize the number of files written.
   ```python
   .option("delta.optimizeWrite.enabled", "true")
   ```
   Note: `optimizeWrite` may add overhead. Test before enabling on latency-sensitive streaming jobs.

### Photon Engine

**What is Photon?**
Photon is Databricks' native vectorized query engine written in C++. It replaces the JVM-based Spark execution for SQL and DataFrame operations.

**How it Works:**
* Processes data in "vectors" (batches of column values) rather than one row at a time.
* Eliminates JVM garbage collection overhead.
* Leverages SIMD CPU instructions for maximum throughput.

**Benefits:**
* 2–8x faster for SQL aggregate queries, joins, and scans.
* No code changes required.
* Especially impactful for large scans and complex joins.

**When Not to Use Photon:**
* Python UDFs (User-Defined Functions) — they still run in the JVM.
* Complex ML operations.
* Custom Scala/Java code not optimized for Photon.

**Enable Photon:**
Select a **"Photon Accelerated"** cluster in the Databricks UI, or use a runtime with Photon included (DBR 9.1+ Photon).

***

## Phase 2 Summary

| Topic | Key Points |
|---|---|
| Medallion | Bronze (raw) → Silver (clean) → Gold (aggregated) |
| Auto Loader | Cloud-native incremental file ingestion with checkpoints |
| DLT | Declarative pipelines with built-in quality expectations |
| Streaming | Micro-batch processing with multiple trigger modes |
| CDC | `MERGE INTO`, SCD patterns, `APPLY CHANGES INTO` in DLT |
| Workflows | Multi-task jobs, conditional logic, parameter passing |
| Performance | Pruning, Bloom filters, caching, small files, Photon |

**Self-Assessment Checklist:**
* [ ] Can you design a Medallion Architecture for a new use case?
* [ ] Can you write an Auto Loader ingestion pipeline?
* [ ] Can you define DLT tables with data quality expectations?
* [ ] Can you implement SCD Type 2 in Delta Lake?
* [ ] Can you build a multi-task Workflow with dependencies?
* [ ] Can you diagnose and fix a small file performance problem?

***

## Resources

* Databricks Academy: "Data Engineering with Databricks"
* Databricks Docs: `docs.databricks.com/delta-live-tables`
* Databricks Docs: `docs.databricks.com/workflows`
* Book: "Delta Lake: The Definitive Guide" (O'Reilly)
