#!/usr/bin/env bash
# break_M22_02.sh — panne BF22.2 (bind mount et UID)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
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

DATA=/srv/factura-docker/data
mkdir -p "$DATA"
construire_base

# --- sauvegarde de l'état du répertoire et du journal existant ----------
if [ ! -f "$SAUV/M22_02.data.stat" ]; then
  stat -c '%u:%g %a' "$DATA" > "$SAUV/M22_02.data.stat"
fi
if [ -f "$DATA/visites.log" ] && [ ! -f "$SAUV/M22_02.visites.log" ]; then
  mv "$DATA/visites.log" "$SAUV/M22_02.visites.log"
fi
rm -f "$DATA/visites.log"

# --- la « migration » a remis le répertoire dans son état d'origine -----
chown root:root "$DATA"
chmod 0755 "$DATA"

docker rm -f factura-migration >/dev/null 2>&1 || true
docker run -d --name factura-migration --user 10001:10001 \
  -e DATA_DIR=/data -v "$DATA":/data -p 8002:8000 \
  --restart unless-stopped factura-bf:base >/dev/null

cat <<'EOF2'

Symptôme attendu : http://127.0.0.1:8002/sante répond, mais
http://127.0.0.1:8002/visites renvoie une erreur 500 et le journal du
conteneur factura-migration parle de « Permission denied ».
Le répertoire /srv/factura-docker/data existe, en 0755.
EOF2
