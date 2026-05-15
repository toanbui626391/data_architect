# Validation Report
## `actuals_vs_budget_modeling.md`

**Reviewed against:** Kimball Group dimensional modeling standards,
FP&A industry practices, and OLAP/EPM system integration patterns.

---

## Overall Assessment

| Dimension | Rating | Notes |
|:---|:---|:---|
| Technical Accuracy | ✅ Strong | Core claims align with Kimball standards |
| Domain Coverage | ⚠️ Partial | Several key FP&A topics missing |
| Depth of Content | ⚠️ Needs Work | Schema examples lack critical columns |
| Actionability | ⚠️ Weak | No guidance on sign convention or variance calc |
| Structure & Clarity | ✅ Strong | Logical flow, easy to follow |

---

## Section-by-Section Findings

### Section 1 — The Core Challenge: Granularity Mismatch

**✅ Validated:**
The granularity mismatch table is accurate and is the
most important conceptual point in this domain.
Kimball Group confirms this is the defining challenge
when integrating Actuals with Planning data.

**⚠️ Gaps:**

> **Missing: Update Frequency Mismatch.**
> Beyond grain differences, Actuals and Forecasts have
> different *update schedules*. Actuals update continuously
> (CDC / daily batch), while Budgets may be frozen annually
> and Forecasts updated monthly. The model must be designed
> to handle these asynchronous refresh cycles gracefully.

---

### Section 2 — Modeling Strategies

**✅ Validated:**
Both patterns (Separate Fact Tables and Unified Fact Table)
are legitimate Kimball-compliant approaches.
The trade-off guidance is generally sound.

**⚠️ Corrections & Gaps:**

> **Kimball's Actual Recommendation (Separation of Grain):**
> The document correctly warns against mixing grains but then
> "recommends" the Unified Fact Table without adequately
> stressing Kimball's cardinal rule:
>
> **"Never mix different levels of granularity in a single
> fact table."**
>
> The "Recommended" label on Approach B should be qualified.
> It is only safe to unify the tables if all scenarios are
> first aggregated to the same grain (e.g., monthly).
> If Actuals remain at daily grain and Budgets at monthly grain,
> the Separate Fact Tables (Approach A / Drill-Across) pattern
> is actually the safer Kimball-compliant choice.

> **Missing: The Drill-Across Pattern.**
> Approach A is underdeveloped. The correct Kimball technique
> for reporting across separate fact tables is the
> **Drill-Across** pattern, where the BI tool issues separate
> queries against each fact table and outer-joins the results
> on conformed dimension keys. This is not a "BI tool will
> figure it out" problem — it is a deliberate design decision
> that must be explicitly implemented in the semantic layer.

> **Unified Schema — Missing Critical Columns:**
> The `FactFinancialVariance` DDL is a good start but is
> incomplete for production use:
>
> ```sql
> -- Missing columns that should be present:
> CurrencyKey        INT,      -- What currency is Amount stored in?
> AmountFunctional   DECIMAL(19,4), -- Amount in reporting currency
> AmountOriginal     DECIMAL(19,4), -- Amount in transaction currency
> VersionKey         INT,      -- Links to DimVersion for multi-version forecasts
> SignMultiplier     SMALLINT, -- +1 or -1 (see Sign Convention below)
> Is_Allocated       BOOLEAN,  -- Was this record derived by allocation?
> Load_Date          DATE      -- When was this record loaded (for debugging)?
> ```

---

### Section 3 — Modeling the `DimScenario`

**✅ Validated:**
The core concept of a scenario dimension is correct and
aligned with industry standards (Oracle EPM, Anaplan,
Adaptive Insights all use Scenario/Version as a dimension).

**⚠️ Corrections & Gaps:**

> **Naming Convention (Scenario vs. Version):**
> Many FP&A platforms (Oracle EPM, Hyperion Planning) use
> two separate hierarchical concepts: **Scenario** (e.g.,
> 'Budget', 'Forecast', 'Actual') and **Version** (e.g.,
> 'V1', 'Final', 'Q2 Update'). Collapsing these into a
> single `DimScenario` table works, but the schema should
> capture both to fully represent planning cycles.

> **Missing: `Scenario_Status` Attribute.**
> Critical for governance. Scenarios can be in states like
> 'Draft', 'Under Review', 'Approved', 'Locked', or
> 'Superseded'. Without this, finance users cannot distinguish
> between a working draft forecast and a board-approved plan.

> **Missing: `Valid_From` / `Valid_To` Dates.**
> A forecast scenario covers a specific time horizon. The
> dimension must declare what time range a given scenario
> is "active for" so the BI layer can correctly scope queries.
>
> Example: `FY24 Q2 3+9 Forecast` is valid from
> `2024-04-01` to `2024-12-31`. Without this, it is ambiguous
> whether to include this forecast when reporting on 2025.

> **Rolling Forecast Modeling Gap:**
> The description of a "3+9 Forecast" is accurate, but the
> advice "let the BI layer stitch it together" understates
> the complexity. In practice, you need a dedicated
> `DimVersion` entry for the "blended" rolling view (e.g.,
> `RF_May2025`) alongside the pure forecast periods. The
> BI layer's calculation must be tested carefully to avoid
> double-counting the actuals months when the blended view
> is used.

---

### Section 4 — The Allocation / Bridge Table Pattern

**✅ Validated:**
The `BridgeAccountAllocation` pattern is correct and is
a real-world necessity. The `Is_Allocated` flag is a
genuine best practice.

**⚠️ Gaps:**

> **Missing: Allocation Method Metadata.**
> Auditors will ask *how* the 60/40 split was determined.
> The bridge table should store the allocation method
> (e.g., `Based_On = 'FY23 Actuals Ratio'`) and the date
> the ratio was calculated, not just the ratio itself.

> **Missing: Periodic Rebalancing.**
> The 60/40 ratio changes over time. The process for
> recalculating and reloading allocation weights must be
> defined (e.g., "Recalculate ratios using prior 12-month
> actuals at the start of each fiscal year").

---

## Critical Missing Topics

The following topics are absent from the document entirely
but are essential to the Actuals vs. Budget vs. Forecast domain:

| Missing Topic | Severity | Why It Matters |
|:---|:---|:---|
| **Sign Convention & `SignMultiplier`** | 🔴 High | Without a sign convention, variance formulas break (e.g., higher expense appears as "favorable") |
| **Variance Calculation Layer** | 🔴 High | Document does not explain where variance is calculated (fact table vs. semantic layer vs. BI) |
| **Driver-Based Forecasting Model** | 🟠 Medium | Modern FP&A uses volume/price/rate drivers, not just monetary amounts |
| **Locked vs. Open Scenarios** | 🟠 Medium | A critical governance concept — approved plans must be immutable |
| **Scenario `Status` lifecycle** | 🟠 Medium | Draft → Under Review → Approved → Locked |
| **Volume/Price/Rate Variance Analysis** | 🟠 Medium | Explaining *why* a variance exists, not just the amount |
| **Currency in unified fact table** | 🟠 Medium | Schema shows a single `Amount` — which currency? |
| **Allocation method auditability** | 🟡 Low | How were bridge table ratios derived? |

---

## The Missing Sign Convention (High Priority)

This is one of the most common and painful mistakes in
financial data modeling. It must be added to the document.

**The Problem:**
- Revenue is credited in accounting (positive in the P&L).
- Expense is debited (positive in the P&L but opposite sign in GL).
- A variance of `Actual - Budget = +$100k` on Revenue is
  **favorable**, but the same `+$100k` on Expenses is
  **unfavorable**.

**The Solution — `SignMultiplier` in `DimAccount`:**
Add a `Sign_Multiplier` attribute (value: `+1` or `-1`)
to the `DimAccount` dimension. Apply this multiplier in
the semantic layer when computing variances so that:
- **Favorable variance always displays as positive.**
- **Unfavorable variance always displays as negative.**

---

## Recommended Next Steps

1. **Add a Section 5: Sign Convention** — Document the
   `SignMultiplier` pattern.
2. **Add a Section 6: Variance Calculation Layer** — Define
   clearly that variances are computed at the BI semantic
   layer (not stored in the fact table), and provide example
   formulas.
3. **Enrich the `DimScenario` Schema** — Add `Status`,
   `Valid_From`, `Valid_To`, and a separate `Version` concept.
4. **Correct the "Recommended" label** on Approach B — Qualify
   it with the grain alignment pre-requisite.
5. **Update the `FactFinancialVariance` DDL** — Add
   `CurrencyKey`, `AmountFunctional`, `VersionKey`, and
   `SignMultiplier` columns.
