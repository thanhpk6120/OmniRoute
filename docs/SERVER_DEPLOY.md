# Server Deployment Guide

OmniRoute builds Docker images locally from source — no Docker Hub/GHCR access needed.

## Prerequisites

- Docker Engine 24+ with Compose V2
- Git
- curl (for health checks)
- 1GB+ RAM (build cần ~512MB, runtime ~256MB)

## Initial Setup

```bash
# Clone repo
git clone https://github.com/thanhpk6120/OmniRoute.git ~/omniroute
cd ~/omniroute

# Config
cp .env.example .env
# Chỉnh sửa .env: API keys, PORT, etc.

# First deploy
chmod +x scripts/deploy-server.sh
./scripts/deploy-server.sh --skip-pull
```

## Daily Operations

```bash
cd ~/omniroute

# Deploy (git pull + build + restart)
./scripts/deploy-server.sh

# Build lại mà không pull code mới
./scripts/deploy-server.sh --skip-pull

# Rollback về image trước đó
./scripts/deploy-server.sh --rollback
```

## File Structure

```
~/omniroute/
├── docker-compose.server.yml   # Compose config (build local)
├── scripts/deploy-server.sh    # Deploy script
├── data/                       # Persistent data (bind-mounted)
├── backups/                    # Auto backup trước mỗi deploy
└── .env                        # Environment variables
```

## Data Persistence

- `./data` được mount vào `/app/data` trong container
- Script tự backup `./data` trước mỗi deploy (giữ 3 bản gần nhất)
- **KHÔNG dùng** `docker compose down -v` — sẽ mất data

## Monitoring

```bash
# Logs
docker compose -f docker-compose.server.yml logs -f

# Container status
docker ps --filter name=omniroute

# Health check manual
curl -sf http://localhost:20128/api/settings && echo "OK"

# Resource usage
docker stats omniroute --no-stream
```

## Troubleshooting

**Build fail:**
```bash
# Xem build log chi tiết
docker compose -f docker-compose.server.yml build --no-cache --progress=plain
```

**Container crash loop:**
```bash
docker compose -f docker-compose.server.yml logs --tail=50
# Rollback nếu cần
./scripts/deploy-server.sh --rollback
```

**Disk full:**
```bash
# Xóa image cũ
docker image prune -a -f
# Xóa backup cũ
ls -t backups/data_*.tar.gz | tail -n +4 | xargs rm -f
```

## CI/CD (GitHub Actions)

Workflow `deploy-vps.yml` tự động SSH vào server và chạy `deploy-server.sh` khi:
- Push lên `main` (sau khi Docker publish workflow thành công)
- Manual trigger (workflow_dispatch)

**Yêu cầu GitHub secrets/vars:**
- `VPS_HOST` — IP hoặc domain server
- `VPS_USER` — SSH username
- `VPS_SSH_KEY` — Private key
- `DEPLOY_ENABLED` — set `true` để bật auto-deploy
- `VPS_APP_DIR` (optional) — đường dẫn repo trên server, mặc định `~/omniroute`
