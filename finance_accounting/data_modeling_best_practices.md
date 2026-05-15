# Data Modeling Best Practices for Finance & Accounting Data Warehouses

Modeling financial data is uniquely challenging. It requires balancing the need for extremely fast period-end reporting with the strict requirements of auditability, exact precision, and complex temporal histories.

Below are the industry-standard best practices for modeling a data warehouse tailored to the needs of the Office of the CFO.

---

## 1. Choosing the Right Modeling Methodology

### The Hybrid Approach: Data Vault + Kimball
For highly regulated financial environments, a pure dimensional (Kimball) model in the data warehouse core is often insufficient for audit purposes.
* **The Raw/Silver Layer (Data Vault 2.0):** Use Data Vault 2.0 (Hubs, Links, and Satellites) for the enterprise data warehouse core. Data Vault naturally supports **bi-temporal data** (tracking both when an event occurred in the business and when it was loaded into the system) and allows for highly decoupled, auditable integration of multiple ERPs.
* **The Gold/Presentation Layer (Kimball Star Schema):** Finance analysts and BI tools (like PowerBI or Tableau) expect simple Star Schemas. Build Conformed Dimensions and Fact tables on top of the Data Vault core to serve as the user-facing presentation layer.

---

## 2. Best Practices for Financial Dimensions

Financial reporting heavily relies on deeply hierarchical and slowly changing dimensions.

### 2.1 The Chart of Accounts (CoA) Dimension
* **Versioning is Critical:** Accounts change. Do not simply overwrite account names or mappings. Implement **Slowly Changing Dimension (SCD) Type 2** for `DimAccount` to preserve historical roll-ups. 
* **Flatten Hierarchies:** Financial hierarchies (e.g., Account -> Sub-Account -> Rollup Category -> Statement Line) can be deep and ragged. Flatten these into fixed-depth columns in your dimension table (e.g., `L1_Category`, `L2_Category`) to make BI tool drill-downs performant and intuitive.

### 2.2 The Custom Fiscal Date Dimension
* **Never rely on native BI date functions.** Finance rarely uses standard Gregorian calendars.
* **Create a Robust `DimDate`:** This table must explicitly map every standard calendar date to its corresponding `Fiscal_Year`, `Fiscal_Quarter`, `Fiscal_Period`, and `Fiscal_Week` (crucial for 4-4-5 calendars).
* **Include Business Flags:** Add boolean columns like `Is_Holiday`, `Is_Weekend`, and `Is_Business_Day` to allow for complex queries like "Accounts Receivable balance 3 business days before month-end."

### 2.3 The Exchange Rate Dimension
* **Separate the Rates:** Do not embed exchange rates directly into fact tables. Maintain a `DimExchangeRate` table with columns for `From_Currency`, `To_Currency`, `Rate_Type` (Spot, Average, Historical), `Effective_Date`, and `Rate_Value`.
* **Join at Query Time:** Fact tables should store the native transaction currency amount. The BI tool or presentation view should join to `DimExchangeRate` to calculate the converted amount dynamically.

---

## 3. Best Practices for Financial Fact Tables

### 3.1 Fact Granularity
* **Store at the Lowest Grain:** The foundation of the warehouse must be the lowest level of detail: the individual General Ledger (GL) journal entry line. If a user sees a top-level revenue number on a dashboard, they must be able to drill down to the exact journal entries that comprise it (a core SOX requirement).
* **Subledger vs. GL Links:** Maintain explicit linkage (surrogate keys) between the GL fact table and the subledger fact tables (e.g., Accounts Payable, Accounts Receivable) to facilitate automated reconciliation reporting.

### 3.2 Implement Periodic Snapshot Facts
* **The Problem:** Querying a massive transactional fact table to find the current balance of an account requires summing all historical transactions since the dawn of time, which is too slow for month-end close dashboards.
* **The Solution:** Build **Periodic Snapshot Fact Tables**. At the end of every financial period (e.g., Month-End), run a pipeline that calculates and stores the closing balances for every account and cost center. 
* Dashboards looking at "Current Balances" query the Snapshot fact; users looking at "Activity" query the Transactional fact.

---

## 4. Technical and Data Integrity Best Practices

### 4.1 Enforce Exact Precision
* **No Floating Points:** Never use `FLOAT` or `REAL` data types for financial amounts. The SQL engine will introduce microscopic rounding errors that will cause double-entry balances to fail.
* **Use Fixed Precision:** Always use `DECIMAL` or `NUMERIC` types with a standardized scale (e.g., `DECIMAL(19,4)` or `DECIMAL(38,4)`).

### 4.2 Bi-Temporal Integrity for Auditability
To satisfy auditors, the data warehouse must act as a time machine.
* Every record in a raw or conformed table must contain two timelines:
    1. `Transaction_Date` / `Effective_Date` (Business Time): When the event happened in the real world.
    2. `System_Load_Date` (System Time): When the data warehouse received the record.
* This allows an auditor to ask: "What did our Q2 Revenue look like *as of* the July 15th board meeting, before we made retroactive restatements in August?"

### 4.3 Handling Reversals and Adjustments
* **Never Delete Records:** In accounting, you do not delete a mistake; you post a reversing entry. The data warehouse must adopt this same paradigm. If a source system physically deletes a record, the CDC pipeline should capture this as a "soft delete" (flagging the record as inactive) rather than physically removing it from the warehouse history.
* **Track Adjustment Types:** Add a `Transaction_Type` column to distinguish between standard entries, automated accruals, and manual adjustments. This helps auditors quickly isolate risky manual journal entries.

---

## 5. Modeling Intercompany Eliminations

* **Source Tracking:** Ensure every transaction fact record has an `Is_Intercompany` flag and identifies the `Trading_Partner_Entity`.
* **The Consolidation Layer:** Do not perform eliminations in the same fact tables where entity-level actuals reside. Create a separate `FactConsolidation` or `FactEliminations` table.
* **Audit Trail:** When eliminating $1M in intercompany revenue against $1M in intercompany expense, the elimination entries should be clearly linked back to the original entity transactions, providing a transparent audit trail of the consolidation process.
