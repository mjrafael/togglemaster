# Instala o ArgoCD no cluster e registra as Applications que apontam para o repositório de GitOps.
# Usa o manifesto oficial em vez do chart Helm porque o Helm 4 desta máquina ainda não é
# suportado por parte dos charts, e a instalação por manifesto não depende disso.

$ErrorActionPreference = "Stop"

$versao = "v3.0.6"
$manifesto = "https://raw.githubusercontent.com/argoproj/argo-cd/$versao/manifests/install.yaml"

Write-Host "criando o namespace argocd"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

Write-Host "instalando o ArgoCD $versao"
kubectl apply -n argocd -f $manifesto

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
