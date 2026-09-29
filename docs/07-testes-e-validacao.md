# 07 — Testes e Validação

Duas camadas de validação: a **conferência da configuração** (compose e bootstrap, antes do deploy) e os **testes da infraestrutura na AWS** (positivos e negativos), que comprovam os requisitos da atividade.

## 1. Conferência da configuração (antes do deploy)

```bash
docker compose -f app/docker-compose.yml config
bash app/bootstrap.sh --dry-run app
```

- O `config` falha se o YAML estiver inválido e mostra a configuração final do Compose (com os defaults de desenvolvimento).
- O `--dry-run` mostra exatamente os comandos que cada papel executa na EC2 (`app`, `postgres`, `redis`), sem alterar nada.

Esperado no papel `app`: `DB_HOST=10.1.1.10`, `REDIS_HOST=10.1.2.10` e `APP_PORT=80`. Nos demais papéis: `up -d postgres` e `up -d redis`.

## 2. Testes de infraestrutura — positivos

| # | Requisito validado | Como testar | Evidência esperada |
|---|---|---|---|
| P1 | Aplicação acessível pela Internet via ALB | `curl -i http://<dns-do-alb>/` | HTTP 200 com o HTML do mural |
| P2 | App fala com PostgreSQL via peering | `curl -s http://<dns-do-alb>/health` | `"postgresql": "online"` |
| P3 | App fala com Redis via peering | `curl -s http://<dns-do-alb>/health` | `"redis": "online"` |
| P4 | ALB distribui entre as duas instâncias | `docker logs -f mural_app` nas duas EC2s enquanto recarrega a página | requisições aparecem nas duas |
| P5 | Publicação de mensagem persiste no banco | publicar no mural e recarregar/consultar outra instância | mensagem listada (veio do PostgreSQL) |
| P6 | Recursos privados acessam a Internet (atualizações) | na `ec2-postgres`: `curl -s -o /dev/null -w '%{http_code}' https://aws.amazon.com` | `200` (saída via NAT Gateway) |
| P7 | EC2 da aplicação alcança o banco e o cache | na `ec2-app-01`: `timeout 3 bash -c '</dev/tcp/10.1.1.10/5432' && echo PG-ok` e idem `10.1.2.10/6379` | `PG-ok` e `REDIS-ok` |
| P8 | Persistência do banco | `docker compose down && docker compose up -d postgres` na `ec2-postgres` e conferir as mensagens | dados continuam (volume `postgres_data`) |
| P9 | Alta disponibilidade da camada web | parar o container em `ec2-app-01` (`docker stop mural_app`) e acessar o ALB | mural continua respondendo via `ec2-app-02` |

## 3. Testes de infraestrutura — negativos (segurança)

| # | Regra validada | Como testar | Evidência esperada |
|---|---|---|---|
| N1 | SSH direto da Internet bloqueado nas EC2s web | da sua máquina: `ssh -i chave.pem ubuntu@<ip-público-da-app>` | timeout / conexão recusada |
| N2 | SSH no Jump Host restrito ao IP administrativo | de outro IP que não o seu: `ssh ubuntu@<ip-do-jumphost>` | timeout (só o `/32` cadastrado entra) |
| N3 | PostgreSQL não acessível da Internet | de uma máquina fora da VPC: tentar `10.1.1.10:5432` | inalcançável (IP privado + SG) |
| N4 | Redis não acessível da Internet | idem para `10.1.2.10:6379` | inalcançável |
| N5 | Jump Host não vaza acesso SSH para os dados | no Jump Host: `timeout 3 bash -c '</dev/tcp/10.1.1.10/22'` | falha (SG-JUMPHOST só vai para SG-EC2-WEB) |
| N6 | Sem regra ampla nos SGs | console → VPC → Security Groups | nenhuma entrada 22/5432/6379 de `0.0.0.0/0` |

> Os testes N1–N4 são os que a banca costuma pedir: mostre o timeout e, em seguida, o **mesmo acesso funcionando pelo caminho correto** (Jump Host para as EC2s web; app para o banco).

## 4. Mapeamento requisito → evidência (atividade)

| Requisito do enunciado | Teste/comprovação |
|---|---|
| App em duas subnets públicas distintas | Console: EC2s nos AZs `us-east-1a`/`us-east-1b` + P9 |
| PostgreSQL e Redis em ambientes separados e privados | Console: subnets privadas distintas + N3/N4 + P2/P3 |
| Acesso à Internet só pelo ALB | P1 + N1 |
| Dados jamais acessíveis da Internet | N3 + N4 |
| Comunicação por VPC Peering | P2, P3, P7 + console (status `Active`, rotas) |
| Controle por Security Groups | N5, N6 + tabelas do doc 03 |
| Recursos privados atualizáveis | P6 |
| Administração apenas via Jump Host | N1, N2 + acesso funcionando pelo Jump |
| Capacidade de expansão | Doc 02 §3 e §9 (251 IPs por `/24`, 20 instâncias / 25 recursos) |

## 5. Comandos úteis de inspeção

```bash
# na EC2 de aplicação
curl -s localhost/health
docker ps

# da sua máquina (com AWS CLI configurada)
aws ec2 describe-vpc-peering-connections --region us-east-1 \
  --query 'VpcPeeringConnections[].{Status:Status.Code,CIDR:AccepterVpcInfo.CidrBlock}'

aws ec2 describe-route-tables --region us-east-1 \
  --query 'RouteTables[].{ID:RouteTableId,Routes:Routes[].DestinationCidrBlock}'
```

## 6. Registro de evidências

Para a entrega, guarde prints de:

1. Diagrama final (já em `Arquitetura_AWS.drawio.png`).
2. Console de VPC Peering com status `Active` e as rotas de peering nas duas Route Tables.
3. Tabela do Target Group com os dois alvos `Healthy`.
4. Navegador no DNS do ALB com o mural funcionando.
5. `curl .../health` retornando PostgreSQL e Redis `online`.
6. Timeouts dos testes negativos N1–N4.
