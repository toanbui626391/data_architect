# Real-Time Ingestion Architecture: Databricks Lakehouse

## 1. Executive Summary
This document outlines the Enterprise **Real-Time Data Ingestion Architecture** designed specifically for the **Databricks Data Intelligence Platform**. 

The objective is to establish a unified, highly scalable streaming pipeline capable of ingesting data from multiple sources (message buses and cloud storage files) with sub-second to minute-level latency. By leveraging Databricks-native streaming technologies—specifically **Auto Loader**, **Structured Streaming**, and **Delta Live Tables (DLT)**—we eliminate the need for complex, third-party orchestration tools while maintaining strict Data Quality and Schema Evolution controls.

---

## 2. Multi-Source Streaming Flow

The following diagram illustrates how data flows continuously from various sources through the Medallion Architecture (Bronze, Silver, Gold) using Delta Lake and Delta Live Tables.

```mermaid
flowchart TD
    subgraph DataSources [Multi-Source Ingestion]
        direction TB
        Files[("Cloud Storage <br>&#40;S3 / ADLS Gen2 / GCS&#41; <br> JSON/CSV/Parquet")]
        Kafka(("Message Bus <br>&#40;Kafka / Kinesis / EventHubs&#41; <br> Streaming Events"))
    end

    subgraph DatabricksLakehouse [Databricks: Delta Live Tables Pipeline]
        
        subgraph IngestionEngine [Ingestion Layer]
            AL["Databricks Auto Loader <br>&#40;cloudFiles&#41;"]
            Spark["Structured Streaming <br>&#40;Kafka Connector&#41;"]
            Files -. Cloud Event/SQS .-> AL
            Kafka --> Spark
        end

        subgraph Bronze [Bronze Layer - Raw]
            BronzeAL[("Bronze Delta Table <br>&#40;Raw Files&#41;")]
            BronzeKaf[("Bronze Delta Table <br>&#40;Raw Events&#41;")]
            AL -->|Append Only| BronzeAL
            Spark -->|Append Only| BronzeKaf
        end

        subgraph Silver [Silver Layer - Cleansed & Validated]
            SilverDT[("Silver Delta Table <br>&#40;Cleansed&#41;")]
            DLQ[("Quarantine Table <br>&#40;DLQ&#41;")]
            
            BronzeAL -->|DLT Expectations| SilverDT
            BronzeKaf -->|DLT Expectations| SilverDT
            BronzeAL -.->|Fails Expectation| DLQ
            BronzeKaf -.->|Fails Expectation| DLQ
        end

        subgraph Gold [Gold Layer - Aggregated]
            GoldDT[("Gold Delta Table <br>&#40;Business Aggregates&#41;")]
            SilverDT -->|Streaming Aggregation| GoldDT
        end
    end

    %% Style classes
    classDef storage fill:#e2f0d9,stroke:#385723,stroke-width:1px,color:#000;
    classDef process fill:#dae8fc,stroke:#6c8ebf,stroke-width:1px,color:#000;
    classDef bad fill:#f8cecc,stroke:#b85450,stroke-width:1px,color:#000;
    
    class Files,Kafka,BronzeAL,BronzeKaf,SilverDT,GoldDT storage;
    class AL,Spark process;
    class DLQ bad;
```

---

## 3. The Real-Time Ingestion Engines

Databricks provides specialized engines optimized for different types of real-time sources. We standardize on the following two patterns:

### 3.1 Pattern 1: Databricks Auto Loader (For Cloud Storage Files)
For upstream systems that drop files (JSON, CSV, Parquet) into Cloud Storage (AWS S3, Azure ADLS Gen2, Google GCS), we utilize **Databricks Auto Loader**.

*   **How it Works:** Auto Loader incrementally and efficiently processes new data files as they arrive in cloud storage without any additional setup. Under the hood, it configures cloud provider event notifications (e.g., AWS SQS or Azure Event Grid) automatically.
*   **Benefits:** Completely eliminates the need to run expensive `ls` (list) operations on massive directories to find new files. It is stateless and highly cost-effective for continuous file ingestion.

```python
# Example: Auto Loader syntax reading JSON from cloud storage
df = (spark.readStream
  .format("cloudFiles")
  .option("cloudFiles.format", "json")
  .option("cloudFiles.inferColumnTypes", "true")
  .load("s3://landing-bucket/raw_data/")
)
```

### 3.2 Pattern 2: Structured Streaming (For Message Buses)
For systems requiring ultra-low latency (e.g., IoT telemetry, clickstreams) passing through Apache Kafka, Confluent, or AWS Kinesis, we utilize native **Spark Structured Streaming**.

*   **How it Works:** Databricks connects directly to the Kafka brokers, continuously pulling micro-batches of events and writing them natively into Bronze Delta tables.
*   **Benefits:** Sub-second latency with exactly-once processing guarantees natively managed by Spark offsets.

---

## 4. Transformation & Orchestration: Delta Live Tables (DLT)

Once data lands in the pipeline, orchestrating the flow from Bronze to Silver to Gold manually requires complex checkpoint management. To simplify this, we utilize **Delta Live Tables (DLT)**.

DLT is a declarative framework (similar to Snowflake Dynamic Tables) that allows data engineers to define *what* the data should look like, while Databricks automatically manages the *how* (infrastructure, cluster scaling, and stream checkpoints).

### 4.1 Streaming Tables vs Materialized Views
In DLT, we utilize two distinct concepts to optimize real-time performance:
*   **Streaming Tables (Bronze & Silver):** Process data exactly once. They are append-only and strictly evaluate new records arriving in the stream, making them highly efficient for parsing massive event logs.
*   **Materialized Views (Gold):** Used for the final presentation layer. DLT automatically computes incremental updates to aggregations (e.g., calculating rolling averages or total sales per region) based on the fresh data arriving in Silver.

---

## 5. Schema Evolution & Format Discrepancies

Streaming data is notorious for unexpected schema drift. Our architecture employs Databricks' robust evolution mechanisms to ensure pipelines never crash.

### 5.1 Auto Loader Schema Evolution
When using Auto Loader, we enable `schemaEvolutionMode`. If an upstream application adds a new column to a JSON file, Auto Loader will automatically detect it and run an `ALTER TABLE` command on the Bronze Delta table to append the new column dynamically.

### 5.2 The "Rescued Data" Column
If an upstream system sends a string into an integer column (a data type discrepancy), a standard pipeline would crash. 
*   **The Solution:** Auto Loader includes a `_rescued_data` column. Instead of failing the stream, Databricks safely inserts a `null` into the integer column and stores the original, unparseable string inside the `_rescued_data` JSON blob. This ensures zero data loss while keeping the pipeline flowing.

---

## 6. Data Quality & Observability (DLT Expectations)

Ensuring data quality in a continuous stream requires inline validation. We utilize **DLT Expectations** to define data quality rules directly in the pipeline code.

### 6.1 The Three Levels of Enforcement
We apply Python decorators to our DLT Silver tables to enforce contracts:

1.  **Retain and Alert (`@expect`):** The data violates a minor rule. The record is loaded, but a data quality metric failure is recorded in the DLT event log.
    *   *Example:* `@expect("valid_timestamp", "timestamp > '2020-01-01'")`
2.  **Drop Bad Data (`@expect_or_drop`):** The data is fundamentally flawed and useless. The record is dropped completely from the Silver table.
    *   *Example:* `@expect_or_drop("valid_user_id", "user_id IS NOT NULL")`
3.  **Fail the Pipeline (`@expect_or_fail`):** A catastrophic data contract violation has occurred that compromises the entire dataset. The pipeline immediately halts to prevent corruption.

### 6.2 The Quarantine Pattern (DLQ)
Instead of simply dropping bad records, enterprise architectures demand a Dead Letter Queue (DLQ). In DLT, we implement a **Quarantine Pattern**:
*   A downstream DLT table is explicitly configured to capture the inverse of the Silver expectations. 
*   All malformed records (e.g., where `user_id IS NULL`) are routed to a `silver_quarantine` Delta table.
*   Data Engineers query this table to triage application bugs and repair the data.

### 6.3 Observability Alerts
The DLT Event Log captures all pipeline metrics. We configure Databricks SQL Alerts on the `event_log` table to trigger Webhook notifications to Slack/PagerDuty whenever:
*   A pipeline fails.
*   The rate of data dropped by `@expect_or_drop` exceeds a specified threshold (e.g., > 5% of the stream is malformed).
