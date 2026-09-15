# ToggleMaster, infraestrutura e entrega contínua

Tech Challenge Fase 3, POSTECH FIAP, DevOps e Arquitetura em Nuvem.

Este repositório contém a infraestrutura em Terraform, os cinco microsserviços e os pipelines
de CI do ToggleMaster, o sistema de feature flags da DevOps Solutions Inc. Os manifestos que
descrevem o que roda no cluster ficam em um repositório separado,
[togglemaster-gitops](https://github.com/mjrafael/togglemaster-gitops).

## O problema

A Fase 2 entregou cinco microsserviços rodando no EKS, mas a operação tinha três buracos:

1. os desenvolvedores aplicavam mudanças rodando `kubectl apply` da própria máquina
2. as credenciais dos bancos circulavam em arquivo de texto
3. uma vulnerabilidade em biblioteca chegou em produção sem ninguém ver

Cada um deles é atacado por uma parte desta entrega.

## Arquitetura

```
                    push na main
                         |
              +----------v-----------+
              |   GitHub Actions     |   build, lint, SAST, SCA,
              |   (um por serviço)   |   scan de imagem
              +----------+-----------+
                         |
            OIDC (sem access key guardada)
                         |
              +----------v-----------+
              |         ECR          |   imagem com tag = commit hash
              +----------+-----------+
                         |
              deploy key com escopo de 1 repo
                         |
              +----------v-----------+
              | togglemaster-gitops  |   manifestos, a tag é reescrita aqui
              +----------+-----------+
                         |
                     ArgoCD puxa
                         |
              +----------v-----------+
              |       EKS            |
              +----------------------+
```

O pipeline não tem acesso ao cluster. Ele não tem kubeconfig, não roda `kubectl` e não sabe
o endereço do control plane. Quem aplica é o ArgoCD, que vive dentro do cluster e lê do git.

## Estrutura

```
infra/
  bootstrap/            bucket de state, criado antes de tudo e nunca destruído
  modules/
    networking/         VPC, 4 subnets em 2 zonas, IGW, NAT, route tables
    eks/                cluster, node group, IAM roles, provedor OIDC para IRSA
    data/               3 RDS, ElastiCache, DynamoDB, SQS, roles de IRSA
    ecr/                5 repositórios de imagem
    cicd/               federação OIDC com o GitHub e role do pipeline
  main.tf               root module, só compõe e liga saída em entrada

services/
  auth-service/         Go, emite e valida chaves de API
  flag-service/         Python, CRUD das definições de flag
  targeting-service/    Python, regras de segmentação
  evaluation-service/   Go, caminho quente, decide e publica evento
  analytics-service/    Python, consome a fila e grava o histórico

.github/workflows/      um pipeline por microsserviço
scripts/                preparação do cluster, testes e demonstrações
```

## Decisões que valem explicação

**State remoto com trava no próprio S3.** O state guarda o mapa da infraestrutura e o
endereço dos bancos. Ele vive no S3 com versionamento, criptografia, bloqueio de acesso
público e uma policy que recusa qualquer acesso fora de TLS. A trava usa `use_lockfile`, que
faz o próprio S3 arbitrar, sem tabela auxiliar no DynamoDB.

O bootstrap tem chave separada do resto. O `destroy` do laboratório roda contra `dev/` e não
tem como alcançar o bucket, porque o bucket nem está naquele state.

**Nenhuma senha no repositório.** As senhas dos três bancos são geradas pelo Terraform,
entregues ao RDS e guardadas no Secrets Manager. Elas não existem em arquivo nenhum, e nem eu
as vi. O `scripts/bootstrap-cluster.ps1` lê do Secrets Manager e monta os secrets do cluster.

**Credencial do pipeline por federação.** Não há access key da AWS guardada no GitHub. Existe
uma relação de confiança: a role só pode ser assumida por este repositório, nesta branch, e a
permissão dela é apenas push nos cinco ECR.

**Permissão de pod por service account, não por nó.** O `evaluation-service` e o
`analytics-service` usam IRSA. Um só pode publicar na fila, o outro só pode consumir dela e
gravar na tabela. Sem isso, qualquer pod do cluster herdaria o acesso pela role da instância.

**Portão de segurança em CRÍTICO, não em estilo.** Cada ferramenta roda duas vezes: a primeira
lista tudo sem bloquear, a segunda bloqueia apenas em vulnerabilidade crítica. Portão que trava
por espaço em branco no fim da linha é portão que alguém desliga na primeira sexta-feira à noite.

**Um NAT Gateway em vez de um por zona.** O padrão de produção é um por zona de
disponibilidade. Dois custam cerca de US$ 64 por mês, um custa US$ 32. O desafio não pede alta
disponibilidade e a conta é pessoal. A consequência é real e assumida: se a zona onde o NAT
vive cair, as duas subnets privadas perdem a saída ao mesmo tempo.

**Tag de imagem imutável.** Uma vez publicada, a tag não pode ser sobrescrita. O manifesto
aponta para um commit hash e precisa da garantia de que aquela tag significa sempre o mesmo
binário.

## Como reproduzir do zero

Pré-requisitos: Terraform 1.10 ou superior, AWS CLI configurado, kubectl, Go 1.24, Python 3.11,
GitHub CLI autenticado.

```powershell
# 1. bucket de state, só na primeira vez
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap apply

# 2. todo o resto, cerca de 45 minutos
.\scripts\reconstruir-tudo.ps1
```

O script faz o apply, atualiza o ConfigMap com os endpoints reais, cria os secrets a partir do
Secrets Manager, executa os `init.sql` por Job dentro da VPC, e instala o ArgoCD. Depois dele,
dispare os cinco pipelines para publicar as imagens e rode:

```powershell
.\scripts\emitir-chave-de-servico.ps1
.\scripts\testar-fluxo.ps1
```

O último exercita a cadeia inteira: emite uma chave, cria uma flag, cria uma regra de 50%,
avalia seis usuários e mostra os eventos gravados no DynamoDB.

## Demonstração do portão de segurança

```powershell
.\scripts\demo-1-introduzir-vulnerabilidade.ps1   # pipeline barra
.\scripts\demo-2-corrigir-vulnerabilidade.ps1     # pipeline passa
```

O primeiro acrescenta `PyYAML==5.3.1`, que carrega a CVE-2020-14343, nota 9.8. O pipeline falha
no passo `portao de critico` e o job de imagem é pulado, então nada chega ao registro.

## Limitações conhecidas

- O NAT único é ponto único de falha, como descrito acima.
- Os microsserviços vieram sem teste unitário, e não foram escritos testes novos.
- Os secrets do Kubernetes são criados fora do git por um script. Em produção o certo seria
  External Secrets Operator ou o driver CSI lendo do Secrets Manager, para o cluster buscar
  sozinho e a rotação funcionar.
- O ambiente roda com um nó por zona e sem autoscaling de pod.

## Custo

Com tudo de pé, cerca de US$ 7,28 por dia. O detalhamento está no relatório de entrega.
O laboratório é destruído ao fim de cada sessão com `terraform -chdir=infra destroy`.
