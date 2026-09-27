#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/emanuelrodrigues2005/cloud-architecture-aws.git"
APP_DIR="${APP_DIR:-/opt/cloud-architecture-aws}"
POSTGRES_IP="${POSTGRES_IP:-10.1.1.10}"
REDIS_IP="${REDIS_IP:-10.1.2.10}"
APP_PORT="${APP_PORT:-80}"
COMPOSE_FILE="$APP_DIR/app/docker-compose.yml"

DRY_RUN=0
ROLE=""

usage() {
  echo "uso: $0 [--dry-run] <app|postgres|redis>" >&2
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    app|postgres|redis)
      if [[ -n "$ROLE" ]]; then
        usage
        exit 2
      fi
      ROLE="$arg"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$ROLE" ]]; then
  usage
  exit 2
fi

run() {
  if (( DRY_RUN )); then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

install_git() {
  if command -v git >/dev/null 2>&1; then
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    run dnf install -y git
  elif command -v apt-get >/dev/null 2>&1; then
    run apt-get update
    run apt-get install -y git
  else
    echo "erro: gerenciador de pacotes não suportado para instalar git" >&2
    exit 1
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    run dnf install -y docker
    run systemctl enable --now docker
  elif command -v apt-get >/dev/null 2>&1; then
    run apt-get update
    run apt-get install -y docker.io
    run systemctl enable --now docker
  else
    echo "erro: gerenciador de pacotes não suportado para instalar docker" >&2
    exit 1
  fi
}

ensure_repo() {
  if [[ -d "$APP_DIR/.git" ]]; then
    run git -C "$APP_DIR" pull --ff-only
  elif [[ -e "$APP_DIR" ]]; then
    echo "erro: $APP_DIR existe e não é um repositório git" >&2
    exit 1
  else
    run git clone "$REPO_URL" "$APP_DIR"
  fi
}

compose_up() {
  case "$ROLE" in
    app)
      run env DB_HOST="$POSTGRES_IP" REDIS_HOST="$REDIS_IP" APP_PORT="$APP_PORT" \
        docker compose -f "$COMPOSE_FILE" up -d --no-deps --build app
      ;;
    postgres)
      run docker compose -f "$COMPOSE_FILE" up -d postgres
      ;;
    redis)
      run docker compose -f "$COMPOSE_FILE" up -d redis
      ;;
  esac
}

install_git
install_docker
ensure_repo
compose_up
