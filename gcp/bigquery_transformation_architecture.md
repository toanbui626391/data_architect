# Data Transformation Architecture: BigQuery Native Platform

## 1. Executive Summary

This document details the Enterprise Data Transformation Architecture for **Google Cloud Platform (GCP) and BigQuery**. Following the ingestion layer, this architecture defines how raw data is cleaned, modeled, and governed to provide high-quality, analytics-ready datasets.

In strict adherence to our architectural guidelines, this design relies exclusively on **native GCP solutions**—specifically **Dataform** running directly within BigQuery. By combining the Medallion Architecture (Bronze, Silver, Gold) with Kimball Dimensional Modeling, we establish a scalable, robust, and highly observable transformation pipeline.

---

## 2. Transformation Architectural Principles

1.  **Native Orchestration:** We strictly use **Dataform** (integrated natively into BigQuery) for defining, managing, and executing SQL-based transformations. No third-party orchestrators or external compute are used for standard in-warehouse data movement.
2.  **Declarative Engineering:** Transformations are written declaratively in SQLX. Dataform automatically infers the dependency graph (DAG) and executes it efficiently using BigQuery's serverless compute.
3.  **Shift-Left Data Quality:** Data quality is not an afterthought. Assertions (uniqueness, null checks, referential integrity) are baked directly into the Dataform models and run concurrently with pipeline execution.
4.  **Idempotent Operations:** All transformation scripts (whether tables or incremental updates) must be idempotent. Re-running a pipeline should safely overwrite or gracefully merge data without creating duplicates.

---

## 3. System Context Diagram

The following diagram illustrates the flow of data through the transformation layers, orchestrated by Dataform, with integrated Data Quality and Observability.

```mermaid
flowchart TD
    subgraph Dataform Orchestration Layer
        DF["Dataform (SQLX DAG)"]
        Git["Cloud Source Repositories / GitHub"]
        
        Git -->|CI/CD| DF
    end

    subgraph BigQuery Data Warehouse
        Raw["Bronze Layer\n(Raw / Append-Only)"]
        Silver["Silver Layer\n(Cleansed / Standardized)"]
        Gold["Gold Layer\n(Kimball Dimensional Models)"]
        DeadLetter["Dead-Letter Tables\n(Failed DQ Checks)"]
        
        Raw -->|Dataform execution| Silver
        Silver -->|Dataform execution| Gold
        
        Silver -.->|DQ Assertion Failures| DeadLetter
    end

    subgraph Operations & Observability
        Logs["Cloud Logging"]
        Monitor["Cloud Monitoring & Alerts"]
        IS["INFORMATION_SCHEMA"]
        
        DF -->|Execution Logs| Logs
        Logs --> Monitor
        BigQuery -->|Billing/Perf Metrics| IS
    end

    DF -.->|Orchestrates| BigQuery
```

---

## 4. Data Modeling Strategy: Medallion & Kimball

We hybridize the Medallion architecture with Kimball Dimensional modeling to provide clear boundaries between raw ingestion and business-ready analytics.

### 4.1 Bronze Layer (Raw)
*   **Purpose:** The landing zone for ingested data.
*   **Structure:** Mirrors the source systems exactly. Append-only tables with no updates or deletes. Includes metadata columns like `_ingested_at` and `_source_file`.
*   **Data Quality:** Minimal. We accept all data to ensure we never lose source records due to strict initial schema validations.

### 4.2 Silver Layer (Cleansed & Standardized)
*   **Purpose:** The enterprise source of truth. Data is cleansed, typed, and deduplicated.
*   **Structure:** Highly normalized, typically mirroring the source structure but resolving historical slowly changing dimensions (SCDs) and standardizing naming conventions (e.g., `snake_case` for all columns).
*   **Transformation:** We use Dataform `incremental` tables here with robust `MERGE` logic to handle deduplication from the append-only Bronze layer.

### 4.3 Gold Layer (Kimball Dimensional Models)
*   **Purpose:** Optimized for business intelligence (BI), reporting, and ad-hoc analytics.
*   **Structure:** Strict **Kimball Dimensional Modeling**. The data is denormalized into **Fact tables** (business events, metrics) and **Dimension tables** (context, attributes).
*   **Transformation:**
    *   **Dimensions:** Managed as Type 1 (overwrite) or Type 2 (historical tracking) Slowly Changing Dimensions using Dataform.
    *   **Facts:** Highly aggregated or grain-specific tables joining multiple Silver tables to answer specific business questions.
    *   BigQuery native features like **Clustering** and **Partitioning** are heavily applied here based on common query filters (e.g., partitioned by `transaction_date`).

---

## 5. Data Quality (DQ) Strategy

Ensuring trust in the data is paramount. We handle Data Quality natively within the transformation execution.

### 5.1 Dataform Assertions
Dataform provides native assertion capabilities. For every critical table in the Silver and Gold layers, we define:
*   **Uniqueness Checks:** Asserting that Primary Keys are strictly unique.
*   **Null Checks:** Ensuring critical fields (like foreign keys or financial amounts) are never null.
*   **Custom SQL Assertions:** Business logic checks (e.g., `order_total_amount >= 0`).

*If an assertion fails, the Dataform pipeline will halt downstream execution, preventing bad data from reaching the Gold layer.*

### 5.2 Dead-Letter Tables (DLT)
When utilizing complex transformations or incremental merges, records that fail logical validation (but shouldn't halt the entire pipeline) are routed to Dead-Letter Tables.
*   **Implementation:** A Dataform script attempts to cast/transform data. Records causing errors are captured via SQL `TRY_CAST` or explicit filtering and `INSERT`ed into a dedicated `_dlt` table for data engineering review, while the healthy records proceed.

### 5.3 BigQuery Table Constraints
While BigQuery does not actively enforce constraints during DML operations like traditional RDBMS, we utilize BigQuery's **Primary Key and Foreign Key constraints**.
*   **Benefit:** The BigQuery query optimizer uses these constraints to improve join performance and eliminate redundant execution paths, saving compute costs on heavy Gold layer queries.

---

## 6. Observability & Operations

Operating the pipeline natively means leveraging GCP's integrated observability stack.

### 6.1 Execution Monitoring (Cloud Logging)
Dataform natively integrates with Google Cloud Logging. Every pipeline run, SQL statement executed, and assertion checked is logged.
*   **Alerting:** We configure **Cloud Monitoring Log-Based Alerts**. If a Dataform execution emits a severity of `ERROR` (e.g., an assertion fails or a query timeouts), an alert is immediately routed via PagerDuty or Slack to the data engineering team.

### 6.2 Cost & Performance Tracking (`INFORMATION_SCHEMA`)
We do not use external tools to monitor warehouse performance. BigQuery's native `INFORMATION_SCHEMA` provides deep operational insights.
*   **`INFORMATION_SCHEMA.JOBS`:** Used to monitor the `total_bytes_billed` and `slot_ms` of every Dataform transformation. This helps us identify poorly optimized queries (e.g., missing partition filters) that are driving up costs.
*   **`INFORMATION_SCHEMA.TABLE_STORAGE`:** Used to monitor the physical footprint of the Bronze, Silver, and Gold layers, ensuring lifecycle policies are aggressively archiving old raw data.

### 6.3 CI/CD and Lifecycle Operations
*   **Environments:** Dataform handles environment isolation natively via **Workspaces**. Data Engineers develop in their own isolated workspace (querying a `dev` dataset).
*   **Deployment:** Dataform connects directly to our Git repository. Pushing to the `main` branch triggers a release configuration that compiles the SQLX into standard SQL and executes it against the production `prod` datasets.
