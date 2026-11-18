# Reconstrói o ambiente inteiro a partir de uma conta vazia e valida o resultado.
#
# Um comando só, do terraform apply até a conferência funcional da cadeia de dados.
# Tempo total: 45 a 60 minutos, quase todo aguardando a AWS.
#
# uso: .\scripts\reconstruir-tudo.ps1

$ErrorActionPreference = "Continue"

$repo = "mjrafael/togglemaster"
$servicos = @("auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service")
$inicio = Get-Date

function Etapa($numero, $titulo) {
    $decorrido = [math]::Round(((Get-Date) - $script:inicio).TotalMinutes, 1)
    Write-Host ""
    Write-Host "=============================================================="
    Write-Host " etapa $numero : $titulo"
    Write-Host " decorrido: $decorrido min"
    Write-Host "=============================================================="
}

Etapa 1 "infraestrutura com terraform, de 20 a 30 minutos"
terraform -chdir=infra init -no-color
terraform -chdir=infra apply -auto-approve -no-color

if ($LASTEXITCODE -ne 0) {
    Write-Host "`no apply falhou. nao adianta seguir." -ForegroundColor Red
    exit 1
}

Etapa 2 "endpoints reais no configmap do repositorio de gitops"
& "$PSScriptRoot\atualizar-config-gitops.ps1"

Etapa 3 "secrets do cluster, lidos do secrets manager"
& "$PSScriptRoot\bootstrap-cluster.ps1"

Etapa "3b" "secrets da observabilidade: New Relic, PagerDuty, Discord, runbook e Grafana"
& "$PSScriptRoot\criar-segredos-observabilidade.ps1"

Etapa 4 "tabelas dos tres bancos, por job dentro da vpc"
& "$PSScriptRoot\criar-tabelas.ps1"

Etapa 5 "argocd e as applications"
& "$PSScriptRoot\instalar-argocd.ps1"

Etapa 6 "publicando as imagens, os repositorios ECR nascem vazios"
foreach ($s in $servicos) {
    gh workflow run "$s.yml" -R $repo --ref main 2>&1 | Out-Null
    Write-Host "  disparado: $s"
}

Write-Host "`naguardando os cinco pipelines"
Start-Sleep -Seconds 20

for ($i = 0; $i -lt 40; $i++) {
    $runs = gh run list -R $repo --limit 5 --json name,status,conclusion 2>$null | ConvertFrom-Json
    $pendentes = @($runs | Where-Object { $_.status -ne "completed" }).Count

    $resumo = ($runs | ForEach-Object { "$($_.name)=$(if ($_.status -eq 'completed') { $_.conclusion } else { $_.status })" }) -join "  "
    Write-Host "  $resumo"

    if ($pendentes -eq 0) { break }
    Start-Sleep -Seconds 25
}

$falhou = @($runs | Where-Object { $_.conclusion -ne "success" })
if ($falhou.Count -gt 0) {
    Write-Host "`nalgum pipeline nao passou. confira antes de seguir." -ForegroundColor Red
}

Etapa 7 "sincronizando o argocd e subindo os pods"
foreach ($s in $servicos) {
    kubectl patch application $s -n argocd --type merge -p '{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\"}}}' 2>$null | Out-Null
}
Start-Sleep -Seconds 20
foreach ($s in $servicos) {
    kubectl rollout status deployment/$s -n togglemaster --timeout=300s 2>&1 | Select-Object -Last 1
}

Etapa 8 "chave de servico do evaluation"
& "$PSScriptRoot\emitir-chave-de-servico.ps1"

# sem limpeza aqui: o apply recria DynamoDB e RDS vazios, e o gerador de trafego ja escreve desde a etapa 7

Etapa "9b" "flags da demonstracao e stack de observabilidade"
& "$PSScriptRoot\preparar-demo.ps1"
foreach ($a in @("kube-prometheus-stack", "loki", "otel-collector", "observabilidade-config")) {
    kubectl patch application $a -n argocd --type merge -p '{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\"}}}' 2>$null | Out-Null
}
foreach ($d in @("deployment/grafana", "deployment/runbook-self-healing", "statefulset/loki", "daemonset/otel-collector-agent")) {
    kubectl rollout status $d -n observabilidade --timeout=420s 2>&1 | Select-Object -Last 1
}

Etapa 10 "validacao completa"
& "$PSScriptRoot\validar-ambiente.ps1"
$resultado = $LASTEXITCODE

$decorrido = [math]::Round(((Get-Date) - $inicio).TotalMinutes, 1)
Write-Host ""
Write-Host "tempo total: $decorrido minutos"

Write-Host "`npara abrir o Grafana, em outro terminal:"
Write-Host "  kubectl port-forward svc/grafana -n observabilidade 3000:80"
Write-Host "e acesse http://localhost:3000 com o usuario admin e a senha:"
$g = kubectl -n observabilidade get secret grafana-admin -o jsonpath="{.data.admin-password}" 2>$null
if ($g) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($g)) }

if ($resultado -eq 0) {
    Write-Host "`nambiente pronto. para abrir o ArgoCD, em outro terminal:"
    Write-Host "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    Write-Host "`nsenha do admin:"
    $s = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>$null
    if ($s) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) }
} else {
    Write-Host "`na validacao apontou problemas. nao grave antes de resolver." -ForegroundColor Red
}

exit $resultado
