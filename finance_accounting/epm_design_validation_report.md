# EPM Solution Design Validation Report

**Document Reviewed:** `finance_accounting/epm_solution_design.md`
**Reviewer:** Enterprise Data Architect

---

## Version History

| Version | Summary |
|:---:|:---|
| v1 | Initial review — 5 strengths, 4 gaps identified |
| v2 | Post-improvement review — all 4 gaps resolved, 2 new findings |

---

## v1 — Gaps Identified (All Resolved)

| Gap | Recommendation | Status |
|:---|:---|:---:|
| Security & Access Control missing | Add entity + CC-level security model | ✅ Done |
| Single Budget version — no Target vs Working | Add `Target` (top-down) + `Working` (bottom-up) versions | ✅ Done |
| Cash Flow forecasting not addressed | Add DSO/DPO drivers → AR/AP → Cash Flow calc | ✅ Done |
| No overhead allocation logic | Add Corporate IT/HR allocation script by headcount | ✅ Done |

---

## v2 — Full Expert Review

### 🟢 Strengths — All Confirmed

**1. IAS 21 Currency Translation — Fully Compliant**
- P&L → Average Rate (AVG) ✅
- Balance Sheet → Closing Rate (CLO) ✅
- Equity → Historical Rate (HIST) ✅
- Translation Difference → OCI (not P&L) ✅

Correct in design and in FCCS configuration examples.
No issues found.

**2. Three-Version Budget Model — Now Complete**

`Target` (CFO top-down) → `Working` (BU bottom-up) → `Budget` (Board locked).
The updated workflow diagram correctly shows the
**Negotiation Gap** review step between Target and Working
before the formal approval chain begins. This is exactly
how enterprise budgeting works in practice.

**3. Driver-Based Planning with Cash Flow — Fully Integrated**

The calculation chain is now end-to-end:
```
Headcount × Avg Comp      → Payroll
Volume × Price            → Revenue
Revenue × (1 - GM%)       → COGS
(Revenue / 30) × DSO      → Accounts Receivable
(COGS / 30) × DPO         → Accounts Payable
Net Income + ΔAP - ΔAR   → Operating Cash Flow
```
This allows the P&L, Balance Sheet, and Cash Flow
Statement to all be driven from the same set of
business inputs — a hallmark of a mature EPM design.

**4. Corporate Overhead Allocation — Correctly Modeled**

The headcount-ratio allocation script is technically
correct. The offset entry on `Corporate_HQ` ensures the
Group total is unchanged — a critical requirement to
avoid double-counting overhead in consolidated reports.

**5. Variance Sign Logic — Correct**

`IIF(Account_Type = "Revenue", Actual - Budget, Budget - Actual)`
correctly inverts expense variances so that "under budget"
on costs shows as a favorable (+ve) number. This is
applied consistently across Budget and Forecast scenarios.

**6. Security Model — Enterprise-Grade**

The two-layer security model is well designed:
- **Group-level:** Entity and Cost Center scope
  per user role (APAC Controller → APAC entities only).
- **Cell-level:** Calculated cells locked, Actuals
  universally read-only, Locked versions fully frozen.

**7. Rolling Forecast Cadence — Gold Standard**

The 3+9 → 6+6 → 9+3 → 12+0 cadence with supersession
logic ensures management always has a full-year view
and the DWH always holds only one `Is_Current = true`
Forecast version.

**8. Intercompany Matching — Production-Ready**

IC elimination using `TradingPartner + Account Pair + Period`
with a $1,000 auto-adjust tolerance and alert threshold
is operationally realistic and will materially reduce
manual close effort.

---

### 🟡 Remaining Considerations

Two items are not gaps in the current design, but should
be addressed in the **build phase** before go-live:

**Finding 1 — Working Version Governance**

The `Working` version is editable by all BU Managers
simultaneously. The design does not specify what happens
if two managers from the same entity (e.g., two regional
leads sharing an entity) overwrite each other's data.

**Recommendation:** Define a lock-at-cost-center-level
rule so each cost center is owned by exactly one user
at a time during the budget submission window.

**Finding 2 — Allocation Sequencing**

The Overhead Allocation script (Section 3.4) currently
runs within the `Budget / Working` fix. However, if BUs
update their headcount after allocation has run, the
allocation amounts will become stale without a re-run.

**Recommendation:** Configure the allocation as a
**scheduled business rule** that re-runs automatically
whenever `Headcount_FTE` is changed in any entity,
rather than a one-time manual execution.

---

## Final Verdict

**Status: ✅ Approved for Build Phase**

The solution design is comprehensive, technically sound,
and complete. All four gaps from v1 have been resolved.
The two remaining considerations are low-risk operational
details that can be addressed during Phase 3 (PBCS Build)
without requiring a design change.
