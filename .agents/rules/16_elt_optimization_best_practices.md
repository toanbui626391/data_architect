# Agent Guidelines: ELT Optimization (Fabric, Databricks, Snowflake)

When developing or refactoring ELT pipelines, schemas, and queries across Microsoft Fabric, Databricks, or Snowflake, the AI agent **MUST** follow these platform-specific optimization rules.

---

## 1. Microsoft Fabric (Spark / OneLake)
*   **Rule:** The agent **MUST** optimize Delta write layouts and enforce incremental processing to accelerate Power BI DirectLake access and reduce compute consumption.
*   **Directives:**
    *   **Mandatory Incremental Processing:** **MUST** execute all Medallion layer updates incrementally using Structured Streaming with checkpointing (using `foreachBatch` or `availableNow` triggers). **NEVER** run full-table recomputations in production unless performing a managed historical backfill.
    *   **V-Order Parquet:** **ALWAYS** enable V-Order sorting for Delta writes (`spark.sql.parquet.vorder.enabled = true`). This organizes data layouts specifically to boost Power BI in-memory performance.
    *   **Write Auto-Optimization:** **MUST** enable `spark.microsoft.delta.optimizeWrite.enabled = true` and `spark.microsoft.delta.autoCompact.enabled = true` to prevent the "small file problem" on ingestion.
    *   **Resource Sizing (Dynamic Allocation):** **MUST** limit executor bounds (`maxExecutors`) on streaming jobs to prevent capacity exhaustion while enabling dynamic allocation to scale down when idle.

---

## 2. Databricks (Delta Lake / Spark Engine)
*   **Rule:** The agent **MUST** write incremental pipelines and leverage the Photon engine and Delta metadata for optimal execution speeds.
*   **Directives:**
    *   **Incremental CDF Aggregations:** **MUST** aggregate downstream models (Gold layer) incrementally by subscribing to the Silver Delta Change Data Feed (CDF) as a stream, executing via continuous triggers or scheduled batch `trigger(availableNow=True)`.
    *   **Partition Pruning during Merges:** **ALWAYS** include the clustering/partition key in the `ON` condition of a `MERGE` statement (e.g. `ON target.id = source.id AND target.date = source.date`). This prevents full table scans by pruning files.
    *   **Liquid Clustering:** **NEVER** use Hive-style directory partitioning for new tables. **ALWAYS** use Liquid Clustering (`CLUSTER BY`) on frequently filtered columns to maintain optimal file sizes automatically.
    *   **Photon Acceleration:** **NEVER** write arbitrary Python UDFs inside Photon-enabled SQL Warehouses. Use SQL expressions, built-in Spark SQL functions, or vectorized Pandas UDFs (`@pandas_udf`) to maintain Photon processing.
    *   **Cache Utilization:** Keep date filters fixed (avoid `CURRENT_DATE`) on BI warehouse dashboards to leverage the 24-hour SQL result cache.

---

## 3. Snowflake (Data Cloud)
*   **Rule:** The agent **MUST** write incremental transformations and manage virtual warehouses to minimize billing credits.
*   **Directives:**
    *   **Streams & Dynamic Tables:** **MUST** implement incremental ELT transformations using **Dynamic Tables** or `MERGE` statements backed by Snowflake Streams/Change Data Capture (CDC). **NEVER** use full table recreations (`CREATE OR REPLACE TABLE`) or full-table scans for production data loads.
    *   **Micro-Partition Clustering:** For tables exceeding 1 TB, define explicit `CLUSTER BY (col1, col2)` keys using high-cardinality filter fields. Monitor the clustering depth to avoid redundant re-clustering compute credits.
    *   **Search Optimization Service (SOS):** **SHOULD** enable SOS only on tables where business queries perform selective point-lookups (matching unique IDs/UUIDs) across millions of rows to bypass scanning partitions.
    *   **Warehouse Sizing Strategy:**
        *   Scale **OUT** (add clusters) to resolve queueing and concurrency.
        *   Scale **UP** (increase warehouse size) only to resolve query-level disk spilling (spilling to local/remote storage).
    *   **Zero-Copy Clones:** **ALWAYS** use `CLONE` for dev/test environments to duplicate table metadata instantly without copying data blocks or incurring extra storage/compute costs.
