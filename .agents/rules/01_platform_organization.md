# Rule: Platform-Specific Organization

## Overview
All work in this repository is organized strictly by platform.

## Rules
1. You will find or create dedicated root directories for each
   target platform, such as:
   - `databricks/`
   - `snowflake/`
   - `bigquery/`
   - `aws/`
   - `gcp/`
   - `azure/`
   - `oracle/`

2. When creating new solutions, always place scripts,
   infrastructure-as-code, and markdown notes inside the
   respective platform directory — never in the repo root.

3. If a platform directory does not yet exist, create it
   before adding any platform-specific files.
