# Real-Time Ingestion Architecture: Databricks Lakehouse

## 1. Executive Summary
This document outlines the Enterprise **Real-Time Data Ingestion Architecture** designed specifically for the **Databricks Data Intelligence Platform**. 

The objective is to establish a unified, highly scalable streaming pipeline capable of ingesting data from multiple sources (message buses and cloud storage files) with sub-second to minute-level latency. By leveraging Databricks-native streaming technologies—specifically **Auto Loader**, **Structured Streaming**, and **Delta Live Tables (DLT)**—we eliminate the need for complex, third-party orchestration tools while maintaining strict Data Quality and Schema Evolution controls.

---

## 2. Multi-Source Streaming Flow

The following diagram illustrates how data flows continuously from various sources through the Medallion Architecture (Bronze, Silver, Gold) using Delta Lake and Delta Live Tables.

```mermaid
flowchart TD
    %% External Sources
    subgraph DataSources [External Sources]
        direction TB
        Files[("Cloud Storage Stage <br>&#40;S3 / ADLS&#41;")]
        Kafka(("Kafka / EventHubs <br>&#40;Message Bus&#41;")]
    end

    %% Security Boundary
    subgraph CustomerVPC [Customer VPC / Data Plane]
        direction TB
        
        %% Ingestion Compute
        subgraph Compute [Databricks Compute Clusters]
            direction TB
            AL["Auto Loader <br>&#40;Files&#41;"]
            Spark["Structured Streaming <br>&#40;Kafka&#41;"]
        end

        %% Medallion Storage
        subgraph Storage [Delta Lake / Cloud Storage]
            direction TB
            Bronze[("Bronze <br>&#40;Raw&#41;")]
            Silver[("Silver <br>&#40;Cleansed&#41;")]
            Gold[("Gold <br>&#40;Aggregates&#41;")]
            DLQ[("Quarantine <br>&#40;DLQ&#41;")]
        end
    end

    %% Databricks Control Plane (Monitoring / DQ)
    subgraph ControlPlane [Databricks Control Plane]
        direction TB
        DLT["Delta Live Tables <br>&#40;Orchestration & DQ&#41;"]
        EventLog["DLT Event Log <br>&#40;System Tables&#41;"]
        Alerts["Databricks Alerts <br>&#40;Email/Slack&#41;"]
    end

    %% Security Routes
    VPCE["PrivateLink / Secure Cluster Connectivity"]

    %% Flow: Sources -> Compute
    Files -.->|IAM/Managed Identity| AL
    Kafka -.->|mTLS/SASL| Spark
    
    %% Flow: Compute -> Storage (via DLT)
    AL --> Bronze
    Spark --> Bronze
    
    %% Flow: DLT Pipeline & Data Quality
    Bronze -->|DLT Expectations| Silver
    Bronze -.->|Fails Expectation| DLQ
    Silver --> Gold

    %% Flow: Monitoring & Networking
    Compute <-->|No Public IPs| VPCE
    VPCE <--> ControlPlane
    
    %% DQ and Alerting
    DLT -.->|Logs Metrics & DQ Failures| EventLog
    EventLog -.->|Triggers| Alerts

    %% Styling
    classDef storage fill:#e2f0d9,stroke:#385723,stroke-width:1px,color:#000;
    classDef process fill:#dae8fc,stroke:#6c8ebf,stroke-width:1px,color:#000;
    classDef bad fill:#f8cecc,stroke:#b85450,stroke-width:1px,color:#000;
    classDef monitor fill:#fff2cc,stroke:#d6b656,stroke-width:1px,color:#000,stroke-dasharray: 5 5;
    classDef network fill:#f9f9f9,stroke:#666,stroke-width:2px,color:#000,stroke-dasharray: 5 5;
    
    class Files,Kafka,Bronze,Silver,Gold storage;
    class AL,Spark,DLT process;
    class DLQ bad;
    class EventLog,Alerts monitor;
    class CustomerVPC,ControlPlane,VPCE network;
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

### 6.4 Data Quality Requirements per Medallion Layer
To maintain trust without creating brittle pipelines, data quality rules must be applied progressively across the layers:

1.  **Bronze Layer (Capture Everything):**
    *   **Requirement:** *Zero data loss.* Do not filter out bad business data here. 
    *   **Rules:** Enforce only structural integrity. Use schema evolution and `_rescued_data` to ensure unexpected columns or data type mismatches do not crash the pipeline. All raw events must be captured for auditability and replayability.
2.  **Silver Layer (Strict Conformance):**
    *   **Requirement:** *Syntactic correctness and deduplication.*
    *   **Rules:** Apply strict `@expect_or_drop` rules for Primary Keys (`id IS NOT NULL`) and deduplicate streams using `APPLY CHANGES INTO`. Filter out corrupted records into the DLQ (Quarantine). Data landing in Silver must be clean enough for Data Scientists to trust.
3.  **Gold Layer (Business Logic):**
    *   **Requirement:** *Semantic and business correctness.*
    *   **Rules:** Apply `@expect` rules to validate business constraints (e.g., `order_total > 0`, `status IN ('Pending', 'Shipped')`). Ensure foreign keys joining to dimension tables are valid. Failures here often indicate logic bugs rather than ingestion errors.

---

## 7. Operational Best Practices

To ensure the Real-Time Ingestion Architecture runs efficiently, securely, and cost-effectively in production, adhere to the following best practices:

### 7.1 Compute & Cost Optimization
*   **Default to Serverless DLT:** Use Serverless DLT for automatic compute management and rapid scaling. If using Classic DLT, always enable **Enhanced Autoscaling** to handle sudden data spikes without over-provisioning.
*   **Strategic Execution Modes:** Do not run clusters continuously 24/7 unless sub-minute latency is a strict business requirement. Use `Trigger.AvailableNow` (Scheduled Micro-Batch) for hourly or daily ingestion to significantly reduce costs.
*   **Cluster Sizing (Classic DLT):** For streaming workloads, favor compute-optimized instances (e.g., AWS `c5` or Azure `Fsv2` series) over memory-optimized instances, as streaming is typically CPU-bound.

### 7.2 Storage & State Management
*   **Let DLT Manage Maintenance:** DLT automatically handles `OPTIMIZE` (file compaction) and `VACUUM` (stale file removal) for your Delta tables. Do not run these commands manually on DLT-managed tables.
*   **Checkpoint Locations:** Store stream checkpoints in robust cloud storage (S3/ADLS/GCS) rather than root DBFS to ensure state durability and avoid corruption during cluster restarts.
*   **Change Data Feed (CDF) Prudence:** Only enable CDF on source tables if downstream pipelines actually require incremental upserts (`APPLY CHANGES INTO`). Leaving it on unnecessarily consumes excess storage.

### 7.3 Data Quality & Schema Operations
*   **Monitor Rescued Data:** Regularly query the `_rescued_data` column in the Bronze layer. A sudden spike indicates an upstream application has silently changed its schema or data types, requiring engineering intervention.
*   **Quarantine (DLQ) Remediation:** Set up an operational workflow to review the Quarantine (Dead Letter Queue) tables weekly. Fix data anomalies at the source application whenever possible, rather than endlessly patching the ingestion pipeline.

### 7.4 CI/CD and Deployment
*   **Infrastructure as Code:** Deploy DLT pipelines exclusively using **Databricks Asset Bundles (DABs)** or Terraform. Never deploy or modify production pipelines manually via the UI.
*   **Environment Isolation:** Strictly separate Development, Staging, and Production workspaces. Use the `PREVIEW` DLT channel in Staging to catch runtime bugs before Databricks rolls out updates to your `CURRENT` Production channel.
