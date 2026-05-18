#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
#  OmniRoute — Server deploy script
# ──────────────────────────────────────────────────────────────────────
#
#  Pulls the latest pre-built image from ghcr.io/thanhpk6120/omniroute
#  and recreates the container. Bind-mounted ./data is preserved.
#
#  Usage on server:
#    1. Copy this script + docker-compose.server.yml + .env to the server
#    2. chmod +x deploy-server.sh
#    3. ./deploy-server.sh                    # pulls :latest
#       ./deploy-server.sh v3.8.0.1           # pin to a specific version
#       ./deploy-server.sh --rollback v3.8.0.0
#
#  Safety:
#    • Backs up ./data automatically before each deploy (last 3 kept)
#    • Never uses `down -v` → named volumes (Redis) are preserved
#    • Bind-mount ./data is left untouched
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

cd "$(dirname "$0")"

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.server.yml}"
DATA_DIR="${DATA_DIR_HOST:-./data}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
KEEP_BACKUPS="${KEEP_BACKUPS:-3}"

if [ ! -f "${COMPOSE_FILE}" ]; then
  echo "[ERROR] ${COMPOSE_FILE} not found in $(pwd)" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "[ERROR] .env not found in $(pwd) — copy from .env.example and configure first" >&2
  exit 1
fi

# Parse args
ROLLBACK=0
TAG=""
for arg in "$@"; do
  case "$arg" in
    --rollback) ROLLBACK=1 ;;
    -*) echo "[ERROR] Unknown flag: $arg" >&2; exit 1 ;;
    *) TAG="$arg" ;;
  esac
done

if [ "${ROLLBACK}" -eq 1 ] && [ -z "${TAG}" ]; then
  echo "[ERROR] --rollback requires a version tag, e.g. ./deploy-server.sh --rollback v3.8.0.0" >&2
  exit 1
fi

if [ -n "${TAG}" ]; then
  export OMNIROUTE_IMAGE_TAG="${TAG}"
else
  export OMNIROUTE_IMAGE_TAG="${OMNIROUTE_IMAGE_TAG:-latest}"
fi

echo "──────────────────────────────────────────────────────────────"
echo " OmniRoute deploy"
echo " Compose:  ${COMPOSE_FILE}"
echo " Image:    ghcr.io/thanhpk6120/omniroute:${OMNIROUTE_IMAGE_TAG}"
echo " Mode:     $([ "${ROLLBACK}" -eq 1 ] && echo "rollback" || echo "update")"
echo "──────────────────────────────────────────────────────────────"

# ── 1. Backup data ────────────────────────────────────────────────
if [ -d "${DATA_DIR}" ]; then
  mkdir -p "${BACKUP_DIR}"
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP_FILE="${BACKUP_DIR}/data-${STAMP}.tar.gz"
  echo "[1/4] Backing up ${DATA_DIR} → ${BACKUP_FILE}"
  tar -czf "${BACKUP_FILE}" -C "$(dirname "${DATA_DIR}")" "$(basename "${DATA_DIR}")"

  # Prune old backups, keep newest N
  ls -1t "${BACKUP_DIR}"/data-*.tar.gz 2>/dev/null \
    | tail -n +"$((KEEP_BACKUPS + 1))" \
    | xargs -r rm -f
  echo "      ✓ Backup done. Kept ${KEEP_BACKUPS} most recent backups."
else
  echo "[1/4] No ${DATA_DIR} directory yet — first run, skipping backup."
  mkdir -p "${DATA_DIR}"
fi

# ── 2. Pull image ─────────────────────────────────────────────────
echo "[2/4] Pulling image..."
docker compose -f "${COMPOSE_FILE}" pull

# ── 3. Recreate container ─────────────────────────────────────────
echo "[3/4] Recreating container with new image..."
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans

# ── 4. Health check ───────────────────────────────────────────────
echo "[4/4] Waiting for healthcheck..."
for i in $(seq 1 30); do
  STATUS="$(docker inspect --format='{{.State.Health.Status}}' omniroute 2>/dev/null || echo unknown)"
  if [ "${STATUS}" = "healthy" ]; then
    echo "      ✓ omniroute is healthy."
    break
  fi
  if [ "${STATUS}" = "unhealthy" ]; then
    echo "[ERROR] omniroute became unhealthy. Last 50 log lines:" >&2
    docker compose -f "${COMPOSE_FILE}" logs --tail 50 omniroute >&2
    exit 1
  fi
  printf "      ... status=%s (%d/30)\r" "${STATUS}" "$i"
  sleep 2
done

if [ "${STATUS}" != "healthy" ]; then
  echo "[WARN] omniroute did not reach healthy state in 60s — check logs." >&2
  docker compose -f "${COMPOSE_FILE}" logs --tail 50 omniroute >&2
fi

echo
echo "──────────────────────────────────────────────────────────────"
echo " Done. Currently running:"
docker compose -f "${COMPOSE_FILE}" ps
echo "──────────────────────────────────────────────────────────────"
