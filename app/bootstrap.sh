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

apt_update() {
  run env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
    apt-get -o DPkg::Lock::Timeout=120 update
}

apt_install() {
  run env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
    apt-get -o DPkg::Lock::Timeout=120 install -y "$@"
}

install_git() {
  if command -v git >/dev/null 2>&1; then
    return
  fi
  if command -v apt-get >/dev/null 2>&1; then
    apt_update
    apt_install git
  else
    echo "erro: apt-get não encontrado para instalar git" >&2
    exit 1
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    return
  fi
  if command -v apt-get >/dev/null 2>&1; then
    apt_update
    apt_install docker.io docker-compose-v2
    run systemctl enable --now docker
  else
    echo "erro: apt-get não encontrado para instalar docker" >&2
    exit 1
  fi
}

ensure_compose() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "erro: apt-get não encontrado para instalar o plugin docker compose" >&2
    exit 1
  fi
  apt_update
  apt_install docker-compose-v2
  if (( ! DRY_RUN )) && ! docker compose version >/dev/null 2>&1; then
    echo "erro: 'docker compose' indisponível; instale o pacote docker-compose-v2" >&2
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
ensure_compose
ensure_repo
compose_up
