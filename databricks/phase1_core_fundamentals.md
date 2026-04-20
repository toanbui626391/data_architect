# Phase 1: Core Fundamentals
*Databricks Data & Solution Architect Track*

***

## 1.1 Databricks Architecture

### Overview

Databricks is a unified data analytics platform built on top of Apache Spark. It uses a **split-plane architecture** that separates management from compute.

### Control Plane

* **Owned and managed by:** Databricks.
* **Hosts:** Web UI, REST APIs, job scheduler, cluster manager, and notebook metadata.
* **Key Point:** Your raw data never passes through the Control Plane. Only orchestration commands and metadata travel here.
* **Location:** Databricks-managed cloud region (e.g., us-east-1).

### Data Plane

* **Owned and managed by:** You (your cloud account).
* **Hosts:** Spark clusters (EC2, Azure VMs, GCP VMs) and your data in object storage (S3, ADLS Gen2, GCS).
* **Key Point:** All actual data processing happens entirely within your cloud account, so your data stays inside your security perimeter.

```
  ┌──────────────────────────────┐
  │       CONTROL PLANE          │
  │   (Databricks-managed)       │
  │  - Web UI / Notebooks        │
  │  - REST API                  │
  │  - Job Scheduler             │
  │  - Cluster Manager           │
  └──────────┬───────────────────┘
             │ Orchestration Commands
             ▼
  ┌──────────────────────────────┐
  │        DATA PLANE            │
  │   (Your Cloud Account)       │
  │  - Spark Driver Nodes        │
  │  - Spark Worker Nodes        │
  │  - Object Storage (S3/ADLS)  │
  └──────────────────────────────┘
```

### Classic vs. Serverless Compute

| Feature | Classic | Serverless |
|---|---|---|
| Cluster startup | 5–10 min | Seconds |
| Management | You manage VMs | Databricks manages |
| Cost model | DBU + VM cost | DBU only |
| Best for | ETL, custom libraries | SQL, DLT pipelines |

### Cloud Provider Integration

Databricks integrates with all three major clouds:

* **AWS:** Clusters run as EC2 instances. Data in S3. IAM roles for access.
* **Azure:** Clusters run as Azure VMs. Data in ADLS Gen2. Entra ID integration.
* **GCP:** Clusters run as Compute Engine VMs. Data in GCS. Service accounts.

The core product is identical across clouds. The difference is only in networking and IAM.

### Networking Concepts

* **VNet Injection (Azure) / VPC Injection (AWS):** Deploy Databricks clusters inside your own virtual network, not Databricks' managed one. Required for most enterprise deployments.
* **Private Link:** Encrypts and privatizes traffic between the Control Plane and Data Plane. No traffic over the public internet.
* **IP Access Lists:** Restrict which IP addresses can reach the Databricks UI and APIs.

**Architect Tip:** Always deploy with VNet injection and Private Link in production environments. This is a compliance requirement for most regulated industries (HIPAA, PCI-DSS).

***

## 1.2 Apache Spark Engine

### What is Spark?

Apache Spark is a distributed, in-memory computation engine. It is the execution engine behind all Databricks workloads—SQL, Python, Scala, R, and ML.

### Cluster Anatomy

A Spark cluster has exactly two node types:

**Driver Node**
* The "brain" of a Spark job.
* Parses your code, creates the execution plan, and coordinates workers.
* Runs the `SparkSession` and `SparkContext`.
* Collects results back from workers when called.
* Single point of failure—if the driver dies, the job fails.

**Worker Nodes (Executors)**
* The "muscle" of the cluster.
* Each worker runs one or more **Executors**.
* Each Executor is a JVM process that runs **tasks** assigned by the driver.
* Tasks operate on **partitions** of data in memory.

```
  Driver
    │
    ├── Worker 1 ── Executor ── Task A │ Task B
    ├── Worker 2 ── Executor ── Task C │ Task D
    └── Worker 3 ── Executor ── Task E │ Task F
```

### Data Structures

**RDD (Resilient Distributed Dataset)**
* The lowest-level Spark abstraction.
* An immutable, distributed collection of Java/Python objects.
* No schema (no column names or types).
* Rarely used directly today. Use DataFrames instead.

**DataFrame**
* Built on top of RDDs.
* Has a defined **schema** (column names and data types).
* Highly optimized by the Catalyst Optimizer.
* The standard data structure for all Databricks workloads.

**Dataset**
* A typed version of a DataFrame.
* Compile-time type safety. Only available in Scala/Java.
* In Python, DataFrames and Datasets are the same object.

### Lazy Evaluation

This is the most important concept to understand about Spark's execution model.

* **Transformations** (`filter`, `select`, `join`, `groupBy`) are **lazy**. They do not execute when called. Spark simply records the instruction.
* **Actions** (`show`, `count`, `write`, `collect`) trigger actual execution.

**Why lazy evaluation?**
Spark collects all your transformation instructions first, then uses the **Catalyst Optimizer** to find the most efficient execution path before running anything.

```python
# Nothing executes yet:
df = spark.read.format("delta").load("/data/orders")
df_filtered = df.filter(df.status == "active")
df_renamed = df_filtered.withColumnRenamed("id", "order_id")

# Execution is triggered here:
df_renamed.write.format("delta").save("/data/active_orders")
```

### DAG (Directed Acyclic Graph)

When an action is triggered, Spark compiles all recorded transformations into a **DAG**—a logical map of stages and tasks.

* **Stage:** A group of tasks that can run in parallel without data movement between nodes.
* **Task:** A single unit of work that processes one partition on one executor.
* **Stage boundaries** are created wherever a **shuffle** is needed.

### Shuffle Operations

A **shuffle** occurs when data must be physically moved between partitions across nodes. This is the most expensive Spark operation.

Operations that cause shuffles:
* Wide joins (`join`, where keys don't align to partitions)
* Aggregations (`groupBy`, `distinct`)
* Sorting (`orderBy`)
* Repartitioning (`repartition`)

**Architect Tip:** Design your data models and code to minimize shuffles. Use broadcast joins (`spark.sql.autoBroadcastJoinThreshold`) for small lookup tables. Monitor shuffles in the Spark UI.

### Catalyst Optimizer

The Catalyst Optimizer automatically rewrites your Spark query plan into a more efficient form. It does this in four steps:

1. **Analysis:** Resolves column names and data types.
2. **Logical Optimization:** Pushes filters down, combines projections, rewrites expressions.
3. **Physical Planning:** Selects join strategies (broadcast vs. sort-merge vs. hash).
4. **Code Generation:** Generates optimized JVM bytecode using Tungsten.

**Architect Tip:** You rarely need to manually optimize simple queries. However, for complex pipelines with many joins and aggregations, reviewing the physical plan with `df.explain(True)` is essential.

### Tungsten Engine

Tungsten is Spark's low-level binary execution engine:
* Stores data in off-heap binary format (not Java objects).
* Eliminates Java garbage collection overhead.
* Generates optimized bytecode for CPU cache efficiency.

The combination of **Catalyst + Tungsten** is what makes DataFrames dramatically faster than raw RDDs.

### Partitions in Detail

* A DataFrame is split into N logical **partitions**, each stored on a different executor.
* One CPU core processes one partition at a time.
* The default number of shuffle partitions is `200` (`spark.sql.shuffle.partitions`). This is almost always wrong for your workload and should be tuned.

**Sizing Rule of Thumb:**
* Target partition size: **100 MB to 200 MB** of data per partition.
* Too few partitions → underutilized cluster, OOM errors.
* Too many partitions → excessive task scheduling overhead.

**Key Functions:**
* `repartition(N)`: Creates a full shuffle to produce N balanced partitions.
* `coalesce(N)`: Reduces partition count without a full shuffle (merge only).
* `df.rdd.getNumPartitions()`: Check the current number of partitions.

***

## 1.3 Delta Lake

### What is Delta Lake?

Delta Lake is an open-source storage layer that adds ACID transactions and other database-like features to cloud object storage (S3, ADLS, GCS).

Without Delta Lake, cloud data lakes are just files with no guarantees: no atomicity, no schema enforcement, no update/delete capability.

### The Transaction Log (`_delta_log/`)

This is the heart of Delta Lake. Every Delta table has a hidden `_delta_log/` directory alongside the data files.

* Every operation (insert, update, delete, schema change) creates a new **JSON commit file** in `_delta_log/`.
* Each JSON file records exactly what data files were added or removed.

```
/my_table/
  ├── _delta_log/
  │   ├── 00000000000000000000.json  ← commit 0 (initial write)
  │   ├── 00000000000000000001.json  ← commit 1 (update)
  │   ├── 00000000000000000002.json  ← commit 2 (delete)
  │   └── 00000000000000000010.checkpoint.parquet
  ├── part-00001.snappy.parquet
  └── part-00002.snappy.parquet
```

After every 10 commits, Delta consolidates the log into a **Parquet checkpoint file** for faster reads.

### ACID Properties

**Atomicity:**
* A write either fully completes or the table is left untouched.
* No corrupted half-written files.

**Consistency:**
* The table always moves from one valid state to another.
* Schema constraints and data quality rules are enforced.

**Isolation:**
* Concurrent readers always see a consistent snapshot.
* Writers use **Optimistic Concurrency Control (OCC)**: they write, then check for conflicts before committing.

**Durability:**
* Once a commit JSON file is written to cloud storage, the data is permanently saved.

### Schema Enforcement

Delta Lake rejects writes that don't match the existing table schema by default.

```python
# This will FAIL if the schema doesn't match:
df_wrong_schema.write \
  .format("delta") \
  .mode("append") \
  .save("/data/my_table")
# Error: A schema mismatch detected when writing to the Delta table.
```

This prevents accidental data corruption from an upstream pipeline change.

### Schema Evolution

When you intentionally want to add or change columns, you opt in:

```python
# Add new columns automatically:
df_new_columns.write \
  .format("delta") \
  .mode("append") \
  .option("mergeSchema", "true") \
  .save("/data/my_table")
```

**`overwriteSchema`:** Use when you need to completely replace the table schema (a more destructive operation).

### Time Travel

Because every historical version is recorded in `_delta_log/`, you can query any past version of a table.

```sql
-- Query a specific version number:
SELECT * FROM orders VERSION AS OF 5;

-- Query the table as it was at a point in time:
SELECT * FROM orders TIMESTAMP AS OF '2024-06-01';
```

**Use Cases:**
* Auditing: "What did this record look like 3 days ago?"
* Data recovery: Roll back a bad write.
* Reproducibility: Re-run an ML training job on the exact same data snapshot.

### `OPTIMIZE`

Over time, many small parquet files accumulate in a Delta table (from streaming writes or many small batch jobs). This causes slow reads ("small file problem").

`OPTIMIZE` compacts small files into fewer, larger files:

```sql
OPTIMIZE orders;
```

**Target file size:** 1 GB per file (Databricks default).

### `ZORDER`

`ZORDER` co-locates related rows within files, so that queries that filter on specific columns can skip entire files.

Think of it as a multi-dimensional index embedded within the file layout.

```sql
OPTIMIZE orders ZORDER BY (customer_id, order_date);
```

**Use `ZORDER` on columns that are:**
* Frequently used in `WHERE` clause filters.
* High cardinality (many unique values).

**Do NOT use `ZORDER` on:**
* Columns already used for Hive-style partitioning.
* More than 3–4 columns at once (diminishing returns).

### `VACUUM`

After updates and deletes, Delta Lake keeps old data files to support time travel. `VACUUM` permanently deletes files that are older than the retention threshold.

```sql
-- Default: removes files older than 7 days (168 hours):
VACUUM orders;

-- Custom retention (must be >= 7 days by default):
VACUUM orders RETAIN 336 HOURS;
```

**Warning:** Files deleted by `VACUUM` cannot be recovered. After running VACUUM, you cannot time travel past the retention threshold.

### Liquid Clustering (Modern Alternative)

Liquid Clustering is a new feature designed to replace `ZORDER` and Hive-style partitioning.

**Hive Partitioning Problems:**
* Partitioning on a low-cardinality column (e.g., country) creates too few files.
* Partitioning on a high-cardinality column (e.g., user_id) creates millions of tiny directories.

**Liquid Clustering solves this by:**
* Dynamically grouping data within files based on cluster columns.
* Incrementally re-clustering only changed data (no full-table rewrites).
* Supporting easy changes to clustering columns without migration.

```sql
-- Create table with Liquid Clustering:
CREATE TABLE orders
CLUSTER BY (customer_id, order_date);

-- Run incremental clustering:
OPTIMIZE orders;
```

**Architect Recommendation:** Use Liquid Clustering for all new Delta tables. It is simpler, more flexible, and more performant than `ZORDER`.

***

## 1.4 Cluster Configuration

### Cluster Types

**All-Purpose Clusters**
* Persistent, manually started and stopped.
* Designed for interactive development: notebooks, exploration, ad hoc queries.
* Shared across teams (multi-user mode).
* **Never use for production automated jobs** — they are expensive and waste resources when idle.

**Job Clusters**
* Ephemeral: created at job start, terminated at job end.
* Optimized for automated workloads (ETL pipelines, batch jobs).
* Cannot be accessed interactively.
* **Best practice:** Always use Job Clusters for production Databricks Workflows.

**SQL Warehouses**
* Specialized compute for SQL-only workloads via Databricks SQL.
* Serverless or Classic options available.
* No Spark configuration required; fully managed by Databricks.

### Single Node vs. Standard Clusters

| | Single Node | Standard |
|---|---|---|
| Workers | 0 (driver only) | 1+ |
| Use case | Local dev, small datasets | Production workloads |
| Libraries | Full Spark + ML support | Full Spark + ML support |
| Cost | Cheaper | Scales with workers |

**Single Node clusters** are useful for running ML model training where the library (scikit-learn, XGBoost) is not distributed. It avoids the overhead of managing workers.

### Autoscaling

Autoscaling allows Databricks to automatically add or remove worker nodes based on cluster load.

* **Min Workers / Max Workers:** Set bounds to control cost.
* **Scale Up:** Adds workers when task queue backs up.
* **Scale Down:** Removes idle workers after a configurable period.

**When to use autoscaling:**
* Variable or unpredictable workloads.
* Interactive clusters shared by multiple users.

**When NOT to use autoscaling:**
* Structured Streaming jobs (scaling disrupts micro-batch execution).
* Time-sensitive ETL jobs (scale-up latency adds unpredictability).

### Spot / Preemptible Instances

Cloud providers offer "leftover" compute capacity at a steep discount (60–90% cheaper):

* AWS: **Spot Instances**
* Azure: **Spot VMs**
* GCP: **Preemptible VMs**

**Risk:** These can be reclaimed by the cloud provider with short notice (typically 2 minutes).

**Architect Pattern:**
* Use **On-Demand** for the Driver (ensures job coordination doesn't fail).
* Use **Spot** for Workers (if a worker is lost, Spark retries the failed task).

```
Driver (On-Demand)  ← Never preempted
Worker 1 (Spot)     ← Cheap, tolerates interruption
Worker 2 (Spot)     ← Cheap, tolerates interruption
```

### Databricks Runtime Versions

Each cluster runs a specific **Databricks Runtime (DBR)** version, which bundles:
* Apache Spark version
* Delta Lake version
* Pre-installed Python/ML libraries
* Optimized connectors for cloud storage

**Key Runtime Variants:**

| Runtime | Description |
|---|---|
| Standard DBR | Core Spark + Delta Lake |
| ML Runtime | Adds PyTorch, TensorFlow, scikit-learn |
| Genomics Runtime | Adds Glow for genomics data |
| Photon Runtime | Adds Photon vectorized engine |

**Photon:**
* A C++ vectorized query engine that replaces JVM-based Spark execution for SQL and DataFrame ops.
* 2–8x faster for SQL workloads.
* No code changes required—it's transparent to the user.

### Init Scripts

Init scripts run shell commands on every node when a cluster starts, before the Spark session is initialized.

**Use cases:**
* Install OS-level dependencies.
* Set environment variables.
* Configure security agents (e.g., CrowdStrike, Qualys).
* Mount network file systems.

```bash
#!/bin/bash
# Example init script: install a custom Python library
pip install my-custom-package==1.2.3
```

**Architect Caution:** Init scripts increase cluster startup time. Minimize their use. Prefer Databricks libraries or cluster-scoped library installs when possible.

***

## Phase 1 Summary

| Topic | Key Points |
|---|---|
| Architecture | Control Plane (Databricks) vs. Data Plane (your cloud) |
| Spark | Lazy evaluation, DAG, Catalyst optimizer, partitions |
| Delta Lake | ACID via `_delta_log/`, time travel, OPTIMIZE, ZORDER |
| Clusters | Job vs. All-Purpose, autoscaling, Spot instances |

**Self-Assessment Checklist:**
* [ ] Can you explain the Control/Data plane split?
* [ ] Can you describe what happens when Spark runs a job?
* [ ] Can you explain why Delta Lake's `_delta_log/` enables ACID?
* [ ] Can you choose the right cluster type for a given workload?
* [ ] Can you explain the difference between ZORDER and Liquid Clustering?

***

## Resources

* Databricks Academy: "Apache Spark Programming with Databricks"
* Databricks Docs: `docs.databricks.com/delta/index.html`
* Book: "Delta Lake: The Definitive Guide" (O'Reilly)
* Book: "Learning Spark, 2nd Edition" (O'Reilly)
