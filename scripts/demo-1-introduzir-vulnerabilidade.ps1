# Primeira metade da demonstração de segurança do vídeo.
#
# Acrescenta ao flag-service uma dependência com vulnerabilidade CRÍTICA conhecida
# e envia para a main. O portão do pipeline deve barrar antes de publicar a imagem.
#
# PyYAML 5.3.1 carrega a CVE-2020-14343, nota 9.8, execução de código arbitrário
# em yaml.full_load. Corrigida na 5.4.

# o git escreve aviso de fim de linha em stderr, e com ErrorActionPreference Stop isso vira erro fatal
$ErrorActionPreference = "Continue"

$arquivo = "services/flag-service/requirements.txt"
$conteudo = Get-Content $arquivo -Raw

if ($conteudo -match "PyYAML==5\.3\.1") {
    Write-Host "a versao vulneravel ja esta no arquivo, nada a fazer"
    exit 0
}

# troca a versao existente ou acrescenta, para o ensaio poder rodar quantas vezes precisar
if ($conteudo -match "PyYAML==") {
    $novo = $conteudo -replace "PyYAML==[\d.]+", "PyYAML==5.3.1"
} else {
    $novo = $conteudo.TrimEnd() + "`nPyYAML==5.3.1`n"
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($arquivo, $novo, $utf8)

Write-Host "requirements.txt do flag-service agora:"
Get-Content $arquivo

git add $arquivo 2>&1 | Out-Null
git commit -m "usa pyyaml pra ler config do servico de flags"
git push origin main

Write-Host ""
Write-Host "commit enviado. o pipeline do flag-service vai comecar em alguns segundos."
Write-Host "acompanhe em https://github.com/mjrafael/togglemaster/actions"
Write-Host "o job que deve falhar e o 'SCA com Trivy', no passo 'portao de critico'."
