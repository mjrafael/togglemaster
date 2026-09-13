variable "name_prefix" {
  description = "prefixo aplicado ao nome dos recursos"
  type        = string
}

variable "vpc_id" {
  description = "VPC onde os bancos e o cache vivem"
  type        = string
}

variable "vpc_cidr" {
  description = "faixa liberada no security group dos bancos"
  type        = string
}

variable "private_subnet_ids" {
  description = "subnets sem saída pública, onde os dados ficam"
  type        = list(string)
}

variable "databases" {
  description = "microsserviços que têm banco relacional próprio"
  type        = list(string)
  default     = ["auth", "flag", "targeting"]
}

variable "db_instance_class" {
  description = "classe das instâncias RDS"
  type        = string
  default     = "db.t4g.micro"
}

variable "cache_node_type" {
  description = "tipo do nó do ElastiCache"
  type        = string
  default     = "cache.t4g.micro"
}

variable "oidc_provider_arn" {
  description = "provedor OIDC do cluster, usado pelas roles de IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "emissor OIDC sem o https://, usado na condição de confiança"
  type        = string
}

variable "service_namespace" {
  description = "namespace onde as service accounts vivem"
  type        = string
  default     = "togglemaster"
}
