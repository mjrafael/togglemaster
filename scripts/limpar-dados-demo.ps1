# Zera os dados de ensaio antes de gravar.
#
# Remove os eventos acumulados no DynamoDB e a flag criada em execuções anteriores,
# para que a demonstração comece do estado limpo e a contagem final feche com o número
# de avaliações feitas ao vivo.

$ErrorActionPreference = "Continue"

$tabela = "ToggleMasterAnalytics"
$namespace = "togglemaster"
$flag = "enable-new-dashboard"

Write-Host "removendo os eventos do DynamoDB"

# o gerador de trafego da fase 4 grava eventos sem parar, entao o total nunca chega a zero
$passada = 0
do {
    $passada++
    $ids = @(aws dynamodb scan --table-name $tabela --query "Items[].event_id.S" --output text 2>$null) -split "`t" | Where-Object { $_ }

    foreach ($id in $ids) {
        aws dynamodb delete-item --table-name $tabela --key "{\`"event_id\`":{\`"S\`":\`"$id\`"}}" 2>$null | Out-Null
    }

    $restantes = aws dynamodb scan --table-name $tabela --select COUNT --query "Count" --output text 2>$null
    Write-Host "  restantes: $restantes"
} while ([int]$restantes -gt 0 -and $passada -lt 3)

Write-Host "`nremovendo a flag de ensaios anteriores"

$masterKeyB64 = kubectl get secret auth-service-runtime -n $namespace -o jsonpath="{.data.master-key}"
$masterKey = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($masterKeyB64))

$pod = "limpeza-demo"
kubectl delete pod $pod -n $namespace --ignore-not-found 2>$null | Out-Null

$cmd = "K=`$(curl -s -X POST http://auth-service:8001/admin/keys -H 'Authorization: Bearer $masterKey' -H 'Content-Type: application/json' -d '{\""name\"":\""limpeza\""}' | sed 's/.*\""key\"":\""//;s/\"".*//'); curl -s -o /dev/null -w 'flag removida: %{http_code}\n' -X DELETE http://flag-service:8002/flags/$flag -H \""Authorization: Bearer `$K\"""

kubectl run $pod -n $namespace --restart=Never --image=curlimages/curl:8.11.1 --command -- sh -c $cmd 2>$null | Out-Null
kubectl wait --for=jsonpath="{.status.phase}"=Succeeded pod/$pod -n $namespace --timeout=120s 2>$null | Out-Null
kubectl logs $pod -n $namespace 2>$null
kubectl delete pod $pod -n $namespace 2>$null | Out-Null

Write-Host "`nestado limpo. a regra de targeting permanece e sera atualizada por PUT no teste."
Write-Host "itens no DynamoDB: $(aws dynamodb scan --table-name $tabela --select COUNT --query 'Count' --output text 2>$null)"
