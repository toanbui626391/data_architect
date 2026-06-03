# Spark & Databricks Optimization: Interview Q&A

This document covers the most frequently asked interview questions regarding Apache Spark and Databricks performance optimization. It is structured to be both concise and comprehensive.

---

## 1. Data Skew

**Q: What is data skew in Spark, and how do you resolve it?**
*   **Concept:** Data skew occurs when data is unevenly distributed across partitions, causing a few tasks to take significantly longer than others (the "straggler" problem).
*   **Resolution Strategies:**
    1.  **Adaptive Query Execution (AQE):** Enable AQE (`spark.sql.adaptive.enabled = true`). AQE dynamically detects and optimizes skewed joins by splitting skewed partitions into smaller sub-partitions.
    2.  **Salting:** Add a random key (salt) to the skewed column before joining, and replicate the smaller table by the salt factor. This forces a redistribution of the skewed data.
    3.  **Broadcast Joins:** If joining a skewed large table with a small table, broadcast the small table. This avoids shuffling the skewed table entirely.
    4.  **Re-partitioning/Coalescing:** Repartition data on the join key if it distributes data more evenly before the join.

## 2. Join Strategies

**Q: Explain the different join strategies in Spark and when to use them.**
*   **Broadcast Hash Join (BHJ):** 
    *   *When:* One table is small enough to fit in the memory of all executors (default `< 10MB`, tunable via `spark.sql.autoBroadcastJoinThreshold`).
    *   *Why:* Avoids shuffling entirely. Fastest join.
*   **Sort Merge Join (SMJ):**
    *   *When:* Both tables are large. 
    *   *Why:* Spark shuffles data by the join key, sorts it within partitions, and then merges. The default choice for large joins in Spark (pre-AQE/Photon).
*   **Shuffle Hash Join (SHJ):**
    *   *When:* Tables are large, but one is smaller than the other (but too large to broadcast), and the data is relatively evenly distributed.
    *   *Why:* Shuffles data, builds a hash table for the smaller side on each executor. Can cause OOM if a partition is too large.
*   **AQE dynamically chooses:** AQE can convert SMJ to BHJ or SHJ at runtime if the actual data size after filtering is smaller than expected.

## 3. Storage and File Management

**Q: How do you optimize file storage for Spark reading?**
*   **File Format:** Always use columnar formats like **Parquet** or **Delta Lake** for analytical workloads. They support predicate pushdown and column pruning.
*   **Partitioning:** Partition tables by columns frequently used in `WHERE` clauses (e.g., `date`). Avoid over-partitioning (creates the "small file problem").
*   **Small File Problem:** Thousands of tiny files cause excessive metadata overhead. 
    *   *Fix:* Use `df.repartition()` or `df.coalesce()` before writing. In Delta Lake, use `OPTIMIZE`.
*   **Z-Ordering / Liquid Clustering (Databricks):** 
    *   *Z-Ordering:* Co-locates related information in the same set of files based on high-cardinality columns. Massively improves data skipping.
    *   *Liquid Clustering:* Databricks' replacement for partitioning and Z-ordering. It dynamically adapts data layout over time without rigid partition definitions.

## 4. Memory Management & OOM Errors

**Q: How do you troubleshoot Out of Memory (OOM) errors in Spark?**
*   **Driver OOM:** Usually caused by `collect()` bringing massive datasets to the driver, or giant broadcast variables.
    *   *Fix:* Avoid `collect()`; use `take()` or `show()`. Increase driver memory if absolutely necessary.
*   **Executor OOM:** Caused by data skew, large partitions, heavy UDFs, or Cartesian joins.
    *   *Fix:* 
        1. Increase executor memory (`spark.executor.memory`).
        2. Increase shuffle partitions (`spark.sql.shuffle.partitions`, default is 200). If you have a 1TB dataset, 200 partitions means 5GB per task, which will OOM. Increase to 1000+.
        3. Resolve data skew.
*   **Overhead OOM:** Non-heap memory (e.g., PySpark Python processes, native libraries).
    *   *Fix:* Increase `spark.executor.memoryOverhead`.

## 5. Databricks Specific Optimizations

**Q: What specific features does Databricks offer for optimization that open-source Spark does not?**
1.  **Photon Engine:** A native vectorized query engine written in C++. It transparently accelerates SQL and DataFrame operations on modern hardware without code changes.
2.  **Delta Lake `OPTIMIZE` and `VACUUM`:** 
    *   `OPTIMIZE`: Compacts small files into larger ones to improve read speeds.
    *   `VACUUM`: Removes old data files no longer referenced by the Delta transaction log, saving storage costs.
3.  **Disk Caching (formerly Delta Cache):** Automatically caches copies of remote files on the local NVMe storage of worker nodes, making subsequent reads significantly faster.
4.  **Liquid Clustering:** Simplifies data layout decisions (replaces traditional partitioning and Z-ordering).
5.  **Serverless Compute:** Databricks SQL Serverless abstracts away cluster sizing and startup times, providing instant, auto-scaled compute.

## 6. Configuration Tuning

**Q: What are the most critical Spark configurations you tune for performance?**
*   `spark.sql.shuffle.partitions`: Default 200 is rarely right for production. Tune based on data size (aim for 100MB - 200MB per partition).
*   `spark.sql.adaptive.enabled`: Always set to `true` (default in Spark 3+).
*   `spark.executor.memory` & `spark.executor.cores`: Balance these. Too many cores per executor degrades HDFS throughput and causes GC pauses. The "fat executor" standard is usually 4-5 cores per executor.
*   `spark.sql.autoBroadcastJoinThreshold`: Increase (e.g., to 20MB or 30MB) if you have enough executor memory and want to force broadcast joins for slightly larger tables.
