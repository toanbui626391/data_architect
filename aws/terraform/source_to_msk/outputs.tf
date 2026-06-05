output "msk_bootstrap_brokers_tls" {
  description = "TLS connection host:port pairs"
  value       = aws_msk_cluster.central_bus.bootstrap_brokers_tls
}

output "msk_connect_role_arn" {
  description = "IAM Role ARN for MSK Connect"
  value       = aws_iam_role.msk_connect_role.arn
}

output "glue_registry_arn" {
  description = "ARN of the Glue Schema Registry"
  value       = aws_glue_registry.sap_schema_registry.arn
}
