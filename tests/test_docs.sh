#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$ROOT_DIR/docs"
failures=0

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc (não encontrado: '$needle')"
    failures=$((failures + 1))
  fi
}

assert_file() {
  local file="$1"
  if [[ -f "$DOCS_DIR/$file" ]]; then
    echo "ok - existe docs/$file"
  else
    echo "FAIL - não existe docs/$file"
    failures=$((failures + 1))
  fi
}

expected_files=(
  00-indice-e-visao-geral.md
  01-fundamentos-aws.md
  02-arquitetura-e-rede.md
  03-security-groups.md
  04-provisionamento-console.md
  05-ec2-dados-e-bootstrap.md
  06-deploy-da-aplicacao.md
  07-testes-e-validacao.md
  08-troubleshooting.md
  09-checklist-entrega.md
)

for expected_file in "${expected_files[@]}"; do
  assert_file "$expected_file"
done

docs_content="$(cat "$DOCS_DIR"/*.md 2>/dev/null || true)"

network_facts=(
  "10.0.0.0/16"
  "10.1.0.0/16"
  "10.0.0.0/24"
  "10.0.1.0/24"
  "10.1.0.0/24"
  "10.1.1.0/24"
  "10.1.2.0/24"
  "10.1.1.10"
  "10.1.2.10"
  "Application VPC"
  "Data VPC"
  "VPC Peering"
  "Internet Gateway"
  "NAT Gateway"
  "Elastic IP"
  "Route Table"
  "Jump Host"
  "Application Load Balancer"
  "us-east-1"
)
for fact in "${network_facts[@]}"; do
  assert_contains "docs contêm '$fact'" "$fact" "$docs_content"
done

security_facts=(
  "SG-ALB-PUBLIC"
  "SG-EC2-WEB"
  "SG-JUMPHOST"
  "SG-POSTGRESQL"
  "SG-REDIS"
  "5432"
  "6379"
  "443"
)
for fact in "${security_facts[@]}"; do
  assert_contains "docs contêm '$fact'" "$fact" "$docs_content"
done

sizing_facts=(
  "20 instâncias"
  "25 recursos"
  "251"
)
for fact in "${sizing_facts[@]}"; do
  assert_contains "docs contêm '$fact'" "$fact" "$docs_content"
done

deploy_facts=(
  "Amazon Linux 2023"
  "bootstrap.sh"
  "--no-deps"
  "APP_PORT=80"
  "DB_HOST=10.1.1.10"
  "REDIS_HOST=10.1.2.10"
  "/health"
  "tests/run_tests.sh"
  "docker compose up -d postgres"
  "docker compose up -d redis"
)
for fact in "${deploy_facts[@]}"; do
  assert_contains "docs contêm '$fact'" "$fact" "$docs_content"
done

if (( failures > 0 )); then
  echo "FALHOU: $failures asserção(ões)"
  exit 1
fi

echo "docs: todas as asserções passaram"
