# Executa os db/init.sql de cada serviço dentro do cluster.
# Os RDS vivem em subnet privada, então o psql precisa rodar de dentro da VPC.
# A senha nunca sai do secret: o Job a recebe por secretKeyRef.

$ErrorActionPreference = "Stop"

$namespace = "togglemaster"
$servicos = @("auth-service", "flag-service", "targeting-service")

foreach ($servico in $servicos) {
    Write-Host "=== $servico ==="

    kubectl create configmap "init-sql-$servico" `
        --namespace $namespace `
        --from-file="init.sql=services/$servico/db/init.sql" `
        --dry-run=client -o yaml | kubectl apply -f -

    kubectl delete job "init-$servico" --namespace $namespace --ignore-not-found | Out-Null

    $job = @"
apiVersion: batch/v1
kind: Job
metadata:
  name: init-$servico
  namespace: $namespace
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: psql
          image: postgres:16-alpine
          command:
            - sh
            - -c
            - psql "`$DATABASE_URL" -v ON_ERROR_STOP=1 -f /sql/init.sql
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: $servico-db
                  key: url
          volumeMounts:
            - name: sql
              mountPath: /sql
      volumes:
        - name: sql
          configMap:
            name: init-sql-$servico
"@

    $job | kubectl apply -f -
}

Write-Host "`naguardando os jobs"
foreach ($servico in $servicos) {
    kubectl wait --for=condition=complete "job/init-$servico" --namespace $namespace --timeout=180s
}

Write-Host "`nsaida de cada job"
foreach ($servico in $servicos) {
    Write-Host "--- $servico ---"
    kubectl logs "job/init-$servico" --namespace $namespace
}
