# 03 — Security Groups

Os Security Groups (SGs) controlam **todo** o tráfego da solução. Regra de ouro: liberar apenas o necessário (menor privilégio). SGs são **stateful**: a resposta de uma conexão permitida retorna automaticamente.

## 1. Mapa dos SGs

| SG | Anexado a | Função |
|---|---|---|
| `SG-ALB-PUBLIC` | Application Load Balancer | Receber tráfego da Internet |
| `SG-EC2-WEB` | EC2 Application 01 e 02 | Receber tráfego do ALB e da Jump Host; falar com os dados |
| `SG-JUMPHOST` | EC2 Jump Host | Acesso administrativo |
| `SG-POSTGRESQL` | EC2 PostgreSQL | Proteger o banco |
| `SG-REDIS` | EC2 Redis | Proteger o cache |

## 2. Regras de entrada

| SG | Protocolo | Porta | Origem | Observação |
|---|---|---|---|---|
| `SG-ALB-PUBLIC` | HTTP | 80 | `0.0.0.0/0` | Qualquer origem IPv4 |
| `SG-ALB-PUBLIC` | HTTPS | 443 | `0.0.0.0/0` | Opcional (certificado ACM) |
| `SG-EC2-WEB` | HTTP | 80 | `SG-ALB-PUBLIC` | Somente via ALB |
| `SG-EC2-WEB` | HTTPS | 443 | `SG-ALB-PUBLIC` | Somente via ALB |
| `SG-EC2-WEB` | SSH | 22 | `SG-JUMPHOST` | Administração em dois saltos |
| `SG-JUMPHOST` | SSH | 22 | IP administrativo `/32` | Nunca `0.0.0.0/0` |
| `SG-POSTGRESQL` | PostgreSQL (TCP) | 5432 | `SG-EC2-WEB` | Referência entre VPCs (mesma região) |
| `SG-REDIS` | Redis (TCP) | 6379 | `SG-EC2-WEB` | Referência entre VPCs (mesma região) |

## 3. Regras de saída

| SG | Protocolo | Porta | Destino | Observação |
|---|---|---|---|---|
| `SG-ALB-PUBLIC` | HTTP | 80 | `SG-EC2-WEB` | Encaminhar requisições às instâncias |
| `SG-ALB-PUBLIC` | HTTPS | 443 | `SG-EC2-WEB` | Encaminhar requisições às instâncias |
| `SG-EC2-WEB` | PostgreSQL (TCP) | 5432 | `SG-POSTGRESQL` | Via VPC Peering |
| `SG-EC2-WEB` | Redis (TCP) | 6379 | `SG-REDIS` | Via VPC Peering |
| `SG-EC2-WEB` | HTTPS | 443 | `0.0.0.0/0` | `git clone` e atualizações (saída via IGW) |
| `SG-JUMPHOST` | SSH (TCP) | 22 | `SG-EC2-WEB` | Segundo salto do acesso administrativo |
| `SG-POSTGRESQL` | HTTPS | 443 | `0.0.0.0/0` | Atualizações (saída via NAT Gateway) |
| `SG-REDIS` | HTTPS | 443 | `0.0.0.0/0` | Atualizações (saída via NAT Gateway) |

> As EC2s PostgreSQL e Redis não têm rota nem regra de entrada para a Internet — o tráfego de saída passa pelo NAT Gateway (ver `02-arquitetura-e-rede.md`).

## 4. Ponto crítico: referência de SG entre VPCs

Usar `SG-EC2-WEB` como origem no `SG-POSTGRESQL` e `SG-REDIS` (e como destino nas saídas do `SG-EC2-WEB`) só funciona porque:

1. As VPCs estão na **mesma região** (us-east-1); e
2. O **VPC Peering está ativo**.

A documentação oficial da AWS confirma: *"You can't reference the security group of a peer VPC that's in a different Region. Instead, use the CIDR block of the peer VPC."*

**Plano B (fallback)**: se você mover as VPCs para regiões diferentes ou a referência não funcionar, troque a origem nas regras de entrada do PostgreSQL/Redis pelas subnets da aplicação:

- `SG-POSTGRESQL` porta 5432 origem `10.0.0.0/24` e `10.0.1.0/24`
- `SG-REDIS` porta 6379 origem `10.0.0.0/24` e `10.0.1.0/24`
- `SG-EC2-WEB` saída 5432/6379 destino `10.1.1.0/24` e `10.1.2.0/24`

## 5. Ordem de criação (evitando dependências circulares)

Os SGs se referenciam mutuamente (`SG-EC2-WEB` ← `SG-ALB-PUBLIC`, `SG-EC2-WEB` → `SG-POSTGRESQL`...). A ordem prática no console:

1. Crie os **cinco SGs vazios** (sem regras), cada um na VPC correta:

| SG | VPC |
|---|---|
| `SG-ALB-PUBLIC` | Application VPC |
| `SG-EC2-WEB` | Application VPC |
| `SG-JUMPHOST` | Application VPC |
| `SG-POSTGRESQL` | Data VPC |
| `SG-REDIS` | Data VPC |

2. Depois volte em cada SG e **adicione as regras** da tabela acima. Como todos já existem, as referências aparecem na lista.

Dica: ao digitar a origem/destino, selecione o tipo **Security Group** e busque pelo nome; se o SG da outra VPC não aparecer, confirme que o peering está `Active` e na mesma região.

## 6. Regras que **não** devem existir

| Regra indevida | Por quê é proibida |
|---|---|
| `SG-EC2-WEB` SSH 22 de `0.0.0.0/0` | Violação do requisito de Jump Host |
| `SG-POSTGRESQL` 5432 de `0.0.0.0/0` | Banco exposto à Internet |
| `SG-REDIS` 6379 de `0.0.0.0/0` | Cache exposto à Internet |
| `SG-JUMPHOST` 22 de `0.0.0.0/0` | Força a um IP administrativo `/32` |
| Qualquer SG com entrada ampla em "All traffic" | Fere o menor privilégio |

## 7. SGs ficam "stale" (obsoletos)

Se o VPC Peering for deletado, as regras que referenciam SGs do outro lado continuam existindo, mas não casam mais (ficam "stale" / obsoletas). Ao recriar o peering, revise as regras — e remova referências antigas para evitar confusão.

## 8. Verificação rápida

No console: **VPC → Security Groups → selecione o SG → Inbound/Outbound rules**. Confira que:

- `SG-POSTGRESQL` e `SG-REDIS` só aceitam origem `SG-EC2-WEB`.
- `SG-EC2-WEB` aceita 80/443 apenas de `SG-ALB-PUBLIC` e 22 apenas de `SG-JUMPHOST`.
- Nenhum SG expõe 5432/6379/22 para `0.0.0.0/0`.
