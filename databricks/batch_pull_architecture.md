# Databricks Batch Pull Ingestion Architecture

## 1. Executive Summary

This document outlines the architectural design for a **Batch Pull Ingestion Pipeline** bringing data from enterprise applications like **SAP (ERP)** and **Salesforce (CRM)** into a Data Warehouse built on the **Databricks Data Intelligence Platform**. 

Unlike real-time push (webhook) systems, this architecture relies on Databricks itself to proactively connect to, query, and extract data in scheduled batches. It leverages the **Medallion Architecture** to process the raw data into business-ready analytical datasets.

---

## 2. Architecture Diagram

```mermaid
flowchart TD
    subgraph EnterpriseSources [Enterprise Source Systems]
        SAP[("SAP ERP <br/> (JDBC / OData)")]
        SFDC[("Salesforce CRM <br/> (Bulk API / SOQL)")]
    end

    subgraph DatabricksWorkspace [Databricks Data Intelligence Platform]
        subgraph IngestionOrchestration [Ingestion & Orchestration]
            Workflows["Databricks Workflows <br/> (Scheduler)"]
            Extraction["Spark Extraction Job <br/> (API/JDBC Connectors)"]
            Workflows -->|Triggers Schedule| Extraction
        end

        subgraph Medallion [Medallion Data Lakehouse]
            Bronze[("Bronze Layer <br/> (Raw Delta Tables)")]
            Silver[("Silver Layer <br/> (Cleansed / Upserts)")]
            Gold[("Gold Layer <br/> (Star Schema DW)")]
        end

        subgraph Governance [Unity Catalog]
            AccessControl["Data Lineage & Access Control"]
        end

        subgraph Consumption [Consumption Tier]
            DBSQL["Databricks SQL <br/> (Serverless Compute)"]
            BI["BI Tools <br/> (PowerBI / Tableau)"]
        end
    end

    %% Data Extraction Flow
    Extraction -->|1. Executes Queries| SAP
    Extraction -->|1. Executes Queries| SFDC
    
    SAP -.->|2. Returns Data &#40;JSON/CSV&#41;| Extraction
    SFDC -.->|2. Returns Data &#40;JSON/CSV&#41;| Extraction

    %% Medallion Processing Flow
    Extraction -->|3. Append Raw Payload| Bronze
    Bronze -->|4. Delta MERGE (Upsert)| Silver
    Silver -->|5. Aggregate & Join| Gold

    Gold -.-> AccessControl
    Gold --> DBSQL
    DBSQL --> BI

    %% Styling
    classDef storage fill:#e2f0d9,stroke:#385723,stroke-width:1px,color:#000;
    classDef process fill:#dae8fc,stroke:#6c8ebf,stroke-width:1px,color:#000;
    classDef db fill:#fce4d6,stroke:#d99694,stroke-width:1px,color:#000;
    classDef gov fill:#fff2cc,stroke:#d6b656,stroke-width:1px,color:#000,stroke-dasharray: 5 5;

    class SAP,SFDC,Bronze,Silver,Gold db;
    class Extraction,Workflows,DBSQL process;
    class Governance,AccessControl gov;
```

---

## 3. Core Components & Responsibilities

### 3.1. Databricks Workflows (The Orchestrator)
Instead of an external scheduler (like Airflow or Control-M), **Databricks Workflows** manages the pipeline dependencies. It triggers the extraction jobs on a defined schedule (e.g., nightly, every 4 hours). If a pull fails (due to source system downtime), Workflows handles the automatic retries.

### 3.2. Extraction Jobs (The Pull Mechanism)
A Databricks Job Cluster runs Python/PySpark or Scala notebooks designed specifically to connect to the source systems.
*   **Salesforce Extraction:** Uses Databricks native partner connectors, third-party Spark connectors (e.g., `spark-salesforce`), or Python scripts utilizing the **Salesforce Bulk API 2.0**. It submits a SOQL query, waits for the batch to process on Salesforce's servers, and downloads the resulting CSV directly into memory or cloud storage.
*   **SAP Extraction:** Pulling from SAP requires navigating its proprietary application layer. We typically use a specialized JDBC driver (e.g., CData, Theobald Software) or extract from SAP's exposed **OData REST Services**.

### 3.3. Ingestion Patterns
The extraction job relies on two primary data load patterns:
1.  **Full Load (Snapshot):** Queries `SELECT * FROM table`. Used for dimension tables that are small (e.g., Product Categories) or for the initial historical backfill.
2.  **Incremental Load (Watermarking):** The job queries the target table for the maximum `last_modified_date` it has processed, and passes that date to the source system: `SELECT * FROM table WHERE last_modified_date > 'watermark'`. 

---

## 4. The Medallion Architecture Processing

Once the extraction job pulls the data into Databricks, it moves through three stages of refinement.

### 4.1. Bronze Layer (Raw)
*   **Purpose:** To land the data exactly as it arrived from SAP/Salesforce without applying business logic or altering columns.
*   **Action:** The Extraction Job writes the payload as a **Delta Table** using `mode("append")`. We also append pipeline metadata (e.g., `_ingest_timestamp`, `_source_system`). 
*   **Benefit:** If a bug is discovered in our Silver layer transformations, we can replay the data from Bronze without querying the source system again.

### 4.2. Silver Layer (Cleansed & Conformed)
*   **Purpose:** To clean the data, enforce data types (e.g., ensuring an SAP Date string becomes a standard SQL Date), and deduplicate records.
*   **Action:** We use the Delta Lake `MERGE INTO` command. Because we perform incremental pulls, we might receive the same Salesforce Account ID multiple times if it was updated frequently. `MERGE INTO` acts as an **Upsert**: it updates the existing record if the ID matches, or inserts a new row if the ID is new.

### 4.3. Gold Layer (Data Warehouse / Star Schema)
*   **Purpose:** To present business-ready, aggregated data optimized for BI reporting. 
*   **Action:** Databricks SQL scripts run to join SAP financial data with Salesforce account data, creating denormalized Fact and Dimension tables (Star Schema).

---

## 5. Security & Governance

1.  **Credentials:** Usernames, API keys, and OAuth tokens for Salesforce and SAP are stored securely in **Databricks Secrets** (or Azure Key Vault / AWS Secrets Manager) and are injected into the extraction notebooks at runtime.
2.  **Network:** Databricks clusters use PrivateLink or VPC Peering to communicate securely over private networks to on-premises SAP databases.
3.  **Data Lineage:** **Unity Catalog** automatically tracks column-level lineage, allowing administrators to trace a field in a PowerBI dashboard all the way back to the exact Salesforce table it was pulled from.
