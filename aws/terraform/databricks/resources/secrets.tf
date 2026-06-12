# -----------------------------------------------------------------------------
# 1. Create Databricks Secret Scope
# -----------------------------------------------------------------------------
resource "databricks_secret_scope" "kafka" {
  name                     = "kafka-credentials"
  initial_manage_principal = "users"
}

# -----------------------------------------------------------------------------
# 2. Register Secret Placeholders
# -----------------------------------------------------------------------------
# We create placeholders so that pipeline codes compile, but actual credentials
# must be updated out-of-band via UI/CLI or AWS Secrets Manager sync.
resource "databricks_secret" "bootstrap_servers" {
  key          = "bootstrap-servers"
  string_value = "REPLACE_WITH_KAFKA_BROKERS_HOST"
  scope        = databricks_secret_scope.kafka.name
}

resource "databricks_secret" "sasl_username" {
  key          = "sasl-username"
  string_value = "REPLACE_WITH_SASL_USERNAME"
  scope        = databricks_secret_scope.kafka.name
}

resource "databricks_secret" "sasl_password" {
  key          = "sasl-password"
  string_value = "REPLACE_WITH_SASL_PASSWORD"
  scope        = databricks_secret_scope.kafka.name
}
