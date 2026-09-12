output "repository_urls" {
  description = "url de cada repositório, usada pelo docker push no CI e pela imagem no manifesto"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}
