resource "aws_ecr_repository" "this" {
  for_each = toset(var.services)

  name = "${var.name_prefix}/${each.key}"

  # tag imutável porque o manifesto de GitOps aponta para o commit hash e precisa sempre significar o mesmo binário
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "${var.name_prefix}-${each.key}"
    Service = each.key
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "mantém apenas as ${var.max_images} imagens mais recentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
