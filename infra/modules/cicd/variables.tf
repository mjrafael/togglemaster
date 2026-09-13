variable "name_prefix" {
  description = "prefixo aplicado ao nome da role"
  type        = string
}

variable "github_repository" {
  description = "repositório autorizado a assumir a role, no formato dono/nome"
  type        = string
}

variable "ecr_repository_arns" {
  description = "repositórios onde o pipeline pode enviar imagem"
  type        = list(string)
}

variable "github_branch" {
  description = "unica branch autorizada a assumir a role"
  type        = string
  default     = "main"
}