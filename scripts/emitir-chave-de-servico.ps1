# O evaluation-service autentica no flag-service e no targeting-service com uma chave
# de API emitida pelo auth-service. Ela só pode existir depois que o auth estiver de pé,
# por isso este passo é separado do bootstrap.
#
# A chave é criada dentro do cluster, gravada direto no secret, e não aparece na tela.

$ErrorActionPreference = "Stop"

$namespace = "togglemaster"
$pod = "emissor-de-chave"

$masterKeyB64 = kubectl get secret auth-service-runtime -n $namespace -o jsonpath="{.data.master-key}"
$masterKey = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($masterKeyB64))

kubectl delete pod $pod -n $namespace --ignore-not-found | Out-Null

Write-Host "pedindo uma chave ao auth-service"

$corpo = '{\"name\":\"evaluation-service\"}'
kubectl run $pod -n $namespace --restart=Never --image=curlimages/curl:8.11.1 --command -- `
    curl -s -X POST http://auth-service:8001/admin/keys `
    -H "Authorization: Bearer $masterKey" `
    -H "Content-Type: application/json" `
    -d $corpo | Out-Null

kubectl wait --for=jsonpath="{.status.phase}"=Succeeded pod/$pod -n $namespace --timeout=120s | Out-Null

$resposta = kubectl logs $pod -n $namespace
kubectl delete pod $pod -n $namespace | Out-Null

$chave = ($resposta | ConvertFrom-Json).key

if (-not $chave) {
    Write-Host "resposta inesperada do auth-service:"
    Write-Host $resposta
    exit 1
}

Write-Host "chave emitida, prefixo $($chave.Substring(0, 10))..."

kubectl create secret generic evaluation-service-runtime `
    --namespace $namespace `
    --from-literal=service-api-key=$chave `
    --dry-run=client -o yaml | kubectl apply -f -

Write-Host "reiniciando o evaluation-service para ele ler a chave nova"
kubectl rollout restart deployment/evaluation-service -n $namespace
kubectl rollout status deployment/evaluation-service -n $namespace --timeout=180s
