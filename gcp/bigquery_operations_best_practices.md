# BigQuery Operations Best Practices

## 1. Executive Summary
This document serves as the Standard Operating Procedure (SOP) for data platform engineers, DBAs, and FinOps teams managing the Google Cloud Platform (GCP) BigQuery Data Warehouse. Following the architectural blueprints for Ingestion, Transformation, and Serving, this guide establishes the operational guardrails required to ensure the environment remains **secure, highly performant, and cost-effective**.

### 1.1 The Zero-Management Paradigm
A critical operational mindset shift for teams coming from traditional databases (PostgreSQL, SQL Server, Oracle) is that **BigQuery is a fully managed, serverless platform that requires almost no routine DBA maintenance commands**. The following tasks are fully automated by GCP and should never be run manually:

| Traditional Command | BigQuery Equivalent | Status |
|---|---|---|
| `VACUUM` / storage reclaim | Storage is managed automatically in the background | ✅ Fully Automatic |
| `ANALYZE` / gather statistics | Statistics are updated automatically on load/query | ✅ Fully Automatic |
| `REINDEX` / rebuild indexes | No indexes exist — relies on columnar storage & partitioning | ✅ Not Applicable |
| Server Provisioning / Scaling | Serverless scaling based on query complexity | ✅ Fully Automatic |
| Storage allocation | Scales infinitely and transparently | ✅ Fully Automatic |

Operator effort shifts entirely to **monitoring, governance, query optimization, and continuous improvement** — not reactive DBA firefighting.

---

## 2. FinOps & Cost Management

BigQuery's serverless nature means costs scale with usage. Active cost governance is mandatory to prevent runaway spend.

### 2.1 Pricing Models Strategy
Understand and leverage BigQuery's two pricing models appropriately:
*   **On-Demand Pricing (per TB scanned):** Best for unpredictable workloads or new projects. Highly flexible but costs can spike if inefficient queries (like `SELECT *` without partition filters) are run frequently.
*   **Capacity-Based Pricing (BigQuery Editions):** Best for predictable, steady-state workloads. You purchase "slots" (virtual CPUs). Use **Autoscaling Slots** to define a baseline and a maximum ceiling, ensuring predictable costs while handling peak loads.

### 2.2 Custom Quotas & Controls
To prevent accidental massive bills from runaway queries:
*   **Project-Level Quotas:** Set a maximum bytes billed per day per project in IAM & Admin -> Quotas.
*   **User-Level Quotas:** Set a maximum bytes billed per day per user. If a user exceeds this, their queries will fail until the quota resets, preventing a single analyst from accidentally scanning petabytes of data.
*   **Maximum Bytes Billed:** Encourage users to use the `--maximum_bytes_billed` flag or the equivalent setting in UI/drivers to fail queries upfront if they are too expensive.

### 2.3 Storage Optimization
*   **Long-Term Storage Pricing:** BigQuery automatically cuts storage costs in half for data in a partition that hasn't been modified for 90 days. Avoid unnecessary updates to old data to retain this discount.
*   **Table/Partition Expiration:** Configure default table expirations at the dataset level for transient data (e.g., Bronze staging). Configure partition expiration for time-series data (e.g., keep only the last 3 years of logs).

---

## 3. Performance Optimization

### 3.1 Partitioning & Clustering (The Golden Rule)
Because BigQuery charges by bytes scanned (on-demand), strictly minimizing the scan size is the highest priority.
*   **Partitioning:** Always partition large tables (typically by a `DATE` or `TIMESTAMP` column). This divides the table into logical segments.
    *   *Mandatory Pattern:* Check "Require partition filter" when creating tables to force users to include a `WHERE` clause on the partition column, preventing accidental full table scans.
*   **Clustering:** After partitioning, cluster the table by up to 4 columns that are frequently used in `WHERE`, `GROUP BY`, or `JOIN` clauses (e.g., `tenant_id`, `status`). BigQuery automatically sorts data based on these columns within each partition.
*   **Avoid `SELECT *`:** Only select the specific columns needed. Because BigQuery is a columnar database, selecting fewer columns directly reduces bytes scanned and cost.

### 3.2 Caching and BI Engine
*   **Query Caching:** BigQuery caches query results for 24 hours (free of charge) as long as the query is deterministic and the underlying data hasn't changed.
*   **BigQuery BI Engine:** For dashboards (Tableau, Looker, PowerBI) requiring sub-second response times, allocate a **BI Engine Reservation**. BI Engine is an in-memory analysis service that accelerates queries transparently without changing SQL or connections.

### 3.3 Materialized Views
*   Use Materialized Views for complex aggregations or joins that are queried frequently. BigQuery automatically routes queries to use the materialized view if it will improve performance and automatically refreshes it incrementally when base tables change.

---

## 4. Security & Governance

### 4.1 IAM (Identity and Access Management)
Implement the principle of least privilege using predefined IAM roles.
*   **Project Level:** Grant `roles/bigquery.jobUser` to allow users to run queries (incurs compute costs).
*   **Dataset Level:** Grant `roles/bigquery.dataViewer` on specific datasets (e.g., Gold layer) to allow reading data. Never grant direct access to Bronze/Silver datasets to end-users.

### 4.2 Authorized Views
*   Instead of granting access to base tables, create **Authorized Views** in a separate dataset. Grant access to the view dataset, and authorize the view to read from the base dataset. This abstracts the physical schema and enforces row/column filtering without exposing the raw data.

### 4.3 Dataplex & Policy Tags (Data Masking)
*   Use **GCP Dataplex / Data Catalog** to define Policy Tags (e.g., `High Security - PII`).
*   Apply these tags to specific columns containing sensitive data (e.g., emails, SSNs).
*   BigQuery automatically enforces **Column-Level Security**: users without the `Fine-Grained Reader` role on that tag will be denied access to the column. Alternatively, configure dynamic data masking rules.

### 4.4 Row-Level Security
*   Use `CREATE ROW ACCESS POLICY` to filter rows based on the user's identity. For example, `region = SESSION_USER()` ensures a manager only sees data for their region.

---

## 5. Monitoring & Alerting

### 5.1 Cloud Logging & Audit Logs
*   All BigQuery interactions are logged in **Cloud Audit Logs** (`cloudaudit.googleapis.com`).
*   Use these logs to audit who queried what data, when, and how much it cost.

### 5.2 INFORMATION_SCHEMA
*   Leverage `INFORMATION_SCHEMA.JOBS` and `INFORMATION_SCHEMA.JOBS_BY_PROJECT` to build internal dashboards tracking slot consumption, query duration, and bytes billed per user or service account.

### 5.3 Cloud Monitoring Alerts
*   Set up alerts in **Cloud Monitoring** based on log metrics.
*   *Alert Examples:*
    *   Query execution time exceeds 30 minutes.
    *   A single query bills over 1 TB of data.
    *   An unexpected spike in slot utilization.

---

## 6. Data Protection & Disaster Recovery

### 6.1 Time Travel
*   BigQuery provides a built-in **Time Travel** window (default 7 days) that allows you to query the state of a table at any point in time or restore accidentally dropped/modified tables.
*   *Example:* `SELECT * FROM my_table FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)`

### 6.2 Table Snapshots
*   For longer-term backups or point-in-time references (e.g., end-of-month financial closing), use **Table Snapshots**. Snapshots only bill for the delta (changes) against the base table, making them highly cost-effective compared to full table copies.

### 6.3 Cross-Region Replication
*   By default, BigQuery datasets are multi-regional (e.g., `US` or `EU`) or single-region. For critical datasets requiring disaster recovery across entirely different geographies, configure **Cross-Region Dataset Replication**.

---

## 7. DevOps & Environment Strategy

### 7.1 Infrastructure as Code (IaC)
*   Do not manually create datasets, configure IAM permissions, or set policy tags in the GCP Console.
*   Use **Terraform** (`google_bigquery_dataset`, `google_bigquery_table`) to manage all BigQuery infrastructure deterministically across `Dev`, `QA`, and `Prod` projects.

### 7.2 Data Pipelines (Dataform)
*   Manage SQL transformations using **GCP Dataform** (natively integrated into BigQuery) or **dbt**.
*   These tools treat SQL as code, support version control (Git), enable testing of data quality assertions before deploying, and automate the creation of views and partitioned tables.
