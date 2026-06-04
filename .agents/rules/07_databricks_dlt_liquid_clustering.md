# Databricks Streaming & Optimization Rules

When designing or writing code for the Databricks platform, you MUST adhere to the following architectural standards:

## 1. Delta Live Tables (DLT) for Streaming
*   **Mandatory Orchestration:** All streaming data pipelines (Bronze and Silver layers) MUST be implemented using the **Delta Live Tables (DLT)** framework.
*   **Declarative Paradigm:** Avoid manual Spark Structured Streaming `readStream` and `writeStream` orchestration code (e.g., manually managing `.option("checkpointLocation", "...")`). Rely on DLT's declarative `CREATE OR REFRESH STREAMING TABLE` syntax.
*   **Quality Gates:** Implement data quality natively using DLT Expectations (`CONSTRAINT ... EXPECT ... ON VIOLATION WARN/FAIL`).

## 2. Liquid Clustering over Partitioning
*   **Optimization Standard:** Use **Liquid Clustering** as the default data layout optimization strategy for all new Delta tables instead of traditional Hive-style partitioning or Z-Ordering.
*   **Syntax:** Use the `CLUSTER BY (col1, col2)` syntax in table definitions.
*   **Forbidden Practice:** DO NOT use `PARTITIONED BY` in Databricks SQL or Spark code unless explicitly requested by the user for a highly specialized edge case (e.g., maintaining an older system). Liquid clustering automatically adapts data layout over time, preventing over-partitioning and the small file problem.
