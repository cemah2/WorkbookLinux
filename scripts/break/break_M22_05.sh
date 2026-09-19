#!/usr/bin/env bash
# break_M22_05.sh — panne BF22.5 (pas de DNS sur le bridge par défaut)
# Idempotent. Rien à sauvegarder sur l'hôte.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
BF=/opt/factura-docker/bf
SAUV=/root/.breakfix-backup
REF=/opt/factura-docker/api
mkdir -p "$SAUV" "$BF"

[ -f "$REF/app.py" ] || { echo "$REF/app.py absent : lance setup_M22.sh" >&2; exit 1; }
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || {
  echo "Docker n'est pas installé ou ne tourne pas : fais d'abord le lab L22.1" >&2
  exit 1; }

# image de base commune aux Break & Fix (construite une seule fois)
construire_base() {
  docker image inspect factura-bf:base >/dev/null 2>&1 && return 0
  mkdir -p "$BF/base"
  cp "$REF/app.py" "$REF/requirements.txt" "$BF/base/"
  cat > "$BF/base/Dockerfile" <<'DEOF'
FROM python:3.12-slim-bookworm
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
ENTRYPOINT ["python3", "app.py"]
DEOF
  echo "construction de l'image factura-bf:base (une fois)…"
  docker build -q -t factura-bf:base "$BF/base" >/dev/null
}

construire_base
docker image inspect redis:7-alpine >/dev/null 2>&1 \
  || docker pull -q redis:7-alpine >/dev/null

docker rm -f factura-app factura-cache >/dev/null 2>&1 || true
docker run -d --name factura-cache --restart unless-stopped \
  redis:7-alpine >/dev/null
docker run -d --name factura-app --restart unless-stopped -p 8005:8000 \
  -e REDIS_URL=redis://factura-cache:6379/0 factura-bf:base >/dev/null

cat <<'EOF2'

Symptôme attendu : http://127.0.0.1:8005/compteur renvoie une erreur 500
et le journal de factura-app contient « Name or service not known » pour
factura-cache. Pourtant factura-cache est Up, répond PONG à redis-cli, et
les deux conteneurs se joignent par IP.
EOF2
