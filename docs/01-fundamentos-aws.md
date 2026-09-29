# 01 — Fundamentos da AWS usados na arquitetura

Este documento explica cada componente da AWS presente na arquitetura, o que ele faz e por que foi usado. Leia antes de provisionar.

## 1. Região e Zonas de Disponibilidade (AZs)

- **Região** é o conjunto de datacenters de uma área geográfica (usamos **us-east-1**, N. Virginia). Preços, AMIs e key pairs são por região.
- **Zona de Disponibilidade (AZ)** é um ou mais datacenters isolados dentro da região (ex.: `us-east-1a`, `us-east-1b`). Recursos em AZs diferentes ficam protegidos contra falha de uma única AZ.
- Uma **subnet pertence a exatamente uma AZ**. Por isso a aplicação usa duas subnets (AZ-1 e AZ-2).
- O **Application Load Balancer exige pelo menos duas subnets em AZs distintas** — atendido pelas duas subnets públicas da Application VPC.

## 2. VPC (Virtual Private Cloud)

Rede virtual isolada, definida por um bloco **CIDR** (ex.: `10.0.0.0/16`). Tudo que criamos (subnets, EC2, ALB, SGs) vive dentro de uma VPC.

A arquitetura usa duas VPCs com blocos **sem sobreposição** (requisito para o VPC Peering):

| VPC | CIDR | Papel |
|---|---|---|
| Application VPC | `10.0.0.0/16` | Camada de aplicação (ALB, EC2 web, Jump Host) |
| Data VPC | `10.1.0.0/16` | Camada de dados (PostgreSQL e Redis) |

## 3. Subnet

Subdivisão da VPC ligada a uma AZ. O que define se ela é **pública** ou **privada** é a **Route Table**:

- **Subnet pública**: possui rota `0.0.0.0/0` para o **Internet Gateway**. Recursos com IP público podem ser acessados e acessar a Internet.
- **Subnet privada**: não tem rota para o Internet Gateway. Para sair à Internet (ex.: atualizações), usa uma rota `0.0.0.0/0` para o **NAT Gateway**.

A AWS reserva **5 endereços IP por subnet** (rede, roteador, DNS, futuro e broadcast). Uma subnet `/24` tem 256 endereços − 5 = **251 IPs utilizáveis** — suficiente para os requisitos de **20 instâncias** (aplicação) e **25 recursos** (dados).

## 4. Internet Gateway (IGW)

Componente anexado à VPC que conecta a rede à Internet. Sem ele, nenhuma subnet é pública.

- Application VPC: IGW para o tráfego dos usuários → ALB e para a saída das EC2s da aplicação (que não têm NAT nesta VPC).
- Data VPC: IGW usado pelo **NAT Gateway** (o NAT precisa de IGW na VPC para alcançar a Internet).

O IGW é **redundante e altamente disponível** por padrão (não há cobrança por hora).

## 5. NAT Gateway e Elastic IP

O **NAT Gateway** permite que recursos em subnets privadas **iniciem** conexões para a Internet (ex.: `apt update`, `docker pull`), mas **não permite conexões de entrada**.

- Fica em uma **subnet pública** (na Data VPC, `10.1.0.0/24`).
- Precisa de um **Elastic IP** (IP público estático) associado.
- As subnets privadas apontam a rota `0.0.0.0/0` para o NAT Gateway.
- É gerenciado pela AWS (diferente de uma "NAT instance" em EC2).

## 6. Route Table (tabela de rotas)

Conjunto de rotas que decide para onde vai o tráfego de cada subnet. A arquitetura usa quatro tabelas:

| Route Table | Associada a | Rotas |
|---|---|---|
| Pública — Application VPC | Public Subnet AZ-1 e AZ-2 | `0.0.0.0/0 → IGW` e `10.1.0.0/16 → VPC Peering` |
| Pública — Data VPC | Public Subnet AZ-1 (NAT) | `0.0.0.0/0 → IGW` |
| Privada — Data VPC | Private Subnet AZ-1 e AZ-2 | `0.0.0.0/0 → NAT Gateway` e `10.0.0.0/16 → VPC Peering` |

Observações:

- A rota para o peering precisa existir **nos dois lados** (ida e volta). Sem a rota `10.0.0.0/16 → Peering` na tabela privada, o PostgreSQL recebe a requisição mas a resposta não sabe voltar.
- A rota mais específica vence. `10.1.0.0/16` é mais específica que `0.0.0.0/0`, então o tráfego entre VPCs nunca sai para a Internet.
- Subnet só é "pública" se a tabela associada tiver rota para IGW.

## 7. Security Group (SG)

Firewall **stateful** (a resposta de uma conexão permitida é liberada automaticamente) aplicado às interfaces de rede (ENIs). Regras são apenas de **allow** — tudo que não é permitido é bloqueado.

- Cada SG tem regras de **entrada** e **saída**.
- Um SG pode ter outro **SG como origem/destino** (referência), o que é mais seguro que usar faixas de IP.
- **Ponto crítico**: referenciar um SG de outra VPC só funciona se as VPCs estiverem na **mesma região** e o **VPC Peering estiver ativo**. É o nosso caso (ambas em us-east-1). Se fosse cross-region, usaríamos o CIDR `10.0.0.0/24` e `10.0.1.0/24` como origem.
- Um SG pode ser associado a várias instâncias; regras valem para todas.

Detalhes completos em `03-security-groups.md`.

## 8. EC2 (Elastic Compute Cloud)

Servidores virtuais. Conceitos usados:

- **AMI**: imagem base. Usaremos **Ubuntu Server 26.04 LTS** (git e Docker disponíveis via `apt`; o Compose vem do pacote `docker-compose-v2`).
- **Instance type**: `t3.micro` (2 vCPU em burst, 1 GiB RAM) é suficiente para a demonstração; elegível a free tier.
- **Key pair**: chave SSH criada na região; o **Jump Host** precisa dela para administrar as instâncias.
- **IP privado**: fixo dentro da VPC (usaremos `10.1.1.10` para o PostgreSQL e `10.1.2.10` para o Redis para configuração estável).
- **IP público**: atribuído automaticamente quando a subnet é pública e a opção *auto-assign public IPv4* está habilitada. Necessário para o `git clone` e atualizações das EC2s da aplicação (a Application VPC não tem NAT).
- **User data**: script executado no primeiro boot. Usado para instalar Docker, clonar o repositório e rodar o `bootstrap.sh`.

## 9. Application Load Balancer (ALB)

Balanceador **camada 7 (HTTP/HTTPS)**:

- **Listener**: porta de escuta (ex.: HTTP 80) e regra de encaminhamento.
- **Target Group (TG)**: grupo de destinos (as EC2s) + configuração de **health check**.
- **Health check**: o ALB chama periodicamente um caminho nas instâncias (usaremos `/health`, esperando HTTP 200). Alvo não saudável sai da rotação automaticamente.
- O ALB precisa de **duas subnets públicas** em AZs distintas e de um SG que aceite o tráfego dos usuários (`SG-ALB-PUBLIC`).
- O ALB **não tem IP público fixo**; o acesso se dá pelo **DNS name** do balanceador.

## 10. VPC Peering

Conexão de rede direta entre duas VPCs, por IP privado, sem passar pela Internet.

Regras práticas:

1. Os CIDRs **não podem se sobrepor** (`10.0.0.0/16` x `10.1.0.0/16` — ok).
2. A conexão precisa ser **aceita** pelo dono da outra VPC (aqui, a mesma conta aceita).
3. As **Route Tables dos dois lados** precisam de rota apontando para a conexão de peering.
4. Os **Security Groups** precisam permitir o tráfego (no nosso caso, referência direta entre SGs por estarem na mesma região).
5. Peering **não é transitivo**: se um dia existir uma terceira VPC, ela não conversa automaticamente com as outras duas.

## 11. Docker e Docker Compose

A aplicação e os serviços de dados rodam em **containers**:

- **Imagem**: empacota a aplicação (Python + dependências) — definida no `app/Dockerfile`.
- **Compose**: sobe e conecta os containers. O `app/docker-compose.yml` foi parametrizado (`${VAR:-default}`) para servir **tanto o dev local quanto as EC2s**, onde os IPs privados das VPCs entram por variáveis de ambiente.
- O `app/bootstrap.sh` automatiza instalação do Docker, clone do repositório e subida do container correto para o papel de cada EC2 (`app`, `postgres` ou `redis`).

Com isso, a "orquestração de containers" exigida se mantém simples e reproduzível: um arquivo de compose e um script de bootstrap.
