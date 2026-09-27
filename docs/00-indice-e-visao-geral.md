# 00 — Índice e Visão Geral

Documentação da implementação da arquitetura AWS do **Projeto AMPLIA UFRPE**.

## Fontes da atividade

| Artefato | Papel |
|---|---|
| `PROJETO_AMPLIA_UFRPE.pdf` | Enunciado e requisitos obrigatórios |
| `Arquitetura_Cloud_AWS_final.pdf` | Documento de arquitetura produzido pela equipe |
| `Arquitetura_AWS.drawio.png` | Desenho final da arquitetura (VPCs, subnets, SGs, rotas) |
| `Arquitetura_AWS_AMPLIA_UFRPE.drawio` | Fonte editável do desenho |
| `app/` | Aplicação Web Flask ("Mural da Turma") já pronta |

## A solução em uma página

- Aplicação Web Flask (`app/app.py` + `app/templates/index.html`) com persistência em **PostgreSQL** e armazenamento temporário em **Redis**.
- **Application VPC (10.0.0.0/16)**: Application Load Balancer (ALB) público, duas instâncias EC2 da aplicação em subnets públicas distintas (AZ-1 e AZ-2) e um Jump Host.
- **Data VPC (10.1.0.0/16)**: PostgreSQL e Redis em subnets privadas separadas, cada um em sua própria EC2.
- Comunicação entre as VPCs exclusivamente por **VPC Peering**, liberada apenas nas portas 5432 (PostgreSQL) e 6379 (Redis).
- Recursos privados saem para a Internet apenas para atualizações, via **NAT Gateway** na Data VPC.
- Acesso administrativo à aplicação somente via **Jump Host**; banco e cache não aceitam acesso da Internet.

## Estrutura do repositório

```
app/
  app.py                  aplicação Flask (rotas /, /messages, /messages/clear, /health)
  templates/index.html    interface do mural
  Dockerfile              imagem da aplicação
  docker-compose.yml      orquestração parametrizável (dev e EC2)
  bootstrap.sh            inicialização idempotente das EC2 (app|postgres|redis)
docs/                     esta documentação (00 a 09)
PROJETO_AMPLIA_UFRPE.pdf  enunciado
Arquitetura_Cloud_AWS_final.pdf
Arquitetura_AWS.drawio.png
```

## Ordem de leitura

1. `00-indice-e-visao-geral.md` (este arquivo)
2. `01-fundamentos-aws.md` — como cada peça da AWS funciona
3. `02-arquitetura-e-rede.md` — CIDRs, subnets, rotas e peering
4. `03-security-groups.md` — regras de firewall por componente
5. `04-provisionamento-console.md` — passo a passo no console AWS
6. `05-ec2-dados-e-bootstrap.md` — EC2, user data, PostgreSQL e Redis
7. `06-deploy-da-aplicacao.md` — deploy, ALB, atualização e rollback
8. `07-testes-e-validacao.md` — validação dos requisitos (positivos e negativos)
9. `08-troubleshooting.md` — erros comuns e correções
10. `09-checklist-entrega.md` — requisito → evidência

## Pré-requisitos

- Conta AWS com permissões de VPC, EC2 e ELB na região **us-east-1 (N. Virginia)**.
- Repositório público já publicado: `https://github.com/emanuelrodrigues2005/cloud-architecture-aws.git`.
- Par de chaves (key pair) criado na região para acesso SSH ao Jump Host.

## Conferência da configuração

Antes de subir para a AWS, confira que o Compose resolve as variáveis e que o bootstrap mostra os comandos certos de cada papel (sem alterar nada):

```bash
docker compose -f app/docker-compose.yml config
bash app/bootstrap.sh --dry-run app
```

## Decisões resumidas

1. **Duas VPCs** (aplicação e dados) para isolar os serviços críticos.
2. **VPC Peering** entre elas, com rotas específicas nos dois lados.
3. **ALB** como única entrada pública da aplicação.
4. **Duas subnets públicas** na aplicação (AZ-1 e AZ-2) para disponibilidade.
5. **PostgreSQL e Redis privados**, em EC2s separadas, sem exposição à Internet.
6. **Security Groups** por função, com origem/destino por referência de SG e princípio do menor privilégio.
7. **Jump Host** para administração; EC2s da aplicação não recebem SSH da Internet.
8. **Compose parametrizado + `bootstrap.sh`**: um único `docker-compose.yml` serve o desenvolvimento local (defaults) e as três EC2s de produção (variáveis de ambiente), sem arquivos duplicados.

## Fluxo de implantação (resumo)

```
1. Provisionar redes (VPCs, subnets, IGW, NAT, Route Tables, Peering)   → docs 02 e 04
2. Criar Security Groups                                                → docs 03 e 04
3. Criar EC2s com user data (bootstrap.sh)                              → doc 05
4. Subir PostgreSQL e Redis (Data VPC)                                  → docs 05 e 06
5. Subir a aplicação (Application VPC) e validar /health                → doc 06
6. Criar ALB + Target Group e registrar as instâncias                   → docs 04 e 06
7. Testar pela Internet e validar requisitos                            → doc 07
```
