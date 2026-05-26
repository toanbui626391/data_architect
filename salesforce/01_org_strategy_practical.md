# Practical Guide 1: Org Strategy & Core Design

Cut through the theory. Here is how you actually decide and implement your Org strategy for an MNC.

## 1. Decision Matrix: Single vs. Multi-Org

| Scenario | Decision | Practical Reason |
| :--- | :--- | :--- |
| **China/Russia Operations** | **Separate Org** | Data residency laws (Cybersecurity Law/Federal Law No. 242-FZ) mandate local storage. A separate org on local infrastructure (e.g., Alibaba Cloud) is practically mandatory. |
| **Highly Autonomous BUs** | **Multi-Org** | If BUs have different products, different sales cycles, and don't cross-sell, forcing them into one org creates technical debt. Integrate at the DWH level instead. |
| **Global Sales/Service** | **Single Org** | If reps sell globally or support cases cross borders, you *must* use a single org. Use Record Types, sharing rules, and Dynamic Forms to localize. |
| **High Transaction Volume** | **Evaluate** | If API calls/transactions push platform limits (LDV), consider Multi-Org or offloading to a data lake. |

## 2. Implementing "Core vs. Local" (Practical Setup)

If you chose a Single Org, you must enforce a Core template while allowing local flexibility.

### Actionable Setup:

1.  **Core Objects (Locked):** `Account`, `Contact`, `Opportunity`.
    *   **Rule:** Local admins CANNOT add fields to these objects without Architecture Review Board (ARB) approval.
    *   **Why:** Ensures global reporting (e.g., pipeline rollups) doesn't break.
2.  **Localization via Record Types & Dynamic Forms:**
    *   Stop creating separate page layouts for every country (e.g., `Account Layout - France`, `Account Layout - Japan`).
    *   **Rule:** Use one Lightning Record Page and use **Dynamic Forms** to conditionally show/hide localized fields based on `User.Country` or a `Region__c` field on the record.
3.  **Local Extensions (Custom Objects):**
    *   If a region needs to track something highly specific (e.g., `French_Tax_Audit__c`), create a custom object related to the core object.
    *   **Rule:** Prefix local custom objects with a region code (e.g., `EMEA_French_Tax_Audit__c`).
4.  **Metadata-Driven Logic:**
    *   **NEVER** hardcode region checks in Apex (e.g., `if(user.Country == 'US')`).
    *   **Rule:** Use Custom Metadata Types (CMDT). Create a CMDT called `Region_Settings__mdt`. Apex queries this to determine behavior (e.g., `if(regionSettings.Requires_VAT_Calc__c)`).
