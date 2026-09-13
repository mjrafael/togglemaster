# Reescreve o ConfigMap do repositório de GitOps com os valores reais da infraestrutura.
#
# O endpoint do ElastiCache e a URL da fila SQS carregam identificadores que a AWS gera,
# e mudam se a infra for recriada do zero. Escrever isso à mão no manifesto é dívida:
# funciona hoje e quebra no próximo destroy. Este script lê os outputs do Terraform
# e regrava o ConfigMap, mantendo o git como fonte da verdade.

$ErrorActionPreference = "Continue"

$gitops = "C:\vs_code_projects\fiap\togglemaster-gitops"
$regiao = "us-east-1"

$cache = terraform -chdir=infra output -raw cache_endpoint
$fila = terraform -chdir=infra output -raw queue_url

if (-not $cache -or -not $fila) {
    Write-Host "nao consegui ler os outputs do terraform"
    exit 1
}

Write-Host "cache : $cache"
Write-Host "fila  : $fila"

$configmap = @"
apiVersion: v1
kind: ConfigMap
metadata:
  name: togglemaster-config
  namespace: togglemaster
data:
  aws-region: $regiao
  sqs-url: $fila
  dynamodb-table: ToggleMasterAnalytics
  redis-url: redis://${cache}:6379
"@

$utf8 = New-Object System.Text.UTF8Encoding($false)

foreach ($servico in @("evaluation-service", "analytics-service")) {
    $destino = "$gitops\apps\$servico\configmap.yaml"
    [System.IO.File]::WriteAllText($destino, $configmap.Replace("`r`n", "`n") + "`n", $utf8)
    Write-Host "escrito $destino"
}

git -C $gitops add -A 2>&1 | Out-Null
$mudou = git -C $gitops diff --cached --quiet; $LASTEXITCODE

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nnada mudou, os endpoints sao os mesmos"
    exit 0
}

git -C $gitops -c user.name="Rafael Martins Junior" -c user.email="mj.rafael@outlook.com" `
    commit -m "atualiza os endpoints de cache e fila no configmap"
git -C $gitops push origin main

Write-Host "`nconfigmap atualizado e enviado"
