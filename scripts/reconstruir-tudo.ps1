# Reconstrói o ambiente inteiro a partir de uma conta vazia.
#
# Serve para dois propósitos: provar que a entrega é reproduzível, e devolver o
# laboratório ao ar depois de um destroy. Não substitui o terraform apply, ele é o
# primeiro passo aqui dentro.
#
# Tempo total: 45 a 60 minutos, quase todo esperando a AWS.

$ErrorActionPreference = "Continue"

function Etapa($numero, $titulo) {
    Write-Host ""
    Write-Host "=============================================================="
    Write-Host " etapa $numero : $titulo"
    Write-Host "=============================================================="
}

Etapa 1 "infraestrutura com terraform, de 20 a 30 minutos"
terraform -chdir=infra init -no-color
terraform -chdir=infra apply -auto-approve -no-color

if ($LASTEXITCODE -ne 0) {
    Write-Host "o apply falhou, nao adianta seguir"
    exit 1
}

Etapa 2 "endpoints reais no configmap do repositorio de gitops"
& "$PSScriptRoot\atualizar-config-gitops.ps1"

Etapa 3 "secrets do cluster, lidos do secrets manager"
& "$PSScriptRoot\bootstrap-cluster.ps1"

Etapa 4 "tabelas dos tres bancos, por job dentro da vpc"
& "$PSScriptRoot\criar-tabelas.ps1"

Etapa 5 "argocd e as applications"
& "$PSScriptRoot\instalar-argocd.ps1"

Etapa 6 "republicar as imagens"
Write-Host "os repositorios ECR nasceram vazios, entao os cinco pipelines precisam rodar."
Write-Host "dispare todos com:"
Write-Host ""
Write-Host '  foreach ($s in @("auth-service","flag-service","targeting-service","evaluation-service","analytics-service")) {'
Write-Host '      gh workflow run "$s.yml" -R mjrafael/togglemaster --ref main'
Write-Host '  }'
Write-Host ""
Write-Host "espere os cinco terminarem antes da etapa 7."

Etapa 7 "chave de servico do evaluation"
Write-Host "rode depois que os pods estiverem de pe:"
Write-Host "  .\scripts\emitir-chave-de-servico.ps1"
Write-Host "  .\scripts\testar-fluxo.ps1"
