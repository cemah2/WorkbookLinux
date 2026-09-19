#!/usr/bin/env bash
# break_M18_03.sh — panne BF18.3 (port publié mais filtré)
# Idempotent. Sauvegarde les règles iptables dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
BF=/opt/factura-docker/bf
SAUV=/root/.breakfix-backup
REF=/opt/factura-docker/api
mkdir -p "$SAUV" "$BF"

[ -f "$REF/app.py" ] || { echo "$REF/app.py absent : lance setup_M18.sh" >&2; exit 1; }
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || {
  echo "Docker n'est pas installé ou ne tourne pas : fais d'abord le lab L18.1" >&2
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
command -v iptables >/dev/null 2>&1 || { echo "iptables absent" >&2; exit 1; }

docker rm -f factura-public >/dev/null 2>&1 || true
docker run -d --name factura-public -p 8003:8000 --restart unless-stopped \
  factura-bf:base >/dev/null
sleep 1
IP=$(docker inspect factura-public \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

[ -f "$SAUV/M18_03.iptables" ] || iptables-save > "$SAUV/M18_03.iptables"

# une règle « temporaire » oubliée par un collègue
iptables -C DOCKER-USER -d "$IP" -p tcp --dport 8000 -j DROP 2>/dev/null \
  || iptables -I DOCKER-USER -d "$IP" -p tcp --dport 8000 -j DROP

cat <<'EOF2'

Symptôme attendu : sur lab-ops, curl http://127.0.0.1:8003/sante répond,
« docker ps » montre 0.0.0.0:8003->8000/tcp et ss -tlnp voit le port.
Depuis lab-adm, curl -m 5 http://10.10.10.14:8003/sante expire.
EOF2
