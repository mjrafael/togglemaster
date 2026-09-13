variable "name_prefix" {
  description = "prefixo aplicado ao nome do cluster e das roles"
  type        = string
}

variable "private_subnet_ids" {
  description = "subnets onde os nós vivem, sem endereço público"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "subnets entregues ao control plane para criar balanceadores voltados para a internet"
  type        = list(string)
}

variable "node_instance_type" {
  description = "tipo das instâncias do node group"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "quantidade de nós em regime normal"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "mínimo de nós, zero permite desligar o cluster à noite sem destruir nada"
  type        = number
  default     = 0
}

variable "node_max_size" {
  description = "máximo de nós"
  type        = number
  default     = 3
}
