#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

if [[ ! -f .env ]]; then
  echo "ERROR: falta ${APP_DIR}/.env. Ejecuta el asistente PowerShell de despliegue." >&2
  exit 1
fi
if [[ ! -s deploy/certs/ca.crt || ! -s deploy/certs/server-fullchain.pem || ! -s deploy/certs/server.key ]]; then
  echo "ERROR: faltan certificados SQL. Repite el bootstrap del VPS." >&2
  exit 1
fi

# Solo repo público: no se almacena un token de GitHub en el servidor.
git fetch origin
git checkout main
git pull --ff-only origin main

docker compose --env-file .env config --quiet
# Compila antes de iniciar SQL Server: reduce la presión de memoria durante el build Angular.
docker compose build api frontend
docker compose up -d sqlserver
# Se fuerza el contenedor one-shot para aplicar scripts idempotentes y carga inicial.
docker compose up -d --force-recreate db-init
for i in $(seq 1 180); do
  state="$(docker inspect -f '{{.State.Status}}' red-solidaria-db-init 2>/dev/null || true)"
  exit_code="$(docker inspect -f '{{.State.ExitCode}}' red-solidaria-db-init 2>/dev/null || echo 1)"
  if [[ "$state" == "exited" && "$exit_code" == "0" ]]; then break; fi
  if [[ "$state" == "exited" && "$exit_code" != "0" ]]; then
    docker compose logs --tail=160 db-init
    echo "ERROR: inicialización de SQL Server fallida." >&2
    exit 1
  fi
  sleep 5
done
if [[ "$(docker inspect -f '{{.State.Status}}' red-solidaria-db-init 2>/dev/null || true)" != "exited" || "$(docker inspect -f '{{.State.ExitCode}}' red-solidaria-db-init 2>/dev/null || echo 1)" != "0" ]]; then
  docker compose logs --tail=160 db-init
  echo "ERROR: timeout esperando inicialización de SQL Server." >&2
  exit 1
fi

docker compose up -d --build api frontend caddy
docker compose ps

DOMAIN="$(grep -E '^DOMAIN=' .env | tail -1 | cut -d= -f2-)"
if [[ -z "$DOMAIN" ]]; then echo "ERROR: DOMAIN no está configurado en .env" >&2; exit 1; fi
for i in $(seq 1 90); do
  if curl --fail --silent --show-error "https://${DOMAIN}/health/db" >/dev/null 2>&1; then break; fi
  sleep 5
done

printf '\nHealth API: '
curl --fail --silent --show-error "https://${DOMAIN}/health"
printf '\nHealth SQL: '
curl --fail --silent --show-error "https://${DOMAIN}/health/db"
printf '\nLogin admin HTTP: '
ADMIN_USER="$(grep -E '^SEED_ADMIN_USERNAME=' .env | tail -1 | cut -d= -f2-)"
ADMIN_PASS="$(grep -E '^SEED_ADMIN_PASSWORD=' .env | tail -1 | cut -d= -f2-)"
STATUS="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  -H 'Content-Type: application/json' \
  -X POST "https://${DOMAIN}/api/v1/auth/login" \
  --data "{\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}")"
if [[ "$STATUS" != "200" ]]; then
  echo "${STATUS} (esperado 200)" >&2
  docker compose logs --tail=100 api db-init caddy
  exit 1
fi
echo "${STATUS} OK"
echo "DESPLIEGUE VERIFICADO: https://${DOMAIN}"
