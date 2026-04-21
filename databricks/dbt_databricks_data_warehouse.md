# Data Warehouse with dbt & Databricks
## A Data Architect's Concept Guide

> **Audience**: Data Architects designing
> production-grade data warehouses on Databricks
> with dbt as the transformation layer.
>
> **Goal**: Understand every core concept and
> how they fit together end-to-end.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [The Medallion Architecture](#2-the-medallion-architecture)
3. [Delta Lake — The Storage Foundation](#3-delta-lake)
4. [Unity Catalog — Governance Layer](#4-unity-catalog)
5. [dbt — The Transformation Engine](#5-dbt)
6. [dbt + Databricks Integration](#6-dbt--databricks-integration)
7. [Ingestion Patterns](#7-ingestion-patterns)
8. [Data Modeling Concepts](#8-data-modeling-concepts)
9. [Orchestration](#9-orchestration)
10. [Data Quality & Testing](#10-data-quality--testing)
11. [Performance & Optimization](#11-performance--optimization)
12. [Security & Access Control](#12-security--access-control)
13. [Observability & Lineage](#13-observability--lineage)
14. [How Everything Works Together](#14-how-everything-works-together)

---

## 1. Architecture Overview

A modern data warehouse on Databricks
follows this high-level flow:

```
┌─────────────────────────────────────┐
│         Source Systems              │
│  (databases, SaaS, files, streams)  │
└────────────────┬────────────────────┘
                 │ Ingest
                 ▼
┌─────────────────────────────────────┐
│   Ingestion Layer                   │
│   (Fivetran, Airbyte, Kafka,        │
│    Spark Structured Streaming)      │
└────────────────┬────────────────────┘
                 │ Raw files / Delta
                 ▼
┌─────────────────────────────────────┐
│   Cloud Object Storage              │
│   (S3 / ADLS / GCS)                 │
│   + Delta Lake format               │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│   Databricks Lakehouse              │
│   ┌──────────────────────────────┐  │
│   │  Unity Catalog (Governance)  │  │
│   └──────────────────────────────┘  │
│   ┌──────────────────────────────┐  │
│   │  Medallion Layers            │  │
│   │  Bronze → Silver → Gold      │  │
│   └──────────────────────────────┘  │
│   ┌──────────────────────────────┐  │
│   │  dbt (Transformations)       │  │
│   └──────────────────────────────┘  │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│   Consumption Layer                 │
│   (BI tools, ML, Data APIs)         │
└─────────────────────────────────────┘
```

**Key insight**: Databricks acts as the
compute AND storage engine. dbt is the
SQL-based transformation framework that
models your data inside Databricks.

---

## 2. The Medallion Architecture

The medallion architecture organizes data
into quality tiers using a metaphor of
bronze → silver → gold medals.

### 2.1 Bronze Layer (Raw)

- **What**: Exact copy of source data,
  no transformation applied.
- **Format**: Delta tables (preserving
  raw structure, schema-on-read).
- **Retention**: Full history retained.
- **Who writes**: Ingestion tools
  (Fivetran, Airbyte, Spark Streaming).
- **Key properties**:
  - Append-only preferred
  - Includes `_ingested_at` metadata
  - Source schema preserved as-is

```sql
-- Example Bronze table
CREATE TABLE bronze.crm.customers (
  _raw_payload  STRING,  -- raw JSON
  _source_file  STRING,
  _ingested_at  TIMESTAMP,
  _batch_id     STRING
)
USING DELTA
LOCATION 's3://my-lake/bronze/crm/customers';
```

### 2.2 Silver Layer (Cleaned)

- **What**: Cleansed, conformed, and
  deduplicated data.
- **Transformations applied**:
  - Type casting
  - Null handling
  - Deduplication (MERGE/UPSERT)
  - Standardized naming conventions
  - PII masking if required
- **Who writes**: dbt models or
  Spark notebooks.

```sql
-- Example Silver model (dbt)
WITH source AS (
  SELECT * FROM {{ source('bronze', 'customers') }}
),
cleaned AS (
  SELECT
    customer_id::BIGINT,
    TRIM(UPPER(email))   AS email,
    first_name,
    last_name,
    created_at::TIMESTAMP
  FROM source
  WHERE customer_id IS NOT NULL
)
SELECT * FROM cleaned
```

### 2.3 Gold Layer (Business-Ready)

- **What**: Aggregated, denormalized,
  business-domain oriented tables.
- **Typical patterns**:
  - Star/snowflake schema
  - Pre-aggregated metrics
  - Wide tables optimized for BI
- **Consumers**: BI tools (Tableau,
  Power BI, Looker), data science teams,
  data APIs.

```
Gold Layer examples:
- dim_customer
- dim_product
- fct_orders
- fct_revenue_daily
- mart_sales_summary
```

### 2.4 Layer Ownership

```
Bronze  → Data Engineering team
Silver  → Data Engineering / Analytics Eng.
Gold    → Analytics Engineering / BI team
```

---

## 3. Delta Lake

Delta Lake is the open-source storage
layer that gives ACID transactions to
data stored in object storage (S3/ADLS).

### 3.1 Why Delta Lake?

| Feature           | Plain Parquet | Delta Lake |
|-------------------|:-------------:|:----------:|
| ACID transactions | ✗             | ✓          |
| Schema evolution  | Manual        | ✓          |
| Time travel       | ✗             | ✓          |
| MERGE (upsert)    | ✗             | ✓          |
| Auto optimization | ✗             | ✓          |
| Streaming + batch | ✗             | ✓          |

### 3.2 Delta Log (Transaction Log)

Every Delta table has a `_delta_log/`
directory containing JSON transaction
files. This is the source of truth for:

- Table schema
- All changes (inserts, updates, deletes)
- Snapshot isolation (readers never
  see partial writes)

```
s3://my-lake/silver/orders/
├── _delta_log/
│   ├── 00000000000000000000.json
│   ├── 00000000000000000001.json
│   └── 00000000000000000010.checkpoint.parquet
├── part-00000-xxx.snappy.parquet
└── part-00001-xxx.snappy.parquet
```

### 3.3 ACID Operations

```sql
-- UPSERT (MERGE) - key operation for SCD
MERGE INTO silver.orders AS target
USING bronze.orders_raw AS src
  ON target.order_id = src.order_id
WHEN MATCHED THEN
  UPDATE SET *
WHEN NOT MATCHED THEN
  INSERT *;

-- Delete (GDPR compliance)
DELETE FROM silver.customers
WHERE customer_id = 12345;

-- Time travel
SELECT * FROM silver.orders
TIMESTAMP AS OF '2025-01-01';

SELECT * FROM silver.orders
VERSION AS OF 42;
```

### 3.4 Delta Table Optimizations

```sql
-- Compact small files
OPTIMIZE silver.orders;

-- Z-Order: collocate related data
-- (key for query performance)
OPTIMIZE silver.orders
ZORDER BY (customer_id, order_date);

-- Auto cleanup old versions
VACUUM silver.orders RETAIN 168 HOURS;
```

### 3.5 Liquid Clustering (Databricks 13+)

Replaces Z-Order and static partitioning
with dynamic, auto-tuned clustering:

```sql
CREATE TABLE silver.orders (...)
CLUSTER BY (customer_id, order_date);

-- Re-cluster incrementally
OPTIMIZE silver.orders;
```

---

## 4. Unity Catalog

Unity Catalog (UC) is Databricks' unified
governance layer for all data assets.

### 4.1 Three-Level Namespace

```
catalog.schema.table

Examples:
  prod.bronze.raw_orders
  prod.silver.orders
  prod.gold.fct_revenue
  dev.silver.orders        ← dev env
```

### 4.2 Object Hierarchy

```
Metastore (1 per region)
└── Catalog  (environment or domain)
    └── Schema / Database
        ├── Tables (managed / external)
        ├── Views
        ├── Volumes  (files)
        └── Functions
```

**Metastore** = top-level container,
tied to your cloud region.

**Catalog** = logical database grouping.
Example: `prod`, `dev`, `raw`.

**Schema** = groups related tables.
Example: `bronze`, `silver`, `crm`.

### 4.3 Managed vs External Tables

| Aspect        | Managed         | External        |
|---------------|-----------------|-----------------|
| Storage       | UC-managed path | Your S3/ADLS    |
| DROP behavior | Deletes data    | Keeps data      |
| Governance    | Full UC control | Full UC control |
| Best for      | Gold/Silver     | Bronze (raw)    |

### 4.4 Access Control

```sql
-- Grant access at catalog level
GRANT USE CATALOG ON CATALOG prod
  TO `data-analysts`;

-- Grant table-level access
GRANT SELECT ON TABLE prod.gold.fct_orders
  TO `bi-team`;

-- Column masking (PII)
CREATE ROW ACCESS POLICY email_mask
  AS (email STRING) ->
    CASE WHEN
      is_member('pii-approved')
    THEN email
    ELSE '***MASKED***'
    END;
```

---

## 5. dbt (Data Build Tool)

dbt is an open-source SQL transformation
framework that brings software engineering
practices to data modeling.

### 5.1 Core Philosophy

- **Transform only**: dbt does not load
  or extract data (T in ELT).
- **SQL-first**: All transformations are
  written in SQL (+ Jinja templating).
- **Version-controlled**: Models live in
  Git, just like application code.
- **Testable**: Built-in data contract
  testing framework.

### 5.2 Project Structure

```
my-dbt-project/
├── dbt_project.yml        ← project config
├── profiles.yml           ← connection config
├── packages.yml           ← dbt packages
├── models/
│   ├── sources.yml        ← source definitions
│   ├── staging/           ← Bronze → Silver
│   │   ├── stg_orders.sql
│   │   └── stg_orders.yml ← tests & docs
│   ├── intermediate/      ← business logic
│   │   └── int_order_items_joined.sql
│   └── marts/             ← Gold layer
│       ├── fct_orders.sql
│       └── dim_customers.sql
├── tests/                 ← custom tests
├── macros/                ← reusable Jinja
├── seeds/                 ← static CSV data
└── snapshots/             ← SCD Type 2
```

### 5.3 Model Materializations

| Materialization | Description          | Use Case          |
|-----------------|----------------------|-------------------|
| `view`          | SQL view, no storage | Lightweight refs  |
| `table`         | Full refresh table   | Small-medium mart |
| `incremental`   | Append/merge rows    | Large fact tables |
| `ephemeral`     | CTE, not materialized| Intermediate logic|
| `dynamic_table` | Databricks auto-refresh| Near-real-time  |

```yaml
# dbt_project.yml
models:
  my_project:
    staging:
      +materialized: view
      +schema: silver
    marts:
      +materialized: table
      +schema: gold
```

### 5.4 Incremental Models

Critical for large fact tables — only
processes new/changed data:

```sql
-- models/marts/fct_orders.sql
{{
  config(
    materialized='incremental',
    unique_key='order_id',
    incremental_strategy='merge'
  )
}}

SELECT
  order_id,
  customer_id,
  order_date,
  total_amount,
  status,
  updated_at
FROM {{ ref('stg_orders') }}

{% if is_incremental() %}
  -- Only process rows newer than
  -- the last load
  WHERE updated_at > (
    SELECT MAX(updated_at) FROM {{ this }}
  )
{% endif %}
```

### 5.5 Sources & Refs

```yaml
# models/sources.yml
sources:
  - name: bronze
    database: prod
    schema: bronze
    tables:
      - name: raw_orders
        loaded_at_field: _ingested_at
        freshness:
          warn_after: {count: 6, period: hour}
          error_after: {count: 24, period: hour}
```

```sql
-- Reference a source (Bronze)
SELECT * FROM {{ source('bronze', 'raw_orders') }}

-- Reference another model (Silver/Gold)
SELECT * FROM {{ ref('stg_orders') }}
```

**Why this matters**: dbt automatically
builds the DAG (Directed Acyclic Graph)
from `source()` and `ref()` calls,
enabling parallel execution and lineage.

### 5.6 Tests

```yaml
# models/marts/fct_orders.yml
models:
  - name: fct_orders
    columns:
      - name: order_id
        tests:
          - unique
          - not_null
      - name: customer_id
        tests:
          - not_null
          - relationships:
              to: ref('dim_customers')
              field: customer_id
      - name: status
        tests:
          - accepted_values:
              values: ['pending','completed',
                       'cancelled']
```

### 5.7 Macros (Reusable Logic)

```sql
-- macros/generate_schema_name.sql
{% macro generate_schema_name(
  custom_schema_name, node
) %}
  {% if custom_schema_name %}
    {{ custom_schema_name | trim }}
  {% else %}
    {{ target.schema }}
  {% endif %}
{% endmacro %}
```

### 5.8 Snapshots (SCD Type 2)

Track historical changes automatically:

```sql
-- snapshots/snap_customers.sql
{% snapshot snap_customers %}
  {{
    config(
      target_schema='snapshots',
      unique_key='customer_id',
      strategy='timestamp',
      updated_at='updated_at'
    )
  }}
  SELECT * FROM {{ source('bronze', 'customers') }}
{% endsnapshot %}
```

dbt adds: `dbt_scd_id`, `dbt_updated_at`,
`dbt_valid_from`, `dbt_valid_to`.

---

## 6. dbt + Databricks Integration

### 6.1 dbt-databricks Adapter

```bash
pip install dbt-databricks
```

```yaml
# profiles.yml
my_project:
  target: prod
  outputs:
    prod:
      type: databricks
      host: <workspace>.azuredatabricks.net
      http_path: /sql/1.0/warehouses/<id>
      token: "{{ env_var('DBT_TOKEN') }}"
      catalog: prod        # Unity Catalog
      schema: dbt_default
      threads: 8
```

### 6.2 Databricks-Specific Features

The `dbt-databricks` adapter unlocks
native Databricks capabilities:

```sql
-- Use Delta Lake features
{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='order_id',
    partition_by=['order_date'],
    cluster_by=['customer_id'],
    tblproperties={
      'delta.autoOptimize.optimizeWrite': 'true',
      'delta.autoOptimize.autoCompact': 'true'
    }
  )
}}
```

### 6.3 SQL Warehouse vs All-Purpose Cluster

| Feature         | SQL Warehouse      | All-Purpose Cluster |
|-----------------|--------------------|---------------------|
| Cost            | Per-query billing  | Per-uptime billing  |
| Auto-stop       | Yes (configurable) | Manual / policy     |
| dbt use case    | ✓ Recommended      | ✓ For Spark models  |
| Serverless      | ✓ Available        | ✗                   |
| Best for        | dbt SQL transforms | Spark Python models |

**Recommendation**: Use a Serverless
SQL Warehouse for dbt runs in production.

### 6.4 Python Models in dbt

For Spark-native transformations:

```python
# models/staging/stg_orders_py.py
import pyspark.sql.functions as F

def model(dbt, spark):
    dbt.config(
        materialized="incremental",
        incremental_strategy="merge",
        unique_key="order_id"
    )
    df = dbt.ref("raw_orders")
    return df.withColumn(
        "order_date",
        F.to_date("order_timestamp")
    )
```

---

## 7. Ingestion Patterns

### 7.1 Batch Ingestion

**Tools**: Fivetran, Airbyte, AWS Glue,
Azure Data Factory, Databricks Autoloader

```python
# Databricks Autoloader (preferred)
# Incrementally ingests new files
spark.readStream \
  .format("cloudFiles") \
  .option("cloudFiles.format", "json") \
  .option(
    "cloudFiles.schemaLocation",
    "/path/to/schema"
  ) \
  .load("s3://bucket/landing/orders/") \
  .writeStream \
  .format("delta") \
  .option("checkpointLocation",
          "/path/to/checkpoint") \
  .trigger(availableNow=True) \
  .toTable("prod.bronze.raw_orders")
```

### 7.2 Streaming Ingestion

**Tools**: Kafka + Spark Structured
Streaming, Delta Live Tables (DLT)

```python
# Read from Kafka
df = (spark.readStream
  .format("kafka")
  .option("kafka.bootstrap.servers",
          "broker:9092")
  .option("subscribe", "orders")
  .load()
)

# Parse and write to Bronze
(df
  .select(
    F.from_json(
      F.col("value").cast("string"),
      schema
    ).alias("data"),
    F.col("timestamp").alias("_ingested_at")
  )
  .writeStream
  .format("delta")
  .outputMode("append")
  .option("checkpointLocation", "/chk/orders")
  .toTable("prod.bronze.raw_orders_stream")
)
```

### 7.3 Change Data Capture (CDC)

For database replication:
- **Debezium** → Kafka → Bronze
- **Fivetran Log-Based CDC** → Bronze
- **AWS DMS** → S3 → Bronze

```sql
-- Handle CDC events in Silver
-- using APPLY CHANGES (DLT) or MERGE
MERGE INTO silver.customers AS t
USING (
  SELECT * FROM bronze.cdc_customers
  WHERE _cdc_op IN ('I','U')
) AS s
ON t.customer_id = s.customer_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- Handle deletes
DELETE FROM silver.customers
WHERE customer_id IN (
  SELECT customer_id
  FROM bronze.cdc_customers
  WHERE _cdc_op = 'D'
);
```

---

## 8. Data Modeling Concepts

### 8.1 Star Schema

The most common Gold layer pattern:

```
          dim_date
             │
dim_product ─┼─ fct_orders ─┬─ dim_customer
             │               │
          dim_store       dim_channel
```

- **Fact tables**: Numeric measurements,
  foreign keys to dimensions
- **Dimension tables**: Descriptive
  attributes, one row per entity

### 8.2 Slowly Changing Dimensions (SCD)

How you handle historical changes to
dimension attributes:

| Type | Strategy         | Storage Cost |
|------|------------------|:------------:|
| 0    | Never update     | Lowest       |
| 1    | Overwrite        | Low          |
| 2    | New row + dates  | Medium       |
| 3    | Add column       | Low–Medium   |
| 4    | History table    | Medium       |

**SCD Type 2 with dbt snapshots**:

```sql
-- dim_customer (Gold, with SCD2)
SELECT
  {{ dbt_utils.surrogate_key([
    'customer_id', 'dbt_valid_from'
  ]) }} AS dim_customer_key,
  customer_id,
  email,
  full_name,
  dbt_valid_from,
  dbt_valid_to,
  CASE WHEN dbt_valid_to IS NULL
    THEN TRUE ELSE FALSE
  END AS is_current
FROM {{ ref('snap_customers') }}
```

### 8.3 Data Vault (Alternative)

Three object types:
- **Hub**: Business keys only
- **Link**: Relationships between hubs
- **Satellite**: Descriptive attributes
  + history

Use when: high source volatility,
very large teams, strict auditability.

### 8.4 One Big Table (OBT)

Pre-join everything into a single wide
table. Common for:
- Self-serve BI tools (Looker Studio)
- ML feature engineering

---

## 9. Orchestration

### 9.1 Databricks Workflows

Native Databricks scheduler:

```
Workflow: daily_dbt_run
├── Task 1: run_ingestion (Notebook)
│   └── on_success →
├── Task 2: dbt_staging (dbt task)
│   └── on_success →
├── Task 3: dbt_marts (dbt task)
│   └── on_success →
└── Task 4: data_quality_check (Notebook)
```

**dbt task in Workflows**:

```json
{
  "task_key": "dbt_staging",
  "dbt_task": {
    "project_directory": "/dbt",
    "commands": [
      "dbt deps",
      "dbt run --select staging",
      "dbt test --select staging"
    ],
    "warehouse_id": "abc123"
  }
}
```

### 9.2 Apache Airflow / MWAA

Better for cross-platform orchestration:

```python
# DAG example with dbt
from airflow.providers.databricks.operators.dbt \
    import DbtRunOperator

dbt_run = DbtRunOperator(
    task_id='dbt_run_silver',
    databricks_conn_id='databricks_default',
    dbt_args=['--select', 'silver'],
)
```

### 9.3 Delta Live Tables (DLT)

Databricks' managed pipeline framework
(alternative to dbt for streaming):

```python
import dlt
from pyspark.sql.functions import *

@dlt.table(
  name="silver_orders",
  comment="Cleaned orders"
)
def silver_orders():
  return (
    dlt.read_stream("bronze_orders")
       .where("order_id IS NOT NULL")
       .withColumn("order_date",
         to_date("order_timestamp"))
  )
```

**DLT vs dbt**:
| Aspect     | DLT                | dbt              |
|------------|--------------------|------------------|
| Language   | Python/SQL         | SQL/Python       |
| Streaming  | ✓ Native           | Limited          |
| Git-native | Partial            | ✓ Full           |
| Testing    | Expectations       | Rich test suite  |
| Cost       | DLT surcharge      | Warehouse cost   |

---

## 10. Data Quality & Testing

### 10.1 dbt Tests (Built-in)

```yaml
# models/marts/fct_orders.yml
models:
  - name: fct_orders
    tests:
      - dbt_utils.expression_is_true:
          expression: "total_amount >= 0"
    columns:
      - name: order_id
        tests: [unique, not_null]
      - name: order_date
        tests:
          - dbt_utils.not_null_proportion:
              at_least: 0.99
```

### 10.2 Great Expectations

Enterprise-grade data quality:

```python
import great_expectations as ge

context = ge.get_context()

# Define expectations
suite = context.add_expectation_suite(
  "orders_suite"
)
validator = context.get_validator(
  batch_request=batch_request,
  expectation_suite_name="orders_suite"
)
validator.expect_column_values_to_not_be_null(
  "order_id"
)
validator.expect_column_values_to_be_between(
  "total_amount", min_value=0
)
validator.save_expectation_suite()
```

### 10.3 Data Contracts

Formal schema agreements between
producers and consumers:

```yaml
# contracts/orders_contract.yml
id: orders-v1
owner: data-engineering@company.com
schema:
  - name: order_id
    type: bigint
    nullable: false
    unique: true
  - name: total_amount
    type: double
    nullable: false
    description: "Order total in USD"
sla:
  freshness: 2 hours
  completeness: 99.9%
```

---

## 11. Performance & Optimization

### 11.1 File Layout

| Problem         | Solution              |
|-----------------|-----------------------|
| Many small files| OPTIMIZE (compaction) |
| Random reads    | Z-ORDER / Liquid Cluster|
| Full table scans| Partitioning          |
| Skewed data     | Salting / AQE         |

### 11.2 Partitioning Rules

```sql
-- Good: low-cardinality, filter columns
PARTITION BY DATE(order_date)

-- Bad: high-cardinality → too many dirs
PARTITION BY customer_id  -- ✗
```

Use partitioning only when:
- Column is frequently used in WHERE
- Cardinality < ~1000 values
- Partition size > 1GB per partition

### 11.3 SQL Warehouse Sizing

| Size   | vCores | Best For              |
|--------|-------:|-----------------------|
| Small  | 4      | Dev/test              |
| Medium | 8      | Standard dbt runs     |
| Large  | 16     | Heavy transformations |
| X-Large| 32     | Large-scale analytics |

**Auto-scaling**: Set min/max clusters
to handle concurrent dbt thread spikes.

### 11.4 dbt Thread Tuning

```yaml
# profiles.yml
prod:
  threads: 8   # parallel model runs
```

Match threads to SQL Warehouse cluster
count × cores for optimal throughput.

### 11.5 Caching

```sql
-- Databricks result cache (automatic)
-- Re-running same query = instant

-- Delta cache (disk-based)
-- Keeps decompressed data in local SSD
spark.conf.set(
  "spark.databricks.io.cache.enabled",
  "true"
)
```

---

## 12. Security & Access Control

### 12.1 Identity & Access

```
Identity Providers (AAD/Okta/Google)
         │ SSO + SCIM
         ▼
Databricks Account
         │
         ├── Service Principals (CI/CD)
         ├── Groups (team-based access)
         └── Users
```

### 12.2 dbt Service Principal

For production dbt runs, use a
service principal (not personal tokens):

```yaml
# profiles.yml (CI/CD)
prod:
  type: databricks
  host: "{{ env_var('DBX_HOST') }}"
  http_path: "{{ env_var('DBX_HTTP_PATH') }}"
  token: "{{ env_var('DBX_SP_TOKEN') }}"
```

### 12.3 Secrets Management

```python
# Never hardcode secrets
# Use Databricks Secret Scopes

dbutils.secrets.get(
  scope="prod-secrets",
  key="dbt-service-principal-token"
)
```

Or integrate with Azure Key Vault /
AWS Secrets Manager.

### 12.4 Network Security

```
Internet
  │
  ▼
VPN / Private Link
  │
  ▼
Databricks Workspace
  │  (inside VNet/VPC)
  ▼
Storage Account (private endpoint)
```

---

## 13. Observability & Lineage

### 13.1 dbt Docs & Lineage

```bash
# Generate docs site
dbt docs generate
dbt docs serve
```

Provides:
- Auto-generated data dictionary
- Column-level lineage graph
- Test coverage reports

### 13.2 Unity Catalog Lineage

UC automatically tracks:
- Table-level lineage across notebooks,
  SQL, dbt, and Spark jobs
- Column-level lineage (Enterprise tier)

### 13.3 dbt Artifacts for Monitoring

```bash
# After each dbt run, consume:
target/manifest.json    # model metadata
target/run_results.json # execution results
target/catalog.json     # schema info
```

Push to observability platforms:
- **Montecarlo**: Data observability
- **Anomalo**: Automated anomaly detection
- **Elementary**: Open-source dbt monitoring

### 13.4 Key Metrics to Monitor

| Metric              | Alert Threshold         |
|---------------------|-------------------------|
| Model run duration  | > 2× historical avg     |
| Row count change    | > 10% deviation         |
| Null rate           | > defined threshold     |
| Source freshness    | > SLA window            |
| Test failures       | Any failure = alert     |

---

## 14. How Everything Works Together

End-to-end data flow for a daily
batch data warehouse pipeline:

```
Step 1: SOURCE → BRONZE (Ingestion)
───────────────────────────────────
• Fivetran syncs Salesforce CRM → S3
• Autoloader detects new files
• Writes raw Delta tables to
  prod.bronze.*

Step 2: BRONZE → SILVER (dbt staging)
──────────────────────────────────────
• Databricks Workflow triggers dbt
• dbt runs staging models:
  - Type casting
  - Deduplication
  - Null handling
• dbt tests validate Silver data
• Written to prod.silver.*

Step 3: SILVER → GOLD (dbt marts)
──────────────────────────────────
• dbt runs mart models:
  - fct_orders (incremental merge)
  - dim_customers (SCD2 snapshot)
  - mart_sales_summary (aggregation)
• dbt tests validate Gold data
• Written to prod.gold.*

Step 4: CONSUMPTION
───────────────────
• BI: Power BI / Tableau → SQL Warehouse
• ML: Feature engineering notebooks
• APIs: Databricks SQL API
• Monitoring: Elementary dashboard
```

### 14.1 Technology Responsibility Matrix

| Concern           | Tool                  |
|-------------------|-----------------------|
| File storage      | S3 / ADLS / GCS       |
| Table format      | Delta Lake            |
| Compute           | Databricks clusters   |
| Query engine      | Databricks SQL        |
| Transformations   | dbt                   |
| Governance        | Unity Catalog         |
| Ingestion (batch) | Fivetran / Airbyte    |
| Ingestion (stream)| Kafka + Spark         |
| Orchestration     | Databricks Workflows  |
| Data quality      | dbt tests + GE        |
| BI                | Tableau / Power BI    |
| Monitoring        | Elementary / Montecarlo|
| Secrets           | Databricks Secrets    |
| Version control   | Git (dbt models)      |

### 14.2 Environment Strategy

```
dev     → Personal sandbox
          catalog: dev_<username>

staging → Shared pre-prod
          catalog: staging
          Runs on subset of data

prod    → Production
          catalog: prod
          Full data, restricted access
```

```yaml
# dbt: environment-aware
# profiles.yml sets target catalog
# per environment automatically

# CI/CD pipeline:
# PR → run dbt against staging
# Merge to main → deploy to prod
```

### 14.3 CI/CD Pipeline

```
Developer pushes code → GitHub/GitLab
         │
         ▼
CI Pipeline (GitHub Actions)
  ├── dbt compile (validate SQL)
  ├── dbt run --select state:modified+
  │   (only changed models + children)
  ├── dbt test --select state:modified+
  └── on success: approve PR

Merge to main →
  ├── Deploy to staging
  ├── Run full dbt test suite
  └── on success: promote to prod
```

---

## Quick Reference: Key Commands

```bash
# dbt essentials
dbt debug                  # test connection
dbt deps                   # install packages
dbt run                    # run all models
dbt run --select staging   # run by tag/folder
dbt run --select +fct_orders  # + ancestors
dbt test                   # run all tests
dbt snapshot               # run SCD snapshots
dbt source freshness       # check ingestion lag
dbt docs generate && dbt docs serve

# Databricks CLI
databricks clusters list
databricks jobs run-now --job-id 123
databricks secrets put-secret \
  --scope prod --key dbt-token

# Delta Lake maintenance
OPTIMIZE prod.silver.orders
  ZORDER BY (customer_id, order_date);
VACUUM prod.silver.orders RETAIN 168 HOURS;

# Unity Catalog
SHOW CATALOGS;
SHOW SCHEMAS IN prod;
DESCRIBE TABLE prod.gold.fct_orders;
SHOW LINEAGE TABLE prod.gold.fct_orders;
```

---

*Document version: 1.0 · April 2026*
*Databricks Runtime ≥ 13.x · dbt ≥ 1.7*
