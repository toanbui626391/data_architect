# Databricks Data Warehouse: Optimization & Data Modeling Best Practices

## 1. Executive Summary
This document outlines the best practices for **Data Modeling** and **Performance Optimization** within a Databricks SQL / Lakehouse environment. Operating a high-performance, cost-effective data warehouse on Databricks requires a shift from traditional relational database modeling towards **Delta Lake-specific physical optimizations** (like Liquid Clustering) and the **Medallion Architecture**.

---

## 2. Data Modeling Strategy (The Medallion Architecture)

Databricks advocates for the Medallion Architecture to logically organize data in the Lakehouse. This allows for incremental data quality improvements and separation of concerns.

### 2.1 The Layers
*   **Bronze (Raw):** 
    *   *Purpose:* Ingest data in its raw state (JSON, CSV, Parquet) with minimal processing. Retain full history.
    *   *Modeling:* Append-only. Schema matches the source system exactly. Include metadata columns (ingestion timestamp, source file name).
*   **Silver (Cleansed & Conformed):** 
    *   *Purpose:* Filter, clean, and standardize the data. Enforce data quality rules (e.g., using DLT Expectations). 
    *   *Modeling:* Typically 3rd Normal Form (3NF) or Data Vault. Tables represent core business entities (Customers, Orders, Products).
*   **Gold (Business-Ready):** 
    *   *Purpose:* Serve analytics, BI dashboards, and ML models.
    *   *Modeling:* **Dimensional Modeling (Star Schema)**. Highly denormalized fact and dimension tables. Optimized for rapid READ operations.

### 2.2 Star Schema in Databricks
While Databricks can handle highly normalized data, the **Star Schema (Facts and Dimensions)** remains the most optimal design for the Gold layer because:
1.  **Photon Engine:** Databricks' vectorized query engine (Photon) is heavily optimized for hash joins typical in Star Schemas.
2.  **Predictive I/O:** Databricks automatically optimizes reading wide dimension tables joined to massive fact tables.

---

## 3. Physical Layout & Storage Optimization

How data is physically stored on disk (cloud storage) dictates 90% of query performance.

### 3.1 Liquid Clustering (The Modern Standard)
**Liquid Clustering** replaces traditional Hive-style partitioning and Z-Ordering. It automatically clusters data by specified columns and dynamically adapts as the data grows and changes.

*   **When to use:** Use this as the default for all new Delta tables in Databricks.
*   **How it works:** It uses an incremental clustering algorithm that avoids the data skew and "small file" problems associated with strict folder partitioning.
*   **Implementation:**
    ```sql
    CREATE TABLE gold_sales (
        date_sk DATE,
        customer_id STRING,
        region STRING,
        total_amount DECIMAL(10,2)
    ) CLUSTER BY (date_sk, customer_id, region);
    ```

### 3.2 Partitioning (Legacy / Niche Use Cases)
*   **Rule of Thumb:** Only use physical partitioning (`PARTITIONED BY`) if you are **not** using Liquid Clustering AND you have over **1 TB of data**, where each partition folder will contain at least **1 GB of data**.
*   **Anti-Pattern:** Partitioning by high-cardinality columns (e.g., `customer_id` or `timestamp`) creates millions of tiny files, crashing the metadata catalog and degrading performance.

### 3.3 Z-Ordering (Legacy)
If you are on an older Databricks runtime and cannot use Liquid Clustering, **Z-Ordering** is a technique to colocate related information in the same set of files based on high-cardinality columns frequently used in `WHERE` clauses.
```sql
-- Legacy approach (use Liquid Clustering instead on new runtimes)
OPTIMIZE gold_sales ZORDER BY (customer_id);
```

---

## 4. File Size Management & Data Skipping

Delta Lake performance degrades significantly if a table consists of thousands of tiny files (the "small file problem").

### 4.1 Bin-Packing (`OPTIMIZE`)
The `OPTIMIZE` command compacts small files into larger, more efficient files (target size is typically 1GB).
*   **Best Practice:** Schedule a Databricks Job to run `OPTIMIZE` daily on highly active transactional tables (Silver/Gold).
*   **Auto-Optimize:** For streaming or high-frequency batch inserts, enable auto-optimization on the table to let Databricks compact files behind the scenes.
    ```sql
    ALTER TABLE silver_orders SET TBLPROPERTIES (
        'delta.autoOptimize.optimizeWrite' = 'true',
        'delta.autoOptimize.autoCompact' = 'true'
    );
    ```

### 4.2 Data Skipping (Min/Max Statistics)
By default, Delta Lake collects minimum and maximum values for the first 32 columns of a table. 
*   **How it works:** When a query filters on a column (e.g., `WHERE date = '2023-01-01'`), Databricks reads the metadata. If the requested date falls outside a file's min/max range, that entire file is skipped without touching the disk.
*   **Optimization:** Ensure the columns you filter on most frequently are placed within the **first 32 columns** of your table definition.

---

## 5. Compute & Query Optimization

### 5.1 The Photon Engine
Photon is a native vectorized query engine written in C++ that accelerates SQL workloads.
*   **Best Practice:** Always enable the Photon engine for **Databricks SQL Warehouses** and any clusters running heavy BI/ETL workloads. It significantly speeds up aggregations and joins.

### 5.2 Serverless SQL Warehouses & Predictive I/O
*   **Serverless:** Use Serverless SQL Warehouses for BI tools (Tableau, PowerBI). They spin up in seconds and utilize **Predictive I/O**, a machine learning feature that anticipates what data a query will need and prefetches it into memory, drastically reducing scan times.
*   **Result Caching:** Databricks SQL automatically caches the results of identical queries. If a dashboard refreshes with the same parameters, the result is served from memory instantly.

---

## 6. Table Maintenance & Hygiene

Regular maintenance is required to keep storage costs down and performance high.

### 6.1 VACUUM (Removing Stale Files)
When you update or delete data in Delta Lake, the old files are kept for Time Travel. Over time, these accumulate and cost money.
*   **Best Practice:** Run `VACUUM` weekly to delete files older than the retention period (default 7 days).
    ```sql
    -- Removes physical files logically deleted more than 7 days ago
    VACUUM gold_sales RETAIN 168 HOURS; 
    ```

### 6.2 ANALYZE (Updating Statistics)
The Cost-Based Optimizer (CBO) relies on accurate statistics to plan the fastest query execution paths (e.g., deciding which table to broadcast in a join).
*   **Best Practice:** Run `ANALYZE TABLE` after major data loads.
    ```sql
    ANALYZE TABLE gold_sales COMPUTE STATISTICS FOR ALL COLUMNS;
    ```
