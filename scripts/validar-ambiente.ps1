# Valida o ambiente inteiro, do cluster até a cadeia de dados.
#
# Pode rodar sozinho a qualquer momento. É chamado no fim do reconstruir-tudo.ps1.
# Sai com código 1 se qualquer verificação falhar, para poder ser usado em automação.

$ErrorActionPreference = "Continue"

$ns = "togglemaster"
$pod = "validador"
$flag = "validacao-automatica"
$fila = "https://sqs.us-east-1.amazonaws.com/024532670257/togglemaster-dev-evaluations"

$falhas = @()
$total = 0

function Verificar($descricao, $condicao, $detalhe = "") {
    $script:total++
    if ($condicao) {
        Write-Host ("  [ ok ] {0}" -f $descricao) -ForegroundColor Green
    } else {
        Write-Host ("  [FALHA] {0}  {1}" -f $descricao, $detalhe) -ForegroundColor Red
        $script:falhas += $descricao
    }
}

function NoCluster($cmd) {
    kubectl delete pod $pod -n $ns --ignore-not-found 2>$null | Out-Null
    kubectl run $pod -n $ns --restart=Never --image=curlimages/curl:8.11.1 --command -- sh -c $cmd 2>$null | Out-Null
    kubectl wait --for=jsonpath="{.status.phase}"=Succeeded pod/$pod -n $ns --timeout=150s 2>$null | Out-Null
    $saida = kubectl logs $pod -n $ns 2>$null
    kubectl delete pod $pod -n $ns 2>$null | Out-Null
    return ($saida -join "`n")
}

Write-Host ""
Write-Host "=============================================================="
Write-Host " validacao do ambiente ToggleMaster"
Write-Host "=============================================================="

# ---------------------------------------------------------------- infra
Write-Host "`nINFRAESTRUTURA"

$cluster = aws eks describe-cluster --name togglemaster-dev-eks --query "cluster.status" --output text 2>$null
Verificar "cluster EKS ativo" ($cluster -eq "ACTIVE") "status: $cluster"

$nos = (kubectl get nodes --no-headers 2>$null | Where-Object { $_ -match "\sReady\s" }).Count
Verificar "nos do cluster prontos" ($nos -ge 2) "encontrados: $nos"

$rds = aws rds describe-db-instances --query "length(DBInstances[?DBInstanceStatus=='available'])" --output text 2>$null
Verificar "tres RDS disponiveis" ($rds -eq "3") "disponiveis: $rds"

$cache = aws elasticache describe-cache-clusters --query "length(CacheClusters[?CacheClusterStatus=='available'])" --output text 2>$null
Verificar "ElastiCache disponivel" ($cache -eq "1") "disponiveis: $cache"

$tabela = aws dynamodb describe-table --table-name ToggleMasterAnalytics --query "Table.TableStatus" --output text 2>$null
Verificar "tabela DynamoDB ativa" ($tabela -eq "ACTIVE") "status: $tabela"

$ecr = aws ecr describe-repositories --query "length(repositories)" --output text 2>$null
Verificar "cinco repositorios ECR" ($ecr -eq "5") "encontrados: $ecr"

# ---------------------------------------------------------------- imagens
Write-Host "`nIMAGENS PUBLICADAS"

foreach ($s in @("auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service")) {
    $tags = aws ecr list-images --repository-name "togglemaster-dev/$s" --query "length(imageIds)" --output text 2>$null
    Verificar "$s tem imagem no ECR" ([int]$tags -gt 0) "tags: $tags"
}

# ---------------------------------------------------------------- cluster
Write-Host "`nCARGAS NO CLUSTER"

foreach ($s in @("auth-service", "flag-service", "targeting-service", "evaluation-service", "analytics-service")) {
    $pronto = kubectl get deployment $s -n $ns -o jsonpath="{.status.readyReplicas}" 2>$null
    Verificar "$s com pod pronto" ($pronto -eq "1") "readyReplicas: $pronto"
}

$apps = kubectl get applications -n argocd --no-headers 2>$null
$saudaveis = ($apps | Where-Object { $_ -match "^(auth|flag|targeting|evaluation|analytics)-service\s+Synced\s+Healthy" }).Count
Verificar "cinco Applications dos servicos Synced e Healthy" ($saudaveis -eq 5) "saudaveis: $saudaveis"

# ---------------------------------------------------------------- funcional
Write-Host "`nVERIFICACAO FUNCIONAL"

$saude = NoCluster "for p in auth-service:8001 flag-service:8002 targeting-service:8003 evaluation-service:8004 analytics-service:8005; do curl -s -o /dev/null -w '%{http_code} ' --max-time 10 http://`$p/health; done"
$ok200 = ([regex]::Matches($saude, "200")).Count
Verificar "health check dos cinco servicos" ($ok200 -eq 5) "respostas 200: $ok200"

$masterB64 = kubectl get secret auth-service-runtime -n $ns -o jsonpath="{.data.master-key}" 2>$null
if ($masterB64) {
    $master = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($masterB64))

    $r = NoCluster "curl -s -X POST http://auth-service:8001/admin/keys -H 'Authorization: Bearer $master' -H 'Content-Type: application/json' -d '{\""name\"":\""validacao\""}'"
    $chave = if ($r -match '"key":"([^"]+)"') { $matches[1] } else { $null }
    Verificar "auth-service emite chave de API" ($null -ne $chave)

    if ($chave) {
        $r = NoCluster "curl -s -o /dev/null -w '%{http_code}' http://flag-service:8002/flags"
        Verificar "flag-service recusa acesso sem chave" ($r -match "401") "codigo: $r"

        $r = NoCluster "curl -s -o /dev/null -w '%{http_code}' http://flag-service:8002/flags -H 'Authorization: Bearer $chave'"
        Verificar "flag-service aceita chave valida" ($r -match "200") "codigo: $r"

        NoCluster "curl -s -o /dev/null -X DELETE http://flag-service:8002/flags/$flag -H 'Authorization: Bearer $chave'" | Out-Null

        $r = NoCluster "curl -s -X POST http://flag-service:8002/flags -H 'Authorization: Bearer $chave' -H 'Content-Type: application/json' -d '{\""name\"":\""$flag\"",\""description\"":\""validacao\"",\""is_enabled\"":true}'"
        Verificar "flag-service cria flag no RDS" ($r -match $flag)

        $r = NoCluster "curl -sf -X POST http://targeting-service:8003/rules -H 'Authorization: Bearer $chave' -H 'Content-Type: application/json' -d '{\""flag_name\"":\""$flag\"",\""is_enabled\"":true,\""rules\"":{\""type\"":\""PERCENTAGE\"",\""value\"":50}}' || curl -s -X PUT http://targeting-service:8003/rules/$flag -H 'Authorization: Bearer $chave' -H 'Content-Type: application/json' -d '{\""is_enabled\"":true,\""rules\"":{\""type\"":\""PERCENTAGE\"",\""value\"":50}}'"
        Verificar "targeting-service grava regra no RDS" ($r -match "PERCENTAGE")

        $antes = [int](aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --query "Count" --output text 2>$null)

        $r = NoCluster "curl -s 'http://evaluation-service:8004/evaluate?user_id=val-a&flag_name=$flag'; echo; curl -s 'http://evaluation-service:8004/evaluate?user_id=val-b&flag_name=$flag'"
        Verificar "evaluation-service decide a flag" ($r -match "result")

        $log = kubectl logs -n $ns -l app=evaluation-service --tail=40 2>$null
        Verificar "evaluation usa o cache Redis" (($log -join "") -match "Cache (HIT|MISS)")
        Verificar "evaluation publica na fila SQS" (($log -join "") -match "SQS")

        Start-Sleep -Seconds 25
        $depois = [int](aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --query "Count" --output text 2>$null)
        Verificar "analytics grava os eventos no DynamoDB" ($depois -gt $antes) "antes: $antes, depois: $depois"

        $pendentes = aws sqs get-queue-attributes --queue-url $fila --attribute-names ApproximateNumberOfMessages --query "Attributes.ApproximateNumberOfMessages" --output text 2>$null
        Verificar "fila SQS drenada" ($pendentes -eq "0") "pendentes: $pendentes"

        NoCluster "curl -s -o /dev/null -X DELETE http://flag-service:8002/flags/$flag -H 'Authorization: Bearer $chave'" | Out-Null
    }
} else {
    Verificar "secret auth-service-runtime existe" $false "nao encontrado"
}

# ---------------------------------------------------------------- observabilidade
Write-Host "`nOBSERVABILIDADE"

$obs = "observabilidade"
foreach ($a in @("kube-prometheus-stack", "loki", "otel-collector", "observabilidade-config")) {
    $saude = kubectl get application $a -n argocd -o jsonpath="{.status.health.status}" 2>$null
    Verificar "Application $a Healthy" ($saude -eq "Healthy") "health: $saude"
}

$nos = (kubectl get nodes --no-headers 2>$null | Measure-Object).Count
$coletores = kubectl get daemonset otel-collector-agent -n $obs -o jsonpath="{.status.numberReady}" 2>$null
Verificar "um OTel Collector pronto por no" ([int]$coletores -eq $nos) "prontos: $coletores de $nos"

foreach ($d in @("grafana", "runbook-self-healing")) {
    $pronto = kubectl get deployment $d -n $obs -o jsonpath="{.status.readyReplicas}" 2>$null
    Verificar "$d pronto" ($pronto -eq "1") "readyReplicas: $pronto"
}

$r = NoCluster "curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://loki.observabilidade.svc:3100/ready"
Verificar "Loki pronto" ($r -match "200") "codigo: $r"

# o gerador de trafego roda desde que o argocd sincronizou, entao ja deve haver span e log
$r = NoCluster "curl -s --max-time 15 -G http://monitoramento-prometheus.observabilidade.svc:9090/api/v1/query --data-urlencode 'query=count(traces_span_metrics_calls_total)'"
Verificar "Prometheus recebe as metricas de span do Collector" ($r -match '"value":\[[0-9.]+,"[1-9]') "resposta: $r"

$r = NoCluster "curl -s --max-time 15 -G http://loki.observabilidade.svc:3100/loki/api/v1/query --data-urlencode 'query=count_over_time({k8s_namespace_name=\`"togglemaster\`"}[5m])'"
Verificar "Loki recebe os logs do togglemaster" ($r -match '"status":"success"' -and $r -match '"value"') "resposta: $r"

$nr = kubectl get secret newrelic -n $obs -o jsonpath="{.data.license-key}" 2>$null
$nrValor = if ($nr) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($nr)) } else { "" }
Verificar "chave do New Relic configurada" ($nrValor -and $nrValor -ne "pendente") "rode o guardar-chaves-integracoes.ps1 e o criar-segredos-observabilidade.ps1"

# ---------------------------------------------------------------- resumo
Write-Host ""
Write-Host "=============================================================="
if ($falhas.Count -eq 0) {
    Write-Host " $total verificacoes, todas passaram" -ForegroundColor Green
    Write-Host "=============================================================="
    exit 0
} else {
    Write-Host " $($falhas.Count) de $total verificacoes falharam:" -ForegroundColor Red
    foreach ($f in $falhas) { Write-Host "   - $f" -ForegroundColor Red }
    Write-Host "=============================================================="
    exit 1
}
