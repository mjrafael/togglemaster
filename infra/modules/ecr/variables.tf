variable "name_prefix" {
  description = "prefixo aplicado ao nome de todos os repositórios"
  type        = string
}

variable "services" {
  description = "microsserviços do ToggleMaster, um repositório por serviço"
  type        = list(string)
}

variable "max_images" {
  description = "quantidade de imagens mantidas antes da expiração automática"
  type        = number
  default     = 10
}
