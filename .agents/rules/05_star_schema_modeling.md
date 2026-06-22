# Rule: Data Modeling Standard — Star Schema (MANDATORY)

## Scope
This rule applies to **Gold layer** schemas only (Medallion Architecture). Bronze and Silver follow their own layer rules (see Rule 08). All Gold ER diagrams, DDL scripts, and schema documents MUST follow the Kimball Star Schema methodology.

---

## Core Rules

### 1. Grain Declaration
Every fact table MUST have a documented, explicitly defined grain (e.g., "one row per individual order line item").
- The grain is the foundational contract. Never mix multiple grains in the same fact table.
- Always aim for the lowest (atomic) grain to maximize flexibility.

---

### 2. Fact Table Types
Choose one of the three primary Kimball fact table patterns. A fact table MUST NOT mix these behaviors.
- **Transaction Fact:** Logs discrete events. Extremely sparse. Best for atomic detail (e.g., clicks, purchases).
- **Periodic Snapshot Fact:** Records state at regular intervals. Dense. Best for trend analysis (e.g., daily account balances).
- **Accumulating Snapshot Fact:** Tracks a process pipeline. Has multiple date FKs (e.g., `order_date`, `ship_date`). Row is updated as milestones complete.

---

### 3. Direct Fact-Dimension Connection
Every dimension table connects DIRECTLY to the fact table. No intermediate tables between fact and dimension.

✅ Correct (Star Schema):
```
FactSales → DimDate
FactSales → DimProduct
FactSales → DimCustomer
```

❌ Forbidden (Snowflake Schema):
```
FactSales → DimProduct → DimCategory
```

---

### 4. No Dimension-to-Dimension Joins
Direct dimension-to-dimension foreign keys are STRICTLY FORBIDDEN. They create Snowflake Schemas which degrade BI tool performance and query simplicity.

If a dimension references another dimension, denormalize the referenced attributes as flat columns instead.

**Exception:** Bridge tables (§7) may sit between a fact and a dimension to resolve many-to-many relationships.

---

### 5. Surrogate Keys
Every dimension table MUST have a surrogate key (integer or deterministic hash) as its primary key. Fact tables reference dimensions exclusively via these surrogate keys.

- **Distributed Hashing:** For cloud scale (Databricks, Snowflake), use deterministic hashing (e.g., `MD5` or `SHA256`) to avoid sequential generator bottlenecks.
- **Standardization:** Clean and standardize natural keys (e.g., `UPPER(TRIM(natural_key))`) before hashing to prevent mismatch issues.
- Natural/business keys MUST be preserved alongside the surrogate key for traceability.
- Surrogate keys MUST be unique and NOT NULL.
- **Informational Constraints:** Do NOT define PK/FK constraints as ENFORCED in cloud databases (Databricks, Snowflake) if they impact load performance. Declare them as INFORMATIONAL (unenforced) to document relationships for BI tools.

---

### 6. Denormalize Dimension Hierarchies
Denormalize (flatten) hierarchies into fixed-depth columns within the dimension table. Do NOT normalize hierarchies into separate parent/child tables.

✅ Correct:
```sql
DimAccount (
  L1_Category VARCHAR,  -- e.g. 'Revenue'
  L2_Category VARCHAR,  -- e.g. 'Product Revenue'
  L3_Category VARCHAR   -- e.g. 'Software Revenue'
)
```

❌ Forbidden:
```sql
DimAccount → DimAccountParent → DimAccountRollup
```

---

### 7. Role-Playing Dimensions
When the same dimension is used in multiple roles (e.g., DimEntity as both "Entity" and "TradingPartner"), use aliased foreign keys on the fact table pointing to the SAME physical dimension table.

Do NOT create a separate physical table per role.

✅ Correct:
```sql
FactFinancialVariance (
  EntityKey              INT FK → DimEntity,
  TradingPartnerEntityKey INT FK → DimEntity
)
```

---

### 8. Degenerate Dimensions
Low-cardinality descriptive attributes that have no meaningful dimension table (e.g., `order_number`, `invoice_id`) MUST be stored directly on the fact table as degenerate dimension columns. Do NOT create trivial single-column dimension tables for these.

---

### 9. Junk Dimensions
Group unrelated, low-cardinality boolean flags and indicators into a single "Junk Dimension" rather than leaving them in the fact table or creating separate tiny dimensions.

---

### 10. Bridge Tables
Bridge tables are permitted ONLY to resolve many-to-many relationships between a fact and a dimension (e.g., `BridgeAccountAlloc`).

- The fact table holds a `group_key` FK pointing to the bridge table.
- The bridge table holds individual dimension surrogate key FKs and an allocation weighting factor.
- Bridge tables are NOT standalone Dim-to-Dim links.

---

### 11. Unknown / Default Member
Every dimension table MUST contain a default "Unknown" row. Fact records with unresolvable or late-arriving dimension keys MUST map to this row. Fact FK columns MUST NEVER be NULL.
- **Integer Keys:** Use `-1` for the surrogate key.
- **Hash Keys:** For string/binary hash surrogate keys, use a static conformed hash of a default string (e.g., `MD5('-1')` or `SHA2('-1', 256)`).
- **Default Resolution:** Resolve during loading using `COALESCE(dim_key, -1)` (or equivalent conformed hash key).

---

### 12. Conformed Dimensions
Shared dimensions (e.g., `DimDate`, `DimCustomer`) MUST be conformed: a single physical table with a single surrogate key sequence, reused across all fact tables.

Do NOT create per-subject-area copies of the same dimension.

---

### 13. Slowly Changing Dimensions (SCD)
- **SCD Type 1** (overwrite) is the default for attributes where history is not required.
- **SCD Type 2** (versioned rows with `valid_from`, `valid_to`, `is_current`) MUST be used when historical attribute tracking is required (e.g., Chart of Accounts, Customer region changes).
- When SCD Type 2 is used, fact tables join on the dimension surrogate key (not the natural key) to preserve point-in-time accuracy.
- **Avoid Volatile Tracking:** Do NOT track rapidly changing attributes (e.g., balances, transactional metrics) as SCD Type 2. This causes dimension row-explosion. Isolate them as facts or into a separate junk dimension.

---

### 14. Data Precision and Measure Classification
- **Classification:** Document facts as fully additive (can be summed across all dimensions), semi-additive (e.g., account balances cannot be summed across time), or non-additive (e.g., ratios, margins).
- **Precision:** To prevent rounding errors, all financial amounts and additive measures in Gold tables MUST use exact precision types (e.g., `DECIMAL(18,2)` or `NUMERIC`). Floating-point types (e.g., `FLOAT`, `DOUBLE`) are STRICTLY FORBIDDEN for additive metrics.

---

### 15. Gold Aggregation Tables
Pre-aggregated Gold summary tables (e.g., daily rollups) that use inline date/grouping columns instead of dimension FKs are permitted as supplementary consumption endpoints.

These tables MUST NOT replace the primary star schema model and should be clearly named (e.g., `gold.sales_daily_summary`).

---

### 16. Audit Columns
All Gold tables MUST include `_gold_updated_at TIMESTAMP` for pipeline lineage (per Rule 08 §1).

---

## Anti-Patterns ("Do Not Do" Rules)

*   **Do NOT Snowflake Dimensions:** Never link dimensions to other dimensions. Flatten hierarchies into single conformed dimension tables.
*   **Do NOT Join Facts Directly:** Fact tables must never join directly to each other. Use conformed dimensions to align metrics across business processes (Drill-Across).
*   **Do NOT Allow NULLs in Fact FKs:** Never leave foreign keys null. Map missing or unmapped values to the `-1` (or conformed hash) Unknown row.
*   **Do NOT Mix Granularities:** Never store multiple levels of detail (e.g., daily sales transactions and monthly targets) in the same fact table. Create separate fact tables for separate grains.
*   **Do NOT Put Volatile Metrics in Dimensions:** Do not store rapidly changing metrics or transactional figures (like dates or amounts) inside dimension tables.
*   **Do NOT Leave Text in Fact Tables:** Text descriptions, names, and string attributes belong in dimension tables. Fact tables should contain only numeric measures, surrogate keys, and degenerate dimensions.
*   **Do NOT Use Multi-Column FKs:** Do not join facts to dimensions on composite keys. Resolve lookups to a single conformed surrogate key column.
*   **Do NOT Enforce Constraints on Ingestion:** Cloud warehouses (Snowflake, Databricks) do not enforce PK/FK constraints natively on write. Leave constraints as informational (unenforced) to avoid write bottlenecks.
*   **Do NOT Join on Natural Keys:** Fact-to-dimension joins must strictly use surrogate keys. Natural keys are reserved for ingestion lookups.

---

## Active Enforcement

When reviewing OR generating any Gold schema:
1. Check every relationship line.
2. Reject any Dim→Dim join (except sanctioned bridge tables).
3. Reject any multi-column PK/FK or direct Fact-to-Fact join.
4. Fix by denormalizing the offending attributes.
5. Verify every dimension has a surrogate key, conformed Unknown row, and informational constraints.
6. Enforce exact numeric precision on financial metrics.
7. Document the fix in a validation comment.
