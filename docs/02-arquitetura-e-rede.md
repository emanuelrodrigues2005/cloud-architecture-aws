# 02 — Arquitetura e Planejamento de Rede

Referências visuais: `Arquitetura_AWS.drawio.png` (visão geral) e `Arquitetura_Cloud_AWS_final.pdf` (documento de arquitetura).

## 1. Visão geral

```
                           Internet
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
┌───────▼────── Application VPC (10.0.0.0/16) ──────┴─────────┐   ┌──── Data VPC (10.1.0.0/16) ────────────────────┐
│                                                             │   │                                                │
│  ┌───────────── Public Subnet AZ-1 ─────────────┐           │   │  ┌──── Public Subnet AZ-1 (10.1.0.0/24) ────┐  │
│  │  EC2 Application 01        Jump Host (EC2)   │           │   │  │  NAT Gateway + Elastic IP               │  │
│  │  10.0.0.0/24                                 │           │   │  └──────────────┬──────────────────────────┘  │
│  └──────────────────────────────────────────────┘           │   │                 │                            │
│  ┌───────────── Public Subnet AZ-2 ─────────────┐           │   │  ┌──── Private Subnet AZ-1 (10.1.1.0/24) ─┐  │
│  │  EC2 Application 02                          │           │   │  │  EC2 PostgreSQL 10.1.1.10:5432        │  │
│  │  10.0.1.0/24                                 │           │   │  └───────────────────────────────────────┘  │
│  └──────────────────────────────────────────────┘           │   │  ┌──── Private Subnet AZ-2 (10.1.2.0/24) ─┐  │
│                                                             │   │  │  EC2 Redis 10.1.2.10:6379             │  │
│  ALB (Internet-facing, subnets AZ-1 + AZ-2, SG-ALB-PUBLIC)  │   │  └───────────────────────────────────────┘  │
│                                                             │   │                                                │
│                     │  VPC Peering 10.0.0.0/16 ↔ 10.1.0.0/16  │  │                                                │
└─────────────────────┼───────────────────────────────────────┘   └────────────────┬───────────────────────────────┘
                      └────────────────────────────────────────────────────────────┘
```

## 2. VPCs e subnets

| VPC | CIDR | Subnet | CIDR | AZ | Tipo | Recursos |
|---|---|---|---|---|---|---|
| Application VPC | `10.0.0.0/16` | Public Subnet AZ-1 | `10.0.0.0/24` | us-east-1a | Pública | EC2 Application 01, Jump Host, ALB |
| Application VPC | `10.0.0.0/16` | Public Subnet AZ-2 | `10.0.1.0/24` | us-east-1b | Pública | EC2 Application 02, ALB |
| Data VPC | `10.1.0.0/16` | Public Subnet AZ-1 | `10.1.0.0/24` | us-east-1a | Pública | NAT Gateway + Elastic IP |
| Data VPC | `10.1.0.0/16` | Private Subnet AZ-1 | `10.1.1.0/24` | us-east-1a | Privada | EC2 PostgreSQL (`10.1.1.10`) |
| Data VPC | `10.1.0.0/16` | Private Subnet AZ-2 | `10.1.2.0/24` | us-east-1b | Privada | EC2 Redis (`10.1.2.10`) |

> O PostgreSQL e o Redis ficam em **subnets privadas distintas**, cada um em sua própria EC2 — atende ao requisito de ambientes de execução separados.

## 3. Dimensionamento (requisitos de capacidade)

| Requisito da atividade | Cálculo | Resultado |
|---|---|---|
| Subnets da aplicação ≥ **20 instâncias** | `/24` = 256 IPs − 5 reservados pela AWS = **251** utilizáveis | Atende com folga |
| Subnets de dados ≥ **25 recursos** | `/24` = 251 utilizáveis por subnet | Atende com folga |
| Expansão futura | Blocos `/16` por VPC permitem criar novas subnets `/24` | Atende |

A AWS reserva 5 IPs por subnet (endereço de rede, roteador, DNS, uso futuro e broadcast).

## 4. Route Tables

| Route Table | Associada a | Destino | Alvo |
|---|---|---|---|
| `rt-app-public` | Public Subnet AZ-1 e AZ-2 (Application VPC) | `0.0.0.0/0` | Internet Gateway |
| `rt-app-public` | idem | `10.1.0.0/16` | VPC Peering (`pcx-...`) |
| `rt-data-public` | Public Subnet AZ-1 (Data VPC) | `0.0.0.0/0` | Internet Gateway |
| `rt-data-private` | Private Subnet AZ-1 e AZ-2 (Data VPC) | `0.0.0.0/0` | NAT Gateway |
| `rt-data-private` | idem | `10.0.0.0/16` | VPC Peering (`pcx-...`) |

Pontos de atenção:

- A rota `10.0.0.0/16 → VPC Peering` na `rt-data-private` é obrigatória para o **tráfego de retorno** da camada de dados para a aplicação.
- Sem a rota do peering nas tabelas, a aplicação alcança a VPC de dados? **Não** — sem rota de ida, o pacote nem sai. Sem rota de volta, sai mas a resposta não retorna (timeout).
- A aplicação **não usa NAT** porque suas instâncias estão em subnets públicas (saída via IGW).

## 5. VPC Peering

| Item | Valor |
|---|---|
| Nome sugerido | `pcx-app-data` |
| Requester | Application VPC (`10.0.0.0/16`) |
| Accepter | Data VPC (`10.1.0.0/16`) |
| Região | us-east-1 (mesma região — permite referência de SG entre VPCs) |
| Rotas | `10.1.0.0/16 → pcx` na `rt-app-public`; `10.0.0.0/16 → pcx` na `rt-data-private` |

CIDRs **não se sobrepõem**, requisito para o peering funcionar.

## 6. Endereçamento fixo dos serviços de dados

Para que a configuração da aplicação seja estável (sem depender de IP dinâmico):

| Serviço | EC2 | IP privado fixo | Porta |
|---|---|---|---|
| PostgreSQL | `ec2-postgres` | `10.1.1.10` | `5432` |
| Redis | `ec2-redis` | `10.1.2.10` | `6379` |

O IP privado é definido no momento do lançamento da EC2 (campo *Primary private IP*). Os valores acima estão embutidos no `app/bootstrap.sh` e podem ser sobrescritos com `POSTGRES_IP` e `REDIS_IP`.

## 7. Fluxos de comunicação

### Externo

```
Usuário → Internet Gateway → Application Load Balancer (80/443) → EC2 Application (80)
```

- O ALB é o **único** ponto de entrada pública.
- As EC2s da aplicação aceitam tráfego HTTP na porta 80 **somente** vindos do SG-ALB-PUBLIC.

### Interno (via VPC Peering)

```
EC2 Application → VPC Peering → PostgreSQL (10.1.1.10:5432)
EC2 Application → VPC Peering → Redis (10.1.2.10:6379)
```

### Administração

```
Administrador → SSH (22) → Jump Host → SSH (22) → EC2 Application
```

- O Jump Host aceita SSH apenas do IP administrativo `/32`.
- PostgreSQL e Redis **não possuem regra de SSH**; são administrados por user data / automação.

### Atualizações (saída para Internet)

```
EC2 Application → Internet Gateway (IP público) → Internet
EC2 PostgreSQL/Redis → NAT Gateway (Elastic IP) → Internet
```

## 8. Portas da solução

| Porta | Protocolo | Uso |
|---|---|---|
| 80 | HTTP | Usuário → ALB; ALB → EC2 Application; app publicado no host como `APP_PORT=80` |
| 443 | HTTPS | Opcional no ALB (requer certificado ACM); saída para atualizações |
| 22 | SSH | Administração via Jump Host |
| 5432 | PostgreSQL | Aplicação → banco |
| 6379 | Redis | Aplicação → cache |

## 9. Expansão futura

- Cada subnet tem espaço para **novas EC2s da aplicação** (basta lançar em AZ-1/AZ-2 e registrar no Target Group; um Auto Scaling Group pode automatizar).
- Novas subnets `/24` podem ser criadas nos blocos `/16` para outros serviços de dados.
- O **peering não é transitivo**: uma terceira VPC exige uma nova conexão de peering.
- A área "expansão" no desenho (`Área de expansão + instâncias EC2`) representa exatamente essa folga da subnet (≥ **20 instâncias**).
