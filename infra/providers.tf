terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    # usado só para ler o certificado do emissor OIDC do cluster e habilitar IRSA
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # gera as senhas dos bancos, que nunca passam por arquivo do repositório
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # mesmo bucket do bootstrap, chave diferente: o destroy do laboratório não alcança o state do bucket
  backend "s3" {
    bucket       = "togglemaster-tfstate-024532670257"
    key          = "dev/terraform.tfstate"
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
