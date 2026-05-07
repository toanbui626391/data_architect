# Snowflake Operations Best Practices

## 1. Executive Summary
This document serves as the Standard Operating Procedure (SOP) for data platform engineers, DBAs, and FinOps teams managing the Snowflake Data Cloud. Following the architectural blueprints for Ingestion, Transformation, and Serving, this guide establishes the operational guardrails required to ensure the environment remains **secure, highly performant, and cost-effective**.

### 1.1 The Zero-Management Paradigm
A critical operational mindset shift for teams coming from traditional databases (PostgreSQL, SQL Server, Oracle) is that **Snowflake requires no routine DBA maintenance commands**. The following tasks are fully automated by the Snowflake platform and should never be run manually:

| Traditional Command | Snowflake Equivalent | Status |
|---|---|---|
| `VACUUM` / storage reclaim | Micro-partition cleanup after Time Travel / Fail-safe | ✅ Fully Automatic |
| `ANALYZE` / gather statistics | Column statistics updated on every data load | ✅ Fully Automatic |
| `REINDEX` / rebuild indexes | No indexes exist — micro-partitions used instead | ✅ Not Applicable |
| Scale warehouse for daily peak | Multi-cluster auto-scale triggered by queue depth | ✅ Fully Automatic |
| `CLUSTER BY` maintenance | Automatic Clustering service runs in background (if enabled) | ✅ Fully Automatic |

Operator effort shifts entirely to **monitoring, governance, and continuous improvement** — not reactive DBA firefighting.

---

## 2. FinOps & Cost Management

Snowflake's consumption-based pricing requires active cost governance to prevent runaway spend.

### 2.1 Virtual Warehouse Sizing Strategy
*   **Scale Up for Complexity:** Increase warehouse size (e.g., Small to Medium) when dealing with complex queries, large joins, or operations spilling to disk.
*   **Scale Out for Concurrency:** Use **Multi-Cluster Warehouses** (e.g., Small 1-5 clusters) when dealing with many concurrent users running simple queries (like BI dashboards). Do not increase the warehouse size to solve concurrency issues.
*   **Auto-Suspend:** Set aggressive auto-suspend times.
    *   BI/API Warehouses: `60 seconds` (to quickly pause between dashboard clicks).
    *   Data Science/Ad-hoc Warehouses: `5 minutes` (to avoid pausing during interactive thought processes).
*   **Auto-Resume:** Always set `AUTO_RESUME = TRUE` so compute is available instantly when needed.
*   **Statement Timeout:** Set `STATEMENT_TIMEOUT_IN_SECONDS` on every warehouse to automatically kill runaway queries before they drain credits.
    ```sql
    ALTER WAREHOUSE ADHOC_WH SET STATEMENT_TIMEOUT_IN_SECONDS = 3600;  -- kill after 1 hour
    ALTER WAREHOUSE API_WH    SET STATEMENT_TIMEOUT_IN_SECONDS = 30;   -- kill after 30 seconds
    ```

### 2.2 Resource Monitors
Resource Monitors are mandatory for all compute resources.
*   **Account-Level Monitor:** Set a hard limit on the entire account to prevent catastrophic billing errors.
*   **Warehouse-Level Monitors:** Attach a monitor to every warehouse with monthly credit quotas.
    *   **Warning Limit:** 80% (Sends alert via `NOTIFY_USERS` to the platform team).
    *   **Suspend Limit:** 100% (Suspends warehouse, preventing further queries until quota resets).
*   **Reset Frequency:** Configure monitors to reset `MONTHLY` (default) to align with billing cycles.

### 2.3 Snowflake Budgets (Recommended)
In addition to Resource Monitors, use the newer native **Budgets** feature for proactive cost management:
*   Create budgets with `CREATE BUDGET` to set spend limits on specific account objects (warehouses, compute pools).
*   Budgets provide **spend forecasting** and **visual cost trends** natively in Snowsight (Admin > Budgets), making them more accessible than writing custom `ACCOUNT_USAGE` SQL queries.

### 2.4 Object Tagging & Chargeback
*   Use native **Object Tagging** (`CREATE TAG`) to assign metadata to Warehouses, Databases, and Users.
*   Required Tags: `COST_CENTER`, `ENVIRONMENT` (e.g., `Prod`, `Dev`), `PROJECT`.
*   Leverage the `ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY` view joined with `TAG_REFERENCES` to build automated monthly chargeback reports for each business unit.

---

## 3. Performance Optimization

### 3.1 Analyzing Query Performance
*   Use the **Query Profiler** in Snowsight to analyze long-running queries.
*   **Look for "Spilling to Disk":** If remote disk spillage is high, the warehouse is out of memory. This is the primary indicator that you need to scale up the warehouse to a larger T-Shirt size.
*   **Query Tags:** Set `QUERY_TAG` on connections or sessions from applications and pipelines to track which system is generating expensive queries.
    ```sql
    ALTER SESSION SET QUERY_TAG = 'app:data_pipeline,service:ingestion';
    ```

### 3.2 Leverage Caching to Eliminate Compute Costs
Understanding Snowflake's caching layers is critical for cost optimization:
*   **Result Cache (24 hours — Free):** If the exact same query is submitted again within 24 hours and the underlying data has not changed, Snowflake returns the result instantly with zero warehouse credit consumption. BI dashboards with static daily reports benefit enormously from this.
*   **Local Disk Cache (SSD — Automatic):** Frequently accessed micro-partitions are cached on the SSD of the warehouse nodes. Keeping warehouses from suspending too aggressively (especially for DS workloads) preserves this cache across queries.

### 3.3 Micro-partitioning & Clustering
*   Snowflake handles micro-partitioning automatically based on the order data is ingested.
*   **Avoid Over-Clustering:** Do not immediately define a `CLUSTER BY` key on tables. Automatic clustering consumes background compute credits monitored via `AUTOMATIC_CLUSTERING_HISTORY`.
*   **When to Cluster:** Only define clustering keys on very large tables (TB scale) where queries frequently filter on specific columns (e.g., `date` or `tenant_id`) and the natural ingestion order does not align with the query pattern.
*   **Validate Before Clustering:** Use `SYSTEM$CLUSTERING_INFORMATION('<table>', '(<column>)')` to measure partition overlap before deciding to enable automatic clustering.

### 3.4 Transient Tables for Cost Optimization
For high-volume staging and intermediate tables (Bronze/Silver layers), use **Transient Tables** to significantly reduce storage costs:
*   Transient tables have **no Fail-safe period** (saving 7 days of storage costs per table).
*   They still support Time Travel up to 1 day.
*   Ideal for Bronze ingestion tables and intermediate Silver transformation tables that can be fully regenerated from source data if lost.
    ```sql
    CREATE TRANSIENT TABLE bronze.raw_events (...) DATA_RETENTION_TIME_IN_DAYS = 1;
    ```

### 3.5 Materialized Views vs. Dynamic Tables
*   Use **Dynamic Tables** for batch data transformation pipelines.
*   Use **Materialized Views** only for accelerating specific point queries or aggregations that require synchronous updates and are queried very frequently.

---

## 4. Security & Governance

### 4.1 Role-Based Access Control (RBAC)
Implement a strict hierarchical RBAC model. **Never grant privileges directly to users.**
*   **System Roles:** Reserve `ACCOUNTADMIN` for top-level setup and billing. Use `SYSADMIN` for creating objects and `SECURITYADMIN` for managing users/roles.
*   **Custom Roles:** Create roles based on function (e.g., `DATA_ENGINEER`, `ANALYST`) and map them to access roles (e.g., `RAW_READ`, `GOLD_READ`).
*   **Managed Access Schemas:** Create schemas with `WITH MANAGED ACCESS` to centralize privilege management. In a managed schema, only the schema owner or `SECURITYADMIN` can grant object-level privileges, preventing uncontrolled privilege sprawl by individual table owners.
    ```sql
    CREATE SCHEMA gold WITH MANAGED ACCESS;
    ```

### 4.2 Network Policies
*   Implement **Network Policies** to restrict access to the Snowflake account.
*   Whitelist only corporate VPN IP ranges, specific VPC endpoints (e.g., AWS PrivateLink), and allowed third-party SaaS IPs.
*   Apply policies at both the **account level** and per-user level for tighter control (e.g., a service account restricted to a single VPC endpoint IP).

### 4.3 Data Masking & PII Protection
*   Use **Dynamic Data Masking** policies to protect Personally Identifiable Information (PII).
*   Apply **Data Classification** tags (`PRIVACY_CATEGORY`) at the Bronze ingestion layer. Build policies that automatically mask columns tagged as PII unless the querying user has an authorized role (e.g., `HR_ANALYST`).

### 4.4 Authentication
*   Enforce **Single Sign-On (SSO)** via an Identity Provider (e.g., Okta, Azure AD) for all human users.
*   Enforce **Multi-Factor Authentication (MFA)** for all local users, especially the `ACCOUNTADMIN` role.
*   **Key Pair Authentication for Service Accounts:** All programmatic access (pipelines, Snowpark, Snowpipe, BI connectors) must use **Key Pair Authentication** instead of username/password. Never embed passwords for service accounts in application code or config files.
    ```sql
    ALTER USER svc_pipeline SET RSA_PUBLIC_KEY = '<your_public_key>';
    ```

---

## 5. Monitoring & Alerting

### 5.1 Key ACCOUNT_USAGE Views Reference
The `SNOWFLAKE.ACCOUNT_USAGE` schema is the source of truth for historical auditing (up to 365 days). The `INFORMATION_SCHEMA` provides real-time state (up to 7-14 days).

Operators should regularly query the following key views:

| View | Purpose | Key Use Case |
|---|---|---|
| `QUERY_HISTORY` | All query executions | Identify long-running, high-credit, or failing queries |
| `LOGIN_HISTORY` | All login attempts | Detect failed logins, audit user access |
| `WAREHOUSE_METERING_HISTORY` | Credit consumption per warehouse | Cost tracking and anomaly detection |
| `DYNAMIC_TABLE_REFRESH_HISTORY` | Pipeline refresh runs | Detect lag violations or refresh failures |
| `TASK_HISTORY` | Serverless Task executions | Detect task failures and retry storms |
| `PIPE_USAGE_HISTORY` | Snowpipe credit consumption | Monitor ingestion costs |
| `AUTOMATIC_CLUSTERING_HISTORY` | Background clustering compute | Monitor clustering cost |
| `COPY_HISTORY` | File load history | Audit which files were loaded and when |

### 5.2 Native Snowflake Alerts
*   Use **Snowflake Alerts** combined with **Notification Integrations** to push critical events to Slack or PagerDuty.
*   **Alert Examples:**
    *   Long-running queries (e.g., queries running > 1 hour).
    *   Failed Serverless Tasks or Dynamic Tables failing to meet `TARGET_LAG`.
    *   Failed login attempts exceeding a threshold.

---

## 6. Data Protection & Disaster Recovery

### 6.1 Time Travel
Time Travel allows querying historical data, recovering dropped objects, and cloning past states without backups.
*   **Configuration:** Set `DATA_RETENTION_TIME_IN_DAYS` appropriately.
    *   Bronze Tables: Use **Transient Tables** (`DATA_RETENTION_TIME_IN_DAYS = 1`, no Fail-safe) to minimize storage costs.
    *   Silver Tables: `1 day` (can be regenerated from Bronze).
    *   Gold/Critical Tables: `7 to 90 days` (requires Snowflake Enterprise Edition).

### 6.2 Fail-safe
*   Fail-safe provides a non-configurable 7-day historical data protection window *after* the Time Travel period ends.
*   This data can only be recovered by Snowflake Support and is strictly for disaster recovery. Note that Fail-safe storage incurs costs.
*   **Important:** Transient and Temporary tables have **no Fail-safe period**, which is why they are appropriate for staging tables that can be fully reloaded.

### 6.3 Replication for High Availability
*   For mission-critical applications requiring high availability across cloud regions or providers, configure **Database Replication**.
*   Group related databases into **Failover Groups** (not individual Database Replication) to ensure referential integrity is maintained during a region failover event, as Failover Groups replicate multiple databases atomically.

---

## 7. DevOps & Environment Strategy

### 7.1 Zero-Copy Cloning
*   Do not duplicate physical data across environments. Use Snowflake's **Zero-Copy Cloning** feature to instantly create Sandbox or QA environments from Production data.
*   Clones incur zero additional storage costs until the cloned data is modified.
*   **Important:** After cloning, immediately **revoke all production roles** from the cloned environment and apply QA-specific access controls to prevent accidental writes back to the shared data.

### 7.2 CI/CD Deployment
*   Treat infrastructure and schema as code. Do not manually create tables or views in Production via the UI.
*   Use tools like **Schemachange**, **Flyway**, or **Terraform** integrated into a Git CI/CD pipeline (e.g., GitHub Actions, GitLab CI) to deploy changes deterministically across Dev -> QA -> Prod environments.
*   **Snowflake CLI:** The official **Snowflake CLI** (`snow` command) is the recommended native tool for scripting deployments, executing SQL scripts in pipelines, and managing Snowflake objects programmatically without third-party dependencies. Install via `pip install snowflake-cli-labs`.
