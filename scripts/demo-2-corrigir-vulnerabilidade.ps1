# Segunda metade da demonstração de segurança do vídeo.
#
# Sobe o PyYAML para a versão corrigida e envia para a main.
# O mesmo pipeline que barrou agora passa, publica a imagem no ECR
# e reescreve a tag no repositório de GitOps.

# o git escreve aviso de fim de linha em stderr, e com ErrorActionPreference Stop isso vira erro fatal
$ErrorActionPreference = "Continue"

$arquivo = "services/flag-service/requirements.txt"
$conteudo = Get-Content $arquivo -Raw

if ($conteudo -notmatch "PyYAML==5\.3\.1") {
    Write-Host "a versao vulneravel nao esta no arquivo, rode antes o demo-1"
    exit 1
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($arquivo, $conteudo.Replace("PyYAML==5.3.1", "PyYAML==6.0.2"), $utf8)

Write-Host "requirements.txt do flag-service agora:"
Get-Content $arquivo

git add $arquivo 2>&1 | Out-Null
git commit -m "sobe o pyyaml pra versao corrigida"
git push origin main

Write-Host ""
Write-Host "commit enviado. o mesmo pipeline agora deve passar inteiro."
Write-Host "no fim dele, confira:"
Write-Host "  a imagem nova no ECR"
Write-Host "  o commit automatico no repositorio togglemaster-gitops"
Write-Host "  o ArgoCD sincronizando o flag-service"
