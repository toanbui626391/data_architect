# Validation Report
## `dwh_design_challenges.md` — Finance & Accounting DWH

**Reviewed against:** Industry standards (SOX, ASC 606, IFRS 15),
data warehousing best practices (Kimball, Data Vault 2.0),
and current cloud data platform capabilities.

---

## Overall Assessment

| Dimension | Rating | Notes |
|:---|:---|:---|
| Technical Accuracy | ✅ Strong | Core claims are factually correct |
| Domain Coverage | ⚠️ Partial | Several significant gaps identified |
| Depth of Content | ⚠️ Needs Work | Topics exist but lack implementation detail |
| Actionability | ⚠️ Weak | Recommendations section is too thin |
| Structure & Clarity | ✅ Strong | Logical, easy to follow |

---

## Section-by-Section Findings

### Section 1 — Data Accuracy & Single Source of Truth

**✅ Validated:**
- Double-entry constraint is accurate and critical.
- Reconciliation to source ERP is a real, daily challenge.
- Late-arriving data is correctly identified as a primary
  operational problem.

**⚠️ Gaps to Address:**
- Missing: **Precision/Scale issues.** Floating-point arithmetic
  in SQL engines can cause rounding errors in multi-currency
  aggregations. Monetary amounts must use `DECIMAL(19,4)`
  or equivalent, not `FLOAT`. This is a concrete, common
  pitfall omitted from the document.
- Missing: **Deduplication strategy.** Financial pipelines
  using CDC (Change Data Capture) must handle duplicate events
  from source systems, requiring idempotent ingestion logic.

---

### Section 2 — Complex Business Logic & Financial Rules

**✅ Validated:**
- ASC 606 / IFRS 15 references are accurate and relevant.
- Currency conversion complexity (spot vs. average vs. historical)
  is correctly described.
- Intercompany eliminations are a well-known consolidation
  challenge.

**⚠️ Corrections & Gaps:**

> **Currency Precision:**
> The document lists exchange rate types correctly, but misses
> a key architectural concern: exchange rates must be stored
> in a separate `DimExchangeRate` table, not embedded in
> fact tables. Architects frequently get this wrong.

> **Missing: Chart of Accounts (CoA) Versioning.**
> The CoA changes over time (accounts are added, renamed,
> or deprecated). The warehouse must handle CoA versioning,
> or historical reports will break when the CoA is updated.
> This is one of the most overlooked challenges in practice.

> **Missing: Accruals & Adjusting Entries.**
> The accounting close cycle involves posting journal entries
> (accruals, deferrals, reclassifications) that are not
> captured in transactional source systems. The DWH must
> integrate with the GL subledger to capture these.

---

### Section 3 — Compliance, Auditability & Security

**✅ Validated:**
- SOX lineage requirement is accurate and well-stated.
- RLS/CLS mention is correct.
- The need for audit trails is correct.

**⚠️ Corrections & Gaps:**

> **SOX Clarification:**
> The document positions SOX only as a data lineage concern.
> More precisely, SOX Section 302 & 404 require controls over
> **both** the data and the process that generates it. This
> includes version control over transformation logic (dbt
> model changes must be auditable), not just data lineage.

> **Missing: Segregation of Duties (SoD).**
> A core SOX IT General Control (ITGC) requirement is that the
> person who develops a pipeline cannot be the same person who
> deploys or approves it. The data platform must enforce this
> through CI/CD access controls.

> **Missing: Data Retention & Right-to-Erasure.**
> Financial records have minimum retention requirements
> (e.g., 7 years under SOX, IRS regulations). Simultaneously,
> GDPR and CCPA require the ability to delete PII on request.
> These requirements directly conflict and must be designed
> for explicitly (e.g., pseudonymization of PII fields in
> financial records).

> **Missing: PCI-DSS.**
> Any financial warehouse storing payment card data must
> also comply with PCI-DSS. This was not mentioned.

---

### Section 4 — Temporal Data & "Time Travel"

**✅ Validated:**
- SCD Type 2 usage for as-was reporting is correct.
- 4-4-5 fiscal calendar is a real and common pattern.
- Restatement management is a genuine challenge.

**⚠️ Corrections & Gaps:**

> **SCD Type Accuracy:**
> The document references "SCD Type 4" for as-was reporting.
> SCD Type 4 uses a separate "mini-dimension" history table
> and is rarely used in finance. The dominant pattern for
> financial as-was reporting is **SCD Type 2**, sometimes
> combined with **point-in-time (PIT) tables** in Data Vault
> 2.0. SCD Type 4 should be removed or clarified to avoid
> misleading architects.

> **Missing: Bi-Temporal Modeling.**
> Financial data requires two timelines:
> 1. `transaction_date` — when the event occurred in reality.
> 2. `load_date` — when the system learned about the event.
> Bi-temporal tables are the correct architectural answer for
> audit-grade financial data, supporting both "as-of" queries
> and "as-known-at" queries. This is a critical omission.

> **Missing: Period-End Snapshots.**
> In addition to transactional fact tables, financial DWHs
> require periodic snapshot fact tables (monthly balance
> snapshots) to efficiently answer questions like
> "What was the AR balance at month-end?" without expensive
> full-history aggregations.

---

### Section 5 — Performance & the Financial Close

**✅ Validated:**
- Month-end spike in query load is well-identified.
- Concurrency challenge is real and correctly described.

**⚠️ Gaps:**

> **Missing: Workload Management (WLM).**
> The document identifies the problem but not the solution.
> Production financial DWHs must implement query priority
> queues (e.g., Snowflake Resource Monitors, Databricks
> Serverless Queue policies, BigQuery Slots reservations) to
> prevent ad-hoc queries from starving scheduled close jobs.

> **Missing: Pre-Aggregated Materialized Views.**
> Month-end dashboards are too slow to run from raw data.
> Architects must pre-build materialized aggregates (e.g.,
> monthly P&L summaries, balance sheet snapshots) refreshed
> at close. This is a key pattern absent from the document.

---

### Section 6 — Disparate & Legacy Data Sources

**✅ Validated:**
- System integration list (ERP, CRM, billing, HRIS) is
  representative and accurate.
- Data quality in legacy systems is a real concern.

**⚠️ Gaps:**

> **Missing: Schema Drift.**
> ERP vendors (SAP, Oracle) release updates that can silently
> change column names, data types, or table structures. The
> ingestion layer must have schema evolution handling to
> prevent silent pipeline failures.

> **Missing: Data Contracts.**
> Mentioned only briefly in the recommendations. This is
> important enough to be a named challenge: without formal
> data contracts with source system owners, upstream changes
> regularly break financial reports without warning.

---

### Strategic Recommendations Section

**⚠️ Significantly Undersized.**
Three bullet points for a topic this complex is insufficient.

The following topics are missing entirely:
- **Data Vault 2.0** as an alternative to Kimball for highly
  auditability-focused financial DWHs (supports bi-temporal
  modeling natively).
- **Semantic Layer** (e.g., dbt Semantic Layer, AtScale) to
  enforce consistent metric definitions across all consumers.
- **Incremental build strategy** during financial close to
  reduce latency without full refreshes.
- **Testing & Validation framework** — Great Expectations,
  dbt tests, or equivalent — to enforce that financial totals
  reconcile before data is exposed to users.

---

## Summary: Missing Topics

The following significant topics are absent from the
current document:

| Missing Topic | Severity |
|:---|:---|
| Decimal precision (FLOAT vs DECIMAL) | 🔴 High |
| Chart of Accounts versioning | 🔴 High |
| Bi-temporal data modeling | 🔴 High |
| Segregation of Duties (SoD / SOX ITGC) | 🔴 High |
| Periodic snapshot fact tables | 🟠 Medium |
| Accruals & adjusting journal entries | 🟠 Medium |
| Schema drift from ERP upgrades | 🟠 Medium |
| Workload management / query queues | 🟠 Medium |
| Data Vault 2.0 as architecture option | 🟠 Medium |
| PCI-DSS compliance | 🟠 Medium |
| GDPR vs. data retention conflict | 🟠 Medium |
| Materialized views for close cycle | 🟡 Low |
| Semantic layer / metric governance | 🟡 Low |
| Idempotent CDC ingestion | 🟡 Low |

---

## Recommended Next Steps

1. **Fix the SCD Type 4 reference** — replace with a
   clearer SCD Type 2 + PIT table explanation.
2. **Add a Section 7: Data Modeling Patterns** covering
   bi-temporal tables, periodic snapshots, and the choice
   between Kimball and Data Vault 2.0.
3. **Add a Section 8: The Accounting Domain Glossary**
   to define key terms (CoA, GL, subledger, accrual) for
   data engineers who may not have accounting background.
4. **Expand the Recommendations section** to include
   SoD enforcement, semantic layers, and validation testing.
5. **Add Mermaid diagrams** illustrating:
   - Source system integration flow
   - Bi-temporal table structure
   - Month-end close data flow
