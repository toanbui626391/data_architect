# Databricks Architect Learning Plan
*Comprehensive roadmap for Data Architects & Solution Architects.*

***

## Overview

| Role | Focus |
|---|---|
| Data Architect | Modeling, governance, pipelines |
| Solution Architect | End-to-end design, sizing, cloud |

**Target Certifications:**
* Data Engineer Associate & Professional
* Solutions Architect Champion

**Estimated Duration:** 6–9 months

***

## Phase 1: Core Fundamentals
*Duration: 4 weeks*

### 1.1 Databricks Architecture
* Control Plane vs. Data Plane separation.
* Classic vs. Serverless compute models.
* Cloud provider integrations (AWS/Azure/GCP).
* Networking: VNet injection, Private Link.

### 1.2 Apache Spark Engine
* Driver and Worker node roles.
* RDDs vs. DataFrames vs. Datasets.
* Lazy evaluation and the DAG model.
* Catalyst Optimizer and Tungsten.
* Partitions, shuffles, and spill to disk.

### 1.3 Delta Lake
* ACID transactions and the transaction log.
* Schema enforcement and schema evolution.
* `OPTIMIZE`, `ZORDER`, `VACUUM`.
* Time travel and version history.
* Liquid Clustering (vs. Hive-style partitioning).

### 1.4 Cluster Configuration
* All-Purpose vs. Job Clusters.
* Single Node vs. Standard clusters.
* Autoscaling and spot instance strategies.
* Runtime versions and init scripts.

**Resources:**
* Databricks Academy: "Apache Spark Programming"
* Docs: `docs.databricks.com/delta`
* Book: "Delta Lake: The Definitive Guide"

***

## Phase 2: Data Engineering
*Duration: 6 weeks*

### 2.1 Medallion Architecture
* **Bronze:** Raw ingestion, no transformation.
* **Silver:** Cleansed, deduplicated, typed.
* **Gold:** Aggregated, business-ready data.
* Naming conventions and lifecycle policies.

### 2.2 Data Ingestion
* **Auto Loader:** Cloud file discovery with checkpointing.
* **Delta Live Tables (DLT):** Declarative pipeline framework.
* DLT expectations and data quality rules.
* Structured Streaming fundamentals.
* `foreachBatch` and trigger intervals.

### 2.3 Change Data Capture (CDC)
* `MERGE INTO` for upserts in Delta Lake.
* CDC patterns: APPEND, APPLY CHANGES.
* DLT `APPLY CHANGES INTO` command.
* SCD Type 1 and SCD Type 2 patterns.

### 2.4 Job Orchestration
* Databricks Workflows and task graphs.
* Conditional branching and retry logic.
* Passing parameters between tasks.
* Notebook, Python, DLT, and SQL tasks.
* Triggering via API and external schedulers.

### 2.5 Performance Design
* Partition pruning strategies.
* Bloom filters on high-cardinality columns.
* Caching: `CACHE TABLE` vs. `.cache()`.
* Avoiding small file problems.
* Photon engine benefits and use cases.

**Resources:**
* Databricks Academy: "Data Engineering with Databricks"
* Databricks: "Delta Live Tables Guide"

***

## Phase 3: Governance & Security
*Duration: 4 weeks*

### 3.1 Unity Catalog
* Three-level namespace: Catalog > Schema > Table.
* Metastore design for enterprise multi-workspaces.
* External locations and Storage Credentials.
* Managed vs External tables and when to use each.
* System tables for audit logging and lineage.

### 3.2 Data Access Control
* `GRANT` and `REVOKE` with SQL syntax.
* Row-level security using dynamic views.
* Column-level security and masking policies.
* Attribute-based access control (ABAC).

### 3.3 Security Architecture
* Service Principals for automation.
* Secret management with Databricks Secrets.
* Network isolation and IP access lists.
* Cloud IAM roles and instance profiles.
* Compliance: GDPR, HIPAA considerations.

### 3.4 Data Lineage & Observability
* Column-level lineage in Unity Catalog.
* Data quality monitoring with DLT expectations.
* Integrating with Alation, Atlan, or Collibra.

**Resources:**
* Databricks: "Unity Catalog Best Practices"
* Databricks Academy: "Data Governance with Unity Catalog"

***

## Phase 4: Serverless & SQL Analytics
*Duration: 3 weeks*

### 4.1 Databricks SQL (DBSQL)
* Serverless vs. Classic SQL Warehouses.
* Warehouse sizing tiers (2X-Small to 4X-Large).
* Query optimization with Query History.
* Materialized views vs. standard views.
* Connection via JDBC/ODBC to BI tools.

### 4.2 BI Integration Patterns
* Connecting Power BI and Tableau.
* Partner Connect setup.
* Direct Query vs. Import mode trade-offs.

### 4.3 Data Sharing
* Delta Sharing protocol.
* Open sharing across organizations.
* Recipient management and auditing.

**Resources:**
* Databricks: "Databricks SQL User Guide"
* Databricks Academy: "SQL Analytics on Databricks"

***

## Phase 5: AI & Machine Learning
*Duration: 5 weeks*

### 5.1 MLflow & Experiment Tracking
* Tracking experiments, runs, and metrics.
* Model Registry: staging and production.
* Autologging for common ML frameworks.

### 5.2 Feature Engineering
* Databricks Feature Store concepts.
* Offline vs. Online feature serving.
* Point-in-time correct lookups.

### 5.3 MLOps Pipelines
* CI/CD for ML model promotion.
* Model serving endpoints (real-time inference).
* A/B testing with traffic split.
* Monitoring model drift in production.

### 5.4 Generative AI & MosaicAI
* Foundation Model APIs (pay-per-token).
* Vector Search for RAG architectures.
* AI Playground for prompt engineering.
* Compound AI systems architecture.
* Fine-tuning with MosaicAI Training.

**Resources:**
* Databricks: "Machine Learning on Databricks"
* Databricks Academy: "ML in Production"

***

## Phase 6: Solution Architecture Design
*Duration: 4 weeks*

### 6.1 Cloud Architecture Patterns
* Landing Zone design for Databricks.
* Hub-and-spoke vs. mesh topologies.
* Multi-region and disaster recovery design.
* Cost allocation with tagging strategies.

### 6.2 Migration Patterns
* Migrating from Hadoop/Hive to Databricks.
* Migrating from Snowflake or Synapse.
* Lift-and-shift vs. re-architecture strategies.

### 6.3 Sizing & Cost Optimization
* Estimating DBU consumption per workload.
* Right-sizing clusters for ETL vs. ad hoc.
* Reserved vs. spot/preemptible instances.
* Using Serverless to reduce management overhead.

### 6.4 Real-World Architecture Patterns
* Lambda Architecture on Databricks.
* Kappa Architecture using Structured Streaming.
* Data Mesh with Unity Catalog as a registry.
* Lakehouse Federation (query external systems).

**Resources:**
* Databricks: "Solutions Architect Reference Architectures"
* Databricks: "The Big Book of Data Engineering"

***

## Phase 7: Certification Preparation
*Duration: 3 weeks*

### 7.1 Associate Level
* **Exam:** Databricks Certified Data Engineer Associate
* Focus: Delta Lake, Spark SQL, basic pipelines.
* Practice exam sets from Udemy/Whizlabs.

### 7.2 Professional Level
* **Exam:** Databricks Certified Data Engineer Professional
* Focus: Streaming, DLT, performance, security.
* Build and review personal portfolio projects.

### 7.3 Solutions Architect Champion
* **Exam:** Databricks Certified Solutions Architect Champion
* Focus: End-to-end design, sizing, governance.
* Complete official Databricks Architect training.

***

## Quick Reference: Key Concepts

### Compute Types
* **Serverless:** Instant startup, no cluster management.
* **Job Cluster:** Ephemeral, auto-terminates after a job.
* **All-Purpose:** Persistent, collaborative, for development.

### Storage Layers
* **Managed Table:** Databricks owns data files.
* **External Table:** You own and control data files.
* **Volume:** For non-tabular files (CSV, images, PDFs).

### Key Design Principles
* Govern data at the Catalog layer, not the cluster layer.
* Prefer Serverless for SQL and DLT workloads.
* Use Job Clusters for ETL; never use All-Purpose in production.
* Always checkpoint Structured Streaming jobs.
