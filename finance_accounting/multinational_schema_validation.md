# Multinational Financial Schema — Validation Report

**Schema File:** `finance_accounting/schema_variance_analysis.md`
**Standard:** Kimball Star Schema + MNC Financial Best Practices

---

## Version History

| Version | Date | Summary |
|:---:|:---|:---|
| v1 | 2026-05-15 | Initial MNC gap analysis; 5 gaps identified |
| v2 | 2026-05-15 | Deep expert review post-implementation; 8 findings |

---

## v1 — Initial Gap Analysis (Resolved)

All 5 gaps identified in v1 have been implemented in the schema.

| Gap | Fix | Status |
|:---|:---|:---:|
| Multi-GAAP / Parallel Ledgers | Added `DimLedger` + `LedgerKey` FK | ✅ Done |
| Matrix org — no segment dim | Added `DimProfitCenter` + `ProfitCenterKey` FK | ✅ Done |
| Intercompany matching detail | Added `TradingPartnerCostCenterKey` FK | ✅ Done |
| No hierarchy flattening | L1/L2/L3 on Entity, CostCenter, Account | ✅ Done |
| Local vs. Global CoA | Added `Global_AccountCode`, `Local_AccountCode` | ✅ Done |

---

## v2 — Deep Expert Review

### Star Schema Compliance

Validated against `.agents/rules/05_star_schema_modeling.md`.

| Rule | Result |
|:---|:---:|
| Direct Fact→Dim connections only | ✅ PASS |
| No Dim→Dim joins | ✅ PASS |
| Flattened hierarchies on all dims | ✅ PASS |
| Role-playing via aliased FKs | ✅ PASS |
| Bridge table usage | ✅ PASS |

---

### 🟢 What Is Genuinely Strong

**1. Three-Currency Model (IAS 21 / ASC 830)**

Tracking `AmountTransaction`, `AmountFunctional`, and
`AmountPresentation` with two separate FX rate keys matches
exactly how Oracle ERP and SAP S/4HANA work internally.
This is the most important design decision for MNC finance
and it is implemented correctly.

Role-playing `DimCurrency` (3 aliases) and `DimExchangeRate`
(2 aliases) on the fact avoids any table bloat and keeps
the schema clean.

**2. Multi-GAAP Parallel Ledgers via `DimLedger`**

`LedgerKey` on the fact means one ERP transaction creates
parallel rows per ledger — exactly how a parallel accounting
system works. Supports IFRS, US GAAP, Local Statutory, Tax
Book, and Management ledgers without schema changes.

**3. Intercompany Matching Keys**

`TradingPartnerEntityKey` + `TradingPartnerCostCenterKey`
together give the elimination team both sides of an
intercompany pair. Most schemas only track the entity,
creating perpetual reconciliation mismatch problems.

**4. `Sign_Multiplier` on `DimAccount`**

The correct solution to the revenue-is-credit /
expense-is-debit problem. Solved at the dimension level
so every query automatically produces a correct
favorable/unfavorable variance sign.

**5. `DimVersion` for Planning Governance**

Locking approved budgets via `Status = 'Locked'` and
tracking superseded forecasts provides immutable audit
trails on planning data — a common SOX requirement.

**6. Bi-Temporal Auditing**

`Transaction_Date` (business time) + `Load_Date` (system
time) supports "as-of" audit queries. `Source_Record_Id`
provides direct ERP drill-through for auditors.

**7. SCD Type 2 on `DimAccount`**

`Valid_From`, `Valid_To`, `Is_Current` correctly versions
the Chart of Accounts so historical reports are not broken
when accounts are restructured.

---

### 🔴 Critical Gaps — High Priority

#### Gap 1 — Single DimDate Cannot Support Multiple Fiscal Calendars

**Risk:** Incorrect fiscal period mapping for subsidiaries.

Large MNCs have subsidiaries with different fiscal year-ends:

| Country | Fiscal Year End |
|:---|:---|
| Vietnam, USA | December 31 |
| Japan, UK | March 31 |
| Australia | June 30 |
| Germany | Varies |

The current `DimDate` has a single `FiscalYear`/`FiscalPeriod`
— reflecting only the Group calendar. All subsidiary-level
statutory reporting resolves to the wrong fiscal period.

**Recommended Fix:**
Add `FiscalCalendarCode` to `DimDate` or introduce a
`DimFiscalCalendar` join dimension so each entity's
transactions resolve to its own fiscal period context.

---

#### Gap 2 — DimEntity Missing Ownership % and Consolidation Method

**Risk:** Consolidation reports cannot be auto-generated
with correct treatment per IFRS 10 / ASC 810.

| Ownership | Required Treatment |
|:---|:---|
| > 50% | Full consolidation |
| 20–50% | Equity method |
| < 20% | Fair value instrument |

Without `Ownership_Pct` and `Consolidation_Method` on
`DimEntity`, finance must manage consolidation rules
outside the warehouse entirely.

**Recommended Fix:**
Add `Ownership_Pct DECIMAL(5,2)` and
`Consolidation_Method VARCHAR` to `DimEntity`.

---

#### Gap 3 — DimExchangeRate Has No IAS 21 Rate-Type Discipline

**Risk:** Wrong exchange rates applied to wrong account types,
causing material misstatement in translated financials.

Under IAS 21, three different rates apply to three account
types:

| Account Type | Required Rate |
|:---|:---|
| Balance Sheet (Assets/Liabilities) | Closing Rate (period-end spot) |
| Income Statement (Revenue/Expense) | Average Rate (period average) |
| Equity (Share Capital, Retained Earnings) | Historical Rate |

The `Rate_Type` string exists on `DimExchangeRate` but
there is no link between `DimAccount.AccountType` and which
rate type should be applied. This logic lives nowhere in the
schema — leaving it entirely to the ETL layer with no
guardrails or auditability.

**Recommended Fix:**
Add `Required_FX_Rate_Type VARCHAR` to `DimAccount` so the
ETL layer has an explicit instruction on which rate to join.

---

#### Gap 4 — No SCD Type 2 on DimEntity or DimCostCenter

**Risk:** Historical reports reflect current org structure
not the structure at time of transaction — a common
audit failure point.

MNCs restructure constantly:
- Subsidiaries move between holding companies.
- Cost centers are transferred between regions.
- Entities are created or dissolved mid-year.

`DimCostCenter` and `DimEntity` have no `Valid_From`,
`Valid_To`, or `Is_Current` columns. This means joins on
current keys will silently produce wrong historical results.

**Recommended Fix:**
Add SCD Type 2 columns to both:
`Valid_From DATE`, `Valid_To DATE`, `Is_Current BOOLEAN`.

---

#### Gap 5 — No `Is_Eliminated` Flag on the Fact Table

**Risk:** Intercompany revenue and expense are double-counted
in consolidated reports.

`TradingPartnerEntityKey` enables matching intercompany
pairs, but there is no way to query which records have
been eliminated after the consolidation process runs.
A reporting user querying consolidated revenue could easily
include intercompany sales that should be eliminated.

**Recommended Fix:**
Add `Is_Eliminated BOOLEAN` and optionally
`EliminationGroupKey INT` to the fact table.

---

### 🟡 Medium Priority Improvements

#### Gap 6 — DimTaxJurisdiction Oversimplifies Tax Reality

A single `Standard_Rate` column cannot represent a
country's tax landscape:

| Tax Type | Applicability |
|:---|:---|
| VAT / GST | Revenue transactions |
| Withholding Tax | Intercompany / dividend payments |
| Corporate Income Tax | Net profit |
| Transfer Pricing Adjustment | Arm's-length pricing |

**Recommended Fix:**
Add `Tax_Category VARCHAR` to support multiple rows per
jurisdiction, each with its own rate and applicability rule.

---

#### Gap 7 — No Cash Flow Classification

The schema supports P&L and Balance Sheet analysis.
The third core financial statement — the Cash Flow
Statement (IAS 7 / ASC 230) — is not addressed.
Transactions must be classified as:
- **Operating** / **Investing** / **Financing**

**Recommended Fix:**
Add `CashFlow_Category VARCHAR` to `DimAccount`.
Classification follows account type and is stable enough
to be a dimension attribute rather than a fact measure.

---

#### Gap 8 — No Debit/Credit Posting Side

For GL reconciliation, the raw accounting direction of a
posting is essential for auditors. `Transaction_Type` tracks
the *purpose* of an entry (Accrual, Reversal, Standard)
but not its accounting direction.

**Recommended Fix:**
Add `Posting_Side CHAR(2)` — `'Dr'` / `'Cr'` — to the
fact table for complete GL reconciliation support.

---

### v2 — Full Findings Summary

| # | Finding | Severity | Recommended Fix |
|:---:|:---|:---:|:---|
| 1 | Single DimDate, no multi-fiscal calendar | 🔴 Critical | Add `FiscalCalendarCode` FK on fact |
| 2 | DimEntity missing ownership % + consolidation method | 🔴 Critical | Add `Ownership_Pct`, `Consolidation_Method` |
| 3 | No IAS 21 rate-type discipline on DimExchangeRate | 🔴 Critical | Add `Required_FX_Rate_Type` to DimAccount |
| 4 | No SCD Type 2 on DimEntity / DimCostCenter | 🔴 Critical | Add `Valid_From`, `Valid_To`, `Is_Current` |
| 5 | No `Is_Eliminated` flag on fact | 🔴 Critical | Add `Is_Eliminated BOOLEAN` to fact |
| 6 | DimTaxJurisdiction oversimplified | 🟡 Medium | Add `Tax_Category` for multiple rate rows |
| 7 | No Cash Flow classification | 🟡 Medium | Add `CashFlow_Category` to DimAccount |
| 8 | No Debit/Credit posting side | 🟡 Medium | Add `Posting_Side CHAR(2)` to fact |
