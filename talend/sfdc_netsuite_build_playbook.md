# Build Playbook: Talend to Snowflake ELT Pipeline

Based on the [Talend to Snowflake Integration Architecture](./sfdc_netsuite_to_snowflake_architecture.md), this playbook details the step-by-step execution plan to build the batch integration Job in **Talend Studio**.

---

## Phase 1: Pre-Job & Global Context Setup

To ensure efficiency and prevent memory leaks, we establish all database and API connections once at the start of the Job.

### 1.1 Initialization (`tPrejob`)
1.  Drag a **`tPrejob`** component onto the canvas.
2.  Connect it (using an *OnComponentOk* trigger) to a series of connection components:
    *   **`tSalesforceConnection`**: Configure with OAuth or Bulk API credentials.
    *   **`tNetSuiteConnection`**: Configure with TBA (Token-Based Authentication).
    *   **`tS3Connection`** (or `tAzureStorageConnection`): Configure access keys to your cloud staging bucket.
    *   **`tSnowflakeConnection`**: Configure JDBC URL, Virtual Warehouse, and Role.

### 1.2 Establish the High-Water Mark (Delta Loading)
1.  Connect the last connection component to a **`tSnowflakeInput`** component.
2.  Query a control table (e.g., `SELECT MAX(Last_Extract_Timestamp) as Last_Run FROM ETL_CONTROL`).
3.  Route the output to a **`tSetGlobalVar`** component to store this value in memory (e.g., `"Last_Run_Date"`). This ensures we only pull records modified *after* this date.

---

## Phase 2: Salesforce Extraction & Cloud Staging

### 2.1 Extract via Bulk API
1.  Drag a **`tSalesforceInput`** component. Set it to use the existing connection.
2.  **Query Mode:** Select `Bulk`. This is crucial for high performance and avoiding API limits.
3.  **SOQL Query:** Write the query injecting the global variable: 
    ```sql
    "SELECT Id, Name, Type, BillingState, LastModifiedDate FROM Account WHERE LastModifiedDate > '" + ((String)globalMap.get("Last_Run_Date")) + "'"
    ```

### 2.2 Map and Cleanse Data
1.  Connect `tSalesforceInput` to a **`tMap`** component via a *Main* row.
2.  Inside `tMap`:
    *   Standardize date fields to `yyyy-MM-dd HH:mm:ss`.
    *   Sanitize strings (e.g., replacing newline characters that might break CSV formatting).
    *   Map the output to align with the Snowflake Bronze schema.

### 2.3 Write to Local Stage
1.  Connect the `tMap` output to a **`tFileOutputDelimited`** component.
2.  **File Name:** Configure a dynamic local temp path: `"/tmp/talend/sfdc_accounts_" + TalendDate.getDate("CCYYMMDD") + ".csv"`.
3.  **Advanced Settings:** Enable *CSV options* and check *Include Header*.

### 2.4 Upload to Cloud Stage (AWS S3)
1.  Right-click `tFileOutputDelimited` and select *Trigger -> OnComponentOk*.
2.  Connect it to a **`tS3Put`** component.
3.  **Bucket Name:** Your Snowflake external stage bucket (e.g., `snowflake-bronze-landing`).
4.  **File to Upload:** Use the exact file path generated in step 2.3.

---

## Phase 3: NetSuite Extraction & Cloud Staging

*Repeat the structure from Phase 2, but adapted for NetSuite SuiteTalk API.*

1.  Drag a **`tNetSuiteInput`** component. Use the existing connection.
2.  **Search Criteria:** Configure a Saved Search or Basic Search using the `lastModifiedDate` filter greater than our `Last_Run_Date` global variable.
3.  Route through a **`tMap`** to flatten NetSuite's complex XML payload into a flat tabular structure.
4.  Write to **`tFileOutputDelimited`** (e.g., `netsuite_orders.csv`).
5.  Upload via **`tS3Put`** using an *OnComponentOk* trigger.

---

## Phase 4: Bulk Ingestion to Snowflake Bronze

Now that all CSV files are sitting in the Cloud Storage bucket (which acts as a Snowflake External Stage), we trigger the MPP load.

### 4.1 Execute `COPY INTO`
1.  From the final `tS3Put` component, create an *OnComponentOk* trigger and connect it to a **`tSnowflakeBulkExec`** component.
2.  Configure the component:
    *   Use existing connection.
    *   **Table:** `BRONZE_SALESFORCE_ACCOUNTS` (or the equivalent target table).
    *   **Stage Name:** Reference the internal or external stage created in Snowflake (e.g., `@s3_bronze_stage`).
    *   **File Format:** Reference a pre-defined CSV file format in Snowflake.
3.  **Advanced Settings:**
    *   Set **On Error** to `CONTINUE`. This ensures that if one bad row exists in the CSV, the entire load does not fail. Failed rows will be captured in Snowflake's `VALIDATE` tables later.

*(Note: In a robust pipeline, you would use a tIterate or multiple tSnowflakeBulkExec components if you are loading multiple distinct tables like Accounts, Opportunities, and Sales Orders).*

---

## Phase 5: Post-Job & Cleanup

Ensure resources are freed up and the environment is kept clean.

### 5.1 Cleanup (`tPostjob`)
1.  Drag a **`tPostjob`** component onto the canvas.
2.  Connect it (via *OnComponentOk*) to a **`tS3Delete`** component to purge the processed CSVs from the landing bucket, saving storage costs.
3.  Connect to a **`tFileDelete`** to purge the local temp CSV files on the Talend JobServer.

### 5.2 Close Connections & Update Watermark
1.  Route to connection closure components: **`tSalesforceClose`**, **`tNetSuiteClose`**, **`tSnowflakeClose`**.
2.  Finally, route to a **`tSnowflakeRow`** component. Execute an `UPDATE` or `INSERT` statement against the `ETL_CONTROL` table to write the current `TalendDate.getCurrentDate()` as the new `Last_Extract_Timestamp`.
