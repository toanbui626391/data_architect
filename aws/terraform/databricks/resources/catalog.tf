# -----------------------------------------------------------------------------
# 1. Register AWS Storage Credential in Unity Catalog
# -----------------------------------------------------------------------------
resource "databricks_storage_credential" "external_s3" {
  name = "metastore_s3_credentials"
  aws_iam_role {
    role_arn = var.unity_catalog_role_arn
  }
}

# -----------------------------------------------------------------------------
# 2. Register External Location in Unity Catalog
# -----------------------------------------------------------------------------
resource "databricks_external_location" "metastore_s3" {
  name            = "metastore_s3_location"
  url             = "s3://${split(":::", var.unity_catalog_bucket_arn)[1]}"
  credential_name = databricks_storage_credential.external_s3.id
}

# -----------------------------------------------------------------------------
# 3. Create Unity Catalog Catalog
# -----------------------------------------------------------------------------
resource "databricks_catalog" "this" {
  name           = var.catalog_name
  storage_root   = "${databricks_external_location.metastore_s3.url}/managed"
  comment        = "Main catalog for sales database pipeline layers"
  force_destroy  = true
}

# -----------------------------------------------------------------------------
# 4. Create Medallion Schemas (Bronze, Silver, Gold)
# -----------------------------------------------------------------------------
resource "databricks_schema" "bronze" {
  catalog_name = databricks_catalog.this.id
  name         = "bronze"
  comment      = "Bronze schema containing raw ingested sales streams"
}

resource "databricks_schema" "silver" {
  catalog_name = databricks_catalog.this.id
  name         = "silver"
  comment      = "Silver schema containing cleansed and conformed sales tables"
}

resource "databricks_schema" "gold" {
  catalog_name = databricks_catalog.this.id
  name         = "gold"
  comment      = "Gold schema containing daily business reporting aggregates"
}
