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

$newrelic = Ler-Segredo "New Relic, license key (INGEST - LICENSE)"
$pagerduty = Ler-Segredo "PagerDuty, integration key do servico (Events API v2)"
$discord = Ler-Segredo "Discord, URL do webhook do canal"

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
