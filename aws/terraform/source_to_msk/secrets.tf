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

resource "aws_secretsmanager_secret" "salesforce_credentials" {
  name        = "salesforce-credentials-${var.environment}"
  description = "Salesforce OAuth credentials for MSK Connect"
}

resource "aws_secretsmanager_secret_version" "salesforce_credentials_val" {
  secret_id = aws_secretsmanager_secret.salesforce_credentials.id
  secret_string = jsonencode({
    client_id   = var.salesforce_client_id
    private_key = var.salesforce_private_key
    login_url   = var.salesforce_login_url
  })
}
