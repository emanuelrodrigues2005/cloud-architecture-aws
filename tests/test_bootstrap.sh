#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$ROOT_DIR/app/bootstrap.sh"
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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc (não encontrado: '$needle')"
    failures=$((failures + 1))
  fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
fake_app_dir="$tmp_dir/repo"

out="$(APP_DIR="$fake_app_dir" bash "$BOOTSTRAP" 2>&1)"
assert_eq "sem papel: exit 2" "2" "$?"
assert_contains "sem papel: mostra uso" "uso:" "$out"

out="$(APP_DIR="$fake_app_dir" bash "$BOOTSTRAP" database 2>&1)"
assert_eq "papel inválido: exit 2" "2" "$?"
assert_contains "papel inválido: mostra uso" "uso:" "$out"

out="$(APP_DIR="$fake_app_dir" bash "$BOOTSTRAP" --help 2>&1)"
assert_eq "--help: exit 0" "0" "$?"
assert_contains "--help: mostra uso" "uso:" "$out"

out="$(APP_DIR="$fake_app_dir" bash "$BOOTSTRAP" --dry-run app 2>&1)"
assert_eq "dry-run app: exit 0" "0" "$?"
assert_contains "dry-run app: clona o repositório" "git clone" "$out"
assert_contains "dry-run app: usa IP privado do PostgreSQL" "DB_HOST=10.1.1.10" "$out"
assert_contains "dry-run app: usa IP privado do Redis" "REDIS_HOST=10.1.2.10" "$out"
assert_contains "dry-run app: publica na porta 80 (ALB)" "APP_PORT=80" "$out"
assert_contains "dry-run app: sobe sem dependências e com build" "up -d --no-deps --build app" "$out"
assert_eq "dry-run não altera o sistema" "ausente" "$([[ -e "$fake_app_dir" ]] && echo presente || echo ausente)"

out="$(APP_DIR="$fake_app_dir" bash "$BOOTSTRAP" --dry-run postgres 2>&1)"
assert_eq "dry-run postgres: exit 0" "0" "$?"
assert_contains "dry-run postgres: sobe apenas o postgres" "up -d postgres" "$out"

out="$(APP_DIR="$fake_app_dir" bash "$BOOTSTRAP" --dry-run redis 2>&1)"
assert_eq "dry-run redis: exit 0" "0" "$?"
assert_contains "dry-run redis: sobe apenas o redis" "up -d redis" "$out"

if (( failures > 0 )); then
  echo "FALHOU: $failures asserção(ões)"
  exit 1
fi

echo "bootstrap: todas as asserções passaram"
