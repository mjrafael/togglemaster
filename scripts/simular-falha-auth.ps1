# Liga (ou desliga) o modo de falha do auth-service: ele continua vivo e com /health 200,
# mas passa a responder 500 em /validate. E a falha silenciosa do enunciado, usada na prova real.
#
# uso: .\scripts\simular-falha-auth.ps1             liga a falha
#      .\scripts\simular-falha-auth.ps1 -Desligar   desliga sem reiniciar
#
# A falha vive so na memoria do pod. O rollout restart do self-healing e o que a limpa.

param([switch]$Desligar)

$ErrorActionPreference = "Continue"
$ns = "togglemaster"
$pod = "simulador-de-falha"

$masterB64 = kubectl get secret auth-service-runtime -n $ns -o jsonpath="{.data.master-key}"
$master = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($masterB64))
$metodo = if ($Desligar) { "DELETE" } else { "POST" }

kubectl delete pod $pod -n $ns --ignore-not-found 2>$null | Out-Null
kubectl run $pod -n $ns --restart=Never --image=curlimages/curl:8.11.1 --command -- `
    curl -s -X $metodo http://auth-service:8001/admin/falha -H "Authorization: Bearer $master" | Out-Null
kubectl wait --for=jsonpath="{.status.phase}"=Succeeded pod/$pod -n $ns --timeout=90s 2>$null | Out-Null
$resposta = kubectl logs $pod -n $ns
kubectl delete pod $pod -n $ns 2>$null | Out-Null

Write-Host "resposta do auth-service: $resposta"
Write-Host "horario: $(Get-Date -Format 'HH:mm:ss')"
if (-not $Desligar) {
    Write-Host ""
    Write-Host "o que deve acontecer agora:"
    Write-Host "  ~1 min   painel 'Erro 5xx no auth-service' acima de 5%, alerta em Pending no Grafana"
    Write-Host "  ~2-3 min alerta em Firing, incidente no PagerDuty, mensagem no Discord"
    Write-Host "  logo depois, o runbook reinicia o auth-service. para acompanhar, em outro terminal:"
    Write-Host "    kubectl get pods -n togglemaster -l app=auth-service -w"
    Write-Host "    kubectl logs -n observabilidade deploy/runbook-self-healing -f"
}
