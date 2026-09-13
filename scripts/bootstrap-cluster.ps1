# Cria no cluster os secrets que os manifestos referenciam.
# As senhas saem do Secrets Manager e nunca passam por arquivo do repositório.

$ErrorActionPreference = "Stop"

$cluster = "togglemaster-dev-eks"
$region = "us-east-1"
$namespace = "togglemaster"

Write-Host "configurando o kubeconfig"
aws eks update-kubeconfig --name $cluster --region $region | Out-Null

Write-Host "criando o namespace"
kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f -

$servicos = @{
    "auth-service"      = "auth"
    "flag-service"      = "flag"
    "targeting-service" = "targeting"
}

foreach ($servico in $servicos.Keys) {
    $banco = $servicos[$servico]
    Write-Host "montando a credencial de $servico"

    $json = aws secretsmanager get-secret-value `
        --secret-id "togglemaster-dev/$banco/database" `
        --query SecretString --output text | ConvertFrom-Json

    $url = "postgres://$($json.username):$($json.password)@$($json.host):$($json.port)/$($json.dbname)?sslmode=require"

    kubectl create secret generic "$servico-db" `
        --namespace $namespace `
        --from-literal=url=$url `
        --dry-run=client -o yaml | kubectl apply -f -
}

# a master key do auth-service nasce aqui e não é guardada em lugar nenhum do repositório
$masterKey = -join ((1..48) | ForEach-Object { "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[(Get-Random -Maximum 62)] })

kubectl create secret generic auth-service-runtime `
    --namespace $namespace `
    --from-literal=master-key=$masterKey `
    --dry-run=client -o yaml | kubectl apply -f -

# o evaluation precisa de uma chave de API emitida pelo auth-service, que só existe depois que ele sobe.
# nasce vazia e é substituída pelo scripts/emitir-chave-de-servico.ps1
kubectl create secret generic evaluation-service-runtime `
    --namespace $namespace `
    --from-literal=service-api-key=pendente `
    --dry-run=client -o yaml | kubectl apply -f -

Write-Host "`nsecrets no namespace $namespace"
kubectl get secrets -n $namespace
