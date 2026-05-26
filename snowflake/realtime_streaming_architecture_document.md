# Real-Time Streaming Ingestion Architecture: Snowflake Native Platform

## 1. Executive Summary
This document outlines the Enterprise **Real-Time Streaming Architecture** designed specifically for Snowflake. 

While batch and micro-batch ingestion (Standard Snowpipe) are sufficient for most workloads, specific use cases—such as fraud detection, operational monitoring, and live telemetry—require sub-second latency. This architecture utilizes the **Snowpipe Streaming API** to achieve ultra-low latency ingestion while completely bypassing the cloud storage (S3/GCS) staging layer.

Crucially, this document defines how to maintain robustness in a live stream by handling **Schema Discrepancies and Data Format Evolution** without crashing the streaming channel.

---

## 2. Streaming Architectural Principles
1.  **Network Direct (No Cloud Storage):** Data is streamed continuously over the network directly into Snowflake Bronze tables. There are no intermediate CSV/Parquet files to manage, reducing both latency and cloud provider storage API costs.
2.  **Connector First:** We prioritize using the official Snowflake Kafka Connector over writing custom streaming application code whenever possible.
3.  **Continuous Orchestration:** Streaming milliseconds into a raw table is useless if transformations run hourly. Real-time streams must be paired with low-latency **Dynamic Tables** for continuous downstream transformation.
4.  **Resilient Streams:** A live stream must never crash due to a malformed payload. Schema evolution and error handling are managed at the stream-connector layer.

---

## 3. The Real-Time Architecture

The following diagram illustrates the flow of data from live applications through the message bus directly into Snowflake, including how malformed records are handled via a Dead Letter Topic (DLT).

```mermaid
flowchart LR
    subgraph DataProducers [Event Producers]
        App["Mobile / Web Apps"]
        Microservices["Backend Microservices"]
    end

    subgraph MessageBus [Streaming Platform]
        direction TB
        Kafka["Apache Kafka / MSK"]
        DLT[("Dead Letter Topic <br>&#40;DLT&#41;")]
    end

    subgraph Snowflake [Snowflake Data Cloud]
        direction TB
        Connector["Snowflake Kafka Connector <br>&#40;Streaming API&#41;"]
        Table[("Raw Bronze Table")]
        DT["Dynamic Table <br>&#40;Lag = 1 MINUTE&#41;"]
        Silver[("Clean Silver Table")]
    end

    App -->|JSON Events| Kafka
    Microservices -->|JSON Events| Kafka
    Kafka -->|Sub-second write| Connector
    
    %% Handling Discrepancies at the Connector
    Connector -->|Malformed Record| DLT
    Connector -->|Valid Record Insert| Table
    
    Table -.->|Continuous Refresh| DT
    DT --> Silver

    %% Styling
    classDef storage fill:#e2f0d9,stroke:#385723,stroke-width:1px,color:#000;
    classDef bad fill:#f8cecc,stroke:#b85450,stroke-width:1px,color:#000;
    classDef process fill:#dae8fc,stroke:#6c8ebf,stroke-width:1px,color:#000;
    
    class Table,Silver storage;
    class DLT bad;
    class Connector,DT process;
```

---

## 4. Streaming Implementation Patterns

### 4.1 Pattern 1: The Snowflake Kafka Connector (Primary)
The most simple and effective way to implement Snowpipe Streaming is via the official **Snowflake Kafka Connector**. 
*   **How it works:** You deploy the connector on your Kafka or Confluent cluster. You configure a topic mapping to a Snowflake table. The connector reads the topic and calls the Streaming API to insert rows.
*   **Exactly-Once Semantics:** The connector and Snowflake API guarantee exactly-once delivery via offset tracking, preventing duplicate rows during network retries.

### 4.2 Pattern 2: Custom Application SDK (Fallback)
If your architecture does not use Kafka (e.g., you rely solely on Kinesis, Pub/Sub, or custom microservices), Snowflake provides the **Ingest SDK** in Java and Python.
*   **How it works:** Your backend microservice embeds the SDK and streams `Map<String, Object>` rows directly into Snowflake.
*   **Trade-off:** Requires custom Java/Python development to handle backpressure and error catching.

---

## 5. Handling Streaming Schema Evolution

When dealing with a live stream, upstream schema changes (e.g., a microservice suddenly adding a new telemetry field) happen instantaneously. The streaming connector must handle this without dropping the stream.

### 5.1 Native Schema Evolution via Schema Registry
When using the Kafka Connector paired with a Schema Registry (e.g., Confluent Schema Registry using Avro or Protobuf), Snowflake can automatically evolve the target tables.

*   **Implementation:**
    1.  The target Snowflake table must be created with `ENABLE_SCHEMA_EVOLUTION = TRUE`.
    2.  The Kafka Connector configuration must have `snowflake.ingestion.method = SNOWPIPE_STREAMING` and `snowflake.enable.schematization = TRUE`.
*   **Behavior (Added Columns):** When the upstream microservice registers a new Avro schema version with a new column, the Kafka Connector detects it, instructs Snowflake to run an `ALTER TABLE ADD COLUMN`, and continues streaming without interruption.
*   **Behavior (Deleted Columns):** Snowflake will **not** physically drop the column from the table (this preserves historical data). Instead, it automatically handles the missing data by inserting `NULL` into that column for all new streaming records. It also automatically drops the `NOT NULL` constraint if the column previously had one.
*   **Behavior (Changed Data Types):** Snowflake's native evolution does **not** support altering data types (e.g., changing an `INT` to a `STRING`). If a schema registry change modifies a data type, the connector will throw a casting error, and the record will be routed to the Dead Letter Topic (DLT) for engineering intervention.

### 5.2 The "VARIANT" Fallback (Schema-on-Read Streaming)
If you are streaming schemaless JSON without a Schema Registry, strict table schematization will fail when new fields appear. 

*   **Implementation:** The Kafka Connector is configured to stream the entire JSON payload into a single Snowflake `RECORD_CONTENT` column of type `VARIANT`.
*   **Behavior:** Because the column is `VARIANT`, any upstream addition or type change is accepted by Snowflake without error. The schema is enforced downstream in Snowflake using Dynamic Tables and `TRY_CAST` logic.

---

## 6. Handling Streaming Data Discrepancies (DLQ)

If a hard discrepancy occurs (e.g., an upstream service sends a fundamentally broken payload that violates the schema registry), the streaming connector must isolate the failure. **A bad record must never halt the live streaming pipeline.**

### 6.1 The Dead Letter Topic (DLT) Pattern
Unlike batch file ingestion where Snowflake handles the Dead Letter Queue, in a streaming architecture, the **Kafka Connector handles the quarantine process** before the data reaches Snowflake.

*   **Implementation Configuration:**
    Set the following properties in the Kafka Connector config:
    ```properties
    errors.tolerance = all
    errors.deadletterqueue.topic.name = "snowflake_ingest_dlq"
    errors.deadletterqueue.context.headers.enable = true
    ```
*   **Behavior:** When the connector attempts to cast a malformed JSON payload and fails, it does not crash. It skips the message, writes the raw malformed payload and the error reason to the `snowflake_ingest_dlq` topic, and continues streaming the healthy records into Snowflake.
*   **Alerting:** The Data Engineering team monitors the DLT topic to investigate application drift.

### 6.2 Top Causes of Bad Records & Remediation Strategy

When a record is routed to the DLT, it is typically due to one of the following root causes. Implementing the right remediation strategy is critical to maintaining data integrity.

#### 1. Schema Registry Mismatch (Data Contract Violation)
*   **Cause:** The upstream microservice deployed a new payload structure (e.g., changing a `user_id` from an Integer to a UUID String) that violates the enforced Avro/Protobuf schema.
*   **Remediation (Shift-Left):** Enforce strict Schema Validation at the Producer level so the Kafka broker rejects the malformed message *before* it enters the streaming pipeline.

#### 2. Data Type Casting Errors
*   **Cause:** When mapping JSON directly to strongly-typed Snowflake columns, the connector will fail if an upstream system sends a string (e.g., `"N/A"`) into a strict `INT` column.
*   **Remediation (Fix & Replay):** Consume the DLT into a temporary staging table, run a SQL transformation to sanitize the data (e.g., `IFF(val='N/A', NULL, val)`), and merge the fixed records into the target Bronze table.

#### 3. Malformed Payload (Deserialization Failure)
*   **Cause:** The message payload is fundamentally corrupt or truncated (e.g., missing a closing brace `}` in a JSON string). The connector cannot parse the byte array.
*   **Remediation:** Alert the upstream software engineering team immediately. This is an application-level bug producing invalid JSON.

#### 4. Message Size Exceeded
*   **Cause:** The record exceeds Snowflake's maximum row size limit (16MB for a `VARIANT` column).
*   **Remediation (Claim Check Pattern):** Massive payloads (like base64 encoded images or massive documents) should be written to cloud storage (S3/GCS). The Kafka stream should only pass the *URL pointer* to that object, rather than embedding the entire payload in the event.

---

## 7. Downstream Orchestration (Near Real-Time Views)

Writing data in milliseconds is useless if transformations take hours. To maintain the low-latency pipeline through the transformation layer, we avoid standard Airflow batch schedules.

*   **Dynamic Tables:** All data from the streaming Bronze table is transformed using Snowflake Dynamic Tables.
*   **Configuration:** We set the `TARGET_LAG = '1 MINUTE'` (or 'DOWNSTREAM') on the Dynamic Table. 
*   **Behavior:** Snowflake continuously reads the streaming raw table using invisible streams, executing incremental refreshes to populate the modeled Silver table. This provides analysts with near real-time dashboards automatically.
