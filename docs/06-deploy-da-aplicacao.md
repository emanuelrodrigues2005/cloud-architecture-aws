# 06 — Deploy da Aplicação

Este é o guia do que fazer **depois que a infraestrutura está montada e as EC2s configuradas** (docs 04 e 05). A ordem é sempre: **dados → aplicação → ALB**.

## 1. Pré-requisitos

- Infraestrutura dos blocos A–E do doc 04 criada (VPCs, subnets, rotas, peering, SGs, EC2s).
- Repositório público acessível: `https://github.com/emanuelrodrigues2005/cloud-architecture-aws.git` (as EC2s clonam daqui).
- Testes locais passando: `bash tests/run_tests.sh`.

## 2. Como o deploy funciona

Não há pipeline externo: cada EC2, no primeiro boot, roda o user data que instala o git, clona o repositório e executa o `app/bootstrap.sh` do seu papel. O script é **idempotente** — rodá-lo de novo atualiza o código (`git pull --ff-only`) e recria o container.

A configuração de conexão vem de variáveis de ambiente no `app/docker-compose.yml` parametrizado:

| Variável | Dev local (default) | Produção (EC2 de app) |
|---|---|---|
| `DB_HOST` | `postgres` | `10.1.1.10` |
| `REDIS_HOST` | `redis` | `10.1.2.10` |
| `APP_PORT` | `8080` | `80` |

Em produção não existe DNS de serviço do Compose entre hosts — a app conversa com os IPs privados da Data VPC via VPC Peering.

## 3. Etapa 1 — Camada de dados (Data VPC)

Confirme que o user data das EC2s `ec2-postgres` e `ec2-redis` terminou (pelo console, *EC2 → Instâncias → selecionar → Actions → Monitor and troubleshoot → Get system log*, ou pelo `docker ps` mostrando os containers).

Se precisar subir manualmente (contingência), rode em cada instância:

**PostgreSQL** (`ec2-postgres`, via SSM ou shell local):

```bash
cd /opt/cloud-architecture-aws/app
docker compose up -d postgres
docker logs mural_postgres
```

**Redis** (`ec2-redis`):

```bash
cd /opt/cloud-architecture-aws/app
docker compose up -d redis
docker logs mural_redis
```

Validação:

- `docker ps` mostra `mural_postgres` / `mural_redis` em `Up`;
- `ss -lntp | grep -E '5432|6379'` mostra as portas escutando.

## 4. Etapa 2 — Aplicação (Application VPC)

Em `ec2-app-01` e `ec2-app-02`, o user data já executou:

```bash
sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh app
```

O comando interno executado pelo script é:

```bash
cd /opt/cloud-architecture-aws/app
DB_HOST=10.1.1.10 REDIS_HOST=10.1.2.10 APP_PORT=80 docker compose up -d --no-deps --build app
```

O `--no-deps` é essencial: impede o Compose de tentar subir PostgreSQL e Redis **dentro** da EC2 de aplicação (eles vivem na Data VPC).

Validação em cada instância:

```bash
docker ps                          # mural_app em Up
curl -s localhost/health           # {"application":"online","postgresql":"online","redis":"online"}
```

Se `postgresql` ou `redis` aparecerem `offline`, o problema é rede/SG/peering — ver doc 08.

## 5. Etapa 3 — Application Load Balancer

Com as duas instâncias saudaveis localmente:

1. **Target Group** `tg-mural-app`: tipo *Instances*, HTTP porta **80**, VPC `vpc-app`, health check `/health` (código de sucesso `200`).
2. Registrar `ec2-app-01` e `ec2-app-02`.
3. **ALB** `alb-mural`: internet-facing, subnets `subnet-app-public-1a` e `subnet-app-public-1b`, SG `SG-ALB-PUBLIC`, listener HTTP 80 → `tg-mural-app`.

Aguarde o status dos alvos ficar `Healthy` (o primeiro health check leva ~30 s).

## 6. Etapa 4 — Teste externo

```bash
curl -i http://<dns-do-alb>/
curl -s http://<dns-do-alb>/health
```

Esperado: página HTML do mural (HTTP 200) e JSON com `"postgresql": "online"` e `"redis": "online"`.

Para provar a distribuição entre as duas instâncias, acompanhe os logs das duas ao mesmo tempo e recarregue a página várias vezes:

```bash
docker logs -f mural_app
```

Requisições devem aparecer nas duas instâncias.

## 7. Atualizando a aplicação (sem downtime)

Fluxo padrão, uma instância por vez:

1. Faça o push da mudança para o repositório (`git push origin main`).
2. Em `ec2-app-01`: `sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh app` (faz `git pull` + rebuild + recria o container).
3. Espere o alvo voltar a `Healthy` no Target Group.
4. Repita em `ec2-app-02`.

Enquanto uma instância reinicia, o ALB só manda tráfego para a outra. Para deploys mais rápidos, reduza o *deregistration delay* do Target Group (padrão 300 s → 30 s).

### Rollback

Se a nova versão falhar, volte para um commit anterior e recrie o container:

```bash
cd /opt/cloud-architecture-aws
sudo git fetch origin
sudo git checkout <commit-ou-tag-anterior>
cd app
DB_HOST=10.1.1.10 REDIS_HOST=10.1.2.10 APP_PORT=80 sudo docker compose up -d --no-deps --build app
```

Para voltar ao fluxo normal depois: `sudo git checkout main`.

## 8. Atualizando os serviços de dados

PostgreSQL e Redis só mudam quando você alterar o `app/docker-compose.yml` (versão da imagem, senha, etc.). Nesse caso, em cada instância:

```bash
cd /opt/cloud-architecture-aws
sudo git pull --ff-only
cd app
sudo docker compose up -d postgres   # ou redis
```

Os volumes (`postgres_data` / `redis_data`) preservam os dados entre recriações.

## 9. HTTPS (opcional)

A arquitetura prevê 80/443 no `SG-ALB-PUBLIC`. Para HTTPS:

1. Emita um certificado no **AWS Certificate Manager (ACM)** na região us-east-1 (requer um domínio válido).
2. Adicione um listener `HTTPS : 443` ao `alb-mural` com o certificado e encaminhamento para `tg-mural-app`.
3. Como o container fala HTTP, o ALB termina o TLS — nenhuma mudança na aplicação.
4. (Recomendado) deixe o listener 80 apenas redirecionando para 443.

Sem domínio, mantenha somente o listener HTTP 80.

## 10. Resumo operacional

| Ação | Comando (em cada instância) |
|---|---|
| Subir/atualizar a app | `sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh app` |
| Subir/atualizar o banco | `sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh postgres` |
| Subir/atualizar o cache | `sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh redis` |
| Ver containers | `docker ps` |
| Ver logs | `docker logs -f mural_app` (ou `mural_postgres` / `mural_redis`) |
| Teste local da app | `curl -s localhost/health` |
| Teste externo | `curl -s http://<dns-do-alb>/health` |
