output "role_arn" {
  description = "vai para o secret AWS_ROLE_ARN do repositório, é ARN e não credencial"
  value       = aws_iam_role.ci.arn
}
