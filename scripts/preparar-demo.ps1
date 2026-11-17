# Cria as flags que o gerador de trafego consulta, para os traces mostrarem a cadeia completa:
# evaluation, flag, targeting, auth, Redis, SQS e analytics.

$ErrorActionPreference = "Continue"
$ns = "togglemaster"
$pod = "preparador-demo"

$chaveB64 = kubectl get secret evaluation-service-runtime -n $ns -o jsonpath="{.data.service-api-key}"
$chave = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($chaveB64))

# o PowerShell 5.1 nao escapa aspas duplas ao passar argumento para executavel.
# o \" no texto final chega como " dentro do pod, o mesmo truque do validar-ambiente.ps1
$linhas = foreach ($f in @("nova-home", "checkout-v2")) {
    "curl -s -o /dev/null -w 'flag $f %{http_code} ' -X POST http://flag-service:8002/flags -H 'Authorization: Bearer $chave' -H 'Content-Type: application/json' -d '{\`"name\`":\`"$f\`",\`"description\`":\`"demonstracao\`",\`"is_enabled\`":true}'"
    "curl -s -o /dev/null -w 'regra $f %{http_code} ' -X POST http://targeting-service:8003/rules -H 'Authorization: Bearer $chave' -H 'Content-Type: application/json' -d '{\`"flag_name\`":\`"$f\`",\`"is_enabled\`":true,\`"rules\`":{\`"type\`":\`"PERCENTAGE\`",\`"value\`":50}}'"
}
$cmd = $linhas -join "; "

kubectl delete pod $pod -n $ns --ignore-not-found 2>$null | Out-Null
kubectl run $pod -n $ns --restart=Never --image=curlimages/curl:8.11.1 --command -- sh -c $cmd | Out-Null
kubectl wait --for=jsonpath="{.status.phase}"=Succeeded pod/$pod -n $ns --timeout=90s 2>$null | Out-Null
kubectl logs $pod -n $ns
kubectl delete pod $pod -n $ns 2>$null | Out-Null
Write-Host "(201 cria, 409 ja existia, os dois servem)"
