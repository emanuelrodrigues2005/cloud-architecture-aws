#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/app/docker-compose.yml"
failures=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc (esperado: '$expected', obtido: '$actual')"
    failures=$((failures + 1))
  fi
}

query() {
  python3 -c "import json, sys; cfg = json.load(sys.stdin); print($1)"
}

service_env() {
  printf '%s' "$1" | query "cfg['services']['$2']['environment']['$3']"
}

service_port() {
  printf '%s' "$1" | query "cfg['services']['$2']['ports'][0]['$3']"
}

service_restart() {
  printf '%s' "$1" | query "cfg['services']['$2'].get('restart')"
}

dev_cfg="$(docker compose -f "$COMPOSE_FILE" config --format json)"
prod_cfg="$(DB_HOST=10.1.1.10 REDIS_HOST=10.1.2.10 APP_PORT=80 docker compose -f "$COMPOSE_FILE" config --format json)"

assert_eq "dev: DB_HOST usa o serviço postgres" "postgres" "$(service_env "$dev_cfg" app DB_HOST)"
assert_eq "dev: REDIS_HOST usa o serviço redis" "redis" "$(service_env "$dev_cfg" app REDIS_HOST)"
assert_eq "dev: publica 8080 no host" "8080" "$(service_port "$dev_cfg" app published)"
assert_eq "dev: container escuta 8080" "8080" "$(service_port "$dev_cfg" app target)"

assert_eq "prod: DB_HOST aponta para o IP privado do PostgreSQL" "10.1.1.10" "$(service_env "$prod_cfg" app DB_HOST)"
assert_eq "prod: REDIS_HOST aponta para o IP privado do Redis" "10.1.2.10" "$(service_env "$prod_cfg" app REDIS_HOST)"
assert_eq "prod: publica 80 no host (ALB)" "80" "$(service_port "$prod_cfg" app published)"
assert_eq "prod: container continua em 8080" "8080" "$(service_port "$prod_cfg" app target)"

for svc in app postgres redis; do
  assert_eq "restart de $svc é unless-stopped" "unless-stopped" "$(service_restart "$dev_cfg" "$svc")"
done

if (( failures > 0 )); then
  echo "FALHOU: $failures asserção(ões)"
  exit 1
fi

echo "compose: todas as asserções passaram"
