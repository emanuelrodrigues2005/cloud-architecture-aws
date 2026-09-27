# 09 — Checklist de Entrega

Use este documento como roteiro de execução e como checklist final da atividade.

## 1. Antes de começar

- [ ] Conta AWS ativa, região **us-east-1** selecionada.
- [ ] Key pair criado em us-east-1.
- [ ] Repositório público acessível: `https://github.com/emanuelrodrigues2005/cloud-architecture-aws.git`.
- [ ] Testes locais passando: `bash tests/run_tests.sh`.

## 2. Provisionamento (doc 04)

- [ ] Application VPC `10.0.0.0/16` criada.
- [ ] Public Subnet AZ-1 `10.0.0.0/24` e AZ-2 `10.0.1.0/24` com auto-assign de IPv4.
- [ ] Internet Gateway da aplicação anexado; Route Table pública com `0.0.0.0/0 → IGW`.
- [ ] Data VPC `10.1.0.0/16` criada.
- [ ] Public Subnet AZ-1 `10.1.0.0/24` (NAT) e Private Subnets `10.1.1.0/24` / `10.1.2.0/24`.
- [ ] Internet Gateway da Data VPC + NAT Gateway com Elastic IP.
- [ ] Route Table privada com `0.0.0.0/0 → NAT` e associada às duas privadas.
- [ ] VPC Peering `pcx-app-data` **aceito** e rotas `10.1.0.0/16`/`10.0.0.0/16` nos dois lados.
- [ ] 5 Security Groups criados e com regras do doc 03.

## 3. Computação e dados (doc 05)

- [ ] `ec2-jumphost` na subnet pública AZ-1 com `SG-JUMPHOST`.
- [ ] `ec2-app-01` (AZ-1) e `ec2-app-02` (AZ-2) com `SG-EC2-WEB` e user data `app`.
- [ ] `ec2-postgres` na privada AZ-1 com IP `10.1.1.10` e user data `postgres`.
- [ ] `ec2-redis` na privada AZ-2 com IP `10.1.2.10` e user data `redis`.
- [ ] Containers `mural_postgres` e `mural_redis` em execução (`docker ps`).
- [ ] Containers `mural_app` em execução nas duas instâncias.

## 4. Deploy e exposição (doc 06)

- [ ] `curl -s localhost/health` retorna `postgresql: online` e `redis: online` nas duas EC2s de app.
- [ ] Target Group `tg-mural-app` com health check `/health` e duas instâncias `Healthy`.
- [ ] ALB `alb-mural` internet-facing nas duas subnets públicas com `SG-ALB-PUBLIC`.
- [ ] `http://<dns-do-alb>/` exibe o mural.
- [ ] `http://<dns-do-alb>/health` retorna `application: online`.

## 5. Validação final (doc 07)

- [ ] P1–P9 (testes positivos) comprovados.
- [ ] N1–N6 (testes negativos) comprovados, em especial:
  - [ ] SSH direto da Internet para as EC2s web falha.
  - [ ] PostgreSQL e Redis não respondem de fora da VPC.
  - [ ] Nenhum SG expõe 22/5432/6379 para `0.0.0.0/0`.
- [ ] Atualização sem downtime testada (uma instância por vez).
- [ ] Evidências registradas (prints/curl) conforme doc 07 §6.

## 6. Requisitos da atividade → onde estão atendidos

| Requisito | Atendido em |
|---|---|
| VPCs com blocos distintos e sem sobreposição | `02-arquitetura-e-rede.md` §2 |
| Recursos em subnets públicas/privadas conforme necessidade | `02-arquitetura-e-rede.md` §2 e §4 |
| ALB para receber as requisições | `04-provisionamento-console.md` Bloco F, `06-deploy-da-aplicacao.md` |
| Subnets de aplicação ≥ 20 instâncias | `02-arquitetura-e-rede.md` §3 (251 IPs por `/24`) |
| Subnets de dados ≥ 25 recursos | `02-arquitetura-e-rede.md` §3 |
| App acessível pela Internet via ALB | `07-testes-e-validacao.md` P1 |
| PostgreSQL para persistência | `05-ec2-dados-e-bootstrap.md` §4, `07-testes-e-validacao.md` P5/P8 |
| Redis para armazenamento temporário | `05-ec2-dados-e-bootstrap.md` §4, `07-testes-e-validacao.md` P3 |
| PostgreSQL e Redis em ambientes distintos | `02-arquitetura-e-rede.md` §2 |
| Banco e cache inacessíveis da Internet | `03-security-groups.md`, `07-testes-e-validacao.md` N3/N4 |
| Recursos privados acessam a Internet para updates | `02-arquitetura-e-rede.md` §4, `07-testes-e-validacao.md` P6 |
| App acessa banco e cache via VPC Peering | `02-arquitetura-e-rede.md` §5, `07-testes-e-validacao.md` P2/P3/P7 |
| Comunicação controlada por Security Groups | `03-security-groups.md` |
| Route Tables somente com caminhos necessários | `02-arquitetura-e-rede.md` §4 |
| Expansão futura | `02-arquitetura-e-rede.md` §9 |
| Administração via Jump Host (sem SSH direto) | `05-ec2-dados-e-bootstrap.md` §6, `07-testes-e-validacao.md` N1/N2 |

## 7. Comandos de verificação rápida (cola)

```bash
# testes do repositório
bash tests/run_tests.sh

# infra local (docker compose)
docker compose -f app/docker-compose.yml config
docker compose -f app/docker-compose.yml up -d --build      # dev local (porta 8080)

# EC2 de aplicação
sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh app
curl -s localhost/health

# EC2 de dados
sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh postgres
sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh redis
```

## 8. O que apresentar

1. Diagrama `Arquitetura_AWS.drawio.png`.
2. Console: peering `Active`, rotas de peering, SGs, Target Group `Healthy`.
3. Mural aberto pelo DNS do ALB + `/health` com PostgreSQL/Redis `online`.
4. Testes negativos (timeouts) e o acesso equivalente pelo caminho correto (Jump Host).
5. `bash tests/run_tests.sh` executando verde.
