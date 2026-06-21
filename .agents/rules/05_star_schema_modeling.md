# Rule: Data Modeling Standard — Star Schema (MANDATORY)

## Scope
This rule applies to **Gold layer** schemas only (Medallion Architecture). Bronze and Silver follow their own layer rules (see Rule 08). All Gold ER diagrams, DDL scripts, and schema documents MUST follow the Kimball Star Schema methodology.

---

## Core Rules

### 1. Direct Fact-Dimension Connection
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

### 2. No Dimension-to-Dimension Joins
Direct dimension-to-dimension foreign keys are STRICTLY FORBIDDEN. They create Snowflake Schemas which degrade BI tool performance and query simplicity.

If a dimension references another dimension, denormalize the referenced attributes as flat columns instead.

**Exception:** Bridge tables (§7) may sit between a fact and a dimension to resolve many-to-many relationships.

---

### 3. Surrogate Keys
Every dimension table MUST have a surrogate key (integer or deterministic hash) as its primary key. Fact tables reference dimensions exclusively via these surrogate keys.

- **Distributed Hashing:** For cloud scale (Databricks, Snowflake), use deterministic hashing (e.g., `MD5` or `SHA256`) to avoid sequential generator bottlenecks.
- **Standardization:** Clean and standardize natural keys (e.g., `UPPER(TRIM(natural_key))`) before hashing to prevent mismatch issues.
- Natural/business keys MUST be preserved alongside the surrogate key for traceability.
- Surrogate keys MUST be unique and NOT NULL.

---

### 4. Denormalize Dimension Hierarchies
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

### 5. Role-Playing Dimensions
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

### 6. Degenerate Dimensions
Low-cardinality descriptive attributes that have no meaningful dimension table (e.g., `order_number`, `invoice_id`) MUST be stored directly on the fact table as degenerate dimension columns. Do NOT create trivial single-column dimension tables for these.

---

### 7. Bridge Tables
Bridge tables are permitted ONLY to resolve many-to-many relationships between a fact and a dimension (e.g., `BridgeAccountAlloc`).

- The fact table holds a `group_key` FK pointing to the bridge table.
- The bridge table holds individual dimension surrogate key FKs and an allocation weighting factor.
- Bridge tables are NOT standalone Dim-to-Dim links.

---

### 8. Unknown / Default Member
Every dimension table MUST contain a default "Unknown" row (surrogate key = `-1`). Fact records with unresolvable or late-arriving dimension keys MUST map to this row via `COALESCE(dim_key, -1)`. Fact FK columns MUST NEVER be NULL.

---

### 9. Conformed Dimensions
Shared dimensions (e.g., `DimDate`, `DimCustomer`) MUST be conformed: a single physical table with a single surrogate key sequence, reused across all fact tables.

Do NOT create per-subject-area copies of the same dimension.

---

### 10. Slowly Changing Dimensions (SCD)
- **SCD Type 1** (overwrite) is the default for attributes where history is not required.
- **SCD Type 2** (versioned rows with `valid_from`, `valid_to`, `is_current`) MUST be used when historical attribute tracking is required (e.g., Chart of Accounts, Customer region changes).
- When SCD Type 2 is used, fact tables join on the dimension surrogate key (not the natural key) to preserve point-in-time accuracy.

---

### 11. Data Precision (Floating-Point Prohibition)
To prevent rounding errors and ensure perfect auditability, all financial amounts and additive measures in Gold tables MUST use exact precision types (e.g., `DECIMAL(18,2)` or `NUMERIC`). Floating-point types (e.g., `FLOAT`, `DOUBLE`, `REAL`) are STRICTLY FORBIDDEN for additive metrics.

---

### 12. Gold Aggregation Tables
Pre-aggregated Gold summary tables (e.g., daily rollups) that use inline date/grouping columns instead of dimension FKs are permitted as supplementary consumption endpoints.

These tables MUST NOT replace the primary star schema model and should be clearly named (e.g., `gold.sales_daily_summary`).

---

### 13. Audit Columns
All Gold tables MUST include `_gold_updated_at TIMESTAMP` for pipeline lineage (per Rule 08 §1).

---

### 14. Active Enforcement
When reviewing OR generating any Gold schema:
1. Check every relationship line.
2. Reject any Dim→Dim join (except sanctioned bridge tables).
3. Fix by denormalizing the offending attributes.
4. Verify every dimension has a surrogate key and Unknown row.
5. Enforce exact numeric precision on financial metrics.
6. Document the fix in a validation comment.
