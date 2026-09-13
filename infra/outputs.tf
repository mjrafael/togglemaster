output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "database_secret_arns" {
  value = module.data.database_secret_arns
}

output "cache_endpoint" {
  value = module.data.cache_endpoint
}

output "queue_url" {
  value = module.data.queue_url
}

output "ci_role_arn" {
  value = module.cicd.role_arn
}
