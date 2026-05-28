# DLT Deployment & Configuration as Code

## 1. Overview
The best practice for configuring and deploying Delta Live Tables (DLT) is using an Infrastructure-as-Code (IaC) approach. Never deploy production pipelines manually via the Databricks UI.

The native, modern standard for Databricks is **Databricks Asset Bundles (DABs)**. DABs allow you to define your pipeline configurations, execution modes, and cluster settings in a declarative YAML file (`databricks.yml`) that sits alongside your SQL/Python code in version control.

---

## 2. Example: `databricks.yml` Configuration

Below is a comprehensive, production-ready configuration that deploys the Bronze and Silver models we created. It demonstrates how to separate `dev` (Triggered mode) and `prod` (Continuous mode) environments.

```yaml
# databricks.yml
bundle:
  name: realtime_ingestion_project

# 1. Define the DLT Pipeline Core Settings
resources:
  pipelines:
    sales_ingestion_pipeline:
      name: "Sales Real-Time Ingestion"
      
      # The SQL/Python models that make up this pipeline
      libraries:
        - file:
            path: ./models/bronze_ingestion.sql
        - file:
            path: ./models/silver_transform.sql
      
      # Use Serverless compute (Best Practice)
      serverless: true
      
      # Required for Auto Loader and DLT Expectations
      edition: ADVANCED
      
      # Ensure data is tracked accurately across updates
      photon: true

# 2. Define Environment-Specific Deployments
targets:
  
  # --- DEVELOPMENT ENVIRONMENT ---
  dev:
    default: true
    workspace:
      host: https://adb-dev-workspace.databricks.com
    
    # Override pipeline settings for Dev
    resources:
      pipelines:
        sales_ingestion_pipeline:
          # Triggered mode saves costs in Dev (runs only when executed manually or scheduled)
          continuous: false 
          channel: PREVIEW # Use PREVIEW to test upcoming Databricks features
          target: "dev_sales_schema" # Isolate data to a dev schema
          storage: "dbfs:/pipelines/dev/sales_ingestion"

  # --- PRODUCTION ENVIRONMENT ---
  prod:
    workspace:
      host: https://adb-prod-workspace.databricks.com
      
    # Override pipeline settings for Prod
    resources:
      pipelines:
        sales_ingestion_pipeline:
          # Continuous mode ensures real-time streaming 24/7
          continuous: true 
          channel: CURRENT # Use the stable production runtime
          target: "prod_sales_schema" # Production data lands here
          storage: "s3://prod-enterprise-lake/pipelines/sales_ingestion"

```

---

## 3. Key Configuration Concepts Explained

### 3.1 `libraries` (Code Linking)
Instead of copying and pasting code, the `libraries` array points directly to your SQL and Python files in the repository. DLT reads these files and automatically figures out the execution order (the DAG) based on table dependencies.

### 3.2 `serverless` vs Custom Compute
By setting `serverless: true`, you completely eliminate the need to configure Spark worker sizes, instance types, and autoscaling logic. Databricks dynamically allocates resources based on the stream's volume in real-time.

### 3.3 Target Schemas (`target`)
Notice that the SQL files (`bronze_ingestion.sql`) do not specify a database (e.g., they don't say `CREATE TABLE prod_db.bronze_sales`). 
*   **Why?** Because the `target` parameter in the YAML file dictates where the data lands. This allows you to run the exact same SQL code in Dev and Prod, but the data will safely land in `dev_sales_schema` or `prod_sales_schema` depending on the deployment target.

### 3.4 Execution Mode (`continuous`)
*   In the **dev target**, `continuous: false` defines it as a Batch/Triggered pipeline.
*   In the **prod target**, `continuous: true` defines it as an always-on Stream.

### 3.5 Trigger Mechanisms (Databricks Workflows)
When you run a pipeline in Triggered Mode (`continuous: false`), the pipeline itself does not contain a scheduler. To schedule it, you must define a **Job (Databricks Workflow)** in the same `databricks.yml` file under the `resources` block.

```yaml
resources:
  jobs:
    daily_ingestion_job:
      name: "Daily Sales Ingestion Trigger"
      
      # Define the trigger mechanism (e.g., a Cron Schedule)
      schedule:
        quartz_cron_expression: "0 0 2 * * ?" # Run daily at 2:00 AM
        timezone_id: "UTC"
      
      # Tell the job to execute the DLT pipeline
      tasks:
        - task_key: run_sales_dlt
          pipeline_task:
            pipeline_id: ${resources.pipelines.sales_ingestion_pipeline.id}
```
*   **Why?** This decouples the transformation code (DLT) from the orchestration logic (Workflows). You can also use `file_arrival` triggers instead of a cron schedule to execute the pipeline exactly when a new file lands in your cloud bucket.

---

## 4. Deployment Commands

Once configured, deployment is handled via the Databricks CLI in your CI/CD pipeline (e.g., GitHub Actions):

```bash
# Validate the configuration
databricks bundle validate

# Deploy to the 'dev' environment
databricks bundle deploy -t dev

# Run the pipeline in the 'dev' environment
databricks bundle run sales_ingestion_pipeline -t dev

# Deploy to Production (usually handled by an automated CI/CD branch merge)
databricks bundle deploy -t prod
```
