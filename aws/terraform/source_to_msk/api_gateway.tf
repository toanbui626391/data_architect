# ------------------------------------------------------------------------------
# API GATEWAY (REST API)
# ------------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "webhook_api" {
  name        = "IngestionWebhookAPI-${var.environment}"
  description = "Secure Webhook endpoint for Salesforce and SAP Event Mesh"
}

resource "aws_api_gateway_resource" "webhook_resource" {
  rest_api_id = aws_api_gateway_rest_api.webhook_api.id
  parent_id   = aws_api_gateway_rest_api.webhook_api.root_resource_id
  path_part   = "salesforce"
}

resource "aws_api_gateway_method" "webhook_method" {
  rest_api_id   = aws_api_gateway_rest_api.webhook_api.id
  resource_id   = aws_api_gateway_resource.webhook_resource.id
  http_method   = "POST"
  authorization = "NONE" # Assume WAF or API Keys handle auth
  api_key_required = true
  
  request_validator_id = aws_api_gateway_request_validator.schema_validator.id
  request_models = {
    "application/json" = aws_api_gateway_model.salesforce_account_schema.name
  }
}

# ------------------------------------------------------------------------------
# EDGE SCHEMA ENFORCEMENT (Rule 10 equivalent)
# ------------------------------------------------------------------------------
resource "aws_api_gateway_request_validator" "schema_validator" {
  name                        = "SchemaValidator"
  rest_api_id                 = aws_api_gateway_rest_api.webhook_api.id
  validate_request_body       = true
  validate_request_parameters = false
}

resource "aws_api_gateway_model" "salesforce_account_schema" {
  rest_api_id  = aws_api_gateway_rest_api.webhook_api.id
  name         = "SalesforceAccountModel"
  description  = "Validates incoming Salesforce Account JSON payload"
  content_type = "application/json"

  schema = <<EOF
{
  "$schema": "http://json-schema.org/draft-04/schema#",
  "title": "Account",
  "type": "object",
  "properties": {
    "Id": { "type": "string" },
    "Name": { "type": "string" }
  },
  "required": ["Id", "Name"]
}
EOF
}

# ------------------------------------------------------------------------------
# API GATEWAY TO SQS INTEGRATION (AWS Service Proxy)
# ------------------------------------------------------------------------------
resource "aws_api_gateway_integration" "sqs_integration" {
  rest_api_id             = aws_api_gateway_rest_api.webhook_api.id
  resource_id             = aws_api_gateway_resource.webhook_resource.id
  http_method             = aws_api_gateway_method.webhook_method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = aws_iam_role.apigw_sqs_role.arn
  uri                     = "arn:aws:apigateway:${var.aws_region}:sqs:path/${aws_sqs_queue.webhook_buffer.name}"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  # Map the raw JSON payload to SQS MessageBody parameter
  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
  }
}

resource "aws_api_gateway_integration_response" "sqs_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.webhook_api.id
  resource_id = aws_api_gateway_resource.webhook_resource.id
  http_method = aws_api_gateway_method.webhook_method.http_method
  status_code = "200"
  
  response_templates = {
    "application/json" = "{\"message\": \"Event Queued successfully\"}"
  }
  depends_on = [aws_api_gateway_integration.sqs_integration]
}

resource "aws_api_gateway_method_response" "200_response" {
  rest_api_id = aws_api_gateway_rest_api.webhook_api.id
  resource_id = aws_api_gateway_resource.webhook_resource.id
  http_method = aws_api_gateway_method.webhook_method.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_deployment" "webhook_deployment" {
  rest_api_id = aws_api_gateway_rest_api.webhook_api.id
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.webhook_resource.id,
      aws_api_gateway_method.webhook_method.id,
      aws_api_gateway_integration.sqs_integration.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "webhook_stage" {
  deployment_id = aws_api_gateway_deployment.webhook_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.webhook_api.id
  stage_name    = var.environment
}
