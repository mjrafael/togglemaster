resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "database" {
  name   = "${var.name_prefix}-database"
  vpc_id = var.vpc_id

  ingress {
    description = "postgres de dentro da vpc"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_security_group" "cache" {
  name   = "${var.name_prefix}-cache"
  vpc_id = var.vpc_id

  ingress {
    description = "redis de dentro da vpc"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "random_password" "db" {
  for_each = toset(var.databases)

  length  = 24
  special = false
}

resource "aws_db_instance" "main" {
  for_each = toset(var.databases)

  identifier     = "${var.name_prefix}-${each.key}"
  engine         = "postgres"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_encrypted = true

  # sufixo _db porque "flag" sozinho é palavra reservada do PostgreSQL e o RDS recusa
  db_name  = "${each.key}_db"
  username = "${each.key}_app"
  password = random_password.db[each.key].result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false

  # laboratório: sem retenção e sem snapshot final, o destroy do fim da sessão precisa ser rápido e barato
  backup_retention_period = 0
  skip_final_snapshot     = true

  tags = {
    Service = each.key
  }
}

# a senha nunca existe em arquivo do repositório: o Terraform gera, entrega ao RDS e guarda aqui
resource "aws_secretsmanager_secret" "db" {
  for_each = toset(var.databases)

  name                    = "${var.name_prefix}/${each.key}/database"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  for_each = toset(var.databases)

  secret_id = aws_secretsmanager_secret.db[each.key].id

  secret_string = jsonencode({
    host     = aws_db_instance.main[each.key].address
    port     = aws_db_instance.main[each.key].port
    dbname   = "${each.key}_db"
    username = "${each.key}_app"
    password = random_password.db[each.key].result
  })
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.name_prefix}-cache"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_cluster" "main" {
  cluster_id      = "${var.name_prefix}-cache"
  engine          = "redis"
  node_type       = var.cache_node_type
  num_cache_nodes = 1

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.cache.id]
}

# nome exigido literalmente pelo enunciado, fora da convenção togglemaster-dev-*
resource "aws_dynamodb_table" "analytics" {
  name         = "ToggleMasterAnalytics"
  billing_mode = "PAY_PER_REQUEST"

  # event_id é a chave que o analytics-service grava, definida no código fornecido pela FIAP
  hash_key = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }
}

resource "aws_sqs_queue" "evaluations" {
  name                      = "${var.name_prefix}-evaluations"
  message_retention_seconds = 86400
}

# IRSA: a permissão fica na service account do pod, não no nó.
# Sem isso, todo pod do cluster herdaria o acesso a SQS e DynamoDB pela role da instância.
data "aws_iam_policy_document" "irsa_assume" {
  for_each = toset(["evaluation-service", "analytics-service"])

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.service_namespace}:${each.key}"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = data.aws_iam_policy_document.irsa_assume

  name               = "${var.name_prefix}-${each.key}"
  assume_role_policy = each.value.json
}

# o evaluation apenas produz na fila, nunca lê
data "aws_iam_policy_document" "evaluation" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
    resources = [aws_sqs_queue.evaluations.arn]
  }
}

resource "aws_iam_role_policy" "evaluation" {
  name   = "sqs-produce"
  role   = aws_iam_role.irsa["evaluation-service"].id
  policy = data.aws_iam_policy_document.evaluation.json
}

# o analytics consome da fila e grava na tabela, e não precisa de mais nada
data "aws_iam_policy_document" "analytics" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = [aws_sqs_queue.evaluations.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.analytics.arn]
  }
}

resource "aws_iam_role_policy" "analytics" {
  name   = "sqs-consume-dynamodb-write"
  role   = aws_iam_role.irsa["analytics-service"].id
  policy = data.aws_iam_policy_document.analytics.json
}
