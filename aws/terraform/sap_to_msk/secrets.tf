resource "aws_secretsmanager_secret" "sap_credentials" {
  name        = "sap-hana-credentials-${var.environment}"
  description = "SAP HANA database credentials for MSK Connect"
}

resource "aws_secretsmanager_secret_version" "sap_credentials_val" {
  secret_id = aws_secretsmanager_secret.sap_credentials.id
  secret_string = jsonencode({
    username = var.sap_db_username
    password = var.sap_db_password
  })
}
