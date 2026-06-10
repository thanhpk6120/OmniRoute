---
title: "OmniRoute — Server Deploy Guide (Local VPS)"
version: 3.8.10
lastUpdated: 2026-06-10
---

# OmniRoute — Server Deploy Guide (Local VPS)

Hướng dẫn deploy OmniRoute lên VPS local (`192.168.1.68`) bằng Docker image prebuilt từ GHCR hoặc build trực tiếp trên server.

---

## 1. Chuẩn bị

### 1.1 Kết nối SSH

```bash
# Kết nối VPS
ssh thanhpk@192.168.1.68

# Nếu dùng password, dùng sshpass (cài trước)
sshpass -p 'YOUR_PASSWORD' ssh -o StrictHostKeyChecking=no thanhpk@192.168.1.68
```

### 1.2 Kiểm tra Docker

```bash
docker --version          # phải >= 24
docker compose version   # phải >= 2.x
```

---

## 2. Cài đặt lần đầu

### 2.1 Tạo thư mục deploy

```bash
ssh thanhpk@192.168.1.68
mkdir -p ~/omniroute && cd ~/omniroute
```

### 2.2 Tạo file `.env`

```bash
cat > ~/omniroute/.env << 'EOF'
# === Security ===
JWT_SECRET=CHANGE-TO-A-UNIQUE-64-CHAR-SECRET-KEY
INITIAL_PASSWORD=YourSecurePassword123!
API_KEY_SECRET=REPLACE-WITH-ANOTHER-SECRET-KEY
STORAGE_ENCRYPTION_KEY=REPLACE-WITH-THIRD-SECRET-KEY
STORAGE_ENCRYPTION_KEY_VERSION=v1
MACHINE_ID_SALT=CHANGE-TO-A-UNIQUE-SALT
OMNIROUTE_WS_BRIDGE_SECRET=REPLACE-WITH-WS-BRIDGE-SECRET

# === App ===
PORT=20128
NODE_ENV=production
HOSTNAME=0.0.0.0
DATA_DIR=/app/data
APP_LOG_TO_FILE=true
AUTH_COOKIE_SECURE=false
REQUIRE_API_KEY=false

# === Domain ===
BASE_URL=https://llms.yourdomain.com
NEXT_PUBLIC_BASE_URL=https://llms.yourdomain.com
EOF
```

> Generate secret keys: `openssl rand -hex 32` cho mỗi key.

### 2.3 Tạo `docker-compose.server.yml`

```bash
cat > ~/omniroute/docker-compose.server.yml << 'EOF'
services:
  omniroute:
    build:
      context: .
      dockerfile: Dockerfile
      target: runner-base
    image: omniroute:local
    container_name: omniroute
    restart: unless-stopped
    ports:
      - "${PORT:-20128}:20128"
    volumes:
      - ./data:/app/data
    env_file:
      - .env
    environment:
      - NODE_ENV=production
      - DATA_DIR=/app/data
    healthcheck:
      test: ["CMD", "node", "healthcheck.mjs"]
      interval: 30s
      timeout: 5s
      start_period: 15s
      retries: 3
EOF
```

### 2.4 Clone repo

```bash
# Trên server
cd ~/omniroute
git clone https://github.com/diegosouzapw/OmniRoute.git .
git checkout thanhpk6120
```

---

## 3. Deploy / Update

### 3.1 Từ máy local (khuyến nghị)

```bash
# Copy code + Dockerfile lên server
scp D:/Job/AI/OmniRoute/Dockerfile thanhpk@192.168.1.68:~/omniroute/
scp -r D:/Job/AI/OmniRoute/scripts/deploy-server.sh thanhpk@192.168.1.68:~/omniroute/

# SSH và chạy deploy
ssh thanhpk@192.168.1.68 "cd ~/omniroute && bash deploy-server.sh"
```

### 3.2 Trên server trực tiếp

```bash
cd ~/omniroute
git fetch origin thanhpk6120
git pull origin thanhpk6120
bash deploy-server.sh
```

---

## 4. Deploy Script

```bash
./deploy-server.sh           # git pull + build + restart
./deploy-server.sh --skip-pull   # build lại, không pull
./deploy-server.sh --rollback    # quay về image trước
```

---

## 5. Kiểm tra sau deploy

```bash
docker ps | grep omniroute
curl -sf http://localhost:20128/api/settings
docker logs -f omniroute
```

---

## 6. Quick Deploy Commands

```bash
# === Deploy nhanh từ máy local ===
# 1. Copy code lên server
scp -r D:/Job/AI/OmniRoute/* thanhpk@192.168.1.68:~/omniroute/

# 2. SSH và deploy
ssh thanhpk@192.168.1.68 "cd ~/omniroute && bash scripts/deploy-server.sh"

# === Hoặc build local rồi save image ===
docker build --target runner-base -t omniroute:local .
docker save omniroute:local | gzip > omniroute-local.tar.gz
scp omniroute-local.tar.gz thanhpk@192.168.1.68:~/omniroute/
ssh thanhpk@192.168.1.68 "cd ~/omniroute && docker load < omniroute-local.tar.gz"
ssh thanhpk@192.168.1.68 "cd ~/omniroute && docker compose up -d"
```

---

## 7. Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| Container không start | `docker logs omniroute` |
| Health check fail | Kiểm tra PORT trong .env |
| Git pull fail | Kiểm tra remote URL |
| Build fail | `docker image prune -af` |
| Data mất | KHÔNG dùng `docker compose down -v` |
