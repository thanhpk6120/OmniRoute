#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
#  OmniRoute — Deploy script (build local từ git source)
# ──────────────────────────────────────────────────────────────────────
#
#  Usage:
#    ./deploy-server.sh                # git pull + build + restart
#    ./deploy-server.sh --skip-pull    # chỉ build lại, không pull
#    ./deploy-server.sh --rollback     # quay về image trước đó
#
set -euo pipefail

cd "$(dirname "$0")/.."

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.server.yml}"
SKIP_PULL=false
ROLLBACK=false

for arg in "$@"; do
  case "$arg" in
    --skip-pull) SKIP_PULL=true ;;
    --rollback)  ROLLBACK=true ;;
  esac
done

# ── Rollback ──────────────────────────────────────────────────────────
if [ "$ROLLBACK" = true ]; then
  PREV=$(docker images omniroute --format '{{.Tag}} {{.CreatedAt}}' | grep -v local | sort -k2 -r | head -1 | awk '{print $1}')
  if [ -z "$PREV" ]; then
    echo "❌ Không tìm thấy image cũ để rollback"
    exit 1
  fi
  echo "🔄 Rolling back to omniroute:$PREV"
  docker tag "omniroute:$PREV" omniroute:local
  docker compose -f "$COMPOSE_FILE" up -d --force-recreate
  echo "✅ Rollback done"
  exit 0
fi

# ── Backup data ───────────────────────────────────────────────────────
if [ -d "./data" ]; then
  BACKUP_DIR="./backups"
  mkdir -p "$BACKUP_DIR"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  tar -czf "$BACKUP_DIR/data_$TIMESTAMP.tar.gz" ./data 2>/dev/null || true
  # Giữ 3 bản backup gần nhất
  ls -t "$BACKUP_DIR"/data_*.tar.gz 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null || true
  echo "📦 Backed up ./data → $BACKUP_DIR/data_$TIMESTAMP.tar.gz"
fi

# ── Git pull ──────────────────────────────────────────────────────────
if [ "$SKIP_PULL" = false ]; then
  echo "📥 Pulling latest code..."
  git pull --ff-only || { echo "❌ Git pull failed (có conflict?)"; exit 1; }
fi

# ── Tag image cũ trước khi build (cho rollback) ──────────────────────
OLD_IMAGE=$(docker images omniroute:local --format '{{.ID}}' 2>/dev/null || true)
if [ -n "$OLD_IMAGE" ]; then
  PREV_TAG="prev-$(date +%Y%m%d%H%M%S)"
  docker tag omniroute:local "omniroute:$PREV_TAG" 2>/dev/null || true
fi

# ── Build ─────────────────────────────────────────────────────────────
echo "🔨 Building image..."
docker compose -f "$COMPOSE_FILE" build --no-cache

# ── Restart ───────────────────────────────────────────────────────────
echo "🚀 Restarting container..."
docker compose -f "$COMPOSE_FILE" up -d --force-recreate

# ── Health check ──────────────────────────────────────────────────────
echo "⏳ Waiting for health check..."
sleep 5
if curl -sf http://localhost:${PORT:-20128}/api/settings > /dev/null 2>&1; then
  echo "✅ OmniRoute is healthy"
else
  echo "⚠️  Health check failed — kiểm tra logs: docker compose -f $COMPOSE_FILE logs -f"
fi

# ── Cleanup old images ────────────────────────────────────────────────
docker image prune -f --filter "dangling=true" > /dev/null 2>&1 || true

echo "🎉 Deploy complete!"
