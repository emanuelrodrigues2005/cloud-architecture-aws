# 04 — Provisionamento no Console AWS

Ordem de execução no console (região **us-east-1**). Valide cada bloco antes de seguir — é mais fácil achar erro perto da causa.

> Convenção: crie todos os recursos com a tag `Projeto=AMPLIA-UFRPE` para facilitar localizar e remover depois.

## Bloco A — Application VPC

1. **VPC**: *VPC → Create VPC → VPC only*
   - Name: `vpc-app` · IPv4 CIDR: `10.0.0.0/16`
2. **Subnets**: *VPC → Subnets → Create subnet*
   - `subnet-app-public-1a` — `10.0.0.0/24` — AZ `us-east-1a`
   - `subnet-app-public-1b` — `10.0.1.0/24` — AZ `us-east-1b`
   - Após criar, selecione cada uma → *Actions → Edit subnet settings* → marque **Enable auto-assign public IPv4 address**.
3. **Internet Gateway**: *VPC → Internet gateways → Create*
   - Name: `igw-app` → *Actions → Attach to VPC* → `vpc-app`
4. **Route Table**: *VPC → Route tables → Create*
   - Name: `rt-app-public` · VPC: `vpc-app`
   - *Edit routes* → adicione `0.0.0.0/0` → target `igw-app`
   - *Edit subnet associations* → associe `subnet-app-public-1a` e `subnet-app-public-1b`

**Validação A**: a tabela `rt-app-public` mostra as duas subnets associadas e a rota para o IGW como `Active`.

## Bloco B — Data VPC

5. **VPC**: `vpc-data` · CIDR `10.1.0.0/16`
6. **Subnets**:
   - `subnet-data-public-1a` — `10.1.0.0/24` — `us-east-1a`
   - `subnet-data-private-1a` — `10.1.1.0/24` — `us-east-1a`
   - `subnet-data-private-1b` — `10.1.2.0/24` — `us-east-1b`
   - Deixe o auto-assign **desabilitado** nas três (as privadas não devem ter IP público; o NAT Gateway recebe o Elastic IP dele).
7. **Internet Gateway**: `igw-data` → attach em `vpc-data`
8. **NAT Gateway**: *VPC → NAT gateways → Create*
   - Name: `nat-data` · Subnet: `subnet-data-public-1a`
   - Connectivity type: **Public** → *Allocate Elastic IP* (o Elastic IP é do NAT)
9. **Route Tables**:
   - `rt-data-public` (VPC `vpc-data`): rota `0.0.0.0/0` → `igw-data`; associar `subnet-data-public-1a`
   - `rt-data-private` (VPC `vpc-data`): rota `0.0.0.0/0` → `nat-data`; associar `subnet-data-private-1a` e `subnet-data-private-1b`

**Validação B**: `rt-data-private` tem 2 subnets associadas e rota `0.0.0.0/0` para o NAT; o NAT aparece como `Available` com um Elastic IP.

## Bloco C — VPC Peering

10. **Peering**: *VPC → Peering connections → Create*
    - Name: `pcx-app-data`
    - Requester: `vpc-app` (`10.0.0.0/16`) · Accepter: `vpc-data` (`10.1.0.0/16`) · Mesma região
    - Após criar, selecione → *Actions → Accept request* (mesma conta)
11. **Rotas do peering**:
    - `rt-app-public` → *Edit routes* → `10.1.0.0/16` → target `Peering connection` → `pcx-app-data`
    - `rt-data-private` → *Edit routes* → `10.0.0.0/16` → target `Peering connection` → `pcx-app-data`

**Validação C**: status do peering = `Active`; as rotas de peering aparecem como `Active` nas duas tabelas.

## Bloco D — Security Groups

Siga `03-security-groups.md`:

12. Crie os 5 SGs **vazios**, nos lugares certos:

| SG | VPC |
|---|---|
| `SG-ALB-PUBLIC` | `vpc-app` |
| `SG-EC2-WEB` | `vpc-app` |
| `SG-JUMPHOST` | `vpc-app` |
| `SG-POSTGRESQL` | `vpc-data` |
| `SG-REDIS` | `vpc-data` |

13. Depois adicione as regras de entrada/saída de cada um (referências de SG funcionam porque o peering está `Active` e as VPCs estão na mesma região).

**Validação D**: `SG-POSTGRESQL` e `SG-REDIS` mostram origem `SG-EC2-WEB`; nenhum SG expõe 5432/6379/22 para `0.0.0.0/0`.

## Bloco E — Instâncias EC2

Detalhes de user data e bootstrap em `05-ec2-dados-e-bootstrap.md`. Resumo do lançamento (*EC2 → Launch instance*):

| Instância | Subnet | IP privado | IP público | SG | User data |
|---|---|---|---|---|---|
| `ec2-jumphost` | `subnet-app-public-1a` | automático | Sim | `SG-JUMPHOST` | — |
| `ec2-app-01` | `subnet-app-public-1a` | automático | Sim | `SG-EC2-WEB` | bootstrap `app` |
| `ec2-app-02` | `subnet-app-public-1b` | automático | Sim | `SG-EC2-WEB` | bootstrap `app` |
| `ec2-postgres` | `subnet-data-private-1a` | **`10.1.1.10`** | Não | `SG-POSTGRESQL` | bootstrap `postgres` |
| `ec2-redis` | `subnet-data-private-1b` | **`10.1.2.10`** | Não | `SG-REDIS` | bootstrap `redis` |

Para cada uma: AMI **Ubuntu Server 26.04 LTS**, tipo `t3.micro`, key pair da região. O usuário padrão para SSH é `ubuntu`. Para o IP privado fixo, em *Advanced network configuration* → *Primary IP* informe `10.1.1.10` / `10.1.2.10`.

**Validação E**: as EC2s aparecem `Running`; as da aplicação/Jump têm IP público; Postgres/Redis têm somente IP privado.

## Bloco F — Application Load Balancer

14. **Target Group**: *EC2 → Target groups → Create*
    - Target type: **Instances** · Name: `tg-mural-app` · Protocol HTTP · Port **80** · VPC `vpc-app`
    - Health check path: `/health` · Success codes: `200`
    - *Register targets*: `ec2-app-01` e `ec2-app-02`
15. **Load Balancer**: *EC2 → Load balancers → Create → Application Load Balancer*
    - Name: `alb-mural` · Scheme: **Internet-facing** · IP type: IPv4
    - Network mapping: `vpc-app`, subnets `subnet-app-public-1a` e `subnet-app-public-1b`
    - Security group: apenas `SG-ALB-PUBLIC`
    - Listener: **HTTP : 80** → forward para `tg-mural-app`
16. **Teste**: copie o **DNS name** do ALB e abra `http://<dns-do-alb>/` no navegador; o mural deve carregar.

**Validação F**: no Target Group, os dois alvos ficam `Healthy`; o `http://<dns-do-alb>/health` responde com `"postgresql": "online"` e `"redis": "online"`.

## Checklist de dependências entre blocos

```
A (rede app) ──┐
B (rede data) ─┼──> C (peering) ──> D (SGs) ──> E (EC2) ──> F (ALB)
```

- Não crie SG antes do peering se for usar referência entre VPCs — a lista de SGs remotos depende do peering ativo.
- Não registre as instâncias no ALB antes de a aplicação responder em `/health`.
