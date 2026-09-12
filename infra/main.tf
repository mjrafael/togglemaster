locals {
  name_prefix = "togglemaster-dev"
  services    = ["auth", "flag", "targeting", "evaluation", "analytics"]
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
