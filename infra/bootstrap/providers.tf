terraform {
  # 1.10 é o mínimo que aceita use_lockfile no backend s3, usado logo após o primeiro apply
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # valores literais porque o bloco backend é lido antes das variáveis existirem
  backend "s3" {
    bucket       = "togglemaster-tfstate-024532670257"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "ToggleMaster"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "rafael"
    }
  }
}
