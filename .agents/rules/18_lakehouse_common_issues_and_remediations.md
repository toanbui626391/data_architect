# Agent Guidelines: Lakehouse Issues & Remediations (Databricks, Fabric, Snowflake)

This document defines rules and best practices for identifying, troubleshooting, and preventing the most common issues across Databricks, Microsoft Fabric, and Snowflake Lakehouse architectures, supporting both streaming and batch workloads.

---

## 1. Databricks (Delta Lake & Unity Catalog)

### 1.1 Out of Memory (OOM) on Streaming State (Stateful Operations)
*   **Issue**: Running stream-to-stream joins or windowed aggregations on default HDFS-backed state stores causes JVM heap exhaustion and Executor OOMs as the state size grows.
*   **Rule**: **MUST** configure the RocksDB state store provider and enable changelog checkpointing for all stateful streams:
    ```python
    spark.conf.set("spark.sql.streaming.stateStore.providerClass", "org.apache.spark.sql.execution.streaming.state.RocksDBStateStoreProvider")
    spark.conf.set("spark.sql.streaming.stateStore.rocksdb.changelogCheckpointing.enabled", "true")
    ```

### 1.2 "Small Files" Degradation in Streaming Appends
*   **Issue**: High-frequency streaming appends generate thousands of tiny Parquet files, degrading listing operations and downstream reads.
*   **Rule**: **MUST** enable both Optimized Writes and Auto-Compaction globally in the Spark Session **and** explicitly in table `TBLPROPERTIES`:
    ```python
    spark.conf.set("spark.databricks.delta.properties.defaults.autoOptimize.optimizeWrite", "true")
    spark.conf.set("spark.databricks.delta.properties.defaults.autoOptimize.autoCompact", "true")
    ```
    ```sql
    ALTER TABLE my_table SET TBLPROPERTIES (
      "delta.autoOptimize.optimizeWrite" = "true",
      "delta.autoOptimize.autoCompact" = "true"
    );
    ```
*   **Maintenance**: **MUST** schedule a daily `OPTIMIZE` (bin-packing) and weekly `VACUUM` job to compact stale files on all active Silver/Gold tables. Use Liquid Clustering (`CLUSTER BY`) — **NEVER** Hive-style `PARTITIONED BY` — for new tables.

### 1.3 Data Skew & Straggler Tasks
*   **Issue**: A single task runs significantly longer than others because a few join or group-by keys contain the majority of rows.
*   **Rule**: **MUST** enable Adaptive Query Execution (AQE) with skew join detection and partition coalescing:
    ```python
    spark.conf.set("spark.sql.adaptive.enabled", "true")
    spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")
    spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
    ```
*   **Manual Fix**: For skewed non-equality joins that AQE cannot resolve, apply **Salting** (appending a random number `0..N` to keys and replicating the matching table) to distribute heavy partitions across executors.

### 1.4 Shuffle Fetch Failures with Dynamic Allocation
*   **Issue**: When dynamic allocation scales down idle executors, their local shuffle files are deleted. Downstream stages that need those files fail with `ShuffleFetchFailedException` or `MetadataFetchFailedException`.
*   **Rule**: **MUST** enable Shuffle Tracking to prevent executors holding active shuffle data from being killed:
    ```python
    spark.conf.set("spark.dynamicAllocation.shuffleTracking.enabled", "true")
    ```
*   **Alternative**: For dedicated cluster environments, configure an **External Shuffle Service (ESS)** so shuffle files are decoupled from executor processes and survive executor termination.

### 1.5 Streaming Schema Evolution Failures on Restart
*   **Issue**: Modifying schema definitions in streaming queries causes stream restarts to fail with schema mismatch or incompatibilities due to checkpoint schema locking.
*   **Rule**: **MUST** handle schema changes according to their type without deleting checkpoints:
    1.  **Additive changes (new columns)**: Enable `.option("mergeSchema", "true")` on the `writeStream` writer and restart the stream. Do **not** delete the checkpoint.
    2.  **Renames or drops**: Enable Delta Column Mapping to avoid rewriting files or breaking the checkpoint:
        ```sql
        ALTER TABLE my_table SET TBLPROPERTIES (
          'delta.columnMapping.mode' = 'name',
          'delta.minReaderVersion' = '2',
          'delta.minWriterVersion' = '5'
        );
        ```
    3.  **Breaking/Type changes**: Deploy a new version of the stream (e.g., v2) with a new target table and checkpoint path to run in parallel, avoiding live checkpoint deletion.
*   **Rule**: For Silver `MERGE` statements, **always** include the partition/cluster key in the `ON` condition to prevent full table scans during schema re-bootstrap.

### 1.6 Silent Failures — Missing DLQ Volume Alerts
*   **Issue**: Records with invalid primary keys or malformed payloads are quietly routed to a Dead Letter Queue (DLQ), but no alert fires. The pipeline reports "Succeeded" while data silently disappears from the Silver layer.
*   **Rule**: **MUST** emit a `deleted_rows` (DLQ count) metric on every batch and configure a **P2 alert** that fires when `deleted_rows / input_rows > 1%` in any micro-batch. Never treat a high DLQ rate as a silent warning.

---

## 2. Microsoft Fabric (OneLake & Power BI Direct Lake)

### 2.1 Broken Power BI Direct Lake Bindings
*   **Issue**: Power BI Direct Lake models bind to the underlying OneLake Delta table using internal metadata GUIDs. Running `DROP TABLE` followed by `CREATE TABLE`, or using metadata renames (`ALTER TABLE ... RENAME TO`), destroys these GUIDs, permanently breaking the semantic model connection.
*   **Rule**: **NEVER** drop or rename production tables during updates. **ALWAYS** use atomic Delta overwrites to rebuild data in-place without altering the table GUID:
    ```python
    df.write.format("delta").mode("overwrite").saveAsTable("production_table")
    ```

### 2.2 Unoptimized Parquet Files for Direct Lake
*   **Issue**: Standard Parquet files written to OneLake are not organized for Direct Lake's in-memory swapping mechanism, causing slow dashboard renders and column-load timeouts.
*   **Rule**: **MUST** enable Fabric's native **V-Order** optimization and Delta optimized writes before any production table write:
    ```python
    spark.conf.set("spark.sql.parquet.vorder.enabled", "true")
    spark.conf.set("spark.microsoft.delta.optimizeWrite.enabled", "true")
    spark.conf.set("spark.databricks.delta.properties.defaults.autoOptimize.autoCompact", "true")
    ```
    > **Note**: The correct Fabric session-level property for auto-compaction is `spark.databricks.delta.properties.defaults.autoOptimize.autoCompact`, **not** `spark.microsoft.delta.autoCompact.enabled`.

### 2.3 Checkpoint Mismatches on Streaming Rebuilds
*   **Issue**: Modifying logic or target schemas in a streaming job without clearing the checkpoint causes Spark to resume with incompatible offset states, leading to schema mismatch failures or silent data gaps.
*   **Rule**: **MUST** purge both the rebuild checkpoint directory and create a shadow table before starting any rebuild:
    ```python
    from notebookutils import mssparkutils
    if mssparkutils.fs.exists("Files/checkpoints/target_rebuild"):
        mssparkutils.fs.rm("Files/checkpoints/target_rebuild", True)
    ```
*   **Rule**: Follow the Shadow Table Rebuild pattern: rebuild into a `_rebuild` shadow table, validate, then perform an atomic Delta overwrite onto production. **Never** rebuild directly into the live production table while it is being queried.

### 2.4 Missing Silver-Layer Data Quality Enforcement
*   **Issue**: Fabric Spark pipelines often lack explicit DQ rules at the Silver layer. Invalid records (null primary keys, negative amounts) pass through to Gold, corrupting aggregations.
*   **Rule**: Every Silver `foreachBatch` function **MUST** split incoming records into `valid_records` (pass DQ gate) and `invalid_records` (routed to a DLQ table). **NEVER** apply a blanket `MERGE` across all incoming records without DQ filtering.

### 2.5 Silent Direct Lake Fallback to DirectQuery
*   **Issue**: If a Power BI Direct Lake model encounters unsupported features (e.g. calculated tables, SQL views) or resource limit guardrails, it silently falls back to DirectQuery, degrading report performance.
*   **Rule**: **MUST** set Direct Lake Behavior to **Direct Lake Only** (`directLakeBehavior = "directLakeOnly"`) to force a hard failure on unsupported operations instead of falling back silently. Move Row-Level Security (RLS) to the semantic model, and avoid exposing raw SQL views.

---

## 3. Snowflake (Data Cloud & Iceberg)

### 3.1 Unbounded Credit Consumption in Dynamic Tables
*   **Issue**: Setting a low `TARGET_LAG` (e.g. 1 minute) on heavy Dynamic Tables causes near-continuous warehouse refreshes, consuming disproportionate compute credits.
*   **Rule**: **MUST** align `TARGET_LAG` with actual downstream SLA. Use `TARGET_LAG = 'DOWNSTREAM'` for chained dependent tables. Avoid lags under `15 minutes` unless real-time SLA is contractually required.
*   **Rule**: Ensure `AUTO_SUSPEND = 60` (seconds) on all warehouses and set warehouse size to the smallest that prevents query spill.

### 3.2 High-Frequency Ingestion Overhead from Batch COPY
*   **Issue**: Using continuous micro-batch `COPY INTO` commands for streaming-rate ingestion incurs per-transaction compilation overhead and generates small micro-partition files.
*   **Rule**: **MUST** use **Snowpipe Streaming** (Kafka Connector in Low-Latency mode, or SDK-based row-set write) for streaming ingestion. Snowpipe Streaming writes directly to table buffers without triggering full COPY compilation.

### 3.3 Dynamic Table Failures due to Breaking Schema Changes
*   **Issue**: Dropping or renaming columns on a source table that feeds a Dynamic Table causes the downstream refresh to freeze or fail indefinitely with a schema resolution error.
*   **Rule**: **NEVER** apply breaking schema changes directly on source tables that back Dynamic Tables. **MUST** introduce a view abstraction layer between source and Dynamic Table, so schema changes can be absorbed in the view without pausing the pipeline.

### 3.4 Query Spilling to Remote Storage
*   **Issue**: Joins or aggregations that exceed available warehouse memory spill data first to local NVMe SSDs and then to remote S3/GCS storage. Remote spill degrades query performance by 10–100×.
*   **Rule**: Monitor `QUERY_HISTORY` for `BYTES_SPILLED_TO_REMOTE_STORAGE > 0`. When detected:
    1.  Scale **UP** the warehouse (not out) to provide more memory per query.
    2.  Rewrite the query to reduce fan-out: pre-aggregate before joins, avoid `SELECT *` on wide tables.
    3.  Enable `SEARCH_OPTIMIZATION` on selective point-lookup tables to reduce per-query scan volume.

### 3.5 Non-Incremental Dynamic Table Refresh Fallbacks
*   **Issue**: Defining Dynamic Tables with unsupported SQL constructs (e.g. non-deterministic functions, outer joins with certain filters, or complex window functions) silently forces Snowflake to run them in `FULL` refresh mode, causing high compute costs.
*   **Rule**: **MUST** check `refresh_mode` using `DYNAMIC_TABLE_REFRESH_HISTORY` after creation to verify it is running in `INCREMENTAL` mode:
    ```sql
    SELECT table_name, refresh_mode, refresh_mode_reason
    FROM TABLE(information_schema.dynamic_table_refresh_history(table_name => 'my_dynamic_table'))
    LIMIT 10;
    ```
    If `refresh_mode` is `FULL`, simplify the SQL query to support incrementality or migrate to scheduled Tasks/Stored Procedures.

