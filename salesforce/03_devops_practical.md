# Practical Guide 3: DevOps & SFDX Pipeline

Stop using Change Sets ("Happy Soup"). MNCs must use Package-Based Development and automated CI/CD to prevent regional teams from overwriting each other's work.

## 1. Unlocked Packages

Break your org into modular Unlocked Packages.
*   **Core-Pkg:** Base objects, global profiles.
*   **EMEA-Pkg:** EMEA specific workflows, tax fields (Depends on Core-Pkg).
*   **APAC-Pkg:** APAC specific validations (Depends on Core-Pkg).

If an APAC developer breaks something, the APAC package build fails, but it doesn't block the EMEA deployment.

## 2. Practical SFDX Command Cheatsheet

How developers actually work locally using VS Code and Salesforce CLI (`sf`):

```bash
# 1. Authenticate to the Dev Hub (Run once)
sf org login web --set-default-dev-hub --alias my-dev-hub

# 2. Create a temporary Scratch Org for a new feature (Valid for 7 days)
sf org create scratch --definition-file config/project-scratch-def.json --alias feature-branch-org --duration-days 7 --set-default

# 3. Push local metadata code to the Scratch Org
sf project deploy start

# 4. Pull changes made directly in the Scratch Org UI back to local code
sf project retrieve start

# 5. Run all local Apex tests before committing to Git
sf apex run test --test-level RunLocalTests --result-format human
```

## 3. Practical CI/CD Pipeline (GitHub Actions)

This is a working template for an automated pipeline. When a developer creates a Pull Request against the `develop` branch, this script spins up a scratch org, deploys the code, and runs tests. If tests fail, the PR is rejected.

Create this file at `.github/workflows/salesforce-ci.yml`:

```yaml
name: Salesforce CI Validation

on:
  pull_request:
    branches:
      - develop
    paths:
      - 'force-app/**'

jobs:
  validate-code:
    runs-on: ubuntu-latest
    steps:
      # 1. Get the code
      - name: Checkout Source Code
        uses: actions/checkout@v3

      # 2. Install Salesforce CLI
      - name: Install Salesforce CLI
        run: npm install --global @salesforce/cli

      # 3. Auth to Dev Hub (Uses a secret URL stored in GitHub Secrets)
      - name: Authenticate Dev Hub
        run: |
          echo "${{ secrets.SFDX_AUTH_URL }}" > auth_url.txt
          sf org login sfdx-url --sfdx-url-file auth_url.txt --set-default-dev-hub

      # 4. Create an empty Scratch Org
      - name: Create Scratch Org
        run: sf org create scratch --definition-file config/project-scratch-def.json --alias ci-org --wait 10

      # 5. Deploy code to Scratch Org and run tests. 
      # The '--dry-run' flag validates deployment without permanently saving.
      - name: Validate Deployment & Run Tests
        run: sf project deploy start --target-org ci-org --dry-run --test-level RunLocalTests

      # 6. Delete the temporary Scratch Org
      - name: Teardown Scratch Org
        if: always()
        run: sf org delete scratch --target-org ci-org --no-prompt
```
