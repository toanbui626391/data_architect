# EPM Implementation — Step-by-Step Project Plan

Based on `epm_solution_design.md`

---

## Overview

| Phase | Focus |
|:---:|:---|
| 1 | Foundation & Prerequisites |
| 2 | Dimension & Master Data Build |
| 3 | PBCS Planning Application |
| 4 | FCCS Consolidation Setup |
| 5 | Integration (FDMEE) |
| 6 | DWH Connection |
| 7 | Reporting & UAT |
| 8 | Go-Live & Hypercare |

---

## Phase 1 — Foundation & Prerequisites

- [ ] **1.1 Provision Oracle EPM Cloud tenant**
  - Order PBCS + FCCS + Narrative Reporting licenses
  - Set up environments: DEV / UAT / PROD
  - Configure SSO (Oracle Identity Cloud)

- [ ] **1.2 Gather master data from ERP**
  - Export full Chart of Accounts from Oracle Fusion GL
  - Export legal entity list with country + ownership %
  - Export cost center hierarchy
  - Export fiscal calendar per entity

- [ ] **1.3 Define global standards**
  - Agree on Group presentation currency (e.g., USD)
  - Agree on functional currency per entity
  - Agree on fiscal year-end per entity
  - Define Budget and Forecast submission calendar

- [ ] **1.4 Set up project team**
  - EPM Architect (you)
  - Finance SME (one per region)
  - IT / Integration lead
  - DWH / ADW engineer

---

## Phase 2 — Dimension & Master Data Build

- [ ] **2.1 Build Account dimension**
  - Map ERP Chart of Accounts to EPM account hierarchy
  - Define L1 → L3 rollup structure
    (Revenue → Product Revenue → Software Revenue)
  - Tag each account:
    - `Account_Type` (Revenue / Expense / Asset / Liability)
    - `Sign_Multiplier` (+1 / -1)
    - `Required_FX_Rate_Type` (AVG / CLO / HIST)
    - `CashFlow_Category` (Operating / Investing / Financing)
  - Identify Intercompany accounts
    (flag `Is_Intercompany = Y`)

- [ ] **2.2 Build Entity dimension**
  - Build full legal entity hierarchy
    (Group → Region → Country → Entity)
  - For each entity record:
    - `Ownership_Pct` (e.g., 80%)
    - `Consolidation_Method` (Full / Equity / FairValue)
    - `FunctionalCurrencyCode`
    - `FiscalCalendarCode`
    - `CountryCode`
  - Add Elimination entities per region
    (ELIM_APAC, ELIM_EMEA, ELIM_AMERICAS)

- [ ] **2.3 Build Period/Fiscal Calendar dimension**
  - Create fiscal calendar per entity type
    (Jan–Dec, Apr–Mar, Jul–Jun)
  - Map each calendar date to:
    - `FiscalYear`, `FiscalPeriod`, `FiscalPeriodName`
    - `Is_Period_End` flag

- [ ] **2.4 Build Scenario & Version dimension**
  - Create Scenarios: Actual / Budget / Forecast / What-If
  - Create initial Versions:
    - FY[Year]_Budget
    - FY[Year]_Q1_3x9 (first forecast version)
  - Set Status = Draft for Budget, Actual = Open

- [ ] **2.5 Build remaining dimensions**
  - Currency dimension (ISO codes + decimal precision)
  - CostCenter dimension (L1/L2 group hierarchy)
  - ProfitCenter / Segment dimension
    (L1_Segment, L2_Segment, ProductLine)

---

## Phase 3 — PBCS Planning Application

- [ ] **3.1 Create planning application in PBCS**
  - Application type: Custom
  - Enable: Multiple currencies, Planning modules
  - Attach all dimensions from Phase 2
  - Set dense dimensions: Account, Period
  - Set sparse dimensions: Entity, Scenario, Version,
    Currency, CostCenter

- [ ] **3.2 Build driver-based calculation model**
  - Define driver accounts:
    - `Headcount_FTE`
    - `Avg_Comp_Per_HC`
    - `Sales_Volume`
    - `Avg_Selling_Price`
    - `Gross_Margin_Pct`
  - Write Calc Scripts / Business Rules:
    - `Payroll = Headcount × Avg_Comp`
    - `Revenue = Volume × Price`
    - `COGS = Revenue × (1 - GM%)`
    - `Gross_Profit = Revenue - COGS`
    - `EBITDA = Gross_Profit - OpEx`

- [ ] **3.3 Build data entry forms**
  - Form 1: Revenue & Volume Drivers
    (by Entity, CostCenter, monthly)
  - Form 2: Headcount & Payroll
    (by Entity, Department, monthly)
  - Form 3: Operating Expenses
    (by CostCenter, Account L3, monthly)
  - Form 4: Full P&L Review
    (read-only, all calculated lines)

- [ ] **3.4 Build approval workflow**
  - Configure promotion path:
    BU Manager → Finance Controller
    → Regional CFO → Group CFO → Board Lock
  - Set ownership rules per entity
  - Define rejection comment requirements

- [ ] **3.5 Build variance member formulas**
  - `Var_vs_Budget = Actual - Budget`
    (with sign flip for expense accounts)
  - `Var_vs_Budget_Pct = Var / ABS(Budget) × 100`
  - `Var_vs_Forecast = Actual - Forecast`
  - `Full_Year_FC = YTD_Actual + Remaining_FC`

---

## Phase 4 — FCCS Consolidation Setup

*(Runs in parallel with Phase 3)*

- [ ] **4.1 Create FCCS application**
  - Link same Entity, Account, Period dimensions
  - Enable: Multi-currency, Intercompany matching

- [ ] **4.2 Configure currency translation rules**
  - P&L accounts → Average Rate (monthly AVG)
  - Balance Sheet accounts → Closing Rate (CLO)
  - Equity accounts → Historical Rate (HIST)
  - Translation Difference → post to OCI (equity)

- [ ] **4.3 Configure intercompany elimination rules**
  - Define IC account pairs:
    (IC Revenue account ↔ IC Expense account)
  - Set matching keys:
    TradingPartner + Account pair + Period
  - Set tolerance: auto-adjust differences < $1,000
  - Set alert: flag differences > $1,000 for review

- [ ] **4.4 Configure consolidation ownership**
  - Enter ownership % per entity per year
  - Configure minority interest calculation:
    `NI = Subsidiary Net Profit × (1 - Ownership_Pct)`
  - Set consolidation method per entity:
    Full / Equity / Fair Value

- [ ] **4.5 Configure consolidation sequence**
  Set the order FCCS processes:
  1. Load entity actuals
  2. Translate currencies
  3. Eliminate intercompany
  4. Calculate minority interest
  5. Roll up to group

---

## Phase 5 — FDMEE Integration

- [ ] **5.1 Set up FDMEE source systems**
  - Register Oracle Fusion ERP as source
  - Register Oracle EPM PBCS as source
  - Register Oracle ADW as target

- [ ] **5.2 Build account mapping rules**
  - Map each ERP CoA account code →
    EPM Global Account Code
  - Map each EPM account →
    DWH `DimAccount.Global_AccountCode`
  - Handle unmapped accounts:
    route to Suspense account + alert

- [ ] **5.3 Build entity mapping rules**
  - Map ERP company codes → EPM entity codes
  - Map EPM entity codes → DWH `DimEntity.EntityCode`

- [ ] **5.4 Build period mapping rules**
  - Map ERP period names (e.g., `2025-01`) →
    EPM period names (e.g., `Jan-2025`)
  - Map EPM periods →
    DWH `DimFiscalCalendar.CalendarDate`

- [ ] **5.5 Build load rules per data flow**
  - Load Rule A: ERP GL → FCCS Actuals (daily)
  - Load Rule B: FCCS Consolidated → PBCS Actuals
    (monthly, post-close)
  - Load Rule C: PBCS Budget → ADW DWH (on lock)
  - Load Rule D: PBCS Forecast → ADW DWH (on approval)

- [ ] **5.6 Schedule and test each load rule**
  - Test with 1 entity × 1 period × 3 accounts
  - Verify debit = credit after each load
  - Verify amounts match ERP trial balance

---

## Phase 6 — DWH Connection (Oracle ADW)

- [ ] **6.1 Create staging tables**
  - `STG_EPM_PLANNING` for Budget/Forecast
  - `STG_EPM_ELIMINATIONS` for IC entries
  - `REF_EPM_ACCOUNT_MAP` mapping table
  - `REF_EPM_ENTITY_MAP` mapping table

- [ ] **6.2 Create dimension tables in ADW**
  Deploy DDL for all dimensions:
  - `DimVersion`, `DimAccount`, `DimEntity`
  - `DimCostCenter`, `DimProfitCenter`
  - `DimFiscalCalendar`, `DimLedger`
  - `DimCurrency`, `DimExchangeRate`
  - `DimCountry`, `DimTaxJurisdiction`

- [ ] **6.3 Create unified fact table**
  - Deploy DDL for `FactFinancialVariance`
  - Apply VPD row-level security policy

- [ ] **6.4 Build ETL stored procedures**
  - `sp_upsert_dim_version` — version lifecycle
  - `sp_load_silver_epm_planning` — key resolution
  - `sp_load_fact_epm` — MERGE into fact
  - `sp_run_eliminations` — IC elimination engine

- [ ] **6.5 Build dbt models**
  - `stg_epm_planning.sql`
  - `int_epm_resolved.sql`
  - `fact_financial_variance_epm.sql`

- [ ] **6.6 Write dbt data quality tests**
  - Uniqueness on fact grain
  - Referential integrity on all FK columns
  - Accepted values for `Posting_Side`, `ScenarioType`
  - Debit = Credit balance check per period

---

## Phase 7 — Reporting & UAT

- [ ] **7.1 Build OAC semantic model**
  Define all KPI measures:
  - `Actual_Amount`
  - `Budget_Amount`
  - `Forecast_Amount`
  - `Variance_vs_Budget`
  - `Variance_vs_Forecast`
  - `Budget_Achievement_Pct`
  - `Full_Year_Forecast`

- [ ] **7.2 Build standard OAC dashboards**
  - Dashboard 1: Monthly P&L — Actual vs Budget vs FC
  - Dashboard 2: Rolling Forecast waterfall
  - Dashboard 3: Entity Scorecard (by region)
  - Dashboard 4: CostCenter Budget vs Actual detail
  - Dashboard 5: Intercompany reconciliation view

- [ ] **7.3 Build Narrative Reporting templates**
  - Monthly management report template (8 pages)
  - Board pack template (4 pages)
  - CFO commentary section with dynamic tables

- [ ] **7.4 User Acceptance Testing (UAT)**
  - Test with Finance Controllers (1 per region)
  - Verify variance calculations match manual Excel
  - Verify FC version supersession logic
  - Verify IC elimination completeness
  - Sign-off from CFO

---

## Phase 8 — Go-Live & Hypercare

- [ ] **8.1 Production cutover**
  - Load 12 months of historical Actuals
  - Load current year Budget (lock version)
  - Load most recent Forecast version

- [ ] **8.2 Train finance users**
  - BU Managers: data entry forms
  - Finance Controllers: review + approval workflow
  - Regional CFOs: variance dashboards
  - Group Finance: consolidation + board reports

- [ ] **8.3 Establish month-end close runbook**
  Day 1–2: Actuals load (ERP → FCCS → PBCS → DWH)
  Day 2: Debit/Credit validation checks
  Day 3: IC matching and elimination run
  Day 3–4: Forecast update in PBCS
  Day 4: FDMEE export new FC version to DWH
  Day 5: OAC refresh + distribute reports

- [ ] **8.4 Hypercare (2 weeks post go-live)**
  - Monitor FDMEE load logs daily
  - Check debit = credit validation results
  - Resolve unmapped account/entity alerts
  - Tune OAC dashboard performance
