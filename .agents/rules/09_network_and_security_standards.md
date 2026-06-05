# Data Warehouse Network & Security Rules

All data warehouse and data platform architectures across this repository MUST strictly adhere to the following network and security standards to ensure enterprise-grade protection.

---

## 1. Network Isolation & Perimeter Security

*   **No Public IPs:** Compute nodes (Databricks clusters, Snowflake warehouses, Spark nodes) MUST NEVER be assigned public IP addresses.
*   **VNet / VPC Injection:** Data processing compute must be deployed within the customer's private network boundary (Azure VNet, AWS VPC, or GCP Shared VPC).
*   **Private Connectivity:** All communication between platform components MUST route through private backbone networks (**Azure Private Link**, **AWS PrivateLink**, **GCP Private Service Connect**). Public internet traversal for data transit is strictly forbidden.

---

## 2. Identity & Access Management (IAM)

*   **Principle of Least Privilege:** Users and service accounts are granted ONLY the minimum privileges required to perform their specific function. No exceptions.
*   **Zero Direct Grants to Users:** Database object privileges (e.g., `SELECT`, `INSERT`) are **never** granted directly to users. Privileges flow strictly through roles: `Object Privilege → Access Role → Functional Role → User`.
*   **No Static Access Keys:** Do not use long-lived static credentials for intra-cloud service access. Use **Managed Identities**, **IAM Instance Profiles**, or **Workload Identity Federation** exclusively.
*   **Layer-Based RBAC:** Access control must map strictly to the Medallion Architecture layers:
    *   **Bronze:** Data Engineering pipelines only (`RAW_ROLE`).
    *   **Silver:** Data Engineering pipeline authors only (`TRANSFORM_ROLE`).
    *   **Gold:** Read-only for Analysts, BI tools, and ML Feature Stores (`BI_READ_ROLE`).
*   **MFA & SSO:** Human access to any platform (Databricks UI, Snowflake UI, Cloud Console) MUST be governed by an enterprise Identity Provider (e.g., Microsoft Entra ID, Okta) enforcing Multi-Factor Authentication.

---

## 3. Data Access Abstraction (PII Protection)

*   **No Direct Base Table Access:** End users and BI tools MUST NEVER query raw base tables directly. All consumption-layer access must be routed through **Secure Views** (Snowflake) or **Unity Catalog Row/Column Filter Policies** (Databricks).
*   **Data Masking:** PII and sensitive columns (e.g., `customer_email`, `national_id`) MUST be masked or excluded from views exposed to non-privileged roles. Use platform-native masking policies.

---

## 4. Secret Management

*   **Zero Hardcoding:** Plaintext credentials (passwords, API keys, tokens) MUST NEVER exist in SQL files, Python scripts, or IaC configurations.
*   **Centralized Vaults:** All secrets must be stored in a cloud-native secret manager (**Azure Key Vault**, **AWS Secrets Manager**, **GCP Secret Manager**).
*   **Runtime Injection:** Compute engines must retrieve secrets dynamically at runtime via secure integration layers (e.g., Databricks Secret Scopes).

---

## 5. Encryption

*   **In-Transit:** All data transmitted across networks MUST be encrypted using **TLS 1.2+**. Mutual TLS (mTLS) is required for point-to-point connections (e.g., Kafka brokers, JDBC sources).
*   **At-Rest:** All data in object storage (ADLS, S3, GCS) and warehouses MUST be encrypted at rest. Where compliance requires (e.g., PCI-DSS, banking regulations), use **Customer Managed Encryption Keys (CMEK)** instead of provider-managed keys.

---

## 6. Auditing & Governance

*   **Centralized Governance:** A unified governance layer (**Databricks Unity Catalog** or **Snowflake Horizon**) must be utilized to manage access policies centrally across all workspaces.
*   **Audit Logging:** Platform diagnostic logs, query histories, and access audit trails MUST be automatically exported to an immutable, centralized log store (e.g., Azure Monitor, AWS CloudTrail, Snowflake `ACCOUNT_USAGE`) for SIEM integration.
*   **Periodic Access Review:** Run access audits regularly to detect violations such as direct grants to analyst roles on base/core tables or over-privileged service accounts.
