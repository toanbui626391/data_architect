# Bronze Layer: Auto Loader Ingestion Model (SQL)

This document provides a concrete **Delta Live Tables (DLT)** SQL implementation for the Bronze layer, based on the [Real-Time Ingestion Architecture](realtime_ingestion_architecture.md). 

It demonstrates how to incrementally ingest JSON data from cloud storage (S3/ADLS/GCS) using Databricks Auto Loader via the modern DLT SQL syntax.

---

## 1. DLT SQL Implementation

Create a new SQL file in your Databricks workspace (e.g., `bronze_ingestion.sql`) and use the following code. This defines a **Streaming Table** that continuously listens to a cloud storage path using the `read_files()` table-valued function.

```sql
-- 1. Define the Streaming Table and its metadata
CREATE OR REFRESH STREAMING TABLE bronze_sales_orders
COMMENT "Raw append-only streaming ingestion of sales orders from cloud storage."
TBLPROPERTIES (
  "quality" = "bronze",
  "pipelines.autoOptimize.managed" = "true" -- Enables automatic file compaction
)
AS 
-- 2. Select data and enrich with Audit Metadata
SELECT 
  *,
  _metadata.file_path AS _source_file_path,
  current_timestamp() AS _ingested_at

-- 3. Read Stream using Auto Loader (read_files function)
FROM STREAM read_files(
  "s3://my-enterprise-data-lake/landing/sales_orders/",
  
  -- --- Auto Loader Options ---
  format => "json",
  inferColumnTypes => "true",
  
  -- --- Schema Evolution & Resilience ---
  -- Automatically add new columns to the Delta table if upstream changes schema
  schemaEvolutionMode => "addNewColumns",
  -- If a column type mismatches, put original string here instead of failing
  schemaHints => "_rescued_data STRING",
  
  -- --- Execution Mode (File Notification) ---
  -- "true" = Uses cloud queues (SQS/EventGrid) instead of expensive directory listing
  useNotifications => "true"
);
```

---

## 2. Key Design Decisions Explained

This implementation utilizes several advanced features of Auto Loader and DLT SQL to ensure the pipeline is robust and production-ready:

### 2.1 Auto Loader Core (`read_files()`)
In DLT SQL, Auto Loader is invoked using the `read_files()` table-valued function wrapped inside a `STREAM()`. 
*   **`useNotifications => "true"`:** This is the most critical setting. It tells Databricks to listen to a cloud message queue (like AWS SQS) for file creation events. This avoids running expensive `ls` operations on buckets with millions of files, saving significant compute costs and reducing latency.

### 2.2 Schema Management
Notice that unlike the Python API, you do not need to explicitly specify a `schemaLocation` in DLT SQL. DLT automatically manages the schema inference state and checkpoint directories under the hood based on your Pipeline's defined Storage Location.

### 2.3 Resilient Schema Evolution
Streaming pipelines are prone to crashing when upstream systems change schemas without notice. This model prevents crashes using two settings:
1.  **`schemaEvolutionMode => "addNewColumns"`:** If a new key appears in the JSON, Databricks will automatically run an `ALTER TABLE` to append the column to the Bronze table.
2.  **`schemaHints => "_rescued_data STRING"`:** If the upstream system accidentally sends a string (e.g., `"N/A"`) into a column that was inferred as an integer, standard pipelines fail. Auto Loader instead inserts `null` into the integer column and saves the original `"N/A"` string inside the `_rescued_data` column. This guarantees zero data loss.

### 2.4 Audit Metadata (The `_metadata` hidden column)
Databricks SQL provides a hidden struct column named `_metadata` when reading files. We extract critical debugging information from it:
*   `_source_file_path`: Answers the question *"Which exact JSON file produced this row?"* when investigating bad data.
*   `_ingested_at`: We generate a timestamp using `current_timestamp()` to allow downstream consumers to calculate pipeline latency.
