# Instala o ArgoCD no cluster e registra as Applications que apontam para o repositório de GitOps.
# Usa o manifesto oficial em vez do chart Helm porque o Helm 4 desta máquina ainda não é
# suportado por parte dos charts, e a instalação por manifesto não depende disso.

$ErrorActionPreference = "Stop"

$versao = "v3.0.6"
$manifesto = "https://raw.githubusercontent.com/argoproj/argo-cd/$versao/manifests/install.yaml"

Write-Host "criando o namespace argocd"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

Write-Host "instalando o ArgoCD $versao"

# baixa antes de aplicar: o kubectl puxando direto da URL falha quando a rede oscila,
# e o erro que ele devolve fala de CRD ausente, que manda investigar o lado errado
# curl.exe em vez de Invoke-WebRequest: o PowerShell 5.1 negocia TLS 1.0 por padrão e o GitHub recusa
$local = Join-Path $env:TEMP "argocd-$versao.yaml"
if (-not (Test-Path $local) -or (Get-Item $local).Length -lt 100000) {
    # -4 força IPv4: a rota IPv6 até o GitHub derruba a conexão nesta rede
    curl.exe -4 -sSL --retry 3 --max-time 180 -o $local $manifesto
}

if (-not (Test-Path $local) -or (Get-Item $local).Length -lt 100000) {
    Write-Host "o download do manifesto falhou"
    exit 1
}

# server-side porque o manifesto passa do limite de anotação do apply tradicional
kubectl apply -n argocd --server-side -f $local

Write-Host "`naguardando o servidor ficar pronto (pode levar 3 minutos)"
kubectl wait --for=condition=available --timeout=420s deployment/argocd-server -n argocd

Write-Host "`nregistrando as Applications"
kubectl apply -f C:\vs_code_projects\fiap\togglemaster-gitops\argocd\applications.yaml

Write-Host "`npods do argocd"
kubectl get pods -n argocd

Write-Host "`napplications"
kubectl get applications -n argocd

Write-Host "`nsenha inicial do usuario admin:"
$senha = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($senha))

Write-Host "`npara abrir a interface, rode em outro terminal:"
Write-Host "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
Write-Host "e acesse https://localhost:8080 com o usuario admin"
