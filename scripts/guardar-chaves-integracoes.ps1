# Guarda no AWS Secrets Manager as tres chaves das integracoes externas da Fase 4.
#
# Roda uma vez so, depois de criar as contas. O segredo fica fora do Terraform de proposito:
# o destroy diario apaga o que o Terraform cria, e as chaves precisam sobreviver a ele.
# As chaves sao digitadas aqui, mascaradas, e nunca passam pelo chat, pelo git ou pelo historico.
#
# uso: .\scripts\guardar-chaves-integracoes.ps1

$ErrorActionPreference = "Continue"

$nome = "togglemaster/observabilidade"
$regiao = "us-east-1"

function Ler-Segredo($rotulo) {
    $seguro = Read-Host -Prompt $rotulo -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# enter vazio mantem o valor ja gravado, para trocar uma chave sem redigitar as outras
$atual = $null
$texto = aws secretsmanager get-secret-value --secret-id $nome --region $regiao --query SecretString --output text 2>$null
if ($LASTEXITCODE -eq 0 -and $texto) { $atual = $texto | ConvertFrom-Json }

$newrelic = Ler-Segredo "New Relic, license key (INGEST - LICENSE) [enter mantem]"
$pagerduty = Ler-Segredo "PagerDuty, integration key do servico (Events API v2) [enter mantem]"
$discord = Ler-Segredo "Discord, URL do webhook do canal [enter mantem]"

if ($atual) {
    if (-not $newrelic) { $newrelic = $atual.newrelic_license_key }
    if (-not $pagerduty) { $pagerduty = $atual.pagerduty_integration_key }
    if (-not $discord) { $discord = $atual.discord_webhook_url }
}

if (-not $discord.StartsWith("https://discord.com/api/webhooks/")) {
    Write-Host "a URL do Discord nao tem o formato esperado (https://discord.com/api/webhooks/...)" -ForegroundColor Red
    exit 1
}

$json = @{
    newrelic_license_key      = $newrelic
    pagerduty_integration_key = $pagerduty
    discord_webhook_url       = $discord
} | ConvertTo-Json -Compress

# arquivo temporario porque o PowerShell 5.1 quebra as aspas do JSON ao passar como argumento
$tmp = New-TemporaryFile
try {
    [IO.File]::WriteAllText($tmp.FullName, $json)
    aws secretsmanager describe-secret --secret-id $nome --region $regiao 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        aws secretsmanager put-secret-value --secret-id $nome --region $regiao --secret-string "file://$($tmp.FullName)" | Out-Null
        Write-Host "segredo $nome atualizado"
    } else {
        aws secretsmanager create-secret --name $nome --region $regiao --secret-string "file://$($tmp.FullName)" `
            --description "chaves das integracoes de observabilidade do ToggleMaster" | Out-Null
        Write-Host "segredo $nome criado"
    }
} finally {
    Remove-Item $tmp.FullName -Force
}

Write-Host "conferindo as chaves gravadas (so os nomes):"
aws secretsmanager get-secret-value --secret-id $nome --region $regiao --query SecretString --output text |
    ConvertFrom-Json | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
