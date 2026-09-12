variable "name_prefix" {
  description = "prefixo aplicado ao nome de todos os recursos da rede"
  type        = string
}

variable "vpc_cidr" {
  description = "faixa de endereços da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "faixas das subnets públicas, uma por AZ"
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "private_subnet_cidrs" {
  description = "faixas das subnets privadas, uma por AZ"
  type        = list(string)
  default     = ["10.0.128.0/20", "10.0.144.0/20"]
}
