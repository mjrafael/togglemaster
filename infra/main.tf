locals {
  name_prefix = "togglemaster-dev"
  services    = ["auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service"]
}

module "networking" {
  source = "./modules/networking"

  name_prefix = local.name_prefix
}

module "ecr" {
  source = "./modules/ecr"

  name_prefix = local.name_prefix
  services    = local.services
}

module "eks" {
  source = "./modules/eks"

  name_prefix        = local.name_prefix
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
}

module "data" {
  source = "./modules/data"

  name_prefix        = local.name_prefix
  vpc_id             = module.networking.vpc_id
  vpc_cidr           = module.networking.vpc_cidr
  private_subnet_ids = module.networking.private_subnet_ids

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

module "cicd" {
  source = "./modules/cicd"

  name_prefix         = local.name_prefix
  github_repository   = "mjrafael/togglemaster"
  ecr_repository_arns = module.ecr.repository_arns
}
