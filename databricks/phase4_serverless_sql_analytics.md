# Phase 4: Serverless & SQL Analytics
*Databricks Data & Solution Architect Track*

***

## 4.1 Databricks SQL (DBSQL)

### What is Databricks SQL?

Databricks SQL (DBSQL) is the native SQL analytics service in the Lakehouse platform. It provides a dedicated, optimized compute layer for running SQL queries, building dashboards, and connecting BI tools — all directly against Delta Lake tables governed by Unity Catalog.

**Why DBSQL Matters for Architects:**
* It's the primary interface for analysts who don't write Python/Scala.
* SQL Warehouses are the recommended compute for all BI and reporting workloads.
* It decouples the "query" workload from the "engineering" workload — different compute, different cost profile.
* Serverless SQL eliminates cluster management entirely for SQL workloads.

**Key Capabilities:**
* Full ANSI SQL support with Delta Lake extensions.
* Native integration with Unity Catalog (all governance policies apply automatically).
* Query History and Query Profile for deep performance analysis.
* Built-in visualization and dashboard authoring.
* AI-powered SQL Assistant for query generation.

### Serverless vs. Classic SQL Warehouses

This is one of the most important architectural decisions for SQL workloads.

**Classic SQL Warehouse:**
* Clusters run **inside your cloud account** (your VPC/VNet).
* You manage (or configure) cluster sizing, startup, and shutdown.
* Cold start time: **5–10 minutes** for new clusters.
* You pay for the compute while it's running, even during idle time (before auto-stop).

**Serverless SQL Warehouse:**
* Clusters run in **Databricks-managed infrastructure** (Databricks' cloud account).
* No cluster management — Databricks handles provisioning, scaling, and patching.
* Cold start time: **~10 seconds** (near-instant).
* You pay only for the queries you run (measured in DBUs).
* Automatic multi-cluster scaling for concurrency.

**Comparison:**

| Factor | Classic | Serverless |
|---|---|---|
| Startup time | 5–10 minutes | ~10 seconds |
| Infrastructure | Your cloud account | Databricks-managed |
| Scaling | Manual or autoscale | Automatic, instant |
| Network isolation | Full (VNet/VPC) | Shared (with security controls) |
| Cost model | Pay while running | Pay per query (DBU) |
| Maintenance | You manage runtime | Databricks manages |
| Ideal for | Strict network reqs | Most SQL workloads |

**Architect Recommendation:** Default to **Serverless** for all new SQL workloads unless you have regulatory requirements that mandate compute running inside your own VPC (e.g., certain HIPAA or PCI-DSS scenarios). The near-instant startup and zero management overhead significantly reduce operational cost.

```sql
-- Create a Serverless SQL Warehouse via SQL (API-managed)
-- Typically done via the UI or Terraform:

-- Terraform example:
-- resource "databricks_sql_endpoint" "analytics" {
--   name             = "analytics-warehouse"
--   cluster_size     = "Medium"
--   max_num_clusters = 5
--   enable_serverless_compute = true
--   warehouse_type   = "PRO"
-- }
```

### Warehouse Sizing Tiers

SQL Warehouses come in T-shirt sizes. Each size doubles the compute capacity (and cost) of the previous one.

| Size | Cluster Workers | Typical Use Case |
|---|---|---|
| 2X-Small | 1 | Development, light testing |
| X-Small | 1 | Small team, few concurrent queries |
| Small | 2 | Medium team, moderate dashboards |
| Medium | 4 | Department-level analytics |
| Large | 8 | Enterprise BI, heavy dashboards |
| X-Large | 16 | Large-scale concurrent access |
| 2X-Large | 32 | Heavy ETL + BI combined |
| 3X-Large | 64 | Very large data, complex queries |
| 4X-Large | 128 | Extreme workloads, rare |

**Multi-Cluster Scaling:**

For handling concurrency (many users running queries simultaneously), SQL Warehouses support **multi-cluster** mode:

```
Single Cluster:          Multi-Cluster (max=5):
┌──────────────┐         ┌──────────────┐
│  Warehouse   │         │  Cluster 1   │  ← queries 1–10
│  (Medium)    │         ├──────────────┤
│              │         │  Cluster 2   │  ← queries 11–20
│  All queries │         ├──────────────┤
│  share this  │         │  Cluster 3   │  ← queries 21–30
│  one cluster │         ├──────────────┤
└──────────────┘         │  Cluster 4   │  ← auto-scaled
                         ├──────────────┤
                         │  Cluster 5   │  ← auto-scaled
                         └──────────────┘
```

* **Min clusters**: Always running (guarantees no cold start for first users).
* **Max clusters**: Upper bound for auto-scaling.
* Each cluster is the same T-shirt size.

**Sizing Decision Framework:**

```
┌─ How many concurrent users? ─────────────────────────────┐
│                                                           │
│  < 5 users      → X-Small, 1 cluster                    │
│  5–20 users     → Small/Medium, max 3 clusters          │
│  20–100 users   → Medium/Large, max 5–10 clusters       │
│  100+ users     → Large, max 10+ clusters               │
│                                                           │
├─ How complex are the queries? ───────────────────────────┤
│                                                           │
│  Simple SELECTs on small tables  → 2X-Small / X-Small   │
│  JOINs across 100M+ row tables  → Medium / Large        │
│  Heavy aggregations, window fns  → Large / X-Large      │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

### Query Optimization with Query History & Query Profile

DBSQL provides two powerful tools for query performance analysis.

**Query History:**
The central log of all queries executed on a warehouse. Accessible via **SQL Warehouses > Query History**.

```
Query History Entry:
┌────────────────────────────────────────────────────┐
│ Query ID: abc-123-def                              │
│ User: analyst@company.com                          │
│ Status: Succeeded                                  │
│ Duration: 12.4s                                    │
│ Rows Returned: 1,500,234                           │
│ Data Scanned: 2.3 GB                               │
│ Warehouse: analytics-warehouse (Medium)            │
│ Timestamp: 2026-04-20 10:30:00 UTC                 │
└────────────────────────────────────────────────────┘
```

**Key metrics to monitor:**
* **Duration**: Total wall-clock time.
* **Rows scanned vs. rows returned**: High scan with low return = missing filters or partitioning.
* **Bytes scanned**: High scan = consider ZORDER or partition pruning.
* **Queue time**: Time waiting for available compute = scale up clusters.

**Query Profile:**
A visual execution plan for an individual query. Click any query in Query History, then click **"Query Profile"**.

The profile shows a **DAG** (directed acyclic graph) of execution stages:

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Scan        │────►│  Filter      │────►│  Aggregate   │
│  orders      │     │  status =    │     │  SUM(amount) │
│  (2.3 GB)    │     │  'completed' │     │  GROUP BY    │
└──────────────┘     └──────────────┘     └──────────────┘
      │                                          │
      │                                          ▼
      │                                   ┌──────────────┐
      │                                   │  Sort        │
      │                                   │  ORDER BY    │
      │                                   │  revenue DESC│
      └───────────────────────────────────└──────────────┘
```

**What to look for in Query Profile:**
* **Scan stage**: Are you scanning the full table? Apply `ZORDER` or filters.
* **Shuffle stage**: Data being redistributed across nodes = expensive. Minimize large JOINs.
* **Spill to disk**: Data doesn't fit in memory = increase warehouse size.
* **Skew**: One worker doing much more work than others = data skew in JOIN key.

**Common Optimization Patterns:**

```sql
-- 1. Use ZORDER on frequently filtered/joined columns:
OPTIMIZE curated.sales.orders ZORDER BY (region, order_date);

-- 2. Use ANALYZE TABLE to update statistics for the optimizer:
ANALYZE TABLE curated.sales.orders COMPUTE STATISTICS FOR ALL COLUMNS;

-- 3. Avoid SELECT * — project only needed columns:
-- Bad:
SELECT * FROM curated.sales.orders WHERE region = 'APAC';
-- Good:
SELECT order_id, amount, status FROM curated.sales.orders WHERE region = 'APAC';

-- 4. Use predicate pushdown (filter early):
-- Bad (filter after join):
SELECT o.*, c.full_name
FROM orders o JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_date > '2026-01-01';
-- Good (filter pushed to scan):
SELECT o.order_id, o.amount, c.full_name
FROM (SELECT * FROM orders WHERE order_date > '2026-01-01') o
JOIN customers c ON o.customer_id = c.customer_id;

-- 5. Use table caching for repeatedly queried small tables:
CACHE TABLE curated.sales.regions;
```

### Materialized Views vs. Standard Views

**Standard View:**
* A SQL query stored as a named object — no data is stored.
* Every time a user queries the view, the underlying SQL runs from scratch.
* Zero storage cost, but query cost every time.

```sql
CREATE VIEW curated.sales.daily_revenue AS
SELECT
  order_date,
  region,
  SUM(amount) AS total_revenue,
  COUNT(*)    AS order_count
FROM curated.sales.orders
WHERE status = 'completed'
GROUP BY order_date, region;

-- Every query against this view re-computes the aggregation.
SELECT * FROM curated.sales.daily_revenue WHERE region = 'APAC';
```

**Materialized View:**
* A query whose **results are pre-computed and stored** as a Delta table.
* Queries against the materialized view read from the stored result — near-instant.
* Databricks automatically refreshes the materialized view when the source data changes.
* Storage cost for the pre-computed results, but dramatically faster queries.

```sql
CREATE MATERIALIZED VIEW curated.sales.daily_revenue_mv AS
SELECT
  order_date,
  region,
  SUM(amount) AS total_revenue,
  COUNT(*)    AS order_count
FROM curated.sales.orders
WHERE status = 'completed'
GROUP BY order_date, region;

-- This reads from pre-computed results — almost instant.
SELECT * FROM curated.sales.daily_revenue_mv WHERE region = 'APAC';

-- Manually refresh (usually automatic):
REFRESH MATERIALIZED VIEW curated.sales.daily_revenue_mv;
```

**Comparison:**

| Feature | Standard View | Materialized View |
|---|---|---|
| Data stored? | No | Yes (Delta table) |
| Query speed | Depends on source | Near-instant |
| Storage cost | None | Proportional to result size |
| Auto-refresh | N/A | Yes (incremental) |
| Best for | Ad hoc, real-time | Dashboards, repeated queries |
| Unity Catalog | Full support | Full support |

**Architect Decision:**

```
┌─ When to use Standard Views ─────────────────────────────┐
│  • Security views (RLS/CLS). Materialized views can't    │
│    use current_user() or is_account_group_member().       │
│  • Ad hoc analysis — data freshness is critical.         │
│  • Small, fast queries that don't benefit from caching.  │
│                                                           │
├─ When to use Materialized Views ─────────────────────────┤
│  • Dashboard backing queries (Power BI / Tableau).       │
│  • Expensive aggregations (GROUP BY, WINDOW functions).  │
│  • Queries run repeatedly by many users.                 │
│  • Gold-layer summary tables.                            │
└───────────────────────────────────────────────────────────┘
```

### Streaming Tables in DBSQL

Streaming Tables provide continuous, incremental ingestion directly within DBSQL — no Spark cluster or DLT pipeline required.

```sql
-- Create a streaming table that ingests from a cloud location:
CREATE STREAMING TABLE curated.sales.orders_stream AS
SELECT *
FROM STREAM read_files(
  's3://company-edw-raw/orders/',
  format => 'json',
  schema => 'order_id BIGINT, customer_id BIGINT, amount DECIMAL(15,2), region STRING, order_date DATE'
);

-- Data is automatically ingested as new files arrive.
-- No need for Auto Loader notebooks or DLT pipelines.

-- Refresh manually (or schedule):
REFRESH STREAMING TABLE curated.sales.orders_stream;
```

**Key differences:**

| Feature | Regular Table | Streaming Table | Materialized View |
|---|---|---|---|
| Data arrives | Manual INSERT | Auto-incremental | Auto from source table |
| Source | Any | Cloud files / Kafka | Other Delta tables |
| Use case | Static data | Real-time ingestion | Pre-computed queries |

### Connection via JDBC/ODBC to BI Tools

SQL Warehouses expose standard JDBC and ODBC endpoints for external tool connectivity.

**Connection Details (found in warehouse settings):**

```
Server Hostname:  adb-1234567890.1.azuredatabricks.net
Port:             443
HTTP Path:        /sql/1.0/warehouses/abcdef1234567890
Protocol:         HTTPS (TLS 1.2+)
Authentication:   Personal Access Token or OAuth
```

**JDBC Connection String:**
```
jdbc:databricks://adb-1234567890.1.azuredatabricks.net:443
  /default;
  transportMode=http;
  ssl=1;
  httpPath=/sql/1.0/warehouses/abcdef1234567890;
  AuthMech=3;
  UID=token;
  PWD=<personal-access-token>
```

**Python (databricks-sql-connector):**
```python
from databricks import sql

connection = sql.connect(
    server_hostname="adb-1234567890.1.azuredatabricks.net",
    http_path="/sql/1.0/warehouses/abcdef1234567890",
    access_token="<personal-access-token>"
)

cursor = connection.cursor()
cursor.execute("SELECT region, SUM(amount) FROM curated.sales.orders GROUP BY region")
for row in cursor.fetchall():
    print(row)

cursor.close()
connection.close()
```

***

## 4.2 BI Integration Patterns

### Connecting Power BI

Power BI is one of the most common BI tools connected to Databricks SQL.

**Connection Methods:**

| Method | Mechanism | Data Freshness | Performance |
|---|---|---|---|
| DirectQuery | Sends SQL to warehouse live | Real-time | Depends on warehouse |
| Import | Copies data into Power BI | Scheduled refresh | Fast (in-memory) |
| Composite | Mix of DirectQuery + Import | Hybrid | Balanced |

**DirectQuery Setup (Recommended for Lakehouse):**
1. Open Power BI Desktop.
2. Click **Get Data > Azure > Azure Databricks**.
3. Enter the Server Hostname and HTTP Path from your SQL Warehouse.
4. Select **DirectQuery** mode.
5. Authenticate with Azure AD (SSO) or Personal Access Token.
6. Select tables/views from your Unity Catalog.

```
Power BI Report
      │
      ▼ (DirectQuery: SQL sent live)
SQL Warehouse (Serverless)
      │
      ▼ (Unity Catalog enforces RLS/CLS/RBAC)
Delta Lake Tables
      │
      ▼
Cloud Storage (S3 / ADLS / GCS)
```

**Key Architecture Decision — DirectQuery vs. Import:**

```
┌─ Use DirectQuery when: ──────────────────────────────────┐
│  • Data freshness is critical (real-time dashboards).    │
│  • Dataset is too large to fit in Power BI memory.       │
│  • Row-level security must be enforced by Unity Catalog. │
│  • Single source of truth is important.                  │
│                                                           │
├─ Use Import when: ───────────────────────────────────────┤
│  • Dashboard performance is the top priority.            │
│  • Data is small (<1 GB) and doesn't change frequently.  │
│  • Users need offline access to reports.                 │
│  • Reducing SQL Warehouse cost is important.             │
└───────────────────────────────────────────────────────────┘
```

**Architect Tip:** Use **Materialized Views** in Databricks as the source for Power BI Import mode. This pre-aggregates data on the Databricks side, reducing both import size and refreshing time.

### Connecting Tableau

**Tableau Connection Setup:**
1. Install the **Databricks ODBC driver** (or use the native Tableau connector).
2. In Tableau Desktop: **Connect > To a Server > Databricks**.
3. Enter Server Hostname and HTTP Path.
4. Authenticate via Personal Access Token or OAuth.
5. Select Catalog > Schema > Table from the Unity Catalog browser.

**Live vs. Extract:**

| Mode | Equivalent to | Data Freshness | Performance |
|---|---|---|---|
| Live Connection | DirectQuery | Real-time | Warehouse-dependent |
| Extract (.hyper) | Import | Scheduled | Fast (Hyper engine) |

**Best Practice for Tableau:**
* Use **Live Connection** for dashboards where data freshness matters.
* Use **Extracts** for large, complex dashboards used by many viewers.
* Publish to Tableau Server/Cloud and schedule extract refreshes during off-peak hours.

### Partner Connect

Databricks **Partner Connect** simplifies integrations by pre-configuring connections to supported tools.

**How it works:**
1. In the Databricks workspace: Click **Partner Connect** in the sidebar.
2. Select a partner (Power BI, Tableau, Fivetran, dbt, etc.).
3. Databricks automatically:
   * Creates a Service Principal for the partner.
   * Grants the SP access to a SQL Warehouse.
   * Generates a connection file (`.pbids` for Power BI, `.tds` for Tableau).
4. Open the connection file in your BI tool — you're connected.

**Supported Partners (key ones):**

| Category | Tools |
|---|---|
| BI & Visualization | Power BI, Tableau, Looker, Sigma, ThoughtSpot |
| Data Ingestion | Fivetran, Airbyte, Rivery, Matillion |
| Data Transformation | dbt Cloud, Prophecy |
| Data Quality | Monte Carlo, Great Expectations |
| Reverse ETL | Census, Hightouch |

**Architect Tip:** Use Partner Connect for initial setup to reduce time-to-value. However, for production deployments, switch to Terraform-managed Service Principals for better secret management and audit control.

### DirectQuery vs. Import Mode — Deep Dive

This decision impacts cost, freshness, and user experience significantly.

**Cost Impact:**

```
DirectQuery:
┌─────────────────────────────────────────────────────────┐
│  Every report page load = SQL query → Warehouse DBUs    │
│  100 users × 5 page loads/day × 20 workdays            │
│  = 10,000 queries/month → High DBU cost                │
│  BUT: No Power BI Premium capacity needed for storage   │
└─────────────────────────────────────────────────────────┘

Import:
┌─────────────────────────────────────────────────────────┐
│  Scheduled refresh (e.g., 4x/day) = limited queries     │
│  = ~120 queries/month → Low DBU cost                    │
│  BUT: Requires Power BI Premium for large datasets      │
│  AND: Data is stale between refreshes                   │
└─────────────────────────────────────────────────────────┘
```

**Hybrid Approach (Composite Model):**
Use Import for large, slowly changing dimension tables and DirectQuery for frequently updated fact tables:

```
Power BI Composite Model:
┌──────────────────────────────────────┐
│            Power BI Report            │
│  ┌────────────┐  ┌─────────────────┐ │
│  │  Imported   │  │  DirectQuery    │ │
│  │  dim_region │  │  fact_orders    │ │
│  │  dim_product│  │  (real-time)    │ │
│  │  (cached)   │  │                 │ │
│  └──────┬─────┘  └───────┬─────────┘ │
│         │ JOIN            │           │
│         └────────┬────────┘           │
│                  ▼                    │
│        Combined Result Set            │
└──────────────────────────────────────┘
```

***

## 4.3 Data Sharing

### Delta Sharing Protocol

Delta Sharing is an **open protocol** for secure, real-time data sharing across organizations, platforms, and clouds — without copying data.

**How Delta Sharing Works:**

```
┌──────────────────────┐         ┌──────────────────────┐
│     Data Provider     │         │     Data Recipient    │
│  (Databricks Account) │         │  (Any platform)       │
│                        │         │                       │
│  Delta Lake Tables     │         │  • Databricks         │
│       │                │         │  • Spark              │
│       ▼                │         │  • Pandas             │
│  Delta Sharing Server  │◄───────►│  • Power BI           │
│  (REST API endpoint)   │  HTTPS  │  • Tableau            │
│       │                │         │  • Java / Python      │
│       ▼                │         │  • Any REST client    │
│  Pre-signed URLs       │         │                       │
│  (direct S3/ADLS read) │────────►│  Reads data directly  │
│                        │         │  from cloud storage   │
└──────────────────────┘         └──────────────────────┘
```

**Key Properties:**
* **Open protocol**: Recipients don't need Databricks — any tool that speaks the Delta Sharing protocol (or REST) can consume data.
* **No data copy**: Recipients read data directly from the provider's cloud storage via pre-signed URLs.
* **Real-time**: Recipients always see the latest version of the data (no ETL lag).
* **Secure**: Provider controls exactly which tables/partitions are shared and can revoke access instantly.
* **Governed**: All sharing activity is logged in the provider's Unity Catalog audit tables.

### Types of Delta Sharing

**1. Open Sharing (Databricks-to-Anything):**
Shares data using a **credential file** (`.share` file) that contains a bearer token and REST endpoint.

```sql
-- Provider: Create a share
CREATE SHARE customer_analytics_share
  COMMENT 'Customer analytics data for partner XYZ';

-- Add tables to the share
ALTER SHARE customer_analytics_share
  ADD TABLE curated.sales.orders;

ALTER SHARE customer_analytics_share
  ADD TABLE curated.sales.customers;

-- Create a recipient (external organization)
CREATE RECIPIENT partner_xyz
  COMMENT 'Partner XYZ analytics team';

-- Grant the share to the recipient
GRANT SELECT ON SHARE customer_analytics_share
  TO RECIPIENT partner_xyz;

-- Download the activation link for the recipient
-- (provides a .share credential file)
```

**Recipient reads data (Python, no Databricks needed):**
```python
import delta_sharing

# Load the .share credential file
profile = delta_sharing.SharingProfile.read("partner_xyz.share")

# List available tables
tables = delta_sharing.list_all_tables(profile)
for table in tables:
    print(f"{table.share}.{table.schema}.{table.name}")

# Read a shared table into a Pandas DataFrame
df = delta_sharing.load_as_pandas(
    f"{profile}#customer_analytics_share.sales.orders"
)
print(df.head())

# Read into a Spark DataFrame
spark_df = delta_sharing.load_as_spark(
    f"{profile}#customer_analytics_share.sales.orders"
)
spark_df.show()
```

**2. Databricks-to-Databricks Sharing:**
Uses Unity Catalog's native sharing — no credential files needed. The recipient accesses shared data as a catalog in their own workspace.

```sql
-- Provider: Create and populate a share (same as above)
CREATE SHARE customer_analytics_share;
ALTER SHARE customer_analytics_share
  ADD TABLE curated.sales.orders;

-- Create a Databricks recipient (by account ID)
CREATE RECIPIENT partner_databricks
  USING ID 'abc-12345-databricks-account-id';

-- Grant access
GRANT SELECT ON SHARE customer_analytics_share
  TO RECIPIENT partner_databricks;
```

```sql
-- Recipient (in their own Databricks workspace):
-- The shared data appears as a catalog
CREATE CATALOG IF NOT EXISTS shared_analytics
  USING SHARE provider_account.customer_analytics_share;

-- Query shared data as if it were local
SELECT * FROM shared_analytics.sales.orders
WHERE region = 'APAC'
LIMIT 100;
```

### Sharing Partitioned Data

You can share specific partitions instead of entire tables to limit data exposure:

```sql
-- Share only APAC region data with a partner
ALTER SHARE apac_share
  ADD TABLE curated.sales.orders
  PARTITION (region = 'APAC');

-- Share only 2026 data
ALTER SHARE annual_share
  ADD TABLE curated.sales.orders
  PARTITION (order_date >= '2026-01-01');
```

### Recipient Management & Auditing

**List all shares and recipients:**
```sql
-- See all shares
SHOW SHARES;

-- See details of a share
DESCRIBE SHARE customer_analytics_share;

-- See all recipients
SHOW RECIPIENTS;

-- See what a recipient has access to
SHOW GRANTS TO RECIPIENT partner_xyz;
```

**Revoke access:**
```sql
-- Remove a table from the share
ALTER SHARE customer_analytics_share
  REMOVE TABLE curated.sales.orders;

-- Revoke access entirely
REVOKE SELECT ON SHARE customer_analytics_share
  FROM RECIPIENT partner_xyz;

-- Delete a recipient
DROP RECIPIENT partner_xyz;
```

**Audit sharing activity:**
```sql
-- All Delta Sharing access events
SELECT
  event_time,
  user_identity.email                AS recipient,
  action_name,
  request_params.share               AS share_name,
  request_params.schema              AS schema_name,
  request_params.name                AS table_name,
  source_ip_address
FROM system.access.audit
WHERE service_name = 'unityCatalog'
  AND action_name LIKE 'deltaSharing%'
  AND event_time >= current_date() - INTERVAL 30 DAYS
ORDER BY event_time DESC;
```

### Delta Sharing Architecture Patterns

**Pattern 1: Internal Data Marketplace**
Share curated datasets across departments within the same organization.

```
┌──────────────────────────────────────────────────────────┐
│                  Unity Catalog Metastore                   │
│                                                            │
│  ┌──────────────┐    SHARE    ┌──────────────────────┐   │
│  │ Data Team    │ ──────────► │ Marketing Workspace   │   │
│  │ (Provider)   │             │ (Recipient)           │   │
│  │              │             │                       │   │
│  │ curated.     │    SHARE    ├──────────────────────┤   │
│  │  sales.*     │ ──────────► │ Finance Workspace     │   │
│  │  marketing.* │             │ (Recipient)           │   │
│  └──────────────┘             └──────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

**Pattern 2: Partner / Vendor Data Exchange**
Share specific datasets with external partners securely.

```
┌─────────────────────┐                ┌─────────────────────┐
│   Your Company      │                │   Partner Company    │
│   (Databricks)      │                │   (Any platform)     │
│                     │   .share file   │                     │
│   Delta Sharing     │ ──────────────► │   Python / Spark     │
│   Server            │                │   Pandas / BI tool   │
│                     │                │                      │
│   curated.sales.    │                │   Reads data via     │
│   orders            │                │   pre-signed URLs    │
│   (filtered by      │                │   (no data copy)     │
│    partner region)  │                │                      │
└─────────────────────┘                └─────────────────────┘
```

**Pattern 3: Data Clean Room**
A trusted third-party workspace where both parties contribute data for joint analysis without exposing raw data to each other.

```
┌───────────────┐                          ┌───────────────┐
│   Company A   │     SHARE tables         │   Company B   │
│               │─────────────────────►    │               │
│               │                     │    │               │
└───────────────┘                     │    └───────────────┘
                                      ▼
                              ┌───────────────┐
                              │   Clean Room   │
                              │   Workspace    │
                              │                │
                              │  JOIN A + B    │
                              │  Aggregated    │
                              │  results only  │
                              │  (no raw data  │
                              │   exposed)     │
                              └───────────────┘
```

***

## 4.4 DBSQL Dashboards & Alerts

### Building Dashboards in DBSQL

Databricks SQL includes a native dashboard builder — no external BI tool required for simple visualizations.

**Dashboard Components:**
* **Queries**: SQL statements that fetch data.
* **Visualizations**: Charts, tables, counters attached to queries.
* **Parameters**: User-selectable filters (dropdowns, date pickers).
* **Filters**: Cross-visualization filters that apply to multiple charts.

**Creating a Dashboard:**

```sql
-- Step 1: Create a query
-- Name: "Daily Revenue by Region"
SELECT
  order_date,
  region,
  SUM(amount)   AS revenue,
  COUNT(*)      AS orders
FROM curated.sales.orders
WHERE order_date >= :start_date    -- parameter
  AND region IN (:region_filter)   -- parameter
GROUP BY order_date, region
ORDER BY order_date;

-- Step 2: In the DBSQL UI:
-- 1. Save the query
-- 2. Add a visualization (Line Chart: x=order_date, y=revenue, series=region)
-- 3. Add to a Dashboard
-- 4. Configure parameters (date picker for start_date, dropdown for region)
```

**Dashboard Sharing:**
```
Permissions:
┌──────────────────────────────────────────┐
│  Owner:      Full control (edit, delete) │
│  Can Edit:   Modify queries, layouts     │
│  Can Run:    Execute queries, view data  │
│  Can View:   See cached results only     │
└──────────────────────────────────────────┘
```

### SQL Alerts

Alerts are scheduled queries that trigger notifications when a condition is met.

**Example: Alert on Revenue Drop**

```sql
-- Alert Query: "Hourly Revenue Check"
SELECT
  SUM(amount) AS current_hour_revenue
FROM curated.sales.orders
WHERE order_date = current_date()
  AND hour(order_timestamp) = hour(now()) - 1;

-- Alert Configuration:
-- Trigger condition: current_hour_revenue < 10000
-- Schedule: Every 1 hour
-- Notification: Slack channel #revenue-alerts
```

**Example: Alert on Data Pipeline Failure**

```sql
-- Alert Query: "Missing Data Check"
SELECT
  COUNT(*) AS rows_today
FROM curated.sales.orders
WHERE order_date = current_date();

-- Trigger condition: rows_today = 0
-- Schedule: Every day at 9:00 AM
-- Notification: PagerDuty / Email
```

**Alert Destinations:**
* **Email**: Direct to users or distribution lists.
* **Slack**: Via Slack webhook integration.
* **PagerDuty**: For critical operational alerts.
* **Custom Webhook**: Any HTTP endpoint.

***

## 4.5 Serverless Compute Beyond SQL

### Serverless for Notebooks

Databricks now supports Serverless compute for interactive notebooks (Python, SQL, Scala).

**Key Benefits:**
* No cluster creation or waiting — notebooks start in seconds.
* Auto-scaling based on workload intensity.
* Pay only for compute consumed during cell execution.

**When to use Serverless Notebooks:**
* Data exploration and ad hoc analysis.
* Quick prototyping before committing to a Job Cluster.
* Lightweight data transformation tasks.

### Serverless for Jobs (Workflows)

Databricks Workflows can run on Serverless Job compute, eliminating infrastructure configuration for scheduled pipelines.

**Classic Job Cluster:**
```json
{
  "job_clusters": [{
    "job_cluster_key": "etl-cluster",
    "new_cluster": {
      "spark_version": "14.3.x-scala2.12",
      "node_type_id": "i3.xlarge",
      "num_workers": 4,
      "autoscale": { "min_workers": 2, "max_workers": 8 }
    }
  }]
}
```

**Serverless Job (No cluster config!):**
```json
{
  "tasks": [{
    "task_key": "etl-task",
    "notebook_task": {
      "notebook_path": "/Production/ETL/daily_orders"
    },
    "environment_key": "default"
  }],
  "environments": [{
    "environment_key": "default",
    "spec": {
      "client": "1",
      "dependencies": ["pandas==2.2.0"]
    }
  }]
}
```

**Comparison:**

| Feature | Classic Job Cluster | Serverless Job |
|---|---|---|
| Startup time | 3–7 minutes | ~30 seconds |
| Cluster config | You define node types, sizes | Automatic |
| Scaling | Manual autoscale config | Automatic |
| Runtime version | You choose | Always latest |
| Cost | DBU + cloud infra | DBU only |
| Best for | Specific hardware needs | Most workloads |

### Serverless for DLT (Delta Live Tables)

Delta Live Tables pipelines can also run on Serverless compute:

```python
# DLT pipeline running on Serverless — no cluster config needed
import dlt

@dlt.table(comment="Bronze orders from Auto Loader")
def orders_bronze():
    return (
        spark.readStream
            .format("cloudFiles")
            .option("cloudFiles.format", "json")
            .load("s3://company-edw-raw/orders/")
    )

@dlt.table(comment="Silver orders — cleansed")
@dlt.expect_or_drop("valid_amount", "amount > 0")
def orders_silver():
    return dlt.read_stream("orders_bronze").select(
        "order_id", "customer_id", "amount", "region",
        "order_date", "status"
    )
```

**Serverless DLT Benefits:**
* Pipeline starts in seconds instead of minutes.
* No cluster sizing decisions — Databricks optimizes automatically.
* Automatic runtime upgrades and Photon acceleration.

***

## 4.6 Cost Management & Performance Tuning

### Understanding DBU Consumption

A **Databricks Unit (DBU)** is the unit of compute billing. Different workload types consume DBUs at different rates.

| Workload Type | DBU Rate | Example |
|---|---|---|
| Jobs Compute (Classic) | 1.0x base rate | ETL pipelines |
| Jobs Compute (Serverless) | ~1.5x base rate | Serverless ETL |
| All-Purpose Compute | 2.0x base rate | Interactive notebooks |
| SQL Warehouse (Classic) | Varies by tier | BI queries |
| SQL Warehouse (Serverless) | ~1.4x SQL rate | Serverless BI |
| DLT (Core) | 1.0x base rate | Basic DLT pipelines |
| DLT (Pro) | 2.5x base rate | DLT with expectations |
| DLT (Advanced) | 3.6x base rate | DLT with CDC |

### Cost Optimization Strategies

**1. Auto-Stop SQL Warehouses:**
```
Set auto-stop timeout to 10 minutes (minimum effective).
Prevents warehouses from running 24×7 when no one is querying.

Savings: Up to 70% for warehouses with intermittent usage.
```

**2. Use Serverless for Spiky Workloads:**
```
Classic:    Running 8 hours/day even with 2 hours of actual queries.
Serverless: Pay only for the 2 hours of actual query execution.

Savings: Up to 75% for intermittent workloads.
```

**3. Right-Size Warehouses:**
```sql
-- Check query history for average duration:
SELECT
  warehouse_id,
  AVG(duration)     AS avg_query_time_ms,
  MAX(duration)     AS max_query_time_ms,
  COUNT(*)          AS total_queries,
  AVG(rows_produced) AS avg_rows
FROM system.query.history
WHERE start_time >= current_date() - INTERVAL 7 DAYS
GROUP BY warehouse_id;

-- If avg_query_time < 2 seconds, consider downsizing.
-- If queue_time > 0 frequently, consider adding clusters or upsizing.
```

**4. Cache Frequently Queried Tables:**
```sql
-- Disk caching (automatic on SQL Warehouses):
-- SQL Warehouses automatically cache frequently accessed data on local SSDs.
-- No manual configuration needed.

-- Result caching (automatic):
-- If the same query runs within 24 hours and data hasn't changed,
-- DBSQL serves cached results — zero compute cost.
```

**5. Monitor with System Tables:**
```sql
-- Top 10 most expensive queries (by DBU consumption)
SELECT
  query_id,
  user_name,
  query_text,
  duration / 1000         AS duration_seconds,
  total_task_duration_ms,
  rows_produced,
  bytes_scanned_from_storage
FROM system.query.history
WHERE start_time >= current_date() - INTERVAL 7 DAYS
ORDER BY total_task_duration_ms DESC
LIMIT 10;
```

***

## Phase 4 Summary

| Topic | Key Points |
|---|---|
| DBSQL | Serverless vs Classic, warehouse sizing, query optimization |
| BI Integration | DirectQuery vs Import, Power BI / Tableau patterns, Partner Connect |
| Data Sharing | Delta Sharing protocol, open vs D2D sharing, clean rooms |
| Dashboards & Alerts | Native dashboards, SQL alerts, notifications |
| Serverless Compute | Notebooks, Jobs, DLT — all on Serverless |
| Cost Management | DBU rates, auto-stop, caching, right-sizing |

**Self-Assessment Checklist:**
* [ ] Can you explain the trade-offs between Serverless and Classic SQL Warehouses?
* [ ] Can you right-size a SQL Warehouse based on concurrency and query complexity?
* [ ] Can you optimize a slow query using Query Profile and ZORDER?
* [ ] Can you explain when to use Materialized Views vs Standard Views?
* [ ] Can you design a Power BI connection using DirectQuery with Unity Catalog RLS?
* [ ] Can you set up Delta Sharing for both Databricks and non-Databricks recipients?
* [ ] Can you implement a partitioned share to limit data exposure to partners?
* [ ] Can you build a SQL Alert to detect missing pipeline data?
* [ ] Can you calculate and optimize DBU cost for a SQL analytics workload?
* [ ] Can you explain the cold-start difference between Classic and Serverless?

***

## Resources

* Databricks Docs: `docs.databricks.com/sql`
* Databricks Docs: `docs.databricks.com/delta-sharing`
* Databricks Academy: "SQL Analytics on Databricks"
* Databricks: "Serverless Compute Technical Overview"
* Databricks: "Delta Sharing: An Open Protocol for Secure Data Sharing"
* Book: "The Lakehouse: A Unified Platform for Data Engineering and AI" — Chapter on SQL Analytics
