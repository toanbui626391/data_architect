# Rule: Data Modeling Standard — Star Schema (MANDATORY)

## Overview
All data warehouse schemas in this repository MUST follow
the Kimball Star Schema methodology. This rule is enforced
on every ER diagram, DDL script, and schema document.

---

## Core Rules

### 1. Direct Fact-Dimension Connection
Every dimension table connects DIRECTLY to the fact table.
No exceptions.

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
Dimension-to-dimension foreign key relationships are
STRICTLY FORBIDDEN. They create Snowflake Schemas which
degrade BI tool performance and query simplicity.

If a dimension has a foreign key pointing to another
dimension, denormalize the referenced attributes as flat
string/int columns instead.

---

### 3. Flatten Dimension Hierarchies
Normalize hierarchies into flat, fixed-depth columns
within the dimension table.

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

### 4. Role-Playing Dimensions
When the same dimension is used in multiple roles
(e.g., DimEntity as both "Entity" and "TradingPartner"),
use aliased foreign keys on the fact table pointing to
the SAME physical dimension table.

Do NOT create a separate DimTradingPartner table.

✅ Correct:
```sql
FactFinancialVariance (
  EntityKey              INT FK → DimEntity,
  TradingPartnerEntityKey INT FK → DimEntity
)
```

---

### 5. Bridge Tables
Bridge tables for many-to-many relationships are permitted
(e.g., BridgeAccountAlloc). However:
- They must NOT appear as a foreign key on the fact table.
- They connect between two dimension tables only.

---

### 6. Active Enforcement
When reviewing OR generating any ER diagram or schema:
1. Check every relationship line.
2. Reject any Dim→Dim join found.
3. Fix by denormalizing the offending attributes.
4. Document the fix in a validation comment.
