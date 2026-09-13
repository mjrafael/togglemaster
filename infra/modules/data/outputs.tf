output "database_secret_arns" {
  description = "onde cada serviço busca a credencial do próprio banco"
  value       = { for name, secret in aws_secretsmanager_secret.db : name => secret.arn }
}

output "cache_endpoint" {
  value = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.analytics.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.analytics.arn
}

output "queue_url" {
  value = aws_sqs_queue.evaluations.url
}

output "queue_arn" {
  value = aws_sqs_queue.evaluations.arn
}

output "irsa_role_arns" {
  description = "anotadas nas service accounts do evaluation e do analytics"
  value       = { for name, role in aws_iam_role.irsa : name => role.arn }
}

output "database_endpoints" {
  description = "usados para montar a DATABASE_URL de cada serviço"
  value       = { for name, db in aws_db_instance.main : name => db.endpoint }
}
