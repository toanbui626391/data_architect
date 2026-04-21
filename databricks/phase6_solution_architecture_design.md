# Phase 6: Solution Architecture Design
*Databricks Data & Solution Architect Track*

---

## Overview

Phase 6 elevates you from building
individual pipelines to designing complete,
end-to-end Databricks data platforms.

A Solution Architect must answer:
* **How** should the platform be structured?
* **Which** architecture pattern fits this
  business problem?
* **How much** will it cost and how do we
  size it correctly?
* **How** do we migrate from legacy systems?
* **What** happens when it fails?

This phase covers the four pillars:

```
┌─────────────────────────────────┐
│  1. Cloud Architecture Patterns │
├─────────────────────────────────┤
│  2. Migration Strategies        │
├─────────────────────────────────┤
│  3. Sizing & Cost Optimization  │
├─────────────────────────────────┤
│  4. Real-World Data Patterns    │
└─────────────────────────────────┘
```

---

## 6.1 Cloud Architecture Patterns

### 6.1.1 Landing Zone Design

A **Landing Zone** is the foundational
cloud environment that hosts your
Databricks platform. It is designed
before any data pipelines are built.

**Landing Zone = Cloud accounts +
networking + IAM + security baseline.**

#### Core Components

```
┌──────────────────────────────────────┐
│         Landing Zone                 │
│                                      │
│  ┌────────────┐  ┌────────────────┐  │
│  │  Identity  │  │  Connectivity  │  │
│  │  (AAD/IAM) │  │  (VPN/ExpRoute)│  │
│  └────────────┘  └────────────────┘  │
│                                      │
│  ┌────────────┐  ┌────────────────┐  │
│  │  Security  │  │  Management    │  │
│  │  (Policies)│  │  (Logging/Mon) │  │
│  └────────────┘  └────────────────┘  │
│                                      │
│  ┌─────────────────────────────────┐ │
│  │  Databricks Workspaces          │ │
│  │  (Dev / Staging / Prod)         │ │
│  └─────────────────────────────────┘ │
│                                      │
│  ┌─────────────────────────────────┐ │
│  │  Object Storage                 │ │
│  │  (Bronze / Silver / Gold)       │ │
│  └─────────────────────────────────┘ │
└──────────────────────────────────────┘
```

#### Account & Workspace Structure

Databricks has two levels:

| Level | Description |
|-------|-------------|
| **Account** | Top-level billing unit, single metastore per region |
| **Workspace** | Isolated runtime environment, compute + notebooks |

**Recommended structure:**

```
Databricks Account
├── Workspace: dev
│     └── Purpose: Developer sandbox
│     └── Users: Data engineers only
├── Workspace: staging
│     └── Purpose: Pre-production CI/CD
│     └── Users: Service principals only
└── Workspace: prod
      └── Purpose: Production workloads
      └── Users: Service principals + analysts
```

**Why separate workspaces?**
* Blast radius isolation — a bad prod job
  can't affect dev budgets or vice versa.
* Separate access control policies per env.
* Different cluster policies per env
  (dev: flexible; prod: locked down).

#### Storage Account Separation

```
Landing Storage (Bronze)
  s3://company-landing/
  → Ingestion tools write here
  → No direct analyst access

Core Storage (Silver / Gold)
  s3://company-data/
  → Processed Delta tables
  → Governed by Unity Catalog

Archive Storage
  s3://company-archive/
  → Data older than retention period
  → Glacier / Cool tier (cheap)
```

**Architect Tip:** Use separate storage
accounts per environment AND per layer.
This enables independent access policies
and lifecycle management rules.

---

### 6.1.2 Hub-and-Spoke Topology

The most common enterprise Databricks
network design.

```
         ┌──────────────┐
         │   Hub VNet   │
         │  (Shared     │
         │  Services)   │
         │  - DNS       │
         │  - Firewall  │
         │  - Bastion   │
         └──────┬───────┘
                │ VNet Peering
      ┌─────────┼──────────┐
      ▼         ▼          ▼
  ┌──────┐  ┌──────┐  ┌──────┐
  │Spoke │  │Spoke │  │Spoke │
  │ Dev  │  │Stage │  │ Prod │
  │VNet  │  │VNet  │  │VNet  │
  └──────┘  └──────┘  └──────┘
```

**Hub** contains shared infrastructure:
* Azure Firewall / AWS Network Firewall
* DNS resolver
* ExpressRoute / Direct Connect gateway
* Private DNS zones

**Spokes** are isolated per environment:
* Databricks workspace injected into
  spoke VNet
* Private endpoints for storage
* No direct spoke-to-spoke traffic

**Benefits:**
* Centralized egress and firewall rules
* Each env is fully network-isolated
* Easy to add new spokes (new environments,
  new business units)

---

### 6.1.3 Data Mesh Network Topology

For large enterprises with multiple
data domains:

```
         Unity Catalog Metastore
         (Central governance only)
                   │
      ┌────────────┼─────────────┐
      │            │             │
  ┌───────┐   ┌───────┐   ┌──────────┐
  │Domain │   │Domain │   │Domain    │
  │Sales  │   │Finance│   │Marketing │
  │Catalog│   │Catalog│   │Catalog   │
  └───┬───┘   └───┬───┘   └────┬─────┘
      │            │             │
   Own team     Own team      Own team
   Own infra    Own infra     Own infra
   Own SLAs     Own SLAs      Own SLAs
```

**Unity Catalog as a mesh registry:**
* Each domain owns its catalog
* Central metastore enforces global
  governance (lineage, audit logs)
* Cross-domain discovery via catalog
  browser and tags

**When to use Data Mesh:**
* 5+ distinct data-producing teams
* Each team has independent release cycles
* Strong domain ownership culture exists

---

### 6.1.4 Multi-Region & Disaster Recovery

#### Active-Passive (most common)

```
Primary Region (us-east-1)
├── Databricks Workspace (ACTIVE)
├── SQL Warehouse (serving)
├── Delta tables (read/write)
└── Replication →

                Failover Region (us-west-2)
                ├── Databricks Workspace (STANDBY)
                ├── SQL Warehouse (off)
                └── Delta tables (replica, read-only)
```

**Replication strategies:**
* **Storage replication**: S3 CRR
  (Cross-Region Replication) or
  ADLS geo-redundant storage (RAGRS)
* **Pipeline config replication**:
  Git-based (Databricks Repos → redeploy
  to DR region)
* **Unity Catalog**: Single metastore
  per region — maintain separate catalog
  in DR region

**RTO / RPO targets:**

| Tier | Workload | RTO | RPO |
|------|----------|-----|-----|
| Critical | BI dashboards | < 1 hr | < 15 min |
| Important | Daily ETL | < 4 hrs | < 1 hr |
| Standard | Batch reports | < 24 hrs | < 4 hrs |

#### Active-Active (advanced)

Both regions serve reads simultaneously.
Writes go to one region, replicate async.

**Only justified when:**
* Latency requirements are strict
* Global user base (multi-region reads)
* Business continuity SLA < 15 min RTO

---

### 6.1.5 Cost Allocation Architecture

**Tagging strategy** — the foundation of
cost accountability:

```
Required tags on every resource:
  environment      = prod | dev | staging
  cost_center      = DEPT-123
  team             = data-engineering
  project          = revenue-pipeline
  managed_by       = terraform
```

**Showback vs Chargeback:**

| Model | Description | Maturity |
|-------|-------------|----------|
| Showback | Report costs per team, no billing | Basic |
| Chargeback | Teams receive actual cloud bills | Advanced |

**Databricks cost attribution:**
* **Cluster tags**: Propagate to cloud VM
  cost reports automatically
* **System tables**: `system.billing.usage`
  tracks DBU consumption per workspace,
  user, cluster, and job
* **Unity Catalog audit logs**: Track
  who ran what query and on which table

```sql
-- Query DBU consumption by team
SELECT
  usage_metadata.cluster_name,
  tags['team']              AS team,
  SUM(usage_quantity)       AS total_dbu,
  SUM(usage_quantity * 0.40) AS est_cost_usd
FROM system.billing.usage
WHERE usage_date >= CURRENT_DATE - 30
GROUP BY 1, 2
ORDER BY total_dbu DESC;
```

---

## 6.2 Migration Patterns

### 6.2.1 Migration Philosophy

**Three strategic options:**

```
Option A: Lift-and-Shift
  "Move it as-is, migrate later"
  Speed: Fast (weeks)
  Value: Low (same problems in cloud)
  Risk: Low

Option B: Lift-and-Optimize
  "Move it, then modernize incrementally"
  Speed: Medium (months)
  Value: Medium
  Risk: Medium

Option C: Re-architecture
  "Design from scratch for Databricks"
  Speed: Slow (6–18 months)
  Value: Highest
  Risk: Higher (greenfield unknowns)
```

**Architect recommendation:**
Use Lift-and-Shift only as a bridge.
Plan for Re-architecture within 12–18
months of initial migration.

---

### 6.2.2 Migrating from Hadoop/Hive

Hadoop/HDFS → Databricks is the most
common legacy migration.

#### Assessment Phase

Before migrating, audit:

```
Discovery Checklist:
[ ] Total data volume (TB/PB)
[ ] Number of Hive tables and schemas
[ ] Active jobs vs zombie jobs
    (jobs not run in 90+ days)
[ ] HQL vs Spark SQL compatibility
[ ] External dependencies
    (HBase, Oozie, Sqoop, Pig)
[ ] SLA requirements per job
[ ] User count and access patterns
```

#### Migration Steps

```
Step 1: Copy Data to Object Storage
  HDFS distcp → S3/ADLS
  (Parquet, ORC formats preserved)

Step 2: Convert to Delta Lake
  CONVERT TO DELTA parquet.`s3://path/`
  (Adds _delta_log, no data rewrite)

Step 3: Register in Unity Catalog
  CREATE EXTERNAL TABLE ... LOCATION ...
  (Hive metastore → Unity Catalog)

Step 4: Convert HQL to Spark SQL
  Most HQL is compatible with Spark SQL
  Key differences:
    - UDFs need rewrite (Java → Python/SQL)
    - Hive-specific functions (nvl → coalesce)
    - Dynamic partitioning syntax

Step 5: Migrate Oozie Workflows
  Oozie DAGs → Databricks Workflows
  (Each Oozie action = one Workflow task)

Step 6: Validate & Cut Over
  Run parallel (old + new) for 2–4 weeks
  Compare row counts, aggregates, SLAs
```

#### HQL to Spark SQL Compatibility

| HQL Feature | Spark SQL Equivalent |
|-------------|----------------------|
| `NVL(a, b)` | `COALESCE(a, b)` |
| `FROM_UNIXTIME` | `FROM_UNIXTIME` ✓ |
| `DISTRIBUTE BY` | `DISTRIBUTE BY` ✓ |
| `SORT BY` | `SORT BY` ✓ |
| Custom SerDe | Spark native format readers |
| `lateralView explode` | `EXPLODE` / `LATERAL VIEW` ✓ |

**Common blockers:**
* Java/Scala Hive UDFs require rewriting
  as Python UDFs or Spark built-ins.
* `INSERT OVERWRITE DIRECTORY` syntax
  differs — use `df.write` instead.

---

### 6.2.3 Migrating from Snowflake

Snowflake → Databricks migration is
growing as organizations consolidate
into a lakehouse architecture.

#### Key Differences to Reconcile

| Concept | Snowflake | Databricks |
|---------|-----------|------------|
| Storage | Internal (opaque) | Open (Delta on S3) |
| Compute | Virtual Warehouse | SQL Warehouse / Cluster |
| Table cloning | Zero-copy clone | Shallow clone (Delta) |
| Tasks | Snowflake Tasks | Databricks Workflows |
| Streams | Snowflake Streams | Structured Streaming |
| Semi-structured | VARIANT type | STRING + from_json() |
| Time travel | 90 days | 30 days (default) |

#### Migration Approach

```
Phase 1: Export Snowflake Data
  COPY INTO 's3://bucket/export/'
  FROM snowflake_table
  FILE_FORMAT = (TYPE = PARQUET);

Phase 2: Load into Bronze Delta
  spark.read.parquet("s3://bucket/export/")
    .write.format("delta")
    .saveAsTable("prod.bronze.table_name")

Phase 3: Rebuild Transformations
  Snowflake SQL → Databricks SQL/dbt
  (Syntax is largely compatible — ANSI SQL)

Phase 4: Rebuild Pipelines
  Snowflake Tasks → Databricks Workflows
  Snowflake Streams → Delta CDC / DLT

Phase 5: Rebuild BI Connections
  Snowflake connector → Databricks JDBC/ODBC
  (Power BI, Tableau: change connection string)
```

#### What Carries Over Easily

```
✓ SQL logic (ANSI compatible)
✓ dbt models (minimal changes)
✓ BI dashboards (reconnect source)
✓ Data models (star schema logic)
```

#### What Needs Rework

```
✗ Snowflake-specific SQL functions
  FLATTEN() → EXPLODE()
  PARSE_JSON() → FROM_JSON()
  TO_VARIANT() → CAST AS STRING / MAP

✗ Snowflake Tasks → Workflows
✗ Snowflake Streams → DLT / Autoloader
✗ Snowflake Shares → Delta Sharing
✗ Row Access Policies → Unity Catalog
```

---

### 6.2.4 Migrating from Azure Synapse Analytics

For Microsoft shops moving to Databricks:

| Synapse Component | Databricks Equivalent |
|------------------|-----------------------|
| Dedicated SQL Pool | SQL Warehouse (Serverless) |
| Serverless SQL Pool | SQL Warehouse (Serverless) |
| Spark Pool | All-Purpose / Job Cluster |
| Azure Data Factory | Databricks Workflows + ADF (hybrid) |
| Synapse Pipelines | Databricks Workflows |
| Synapse Link | Delta Live Tables |

**Migration path:**
1. Keep ADF for ingestion (it integrates
   natively with Databricks)
2. Replace Spark Pools with Databricks
   clusters (code is portable PySpark)
3. Replace Dedicated SQL Pool with
   Gold Delta tables + SQL Warehouse
4. Replace Synapse Pipelines with
   Databricks Workflows

---

### 6.2.5 Validation Framework

Always validate migrations with a
formal comparison methodology:

```python
# Validation pattern: compare old vs new
def validate_migration(
    old_df, new_df, key_cols, metric_cols
):
    # 1. Row count check
    assert old_df.count() == new_df.count(), \
      "Row count mismatch!"

    # 2. Null rate check per column
    for col in metric_cols:
        old_null = old_df.filter(
          F.col(col).isNull()
        ).count()
        new_null = new_df.filter(
          F.col(col).isNull()
        ).count()
        assert old_null == new_null, \
          f"Null rate mismatch in {col}"

    # 3. Aggregate value check
    old_agg = old_df.agg(
      {c: "sum" for c in metric_cols}
    ).collect()[0]
    new_agg = new_df.agg(
      {c: "sum" for c in metric_cols}
    ).collect()[0]
    for c in metric_cols:
        diff = abs(
          old_agg[f"sum({c})"] -
          new_agg[f"sum({c})"]
        )
        assert diff < 0.01, \
          f"Aggregate mismatch in {c}"
```

**Cutover gate:**
* Row counts match within 0.01%
* Sum of key metrics matches within 0.1%
* No regression in downstream BI reports
* SLA met for 3 consecutive runs

---

## 6.3 Sizing & Cost Optimization

### 6.3.1 Understanding DBU (Databricks Units)

A **DBU** is Databricks' unit of compute
consumption. Cost = DBU × DBU rate.

**DBU rates vary by:**
* Compute type (Job, All-Purpose,
  SQL Warehouse, Serverless)
* SKU tier (Standard, Premium, Enterprise)
* Cloud provider and region

```
Example rates (approximate USD):
  Job Compute (Premium):    $0.20/DBU
  All-Purpose (Premium):    $0.55/DBU
  SQL Serverless (Premium): $0.70/DBU
  DLT Advanced:             $0.36/DBU
```

**Key insight:** Running a job cluster
vs. all-purpose cluster for the same
workload is ~2.75x cheaper per DBU.

---

### 6.3.2 Estimating DBU Consumption

**Formula:**

```
DBUs = num_workers × DBU_per_worker_hour
       × job_duration_hours

Total Cost = DBUs × DBU_rate
           + VM cost (Classic only)
```

**DBU per instance type (approx):**

| Instance | DBU/hr (worker) |
|----------|---------------:|
| m5.xlarge (4 core) | 1.0 |
| m5.2xlarge (8 core) | 2.0 |
| m5.4xlarge (16 core) | 4.0 |
| m5.8xlarge (32 core) | 8.0 |

**Example calculation:**

```
Workload: Daily ETL job
Cluster: 8 workers × m5.2xlarge
Duration: 45 minutes = 0.75 hrs
Compute type: Job Cluster (Premium)

DBUs = 8 workers × 2.0 DBU/hr × 0.75 hrs
     = 12 DBUs

Cost = 12 DBUs × $0.20/DBU = $2.40/run
Monthly = $2.40 × 30 = $72/month
```

---

### 6.3.3 Right-Sizing Clusters

**Memory-intensive workloads**
(large joins, aggregations, ML training):

```
Prefer: Memory-optimized instances
  AWS:   r5.xlarge, r5.2xlarge
  Azure: Standard_E4ds_v4
  GCP:   n1-highmem-4

Signs you need more memory:
  - Spark UI shows spill to disk
  - OOM errors in executor logs
  - Frequent GC pauses
```

**Compute-intensive workloads**
(complex SQL, transformations):

```
Prefer: Compute-optimized + Photon
  AWS:   c5.xlarge, c5.2xlarge
  Azure: Standard_F4s_v2

Photon: Enable on SQL Warehouse
  and compute-optimized clusters
```

**I/O-intensive workloads**
(reading/writing massive datasets):

```
Prefer: Storage-optimized + SSD
  AWS:   i3.xlarge (local NVMe SSD)
  (Delta cache works best on SSD)
```

#### Cluster Sizing Guidance

```
Rule of thumb per workload:

ETL Batch Jobs:
  Start: 4 workers × m5.2xlarge
  Adjust based on job duration

Interactive Exploration:
  All-Purpose: 2–4 workers
  Autoscaling: min 2, max 8

SQL Warehouse (BI serving):
  2–3x concurrent users = warehouse size
  E.g., 20 analysts → Medium warehouse
  (Medium = 8 vCores × ~3 clusters)

ML Training:
  Single Node for < 10GB datasets
  Distributed for > 10GB or deep learning
```

---

### 6.3.4 Reserved vs. Spot Instances

**On-Demand pricing** — full list price,
no interruption risk.

**Reserved Instances (1 or 3 year)**
— 30–60% savings, committed use.

**Spot / Preemptible** — 60–90% savings,
can be reclaimed with 2-min notice.

#### Architect's Blended Strategy

```
Driver nodes:     Always On-Demand
                  (never interrupted)

Worker nodes:
  - Prod ETL:     Spot workers
                  + retry on interruption
  - Streaming:    On-Demand
                  (interruption breaks micro-batch)
  - Dev/test:     Spot only
                  (cost savings priority)

SQL Warehouse:    Serverless
                  (DBrick manages spot/on-demand)
```

**Serverless advantage:**
No VM cost visibility — Databricks
absorbs spot/on-demand risk. You pay
only DBU rates. Ideal for SQL Warehouses
and DLT pipelines.

---

### 6.3.5 Cost Optimization Checklist

```
Compute:
[ ] Replace all-purpose with job clusters
    for production workloads
[ ] Enable autoscaling on interactive clusters
[ ] Set auto-terminate (30 min dev, 1 hr prod)
[ ] Use Spot instances for workers
[ ] Use Serverless SQL Warehouses for DBSQL
[ ] Enable Photon on SQL-heavy clusters

Storage:
[ ] Run OPTIMIZE weekly on active tables
[ ] Run VACUUM to delete old versions
[ ] Set S3/ADLS lifecycle rules for archive
[ ] Use Delta table properties:
    delta.logRetentionDuration = "15 days"

Governance:
[ ] Set cluster policies (max workers, runtime)
[ ] Tag all clusters for cost attribution
[ ] Review system.billing.usage monthly
[ ] Terminate idle all-purpose clusters
[ ] Use Unity Catalog to identify
    unused/stale tables
```

---

## 6.4 Real-World Architecture Patterns

### 6.4.1 Lambda Architecture

Combines batch and streaming into
a single logical view.

```
Source Events
     │
     ├──────────────────────────────────┐
     │ Batch layer                      │ Speed layer
     │ (historical, accurate)           │ (real-time, approx.)
     ▼                                  ▼
  Autoloader                      Structured Streaming
  (daily/hourly batch)            (seconds latency)
     │                                  │
     ▼                                  ▼
  Silver (batch)              Silver (streaming)
     │                                  │
     └──────────────┬───────────────────┘
                    │ Merge / Union
                    ▼
              Gold (serving layer)
              (batch corrects stream)
```

**Use case:** Revenue reporting dashboard
that shows near-real-time data (from
stream) but reconciles at end-of-day
with the authoritative batch pipeline.

**When to use Lambda:**
* Latency < 1 minute required
* Historical reprocessing also needed
* Accuracy is critical (batch corrects
  streaming approximations)

**Databricks Implementation:**

```python
# Batch layer: Autoloader daily
batch_df = (spark.readStream
  .format("cloudFiles")
  .option("cloudFiles.format", "json")
  .load("s3://bucket/landing/")
  .trigger(availableNow=True)
)

# Speed layer: Kafka stream
stream_df = (spark.readStream
  .format("kafka")
  .option("subscribe", "orders")
  .load()
)

# Serving layer: MERGE batch over stream
```

---

### 6.4.2 Kappa Architecture

Single streaming pipeline — no separate
batch layer. Reprocessing is done by
replaying the event stream.

```
Source Events
(Kafka - retained 30-90 days)
     │
     ▼
Structured Streaming
(always-on pipeline)
     │
     ▼
  Bronze Delta (streaming append)
     │
     ▼
  Silver Delta (streaming MERGE/CDC)
     │
     ▼
  Gold Delta (streaming aggregation)
     │
     ▼
SQL Warehouse / BI
```

**Reprocessing pattern (no batch needed):**

```
When you need to fix historical data:
1. Reset Kafka consumer offset to T-30d
2. Replay stream through the pipeline
3. MERGE overwrites incorrect records
4. Delta time travel preserves audit trail
```

**When to use Kappa:**
* Event stream is durable (Kafka 30+ days)
* Latency requirement is < 5 minutes
* You want to eliminate dual maintenance
  of batch + stream code

**Databricks advantage:**
Delta Lake MERGE + Structured Streaming
makes Kappa practical — you get ACID
guarantees on the stream output.

---

### 6.4.3 Medallion with dbt Architecture

Most common enterprise pattern — combines
Databricks for compute and dbt for
SQL transformation management.

```
[Ingestion]
Fivetran / Autoloader
        │
        ▼
[Bronze] prod.bronze.*
  Raw Delta tables
  Written by ingestion tools
        │
        ▼  ← dbt staging models
[Silver] prod.silver.*
  stg_orders, stg_customers
  stg_products (cleansed)
        │
        ▼  ← dbt mart models
[Gold] prod.gold.*
  fct_orders (incremental)
  dim_customers (SCD2)
  mart_sales_summary
        │
        ▼
[Consumption]
SQL Warehouse → Power BI / Tableau
ML clusters → Feature engineering
```

**Orchestration:**

```
Databricks Workflow
├── Task 1: Fivetran sync (trigger via API)
├── Task 2: Autoloader ETL (notebook)
├── Task 3: dbt run --select staging
│           (dbt task in Workflow)
├── Task 4: dbt test --select staging
├── Task 5: dbt run --select marts
├── Task 6: dbt test --select marts
└── Task 7: Freshness alert (if test fails)
```

---

### 6.4.4 Lakehouse Federation

Query external systems without migrating
data. Databricks federates queries to:

* Snowflake
* Azure Synapse / SQL Server
* MySQL / PostgreSQL
* Redshift
* BigQuery
* Salesforce Data Cloud

```sql
-- Create a foreign catalog
CREATE FOREIGN CATALOG snowflake_prod
  USING CONNECTION snowflake_connection
  OPTIONS (database 'PROD_DB');

-- Query external Snowflake table
-- directly from Databricks SQL
SELECT *
FROM snowflake_prod.public.orders
WHERE order_date >= '2025-01-01';

-- Join across systems!
SELECT
  dbx.customer_id,
  dbx.lifetime_value,
  sf.contract_value
FROM prod.gold.dim_customers  AS dbx
JOIN snowflake_prod.crm.accounts AS sf
  ON dbx.customer_id = sf.account_id;
```

**Use cases:**
* Gradual migration — query Snowflake
  while rebuilding in Databricks
* Cross-platform analytics without ETL
* Vendor-neutral reporting layer

**Performance considerations:**
* Lakehouse Federation pushes predicates
  to the remote system (filter pushdown)
* Large joins across systems are slow —
  cache remote data as a Delta table
  for repeated use

---

### 6.4.5 Data Sharing Architecture

Share Delta tables with external partners
or internal consumers without copying data.

```
Your Databricks Account
  prod.gold.partner_metrics
          │
          │ Delta Sharing protocol
          ▼
  ┌────────────────────┐
  │  Sharing Server    │
  │  (Unity Catalog)   │
  └────────┬───────────┘
           │
    ┌──────┴──────┐
    │             │
    ▼             ▼
Partner A     Partner B
(Databricks)  (Spark/Pandas/BI)
```

```sql
-- Create a share
CREATE SHARE partner_a_share;

-- Add tables to share
ALTER SHARE partner_a_share
  ADD TABLE prod.gold.partner_metrics
  WITH PARTITION FILTER
    (partner_id = 'PARTNER_A');

-- Create recipient
CREATE RECIPIENT partner_a_recipient;

-- Audit who accessed the share
SELECT *
FROM system.access.audit
WHERE action_name = 'deltaSharingQueryTable'
  AND request_params:share = 'partner_a_share';
```

---

### 6.4.6 Medallion with Streaming (Real-Time)

For low-latency use cases requiring
pipeline-to-BI latency < 5 minutes:

```
Kafka topic: orders
      │
      ▼
[DLT Pipeline]
  @dlt.table Bronze: raw_orders_stream
      │
  @dlt.table Silver: orders_clean
      (deduplicated, typed)
      │
  @dlt.table Gold: orders_realtime_agg
      (5-min rolling window metrics)
      │
      ▼
[Materialized View]
prod.gold.mv_orders_dashboard
      │
      ▼
[SQL Warehouse]
Power BI Direct Query
(sub-second dashboard refresh)
```

**DLT implementation:**

```python
import dlt
from pyspark.sql.functions import (
  from_json, col, window, sum as _sum
)

@dlt.table(name="raw_orders_stream")
def bronze():
    return (
      spark.readStream
        .format("kafka")
        .option("subscribe", "orders")
        .load()
        .select(
          from_json(
            col("value").cast("string"),
            order_schema
          ).alias("data"),
          col("timestamp").alias("_ts")
        )
        .select("data.*", "_ts")
    )

@dlt.table(name="orders_clean")
@dlt.expect_or_drop(
  "valid_order_id",
  "order_id IS NOT NULL"
)
def silver():
    return dlt.read_stream("raw_orders_stream")

@dlt.table(name="orders_realtime_agg")
def gold():
    return (
      dlt.read_stream("orders_clean")
        .groupBy(
          window("_ts", "5 minutes"),
          "region"
        )
        .agg(_sum("amount").alias("revenue"))
    )
```

---

## 6.5 Architecture Decision Framework

### 6.5.1 Architecture Decision Records (ADRs)

Document every significant architecture
decision with an ADR. This prevents
"why did we do this?" confusion later.

**ADR Template:**

```markdown
# ADR-001: Use Serverless SQL Warehouse
## Status: Accepted
## Date: 2025-03-15

## Context
We need a SQL compute layer for 40
analysts to run ad hoc queries and
power Power BI dashboards. We evaluated:
- Classic SQL Warehouse
- Serverless SQL Warehouse
- All-Purpose Cluster

## Decision
Use Serverless SQL Warehouse.

## Rationale
- No VM management overhead
- Instant startup (vs 5 min classic)
- Pay per query (vs per uptime)
- 30% cost reduction for our query pattern

## Consequences
- Slightly higher DBU rate per query
- Network must allow Databricks-managed VMs
- Cannot install custom JARs (acceptable)
```

---

### 6.5.2 Pattern Selection Guide

Use this decision tree when designing:

```
Q: Do you need sub-minute latency?
├── YES → Kappa or DLT Streaming
│         (Kafka → Structured Streaming
│          → Delta MERGE)
└── NO  →
     Q: Do you need both stream + batch?
     ├── YES → Lambda Architecture
     │         (batch corrects stream)
     └── NO  →
          Q: Is primary transformation SQL?
          ├── YES → Medallion + dbt
          │         (most common pattern)
          └── NO  →
               Q: Heavy Python/ML?
               ├── YES → Medallion + Notebooks
               │         (+ MLflow tracking)
               └── NO  → Medallion + dbt
                         (default choice)
```

---

### 6.5.3 Non-Functional Requirements

Every architecture must define these
before implementation:

| NFR | Questions to Answer |
|-----|---------------------|
| **Latency** | Max time raw → dashboard? |
| **Throughput** | Peak events per second? |
| **Availability** | What is acceptable downtime? |
| **RPO** | Max data loss if system fails? |
| **RTO** | Max time to recover from failure? |
| **Scale** | Growth rate over 3 years? |
| **Security** | Compliance needs (HIPAA/PCI)? |
| **Cost** | Monthly budget ceiling? |

**NFR worksheet example:**

```
Pipeline: Order processing system

Latency:     Raw → Gold < 15 minutes
Throughput:  10,000 events/second peak
Availability: 99.5% (43 hrs downtime/yr)
RPO:         < 5 minutes
RTO:         < 30 minutes
Scale:       3x growth over 2 years
Security:    PCI-DSS Level 1
Budget:      < $8,000/month
```

---

### 6.5.4 Architecture Review Checklist

Use this before presenting a design:

**Data Layer**
```
[ ] Each layer (bronze/silver/gold)
    has a clear owner and SLA
[ ] Retention policy defined per layer
[ ] Schema versioning strategy defined
[ ] Data contracts documented
```

**Compute Layer**
```
[ ] Right cluster type per workload
[ ] Autoscaling configured where needed
[ ] Auto-terminate set on all clusters
[ ] Spot instances used where safe
[ ] Photon enabled for SQL workloads
```

**Governance**
```
[ ] Unity Catalog namespace defined
[ ] Access control model documented
[ ] PII columns identified and masked
[ ] Audit logging enabled
[ ] Data lineage coverage confirmed
```

**Operations**
```
[ ] Pipeline monitoring configured
[ ] Alerting on failures (Slack/PagerDuty)
[ ] Runbook for common failure modes
[ ] DR plan tested and documented
[ ] Cost alert thresholds set
```

**Security**
```
[ ] VNet injection configured
[ ] Private Link enabled
[ ] Service principals for automation
[ ] Secrets in Databricks Secret Scope
[ ] No hardcoded credentials in notebooks
```

---

## Phase 6 Summary

| Topic | Key Takeaways |
|-------|---------------|
| Landing Zone | Separate workspace per env, storage per layer, hub-and-spoke network |
| Migration | Always validate with row counts + aggregates; plan re-architecture within 18 months |
| Sizing | Use job clusters for prod, spot workers, Serverless SQL for analysts |
| Lambda | Batch + stream combined; batch corrects stream for accuracy |
| Kappa | Stream-only; replay Kafka to reprocess historic data |
| Medallion + dbt | Most common pattern; SQL-first, Git-native, testable |
| Lakehouse Federation | Query external systems without migrating data |
| ADRs | Document every key architecture decision |

**Self-Assessment Checklist:**
* [ ] Can you design a Databricks Landing
      Zone from scratch?
* [ ] Can you compare hub-and-spoke vs.
      Data Mesh topologies?
* [ ] Can you estimate DBU cost for a
      given workload?
* [ ] Can you choose between Lambda,
      Kappa, or Medallion+dbt?
* [ ] Can you create an ADR for a major
      architecture decision?
* [ ] Can you define NFRs before
      designing a solution?
* [ ] Can you plan a Hadoop or Snowflake
      migration step by step?

---

## Resources

* Databricks: "Solutions Architect
  Reference Architectures"
  `databricks.com/resources/guide`
* Databricks: "The Big Book of
  Data Engineering" (free PDF)
* Databricks: "Well-Architected
  Framework for Databricks"
* AWS / Azure / GCP: Cloud Adoption
  Framework (Landing Zone guidance)
* Book: "Fundamentals of Data Engineering"
  (O'Reilly — Joe Reis & Matt Housley)
* dbt docs: `docs.getdbt.com`
