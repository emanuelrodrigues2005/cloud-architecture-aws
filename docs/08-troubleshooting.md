# 08 — Troubleshooting

Erros mais comuns e como diagnosticar, na ordem em que costumam aparecer.

## 1. O alvo (EC2 da app) não fica `Healthy` no Target Group

Sintomas: ALB responde `502 Bad Gateway` ou `504 Gateway Timeout`; alvos em `unhealthy`.

Checklist:

1. **Container está de pé?** Na EC2: `docker ps` e `docker logs mural_app`. Se estiver reiniciando em loop, veja o erro no log (muito comum: não achou o PostgreSQL).
2. **A aplicação responde localmente?** `curl -s localhost/health`. Se falhar, o problema é na instância; se responder, é rede/SG.
3. **Porta publicada correta?** O container é publicado em `APP_PORT` (produção: 80). `docker ps` mostra `0.0.0.0:80->8080/tcp`.
4. **`SG-EC2-WEB` permite 80 a partir de `SG-ALB-PUBLIC`?** Console → VPC → Security Groups.
5. **Health check do TG está em `/health`, HTTP 80, sucesso `200`?** Um caminho errado (`/` com redirecionamento, por exemplo) marca o alvo como unhealthy se não retornar 200.
6. **A instância foi registrada na porta certa?** O TG usa "traffic port" (80).

## 2. A página do ALB abre, mas `/health` mostra PostgreSQL/Redis `offline`

Sintoma: `{"application":"online","postgresql":"offline","redis":"offline"}`.

Checklist:

1. **Containers de dados de pé?** Nas EC2s da Data VPC: `docker ps`.
2. **IPs corretos?** Na app: `docker inspect mural_app | grep -A5 DB_HOST` ou `env` dentro do container. Esperado `10.1.1.10` e `10.1.2.10`. Se estiver `postgres`/`redis` (defaults de dev), o `--no-deps` ou as variáveis não foram passadas — rode `sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh app`.
3. **Peering ativo?** Console → VPC → Peering connections → status `Active`.
4. **Rotas de peering nos dois lados?** `rt-app-public` precisa de `10.1.0.0/16 → pcx`; `rt-data-private` precisa de `10.0.0.0/16 → pcx`. Falta da rota de volta = timeout (conexão abre e nada responde).
5. **SGs de dados permitem `SG-EC2-WEB`?** `SG-POSTGRESQL` 5432 e `SG-REDIS` 6379 com origem `SG-EC2-WEB`.
6. **Teste binário** na EC2 de app: `timeout 3 bash -c '</dev/tcp/10.1.1.10/5432' && echo ok`. Sem `ok` → rede/SG; com `ok` → aplicação/credenciais.

## 3. VPC Peering não sai de `Pending`

- O pedido precisa ser **aceito** no lado aceitador (*Actions → Accept request*). Mesmo na mesma conta, não é automático.

## 4. Regras de SG "não aparecem" ou ficam obsoletas

- Referência de SG entre VPCs exige **peering ativo** e **mesma região**; se o SG da outra VPC não aparece na busca, confirme os dois.
- Se o peering foi deletado, as regras que o referenciavam viram *stale*: revogue e recrie após reconectar.

## 5. Recursos privados sem acesso à Internet (não atualizam)

Sintoma: `dnf update`/`curl https://...` pendura na EC2 do PostgreSQL ou Redis.

Checklist:

1. **NAT Gateway existe e está `Available`?** Console → VPC → NAT gateways.
2. **NAT está na subnet pública certa?** `subnet-data-public-1a` (precisa de rota para o IGW).
3. **A Route Table privada tem `0.0.0.0/0 → nat-data`?** E ela está associada às duas subnets privadas?
4. **Elastic IP alocado?** Sem EIP o NAT não é criado.

## 6. `git clone` falha na EC2

Sintoma: no log do user data ou ao rodar o bootstrap, `Could not resolve host` / timeout.

Checklist:

1. **A instância tem IP público?** (app/jumphost). Confira *auto-assign public IPv4* na subnet e o IP na instância.
2. **`SG-EC2-WEB` permite saída 443 para `0.0.0.0/0`?**
3. **Repositório é público?** Se virou privado, o clone sem credencial falha (o projeto assume repositório público).
4. **A instância de dados consegue clonar?** Ela sai pelo NAT — valide o item 5.

## 7. User data não executou (ou falhou)

- O user data roda apenas no **primeiro boot**. Instância criada sem ele não roda depois.
- Log: `sudo cat /var/log/cloud-init-output.log`.
- Solução: rodar o bootstrap manualmente (doc 05 §5).

## 8. `docker: command not found` ou `permission denied`

- `command not found`: instale via bootstrap (`sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh <papel>`) ou `sudo dnf install -y docker && sudo systemctl enable --now docker`.
- `permission denied while trying to connect to the Docker daemon`: use `sudo docker ...` ou entre no grupo: `sudo usermod -aG docker ec2-user` (reconecte a sessão SSH). Os scripts do projeto usam `sudo`.

## 9. SSH pelo Jump Host falha

- `Permission denied (publickey)`: use `ssh -A` (agent forwarding) da sua máquina para o Jump; a chave não fica no Jump.
- `Connection timed out` no segundo salto: o `SG-EC2-WEB` precisa aceitar 22 **de `SG-JUMPHOST`**.
- `Connection timed out` no Jump: o `SG-JUMPHOST` só aceita 22 do seu IP `/32` — confirme o IP e atualize a regra se ele mudar.

## 10. Redis: `NOAUTH Authentication required` / `WRONGPASS`

- O compose sobe o Redis com `--requirepass` e a app usa a mesma senha default (`12345678`). Se você mudou a senha no compose de um lado, mude do outro via variável `REDIS_PASSWORD` no momento da subida, ou ajuste o compose e recrie os dois containers.

## 11. PostgreSQL: `connection refused` x `timeout`

- **Refused**: chegou no host, mas nada escutando na 5432 → container do banco não subiu.
- **Timeout**: pacote não chega → falta rota de peering, SG bloqueando ou IP errado.

## 12. Reset geral de uma instância

```bash
sudo bash /opt/cloud-architecture-aws/app/bootstrap.sh app   # ou postgres / redis
docker ps
docker logs --tail 100 mural_app                            # ou mural_postgres / mural_redis
```

O bootstrap é idempotente: atualiza o código e recria o container sem apagar volumes (`postgres_data`, `redis_data`).
