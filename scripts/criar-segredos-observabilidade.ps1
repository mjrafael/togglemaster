# Cria no namespace observabilidade os secrets que a stack da Fase 4 referencia.
#
# As chaves externas saem do Secrets Manager (gravadas pelo guardar-chaves-integracoes.ps1).
# O token do runbook e a senha do Grafana nascem aqui a cada reconstrucao e nao ficam em lugar nenhum.
# Se o segredo externo ainda nao existir, entra um valor marcador: a stack sobe, so as integracoes falham.

# Continue: no PowerShell 5.1, stderr de comando nativo redirecionado vira erro fatal com Stop
$ErrorActionPreference = "Continue"

$ns = "observabilidade"
$regiao = "us-east-1"

function Aleatorio($tamanho) {
    -join ((1..$tamanho) | ForEach-Object { "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"[(Get-Random -Maximum 57)] })
}

function Aplicar-Secret($nome, $pares) {
    $argumentos = @("create", "secret", "generic", $nome, "--namespace", $ns, "--dry-run=client", "-o", "yaml")
    foreach ($k in $pares.Keys) { $argumentos += "--from-literal=$k=$($pares[$k])" }
    & kubectl @argumentos | kubectl apply -f - | Out-Null
    Write-Host "  secret $nome aplicado"
}

kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - | Out-Null

$chaves = $null
$bruto = aws secretsmanager get-secret-value --secret-id togglemaster/observabilidade --region $regiao --query SecretString --output text 2>$null
if ($LASTEXITCODE -eq 0 -and $bruto) {
    $chaves = $bruto | ConvertFrom-Json
    Write-Host "chaves das integracoes lidas do Secrets Manager"
} else {
    Write-Host "segredo togglemaster/observabilidade nao encontrado. rode o guardar-chaves-integracoes.ps1" -ForegroundColor Yellow
    Write-Host "seguindo com valores marcadores: New Relic, PagerDuty e Discord nao vao receber nada" -ForegroundColor Yellow
    $chaves = [pscustomobject]@{
        newrelic_license_key      = "pendente"
        pagerduty_integration_key = "pendente"
        discord_webhook_url       = "https://discord.com/api/webhooks/0/pendente"
    }
}

Aplicar-Secret "newrelic" @{ "license-key" = $chaves.newrelic_license_key }

# se o secret ja existe, reaproveita o token e a senha: trocar a cada execucao derrubaria o runbook
$tokenB64 = kubectl get secret grafana-integracoes -n $ns -o jsonpath="{.data.RUNBOOK_TOKEN}" 2>$null
$token = if ($tokenB64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($tokenB64)) } else { Aleatorio 40 }

Aplicar-Secret "grafana-integracoes" @{
    "PAGERDUTY_INTEGRATION_KEY" = $chaves.pagerduty_integration_key
    "DISCORD_WEBHOOK_URL"       = $chaves.discord_webhook_url
    "RUNBOOK_TOKEN"             = $token
}

$senhaB64 = kubectl get secret grafana-admin -n $ns -o jsonpath="{.data.admin-password}" 2>$null
$senha = if ($senhaB64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($senhaB64)) } else { Aleatorio 24 }

Aplicar-Secret "grafana-admin" @{ "admin-user" = "admin"; "admin-password" = $senha }
