# Hướng dẫn deploy OmniRoute lên server (image prebuilt từ GHCR)

> **Mục tiêu:** Server **không build** code nữa. CI tự build image trên GitHub → server chỉ `pull` về và restart container. Data cũ luôn được giữ.

---

## 0. Yêu cầu trên server

| Yêu cầu                                         | Lệnh kiểm tra             |
| ----------------------------------------------- | ------------------------- |
| Docker Engine ≥ 20.10                           | `docker --version`        |
| Docker Compose v2 (plugin)                      | `docker compose version`  |
| Internet ra ngoài (để `docker pull` từ ghcr.io) | `curl -I https://ghcr.io` |
| Quyền chạy `docker` (root hoặc nhóm `docker`)   | `docker ps`               |

Nếu thiếu Docker:

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
newgrp docker
```

---

## 1. Setup 1 lần trên GitHub (chỉ làm 1 lần đầu)

### 1.1. Cấp quyền cho GitHub Actions push image

1. Vào repo: https://github.com/thanhpk6120/OmniRoute
2. `Settings` → `Actions` → `General`
3. Phần **Workflow permissions** → chọn **Read and write permissions** → `Save`

> Không làm bước này → workflow fail với HTTP 403 khi push image.

### 1.2. (Khuyến nghị) Set image visibility = Public

Để server không cần `docker login` mới pull được:

1. Vào https://github.com/thanhpk6120?tab=packages
2. Click vào package `omniroute` (sau khi build lần đầu xong nó mới hiện)
3. `Package settings` (sidebar phải) → cuối trang `Change visibility` → **Public** → xác nhận

> Nếu vẫn muốn để private, xem mục **Phụ lục A** ở cuối file để cấu hình `docker login ghcr.io` trên server.

---

## 2. Setup 1 lần trên server (chỉ làm 1 lần đầu)

### 2.1. Tạo thư mục deploy

```bash
mkdir -p ~/omniroute && cd ~/omniroute
```

### 2.2. Tải file deploy từ repo

```bash
curl -O https://raw.githubusercontent.com/thanhpk6120/OmniRoute/thanhpk6120/docker-compose.server.yml
curl -O https://raw.githubusercontent.com/thanhpk6120/OmniRoute/thanhpk6120/scripts/deploy-server.sh
curl -O https://raw.githubusercontent.com/thanhpk6120/OmniRoute/thanhpk6120/.env.example
chmod +x deploy-server.sh
```

Sau bước này thư mục `~/omniroute/` có 3 file:

```
~/omniroute/
├── docker-compose.server.yml
├── deploy-server.sh
└── .env.example
```

### 2.3. Tạo `.env` từ `.env.example`

```bash
cp .env.example .env
nano .env       # dán JWT_SECRET, API_KEY_SECRET, INITIAL_PASSWORD... vào
```

Generate secret nếu cần:

```bash
# JWT_SECRET (48 byte base64)
openssl rand -base64 48

# API_KEY_SECRET (32 byte hex)
openssl rand -hex 32
```

### 2.4. Migrate data cũ vào `./data/`

> **CRITICAL:** Bước này quyết định việc giữ được data cũ hay không.

`docker-compose.server.yml` mount `./data:/app/data`. Phải có data ở đường dẫn `~/omniroute/data/` trước khi start container.

#### Trường hợp A — Server cũ chạy `docker compose --profile base up`

Container cũ cũng mount `./data:/app/data`, nên data đã ở thư mục `data/` cạnh `docker-compose.yml` cũ. Copy sang:

```bash
# Giả sử setup cũ ở /opt/omniroute hoặc ~/repo/OmniRoute
OLD_DIR="/đường/dẫn/setup/cũ"

# Stop container cũ trước (đảm bảo SQLite không bị ghi)
cd "$OLD_DIR"
docker compose down                       # KHÔNG dùng -v
cd ~/omniroute

# Copy toàn bộ data, giữ nguyên permission
cp -a "$OLD_DIR/data/." ./data/

# Verify
ls -la ./data/
```

#### Trường hợp B — Server cũ chạy named volume (không bind-mount)

Nếu compose cũ dùng `omniroute-prod-data:/app/data` (named volume) thay vì `./data`, copy data từ volume ra thư mục:

```bash
# Stop container cũ
docker stop omniroute-prod || true

# Copy data từ named volume ra ./data/
docker run --rm \
  -v omniroute-prod-data:/from \
  -v ~/omniroute/data:/to \
  alpine sh -c "cp -a /from/. /to/"

# Verify
ls -la ./data/
```

#### Trường hợp C — Server hoàn toàn mới, không có data cũ

```bash
mkdir -p ./data
```

Script deploy sẽ tự tạo data lần đầu start.

### 2.5. (Skip nếu image Public) Login ghcr.io

Chỉ cần làm nếu bước 1.2 chưa set image Public.

```bash
# Tạo Personal Access Token (PAT) tại:
# https://github.com/settings/tokens/new
# Scope: read:packages
# Copy token

echo "<PASTE_TOKEN>" | docker login ghcr.io -u thanhpk6120 --password-stdin
```

Token này lưu trong `~/.docker/config.json`, chỉ cần login 1 lần.

---

## 3. Deploy lần đầu

```bash
cd ~/omniroute

# Pull image v3.8.0.1 và start
./deploy-server.sh v3.8.0.1
```

Output sẽ hiển thị:

```
[1/4] Backing up ./data → ./backups/data-20260518-184200.tar.gz
[2/4] Pulling image...
[3/4] Recreating container with new image...
[4/4] Waiting for healthcheck...
      ✓ omniroute is healthy.
```

Verify hoạt động:

```bash
# Check container running
docker compose -f docker-compose.server.yml ps

# Tail log
docker compose -f docker-compose.server.yml logs -f --tail 100 omniroute

# Test API
curl http://localhost:20128/api/health
```

Mở trình duyệt: `http://<server-ip>:20128` — dashboard phải load được, các provider/key cũ phải còn nguyên.

---

## 4. Cập nhật phiên bản mới (mỗi lần code có thay đổi)

### Quy trình tổng thể

```
[Local máy]              [GitHub Actions]            [Server]
git push  →  CI tự build image  →  ./deploy-server.sh v3.8.0.X
```

### 4.1. Trên máy local — push code

Mỗi khi muốn release version mới:

```bash
# Commit changes như thường
git add .
git commit -m "fix(...): mô tả thay đổi"

# Tạo tag version mới (kèm changelog)
git tag -a v3.8.0.2 -m "Release v3.8.0.2

- fix: ...
- feat: ..."

# Push branch + tag
git push origin thanhpk6120
git push origin v3.8.0.2
```

### 4.2. Theo dõi GitHub Actions

- Mở https://github.com/thanhpk6120/OmniRoute/actions
- Workflow `Fork — Publish image to GHCR` đang chạy
- Lần đầu: ~10–15 phút (cache trống)
- Lần sau: ~2–5 phút (cache GHA reuse)

Khi workflow xong (status xanh), image đã sẵn ở:

- `ghcr.io/thanhpk6120/omniroute:v3.8.0.2`
- `ghcr.io/thanhpk6120/omniroute:latest`
- `ghcr.io/thanhpk6120/omniroute:sha-<7-ký-tự>`

### 4.3. Trên server — deploy

```bash
ssh user@server
cd ~/omniroute

# Cách 1 — pin version (khuyến nghị cho production)
./deploy-server.sh v3.8.0.2

# Cách 2 — luôn lấy bản mới nhất
./deploy-server.sh
```

Script tự động:

1. Backup `./data/` thành `./backups/data-YYYYMMDD-HHMMSS.tar.gz` (giữ 3 bản mới nhất)
2. `docker compose pull` — kéo image mới
3. `docker compose up -d` — recreate container, **giữ nguyên volume**
4. Đợi healthcheck → báo `✓ omniroute is healthy`

> Toàn bộ quy trình: ~30s đến 2 phút (tùy băng thông server).

---

## 5. Rollback nếu version mới có bug

```bash
cd ~/omniroute

# Quay về version trước
./deploy-server.sh --rollback v3.8.0.1

# Hoặc nếu data đã hỏng, khôi phục backup
docker compose -f docker-compose.server.yml down
ls ./backups/                              # liệt kê backup
tar -xzf ./backups/data-20260518-184200.tar.gz -C ./
./deploy-server.sh --rollback v3.8.0.1
```

---

## 6. Bảo vệ dữ liệu — Tóm tắt

| Loại data                        | Lưu ở đâu trên host                        | Mất khi nào?                                                   |
| -------------------------------- | ------------------------------------------ | -------------------------------------------------------------- |
| OmniRoute (SQLite, config, logs) | `~/omniroute/data/` (bind-mount)           | Chỉ khi xoá thư mục bằng tay                                   |
| Redis state                      | Docker named volume `omniroute-redis-data` | Chỉ khi `docker volume rm omniroute-redis-data` hoặc `down -v` |
| Backup tự động                   | `~/omniroute/backups/data-*.tar.gz`        | Khi script prune (giữ 3 bản gần nhất)                          |

### Việc CẦN làm

- ✅ Backup `./data/` định kỳ (script đã tự làm trước mỗi deploy)
- ✅ Snapshot VPS định kỳ qua control panel của VPS provider
- ✅ Pin version `v3.8.0.X` cho production (không dùng `latest` để tránh upgrade ngoài ý muốn)

### Việc TUYỆT ĐỐI KHÔNG làm

- ❌ `docker compose -f docker-compose.server.yml down -v` — cờ `-v` xoá named volumes (Redis)
- ❌ `rm -rf ~/omniroute/data/` — xoá toàn bộ DB
- ❌ Đổi `DATA_DIR` trong `.env` mà không migrate data
- ❌ `docker volume prune --all` — xoá nhầm volume Redis

---

## 7. Troubleshooting

### 7.1. `docker pull` báo `denied: denied`

Image đang Private và chưa login. Xem mục **2.5**.

### 7.2. Workflow GitHub Actions fail với HTTP 403

Chưa cấp `Read and write permissions` cho Actions. Xem mục **1.1**.

### 7.3. Container start nhưng healthcheck fail

```bash
docker compose -f docker-compose.server.yml logs --tail 200 omniroute
```

Nguyên nhân thường gặp:

- `.env` thiếu `JWT_SECRET` hoặc `API_KEY_SECRET`
- Port `20128` đã bị process khác chiếm — đổi `PORT` trong `.env`
- `./data/` không có quyền write — `chmod -R u+rw ./data/`

### 7.4. Sau khi update, dữ liệu bị reset

Chứng tỏ image mới đã chạy nhưng không mount `./data` đúng. Kiểm tra:

```bash
docker inspect omniroute --format '{{ json .Mounts }}' | python3 -m json.tool
```

Phải thấy mount kiểu `bind` từ `~/omniroute/data` → `/app/data`. Nếu không, restart bằng compose file đúng.

### 7.5. Pull chậm / timeout

```bash
# Check network ra ghcr.io
curl -I https://ghcr.io
curl -I https://pkg-containers.githubusercontent.com

# Nếu chậm: pull thủ công với progress chi tiết
docker pull ghcr.io/thanhpk6120/omniroute:v3.8.0.1
```

---

## 8. Lệnh tham khảo nhanh

```bash
# Status
docker compose -f docker-compose.server.yml ps

# Logs realtime
docker compose -f docker-compose.server.yml logs -f --tail 100

# Restart không pull
docker compose -f docker-compose.server.yml restart omniroute

# Stop (KHÔNG -v)
docker compose -f docker-compose.server.yml down

# Pull + start (manual, không qua deploy script)
docker compose -f docker-compose.server.yml pull
docker compose -f docker-compose.server.yml up -d

# List versions đã pull về local
docker images ghcr.io/thanhpk6120/omniroute

# Xoá image cũ giải phóng disk
docker image prune -a --filter "until=720h"   # > 30 ngày
```

---

## Phụ lục A — Pull image private

Nếu giữ package ở chế độ Private:

1. Tạo Personal Access Token tại: https://github.com/settings/tokens/new
   - Note: `omniroute-server-pull`
   - Expiration: tuỳ ý (1 năm hoặc no expiration)
   - Scope: chọn `read:packages`
   - Click `Generate token` → copy chuỗi `ghp_...`

2. Trên server:

```bash
echo "ghp_..." | docker login ghcr.io -u thanhpk6120 --password-stdin
```

Login lưu ở `~/.docker/config.json`. Sau đó `docker pull` không cần auth lại.

3. Nếu CI deploy dùng nhiều account khác nhau, dùng `docker logout ghcr.io` để gỡ login.

---

## Phụ lục B — Mapping version

| Version    | Commit     | Changes chính                                                                 |
| ---------- | ---------- | ----------------------------------------------------------------------------- |
| `v3.8.0.1` | `c73e8ac1` | feat(network): allow private/local provider URLs by default + GHCR auto-build |

Mỗi tag tương ứng 1 image trên GHCR. Có thể dùng commit SHA ngắn để pin chính xác:

```bash
./deploy-server.sh sha-c73e8ac
```

---

## Tóm tắt 1 dòng

```bash
# Lần đầu (1 lần): tải file → cấu hình .env → migrate data → ./deploy-server.sh v3.8.0.1
# Lần sau (mỗi lần update): ./deploy-server.sh v3.8.0.X
```
