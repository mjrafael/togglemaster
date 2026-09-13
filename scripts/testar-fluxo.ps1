# Exercita o caminho completo do ToggleMaster dentro do cluster.
# Serve como ensaio da demonstração do vídeo.

$ErrorActionPreference = "Stop"

$namespace = "togglemaster"
$pod = "cliente-de-teste"
$flag = "enable-new-dashboard"

function Invocar($descricao, $comando) {
    Write-Host "`n### $descricao"
    kubectl delete pod $pod -n $namespace --ignore-not-found | Out-Null
    kubectl run $pod -n $namespace --restart=Never --image=curlimages/curl:8.11.1 --command -- sh -c $comando | Out-Null
    kubectl wait --for=jsonpath="{.status.phase}"=Succeeded pod/$pod -n $namespace --timeout=120s | Out-Null
    $saida = kubectl logs $pod -n $namespace
    kubectl delete pod $pod -n $namespace | Out-Null
    Write-Host $saida
    return $saida
}

$masterKeyB64 = kubectl get secret auth-service-runtime -n $namespace -o jsonpath="{.data.master-key}"
$masterKey = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($masterKeyB64))

$r = Invocar "emitindo uma chave de API para o teste" @"
curl -s -X POST http://auth-service:8001/admin/keys -H 'Authorization: Bearer $masterKey' -H 'Content-Type: application/json' -d '{\"name\":\"teste-manual\"}'
"@

$chave = ($r | ConvertFrom-Json).key

Invocar "criando a flag $flag no flag-service" @"
curl -s -X POST http://flag-service:8002/flags -H 'Authorization: Bearer $chave' -H 'Content-Type: application/json' -d '{\"name\":\"$flag\",\"description\":\"novo dashboard\",\"is_enabled\":true}'
"@ | Out-Null

Invocar "criando a regra de 50 por cento no targeting-service" @"
curl -s -X POST http://targeting-service:8003/rules -H 'Authorization: Bearer $chave' -H 'Content-Type: application/json' -d '{\"flag_name\":\"$flag\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":50}}'
"@ | Out-Null

# um curl por usuário em vez de laço: o laço do shell se perde na passagem de argumentos pelo PowerShell
$usuarios = @("user-1", "user-2", "user-abc", "user-xyz", "user-42", "user-99")
$chamadas = ($usuarios | ForEach-Object { "curl -s 'http://evaluation-service:8004/evaluate?user_id=$_&flag_name=$flag'; echo" }) -join "; "

Invocar "avaliando seis usuarios diferentes no evaluation-service" $chamadas | Out-Null

Write-Host "`n### esperando o analytics-service consumir a fila"
Start-Sleep -Seconds 25

Write-Host "`n### itens gravados no DynamoDB"
aws dynamodb scan --table-name ToggleMasterAnalytics --query "Items[].{flag:flag_name.S,user:user_id.S,resultado:result.BOOL}" --output table
