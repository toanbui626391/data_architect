# Phase 3: Governance & Security
*Databricks Data & Solution Architect Track*

***

## 3.1 Unity Catalog

### What is Unity Catalog?

Unity Catalog (UC) is Databricks' unified governance layer for all data and AI assets across the Lakehouse. It provides a single control point for access control, data discovery, lineage tracking, and auditing — across multiple workspaces, clouds, and data types.

**Before Unity Catalog:**
* Each Databricks workspace had its own isolated Hive Metastore.
* No cross-workspace data sharing.
* No column-level security.
* No lineage tracking.
* Access control was cluster-level table ACLs — difficult to manage.

**With Unity Catalog:**
* One centralized governance layer for all workspaces.
* Fine-grained access control down to individual rows and columns.
* Automated data lineage.
* Full audit logging.
* Support for non-tabular assets: files, models, features.

### Three-Level Namespace

Unity Catalog introduces a 3-level object hierarchy:

```
  Metastore
    └── Catalog
          └── Schema (Database)
                ├── Table
                ├── View
                ├── Volume (files)
                └── Function
```

**Metastore:**
* The top-level container for all UC metadata.
* One metastore per cloud region.
* Linked to one or more Databricks workspaces.

**Catalog:**
* The top-level namespace for organizing data domains.
* Recommended pattern: one catalog per environment or domain.
* Examples: `prod`, `dev`, `raw`, `finance`, `marketing`.

**Schema:**
* Equivalent to a database.
* Groups related tables, views, and volumes within a catalog.

**Full Object Reference:**
```sql
-- Format:  catalog.schema.table
SELECT * FROM prod.silver.orders;
SELECT * FROM finance.gold.revenue_daily;
```

### Metastore Design for Enterprise

A common enterprise design pattern:

```
  Metastore (us-east-1)
    ├── Catalog: raw          ← Bronze landing zone
    ├── Catalog: dev          ← Development & testing
    ├── Catalog: prod         ← Production data
    │     ├── Schema: bronze
    │     ├── Schema: silver
    │     └── Schema: gold
    ├── Catalog: sandbox      ← Analyst self-service
    └── Catalog: shared       ← Cross-team shared assets
```

**Workspace Assignment:**
* Multiple workspaces can be attached to the same metastore.
* A single workspace can only be attached to one metastore.
* Workspace catalog access is controlled via `GRANT` on the Catalog.

```
  Metastore
    ├── Workspace: prod-ws   → Access: prod catalog
    ├── Workspace: dev-ws    → Access: dev, sandbox catalogs
    └── Workspace: analyst-ws → Access: prod (read), sandbox
```

### Managed vs External Tables

This is one of the most critical design choices in Unity Catalog.

**Managed Table:**
* Unity Catalog owns and controls the data files.
* Files stored in the UC-managed root storage location.
* When you `DROP TABLE`, the underlying data files are also deleted.
* Simpler setup, recommended for most use cases.

```sql
-- Managed table: UC owns the files
CREATE TABLE prod.silver.orders (
  order_id STRING,
  amount DECIMAL(18, 2),
  status STRING
);
```

**External Table:**
* You own and control the data files in your own storage (S3/ADLS/GCS).
* UC only stores the metadata (schema, location pointer).
* When you `DROP TABLE`, the data files are NOT deleted.
* Required when data must be accessible by non-Databricks tools.

```sql
-- External table: You own the files
CREATE TABLE prod.bronze.orders_raw
LOCATION 's3://my-bucket/raw/orders/'
AS SELECT * FROM parquet.`s3://my-bucket/raw/orders/`;
```

**Decision Framework:**

| Factor | Managed | External |
|---|---|---|
| Data ownership | Databricks/UC | You |
| Cross-tool access | Difficult | Easy |
| Drop behavior | Deletes data | Keeps data |
| Setup complexity | Low | Medium |
| Recommended for | Silver, Gold | Bronze, raw |

### External Locations & Storage Credentials

To allow UC to read/write from your own cloud storage, you must configure:

**1. Storage Credential:**
* An IAM role (AWS), Service Principal (Azure), or Service Account (GCP) that has permission to access the storage bucket.
* Created once and referenced by External Locations.

**2. External Location:**
* Maps a UC-managed path alias to an actual cloud storage path.
* Controls which Storage Credential is used for that path.

```sql
-- Create a storage credential (AWS example):
CREATE STORAGE CREDENTIAL my_s3_cred
WITH IAM_ROLE 'arn:aws:iam::123456789:role/databricks-uc-role';

-- Create an external location:
CREATE EXTERNAL LOCATION my_raw_data
URL 's3://my-bucket/raw/'
WITH (STORAGE CREDENTIAL my_s3_cred);

-- Grant access to a group:
GRANT READ FILES ON EXTERNAL LOCATION my_raw_data
TO `data-engineers`;
```

### Volumes

Volumes are UC-managed assets for **non-tabular data** (files, images, PDFs, models, etc.).

```sql
-- Create a managed volume:
CREATE VOLUME prod.bronze.raw_files;

-- Access in Python:
df = spark.read.format("json")
  .load("/Volumes/prod/bronze/raw_files/orders/")
```

**Volume Types:**
* **Managed Volume:** UC manages the files. Files deleted on `DROP VOLUME`.
* **External Volume:** Points to your cloud storage path.

### System Tables

Unity Catalog provides built-in system tables for auditing and observability.

```sql
-- All access events (login, table reads, writes):
SELECT * FROM system.access.audit
WHERE event_date = current_date()
ORDER BY event_time DESC;

-- Table lineage (which tables read/write to which):
SELECT * FROM system.access.table_lineage
WHERE target_table_full_name = 'prod.silver.orders';

-- Column lineage:
SELECT * FROM system.access.column_lineage
WHERE target_table_full_name = 'prod.gold.revenue_daily';

-- Storage usage per table:
SELECT * FROM system.storage.predictive_optimization_operations_history;
```

***

## 3.2 Data Access Control

### Unity Catalog Permission Model

Permissions in Unity Catalog are:
* **Hierarchical:** Permissions granted on a Catalog flow down to all Schemas and Tables within it.
* **Additive:** A user's effective permissions are the union of all privileges granted to them directly and via groups.
* **Deny-by-default:** No access is granted unless explicitly `GRANT`ed.

### Privilege Types

**On Catalogs:**
| Privilege | Description |
|---|---|
| `USE CATALOG` | Allows seeing the catalog |
| `CREATE SCHEMA` | Create new schemas within |
| `ALL PRIVILEGES` | Full control |

**On Schemas:**
| Privilege | Description |
|---|---|
| `USE SCHEMA` | Allows seeing the schema |
| `CREATE TABLE` | Create tables |
| `CREATE VIEW` | Create views |

**On Tables/Views:**
| Privilege | Description |
|---|---|
| `SELECT` | Query the table or view |
| `INSERT` | Append data |
| `MODIFY` | Update, delete, merge |
| `ALL PRIVILEGES` | Full control |

### GRANT and REVOKE Syntax

```sql
-- Grant SELECT on a table to a group:
GRANT SELECT ON TABLE prod.silver.orders
TO `data-analysts`;

-- Grant full access on a schema to engineers:
GRANT ALL PRIVILEGES ON SCHEMA prod.silver
TO `data-engineers`;

-- Grant USE on catalog and schema (required for any table access):
GRANT USE CATALOG ON CATALOG prod TO `data-analysts`;
GRANT USE SCHEMA ON SCHEMA prod.silver TO `data-analysts`;

-- Revoke access:
REVOKE SELECT ON TABLE prod.silver.orders
FROM `data-analysts`;

-- Check current grants:
SHOW GRANTS ON TABLE prod.silver.orders;
```

**Important:** `SELECT` on a table alone is not enough. The user or group must also have `USE CATALOG` and `USE SCHEMA` on the parent objects.

### Principals: Users, Groups & Service Principals

| Principal | Description |
|---|---|
| User | An individual human identity (email address) |
| Group | A collection of users, managed in the identity provider |
| Service Principal | A non-human machine identity for automation |

**Best Practice:** Always grant permissions to **Groups**, not individual users. This makes permission management scalable — adding a user to a group automatically grants all relevant permissions.

### Row-Level Security (RLS)

Row-level security restricts which rows a user can see within a table, based on their identity or group membership.

**Implementation via Dynamic Views:**

```sql
-- Create a view that filters rows based on the current user's region:
CREATE VIEW prod.silver.orders_secure AS
SELECT *
FROM prod.silver.orders
WHERE
  -- Admins see all rows:
  is_account_group_member('data-admins')
  OR
  -- Others only see rows in their region:
  region = (
    SELECT region
    FROM prod.silver.user_regions
    WHERE email = current_user()
  );

-- Grant SELECT on the view, NOT the underlying table:
GRANT SELECT ON VIEW prod.silver.orders_secure
TO `data-analysts`;
REVOKE SELECT ON TABLE prod.silver.orders
FROM `data-analysts`;
```

**Key Functions for Dynamic Views:**

| Function | Returns |
|---|---|
| `current_user()` | Email of the logged-in user |
| `is_account_group_member('group')` | True if user is in the group |

### Column-Level Security (CLS)

Column-level security restricts which columns a user can see, typically to hide PII or sensitive financial data.

**Option 1: Column Masking (Databricks 13.0+)**

```sql
-- Create a masking policy:
CREATE FUNCTION prod.security.mask_email(email STRING)
RETURN
  CASE
    WHEN is_account_group_member('pii-allowed')
      THEN email
    ELSE CONCAT(LEFT(email, 2), '****@****.com')
  END;

-- Apply the mask to a column:
ALTER TABLE prod.silver.customers
ALTER COLUMN email
SET MASK prod.security.mask_email;
```

**Option 2: Column Exclusion via View:**
```sql
CREATE VIEW prod.silver.customers_masked AS
SELECT
  customer_id,
  -- Omit: email, phone, ssn
  country,
  age_band,
  segment
FROM prod.silver.customers;
```

**Column masking is preferred** as it applies automatically without requiring users to use a separate view.

### Attribute-Based Access Control (ABAC)

ABAC extends RLS/CLS by using table or column **tags** as the basis for access decisions.

```sql
-- Tag a table with a sensitivity level:
ALTER TABLE prod.silver.patients
SET TAGS ('sensitivity' = 'high', 'pii' = 'true');

-- In a dynamic view, enforce access based on tags:
CREATE VIEW prod.silver.patients_secure AS
SELECT *
FROM prod.silver.patients
WHERE
  is_account_group_member('hipaa-approved')
  OR
  (SELECT tag_value FROM system.information_schema.table_tags
   WHERE table_name = 'patients' AND tag_name = 'sensitivity') = 'low';
```

**Architect Tip:** Use Tags + ABAC for large organizations where tables and their sensitivity levels change frequently. It decouples the access policy from individual table definitions.

***

## 3.3 Security Architecture

### Service Principals

A **Service Principal (SP)** is a non-human identity used by automated processes, CI/CD pipelines, and applications.

**Why Use Service Principals:**
* Human user tokens expire and rotate unexpectedly.
* Auditing is cleaner — SP actions appear separately in audit logs.
* Principle of least privilege — each SP only has the permissions it needs.
* Password/token rotation doesn't affect other users.

**Creating and Using a Service Principal:**
```bash
# Via CLI:
databricks service-principals create \
  --display-name "prod-etl-pipeline"

# Generate a token for the SP:
databricks tokens create \
  --comment "prod-etl-sp-token" \
  --lifetime-seconds 7776000  # 90 days
```

**Grant SP access to Databricks resources:**
```sql
GRANT USE CATALOG ON CATALOG prod TO `prod-etl-sp`;
GRANT SELECT ON SCHEMA prod.silver TO `prod-etl-sp`;
GRANT MODIFY ON TABLE prod.silver.orders TO `prod-etl-sp`;
```

### Secret Management

Never hardcode credentials (API keys, passwords, connection strings) in notebooks or code files. Use Databricks Secrets.

**Secret Scopes:**
* **Databricks-backed:** Secrets stored in Databricks' own encrypted store.
* **Azure Key Vault-backed:** Secrets stored in Azure Key Vault; Databricks reads from there.

```bash
# Create a secret scope:
databricks secrets create-scope --scope my-scope

# Add a secret:
databricks secrets put-secret \
  --scope my-scope \
  --key db-password

# List secrets (names only, never values):
databricks secrets list-secrets --scope my-scope
```

**Using Secrets in Notebooks:**
```python
# Retrieve a secret value (masked in output):
password = dbutils.secrets.get(
  scope="my-scope",
  key="db-password"
)

# Connect to a database using the secret:
jdbc_url = (
  f"jdbc:postgresql://db-host:5432/mydb"
  f"?user=admin&password={password}"
)
```

**Access Control on Secrets:**
```bash
# Grant read access to a group:
databricks secrets put-acl \
  --scope my-scope \
  --principal data-engineers \
  --permission READ
```

### Network Isolation

**VNet / VPC Injection:**
* Deploy all Databricks clusters inside your own cloud virtual network.
* Prevent any cluster traffic from traversing the public internet.
* Required for most enterprise, HIPAA, and PCI-DSS deployments.

**Private Link:**
* Encrypts and privatizes the connection between the Databricks Control Plane and your Data Plane.
* All traffic stays within the cloud provider's backbone network.
* Eliminates exposure to the public internet entirely.

**IP Access Lists:**
* Restrict which source IP addresses can authenticate to the Databricks workspace.
* Useful for allowing access only from corporate VPN or office IPs.

```bash
# Add an IP to the allow-list:
databricks ip-access-lists create \
  --label "Corporate VPN" \
  --list-type ALLOW \
  --ip-addresses "203.0.113.0/24"
```

**Firewall / NSG Rules:**
Restrict outbound traffic from cluster nodes:
* Allow: Cloud storage (S3/ADLS/GCS).
* Allow: Databricks Control Plane endpoints.
* Deny: All other destinations (prevents data exfiltration).

### Cloud IAM Roles

Databricks clusters access cloud resources (S3, ADLS, GCS) using cloud IAM identities.

**AWS — Instance Profiles:**
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::my-data-bucket",
    "arn:aws:s3:::my-data-bucket/*"
  ]
}
```

Attach an Instance Profile to a cluster:
```python
# In cluster config:
"aws_attributes": {
  "instance_profile_arn":
    "arn:aws:iam::123456789:instance-profile/databricks-cluster-role"
}
```

**Azure — Managed Identity:**
* Assign an Azure Managed Identity to the cluster.
* Grant the identity `Storage Blob Data Contributor` on the ADLS container.
* No credentials to manage or rotate.

**Architect Tip:** Always use instance profiles / managed identities for cluster-to-storage access. Never put cloud credentials (access keys, secrets) directly in notebooks or cluster environment variables.

### Compliance Considerations

**GDPR (General Data Protection Regulation):**
* Right to erasure: Implement deletion via `DELETE` + `VACUUM` in Delta Lake.
* Data minimization: Use column masking to limit PII field exposure.
* Audit logging: Enable Unity Catalog system tables.
* Data residency: Deploy workspaces in the correct cloud region.

**HIPAA (Health Insurance Portability):**
* PHI (Protected Health Information) must be encrypted at rest and in transit.
* Databricks encrypts data at rest by default (AES-256).
* Enable Customer-Managed Keys (CMK) for managed encryption control.
* Require VNet injection and Private Link.
* Separate PHI workspaces from non-PHI workspaces.

**PCI-DSS (Payment Card Industry):**
* Cardholder data must be isolated.
* Use separate catalogs with strict access controls.
* Enable IP Access Lists to limit workspace access.
* Tokenize PANs (card numbers) before storing.
* Enable comprehensive audit logging.

**Customer-Managed Keys (CMK):**
```
  Default:                Customer-Managed:
  Databricks manages      You control the encryption
  encryption keys.        key in your KMS (AWS KMS/
                          Azure Key Vault).
```
CMK is required for most regulated workloads.

***

## 3.4 Data Lineage & Observability

### Column-Level Lineage in Unity Catalog

Unity Catalog automatically tracks lineage — no configuration needed. Every time a table is created from another table, UC records the dependency.

**Lineage is captured for:**
* `CREATE TABLE AS SELECT (CTAS)` statements.
* `INSERT INTO` statements.
* `MERGE INTO` statements.
* DLT pipeline table outputs.
* Notebook and job executions.

**Viewing Lineage in the UI:**
1. Open any table in the Databricks Catalog Explorer.
2. Click the **"Lineage"** tab.
3. See upstream sources and downstream consumers graphically.

**Querying Lineage via System Tables:**
```sql
-- Table-level lineage: what tables feed prod.gold.revenue?
SELECT
  source_table_full_name,
  target_table_full_name,
  created_by,
  event_time
FROM system.access.table_lineage
WHERE target_table_full_name = 'prod.gold.revenue_daily'
ORDER BY event_time DESC;

-- Column-level lineage: which source columns feed revenue_amount?
SELECT
  source_table_full_name,
  source_column_name,
  target_table_full_name,
  target_column_name
FROM system.access.column_lineage
WHERE target_table_full_name = 'prod.gold.revenue_daily'
  AND target_column_name = 'revenue_amount';
```

### Data Quality Monitoring

**DLT Expectations as Quality Metrics:**
All `@dlt.expect` violations are automatically tracked and exposed via the DLT pipeline UI and event log.

```sql
-- Query DLT event log for data quality metrics:
SELECT
  timestamp,
  details:flow_progress:data_quality:dropped_records,
  details:flow_progress:data_quality:expectations
FROM delta.`/pipelines/<pipeline-id>/system/events`
WHERE event_type = 'flow_progress'
ORDER BY timestamp DESC;
```

**Databricks Lakehouse Monitoring:**
A native feature for tracking statistical drift of table data over time.

```python
from databricks.sdk.monitor import MonitorMetricType

databricks_client.quality_monitors.create(
  table_name="prod.silver.orders",
  assets_dir="/monitors/orders",
  output_schema_name="prod.monitoring",
  time_series=databricks_client.sdk.TimeSeriesSpec(
    timestamp_col="order_date",
    granularities=["1 day"]
  )
)
```

This generates:
* **Profile table:** Statistical summary (min, max, mean, null %) per column.
* **Drift table:** Change in statistics over time (detects upstream data changes).

**Key Metrics to Monitor:**
* Null rates per column.
* Row count delta (drops indicate missing upstream data).
* Distinct value counts (cardinality drift).
* Min/max/mean drift (detects schema or upstream logic changes).

### Integrating External Governance Tools

For large enterprises, Unity Catalog integrates with dedicated data catalog and governance platforms.

**Alation:**
* Bidirectional sync of metadata (schemas, descriptions, tags).
* UC lineage exported to Alation's lineage graph.
* Business glossary definitions synced back to UC.

**Atlan:**
* Native Unity Catalog connector.
* Pulls table schemas, tags, and lineage automatically.
* Supports automated PII tagging based on column name patterns.

**Collibra:**
* Policy management defined in Collibra, enforced in UC.
* Automated data classification and tagging.
* Stewardship workflows triggered on new UC assets.

**Integration Pattern:**
```
  Unity Catalog ──(API sync)──► External Catalog Tool
  (Source of truth for       (Business context, glossary,
   technical metadata)        data stewardship workflows)
```

**Architect Recommendation:** Unity Catalog is the source of truth for technical metadata (schemas, lineage, access control). Use external tools only to add business context (descriptions, business glossary, stewardship) that UC doesn't natively support.

***

## Phase 3 Summary

| Topic | Key Points |
|---|---|
| Unity Catalog | 3-level namespace, Metastore design, Managed vs External |
| Access Control | GRANT/REVOKE on hierarchy, row & column security |
| Security Arch | Service Principals, Secrets, VNet, Private Link, CMK |
| Lineage | Automatic column-level lineage, system tables, monitoring |

**Self-Assessment Checklist:**
* [ ] Can you design a Unity Catalog metastore for a multi-workspace enterprise?
* [ ] Can you implement row-level security using dynamic views?
* [ ] Can you apply column masking for PII protection?
* [ ] Can you explain the difference between Managed and External tables?
* [ ] Can you configure secure cluster-to-storage access via IAM roles?
* [ ] Can you query UC system tables for audit and lineage data?
* [ ] Can you explain GDPR deletion requirements in Delta Lake?

***

## Resources

* Databricks Docs: `docs.databricks.com/data-governance/unity-catalog`
* Databricks Academy: "Data Governance with Unity Catalog"
* Databricks: "Unity Catalog Best Practices Guide"
* Book: "Fundamentals of Data Engineering" (O'Reilly) — Chapter on Governance
