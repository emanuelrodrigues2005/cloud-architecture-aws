# 05 — EC2, Dados e Bootstrap

Este documento cobre AMI, tipos, user data, o script `app/bootstrap.sh` e a operação do PostgreSQL e do Redis nas EC2s privadas.

## 1. Especificação das instâncias

| Instância | AMI | Tipo | Subnet | IP privado | Papel |
|---|---|---|---|---|---|
| `ec2-jumphost` | Amazon Linux 2023 | t3.micro | `subnet-app-public-1a` | automático | Acesso SSH administrativo |
| `ec2-app-01` | Amazon Linux 2023 | t3.micro | `subnet-app-public-1a` | automático | Aplicação Web (container) |
| `ec2-app-02` | Amazon Linux 2023 | t3.micro | `subnet-app-public-1b` | automático | Aplicação Web (container) |
| `ec2-postgres` | Amazon Linux 2023 | t3.micro | `subnet-data-private-1a` | `10.1.1.10` | PostgreSQL 16 (container) |
| `ec2-redis` | Amazon Linux 2023 | t3.micro | `subnet-data-private-1b` | `10.1.2.10` | Redis 7 (container) |

- Key pair: o mesmo par criado em us-east-1 para as cinco instâncias.
- As EC2s da aplicação e o Jump Host precisam de **IP público** (subnet pública com auto-assign) para `git clone` e SSH.
- PostgreSQL e Redis ficam sem IP público; saída à Internet via NAT Gateway.

## 2. `app/bootstrap.sh` — inicialização idempotente

O script é o mesmo para as três funções e pode ser rodado de novo sem problema (atualiza o repositório e sobe o container):

```bash
bash app/bootstrap.sh app        # EC2 Application
bash app/bootstrap.sh postgres   # EC2 PostgreSQL
bash app/bootstrap.sh redis      # EC2 Redis
```

O que ele faz, em ordem:

1. Instala `git` e `docker` (via `dnf` no Amazon Linux 2023; há suporte a `apt-get`), habilita o serviço Docker.
2. Garante o repositório em `/opt/cloud-architecture-aws`:
   - não existe → `git clone` do repositório público;
   - existe → `git pull --ff-only` (atualiza).
3. Sobe o container do papel:
   - `app`: `DB_HOST=10.1.1.10 REDIS_HOST=10.1.2.10 APP_PORT=80 docker compose up -d --no-deps --build app`
   - `postgres`: `docker compose up -d postgres`
   - `redis`: `docker compose up -d redis`

Variáveis suportadas (com defaults):

| Variável | Default | Uso |
|---|---|---|
| `APP_DIR` | `/opt/cloud-architecture-aws` | Onde clonar/atualizar o repositório |
| `POSTGRES_IP` | `10.1.1.10` | IP privado do banco |
| `REDIS_IP` | `10.1.2.10` | IP privado do cache |
| `APP_PORT` | `80` | Porta publicada no host da aplicação (porta que o ALB usa) |

Para inspecionar sem alterar nada:

```bash
bash app/bootstrap.sh --dry-run app
```

## 3. User data de cada EC2 (colar no lançamento)

O user data roda **uma vez, no primeiro boot**. Ele instala o git, clona o repositório e chama o `bootstrap.sh` do papel correspondente.

**EC2 Application (`ec2-app-01` e `ec2-app-02`):**

```bash
#!/bin/bash
set -eux
dnf install -y git
git clone https://github.com/emanuelrodrigues2005/cloud-architecture-aws.git /opt/cloud-architecture-aws
bash /opt/cloud-architecture-aws/app/bootstrap.sh app
```

**EC2 PostgreSQL (`ec2-postgres`):**

```bash
#!/bin/bash
set -eux
dnf install -y git
git clone https://github.com/emanuelrodrigues2005/cloud-architecture-aws.git /opt/cloud-architecture-aws
bash /opt/cloud-architecture-aws/app/bootstrap.sh postgres
```

**EC2 Redis (`ec2-redis`):**

```bash
#!/bin/bash
set -eux
dnf install -y git
git clone https://github.com/emanuelrodrigues2005/cloud-architecture-aws.git /opt/cloud-architecture-aws
bash /opt/cloud-architecture-aws/app/bootstrap.sh redis
```

**Jump Host:** sem user data. Ele só precisa do SG correto e da chave SSH.

> O `bootstrap.sh` instala o Docker porque o user data instala apenas o git (necessário para clonar). O restante é responsabilidade do script.

## 4. O que roda em cada container

### PostgreSQL (`ec2-postgres`)

- Imagem `postgres:16`, volume persistente `postgres_data`, banco `mural`, usuário `mural_user`.
- Publica `5432:5432`; aceita conexão apenas de `SG-EC2-WEB` (via VPC Peering).
- Volume: os dados sobrevivem a `docker compose down` / restart da instância.
- Verificação: `docker logs mural_postgres` deve mostrar `database system is ready to accept connections`.

### Redis (`ec2-redis`)

- Imagem `redis:7`, volume `redis_data`, senha obrigatória (`--requirepass`).
- Publica `6379:6379`; aceita conexão apenas de `SG-EC2-WEB`.
- Verificação: `docker logs mural_redis` deve mostrar `Ready to accept connections`.

### Aplicação (`ec2-app-01/02`)

- Imagem construída do `app/Dockerfile`; o processo é `python app.py`, que roda `init_db()` (cria a tabela `messages` se não existir) e sobe o servidor em `0.0.0.0:8080` dentro do container.
- No host, a porta `80` é publicada (`APP_PORT=80` → `8080` do container), compatível com o `SG-EC2-WEB` (80/443).
- Sem volume: é stateless, pode ser recriada a qualquer momento.

## 5. Instalação manual (sem user data)

Se a instância já subiu sem user data, faça SSH (no caso das EC2s da aplicação, pelo Jump Host) e rode:

```bash
sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh app
```

Se o repositório ainda não estiver clonado:

```bash
sudo dnf install -y git
sudo git clone https://github.com/emanuelrodrigues2005/cloud-architecture-aws.git /opt/cloud-architecture-aws
sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh app
```

Para os serviços de dados, os mesmos passos trocando o papel (`postgres` / `redis`). Como o user data já faz isso no primeiro boot, o caminho manual é apenas contingência.

## 6. Acesso administrativo

### Pelo Jump Host (caminho previsto)

1. Da sua máquina: `ssh -A -i chave.pem ec2-user@<IP-público-do-jumphost>` (`-A` habilita o encaminhamento do agente SSH).
2. Do Jump Host: `ssh ec2-user@<IP-privado-da-app>` (usa sua chave encaminhada).

Assim a chave privada nunca é copiada para o Jump Host.

### PostgreSQL e Redis

O `SG-JUMPHOST` só permite saída SSH para `SG-EC2-WEB`; portanto o Jump Host **não acessa** as instâncias de dados diretamente. A configuração delas é feita por user data/`bootstrap.sh`.

Se precisar de um shell nelas para um diagnóstico pontual, duas opções:

- **Temporária**: adicione uma regra de entrada SSH 22 no `SG-POSTGRESQL`/`SG-REDIS` com origem `SG-JUMPHOST`, faça o diagnóstico e **remova a regra** em seguida.
- **Recomendada para produção**: usar o **AWS Systems Manager Session Manager** (exige uma IAM role com `AmazonSSMManagedInstanceCore` na instância; a saída pelo NAT já existe). Não abre porta alguma.

## 7. Verificações rápidas em cada host

| Host | Comando | Esperado |
|---|---|---|
| app | `curl -s localhost/health` | JSON com `"application": "online"` |
| app | `docker ps` | `mural_app` em `Up` |
| postgres | `docker ps` | `mural_postgres` em `Up` |
| postgres | `ss -lntp \| grep 5432` | porta `5432` escutando |
| redis | `docker ps` | `mural_redis` em `Up` |
| redis | `ss -lntp \| grep 6379` | porta `6379` escutando |
